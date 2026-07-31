class_name MovementRules
extends RefCounted

## The SINGLE home for ground-walker step legality on a VoxelMapData: support,
## ±1-level transitions via stair / ramp / spiral features, and the compass
## direction helpers. `MovementResolver` (combat + exploration pathing), the
## composed-volume navigability validator, and the key/lever placer all consume
## THIS — no independent stair/support logic lives in the validator or placer
## (gdd-dungeon-contiguous-3d.md §4 "One movement predicate"; DG-C3D.E).
##
## Door lock policy is deliberately NOT here — it differs per consumer (combat
## strict/explore; validator structural-all-passable vs solvability-with-keys).
## Each consumer layers its own door check on top of these geometry+support
## rules. A door cell is a `solidity: air` cell, so it passes `is_ground_step_open`
## and the caller then applies its door policy.


## Reverse compass direction, for matching a stair's suffix when descending.
const REVERSE_DIRECTION := {
	"N": "S", "NE": "SW", "E": "W", "SE": "NW",
	"S": "N", "SW": "NE", "W": "E", "NW": "SE",
}


## Ground-walker support (gdd-voxel-tactical-architecture.md §9.2). Delegates to
## the single support source `FallingResolver.has_support` (floor_type != none OR
## a solid cell below OR a ladder OR — DG-C3D.E — a stairs_spiral step, which
## holds a climber even where the slab is open, §10.5).
static func has_support(map: VoxelMapData, pos: Vector3i) -> bool:
	return FallingResolver.has_support(map, pos)


## Compass suffix (N..NW) for a unit horizontal delta; "" when the delta is not
## a single horizontal step (pure vertical, zero, or non-adjacent).
static func direction_suffix(delta: Vector2i) -> String:
	for i in range(VoxelGrid.DIRECTION_OFFSETS.size()):
		if VoxelGrid.DIRECTION_OFFSETS[i] == delta:
			return VoxelGrid.Direction.keys()[i]
	return ""


## The opposite compass direction ("" if not a compass string).
static func reverse_direction(dir: String) -> String:
	return REVERSE_DIRECTION.get(dir, "")


## True when a stair / ramp / spiral feature legally connects [param from] to
## [param to] across a ±1 level change. Caller guarantees abs(dz) == 1.
##
## - Diagonal-vertical (a stepped stair/ramp): the FROM cell carries
##   `stairs_up_<suffix>` / `ramp_<suffix>` when ascending in <suffix>, OR the TO
##   cell carries the reverse-direction descent feature (mirror when descending).
## - Pure-vertical, same column: a `ladder` OR a `stairs_spiral` shaft cell —
##   the spiral clause (voxel GDD §10.5): ±1 level in-column at normal cost, no
##   climb throw. Either endpoint carrying the feature suffices.
## - Natural slope (outdoor battle maps, gdd-combat-map-generation.md §4.2):
##   when the map is flagged `natural_slopes`, ANY diagonal-vertical ±1 step is
##   legal — a 5' grade is walkable terrain, no feature required. Pure-vertical
##   still needs a ladder/spiral (slopes are always diagonal). Air/support
##   checks remain the caller's (is_ground_step_open) responsibility.
static func connects_via_feature(map: VoxelMapData, from: Vector3i, to: Vector3i) -> bool:
	var going_up: bool = to.z > from.z
	var h_delta := Vector2i(to.x - from.x, to.y - from.y)
	var suffix := direction_suffix(h_delta)
	var from_cell := map.get_cell(from)
	var to_cell := map.get_cell(to)
	if suffix.is_empty():
		# Pure vertical (same column): ladder or spiral shaft.
		return from_cell.feature == "ladder" or to_cell.feature == "ladder" \
			or from_cell.feature == "stairs_spiral" or to_cell.feature == "stairs_spiral"
	if map.natural_slopes:
		return true
	var rev := reverse_direction(suffix)
	if going_up:
		if from_cell.feature == "stairs_up_" + suffix:
			return true
		if from_cell.feature == "ramp_" + suffix:
			return true
		if to_cell.feature == "stairs_down_" + rev:
			return true
		if to_cell.feature == "ramp_" + rev:
			return true
	else:
		if from_cell.feature == "stairs_down_" + suffix:
			return true
		if from_cell.feature == "ramp_" + suffix:
			return true
		if to_cell.feature == "stairs_up_" + rev:
			return true
		if to_cell.feature == "ramp_" + rev:
			return true
	return false


## Water-depth wading gate (gdd-combat-map-generation.md §5.6 / §9.3). A ground
## walker may enter a water cell when its water_depth (full 5' voxels of water)
## is within the walker's wade allowance. Default allowance 0 = shallow water
## only ("most characters can traverse water that is less than 1 voxel deep
## without swimming"). Bigger creatures get more leeway once the creature-size
## build session supplies per-creature allowances — callers pass that value
## here; nothing else changes.
static func can_wade(cell: VoxelCell, wade_depth_allowance: int = 0) -> bool:
	return cell.water_depth <= wade_depth_allowance


## Legality of the level change alone: 0 = flat (free), 1 = requires a matching
## stair/ramp/spiral feature, ≥2 = blocked for ground walkers.
static func level_transition_legal(map: VoxelMapData, from: Vector3i, to: Vector3i) -> bool:
	var d: int = abs(to.z - from.z)
	if d == 0:
		return true
	if d == 1:
		return connects_via_feature(map, from, to)
	return false


## Whether a ground walker may step from [param from] to [param to] treating the
## destination as an OPEN AIR cell (door LOCK policy is the caller's — a closed
## door cell is air and passes this; the validator/placer/mover apply their own
## door rule). Requires: destination solidity air, supported, and a legal level
## transition. This is the geometry+support core of one legal step; it is the
## edge predicate for the composed-volume reachability BFS.
static func is_ground_step_open(map: VoxelMapData, from: Vector3i, to: Vector3i) -> bool:
	var cell := map.get_cell(to)
	if cell.solidity != "air":
		return false
	if not has_support(map, to):
		return false
	return level_transition_legal(map, from, to)
