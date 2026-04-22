class_name VoxelCell
extends RefCounted

## A single 5-foot cube cell in the voxel grid.
##
## Replaces the flat Dictionary-based cell storage from TacticalMapData with a
## typed class. Derived properties (passability, LOS blocking, etc.) are computed
## on read, not stored.
##
## Coordinate convention: (col, row, level) where level is the integer vertical
## cell index. Level 0 is the canonical ground plane; positive = up, negative = down.
## Each level represents 5 vertical feet.
##
## See gdd-voxel-tactical-architecture.md section 7 for the full schema.


# ---------------------------------------------------------------------------
# Spatial identity
# ---------------------------------------------------------------------------

var col: int = 0
var row: int = 0
var level: int = 0


# ---------------------------------------------------------------------------
# Cell contents
# ---------------------------------------------------------------------------

## "air" | "solid" | "liquid"
var solidity: String = "air"

## Terrain feature vocabulary (see GDD section 7.1).
## Common values: "open", "rock", "wall_stone", "wall_wood", "pillar",
## "stairs_up_N" .. "stairs_down_SW", "ramp_N" .. "ramp_SW", "ladder",
## "window", "arrow_slit", "murder_hole", "water_shallow", "water_deep",
## "air_open", "burrow_tunnel"
var feature: String = "open"

## Floor at the bottom face of this cube. "none" means empty airspace.
## Common values: "none", "stone", "wood", "grate", "pit_cover", "trap_door",
## "rubble", "ice", "grass", "dirt"
var floor_type: String = "none"


# ---------------------------------------------------------------------------
# Door state
# ---------------------------------------------------------------------------

## "" | "open" | "closed" | "locked" | "stuck" | "destroyed"
var door_state: String = ""

## "" | "arch" | "unlocked" | "locked" | "trapped" | "secret" | "portcullis"
var door_type: String = ""

var door_detected: bool = false

## Evil doors auto-close on turn tick unless wedged or spiked.
var is_evil: bool = false

## Explicit stair-pair target (voxel cell coordinate). When set (any component
## != -1), overrides the direction-suffix inference in
## DungeonMapController.get_stair_target. Used when stair geometry doesn't
## permit a single-step diagonal (e.g. multi-level jumps, hand-authored dungeons
## whose stair destinations are not spatially adjacent).
var stair_target_col: int = -1
var stair_target_row: int = -1
var stair_target_level: int = -1


# ---------------------------------------------------------------------------
# Dungeon / room metadata
# ---------------------------------------------------------------------------

var room_id: int = -1
var is_corridor: bool = false


# ---------------------------------------------------------------------------
# Fog of war
# ---------------------------------------------------------------------------

## "hidden" | "explored" | "visible"
var fog_state: String = "hidden"


# ---------------------------------------------------------------------------
# Cover & combat
# ---------------------------------------------------------------------------

## 0-4, per ACKS cover rules.
var cover_value: int = 0


# ---------------------------------------------------------------------------
# Convenience
# ---------------------------------------------------------------------------

## Returns the cell's grid position as a Vector3i(col, row, level).
var pos: Vector3i:
	get:
		return Vector3i(col, row, level)


# ---------------------------------------------------------------------------
# Derived properties (computed on read, not stored)
# ---------------------------------------------------------------------------

## Whether a ground-walking creature can occupy this cell (ignoring support).
## Support checking (floor_type / solid below) is the pathfinder's job.
func is_passable_by_walker() -> bool:
	if solidity != "air":
		return false
	if door_state == "closed" or door_state == "locked" or door_state == "stuck":
		return false
	return true


## Whether this cell blocks line of sight for ranged attacks / fog reveals.
## Solid cells block except arrow_slit, window, and portcullis features.
## Closed/locked doors block except portcullis type.
func blocks_los() -> bool:
	if solidity == "solid":
		return feature != "arrow_slit" and feature != "window" and feature != "portcullis"
	if door_state == "closed" or door_state == "locked":
		return door_type != "portcullis"
	return false


## Whether this cell blocks flying creatures.
func blocks_flight() -> bool:
	return solidity == "solid" or door_state in ["closed", "locked", "stuck"]


## Whether this cell blocks burrowing creatures. Burrowers move through solid;
## air blocks them (they cannot "burrow" through empty space).
func blocks_burrow() -> bool:
	return solidity == "air"


# ---------------------------------------------------------------------------
# Serialization
# ---------------------------------------------------------------------------

## Creates a VoxelCell from a dictionary (e.g. JSON-loaded data or DB row).
static func from_dict(data: Dictionary) -> VoxelCell:
	var cell := VoxelCell.new()
	cell.col = data.get("col", 0)
	cell.row = data.get("row", 0)
	cell.level = data.get("level", 0)
	cell.solidity = data.get("solidity", "air")
	cell.feature = data.get("feature", "open")
	cell.floor_type = data.get("floor_type", "none")
	cell.door_state = data.get("door_state", "")
	cell.door_type = data.get("door_type", "")
	cell.door_detected = data.get("door_detected", false)
	cell.is_evil = data.get("is_evil", false)
	cell.stair_target_col = data.get("stair_target_col", -1)
	cell.stair_target_row = data.get("stair_target_row", -1)
	cell.stair_target_level = data.get("stair_target_level", -1)
	cell.room_id = data.get("room_id", -1)
	cell.is_corridor = data.get("is_corridor", false)
	cell.fog_state = data.get("fog_state", "hidden")
	cell.cover_value = data.get("cover_value", 0)
	return cell


## Serializes this cell to a dictionary.
func to_dict() -> Dictionary:
	return {
		"col": col,
		"row": row,
		"level": level,
		"solidity": solidity,
		"feature": feature,
		"floor_type": floor_type,
		"door_state": door_state,
		"door_type": door_type,
		"door_detected": door_detected,
		"is_evil": is_evil,
		"stair_target_col": stair_target_col,
		"stair_target_row": stair_target_row,
		"stair_target_level": stair_target_level,
		"room_id": room_id,
		"is_corridor": is_corridor,
		"fog_state": fog_state,
		"cover_value": cover_value,
	}
