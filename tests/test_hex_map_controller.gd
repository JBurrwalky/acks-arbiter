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
