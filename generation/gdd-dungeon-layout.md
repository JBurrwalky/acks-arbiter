# GDD: Dungeon Layout Generation

**Authority:** PROJECT-DESIGNED — the layout algorithm is not derived from any ACKS sourcebook. ACKS dungeon stocking procedures (room contents, monsters, traps, treasure) are defined in the XML rules reference library and applied AFTER layout generation.
**Status:** Draft
**Depends on ACKS rules:** `acore-setting-construction-rules.xml` (dungeon stocking tables, dungeon type/flavor table, special features — applied after layout, not during)
**Modifiable by Claude Code:** Yes — suggest improvements freely. The algorithm, parameters, and room templates are all engineering decisions.
**Last updated:** 2026-03-25

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

The generator is adapted from the donjon random dungeon generator (Creative Commons BY-NC 3.0, by drow/donjon.bin.sh), translated to GDScript and extended with dungeon-type theming, ACKS-compatible cell-based walls, and faction-aware spatial properties.

### 4.1 Core Pipeline

```
1. SEED PARAMETERS → determine grid size, room count, room size ranges, corridor style from dungeon type + size category
2. INIT GRID → 2D array of cell bitmasks, all cells start as solid rock
3. PLACE ROOMS → scatter rectangular rooms onto the grid, mark cells as ROOM, mark perimeters
4. OPEN DOORS → for each room, open doorways on the perimeter connecting to adjacent rooms or corridor space
5. TUNNEL CORRIDORS → recursive maze carving fills remaining space with corridors connecting room doors
6. PLACE STAIRS → find suitable corridor dead-ends or room locations for up/down stairs
7. CLEAN → remove percentage of dead-end corridors (configurable)
8. FINALIZE CELLS → convert bitmask grid to CellData grid (passable/impassable, terrain_feature, door_state per bitmask flags). No wall model conversion needed — the cell grid IS the wall model.
9. DETECT ROOMS → flood-fill connected open regions to assign room IDs
10. APPLY THEME → adjust door types, corridor widths, room shapes based on dungeon type
11. OUTPUT → DungeonLayout data structure ready for ACKS stocking
```

### 4.2 Grid Data Model (Generation-Time)

During generation, the grid uses cell bitmasks for efficient manipulation (adapted from donjon). Each cell is an integer with bitflags:

```
NOTHING    = 0x00000000  # Solid rock
BLOCKED    = 0x00000001  # Permanently blocked (outside dungeon boundary)
ROOM       = 0x00000002  # Room interior
CORRIDOR   = 0x00000004  # Corridor
PERIMETER  = 0x00000010  # Room perimeter (prevents corridor encroachment)
ENTRANCE   = 0x00000020  # Doorway/entrance
ROOM_ID    = 0x0000FFC0  # Room ID encoded in bits 6-15 (supports up to 1023 rooms)
ARCH       = 0x00010000  # Open archway
DOOR       = 0x00020000  # Unlocked door
LOCKED     = 0x00040000  # Locked door
TRAPPED    = 0x00080000  # Trapped door
SECRET     = 0x00100000  # Secret door
PORTCULLIS = 0x00200000  # Portcullis
STAIR_DN   = 0x00400000  # Stairs down
STAIR_UP   = 0x00800000  # Stairs up
```

After generation, the bitmask grid is converted to the project's standard CellData grid for runtime use. Because the project uses cell-based walls, this is a direct translation of bitmask flags to CellData properties — no structural conversion is needed.

### 4.3 Grid Sizing

The generation grid uses odd-numbered dimensions (following donjon's convention where rooms and corridors fall on odd cells, walls on even cells). This simplifies room placement and corridor carving.

| Dungeon Size | Grid (cells) | Effective Map Area | Notes |
|---|---|---|---|
| Lair | 21 × 21 | ~50' × 50' | Tight, few rooms |
| Small | 31 × 31 | ~75' × 75' | Compact single level |
| Medium | 51 × 51 | ~125' × 125' | Room to spread out |
| Large (per level) | 79 × 79 | ~195' × 195' | Spacious, multiple wings |

Each grid cell represents a 5' × 5' area in world space (rendered as an isometric diamond). The effective area is smaller than grid_size × 5' because the grid uses every-other-cell for rooms/corridors.

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
| Wizard's dungeon | mixed | bent | 60% | 0.3 | mixed | standard | construct, arcane, aberration, fiend |

### 5.3 Themed Encounter Tables

Each dungeon type's `encounter_flavor` tags are used to build a custom encounter table from the available monster catalog:

1. Query the monster catalog for entries matching any of the dungeon type's flavor tags
2. Filter by dungeon level (HD-appropriate monsters)
3. Weight by tag match count (a monster matching 2 tags is weighted higher than one matching 1)
4. Apply the standard ACKS encounter table construction guidelines (from ACore Secrets chapter)
5. Store as the dungeon's custom wandering monster table

Claude Code can implement this table construction — the ACKS guidelines for building custom tables exist in the source material. The resulting tables should be stored as editable JSON so they can be hand-tuned after generation.

---

## 6. Room Placement Algorithm

Adapted from donjon's "Scattered" mode (preferred over "Packed" for ACKS-style dungeons).

### 6.1 Procedure

```
1. Calculate target room count from dungeon size category
2. Calculate room size range from theme's room_size_bias:
   - small: min 2, max 4 (in half-grid units → 10'-20' rooms)
   - mixed: min 2, max 6 (10'-30' rooms)
   - large: min 3, max 8 (15'-40' rooms)
   - huge: min 4, max 10 (20'-50' rooms)
3. Attempt to place (target_rooms × 2) rooms (some will fail collision checks):
   a. Generate random room width and height within range
   b. Generate random position on the grid (aligned to odd cells)
   c. Check for collisions with existing rooms (including perimeter buffer)
   d. If no collision: mark cells as ROOM, mark perimeter cells as PERIMETER
   e. If collision: discard and try next
4. Record each room's bounds, area, and center point
```

### 6.2 Room Shape Variation

For dungeon types with `room_shape: "irregular"` or `"mixed"`:

After placing the base rectangular room, optionally modify it:
- **L-shape:** Remove a rectangular notch from one corner (25% chance for irregular)
- **T-shape:** Extend a rectangular protrusion from one side (15% chance)
- **Round:** Place a circular room instead of rectangular (10% chance for irregular themes; achieved by blocking corner cells of a square room)

For `"rectangular"` themes, all rooms are axis-aligned rectangles (the default).

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

Adapted from donjon's recursive maze-carving tunnel algorithm, extended to support **2-cell-wide corridors** as the ACKS standard (10' wide).

### 7.1 Corridor Width

The default corridor width is **10' (2 cells)**, matching the ACKS standard. The algorithm carves corridors 2 cells wide instead of donjon's original 1-cell-wide.

Width selection per corridor segment:
- **"narrow"** theme: all corridors are 5' (1 cell). Used for Barrow mound, Tower.
- **"standard"** theme: all corridors are 10' (2 cells). Used for most dungeon types.
- **"wide"** theme: corridors are 70% at 10' (2 cells) and 30% at 20' (4 cells). Main passages tend toward 20', side passages toward 10'. Used for Temple, Natural caverns, Giant burrow, etc.
- **"mixed"** theme: corridors are 50% at 10', 30% at 20%, 15% at 5', 5% at 15'. Produces variety. Used for Abandoned mine, Giant insect hive, etc.

Implementation note: 2-wide carving requires the grid to have enough space between rooms. The room perimeter buffer (the PERIMETER cells around each room) naturally provides this spacing. The tunneling algorithm checks a 2-cell-wide path instead of a 1-cell path when determining if a tunnel can be opened.

### 7.2 Procedure

```
1. For each odd-indexed cell in the grid that is not already ROOM or CORRIDOR:
   a. Begin recursive tunneling from this cell
   b. At each step, choose a direction (N/S/E/W):
      - For "straight" corridors: 100% chance to continue in same direction
      - For "bent" corridors: 50% chance to continue, 50% to turn
      - For "labyrinth" corridors: 0% chance to continue (pure random)
   c. Check if the next cell (and the wall cell between) are unoccupied
   d. If valid: mark both cells as CORRIDOR, recurse from the new cell
   e. If invalid: try another direction
   f. If all directions exhausted: backtrack (end of recursive branch)
2. This fills all reachable space with a perfect maze of corridors
3. The corridors will naturally connect to room perimeters via door openings
```

### 7.3 Loop Creation

After corridor generation, optionally add loops (connections between existing corridors/rooms that create alternate paths). For each candidate loop point:

1. Find corridor dead-ends adjacent to other corridors or rooms (separated by one wall cell)
2. With probability = theme's `loop_frequency`, remove the wall cell to create a shortcut
3. This converts dead-ends into connected loops, making the dungeon less tree-like

### 7.4 Dead-End Removal

After corridor generation and loop creation:

1. Scan for corridor cells with only one open neighbor (dead-ends)
2. With probability = theme's `dead_end_removal` percentage, fill in the dead-end cell (set to NOTHING)
3. Recurse: the cell behind the removed dead-end may now itself be a dead-end
4. This trims unused corridor stubs while preserving the main path network

---

## 8. Door Placement

### 8.1 Procedure

For each room:

1. Identify all "sill" positions — room cells adjacent to the perimeter, where a door could open onto a corridor or another room
2. Calculate target door count: `sqrt(room_area_in_grid_units) + random(0, sqrt(room_area))`
3. For each door to place:
   a. Select a random sill from the available list
   b. Check that the cell beyond the perimeter (the "outside" cell) is valid corridor or room space
   c. Mark the perimeter cell as a door type based on weighted random:
      - Archway (open): 15%
      - Unlocked door: 40%
      - Locked door: 15%
      - Trapped door: 10%
      - Secret door: 10%
      - Portcullis: 10%
4. Theme overrides can shift these weights (e.g., Prisons have more locked doors, Tombs have more secret doors)

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

---

## 10. Cell Finalization and Room Detection

After generation, convert the bitmask grid to the project's standard CellData grid and detect rooms.

### 10.1 Cell Finalization

For each cell in the bitmask grid, produce a CellData:
1. If cell has ROOM or CORRIDOR flag: `passable = true`, `terrain_feature = "open"`
2. If cell has NOTHING flag (solid rock): `passable = false`, `terrain_feature = "rock"`
3. If cell has PERIMETER flag and no ENTRANCE: `passable = false`, `terrain_feature = "wall_stone"` (or theme-appropriate wall type)
4. If cell has a door flag (DOOR, LOCKED, TRAPPED, SECRET, PORTCULLIS): `passable` depends on door state, `terrain_feature` = door type, `door_state` = initial state per type, `door_detected = false` for SECRET doors
5. If cell has STAIR_UP or STAIR_DN: `passable = true`, `terrain_feature = "stairs_up"` or `"stairs_down"`

Door cells sit between two floor cells. When closed, a door cell is impassable (blocks movement) and blocks LOS (except for portcullis, which blocks movement but not LOS). When open, a door cell is passable and does not block LOS.

### 10.2 Room Detection

After cell finalization, run flood-fill to assign room IDs:
1. For each unassigned passable cell, flood-fill to all connected passable cells bounded by impassable cells and door cells
2. Assign a room ID to the group
3. Record room metadata: constituent cells, bounding box, area, center point, door list (door cells adjacent to the room's floor cells)
4. This produces the `Room` data structures that the ACKS stocking procedure will populate

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
  #   type: string               # arch / unlocked / locked / trapped / secret / portcullis
  #   connects: Array[int]       # Room IDs this door connects (may include corridor pseudo-room)
  
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

The output `DungeonLayout` is rendered by the dungeon map renderer using Godot's isometric TileMap system (per `gdd-combat-map-generation.md` §12). Wall cells, floor cells, door cells, and corridor cells each map to tile types. Room interiors and corridors are floor tiles; wall cells and rock cells are impassable solid tiles. The cell-based wall model maps cleanly to TileMap autotile rules — each cell IS either passable or impassable, and the autotile system handles visual wall-face presentation based on neighbor adjacency.

### 12.4 Stronghold Claiming

A cleared dungeon may be claimed as a stronghold or sanctum by a qualifying character (see `gdd-stronghold-construction.md` §8.4). When this occurs, the DungeonLayout is wrapped in a StrongholdLayout shell — the dungeon's grid, cells, rooms, doors, and stairs become the stronghold's interior navigation map and battle map. Both systems share the same 5' cell-based diamond grid and wall model, so no conversion is required. The stronghold planner's edit mode (§8.5) then allows the player to commission expansions (surface fortifications, additional underground rooms) that connect to the existing dungeon layout.

---

## 13. Godot Implementation Notes

### 13.1 No Godot-Native Dungeon Generation

Godot provides TileMap/TileMapLayer for rendering grids but no built-in procedural generation. The entire generation algorithm lives in GDScript as pure data manipulation on 2D arrays. Godot's contribution is rendering the output, not generating it.

### 13.2 Key Godot Classes Used

- `TileMapLayer` — renders the generated dungeon (floor tiles, wall autotiling)
- `RandomNumberGenerator` — seeded RNG for reproducible generation
- `Vector2i` — grid coordinate math
- `Rect2i` — room bounding boxes
- `AStarGrid2D` — optional, for pathfinding validation (ensuring all rooms are reachable)

### 13.3 Performance

Generation is a one-time cost per dungeon level. Even the largest grids (79×79 = ~6,200 cells) should generate in under 100ms on modern hardware. The bitmask approach is cache-friendly and avoids object allocation during the hot loop.

### 13.4 File Organization

```
engine/subsystems/generation/dungeon_layout/
  dungeon_generator.gd        # Main generator class
  dungeon_theme.gd             # Theme parameter definitions
  dungeon_theme_data.json      # Theme table (the §5.2 table as data)
  grid_operations.gd           # Cell bitmask operations, room placement, tunneling
  cell_finalizer.gd            # Bitmask grid → CellData grid conversion
  room_detector.gd             # Flood-fill room detection
  encounter_table_builder.gd   # Themed encounter table construction
```

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

- **2026-03-10:** Initial draft. Algorithm adapted from donjon dungeon generator. Dungeon type theming table designed from ACKS flavor table. ACKS placement constraints documented.
- **2026-03-10 (rev 2):** All four open questions resolved. Cellular automata for cavern types. Dual room purpose system (original + current). Multi-level rules split by structure type (subterranean vs above-ground). Corridor width standardized to 10' default with width variation by theme. Room purpose tables added per dungeon type. Corridor generation updated for 2-cell-wide default carving.
- **2026-03-25:** Grid system unified with project-wide diamond grid (per `gdd-combat-map-generation.md` §3). Replaced edge-based wall model with cell-based walls — walls are impassable cells, doors are cells with state. Eliminated edge-model conversion step (§10); generator's native cell output IS the final wall model. Updated CellData to include elevation, door_state, door_detected fields. Updated file organization (edge_converter.gd → cell_finalizer.gd).
