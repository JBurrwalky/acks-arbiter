# GDD: Dungeon Layout Generation

**Authority:** PROJECT-DESIGNED — the layout algorithm is not derived from any ACKS sourcebook. ACKS dungeon stocking procedures (room contents, monsters, traps, treasure) are defined in the XML rules reference library and applied AFTER layout generation.
**Status:** Draft
**Depends on ACKS rules:** `acore-setting-construction-rules.xml` (dungeon stocking tables, dungeon type/flavor table, special features — applied after layout, not during)
**Modifiable by Claude Code:** Yes — suggest improvements freely. The algorithm, parameters, and room templates are all engineering decisions.
**Last updated:** 2026-04-16

---

## 1. Purpose

Generate a complete dungeon map layout — rooms, corridors, doors, stairs, and spatial metadata — given a dungeon seed (type, size, level range, theme). The output is a data structure that the ACKS stocking procedures then populate with monsters, traps, treasure, and special features. This GDD controls **layout only** — what goes *in* the rooms comes from the XML rules reference library.

The generator must produce dungeons that feel like hand-drawn ACKS dungeons: rooms of varied sizes connected by corridors with doors, occasional loops, vertical connections between levels, and a spatial logic that supports faction-based play (territorial groups controlling connected room clusters).

---

## 2. ACKS Constraints

These come from the sourcebooks and MUST be respected:

**Dungeon flavor table (ACore)** — roll 1d20 to determine dungeon type. The generator uses this to select thematic parameters:

| d20 | Type | d20 | Type |
|-----|------|-----|------|
| 1 | Abandoned mine | 11 | Natural caverns |
| 2 | Barrow mound | 12 | Prison |
| 3 | Catacombs | 13 | Ruined manor |
| 4 | Cliff city | 14 | Sewers |
| 5 | Crumbling castle | 15 | Sunken city |
| 6 | Giant burrow | 16 | Temple |
| 7 | Giant insect hive | 17 | Tomb |
| 8 | Humanoid warren | 18 | Tower |
| 9 | Maze | 19 | Underground river |
| 10 | Monster lair | 20 | Wizard's dungeon |

**Dungeon size assumptions (ACore p.235):** A regional map of ~30 dungeons should include approximately 3 large dungeons (6-10 sessions each), 10 medium dungeons (1-2 sessions each), and 17 small lair dungeons (~half a session, 1-3 encounters each).

**Room stocking probabilities** — 1d6 per room: 1 = monster, 2 = monster with treasure, 3 = trap (with treasure on 1-2 on 1d6), 4 = special, 5-6 = empty. Applied AFTER layout generation, not during. (Exact probabilities defined in `acore-setting-construction-rules.xml`.)

**5-foot diamond grid** — all rooms and corridors are on the project's unified 5' × 5' isometric diamond grid (per `gdd-combat-map-generation.md` §3). Dungeon maps are diamond maps with diamond cells, the same grid system used by all tactical-scale maps in the project (combat battle maps, strongholds, building interiors). The generation algorithm operates in 2D grid coordinates; the diamond geometry is a property of the grid system itself.

**Cell-based walls** — walls are impassable cells, not edge properties. A wall cell occupies a full 5' × 5' grid cell. Doors are also cells that toggle between passable and impassable. This is the project's unified wall model shared across all tactical-scale maps (per `gdd-combat-map-generation.md` §9.2). The donjon-derived generation algorithm already operates cell-based internally (walls on even cells, rooms/corridors on odd cells), so the generator's native output IS the final wall model with no conversion step required.

**Dungeon placement guidance** — large dungeons should not be placed too close to each other. The most dangerous dungeons should be deep in the wilderness or otherwise hard to access. Medium and small dungeons/lairs can be within 3-5 hexes of settlements (including Market Class III). There are published precedents for very large dungeons beneath major settlements, so any placement is valid as long as large dungeons are spaced apart and the most lethal ones aren't trivially accessible.

---

## 3. Dungeon Size Categories

Project-designed parameters mapping ACKS dungeon assumptions to generator inputs:

| Category | Session Target | Room Count | Levels | Typical Use |
|----------|---------------|------------|--------|-------------|
| Lair | Half-session (1-3 encounters) | 3-6 rooms | 1 | Lair dungeons, half of all dungeons |
| Small | 1 session | 8-12 rooms | 1 | Small adventure sites |
| Medium | 1-2 sessions | 15-25 rooms | 1-2 | Standard dungeons |
| Large | 6-10 sessions | 30-50 rooms per level | 3-6 levels | Major dungeons, tentpole sites |

For large dungeons, the room count is per level, not total. A 4-level large dungeon might have 120-200 rooms total, but the generator builds one level at a time with connecting stairs.

---

## 4. Algorithm Overview

The generator is a **rooms-first** pipeline: rooms are placed as geometric primitives, then a corridor network connects them, then everything is rasterized onto a 2D cell grid at the end. The output matches the look of hand-drawn ACKS published dungeons (e.g. *The Sinister Stone of Sakkara*) — discrete designed rooms connected by deliberate corridor runs, with adjacent rooms sharing walls and L-bend corridor turns dominating the corridor geometry.

The algorithm is implemented entirely in GDScript using standard CS building blocks (collision-checked random placement, Prim's minimum spanning tree, A* path search) with no third-party generator dependency.

### 4.1 Core Pipeline

```
1. SEED PARAMETERS → derive grid_size, target_room_count, room_size_range,
                     corridor_style, corridor_width from dungeon_size + theme
2. PLAN ROOMS → scatter rectangular rooms (collision-checked) into the grid
                bounds; rooms MAY share walls
3. PLAN CONNECTION GRAPH → MST over room centroids (Manhattan distance),
                           plus loop_frequency × N extra edges as loops
4. ROUTE CORRIDORS → for each graph edge, route an axis-aligned corridor
                     from source room's perimeter to target room's perimeter,
                     trying L-shapes first then S-shapes; corridor avoids
                     crossing other rooms when possible
5. PLAN DOORS → identify corridor-to-room transition cells; install one
                door per cell using theme.door_type_weights
6. PLAN STAIRS → pick up/down stair cells (prefer rooms; avoid entrance)
7. ASSIGN ROOM PURPOSES → weighted pick from theme.purpose_weights (§6.3)
8. RASTERIZE → stamp planned rooms / corridors / doors / stairs onto a
               2D Array[Array[DungeonCellData]] grid
9. VERIFY → BFS from a stair; warn if any room is unreachable
10. OUTPUT → DungeonLayout per §11
```

Steps 1-7 work in **geometric primitives** (rectangles, polylines, points) — no per-cell grid exists during planning. Only step 8 produces the cell grid. This separation makes the algorithm easy to reason about and trivially supports adjacent-rooms-with-shared-walls (a routine pattern in published ACKS dungeons that bitmask-style maze-carve generators struggle with).

### 4.2 Internal Representation

During planning (steps 1-7), the generator carries the following typed data:

- **Rooms**: `Array[RoomPlan]` where each `RoomPlan` holds `bounds: Rect2i`, `id: int`, and `original_purpose: String` (filled in step 7).
- **Connection graph**: `Array[Vector2i]` of `(room_id_a, room_id_b)` edges produced by the MST + loops step.
- **Corridors**: `Array[CorridorPlan]` where each `CorridorPlan` holds an ordered `Array[Vector2i]` of cells along the corridor's centerline and `width: int` (1, 2, or 3 cells).
- **Doors**: `Array[DoorPlan]` with `position: Vector2i`, `type: String`, `room_id_a: int`, `room_id_b: int` (the corridor pseudo-room is room id `-1`).
- **Stairs**: `Array[StairPlan]` with `position: Vector2i`, `direction: String`.

A small **occupancy index** (a `Dictionary[Vector2i, int]` mapping cell positions to room ids) is built incrementally during steps 2-4 so the corridor router can cheaply check "does this cell belong to a room?". The occupancy index is generation-time scratch state, not part of the output.

The rasterization step (8) consumes the geometric plan and produces the final `Array[Array[DungeonCellData]]` grid per the §11 output schema. This is the only point in the pipeline where per-cell flags exist.

### 4.3 Grid Sizing

Per-size grid dimensions:

| Dungeon Size | Grid (cells) | Effective Map Area | Notes |
|---|---|---|---|
| Lair | 21 × 21 | ~105' × 105' | Tight, few rooms |
| Small | 31 × 31 | ~155' × 155' | Compact single level |
| Medium | 51 × 51 | ~255' × 255' | Room to spread out |
| Large (per level) | 79 × 79 | ~395' × 395' | Spacious, multiple wings |

Each grid cell represents a 5' × 5' area in world space (rendered as an isometric diamond). The "effective map area" column is simply `grid_size × 5'`. There is no "every-other-cell" reservation — rooms and corridors occupy contiguous cells, and walls are the cells around the room/corridor footprint.

**Image-to-cell math when comparing against ACKS published dungeons:** ACKS published maps (e.g. *Sakkara*) draw rooms at **10' per square** to save paper. The project uses 5' cells. So **one visible square in a published map equals four (2×2) cells in our grid**. A "10' wide corridor" in a published map is 2 cells wide in our grid. A "20' × 30' room" is 4 × 6 cells in our grid.

---

## 5. Dungeon Type Theming

Each dungeon type from the ACKS flavor table maps to a set of generator parameters that affect layout feel. These are the project-designed "personality" of each dungeon type.

### 5.1 Theme Parameter Set

Each dungeon type defines overrides for these parameters:

```
DungeonTheme:
  type_name: string              # From the ACKS d20 table
  room_size_bias: string         # "small", "mixed", "large", "huge"
  corridor_style: string         # "labyrinth", "bent", "straight"
  dead_end_removal: int          # 0-100, percentage of dead ends to remove
  loop_frequency: float          # 0.0-1.0, how often corridors create loops
  room_shape: string             # "rectangular", "irregular", "mixed"
  door_type_weights: Dictionary  # Override default door type probabilities
  vertical_tendency: string      # "none", "low", "medium", "high"
  corridor_width: string         # "narrow" (5'), "standard" (10'), "wide" (15'-20'), "mixed"
  special_features: Array        # Theme-specific features the LLM should consider
  encounter_flavor: Array        # Monster type tags for themed encounter table construction
  structure_type: string         # "subterranean" or "above_ground" — controls multi-level rules
```

### 5.2 Theme Definitions

| Type | Room Bias | Corridors | Dead End Removal | Loops | Shapes | Corridor Width | Monster Flavor Tags |
|---|---|---|---|---|---|---|---|
| Abandoned mine | mixed | straight | 30% | 0.2 | rectangular | mixed | vermin, undead, construct, earth_creature |
| Barrow mound | small | bent | 80% | 0.1 | rectangular | narrow | undead, spirit, vermin |
| Catacombs | small | labyrinth | 20% | 0.4 | rectangular | standard | undead, vermin, cultist |
| Cliff city | large | straight | 70% | 0.3 | mixed | wide | humanoid, beast, aerial |
| Crumbling castle | mixed | bent | 60% | 0.3 | rectangular | wide | undead, humanoid, vermin, beast |
| Giant burrow | large | bent | 50% | 0.2 | irregular | wide | giant, beast, vermin |
| Giant insect hive | mixed | labyrinth | 10% | 0.5 | irregular | mixed | insect, vermin |
| Humanoid warren | small | labyrinth | 20% | 0.4 | mixed | standard | humanoid, beast |
| Maze | mixed | labyrinth | 0% | 0.1 | rectangular | standard | construct, aberration, beast |
| Monster lair | mixed | bent | 70% | 0.2 | irregular | standard | beast, dragon, giant |
| Natural caverns | large | bent | 40% | 0.3 | irregular | wide | beast, vermin, earth_creature |
| Prison | small | straight | 90% | 0.1 | rectangular | standard | undead, humanoid, aberration |
| Ruined manor | mixed | straight | 70% | 0.2 | rectangular | standard | undead, humanoid, vermin |
| Sewers | mixed | straight | 30% | 0.5 | rectangular | standard | vermin, ooze, aberration, humanoid |
| Sunken city | large | bent | 50% | 0.3 | mixed | wide | aquatic, undead, aberration |
| Temple | large | straight | 80% | 0.2 | rectangular | wide | undead, fiend, cultist, construct |
| Tomb | mixed | bent | 70% | 0.15 | rectangular | standard | undead, construct, vermin |
| Tower | small | straight | 90% | 0.1 | rectangular | narrow | arcane, construct, humanoid |
| Underground river | mixed | bent | 40% | 0.3 | irregular | wide | aquatic, beast, aberration |
| Wizard's dungeon | mixed | bent | 60% | 0.3 | mixed | standard | *(none — generic; uses raw Random Monsters by Level — see §5.3 note)* |

### 5.3 Themed Encounter Tables

Each dungeon type's `encounter_flavor` tags are used to build a custom encounter table from the available monster catalog:

1. Query the monster catalog for entries matching any of the dungeon type's flavor tags
2. Filter by dungeon level (HD-appropriate monsters)
3. Weight by tag match count (a monster matching 2 tags is weighted higher than one matching 1)
4. Apply the standard ACKS encounter table construction guidelines (from ACore Secrets chapter)
5. Store as the dungeon's custom wandering monster table

Claude Code can implement this table construction — the ACKS guidelines for building custom tables exist in the source material. The resulting tables should be stored as editable JSON so they can be hand-tuned after generation.

**Wizard's Dungeon exception (added 2026-05-27).** The Wizard's Dungeon is re-flavored as a generic dungeon deliberately built by a wizard to attract monsters for harvesting their magical components and to lure (hopefully wealthy) adventurers to their deaths. It is the V1 dungeon generator's universal fallback (per [`gdd-dungeon-generator-v1.md`](gdd-dungeon-generator-v1.md) §7) and uses the **raw Random Monsters by Level table** (`rules/acore-monster-stocking-rules.xml:112-136`) directly — tag-filtered encounter table construction does NOT apply to Wizard's Dungeon. Every other dungeon type uses the §5.3 tag-filter procedure; Wizard's Dungeon does not. This exception preserves the "everything dungeon" semantics that makes Wizard's Dungeon the canonical fallback for any unknown / unspecified dungeon type.

---

## 6. Room Placement Algorithm

### 6.1 Procedure

```
1. target_count   = midpoint of the §3 row for this dungeon_size
2. size_range     = (min_cells, max_cells) per theme.room_size_bias:
                       small  → (2,  4)  → 10'-20' rooms
                       mixed  → (2,  6)  → 10'-30' rooms
                       large  → (3,  8)  → 15'-40' rooms
                       huge   → (4, 10)  → 20'-50' rooms
3. attempts_cap   = target_count × 5
4. for each attempt (until target reached or cap hit):
   a. roll a random width  w in size_range
   b. roll a random height h in size_range
   c. roll a random (x, y) such that the room fits inside the grid with
      at least 1 cell of clearance from the grid edge
   d. collision check: the proposed room MAY share an edge with an
      existing room (adjacent walls — common in ACKS published dungeons),
      but its interior MUST NOT overlap any existing room interior
   e. if no collision: assign the next room id, append a RoomPlan, and
      stamp the room's cells into the occupancy index
5. return Array[RoomPlan] (length ≤ target_count)
```

Adjacent rooms (shared walls) are permitted by design — the published *Sakkara* dungeons routinely use this pattern (e.g. rooms 7-8, 12-13, 22-23 in the Buried Temple level). The corridor router (§7) and door placer (§8) will install doors between adjacent rooms that the connection graph (§7.2) chose to connect.

The collision check uses **interior overlap**, not "interior plus perimeter buffer." This is the key structural difference from grid-fill maze generators: the corridor network is built from MST connections, not from "fill the negative space with a maze," so there is no need to reserve negative space between rooms.

### 6.2 Room Shape Variation

For `room_shape: "rectangular"` themes (the default for V1's Wizard's Dungeon), all rooms are axis-aligned rectangles.

For `room_shape: "irregular"` or `"mixed"` themes (deferred to V2): after placing the base rectangular room, optionally modify it via a small **template library**:
- **L-shape:** remove a rectangular notch from one corner (25% chance for irregular)
- **T-shape:** extend a rectangular protrusion from one side (15% chance)
- **Round:** place a circular room (corner cells blocked, 10% chance for irregular themes)
- **Nested-square sanctum:** the inner-sanctum centerpiece pattern (rooms 73-75 in the Buried Temple) — a designed multi-tier room

The V2 template library replaces step 4a-b of §6.1: instead of rolling width and height for a plain rectangle, the placer rolls a template from a per-theme catalog and stamps its footprint. Theme-specific templates (forge, library, observatory, etc.) carry pre-placed interior features (anvils, shelves, telescopes) that flow into stocking and LLM narration.

### 6.3 Original Room Purpose Assignment

After rooms are placed, the generator assigns an `original_purpose` to each room based on the dungeon type. This represents what the room was built for, before its current inhabitants moved in. The stocking procedure later assigns a `current_purpose` based on what ends up in the room.

Each dungeon type has a weighted purpose table. The generator rolls against it for each room. Example tables (weights are approximate — tune after playtesting):

**Abandoned Mine:** ore storage (15%), bunkroom (15%), tool shed (10%), shaft head (10%), foreman's office (5%), mess hall (10%), cart staging (10%), ventilation junction (5%), ore processing (10%), guard post (10%)

**Tomb:** burial chamber (25%), antechamber (15%), offering room (10%), guardian chamber (15%), sealed vault (10%), preparation room (10%), false tomb (5%), corridor shrine (10%)

**Temple:** worship hall (15%), clergy quarters (10%), vestry (10%), library/scriptorium (10%), reliquary (10%), meditation cell (10%), kitchen/refectory (10%), storage (10%), sanctum (10%), bell tower/upper chamber (5%)

**Humanoid Warren:** sleeping den (20%), food storage (15%), chieftain's chamber (5%), trophy room (5%), guard post (15%), waste pit (10%), workshop (10%), communal hall (10%), breeding pen (10%)

**Natural Caverns:** open cavern (30%), narrow passage (15%), underground pool (10%), crystal formation (5%), fungal garden (10%), bat colony roost (10%), underground stream crossing (10%), collapsed section (10%)

**Wizard's Dungeon:** laboratory (15%), library (15%), summoning chamber (10%), specimen storage (10%), apprentice quarters (10%), golem workshop (10%), scrying room (5%), trapped corridor (10%), vault (10%), observatory (5%)

Complete purpose tables for all 20 dungeon types should be built during implementation. Claude Code can draft initial tables from the dungeon type names and general RPG conventions; they are project-designed content and can be freely edited.

The `original_purpose` is stored on the room data and passed to the LLM during room description generation. The LLM uses it to describe physical features: a former bunkroom still has rotting wooden frames along the walls, even if orcs now use it as a treasure hoard.

---

## 7. Corridor Generation

Corridors are planned in **two stages**: first a connection graph chooses which room pairs to connect; second, each chosen pair gets a routed axis-aligned corridor. No maze-fill is performed — the negative space between rooms is left as rock unless a corridor passes through it.

This matches the published ACKS dungeon style: corridors are deliberate runs between rooms, not the dominant fill medium. Long winding corridors and dead-ends appear when the connection graph chooses a circuitous route or when extra loop edges create branches; they are emergent, not algorithmic stubs.

### 7.1 Corridor Width

The default corridor width is **10' (2 cells)**, matching the ACKS standard. The corridor router emits corridors whose width is set by the theme:

| Theme `corridor_width` | Cells | World width |
|---|---|---|
| `narrow`   | 1 | 5' |
| `standard` | 2 | 10' — default; used for most themes |
| `wide`     | 3 | 15' |
| `mixed`    | per-edge: 60% standard / 25% wide / 15% narrow | varies |

The router treats `width` as a constraint: at every step it advances a centerline by one cell and emits a perpendicular footprint of `width` cells stamped centered on the centerline. The collision check rejects routes whose footprint would overlap a room interior.

### 7.2 Connection Graph

```
1. Compute centroids of all placed rooms.
2. Build a minimum spanning tree (Prim's algorithm) over centroids using
   Manhattan distance as edge weight. This produces N-1 edges that touch
   every room exactly once and minimize total corridor length.
3. Pick a random sample of non-MST edges and add them as "loop" edges.
   The sample size is `int(loop_frequency × (N choose 2 - (N-1)))`.
   Loop edges create alternate paths and reduce the tree-likeness of the
   resulting connectivity graph.
4. Return Array[(room_id_a, room_id_b)] of edges to route.
```

The MST stage is critical for the navigability guarantee: by construction, every room is reachable from every other room via the MST, even before any loop edges are added.

### 7.3 Corridor Routing

For each edge in the connection graph, route an axis-aligned corridor from
the source room to the target room:

```
route_corridor(room_a, room_b, theme):
   1. Pick `start` = a perimeter-adjacent cell of room_a facing toward
      room_b (the cell on room_a's edge closest to room_b's centroid,
      offset 1 cell outside the room).
   2. Pick `end` = same for room_b facing toward room_a.
   3. Try several axis-aligned route strategies in order; the first one
      that succeeds without crossing a third room is accepted:
        a. L-route, horizontal first  (run east/west, turn, run north/south)
        b. L-route, vertical first    (run north/south, turn, run east/west)
        c. S-route, horizontal first  (H, V, H zigzag through a chosen mid-x)
        d. S-route, vertical first    (V, H, V zigzag through a chosen mid-y)
   4. If no strategy avoids crossing another room, accept the L-route with
      the fewest cells of crossing — the crossing cells become through-room
      passages (visible as openings on opposite walls of the crossed room;
      the §8 door placer treats them as 2-door openings).
   5. Stamp the corridor's cells into the occupancy index as CORRIDOR.
      Both endpoints (start, end) belong to corridor cells just outside
      the source / target room perimeters; the in-room door cells are
      added by §8.
   6. Return CorridorPlan with the ordered cell list and width.
```

The straight-line preference in steps 3a-3d (single L-bend before zigzag) produces the L-bend corridor geometry visible in *Sakkara* and most other ACKS published dungeons. `corridor_style` shifts the strategy-order weighting:

| `corridor_style` | Effect |
|---|---|
| `straight`  | L-routes only; if both fail, accept the best crossing rather than S-route |
| `bent`      | L then S; default for most themes |
| `labyrinth` | S then L (prefers zigzag); ideal for `Maze` and `Catacombs` themes |

There is no separate "dead-end removal" pass — corridors connect two rooms by construction; dead-ends never form. The illusion of dead-end side passages in published dungeons comes from the §7.2 loop edges that branch off the MST trunk and connect a single off-path room; that's the natural place for them.

### 7.4 Loop Density

The theme's `loop_frequency` (0.0-1.0) governs how many non-MST edges are added. Recommended values:

| `loop_frequency` | Effect |
|---|---|
| 0.0 | Pure tree — every room has exactly one path to every other. Maximum dead-end feel. |
| 0.1-0.2 | Sparse loops — most rooms have one path; a few have two. The default for tight themes (Prison, Tower). |
| 0.3-0.4 | Moderate loops — common for Wizard's Dungeon and most themes; matches *Sakkara* density. |
| 0.5+ | Heavy loops — many redundant paths; suited to Sewers, Maze. |

---

## 8. Door Placement

### 8.1 Procedure

Doors are installed at corridor-to-room transition cells. Each transition cell is on a room's perimeter (the cell between a room interior and a corridor centerline cell or another room interior). The corridor router (§7.3) produced the corridor cell paths; the door placer walks each corridor and finds where it enters or exits a room.

```
plan_doors(rooms, corridors, theme):
   for each corridor:
      for each cell on the corridor's centerline (and per width-cell offset):
         compare against the previous cell:
            if the previous cell was inside a room AND the current is not,
              OR the previous cell was outside a room AND the current is:
                 the boundary cell at the transition is a door slot
   for each unique door slot:
      type = weighted_pick(theme.door_type_weights or §8.1 default)
      install DoorPlan(position, type, room_id_a, room_id_b)

# Adjacent-room doors:
   for each pair of rooms that share an edge AND are connected in the
   §7.2 connection graph:
      pick one cell on the shared edge (random per the seeded rng)
      install DoorPlan there with `type = weighted_pick(...)`
```

The §8.1 baseline door type weights (used when `theme.door_type_weights` is empty):

| Type | Default weight |
|---|---|
| Arch (open passage) | 15% |
| Unlocked door | 40% |
| Locked door | 15% |
| Trapped door | 10% |
| Secret door | 10% |
| Portcullis | 10% |

Theme overrides (§8.2 below) shift these weights — e.g. Prisons have more locked doors, Tombs have more secret doors, Wizard's Dungeon has higher Trapped and Secret fractions.

5. **Secret-as-overlay (added 2026-05-27).** A "Secret door" roll does NOT produce `type = "secret"` in the final DoorData. Instead, roll a sub-weight (50% unlocked, 40% locked, 10% trapped) for the underlying type, then set `is_secret = true` on the resulting door. This makes Secret compositional with Locked and Trapped — e.g., a Locked+Secret door is now expressible (the §11.4 trap-placeholder fallback in `gdd-dungeon-generator-v1.md` relies on this). For the theme door weight overrides in §8.2 below, the "Secret" column continues to mean "roll secret-overlay," not "produce type=secret."

### 8.2 Theme Door Weight Overrides

| Type | Arch | Unlocked | Locked | Trapped | Secret | Portcullis |
|---|---|---|---|---|---|---|
| Default | 15% | 40% | 15% | 10% | 10% | 10% |
| Prison | 5% | 15% | 40% | 10% | 10% | 20% |
| Tomb | 10% | 25% | 15% | 20% | 20% | 10% |
| Temple | 25% | 35% | 10% | 5% | 15% | 10% |
| Wizard's dungeon | 10% | 20% | 20% | 20% | 20% | 10% |
| Humanoid warren | 30% | 40% | 5% | 5% | 10% | 10% |
| Natural caverns | 60% | 20% | 0% | 5% | 15% | 0% |

Other types use default weights. These can be tuned after playtesting.

**Structure type classification:** Above-ground types (levels must roughly match spatially, upper levels shrink for towers): **Tower, Ruined manor, Crumbling castle, Cliff city.** All other types are subterranean (levels generated independently, only stair positions must match).

### 8.3 Door Material and Tier-Scaled Portcullis Override (added 2026-05-27)

The §8.1 type roll determines whether a door slot is `arch`, `unlocked`, `locked`, `trapped`, `secret`, or `portcullis`. A *second* per-door pass determines the door's material and may override the type to portcullis as dungeons get deeper. This pass takes the floor's **dungeon level / tier** (1–6, supplied by the caller — typically the dungeon generator orchestration, e.g., `gdd-dungeon-generator-v1.md` §6) as its only parameter.

#### 8.3.1 Procedure

For each door produced by §8.1, in order:

1. **Skip arches and existing portcullises.** If `type == "arch"` (open passage, no door object), set `door_material = ""` (MATERIAL_NONE) — there is no material to roll. If `type == "portcullis"` (already a portcullis from the §8.1 roll), set `door_material = "metal"` and skip both the portcullis-override and the material roll (a portcullis is intrinsically metal; the see-through-bars property is captured by the cell's `blocks_los = false`, not by the material name).
2. **Skip secret-overlay doors.** If `is_secret == true` (regardless of the underlying type), set `door_material = "wood_standard"` and skip the portcullis-override roll. Secret doors are wall-disguised by construction; promoting one to a portcullis would defeat the disguise, and metal secret doors are detectable by acoustic / visual cues that don't match the surrounding wall, breaking the secret. (This decision is project-designed; if Jedidiah wants secret-overlay doors to roll material too, easy to revise.) Note: this means a Locked+Secret door is always `wood_standard` — bashable in principle, but the player must first detect it. The §10.1 door inventory in `gdd-dungeon-generator-v1.md` treats wooden Locked+Secret doors as not requiring placed keys (they can be bashed once detected).
3. **Portcullis-override roll.** Roll d100. If the result is ≤ `5 × floor_tier`, override `type = "portcullis"`. Drop any `is_locked` / `is_trapped` flags (a portcullis is its own access challenge — handled via Force Portcullis or wired lever per `gdd-dungeon-map-ui.md` §4.2.1). Set `door_material = "metal"`. Skip step 4.
4. **Material roll.** Roll d100. If the result is ≤ `5 × floor_tier`, the door is a hard material — roll d6: 1–3 → `door_material = "metal"`, 4–6 → `door_material = "stone"` (50/50 split). Else `door_material = "wood_standard"`.

#### 8.3.2 Tier-by-tier expected distribution

For a non-arch / non-portcullis / non-secret door at each tier (probabilities of the *final* type/material outcome after both rolls; rounded):

| Floor tier | Portcullis override | Hard (metal or stone) | Wood_standard |
|---|---|---|---|
| 1 | 5% | 4.75% | 90.25% |
| 2 | 10% | 9.00% | 81.00% |
| 3 | 15% | 12.75% | 72.25% |
| 4 | 20% | 16.00% | 64.00% |
| 5 | 25% | 18.75% | 56.25% |
| 6 | 30% | 21.00% | 49.00% |

Aggregated with the §8.2 baseline portcullis (default 10%, theme-overridable), tier-6 dungeons will be roughly 30% portcullis + 21% hard (metal/stone) of remaining = a high fraction of inaccessible-by-bash doors, exactly as intended for deep-dungeon difficulty progression.

#### 8.3.3 Schema impact

The DoorData (§11) carries `door_material` from the **canonical door material vocabulary**: `{"" (none/arch), curtain_cloth, curtain_leather, wood_standard, wood_thick, stone, metal}`. §8.3 populates this field but produces only a subset: `""` (arches), `metal` (portcullises + the metal half of the hard-material roll), `stone` (the stone half), and `wood_standard` (the common case). The curtain materials and `wood_thick` are NOT produced by §8.3 — they are reserved for V2 themes (primitive lairs use curtains; reinforced doors use wood_thick), monster-lair stocking, and hand-authoring.

Bashability (consumed by `gdd-dungeon-map-ui.md` §4.2.1): `curtain_*` → free passage (no bash); `wood_standard` / `wood_thick` → bashable with an axe; `stone` / `metal` → unbashable.

The tier-scaled portcullis override means a door originally rolled as `locked` or `trapped` may end up as `portcullis` after §8.3 step 3. The `gdd-dungeon-generator-v1.md` §10.1 door inventory (which classifies doors into LockedDoor and PortcullisDoor lists for key/lever placement) processes the post-§8.3 types, so this is consistent end-to-end.

The tier-scaled portcullis override means a door originally rolled as `locked` or `trapped` may end up as `portcullis` after §8.3 step 3. The `gdd-dungeon-generator-v1.md` §10.1 door inventory (which classifies doors into LockedDoor and PortcullisDoor lists for key/lever placement) processes the post-§8.3 types, so this is consistent end-to-end.

#### 8.3.4 Theme overrides (future)

For V1, §8.3 is tier-driven only. Future theme work may add per-type modifiers — e.g., a Prison theme might have a higher metal-door fraction at every tier (because the architecture intentionally uses metal for security), or a Natural Caverns theme might never roll metal (no smithing in raw caves). The hook for those overrides is a theme-level `door_material_weights` field on each row of §5.2, parallel to the existing door-type weights in §8.2. Not in scope for V1; flagged for V2 theme work.

### 8.4 Curtain doors (V2 runtime semantics — reserved)

The canonical door material vocabulary includes `curtain_cloth` and `curtain_leather` (per §8.3.3). The §8.3 generator does NOT produce curtains in V1 — they are reserved for V2 producers (primitive monster lairs, beast burrows, and themes where hanging cloth/hide replaces hinged doors). The intended runtime behavior is **reserved here** so the V2 system and the runtime dungeon UI implement it consistently:

- **Movement:** a curtain is ALWAYS passable, even when "closed." A creature pushes through without an open action. (Contrast with a closed wooden door, which blocks movement until opened or bashed.)
- **Line of sight / light:** a closed (hanging) curtain BLOCKS LOS and light, exactly like a closed door — `cell.blocks_los = true`. This is the curtain's purpose: privacy / light containment without a hard barrier.
- **Open like a door:** a curtain can be explicitly parted / tied back via the normal door-open interaction. When open, `door_state = "open"` and `blocks_los = false` (the parted curtain no longer blocks sight). Closing re-hangs it (`door_state = "closed"`, `blocks_los = true`).
- **The novel cell-state combination** a curtain introduces is `passable = true` AND `blocks_los = true` (closed). No other door type has this — closed hard doors are `passable=false, blocks_los=true`; portcullises are `passable=false, blocks_los=false`; open passages are `passable=true, blocks_los=false`.
- **No bash, no lock, no trap, no portcullis-override:** curtains skip all of §8.3 — they are never locked, trapped, or bashed (you just walk through). `DungeonDoorData.is_curtain(material)`, `is_bashable(material)` (false for curtains), and `is_flammable(material)` (true for curtains) classify them.

**Runtime wiring required when V2 first produces a curtain** (NOT done in V1 — `gdd-dungeon-generator-v1.md` generates no curtains):
- The runtime `VoxelCell` needs to carry the curtain marker (a `door_type = "curtain"` value or a propagated `door_material`) so `is_walkable_with_open_door()` / `blocks_flight()` grant the "walkable while closed" exception. `blocks_los()` already returns true for a closed door, so the LOS half works unchanged.
- The `DungeonCellData → VoxelMapData` load conversion must propagate the curtain marker.
- The dungeon context-menu builder + handler add "Part Curtain" / "Close Curtain" (reusing the existing `interact_door` toggle + `door_state_changed` → fog refresh path).
- This is a moderate cross-subsystem task scoped to V2; deferring it until curtains are actually generated keeps it testable against real content.

---

## 9. Stairs and Vertical Connections

### 9.1 Placement

For multi-level dungeons:

1. Find suitable stair locations — corridor dead-ends or room corners with sufficient space
2. Place at least 2 stair connections per level:
   - 1 stair up (to previous level or to the surface on level 1)
   - 1 stair down (to next level, if applicable)
3. Optional additional stairs for large dungeons (1 per 15-20 rooms)
4. Stairs on adjacent levels must spatially align (the "down" stair on level 2 corresponds to the "up" stair on level 3 at the same grid position)

### 9.2 Dungeon Entrance

The entrance to the dungeon (connection to the overworld map) is placed as a special stair-up on level 1. Its position should be:
- Near an edge of the grid (not buried in the center)
- Connected to the corridor network
- The first room/area the party encounters

### 9.3 Constrained Stair Placement (added 2026-05-27)

When the layout generator is called as part of a multi-level dungeon pipeline (e.g., from [`gdd-dungeon-generator-v1.md`](gdd-dungeon-generator-v1.md) §8.1), the caller may pass an optional `required_stair_positions` parameter that anchors specific stair cells to exact grid coordinates. This is the **preferred** interface for multi-level pipelines because it guarantees stair alignment between adjacent floors on the first generation attempt, without post-hoc carving or scooting.

#### 9.3.1 Parameter shape

```
required_stair_positions: Array[StairAnchor]   # defaults to []
StairAnchor:
  position: Vector2i      # The exact grid cell where a stair must appear
  direction: string       # "up" or "down"
```

If the parameter is empty or omitted, the layout generator behaves per §9.1 (free placement). If the parameter is non-empty, the generator MUST place a stair of the specified direction at each listed position, and the placed cells MUST be connected to the room/corridor network.

#### 9.3.2 Generation order with anchors

When `required_stair_positions` is non-empty, the layout pipeline (§4.1) is reordered as follows:

1. **RESERVE ANCHOR CELLS.** Before planning rooms (§4.1 step 2), reserve each anchor cell in the occupancy index as a "stair cell." Each anchor cell sits inside a small "stair antechamber" rectangle — a 3×3 room reserved around the anchor — to give the anchor a guaranteed room context. The antechamber is added to `Array[RoomPlan]` as a normal room with `is_anchor_room = true`.
2. **PROCEED WITH ROOM SCATTER.** Run §6.1 normally. The anchor antechambers participate in collision checks like any other room; new rooms cannot overlap them.
3. **PROCEED WITH CONNECTION GRAPH AND CORRIDOR ROUTING.** Run §7 normally. The anchor antechambers are nodes in the MST; corridors connect them to the rest of the dungeon like any other room.
4. **PROCEED WITH DOOR PLACEMENT.** Run §8 normally. The anchor cell itself is NOT a door — it's a stair (§9.1 step 6 below).
5. **STAIR PLACEMENT.** For each anchor, the stair is placed at the anchor cell (already reserved). Free-placement stairs (§9.1) only fill in additional non-anchored stair slots if requested.

#### 9.3.3 Failure handling

The anchor-aware procedure is constructed so that constraint satisfaction is **structural, not search-based** — the anchor cells are reserved before generation starts as part of their own antechambers, so generation cannot produce a layout that fails the anchor constraint. The only failure mode is the MST's room-to-room corridor router being unable to connect the anchor antechamber to the rest of the network (extremely rare; the §7.3 strategy fallback chain handles all realistic cases). If a connection fails, the generator carves a direct corridor from the anchor antechamber's centroid to the nearest existing corridor cell as a safety net.

If the caller supplies anchor positions that lie outside the grid bounds or that conflict with each other (two anchors at the same position with different directions), the generator returns an error to the caller without attempting generation. The orchestrating multi-level pipeline should not produce such input.

#### 9.3.4 Caller responsibilities

The multi-level pipeline (e.g., `gdd-dungeon-generator-v1.md` §8.1) is responsible for:

- Computing the correct anchor positions for each non-entrance floor from the prior floor's already-generated stair positions.
- Passing the opposite direction ("up" if the prior floor's stair was "down", and vice versa).
- Generating floors in the right order (entrance floor first; other floors radiating outward in BFS order from the entrance floor).
- Validating cross-floor stair alignment as part of its own acceptance tests.

This GDD owns only the within-floor anchor-honoring procedure. Cross-floor coordination is the caller's job.

---

## 10. Rasterization

The planning pipeline (§4.1 steps 2-7) emits geometric primitives: `Array[RoomPlan]`, `Array[CorridorPlan]`, `Array[DoorPlan]`, `Array[StairPlan]`. The rasterization step (§4.1 step 8) converts these into the final `Array[Array[DungeonCellData]]` grid.

### 10.1 Rasterization Procedure

```
rasterize(rooms, corridors, doors, stairs, width, height) -> Array[Array[DungeonCellData]]:
  1. Allocate width × height cells, all default = solid rock (passable=false,
     blocks_los=true, terrain_feature=FEATURE_ROCK, room_id=-1).

  2. Stamp room interiors:
     for each RoomPlan, for each cell inside its bounds:
       cell.terrain_feature = FEATURE_OPEN
       cell.passable = true
       cell.blocks_los = false
       cell.room_id = room.id
       cell.is_corridor = false

  3. Stamp room perimeter walls:
     for each RoomPlan, for each cell on its 1-cell-thick perimeter band:
       if the cell is NOT inside another room (i.e., adjacent rooms share
         walls and the cell stays solid wall between them):
           cell.terrain_feature = FEATURE_WALL_STONE
           cell.passable = false
           cell.blocks_los = true

  4. Stamp corridor centerlines + width:
     for each CorridorPlan, for each centerline cell:
       for each per-width footprint cell (corridor.width cells centered):
         if the cell is NOT inside a room (corridor passes around rooms,
           never through — see §7.3 step 4 exception for forced crossings):
             cell.terrain_feature = FEATURE_OPEN
             cell.passable = true
             cell.blocks_los = false
             cell.is_corridor = true
             cell.room_id = -1

  5. Stamp doors:
     for each DoorPlan:
       cell.terrain_feature = door-type-specific FEATURE_DOOR_* constant
       cell.passable = (type == arch)  # arches are open passages
       cell.blocks_los = (type != portcullis and type != arch)
       cell.door_state = "open" for arches, "locked" for locked / trapped,
                          "closed" otherwise
       cell.door_detected = (type != secret)

  6. Stamp stairs:
     for each StairPlan:
       cell.terrain_feature = FEATURE_STAIRS_UP or FEATURE_STAIRS_DOWN
       cell.passable = true
       cell.blocks_los = false
       # Stairs sit inside rooms, so cell.room_id is preserved from step 2.

  Return the fully-populated cells grid.
```

The rasterizer is deterministic and idempotent — re-running it on the same plan produces the same grid.

Door cells sit between two floor cells. When closed, a door cell is impassable (blocks movement) and blocks LOS (except for portcullis, which blocks movement but not LOS). When open, a door cell is passable and does not block LOS.

### 10.2 Room Detection (Verification Only)

Unlike grid-fill maze generators, this pipeline does NOT need flood-fill room detection to figure out which cells belong to which room — it already knows from the room plans. The rasterizer stamps `room_id` directly per step 2.

A flood-fill **verification pass** can optionally run after rasterization to sanity-check that the rasterized rooms are connected internally and disconnected from each other through door cells (catches programmer errors in the rasterizer, not user-facing failures). This pass walks each `RoomPlan.bounds`, flood-fills connected `passable && !is_corridor` cells, and asserts the resulting region exactly matches the plan's cell set.

The verification pass is on by default in debug builds and off in release builds. It is NOT the canonical room-detection mechanism — the plan IS the room definition.

---

## 11. Output Data Structure

The generator outputs a `DungeonLayout` that matches the project's dungeon data model:

```
DungeonLayout:
  dungeon_id: string
  dungeon_type: string           # From the ACKS d20 table
  dungeon_size: string           # lair / small / medium / large
  structure_type: string         # "subterranean" or "above_ground" — controls multi-level spatial rules
  level_number: int              # Which level this is
  grid_width: int                # In 5' cells
  grid_height: int               # In 5' cells
  
  cells: Array[Array[CellData]]  # 2D grid
  # CellData:
  #   elevation: int              # 0-30, each unit = 2.5 feet (per gdd-combat-map-generation.md §4)
  #   terrain_feature: string     # "open", "rock", "wall_stone", "wall_wood", "door",
  #                               #   "door_locked", "door_secret", "portcullis",
  #                               #   "stairs_up", "stairs_down"
  #   passable: bool              # false for walls, rock, closed doors
  #   blocks_los: bool            # false for open, stairs; true for walls, rock, closed doors
  #                               #   (portcullis: blocks movement but not LOS)
  #   door_state: string or null  # null if not a door; "open", "closed", "locked", "stuck"
  #   door_detected: bool         # For secret doors — false until found
  #   room_id: int or null
  #   is_corridor: bool
  #   contents: null              # Populated by stocking, not layout
  
  rooms: Array[RoomData]
  # RoomData:
  #   id: int
  #   cells: Array[Vector2i]     # Grid coordinates of constituent cells
  #   bounds: Rect2i             # Bounding box
  #   area_sqft: int             # In square feet (cell count × 25)
  #   center: Vector2i           # Center cell
  #   doors: Array[DoorData]     # Doors on this room's perimeter
  #   original_purpose: string   # What this room was built for (from §6.3 purpose table)
  #   current_purpose: string    # What the room is used for now (assigned by stocking, initially null)
  #   contents: null             # Populated by stocking
  
  doors: Array[DoorData]
  # DoorData:
  #   position: Vector2i         # Grid cell of the door (the door IS this cell)
  #   type: string               # arch / unlocked / locked / trapped / portcullis
  #                              # NOTE: 'secret' is NO LONGER a type value (as of 2026-05-27).
  #                              # Secret is now an overlay via is_secret (below) because a door
  #                              # may be both Locked AND Secret simultaneously; once detected, a
  #                              # secret door is never secret again, so the overlay can be flipped
  #                              # at runtime without altering the door's underlying type.
  #   is_secret: bool            # Overlay flag (added 2026-05-27). Orthogonal to type.
  #                              # When true, the door is concealed: blocks BFS / LOS for parties
  #                              # that have not detected it. Once detected (via Search action at
  #                              # runtime), is_secret remains true for data continuity but
  #                              # door_detected flips to true and the door functions per its type.
  #                              # A door rolled as 'secret' at §8.1 produces type="unlocked" or
  #                              # type="locked" (per the door's underlying access state) PLUS
  #                              # is_secret=true. The §11.4 trap-placeholder fallback in
  #                              # gdd-dungeon-generator-v1.md sets is_secret=true on a Locked door
  #                              # to produce the Locked+Secret combination.
  #   connects: Array[int]       # Room IDs this door connects (may include corridor pseudo-room)
  #   door_material: string      # "" (none/arch) / curtain_cloth / curtain_leather /
  #                              #   wood_standard / wood_thick / stone / metal
  #                              # Determines Bash Door availability (see gdd-dungeon-map-ui.md §4.2.1):
  #                              #   curtains → free passage; wood_* → bashable with axe;
  #                              #   stone / metal → unbashable.
  #                              # Populated per §8.3 (rev 2026-05-27 — canonical 6-material set).
  #                              # §8.3 produces only "", metal, stone, wood_standard; curtains
  #                              # and wood_thick come from V2 themes / lairs / hand-authoring.
  #   is_evil: bool              # Default false. Evil doors auto-close every turn (60 rounds)
  #                              # unless wedged, spiked, held, bashed, or magically held
  
  stairs: Array[StairData]
  # StairData:
  #   position: Vector2i
  #   direction: string          # "up" or "down"
  #   connects_to_level: int     # Which dungeon level this leads to
  
  entrance: Vector2i             # Grid position of the dungeon entrance
  
  theme: DungeonTheme            # The theme parameters used for generation
  encounter_table: Array         # Themed encounter table built from monster catalog
  
  # Metadata for LLM context generation
  generation_seed: int           # For reproducibility
  type_description: string       # Human-readable: "This is an abandoned mine..."
```

---

## 12. Integration Points

### 12.1 Who Calls This Generator

The generator is called by the region zoom-in pipeline (§14A.3) or dungeon stocking pipeline (§14A.4) when a dungeon seed needs to be expanded into a playable map. The caller provides:
- Dungeon type (from the d20 table or manually assigned)
- Dungeon size category
- Dungeon level range (affects stocking, not layout)
- Regional context (for encounter table construction)

### 12.2 What Happens After Layout

1. **ACKS stocking** (from XML rules reference) — rolls room contents per the stocking tables
2. **Faction generation** (from `gdd-faction-generation.md`) — assigns factions to monster groups
3. **LLM narrative pass** — generates room descriptions, dungeon history, names
4. **Encounter table attachment** — the themed encounter table is stored with the dungeon

### 12.3 Rendering

The output `DungeonLayout` is rendered by the dungeon map renderer as a true runtime 3D tactical scene (per `gdd-combat-map-generation.md` §12). Wall cells, floor cells, door cells, and corridor cells map directly to 3D tactical surfaces and blocking geometry. Room interiors and corridors are walkable floor cells; wall cells and rock cells are impassable solid geometry. The cell-based wall model still maps cleanly to rendering because each cell IS either passable or impassable; the renderer simply presents that state in 3D rather than through 2D autotiling.

### 12.4 Stronghold Claiming

A cleared dungeon may be claimed as a stronghold or sanctum by a qualifying character (see `gdd-stronghold-construction.md` §8.4). When this occurs, the DungeonLayout is wrapped in a StrongholdLayout shell — the dungeon's grid, cells, rooms, doors, and stairs become the stronghold's interior navigation map and battle map. Both systems share the same 5' cell-based diamond grid and wall model, so no conversion is required. The stronghold planner's edit mode (§8.5) then allows the player to commission expansions (surface fortifications, additional underground rooms) that connect to the existing dungeon layout.

---

## 13. Godot Implementation Notes

### 13.1 No Godot-Native Dungeon Generation

Godot provides the 3D scene, camera, mesh, and material systems needed to render the dungeon, but no built-in procedural generator. The entire generation algorithm lives in GDScript as pure data manipulation on geometric primitives plus one rasterization pass at the end. Godot's contribution is rendering the output, not generating it.

### 13.2 Key Godot Classes Used

- `Node3D` / `Camera3D` / generated mesh instances — render the dungeon as a 3D tactical scene
- `RandomNumberGenerator` — seeded RNG for reproducible generation
- `Vector2i` — grid coordinate math
- `Rect2i` — room bounding boxes
- `AStarGrid2D` — optional, for pathfinding validation (ensuring all rooms are reachable)

### 13.3 Performance

Generation is a one-time cost per dungeon level. Even the largest grids (79×79 = ~6,200 cells) should generate in under 100ms on modern hardware. The bitmask approach is cache-friendly and avoids object allocation during the hot loop.

### 13.4 File Organization

```
engine/subsystems/generation/dungeon_layout/
  dungeon_layout_generator.gd   # Top-level orchestrator (generate(request))
  dungeon_layout_request.gd     # Input shape (dungeon_type, size, seed, …)
  dungeon_room_composer.gd      # Plans rooms + connection graph + corridors
                                #   + doors + stairs (geometric primitives only)
  dungeon_layout_rasterizer.gd  # Stamps geometric plan onto DungeonCellData grid
  dungeon_theme.gd              # DungeonTheme parameter shape (§5.1)
  dungeon_theme_catalog.gd      # Theme lookup with V1 fallback (Wizard's Dungeon)
```

The geometric output types (`DungeonLayout`, `DungeonCellData`, `DungeonRoomData`, `DungeonDoorData`, `DungeonStairData`) live under `engine/shared_types/` because they cross subsystem boundaries (the V1 dungeon-generator orchestrator, the runtime tactical loader, the persistence layer, and the renderer all consume them).

---

## 14. Design Decisions (Resolved)

- **Cavern generation: DECIDED.** Natural cavern types (Natural caverns, Giant burrow, Underground river, Giant insect hive) use cellular automata smoothing after initial room placement to produce organic shapes. The procedure: place rooms normally, then run 3-5 iterations of cellular automata (a cell becomes open if 4+ of its 8 neighbors are open, becomes wall if fewer than 4 are open) on the room interior cells only (not corridors). This erodes sharp corners and produces cave-like irregular boundaries while preserving corridor connectivity.
- **Room purpose assignment: DECIDED.** The generator assigns an **original purpose** to each room based on dungeon type (e.g., an Abandoned Mine has bunk rooms, ore storage, tool sheds, shaft heads, foreman's office). The stocking procedure then assigns a **current purpose** based on what the stocking tables placed there (if the room got a monster + treasure, and the monster's lair is the adjacent room, the room's current purpose becomes "treasure hoard" even though its original purpose was "miners' bunkroom"). Both purposes are stored: `room.original_purpose` feeds the LLM's physical description (bunks still line the walls), while `room.current_purpose` feeds the LLM's narrative of what's happening now (but the bunks are shoved aside and the space is piled with stolen goods). Original purpose is generated per dungeon type from a purpose table (see §6.3).
- **Multi-level spatial coherence: DECIDED.** Two modes based on dungeon type:
  - **Subterranean dungeons** (mines, caverns, catacombs, sewers, etc.): Levels are generated independently. They do NOT constrain each other in size or shape. The only requirement is that stair positions match across levels — a stair-down on level 2 at grid position (15, 22) must correspond to a stair-up on level 3 at position (15, 22). Each level can have a completely different layout, grid size, and room arrangement.
  - **Above-ground structures** (Tower, Ruined manor, Crumbling castle, Cliff city): Levels should roughly match spatially. The generator uses the first (ground) level's footprint as a constraint for upper levels — upper levels must fit within the ground level's bounding box (with some variance: ±10-20% per dimension, and upper levels of towers should get progressively smaller). Stair positions must match. Interior walls do NOT need to align between floors.
- **Corridor width: DECIDED.** The default corridor width is **10'** (2 cells wide), which is the ACKS norm. The generator must carve 2-wide corridors instead of the donjon default of 1-wide. Supported widths: 5' (1 cell, tight/cramped), 10' (2 cells, standard), 15' (3 cells, wide), 20' (4 cells, grand hall corridors). Most corridors should be 10' or 20'. The theme table's `corridor_width` field is updated to reflect this — see §5.2 revised. Implementation: the tunnel algorithm carves a 2-cell-wide path by default. When the theme specifies "narrow," it drops to 1-cell. For "wide," it carves 3 cells. For "mixed," each corridor segment randomly selects between 10' and 20' with occasional 5' tight spots.

---

## 15. Revision History

- **2026-03-10:** Initial draft. Dungeon type theming table designed from ACKS flavor table. ACKS placement constraints documented.
- **2026-03-10 (rev 2):** All four open questions resolved. Cellular automata for cavern types. Dual room purpose system (original + current). Multi-level rules split by structure type (subterranean vs above-ground). Corridor width standardized to 10' default with width variation by theme. Room purpose tables added per dungeon type. Corridor generation updated for 2-cell-wide default carving.
- **2026-03-25:** Grid system unified with project-wide diamond grid (per `gdd-combat-map-generation.md` §3). Replaced edge-based wall model with cell-based walls — walls are impassable cells, doors are cells with state. Eliminated edge-model conversion step (§10); generator's native cell output IS the final wall model. Updated CellData to include elevation, door_state, door_detected fields. Updated file organization (edge_converter.gd → cell_finalizer.gd).
- **2026-04-14:** Added `door_material` (string) and `is_evil` (bool) fields to DoorData schema (§11). Required by `gdd-dungeon-map-ui.md` for Bash Door mechanics and evil door auto-close scheduler events.
- **2026-05-27:** Re-flavored Wizard's Dungeon in §5.2 as the universal generic-fallback type (drops the `construct/arcane/aberration/fiend` flavor tags). Added §5.3 note that Wizard's Dungeon does NOT use tag-filtered encounter table construction — it uses the raw Random Monsters by Level table directly. Added §8.3 "Door Material and Tier-Scaled Portcullis Override" specifying the per-door material roll: default `wood_standard`, with a 5%-per-tier chance of metal (iron/stone 50/50) and a separate 5%-per-tier chance of portcullis override. Both edits driven by `gdd-dungeon-generator-v1.md` V1 requirements.
- **2026-05-27 (rev 2):** Algorithm rewrite. §4 / §6.1 / §7 / §8.1 / §9.3.2 / §10 / §13 rewritten for a **rooms-first** pipeline (geometric room placement → MST connection graph → A*/L-shape corridor routing → rasterization) replacing the previous bitmask-grid maze-fill approach. The new algorithm matches ACKS published dungeon style more closely: supports adjacent rooms sharing walls (`Sakkara` rooms 7-8, 12-13, 22-23), produces L-bend corridor geometry by construction, and avoids the negative-space-is-maze model that constrained room compositions. §11 DungeonLayout output schema is unchanged; rasterization (§10.1) replaces the previous bitmask→CellData conversion. New §4.2 "Internal Representation" describes the typed geometric plan that planning steps 2-7 manipulate. §6 collision check now allows adjacent rooms with shared walls. §7 introduces the MST-plus-loops connection graph (§7.2) and the L-shape-first corridor router (§7.3). §7.3 / §7.4 dead-end removal is removed (corridors connect rooms by construction; no dead-end formation). §13.4 file organization updated.
