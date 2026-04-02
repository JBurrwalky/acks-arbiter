extends "res://tests/test_suite_base.gd"

## Unit tests for TacticalMapData.
##
## Uses in-memory dictionaries — no JSON file required.
## All tests construct minimal map data directly via from_dict().


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Creates a minimal 5×5 map with a 3×3 open room, walls around it,
## one unlocked door on the south wall, and one wall_stone cell.
func _make_small_map() -> TacticalMapData:
	var cells := []

	# 3×3 open floor: cols 1-3, rows 1-3
	for col in range(1, 4):
		for row in range(1, 4):
			cells.append({"col": col, "row": row, "terrain_feature": "open"})

	# Wall border (partial — just the cells we need for tests)
	cells.append({"col": 0, "row": 0, "terrain_feature": "wall_stone"})
	cells.append({"col": 1, "row": 0, "terrain_feature": "wall_stone"})
	cells.append({"col": 2, "row": 0, "terrain_feature": "wall_stone"})
	cells.append({"col": 3, "row": 0, "terrain_feature": "wall_stone"})
	cells.append({"col": 4, "row": 0, "terrain_feature": "wall_stone"})
	cells.append({"col": 0, "row": 1, "terrain_feature": "wall_stone"})
	cells.append({"col": 4, "row": 1, "terrain_feature": "wall_stone"})
	cells.append({"col": 0, "row": 2, "terrain_feature": "wall_stone"})
	cells.append({"col": 4, "row": 2, "terrain_feature": "wall_stone"})
	cells.append({"col": 0, "row": 3, "terrain_feature": "wall_stone"})
	cells.append({"col": 4, "row": 3, "terrain_feature": "wall_stone"})
	cells.append({"col": 0, "row": 4, "terrain_feature": "wall_stone"})
	cells.append({"col": 1, "row": 4, "terrain_feature": "wall_stone"})
	cells.append({"col": 3, "row": 4, "terrain_feature": "wall_stone"})
	cells.append({"col": 4, "row": 4, "terrain_feature": "wall_stone"})

	# South door (unlocked, closed)
	cells.append({"col": 2, "row": 4, "terrain_feature": "door",
		"door_type": "unlocked", "door_state": "closed"})

	return TacticalMapData.from_dict({
		"id": "test_small",
		"name": "Small Test Map",
		"grid_width": 5,
		"grid_height": 5,
		"entry_col": 1,
		"entry_row": 1,
		"cells": cells,
	})


## Creates a map with a portcullis.
func _make_portcullis_map() -> TacticalMapData:
	var cells := [
		{"col": 0, "row": 0, "terrain_feature": "open"},
		{"col": 1, "row": 0, "terrain_feature": "portcullis",
			"door_type": "portcullis", "door_state": "closed"},
		{"col": 2, "row": 0, "terrain_feature": "open"},
	]
	return TacticalMapData.from_dict({
		"id": "portcullis_test", "grid_width": 3, "grid_height": 1,
		"entry_col": 0, "entry_row": 0, "cells": cells
	})


## Creates a map with a secret door.
func _make_secret_door_map() -> TacticalMapData:
	var cells := [
		{"col": 0, "row": 0, "terrain_feature": "open"},
		{"col": 1, "row": 0, "terrain_feature": "door_secret",
			"door_type": "secret", "door_state": "closed", "door_detected": false},
		{"col": 2, "row": 0, "terrain_feature": "open"},
	]
	return TacticalMapData.from_dict({
		"id": "secret_test", "grid_width": 3, "grid_height": 1,
		"entry_col": 0, "entry_row": 0, "cells": cells
	})


# ---------------------------------------------------------------------------
# Test runner
# ---------------------------------------------------------------------------

func run_all_tests() -> void:
	test_from_dict_loads_cells()
	test_void_for_missing_cells()
	test_has_cell_true()
	test_has_cell_false()
	test_detect_rooms_finds_one_room()
	test_room_cells_are_open_only()
	test_door_state_from_dict()
	test_set_door_state_open()
	test_set_door_state_rederives_passable()
	test_fog_default_hidden()
	test_set_fog_state()
	test_is_passable_open_cell()
	test_is_passable_open_door()
	test_not_passable_closed_door()
	test_not_passable_wall()
	test_blocks_los_wall()
	test_portcullis_blocks_movement_not_los()
	test_secret_door_undetected_impassable()
	test_entity_position_crud()
	test_room_boundary_cells_not_open()
	test_is_in_bounds()
	if not has_failures():
		print("TacticalMapData: all tests passed.")


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_from_dict_loads_cells() -> void:
	var m := _make_small_map()
	# 9 open + 15 wall/door = 25 cells total (but we only listed 9+15+1 = 25 - checking walls)
	# Actually 9 open + 14 wall + 1 door = 24 cells (partial walls listed)
	check(m.has_cell(Vector2i(1, 1)), "open cell (1,1) should be loaded")
	check(m.has_cell(Vector2i(0, 0)), "wall cell (0,0) should be loaded")
	check(m.has_cell(Vector2i(2, 4)), "door cell (2,4) should be loaded")


func test_void_for_missing_cells() -> void:
	var m := _make_small_map()
	check(not m.has_cell(Vector2i(10, 10)), "cell (10,10) not in map should return false")
	check(m.get_cell(Vector2i(10, 10)).is_empty(), "get_cell for void should return empty dict")


func test_has_cell_true() -> void:
	var m := _make_small_map()
	check(m.has_cell(Vector2i(2, 2)), "has_cell should return true for present cell")


func test_has_cell_false() -> void:
	var m := _make_small_map()
	check(not m.has_cell(Vector2i(99, 99)), "has_cell should return false for absent cell")


func test_detect_rooms_finds_one_room() -> void:
	var m := _make_small_map()
	# The 3×3 open area forms 1 connected region
	check(m.rooms.size() == 1, "small map should have exactly 1 room, got %d" % m.rooms.size())


func test_room_cells_are_open_only() -> void:
	var m := _make_small_map()
	if m.rooms.is_empty():
		check(false, "no rooms detected — cannot check room cells")
		return
	var room = m.rooms[0]
	for c in room["cells"]:
		var cell := m.get_cell(c)
		var tf: String = cell.get("terrain_feature", "")
		check(tf == "open", "room cell at %s should be 'open', got '%s'" % [str(c), tf])


func test_door_state_from_dict() -> void:
	var m := _make_small_map()
	var door_cell := m.get_cell(Vector2i(2, 4))
	check(door_cell.get("door_state", "") == "closed",
		"door at (2,4) should have state 'closed', got '%s'" % door_cell.get("door_state", ""))
	check(door_cell.get("door_type", "") == "unlocked",
		"door at (2,4) should have type 'unlocked'")


func test_set_door_state_open() -> void:
	var m := _make_small_map()
	m.set_door_state(Vector2i(2, 4), "open")
	check(m.get_door_state(Vector2i(2, 4)) == "open",
		"after set_door_state('open'), get_door_state should return 'open'")


func test_set_door_state_rederives_passable() -> void:
	var m := _make_small_map()
	check(not m.is_passable(Vector2i(2, 4)), "closed door should be impassable")
	m.set_door_state(Vector2i(2, 4), "open")
	check(m.is_passable(Vector2i(2, 4)), "open door should be passable")


func test_fog_default_hidden() -> void:
	var m := _make_small_map()
	check(m.get_fog(Vector2i(1, 1)) == TacticalMapData.FogState.HIDDEN,
		"fresh map cell should default to HIDDEN fog")
	check(m.get_fog(Vector2i(99, 99)) == TacticalMapData.FogState.HIDDEN,
		"void position should also return HIDDEN fog")


func test_set_fog_state() -> void:
	var m := _make_small_map()
	m.set_fog(Vector2i(1, 1), TacticalMapData.FogState.VISIBLE)
	check(m.get_fog(Vector2i(1, 1)) == TacticalMapData.FogState.VISIBLE,
		"set_fog VISIBLE should be readable back as VISIBLE")
	m.set_fog(Vector2i(1, 1), TacticalMapData.FogState.EXPLORED)
	check(m.get_fog(Vector2i(1, 1)) == TacticalMapData.FogState.EXPLORED,
		"set_fog EXPLORED should be readable back as EXPLORED")


func test_is_passable_open_cell() -> void:
	var m := _make_small_map()
	check(m.is_passable(Vector2i(2, 2)), "open cell should be passable")


func test_is_passable_open_door() -> void:
	var m := _make_small_map()
	m.set_door_state(Vector2i(2, 4), "open")
	check(m.is_passable(Vector2i(2, 4)), "open door should be passable")


func test_not_passable_closed_door() -> void:
	var m := _make_small_map()
	check(not m.is_passable(Vector2i(2, 4)),
		"closed door (2,4) should be impassable")


func test_not_passable_wall() -> void:
	var m := _make_small_map()
	check(not m.is_passable(Vector2i(0, 0)),
		"wall_stone cell (0,0) should be impassable")


func test_blocks_los_wall() -> void:
	var m := _make_small_map()
	check(m.blocks_los(Vector2i(0, 0)), "wall_stone should block LOS")
	check(not m.blocks_los(Vector2i(2, 2)), "open cell should not block LOS")


func test_portcullis_blocks_movement_not_los() -> void:
	var m := _make_portcullis_map()
	var portcullis_pos := Vector2i(1, 0)
	check(not m.is_passable(portcullis_pos), "portcullis should block movement")
	check(not m.blocks_los(portcullis_pos), "portcullis should NOT block LOS")


func test_secret_door_undetected_impassable() -> void:
	var m := _make_secret_door_map()
	var secret_pos := Vector2i(1, 0)
	# Undetected secret door: terrain=door_secret, state=closed → impassable
	check(not m.is_passable(secret_pos),
		"undetected secret door should be impassable (looks like a wall)")
	# But blocks LOS (it's a closed door)
	check(m.blocks_los(secret_pos),
		"undetected secret door (closed) should block LOS")


func test_entity_position_crud() -> void:
	var m := _make_small_map()
	check(m.get_entity_pos("hero") == Vector2i(-1, -1),
		"entity not placed should return (-1,-1)")
	m.set_entity_pos("hero", Vector2i(2, 2))
	check(m.get_entity_pos("hero") == Vector2i(2, 2),
		"after set, get_entity_pos should return the set position")
	var at_pos := m.get_entities_at(Vector2i(2, 2))
	check("hero" in at_pos, "get_entities_at should include 'hero' after placement")
	m.remove_entity("hero")
	check(m.get_entity_pos("hero") == Vector2i(-1, -1),
		"after remove, entity should not be found")
	check(m.get_entities_at(Vector2i(2, 2)).is_empty(),
		"after remove, get_entities_at should return empty")


func test_room_boundary_cells_not_open() -> void:
	var m := _make_small_map()
	if m.rooms.is_empty():
		check(false, "no rooms to test boundary on")
		return
	var room_id: int = m.rooms[0]["id"]
	var boundary := m.get_room_boundary_cells(room_id)
	check(not boundary.is_empty(), "room should have non-empty boundary")
	for b in boundary:
		var cell := m.get_cell(b)
		var tf: String = cell.get("terrain_feature", "")
		check(tf != "open",
			"boundary cell %s should not be 'open', got '%s'" % [str(b), tf])


func test_is_in_bounds() -> void:
	var m := _make_small_map()
	check(m.is_in_bounds(Vector2i(0, 0)), "(0,0) should be in bounds of 5×5 grid")
	check(m.is_in_bounds(Vector2i(4, 4)), "(4,4) should be in bounds of 5×5 grid")
	check(not m.is_in_bounds(Vector2i(5, 0)), "(5,0) should be out of bounds")
	check(not m.is_in_bounds(Vector2i(0, 5)), "(0,5) should be out of bounds")
	check(not m.is_in_bounds(Vector2i(-1, 0)), "(-1,0) should be out of bounds")
