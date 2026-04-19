class_name VisibilityManager
extends Node

## Multi-level visibility state machine.
##
## Tracks the camera's focus level and computes per-level visibility for
## rendering. Instanced in the scene tree by the dungeon map scene (NOT an
## autoload).
##
## The focus level determines which voxel y-layer the camera is "at." All
## rendering decisions cascade from this: the focused level is fully opaque,
## levels below are dimmed, the level above is dithered, and everything else
## is hidden.
##
## See gdd-voxel-tactical-architecture.md section 16.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Visibility values for each relative layer.
const VIS_FOCUS: float = 1.0     ## Focused level: fully opaque
const VIS_BELOW: float = 0.6     ## Below focus: dimmed
const VIS_DITHER: float = 0.3    ## Focus + 1: dithered semi-transparent
const VIS_HIDDEN: float = 0.0    ## Everything else: not rendered


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var focus_level: int = 0

## Updated by the dungeon/combat controller whenever party positions change.
var party_positions: Array[Vector3i] = []

## Sorted unique array of levels that have any fog_state != "hidden" cells.
## Recomputed by update_explored_levels() — not cached.
var explored_levels: Array[int] = []


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal focus_level_changed(new_level: int)


# ---------------------------------------------------------------------------
# Focus level management
# ---------------------------------------------------------------------------

## Sets the focus level, clamping to explored levels.
## If [param new_level] is in explored_levels, uses it directly.
## Otherwise, finds the nearest explored level in the requested direction:
##   Going up (new > current): smallest explored >= new_level, or stays.
##   Going down (new < current): largest explored <= new_level, or stays.
func set_focus_level(new_level: int) -> void:
	if explored_levels.is_empty():
		return

	var target: int = focus_level

	if new_level in explored_levels:
		target = new_level
	elif new_level > focus_level:
		# Going up: find smallest explored >= new_level
		for lvl in explored_levels:
			if lvl >= new_level:
				target = lvl
				break
		# If none found, stay at current
	elif new_level < focus_level:
		# Going down: find largest explored <= new_level
		for i in range(explored_levels.size() - 1, -1, -1):
			if explored_levels[i] <= new_level:
				target = explored_levels[i]
				break
		# If none found, stay at current

	if target != focus_level:
		focus_level = target
		focus_level_changed.emit(focus_level)


## Jumps focus to the party leader's level.
## Leader is party_positions[0] by convention.
func jump_to_party_leader() -> void:
	if party_positions.is_empty():
		return
	var leader_level: int = party_positions[0].z
	if leader_level != focus_level:
		focus_level = leader_level
		focus_level_changed.emit(focus_level)


# ---------------------------------------------------------------------------
# Visibility queries (consumed by renderers)
# ---------------------------------------------------------------------------

## Returns the opacity for [param level] given the current focus.
## Used by renderers to set per-level MultiMeshInstance3D visibility.
func get_level_visibility(level: int) -> float:
	if level == focus_level:
		return VIS_FOCUS
	if level == focus_level + 1:
		return VIS_DITHER
	if level < focus_level and level in explored_levels:
		return VIS_BELOW
	return VIS_HIDDEN


## Returns true if [param level] should use the dither transparency shader.
func should_dither(level: int) -> bool:
	return level == focus_level + 1


## Returns true if [param level] has any explored content.
func level_has_content(level: int) -> bool:
	return level in explored_levels


# ---------------------------------------------------------------------------
# State updates
# ---------------------------------------------------------------------------

## Recomputes explored_levels from the current fog state of [param voxel_map].
## A level is "explored" if any cell on that level has fog_state != "hidden".
## Always recomputes from scratch — no stale cache.
func update_explored_levels(voxel_map: VoxelMapData) -> void:
	var level_set: Dictionary = {}
	for cell: VoxelCell in voxel_map.get_all_cells():
		if cell.fog_state != "hidden":
			level_set[cell.level] = true
	explored_levels.clear()
	for lvl: int in level_set:
		explored_levels.append(lvl)
	explored_levels.sort()
