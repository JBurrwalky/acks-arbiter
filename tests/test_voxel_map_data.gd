extends "res://tests/test_suite_base.gd"

## Unit tests for VoxelMapData sparse voxel storage.


func run_all_tests() -> void:
	test_empty_map_has_no_cells()
	test_set_and_get_cell()
	test_get_cell_absent_returns_sentinel()
	test_sentinel_not_shared()
	test_has_cell_true_and_false()
	test_remove_cell()
	test_set_cell_syncs_col_row_level()
	test_get_all_cells()
	test_get_all_positions()
	test_get_cells_at_level()
	test_get_levels_sorted()
	test_overwrite_cell()
	test_cell_count()
	# Phase 0 (session 7): entity tracking, fog, rooms, navigation, combat factory
	test_entity_set_and_get_pos()
	test_entity_pos_absent_returns_sentinel()
	test_get_entities_at()
	test_is_occupied()
	test_is_occupied_by_other()
	test_remove_entity()
	test_fog_get_default_hidden()
	test_fog_set_and_get()
	test_fog_set_hidden_no_create()
	test_fog_set_creates_cell()
	test_is_passable_delegates()
	test_is_passable_absent_false()
	test_is_walkable_with_open_door_delegates()
	test_is_walkable_with_open_door_absent_false()
	test_is_door()
	test_door_state_set_and_get()
	test_door_state_creates_cell()
	test_blocks_los_delegates()
	test_set_cell_field()
	test_detect_rooms_single_room()
	test_detect_rooms_two_rooms_separated()
	test_detect_rooms_per_level()
	test_get_room_cells()
	test_get_room_boundary_cells()
	test_transition_cell_queries()
	test_transition_cells_serialization()
	test_generate_open_field()
	test_generate_open_field_all_visible()
	if not has_failures():
		print("VoxelMapData: all tests passed.")


func test_empty_map_has_no_cells() -> void:
	var map := VoxelMapData.new()
	check(map.cell_count() == 0, "new map should have 0 cells")
	check(map.get_all_cells().size() == 0, "get_all_cells should be empty")
	check(map.get_levels().size() == 0, "get_levels should be empty")


func test_set_and_get_cell() -> void:
	var map := VoxelMapData.new()
	var cell := VoxelCell.new()
	cell.solidity = "solid"
	cell.feature = "wall_stone"
	var pos := Vector3i(3, 5, 2)
	map.set_cell(pos, cell)

	var got := map.get_cell(pos)
	check(got.solidity == "solid", "retrieved cell should have solidity 'solid'")
	check(got.feature == "wall_stone", "retrieved cell should have feature 'wall_stone'")


func test_get_cell_absent_returns_sentinel() -> void:
	var map := VoxelMapData.new()
	var sentinel := map.get_cell(Vector3i(99, 99, 99))
	check(sentinel.solidity == "air", "sentinel solidity should be 'air'")
	check(sentinel.feature == "open", "sentinel feature should be 'open'")
	check(sentinel.floor_type == "none", "sentinel floor_type should be 'none'")
	check(sentinel.fog_state == "hidden", "sentinel fog_state should be 'hidden'")
	check(sentinel.col == 99, "sentinel col should match requested position")
	check(sentinel.row == 99, "sentinel row should match requested position")
	check(sentinel.level == 99, "sentinel level should match requested position")


func test_sentinel_not_shared() -> void:
	var map := VoxelMapData.new()
	var pos := Vector3i(1, 2, 3)
	var s1 := map.get_cell(pos)
	s1.solidity = "solid"  # Mutate the sentinel
	var s2 := map.get_cell(pos)
	check(s2.solidity == "air",
		"mutating a sentinel should not affect subsequent get_cell calls")
	check(map.has_cell(pos) == false,
		"getting a sentinel should not store it in the map")


func test_has_cell_true_and_false() -> void:
	var map := VoxelMapData.new()
	var pos := Vector3i(1, 1, 0)
	check(map.has_cell(pos) == false, "has_cell should be false before set")
	map.set_cell(pos, VoxelCell.new())
	check(map.has_cell(pos) == true, "has_cell should be true after set")


func test_remove_cell() -> void:
	var map := VoxelMapData.new()
	var pos := Vector3i(2, 3, 1)
	map.set_cell(pos, VoxelCell.new())
	check(map.has_cell(pos) == true, "cell should exist before remove")
	map.remove_cell(pos)
	check(map.has_cell(pos) == false, "cell should not exist after remove")
	check(map.cell_count() == 0, "cell_count should be 0 after removing only cell")


func test_set_cell_syncs_col_row_level() -> void:
	var map := VoxelMapData.new()
	var cell := VoxelCell.new()
	cell.col = 99
	cell.row = 99
	cell.level = 99
	var pos := Vector3i(5, 10, 3)
	map.set_cell(pos, cell)
	check(cell.col == 5, "set_cell should sync col to pos.x")
	check(cell.row == 10, "set_cell should sync row to pos.y")
	check(cell.level == 3, "set_cell should sync level to pos.z")


func test_get_all_cells() -> void:
	var map := VoxelMapData.new()
	map.set_cell(Vector3i(0, 0, 0), VoxelCell.new())
	map.set_cell(Vector3i(1, 0, 0), VoxelCell.new())
	map.set_cell(Vector3i(0, 0, 1), VoxelCell.new())
	var all := map.get_all_cells()
	check(all.size() == 3, "get_all_cells should return 3 cells, got %d" % all.size())


func test_get_all_positions() -> void:
	var map := VoxelMapData.new()
	var p1 := Vector3i(0, 0, 0)
	var p2 := Vector3i(1, 2, 3)
	map.set_cell(p1, VoxelCell.new())
	map.set_cell(p2, VoxelCell.new())
	var positions := map.get_all_positions()
	check(positions.size() == 2, "get_all_positions should return 2 positions")
	check(p1 in positions, "positions should contain p1")
	check(p2 in positions, "positions should contain p2")


func test_get_cells_at_level() -> void:
	var map := VoxelMapData.new()
	map.set_cell(Vector3i(0, 0, 0), VoxelCell.new())
	map.set_cell(Vector3i(1, 0, 0), VoxelCell.new())
	map.set_cell(Vector3i(0, 0, 1), VoxelCell.new())
	map.set_cell(Vector3i(1, 1, 1), VoxelCell.new())
	map.set_cell(Vector3i(0, 0, 2), VoxelCell.new())

	var level_0 := map.get_cells_at_level(0)
	check(level_0.size() == 2, "level 0 should have 2 cells, got %d" % level_0.size())

	var level_1 := map.get_cells_at_level(1)
	check(level_1.size() == 2, "level 1 should have 2 cells, got %d" % level_1.size())

	var level_2 := map.get_cells_at_level(2)
	check(level_2.size() == 1, "level 2 should have 1 cell, got %d" % level_2.size())

	var level_99 := map.get_cells_at_level(99)
	check(level_99.size() == 0, "level 99 should have 0 cells")


func test_get_levels_sorted() -> void:
	var map := VoxelMapData.new()
	map.set_cell(Vector3i(0, 0, 3), VoxelCell.new())
	map.set_cell(Vector3i(0, 0, 0), VoxelCell.new())
	map.set_cell(Vector3i(0, 0, 1), VoxelCell.new())
	map.set_cell(Vector3i(1, 1, 3), VoxelCell.new())  # duplicate level 3
	var levels := map.get_levels()
	check(levels.size() == 3, "should have 3 unique levels, got %d" % levels.size())
	check(levels[0] == 0, "first level should be 0")
	check(levels[1] == 1, "second level should be 1")
	check(levels[2] == 3, "third level should be 3")


func test_overwrite_cell() -> void:
	var map := VoxelMapData.new()
	var pos := Vector3i(1, 1, 0)
	var cell1 := VoxelCell.new()
	cell1.feature = "rock"
	map.set_cell(pos, cell1)

	var cell2 := VoxelCell.new()
	cell2.feature = "wall_stone"
	map.set_cell(pos, cell2)

	var got := map.get_cell(pos)
	check(got.feature == "wall_stone",
		"overwritten cell should have new feature, got '%s'" % got.feature)
	check(map.cell_count() == 1, "cell_count should still be 1 after overwrite")


func test_cell_count() -> void:
	var map := VoxelMapData.new()
	check(map.cell_count() == 0, "empty map cell_count = 0")
	map.set_cell(Vector3i(0, 0, 0), VoxelCell.new())
	check(map.cell_count() == 1, "after 1 set, cell_count = 1")
	map.set_cell(Vector3i(1, 0, 0), VoxelCell.new())
	check(map.cell_count() == 2, "after 2 sets, cell_count = 2")
	map.remove_cell(Vector3i(0, 0, 0))
	check(map.cell_count() == 1, "after remove, cell_count = 1")


# ---------------------------------------------------------------------------
# Entity tracking
# ---------------------------------------------------------------------------

func test_entity_set_and_get_pos() -> void:
	var map := VoxelMapData.new()
	var pos := Vector3i(3, 5, 2)
	map.set_entity_pos("hero_1", pos)
	check(map.get_entity_pos("hero_1") == pos, "get_entity_pos should return set position")


func test_entity_pos_absent_returns_sentinel() -> void:
	var map := VoxelMapData.new()
	var pos := map.get_entity_pos("nonexistent")
	check(pos == Vector3i(-1, -1, -1), "absent entity pos should be (-1,-1,-1)")


func test_get_entities_at() -> void:
	var map := VoxelMapData.new()
	var pos := Vector3i(1, 1, 0)
	map.set_entity_pos("a", pos)
	map.set_entity_pos("b", pos)
	map.set_entity_pos("c", Vector3i(2, 2, 0))
	var at_pos := map.get_entities_at(pos)
	check(at_pos.size() == 2, "should have 2 entities at pos, got %d" % at_pos.size())
	check("a" in at_pos, "should contain 'a'")
	check("b" in at_pos, "should contain 'b'")


func test_is_occupied() -> void:
	var map := VoxelMapData.new()
	var pos := Vector3i(3, 3, 0)
	check(map.is_occupied(pos) == false, "empty map: not occupied")
	map.set_entity_pos("hero", pos)
	check(map.is_occupied(pos) == true, "after placing entity: occupied")


func test_is_occupied_by_other() -> void:
	var map := VoxelMapData.new()
	var pos := Vector3i(1, 1, 0)
	map.set_entity_pos("hero", pos)
	check(map.is_occupied_by_other(pos, "hero") == false,
		"only occupant is excluded: should be false")
	map.set_entity_pos("goblin", pos)
	check(map.is_occupied_by_other(pos, "hero") == true,
		"another entity present: should be true")


func test_remove_entity() -> void:
	var map := VoxelMapData.new()
	map.set_entity_pos("hero", Vector3i(1, 1, 0))
	map.remove_entity("hero")
	check(map.get_entity_pos("hero") == Vector3i(-1, -1, -1),
		"removed entity should return sentinel pos")


# ---------------------------------------------------------------------------
# Fog of war
# ---------------------------------------------------------------------------

func test_fog_get_default_hidden() -> void:
	var map := VoxelMapData.new()
	check(map.get_fog(Vector3i(5, 5, 0)) == "hidden", "absent cell fog should be 'hidden'")


func test_fog_set_and_get() -> void:
	var map := VoxelMapData.new()
	var pos := Vector3i(1, 1, 0)
	var cell := VoxelCell.new()
	cell.floor_type = "stone"
	map.set_cell(pos, cell)
	map.set_fog(pos, "visible")
	check(map.get_fog(pos) == "visible", "fog should be 'visible' after set")
	map.set_fog(pos, "explored")
	check(map.get_fog(pos) == "explored", "fog should be 'explored' after update")


func test_fog_set_hidden_no_create() -> void:
	var map := VoxelMapData.new()
	var pos := Vector3i(99, 99, 99)
	map.set_fog(pos, "hidden")
	check(map.has_cell(pos) == false,
		"setting fog to 'hidden' on absent cell should not create it")


func test_fog_set_creates_cell() -> void:
	var map := VoxelMapData.new()
	var pos := Vector3i(5, 5, 0)
	map.set_fog(pos, "explored")
	check(map.has_cell(pos) == true,
		"setting fog to non-hidden on absent cell should create it")
	check(map.get_cell(pos).fog_state == "explored",
		"created cell should have the set fog_state")


# ---------------------------------------------------------------------------
# Navigation queries
# ---------------------------------------------------------------------------

func test_is_passable_delegates() -> void:
	var map := VoxelMapData.new()
	var pos := Vector3i(1, 1, 0)
	var cell := VoxelCell.new()
	cell.solidity = "air"
	cell.feature = "open"
	map.set_cell(pos, cell)
	check(map.is_passable(pos) == true, "air+open cell should be passable")

	cell.solidity = "solid"
	check(map.is_passable(pos) == false, "solid cell should not be passable")


func test_is_passable_absent_false() -> void:
	var map := VoxelMapData.new()
	check(map.is_passable(Vector3i(99, 99, 99)) == false,
		"absent cell should not be passable")


func test_is_walkable_with_open_door_delegates() -> void:
	var map := VoxelMapData.new()
	var pos := Vector3i(3, 3, 0)
	var cell := VoxelCell.new()
	cell.solidity = "air"
	cell.door_state = "closed"
	cell.door_type = "unlocked"
	map.set_cell(pos, cell)
	check(map.is_passable(pos) == false,
		"strict is_passable rejects closed unlocked door")
	check(map.is_walkable_with_open_door(pos) == true,
		"explore-mode is_walkable_with_open_door permits closed unlocked door")
	cell.door_state = "locked"
	check(map.is_walkable_with_open_door(pos) == false,
		"explore-mode still blocks locked door")


func test_is_walkable_with_open_door_absent_false() -> void:
	var map := VoxelMapData.new()
	check(map.is_walkable_with_open_door(Vector3i(7, 7, 0)) == false,
		"absent cell should not be walkable")


func test_is_door() -> void:
	var map := VoxelMapData.new()
	var pos := Vector3i(2, 2, 0)
	var cell := VoxelCell.new()
	cell.door_state = "closed"
	cell.door_type = "locked"
	map.set_cell(pos, cell)
	check(map.is_door(pos) == true, "cell with door_state should be a door")
	check(map.is_door(Vector3i(0, 0, 0)) == false, "absent cell is not a door")


func test_door_state_set_and_get() -> void:
	var map := VoxelMapData.new()
	var pos := Vector3i(2, 2, 0)
	var cell := VoxelCell.new()
	cell.door_state = "closed"
	map.set_cell(pos, cell)
	check(map.get_door_state(pos) == "closed", "door should be closed")
	map.set_door_state(pos, "open")
	check(map.get_door_state(pos) == "open", "door should be open after set")


func test_door_state_creates_cell() -> void:
	var map := VoxelMapData.new()
	var pos := Vector3i(10, 10, 0)
	map.set_door_state(pos, "closed")
	check(map.has_cell(pos) == true, "set_door_state should create cell if absent")
	check(map.get_door_state(pos) == "closed", "created cell should have door_state")


func test_blocks_los_delegates() -> void:
	var map := VoxelMapData.new()
	var pos := Vector3i(1, 1, 0)
	var cell := VoxelCell.new()
	cell.solidity = "solid"
	cell.feature = "wall_stone"
	map.set_cell(pos, cell)
	check(map.blocks_los(pos) == true, "solid wall should block LOS")

	cell.feature = "arrow_slit"
	check(map.blocks_los(pos) == false, "arrow slit should not block LOS")


func test_set_cell_field() -> void:
	var map := VoxelMapData.new()
	var pos := Vector3i(1, 1, 0)
	var cell := VoxelCell.new()
	map.set_cell(pos, cell)
	map.set_cell_field(pos, "cover_value", 3)
	check(map.get_cell(pos).cover_value == 3, "set_cell_field should update field")


# ---------------------------------------------------------------------------
# Room detection
# ---------------------------------------------------------------------------

func _make_test_room_map() -> VoxelMapData:
	## Creates a 3x3 room surrounded by walls on level 0.
	var map := VoxelMapData.new()
	for col in range(5):
		for row in range(5):
			var cell := VoxelCell.new()
			if col == 0 or col == 4 or row == 0 or row == 4:
				cell.solidity = "solid"
				cell.feature = "wall_stone"
			else:
				cell.solidity = "air"
				cell.feature = "open"
				cell.floor_type = "stone"
			map.set_cell(Vector3i(col, row, 0), cell)
	return map


func test_detect_rooms_single_room() -> void:
	var map := _make_test_room_map()
	map.detect_rooms()
	check(map.rooms.size() == 1, "should detect 1 room, got %d" % map.rooms.size())
	check(map.rooms[0]["cells"].size() == 9,
		"3x3 interior should have 9 cells, got %d" % map.rooms[0]["cells"].size())
	check(map.get_room_at(Vector3i(2, 2, 0)) == 0, "center cell should be room 0")
	check(map.get_room_at(Vector3i(0, 0, 0)) == -1, "wall cell should have no room")


func test_detect_rooms_two_rooms_separated() -> void:
	var map := VoxelMapData.new()
	# Room A: cells at (0,0,0) and (1,0,0)
	for col in range(2):
		var cell := VoxelCell.new()
		cell.solidity = "air"
		cell.feature = "open"
		cell.floor_type = "stone"
		map.set_cell(Vector3i(col, 0, 0), cell)

	# Wall separator at (2,0,0)
	var wall := VoxelCell.new()
	wall.solidity = "solid"
	wall.feature = "wall_stone"
	map.set_cell(Vector3i(2, 0, 0), wall)

	# Room B: cells at (3,0,0) and (4,0,0)
	for col in range(3, 5):
		var cell := VoxelCell.new()
		cell.solidity = "air"
		cell.feature = "open"
		cell.floor_type = "stone"
		map.set_cell(Vector3i(col, 0, 0), cell)

	map.detect_rooms()
	check(map.rooms.size() == 2, "should detect 2 rooms, got %d" % map.rooms.size())


func test_detect_rooms_per_level() -> void:
	var map := VoxelMapData.new()
	# Same col/row on different levels should be separate rooms
	for lvl in [0, 2]:
		var cell := VoxelCell.new()
		cell.solidity = "air"
		cell.feature = "open"
		cell.floor_type = "stone"
		map.set_cell(Vector3i(0, 0, lvl), cell)

	map.detect_rooms()
	check(map.rooms.size() == 2,
		"cells on different levels should be separate rooms, got %d" % map.rooms.size())


func test_get_room_cells() -> void:
	var map := _make_test_room_map()
	map.detect_rooms()
	var cells := map.get_room_cells(0)
	check(cells.size() == 9, "room 0 should have 9 cells")
	check(Vector3i(1, 1, 0) in cells, "room should contain (1,1,0)")


func test_get_room_boundary_cells() -> void:
	var map := _make_test_room_map()
	map.detect_rooms()
	var boundary := map.get_room_boundary_cells(0)
	# The boundary should be the wall cells adjacent to the room
	check(boundary.size() > 0, "room should have boundary cells")
	check(Vector3i(0, 1, 0) in boundary, "wall at (0,1,0) should be boundary")
	check(not (Vector3i(2, 2, 0) in boundary), "center cell should not be boundary")


# ---------------------------------------------------------------------------
# Transition cells
# ---------------------------------------------------------------------------

func test_transition_cell_queries() -> void:
	var map := VoxelMapData.new()
	var tc1 := Vector3i(3, 3, 0)
	var tc2 := Vector3i(5, 5, 2)
	map.transition_cells.append(tc1)
	map.transition_cells.append(tc2)
	map.transition_cell_labels[tc1] = "Entrance"

	check(map.is_transition_cell(tc1) == true, "tc1 should be transition cell")
	check(map.is_transition_cell(tc2) == true, "tc2 should be transition cell")
	check(map.is_transition_cell(Vector3i(0, 0, 0)) == false,
		"non-transition cell should return false")
	check(map.get_transition_cell_label(tc1) == "Entrance",
		"tc1 label should be 'Entrance'")
	check(map.get_transition_cell_label(tc2).begins_with("Cell"),
		"tc2 should have default label")


func test_transition_cells_serialization() -> void:
	var map := VoxelMapData.new()
	var tc := Vector3i(3, 3, 0)
	map.transition_cells.append(tc)
	map.transition_cell_labels[tc] = "Exit"

	var dict := map.to_dict()
	check(dict.has("transition_cells"), "to_dict should include transition_cells")
	check(dict["transition_cells"].size() == 1, "should have 1 transition cell in dict")
	check(dict["transition_cells"][0]["label"] == "Exit", "label should be serialized")

	var restored := VoxelMapData.from_dict(dict)
	check(restored.is_transition_cell(tc), "restored map should have transition cell")
	check(restored.get_transition_cell_label(tc) == "Exit",
		"restored label should be 'Exit'")


# ---------------------------------------------------------------------------
# Combat map factory
# ---------------------------------------------------------------------------

func test_generate_open_field() -> void:
	var map := VoxelMapData.generate_open_field(10, 8)
	check(map.cell_count() == 80, "10x8 field should have 80 cells, got %d" % map.cell_count())
	check(map.entry_pos == Vector3i(2, 4, 0), "entry should be (2, 4, 0)")
	var cell := map.get_cell(Vector3i(5, 3, 0))
	check(cell.feature == "open", "field cells should be 'open'")
	check(cell.floor_type == "grass", "field cells should have 'grass' floor")
	check(cell.solidity == "air", "field cells should be 'air'")


func test_generate_open_field_all_visible() -> void:
	var map := VoxelMapData.generate_open_field(5, 5)
	for pos: Vector3i in map.get_all_positions():
		check(map.get_fog(pos) == "visible",
			"open field cells should have 'visible' fog")
