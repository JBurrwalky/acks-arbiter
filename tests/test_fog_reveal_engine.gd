extends "res://tests/test_suite_base.gd"

## B5 — Light-source-based fog reveal. Verifies the LOS+radius compute step
## that replaced the room-scoped reveal in DungeonMapController.


func run_all_tests() -> void:
	test_lit_cells_within_radius_no_walls()
	test_lit_cells_blocked_by_wall()
	test_lit_cells_multiple_sources_union()
	test_no_light_source_only_party_cell_visible()
	test_off_map_member_skipped()
	test_radius_zero_falls_back_to_self_cell()
	if not has_failures():
		print("FogRevealEngine: all tests passed.")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _make_open_room(width: int, height: int) -> VoxelMapData:
	var map := VoxelMapData.new()
	for c in range(width):
		for r in range(height):
			var cell := VoxelCell.new()
			cell.solidity = "air"
			cell.feature = "open"
			cell.floor_type = "stone"
			map.set_cell(Vector3i(c, r, 0), cell)
	return map


func _place_solid(map: VoxelMapData, pos: Vector3i) -> void:
	var cell := VoxelCell.new()
	cell.solidity = "solid"
	cell.feature = "rock"
	map.set_cell(pos, cell)


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_lit_cells_within_radius_no_walls() -> void:
	var map := _make_open_room(7, 7)
	var lit := FogRevealEngine.compute_visible_cells(map, {
		"A": {"pos": Vector3i(3, 3, 0), "radius": 2},
	})
	# Chebyshev radius 2 from (3,3,0) → 5×5 box = 25 cells, all open.
	check(lit.size() == 25,
		"radius-2 in open room should light 25 cells, got %d" % lit.size())
	check(lit.has(Vector3i(3, 3, 0)), "self cell should always be lit")
	check(lit.has(Vector3i(5, 5, 0)), "corner cell within radius should be lit")
	check(not lit.has(Vector3i(6, 6, 0)), "cell outside Chebyshev radius should not be lit")


func test_lit_cells_blocked_by_wall() -> void:
	# 5×1 corridor with a solid wall at (2,0,0). Light from (0,0,0) radius 4.
	# Cells 0,1 lit; cell 2 is solid (target itself blocks LOS toward it via
	# `blocks_los`), cells 3,4 are NOT lit because LOS rays pass through (2,0,0).
	var map := _make_open_room(5, 1)
	_place_solid(map, Vector3i(2, 0, 0))
	var lit := FogRevealEngine.compute_visible_cells(map, {
		"A": {"pos": Vector3i(0, 0, 0), "radius": 4},
	})
	check(lit.has(Vector3i(0, 0, 0)), "self cell always lit")
	check(lit.has(Vector3i(1, 0, 0)), "cell adjacent to source should be lit")
	check(not lit.has(Vector3i(3, 0, 0)),
		"cell behind wall should NOT be lit (LOS blocked)")
	check(not lit.has(Vector3i(4, 0, 0)),
		"cell further behind wall should NOT be lit")


func test_lit_cells_multiple_sources_union() -> void:
	# Two sources at opposite ends of a 7-wide corridor; their lit sets should
	# union, not double-count.
	var map := _make_open_room(7, 1)
	var lit := FogRevealEngine.compute_visible_cells(map, {
		"A": {"pos": Vector3i(0, 0, 0), "radius": 2},
		"B": {"pos": Vector3i(6, 0, 0), "radius": 2},
	})
	# A lights cells 0..2, B lights cells 4..6 — the middle cell (3) is
	# outside both radii and remains unlit.
	check(lit.has(Vector3i(0, 0, 0)) and lit.has(Vector3i(2, 0, 0)),
		"A's radius should light cells 0..2")
	check(lit.has(Vector3i(4, 0, 0)) and lit.has(Vector3i(6, 0, 0)),
		"B's radius should light cells 4..6")
	check(not lit.has(Vector3i(3, 0, 0)),
		"the gap between two radii must remain dark")


func test_no_light_source_only_party_cell_visible() -> void:
	# Per the v1 pitch-darkness simplification: even with no light, the
	# member's own cell is shown so the player can see their portrait.
	var map := _make_open_room(5, 5)
	var lit := FogRevealEngine.compute_visible_cells(map, {
		"A": {"pos": Vector3i(2, 2, 0), "radius": 0},
	})
	check(lit.size() == 1,
		"radius-0 should light exactly the self cell, got %d" % lit.size())
	check(lit.has(Vector3i(2, 2, 0)),
		"self cell must be lit even when radius is zero")


func test_off_map_member_skipped() -> void:
	# A member with sentinel position (-1,-1,-1) is off the map and contributes
	# nothing.
	var map := _make_open_room(3, 3)
	var lit := FogRevealEngine.compute_visible_cells(map, {
		"A": {"pos": Vector3i(-1, -1, -1), "radius": 5},
	})
	check(lit.is_empty(),
		"off-map member should contribute zero lit cells, got %d" % lit.size())


func test_radius_zero_falls_back_to_self_cell() -> void:
	# Edge case: radius is exactly zero (no torch, no darkvision) — only
	# the self cell is lit, no neighbors.
	var map := _make_open_room(3, 3)
	var lit := FogRevealEngine.compute_visible_cells(map, {
		"A": {"pos": Vector3i(1, 1, 0), "radius": 0},
	})
	check(lit.size() == 1, "radius 0 should expose only the self cell")
	check(not lit.has(Vector3i(0, 0, 0)),
		"radius 0 must not leak into neighbors")
