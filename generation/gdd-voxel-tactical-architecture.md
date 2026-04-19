# GDD: Voxel Tactical Architecture (3D Cube-Cell Migration)

**Authority:** PROJECT-DESIGNED — the voxel grid design, camera/occlusion strategy, and data schema are engineering decisions. ACKS Constraints sections below mark where the rules are sacred.
**Status:** Draft v1.1 — resolves open questions from v1.0 review. Ready for implementation planning.
**Depends on ACKS rules:** `acore_combat_and_wounds.xml` (falling damage, charge rules), `acore_adventures_and_encounters.xml` (air travel, encounter distance), `acore-setting-construction-rules.xml` (pit trap depth per dungeon level), `daw_equipment_and_construction.xml` (structure heights, stories, wall dimensions), `le_wilderness_lair_rules.xml` (burrowing), `acore_proficiencies_rules_and_catalog.xml` (Climbing, Cat Burglary, Mountaineering).
**Depends on project GDDs:** `gdd-combat-map-generation.md` (the current diamond grid / cell / elevation model this replaces), `gdd-dungeon-layout.md` (multi-level generation, stairs), `gdd-stronghold-construction.md` (cell-based walls, interior auto-generation), `gdd-dungeon-map-ui.md` (fog of war, party UI), `gdd-combat-ui.md`, `gdd-trap-generation.md`, `gdd-realtime-scheduler.md` (clock, pause, adjacency timing), `gdd-party-inventory.md` (carrier model, adjacency transfers).
**Modifiable by Claude Code:** Yes — all tables, probabilities, thresholds, shader details, and UI layouts are engineering decisions. The core voxel cell model (§6), the falling damage formula (§11.5), the engagement/adjacency rule (§16.9), and ACKS-sourced heights (§2) are sacred.
**Last updated:** 2026-04-18

---

## 1. Purpose & Scope

The tactical-scale renderer (dungeons and combat maps) migrated from 2D isometric TileMap to 3D isometric mesh rendering in session 2026-04-15 (`tactical_grid_3d.gd`, `dungeon_map_renderer_3d.gd`, `combat_map_renderer_3d.gd`). That migration kept the underlying data model flat — a 2D grid of cells with an integer `elevation` score (0-30, each unit = 2.5 feet) rendered into true 3D space. Walls render as tall boxes, doors as thin slabs, entities as billboarded sprite tokens. Multi-level dungeons remain modeled as an array of separate 2D `TacticalMapData` instances stitched together by stair transition points.

This works today. It breaks when we need:

- **Flying creatures** to occupy airspace above the walkable ground, where ground elevation and flyer altitude are both meaningful independent quantities
- **Burrowing creatures** to move through stone that was previously just the absence of a floor cell
- **Multi-story buildings as a single playable space** instead of two separate "level 1" and "level 2" maps that only communicate through stairs
- **Party members dispersed across floors of a building** during exploration or combat, where the camera must somehow let the player reason about all of them at once

This GDD specifies the migration from a 2D-grid-with-elevation-score model to a **true 3D voxel grid** of 5-foot cube cells. It addresses dungeon rendering, wilderness combat maps, slopes and stairs, all five ACKS movement modes, stronghold construction, vertical traps, line-of-sight, the inventory adjacency rule under real-time-with-pause, and the largest UX problem: **multi-level camera and occlusion when the party is spread across floors.**

This GDD does not redesign the combat engine, the generation pipelines, or the HUD. It redefines the spatial substrate those systems sit on, and specifies how the presentation layer renders it.

---

## 2. ACKS Constraints

These rules are sacred. The voxel model must conform to them, not the other way around.

### 2.1 Vertical Unit Is 5 Feet

ACKS uses 5-foot increments everywhere structural:

| Feature | Height | Source |
|---|---|---|
| Standard dungeon wall / story | 10' (2 cells) | `daw_equipment_and_construction.xml` (Tower: "1 story per 10' of height") |
| Short wall / low parapet | 20' | `daw_equipment_and_construction.xml` walls |
| Standard fortress wall | 20'-60' in 10' increments | Same |
| Standard keep | 80' | Same |
| Siege tower stories | 10' each (standard 40'/4 stories) | Same |
| Pit trap depth | 10' per dungeon level | `acore-setting-construction-rules.xml` (camouflaged pit trap) |
| Arrow-slit frequency | 1 per 5' per story | `daw_equipment_and_construction.xml` wall rules |

**Consequence:** The voxel unit must be 5 feet, because every other ACKS increment is a multiple of 5 feet and no feature is smaller than that. A single 5' cube cell cleanly represents one "slot" in any ACKS construction or trap rule.

### 2.2 Falling Damage Is 1d6 per 10 Feet

From `acore_combat_and_wounds.xml`, mounted-combat section: *"Falling from an aerial mount deals 1d6 damage per 10 feet fallen."* This is the general rule; it is consistent with the camouflaged pit trap rule in `acore-setting-construction-rules.xml`: *"1d6 damage per 10 feet fallen."*

**Consequence:** Falls are measured in 10-foot units. A fall of 2 voxel cells = 1d6. A fall of 8 cells = 4d6. Spike damage or similar riders stack on top of the base fall roll per the trap generator.

### 2.3 Climb Threshold: Sheer Surfaces Require Proficiency/Skill

From `acore_proficiencies_rules_and_catalog.xml`: the Climbing proficiency allows a character to *"climb cliffs, branchless trees, walls, and similar sheer surfaces without climbing aids as a thief of class level."* Non-thieves without the proficiency cannot climb sheer surfaces unaided.

**Consequence:** The engine must distinguish between *walkable slopes* (moved across as normal terrain) and *climbing surfaces* (require the Climb Walls throw or equivalent). A level difference of exactly 1 between adjacent cells (5') is walkable with no cost or throw. A level difference of 2+ (10'+) is a climbing surface requiring the action. See §11.4.

### 2.4 ACKS 1e Does Not Have "Difficult Terrain" as a Movement Concept

ACKS was written with tabletop minis on a flat battlemap. It does not apply movement-cost penalties to slopes or other rough ground. Where it does impose consequences for treacherous footing, it does so via save-vs-Paralysis-or-fall-prone style checks, not via multiplicative movement cost.

**Consequence:** A walkable 1-level slope costs exactly 1 movement point, same as any flat cell. No "2× cost for sloped cells" rule. No "double movement into mud" rule. If surface hazards need representation, they use `feature` flags that trigger save throws (per ACKS), not cost multipliers.

### 2.5 Flying Creatures Have Separate Air and Ground Movement

From the monster catalog, every flying creature has distinct `land` and `fly` exploration/combat movement rates (e.g., roc: land 60'/20', fly 480'/160'). Dive attacks require altitude and open terrain (§2.16 of `monster_system_map.md`).

**Consequence:** Flight is not "ground movement with occasional airspace." It is a movement mode that operates in airspace voxels, with its own cost per cell.

### 2.6 Burrowing Has Two Subtypes

From `monster_system_map.md` §3.4: tunnel-creating burrowers (purple worm, ankheg) leave passable tunnels; earth-passing burrowers (earth elemental, xorn) do not.

**Consequence:** The voxel model must support both — a "burrow through" action that permanently converts solid voxels to air (tunnel creators), and a "pass through solid" flag that lets a creature move through solid voxels without changing them (earth-passers).

### 2.7 ACKS Does Not Define Combat Modifiers for Elevation

Per the Design Decisions section of `gdd-combat-map-generation.md`: *"ACKS 1e does not define explicit bonuses or penalties for elevation in individual combat."*

**Consequence:** The voxel model exists for climbing, falling, line of sight, and visual presentation — not for inventing attack bonuses based on high ground. Do not add a "+1 to hit from elevation" unless ACKS adds one.

---

## 3. Core Decision: 5' Cube Cell Model

The unified spatial unit becomes a **5-foot cube**. Every cell is 5' wide, 5' deep, and 5' tall.

- **Horizontal grid:** Unchanged — diamond grid, `(col, row)` integer coordinates, 5' × 5' footprint, same isometric projection math that `IsometricGrid` / `TacticalGrid3D` already use.
- **Vertical grid:** NEW — integer `level` coordinate. Level 0 is a canonical "ground plane" per map. Positive levels extend upward (upper floors, airspace). Negative levels extend downward (basements, subterranean).

This replaces the current `elevation: int 0-30` (each unit = 2.5 feet) model. The resolution drops by half, which is an acceptable loss: ACKS never uses a 2.5-foot increment for any structural feature. Wilderness "gentle undulation" is handled visually (§10), not by half-cell elevation.

### 3.1 Scale Mapping

| Quantity | Unit | World Unit (Godot) |
|---|---|---|
| 1 cell (all three axes) | 5 feet | 1.0 |
| Standard wall height | 10 feet / 2 cells | 2.0 |
| Standard story height | 10 feet / 2 cells | 2.0 |
| Tower (30') | 6 cells | 6.0 |
| Keep (80') | 16 cells | 16.0 |
| Fall threshold for 1d6 | 10 feet / 2 cells | — |

### 3.2 The "Typical Wall" Pattern

A standard dungeon wall section is **1 cell wide × 2 cells tall** — exactly two stacked solid voxels = 10 feet. This is the default for:

- Any ACKS dungeon corridor wall
- Interior stronghold walls (keep interior, building interior)
- Any 10'-ceiling location

Taller walls stack more solid cubes: a 20' exterior fortress wall = 4 cubes tall, a 40' tower wall = 8 cubes tall.

### 3.3 Grid Basis Decision: Diamond Retained

The horizontal grid stays diamond-based, not square. Rationale:

- Visual output is identical either way (both render as isometric diamonds on screen)
- `IsometricGrid` is load-bearing across the codebase with 16 passing tests
- No pathfinding library in use (`AStar2D`, `AStar3D`, and hand-rolled BFS are all coordinate-basis-agnostic)
- `AStarGrid2D` is referenced only as "optional, for connectivity validation" in `gdd-dungeon-layout.md` §13.2 and has never been instantiated
- Switching would invalidate tests, JSON test dungeons, and the multi-level controller for zero gameplay benefit

The existing `(col, row)` semantics extend naturally to `(col, row, level)`; no basis change is required.

---

## 4. Floor Model Decision

> **The question:** should a floor between two dungeon/building levels be (a) a simple 2D no-pass barrier, or (b) a full 5' cube impassable block like walls, just with the players on top?

**Neither, exactly — floors are a boolean property of a voxel cell, not a separate full cube.**

### 4.1 Why Not Full-Cube Floors (Option b)

A full 5' cube floor between stories means: air cube (ceiling headroom) → floor cube → air cube (next story headroom) → floor cube → ... A 10' ACKS story would need 3 cells vertical (air + floor + air). Two-story keep at 20' = 5 cells. A 10-story tower at 100' = 21 cells. This breaks the "10' story = 2 cells" clean mapping and wastes 50% of vertical cell count on slab cubes.

Worse, it forces an awkward choice every time a wall is placed: does a 10' wall mean 2 cubes (story height) or 3 cubes (story + floor)? The ACKS rule "1 arrow slit per 5' per story" now divides by 3 instead of 2.

### 4.2 Why Not Pure 2D Barrier (Option a)

A 2D barrier between levels works for the top face of one cube / bottom face of the cube above it, but it creates an ambiguity: where does an entity "stand"? If the barrier is between cells, an entity at (col, row, level=1) is literally inside a 5-foot cube of air, floating somewhere. The renderer must pick a convention (feet at the bottom face) and every subsystem must agree.

### 4.3 The Chosen Model: Floor as Cell Property

Each voxel cell stores a **`floor_type`** field. The floor is conceptually at the bottom face of the cube (where an entity's feet would rest). The thickness is negligible for mechanical purposes — no cell is "consumed" by the floor.

- A normal ground-floor dungeon cell is `solidity: air, floor_type: stone` — an entity stands on the stone floor inside a 5' air cube.
- A normal second-story cell directly above is `solidity: air, floor_type: wood` — the wooden floor of the upper story.
- A cell in an open atrium with no floor at that level is `solidity: air, floor_type: none` — an entity here is in open airspace; ground-walkers cannot occupy it; flyers can.
- A "ceiling" is implicit: the `floor_type` of the cell directly above. A room with a vaulted 20' ceiling is a cell at `level=0` with `floor_type: stone`, plus three cells stacked above it all at `floor_type: none`, with the cell at `level=4` having `floor_type: stone` (the next story's floor is this room's ceiling).

**Trapdoors, grates, pit covers, and collapsing floors are all transitions of this single `floor_type` property.** See §14.

### 4.4 Rendering

The renderer draws a thin slab mesh at the bottom face of any cell where `floor_type != "none"`. Slab thickness is visual-only (~0.05-0.10 world units = 3-6 inches). The slab's surface material is keyed off `floor_type` (wood, stone, grate, pit_cover, trap_door).

This produces the visual consumers expect — you see a floor under your feet — without spending a voxel on the floor's physical volume.

---

## 5. Inventory & Carrier Adjacency Under Real-Time-with-Pause

The voxel migration forces a long-pending question to resolve: how does "shared party inventory" work when party members can be on completely different floors? The answer, compatible with the existing carrier-and-adjacency stubs in the validator, is to drop the unified-pool fiction during tactical play and enforce adjacency at the moment of transfer.

### 5.1 Carriers Only

All items reside on a **carrier** — a specific entity at a specific `Vector3i(col, row, level)`:

- A party member's backpack
- A pack animal (mule, donkey, horse)
- A draft vehicle (wagon, cart)
- A dropped container on the floor (chest, sack, corpse)

There is no abstract "party pool" during dungeon exploration or combat. The UI concept of a "party inventory pane" is preserved as a **filtered view** (§5.4), but the underlying data is always per-carrier.

### 5.2 Adjacency Rule

Two carriers are **adjacent** if they are at 3D Chebyshev distance ≤ 1: `abs(c1.col - c2.col) ≤ 1 AND abs(c1.row - c2.row) ≤ 1 AND abs(c1.level - c2.level) ≤ 1`. This is the same rule used for engagement (§16.9), so there is exactly one adjacency check in the codebase.

A transfer is legal only between adjacent carriers. Cross-floor transfers require at least one carrier to move to a cell adjacent to the other (e.g., a party member walking up the stairs to meet another on the level above).

### 5.3 Timing Under the Scheduler

The project uses a real-time-with-pause clock (`gdd-realtime-scheduler.md`). There are no player-facing "end turn" buttons in dungeon exploration. Adjacency timing adapts:

- **Exploration mode (clock running or paused, not in combat):** a transfer request is validated against the carriers' positions *at the moment of the request*. Legal transfers are instantaneous and free-action. If positions have since drifted and the transfer is no longer adjacent, the request fails with a toast notification explaining why.
- **Combat mode (turn-based sub-game):** a transfer costs one action on the transferor's combat turn. This is exactly what `_check_combat_trade_action()` exists to enforce — the stub can now do its job because grid positions are first-class.
- **Hand-off during movement:** if two party members' paths cross or pass adjacent during scheduler ticks, the transfer is legal during those ticks. No special "conga line" logic is needed; adjacency just happens to be true at that moment.

### 5.4 Filtered Inventory View

The existing inventory UI stays. Its internals change:

- The UI subscribes to position-change signals (`party_moved`, `entity_moved`, whichever the renderer / controller emits each tick).
- On signal, recompute the adjacency set for the currently-selected character: which other carriers are at Chebyshev distance ≤ 1?
- The inventory pane shows items from those carriers, grouped by carrier with the carrier's name as a section header.
- Items on non-adjacent carriers simply do not appear. They will reappear when the carriers come back into range.

At 25-unit max party size, this is O(N²) in the worst case and still trivial — a handful of microseconds per tick.

### 5.5 Loot, Drops, and Containers on the Floor

A dropped container (chest, loot pile) is a carrier whose `Vector3i` position is a specific cell. It has infinite capacity (for gameplay purposes) and a "container" flag. Adjacency rules apply the same way — you must stand next to (or on) the cell to loot it.

The existing loot distribution modal (flagged as Session 4 work in your build log) runs at combat end. Under the adjacency rule, participants are: every living party member currently at Chebyshev distance ≤ 1 from the loot cell. Distant party members miss out unless they physically return to the loot cell.

### 5.6 Manual Rebalance Button

A UI button — "Rebalance Load" — finds the currently-adjacent cluster of party carriers and redistributes loose items to balance encumbrance. It is strictly manual; there is no automatic rebalance at scheduler ticks. The player chooses when to invoke it.

### 5.7 What to Wire

This section primarily formalizes what your existing validator stubs were waiting for. In `test_party_inventory_transfer_validator.gd` there are already tests for coin locks, clothing locks, carrier-type restrictions, and context friction. The dungeon-adjacency stub (`_check_dungeon_adjacency()` always returns ok) and the combat-trade-action stub (`_check_combat_trade_action()` always returns ok) become real checks against `Vector3i` positions. No new validator is needed — the existing one gets its spatial input connected.

---

## 6. Coordinate System & Data Migration

### 6.1 New Coordinate Conversion

Replace the current `TacticalGrid3D.cell_to_world(col, row, elevation)` signature:

```gdscript
# OLD (elevation score, each unit = 2.5 ft)
static func cell_to_world(col: int, row: int, elevation: int) -> Vector3:
    var x := (col - row) * 0.5
    var z := (col + row) * 0.5
    var y := elevation * 0.5   # ELEVATION_SCALE = 0.5 per unit
    return Vector3(x, y, z)

# NEW (integer level, each level = 5 ft)
static func cell_to_world(col: int, row: int, level: int) -> Vector3:
    var x := (col - row) * 0.5
    var z := (col + row) * 0.5
    var y := level * 1.0       # Each level is a full cell (5 ft)
    return Vector3(x, y, z)
```

Constants:

```gdscript
const CELL_SIZE := 1.0         # 5 feet, all three axes
const WALL_HEIGHT := 2.0       # 10 feet (2 cells) — legacy helper only;
                               # walls are now stacks of solid cells, not tall boxes
```

`WALL_HEIGHT` becomes a deprecation target. The old renderer drew each wall as one tall BoxMesh. The new renderer draws walls as stacks of 1×1×1 MultiMesh instances (one per solid cell). This is uniform across walls, columns, pillars, and any other solid voxel.

### 6.2 Entity Position

Entity world positions change from `(Vector2i col_row, int elevation)` to `Vector3i(col, row, level)`. A smooth movement tween still uses `Vector3` for interpolation; the logical position is always a `Vector3i` snapped to the voxel grid.

Characters, monsters, light sources, and traps all adopt the same coordinate triple.

### 6.3 Database Schema Changes

Migration from the current `dungeon_map_cells` table (D-4, migration 017):

```sql
-- OLD:
-- dungeon_map_cells (dungeon_id, level_num, col, row, door_state, fog_state)

-- NEW migration (TBD number):
-- Sparse storage: one row per non-default voxel cell
CREATE TABLE voxel_map_cells (
  map_id TEXT NOT NULL,
  col INTEGER NOT NULL,
  row INTEGER NOT NULL,
  level INTEGER NOT NULL,       -- integer voxel y-coordinate
  solidity TEXT NOT NULL,       -- "air" | "solid" | "liquid"
  feature TEXT NOT NULL,        -- terrain feature string
  floor_type TEXT NOT NULL DEFAULT 'none',
  door_state TEXT NOT NULL DEFAULT '',
  fog_state TEXT NOT NULL DEFAULT 'hidden',
  PRIMARY KEY (map_id, col, row, level)
);
```

The `parties` table's existing `dungeon_level INTEGER` column carries forward with the same meaning (integer level), but now the levels are stacked in a single map rather than split across separate `TacticalMapData` instances.

Migration is lossless if executed as: for every (dungeon_id, level_num, col, row) row in the old table, emit a new row with `level = level_num * 2` (old level_num was "story index," new level is "5-foot vertical index"). The factor of 2 reflects that each ACKS story is 2 cells tall in the new model.

Fog of war and door state carry over directly.

### 6.4 Sparse Cell Storage

In-memory, cells are stored as `Dictionary[Vector3i, VoxelCell]`, not a dense 3D array. A 100×100 wilderness map with 20 levels of airspace would naively allocate 200,000 cells, the vast majority of which are featureless air. Sparse storage only allocates cells that differ from the default (air with `floor_type: none`). Typical dungeon: 1,500-3,000 stored cells per level × 3-6 levels = 5,000-20,000 entries. Typical outdoor map: 10,000-20,000 stored cells (ground floor dominant; air layers stored only where flyers or features exist).

Lookups are O(1) hash access. Absent keys return a sentinel "empty air, no floor, no feature" cell. No null handling needed at call sites.

---

## 7. The Unified Voxel Cell Schema

Rename `CellData` → `VoxelCell`. This replaces both the existing 2D `TacticalMapData` cell storage and the per-level `_all_levels` dictionary in `DungeonMapController`.

```gdscript
class_name VoxelCell
extends RefCounted

# Spatial identity
var col: int
var row: int
var level: int                   # integer vertical cell index

# What's in this cube
var solidity: String = "air"     # "air" | "solid" | "liquid"
var feature: String = "open"     # terrain vocabulary (see below)
var floor_type: String = "none"  # "none" | "stone" | "wood" | "grate" | "pit_cover" |
                                 #   "trap_door" | "rubble" | "ice" | "grass" | "dirt" | ...

# Door state
var door_state: String = ""      # "" | "open" | "closed" | "locked" | "stuck"
var door_type: String = ""       # arch | unlocked | locked | trapped | secret | portcullis
var door_detected: bool = false

# Dungeon/room metadata
var room_id: int = -1
var is_corridor: bool = false

# Fog of war
var fog_state: String = "hidden" # "hidden" | "explored" | "visible"

# Cover & combat
var cover_value: int = 0         # 0-4, ACKS cover rules

# Derived properties (computed on read, not stored)
func is_passable_by_walker() -> bool:
    if solidity != "air":
        return false
    if door_state == "closed" or door_state == "locked" or door_state == "stuck":
        return false
    return true  # support check is done by the pathfinder, not here

func blocks_los() -> bool:
    if solidity == "solid":
        return feature != "arrow_slit" and feature != "window" and feature != "portcullis"
    if door_state == "closed" or door_state == "locked":
        return door_type != "portcullis"
    return false

func blocks_flight() -> bool:
    return solidity == "solid" or door_state in ["closed", "locked", "stuck"]

func blocks_burrow() -> bool:
    return solidity == "air"
```

### 7.1 Feature Vocabulary Additions

| Feature | Solidity | Floor Type | Notes |
|---|---|---|---|
| `"open"` | air | (varies) | default walkable cell |
| `"rock"` | solid | none | solid earth/rock, subterranean dungeon walls |
| `"wall_stone"` | solid | none | above-ground stone wall |
| `"wall_wood"` | solid | none | wooden structure wall |
| `"pillar"` | solid | none | single-cell columnar support |
| `"stairs_up_N"` ... `"stairs_down_SW"` | air | stone | stair cell, connects to adjacent cell at level±1 per direction suffix (§9) |
| `"ramp_N"` ... | air | dirt | gradual slope cell, connects adjacent cell at level±1 |
| `"ladder"` | air | none | vertical ladder, allows climbing without a proficiency throw |
| `"window"` | solid | none | wall cell allowing LOS & ranged attacks but not movement |
| `"arrow_slit"` | solid | none | like window but small; LOS + ranged attack, not movement |
| `"murder_hole"` | solid | none | floor feature on gatehouse upper story; LOS/attack down, no movement |
| `"water_shallow"` | liquid | none | wadeable |
| `"water_deep"` | liquid | none | requires swim movement |
| `"air_open"` | air | none | airspace — flyers only, no support |
| `"burrow_tunnel"` | air | none | tunnel left by tunnel-creating burrower |

(String-typed and open-ended, per existing project convention; no CHECK constraint.)

---

## 8. Walls in the Voxel Model

Replace the current "wall = cell with impassable terrain_feature + tall BoxMesh" model with "wall = stack of `solidity: solid` cells, rendered per-cube."

### 8.1 Wall Construction Rules

| Wall Height | Voxel Count per 5' Run | Rendering |
|---|---|---|
| 10' standard (1 story / dungeon) | 2 solid cubes stacked | MultiMesh, 2 instances |
| 20' (short fortress / 2-story) | 4 solid cubes stacked | MultiMesh, 4 instances |
| 30' (standard tower) | 6 solid cubes stacked | MultiMesh, 6 instances |
| 40'-60' (heavy fortress) | 8-12 solid cubes stacked | MultiMesh |
| 80' (max keep) | 16 solid cubes stacked | MultiMesh |

### 8.2 Openings (Windows, Arrow Slits, Murder Holes)

These are solid cells with special `feature` values that override LOS/attack rules without changing solidity. A cell with `feature: "arrow_slit"` is still `solidity: solid` (no movement through), but `blocks_los()` returns false for ranged LOS originating from an attacker in an adjacent interior cell. This matches ACKS "1 arrow slit per 5' per story" — each slit is one voxel on the appropriate story level.

### 8.3 Wall Adjacency Rendering (Optional, Future)

For visual polish, the renderer can optionally compute exposed-face meshes: if a solid cell is adjacent to air cells on some faces, only those faces need to be drawn. This is the standard Minecraft-style chunk meshing optimization. Not required for v1 — the MultiMesh-instance-per-cube approach is fast enough at the scale of ACKS dungeons.

### 8.4 Removing the `WALL_HEIGHT` Constant

The current `TacticalGrid3D.WALL_HEIGHT = 2.0` constant, and all mesh-builder code that draws walls as tall BoxMeshes, becomes obsolete. Wall meshes are now 1×1×1 cubes and the wall's shape comes from how many cells are flagged `solid`. Legacy callers should be audited and removed.

---

## 9. Floors, Ceilings, and Vertical Transitions

Per §4, floors are the `floor_type` property on a voxel cell. There is no standalone "floor" cell.

### 9.1 Ceilings Are Implicit

A cell's ceiling is the `floor_type` of the cell directly above it. A ground-floor dungeon room with a 10' ceiling has:

- Cell (c, r, 0): `solidity: air, floor_type: stone` — the floor
- Cell (c, r, 1): `solidity: air, floor_type: none` — mid-room airspace
- Cell (c, r, 2): `solidity: air, floor_type: stone` — the ceiling (which is the next story's floor, or a cap)

For a vaulted 20' room, replace level-2 with `floor_type: none` and add a level-4 cap. For an outdoor wilderness map, no cap exists — airspace continues indefinitely upward, represented as absent cells in the sparse storage.

### 9.2 Support Checking

A ground walker standing at (c, r, L) needs support. The pathfinder/mover checks:

1. The cell's `floor_type != "none"` (floor under the walker's feet), OR
2. The cell directly below (c, r, L-1) is `solidity: solid` (standing on top of a solid wall/pillar), OR
3. The walker is attached to a ladder/rope/climbing feature.

If none of these hold and the walker is not a flyer or climber, the walker falls (§11.5).

### 9.3 Multi-Story Building Example

A 3-story keep interior, one 5'×5' column of voxels at some (c, r):

| Level | Solidity | Floor Type | Meaning |
|---|---|---|---|
| 0 | air | stone | ground floor, stone floor |
| 1 | air | none | headroom for ground floor |
| 2 | air | wood | 2nd floor, wooden floor |
| 3 | air | none | headroom for 2nd floor |
| 4 | air | wood | 3rd floor, wooden floor |
| 5 | air | none | headroom for 3rd floor |
| 6 | solid | — | solid roof cell (OR `air` with `floor_type: stone` for a battlement top) |

---

## 10. Stairs, Ramps, and Slopes

Stairs and ramps are **air cells** with a special `feature` value that permits movement between that cell and one adjacent cell at `level ± 1`. They are the voxel-model replacement for the existing stair-pairs in `gdd-dungeon-layout.md` §9.

### 10.1 Stair Cell Direction Suffix

A stair cell's `feature` encodes which adjacent cell it connects to at the other level:

- `stairs_up_N` = stairs rising northward; entering from the south at level L exits at the north-adjacent cell at level L+1
- `stairs_down_N` = stairs descending northward; entering from the south at level L exits at the north-adjacent cell at level L-1

By ACKS convention, a flight of stairs is 10' long and rises 10' — so a single `stairs_up_N` voxel cell is a 5' step, and a real 10' staircase is 2 stair cells in sequence (e.g., `stairs_up_N` at (c, r, 0) and `stairs_up_N` at (c, r+1, 1)). For simplicity the generator can treat both cells as one "logical staircase" feature and compose them automatically.

### 10.2 Ramps

Identical to stairs in mechanics, different in `feature` name (`ramp_N`, `ramp_E`, etc.) and visual rendering.

### 10.3 Slopes in the Wilderness

Wilderness "rolling hills" handled by the current elevation score (±1-3 units = ±2.5'-7.5' subtle undulation) are **not preserved** in the migration. The new model is strictly 5' increments. Gentle undulations become visual-only: the mesh builder for outdoor cells can offset the floor slab vertically by up to ±0.4 world units (inside the voxel's 1.0 unit height) for visual interest, without changing the logical cell-level integer. This is similar to the FFT cliff-face rendering approach but at sub-cell scale.

For mechanical terrain, the rule per §2.4 (ACKS has no difficult-terrain concept):

| Adjacent Cell Level Difference | Movement |
|---|---|
| 0 levels (same) | Normal, 1 movement point |
| 1 level (5' up or down) | Normal, 1 movement point — walkable slope. No cost penalty. |
| 2+ levels (10'+) | Not walkable — requires Climb action (§11.4), fly, burrow, or go around |

No cost multiplier for slopes. No "difficult terrain." If a surface is treacherous (ice, scree), that's encoded as a `feature` value that triggers a save-vs-Paralysis-or-fall-prone per ACKS convention, not as a movement-cost multiplier.

### 10.4 Stair Transitions Replace the Old `StairData`

The existing `stairs: Array[StairData]` in the multi-level dungeon JSON format dissolves. Stairs are now just cells with stair `feature` values, and the party moves to them and through them like any other adjacent cells. The `DungeonMapController.use_stairs(pos)` method becomes a general "move to adjacent cell at different level" operation, which is the same as any movement, so the special-case method goes away.

---

## 11. Movement Modes

### 11.1 Ground Movement

Default for all non-flying, non-burrowing creatures. The mover checks:

1. The destination cell is `solidity: air` (or liquid for wading/swimming subtypes)
2. The destination cell has support (§9.2)
3. No closed door / wall / locked portcullis blocks the path
4. Level difference between source and destination is 0 or 1 AND one of the cells has an appropriate `ramp_` / `stairs_` feature when the difference is 1

Movement cost: 1 per step regardless of direction (flat, slope, stairs all cost the same). Per ACKS, no difficult-terrain multipliers.

### 11.2 Flying

A creature with a `fly` movement mode uses its fly rate instead of land rate. Flight movement:

1. Can enter any cell with `solidity: air`, regardless of support
2. Cannot enter `solidity: solid` cells or closed doors
3. Each cell-step (horizontal or vertical) costs one unit of fly rate
4. Diagonal vertical movement (e.g., NE and up) costs 1.5 units (banker's rounded — use `roundi()` per project convention)

**Altitude tracking:** A flyer's altitude is `flyer.level - ground_level_at_current_(col,row)`. Dive attacks require altitude ≥ 2 levels (10'+) above the target, per monster_system_map §2.16.

**Dispel interaction:** If a flyer is dispelled mid-combat, they begin falling from their current airspace cell. Apply falling damage per §11.5.

### 11.3 Burrowing

Two variants, matching `monster_system_map.md` §3.4:

**Tunnel-creating burrowers** (purple worm, ankheg):
- Move through `solidity: solid` cells at their burrow rate
- When they leave a cell, that cell changes: `solidity: solid → solidity: air, feature: "burrow_tunnel"`. Subsequent non-burrowers can walk through these tunnels.
- Tunnels persist indefinitely unless the dungeon layout regenerates (it doesn't during play).

**Earth-passers** (xorn, earth elemental):
- Move through solid cells without changing them
- Functionally teleport through solid rock at their burrow rate
- Not targetable by melee while inside solid cells; limited targeting from adjacent air cells per monster rules

Modeled as `entity.can_burrow_earth_pass: bool` plus `entity.can_burrow_tunnel: bool` flags. A creature with `tunnel = true` runs the "convert solid to air on exit" callback; a creature with `earth_pass = true` simply treats solid as passable for its own pathing.

### 11.4 Climbing

A non-flying, non-burrowing creature attempts to move into an air cell that has no support AND is adjacent to a solid wall face. This is a climb attempt:

- Thief-class: Climb Walls skill throw at class level
- Any class with Climbing proficiency: throw as a thief of class level
- Any other class: generally fails; may make an attribute check at Judge discretion per ACKS
- Ladder cells (`feature: "ladder"`) are auto-climbable: no throw required, movement rate is halved during climbing

If the throw succeeds, the creature occupies the target air cell (one cell per round of climbing per ACKS). If it fails, Cat Burglary proficiency allows a second throw at -4 to catch themselves; otherwise they fall per §11.5.

### 11.5 Falling

A ground-walker ends a turn or is knocked into a cell without support. The engine:

1. Scans downward from the current cell: for each level L-1, L-2, ..., check whether the cell at (col, row, L-k) provides support (its `floor_type != "none"` OR its `solidity == "solid"`).
2. The creature falls to the first cell that provides support (or terminates at the bottom of the map).
3. Fall distance in feet = (starting_level - landing_level) × 5.
4. **ACKS damage: `floor(fall_feet / 10) × d6`.** A 5' fall = 0d6 (no damage). A 10'-19' fall = 1d6. A 20'-29' fall = 2d6. A 100' fall = 10d6.
5. Spike damage riders (pit trap with spikes) add 1d6 per spike per ACKS §2 and `gdd-trap-generation.md`.

A flying creature that is dispelled/grounded mid-air falls the same way, starting from its current airspace cell.

### 11.6 Diagonal Vertical Movement

Any movement that changes both horizontal position AND level in the same step:

- **Ground walker on a stairs/ramp:** pay 1 movement cost for the combined step
- **Climbing creature (e.g., giant spider) on a vertical face:** moves at its climb rate, one cell per step, treating vertical and horizontal moves on the face as the same cost
- **Flying creature:** a pure diagonal (NE + up) costs 1.5 fly units, banker's-rounded to 2 for the turn
- **Falling creature:** falls take the vertical leg only; no horizontal displacement during the fall

---

## 12. Dungeon Model: From Two-Layer to True 3D

### 12.1 Current Model (Obsolete)

`DungeonMapController._all_levels: Dictionary[int → TacticalMapData]`. Each level is a completely independent 2D grid; moving between levels is a special `use_stairs()` operation that swaps which `TacticalMapData` is active. The scene tree contains only one level at a time; the other levels aren't rendered.

### 12.2 New Model (Voxel Single-Map)

A dungeon is a single `VoxelMapData` containing cells indexed by `Vector3i(col, row, level)`. Multi-level dungeons are a single coordinate space. The generator still operates per-level internally — each level is generated as a 2D pattern, then stamped into the voxel grid at the appropriate `level` coordinate — but the output is unified.

### 12.3 Renderer Changes

`dungeon_map_renderer_3d.gd` and `combat_map_renderer_3d.gd` both consume `VoxelMapData`:

- Per-level MultiMeshInstance3D groups, one per `y` layer. Each group contains the floor slabs, walls, doors, and features for that level.
- Entity tokens positioned at `Vector3(cell_to_world_x, (level + 0.2) * CELL_SIZE, cell_to_world_z)` — the +0.2 places the token slightly above the floor slab so billboards don't z-fight.
- The camera always sees all currently-visible levels (controlled by the Visibility Manager, §16).

### 12.4 Fog of War Per Level

Fog state stays per-cell (already the model). Room-scoped reveal from `gdd-dungeon-map-ui.md` §6.2 still applies: entering a room on level 2 reveals level-2 cells in that room. Level 1's fog is unaffected.

Consequence: a party split across levels has DIFFERENT fog visibility on DIFFERENT levels. The camera needs to show this correctly (§16.5).

### 12.5 Migration of `test_dungeon.json`

The test "Goblin Warrens" dungeon has 2 levels. Under the new model, its JSON format simplifies:

```json
{
  "id": "goblin_warrens",
  "name": "Goblin Warrens",
  "theme": "humanoid_warren",
  "entry": {"col": 3, "row": 4, "level": 0},
  "cells": [
    { "col": 3, "row": 4, "level": 0, "solidity": "air", "feature": "stairs_up_S",
      "floor_type": "stone", "room_id": 1 },
    ...
  ]
}
```

The separate `levels[]` array and `stairs[]` array go away. Stair cells are inline with other cells.

---

## 13. Stronghold Construction in Voxels

### 13.1 Walls Become Cell Stacks

`gdd-stronghold-construction.md` §4 already specifies cell-based walls ("A 5' wall is 1 cell thick; a 10' wall is 2 cells thick"). The voxel model extends this vertically: a 40' wall is 8 cells tall. The wall preset tables in §4.2 of that GDD update their "Grid Footprint" column to an additional row count for vertical cells.

### 13.2 Towers Become Voxel Columns

A 30' tower (small round) at 20' diameter: 4×4 circular horizontal mask, 6 cells tall = 96 solid cells on the shell (only the shell, not the interior). Each of the 6 stories = 2 cells of interior airspace.

Interior auto-generation (§8.6 of stronghold GDD) updates: each story is a single-room interior at the tower's level band (levels 0-1 = ground floor, levels 2-3 = 2nd floor, etc.).

### 13.3 Keeps and Buildings

Multi-story buildings gain natively — each story is a level band of 2 cells vertical. The auto-generated interior rules from stronghold GDD §8.6 translate directly: ground-floor great hall is a wide air region at levels 0-1 with `floor_type: stone` on level 0 and `floor_type: none` on level 1; second floor is levels 2-3 with `floor_type: wood` on level 2.

Internal stairs are stair-cell features at the connection between stories.

### 13.4 Stronghold Planner UI Changes

The G-10 stronghold planner's grid view (currently a 2D top-down grid) gains:

- A **level selector** — defaults to ground floor (level 0), can switch up or down
- **Level-specific editing** — placing a structure at a non-ground level adds to that level; default behavior for taller structures (walls, towers) remains "place on ground + extrude up"
- **Cross-section preview** — a side/isometric view showing all levels of the design at once (this is essentially a mini version of the combat/dungeon view using the same renderer)

### 13.5 Battle Map Integration

The stronghold's `battle_map_cells: Array[Array[CellData]]` flat 2D grid (§9.1 of stronghold GDD) becomes a 3D `VoxelMapData`. When a stronghold is attacked, it IS the battle map directly — no conversion step. This was always the intent; the voxel model just makes it uniform across levels.

---

## 14. Vertical Traps

All trap types from `gdd-trap-generation.md` §6 operate on voxel cells. The vertically-oriented traps each become clean state transitions on `floor_type` or `solidity`.

### 14.1 Pit Trap

- Setup: Cell (c, r, L) has `floor_type: "pit_cover"`, and the cell below at (c, r, L-1) has `solidity: air, floor_type: none`. If the pit is 2 cells deep (20' = dungeon level 2), the cells at L-2 may also be air.
- Trigger: weight or pressure (from `gdd-trap-generation.md` §5.2).
- On trigger: cell (c, r, L).`floor_type` transitions to `"none"`. Any entity currently in that cell with no other support falls per §11.5. Spikes at the bottom of the pit add 1d6 each.
- Post-trigger state: the cell's `floor_type` stays `"none"` — the pit is open permanently (single-use trap).

### 14.2 Trap Door

Functionally identical to a pit trap but intended — a known intentional opening in the floor, often with a mechanism to open and close it.

- Setup: `floor_type: "trap_door"` on cell (c, r, L)
- States: closed (walkable) and open (air below, entity falls through)
- Can be opened/closed manually by an entity in an adjacent cell, or by a mechanism/lever

### 14.3 Collapsing Ceiling

- Setup: Cell (c, r, L+1) at the ceiling of a room has `solidity: solid` or `floor_type: stone`. A trap trigger is armed in the room below.
- On trigger: the solid cells above convert to `solidity: air, feature: "rubble"` (or stay solid if the floor/ceiling itself is the debris). Entities below take crushing damage per `gdd-trap-generation.md` §6.2.
- Post-trigger: cells may be impassable (`feature: "rubble"` at ground level, difficult to traverse; large piles can become `solidity: solid`).

### 14.4 Rising Floor / Crushing Ceiling

- Setup: a lever or timer starts the effect. Cell (c, r, L+3), previously `solidity: air`, starts descending.
- On each scheduler tick: the cells between creature and descending surface compress by 1 level until contact. Creature must escape or take crushing damage.

### 14.5 Illusory Floors

A cell with `floor_type: "pit_cover"` (or a themed equivalent) that looks like standard floor to the player. The cell below is air. Normal fog/rendering shows nothing unusual. Detection follows `gdd-trap-generation.md` detection rules; successful detection adds a tooltip/hatching to the cell.

---

## 15. Line of Sight and Visibility

LOS uses a true 3D raycast. The raycaster walks a 3D DDA (Digital Differential Analyzer) between the source cell center and the target cell center, checking each cell along the line:

1. If any intermediate cell has `blocks_los() == true`, LOS is blocked
2. Elevation is free — the ray naturally passes over lower obstacles if the source is high enough
3. `cover_value` from intervening cells aggregates per ACKS cover rules

Performance: for a 100×100×20 voxel map, worst-case LOS between opposite corners is ~120 cells of ray traversal. Negligible for combat-frequency calls.

### 15.1 Flying Creature LOS

Flyers see over walls naturally because their source cell is elevated. This is the reason the data model needs a true 3D LOS and not a 2D-with-elevation-peek approximation — a flyer at level 6 (30' up) looking at a ground target behind a 20' wall should have LOS, and the straightforward 3D raycast makes this automatic.

### 15.2 Fog of War Reveal

A creature at (c, r, L) with a light radius R reveals cells within R cells (3D Chebyshev — simpler and already consistent with existing movement reach). Room-scoped reveal on entering a dungeon room still applies, scoped to the room's `room_id` across all cells belonging to that room regardless of their level.

### 15.3 Multi-Level Fog

A multi-story room (cells across multiple levels sharing a `room_id`) can have different fog states on different levels. In practice: if the party enters level 0 of a great hall, level-0 cells in that room go from HIDDEN to VISIBLE. Level-1 cells (the empty airspace above) stay HIDDEN unless the party actively flies or is seen from above. This matters for balcony/gallery layouts — you can see into a room from a balcony without revealing the balcony itself.

---

## 16. Camera and Occlusion Across Multi-Level Parties

The largest UX problem the migration creates. The user example: **"John is on Floor 1, Bob is on Floor 2, Gary is on Floor 4."** The camera must let the player reason about, command, and view all three simultaneously without hiding anyone permanently, getting lost in fog-of-war darkness, or rendering all floors as a tangled opaque mess.

The design below borrows from XCOM (Enemy Unknown and XCOM 2), Jagged Alliance 3, Baldur's Gate 3, and Divinity: Original Sin 2 — all of which have tried-and-debated solutions to this exact problem.

### 16.1 The Focus Level Concept

At any moment, the camera has a single **focus level** — the voxel y-layer the camera is "currently at." All rendering decisions cascade from this focus level.

- Default on entering a map: focus = the level of the party leader
- Auto-switch on selection: clicking a party member sets focus = that member's level
- Manual control: PgUp / PgDn cycles focus up/down one level at a time
- Fast jump: clicking a party-member portrait on the HUD (existing widget) jumps focus to their level
- A HUD widget in a screen corner shows "Focus: Level N" with clickable up/down chevrons and a list of levels that contain party members, enemies, or revealed structure

### 16.2 Per-Level Visibility Strategy

With the focus level set, each voxel y-layer renders with a different strategy. The Visibility Manager (§17.2) applies these rules:

| Layer | Rendering |
|---|---|
| `level > focus + 1` | Hidden (not rendered at all). Saves GPU, avoids clutter. |
| `level == focus + 1` | Dithered transparency shader (see §16.3). Can see through it but silhouette is legible. |
| `level == focus` | Fully opaque, full color, primary illumination |
| `level < focus` | Fully opaque but dimmed (multiply by 0.6 brightness). Provides spatial context without pulling attention. |

Exceptions:
- **Completely-explored open-air / outdoor maps:** no ceiling, no upper levels to hide. Strategy reduces to just the "below focus" rule.
- **Party members on non-focused levels:** their tokens ALWAYS render at full opacity, regardless of the level's transparency. Otherwise Bob vanishes when you focus-switch to Gary's floor.
- **Enemies revealed on non-focused levels:** render at half opacity with a colored outline (e.g., red) so the player is aware of them.

### 16.3 Shader-Based Dithered Occlusion

For the `level == focus + 1` layer, use Godot's `StandardMaterial3D.distance_fade_mode = DISTANCE_FADE_PIXEL_DITHER`. This is a screen-door dither that plays well with depth testing (unlike alpha blending) and costs nearly nothing performance-wise. Configure fade based on a uniform that the Visibility Manager updates each frame with the current focus level.

If the dither composes poorly with the cel-shaded art direction (a known risk, per the current presentation docs that standardize on flat unshaded materials), the documented fallbacks in order of preference are:

1. **Hard clip plane (BG3 approach).** Just set `Level_N.visible = (N <= focus_level)`. Loses the silhouette context, but the Level Strip Widget (§16.4) provides that info anyway. Trivial implementation, reliable. Recommended first fallback.
2. **X-ray silhouette for entities only.** Geometry clips hard at `focus + 1`, but entity tokens on higher levels render through the ceiling as flat colored silhouettes using `cull_mode = DISABLED` with a depth-test-disabled shader. Preserves "I know Gary is up there" while keeping the world crisp.
3. **Context-aware cutaway.** Only voxels within a screen-space radius of the party centroid get transparency. Fancier, fiddlier. Post-v1.

True alpha blending is not a fallback — it creates draw-order pain and interacts poorly with depth testing at voxel scale.

### 16.4 Party Dispersion UI

When party members are on different levels, the UI must make their distribution legible.

**Level Strip Widget** (new HUD component):
- Vertical strip on the right side of the screen
- One row per level that contains anything the player cares about: party members, visible enemies, explored rooms
- Each row shows: level number, icons for party members on that level, enemy-count badge, "unexplored" badge
- Clicking a row jumps focus to that level
- The currently-focused level row is highlighted
- Roughly inspired by Jagged Alliance 3's floor buttons and XCOM 2's level indicator

Example for John-on-1, Bob-on-2, Gary-on-4:

```
┌─────┐
│ L4  │  [Gary]                    ← click to focus
│ L3  │  (empty, explored)
│ L2  │  [Bob]
│ L1  │  [John]  ← currently focused, highlighted
│ L0  │  (entry, explored)
└─────┘
```

**Party Bar Grouping** (modification to existing party bar):
- When party members are on different levels, visually group them by level with small level-number chips
- Portraits on non-focused levels get a small numeric badge showing their level
- Clicking a portrait jumps focus to that member's level AND selects them

**Off-Screen Indicators:**
- When a party member is on the focused level but outside the camera viewport, show an arrow on the screen edge pointing toward them
- Click the arrow to pan camera to that member

### 16.5 Auto-Focus Rules

The scheduler is real-time-with-pause. Auto-focus fires on specific scheduler events, not on fixed turn boundaries:

- **Auto-pause event on non-focused level** (encounter, trap trigger, secret-door reveal, torch expire on that level): focus auto-changes to the event's level. Camera smoothly tweens Y over ~0.3 seconds.
- **Combat turn rotation (inside turn-based combat sub-game):** focus auto-changes to the current active combatant's level, same tween.
- **Player clicks a party-member portrait:** immediate focus change and selection.
- **Player clicks a cell on a non-focused level:** first click highlights the cell and shows a "Move here on Level N" tooltip; second click confirms the order. This prevents misclicks on the dimmed/dithered lower levels.

### 16.6 Free Camera & Fog Safety

Protection against camera-lost-in-fog-of-war:

1. **Focus level is clamped to "meaningfully explored" levels by default.** The manager tracks which levels have ANY `fog_state != "hidden"` cells. The player cannot PgUp/PgDn to a level with no explored cells unless they enable Free Camera mode (dev-option or post-tutorial toggle).
2. **Camera horizontal pan is clamped to the bounding box of explored cells plus a 1-cell border.** Middle-mouse drag stops at the edge of explored territory.
3. **Home key** instantly restores focus level to the party leader and centers the camera on them.
4. **Fog-of-war darkness is opaque, not black.** Hidden cells render as a textured dark void (subtle noise or parchment pattern) that reads as "not here" rather than "camera broke."
5. **Level indicator breadcrumb:** the Level Strip Widget shows the player's party members on levels with lit icons. As long as they can see the lit icons they know where the party is, regardless of where the camera drifted.

### 16.7 Occlusion of Walls Between Camera and Party

Separate problem from level occlusion: even on a single level, a wall or structure between the isometric camera and a party member obscures that member. Apply the same dither-transparency treatment to wall cells that sit between the camera and any party member on the focused level. In practice, much of this falls out for free because `level == focus + 1` walls (the upper half of a typical 2-cube-tall wall) already get the dither under §16.2's rules.

### 16.8 Visibility Manager State

The Visibility Manager (§17.2) maintains this state each frame:

```gdscript
class_name VisibilityManager
extends Node

var focus_level: int = 0
var party_positions: Array[Vector3i] = []   # updated by PartyController
var explored_levels: Array[int] = []        # derived from VoxelMapData fog
var camera_forward: Vector3                 # from active Camera3D

signal focus_level_changed(new_level: int)

func set_focus_level(new_level: int) -> void: ...
func jump_to_party_leader() -> void: ...
func get_level_visibility(level: int) -> float: ...   # 0.0 hidden, 1.0 opaque
func should_dither(level: int) -> bool: ...
```

The manager drives per-level MultiMeshInstance3D visibility, per-level shader uniforms, and the Level Strip Widget.

### 16.9 Adjacency Definition — Single Source of Truth

Entity adjacency in the voxel model is **3D Chebyshev distance ≤ 1**: the 26 cells surrounding any given cell (plus the cell itself) are "adjacent." This single rule governs:

- **Melee engagement** — two entities in any of the 26 adjacent positions can engage each other in melee, regardless of the 1-level height difference. A flyer 5' above a ground target IS engaged with that target. A character on a stair cell 5' below another character on the same stair cell IS adjacent.
- **Inventory transfers** — the §5 carrier-adjacency rule uses the same predicate.
- **Area effects that specify "adjacent"** — burst radius 1 from an entity includes all 26 neighbors.
- **Reach weapons** — extend to Chebyshev distance 2 in 3D, uniformly.

One implementation in `VoxelGrid.is_adjacent(a: Vector3i, b: Vector3i) -> bool`. Combat, inventory, and effects all call it.

**Consequence for flyers vs. ground:** a flyer hovering 5' (1 level) above a ground target is engaged. A flyer at 10'+ (2+ levels) above a ground target is not engaged (unless the ground target has a reach weapon, which extends to Chebyshev 2). This is consistent with monster_system_map §3.2's engagement rules.

---

## 17. Godot 4 Implementation Notes

### 17.1 Files to Modify or Create

```
engine/shared_types/
  voxel_cell.gd                   NEW — replaces CellData
  voxel_map_data.gd               NEW — replaces TacticalMapData, sparse Dict storage
  voxel_grid.gd                   NEW — static math helpers (adjacency, neighbors, distance)
  isometric_grid.gd               MODIFY — retain 2D math, add 3D helpers delegating to VoxelGrid
  falling_resolver.gd             NEW — computes fall paths and damage

engine/subsystems/
  presentation/
    visibility_manager.gd         NEW — focus level, per-level opacity
    voxel_los.gd                  NEW — 3D DDA line-of-sight
  inventory/
    party_inventory_transfer_validator.gd
                                  MODIFY — wire _check_dungeon_adjacency() and
                                    _check_combat_trade_action() to VoxelGrid.is_adjacent()

scenes/maps/
  tactical_grid_3d.gd             MAJOR REFACTOR — per-level MultiMesh groups,
                                    cube-voxel mesh builders, no more WALL_HEIGHT
  dungeon_map_renderer_3d.gd      REFACTOR — consume VoxelMapData, drive VisibilityManager
  combat_map_renderer_3d.gd       REFACTOR — same
  dungeon_map_3d.tscn             MODIFY — scene-tree structure for per-level groups

scenes/ui/
  hud/
    level_strip_widget.gd         NEW — right-side level indicator
    level_strip_widget.tscn       NEW
  components/
    combatant_token_3d.gd         MINOR — position takes Vector3i, computes world Y from level

engine/autoloads/
  campaign_repository.gd          MODIFY — replace dungeon_map_cells CRUD with
                                    voxel_map_cells CRUD

db/migrations/
  0XX_voxel_grid.sql              NEW — create voxel_map_cells table, migrate old data

tests/
  test_voxel_cell.gd              NEW
  test_voxel_map_data.gd          NEW
  test_voxel_grid.gd              NEW — adjacency, neighbors, distance in 3D
  test_voxel_los.gd               NEW
  test_falling_resolver.gd        NEW
  test_visibility_manager.gd      NEW
  test_party_inventory_transfer_validator.gd
                                  UPDATE — add 3D adjacency test cases
```

### 17.2 Pathfinding

No Godot-native 3D grid pathfinder exists (`AStarGrid2D` is 2D-only). The options:

- **Hand-rolled BFS on `VoxelGrid.get_neighbors_3d()`** — matches the existing pattern in `MovementResolver._bfs` and `DungeonMapController._bfs_path`. Recommended.
- **`AStar3D`** (Godot built-in, generic graph-based) — basis-agnostic, takes `Vector3` points and edges. Use for longer-distance pathfinding where BFS would be slow (> 50 cells).

Coordinate basis (diamond vs. square) is irrelevant to both — they operate on abstract neighbor graphs, not projected geometry.

**Neighbor function:**

```gdscript
# VoxelGrid static
static func get_neighbors_3d(pos: Vector3i) -> Array[Vector3i]:
    var out: Array[Vector3i] = []
    for dc in [-1, 0, 1]:
        for dr in [-1, 0, 1]:
            for dl in [-1, 0, 1]:
                if dc == 0 and dr == 0 and dl == 0:
                    continue
                out.append(Vector3i(pos.x + dc, pos.y + dr, pos.z + dl))
    return out   # 26 neighbors

static func is_adjacent(a: Vector3i, b: Vector3i) -> bool:
    var d := b - a
    return abs(d.x) <= 1 and abs(d.y) <= 1 and abs(d.z) <= 1 and d != Vector3i.ZERO

static func chebyshev_distance(a: Vector3i, b: Vector3i) -> int:
    var d := b - a
    return max(abs(d.x), max(abs(d.y), abs(d.z)))
```

Restricted-neighbor variants (e.g., "only cells the walker can actually enter considering support") layer on top of `get_neighbors_3d` as filters.

### 17.3 Scene Tree Structure for Per-Level Rendering

```
DungeonMap3D (Node3D, extends TacticalMap3D)
├── LevelGroups (Node3D)
│   ├── Level_0 (Node3D)
│   │   ├── FloorSlabs (MultiMeshInstance3D)
│   │   ├── Walls (MultiMeshInstance3D)
│   │   ├── Doors (Node3D, children: individual MeshInstance3D per door)
│   │   ├── Features (Node3D, children: stairs, ramps, trap_door cells with unique meshes)
│   │   └── FogOverlay (MultiMeshInstance3D)
│   ├── Level_1 (Node3D)
│   │   └── ... (same structure)
│   └── Level_N ...
├── HighlightLayer (Node3D, non-per-level, drawn above)
├── EntityLayer (Node3D, children: CombatantToken3D instances positioned by level)
├── OrderOverlayLayer (Node3D)
├── Camera3D (orthographic isometric, Y controlled by VisibilityManager)
├── DirectionalLight3D
└── DungeonHUD (CanvasLayer layer=10)
    ├── LevelStripWidget
    ├── TooltipPanel
    └── ContextMenuLayer
```

Each `Level_N` node's `visible` property and its children's shader uniforms are driven by `VisibilityManager` each frame.

### 17.4 MultiMesh Performance

For a 50×50 per-level footprint with ~20 levels, that's up to 50,000 voxel cells. Most are air (not stored in sparse storage, not rendered). Solid cells (walls, pillars) in a typical dungeon level: 200-600 per level. Across 20 levels: ~8,000 MultiMesh instances total. MultiMeshInstance3D handles this easily — tested up to 100,000 on low-end GPUs.

Floor slabs: roughly 1,500 passable cells per level × 20 levels = 30,000. Still fine for MultiMesh.

### 17.5 Camera Y Position

Orthographic camera keeps its current rotation (`-35.264°, -45°, 0°`). Its Y position is controlled by focus level:

```gdscript
func _update_camera_for_focus_level(new_level: int) -> void:
    var target_y := new_level * CELL_SIZE + (CELL_SIZE * 0.5)  # center of focus cell
    var tween := get_tree().create_tween()
    tween.tween_property(camera, "position:y", target_y, 0.25)
```

Tween easing `TRANS_SINE, EASE_IN_OUT`. Preserves existing X/Z pan; only Y changes with focus.

### 17.6 Input Bindings (Recommended)

| Key | Action |
|---|---|
| PgUp | focus_level + 1 |
| PgDn | focus_level - 1 |
| Home | jump to party leader |
| Shift+Home | jump to next party member |
| F1-F8 | select party member N (existing) |
| Middle-mouse drag | horizontal pan (existing) |
| Mouse wheel | zoom (existing) |
| Space | pause/resume (existing scheduler control) |

### 17.7 Test Coverage Minimums

- Coordinate conversion roundtrip (cell_to_world → world_to_cell), including Y axis
- Voxel cell support derivation (walker in air with floor below = supported; walker in air with no floor below and no solid below = unsupported → falling)
- Falling resolver: 5', 10', 15', 100' drops; with spikes; into water (half damage default); into rubble
- LOS across levels (flyer sees ground target over wall; ground-to-ground past pillar at different height)
- Multi-level fog: entering room on level 2 reveals level-2 cells of room but not level-1 cells of same room
- VisibilityManager: focus level clamp to explored levels; dither flag on focus+1; recenter on leader
- 3D adjacency: Chebyshev ≤ 1 over 26 neighbors, cross-level for inventory and engagement
- Inventory validator: dungeon-adjacency stub replacement; combat-trade-action stub replacement

---

## 18. Migration Path: Order of Operations

Sequence for Claude Code. Each step produces a stable commit; data-only steps can be landed without regressing visuals.

1. **Schema and data types first.** Create `VoxelCell`, `VoxelMapData`, `VoxelGrid` (static math with 3D adjacency). Write tests. Do not touch renderers yet.
2. **Migration script.** Generate `voxel_map_cells` table and a one-time migration of existing `dungeon_map_cells` data.
3. **Wire inventory validator to 3D positions.** Replace the two stubs (`_check_dungeon_adjacency()`, `_check_combat_trade_action()`) with real checks against `VoxelGrid.is_adjacent()`. Add adjacency test cases.
4. **Falling resolver.** Pure data + math subsystem. Tests.
5. **VoxelLOS.** Pure data + math. Tests.
6. **VisibilityManager skeleton.** No rendering logic yet; just the state machine, focus level tracking, and level-strip-friendly queries.
7. **TacticalGrid3D refactor.** Cube-cell mesh builders. Per-level MultiMesh groups. Remove the `WALL_HEIGHT` tall-box code paths. Keep the existing 2D-grid-with-elevation-score code paths behind a feature flag until renderer migration is complete.
8. **dungeon_map_renderer_3d.gd refactor.** Consume `VoxelMapData`, instantiate per-level scene groups, wire in the VisibilityManager.
9. **combat_map_renderer_3d.gd refactor.** Same.
10. **Level Strip Widget.** HUD component, wire to VisibilityManager.
11. **Input bindings.** PgUp/PgDn, Home.
12. **Dithered-transparency shader** via `StandardMaterial3D.DISTANCE_FADE_PIXEL_DITHER`. Prototype. If it fights the cel-shaded direction, switch to the hard-clip fallback (§16.3) — one-line change.
13. **Party bar grouping for multi-level parties.**
14. **Inventory UI filtered view.** Subscribe to position-change signals, recompute adjacent carrier set, show grouped by carrier.
15. **Update the existing `test_dungeon.json`** to the new format.
16. **Update `gdd-combat-map-generation.md`, `gdd-dungeon-layout.md`, `gdd-stronghold-construction.md`, `gdd-party-inventory.md`** header references and any inline model assumptions.
17. **Delete dead code** from the elevation-score era.

Steps 1-6 are data-only and can be landed without regressing visuals. Step 7 is the risky one — preserve the old renderer behind a flag, as the 2026-04-15 session did.

---

## 19. Resolved Decisions

| Decision | Resolution | Notes |
|---|---|---|
| Voxel unit size | 5' cube on all three axes | Aligns with every ACKS structural increment |
| Floor model | Cell property (`floor_type`), not full cube | 10' story = 2 cells; ceilings are implicit |
| Horizontal basis | Diamond grid retained | Zero pathfinding friction; switching costs tests and JSON for identical visual output |
| Wilderness airspace cap | ±20 levels (±100') from ground mean | Sufficient for every flight encounter in published ACKS stat blocks |
| Slope movement cost | No cost penalty for 1-level slopes | ACKS has no "difficult terrain" concept |
| Slope threshold | Walkable: 0-1 level diff. Climb action required: 2+ level diff | Aligns with existing `gdd-combat-map-generation.md` §4.3 threshold |
| Cell storage | Sparse `Dictionary[Vector3i, VoxelCell]` | Typical maps have < 20,000 non-default cells |
| Multi-level occlusion | Dither via `StandardMaterial3D.DISTANCE_FADE_PIXEL_DITHER` | Hard-clip plane is documented fallback if dither fights cel-shaded style |
| Focus level UX | Single camera focus level + Level Strip Widget + PgUp/PgDn + Home | Borrowed from XCOM 2 / Jagged Alliance 3 / BG3 patterns |
| Adjacency rule | 3D Chebyshev ≤ 1 (26 neighbors + self) | Single predicate for melee engagement, inventory transfers, and area effects |
| Inventory model in dungeon/combat | Carriers only, adjacency-gated transfers | Drops the "shared pool" fiction in tactical play; completes the existing validator stubs |
| Inventory timing | Adjacency checked at moment of request (real-time-with-pause) | No turn boundaries; combat mode costs one action per ACKS |
| 3D pathfinding tool | Hand-rolled BFS on `VoxelGrid.get_neighbors_3d()`; `AStar3D` for long paths | Neither cares about horizontal basis |

---

## 20. Remaining Open Questions

These do not block implementation of §18 steps 1-11 (the data and non-shader portions). They should be resolved before step 12 (shader prototype) or step 14 (inventory UI).

1. **Dithered shader interaction with cel-shaded art direction.** The 2026-04-16 presentation docs standardize on cel-shaded flat-unshaded materials. Dither may or may not compose well. Resolve by prototype during step 12; fall back to hard-clip if needed (§16.3).
2. **Manual "Rebalance Load" scope.** Does it redistribute across all currently-adjacent carriers, or only among characters in the selected character's adjacency cluster? Probably the latter (stricter). Clarify during step 14.
3. **Split-party dungeon scheduler interaction with the adjacency inventory rule.** If a party splits into two groups on different floors of a dungeon, each group's internal adjacency works fine. But cross-group transfers require the groups to rejoin. Confirm this is acceptable (probably yes — it matches the verisimilitude goal). (Yes, I confirm this, adjacency is necessary for all in-dungeon or in-combat item trasnfers - Jedidiah.)
4. **Combat on a staircase.** Can two combatants occupy adjacent stair cells at different levels and engage each other in melee? Per §16.9, yes — the 3D Chebyshev rule handles this automatically. Verify the engine doesn't special-case stair movement in a way that breaks this.
5. **Reach weapons.** The 3D Chebyshev-2 rule (§16.9) for reach weapons should be smoke-tested with ACKS polearms and spears. ACKS reach rules are relatively simple but have edge cases around charge bonuses.

---

## 21. Testing Considerations

Integration test scenarios that exercise the full stack:

1. **"Three-level keep" test dungeon.** Hand-built `VoxelMapData` with a ground floor, second floor, and roof. Place one party member on each. Verify:
   - Level Strip Widget shows 3 members on 3 rows
   - PgUp/PgDn switches focus
   - Clicking a portrait jumps focus
   - Upper-level dither is applied correctly
   - Lower-level dim is applied correctly
2. **"Pit trap" test dungeon.** Character walks into a concealed pit, falls 10' (=2 cells), takes 1d6 damage. Floor transition from `pit_cover` → `none` persists after the fall.
3. **"Flying combat" test combat map.** Outdoor map, party on ground, roc flying at altitude 6 (30'). Verify the roc is rendered at the correct Y, can dive-attack, and is correctly targetable when a ground archer shoots at it.
4. **"Burrower tunnel" test.** Ankheg burrows from air under a wall into an air cell. Solid cells on the ankheg's path convert to `burrow_tunnel` air cells and are newly walkable by the party.
5. **"Multi-level fog" test.** Party enters level 2 through a door; level-2 cells of the room reveal to VISIBLE but level-1 cells of the same room (directly below, different `room_id`) stay in their previous fog state.
6. **"Lost in darkness prevention" test.** With only levels 0-2 explored, attempt PgDn to level -1 (unexplored). Confirm the focus level clamps. Enable Free Camera dev mode; confirm PgDn now works.
7. **"Cross-floor inventory lockout" test.** John on floor 0 holds a healing potion. Gary on floor 4 needs it. Attempt transfer: fails with "carriers not adjacent." Move Gary to floor 0 adjacent to John. Attempt transfer: succeeds. Move Gary back to floor 4 holding the potion. Verify John's filtered inventory view no longer shows the potion; Gary's shows it.
8. **"Combat adjacency across levels" test.** A flying wyvern 1 level (5') above a ground fighter: confirm melee engagement fires on both sides. Move the wyvern to 2 levels (10') above: confirm engagement drops (unless the fighter has a reach weapon, in which case engagement persists).

---

## 22. Revision History

- **2026-04-18 (v1.0):** Initial draft. 2D-grid-with-elevation-score to true 3D voxel grid of 5' cube cells. Floor-as-cell-property, wall-as-stack-of-solid-cells, all five movement modes, vertical traps, multi-level camera with dithered transparency, focus-level UI inspired by XCOM / Jagged Alliance 3 / BG3.
- **2026-04-18 (v1.1):** Resolved seven open questions from v1.0 review. Set wilderness airspace cap at ±20 levels. Eliminated slope movement cost (ACKS has no difficult-terrain concept). Committed to sparse cell storage. Committed to diamond basis (zero pathfinding friction; `AStar3D` is basis-agnostic). Replaced "shared inventory pool" assumption with carriers-with-adjacency model (§5), adapted to real-time-with-pause timing. Added 3D Chebyshev adjacency as the single source of truth (§16.9) shared across melee engagement, inventory, and area effects. Added explicit pathfinding guidance (§17.2). Added inventory-related test scenarios (§21.7-8).
