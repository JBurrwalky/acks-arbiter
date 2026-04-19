extends "res://tests/test_suite_base.gd"

## Unit tests for VoxelLOS 3D line-of-sight.
##
## Tests LOS through open cells, blocking by solid/doors, special features
## (arrow slit, window, portcullis), cross-level rays, and cover values.


func run_all_tests() -> void:
	test_los_same_cell()
	test_los_adjacent_open()
	test_los_blocked_by_solid()
	test_los_blocked_by_closed_door()
	test_los_through_open_door()
	test_los_through_portcullis()
	test_los_through_arrow_slit()
	test_los_through_window()
	test_los_diagonal_same_level()
	test_los_across_levels_clear()
	test_los_across_levels_blocked()
	test_los_long_range_open()
	test_los_start_not_checked()
	test_los_end_not_checked()
	test_los_absent_cells_dont_block()
	test_cover_value_no_cover()
	test_cover_value_partial()
	test_cover_value_max_aggregation()
	if not has_failures():
		print("VoxelLOS: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_open_line(from_pos: Vector3i, to_pos: Vector3i) -> VoxelMapData:
	## Creates a map with open air cells along a line from from_pos to to_pos.
	var map := VoxelMapData.new()
	# Add cells at start and end
	var cell_a := VoxelCell.new()
	cell_a.floor_type = "stone"
	map.set_cell(from_pos, cell_a)
	var cell_b := VoxelCell.new()
	cell_b.floor_type = "stone"
	map.set_cell(to_pos, cell_b)
	return map


func _place_solid(map: VoxelMapData, pos: Vector3i) -> void:
	var cell := VoxelCell.new()
	cell.solidity = "solid"
	cell.feature = "rock"
	map.set_cell(pos, cell)


func _place_door(map: VoxelMapData, pos: Vector3i, state: String, dtype: String = "unlocked") -> void:
	var cell := VoxelCell.new()
	cell.door_state = state
	cell.door_type = dtype
	cell.floor_type = "stone"
	map.set_cell(pos, cell)


# ---------------------------------------------------------------------------
# LOS tests
# ---------------------------------------------------------------------------

func test_los_same_cell() -> void:
	var map := VoxelMapData.new()
	check(VoxelLOS.has_los(map, Vector3i(5, 5, 0), Vector3i(5, 5, 0)) == true,
		"LOS to same cell should always be true")


func test_los_adjacent_open() -> void:
	var map := _make_open_line(Vector3i(5, 5, 0), Vector3i(6, 5, 0))
	check(VoxelLOS.has_los(map, Vector3i(5, 5, 0), Vector3i(6, 5, 0)) == true,
		"LOS between adjacent open cells should be clear")


func test_los_blocked_by_solid() -> void:
	var map := VoxelMapData.new()
	# Place solid wall between (5,5,0) and (7,5,0)
	_place_solid(map, Vector3i(6, 5, 0))
	check(VoxelLOS.has_los(map, Vector3i(5, 5, 0), Vector3i(7, 5, 0)) == false,
		"solid cell between should block LOS")


func test_los_blocked_by_closed_door() -> void:
	var map := VoxelMapData.new()
	_place_door(map, Vector3i(6, 5, 0), "closed")
	check(VoxelLOS.has_los(map, Vector3i(5, 5, 0), Vector3i(7, 5, 0)) == false,
		"closed door should block LOS")


func test_los_through_open_door() -> void:
	var map := VoxelMapData.new()
	_place_door(map, Vector3i(6, 5, 0), "open")
	check(VoxelLOS.has_los(map, Vector3i(5, 5, 0), Vector3i(7, 5, 0)) == true,
		"open door should not block LOS")


func test_los_through_portcullis() -> void:
	var map := VoxelMapData.new()
	_place_door(map, Vector3i(6, 5, 0), "closed", "portcullis")
	check(VoxelLOS.has_los(map, Vector3i(5, 5, 0), Vector3i(7, 5, 0)) == true,
		"closed portcullis should not block LOS")


func test_los_through_arrow_slit() -> void:
	var map := VoxelMapData.new()
	var cell := VoxelCell.new()
	cell.solidity = "solid"
	cell.feature = "arrow_slit"
	map.set_cell(Vector3i(6, 5, 0), cell)
	check(VoxelLOS.has_los(map, Vector3i(5, 5, 0), Vector3i(7, 5, 0)) == true,
		"arrow slit should not block LOS")


func test_los_through_window() -> void:
	var map := VoxelMapData.new()
	var cell := VoxelCell.new()
	cell.solidity = "solid"
	cell.feature = "window"
	map.set_cell(Vector3i(6, 5, 0), cell)
	check(VoxelLOS.has_los(map, Vector3i(5, 5, 0), Vector3i(7, 5, 0)) == true,
		"window should not block LOS")


func test_los_diagonal_same_level() -> void:
	# Diagonal ray from (3,3,0) to (6,6,0) — 3 cells apart diagonally
	# All intermediate cells are absent (sentinel air) — should pass
	var map := VoxelMapData.new()
	check(VoxelLOS.has_los(map, Vector3i(3, 3, 0), Vector3i(6, 6, 0)) == true,
		"diagonal ray through empty cells should be clear")


func test_los_across_levels_clear() -> void:
	# Vertical LOS from (5,5,0) to (5,5,3) — straight up through air
	var map := VoxelMapData.new()
	check(VoxelLOS.has_los(map, Vector3i(5, 5, 0), Vector3i(5, 5, 3)) == true,
		"vertical ray through air should be clear")


func test_los_across_levels_blocked() -> void:
	# Vertical LOS from (5,5,0) to (5,5,3) with solid at level 2
	var map := VoxelMapData.new()
	_place_solid(map, Vector3i(5, 5, 2))
	check(VoxelLOS.has_los(map, Vector3i(5, 5, 0), Vector3i(5, 5, 3)) == false,
		"solid cell in vertical path should block LOS")


func test_los_long_range_open() -> void:
	# 10 cells apart, all air
	var map := VoxelMapData.new()
	check(VoxelLOS.has_los(map, Vector3i(0, 0, 0), Vector3i(10, 0, 0)) == true,
		"long range through empty air should be clear")


func test_los_start_not_checked() -> void:
	# Start cell is solid, but LOS should still pass (start not checked)
	var map := VoxelMapData.new()
	_place_solid(map, Vector3i(5, 5, 0))
	check(VoxelLOS.has_los(map, Vector3i(5, 5, 0), Vector3i(7, 5, 0)) == true,
		"start cell should not be checked for LOS blocking")


func test_los_end_not_checked() -> void:
	# End cell is solid, but LOS should still pass (end not checked)
	var map := VoxelMapData.new()
	_place_solid(map, Vector3i(7, 5, 0))
	check(VoxelLOS.has_los(map, Vector3i(5, 5, 0), Vector3i(7, 5, 0)) == true,
		"end cell should not be checked for LOS blocking")


func test_los_absent_cells_dont_block() -> void:
	# All cells absent (empty map) — sentinels are air, should not block
	var map := VoxelMapData.new()
	check(VoxelLOS.has_los(map, Vector3i(0, 0, 0), Vector3i(5, 5, 5)) == true,
		"absent sentinel cells should not block LOS")


# ---------------------------------------------------------------------------
# Cover value tests
# ---------------------------------------------------------------------------

func test_cover_value_no_cover() -> void:
	var map := VoxelMapData.new()
	var cv := VoxelLOS.get_cover_value(map, Vector3i(5, 5, 0), Vector3i(8, 5, 0))
	check(cv == 0, "open path should have 0 cover, got %d" % cv)


func test_cover_value_partial() -> void:
	var map := VoxelMapData.new()
	var cell := VoxelCell.new()
	cell.cover_value = 2
	map.set_cell(Vector3i(6, 5, 0), cell)
	var cv := VoxelLOS.get_cover_value(map, Vector3i(5, 5, 0), Vector3i(7, 5, 0))
	check(cv == 2, "should return cover_value 2 from intermediate cell, got %d" % cv)


func test_cover_value_max_aggregation() -> void:
	var map := VoxelMapData.new()
	var cell1 := VoxelCell.new()
	cell1.cover_value = 1
	map.set_cell(Vector3i(6, 5, 0), cell1)
	var cell2 := VoxelCell.new()
	cell2.cover_value = 3
	map.set_cell(Vector3i(7, 5, 0), cell2)
	# Ray from (5,5,0) to (9,5,0) — intermediate cells at 6,7,8
	var cv := VoxelLOS.get_cover_value(map, Vector3i(5, 5, 0), Vector3i(9, 5, 0))
	check(cv == 3, "should return max cover_value 3, got %d" % cv)
