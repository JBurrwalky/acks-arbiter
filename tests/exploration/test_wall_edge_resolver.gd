extends "res://tests/test_suite_base.gd"

## Unit tests for WallEdgeResolver (edge-resolved wall placement, Strategy A).
##
## Verifies that the resolver emits one record per floored-air-cell edge whose
## same-level neighbor is solid — and nothing for interior solids, floorless
## airspace, absent neighbors, or cross-level solids.


func run_all_tests() -> void:
	test_empty_map_no_edges()
	test_single_solid_neighbor_north()
	test_corridor_edge_count()
	test_interior_solid_emits_nothing()
	test_floorless_air_emits_nothing()
	test_absent_neighbor_no_wall()
	test_cross_level_solid_ignored()
	test_records_are_deterministic_order()
	if not has_failures():
		print("WallEdgeResolver: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _air(map: VoxelMapData, c: int, r: int, l: int, floor_type: String = "stone") -> void:
	var cell := VoxelCell.new()
	cell.solidity = "air"
	cell.feature = "open"
	cell.floor_type = floor_type
	map.set_cell(Vector3i(c, r, l), cell)


func _solid(map: VoxelMapData, c: int, r: int, l: int) -> void:
	var cell := VoxelCell.new()
	cell.solidity = "solid"
	cell.feature = "wall_stone"
	cell.floor_type = "none"
	map.set_cell(Vector3i(c, r, l), cell)


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_empty_map_no_edges() -> void:
	var map := VoxelMapData.new()
	var edges := WallEdgeResolver.resolve_level(map, 0)
	check(edges.is_empty(), "empty map should yield no wall edges, got %d" % edges.size())


func test_single_solid_neighbor_north() -> void:
	var map := VoxelMapData.new()
	_air(map, 5, 5, 0)
	_solid(map, 5, 4, 0)  # N neighbor (offset 0,-1)
	var edges := WallEdgeResolver.resolve_level(map, 0)
	check(edges.size() == 1, "one solid neighbor -> one edge, got %d" % edges.size())
	if edges.size() == 1:
		var e: Dictionary = edges[0]
		check(e["air_cell"] == Vector3i(5, 5, 0), "air_cell should be (5,5,0), got %s" % str(e["air_cell"]))
		check(e["edge_dir"] == WallEdgeResolver.EdgeDir.N, "edge_dir should be N, got %d" % e["edge_dir"])
		check(e["neighbor_solid"] == Vector3i(5, 4, 0), "neighbor should be (5,4,0), got %s" % str(e["neighbor_solid"]))


func test_corridor_edge_count() -> void:
	# 3x1 floored corridor flanked N and S, capped W of the first and E of the last.
	var map := VoxelMapData.new()
	for c in [1, 2, 3]:
		_air(map, c, 1, 0)
		_solid(map, c, 0, 0)  # N row
		_solid(map, c, 2, 0)  # S row
	_solid(map, 0, 1, 0)  # W of first
	_solid(map, 4, 1, 0)  # E of last
	var edges := WallEdgeResolver.resolve_level(map, 0)
	# (1,1): N,S,W = 3 ; (2,1): N,S = 2 ; (3,1): N,S,E = 3  -> 8
	check(edges.size() == 8, "corridor should yield 8 wall edges, got %d" % edges.size())


func test_interior_solid_emits_nothing() -> void:
	# A solid fully surrounded by solids: no floored-air cell borders it -> nothing.
	var map := VoxelMapData.new()
	for c in range(3):
		for r in range(3):
			_solid(map, c, r, 0)
	var edges := WallEdgeResolver.resolve_level(map, 0)
	check(edges.is_empty(), "all-solid block should yield no edges, got %d" % edges.size())


func test_floorless_air_emits_nothing() -> void:
	# Air with floor_type "none" is empty airspace, not a rendered cell.
	var map := VoxelMapData.new()
	_air(map, 5, 5, 0, "none")
	_solid(map, 5, 4, 0)
	var edges := WallEdgeResolver.resolve_level(map, 0)
	check(edges.is_empty(), "floorless air should not border walls, got %d" % edges.size())


func test_absent_neighbor_no_wall() -> void:
	# A floored air cell with no stored neighbors -> open on all sides, no walls.
	var map := VoxelMapData.new()
	_air(map, 5, 5, 0)
	var edges := WallEdgeResolver.resolve_level(map, 0)
	check(edges.is_empty(), "isolated floored air cell should yield no edges, got %d" % edges.size())


func test_cross_level_solid_ignored() -> void:
	# A solid directly above (level 1) must not produce a wall on level 0.
	var map := VoxelMapData.new()
	_air(map, 5, 5, 0)
	_solid(map, 5, 4, 1)  # N neighbor but on level 1
	var edges := WallEdgeResolver.resolve_level(map, 0)
	check(edges.is_empty(), "cross-level solid should be ignored, got %d" % edges.size())


func test_records_are_deterministic_order() -> void:
	# Same map resolved twice yields identical record sequences.
	var map := VoxelMapData.new()
	_air(map, 1, 1, 0)
	_solid(map, 1, 0, 0)
	_solid(map, 0, 1, 0)
	var a := WallEdgeResolver.resolve_level(map, 0)
	var b := WallEdgeResolver.resolve_level(map, 0)
	check(a.size() == b.size() and a.size() == 2, "expected 2 edges twice, got %d/%d" % [a.size(), b.size()])
	if a.size() == b.size():
		var same := true
		for i in range(a.size()):
			if a[i]["edge_dir"] != b[i]["edge_dir"] or a[i]["air_cell"] != b[i]["air_cell"]:
				same = false
		check(same, "edge records should be order-stable across calls")
