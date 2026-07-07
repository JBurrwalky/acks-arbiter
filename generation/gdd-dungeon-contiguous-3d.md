# GDD: Contiguous 3D Dungeon Generation (Vertical Composition Rework)

**Authority:** PROJECT-DESIGNED — ACKS prescribes the construction/stocking procedure and structural dimensions (cited in §2); it says nothing about how a video game represents vertical space. Everything else here is project design and engineering.
**Status:** Draft v0.3 — Jedidiah rulings 2026-07-06: story bands with free-form hooks; balcony zones within one room; full stair vocabulary; regenerate-no-migration; **§9 data schema APPROVED**; **fog reveal ruled room-agnostic** (light radius + occlusion only — which the built `FogRevealEngine` already implements; the stale room-scoped text lived only in older GDD prose). Companion edits (§12) applied to the four affected GDDs 2026-07-06. v0.3 adds **§10.3 solvability guidance** (carried-forward discovery-order fixpoint + vertical-gating updates) at Jedidiah's direction. **Build plan:** [`docs/dungeon-contiguous-3d-build-plan.md`](../docs/dungeon-contiguous-3d-build-plan.md) (sub-phases DG-C3D.A–G). Two soft items remain open in §15.
**Depends on ACKS rules:** `rules/acore-setting-construction-rules.xml:573-583` (dungeon construction runs in fixed order: choose type, draw map, stock each room, …); `rules/acore-setting-construction-rules.xml:621-642` (stocking: roll once per room **on each dungeon level**; record results separately by dungeon level); `rules/acore-setting-construction-rules.xml:659-663` (monster placement may reference inter-level connections); `rules/acore-setting-construction-rules.xml:685-688` (camouflaged pit trap: pits are generally 10' deep per dungeon level); `rules/daw_equipment_and_construction.xml:721` (structures have 1 story per 10' of height), `:733` (1 arrow slit per 5' per story); `rules/acore_combat_and_wounds.xml:797` (falling deals 1d6 per 10 feet fallen).
**Depends on project GDDs:** [`gdd-voxel-tactical-architecture.md`](gdd-voxel-tactical-architecture.md) (the 5' cube voxel substrate, floor-as-cell-property, stair cell features, movement modes, multi-level camera — all built and live; this GDD finally generates content that uses it natively); [`gdd-dungeon-layout.md`](gdd-dungeon-layout.md) (the rooms-first per-floor layout pipeline this GDD extends; §9/§9.3/§14 multi-level rules are superseded per §12.1 below); [`gdd-dungeon-generator-v1.md`](gdd-dungeon-generator-v1.md) (the stocking/key/lever orchestrator; its per-room stocking loop becomes per-zone, its stair anchoring is superseded per §12.2); [`gdd-dungeon-map-ui.md`](gdd-dungeon-map-ui.md) (interaction grammar and fog; §12.4); [`gdd-trap-generation.md`](gdd-trap-generation.md) (pit traps become geometrically real; forward hook §12.5); [`gdd-dungeon-factions.md`](gdd-dungeon-factions.md) (consumes zones as territory units when built).
**Implementing files (to be modified):** `engine/subsystems/generation/dungeon_layout/*.gd` (planner), `engine/subsystems/generation/dungeon_generator_v1/dungeon_generator_v1.gd`, `dungeon_voxel_serializer.gd`, `navigability_validator.gd`, `key_lever_placer.gd`, `engine/shared_types/voxel_cell.gd`, `dungeon_stair_data.gd` (superseded), `engine/subsystems/exploration/dungeon_map_controller.gd` (stair-teleport path removed).
**Modifiable by Claude Code:** Yes — all algorithms, footprint sizes, counts, weights, and validation strategies are engineering decisions. The ACKS Constraints in §2 and the user decisions recorded in §4 are not.
**Last updated:** 2026-07-06

---

## 1. Purpose

Rework the dungeon generator so that a multi-story dungeon is **one contiguous voxel volume** instead of independent per-floor 2D maps stitched together by teleporting stair pairs. Stairs become real stepped geometry — a walker ascends 5' per stair cell through an actual stairwell opening — and the generator becomes capable of **multi-story rooms**: a grand atrium with a 20'+ ceiling, second-story balconies and galleries overlooking its floor, and grand stairs connecting them.

The voxel runtime ([`gdd-voxel-tactical-architecture.md`](gdd-voxel-tactical-architecture.md), built 2026-04) already supports everything this requires: floors as cell properties, stepped stair features with direction suffixes (§10.1 there), per-level fog, multi-level camera and Level Strip Widget, 3D LOS, falling. What it never received is *content shaped like that*. The generator still plans each floor as an isolated 2D grid and the serializer stamps floor N at voxel levels N×2 / N×2+1 with `stair_target_*` teleport coordinates gluing floors together. This GDD replaces that seam with a vertical composition stage, while preserving the two things the stocking pipeline cannot lose: **every room and hallway remains individually identifiable**, and **every stocking unit has a definite ACKS dungeon level**.

---

## 2. ACKS Constraints

These come from the books and may NOT be changed:

- **The construction procedure runs in fixed order** — choose type, draw the map, stock each room, place monsters, place traps, add unique encounters, assign treasure, finalize descriptions (`rules/acore-setting-construction-rules.xml:573-583`). The vertical composition stage in §8 is part of "draw the map"; it completes before any stocking roll.
- **Stocking is rolled once per room on each dungeon level, and results are recorded separately by dungeon level** (`rules/acore-setting-construction-rules.xml:621-642`, `stocking_the_dungeon` steps 1-2). This is the load-bearing constraint for the whole rework: a contiguous 3D dungeon must still expose a discrete "dungeon level" for every stockable space. §11 defines how zones satisfy this — including the interpretation for rooms that exist on two dungeon levels at once.
- **Monster placement may consider inter-level connections** — "Lower-level monsters can be placed near inter-level connections or as guards for stronger intelligent monsters" (`rules/acore-setting-construction-rules.xml:659-663`). The rework makes "near inter-level connections" a literal cell-distance to stairwell geometry rather than a same-cell teleport marker.
- **A story is 10 feet** — towers and structures have "1 story per 10' of height" (`rules/daw_equipment_and_construction.xml:721`); arrow-slit allocation is per-5'-per-story (`:733`). With 5' voxels this fixes the story band at exactly 2 voxel levels, as the voxel GDD already established.
- **Pits are generally 10' deep per dungeon level** (`rules/acore-setting-construction-rules.xml:685-688`). Confirms that ACKS itself treats one dungeon level as one 10' story of depth — the band model in §5 is the geometric realization of this.
- **Falling deals 1d6 per 10 feet fallen** (`rules/acore_combat_and_wounds.xml:797`). A creature stepping off an atrium balcony onto the floor 10' below takes 1d6. The voxel GDD's falling resolver (§11.5 there) already implements this; balconies simply give it content.

---

## 3. Problem Statement — Current-State Audit

What exists today (verified against built code, 2026-07-06):

1. **Planner:** `gdd-dungeon-layout.md`'s rooms-first pipeline generates one 2D floor at a time. Multi-floor coordination is only `required_stair_positions` — the next floor must place a stair cell at the *same (col,row)* as the prior floor's stair (layout GDD §9.3).
2. **Serializer:** `dungeon_voxel_serializer.gd` stamps floor N's cells at voxel levels N×2 (walk) and N×2+1 (headroom), then `_apply_stair_overlays` writes `stair_target_col/row/level` onto stair cells. Stair facing is not even recorded — every stair gets a default `_N` suffix.
3. **Runtime:** `DungeonMapController.get_stair_target()` teleports the party between floors. Movement between floors is a special case, not movement.
4. **Consequences:** floors are spatially unrelated islands (deeper floors are not physically below shallower ones — the teleport hides it); no room can span stories; no balcony, no atrium, no open stairwell sightlines; falling between floors is impossible; flyers cannot fly up a stairwell; the voxel model's multi-level fog and camera machinery has nothing multi-level to show inside a dungeon.

What must be preserved:

- The rooms-first planner (scatter → MST → corridor routing → doors) is good and stays as the **per-band** planner.
- The V1 stocking/key/lever/treasure orchestration stays; its inputs change shape only where §9 and §11 say so.
- Room and corridor identity (`room_id`, `is_corridor` on cells) — the stocking algorithm and fog reveal depend on it.

---

## 4. Design Decisions (User-Specified, 2026-07-06)

These are Jedidiah's decisions for this rework. They are not engineering-negotiable:

1. **Story bands now, free-form hooks reserved.** Vertical structure is strict 10' story bands (2 voxel levels each) in this version. Rooms and corridors sit flat within their band. However, the schema (§9) carries `level_offset` and height fields on rooms and zones so a later pass can add mezzanines, half-story splits, and sloped corridors **without a data migration**. The generator asserts `level_offset == 0` for now.
2. **Balconies are zones within one room.** A grand atrium and its overlooking balconies share one `room_id` — it is all one chamber. Balconies are tagged sub-zones, and **stocking rolls once per zone** (§11). This preserves "it's one room" semantics while a 2-story galleried atrium still yields more content than a broom closet.
3. **Full stair vocabulary.** The generator produces straight runs, switchback stairwells (L/U-shaped with landings), and spiral stairs, plus ramps for the themes that want them (§6).
4. **Regenerate, no migration.** The generator version bumps; previously stored dungeons are discarded and lazily regenerated. The legacy `stair_target_*` fields and the teleport path in `DungeonMapController` are deprecated and removed once the rework lands (§13).

---

## 5. Core Model: Bands, the Shared Volume, and Zones

### 5.1 Story Bands

A **band** is one ACKS dungeon level realized as 2 voxel levels: a **walk level** (cells with `floor_type` set, where entities stand) and a **headroom level** above it. Bands stack back-to-back; the walk-level floor slab of band k+1 is the implicit ceiling of band k (voxel GDD §9.1).

Band placement in voxel space:

```
walk_level(floor_index) = 2 × direction × (entrance_floor_index − floor_index)
  direction = +1 for subterranean (deeper floors physically LOWER, negative levels)
  direction = −1 for above-ground structures (higher floors physically HIGHER)
```

The entrance floor's walk level is always 0. Example, subterranean, entrance on floor 1 of 3: floor 1 → walk 0, floor 2 → walk −2, floor 3 → walk −4. This fixes the current model's quiet absurdity where "deeper" floors sit at *higher* voxel levels connected by teleports.

`floor_index`, per-floor tier derivation, and the `encounter_table_row` attachment are unchanged from `gdd-dungeon-generator-v1.md` §6 — a band IS a floor for every tier, treasure, and wandering-monster purpose.

### 5.2 One Volume, One Grid

All bands of a dungeon share a single horizontal grid (same `grid_width × grid_height`, same coordinate origin) and are stamped into **one `VoxelMapData`**. The per-`dungeon_size` grid dimensions from layout GDD §4.3 are unchanged; they simply apply to the whole volume. Solid rock is the default fill for subterranean bands (cells not carved by any room, corridor, or vertical feature are `solidity: solid`), exactly as the per-floor stamping does today — contiguity does not change the rock model, it only makes the space between carved regions *shared and honest*.

### 5.3 Zones — the Stocking Unit

A **zone** is a maximal contiguous walkable region of a single room on a single band. Every room has at least one zone (its main floor). Only multi-story rooms have more:

- A normal 10'-ceiling room = 1 zone (`zone_type: "main"`). Identical to today's behavior.
- A grand atrium = 1 main zone (ground floor, base band) + 1..n balcony/gallery zones (upper band walk cells with floor slabs, at the room's perimeter).
- Corridors are not rooms and have no zones (`room_id = −1`, `is_corridor = true`, unchanged).
- Stairwell rooms (§6.5) are rooms of `kind: "circulation"` — they have zones for identity and fog purposes but are **excluded from stocking**, exactly as stair/lever-only rooms are excluded today (`gdd-dungeon-generator-v1.md` §11.1).

**Zone identity on cells:** `VoxelCell` gains `zone_index: int = −1` alongside the existing `room_id`. Two balconies on the same band of the same atrium (e.g., east and west galleries that do not connect to each other) are distinct zones, so zone membership cannot always be derived from `(room_id, band)` — it is stamped per-cell at composition time.

### 5.4 Free-Form Hooks (Reserved, Not Implemented)

Per decision #1, the following fields exist in the schema from day one but are always default in this version: `RoomData.level_offset: int = 0` (voxel levels relative to band walk level), `RoomZone.level_offset: int = 0`, `RoomData.height_levels: int` (2 for normal rooms; 4 for a two-band atrium; a future mezzanine room might be 3). Validation asserts the defaults; persistence and serialization carry the fields. When free-elevation work happens later, it changes the planner, not the data model.

---

## 6. Vertical Connector Vocabulary

All connectors are built from the voxel GDD's existing primitives — stepped stair cells (`stairs_up_D` / `stairs_down_D`, 1 level per cell, voxel GDD §10.1), ramp cells, and floor openings. A 10' story change therefore always spans **two stepped cells** (or a shaft). Each generated connector is recorded as a logical `StairwellData` object (§9.3) so validation, minimap labeling, and the ACKS placement heuristic (§2) can reason about "the stairs" as a unit.

### 6.1 Straight Run

The workhorse. Descending from band k+1 (walk W+2) to band k (walk W), one 5'-wide lane:

| Cell | Level | Content |
|---|---|---|
| T (top landing) | W+2 | normal upper-band cell, floor slab |
| H (shaft opening) | W+2 | `floor_type: none` — the hole in the upper floor, directly above B |
| B (upper step) | W+1 | stair cell, `floor_type: stone`, direction suffix toward T |
| A (lower step) | W | stair cell, `floor_type: stone`, direction suffix continuing the run |
| L (bottom landing) | W | normal lower-band cell adjacent to A |
| under-B | W | `solidity: solid` — the staircase's supporting mass |

Movement: L → A (flat), A → B (+1, stair feature), B → T (+1 diagonal through the shaft opening, stair feature) — every step is legal under voxel GDD §11.1 rule 4, no special case. Total footprint: 2 cells of the lower band's plan (columns A and B) plus 1 floor opening in the upper band. Standard width is 2 lanes side by side (10', matching the corridor standard, layout GDD §7.1); grand stairs in atria may be 3-4 lanes.

### 6.2 Switchback Stairwell (L / U shaped)

A compact stairwell room: run up half a flight, landing, turn 90° or 180°, run up the rest. Footprint 3×2 (L) or 3×3 (U) occupied on **both** bands. Interior: two straight-run halves whose middle landing sits at W+1 with `floor_type: stone`. Reads architecturally as "a stairwell," encloses the vertical connection behind doors (the door placer treats stairwell room perimeter transitions like any room), and is the preferred connector for Prison / Tower / Temple style themes.

### 6.3 Spiral Stair

A 1-cell (5') or 2×2 (10') shaft spanning 2+ levels. Cells in the shaft carry `feature: "stairs_spiral"`, `floor_type: stone` at each walk level, and floor openings through each intervening slab. Movement rule: a creature in a spiral cell may step ±1 level within the shaft column per move, at normal movement cost, no climb throw (it is stairs, not a ladder — contrast voxel GDD §11.4's half-rate ladders). This is one new movement-rule clause in the mover; everything else reuses existing machinery. Preferred for Tower and Wizard's Dungeon themes and as a space-cheap secondary connection.

### 6.4 Ramp

Two ramp cells in sequence, mechanically identical to a straight run with `ramp_D` features (voxel GDD §10.2). Produced for themes whose builders don't do stairs: Giant burrow, Natural caverns, Giant insect hive, Underground river (theme→connector-weights table in §8.3).

### 6.5 Connector Rooms Are Circulation

Straight runs may sit inside ordinary rooms or corridors (a grand stair in an atrium; a stair at a corridor end). Switchbacks and spirals always generate as their own small `kind: "circulation"` rooms so they get walls, doors, and fog identity. Circulation rooms are excluded from the stocking roll loop (§11) but ARE eligible key/treasure *placement* targets only in the same way corridors are today: they are not.

### 6.6 The Entrance

The dungeon entrance remains a special surface connection (scene transition to the wilderness map), flagged `is_entrance` on its StairwellData. Intra-dungeon geometry does not model the surface; this is the one legitimately non-geometric transition and it is out of scope.

---

## 7. Multi-Story Rooms: Atriums, Balconies, Galleries

### 7.1 Anatomy of a Grand Atrium

An atrium is a room with `height_levels: 4` (two bands, 20' ceiling) whose footprint exists on the base band and punches through the band above:

- **Base band (walk W):** normal room floor — the atrium's main zone.
- **Upper band walk level (W+2), interior:** `floor_type: none` open void. Ground-walkers cannot occupy it; flyers can (`feature: "air_open"` semantics). LOS crosses it freely — an archer on a balcony sees the atrium floor.
- **Upper band walk level (W+2), perimeter ring (1-2 cells deep):** `floor_type: wood|stone` — the **balcony/gallery zones**, same `room_id`, distinct `zone_index`.
- **Ceiling:** implicit at W+4 (the slab of the band above that, or solid rock cap).
- **Balcony edge cells** get `cover_value` > 0 (a parapet — engineering-tunable, suggest 1 per ACKS cover conventions already carried on `VoxelCell.cover_value`), and are fall hazards: stepping off is a deliberate 10' drop, 1d6 per `rules/acore_combat_and_wounds.xml:797`.

### 7.2 Balcony Connectivity Guarantee

Every balcony zone must be reachable by at least one of: (a) a door/corridor connection to the upper band's own circulation network, or (b) an internal grand stair rising from the atrium's main floor. The composer prefers (a) and adds (b) with probability per theme (a temple gallery reached only from the upper cloister is good design; so is a wizard's observation balcony with its own sweeping stair). If neither can be routed, the balcony ring is removed and the room degrades gracefully to a plain double-height hall (main zone only) — degradation is logged.

### 7.3 Placement and Frequency

Atrium candidacy is decided in the vertical plan (§8.2): a room slated for the base band is promoted to multi-story if (a) the band directly above exists in the dungeon, (b) the footprint on the upper band can be reserved without colliding with that band's other reserved features, and (c) the theme rolls under its `multi_story_room_chance`. Suggested starting parameters (engineering-tunable):

| Theme | Chance per eligible dungeon | Typical purposes promoted |
|---|---|---|
| Temple | 60% | worship hall, sanctum |
| Wizard's dungeon | 40% | summoning chamber, library |
| Crumbling castle / Ruined manor | 40% | great hall |
| Tomb / Catacombs | 20% | burial vault rotunda |
| Natural caverns / Giant burrow | 35% | open cavern (no balcony ring — a natural gallery ledge instead, 1 cell, irregular) |
| Prison / Sewers / Maze / others | 10% | communal hall or none |

Room size gate: only rooms ≥ 5×5 cells promote (a 20' ceiling over a 10' closet is silly). Cap: 1 atrium per adjacent band pair by default, +1 for Large dungeons.

### 7.4 What Multi-Story Rooms Give the Rest of the Game

Free consequences, no extra systems: balcony archers with cover firing on the atrium floor (3D LOS already works); flyers using the void (roc in the great hall); falling and being pushed off galleries (falling resolver); the multi-level fog rule (voxel GDD §15.3) finally has its intended balcony case; faction guard posts overlooking a contested hall when `gdd-dungeon-factions.md` lands (zones are natural territory units).

---

## 8. Generation Pipeline Rework

Replaces the multi-floor portions of `gdd-dungeon-generator-v1.md` §5/§8.1 and layout GDD §9.3. The per-band planner (rooms-first: scatter → MST → corridors → doors) is unchanged internally.

```
A. VERTICAL PLAN (new, whole-dungeon, runs FIRST)
   A1. Derive bands: floor_count, entrance_floor_index → band list, walk levels (§5.1),
       per-band tier (V1 §6 unchanged), structure direction (subterranean/above-ground).
   A2. Choose connectors per adjacent band pair: count = 1 + extra for Large
       (1 per 15-20 rooms, layout GDD §9.1 unchanged); types rolled from the
       theme's connector-weight row (§8.3).
   A3. Choose atrium promotions per §7.3.
   A4. Reserve footprints: each connector and atrium claims rectangles on BOTH
       affected bands (collision-checked against each other, interior margin
       [2, grid−3] as today). Output: per-band reservation lists.
B. PER-BAND LAYOUT (existing rooms-first planner, one call per band, any order)
   B1. Reservations enter the plan as pre-placed rooms: connector footprints as
       circulation rooms; atrium base footprint as a normal (large) room; atrium
       upper footprint as a BLOCKED region with a balcony-ring room stub the
       corridor router may connect doors to.
   B2. Scatter remaining rooms, MST (reserved rooms are MST nodes — guaranteeing
       every connector and balcony joins the band's network), corridors, doors,
       purposes — all per existing layout GDD §6-§8.
C. VERTICAL COMPOSITION (new)
   C1. Stamp every band into the single VoxelMapData at its walk/headroom levels;
       solid-fill uncarved subterranean space.
   C2. Carve connectors: stair steps, under-fill, shaft/floor openings, spiral
       shafts, landings (§6 patterns). Stamp StairwellData records.
   C3. Carve atria: void the upper-band interior, slab the balcony ring,
       parapet cover values, optional internal grand stair (§7.2b).
   C4. Assign zones: flood-fill walkable regions per (room, band) → zone_index
       stamped on cells; build RoomZone records.
   C5. FLOOR INTEGRITY PASS: every walkable cell on band k+1 above open space of
       band k must have floor_type != none unless its column belongs to a
       registered opening (stair shaft, atrium void, spiral shaft). Every
       registered opening must have NO floor. Violations are generation bugs —
       fail loudly, never ship a hole nobody declared.
D. DOOR MATERIALS, KEYS, LEVERS (V1 §5 steps 3.2/4 unchanged in logic)
   The discovery-order fixpoint BFS (V1 §10.2) now walks the real 3D movement
   graph (§10 below) instead of per-floor BFS + stair-teleport edges. The DAG
   guarantee ports intact; the new gating hazards and required updates are
   specified in §10.3 (sole-connector secret exclusion, extended repair
   ladder, gate blast-radius telemetry).
E. STOCKING + TREASURE (V1 §5 steps 5-7, per-ZONE per §11)
F. ACCEPTANCE (V1 §14 extended per §10.2)
```

Because ALL vertical reservations are computed before any band lays out, the sequential "radiate outward from the entrance floor, anchor each floor to the last" choreography (V1 §8.1) disappears, along with its same-(col,row) constraint and its post-hoc carving safety nets. Bands can generate in any order or in parallel. The whole-dungeon re-seed ladder (V1 §9.2 recovery levels) is retained unchanged as the outer safety net.

### 8.3 Theme Connector Weights (starting values, engineering-tunable)

| Theme group | straight | switchback | spiral | ramp |
|---|---|---|---|---|
| Default (Wizard's dungeon, etc.) | 45% | 25% | 20% | 10% |
| Tower, Prison, Temple | 20% | 45% | 35% | 0% |
| Natural caverns, Giant burrow, Insect hive, Underground river | 25% | 0% | 0% | 75% |
| Catacombs, Tomb, Barrow mound | 55% | 25% | 20% | 0% |
| Mine | 40% | 10% | 10% | 40% |

---

## 9. Data Model and Schema Changes

### 9.1 RoomData (extends layout GDD §11)

```
RoomData (additions):
  band: int                    # floor_index — the room's ACKS dungeon level
  kind: string                 # "chamber" (default) | "circulation" (stairwells)
  height_levels: int = 2       # 2 = standard 10'; 4 = two-band atrium
  level_offset: int = 0        # RESERVED free-form hook (§5.4); always 0 for now
  zones: Array[RoomZone]
```

Stocking result fields (`contents_kind`, `monster_group_id`, `treasure_hoard_id`, `current_purpose`) **move from RoomData to RoomZone**. A room's `current_purpose` remains as the LLM-facing rollup (composed from its zones' results).

### 9.2 RoomZone (new)

```
RoomZone:
  room_id: int
  zone_index: int              # 0 = main floor zone
  band: int                    # the zone's ACKS dungeon level — drives tier for stocking
  zone_type: string            # "main" | "balcony" | "gallery" | "ledge" | "landing"
  cells: Array[Vector2i]       # footprint at walk_level(band) + level_offset
  level_offset: int = 0        # RESERVED hook
  # Stocking (formerly on RoomData):
  contents_kind: string        # "empty" | "monster" | "monster_lair" | "trap_placeholder" | "unique_placeholder"
  monster_group_id: string|null
  treasure_hoard_id: string|null
  current_purpose: string
```

`MonsterGroup.room_id` gains a sibling `zone_index`; `KeyItem.placed_in_room_id` likewise. Treasure hoards and containers bind to zones.

### 9.3 StairwellData (replaces StairData)

```
StairwellData:
  stairwell_id: string
  type: string                 # "straight" | "switchback" | "spiral" | "ramp"
  lower_band: int
  upper_band: int
  bottom_cell: Vector3i        # lower-band landing approach
  top_cell: Vector3i           # upper-band landing approach
  run_cells: Array[Vector3i]   # every stair/ramp/shaft cell
  width: int                   # lanes (1-4)
  room_id: int                 # owning circulation room, or the room/corridor containing an inline run
  is_entrance: bool
```

Consumed by: acceptance tests ("every stairwell traversable both directions"), minimap/UI labels ("Stairs down to Level 3"), the ACKS placement heuristic (V1 §11.8 — "near inter-level connections" = Chebyshev distance to `run_cells`), and factions later.

### 9.4 VoxelCell / Persistence

- `VoxelCell.zone_index: int = −1` — new, stamped at composition.
- `VoxelCell.stair_target_col/row/level` — **deprecated, removed** (§13). Movement through stairs is ordinary movement.
- `voxel_map_cells` table: add `zone_index INTEGER NOT NULL DEFAULT -1` (additive migration). New tables or columns for `room_zones` and `stairwells` per the repository's existing patterns; `dungeon_rooms` gains `band`, `kind`, `height_levels`, `level_offset`. Migrations are sequential and non-destructive per project convention, but note: since old dungeons regenerate rather than migrate (§13), the migration only needs to establish schema, not convert stored rows.

### 9.5 Generator Output Shape

The V1 generator's per-floor `DungeonLayout` array is replaced by one whole-dungeon output: a composed `VoxelMapData` plus dungeon-level metadata (rooms with zones, stairwells, per-band summaries — `floor_tier`, `encounter_table_row`, XP/GP ledgers stay **per band**). Whether Claude Code keeps a per-band internal planning struct is an engineering decision; the persisted and runtime-consumed shape is the composed volume.

---

## 10. Validation and Navigability

### 10.1 One Graph, One BFS

All reachability checks run on the real 3D movement graph: nodes are walkable cells (support rule, voxel GDD §9.2), edges are legal walker steps (flat, ±1 level via stair/ramp/spiral features, doors per their passability model). The per-floor BFS + stair-teleport-edge special case in `navigability_validator.gd` is deleted. Every pass seeds from the **dungeon entrance only** — never per-stair — preserving the DG-V1 lesson that multi-point seeding masks disconnected pockets (generator-v1 GDD §9.2's single-stair-seeding fix). The two-pass structure survives:

- **Structural pass (pre-keys):** all doors passable; every zone of every room reachable from the entrance; every stairwell traversable in both directions.
- **Solvability pass (post-keys/stocking):** doors in initial states, fixpoint key/lever unlock exactly as V1 §9.2 — acceptance criteria unchanged, restated over zones: every stairwell reachable, every locked door's key reachable, every portcullis lever reachable or forceable, every MonsterGroup's **zone** reachable, treasure soft-check per zone.

### 10.2 New Acceptance Checks

1. **Floor integrity** (§8 C5): no undeclared holes; all declared openings open.
2. **Stair geometry**: each StairwellData's run walks cleanly bottom→top and top→bottom under the movement rules (catches a missing shaft opening or landing).
3. **Balcony reachability** (§7.2): every balcony zone reachable; else degraded and logged.
4. **Band honesty**: every walkable cell's level equals `walk_level(band of its room) + level_offset` (asserts the §5.4 hooks stay zeroed until free-form work actually lands).
5. **Fall audit (soft)**: log count of walkable cells adjacent to a ≥10' drop (balcony edges, shaft edges) per band — playtest telemetry for accident frequency, not a gate.

### 10.3 Solvability Under Vertical Gating — Carried-Forward Method and Required Updates

*(Added 2026-07-06 at Jedidiah's direction. DG-V1's hardest roadblock was exactly this: dungeons rendered partially unplayable by unbashable locked doors with no reachable key, or by secret doors gating required content. This section states what carries forward, what is new, and what must change.)*

**Verdict on the old method: keep the post-2026-06-10 version, verbatim in spirit.** DG-V1 solved the roadblock twice. The first solution (per-door "outside region" BFS) had a circular-key-dependency hole (~15-20% multi-floor failure) and was retired. The second — the **discovery-order fixpoint** (generator-v1 GDD §10.2): one BFS from the entrance; when the frontier reaches a gated door, place its key/lever immediately in space *already fully discovered*, open the door, continue — makes "key on the inaccessible side" **impossible by construction**, because the placement graph is a dependency DAG. Critically, that guarantee is *topology-agnostic*: the BFS does not care whether an edge is a corridor step or a stairwell step. It ports to the 3D graph unchanged. Do not resurrect the outside-region method.

**Substitutions when porting:**

- Key/lever candidate unit is the **fully-discovered zone** (not room): excluding the entrance zone and circulation rooms, exactly as rooms were excluded/filtered before. This matters for atriums — a discovered main zone qualifies even while its balcony zones are unexplored, and a key must never be physically homed into an undiscovered balcony of a "mostly discovered" room.
- Distance weighting (V1 §10.3): same **band** 5, adjacent band 2, distant 1.
- All door-class rules carry forward: hard locked/trapped doors get keys; wooden ones are bash-resolvable; **every secret locked/trapped door gets a key regardless of material** (V1 §10.1 refinement — the model blocks on `is_secret` until the key is discovered, standing in for "Search, then open").

**New invariant — doors are the ONLY gates.** Vertical geometry must never create a keyless gate: stairwell runs, ramp runs, spiral shafts, and atrium internal stairs carry **no door cells and no gate semantics on their run cells**. Gates live where they always did — at room-boundary door cells (a switchback stairwell room's entry doors may roll locked/secret like any door; the run inside is free). The composer enforces this; the validator asserts it (no door cell within any `StairwellData.run_cells`).

**New invariant — reachability counts reversible edges only.** Falls (stepping off a balcony, shaft drops) are real at runtime but are **never** edges in any validation BFS: a zone reachable only by falling into it is *unreachable*, and one-way geometry is a composition bug. Since every legal walk edge in this design is symmetric (stairs traverse both directions — §10.2 check 2), reachable ⇒ exitable; the validator asserts symmetry rather than assuming it.

**The blast radius grows — and gets telemetry.** In DG-V1 a locked door gated at most a room cluster; stairs sat in open antechambers. Now a single locked or secret door on a stairwell room can gate an **entire band and everything below it**. The fixpoint handles this correctly (the key lands on an earlier-discovered band), but "correct" is not the same as "good play." Two mitigations:

1. **Proactive — sole-connector secret exclusion.** At door-roll time, doors on a circulation room that is the *only* connector for an adjacent band pair skip the secret-overlay roll (locked is fine — locked doors carry keys; secret doors carry only the hope of a Search throw). If a band pair has 2+ connectors, at most all-but-one may end up secret-gated; if the dice disagree, clear `is_secret` on one (log it). Net rule: **every band is reachable through at least one never-secret path.**
2. **Telemetry — gate blast radius.** For every gated door, the solvability pass records the cell/zone count exclusively gated behind it; a `[GATE]` warning logs when any single key gates more than a tunable fraction (suggest 40%) of the dungeon's stockable zones. Soft, tunable, playtest-facing — the DG-V1 XP/GP-ledger philosophy applied to access.

**Repair ladder, extended.** DG-V1's two repair rules carry forward with a zone/stairwell-aware unreached set, plus a new hard boundary:

1. Gated door reached before *any* zone is fully discovered (sole entrance path) → V1 §10.4 downgrade (hard door → wood; portcullis → wooden door). Unchanged.
2. Fixpoint completes with a stairwell or zone unreached, and a frontier **secret+unlocked** door (keyless, model-impassable) explains it → clear `is_secret`, log, re-drain. Unchanged in mechanism; the unreached set now spans bands, zones, and stairwells.
3. **NEW:** fixpoint completes with unreached content and *no* frontier door explains it → this is structural (a composition defect: missing landing, unregistered opening, disconnected reservation), NOT a key problem. Hard-fail into the whole-dungeon re-seed ladder; never attempt geometric repair from the key layer.

**Post-hoc carving is demoted to near-dead code.** DG-V1's L-shaped corridor carve (`_carve_unreachable_rooms`) was a legitimate per-floor safety net. In a composed volume, blind carving can punch through stair shafts, atrium voids, under-stair fill, or the floor above/below — trading an unreachable room for a corrupted dungeon. Rules: carving (if retained at all) operates per-band, horizontally, must not intersect any registered opening or connector footprint, and re-runs the floor-integrity pass afterward. But the honest position: connectivity is by-construction now (reservations are MST nodes; stairwells are physical), so if the structural pass fails, prefer re-seed over repair. Carving firing at all is a bug to investigate, per the V1 §8.1 precedent.

**Stocking-time gate additions re-validate.** The trap-placeholder fallback (V1 §11.4) upgrades a door to Locked+Secret *after* primary key placement and homes its key via the same discovery-order candidate rule; the full solvability pass then re-runs as pipeline step 8 (V1 §5). That ordering carries forward unchanged — no gate is ever added without re-running acceptance. The §11 balcony nuance (trap results on door-less zones re-target or swap within the band) exists precisely to keep this machinery sound for zones.

---

## 11. Stocking Contract (Per-Zone)

**RAW interpretation note.** ACKS instructs: "Roll once on the dungeon stocking table for each room on each dungeon level. Record results separately by dungeon level" (`rules/acore-setting-construction-rules.xml:621-642`). A multi-story room genuinely exists on two dungeon levels. Rolling once for its main floor (at the base band's level) and once per balcony zone (at the upper band's level) is the most literal available reading of "each room on each dungeon level" — the room is stocked on each level it presents walkable space, and results are recorded by level. This is documented as an interpretation, not a deviation.

Mechanics, replacing "room" with "zone" in V1 §11 wholesale:

- The d100 loop iterates **zones of chamber-kind rooms** (circulation rooms and corridors skipped, as stair/lever rooms are today). Single-zone rooms behave byte-for-byte as before.
- The zone's **band tier** drives the monster level roll and unprotected-treasure row — a balcony over a floor-2 atrium in a floor-3-adjacent band stocks at the upper band's tier. All V1 procedures (cascaded monster rolls, % In Lair per group, no coalescing, trap/unique placeholders with fallbacks, treasure resolution, key homing) apply per zone unchanged.
- **Trap-placeholder fallback nuance:** the Locked+Secret door fallback (V1 §11.4) gates *doors*. A balcony zone whose only access is an open gallery cannot take that fallback; if a trap result lands on such a zone, re-roll the fallback onto the zone's access door if one exists, else swap the trap result with another zone in the same band (log the swap). The d100 result itself is never re-rolled — assignment within the level is Judge's discretion per `rules/acore-setting-construction-rules.xml:621-642` step 3 ("assign each result to a specific room in a way that fits dungeon logic").
- **Placement heuristics** (V1 §11.8): "near inter-level connections" becomes distance-to-`StairwellData.run_cells`; balcony zones are attractive spots for low-HD guard groups overlooking a stronger group's floor zone — that composition is exactly the RAW placement rule's intent (`rules/acore-setting-construction-rules.xml:659-663`) and is a suggested V2 heuristic, not required now.

XP/GP ratio ledgers (V1 §13.3) aggregate zones by band, so per-level balance reporting is unchanged.

---

## 12. Integration Impacts and Companion Edits

Edits 12.1-12.4 were drafted and applied 2026-07-06 on Jedidiah's instruction. 12.5-12.7 remain forward hooks.

### 12.1 `gdd-dungeon-layout.md` — APPLIED 2026-07-06
- §9.1/§9.2 (stair placement) and §9.3 (constrained stair anchors) superseded by §8 here; §14's "Multi-level spatial coherence: levels generated independently, only stair positions must match" superseded by the shared-grid single-volume model (§5.2). Above-ground footprint-shrink rules survive, applied per band.
- §11 schema: RoomData/StairData deltas per §9 here.

### 12.2 `gdd-dungeon-generator-v1.md` — APPLIED 2026-07-06
- §5 pipeline steps 3.x, §8.1 (anchors, radiate-outward order, post-hoc stair carving) superseded by §8; §9 navigability rewritten per §10; §11 stocking re-worded per-zone per §11 here (ACKS Constraints §2 there are untouched — the tables and rolls are identical).

### 12.3 `gdd-voxel-tactical-architecture.md` — APPLIED 2026-07-06
- No model changes — this GDD is its first native content producer. §10.4's promise ("StairData dissolves; use_stairs becomes ordinary movement") is finally redeemed. One addition: the `stairs_spiral` feature + its movement clause (§6.3 here).
- **Fog reveal (RULED by Jedidiah 2026-07-06): room-agnostic.** Reveal is determined by light-source radius and occlusion (3D LOS) only — never by room boundary. The stale "room-scoped reveal" prose in §15.2/§12.4 there contradicted both this ruling and the *built engine* (`fog_reveal_engine.gd` explicitly replaced room-scoped reveal with light+LOS in Batch 3, and `gdd-dungeon-map-ui.md` §8.2 already documents the light+LOS model). The companion edit deletes the room-scoped sentences and aligns §15.3 and §21.5. The former §15.2/§15.3 contradiction dissolves: a balcony reveals exactly when a party light source has line of sight to it, symmetric in both directions.

### 12.4 `gdd-dungeon-map-ui.md` — APPLIED 2026-07-06
- §4.2.2 Ascend/Descend teleport options removed: internal stairs are plain movement (Move Here; `path_bfs_3d` already walks ±1-level stair steps). **Exit Dungeon** on transition cells is unchanged. Minimap gains stairwell glyphs/labels from StairwellData. Level Strip Widget needs no change (already per-voxel-level). §13.1's `stair_target_*` build-status line marked deprecated per §13 here.

### 12.5 `gdd-trap-generation.md` (forward hook, V2)
- Pit traps become geometrically real: a pit on band k can open into band k−1's actual space below — 10' per dungeon level (`rules/acore-setting-construction-rules.xml:685-688`) now literally lands you one level down, possibly in an occupied room. When the trap GDD wires real pits, it should query the volume for what's below rather than fabricating a pocket void. Delightful; out of scope here.

### 12.6 `gdd-dungeon-factions.md` (unbuilt)
- Zones and StairwellData are the natural territory/chokepoint units. No action now; noted so the faction design doesn't reinvent them.

### 12.7 Asset/render pipeline (`gdd-dungeon-asset-integration-plan.md`)
- Needs step, ramp, spiral-stair, parapet, and balcony-edge meshes. Rendering is per existing voxel per-level MultiMesh groups; no renderer architecture change.

---

## 13. Deprecations and Rollout (per decision #4)

1. Generator version bumps (`dungeon_generator_version` or equivalent); stored dungeons with the old version are discarded and lazily regenerated on next access (lazy generation is already the runtime model per build log 2026-05-28).
2. `VoxelCell.stair_target_*`, `DungeonMapController.get_stair_target()`, `_apply_stair_overlays`, and the legacy `_convert_legacy_to_voxel` floor-stitcher are removed after the rework's acceptance suite is green. No dual code path is kept.
3. `dungeon_stair_data.gd` (StairData shared type) is replaced by StairwellData; audit importers before deletion.
4. Test dungeons (`test_dungeon.json` "Goblin Warrens" et al.) are re-authored in composed-volume form — hand-authoring one switchback and one 2-story hall in the test content is the cheapest possible integration test bed.

---

## 14. Testing and Acceptance (minimums)

1. **Unit — stair patterns:** each connector type carves its documented cell pattern (§6 tables); traversal both directions passes movement rules; floor integrity holds around every opening.
2. **Unit — zone assignment:** atrium flood-fill yields main + N balcony zones; disconnected same-band galleries get distinct zone_index; single-zone rooms unchanged.
3. **Property test — multi-seed sweep:** re-run the existing 80-dungeon stress sweep (tiers 1-4, 1-4 floors, per V1 §9.2) on the contiguous generator: 100% structural + solvability pass required, plus new checks §10.2(1-4), zero rule-3 structural failures (§10.3), and every band reachable through ≥1 never-secret path.
3a. **Adversarial solvability fixtures (§10.3):** hand-built cases that exercise the repair ladder and invariants — a locked stairwell-room door gating an entire band (key must land on an earlier band); a sole connector whose doors attempt the secret roll (exclusion fires); a two-connector pair where both roll secret (one cleared); a balcony zone gated by a secret+locked door (key placed; reachable); a deliberately disconnected reservation (rule-3 hard fail, not carve); a door cell injected into a run (composer/validator assertion trips).
4. **Stocking regression:** a single-band dungeon stocks byte-identically (same seed → same rolls → same contents) before and after the rework — proves the zone refactor is identity-preserving for the degenerate case.
5. **Integration:** party walks entrance → band −1 via straight run with no teleport call; archer on hand-authored balcony has LOS + cover vs. atrium floor; character stepping off balcony falls 10', takes 1d6 (`rules/acore_combat_and_wounds.xml:797`); fog: balcony cells follow light radius + occlusion only — no reveal from room membership (per Jedidiah's 2026-07-06 ruling; already the `FogRevealEngine` behavior).
6. **Determinism:** fixed request seed reproduces the identical volume (existing V1 guarantee carried forward).

---

## 15. Open Questions / Architectural Concerns

Resolved 2026-07-06:

- **Fog reveal — RESOLVED (Jedidiah):** room-agnostic; light-source radius + occlusion only, never room boundary. The built `FogRevealEngine` already behaves this way (Batch 3 replaced room-scoped reveal); the companion edits align the stale voxel-GDD prose. No engine change required.
- **Schema — APPROVED (Jedidiah):** §9's RoomZone / StairwellData / `zone_index` changes may proceed to migration when the build lands.

Still open:

- **Spiral stair movement clause (§6.3):** one new mover rule (±1 level within a spiral column at normal cost). Cross-system contract touch (movement resolver) — flagged per CLAUDE.md architecture rules even though it is small; approved implicitly with this design but Claude Code should treat the movement-resolver seam with care and test cross-level engagement on spiral cells.
- **Stocking density drift:** per-zone rolls mean a dungeon with atria has slightly more stocked spaces than the same dungeon without. The XP/GP-per-band ledger will show it; no auto-balance (consistent with V1 §13.3's log-don't-balance stance). Flag in playtest telemetry; revisit only if the ledger shows meaningful drift.
- **Above-ground structure types** (Tower, Crumbling castle, Cliff city, Ruined manor): this GDD's machinery handles them (direction = up, footprint constraints per band), but V1 still forces Wizard's Dungeon for everything, so above-ground paths are latent until V2 dungeon types land. Recommendation stands: implement direction handling now (one sign flip), test with a hand-authored fixture, defer generation of those types to V2.
- **Banker's rounding:** no rounding operations are introduced by this GDD (all geometry is integer cells; balcony ring depth and lane widths are direct parameters). Noting for the checklist.
