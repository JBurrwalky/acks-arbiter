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


# ---------------------------------------------------------------------------
# Dungeon / room metadata
# ---------------------------------------------------------------------------

var room_id: int = -1
var is_corridor: bool = false

## Zone membership within the owning room (gdd-dungeon-contiguous-3d.md §5.3).
## -1 = no zone (corridors, non-dungeon maps, pre-DG-C3D content). Stamped at
## composition time (DG-C3D.D) — zone membership cannot always be derived from
## (room_id, band) because disconnected same-band galleries are distinct zones.
var zone_index: int = -1


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

## Whether a ground-walking creature can occupy this cell right now (ignoring
## support). Strict mode — closed doors block. Used by combat and other paths
## where door interactions must be explicit.
## Support checking (floor_type / solid below) is the pathfinder's job.
func is_passable_by_walker() -> bool:
	if solidity != "air":
		return false
	if door_state in ["closed", "locked", "stuck"]:
		return false
	return true


## Whether a creature in Gaseous Form (Arcane L3 Gaseous Form spell, Potion
## of Gaseous Form) can occupy this cell. RAW (pc_spell_catalog_f-u.xml:
## 90-126): "can flow below doors and through small unsealed spaces."
## Implementation: gas passes any air cell, ignoring door_state — closed
## doors, locked doors, stuck doors, AND closed portcullises don't block.
## Solid walls and other solid terrain still block (gas can't pass solid
## matter). Used by MovementResolver._can_enter_3d's "gaseous" branch
## (and auto-detected for combatants carrying the is_gaseous flag).
func is_passable_by_gaseous() -> bool:
	return solidity == "air"


## Whether a door at this cell is impossible to open by simply pulling/pushing
## (i.e. not just "closed and unlocked"). Locked, stuck, undetected secret, and
## portcullis doors return true and block movement even when paired with the
## explore-mode auto-open behavior.
func is_opening_blocked() -> bool:
	if door_state == "locked" or door_state == "stuck":
		return true
	if door_type == "portcullis" and door_state != "open":
		return true
	if door_type == "secret" and not door_detected:
		return true
	return false


## Whether a ground walker can plan a path through this cell, treating closed
## but openable doors as walkable (the path execution layer will pause for one
## round to swing the door open). Used by exploration BFS so clicks past a
## closed unlocked door route the party through it without a separate command.
func is_walkable_with_open_door() -> bool:
	if solidity != "air":
		return false
	if is_opening_blocked():
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
	cell.room_id = data.get("room_id", -1)
	cell.is_corridor = data.get("is_corridor", false)
	cell.zone_index = data.get("zone_index", -1)
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
		"room_id": room_id,
		"is_corridor": is_corridor,
		"zone_index": zone_index,
		"fog_state": fog_state,
		"cover_value": cover_value,
	}
