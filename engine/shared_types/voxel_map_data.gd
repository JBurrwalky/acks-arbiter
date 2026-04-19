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

	return map


## Serializes this map to a dictionary suitable for JSON output.
func to_dict() -> Dictionary:
	var cells_array: Array = []
	for cell: VoxelCell in get_all_cells():
		cells_array.append(cell.to_dict())

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
