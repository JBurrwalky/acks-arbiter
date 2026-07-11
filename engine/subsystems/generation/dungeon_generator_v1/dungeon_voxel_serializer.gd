class_name DungeonVoxelSerializer
extends RefCounted

## Translates a DungeonGeneratorResultV1 (generator output) into the voxel-JSON
## Dictionary shape consumed by VoxelMapData.from_dict().
##
## WALL EMISSION STRATEGY — emit ALL cells including solid walls:
##   VoxelMapData.get_cell() returns a fresh sentinel with solidity="air" and
##   feature="open" for any absent key (see VoxelMapData.gd line ~66).  That means
##   an absent cell renders and navigates as open air — NOT as solid rock.  We must
##   therefore emit every grid cell from the source layout, including wall_stone,
##   wall_wood, and rock cells, to guarantee the dungeon has actual walls.
##
## LEVEL INDEXING:
##   DungeonLayout.level_number is 1-based (floor 1, 2, 3 …).
##   Voxel level = level_number - 1  (floor 1 → level 0, floor 2 → level 1, …).
##
## PLACED CONTENT (monster_groups, treasure_hoards) — phase-2 concern:
##   TODO: DG-V1.D stocking data (monster groups, treasure spawns) is not yet
##   wired into the voxel output.  When DG-V1.E is implemented, extend this
##   serializer to populate wandering_monster_table from result.floors[n].monster_groups.


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Converts a DungeonGeneratorResultV1 to a voxel-JSON Dictionary that can be
## passed directly to VoxelMapData.from_dict().
static func to_voxel_dict(result: DungeonGeneratorResultV1) -> Dictionary:
	var cells_array: Array = []
	var lever_links_array: Array = []

	# Collect cells floor by floor.
	for floor_layout: DungeonLayout in result.floors:
		var voxel_level: int = floor_layout.level_number - 1
		_emit_floor_cells(floor_layout, voxel_level, cells_array)
		_apply_door_overlays(floor_layout, voxel_level, cells_array)
		_apply_stair_overlays(floor_layout, voxel_level, cells_array)
		_apply_lever_overlays(floor_layout, voxel_level, cells_array, lever_links_array)

	# Resolve the top-level entry from the entrance floor.
	var entry_dict: Dictionary = {}
	for floor_layout: DungeonLayout in result.floors:
		if floor_layout.is_entrance_floor and floor_layout.entrance != Vector2i(-1, -1):
			entry_dict = {
				"col": floor_layout.entrance.x,
				"row": floor_layout.entrance.y,
				"level": floor_layout.level_number - 1,
			}
			break

	# generation_seed from the first floor (the orchestrator seeds all floors from
	# the same master seed; the first floor's value is canonical).
	var gen_seed: int = 0
	if not result.floors.is_empty():
		gen_seed = result.floors[0].generation_seed

	var out: Dictionary = {
		"id": result.dungeon_id,
		"name": result.dungeon_id,      # V1 has no separate display name field
		"theme": "",
		"tileset_group": "",
		"generation_seed": gen_seed,
		# DG-C3D.A: version stamp checked at the DungeonFixtureService lazy-
		# generation seam — a stored payload whose version does not match the
		# current constant is discarded and regenerated (contiguous GDD §13).
		"generator_version": DungeonGeneratorV1.GENERATOR_VERSION,
		"cells": cells_array,
		"lever_links": lever_links_array,
		# TODO: populate from stocked monster_groups once DG-V1.E is wired.
		# The runtime falls back to a level-based default catalog when this is [].
		"wandering_monster_table": [],
	}

	if not entry_dict.is_empty():
		out["entry"] = entry_dict

	return out


## Converts a DungeonGeneratorResultV1 to a JSON string.
static func to_voxel_json(result: DungeonGeneratorResultV1) -> String:
	return JSON.stringify(to_voxel_dict(result))


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Emits one voxel cell dict per grid coordinate for [param floor_layout].
## All cells — open, wall, rock, stairs, door-placeholder — are emitted here;
## door and stair overlays are applied by the _apply_* methods afterward.
static func _emit_floor_cells(
	floor_layout: DungeonLayout,
	voxel_level: int,
	cells_array: Array
) -> void:
	for x in range(floor_layout.grid_width):
		for y in range(floor_layout.grid_height):
			var cell: DungeonCellData = floor_layout.cells[x][y]
			var voxel_cell: Dictionary = _base_cell_dict(cell, x, y, voxel_level)
			cells_array.append(voxel_cell)


## Returns the base voxel cell dictionary for a DungeonCellData.
## Door and stair features are emitted as their open/air equivalents here;
## the overlay passes refine them with door_state/door_type and stair_target.
static func _base_cell_dict(
	cell: DungeonCellData,
	col: int,
	row: int,
	voxel_level: int
) -> Dictionary:
	var d: Dictionary = {
		"col": col,
		"row": row,
		"level": voxel_level,
		# Door state / type defaults; overwritten by _apply_door_overlays.
		"door_state": "",
		"door_type": "",
		"door_detected": false,
		# Stair target defaults; overwritten by _apply_stair_overlays.
		"stair_target_col": -1,
		"stair_target_row": -1,
		"stair_target_level": -1,
	}

	match cell.terrain_feature:
		DungeonCellData.FEATURE_OPEN:
			d["solidity"] = "air"
			d["feature"] = "open"
			d["floor_type"] = "stone"

		DungeonCellData.FEATURE_WALL_STONE:
			d["solidity"] = "solid"
			d["feature"] = "wall_stone"
			d["floor_type"] = "none"

		DungeonCellData.FEATURE_WALL_WOOD:
			d["solidity"] = "solid"
			d["feature"] = "wall_wood"
			d["floor_type"] = "none"

		DungeonCellData.FEATURE_ROCK:
			# Rock treated as solid stone wall (impassable natural stone).
			d["solidity"] = "solid"
			d["feature"] = "wall_stone"
			d["floor_type"] = "none"

		DungeonCellData.FEATURE_DOOR, \
		DungeonCellData.FEATURE_DOOR_LOCKED, \
		DungeonCellData.FEATURE_DOOR_SECRET, \
		DungeonCellData.FEATURE_PORTCULLIS:
			# Emit the cell as open air; the door overlay sets door_state / door_type.
			d["solidity"] = "air"
			d["feature"] = "open"
			d["floor_type"] = "stone"

		DungeonCellData.FEATURE_STAIRS_UP:
			# Default compass suffix "N"; _apply_stair_overlays keeps this suffix
			# (the generator does not record stair facing in V1).
			d["solidity"] = "air"
			d["feature"] = "stairs_up_N"
			d["floor_type"] = "stone"

		DungeonCellData.FEATURE_STAIRS_DOWN:
			d["solidity"] = "air"
			d["feature"] = "stairs_down_N"
			d["floor_type"] = "stone"

		_:
			# Unknown feature — treat as solid rock (safe fallback).
			d["solidity"] = "solid"
			d["feature"] = "wall_stone"
			d["floor_type"] = "none"

	return d


## Applies door overlays from floor_layout.doors[] onto the matching cells in
## cells_array.  Must run AFTER _emit_floor_cells so the base cells exist.
static func _apply_door_overlays(
	floor_layout: DungeonLayout,
	voxel_level: int,
	cells_array: Array
) -> void:
	for door: DungeonDoorData in floor_layout.doors:
		var target_dict: Dictionary = _find_cell_dict(cells_array, door.position.x, door.position.y, voxel_level)
		if target_dict.is_empty():
			continue  # no matching cell (shouldn't happen with a well-formed layout)

		# Map door type to voxel door_state + door_type.
		match door.type:
			DungeonDoorData.TYPE_ARCH:
				target_dict["door_state"] = "open"
				target_dict["door_type"] = "arch"
			DungeonDoorData.TYPE_UNLOCKED:
				target_dict["door_state"] = "closed"
				target_dict["door_type"] = "unlocked"
			DungeonDoorData.TYPE_LOCKED:
				target_dict["door_state"] = "locked"
				target_dict["door_type"] = "locked"
			DungeonDoorData.TYPE_TRAPPED:
				target_dict["door_state"] = "closed"
				target_dict["door_type"] = "trapped"
			DungeonDoorData.TYPE_PORTCULLIS:
				target_dict["door_state"] = "closed"
				target_dict["door_type"] = "portcullis"

		# Secret overlay: overrides door_type and hides the door.
		if door.is_secret:
			target_dict["door_type"] = "secret"
			target_dict["door_state"] = "closed"
			target_dict["door_detected"] = false


## Applies stair target coordinates from floor_layout.stairs[] onto matching
## cells.  Skips entrance stairs (those use the top-level entry dict instead).
static func _apply_stair_overlays(
	floor_layout: DungeonLayout,
	voxel_level: int,
	cells_array: Array
) -> void:
	for stair: DungeonStairData in floor_layout.stairs:
		if stair.is_entrance_stair:
			continue  # surface entry is represented by the top-level "entry" dict

		var target_dict: Dictionary = _find_cell_dict(cells_array, stair.position.x, stair.position.y, voxel_level)
		if target_dict.is_empty():
			continue

		# Stair cells are position-aligned across floors in the generator's multi-floor
		# anchoring scheme: the stair at (x, y) on floor N lands at (x, y) on the
		# adjacent floor.  The target col/row therefore equals the stair's own position.
		target_dict["stair_target_col"] = stair.position.x
		target_dict["stair_target_row"] = stair.position.y

		# Resolve the target level.
		if stair.connects_to_level > 0:
			# connects_to_level is 1-based floor index → convert to 0-based voxel level.
			target_dict["stair_target_level"] = stair.connects_to_level - 1
		else:
			# Fallback: unset connection — infer from direction.
			if stair.direction == DungeonStairData.DIRECTION_DOWN:
				target_dict["stair_target_level"] = voxel_level + 1
			else:
				target_dict["stair_target_level"] = voxel_level - 1


## Converts portcullis-lever wiring from floor_layout.doors[] into lever cell
## mutations and top-level lever_links entries.
static func _apply_lever_overlays(
	floor_layout: DungeonLayout,
	voxel_level: int,
	cells_array: Array,
	lever_links_array: Array
) -> void:
	for door: DungeonDoorData in floor_layout.doors:
		if door.type != DungeonDoorData.TYPE_PORTCULLIS:
			continue
		if door.wired_lever_position == Vector2i(-1, -1):
			continue

		var lx: int = door.wired_lever_position.x
		var ly: int = door.wired_lever_position.y

		var lever_dict: Dictionary = _find_cell_dict(cells_array, lx, ly, voxel_level)
		if lever_dict.is_empty():
			continue

		# Mutate the lever cell: keep solidity=air, floor_type=stone, but set
		# feature to "lever" so the runtime can detect and render it.
		lever_dict["feature"] = "lever"
		lever_dict["solidity"] = "air"
		lever_dict["floor_type"] = "stone"

		lever_links_array.append({
			"lever": [lx, ly, voxel_level],
			"target": [door.position.x, door.position.y, voxel_level],
		})


## Linear scan over cells_array to find a cell dict matching (col, row, level).
## Returns an empty Dictionary if not found.
## NOTE: returns a reference to the actual dict inside the array — mutating the
## return value mutates the cell in cells_array (this is intentional for overlays).
static func _find_cell_dict(cells_array: Array, col: int, row: int, level: int) -> Dictionary:
	for cell_dict in cells_array:
		if cell_dict["col"] == col and cell_dict["row"] == row and cell_dict["level"] == level:
			return cell_dict
	return {}
