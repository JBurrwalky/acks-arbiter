class_name DungeonCellData
extends RefCounted

## A single cell in a generated dungeon layout (2D grid representation).
##
## Per `gdd-dungeon-layout.md` §11 (BASELINE schema — the §11 schema additions
## introduced 2026-05-27 like the DoorData `is_secret` overlay are NOT here;
## door state lives on DoorData, not CellData).
##
## The layout generator emits a 2D `Array[Array[DungeonCellData]]` grid where
## each cell describes the static terrain at that grid coordinate. Downstream
## systems (the V1 generator orchestrator, the runtime 3D voxel loader) consume
## this grid; they do NOT mutate it.
##
## Coordinate convention: Vector2i(x, y). x = column (0..grid_width-1),
## y = row (0..grid_height-1). Rooms and corridors are stamped onto contiguous
## cells by the rasterization step (layout GDD §10.1); walls occupy whatever
## cells are not part of any room/corridor footprint.
##
## Each grid cell represents 5 feet square (the project's unified 5' diamond
## grid; see coding_conventions.md §53). Elevation defaults to 0 (ground level);
## the layout generator does not assign elevation in V1 — multi-elevation
## features are handled at the runtime voxel layer.


# ---------------------------------------------------------------------------
# Terrain feature vocabulary
# ---------------------------------------------------------------------------

const FEATURE_OPEN := "open"
const FEATURE_ROCK := "rock"
const FEATURE_WALL_STONE := "wall_stone"
const FEATURE_WALL_WOOD := "wall_wood"
const FEATURE_DOOR := "door"
const FEATURE_DOOR_LOCKED := "door_locked"
const FEATURE_DOOR_SECRET := "door_secret"
const FEATURE_PORTCULLIS := "portcullis"
const FEATURE_STAIRS_UP := "stairs_up"
const FEATURE_STAIRS_DOWN := "stairs_down"

## DG-V1.B-base note: this vocabulary preserves "door_secret" as a feature
## value because the BASELINE §11 schema still treats "secret" as a door
## category. DG-V1.B-edits will refactor to is_secret overlay on DoorData.


# ---------------------------------------------------------------------------
# Spatial + static terrain
# ---------------------------------------------------------------------------

## Elevation in 2.5' units (per `gdd-combat-map-generation.md` §4). Range 0-30.
## V1 layout generator emits 0 uniformly; multi-elevation is V2.
var elevation: int = 0

## See FEATURE_* constants above. Defaults to FEATURE_ROCK so an unset cell
## is the safe "impassable solid rock" baseline.
var terrain_feature: String = FEATURE_ROCK

## False for walls, rock, closed doors; true for open / corridor / stair cells.
var passable: bool = false

## False for open cells and stairs; true for walls, rock, closed solid doors.
## Portcullises block movement but NOT LOS — set blocks_los = false for them.
var blocks_los: bool = true


# ---------------------------------------------------------------------------
# Door state (only meaningful when terrain_feature is a door variant)
# ---------------------------------------------------------------------------

## "" if not a door; otherwise "open" | "closed" | "locked" | "stuck".
## Per §11 the door's PERSISTENT properties (type, material) live on DoorData;
## the CellData just mirrors the current runtime state for fast lookups during
## movement / LOS queries.
var door_state: String = ""

## For SECRET doors — false until detected via Search action.
## DG-V1.B-base sets this from the bitmask SECRET flag at finalization.
var door_detected: bool = false


# ---------------------------------------------------------------------------
# Room association
# ---------------------------------------------------------------------------

## -1 if this cell is not in a detected room (corridor, wall, rock).
## Otherwise the integer id of the DungeonRoomData this cell belongs to.
var room_id: int = -1

## True if the cell was carved as a corridor (vs. placed as part of a room).
## A door cell sits on a room perimeter and is_corridor = false there.
var is_corridor: bool = false


# ---------------------------------------------------------------------------
# Convenience
# ---------------------------------------------------------------------------

## True if this cell is a door of any kind (closed or open, any type).
func is_door() -> bool:
	return (terrain_feature == FEATURE_DOOR
		or terrain_feature == FEATURE_DOOR_LOCKED
		or terrain_feature == FEATURE_DOOR_SECRET
		or terrain_feature == FEATURE_PORTCULLIS)


## True if this cell is a stair of either direction.
func is_stair() -> bool:
	return terrain_feature == FEATURE_STAIRS_UP or terrain_feature == FEATURE_STAIRS_DOWN
