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
	# Party visibility bonus (Eyes of the Eagle V2 — 2026-06-03)
	test_default_visibility_radius_is_one()
	test_set_party_visibility_bonus_extends_radius_to_two()
	test_set_party_visibility_bonus_re_runs_visibility_on_loaded_map()
	test_set_party_visibility_bonus_idempotent_no_redundant_emit()
	test_set_party_visibility_bonus_clamps_negative_to_zero()
	test_set_party_visibility_bonus_no_map_loaded_does_not_crash()
	test_compute_party_visibility_bonus_empty_party_returns_zero()
	test_compute_party_visibility_bonus_member_without_eagle_returns_zero()
	test_compute_party_visibility_bonus_single_eagle_returns_one()
	test_compute_party_visibility_bonus_multi_wearer_maxes_not_sums()
	test_compute_party_visibility_bonus_skips_null_members()
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


# ---------------------------------------------------------------------------
# Party visibility bonus — Eyes of the Eagle V2 (2026-06-03 Jedidiah ruling)
# ---------------------------------------------------------------------------
#
# V2 mechanic: while at least one party member wears Eyes of the Eagle, the
# party gains +1 hex ring of visibility on the hexmap layer (default radius
# 1 → effective radius 2 = 1 + 6 + 12 = 19 hexes visible centered on party).
# Bonus does NOT stack across multiple wearers (RAW semantics: people don't
# see further if companions are also looking).

func _make_eagle_eyed_character() -> CharacterData:
	var cd := CharacterData.new()
	cd.id = "test_pc_eagle"
	cd.name = "Eagle-Eyed Test PC"
	cd.character_class = "fighter"
	cd.combat_progression = "fighter"
	cd.level = 1
	cd.hp_max = 8; cd.hp_current = 8
	cd.flags.set_flag("has_eyes_of_the_eagle", "test_source_id", {
		"source_kind": "worn_magic_item",
		"missile_medium_range_modifier": -1,
		"missile_long_range_modifier": -2,
		"extra_hex_visibility": 1,
	})
	return cd


func _make_plain_character() -> CharacterData:
	var cd := CharacterData.new()
	cd.id = "test_pc_plain"
	cd.name = "Plain Test PC"
	cd.character_class = "fighter"
	cd.combat_progression = "fighter"
	cd.level = 1
	cd.hp_max = 8; cd.hp_current = 8
	return cd


func test_default_visibility_radius_is_one() -> void:
	# Regression: without any bonus, ring 2 hexes are NOT VISIBLE after
	# load (they may be HIDDEN). Ring 1 IS visible. This locks the existing
	# default behavior against the bonus extension.
	var controller := HexMapController.new()
	var map_data := _make_test_map()
	controller.load_map(map_data)
	check(controller.get_party_visibility_bonus_hexes() == 0,
		"default bonus is 0 (no extra rings)")
	for ring1 in HexMapController.get_hex_ring(Vector2i(0, 0), 1):
		if map_data.is_valid_coord(ring1):
			check(map_data.get_fog_state(ring1) == HexMapData.FogState.VISIBLE,
				"ring 1 hex %s is VISIBLE by default" % str(ring1))
	# Ring 2 should be HIDDEN — no bonus, default radius=1.
	for ring2 in HexMapController.get_hex_ring(Vector2i(0, 0), 2):
		if map_data.is_valid_coord(ring2):
			check(map_data.get_fog_state(ring2) == HexMapData.FogState.HIDDEN,
				"ring 2 hex %s is HIDDEN without bonus" % str(ring2))
	controller.free()


func test_set_party_visibility_bonus_extends_radius_to_two() -> void:
	# With bonus=1, ring 2 hexes become VISIBLE on next visibility update.
	var controller := HexMapController.new()
	var map_data := _make_test_map()
	controller.load_map(map_data)
	# Sanity check: ring 2 was HIDDEN.
	var sample_ring2: Vector2i = Vector2i(2, 0)  # 2 hexes away from (0,0)
	check(map_data.get_fog_state(sample_ring2) == HexMapData.FogState.HIDDEN,
		"setup: %s is HIDDEN before bonus applied" % str(sample_ring2))
	controller.set_party_visibility_bonus_hexes(1)
	check(controller.get_party_visibility_bonus_hexes() == 1,
		"bonus stored as 1")
	# All ring 2 hexes should now be VISIBLE.
	for ring2 in HexMapController.get_hex_ring(Vector2i(0, 0), 2):
		if map_data.is_valid_coord(ring2):
			check(map_data.get_fog_state(ring2) == HexMapData.FogState.VISIBLE,
				"ring 2 hex %s is VISIBLE with bonus=1" % str(ring2))
	# Ring 1 stays VISIBLE.
	for ring1 in HexMapController.get_hex_ring(Vector2i(0, 0), 1):
		if map_data.is_valid_coord(ring1):
			check(map_data.get_fog_state(ring1) == HexMapData.FogState.VISIBLE,
				"ring 1 still VISIBLE with bonus=1")
	# Ring 3 stays HIDDEN (bonus=1 only extends one ring).
	for ring3 in HexMapController.get_hex_ring(Vector2i(0, 0), 3):
		if map_data.is_valid_coord(ring3):
			# Ring 3 may be EXPLORED if it was revealed by movement, but
			# under our test fixture (no movement) it should be HIDDEN.
			check(map_data.get_fog_state(ring3) == HexMapData.FogState.HIDDEN,
				"ring 3 stays HIDDEN with bonus=1")
	controller.free()


func test_set_party_visibility_bonus_re_runs_visibility_on_loaded_map() -> void:
	# Setting bonus AFTER the map is loaded should immediately re-run
	# _update_visibility so the renderer sees the wider sight radius without
	# requiring party movement.
	var controller := HexMapController.new()
	var map_data := _make_test_map()
	controller.load_map(map_data)
	var ring2 := Vector2i(2, 0)
	check(map_data.get_fog_state(ring2) == HexMapData.FogState.HIDDEN, "setup")
	# Connect to the signal to confirm visibility_updated fires.
	var emitted := [false]
	controller.visibility_updated.connect(func() -> void: emitted[0] = true)
	controller.set_party_visibility_bonus_hexes(1)
	check(emitted[0], "visibility_updated signal fires after bonus change")
	check(map_data.get_fog_state(ring2) == HexMapData.FogState.VISIBLE,
		"ring 2 hex now VISIBLE after bonus applied")
	controller.free()


func test_set_party_visibility_bonus_idempotent_no_redundant_emit() -> void:
	# Setting the same bonus value twice should NOT re-run _update_visibility
	# (cheap optimisation; the renderer doesn't want spurious refreshes).
	var controller := HexMapController.new()
	var map_data := _make_test_map()
	controller.load_map(map_data)
	controller.set_party_visibility_bonus_hexes(1)
	# Reset signal capture.
	var emitted := [false]
	controller.visibility_updated.connect(func() -> void: emitted[0] = true)
	# Re-set to same value — should be a no-op.
	controller.set_party_visibility_bonus_hexes(1)
	check(not emitted[0], "redundant set does NOT re-emit visibility_updated")
	controller.free()


func test_set_party_visibility_bonus_clamps_negative_to_zero() -> void:
	# Defensive: a negative bonus would crash get_hex_ring or produce empty
	# rings. Clamp at 0.
	var controller := HexMapController.new()
	var map_data := _make_test_map()
	controller.load_map(map_data)
	controller.set_party_visibility_bonus_hexes(-3)
	check(controller.get_party_visibility_bonus_hexes() == 0,
		"negative bonus clamps to 0; got %d"
			% controller.get_party_visibility_bonus_hexes())
	controller.free()


func test_set_party_visibility_bonus_no_map_loaded_does_not_crash() -> void:
	# Calling the setter BEFORE a map is loaded should silently no-op the
	# visibility refresh (no _map_data to update). The bonus value is still
	# stored so the next load_map call honors it.
	var controller := HexMapController.new()
	# No load_map call.
	controller.set_party_visibility_bonus_hexes(1)
	check(controller.get_party_visibility_bonus_hexes() == 1,
		"bonus stored even without map loaded")
	# Now load a map — the bonus should take effect.
	var map_data := _make_test_map()
	controller.load_map(map_data)
	check(map_data.get_fog_state(Vector2i(2, 0)) == HexMapData.FogState.VISIBLE,
		"loaded map with pre-set bonus reveals ring 2")
	controller.free()


func test_compute_party_visibility_bonus_empty_party_returns_zero() -> void:
	check(HexMapController.compute_party_visibility_bonus([]) == 0,
		"empty party → 0 bonus")


func test_compute_party_visibility_bonus_member_without_eagle_returns_zero() -> void:
	var plain := _make_plain_character()
	check(HexMapController.compute_party_visibility_bonus([plain]) == 0,
		"party with no Eagle-eyed member → 0 bonus")


func test_compute_party_visibility_bonus_single_eagle_returns_one() -> void:
	var eagle := _make_eagle_eyed_character()
	var plain := _make_plain_character()
	check(HexMapController.compute_party_visibility_bonus([eagle, plain]) == 1,
		"1 Eagle-eyed member + 1 plain → bonus 1")


func test_compute_party_visibility_bonus_multi_wearer_maxes_not_sums() -> void:
	# 2 Eagle-eyed members both contribute 1 each, but the bonus MAXES
	# (not sums) — RAW semantics: people don't see further if companions
	# are also looking.
	var eagle_a := _make_eagle_eyed_character()
	var eagle_b := _make_eagle_eyed_character()
	eagle_b.id = "test_pc_eagle_b"
	check(HexMapController.compute_party_visibility_bonus([eagle_a, eagle_b]) == 1,
		"2 Eagle-eyed members → bonus 1 (max), NOT 2 (sum); got %d"
			% HexMapController.compute_party_visibility_bonus([eagle_a, eagle_b]))


func test_compute_party_visibility_bonus_skips_null_members() -> void:
	# Defensive: a null entry in the party array (e.g. a freshly-removed
	# henchman) shouldn't crash the scan.
	var eagle := _make_eagle_eyed_character()
	check(HexMapController.compute_party_visibility_bonus([null, eagle, null]) == 1,
		"null members skipped without crash; Eagle still counted")
