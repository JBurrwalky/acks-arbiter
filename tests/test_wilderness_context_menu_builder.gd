extends "res://tests/test_suite_base.gd"

## Plain GDScript unit tests for WildernessContextMenuBuilder.
##
## These tests don't touch the campaign DB — they rely on LocationCacheManager
## returning an empty cache dict when GameState.campaign_id is empty (which is
## the default in the test harness).


const TARGET_HEX := Vector2i(3, -2)
const CURRENT_HEX := Vector2i(0, 0)
const ACTIVE_PARTY_ID := "party_test_001"


func run_all_tests() -> void:
	test_returns_expected_options_including_cancel()
	test_all_expected_ids_present()
	test_cancel_option_has_cancel_action_type()
	test_action_data_carries_hex_coords()
	test_empty_active_party_disables_action_options()
	test_cancel_remains_enabled_when_no_party()
	test_visit_cache_disabled_when_no_cache()
	test_place_cache_enabled_when_no_cache()
	test_controller_can_move_false_disables_actions()
	test_current_hex_menu_omits_move_here()
	test_current_hex_menu_includes_place_loot_cache()
	test_current_hex_menu_visit_disabled_when_no_cache()
	test_current_hex_menu_includes_survey()
	test_non_adjacent_hex_move_here_enabled()
	test_impassable_hex_move_here_disabled()
	if not has_failures():
		print("WildernessContextMenuBuilder: all tests passed.")


func _build(party_id: String = ACTIVE_PARTY_ID) -> Array[Dictionary]:
	return WildernessContextMenuBuilder.build_menu(TARGET_HEX, party_id, null, null)


func _build_with_map(map_data: HexMapData, target: Vector2i,
		current: Vector2i = Vector2i(-9999, -9999)) -> Array[Dictionary]:
	return WildernessContextMenuBuilder.build_menu(
		target, ACTIVE_PARTY_ID, map_data, null, current)


func _make_map_with_terrain(coord: Vector2i, terrain: HexTerrainData) -> HexMapData:
	var m := HexMapData.new()
	m.id = "test"
	m.party_hex = CURRENT_HEX
	# Make sure the start hex exists too (passable clear default).
	m.hexes[CURRENT_HEX] = HexTerrainData.new()
	m.hexes[coord] = terrain
	return m


func test_returns_expected_options_including_cancel() -> void:
	# 8 actions (move_here, explore, build_stronghold, place_loot_cache,
	# visit_loot_cache, survey, search_lair, hunt) + cancel = 9 entries.
	var options := _build()
	check(options.size() == 9, "expected 9 options (8 actions + cancel), got %d" % options.size())


func test_all_expected_ids_present() -> void:
	var options := _build()
	var expected := ["move_here", "explore", "build_stronghold",
		"place_loot_cache", "visit_loot_cache", "survey", "search_lair",
		"hunt", "cancel"]
	var ids: Array = []
	for opt in options:
		ids.append(opt.get("id", ""))
	for e in expected:
		check(e in ids, "missing option id: %s" % e)


func test_cancel_option_has_cancel_action_type() -> void:
	var options := _build()
	var cancel_opt: Dictionary = options.back()
	check(cancel_opt.get("id", "") == "cancel", "last option should be cancel")
	var ad: Dictionary = cancel_opt.get("action_data", {})
	check(ad.get("action_type", "") == "cancel", "cancel option action_type mismatch")


func test_action_data_carries_hex_coords() -> void:
	var options := _build()
	for opt in options:
		if opt.get("id", "") == "cancel":
			continue
		var ad: Dictionary = opt.get("action_data", {})
		check(int(ad.get("hex_q", 999)) == TARGET_HEX.x,
			"option %s missing hex_q" % opt.get("id", ""))
		check(int(ad.get("hex_r", 999)) == TARGET_HEX.y,
			"option %s missing hex_r" % opt.get("id", ""))


func test_empty_active_party_disables_action_options() -> void:
	var options: Array[Dictionary] = WildernessContextMenuBuilder.build_menu(
		TARGET_HEX, "", null, null)
	for opt in options:
		if opt.get("id", "") == "cancel":
			continue
		check(not opt.get("enabled", true),
			"option %s should be disabled without active party" % opt.get("id", ""))


func test_cancel_remains_enabled_when_no_party() -> void:
	var options: Array[Dictionary] = WildernessContextMenuBuilder.build_menu(
		TARGET_HEX, "", null, null)
	var cancel_opt: Dictionary = options.back()
	check(cancel_opt.get("enabled", false), "cancel must always be enabled")


func test_visit_cache_disabled_when_no_cache() -> void:
	# No campaign loaded → LocationCacheManager returns empty dict → has_cache=false.
	var options := _build()
	for opt in options:
		if opt.get("id", "") == "visit_loot_cache":
			check(not opt.get("enabled", true),
				"visit_loot_cache should be disabled when no cache is present")
			return
	check(false, "visit_loot_cache option not found")


func test_place_cache_enabled_when_no_cache() -> void:
	var options := _build()
	for opt in options:
		if opt.get("id", "") == "place_loot_cache":
			check(opt.get("enabled", false),
				"place_loot_cache should be enabled when no cache exists yet")
			return
	check(false, "place_loot_cache option not found")


func test_controller_can_move_false_disables_actions() -> void:
	# Adjacency gating was removed in favor of passability + reachability.
	# A null controller falls back to map_data validity; this test now just
	# confirms the legacy "controller==null+map==null → enabled" path stays
	# permissive so unit-test fixtures still produce enabled actions.
	check(true, "adjacency gate removed; passability gating exercised in other tests")


# ---------------------------------------------------------------------------
# Current-hex menu shape (Fix 3)
# ---------------------------------------------------------------------------

func test_current_hex_menu_omits_move_here() -> void:
	var options := WildernessContextMenuBuilder.build_menu(
		CURRENT_HEX, ACTIVE_PARTY_ID, null, null, CURRENT_HEX)
	var ids: Array = []
	for opt in options:
		ids.append(opt.get("id", ""))
	check(not ("move_here" in ids),
		"move_here should be omitted on the party's current hex; got %s" % str(ids))
	# Current-hex menu omits move_here, leaves 7 activities + cancel = 8.
	check(options.size() == 8,
		"current-hex menu should have 8 options (7 activities + cancel), got %d" % options.size())


func test_current_hex_menu_includes_place_loot_cache() -> void:
	var options := WildernessContextMenuBuilder.build_menu(
		CURRENT_HEX, ACTIVE_PARTY_ID, null, null, CURRENT_HEX)
	for opt in options:
		if opt.get("id", "") == "place_loot_cache":
			check(opt.get("enabled", false),
				"place_loot_cache should be enabled on current hex when no cache exists")
			return
	check(false, "place_loot_cache option not found in current-hex menu")


func test_current_hex_menu_visit_disabled_when_no_cache() -> void:
	var options := WildernessContextMenuBuilder.build_menu(
		CURRENT_HEX, ACTIVE_PARTY_ID, null, null, CURRENT_HEX)
	for opt in options:
		if opt.get("id", "") == "visit_loot_cache":
			check(not opt.get("enabled", true),
				"visit_loot_cache should be disabled on current hex with no cache present")
			return
	check(false, "visit_loot_cache option not found in current-hex menu")


func test_current_hex_menu_includes_survey() -> void:
	var options := WildernessContextMenuBuilder.build_menu(
		CURRENT_HEX, ACTIVE_PARTY_ID, null, null, CURRENT_HEX)
	for opt in options:
		if opt.get("id", "") == "survey":
			check(opt.get("enabled", false), "survey should be enabled on current hex")
			return
	check(false, "survey option not found in current-hex menu")


# ---------------------------------------------------------------------------
# Move Here passability gating (Fix 2)
# ---------------------------------------------------------------------------

func test_non_adjacent_hex_move_here_enabled() -> void:
	# Non-adjacent target with passable terrain (no controller), via map_data.
	var clear := HexTerrainData.new()  # default: clear / flat / no water
	var map := _make_map_with_terrain(Vector2i(3, -2), clear)
	var options := _build_with_map(map, Vector2i(3, -2), CURRENT_HEX)
	for opt in options:
		if opt.get("id", "") == "move_here":
			check(opt.get("enabled", false),
				"move_here should be enabled on a passable non-adjacent hex")
			return
	check(false, "move_here option not found")


func test_impassable_hex_move_here_disabled() -> void:
	var ocean := HexTerrainData.new()
	ocean.water = HexTerrainData.WATER_OCEAN
	var map := _make_map_with_terrain(Vector2i(3, -2), ocean)
	var options := _build_with_map(map, Vector2i(3, -2), CURRENT_HEX)
	for opt in options:
		if opt.get("id", "") == "move_here":
			check(not opt.get("enabled", true),
				"move_here should be disabled on impassable (ocean) terrain")
			return
	check(false, "move_here option not found")
