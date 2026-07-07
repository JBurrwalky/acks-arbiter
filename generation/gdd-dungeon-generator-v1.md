# GDD: Random Dungeon Generator — V1

**Authority:** PROJECT-DESIGNED — orchestration pipeline tying the existing layout generator to RAW ACKS stocking rules. ACKS Constraints (the d100 dungeon stocking table, monster level tables, treasure types, in-lair logic) are sacred and applied verbatim, with **one explicitly documented deviation** noted in §2 (lair non-coalescing, see §11.7).
**Status:** Draft v1.2 — v1.1 incorporated Jedidiah's open-question resolutions (door material rules in layout GDD §8.3, lair non-coalescing as intentional RAW deviation, Trap/Unique encode-and-fallback, constraint-aware stair placement, build-time XML encoding). **2026-07-06: multi-floor orchestration superseded in part by [`gdd-dungeon-contiguous-3d.md`](gdd-dungeon-contiguous-3d.md)** — stair anchoring/radiate-outward order replaced by a vertical plan + composed single volume; navigability BFS moves to the real 3D movement graph; stocking iterates zones instead of rooms (identical for single-zone rooms). Supersession banners mark the affected sections; the ACKS Constraints in §2 and all stocking/treasure/key-lever logic are unchanged.
**Depends on ACKS rules:** `rules/acore-setting-construction-rules.xml:573-789` (dungeon construction pipeline, stocking table, monster placement rules, treasure assignment rules); `rules/acore-monster-stocking-rules.xml:22-138` (dungeon wandering monster procedure, dungeon wandering monster level table, random monsters by level table, wandering monster table guidelines, NPC parties procedure); `rules/acore_treasure_and_magic_items_rules.xml:1-200+` (treasure types A–R, generation procedure, accumulation categories, gem and jewelry sub-tables).
**Depends on project GDDs:** [`gdd-dungeon-layout.md`](gdd-dungeon-layout.md) (produces the floor plan that this generator stocks; defines the DungeonLayout / RoomData / DoorData / StairData schema and the diamond-grid cell-based wall model; §8.3 provides the door material distribution this generator consumes; §5.2 re-flavor of Wizard's Dungeon as universal fallback applied as companion edit alongside this draft); [`gdd-dungeon-map-ui.md`](gdd-dungeon-map-ui.md) (defines the runtime door / lever / key interaction grammar — Bash Door, Unlock with matching key, Force Portcullis, Use Lever — that this generator must produce solvable content for); [`gdd-realtime-scheduler.md`](gdd-realtime-scheduler.md) (evil-door auto-close events; entity-context model that the dungeon is consumed by).
**Modifiable by Claude Code:** Yes — all engineering decisions (validation algorithms, key/lever placement heuristics, retry counts, treasure ledger format, runtime data encoding format) are open. The ACKS Constraints in §2 and the user-specified V1 behaviors in §3 are not.
**Last updated:** 2026-05-27

---

## 1. Purpose and Scope

The Random Dungeon Generator V1 is the end-to-end pipeline that turns a dungeon seed (entrance tier, floor count, entrance floor index, optional type/size/seed) into a fully stocked, navigable, solvable multi-floor dungeon ready for the EventScheduler to load and for the player to enter. It is the bridge between the already-designed layout generator ([gdd-dungeon-layout.md](gdd-dungeon-layout.md)) and the RAW ACKS stocking / treasure / wandering-monster rules.

V1 is deliberately scoped as a "gonzo" system test: a single fixed dungeon type (Wizard's Dungeon, re-flavored as a generic monster-attractor dungeon — see §7) serves as the universal fallback for **every** dungeon on a campaign map until V2 introduces additional types. Traps and unique encounters are deferred but the dungeons are **forward-marked** for their re-introduction: rooms rolled as Trap or Unique on the d100 stocking table are encoded with the original category (so the V2 systems can find them and plug in the real content) **and** carry a fallback mechanism so V1 dungeons are still playable today (§11.4, §11.5). Dungeon factions, hand-authored encounter tables, and LLM narrative passes are all deferred (§15). What V1 *must* do correctly is six things:

1. Accept or derive a difficulty tier range across multiple floors per the user-specified rule (entrance floor is easiest; each step from the entrance adds one tier).
2. Generate a multi-floor layout via the existing layout generator, with hard navigability checks that no room is unreachable and with **constraint-aware stair placement** so multi-floor dungeons always generate cleanly on the first attempt (§8.1).
3. Stock each floor per the RAW ACKS d100 dungeon stocking table (`rules/acore-setting-construction-rules.xml:629-641`) using the floor's tier as the dungeon level for monster and treasure rolls.
4. Resolve treasure end-to-end into coins, gems, jewelry, and magic items (not deferred-resolution tags).
5. Place a key for every locked indestructible door and a wired lever for every portcullis, in rooms reachable without first crossing the door the key/lever opens — across floors if necessary.
6. Validate that every dungeon entrance and floor-to-floor stair is reachable from the entrance cell with all doors in their generated initial states.

The output is a populated DungeonLayout (the existing schema from `gdd-dungeon-layout.md` §11, extended in §4 below) plus per-floor stocking ledgers. The session runner then loads this output into a 3D tactical scene per `gdd-dungeon-layout.md` §12.3.

Critically, the V1 generator **never reads `rules/*.xml` at runtime**. All ACKS tables required by the generator are encoded at build time into runtime data files; see §12 for the encoding rules and the conventions reference.

---

## 2. ACKS Constraints

These come from the books and may NOT be changed. Where V1 deviates from RAW, the deviation is **flagged explicitly** with the design rationale:

- **The dungeon construction procedure runs in a fixed order:** choose type, draw map, stock each room, place monsters, place traps, add unique encounters, assign treasure, finalize descriptions (`rules/acore-setting-construction-rules.xml:573-583`, `constructing_the_dungeons`). V1 follows this order verbatim except that "place traps" and "add unique encounters" become *placeholder-and-fallback* steps per §11.4 and §11.5 (per Jedidiah's direction; the room is still tagged with the original category so V2 can plug in real content).
- **Room contents are determined by a single d100 roll per room on each dungeon level:** 01–30 Empty (15% chance of treasure), 31–60 Monster (treasure if lair), 61–75 Trap (30% chance of treasure), 76–00 Unique (treasure as needed) (`rules/acore-setting-construction-rules.xml:621-642`, `stocking_the_dungeon` table `dungeon_stocking`). The d100 roll itself is sacred. V1's placeholders for Trap and Unique preserve the **d100 roll, the contents category, and the treasure rates** exactly; only the *trap mechanism* and *unique encounter content* are deferred.
- **Monster selection uses two cascaded rolls:** first 1d12 on the Dungeon Wandering Monster Level table (`rules/acore-monster-stocking-rules.xml:76-94`, `dungeon_wandering_monster_level`) using the floor's dungeon level row to pick which monster-level table to consult; then 1d12 on the selected Random Monsters by Level table (`rules/acore-monster-stocking-rules.xml:112-136`, `random_monsters_by_level`) to pick the specific monster and its number appearing. This two-stage roll automatically produces the small-chance-of-deeper-or-shallower-monster behavior that supplies cross-tier variety — V1 does NOT need a project-designed encounter table.
- **Number-appearing adjustment for cross-tier picks:** when the rolled monster's table differs from the floor's dungeon level, increase or decrease the rolled number appearing by one-half for each step of difference, rounded **down** (`rules/acore-monster-stocking-rules.xml:42-46`). This is one of the rare cases where ACKS explicitly does not use banker's rounding, and the project-wide banker's rounding convention is overridden by this specific RAW rule. The exception is recorded in `docs/coding_conventions.md` §3.3 as a companion edit to this GDD.
- **In-lair logic — V1 DEVIATES FROM RAW HERE.** RAW (`rules/acore-setting-construction-rules.xml:654-657`) says that if the stocking process produces multiple encounters of an organized monster type on the same floor, the dungeon is assumed to contain a single lair of that type, with one room as the lair chamber and other groups as guard posts / barracks / splinter colonies. **V1 does NOT coalesce.** Each rolled monster group is independently checked for `% In Lair` per its catalog entry; each lair gets its own treasure roll. The rationale (per Jedidiah): when the faction system lands, multiple same-race lairs become competing or allied factions of the same race. Coalescing into a single lair at V1 would foreclose that design space. See §11.7 for the algorithm.
- **Placement preferences:** lower-level monsters can be placed near inter-level connections or as guards for stronger intelligent monsters; higher-level intelligent monsters can be placed in hidden or inaccessible areas; powerful unintelligent monsters may dominate isolated sub-areas alone (`rules/acore-setting-construction-rules.xml:659-663`, `placing_monsters` `placement_rules`). V1 implements a single heuristic in §11.8; richer placement is V2.
- **Treasure rules:** monster lairs have treasure per the monster's treasure type; empty rooms have treasure 15% of the time; trap rooms have treasure 30% of the time. Use the unprotected treasure table by dungeon level and 1d6 for treasure in empty or trap rooms (`rules/acore-setting-construction-rules.xml:742-779`, `assigning_treasure` and table `unprotected_treasure`). Target ratio is 4 gp of treasure per 1 XP of monsters on each floor (step 11); V1 logs deviation from this ratio but does not auto-balance (see §13.3).
- **Treasure types A–R are resolved by rolling each coin / gem / jewelry / magic-item column independently per the treasure type table** (`rules/acore_treasure_and_magic_items_rules.xml:9-87`, `treasure_generation` procedure and `treasure_type_table`). Treasure types fall into three accumulation categories — Hoarder (B, D, H, N, Q, R), Raider (E, G, J, L, O), Incidental (A, C, F, I, K, M, P) — which affect how the treasure presents physically.
- **Wandering monster check during play** (informative, not generated by this GDD): every 2 turns of dungeon exploration, 1d6 with encounter on 6+ (`rules/acore-monster-stocking-rules.xml:23-32`, `encounter_check`). The encounter table this check uses for each floor is the same Dungeon Wandering Monster Level row that V1 uses for stocking — V1 attaches it to the floor data (§4.2) so the runtime can roll without re-doing math. **Note (§15):** the wandering-monster table mechanism is itself a stopgap; the long-term design replaces it with overstocking-plus-patrols-plus-respawn, at which point the attached table becomes vestigial.

---

## 3. V1 Project Decisions (User-Specified)

These are not from ACKS — they are V1 design choices Jedidiah established for this generator:

1. **Tier API shape:** the generator accepts `(entrance_tier: int 1–6, floor_count: int ≥ 1, entrance_floor_index: int ≥ 1)`. Per-floor tier is derived as `clamp(entrance_tier + |floor_index − entrance_floor_index|, 1, 6)`. See §6.
2. **Single dungeon type:** V1 uses Wizard's Dungeon (re-flavored per §7) for every dungeon. If the caller passes any other `dungeon_type` value, the generator logs a warning and falls back to Wizard's Dungeon.
3. **Trap rooms (d100 61–75) → encoded as `trap_placeholder` with Locked Secret Door fallback.** The room keeps `contents_kind = "trap_placeholder"` so V2's trap GDD can find these rooms and plug in real traps. The fallback challenge: one of the room's bordering doors is forcibly upgraded to be **both Locked and Secret** (via the `is_secret` overlay flag added in §4.2). Treasure chance remains **30%** per RAW. See §11.4.
4. **Unique rooms (d100 76–00) → encoded as `unique_placeholder` with monster-roll fallback.** The room keeps `contents_kind = "unique_placeholder"` so V2's unique-encounter system can find it. The fallback content: re-roll on the Monster stocking procedure (§11.3) and place the resulting MonsterGroup in this room. Treasure follows lair rules (treasure if `% In Lair` hits). See §11.5.
5. **Trapped doors (door type from layout GDD §8.1) → encoded as `trapped` with Locked behavior fallback.** The DoorData keeps `type = "trapped"` so V2's trap GDD can find these doors and plug in real trap effects. The fallback behavior: the door acts as a Locked door (requires a matching key OR bash if wooden). Key placement follows §10.3. See §10.5.
6. **Treasure resolved end-to-end:** every treasure type drawn during stocking is rolled out into specific coins, gems, jewelry, and magic items at generation time. No deferred-resolution tags. Magic item placeholders are emitted only when the magic item catalog itself has a gap (§13.4).
7. **Key/lever placement is cross-floor:** for any locked indestructible door or portcullis, the key (or wired lever) must land in a room reachable from the dungeon entrance **without crossing the door it opens**, regardless of which floor that room is on. See §10.
8. **Lair coalescing is OFF (RAW deviation, §2).** Each rolled monster group is its own independent lair. Future faction system uses these as competing/allied same-race factions.
9. ~~**Stair placement is constraint-aware, not retry-and-scoot.** The layout generator must accept stair anchor points (the position of the prior floor's stair-down) and produce a layout that places a stair-up at that exact position on the first attempt.~~ **Superseded 2026-07-06:** stair *anchors* are gone entirely — the vertical plan reserves whole stairwell footprints (real stepped geometry spanning both bands) before any band lays out, per `gdd-dungeon-contiguous-3d.md` §6/§8. The underlying principle — robustness by construction over retries — carries forward unchanged.
10. **Door material distribution from layout GDD §8.3.** V1 consumes the door material rule defined as a companion edit to the layout GDD: default `wood_standard`, with a 5%-per-tier chance of metal (iron or stone, 50/50) and a separate 5%-per-tier chance of portcullis override. See §10.1.
11. **Rules XML is never read at runtime.** All ACKS tables consumed by the generator are encoded at build time into `data/dungeon_generator/*.json`, with a build-time extraction script and a diff-test that fails CI if the encoded data drifts from the XML. See §12.
12. **Wizard's Dungeon as universal fallback** until V2 adds more types: this means the V1 generator IS the generator for every dungeon on the campaign map at first playable build, and downstream systems (POI generator, region zoom-in pipeline, save/load) must treat the Wizard's Dungeon as the canonical default.

---

## 4. Input and Output

### 4.1 Generator Input

```
DungeonGeneratorRequestV1:
  # Required
  entrance_tier: int          # 1..6, the ACKS dungeon-level of the entrance floor
  floor_count: int            # >= 1
  entrance_floor_index: int   # 1..floor_count; which floor the dungeon entrance is on

  # Optional, with defaults
  dungeon_type: string = "wizards_dungeon"   # Anything else → fallback + warning
  dungeon_size: string = "medium"            # lair / small / medium / large (per gdd-dungeon-layout.md §3)
  seed: int = <random>                       # For reproducibility

  # Optional regional context (passed through to LLM later; V1 just stores it)
  region_id: string = null
  hex_coords: Vector2i = null
```

The caller is the POI generator or the region zoom-in pipeline (per `gdd-dungeon-layout.md` §12.1). V1 does not call itself recursively; multi-floor generation is one request producing one multi-floor `DungeonLayout`.

### 4.2 Generator Output — Schema Extensions

V1 emits the existing `DungeonLayout` data structure from `gdd-dungeon-layout.md` §11, **per floor**, plus the following additions:

```
DungeonLayout (V1 additions):
  # Floor-level identifiers
  floor_index: int                # 1..floor_count
  floor_tier: int                 # The derived dungeon level (1..6) for this floor
  is_entrance_floor: bool

  # Floor-level summary
  total_monster_xp: int           # Sum of all monster XP placed on this floor
  total_treasure_gp_value: int    # Sum of coin/gem/jewelry/magic item GP value
  xp_to_gp_ratio: float           # total_treasure_gp_value / total_monster_xp; target 4.0
  encounter_table_row: int        # The dungeon-level row from dungeon_wandering_monster_level
                                  #   used both for stocking AND for runtime wandering checks
                                  # NOTE (§15): vestigial once overstocking+patrols+respawn lands.

RoomData (V1 additions; the existing `contents: null` is replaced):
  # 2026-07-06: these stocking-result fields MOVE to RoomZone per
  # gdd-dungeon-contiguous-3d.md §9 (schema approved). A single-zone room's
  # sole zone carries them; RoomData keeps a current_purpose rollup for the LLM.
  contents_kind: string           # "empty" | "monster" | "monster_lair"
                                  #   | "trap_placeholder"    (V2 trap GDD plugs in here)
                                  #   | "unique_placeholder"  (V2 unique system plugs in here)
  monster_group_id: string | null # FK to a MonsterGroup record
                                  # NOTE: trap_placeholder rooms have null;
                                  # unique_placeholder rooms have a re-rolled monster group as fallback
  treasure_hoard_id: string | null # FK to a TreasureHoard record
  current_purpose: string         # Set by stocking; fills the slot left null by the layout GDD §6.3

DoorData (V1 additions):
  required_key_id: string | null  # FK to a KeyItem
  wired_lever_position: Vector3i | null  # For portcullises, the cell containing the actuating lever
  is_secret: bool                 # OVERLAY flag.
                                  # Orthogonal to `type`. A door can have type="locked" AND is_secret=true
                                  # (the trap-room fallback in §11.4 sets this combination).
                                  # Runtime behavior: secret doors are blocked from BFS until detected;
                                  # detection is via Search check at runtime. Once detected, is_secret
                                  # remains true for data continuity but door_detected flips true.
                                  # Now lives in the layout GDD §11 DoorData schema (companion edit
                                  # 2026-05-27). The §8.1 "Secret door: 10%" type roll now produces
                                  # underlying_type + is_secret=true instead of type="secret".

# New record types
MonsterGroup:
  group_id: string
  room_id: int                    # The room this group occupies (each group is its OWN lair; no coalescing)
  zone_index: int                 # ADDED 2026-07-06: which zone of the room (0 for single-zone rooms)
  floor_index: int
  monster_name: string            # ACKS catalog name, e.g., "Goblin"
  monster_xp_each: int            # From catalog (copied at generation time per §12.3 — no runtime catalog reads)
  number_appearing: int           # After all adjustments (cross-tier ±0.5×, lair leaders, etc.)
  hd: string                      # Catalog HD string, e.g., "1-1", "2*", "8+3"
  associated_creatures: Array     # [{monster_name, number, role}]; leaders/champions/young per catalog
  is_lair: bool                   # True if this group passed its % In Lair check (per-group, not per-dungeon)
  morale: int                     # Copied from catalog
  alignment: string               # Copied from catalog
  treasure_type_letter: string | null  # Catalog's listed treasure type if this group is in lair
  initial_inventory: Array        # Items each member carries, including any KeyItems wired here

TreasureHoard:
  hoard_id: string
  source: string                  # "lair" | "unprotected_empty" | "unprotected_trap_placeholder"
                                  #   | "unprotected_unique_placeholder"
  treasure_type_letter: string | null
  copper: int                     # Actual coin counts (post the 1d4 × 1000 etc. rolls)
  silver: int
  electrum: int
  gold: int
  platinum: int
  gems: Array                     # [{value_gp, gem_class}]; gem_class ∈ ornamental/gem/brilliant
  jewelry: Array                  # [{value_gp, jewelry_class}]; class ∈ trinket/jewelry/regalia
  magic_items: Array              # [{category, specific_item_id_or_placeholder}]
  total_gp_value: int             # Computed after rolling; cached for XP-balance reporting
  is_hidden: bool                 # True for unprotected_* hoards (per RAW: hidden by default)

KeyItem:
  key_id: string
  opens_door_position: Vector3i   # The DoorData this key opens
  opens_door_floor: int           # Floor index of the door
  placed_in: string               # "monster_group_inventory" | "treasure_hoard" | "loose_in_room"
  placed_in_room_id: int
  placed_in_zone_index: int       # ADDED 2026-07-06: zone within the room (0 for single-zone rooms)
  placed_on_floor: int
```

All of the above persist to SQLite via the dungeon repository. Tables: `dungeon_floors`, `dungeon_rooms`, `dungeon_doors`, `monster_groups`, `treasure_hoards`, `key_items`. Schema migration owns those tables; existing CellData, RoomData, DoorData, StairData persistence from the layout GDD remains the same with the additions above.

---

## 5. Pipeline Overview

> **SUPERSEDED IN PART (2026-07-06).** The multi-floor choreography below (step 3's per-floor loop with `required_stair_positions`, entrance-first radiate-outward order) is replaced by the staged pipeline in [`gdd-dungeon-contiguous-3d.md`](gdd-dungeon-contiguous-3d.md) §8: vertical plan → per-band layout (any order, reservations pre-placed) → vertical composition → keys/levers → stocking → acceptance. Steps 1-2 (input validation, tier derivation) and the *logic* of steps 4-9 (key/lever fixpoint, per-unit d100 stocking, treasure resolution, acceptance) survive intact — with "floor" → "band" and "room" → "zone" substitutions per that GDD's §5/§11. The text below is retained as the authoritative specification of those surviving steps.

```
1. VALIDATE INPUT
   - Clamp entrance_tier into 1..6.
   - Floor count >= 1; entrance_floor_index in 1..floor_count.
   - If dungeon_type unknown or null → "wizards_dungeon" + warning.
   - Seed the RNG.
2. DERIVE PER-FLOOR TIERS
   - For floor i in 1..floor_count: tier[i] = clamp(entrance_tier + |i - entrance_floor_index|, 1, 6).
3. GENERATE EACH FLOOR (loop over floors in order: entrance floor first, then radiate outward)
   3.1 LAYOUT (CONSTRAINT-AWARE): call layout generator with (dungeon_type, dungeon_size, seed_for_floor,
       required_stair_positions). For the entrance floor, required_stair_positions = []. For all
       other floors, required_stair_positions includes the prior-generated adjacent floor's matching
       stair position. See §8.1.
   3.2 APPLY DOOR MATERIAL RULE (per layout GDD §8.3 and §10.1 below): for each door from the layout,
       roll material/portcullis override per the tier-scaled rule.
   3.3 LAYOUT NAVIGABILITY: BFS from entrance/stair cells with all doors treated as passable.
       Every passable cell with room_id must be reachable. Retry layout up to N=3 times if not; if
       all retries fail, fall back to post-hoc connectivity carving (§9.1).
4. CROSS-FLOOR DOOR/KEY/LEVER PLACEMENT
   - Collect every locked door (any material) and portcullis across all floors.
   - For each, compute the "outside region" (cells reachable from the entrance with that door blocked).
   - Place the matching key (locked door) or wired lever (portcullis) somewhere in the outside region.
   - If no outside region exists for a given door (door is on the entrance path):
     downgrade per §10.4.
5. STOCK EACH FLOOR (loop over floors)
   5.1 d100 PER ROOM per dungeon_stocking table.
   5.2 EMPTY (01-30): contents_kind = "empty"; 15% chance of unprotected treasure.
   5.3 MONSTER (31-60): rolls per §11.3; % In Lair check per group; no coalescing (§11.7).
   5.4 TRAP (61-75): contents_kind = "trap_placeholder"; ONE bordering door is upgraded
       to is_secret=true AND (if not already locked) type="locked" (§11.4). 30% treasure.
   5.5 UNIQUE (76-00): contents_kind = "unique_placeholder"; re-roll on the §11.3 monster
       procedure and place the resulting MonsterGroup in this room as fallback content (§11.5).
       Treasure follows lair rules (treasure if % In Lair).
6. RESOLVE TREASURE
   6.1 Lair rooms → roll the monster's treasure type per acore_treasure_and_magic_items_rules.xml.
   6.2 Empty + Trap-placeholder + Unique-placeholder with treasure → unprotected_treasure[tier, 1d6].
   6.3 Materialize every coin, gem, jewelry, magic item.
7. PLACE KEYS INTO STOCKING
   - Each KeyItem from step 4 must end up in (a) a monster's inventory, (b) a treasure hoard, or
     (c) loose in the floor of its assigned room.
   - Preference order: monster inventory if a monster is in the assigned room; else treasure hoard
     if one is in the room; else loose-in-room.
   - If the assigned room ended up Empty with no treasure, force a treasure hoard of type A onto it
     so the key has a home (and the hoard contains the key).
8. FINAL ACCEPTANCE TESTS (§14)
   - Re-run global navigability: BFS from entrance cell with doors in initial state. Every locked
     door must have a reachable key. Every portcullis must have a reachable lever or be forceable.
     The entrance must reach every stair on every floor (with doors in initial state).
   - Trap_placeholder validation: every such room has its fallback Locked+Secret door.
   - Unique_placeholder validation: every such room has its fallback MonsterGroup.
   - XP/GP ratio logged.
9. EMIT DungeonLayout per floor + cross-floor metadata + KeyItem ledger.
```

---

## 6. Tier Derivation

The user-specified rule: "entrance floor is easiest tier, each floor +/- 1 from entrance floor is +1 difficulty tier."

Formula:

```
for floor_index in 1..floor_count:
    floor_tier[floor_index] = clamp(
        entrance_tier + abs(floor_index - entrance_floor_index),
        1, 6
    )
```

Worked examples:

| floor_count | entrance_floor_index | entrance_tier | Per-floor tiers (floor 1 → floor N) |
|---|---|---|---|
| 1 | 1 | 1 | [1] |
| 3 | 1 | 1 | [1, 2, 3] |
| 3 | 2 | 2 | [3, 2, 3] |
| 5 | 1 | 1 | [1, 2, 3, 4, 5] |
| 5 | 3 | 2 | [4, 3, 2, 3, 4] |
| 6 | 1 | 1 | [1, 2, 3, 4, 5, 6] |
| 6 | 1 | 3 | [3, 4, 5, 6, 6, 6] (clamped) |

The clamp at 6 means a deep dungeon with a high entrance tier collapses its deeper floors to the maximum ACKS dungeon level (6). The generator logs a warning when clamping happens so the caller can flag the seed as outside the supported envelope. The clamp at 1 is in place defensively; it never fires given the input constraints.

**Above-ground structures** (Tower, Crumbling Castle, Cliff City, Ruined Manor from `gdd-dungeon-layout.md` §5.2): the entrance is the ground floor (index 1), and "deeper" floors are upward in space. The tier formula doesn't care about direction — distance from the entrance floor is what matters. For Wizard's Dungeon (the V1 type, classified subterranean per the layout GDD's structure_type), the entrance defaults to floor 1 and floors descend.

---

## 7. Dungeon Type for V1 — Wizard's Dungeon as Universal Fallback

Per Jedidiah's direction, V1 uses **Wizard's Dungeon** as the dungeon type for every generated dungeon, regardless of what the caller passes. The flavor is re-cast: a Wizard's Dungeon is a generic dungeon **deliberately built by a wizard to attract monsters for harvesting their magical components and to lure (hopefully wealthy) adventurers to their deaths**. It is not a tower, not a magical laboratory, not themed around any specific monster category. It is the "everything dungeon" — the procedural fallback that supplies dungeons on the campaign map until V2 adds bespoke types.

### 7.1 Fallback rule

```
if dungeon_type is null OR dungeon_type not in known_dungeon_types:
    log_warning("Unknown dungeon_type '%s'; falling back to wizards_dungeon" % dungeon_type)
    dungeon_type = "wizards_dungeon"
```

This is the V1 universal contract. Downstream systems (POI generator, save/load, region zoom-in) can pass any string they want; they will get a Wizard's Dungeon back until V2.

### 7.2 Encounter table source

V1 uses the **encoded Random Monsters by Level table** (extracted from `rules/acore-monster-stocking-rules.xml:112-136` at build time per §12), indexed by `floor_tier`. The Dungeon Wandering Monster Level table (`rules/acore-monster-stocking-rules.xml:76-94`) handles cross-tier variety automatically (a tier-3 floor has a 1/12 chance of rolling on the tier-1 monsters table, a 2/12 chance of tier-2, 6/12 of tier-3, 2/12 of tier-4, 1/12 of tier-5). No project-designed encounter table is needed for V1.

### 7.3 Companion edit to `gdd-dungeon-layout.md` §5.2 — APPLIED

The companion edit re-flavoring Wizard's Dungeon in `gdd-dungeon-layout.md` §5.2 (drop the `construct, arcane, aberration, fiend` tag list; add §5.3 note that Wizard's Dungeon uses raw Random Monsters by Level) has been applied alongside this draft.

### 7.4 Theme parameters used from §5.2

V1 consumes the rest of the Wizard's Dungeon theme row from `gdd-dungeon-layout.md` §5.2: room bias = mixed, corridors = bent, dead-end removal = 60%, loop frequency = 0.3, room shape = mixed, corridor width = standard. The door-type weights from §8.2 of the layout GDD for Wizard's Dungeon (Arch 10%, Unlocked 20%, Locked 20%, Trapped 20%, Secret 20%, Portcullis 10%) are also used as-is. Door material and tier-scaled portcullis overrides apply per the new layout GDD §8.3 (companion edit, see below).

### 7.5 Companion edit to `gdd-dungeon-layout.md` §8 — APPLIED

The companion edit adding §8.3 "Door Material Distribution" to `gdd-dungeon-layout.md` has been applied alongside this draft. The rule, summarized: after the §8.1 type roll, for each non-arch and non-portcullis door, roll d100 — on ≤ `5 × floor_tier`, override type to Portcullis. Otherwise, roll d100 again — on ≤ `5 × floor_tier`, set `door_material` to iron (50%) or stone (50%); else `door_material = wood_standard`. See the layout GDD §8.3 for the full procedure and worked tier-by-tier expectations.

---

## 8. Layout Generation

V1 delegates entirely to the layout generator from `gdd-dungeon-layout.md`. There is no V1-specific layout algorithm. V1 passes the request through and receives back the DungeonLayout cells/rooms/doors/stairs per layout GDD §11.

### 8.1 Constraint-aware stair placement — SUPERSEDED 2026-07-06

> **Superseded by `gdd-dungeon-contiguous-3d.md` §8.** There are no stair anchors, no same-(col,row) pairing, and no sequential floor generation order anymore. The vertical plan reserves stairwell footprints (as circulation rooms spanning both bands, with horizontally offset entry/exit landings) before any band's layout runs; the composition stage carves the stepped geometry. The post-hoc carving safety net below is retired with it — floor-integrity and stair-geometry acceptance checks (`gdd-dungeon-contiguous-3d.md` §10.2) replace it, and the whole-dungeon re-seed ladder (§9.2 below) remains the outer safety net. Retained for historical context:

Per user direction #9, robustness is preferred over post-hoc retries. The layout generator is called with an explicit `required_stair_positions` parameter:

```
required_stair_positions: Array[StairAnchor]
StairAnchor:
  position: Vector2i      # The exact grid cell where a stair must appear
  direction: string       # "up" or "down"
```

For the entrance floor: `required_stair_positions = []` (free placement). The layout generator places stairs per its §9.1 procedure and one of them is designated `is_entrance_stair = true` (for the entrance floor only; this is the dungeon's connection to the surface).

For each subsequent floor (radiating outward from the entrance floor in BFS order): for each adjacent already-generated floor, look up its stair-toward-this-floor position and pass it as a StairAnchor with the opposite direction. Example: if floor 1 has a stair-down at (15, 22), then floor 2 is generated with `required_stair_positions = [{position: (15, 22), direction: "up"}]`. The layout generator MUST honor the anchor: the cell at (15, 22) on floor 2 is forced to be a stair-up, and the room/corridor network is built around it.

**Layout-GDD dependency — RESOLVED 2026-05-27:** `gdd-dungeon-layout.md` §9.3 "Constrained Stair Placement" now defines the `required_stair_positions` parameter and the layout generator's procedure for honoring it (companion edit landed alongside this draft). V1 calls the layout generator with the anchors directly. The §9.3 procedure is structural — anchor cells are reserved in the bitmask grid before room placement, so the layout cannot produce a layout that fails the anchor constraint. Connectivity is guaranteed by the maze carver plus a fallback direct-corridor carve if any anchor is unreachable after carving.

**Post-hoc carving retained as catastrophic-failure safety net only.** If the layout generator returns an output that violates an anchor (a regression in the layout code, an invalid anchor set the generator failed to reject, or some other broken contract), V1 falls back to the post-hoc procedure: set target cell to `stairs_up` / `stairs_down`, carve a 2-cell-wide corridor to the nearest open cell, re-run §9.1 BFS. This is not the expected code path; if it ever fires, log loudly and treat it as a layout-generator bug to investigate.

### 8.2 What V1 explicitly does NOT do at layout time

- **No theme-tag-based encounter table construction** (deferred to V2 per §7.3).
- **No faction generation** (`gdd-dungeon-factions.md` remains unimplemented for V1).
- **No LLM narrative pass on rooms** (the room `original_purpose` from layout GDD §6.3 is generated; `current_purpose` is set by V1 stocking per §11.6 below; LLM descriptions come later).
- **No trap object instances** in cells (door type "Trapped" is encoded but inert — see §10.5; room result "Trap" is encoded as trap_placeholder with a Locked+Secret door fallback — see §11.4).

---

## 9. Navigability Validation

> **Graph substrate updated 2026-07-06.** Both passes now run on the real 3D movement graph of the composed volume (support rule + ±1-level steps via stair/ramp/spiral features + door passability) per `gdd-dungeon-contiguous-3d.md` §10 — per-floor BFS with stair-teleport edges is gone. The two-pass structure, the fixed-point key/lever model, all acceptance criteria (restated over zones), and the three-level retry/re-seed recovery ladder below are unchanged.

Two passes, both BFS.

### 9.1 Layout navigability (pre-key-placement)

After layout generation for each floor, run BFS from the floor's entrance cell (for the entrance floor) or from each stair cell (for non-entrance floors), treating every door cell as **passable regardless of type or state**. Every passable cell with a `room_id` must be reachable. If any room is unreachable, the layout is invalid; retry up to 3 times before applying post-hoc carving: identify the disconnected room(s) and carve a 2-cell-wide corridor from each one to the nearest reachable corridor/room. Re-run BFS to confirm. If the post-hoc carving still leaves anything unreachable (this is essentially impossible given the algorithm), abort generation and log the seed as ungenerable.

**Status (2026-06-10):** the post-hoc carving is implemented as `DungeonGeneratorV1._carve_unreachable_rooms` — an L-shaped 2-cell-wide carve from each disconnected room to the nearest reachable cell, looped until the floor is connected (bounded by room count). It runs only after the 3 layout retries fail, replacing the earlier warn-and-continue behavior that shipped structurally disconnected floors no downstream retry could repair.

This is a structural check: it confirms the layout's connectivity graph is sound before the key/lever puzzle layer is applied.

### 9.2 Solvability navigability (post-key-placement and stocking)

After stocking and key/lever placement (§10), run BFS from the dungeon entrance cell across all floors, treating doors in their **initial generated state**:

- Open archways: passable.
- Unlocked closed doors: passable (player can open them with no prerequisite).
- Locked doors: blocked **unless** the player's reachable region contains the matching KeyItem.
- Trapped doors (V1): treat as Locked (per §10.5 fallback — runtime behavior is Locked, key required or bash if wooden).
- Secret doors (including `is_secret = true` overlay on a Locked door, per §11.4): blocked initially. BFS treats them as blocked for the conservative reachability test; runtime detection is via Search.
- Portcullises: blocked unless the player's reachable region contains the wired lever cell, OR the design accepts that the player can Force Portcullis (always available per `gdd-dungeon-map-ui.md` §4.2.1 — STR throw 18+).
- Stairs: passable; crossing a stair adds the destination floor's stair-cell to the BFS frontier.

The algorithm is a fixed-point iteration: BFS expands the reachable region; if a new key/lever cell is reached, the corresponding door is unlocked and BFS continues. Iterate until no new cells are reached.

**Acceptance criteria for the global solvability pass:**

1. Every stair on every floor is reachable.
2. Every locked door (including Locked+Secret combinations) has its key in the reachable region.
3. Every portcullis has its lever in the reachable region OR is forceable.
4. Every MonsterGroup's room is reachable.
5. (Soft) Every treasure hoard is reachable. Hidden treasure that's only reachable by passing a secret door is acceptable — the generator logs a count of "secret-gated treasure" per floor so playtesters can monitor whether too much wealth is being hidden behind detection rolls.

If any hard criterion fails, recovery happens at three escalating levels (all implemented 2026-05-28): (1) the per-floor layout retry / post-hoc carving (§9.1); (2) the stocking-seed retry, which re-rolls room contents (it cannot fix a *layout*-generated door, e.g. a locked-stone / portcullis / secret door isolating a floor's entry antechamber); and (3) a **top-level whole-dungeon re-seed** — `DungeonGeneratorV1.generate` runs up to 4 attempts, each `_generate_attempt` deriving an independent master seed, so a layout-door dead-end on one attempt is replaced by a fresh, independent layout on the next. Attempt 0 reuses the request seed verbatim, so a fixed request reproduces its prior result whenever that was already solvable. A multi-seed stress sweep (80 dungeons, tiers 1-4, 1-4 floors) reaches 100% solvable with this in place; only if all top-level attempts fail is the seed returned with `success = false` and the failures logged.

(Two robustness fixes feed this: free-placed stairs are constrained to the anchorable interior `[2, grid-3]` so a down-stair always becomes a valid next-floor anchor — §9.3; and the pre-stocking connectivity guard seeds its BFS from a **single** stair so a disconnected entry antechamber is detected rather than masked by per-stair seeding.)

---

## 10. Door Key and Lever Placement

This is the most novel V1 system. It runs AFTER all layouts are generated (so it can see all floors simultaneously) and BEFORE stocking begins (so stocking can place keys into monster inventories or treasure hoards).

### 10.1 Door inventory

Door material and type are determined by the layout GDD §8 + the new §8.3 material rule (companion edit). V1 walks every floor and collects:

- `LockedDoor` — a DoorData with `type ∈ {locked, trapped}` and `door_material ∈ {iron, stone}`.
- `PortcullisDoor` — a DoorData with `type = "portcullis"`.

Wooden locked doors are not in this list: per `gdd-dungeon-map-ui.md` §4.2.1, any wooden door can be bashed by a party member carrying an axe (1 turn). Wooden locked doors do not need keys placed (though §10.6 may still place one in stocking if a natural opportunity arises). They have `door_state = "locked"` initially; the player can either find a matching key (if rolled in stocking inventory) or bash.

Locked+Secret doors created by §11.4's trap-placeholder fallback are processed the same way, with one refinement (implemented; supersedes the original "is_secret does not affect key placement" wording): a secret Locked/Trapped door **always** receives a key regardless of material. The §9.2 solvability model blocks on `is_secret` even for wood (the player must Search before bashing is an option), so a keyless secret wood door would read as permanently blocking; the key guarantees the fixed-point BFS can resolve it (Search, then key).

### 10.2 Key/lever region — discovery-order placement (rev 2026-06-10)

**Superseded approach (pre-2026-06-10):** a per-door "outside region" BFS that blocked only the door in question and treated **all other locked doors as passable**. That model had a correctness hole — key A could be placed behind locked door B while key B sat behind door A (a circular dependency the §9.2 fixed-point BFS correctly rejects but placement could not avoid; observed in ~15-20% of multi-floor attempts, where it burned the full stocking/dungeon retry budget) — and a cost problem (one multi-floor BFS **per gated door** was ~90% of total generation CPU; worst observed: 47 s for a 6-floor medium dungeon).

**Current approach:** one multi-floor fixpoint BFS from the dungeon entrance, using the **same door-passability model as §9.2 solvability**. When the frontier reaches a gated door (Locked/Trapped iron-stone, any secret Locked/Trapped, or a Portcullis), its key/lever is placed immediately in a room that is **already fully discovered**, the door becomes passable, and the BFS continues. Because every key/lever lands in a region provably reachable before its door opens, the placement graph is a dependency DAG by construction — circular key dependencies are impossible, and the §9.2 acceptance pass succeeds for the door layer on the first attempt. Cost is one BFS total (measured: 1745 ms → 45 ms on the 3-floor-medium reference seed).

Two repair rules ride on the same pass:

- A gated door reached before **any** room has been fully discovered sits on the sole entrance path — the §10.4 downgrade applies (first such door only; the BFS then re-drains, since the opened door may reveal candidate rooms for the rest).
- If the fixpoint completes with a stair or room still unreached, and a frontier **secret+unlocked** door is what blocks it (such doors carry no key and are model-impassable), that door's `is_secret` flag is cleared — §10.4's philosophy applied to the one door class the key system cannot otherwise resolve. Secret doors guarding pockets the BFS reached another way are never touched, so optional secret content survives.

### 10.3 Key/lever room selection

For each gated door, when the frontier reaches it:

1. Enumerate rooms whose cells have all been discovered (i.e., rooms fully reachable without the door — the discovery-order equivalent of "entirely within the outside region").
2. Filter out the dungeon entrance room (keys/levers in the entrance room would be too obvious).
3. Weight remaining rooms by floor — prefer placing the key on the same floor as the door (weight 5), then on an adjacent floor (weight 2), then on a more distant floor (weight 1).
4. Randomly select one room from the weighted candidates.
5. For locked doors: create a `KeyItem` with `opens_door_position`/`opens_door_floor` set to the door, and `placed_in_room_id`/`placed_on_floor` set to the chosen room. The actual placement-within-room (which monster's inventory, which hoard, or loose) is decided in pipeline step 7 (§5), after stocking has run.
6. For portcullises: pick a wall-adjacent cell in the chosen room (any cell directly adjacent to an impassable wall cell), record it in the DoorData's `wired_lever_position`. The cell is set to `terrain_feature = "lever_portcullis_<door_position>"` at cell finalization time. The runtime resolves the lever wiring via the matching string in the terrain_feature.

### 10.4 The "no outside region" case

A door may have no outside region — meaning the door is on the only path from the entrance to anywhere else. This is a generator pathology, but V1 handles it gracefully:

- For locked iron/stone doors with no outside region: downgrade `door_material` to `wood_standard`. The door remains locked but is now bashable. No key is placed. Log: "Downgraded indestructible locked door at {pos} to wood — no reachable outside region."
- For portcullises with no outside region: downgrade `type` to `unlocked` (a regular closed door) with `door_material = wood_standard`. No lever is placed. Log: "Downgraded portcullis at {pos} to wooden door — no reachable outside region."

This guarantees solvability by construction: every locked indestructible door has either a placed key in a reachable region OR has been downgraded to wood (and is therefore bashable). Every portcullis has either a lever in a reachable region OR is forceable via Force Portcullis. The §9.2 acceptance test will pass for any generated dungeon.

### 10.5 Trapped doors in V1

Per Jedidiah's encode-and-fallback philosophy (decision #3 in §3, applied also to doors as decision #5):

- Door type stays as `"trapped"` (so V2's trap GDD can find these doors).
- `door_state` is initialized to `"locked"` (V1 runtime fallback: trapped doors behave as Locked).
- Door material is rolled per layout GDD §8.3 (so the same 5%-per-tier metal chance applies).
- If material is iron/stone: door enters the LockedDoor list (§10.1) and gets a key placed per §10.3.
- If material is wood: door is bash-able (no key required, though one may still be placed by stocking if a monster inventory call lands a matching key).
- No trap_id is attached; the runtime, finding `type = "trapped"` with no trap definition, treats it as a plain Locked door of the appropriate material.

The build log entry for V1 should track how many trapped doors are emitted per dungeon so V2 can audit when the trap GDD wires real effects in.

---

## 11. Room Stocking

> **Stocking unit updated 2026-07-06: rooms → zones.** Per [`gdd-dungeon-contiguous-3d.md`](gdd-dungeon-contiguous-3d.md) §11, the d100 loop iterates the **zones** of chamber-kind rooms (a zone = a room's walkable region on one band; single-zone rooms behave byte-for-byte as before). Each zone stocks at **its own band's tier**. `kind: "circulation"` rooms (stairwells) are excluded exactly as stair/lever rooms are below. This is the RAW-faithful reading of "roll once for each room on each dungeon level" (`rules/acore-setting-construction-rules.xml:621-642`) — a multi-story room is stocked on each dungeon level where it presents walkable space. Every procedure in this section applies per zone; the text below retains "room" wording for the common single-zone case.

Stocking happens per floor, AFTER layout and key/lever placement.

### 11.1 The d100 roll per room

For every room on the floor (skipping rooms that are entirely corridor / stair / lever cells), roll d100 once and consult `dungeon_stocking` (encoded per §12 from `rules/acore-setting-construction-rules.xml:629-641`):

| d100 | Contents | Treasure |
|---|---|---|
| 01–30 | Empty | 15% |
| 31–60 | Monster | If Lair |
| 61–75 | Trap | 30% |
| 76–00 | Unique | As Needed |

### 11.2 Empty rooms

`contents_kind = "empty"`. Roll d100: on 1–15, the room has unprotected treasure (§13.2). Otherwise the room has nothing. The room's `current_purpose` is set per §11.6.

### 11.3 Monster rooms — the cascaded roll procedure

Cascading rolls per `rules/acore-monster-stocking-rules.xml:35-46` (encoded per §12):

1. Roll 1d12 on the `dungeon_wandering_monster_level` row matching this floor's `floor_tier`. Identify which monster-level table column to consult (1..6).
2. Roll 1d12 on the `random_monsters_by_level` table, that column. Read off the monster name and base number-appearing dice (e.g., "Goblin (2d4)").
3. Roll the number-appearing dice.
4. If the picked monster-level differs from the floor's tier, multiply the rolled number by `0.5 ^ |tier_diff|` for higher-table picks (deeper monster, fewer of them) or `2.0 ^ |tier_diff|` for lower-table picks (shallower monster, more of them). Round **down** per the RAW rule (`rules/acore-monster-stocking-rules.xml:42-46`; convention exception recorded in `docs/coding_conventions.md` §3.3).
5. Consult the encoded monster catalog (§12) for the monster's `% In Lair` and HD. Roll `% In Lair` for **this specific group** (no coalescing — see §11.7).
6. If in lair: `contents_kind = "monster_lair"`, treasure_type letter taken from monster entry, MonsterGroup placed in this room.
7. If not in lair: `contents_kind = "monster"`, no treasure here from this group.
8. NPC Party result (the 12 column in each row of `random_monsters_by_level`) — generate per `rules/acore-monster-stocking-rules.xml:446-558`, `npc_parties` procedure. V1 uses `base_level = floor_tier`'s indicated party_level from the wandering_monster_table_guidelines (tier 1 → 1, tier 2 → 2, tier 3 → 4, tier 4 → 6, tier 5 → 8, tier 6 → 10 — picking the lower end of each range for determinism per §16). Equipment, mounts, treasure, magic items all rolled per the NPC Parties procedure.

### 11.4 Trap rooms (61–75) — placeholder + fallback

Per user direction #3:

- `contents_kind = "trap_placeholder"`. The V2 trap GDD identifies these rooms by this kind and plugs in real trap content.
- **Fallback challenge:** ensure the room is gated by a Locked+Secret door. If the room *already* borders a qualifying `is_secret` + `locked`/`trapped` door (e.g. one the §8.1 secret roll produced, or one an adjacent trap room marked on a shared door), reuse it and add nothing (this keeps the §14.1.6 target of one gate). Otherwise select one bordering door — preferring one whose upgrade will not give a neighbouring trap room a second qualifying door — and apply both modifications:
  - Set `is_secret = true` (the new overlay flag from §4.2).
  - If the door's current `type` is not `"locked"` and not `"trapped"`, override to `type = "locked"` (the door must visibly be a barrier). If the door is already `"locked"` or `"trapped"`, retain its type and just set `is_secret = true`.
  - Roll material per layout GDD §8.3 (already done in pipeline step 3.2, but if the existing material is wood and the door is now Locked+Secret, leave it wood — secret doors disguised as walls are typically wood/plaster construction anyway; this gives the player a bash path).
- Place a key per §10.3 IF the door material rolled iron/stone (key required since indestructible).
- Treasure chance **30%**, rolled per §13.2 on unprotected_treasure[tier].
- `current_purpose` set per §11.6.

The room is now playable: the player finds (Search) the secret door, deals with the lock (key or bash), enters the room, and finds treasure. When V2 lands, the trap GDD plugs in the real trap content into this room and the Locked+Secret door becomes superfluous (V2 can choose to keep or remove the door modification per its own rules).

### 11.5 Unique rooms (76–00) — placeholder + monster fallback

Per user direction #4:

- `contents_kind = "unique_placeholder"`. The V2 unique-encounter system identifies these rooms by this kind.
- **Fallback content:** run the §11.3 Monster procedure for this room. The result is a MonsterGroup placed in this room with `is_lair` determined per `% In Lair`. Treasure follows lair rules (treasure if the group is in lair, none otherwise).
- `current_purpose` set per §11.6.

The room is now playable: it contains a monster (perhaps a lair monster with treasure). When V2 lands, the unique system can either replace the monster with a real unique encounter, or layer the unique content on top of the existing monster (e.g., the monster is now the puzzle's guardian).

### 11.6 Current purpose assignment

The layout GDD §6.3 already sets each room's `original_purpose`. V1 stocking sets `current_purpose` per the following table:

| Stocking result | current_purpose |
|---|---|
| Empty (no treasure) | Same as `original_purpose` |
| Empty (with treasure) | `original_purpose` + " (with cached valuables)" |
| Monster (not in lair) | "patrol / temporary occupation by {monster_name}" |
| Monster (in lair) | "{monster_name} lair" |
| Trap-placeholder | "trap chamber (deferred — Locked+Secret door fallback active)" |
| Unique-placeholder + monster-fallback (not in lair) | "unique feature (deferred) — patrol by {monster_name}" |
| Unique-placeholder + monster-fallback (in lair) | "unique feature (deferred) — {monster_name} lair fallback" |

This is purely an audit + later-LLM-prompting hook. It does not affect rendering or mechanics.

### 11.7 NO lair coalescing — V1 RAW deviation

Per user direction #8 and §2 deviation flag: V1 does NOT coalesce multi-group organized monster rolls into a single lair-with-guard-posts.

**Algorithm:**
- After every monster roll for the floor (across §11.3, §11.5 fallback), each MonsterGroup stands alone.
- Each MonsterGroup independently rolls its `% In Lair` per the monster catalog.
- If a roll passes, that MonsterGroup is its own lair with its own treasure type rolled per §13.1.
- If multiple Goblin groups are rolled on the same floor (or across the dungeon), each is its own goblin lair with its own treasure.
- No `guard_post_room_ids`. No `lair_room_id` cross-reference. Each MonsterGroup.room_id IS its lair room.

**Rationale:** when the faction system lands (`gdd-dungeon-factions.md` is currently unimplemented), V1's separate lairs become candidate factions of the same race. The faction system can model competing goblin tribes, allied warring chieftains, breakaway splinter cells — possibilities that RAW's "one big goblin lair with guard posts" would foreclose.

**Audit note for V2:** when the faction system lands, it will need to look at the V1-emitted MonsterGroup list per dungeon and decide which same-race groups are competing factions vs. allied factions vs. coalesced lairs (post-faction-system, RAW-style coalescing may still be desirable as one possible faction-graph topology). V1 emits the raw groups; V2 owns the topology decision.

### 11.8 Placement heuristics

After all rolls, the generator may swap monster assignments between rooms to honor `rules/acore-setting-construction-rules.xml:659-663` placement_rules. V1 implements a single heuristic:

- If any group with HD < floor_tier rolled into a room far from a stair, AND there is an unassigned-monster room near a stair, swap them. This honors "lower-level monsters can be placed near inter-level connections as guards."

More sophisticated placement is a V2 concern.

---

## 12. Runtime Data Encoding (XML → JSON at Build Time)

**Hard rule (user direction #11):** the generator NEVER reads `rules/*.xml` at runtime. Ever. All rule tables consumed by the V1 generator are extracted from the sacred XML at **build time** and stored as runtime data files.

### 12.1 Encoding location

Per `docs/coding_conventions.md` §2 file organization, runtime-extracted RAW data lives at:

```
data/dungeon_generator/
  dungeon_stocking.json                       # from acore-setting-construction-rules.xml §621-642
  dungeon_wandering_monster_level.json        # from acore-monster-stocking-rules.xml §76-94
  random_monsters_by_level.json               # from acore-monster-stocking-rules.xml §112-136
  wandering_monster_table_guidelines.json     # from acore-monster-stocking-rules.xml §96-110
  unprotected_treasure.json                   # from acore-setting-construction-rules.xml §760-778
  treasure_type_table.json                    # from acore_treasure_and_magic_items_rules.xml §56-87
  gem_value.json, jewelry_value.json          # from acore_treasure_and_magic_items_rules.xml gems/jewelry sections
  npc_class.json, npc_alignment.json,
  npc_level.json, npc_treasure_type_by_level.json   # from acore-monster-stocking-rules.xml §479-548
```

The condition_catalog precedent at `data/conditions/condition_catalog.json` (referenced in `docs/coding_conventions.md` §43, "extracted from ax_conditions_catalog.xml — sacred") establishes the project pattern. V1 follows it.

### 12.2 Build-time extraction script

A single Python script under `tools/extract_dungeon_generator_data.py` (or similar) reads the sacred XML files and emits the JSON files above. The script:

- Is idempotent (re-running produces byte-identical output for identical XML input).
- Embeds the source citation in each JSON file (e.g., `"_source": "rules/acore-monster-stocking-rules.xml:76-94 dungeon_wandering_monster_level"`) for traceability.
- Is run via the project's existing build pipeline (or manually before tests; document the command in the script header).

### 12.3 Monster catalog snapshot

When V1 stocks a dungeon, it copies the monster's HD / XP / `% In Lair` / morale / alignment / treasure_type / associated_creatures values from the monster catalog onto the MonsterGroup record. This guarantees that the dungeon is a self-contained snapshot at generation time, immune to later catalog edits. The catalog itself is similarly extracted from XML at build time per the existing project pattern (each monster's XML entry becomes a JSON object under `data/monsters/` or equivalent — exact location TBD by the monster-catalog-encoding skill / phase).

### 12.4 Diff test (CI gate)

A test under `tests/data_integrity/test_dungeon_generator_data_freshness.py` (or equivalent) re-runs the extraction script in a temp directory and diffs the output against the checked-in JSON. If they differ, the test fails. This prevents accidental drift between the XML and the encoded JSON.

### 12.5 Convention reference — APPLIED

The general rule is now documented at `docs/coding_conventions.md` §7.4 "Runtime Data Extracted from Sacred Rules XML" (companion edit 2026-05-27). V1's `data/dungeon_generator/*.json` is the second canonical instance of the pattern (after the existing condition_catalog precedent). Every file under `data/dungeon_generator/` carries the required `_source` field; the extraction script lives under `tools/extract_dungeon_generator_data.py`; the CI diff test lives under `tests/data_integrity/test_dungeon_generator_data_freshness.<py|gd>`. See coding_conventions.md §7.4.1–§7.4.6 for the full discipline.

---

## 13. Treasure Resolution

V1 resolves every treasure type to specific coins, gems, jewelry, and magic items at generation time per Jedidiah's direction (§3, decision 6).

### 13.1 Lair treasure

For each MonsterGroup with `is_lair = true` and a non-null `treasure_type_letter`, roll the treasure type per the encoded `treasure_type_table` (§12, originally `rules/acore_treasure_and_magic_items_rules.xml:14-19`):

1. For each non-"None" column in the treasure_type_table row for that letter, roll the listed dice/percentage.
2. For coins: multiply the rolled die result by 1000 to get actual coin count.
3. For gems: roll each on the gem-value sub-table (ornamental / gem / brilliant).
4. For jewelry: roll each on the jewelry-value sub-table (trinket / jewelry / regalia).
5. For magic items: roll the percentage chance; if it hits, roll the indicated number in the indicated category from the magic item catalog. If a category catalog is unpopulated, emit a placeholder per §13.4.

Place the materialized treasure into a `TreasureHoard` attached to the room. The hoard's accumulation category (Hoarder/Raider/Incidental) influences physical presentation per `rules/acore_treasure_and_magic_items_rules.xml:21-36`; V1 records the category on the hoard for later LLM description.

### 13.2 Unprotected treasure (Empty, Trap-placeholder, Unique-placeholder)

For each room flagged for unprotected treasure (15% on Empty, 30% on Trap-placeholder, 15% on Unique-placeholder when the monster fallback is non-lair), roll 1d6 and consult `unprotected_treasure[floor_tier]` (encoded per §12, originally `rules/acore-setting-construction-rules.xml:760-778`). The cell value is a treasure-type letter (A–R). Roll that treasure type per §13.1.

Place the result in a TreasureHoard with `source ∈ {unprotected_empty, unprotected_trap_placeholder, unprotected_unique_placeholder}` and `treasure_type_letter = null` (the letter is consumed; the hoard knows its origin).

Per RAW, unprotected treasure is hidden by default. V1 sets `is_hidden = true` on these hoards; the runtime can use this for Search-check gating.

### 13.3 XP-to-GP ratio reporting (no auto-balance in V1)

After all treasure is rolled for a floor, compute:

```
total_monster_xp = sum(MonsterGroup.monster_xp_each × MonsterGroup.number_appearing
                      for all groups on the floor, including associated creatures)
total_gp = sum(TreasureHoard.total_gp_value for all hoards on the floor,
               with magic items valued at their listed gp value or 0 if placeholder)
ratio = total_gp / max(1, total_monster_xp)
```

Per RAW, target is 4.0. V1 **logs** the ratio per floor and a `[BALANCE]` warning if outside [3.0, 5.0]. No auto-adjustment in V1.

### 13.4 Magic item catalog gaps

When a treasure roll calls for a magic item category that has no populated catalog, emit:

```
MagicItemPlaceholder:
  category: string         # "any", "potion", "scroll", "sword", "weapon", "armor", "ring", "wand_staff_rod", "misc_item"
  placed_in_hoard: string  # hoard_id
  notes: string            # e.g., "Treasure type N: 'any' magic item 3/4 indicated; catalog incomplete"
```

The V1 build log entry should list every category needed at generation time so the magic-item-catalog work can backfill.

---

## 14. Per-Floor and Per-Dungeon Acceptance Tests

These run automatically at the end of generation. A failed hard test aborts generation with a logged error; the seed is recorded as "ungenerable" and the caller is told to retry.

### 14.1 Hard tests (must pass)

1. **Layout reachability** (per-floor): BFS from each floor's stair / entrance cells, doors-treated-as-passable, reaches every room cell.
2. ~~**Stair alignment** (cross-floor): every stair-down on floor *i* has a matching stair-up on floor *i+1* at the same grid position.~~ **Replaced 2026-07-06** by the stair-geometry and floor-integrity checks of `gdd-dungeon-contiguous-3d.md` §10.2: every StairwellData run walks cleanly bottom→top and top→bottom under the movement rules, and no undeclared floor openings exist.
3. **Global solvability** (cross-floor): the §9.2 algorithm reaches every stair on every floor and every locked door has its key in the reached region and every portcullis has its lever OR is forceable.
4. **Every locked door** has either a placed key OR has been downgraded to wood (§10.4).
5. **Every portcullis** has either a placed lever OR has been downgraded.
6. **Every Trap-placeholder room** has **at least one** bordering door with `is_secret = true` AND `type ∈ {"locked", "trapped"}` — its §11.4 fallback gate. *Exactly one* is the stocker's per-room **target** (it reuses an existing qualifying door rather than adding a second, and prefers a door that won't over-gate a neighbouring trap room), but exactly-one is **not** an enforceable invariant: the layout generator's §8.1 secret roll independently produces `secret` + `locked`/`trapped` doors, so a room can already border two such doors before stocking runs — and no stocking choice can undo a layout-generated door. Therefore **0 qualifying doors is a HARD failure** (the room is ungated / unsearchable / unplayable); **>1 is a benign SOFT warning** (over-gated but fully playable — see §14.2.5). *[Refined 2026-05-28 from "exactly one" after stress testing surfaced layout-generated double-secret-door rooms; rationale in build log.]*
7. **Every Unique-placeholder room** has a non-null `monster_group_id` (the fallback monster).
8. **Every MonsterGroup with `is_lair = true`** has either a non-null `treasure_type_letter` (with a materialized TreasureHoard) OR a logged note explaining why the monster entry lists no treasure.

### 14.2 Soft tests (warn only)

1. **XP-to-GP ratio** per floor within [3.0, 5.0] (§13.3).
2. **Secret-gated treasure fraction** below 30% per floor.
3. **Total room count** within the expected range for the dungeon_size category (per layout GDD §3).
4. **At least one monster room per floor.**
5. **Trap-placeholder over-gating:** a Trap-placeholder room bordered by more than one `is_secret` + `locked`/`trapped` door (target is one — see §14.1.6). Benign (the room is still gated + playable); usually a layout-generated §8.1 secret door coinciding with the §11.4 fallback gate.

---

## 15. Deferred to V2+

Listed here so future planning sessions have a single place to look for "what V1 didn't do":

- **Traps as real mechanisms.** V1 encodes trap rooms as `trap_placeholder` with a Locked+Secret door fallback (§11.4) and trap doors as `type = "trapped"` with Locked behavior fallback (§10.5). V2's trap GDD plugs real trap effects into these placeholders.
- **Unique encounters.** V1 encodes unique rooms as `unique_placeholder` with a monster-roll fallback (§11.5). V2's unique-encounter system replaces or augments the fallback monster.
- **All non-Wizard's-Dungeon dungeon types.** V2 onwards builds the d20 dungeon flavor table from the layout GDD §5.2 properly, with each type getting its own theme parameters and (eventually) its own bespoke stocking tables.
- **Dungeon factions.** `gdd-dungeon-factions.md` integration. V1 emits separate lairs per the non-coalescing rule (§11.7) precisely so the faction system can later promote same-race lairs into competing/allied factions.
- **Tag-filtered encounter table construction.** Per layout GDD §5.3, themed dungeons should build custom encounter tables from monster-catalog tags. V1 uses raw tables exclusively.
- **LLM narrative pass.** Room descriptions, dungeon history, NPC names, etc. V1 records `original_purpose` and `current_purpose` text fields and stops there.
- **Auto-balancing of XP/GP ratio.** V1 logs deviation; V2 actively balances per `rules/acore-setting-construction-rules.xml:755-756`.
- **Wandering monster mechanism replacement.** V1 attaches `encounter_table_row` to each floor so the runtime can roll wandering encounters per `rules/acore-monster-stocking-rules.xml:23-32`. **The user has flagged that wandering monster tables themselves are stopgaps**: the end-state design replaces table rolls with **overstocking at generation time + assigning the excess stock to active patrol routes + specific vermin infinite-respawn points**. When that system lands:
  - V1's `encounter_table_row` becomes vestigial (the runtime stops rolling against tables).
  - The stocking step itself changes: V1 currently generates "exactly the right amount" per the d100 procedure. The new design generates **more** monsters per floor, places some in rooms (the V1-style fixed encounters), and assigns the rest to patrol routes and respawn points.
  - The MonsterGroup schema may grow `assignment_kind ∈ {fixed, patrol, respawn}` and patrol routes / respawn points become their own data structures.
  - This is a significant rewrite of the stocking step; the V1 encode-and-fallback pattern (`trap_placeholder`, etc.) is the model for how V1's MonsterGroups should be tagged so the V2 stocking can find and reassign them.
- **Hidden treasure mechanics.** V1 records `is_hidden = true` but doesn't specify Search-check rules.
- **Trapped door mechanism.** V1 encodes trapped doors as `type = "trapped"` with Locked behavior fallback. V2's trap GDD wires real effects.
- **Multi-group lair "associated creatures" detail.** V1 reads associated creatures from monster catalog entries where defined. V2 may build a richer lair-composition table per monster type.
- **Magic item catalog completeness.** V1 generates placeholders for missing categories (§13.4).
- **Cellular automata for cave-type dungeons.** Layout GDD §14 specifies this. V1 never uses cave types.
- **Above-ground tier-direction question.** V1's tier formula uses absolute distance from entrance regardless of direction. The "deeper = harder" mental model breaks for above-ground structures. V2 may want a different intuition.

---

## 16. Open Questions / Architectural Concerns

**Resolved by Jedidiah (2026-05-27):**

- ~~Companion edit to `gdd-dungeon-layout.md` §5.2 — applied.~~
- ~~Door material distribution — companion edit to layout GDD §8.3 applied.~~
- ~~Banker's rounding override for cross-tier number appearing — exception added to `docs/coding_conventions.md` §3.3.~~
- ~~NPC party base-level choice within a tier's range — V1 uses lower end; randomization deferred until system is proven.~~
- ~~Lair coalescing — V1 does NOT coalesce. Each rolled group is its own lair. Documented as RAW deviation in §2 with faction-system rationale.~~
- ~~Trapped/Unique conversions — encode-with-fallback pattern: Trap rooms get Locked+Secret door fallback, Unique rooms get monster-roll fallback, Trapped doors behave as Locked.~~
- ~~Stair scooting — replaced with constraint-aware placement (§8.1) + post-hoc carving safety net.~~
- ~~Rules XML at runtime — never. Build-time extraction to `data/dungeon_generator/*.json` per §12.~~

**Resolved by Jedidiah's second pass (2026-05-27):**

- ~~Layout GDD §9 stair anchor API — `gdd-dungeon-layout.md` §9.3 "Constrained Stair Placement" added as companion edit. V1 §8.1 uses the preferred constraint-aware path; post-hoc carving retained as catastrophic-failure safety net only.~~
- ~~DoorData `is_secret` overlay flag migrated into the layout GDD §11 DoorData schema. The §8.1 type table updated so a "Secret" roll produces `underlying_type + is_secret=true` rather than `type="secret"`. The §8.3 secret-skip check updated to check `is_secret` instead of `type == "secret"`. Rationale: "once detected, a secret door is never secret again" — overlay is the natural model because detection can flip independently of the door's underlying access state.~~
- ~~Runtime data encoding convention — added as `docs/coding_conventions.md` §7.4 "Runtime Data Extracted from Sacred Rules XML." V1 follows it. Condition catalog and V1 dungeon_generator dataset are the two canonical instances of the pattern.~~

**Smaller items, flagged for record:**

- **Cross-floor lair non-coalescing extends to within-floor non-coalescing (§11.7).** This is the broad reading of Jedidiah's "separate lairs is preferred" direction. If the narrow reading (only across-floor non-coalescing, with within-floor coalescing per RAW) was intended, §11.7 needs revision and the §2 deviation flag is overstated. Flag for confirmation.
- **Build log entries should track placeholder counts** so V2's trap and unique systems can audit pre-existing placeholders before plugging in real content. Recommend the V1 build log entry template include "trap_placeholder count", "unique_placeholder count", and "trapped_door count" per generated dungeon.
- **The unprotected treasure mix on Trap-placeholder rooms (30% chance)** is higher than the 15% rate on plain Empty rooms. Floors with many Trap-placeholder rolls will skew richer than RAW-with-real-traps would, because real traps would absorb some of the "danger budget" that V1 currently routes entirely into the door-fallback. Worth playtesting.
- **NPC party tier-to-level mapping picks the lower end of each ACKS range.** Tier 2 → level 2 (not 3), tier 3 → level 4 (not 5), etc. Confirmed by Jedidiah; randomization deferred. Re-flag once V1 produces playable NPC parties consistently.

---

## 17. Revision History

- **2026-05-27 (rev 1):** Initial draft. V1 orchestration pipeline tying gdd-dungeon-layout.md to RAW ACKS stocking. Wizard's Dungeon as universal fallback. Tier formula per Jedidiah's spec. Cross-floor key/lever placement. Full treasure resolution. Trap/Unique → Empty conversion with 30%/15% treasure rates preserved.
- **2026-05-27 (rev 2):** Incorporates Jedidiah's open-question resolutions. Layout GDD companion edits applied (§5.2 re-flavor, §8.3 door material rule). Lair coalescing turned OFF as intentional RAW deviation with faction-system rationale. Trap and Unique stocking results now use encode-and-fallback (trap_placeholder + Locked+Secret door; unique_placeholder + monster re-roll); trapped doors encoded as `type = "trapped"` with Locked behavior fallback. Stair placement is constraint-aware with post-hoc carving safety net (no more retry-and-scoot). Runtime data encoding section added: rules XML extracted at build time to `data/dungeon_generator/*.json`. DoorData augmented with `is_secret: bool` overlay flag. Wandering monster table flagged as a long-term stopgap to be replaced by overstocking + patrols + respawn.
- **2026-05-27 (rev 3):** Three open questions resolved with companion edits. Layout GDD §9.3 "Constrained Stair Placement" added — V1 §8.1 now uses the constraint-aware path as the primary; post-hoc carving demoted to catastrophic-failure safety net. Layout GDD §11 DoorData schema gained the `is_secret: bool` overlay flag; §8.1 type table updated so "Secret" rolls produce `underlying_type + is_secret=true`; §8.3 secret-skip check updated accordingly. Coding conventions §7.4 "Runtime Data Extracted from Sacred Rules XML" added as a documented project rule (with `_source` field requirement, idempotent extraction script discipline, mandatory CI diff test, and RAW PATCH lock-in pattern); V1 §12.5 references the new convention.
- **2026-07-06 (v1.2):** Contiguous-volume supersession pass (companion edit to [`gdd-dungeon-contiguous-3d.md`](gdd-dungeon-contiguous-3d.md), schema approved by Jedidiah). §3 decision #9 and §8.1 superseded (vertical-plan reservations replace stair anchors; no sequential floor order); §5 banner scoping what survives; §9 moved to the real 3D movement graph; §11 stocking iterates zones at their band tier (RAW-faithful per-level reading); §4.2 stocking fields relocated RoomData → RoomZone, `MonsterGroup.zone_index` + `KeyItem.placed_in_zone_index` added; §14.1.2 stair-alignment test replaced by stair-geometry + floor-integrity checks. ACKS Constraints (§2), tier derivation (§6), key/lever logic (§10), treasure (§13) untouched.
