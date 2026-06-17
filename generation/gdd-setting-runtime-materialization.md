# GDD: Setting → Runtime Materialization (the Handoff)

**Document type:** Game Design Document (project-designed, architecture/umbrella)
**Authority:** PROJECT-DESIGNED — the mapping from the generated `setting_*` world to the runtime tables is an engineering concern. The runtime data model (`domains`/`realms`/`hex_maps`/`settlement_entrances`/`characters`), the 24mi↔6mi scale hierarchy, and the ACKS density/sizing constraints are NOT modifiable here (they are design-brief and RAW ground truth). This GDD specifies how to *fill* the runtime model from generated data; it does not restructure it.
**Status:** Draft v0.3 — planning. Decision Register (§12) ruled by Jedidiah 2026-06-16 (the 6-mile map is the play surface; the 24-mile map retires to a world-map + off-camera data layer; full procedural zoom-in of an initial ~30×40 six-mile extent that ROLLS/GROWS and persists). v0.3 folds in his second-pass corrections (clanhold soft-caps not hard caps; beastman family conversion; source-of-truth handoff; persisted rolling map; determined migrations; `elevation_raw` persistence; culture-weighted archetype sub-roll deferred). **`gdd-region-zoom-in.md` AUTHORED (v0.1)**. **Phases M0 + M1 LANDED 2026-06-16** — M0: migrations 163–167 + `SettingMaterializer` 24-mile world-map copy. M1: `setting_polities` → realms + abstracted domains + sovereign rulers (incl. the new `BeastmanRulerMaterializer` monster-statblock path + the `ClassedNpcBuilder` adapter honoring generated class/level + the Barony→Baron tribute-title translation + clanhold tribal warriors). `SettingMaterializationTests` 69 checks green (net-zero: branch baseline 460/18 → 461/18). M2 (6-mile play map) is next.
**Depends on ACKS rules:** `rules/acore_axioms_strongholds_and_domains.xml:14-21` (the 1.5/6/24-mile hex hierarchy and the 16-contiguous-sub-hexes ratio); `rules/ax_domains_of_chaos.xml:10-11,79` (clanhold density 125/6-mile + 2,000/24-mile — a SOFT starting limit: excess gives half land revenue, not a hard cap); `rules/ax_domains_of_chaos.xml:15-19,106-233` (beastman family conversion: 1 warrior + N race-specific noncombatants per family; ogre/troll = 4 families + 4× land; slave-labor→peasant-family table; per-race demographics); `rules/ax_domains_of_chaos.xml:37` (1 tribal warrior per family); `rules/acore-setting-construction-rules.xml:32-39` (the standard campaign-24mi + regional-6mi map pair); `rules/acore-campaign-hijinks.xml:632-638` (market class by urban families); `rules/acore_axioms_strongholds_and_domains.xml:106` (5 persons per family — humans/demihumans).
**Depends on project GDDs:** [`gdd-setting-generation.md`](gdd-setting-generation.md) (the producer of `setting_*` — esp. §7.2 sim output contract); [`gdd-hex-subdivision.md`](gdd-hex-subdivision.md) (24mi↔6mi parent/child model + §6 terrain-inheritance contract); [`gdd-region-zoom-in.md`](gdd-region-zoom-in.md) (**must be authored — critical-path**; owns 6-mile content placement + road/river generation); [`gdd-history-simulation.md`](gdd-history-simulation.md) §12 (present-day handoff); [`gdd-campaign-creation-ui.md`](gdd-campaign-creation-ui.md) (the front door + the starting-city picker); [`gdd-wilderness-hex-3d.md`](gdd-wilderness-hex-3d.md) (future 3D renderer — the consumer of persisted `elevation_raw`).
**Depends on un-built systems:** the 6-mile region zoom-in content pass ([`gdd-region-zoom-in.md`](gdd-region-zoom-in.md) — AUTHORED v0.1, not yet built); a beastman-ruler stat-block path (no `*_chieftain` class files — beastmen are monsters); the culture-weighted human-archetype sub-roll (post-MVP); live off-camera realm simulation (Phase M5).
**Modifiable by Claude Code:** Yes within constraints. The mapping tables, materialization order, migrations, initial extent, and the eager/lazy boundary are engineering decisions within the ruled Decision Register. The runtime data model and the scale hierarchy are NOT modifiable.
**Last updated:** 2026-06-16

---

## 1. Purpose and Scope

The setting-generation pipeline (Stages 0–10, `engine/subsystems/generation/world/`) deterministically produces a complete campaign world at **24-mile** scale and freezes it into `setting_*` at the Layer-8 lock. The **live game reads a completely different set of runtime tables** — `hex_maps`/`hex_cells`, `domains`, `realms`, `settlement_entrances`, `dungeon_entrances`, `strongholds`, `pois`, `characters`, `parties` — populated today **only** by the hand-authored Avalon/Ashford fixture (`engine/autoloads/test_content_seeder.gd`). **Nothing bridges generated → playable.**

This GDD specifies the **materialization** step. Per Jedidiah's 2026-06-16 rulings, it is fundamentally a **scale change**: the 24-mile generated world is the *worldbuilding* scale (and becomes a world-map screen + an off-camera political data layer), while **the 6-mile map is the play surface.** The handoff expands the player-chosen starting region into a 6-mile play map — initially ~30×40 hexes centered on the chosen city — and that map **grows at its frontier and persists permanently** as the party travels. It maps `setting_*` onto the runtime tables, reuses the existing NPC/settlement/dungeon generators as content producers, and adds migrations only where the runtime schema lacks a column.

---

## 2. ACKS Constraints

These come from the books and may NOT be changed:

- **Three nested hex scales, 16:1 ratio** (`rules/acore_axioms_strongholds_and_domains.xml:14-21`): a 24-mile hex contains sixteen 6-mile hexes, each sixteen 1.5-mile hexes. The setting is generated at 24-mile; **play happens at 6-mile**; the 24-mile becomes the strategic/world-map view.
- **The standard map pair is campaign-24mi + regional-6mi** (`rules/acore-setting-construction-rules.xml:32-39`). The 24-mile is the world map / data layer; the 6-mile is the play surface.
- **Clanhold density is a SOFT starting limit, not a hard cap** (`rules/ax_domains_of_chaos.xml:10-11,79`): 125 peasant families per 6-mile hex (2,000 per 24-mile) is the *beastman/clanhold* starting density; **clanholds may grow past it — excess families simply give half land revenue** (a runtime economy penalty). It does **not** bind civilized/human domains (which use the higher territory-class densities the generator already applies). **Materialization must NOT enforce a hard 125 cap on anyone.**
- **Beastman family conversion** (`rules/ax_domains_of_chaos.xml:15-19,37,106-233`): a beastman clanhold family = **1 warrior + N race-specific noncombatants** (kobold ~1, gnoll ~4-5, etc.), NOT 5 persons; **ogre/troll families count as 4 families** for limits/growth and take **4× land area**; **1 tribal warrior per family** (→ `domains.available_tribal_warriors`); a slave-labor→peasant-family conversion table exists. These apply to **beastmen only**.
- **5 persons per family — humans/demihumans** (`rules/acore_axioms_strongholds_and_domains.xml:106`). No conversion at the handoff for non-beastmen; the generator and runtime both work in families.
- **Market class by urban families** (`rules/acore-campaign-hijinks.xml:632-638`): Class I ≥20,000 … VI <250. `setting_settlements.market_class` is already the integer 1–6.
- **Beastman rulers are monster chieftains, not classed characters** (`rules/ax_domains_of_chaos.xml` lair/leader hierarchy, via `data/monsters/monster_catalog.json`). Ruler HD = lair-leader base HD, per `BeastmanLeaderLoader`. Not materializable through the classed-NPC path.

---

## 3. The Gap — Generated Tables vs. Runtime Tables

| Concept | Generated (`setting_*`, frozen at lock) | Runtime (read by the live game) |
|---|---|---|
| World terrain | `setting_hexes` (24-mile substrate) | `hex_maps`+`hex_cells` (24-mile world map **and** the 6-mile play map) |
| Rivers | `setting_river_edges` | `hex_river_edges` |
| Roads | `setting_roads` (ordered paths) | `hex_overlays` (geometry) + a runtime `roads` entity (metadata) |
| Polities | `setting_polities` (flat + liege chains; rulers as `ruler_class`/`ruler_level`) | `realms` (apex) + `domains` (`liege_domain_id`) |
| Settlements | `setting_settlements` | `settlement_entrances` (+ `settlement_pois`, lazy) |
| Dungeons/ruins | `setting_ruin_seeds` (24-mile TAG) | `dungeon_entrances` (placed on a 6-mile child at zoom-in) |
| Fortifications | `setting_fortifications` | `strongholds` |
| POIs | `setting_poi_seeds` (24-mile TAG) | `pois` |
| Narrative | `setting_narrative` | — (read in place for the brief) |
| Rulers / NPCs | none (`ruler_class`/`ruler_level`/`alignment`/`culture_id` on `setting_polities`) | `characters` |
| Party / clock | — | `parties`, `party_state`, `campaigns.calendar_day` |

*(Column inventories for both sides are unchanged from v0.2; see git history. Verified: `setting_hexes.elevation/biome/water` use the identical `hex_cells` vocab; `market_class` int 1–6 both sides; `strongholds`/`dungeon_entrances` exist; `domains.culture_id`+`settlement_entrances.culture_id` exist (mig 160); `domains.available_tribal_warriors` exists for clanhold warrior pools.)*

---

## 4. The Scale Model — 6-Mile Is the Play Surface (Decision C, ruled)

**Ruling (Jedidiah, 2026-06-16):** the 6-mile map is the main play map; the 24-mile map retires to a world-map screen + an off-camera political data layer. At game start no player travels at 24-mile (too low-level to cross a full 24-mile hex). Dungeons/POIs do not populate the 24-mile play surface — they are metadata tags forcing placement into a 6-mile child. The handoff expands the chosen region into a ~30×40 six-mile extent centered on the start city, via full procedural zoom-in.

### 4.1 The two runtime maps
1. **24-mile world map** (`hex_maps.scale='campaign_24mi'`, `parent_map_id=NULL`): a cheap ~1:1 copy of `setting_hexes`. Drives the **world-map screen** (Strategic view) and is the **parent** of the 6-mile map + the spatial key for the off-camera political data layer. **View-only — no travel or encounters at 24-mile** (Decision 7e), at least at this stage.
2. **6-mile regional play map** (`hex_maps.scale='regional_6mi'`, `parent_map_id`=the 24-mile map): **`parties.current_map_id`** — where play happens. Built by full procedural zoom-in of the 24-mile parents it covers.

### 4.2 Source-of-truth handoff (point 3)
- **Before** a given 6-mile area is generated, the **24-mile `setting_hexes` is the source of truth** for it (terrain, substrate, ownership, tagged content).
- **Once** that 6-mile area is generated, the **persisted 6-mile data is the source of truth** for it — and it is **never regenerated**. Reads for a generated 6-mile hex go to the 6-mile rows; reads for a not-yet-generated area fall back to the 24-mile parent.

### 4.3 The play map ROLLS and PERSISTS — one growing map, no seams (Decision 7a/7b)
The 6-mile play map is **one continuous `hex_maps` row that grows at its frontier**, not a set of discrete windows:
- **Initial extent:** ~30×40 six-mile hexes centered on the start city, **snapped to whole 24-mile parents** (so the footprint is full parents; the extent is "≥30×40, rounded up to parent boundaries"). The extent is deliberately large so **rumors and quests can be seeded from the surrounding generated content** within sight range.
- **Rolling growth:** as the party approaches the generated frontier, the zoom-in pass **appends the next 24-mile parent's 16 children** to the same map. Snapping to whole parents means ~one new 6-mile row/column arrives roughly every two hexes traveled — smooth and out of immediate line of sight.
- **Persistence:** generated 6-mile data is written once and **kept forever** (determinism + persistence; never discarded or re-derived). There is therefore **no cross-window seam** — it is one map that only ever grows. Extent can be tuned (or capped for performance) later without changing the model.

### 4.4 Forced 6-mile placement of 24-mile content
Dungeons (`setting_ruin_seeds`), POIs (`setting_poi_seeds`), settlements, and fortifications are **24-mile tags**. When their parent hex is zoomed (eagerly in the initial extent, or at frontier growth), the zoom-in pass **places each onto exactly one of the 16 child sub-hexes** (carrier child per `gdd-hex-subdivision.md §6.3` step 6, biased by terrain/road). Full procedural zoom-in additionally scatters **new** minor content (hamlets, lesser ruins, wilderness POIs, beastman clanholds) and **generates new roads/rivers** across the 16 children that did not exist at 24-mile — the work `gdd-region-zoom-in.md` must specify (Decision 7h).

### 4.5 Off-camera political data layer
Realms beyond the generated 6-mile area are materialized as **abstracted `domains` + `realms` + a sovereign-ruler each** (§7.3), keyed to the 24-mile world map. At MVP this is a **static backdrop** (Decision G); the hooks for the eventual "continuing off-camera dramas" (live realm sim) are present, but the continuation is Phase M5.

---

## 5. Table-by-Table Mapping

Campaign-scoped, transactional, deterministic (frozen source + seeded `WorldGenRng`).

### 5.1 `setting_hexes` → the 24-mile world map (eager 1:1)
One `hex_maps` row (`campaign_24mi`). Per `setting_hexes` row, one `hex_cells` row: `elevation/biome/biome_subtype/water` 1:1; `civilization`=`territory_class`; `original_biome` copies; `has_city`=true iff a settlement sits there; `fog_state='hidden'` (Decision 7g); **`elevation_raw` persisted** (new column — Decision 6, for the future 3D renderer). `culture_weights`/`alignment_weights` handled by §5.10; `population_band`/`land_value` flow to domains (§5.4).

### 5.2 `setting_hexes` (covered parents) → the 6-mile play map (eager initial extent + rolling)
For the 24-mile parents in the current generated area, run the zoom-in: one `hex_maps` row (`regional_6mi`, parent=world map, footprint grows), and per parent emit 16 `hex_cells` children via `gdd-hex-subdivision.md §6` (terrain) + content placement (§5.5–5.8, `gdd-region-zoom-in.md`). Distribute the parent's `population_band` across the children **with no hard cap** (the clanhold 125/6-mile soft limit is a runtime economy penalty, §2 — not a materialization clamp). Child `elevation_raw` is synthesized/inherited at zoom-in (detail owned by the 3D/zoom-in work). Frontier growth appends parents to this same map.

### 5.3 `setting_river_edges` / `setting_roads` → overlays + metadata (Decision 7h)
- **Rivers** → `hex_river_edges` (copy `flow_clockwise/navigability/crossing` + **`width_category`**, new column). At 6-mile, river **boundary constraints** inherit per `gdd-hex-subdivision.md §6.3` step 7; zoom-in details the path **and generates new rivers** for newly-placed 6-mile features.
- **Roads** → `hex_overlays(road)` geometry (per-cell edge sets from the ordered path) **plus a runtime `roads` entity** (new — mirrors `setting_roads`: id, map_id, ordered hexes, `road_class`, `purpose`, `name`) so the game knows *where roads are* and *what they are*. At 6-mile, zoom-in projects the 24-mile roads down **and generates new roads** connecting newly-generated 6-mile settlements (Decision 7h).

### 5.4 `setting_polities` → `realms` + `domains` (+ `domain_hexes`)
Each **sovereign** → a `realms` row (`name`, `alignment`, `culture`=`culture_id`, `realm_kind`='tracked' if it overlaps the generated area else 'foreign') + a `domains` row for its seat. Each **vassal** → a `domains` row with `liege_domain_id`+`realm_id`. Domains whose territory is in the generated 6-mile area get `location_map_id`=play map + `domain_hexes` (land_value distributed from the parent); domains outside are **abstracted** (NULL location). Key fields: `territory_type`←dominant `territory_class`; `peasant_families`←Σ `population_band` (banker-rounded, **no hard cap**); `morale`←`morale_seed`; `domain_style`='clanhold' if `civ_or_clan_state=='clan'`; `culture_id`←polity `culture_id`; `religion` derived. **Beastman/clanhold domains:** set `available_tribal_warriors` from the family count (1 warrior/family; **ogre/troll families ×4** for limits/land per §2); family composition per the Domains-of-Chaos per-race table at 6-mile materialization. **Sovereigns before vassals** (FK order).

### 5.5 `setting_settlements` → `settlement_entrances`
Per settlement in the generated area: a `settlement_entrances` row on its **carrier 6-mile child** (`map_id`=play map, `name`, `market_class` 1:1, `urban_families`, `parent_domain_id`, `culture_id`, `dominant_race`). Settlements outside the generated area stay in `setting_settlements` until their region rolls in. **`settlement_data` (voxel layout) + `settlement_pois` are lazy on entry** (Decision H). Note: rolling 6-mile generation also creates **new** settlements not present at 24-mile (small towns/hamlets) — these get full `settlement_entrances` rows at gen time.

### 5.6 `setting_ruin_seeds` → `dungeon_entrances` (24-mile tag → carrier child)
At zoom-in of the tagged parent, a `dungeon_entrances` stub on a carrier child (`name`, `dungeon_data`=spec JSON: `size_hint`/flavor/provenance). DG-V1 layout on first entry; tier from distance/depth. Coexists with the existing lazy **emergent** lair system (Decision I).

### 5.7 `setting_fortifications` → `strongholds`
Per fortification: a `strongholds` row tied to the owning domain (`archetype` from `fort_type`; clanhold domains→'clanhold'; `cp_value`=`stronghold_value_gp`×100; `garrison_capacity`; `completion_pct=100`). Orphan watch/border forts → nearest domain or dropped (Decision I).

### 5.8 `setting_poi_seeds` → `pois` (24-mile tag → carrier child)
At zoom-in, a `pois` row on a carrier child (`poi_type`, `name`, `discovered=0`, `seed`) **carrying its own `context`/`rumor_seeds`** (new columns — Decision 7h/point 3: rolling 6-mile generation creates POIs with no `setting_poi_seeds` row, so the runtime `pois` row must self-contain context). Contents resolve at discovery.

### 5.9 `setting_narrative` → campaign brief (no runtime copy)
Read in place by the brief/review UI; already campaign-scoped.

### 5.10 Substrate carry-over (`culture_weights`/`alignment_weights`) — read-back (Decision D)
Needed for runtime NPC culture + religion derivation. **Read back from the source of truth** (§4.2): a generated 6-mile hex inherits its parent's weights (read from `setting_hexes` by parent (q,r)); a not-yet-generated area reads the 24-mile directly. **No migration for MVP.** A `hex_substrate` runtime table is **deferred** until play actually mutates substrate (no mechanism today; campaigns run ~2-5 in-game years, so divergence is unlikely — Decision 7d). Revisit then.

---

## 6. New Migrations Required (DETERMINED — Decision 4)

Sequential from head (162). Never destructive. **Items 1–5 LANDED 2026-06-16 as migrations 163–167 (M0); schema.sql synced.**

1. **`campaign_origin` marker** ({fixture, generated}) — REQUIRED. Keeps the fixture seeder and the materializer mutually exclusive per campaign (Decision M).
2. **`hex_cells.elevation_raw` (REAL)** — REQUIRED. Persist raw height from gen for the future 3D renderer (Decision 6; `gdd-wilderness-hex-3d.md`).
3. **Runtime `roads` entity table** (id, campaign_id, map_id, hexes JSON path, road_class, purpose, name) — REQUIRED. The game needs road location + metadata, and 6-mile generation creates new roads (Decision 7h). `hex_overlays` keeps the render geometry.
4. **`hex_river_edges.width_category`** — REQUIRED. Carry river width (Decision 7h).
5. **`pois.context` + `pois.rumor_seeds` (TEXT JSON)** — REQUIRED. Rolling 6-mile POIs have no `setting_poi_seeds` row, so the runtime row self-contains context (Decision 7h/point 3).
6. **`hex_substrate` table** — DEFERRED. Read-back covers MVP (§5.10); add only when play mutates substrate (Decision 7d).
7. **`domains` provenance columns** (`founding_tick`/`ruler_quality`/`garrison_coverage`/fallen-provenance) — DEFERRED to Phase M5 (live realm sim).

`domains.culture_id` + `settlement_entrances.culture_id` + `domains.available_tribal_warriors` **already exist** — populate, don't migrate.

---

## 7. NPC / Ruler Materialization

### 7.1 The three `ruler_class` id forms (all present)
1. **Human bare** — `fighter`/`cleric`/`mage`/`thief`.
2. **Demihuman prefixed** — `elven_spellsword`/`elven_courtier`/`elven_enchanter`, `dwarven_vaultguard`/`dwarven_delver`/`dwarven_craftpriest`.
3. **Beastman monster-chieftain** — `goblin_chieftain`/…, `ruler_level`=floor(base HD).

### 7.2 Reuse vs. new code
- **`ClassedNpcBuilder.build_and_persist(class_id, campaign_id, opts)`** builds any class with a `data/classes/*.json` file, threads `culture_id`/`role` into personality. **Verified `elven_*`/`dwarven_*` exist** → forms 1 & 2 reuse it as-is (pass the generated `ruler_class`+`ruler_level`; **do not re-roll**).
- **`NpcRulerGenerator.generate_for_domain`** **re-rolls** a human class via `roll_class()` — must be **bypassed or limited** for handoff NPCs (Decision 7c): reuse only its tribute/owner-wiring, never its class selection, or it overwrites generated demihuman/beastman rulers.
- **Beastman chieftains have no class file** → a new **`BeastmanRulerMaterializer`** builds the `characters` row from the monster stat block via `BeastmanLeaderLoader.leader_for_race(race)`. The one genuine new generator.

### 7.3 Depth — which NPCs become full `characters` rows (Decision E, ruled)
- **Eager:** every **ruler in the generated 6-mile area** + **all NPCs upstream in each vassal chain** to the highest realm ruler; **plus every sovereign (highest-realm) ruler globally** (the off-camera data layer needs them).
- **Lazy / names-only:** all other off-camera mid-tier vassals, settlement staff (`BaselineNpcStocker` on contact), encounter NPCs. "Names-only" = a `persistence_tier='named'` stub promoted to `'full'` on first contact.

### 7.4 Culture-weighted human archetype sub-roll (POST-MVP — point 5)
The generated human `ruler_class` is a bare progression (fighter/cleric/mage/thief). **Eventually**, materialization must **sub-roll the specific class/archetype** (e.g. fighter → barbarian/explorer/etc.) **weighted by the culture's class-kit weights** (the same culture catalog the names/personality use). **Not MVP** — MVP materializes the bare progression; the culture-weighted archetype sub-roll is a completion item (demihuman prefixed ids and beastman chieftains are unaffected — already specific).

---

## 8. The Materialization Pipeline (proposed)

Triggered after `EventBus.world_approved` + `lock_setting` and the **starting-city pick** (Decision K), before the party boundary. A new `SettingMaterializer` (RefCounted, **not** an autoload):

```
materialize(campaign_id, start_settlement_id):
  0. GUARD       → setting locked; runtime tables empty; campaign_origin='generated'
  1. WORLD MAP   → campaign_24mi hex_map; hex_cells from setting_hexes (1:1, +elevation_raw);
                   24-mile roads/rivers metadata; off-camera data key (view-only)
  2. POLITIES    → realms (sovereigns) + domains (all, topo order);
                   in-area domains located; out-of-area abstracted; clanholds set tribal warriors
  3. RULERS      → eager set (§7.3): in-area vassal chains + ALL sovereigns;
                   ClassedNpcBuilder (human/demihuman, honor generated class/level) +
                   BeastmanRulerMaterializer; tribute via NpcRulerGenerator (class-selection bypassed)
  4. EXTENT      → ~30×40 around start city, snapped to whole 24-mile parents;
                   create the regional_6mi play map (parent=world map)
  5. ZOOM-IN     → per parent: 16 children (gdd-hex-subdivision §6 terrain) +
                   gdd-region-zoom-in content: project tagged settlement/dungeon/POI/fort onto
                   carrier children; scatter new minor content + beastman intermingling;
                   distribute population (NO hard cap); GENERATE new 6-mile roads/rivers
  6. IN-AREA     → settlement_entrances, dungeon_entrances stubs, strongholds, pois (+context),
                   roads entity, domain_hexes — all on the 6-mile play map; PERSIST
  7. CLOCK       → campaigns.calendar_day = 1, season = spring (Decision J)
  8. PARTY       → place party in/at the start city on the 6-mile play map
  9. VERIFY      → FK integrity; ≥1 settlement, ≥1 reachable ruler, ≥1 dungeon in area;
                   party on a real 6-mile hex  (NO pop-cap check — caps are soft)
 — ROLLING —     → on frontier approach, repeat 5–6 for the next parent(s); append + persist
```

Determinism: frozen source + seeded RNG keyed by (campaign_seed, parent_q, parent_r, child).

---

## 9. Day-1 Playable MVP (Decision A, ruled — 6-mile + full zoom-in)

1. Approve a generated world → **pick a starting city on the review screen** (Decision K) → land there.
2. **Travel the 6-mile play map** (initial ~30×40, snapped to parents) on real procedurally-zoomed terrain, with fog; a **24-mile world-map screen** (Strategic toggle, view-only) is available.
3. **Enter ≥1 generated settlement** (interior stocked on entry).
4. **Meet ≥1 generated ruler NPC** (full `characters` row; demihuman + beastman supported; human bare-class for MVP — archetype sub-roll §7.4 deferred).
5. **Enter ≥1 generated dungeon** (DG-V1 layout on first entry, on a 6-mile carrier child).
6. The play map **rolls/grows + persists** as the party travels to its frontier.

**Out of scope for first-playable:** culture-weighted human archetype sub-roll (§7.4); live off-camera realm sim (Phase M5); quests (Phase M6); sea travel; 1.5-mile insets; eager population of off-camera mid-tier vassals; substrate mutation / `hex_substrate` table.

**Critical-path prerequisite:** `gdd-region-zoom-in.md` (6-mile content placement + road/river generation + beastman intermingling). The terrain half exists (`gdd-hex-subdivision.md §6`).

---

## 10. Phase Plan (proposed)

- **Phase M-pre — Author `gdd-region-zoom-in.md`. ✅ DONE (v0.1, 2026-06-16).** 6-mile content placement + the natural-variation algorithm + the performance/optimization (chunked-render) model + the rolling/persisted frontier.
- **Phase M0 — Skeleton + world map + clock + migrations. ✅ LANDED 2026-06-16.** Migrations 163–167; `SettingMaterializer.materialize()` (RefCounted, engine/subsystems/generation/materialization/) — GUARD (locked + not-already-materialized) → `campaign_origin='generated'` → 24-mile world map (hex_maps + hex_cells 1:1 incl `elevation_raw`, river edges incl `width_category`, the `roads` entity) → `calendar_day=1`; `SettingMaterializationTests` (id 466, 21 checks). Net-zero new failures. `hex_overlays` road geometry deferred to M2 (24-mile map is view-only).
- **Phase M1 — Polities + rulers. ✅ LANDED 2026-06-16.** `setting_polities` → `realms` (sovereigns, all `realm_kind='foreign'` at M1) + `domains` (ALL abstracted — no location/hexes yet; located domains deferred to M2) + the eager SOVEREIGN ruler set. Rulers: `ClassedNpcBuilder` (instance) for human/demihuman honoring the generated `ruler_class`+`ruler_level` (seeded template band for determinism); NEW `BeastmanRulerMaterializer` (monster stat block via the catalog) for `*_chieftain`; `NpcRulerGenerator.roll_class()` bypassed. `realm_title` TRANSLATED Barony→Baron etc. (else tribute zeroes — `AbstractTributeResolver` keys on ruler titles); tribute via `compute_tribute_owed`; clanhold `available_tribal_warriors` (1/family, ogre/troll ×4) from `setting_hexes.population_band`; culture threaded (`domains.culture_id`/`realms.culture`). Vassal-chain rulers + located domains + realm_kind promotion deferred to M2.
- **Phase M2 — The 6-mile play map (steps 4–6) + rolling growth.** Implement the zoom-in (consuming M-pre); initial extent + frontier append + persistence.
- **Phase M3 — Party placement + travel + entry (steps 8–9 + UI).** Start-city picker on the review screen; party on the 6-mile map; Strategic⇄Regional toggle → world-map/play-map; settlement entry; dungeon entry. **← Day-1 MVP complete.**
- **Phase M4 — Culture-weighted human archetype sub-roll (§7.4)** + richer lazy stocking.
- **Phase M5 — Live off-camera realm simulation** (Decision G's deferred half; +domains provenance migration).
- **Phase M6 — Quests** (when the NPC questgiver/motivation system lands).

---

## 11. Coexistence with the Test Fixtures (Decision M)

`test_content_seeder.gd` (Avalon/Ashford) and the materializer both write the same runtime tables and must **never run for the same campaign.** A `campaign_origin` marker ({fixture, generated}) keeps them mutually exclusive: the fixture path stays for the test suite + dev scaffolding; the materializer is the production path, invoked only from the campaign-creation approve step. Existing tests/fixtures keep working untouched.

---

## 12. Decision Register — Jedidiah's Rulings (2026-06-16, v0.3)

| # | Decision | Ruling |
|---|---|---|
| **A** | Day-1 MVP scope | **6-mile travel is the MVP**: pick start city → travel the 6-mile play map → settlement → ruler → dungeon, with the map rolling/growing. |
| **B** | Eager vs. lazy | **Eager-coarse / lazy-fine**: eager = 24-mile world map + the initial 6-mile extent (full content) + targeted rulers + party; lazy = frontier growth, interiors, layouts, staff/encounter NPCs. |
| **C** | Scale model | **6-mile is the play surface.** 24-mile = world-map + off-camera data layer (view-only). Handoff expands the chosen region into a ~30×40 six-mile extent (snapped to parents) that **rolls/grows and persists**. Dungeons/POIs = 24-mile tags → 6-mile carrier child. |
| **D** | Mapping + migrations | Mechanical per §5/§6; **§6 migrations now DETERMINED** (campaign_origin, elevation_raw, roads entity, river width, pois context REQUIRED; hex_substrate + domains provenance DEFERRED). Substrate via **read-back** (source-of-truth rule §4.2). |
| **E** | NPC depth | **Mix:** eager = all rulers in the generated area + their full vassal→sovereign chains + every sovereign globally; rest lazy or names-only. Beastman rulers via the new monster-statblock path. |
| **F** | Beastman 6-mile (Part B) | Rides the zoom-in: **eager within the generated area, lazy at the frontier.** Per-race intermingling + family composition from the Domains-of-Chaos tables / `beastman_distribution.json`. |
| **G** | Realm sim | **Static backdrop first.** Sovereign characters exist so the data layer can go live later (Phase M5). |
| **H** | Settlement interiors | **Lazy on entry** (only the `settlement_entrances` row is eager). |
| **I** | Dungeons/lairs | Ruin seeds = authored landmarks (24-mile tag → 6-mile carrier child; lazy DG-V1 layout); existing lazy lair system adds **emergent** lairs — they **coexist**. Orphan forts → nearest domain or drop. |
| **J** | Calendar | **`calendar_day = 1`, season = spring.** |
| **K** | Starting position | **Player picks the starting city on the review screen**; the extent centers on it. |
| **L** | Persistence | **Write once**; generated 6-mile data persists permanently and is never regenerated (source-of-truth rule). |
| **M** | Fixture coexistence | **`campaign_origin` marker**; fixture vs. materializer mutually exclusive per campaign. |
| **N** | Quests | **Deferred** to Phase M6. |
| **1** | Clanhold caps | **SOFT starting limit, not a hard cap.** 125/6-mile applies to clanholds; excess → half land revenue (runtime penalty). Civilized domains uncapped by it. Materialization enforces **no** hard cap. |
| **2** | Beastman conversion | **Per Domains of Chaos** (`ax_domains_of_chaos.xml:15-19,106-233`): 1 warrior + N race-specific noncombatants/family; ogre/troll = 4 families + 4× land; 1 tribal warrior/family → `available_tribal_warriors`. Humans/demihumans stay 5/family. |
| **3** | Source of truth | **24-mile is truth until a 6-mile area is generated; thereafter the persisted 6-mile is truth** (and never regenerated). |
| **5** | Human archetype sub-roll | Needed eventually (culture class-kit-weighted), **NOT MVP** (Phase M4). |
| **6** | `elevation_raw` | **Persist from gen to gameplay** (future 2D→3D renderer); new `hex_cells.elevation_raw` column. |
| **7e** | 24-mile travel | **Confirmed view-only** — no travel/encounters at 24-mile scale at this stage. |
| **7f** | Background ruler count | Materialize **as many sovereigns as perf tolerates**; if it lags, add a setting-gen consolidation pass (force small realms into larger polities) to cut the count. |

---

## 13. Open Questions / Architectural Concerns

- **`gdd-region-zoom-in.md` — AUTHORED (v0.1, 2026-06-16).** Specifies the natural-variation algorithm (neighbor-gradient ecotones + feature-driven local variation incl. river oases/foothills + coherent stochastic patches + polity/culture dithering), content placement (carrier-child projection + minor scatter + beastman intermingling + 6-mile road/river generation), the performance/optimization model (chunked render + off-camera compression), and the rolling/persisted frontier. Its open items (chunk size, strength-dial calibration, 6-mile `elevation_raw` synthesis) are tuning passes, not blockers.
- **Frontier growth mechanics.** Confirm the trigger (party within N hexes of the generated edge), the append unit (one 24-mile parent's 16 children), and that growth runs as a scheduled `zoom_in_requested` event (per `gdd-hex-subdivision.md §8.4`) so it completes before movement resumes. Append-only + persisted → the migration-119 `compute_consistent_domain_hex_set` reconciles a newly-located domain's hexes.
- **6-mile `elevation_raw` synthesis.** The 24-mile `elevation_raw` persists directly; the 6-mile children need synthesized continuous height (no 6-mile height exists at gen). Owned jointly by zoom-in + `gdd-wilderness-hex-3d.md`; MVP can inherit the parent value flat and let the 3D renderer synthesize later.
- **Beastman ruler path is a new generator.** Confirm the `characters` row shape for a monster-statted ruler (combat_progression, saves; HD→level solved by `BeastmanLeaderLoader`).
- **`NpcRulerGenerator` re-rolls class.** Bypass/limit it for handoff NPCs so generated demihuman/beastman rulers aren't overwritten.
- **Background sovereign count vs. lag (7f).** Materializing every sovereign + ruler is cheap as static rows; the perf risk is Phase M5's live sim. The fallback lever is a setting-gen consolidation pass — note it for M5, not MVP.
- **`territory_class` value identity.** Confirm `setting_hexes.territory_class` strings exactly match `hex_cells.civilization` {civilized,borderlands,wilderness}; else a small translation map.
- **Substrate mutation (deferred).** Read-back is fine now (no mutation mechanism; ~2-5-yr campaigns). When cultural drift during play ships, promote to a `hex_substrate` runtime table keyed to the 6-mile (the then-source-of-truth) hex.

---

## 14. Revision History

- **2026-06-16 (v0.3):** Folded Jedidiah's second-pass corrections. Clanhold caps are SOFT (half-revenue penalty, not a hard cap; clanhold-only) — removed all hard-cap enforcement. Added beastman family conversion (Domains of Chaos: 1 warrior + race noncombatants; ogre/troll ×4; tribal warriors → `available_tribal_warriors`). Added the **source-of-truth handoff rule** (24-mile until generated, then persisted 6-mile) and the **rolling-persisted single 6-mile map** model (resolves the false "cross-window" concern — there is no seam). Determined the §6 migration set (campaign_origin, `elevation_raw`, roads entity, river width, pois context REQUIRED; hex_substrate + domains provenance DEFERRED). Added `elevation_raw` persistence for the future 3D renderer; the post-MVP culture-weighted human archetype sub-roll (§7.4); 6-mile road/river generation. Confirmed open Qs a/c/d/e/f/g/h.
- **2026-06-16 (v0.2):** 6-mile-as-play-surface reframe; 24-mile world-map + data layer; ~30×40 window via full procedural zoom-in; NPC depth = in-region chains + all sovereigns; `gdd-region-zoom-in.md` critical-path.
- **2026-06-16 (v0.1):** Initial planning draft; full gap map, table mapping, provisional migrations, NPC paths (incl. beastman-ruler gap), pipeline, MVP, open Decision Register.
