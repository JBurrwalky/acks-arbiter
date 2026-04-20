class_name VoxelMapData
extends RefCounted

## Sparse 3D voxel map storage.
##
## Cells are stored in a Dictionary keyed by Vector3i(col, row, level).
## Absent keys represent "default" cells — empty air with no floor, no feature,
## hidden fog. The get_cell() method returns a fresh sentinel for absent keys
## so callers never deal with null.
##
## This replaces TacticalMapData for the voxel architecture. The old type is
## retained for backward compatibility until Session 11 cleanup.
##
## See gdd-voxel-tactical-architecture.md section 6.4 for sparse storage rationale.


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var id: String = ""
var name: String = ""
var theme: String = ""
var tileset_group: String = ""
var entry_pos: Vector3i = Vector3i.ZERO
var generation_seed: int = 0

## Sparse cell storage. Key: Vector3i(col, row, level) -> VoxelCell.
var _cells: Dictionary = {}

## Entity positions. Key: entity_id (String) -> Vector3i(col, row, level).
var entity_positions: Dictionary = {}

## Designated entry/exit transition cells.
var transition_cells: Array[Vector3i] = []

## Optional display labels for transition cells.
var transition_cell_labels: Dictionary = {}  # Vector3i -> String

## Detected rooms (populated by detect_rooms()).
var rooms: Array = []


# ---------------------------------------------------------------------------
# Cell access
# ---------------------------------------------------------------------------

## Returns the cell at [param pos], or a fresh sentinel (air/open/none/hidden)
## if no cell exists at that position. Never returns null.
## The sentinel is created on each call — mutating it does not affect the map.
func get_cell(pos: Vector3i) -> VoxelCell:
	if _cells.has(pos):
		return _cells[pos]
	# Return a fresh sentinel so callers can inspect defaults safely.
	var sentinel := VoxelCell.new()
	sentinel.col = pos.x
	sentinel.row = pos.y
	sentinel.level = pos.z
	return sentinel


## Stores [param cell] at [param pos]. Also syncs the cell's col/row/level
## fields to match the position key.
func set_cell(pos: Vector3i, cell: VoxelCell) -> void:
	cell.col = pos.x
	cell.row = pos.y
	cell.level = pos.z
	_cells[pos] = cell


## Returns true if a cell has been explicitly stored at [param pos].
func has_cell(pos: Vector3i) -> bool:
	return _cells.has(pos)


## Removes the cell at [param pos] if one exists.
func remove_cell(pos: Vector3i) -> void:
	_cells.erase(pos)


# ---------------------------------------------------------------------------
# Iteration
# ---------------------------------------------------------------------------

## Returns all stored cells (unordered).
func get_all_cells() -> Array:
	return _cells.values()


## Returns all stored position keys (unordered).
func get_all_positions() -> Array:
	return _cells.keys()


## Returns only cells whose level matches [param target_level].
func get_cells_at_level(target_level: int) -> Array:
	var result: Array = []
	for pos: Vector3i in _cells:
		if pos.z == target_level:
			result.append(_cells[pos])
	return result


## Returns a sorted array of unique level values present in the map.
func get_levels() -> Array[int]:
	var levels_set: Dictionary = {}
	for pos: Vector3i in _cells:
		levels_set[pos.z] = true
	var levels: Array[int] = []
	for lvl: int in levels_set:
		levels.append(lvl)
	levels.sort()
	return levels


## Returns the number of explicitly stored cells.
func cell_count() -> int:
	return _cells.size()


# ---------------------------------------------------------------------------
# Entity positions
# ---------------------------------------------------------------------------

## Returns the grid position of [param entity_id], or Vector3i(-1,-1,-1) if not placed.
func get_entity_pos(entity_id: String) -> Vector3i:
	return entity_positions.get(entity_id, Vector3i(-1, -1, -1))


## Sets the grid position of [param entity_id].
func set_entity_pos(entity_id: String, pos: Vector3i) -> void:
	entity_positions[entity_id] = pos


## Returns all entity IDs at [param pos].
func get_entities_at(pos: Vector3i) -> Array[String]:
	var result: Array[String] = []
	for eid in entity_positions.keys():
		if entity_positions[eid] == pos:
			result.append(eid)
	return result


## Returns true if any entity occupies [param pos].
func is_occupied(pos: Vector3i) -> bool:
	for eid in entity_positions:
		if entity_positions[eid] == pos:
			return true
	return false


## Returns true if any entity other than [param exclude_id] occupies [param pos].
func is_occupied_by_other(pos: Vector3i, exclude_id: String) -> bool:
	for eid in entity_positions:
		if eid != exclude_id and entity_positions[eid] == pos:
			return true
	return false


## Removes [param entity_id] from entity_positions.
func remove_entity(entity_id: String) -> void:
	entity_positions.erase(entity_id)


# ---------------------------------------------------------------------------
# Navigation queries
# ---------------------------------------------------------------------------

## Returns true if a ground walker can enter the cell at [param pos].
## Delegates to VoxelCell.is_passable_by_walker(). Returns false for absent cells.
func is_passable(pos: Vector3i) -> bool:
	if not _cells.has(pos):
		return false
	return _cells[pos].is_passable_by_walker()


## Returns true if the cell at [param pos] has a door (any state).
func is_door(pos: Vector3i) -> bool:
	return get_cell(pos).door_state != ""


## Returns the door state at [param pos], or "" if no door.
func get_door_state(pos: Vector3i) -> String:
	return get_cell(pos).door_state


## Sets the door state at [param pos]. Creates cell if absent.
func set_door_state(pos: Vector3i, state: String) -> void:
	var cell := _ensure_cell(pos)
	cell.door_state = state


## Returns the door type at [param pos], or "" if no door.
func get_door_type(pos: Vector3i) -> String:
	return get_cell(pos).door_type


## Returns true if the cell at [param pos] blocks line of sight.
func blocks_los(pos: Vector3i) -> bool:
	return get_cell(pos).blocks_los()


## Sets an arbitrary field on the cell at [param pos]. Creates cell if absent.
func set_cell_field(pos: Vector3i, field: String, value) -> void:
	var cell := _ensure_cell(pos)
	cell.set(field, value)


# ---------------------------------------------------------------------------
# Fog of war
# ---------------------------------------------------------------------------

## Returns the fog state at [param pos]. Defaults to "hidden" for absent cells.
func get_fog(pos: Vector3i) -> String:
	return get_cell(pos).fog_state


## Sets the fog state at [param pos]. Creates cell if absent and state != "hidden".
func set_fog(pos: Vector3i, state: String) -> void:
	if not _cells.has(pos) and state == "hidden":
		return  # no-op: absent cells are already hidden
	var cell := _ensure_cell(pos)
	cell.fog_state = state


# ---------------------------------------------------------------------------
# Room queries
# ---------------------------------------------------------------------------

## Returns the room_id of the cell at [param pos], or -1 if none.
func get_room_at(pos: Vector3i) -> int:
	return get_cell(pos).room_id


## Returns all cell positions belonging to [param room_id].
func get_room_cells(room_id: int) -> Array[Vector3i]:
	for room in rooms:
		if room["id"] == room_id:
			return room["cells"]
	return []


## Returns all cell positions adjacent to any cell in [param room_id] that
## are not part of the room (walls, doors, boundaries).
func get_room_boundary_cells(room_id: int) -> Array[Vector3i]:
	var room_cell_set: Dictionary = {}
	for room in rooms:
		if room["id"] == room_id:
			for c in room["cells"]:
				room_cell_set[c] = true
			break

	var boundary_set: Dictionary = {}
	for rc: Vector3i in room_cell_set.keys():
		for neighbor: Vector3i in VoxelGrid.get_neighbors_2d(rc):
			if not room_cell_set.has(neighbor) and _cells.has(neighbor):
				boundary_set[neighbor] = true

	var result: Array[Vector3i] = []
	for b: Vector3i in boundary_set.keys():
		result.append(b)
	return result


# ---------------------------------------------------------------------------
# Room detection (BFS flood-fill)
# ---------------------------------------------------------------------------

## BFS flood-fill through passable air cells to identify rooms.
## Operates per-level only — rooms do not span levels.
## Assigns room_id to each cell. Populates the rooms array.
func detect_rooms() -> void:
	rooms.clear()

	var visited: Dictionary = {}
	var next_room_id := 0

	for pos: Vector3i in _cells.keys():
		if visited.has(pos):
			continue
		var cell: VoxelCell = _cells[pos]
		if cell.feature != "open" or cell.solidity != "air":
			continue

		# BFS from this unvisited open cell (same level only)
		var region: Array[Vector3i] = []
		var queue: Array[Vector3i] = [pos]
		visited[pos] = true

		while not queue.is_empty():
			var current: Vector3i = queue.pop_front()
			region.append(current)

			for neighbor: Vector3i in VoxelGrid.get_neighbors_2d(current):
				if visited.has(neighbor):
					continue
				if not _cells.has(neighbor):
					continue
				var ncell: VoxelCell = _cells[neighbor]
				if ncell.feature == "open" and ncell.solidity == "air":
					visited[neighbor] = true
					queue.append(neighbor)

		if region.is_empty():
			continue

		# Compute bounding box
		var min_col: int = region[0].x
		var max_col: int = region[0].x
		var min_row: int = region[0].y
		var max_row: int = region[0].y
		for c: Vector3i in region:
			min_col = min(min_col, c.x)
			max_col = max(max_col, c.x)
			min_row = min(min_row, c.y)
			max_row = max(max_row, c.y)

		var bounds := Rect2i(min_col, min_row, max_col - min_col + 1, max_row - min_row + 1)
		var center := Vector3i((min_col + max_col) / 2, (min_row + max_row) / 2, pos.z)

		# Assign room_id to all cells in this region
		for c: Vector3i in region:
			_cells[c].room_id = next_room_id

		rooms.append({
			"id": next_room_id,
			"cells": region,
			"bounds": bounds,
			"center": center,
			"level": pos.z,
		})

		next_room_id += 1


# ---------------------------------------------------------------------------
# Transition cells
# ---------------------------------------------------------------------------

## Returns true if [param pos] is a designated entry/exit transition cell.
func is_transition_cell(pos: Vector3i) -> bool:
	return pos in transition_cells


## Returns the display label for [param pos], or a default string if none.
func get_transition_cell_label(pos: Vector3i) -> String:
	return transition_cell_labels.get(pos, "Cell (%d, %d, %d)" % [pos.x, pos.y, pos.z])


# ---------------------------------------------------------------------------
# Combat map factory
# ---------------------------------------------------------------------------

## Generate a simple open-field battle map for wilderness encounters.
## All cells on level 0 with passable open terrain and visible fog.
static func generate_open_field(width: int = 20, height: int = 16) -> VoxelMapData:
	var m := VoxelMapData.new()
	m.id = "battlefield"
	m.name = "Open Field"
	m.entry_pos = Vector3i(2, height / 2, 0)

	for col in range(width):
		for row in range(height):
			var cell := VoxelCell.new()
			cell.col = col
			cell.row = row
			cell.level = 0
			cell.solidity = "air"
			cell.feature = "open"
			cell.floor_type = "grass"
			cell.fog_state = "visible"
			m.set_cell(Vector3i(col, row, 0), cell)
	return m


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Returns the stored cell at [param pos], creating a default air cell if absent.
func _ensure_cell(pos: Vector3i) -> VoxelCell:
	if _cells.has(pos):
		return _cells[pos]
	var cell := VoxelCell.new()
	cell.col = pos.x
	cell.row = pos.y
	cell.level = pos.z
	_cells[pos] = cell
	return cell


# ---------------------------------------------------------------------------
# Serialization
# ---------------------------------------------------------------------------

## Creates a VoxelMapData from a dictionary (e.g. parsed JSON).
## Expected keys: id, name, theme, tileset_group, generation_seed,
## entry (as {col, row, level}), cells (Array of cell dicts).
static func from_dict(data: Dictionary) -> VoxelMapData:
	var map := VoxelMapData.new()
	map.id = str(data.get("id", ""))
	map.name = str(data.get("name", ""))
	map.theme = str(data.get("theme", ""))
	map.tileset_group = str(data.get("tileset_group", ""))
	map.generation_seed = int(data.get("generation_seed", 0))

	var entry_dict: Dictionary = data.get("entry", {})
	if not entry_dict.is_empty():
		map.entry_pos = Vector3i(
			int(entry_dict.get("col", 0)),
			int(entry_dict.get("row", 0)),
			int(entry_dict.get("level", 0))
		)

	var cells_array: Array = data.get("cells", [])
	for cell_dict: Dictionary in cells_array:
		var cell := VoxelCell.from_dict(cell_dict)
		map.set_cell(cell.pos, cell)

	# Parse transition cells
	var tc_array: Array = data.get("transition_cells", [])
	for tc in tc_array:
		var tc_pos := Vector3i(
			int(tc.get("col", 0)),
			int(tc.get("row", 0)),
			int(tc.get("level", 0))
		)
		map.transition_cells.append(tc_pos)
		var label: String = tc.get("label", "")
		if not label.is_empty():
			map.transition_cell_labels[tc_pos] = label

	map.detect_rooms()
	return map


## Serializes this map to a dictionary suitable for JSON output.
func to_dict() -> Dictionary:
	var cells_array: Array = []
	for cell: VoxelCell in get_all_cells():
		cells_array.append(cell.to_dict())

	var tc_array: Array = []
	for tc_pos: Vector3i in transition_cells:
		var tc_dict: Dictionary = {
			"col": tc_pos.x,
			"row": tc_pos.y,
			"level": tc_pos.z,
		}
		if transition_cell_labels.has(tc_pos):
			tc_dict["label"] = transition_cell_labels[tc_pos]
		tc_array.append(tc_dict)

	return {
		"id": id,
		"name": name,
		"theme": theme,
		"tileset_group": tileset_group,
		"generation_seed": generation_seed,
		"entry": {
			"col": entry_pos.x,
			"row": entry_pos.y,
			"level": entry_pos.z,
		},
		"cells": cells_array,
		"transition_cells": tc_array,
	}


## Loads a VoxelMapData from a JSON file. Returns null on failure.
static func load_from_file(path: String) -> VoxelMapData:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("VoxelMapData.load_from_file: cannot open '%s'" % path)
		return null
	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if parsed == null or not parsed is Dictionary:
		push_error("VoxelMapData.load_from_file: invalid JSON in '%s'" % path)
		return null

	return from_dict(parsed as Dictionary)


## Saves this map to a JSON file. Returns true on success.
func save_to_file(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("VoxelMapData.save_to_file: cannot open '%s' for writing" % path)
		return false
	var json_str := JSON.stringify(to_dict(), "\t")
	file.store_string(json_str)
	file.close()
	return true
