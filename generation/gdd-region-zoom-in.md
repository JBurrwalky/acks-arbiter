# GDD: Region Zoom-In (24-mile → 6-mile content materialization)

**Document type:** Game Design Document (project-designed, generation/procedural)
**Authority:** PROJECT-DESIGNED — the 6-mile content-placement and natural-variation algorithms are engineering decisions. The scale hierarchy (24mi→6mi, 16:1) and the ACKS density/settlement/beastman tables are RAW and may NOT be changed. Subordinate to `acks_arbiter_design_brief_v11.md` (the §5.1 map-scale model) and to `gdd-setting-runtime-materialization.md` (which invokes this as its critical-path content pass).
**Status:** Draft v0.1 — specifies the lazy/eager 6-mile zoom-in that `gdd-setting-runtime-materialization.md` Phase M2 consumes. Terrain-tag *inheritance* (the per-child base) is already specified in `gdd-hex-subdivision.md §6`; this GDD owns the **content placement, the richer natural-variation passes, road/river generation, beastman intermingling, the rolling/persisted frontier, and the performance/optimization model.** No code written.
**Depends on ACKS rules:** `rules/acore_axioms_strongholds_and_domains.xml:14-21` (16:1 sub-hex ratio); `rules/ax_domains_of_chaos.xml:10-11,79` (125 fam/6-mile SOFT limit — half land revenue beyond, not a hard cap); `rules/ax_domains_of_chaos.xml:15-19,106-233,248-324` (beastman family composition, ogre/troll ×4, per-terrain clanhold density + race d100); `rules/acore-setting-construction-rules.xml:412` (~15 settlement points on a 6-mile *regional* map — **RE-VERIFY at build**, sourced from the setting-gen build notes); `rules/acore-campaign-hijinks.xml:632-638` (market class by urban families).
**Depends on project GDDs:** [`gdd-hex-subdivision.md`](gdd-hex-subdivision.md) (§5 aggregation, §6 the terrain-tag inheritance base this GDD enriches, §6.2 child indexing + seeding); [`gdd-setting-runtime-materialization.md`](gdd-setting-runtime-materialization.md) (the caller; source-of-truth rule; rolling-map model; migrations); [`gdd-terrain-system.md`](gdd-terrain-system.md) (the tag layers + movement/encounter derivation); [`gdd-settlement-stocking.md`](gdd-settlement-stocking.md) (interiors on entry — NOT here); [`gdd-lair-discovery.md`](gdd-lair-discovery.md) (emergent lairs — coexist, NOT here); [`gdd-realtime-scheduler.md`](gdd-realtime-scheduler.md) (zoom-in + frontier growth run as scheduled events); [`gdd-wilderness-hex-3d.md`](gdd-wilderness-hex-3d.md) (heightmap-era variation hooks).
**Modifiable by Claude Code:** Yes — all variation strengths, placement densities, chunk sizes, and growth thresholds are engineering/tuning decisions. The scale ratio and the RAW tables are not.
**Last updated:** 2026-06-16

---

## 1. Purpose and Scope

When the player's party plays at 6-mile scale (per `gdd-setting-runtime-materialization.md`), the world must exist at 6-mile resolution where they are. This GDD specifies the **zoom-in pass** that turns a 24-mile parent hex into its sixteen 6-mile children — terrain, content, roads/rivers, ownership, culture — in a way that **feels natural** (not 16 identical tiles), **performs** at the scale a real campaign explores, and is **deterministic and persisted** (computed once, never regenerated).

It runs in two modes, identical algorithm:
- **Eager** — at the handoff, for the ~30×40 starting extent (~80 parents) around the player's chosen city.
- **Rolling** — as the party approaches the generated frontier, one parent at a time, appended to the same growing 6-mile map.

What this GDD does **not** own: terrain-tag *inheritance* defaults (`gdd-hex-subdivision.md §6` — this GDD enriches them); settlement *interiors*/POI stocking (`gdd-settlement-stocking.md`, on entry); dungeon *layouts* (DG-V1, on entry); *emergent* wilderness lairs (`gdd-lair-discovery.md`, which coexists). It produces the **map and the placed-content stubs**; downstream systems flesh them out on contact.

---

## 2. ACKS Constraints

- **16:1 sub-hex ratio** (`rules/acore_axioms_strongholds_and_domains.xml:14-21`): each 24-mile parent → sixteen 6-mile children, indexed `child.q = parent_q*4 + cqi`, `child.r = parent_r*4 + cri`, `cqi,cri ∈ {0..3}` (`gdd-hex-subdivision.md §6.2`).
- **125 families/6-mile hex is a SOFT clanhold limit** (`rules/ax_domains_of_chaos.xml:10-11,79`): population distribution across children may exceed it; excess simply yields half land revenue at runtime (a domain-economy concern, NOT a placement clamp). **Never hard-cap here.**
- **Beastman intermingling tables** (`rules/ax_domains_of_chaos.xml:248-324`): per-terrain clanhold density (`clanhold_chance_per_6_mile_hex`, `clanholds_per_24_mile_hex`) and per-terrain race d100 — already extracted to `data/setting_generation/beastman_distribution.json`. Family composition (1 warrior + N race noncombatants; ogre/troll ×4) per `:15-19,160-233`.
- **~15 settlement points on a 6-mile regional map** (`rules/acore-setting-construction-rules.xml:412` — RE-VERIFY): the budget for *minor* 6-mile settlement scatter is a regional-map quantity, distinct from the 24-mile settlement density. Hamlets/villages below the 24-mile settlement threshold legitimately appear here.
- **Market class by urban families** (`rules/acore-campaign-hijinks.xml:632-638`): any minor settlement generated at 6-mile gets its market class from its own urban families.
- **Villages, Towns & Cities urbanization table** (ACKS Core "Placing Villages, Towns, and Cities", p.231; verify against `rules/acore-*`): a realm's peasant-family count → its **urban population** (~10%) + its **largest settlement** (family size band) + that settlement's **market class**. Applied **per realm, recursing the vassal tree** (largest realm first): each vassal realm gets its own largest settlement, placed **at/near the most-populous domain's stronghold** on water/road. **"A Class VI market exists at the domain's stronghold only"** — i.e. urban settlements CLUSTER at the stronghold. **Scale rule:** the 24-mile map omits Class IV-and-smaller; the **6-mile regional map omits only Class VI** → the 6-mile play map surfaces **Class V and larger** as settlements, and **Class VI stronghold-markets are surfaced as Stronghold POIs** (UI hooks the tabletop map omits but the game needs). **BASELINE ONLY:** the urban/agrarian/centralized/dispersed column-shifts and per-culture adjustments are DEFERRED (later phase) — assume the unshifted table now.
- **Auran title → ACKS tier mapping** (the AX3 reference's flavor names): Prefect=**Prince**/Principality, Palatine=**Duke**/Duchy, Legate=**Count**/County, Tribune=**Marquis**/March, Castellan=**Baron**/Barony. The feudal ladder **bottoms at Barony** (the `DomainTierTable` floor) — **there is no sub-Baron tier.** (Titles shift with realm size — a larger realm's "Prefect" is an Exarch's vassal, etc. — but the ACKS tier is set by family count, below.)
- **Domain size is set by FAMILIES, not hexes** (`titles_of_nobility` family thresholds; `DomainTierTable.tier_for_families`): decomposition partitions a realm by its **family budget**; the hexes a domain spans are an **estimation for placement only**, never the sizing input. (E.g. a borderlands Barony of ~125 families occupies roughly one 6-mile hex of low-density frontier, but the 125-family budget — not "1 hex" — is what defines it.)
- **Realm apportionment + garrison (ACKS II Judges Journal "Realm Apportionment", validated against AX3 — translate titles/classes to our model):**
  - **Population density → families/hex** (Step 8B table): families per 6-mile hex = families per 24-mile hex ÷ 16 (e.g. 125→2,000; **185→3,000** = the AX3 Borderlands base; 250→4,000; 375→6,000; 500→8,000). A ruler's **personal-domain hex count = personal families ÷ density**. The canonical **urban-centered personal domain ≈ 7 hexes** (the settlement hex + its 6 neighbours).
  - **Fan-out (Step 8E):** a Count's realm = personal domain + urban settlement + its vassals; the vassal families = realm − personal − urban, and **each Count has ≈4–6 Marquis (JJ "Viscounts") + ≈16–24 Barons** holding them. ACKS II *abstracts* these (computes only their total hexes); **WE MATERIALIZE them down to Baron** for UI hooks (§5.6). AX3 worked example: a Legate realm ≈3,950 fam − 725 personal − 110 urban = **3,115 vassal fam → 17 hexes**, +4 personal = **21-hex County**. So the full AX3 tree is ≈ 1 Prince → 4 Dukes → 20 Counts → ~80 Marquis → **~320–480 Barons (≈425–625 domains)** — much denser than a first read of the spreadsheet suggests.
  - **Domain classification (Step 9) → our 3 classes:** ACKS II uses civilized / borderlands / **outlands / unsettled / wildlands**; **collapse outlands + unsettled + wildlands → our `Wilderness`** (CLAUDE.md three-class rule — never introduce outlands/unsettled). Proximity heuristic: ≤48 mi of a city/large town ⇒ civilized; ≤72 mi ⇒ ≥ borderlands; named forests/swamps stay Wilderness. (Our `territory_class` already approximates this; reuse it.)
  - **Garrison (Step 10) → M4-3 `garrison_composition`:** minimum garrison gp = **2 gp/family civilized, 3 gp/family borderlands, 4 gp/family wilderness** (+ a separate urban-family rate; AX3 used 2 gp/urban + 3 gp/peasant at the capital, 4 gp/peasant elsewhere). Convert gp → troops by unit cost (Elite Cataphract 87 / Cataphract 75 / Horse Archer 45 / Vet Heavy Inf 24 / Composite Bowman 18 / Heavy Inf 12 gp), **~25% veterans**. Garrisons **stack up the liege chain** for Call-to-Arms (a Count can call his own + his Baronies'/Marches' garrisons). This is the deterministic, display-ready garrison; the live troop economy is a later Domain phase.

---

## 3. Performance & Optimization Model

The two questions: *how much 6-mile can we create/persist before breakdown,* and *how do we optimize.*

### 3.1 The numbers (grounded in real map sizes)
24-mile map presets (`setting_parameters.gd`): small 15×12 = **180**, medium 25×20 = **500**, large 40×30 = **1,200**, huge 60×45 = **2,700** parent hexes. Each parent → 16 children, so a *fully-explored* continent at 6-mile is **2,880 / 8,000 / 19,200 / 43,200** hexes.

| Quantity | Count | Cost |
|---|---|---|
| **Eager starting extent** (~80 parents) | **~1,280** 6-mile hex_cells + a few hundred content rows | ~2× the Avalon fixture (600 hexes) which already runs; one-time write behind the loading screen; ~100 KB on disk |
| **Rolling growth** (per frontier parent) | **16** hex_cells + a few content rows | milliseconds; scheduled event; imperceptible |
| **Fully-explored continent** (worst case, huge) | up to **43,200** hex_cells | ~4 MB on disk (SQLite is fine); the pressure is RENDER, not storage |

**Bottleneck is render texture memory + image-build time, not storage or generation.** `hex_map_renderer` rasterizes hexes to an image (cheap per-frame to blit; build-time + texture scale with hex count). Comfortable to several thousand active hexes; beyond ~10k a single image is wasteful.

### 3.2 Optimization levers (the answer to "can we optimize")
1. **Persist all, render near (chunked rendering) — the key lever.** Every explored 6-mile hex is persisted (cheap), but the renderer builds/keeps image chunks only within a radius of the party; distant chunks' *images* unload (data stays in the DB, rebuilt on approach). Caps render memory regardless of explored extent → the system is scale-free. Chunk size is a tuning parameter (e.g. one chunk = one 24-mile parent's 4×4 children, or a fixed N×N).
2. **24-mile world map from `setting_hexes`.** The world-map screen can render from the source-of-truth `setting_hexes` rather than a full `hex_cells` duplicate (≤2,700 rows; copying is also acceptable). Avoids a redundant continent-sized copy.
3. **Off-camera sovereigns as `named`-tier stubs.** Eager-create every sovereign (per the handoff ruling) as lightweight name+class+level+culture+alignment+morale; promote to `full` on contact. Hundreds = KB-scale.
4. **Abstract off-camera simulation.** The off-camera "political goings-on" run on *abstracted* domains (gp-value ledger, no per-hex) — the same abstraction the history sim used (cheap, hundreds of realms). (Phase M5.)
5. **Lazy fine content.** Settlement interiors, dungeon layouts, `settlement_pois`, encounter NPCs — all on contact. The zoom-in writes only stubs.
6. **Compute-once.** Deterministic + persisted → no recompute on revisit. The only ongoing cost is rendering the chunks near the party.

### 3.3 Budget recommendation
Eager window **~1,280** (safe, proven-scale). Keep the **actively rendered** region in the low thousands via chunking; persist without limit. Revisit chunk size only if profiling shows image-build hitches at the frontier.

---

## 4. Natural-Variation Algorithm

**Goal (Jedidiah):** do not plop 16 identical tiles because the parent is one type; mingle/dither/vary *smartly* and *naturally* — foothills, dense/light forest patches, grass/jungle oases in desert (especially near rivers) — while avoiding **both** too much uniformity **and** too much randomized noise. Dither polity boundaries and culture %s across the children too.

The algorithm composes **three structured passes** over the `gdd-hex-subdivision.md §6` base, each physically motivated, **budget-bounded** (so it reads as variation, not noise) and **coherence-clustered** (so it clusters, not salt-and-pepper). All are deterministic, seeded per `gdd-hex-subdivision.md §6.2`.

```
zoom_parent(P, neighbors[6]):
  1. BASE      → 16 children inherit P's tags (gdd-hex-subdivision §6.3 step 2)
  2. NOISE     → per-child smoothed_noise (gdd-hex-subdivision §6.3 step 3 + §6.5 smoothing)
  3. PASS A    → neighbor-gradient ecotones        (§4.1)   [boundary-directed]
  4. PASS B    → feature-driven local variation    (§4.2)   [river/elevation/coast-directed]
  5. PASS C    → coherent stochastic texture        (§4.3)   [remaining budget; patches]
  6. DITHER    → polity-boundary feathering + culture-% interpolation (§4.4)
  7. WATER/CITY→ gdd-hex-subdivision §6.6 / §6.3 step 6 (carrier child)
```

Each pass writes within a **per-layer deviation budget** (elevation ≤10%, biome ≤25%, civilization ≤5% of the 16 children — `gdd-hex-subdivision.md §6.4`). The passes are **ordered by priority**: gradients and features claim the budget first (structured deviation), and the stochastic pass fills only what remains (texture). A **strength dial** per pass (`grad_strength`, `feature_strength`, `texture_strength`) tunes the uniformity↔noise balance globally.

### 4.1 Pass A — Neighbor-gradient (ecotones)
A child near a parent edge is biased toward the **adjacent parent's** biome/elevation, producing a feathered transition rather than a hard 24-mile step.

- For each child, compute its **edge proximity** to each of the 6 parent neighbors (children in the outer ring of the 4×4 are near one or two neighbors; interior children near none).
- For a neighbor `N` whose biome is one impedance step from `P`'s, the bordering children gain a deviation bias toward `N`'s biome, **strongest in the corner/edge children, fading inward over 2–3 children**. Example: a `woods` parent bordering a `clear` parent → the clear-facing edge children lean `woods → (scrub subtype) → clear`, interior stays `woods`.
- Elevation gradients the same way (a `mountains` parent bordering `flat` → the flat-facing children step `mountains → hills → flat` — see also §4.2 foothills).
- Interior children (near no qualifying neighbor) receive **no** Pass-A deviation → uniform-region cores stay uniform (anti-over-variation).

This makes boundaries **directional and natural**, and it is the primary anti-uniformity mechanism without being random — the variation *points* at the neighbor.

### 4.2 Pass B — Feature-driven local variation
Within-parent features override/augment the base. These are the cases Jedidiah named:

- **Riparian corridors (the oasis case).** Children a river edge passes through or adjacent to get a **+1 wetness step**:
  - desert parent → riverside children become `clear` (grassland subtype) or, if latitude/precip permits, `jungle` (an oasis);
  - clear parent → riverside → `woods` (gallery forest);
  - the corridor follows the river's child path (from the inherited boundary constraints, `gdd-hex-subdivision.md §6.3` step 7), so it's a coherent ribbon, not scattered.
- **Orographic foothills.** Around any `mountains` child (or toward a `mountains` neighbor), adjacent children step **mountains → hills → flat** in a ring, instead of a cliff edge. Same for `hills → flat` skirts. Deterministic ring, bounded by the elevation budget.
- **Coastal fringe.** `ocean`/`lake`-adjacent land children get a beach/marsh/`clear` deviation (coast is rarely the parent's interior biome).
- **Rain-shadow (heightmap-era hook).** When continuous 6-mile height exists (`gdd-wilderness-hex-3d.md`), the lee side of a ridge gets a drier biome deviation. Hook only; off for MVP.

Pass B claims budget after Pass A (features beat generic gradients where they conflict — a river oasis overrides a faint ecotone bias).

### 4.3 Pass C — Coherent stochastic texture (patches)
Whatever deviation budget remains after A and B is spent on **coherence-smoothed noise** (`gdd-hex-subdivision.md §6.5`) to create natural, feature-independent **patches**:

- **Dense vs light forest** via `biome_subtype` (`forest_dense` vs the base `woods`) — the cheapest, highest-value texture, and exactly Jedidiah's "patches of dense and light forest."
- Copses in grassland (`woods` specks in `clear`), rocky scrub in desert (`desert_badlands` subtype), tundra/taiga mottling.
- Clustered (smoothed noise) so patches are 2–3 contiguous children, never single-cell speckle.

Because A and B usually consume most of the budget near boundaries/features, Pass C dominates only in **uniform interiors**, adding gentle texture where there's nothing else going on — which is precisely where "16 identical tiles" would otherwise occur.

### 4.4 Polity-boundary feathering + culture-% interpolation
Political and cultural geography dither across the children too (Jedidiah's explicit ask).

- **Polity-boundary feathering.** A child near a parent boundary with a **different owning polity** may flip ownership to that neighbor with probability scaled by:
  - **contested-ness** — how much war/conquest/pillage history that border carried (from the event log / `setting_polities` provenance): hotly-contested borders feather more (raids blur the line); quiet borders stay crisp;
  - **terrain hardness** — rivers/mountains/coast **dampen** feathering (natural defensible borders hold); open plains feather freely.
  Bounded so a polity never loses its **core** children (only outer-ring boundary children flip). Result: jagged, terrain-respecting borders at 6-mile instead of 24-mile-hex steps.
- **Culture-% interpolation.** Each child's `culture_weights` = `P`'s weights **blended toward adjacent parents' weights** by edge proximity (the Pass-A gradient), renormalized, with the **minimum-presence floor** (default 0.1%) retained. A border child genuinely has mixed population — consistent with the substrate philosophy (traders, refugees, persecuted minorities appear anywhere). `alignment_weights` interpolate the same way. (These feed runtime NPC culture + derived religion; persisted on the 6-mile hex per the source-of-truth rule, or read-back from the parent for MVP per `gdd-setting-runtime-materialization.md §5.10`.)

### 4.5 The uniformity ↔ noise dial
The three strength parameters give a single tunable axis:
- **Low strengths** → near-uniform children (the §6 base alone).
- **High strengths** → strong ecotones/features/patches.
- The **priority ordering** (A → B → C within a fixed budget) guarantees the character: structured deviation at boundaries/features, gentle texture in interiors, never random chaos (budget cap) and never flat (texture floor).
These are **eyeball-tunable** once a real region renders (godot-ai MCP) — expect a calibration pass, like the history-sim knobs.

---

## 5. Content Placement

After terrain (§4), place content onto the resolved children. Tagged 24-mile content projects down (§5.1); the **AX3-density decomposition spine** (§5.6) then fills each in-window realm out to its full per-6-mile-hex vassal tree, urban settlements, strongholds, garrisons, and Stronghold POIs; minor scatter (§5.2), beastman intermingling (§5.3), and roads/rivers (§5.4) hang off that spine; population is distributed last (§5.5). **§5.6 is the controlling algorithm; read it first — §5.1–5.5 are the passes it drives.** The *phase sequencing, migrations, and acceptance bar* for building this live in `gdd-setting-runtime-materialization.md §15.5` (which cross-references this section for the algorithm).

### 5.1 Carrier-child projection (24-mile tags → 6-mile)
Each 24-mile-tagged settlement (`setting_settlements`), dungeon (`setting_ruin_seeds`), POI (`setting_poi_seeds`), and fortification (`setting_fortifications`) is placed on **exactly one** of the 16 children — the **carrier child** (`gdd-hex-subdivision.md §6.3` step 6: highest-noise child, biased toward roads/rivers/lower-impedance terrain for settlements; toward dramatic/remote terrain for dungeons). Writes the runtime stub row (`settlement_entrances`, `dungeon_entrances`, `pois` with own context, `strongholds`).

### 5.2 Minor 6-mile content scatter
The 24-mile scale intentionally omits sub-threshold content; the 6-mile scale adds it, **budgeted** (not noise):
- **Minor settlements** (hamlets/villages below the 24-mile cut): up to ~the regional ~15-settlement-points budget (`acore:412`, re-verify), placed on civilized/borderlands children near roads/water, market class from their own families. Full `settlement_entrances` stubs.
- **Lesser ruins / wilderness POIs:** a small budget of geometric dungeons + natural-feature POIs on dramatic children, reusing the setting-gen scoring heuristics at 6-mile.
- **Emergent lairs are NOT placed here** — `gdd-lair-discovery.md`'s lazy per-hex lair system continues to own them and coexists (authored landmarks vs emergent lairs).

### 5.3 Beastman per-race intermingling (the deferred "Part B")
A 24-mile beastman/clanhold area carries one generic culture + a race hint. At zoom-in, materialize the **per-race mix** from `data/setting_generation/beastman_distribution.json`:
- per child, roll `clanhold_chance_per_6_mile_hex` for the child's terrain; on a hit, roll the per-terrain **race d100**;
- create a clanhold (a clanhold-style domain + `strongholds.archetype='clanhold'` + a `BeastmanRulerMaterializer` chieftain), with **family composition** per race (1 warrior + N noncombatants; ogre/troll ×4 families + 4× land); set `available_tribal_warriors` = families.
- Eager within the generated area; lazy at the frontier. Deterministic per child seed.

### 5.4 Road & river generation (Decision 7h)
- **Project** the 24-mile roads/rivers down to their child boundary constraints (`gdd-hex-subdivision.md §6.3` step 7; §5.2 road/river aggregation in reverse), detailing the interior path biased by terrain (roads prefer cleared/civilized + low impedance; rivers follow the wetness/elevation gradient).
- **Generate new** 6-mile roads/rivers to connect the **newly-placed minor settlements** (§5.2) that did not exist at 24-mile — short local roads to the nearest existing road/settlement; minor streams along low-elevation child chains feeding the main rivers. Persist road metadata in the runtime `roads` entity (class/name/purpose) + `hex_overlays` geometry; rivers in `hex_river_edges` (+ width).

### 5.5 Population distribution
Distribute each parent's `population_band` across its civilized/borderlands children weighted by land value / settlement presence, **with no hard cap** (the clanhold 125 soft limit is a runtime economy penalty, §2). Write per-child `domain_hexes` land values; aggregate to the domain's `peasant_families`. **The per-6-mile-hex family count produced here is the input to the §5.6 decomposition** — store it (new `domain_hexes.families`, conserved: a parent's 16 children sum to its `population_band`).

### 5.6 AX3-density fill — the per-window decomposition spine

This is the **controlling content-density algorithm** (motivated by the AX3 "Capital of the Borderlands" principality as the per-window detail bar — see `gdd-setting-runtime-materialization.md §15.5`). The 24-mile `setting_*` handoff is the **structural budget**; this pass *realizes* that budget on the real 6-mile substrate. **Ruling (Jedidiah 2026-06-19):** synthesize this detail at the 6-mile materialization (here), NOT by expanding the `setting_*` tables — eager in the play window, lazy at the frontier; off-camera stays coarse. Everything below is deterministic (`WorldGenRng`, §7), conserves population (§5.5), and reuses `DomainTierTable` + the §2 urbanization table.

**(a) Decompose every in-window civ/BL realm to Barony, by family budget.** For each in-window 24-mile leaf domain (today `setting_domains` bottoms at one leaf per *24-mile* hex — 16× too coarse), split its 16 children's families into a continuous **County → March → Barony** runtime `domains` ladder so **every populated 6-mile hex sits in exactly one Barony** (the floor; no sub-Baron). Partition by **families, not hexes** (§2): peel children whose own families stand as a `(tier−1)` realm into leaves at that rank; cluster the remainder into synthesized intermediate nodes (mirrors the existing 24-mile `_split_realm`, one scale-step deeper). Wire `liege_domain_id` up to the 24-mile leaf and on to the sovereign. Fan-out is RAW (§2 / JJ Step 8E): a Count → ~4–6 Marquis + ~16–24 Barons. Each domain gets a **stronghold at its seat hex**, valued by **formula, not a per-tier table** (resolved rule below): `stronghold gp = hexes the domain personally secures × the per-6-mile-hex securing rate by territory` (civ 15,000 / BL 22,500 / wild 30,000), floored at one hex. A Barony (= one 6-mile hex) takes the 1-hex rate; a Model-E interior node (March) personally secures 0 hexes and so also falls to the 1-hex floor (its power is the vassal tree, not demesne); a clanhold scales by its whole hex group. Helpers live on `DomainTierTable` (`min_stronghold_gp` / `stronghold_gp_for_hexes` / `max_hexes_for_stronghold`), shared with the player securing system.

> **RESOLVED 2026-06-20 (Jedidiah) — minimum domain size = one 6-mile hex.** The RAW smallest domain is a 1.5-mile hex (a 6-mile hex = 16 of them); we do **NOT** build that local-map layer (it's the 6-mile zoom-in again, and little play happens there). Instead **one Barony = one full 6-mile hex**, sized by that hex's families — so a dense civilized hex yields a single **"fat" Barony** (up to ~780 families) rather than ~6 small Castellans, and sparse wilderness/borderlands hexes (~125–250 families) land at true Castellan size. This conserves area + families and matches the AX3 *average* Castellan density (~1 per habitable hex); the AX3 "~6 watchtowers per road hex" dense-corridor cluster collapses into the one fat Barony (those tiny holdings lack a market and aren't worth accessing). Knock-on: the **minimum stronghold cost rises** from the 1.5-mile RAW figure (1,000/1,500/2,000 civ/BL/wild) to the 6-mile-hex figure (15,000/22,500/30,000) — the per-hex securing rate below. Also simplifies player land grants / conquest / securing (1 hex = 1 grant). **Per-Barony tribute up the chain is DEFERRED** (open question: build explicit tribute flows for NPC realms, or keep the abstract "realm families × 18^0.6 gp" NPC model? — revisit; player realms may differ).
>
> **REVISED 2026-06-20 (Jedidiah) — stronghold value is a FORMULA, not per-tier.** Replaced the per-tier `DomainTierTable` stronghold figures (for sizing actual domain strongholds) with: **max 6-mile-hex territory of a domain = `floor(stronghold gp ÷ (15,000 × territory modifier))`**, modifier civ 1.0 / borderlands 1.5 / wilderness 2.0 (so the per-hex securing cost is 15,000 / 22,500 / 30,000 gp — wilderness corrected from the earlier 32,000). **Remainders round down** (a partial securing value claims no hex — no toe-holds), and the 1-hex cost is kept as a **hard floor** (spend less and you secure nothing — no orphaned strongholds, no frustration). Every domain owner must hold a stronghold. Implemented on `DomainTierTable` (`min_stronghold_gp`, `stronghold_gp_for_hexes`, `max_hexes_for_stronghold`) so the materializer and the future player-securing/conquest system share one rule; `stronghold_value_for_tier` is retained only as the abstract 24-mile revenue/tribute reference.

This `~750–1,100 domains` per eager window is *much* denser than the spreadsheet's surface read. **Perf split (to keep the eager window tractable at that count):** the **domain row + its `strongholds`/Stronghold-POI row are EAGER** (cheap static rows — these are the clickable UI hooks); the **ruler CHARACTER is materialized EAGER only for Count-tier and above, and LAZY/names-only for Marquis + Baron leaves** (`persistence_tier='named'`, promoted to a full `ClassedNpcBuilder` NPC on first interaction/visit — the existing lazy-NPC pattern). Honor pre-rolled `setting_domains` rulers; deterministic bare class/level for invented leaves on promotion (the culture-kit archetype sub-roll is the deferred §7.4 post-MVP step). Beastman/clanhold realms take the §5.3 path instead (shallow chieftain→sub-clanhold tree + per-race intermingling), not this feudal ladder.

**(b) Urbanize per the §2 table — settlements cluster at strongholds.** Walk the realm's domains largest-first; each domain's **largest settlement** = the §2 table lookup on its peasant families, **placed at/near that domain's stronghold** on water/road. On the 6-mile map surface **Class V+** as `settlement_entrances`; **Class VI** is a *stronghold-market* surfaced as a **Stronghold POI** (below), not a settlement row. Market class falls out of each domain's **actual urban families**, so a borderlands/wilderness County seat (a "Téros" border fort) lands at **Class VI automatically** — no special-casing (this is the Túros Tem correction). This **replaces** the vague "~15 settlement-points budget" framing in §5.2: settlement count/size is *derived* from the decomposed realm's urbanization, not a flat scatter quota. The recovered Class IV–VI urban families are the ones the 24-mile rank-size model intentionally folded away → conservation-consistent, not double-counting.

**(c) Strongholds & Stronghold POIs (UI hooks).** Every leaf and interior domain has a `strongholds` row at its seat. Domains with **no urban settlement** — Marquis "cavalry watchtowers" (added stable/palisade value, no market) and Baron watchtowers (the ~6-per-road-hex frontier towers securing small domains, per AX3 text) — are also surfaced as **Stronghold POIs** so the party can interact with them (tabletop maps omit these; the game needs the clickable hook). So the "watchtower line" is **not a separate random scatter** — the watchtowers *are* the leaf-domain strongholds.

**(d) Garrison composition (denormalized, display-ready).** Materialize a per-domain **`domains.garrison_composition`** (new column, TEXT JSON: troop counts by unit type) via the RAW **JJ Step 10** model (§2): garrison gp = `families × {2 civ / 3 BL / 4 wilderness}` (+ the urban-family rate), converted to troops by unit cost (Elite Cataphract 87 / Cataphract 75 / Horse Archer 45 / Vet Heavy Inf 24 / Composite Bowman 18 / Heavy Inf 12 gp) with ~25% veterans; garrisons **stack up the liege chain** (a Count's Call-to-Arms = own + vassals'). Deterministic from the domain's families + classification + tier, so the map/LLM/UI render AX3-level fort detail **now** without the live troop economy. **The real economic troop entity** (recruitment, monthly upkeep, `troop_units`) is a later Domain-phase system, explicitly out of handoff scope — flag, don't build here. `strongholds` already carries `cp_value` + `garrison_capacity`.

**(e) Adventure-site density re-budgeted to 6-mile.** The 24-mile dungeon/POI budgets (`infrastructure_generator §9.3/§9.7`) are 24-mile quantities; layer a 6-mile re-budgeted scatter (§5.2) so site density approaches the AX3 bar (~1 interactable per 1–2 settled/frontier hexes; thinning in deep wilderness). Add a **`faction_stronghold`/inhabited-site POI archetype** (wizard tower, ogre warband, dwarven vault, beastman clanhold). **Ruling:** place the full density **now as data + LLM-narrated stubs**; deep POI contents-on-discovery mechanics are a separate, later system. The lazy emergent-lair system (`gdd-lair-discovery.md`) still coexists.

**Acceptance bar (the "interactivity floor"):** no large stretch of empty 6-mile hexes in settled/frontier bands — every settled hex has a settlement *or* stronghold *or* ruler, every few frontier hexes a fort/watchtower or lair, every interesting-terrain cluster a dungeon or POI. Densities are tunable dials, MCP-calibrated on a rendered window against the AX3 numbers. **Golden test:** the decomposition + urbanization, run over the AX3 Borderlands realm parameters, should reproduce its published structure (≈185 domains; 1 Prince → 4 Duke → 20 Count → 80 Marquis → 80 Baron; the Téros County forts at Class V civ / VI BL-WIL; the watchtower line) — validated against the ACKS II Judges Journal partition of AX3.

---

## 6. The Rolling, Persisted Frontier

One growing `regional_6mi` `hex_maps` row (per `gdd-setting-runtime-materialization.md §4.3`), not discrete windows.

- **Initial extent:** the eager ~30×40 around the start city, snapped to whole 24-mile parents (footprint = those parents).
- **Growth trigger:** when the party comes within a threshold distance of the generated frontier (a tunable ring, e.g. 3–4 six-mile hexes from the edge), schedule a `zoom_in_requested` event (`gdd-realtime-scheduler.md`) for the next parent(s) just beyond the edge; it completes before movement resumes.
- **Append + persist:** the new parent's 16 children + content are written to the **same** map and footprint, permanently. Never regenerated, never discarded → no seam (the false "cross-window" concern is moot).
- **Newly-located domains:** an off-camera abstracted domain whose hexes the frontier reaches becomes **located** (gains `location_map_id` + `domain_hexes`) append-only; the migration-119 `compute_consistent_domain_hex_set` reconciles its cross-scale hex set.
- **Determinism:** growth order doesn't matter — each parent's children are a pure function of its seed, so the same hexes always resolve identically regardless of when the player reaches them.

---

## 7. Determinism & Data Model

- **Seeding:** every roll keys on `(campaign_seed, parent_q, parent_r, child_local_q, child_local_r [, salt])` via `WorldGenRng` (`gdd-hex-subdivision.md §6.2`); per-pass salts keep A/B/C/dither independent. No `Date.now()`/global RNG.
- **Writes:** `hex_cells` (16/parent, + `elevation_raw`), `hex_river_edges`, `hex_overlays` + `roads` entity, `settlement_entrances`, `dungeon_entrances`, `pois` (+context), `strongholds`, `domain_hexes`, clanhold `domains`/`characters` — all on the `regional_6mi` play map, campaign-scoped.
- **Source of truth:** once a parent is zoomed, its 6-mile rows are authoritative; pre-zoom reads fall back to `setting_hexes` (`gdd-setting-runtime-materialization.md §4.2`).
- **Idempotence:** a parent is zoomed at most once (guard on footprint membership); re-entry is a no-op.

---

## 8. Open Questions / Architectural Concerns

- **Chunk size + unload policy.** §3.2 lever 1 needs a concrete chunk granularity and an LRU/radius unload rule; pick after profiling the image-build at the frontier. Persisted data is never unloaded — only render images.
- **Strength-dial calibration (§4.5).** `grad_strength`/`feature_strength`/`texture_strength` + the feathering probability need an eyeball pass on a rendered region (godot-ai MCP), like the history-sim knobs. Start conservative.
- **6-mile `elevation_raw` synthesis.** Children currently inherit the parent's raw height flat; true continuous 6-mile height (for foothill heightmaps + rain-shadow §4.2) is a joint concern with `gdd-wilderness-hex-3d.md`. The variation passes are written to consume it when it exists.
- **`acore:412` settlement-point budget — RE-VERIFY** the citation + number at build (sourced from setting-gen notes, not re-read here).
- **Ecotone direction at corners.** A corner child borders two neighbors; resolve the gradient by the stronger (nearer/larger-impedance-gap) neighbor, or blend — decide at implementation, low stakes.
- **Polity feathering vs. domain-hex consistency.** Feathered ownership at 6-mile must still satisfy the migration-119 cross-scale consistency check (a child flipping owner means the parent's aggregated ownership must still hold). Confirm the feathering stays within the "parent owner = plurality of children" tolerance.
- **Frontier prefetch.** Optionally pre-zoom one parent-ring ahead of the trigger during idle, to hide even the 16-hex hitch. Defer unless profiling demands it.

---

## 9. Revision History

- **2026-06-19 (v0.2):** Added **§5.6 AX3-density fill** (the per-window decomposition spine) + §2 RAW grounding (Villages/Towns/Cities urbanization table, Auran→ACKS title mapping, domain-size-by-families). Motivated by Jedidiah's AX3 "Capital of the Borderlands" reference as the per-6-mile-window detail bar. Rulings folded in: synthesize the to-Baron detail at 6-mile materialization (not by expanding `setting_*`); denormalized garrison now; rich POIs as stubs now; beastman shallow clanhold tree. Corrections folded in: Tribune=Marquis/March, Castellan=Baron/Barony (no sub-Baron); settlements cluster at the domain stronghold; County border forts (Téros) are Class V civ / VI BL-WIL; Marquis/Baron watchtowers surface as Stronghold POIs for UI hooks. Phase sequencing/migrations live in `gdd-setting-runtime-materialization.md §15.5` (mutual cross-reference). §5.5 now stores per-6-mile-hex `families` for the decomposition. **Validated against the ACKS II Judges Journal "Realm Apportionment" (same day):** added the RAW density→families table, the personal-domain-by-density sizing (urban-centered ≈7 hexes), the Count fan-out (~4–6 Marquis + ~16–24 Barons; corrects the per-principality count to ≈425–625 domains), the JJ Step-10 garrison model (2/3/4 gp per family by class → troops by unit cost, ~25% vet, stacking up the chain), the classification mapping (outlands/unsettled/wildlands → our Wilderness), and the eager/lazy perf split (eager domain+Stronghold-POI rows; lazy Marquis/Baron ruler NPCs).
- **2026-06-16 (v0.1):** Initial draft, authored as the critical-path content pass for `gdd-setting-runtime-materialization.md` Phase M2, in response to Jedidiah's three build-time concerns: §3 performance/optimization model (grounded in real map sizes + the chunked-render lever + off-camera compression); §4 the natural-variation algorithm (neighbor-gradient ecotones + feature-driven local variation incl. river oases & foothills + coherent stochastic patches + polity/culture dithering, with a uniformity↔noise dial); §5 content placement (carrier-child projection, minor scatter, beastman intermingling, road/river generation); §6 the rolling/persisted frontier. Enriches `gdd-hex-subdivision.md §6` (the terrain base) rather than restating it.
