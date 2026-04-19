extends "res://tests/test_suite_base.gd"

## Unit tests for VoxelGrid static 3D grid math.
##
## Tests coordinate conversion (cell <-> world including Y), 3D adjacency,
## Chebyshev distance, neighbor enumeration, and direction helpers.


func run_all_tests() -> void:
	test_cell_to_world_origin()
	test_cell_to_world_positive_col()
	test_cell_to_world_positive_row()
	test_cell_to_world_with_level()
	test_cell_to_world_negative_level()
	test_world_to_cell_roundtrip()
	test_world_to_cell_includes_y()
	test_get_neighbors_3d_count()
	test_get_neighbors_3d_excludes_center()
	test_get_neighbors_3d_specific()
	test_get_neighbors_3d_diagonal_vertical()
	test_get_neighbors_2d_count()
	test_get_neighbors_2d_same_level()
	test_is_adjacent_same_level_orthogonal()
	test_is_adjacent_same_level_diagonal()
	test_is_adjacent_cross_level()
	test_is_adjacent_same_cell_false()
	test_is_adjacent_far_false()
	test_is_adjacent_two_levels_false()
	test_chebyshev_distance_same()
	test_chebyshev_distance_adjacent()
	test_chebyshev_distance_3d()
	test_direction_offset_values()
	test_step_horizontal()
	if not has_failures():
		print("VoxelGrid: all tests passed.")


# ---------------------------------------------------------------------------
# Coordinate conversion
# ---------------------------------------------------------------------------

func test_cell_to_world_origin() -> void:
	var w := VoxelGrid.cell_to_world(0, 0, 0)
	check(w.is_equal_approx(Vector3.ZERO),
		"cell_to_world(0,0,0) should be Vector3.ZERO, got %s" % str(w))


func test_cell_to_world_positive_col() -> void:
	# col=2, row=0, level=0: x=(2-0)*0.5=1.0, z=(2+0)*0.5=1.0, y=0
	var w := VoxelGrid.cell_to_world(2, 0, 0)
	check(w.is_equal_approx(Vector3(1.0, 0.0, 1.0)),
		"cell_to_world(2,0,0) should be (1,0,1), got %s" % str(w))


func test_cell_to_world_positive_row() -> void:
	# col=0, row=2, level=0: x=(0-2)*0.5=-1.0, z=(0+2)*0.5=1.0, y=0
	var w := VoxelGrid.cell_to_world(0, 2, 0)
	check(w.is_equal_approx(Vector3(-1.0, 0.0, 1.0)),
		"cell_to_world(0,2,0) should be (-1,0,1), got %s" % str(w))


func test_cell_to_world_with_level() -> void:
	# col=1, row=1, level=3: x=0, z=1.0, y=3.0
	var w := VoxelGrid.cell_to_world(1, 1, 3)
	check(w.is_equal_approx(Vector3(0.0, 3.0, 1.0)),
		"cell_to_world(1,1,3) y should be 3.0, got %s" % str(w))


func test_cell_to_world_negative_level() -> void:
	var w := VoxelGrid.cell_to_world(0, 0, -2)
	check(w.is_equal_approx(Vector3(0.0, -2.0, 0.0)),
		"cell_to_world(0,0,-2) y should be -2.0, got %s" % str(w))


func test_world_to_cell_roundtrip() -> void:
	var test_cases: Array[Vector3i] = [
		Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 1, 0),
		Vector3i(3, 5, 2), Vector3i(10, 7, 4), Vector3i(0, 0, -1),
	]
	for cell_pos in test_cases:
		var world := VoxelGrid.cell_to_world(cell_pos.x, cell_pos.y, cell_pos.z)
		var back := VoxelGrid.world_to_cell(world)
		check(back == cell_pos,
			"roundtrip failed for %s: got %s" % [str(cell_pos), str(back)])


func test_world_to_cell_includes_y() -> void:
	# World pos with y=5.0 should map to level=5
	var pos := VoxelGrid.world_to_cell(Vector3(0.0, 5.0, 0.0))
	check(pos.z == 5, "world y=5.0 should map to level=5, got %d" % pos.z)


# ---------------------------------------------------------------------------
# 3D neighbors
# ---------------------------------------------------------------------------

func test_get_neighbors_3d_count() -> void:
	var n := VoxelGrid.get_neighbors_3d(Vector3i(5, 5, 5))
	check(n.size() == 26, "3D neighbors should be 26, got %d" % n.size())


func test_get_neighbors_3d_excludes_center() -> void:
	var center := Vector3i(5, 5, 5)
	var n := VoxelGrid.get_neighbors_3d(center)
	check(center not in n, "3D neighbors should not include center")


func test_get_neighbors_3d_specific() -> void:
	var center := Vector3i(5, 5, 5)
	var n := VoxelGrid.get_neighbors_3d(center)
	# Face neighbors (same level)
	check(Vector3i(4, 5, 5) in n, "west neighbor should be included")
	check(Vector3i(6, 5, 5) in n, "east neighbor should be included")
	check(Vector3i(5, 4, 5) in n, "north neighbor should be included")
	check(Vector3i(5, 6, 5) in n, "south neighbor should be included")
	# Vertical neighbors (same col/row)
	check(Vector3i(5, 5, 4) in n, "below neighbor should be included")
	check(Vector3i(5, 5, 6) in n, "above neighbor should be included")


func test_get_neighbors_3d_diagonal_vertical() -> void:
	var center := Vector3i(5, 5, 5)
	var n := VoxelGrid.get_neighbors_3d(center)
	# Diagonal in all 3 axes simultaneously (corner of 3x3x3 cube)
	check(Vector3i(6, 6, 6) in n, "3D diagonal corner should be included")
	check(Vector3i(4, 4, 4) in n, "3D diagonal corner (opposite) should be included")
	# Edge: horizontal diagonal + level change
	check(Vector3i(6, 4, 6) in n, "NE + up should be included")


func test_get_neighbors_2d_count() -> void:
	var n := VoxelGrid.get_neighbors_2d(Vector3i(5, 5, 3))
	check(n.size() == 8, "2D neighbors should be 8, got %d" % n.size())


func test_get_neighbors_2d_same_level() -> void:
	var center := Vector3i(5, 5, 3)
	var n := VoxelGrid.get_neighbors_2d(center)
	for neighbor: Vector3i in n:
		check(neighbor.z == 3,
			"2D neighbor %s should have same level 3" % str(neighbor))


# ---------------------------------------------------------------------------
# Adjacency
# ---------------------------------------------------------------------------

func test_is_adjacent_same_level_orthogonal() -> void:
	check(VoxelGrid.is_adjacent(Vector3i(5, 5, 0), Vector3i(6, 5, 0)) == true,
		"same-level east neighbor should be adjacent")
	check(VoxelGrid.is_adjacent(Vector3i(5, 5, 0), Vector3i(5, 4, 0)) == true,
		"same-level north neighbor should be adjacent")


func test_is_adjacent_same_level_diagonal() -> void:
	check(VoxelGrid.is_adjacent(Vector3i(5, 5, 0), Vector3i(6, 6, 0)) == true,
		"same-level SE diagonal should be adjacent")


func test_is_adjacent_cross_level() -> void:
	check(VoxelGrid.is_adjacent(Vector3i(5, 5, 0), Vector3i(5, 5, 1)) == true,
		"directly above should be adjacent")
	check(VoxelGrid.is_adjacent(Vector3i(5, 5, 0), Vector3i(6, 6, 1)) == true,
		"diagonal + one level up should be adjacent")


func test_is_adjacent_same_cell_false() -> void:
	check(VoxelGrid.is_adjacent(Vector3i(5, 5, 0), Vector3i(5, 5, 0)) == false,
		"same cell should not be adjacent")


func test_is_adjacent_far_false() -> void:
	check(VoxelGrid.is_adjacent(Vector3i(5, 5, 0), Vector3i(7, 5, 0)) == false,
		"2 cells away should not be adjacent")


func test_is_adjacent_two_levels_false() -> void:
	check(VoxelGrid.is_adjacent(Vector3i(5, 5, 0), Vector3i(5, 5, 2)) == false,
		"2 levels apart should not be adjacent")


# ---------------------------------------------------------------------------
# Chebyshev distance
# ---------------------------------------------------------------------------

func test_chebyshev_distance_same() -> void:
	check(VoxelGrid.chebyshev_distance(Vector3i(3, 3, 3), Vector3i(3, 3, 3)) == 0,
		"distance to self should be 0")


func test_chebyshev_distance_adjacent() -> void:
	check(VoxelGrid.chebyshev_distance(Vector3i(3, 3, 0), Vector3i(4, 3, 0)) == 1,
		"orthogonal neighbor distance should be 1")
	check(VoxelGrid.chebyshev_distance(Vector3i(3, 3, 0), Vector3i(4, 4, 1)) == 1,
		"3D diagonal neighbor distance should be 1")


func test_chebyshev_distance_3d() -> void:
	# max(|5-3|, |3-3|, |7-3|) = max(2, 0, 4) = 4
	check(VoxelGrid.chebyshev_distance(Vector3i(3, 3, 3), Vector3i(5, 3, 7)) == 4,
		"3D distance should be max of axis deltas")


# ---------------------------------------------------------------------------
# Direction helpers
# ---------------------------------------------------------------------------

func test_direction_offset_values() -> void:
	check(VoxelGrid.direction_offset(VoxelGrid.Direction.N) == Vector2i(0, -1),
		"N offset should be (0,-1)")
	check(VoxelGrid.direction_offset(VoxelGrid.Direction.NE) == Vector2i(1, -1),
		"NE offset should be (1,-1)")
	check(VoxelGrid.direction_offset(VoxelGrid.Direction.E) == Vector2i(1, 0),
		"E offset should be (1,0)")
	check(VoxelGrid.direction_offset(VoxelGrid.Direction.SE) == Vector2i(1, 1),
		"SE offset should be (1,1)")
	check(VoxelGrid.direction_offset(VoxelGrid.Direction.S) == Vector2i(0, 1),
		"S offset should be (0,1)")
	check(VoxelGrid.direction_offset(VoxelGrid.Direction.SW) == Vector2i(-1, 1),
		"SW offset should be (-1,1)")
	check(VoxelGrid.direction_offset(VoxelGrid.Direction.W) == Vector2i(-1, 0),
		"W offset should be (-1,0)")
	check(VoxelGrid.direction_offset(VoxelGrid.Direction.NW) == Vector2i(-1, -1),
		"NW offset should be (-1,-1)")


func test_step_horizontal() -> void:
	var start := Vector3i(5, 5, 3)
	var stepped := VoxelGrid.step_horizontal(start, VoxelGrid.Direction.NE)
	check(stepped == Vector3i(6, 4, 3),
		"step NE from (5,5,3) should be (6,4,3), got %s" % str(stepped))
