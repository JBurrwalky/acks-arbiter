extends "res://tests/test_suite_base.gd"

## Unit tests for IsometricGrid static utility.
##
## Tests coordinate conversion, adjacency, and range queries.


func run_all_tests() -> void:
	test_cell_to_screen_origin()
	test_cell_to_screen_positive_col()
	test_cell_to_screen_positive_row()
	test_cell_to_screen_diagonal()
	test_screen_to_cell_roundtrip()
	test_get_neighbors_count()
	test_get_neighbors_directions()
	test_is_adjacent_true()
	test_is_adjacent_diagonal_true()
	test_is_adjacent_false_far()
	test_chebyshev_distance()
	test_manhattan_distance_zero()
	test_manhattan_distance_adjacent()
	test_manhattan_distance_far()
	test_cells_in_radius_zero()
	test_cells_in_radius_one()
	test_cells_in_radius_two()
	if not has_failures():
		print("IsometricGrid: all tests passed.")


func test_cell_to_screen_origin() -> void:
	var s := IsometricGrid.cell_to_screen(0, 0)
	check(s == Vector2.ZERO, "cell_to_screen(0,0) should be (0,0), got %s" % str(s))


func test_cell_to_screen_positive_col() -> void:
	# col=1, row=0: x=(1-0)*32=32, y=(1+0)*16=16
	var s := IsometricGrid.cell_to_screen(1, 0)
	check(s == Vector2(32.0, 16.0),
		"cell_to_screen(1,0) should be (32,16), got %s" % str(s))


func test_cell_to_screen_positive_row() -> void:
	# col=0, row=1: x=(0-1)*32=-32, y=(0+1)*16=16
	var s := IsometricGrid.cell_to_screen(0, 1)
	check(s == Vector2(-32.0, 16.0),
		"cell_to_screen(0,1) should be (-32,16), got %s" % str(s))


func test_cell_to_screen_diagonal() -> void:
	# col=2, row=2: x=(2-2)*32=0, y=(2+2)*16=64
	var s := IsometricGrid.cell_to_screen(2, 2)
	check(s == Vector2(0.0, 64.0),
		"cell_to_screen(2,2) should be (0,64), got %s" % str(s))


func test_screen_to_cell_roundtrip() -> void:
	for col in range(6):
		for row in range(6):
			var s := IsometricGrid.cell_to_screen(col, row)
			var back := IsometricGrid.screen_to_cell(s)
			check(back == Vector2i(col, row),
				"roundtrip failed: col=%d row=%d → screen=%s → cell=%s" % [col, row, str(s), str(back)])


func test_get_neighbors_count() -> void:
	var n := IsometricGrid.get_neighbors(Vector2i(5, 5))
	check(n.size() == 8, "get_neighbors should return 8 neighbors, got %d" % n.size())


func test_get_neighbors_directions() -> void:
	var pos := Vector2i(5, 5)
	var n := IsometricGrid.get_neighbors(pos)
	check(Vector2i(5, 4) in n, "N neighbor (5,4) should be present")
	check(Vector2i(6, 4) in n, "NE neighbor (6,4) should be present")
	check(Vector2i(6, 5) in n, "E neighbor (6,5) should be present")
	check(Vector2i(6, 6) in n, "SE neighbor (6,6) should be present")
	check(Vector2i(5, 6) in n, "S neighbor (5,6) should be present")
	check(Vector2i(4, 6) in n, "SW neighbor (4,6) should be present")
	check(Vector2i(4, 5) in n, "W neighbor (4,5) should be present")
	check(Vector2i(4, 4) in n, "NW neighbor (4,4) should be present")


func test_is_adjacent_true() -> void:
	check(IsometricGrid.is_adjacent(Vector2i(3, 3), Vector2i(4, 3)),
		"(3,3) and (4,3) should be adjacent")
	check(IsometricGrid.is_adjacent(Vector2i(3, 3), Vector2i(3, 4)),
		"(3,3) and (3,4) should be adjacent")
	check(IsometricGrid.is_adjacent(Vector2i(3, 3), Vector2i(2, 3)),
		"(3,3) and (2,3) should be adjacent")
	check(IsometricGrid.is_adjacent(Vector2i(3, 3), Vector2i(3, 2)),
		"(3,3) and (3,2) should be adjacent")


func test_is_adjacent_diagonal_true() -> void:
	check(IsometricGrid.is_adjacent(Vector2i(3, 3), Vector2i(4, 4)),
		"(3,3) and (4,4) are diagonal — should be adjacent (8-directional)")
	check(IsometricGrid.is_adjacent(Vector2i(3, 3), Vector2i(2, 2)),
		"(3,3) and (2,2) NW diagonal — should be adjacent")
	check(IsometricGrid.is_adjacent(Vector2i(3, 3), Vector2i(4, 2)),
		"(3,3) and (4,2) NE diagonal — should be adjacent")
	check(IsometricGrid.is_adjacent(Vector2i(3, 3), Vector2i(2, 4)),
		"(3,3) and (2,4) SW diagonal — should be adjacent")


func test_is_adjacent_false_far() -> void:
	check(not IsometricGrid.is_adjacent(Vector2i(0, 0), Vector2i(5, 5)),
		"(0,0) and (5,5) are far — should NOT be adjacent")


func test_manhattan_distance_zero() -> void:
	check(IsometricGrid.manhattan_distance(Vector2i(3, 3), Vector2i(3, 3)) == 0,
		"manhattan distance from a point to itself should be 0")


func test_manhattan_distance_adjacent() -> void:
	check(IsometricGrid.manhattan_distance(Vector2i(0, 0), Vector2i(1, 0)) == 1,
		"adjacent cells should have distance 1")
	check(IsometricGrid.manhattan_distance(Vector2i(0, 0), Vector2i(0, 1)) == 1,
		"adjacent cells should have distance 1")


func test_manhattan_distance_far() -> void:
	check(IsometricGrid.manhattan_distance(Vector2i(0, 0), Vector2i(3, 4)) == 7,
		"manhattan_distance((0,0),(3,4)) should be 7")


func test_chebyshev_distance() -> void:
	check(IsometricGrid.chebyshev_distance(Vector2i(0, 0), Vector2i(0, 0)) == 0,
		"chebyshev distance to self should be 0")
	check(IsometricGrid.chebyshev_distance(Vector2i(0, 0), Vector2i(1, 0)) == 1,
		"chebyshev distance orthogonal step should be 1")
	check(IsometricGrid.chebyshev_distance(Vector2i(0, 0), Vector2i(1, 1)) == 1,
		"chebyshev distance diagonal step should be 1")
	check(IsometricGrid.chebyshev_distance(Vector2i(0, 0), Vector2i(2, 1)) == 2,
		"chebyshev_distance((0,0),(2,1)) should be 2")
	check(IsometricGrid.chebyshev_distance(Vector2i(0, 0), Vector2i(3, 5)) == 5,
		"chebyshev_distance((0,0),(3,5)) should be 5")


func test_cells_in_radius_zero() -> void:
	var cells := IsometricGrid.get_cells_in_radius(Vector2i(5, 5), 0)
	check(cells.size() == 1, "radius 0 should return 1 cell (the center), got %d" % cells.size())
	check(cells[0] == Vector2i(5, 5), "radius 0 should return only the center cell")


func test_cells_in_radius_one() -> void:
	var cells := IsometricGrid.get_cells_in_radius(Vector2i(5, 5), 1)
	# Center + 4 orthogonal = 5 cells (Manhattan radius 1)
	check(cells.size() == 5, "radius 1 should return 5 cells, got %d" % cells.size())
	check(Vector2i(5, 5) in cells, "center should be included in radius 1")
	check(Vector2i(5, 4) in cells, "north neighbor should be in radius 1")
	check(Vector2i(6, 5) in cells, "east neighbor should be in radius 1")
	check(Vector2i(5, 6) in cells, "south neighbor should be in radius 1")
	check(Vector2i(4, 5) in cells, "west neighbor should be in radius 1")


func test_cells_in_radius_two() -> void:
	var cells := IsometricGrid.get_cells_in_radius(Vector2i(5, 5), 2)
	# Manhattan ball of radius 2: 1+4+8 = 13 cells
	check(cells.size() == 13, "radius 2 should return 13 cells, got %d" % cells.size())
