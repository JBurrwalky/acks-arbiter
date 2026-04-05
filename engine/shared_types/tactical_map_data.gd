class_name TacticalMapData
extends RefCounted

## Unified cell grid for dungeon exploration and combat maps.
##
## Cell data is stored in a Dictionary keyed by Vector2i(col, row).
## Each value is a Dictionary with the CellData fields listed below.
## Cells not present in _cells are "void" (outside the dungeon/map).
##
## Fog state is stored separately (renderer/controller state, not definition data).
## Room registry is built by detect_rooms() via BFS flood-fill.
##
## This type is NOT an autoload. Instantiate via from_dict() or load_from_file().


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

enum FogState {
	HIDDEN,    ## Never seen — fully obscured
	EXPLORED,  ## Previously seen — rendered dimmed
	VISIBLE,   ## Currently visible — full brightness
}


# ---------------------------------------------------------------------------
# CellData field defaults
# ---------------------------------------------------------------------------
# elevation: int = 0                   (0-30, each unit = 2.5 ft)
# terrain_feature: String = "open"     ("open","rock","wall_stone","wall_wood",
#                                       "door","door_locked","door_secret","portcullis",
#                                       "stairs_up","stairs_down")
# passable: bool                        (derived from terrain_feature + door_state)
# blocks_los: bool                      (derived from terrain_feature + door_state)
# cover_value: int = 0                  (future combat use)
# surface_type: String = "stone"
# door_state: String = ""              ("","open","closed","locked","stuck")
# door_type: String = ""               ("","arch","unlocked","locked","trapped","secret","portcullis")
# door_detected: bool = true           (false for undiscovered secret doors)
# room_id: int = -1                    (assigned by detect_rooms())
# is_corridor: bool = false


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var id: String = ""
var name: String = ""
var grid_width: int = 0
var grid_height: int = 0
var entry_pos: Vector2i = Vector2i.ZERO

## Cell data. Key: Vector2i(col, row) → Dictionary (CellData fields).
var _cells: Dictionary = {}

## Fog state. Key: Vector2i(col, row) → FogState int. Absent = HIDDEN.
var fog: Dictionary = {}

## Room registry. Each entry: {id, cells: Array[Vector2i], bounds: Rect2i,
##                              center: Vector2i, original_purpose, current_purpose}
var rooms: Array = []

## Entity positions. Key: entity_id String → Vector2i cell pos.
var entity_positions: Dictionary = {}

## Entry/exit transition cells. Only these cells allow dungeon exit.
var transition_cells: Array[Vector2i] = []

## Optional display labels for transition cells. Vector2i → String.
var transition_cell_labels: Dictionary = {}


# ---------------------------------------------------------------------------
# Factory methods
# ---------------------------------------------------------------------------

## Builds a TacticalMapData from a level dict (one entry from the "levels" array).
## Expects: level, grid_width, grid_height, entry_col, entry_row, cells (array).
## Calls detect_rooms() after loading cells.
static func from_dict(data: Dictionary) -> TacticalMapData:
	var m := TacticalMapData.new()
	m.id = data.get("id", "")
	m.name = data.get("name", "")
	m.grid_width = data.get("grid_width", 0)
	m.grid_height = data.get("grid_height", 0)
	m.entry_pos = Vector2i(
		data.get("entry_col", 0),
		data.get("entry_row", 0)
	)

	var cells_array: Array = data.get("cells", [])
	for cell_data in cells_array:
		var col: int = cell_data.get("col", 0)
		var row: int = cell_data.get("row", 0)
		var pos := Vector2i(col, row)

		var tf: String = cell_data.get("terrain_feature", "open")
		var door_type: String = cell_data.get("door_type", "")
		var door_state: String = cell_data.get("door_state", "")
		var door_detected: bool = cell_data.get("door_detected", true)

		var cell: Dictionary = {
			"elevation": cell_data.get("elevation", 0),
			"terrain_feature": tf,
			"cover_value": cell_data.get("cover_value", 0),
			"surface_type": cell_data.get("surface_type", "stone"),
			"door_state": door_state,
			"door_type": door_type,
			"door_detected": door_detected,
			"room_id": -1,
			"is_corridor": false,
		}

		# Derive passable and blocks_los
		cell["passable"] = _compute_passable(tf, door_type, door_state)
		cell["blocks_los"] = _compute_blocks_los(tf, door_state)

		m._cells[pos] = cell

	# Parse transition cells
	var tc_array: Array = data.get("transition_cells", [])
	for tc in tc_array:
		var tc_pos := Vector2i(tc.get("col", 0), tc.get("row", 0))
		m.transition_cells.append(tc_pos)
		var label: String = tc.get("label", "")
		if not label.is_empty():
			m.transition_cell_labels[tc_pos] = label

	m.detect_rooms()
	return m


## Opens a JSON file, parses it, and returns a TacticalMapData from the first level.
## For multi-level dungeons use load_all_levels() pattern in DungeonMapController.
static func load_from_file(path: String) -> TacticalMapData:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("TacticalMapData.load_from_file: cannot open '%s' (error %d)" % [
			path, FileAccess.get_open_error()
		])
		return null

	var content := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(content)
	if parsed == null:
		push_error("TacticalMapData.load_from_file: JSON parse failed for '%s'" % path)
		return null

	# Support both single-level and multi-level formats
	if parsed.has("levels") and parsed["levels"] is Array and not parsed["levels"].is_empty():
		var level_data: Dictionary = parsed["levels"][0]
		level_data["id"] = parsed.get("id", "")
		level_data["name"] = parsed.get("name", "")
		return TacticalMapData.from_dict(level_data)

	return TacticalMapData.from_dict(parsed)


# ---------------------------------------------------------------------------
# Cell access
# ---------------------------------------------------------------------------

## Returns the cell dictionary at [param pos], or an empty Dictionary if void.
func get_cell(pos: Vector2i) -> Dictionary:
	return _cells.get(pos, {})


## Returns true if a cell exists at [param pos] (not void).
func has_cell(pos: Vector2i) -> bool:
	return _cells.has(pos)


## Sets a single field on the cell at [param pos].
## Creates the cell if it does not exist (use with care).
func set_cell_field(pos: Vector2i, field: String, value: Variant) -> void:
	if not _cells.has(pos):
		push_error("TacticalMapData.set_cell_field: no cell at %s" % str(pos))
		return
	_cells[pos][field] = value


# ---------------------------------------------------------------------------
# Navigation queries
# ---------------------------------------------------------------------------

## Returns true if the cell at [param pos] can be entered by a character.
func is_passable(pos: Vector2i) -> bool:
	var cell := get_cell(pos)
	if cell.is_empty():
		return false
	return cell.get("passable", false)


## Returns true if [param pos] is within the grid bounds.
func is_in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < grid_width and pos.y >= 0 and pos.y < grid_height


## Returns true if the cell at [param pos] blocks line of sight.
func blocks_los(pos: Vector2i) -> bool:
	var cell := get_cell(pos)
	if cell.is_empty():
		return false
	return cell.get("blocks_los", false)


## Returns true if [param pos] is a door cell of any type.
func is_door(pos: Vector2i) -> bool:
	var cell := get_cell(pos)
	if cell.is_empty():
		return false
	var tf: String = cell.get("terrain_feature", "")
	return tf in ["door", "door_locked", "door_secret", "portcullis"]


## Returns the door state at [param pos], or "" if not a door.
func get_door_state(pos: Vector2i) -> String:
	var cell := get_cell(pos)
	if cell.is_empty():
		return ""
	return cell.get("door_state", "")


## Returns the door type at [param pos], or "" if not a door.
func get_door_type(pos: Vector2i) -> String:
	var cell := get_cell(pos)
	if cell.is_empty():
		return ""
	return cell.get("door_type", "")


## Updates the door state at [param pos] and re-derives passable/blocks_los.
func set_door_state(pos: Vector2i, state: String) -> void:
	if not _cells.has(pos):
		push_error("TacticalMapData.set_door_state: no cell at %s" % str(pos))
		return
	var cell = _cells[pos]
	cell["door_state"] = state
	var tf: String = cell.get("terrain_feature", "open")
	var dt: String = cell.get("door_type", "")
	cell["passable"] = _compute_passable(tf, dt, state)
	cell["blocks_los"] = _compute_blocks_los(tf, state)


# ---------------------------------------------------------------------------
# Fog of war
# ---------------------------------------------------------------------------

## Returns the fog state at [param pos]. Defaults to HIDDEN.
func get_fog(pos: Vector2i) -> int:
	return fog.get(pos, FogState.HIDDEN)


## Sets the fog state at [param pos].
func set_fog(pos: Vector2i, state: int) -> void:
	fog[pos] = state


# ---------------------------------------------------------------------------
# Room queries
# ---------------------------------------------------------------------------

## Returns the room_id of the room at [param pos], or -1 if none.
func get_room_at(pos: Vector2i) -> int:
	var cell := get_cell(pos)
	if cell.is_empty():
		return -1
	return cell.get("room_id", -1)


## Returns all cell positions belonging to [param room_id].
func get_room_cells(room_id: int) -> Array[Vector2i]:
	for room in rooms:
		if room["id"] == room_id:
			return room["cells"]
	return []


## Returns all non-open cells immediately adjacent to any cell in [param room_id].
## These are the walls, doors, and portcullises that form the room boundary.
func get_room_boundary_cells(room_id: int) -> Array[Vector2i]:
	var room_cell_set: Dictionary = {}
	for room in rooms:
		if room["id"] == room_id:
			for c in room["cells"]:
				room_cell_set[c] = true
			break

	var boundary_set: Dictionary = {}
	for rc in room_cell_set.keys():
		for neighbor in IsometricGrid.get_neighbors(rc):
			if not room_cell_set.has(neighbor) and _cells.has(neighbor):
				boundary_set[neighbor] = true

	var result: Array[Vector2i] = []
	for b in boundary_set.keys():
		result.append(b)
	return result


# ---------------------------------------------------------------------------
# Room detection (BFS flood-fill)
# ---------------------------------------------------------------------------

## BFS flood-fill through "open" cells to identify rooms.
## Assigns room_id to each cell's dict. Populates the rooms array.
func detect_rooms() -> void:
	rooms.clear()

	var visited: Dictionary = {}
	var next_room_id := 0

	for pos in _cells.keys():
		if visited.has(pos):
			continue
		var cell = _cells[pos]
		var tf: String = cell.get("terrain_feature", "")
		if tf != "open":
			continue

		# BFS from this unvisited open cell
		var region: Array[Vector2i] = []
		var queue: Array[Vector2i] = [pos]
		visited[pos] = true

		while not queue.is_empty():
			var current: Vector2i = queue.pop_front()
			region.append(current)

			for neighbor in IsometricGrid.get_neighbors(current):
				if visited.has(neighbor):
					continue
				if not _cells.has(neighbor):
					continue
				var ncell = _cells[neighbor]
				var ntf: String = ncell.get("terrain_feature", "")
				if ntf == "open":
					visited[neighbor] = true
					queue.append(neighbor)

		if region.is_empty():
			continue

		# Compute bounding box
		var min_col := region[0].x
		var max_col := region[0].x
		var min_row := region[0].y
		var max_row := region[0].y
		for c in region:
			min_col = min(min_col, c.x)
			max_col = max(max_col, c.x)
			min_row = min(min_row, c.y)
			max_row = max(max_row, c.y)

		var bounds := Rect2i(min_col, min_row, max_col - min_col + 1, max_row - min_row + 1)
		var center := Vector2i((min_col + max_col) / 2, (min_row + max_row) / 2)

		# Assign room_id to all cells in this region
		for c in region:
			_cells[c]["room_id"] = next_room_id

		rooms.append({
			"id": next_room_id,
			"cells": region,
			"bounds": bounds,
			"center": center,
			"original_purpose": "",
			"current_purpose": "",
		})

		next_room_id += 1


# ---------------------------------------------------------------------------
# Entity positions
# ---------------------------------------------------------------------------

## Returns the grid position of [param entity_id], or Vector2i(-1,-1) if not placed.
func get_entity_pos(entity_id: String) -> Vector2i:
	return entity_positions.get(entity_id, Vector2i(-1, -1))


## Sets the grid position of [param entity_id].
func set_entity_pos(entity_id: String, pos: Vector2i) -> void:
	entity_positions[entity_id] = pos


## Returns all entity_ids at [param pos].
func get_entities_at(pos: Vector2i) -> Array[String]:
	var result: Array[String] = []
	for eid in entity_positions.keys():
		if entity_positions[eid] == pos:
			result.append(eid)
	return result


## Removes [param entity_id] from entity_positions.
func remove_entity(entity_id: String) -> void:
	entity_positions.erase(entity_id)


# ---------------------------------------------------------------------------
# Transition cells
# ---------------------------------------------------------------------------

## Returns true if [param pos] is a designated entry/exit transition cell.
func is_transition_cell(pos: Vector2i) -> bool:
	return pos in transition_cells


## Returns the display label for [param pos], or "Cell (col, row)" if none.
func get_transition_cell_label(pos: Vector2i) -> String:
	return transition_cell_labels.get(pos, "Cell (%d, %d)" % [pos.x, pos.y])


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Derives whether a cell is passable from its terrain and door state.
static func _compute_passable(tf: String, door_type: String, door_state: String) -> bool:
	match tf:
		"open", "stairs_up", "stairs_down":
			return true
		"wall_stone", "wall_wood", "rock":
			return false
		"portcullis":
			return false  # portcullis blocks movement but not LOS
		"door", "door_locked", "door_secret":
			if door_type == "arch":
				return true  # arch is always open
			return door_state == "open"
		_:
			return false


## Derives whether a cell blocks line of sight.
static func _compute_blocks_los(tf: String, door_state: String) -> bool:
	match tf:
		"open", "stairs_up", "stairs_down":
			return false
		"wall_stone", "wall_wood", "rock":
			return true
		"portcullis":
			return false  # see-through
		"door", "door_locked", "door_secret":
			return door_state != "open"
		_:
			return true
