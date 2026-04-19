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
