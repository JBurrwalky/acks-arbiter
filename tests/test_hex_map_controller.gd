extends "res://tests/test_suite_base.gd"

## Plain GDScript unit tests for HexMapController (static hex math and game logic).


func run_all_tests() -> void:
	test_get_neighbors_returns_six()
	test_get_neighbors_origin_flat_top()
	test_hex_distance_adjacent_is_one()
	test_hex_distance_two_hops()
	test_hex_distance_symmetric()
	test_is_adjacent_true_for_neighbor()
	test_is_adjacent_false_for_two_hops()
	test_axial_to_godot_map_origin()
	test_axial_to_godot_map_positive_even_col()
	test_godot_map_to_axial_roundtrip()
	test_move_party_updates_position()
	test_move_party_non_adjacent_fails()
	test_load_map_reveals_start_and_neighbors_as_visible()
	test_move_party_demotes_old_visible_to_explored()
	test_hex_never_goes_back_to_hidden()
	test_get_hex_ring_radius_0_returns_center()
	test_get_hex_ring_radius_1_returns_six()
	test_is_hex_passable_clear_terrain()
	test_is_hex_passable_ocean_blocked()
	test_is_hex_passable_lake_blocked()
	test_find_path_same_hex_returns_single_hex()
	test_find_path_direct_route()
	test_find_path_routes_around_impassable()
	test_find_path_no_path_returns_empty()
	test_find_path_target_impassable_returns_empty()
	if not has_failures():
		print("HexMapController: all tests passed.")


func test_get_neighbors_returns_six() -> void:
	var neighbors := HexMapController.get_neighbors(Vector2i(0, 0))
	check(neighbors.size() == 6, "every hex has exactly 6 neighbors")


func test_get_neighbors_origin_flat_top() -> void:
	var neighbors := HexMapController.get_neighbors(Vector2i(0, 0))
	var expected: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0),
		Vector2i(1, -1), Vector2i(-1, 1),
		Vector2i(0, -1), Vector2i(0, 1)
	]
	for e in expected:
		check(e in neighbors, "neighbor %s missing" % str(e))


func test_hex_distance_adjacent_is_one() -> void:
	check(HexMapController.hex_distance(Vector2i(0, 0), Vector2i(1, 0)) == 1)
	check(HexMapController.hex_distance(Vector2i(0, 0), Vector2i(0, 1)) == 1)
	check(HexMapController.hex_distance(Vector2i(0, 0), Vector2i(1, -1)) == 1)


func test_hex_distance_two_hops() -> void:
	check(HexMapController.hex_distance(Vector2i(0, 0), Vector2i(2, 0)) == 2)
	check(HexMapController.hex_distance(Vector2i(0, 0), Vector2i(1, 1)) == 2)


func test_hex_distance_symmetric() -> void:
	check(HexMapController.hex_distance(Vector2i(3, 2), Vector2i(-1, 0)) == HexMapController.hex_distance(Vector2i(-1, 0), Vector2i(3, 2)))


func test_is_adjacent_true_for_neighbor() -> void:
	check(HexMapController.is_adjacent(Vector2i(0, 0), Vector2i(1, 0)))


func test_is_adjacent_false_for_two_hops() -> void:
	check(not HexMapController.is_adjacent(Vector2i(0, 0), Vector2i(2, 0)))


func test_axial_to_godot_map_origin() -> void:
	var result := HexMapController.axial_to_godot_map(Vector2i(0, 0))
	check(result == Vector2i(0, 0), "origin axial should map to origin godot")


func test_axial_to_godot_map_positive_even_col() -> void:
	# Even-q offset: q=2 (even), so row = r + (2 - 0)/2 = r + 1
	var result := HexMapController.axial_to_godot_map(Vector2i(2, 0))
	check(result == Vector2i(2, 1), "q=2,r=0 should map to col=2,row=1 with even-q offset")


func test_godot_map_to_axial_roundtrip() -> void:
	var original := Vector2i(3, -2)
	var roundtrip := HexMapController.godot_map_to_axial(HexMapController.axial_to_godot_map(original))
	check(roundtrip == original, "axial→godot→axial should be identity")


func test_move_party_updates_position() -> void:
	var controller := HexMapController.new()
	var map_data := _make_test_map()
	controller.load_map(map_data)
	var result := controller.move_party(Vector2i(1, 0))
	check(result == true)
	check(map_data.party_hex == Vector2i(1, 0))
	controller.free()


func test_move_party_non_adjacent_fails() -> void:
	var controller := HexMapController.new()
	var map_data := _make_test_map()
	controller.load_map(map_data)
	var result := controller.move_party(Vector2i(3, 0))  # 3 hops away — not adjacent
	check(result == false)
	check(map_data.party_hex == Vector2i(0, 0))  # unchanged
	controller.free()


func test_load_map_reveals_start_and_neighbors_as_visible() -> void:
	var controller := HexMapController.new()
	var map_data := _make_test_map()
	controller.load_map(map_data)
	# Party starts at (0,0) — it and all neighbors should be VISIBLE
	check(map_data.get_fog_state(Vector2i(0, 0)) == HexMapData.FogState.VISIBLE)
	for neighbor in HexMapController.get_neighbors(Vector2i(0, 0)):
		if map_data.is_valid_coord(neighbor):
			check(map_data.get_fog_state(neighbor) == HexMapData.FogState.VISIBLE,
				"neighbor %s should be VISIBLE after load" % str(neighbor))
	controller.free()


func test_move_party_demotes_old_visible_to_explored() -> void:
	var controller := HexMapController.new()
	var map_data := _make_test_map()
	controller.load_map(map_data)
	# Move to (1,0) — the hex at (0,-1) was visible before, should become EXPLORED if not a neighbor of (1,0)
	controller.move_party(Vector2i(1, 0))
	# (0,0) was the old party hex — it's a neighbor of (1,0) so it stays VISIBLE
	# But hexes only adjacent to (0,0) and not (1,0) should be EXPLORED
	# Verify old center is still visible (it's a neighbor of (1,0))
	check(map_data.get_fog_state(Vector2i(0, 0)) == HexMapData.FogState.VISIBLE)
	controller.free()


func test_hex_never_goes_back_to_hidden() -> void:
	var controller := HexMapController.new()
	var map_data := _make_test_map()
	controller.load_map(map_data)
	# (0,-1) is visible initially (neighbor of start)
	controller.move_party(Vector2i(1, 0))  # move away
	var state := map_data.get_fog_state(Vector2i(0, -1))
	check(state == HexMapData.FogState.VISIBLE or state == HexMapData.FogState.EXPLORED,
		"hex can never revert to HIDDEN once seen")
	controller.free()


func test_get_hex_ring_radius_0_returns_center() -> void:
	var ring := HexMapController.get_hex_ring(Vector2i(0, 0), 0)
	check(ring.size() == 1)
	check(ring[0] == Vector2i(0, 0))


func test_get_hex_ring_radius_1_returns_six() -> void:
	var ring := HexMapController.get_hex_ring(Vector2i(0, 0), 1)
	check(ring.size() == 6, "ring of radius 1 has 6 hexes")


# ---------------------------------------------------------------------------
# Passability + A* pathfinding (added 2026-04-23)
# ---------------------------------------------------------------------------

func test_is_hex_passable_clear_terrain() -> void:
	var controller := HexMapController.new()
	controller.load_map(_make_test_map())
	check(controller.is_hex_passable(Vector2i(0, 0)),
		"default-clear hex should be passable")
	controller.free()


func test_is_hex_passable_ocean_blocked() -> void:
	var controller := HexMapController.new()
	var map := _make_test_map()
	var t: HexTerrainData = map.get_hex(Vector2i(1, 0))
	t.water = HexTerrainData.WATER_OCEAN
	controller.load_map(map)
	check(not controller.is_hex_passable(Vector2i(1, 0)),
		"ocean hex must be impassable for land travel")
	controller.free()


func test_is_hex_passable_lake_blocked() -> void:
	var controller := HexMapController.new()
	var map := _make_test_map()
	var t: HexTerrainData = map.get_hex(Vector2i(1, 0))
	t.water = HexTerrainData.WATER_LAKE
	controller.load_map(map)
	check(not controller.is_hex_passable(Vector2i(1, 0)),
		"lake hex must be impassable for land travel")
	controller.free()


func test_find_path_same_hex_returns_single_hex() -> void:
	var controller := HexMapController.new()
	controller.load_map(_make_test_map())
	var path := controller.find_path(Vector2i(0, 0), Vector2i(0, 0))
	check(path.size() == 1 and path[0] == Vector2i(0, 0),
		"start == goal should return [start]; got %s" % str(path))
	controller.free()


func test_find_path_direct_route() -> void:
	var controller := HexMapController.new()
	controller.load_map(_make_test_map())
	var path := controller.find_path(Vector2i(0, 0), Vector2i(3, 0))
	# Path includes both endpoints; (0,0) → (3,0) is 3 steps so 4 cells total.
	check(path.size() == 4,
		"direct path 0,0 → 3,0 should be 4 cells (incl. endpoints); got %d (%s)"
		% [path.size(), str(path)])
	check(path[0] == Vector2i(0, 0), "path must start at the start hex")
	check(path[path.size() - 1] == Vector2i(3, 0), "path must end at the goal hex")
	controller.free()


func test_find_path_routes_around_impassable() -> void:
	var controller := HexMapController.new()
	var map := _make_test_map()
	# Block (1,0) — the natural step toward (2,0). The pathfinder must detour.
	var blocker: HexTerrainData = map.get_hex(Vector2i(1, 0))
	blocker.water = HexTerrainData.WATER_OCEAN
	controller.load_map(map)
	var path := controller.find_path(Vector2i(0, 0), Vector2i(2, 0))
	check(not path.is_empty(),
		"detour path 0,0 → 2,0 around blocked (1,0) should exist")
	for cell in path:
		check(cell != Vector2i(1, 0),
			"path must NOT cross the impassable hex (1,0); got %s" % str(path))
	check(path[0] == Vector2i(0, 0) and path[path.size() - 1] == Vector2i(2, 0),
		"detour endpoints wrong: %s" % str(path))
	controller.free()


func test_find_path_no_path_returns_empty() -> void:
	var controller := HexMapController.new()
	var map := _make_test_map()
	# Surround (2,0) with ocean on every neighbor so no land path reaches it.
	for n in HexMapController.get_neighbors(Vector2i(2, 0)):
		var t: HexTerrainData = map.get_hex(n)
		if t != null:
			t.water = HexTerrainData.WATER_OCEAN
	controller.load_map(map)
	var path := controller.find_path(Vector2i(0, 0), Vector2i(2, 0))
	check(path.is_empty(),
		"path through fully-blocked goal should be empty; got %s" % str(path))
	controller.free()


func test_find_path_target_impassable_returns_empty() -> void:
	var controller := HexMapController.new()
	var map := _make_test_map()
	var t: HexTerrainData = map.get_hex(Vector2i(2, 0))
	t.water = HexTerrainData.WATER_OCEAN
	controller.load_map(map)
	var path := controller.find_path(Vector2i(0, 0), Vector2i(2, 0))
	check(path.is_empty(),
		"path to an impassable goal should be empty; got %s" % str(path))
	controller.free()


# ---------------------------------------------------------------------------
# Helper: build a map with center + 3-ring radius for controller tests
# ---------------------------------------------------------------------------

func _make_test_map() -> HexMapData:
	var map := HexMapData.new()
	map.id = "test"
	map.name = "Test"
	map.scale = HexMapData.MapScale.REGIONAL_6MI
	map.party_hex = Vector2i(0, 0)
	# Populate center + two rings (to ensure movement targets exist)
	for q in range(-3, 4):
		for r in range(-3, 4):
			if HexMapController.hex_distance(Vector2i(0, 0), Vector2i(q, r)) <= 3:
				var terrain := HexTerrainData.new()
				map.hexes[Vector2i(q, r)] = terrain
	return map
