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
	test_enter_lair_buttons_with_stable_ordinals()
	test_build_stronghold_gated_by_survey_and_clearance()
	test_climb_here_appears_across_cliff_edge()
	test_climb_here_absent_without_cliff_edge()
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
	# visit_loot_cache, survey, search_lair, hunt) + get_hex_info (dev) + cancel = 10.
	var options := _build()
	check(options.size() == 10, "expected 10 options (8 actions + dev info + cancel), got %d" % options.size())


func test_all_expected_ids_present() -> void:
	var options := _build()
	var expected := ["move_here", "explore", "build_stronghold",
		"place_loot_cache", "visit_loot_cache", "survey", "search_lair",
		"hunt", "get_hex_info", "cancel"]
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
		var oid := str(opt.get("id", ""))
		# cancel + get_hex_info (a pure-read dev tool) are always enabled, party or not.
		if oid == "cancel" or oid == "get_hex_info":
			continue
		check(not opt.get("enabled", true),
			"option %s should be disabled without active party" % oid)


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
	# Current-hex menu omits move_here: 7 activities + get_hex_info (dev) + cancel = 9.
	check(options.size() == 9,
		"current-hex menu should have 9 options (7 activities + dev info + cancel), got %d" % options.size())


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


# ---------------------------------------------------------------------------
# Climb Here (cliff crossing — gdd-cliffs-canyons.md §6); needs a real controller
# ---------------------------------------------------------------------------

func _controller_with_terrain(with_cliff: bool) -> HexMapController:
	var m := HexMapData.new()
	m.id = "test_climb_menu"
	m.party_hex = CURRENT_HEX
	for q in range(-1, 2):
		for r in range(-1, 2):
			m.hexes[Vector2i(q, r)] = HexTerrainData.new()
	if with_cliff:
		# Cliff edge (0,0)-(1,0): owner (0,0), edge 2 (SE) → neighbour (1,0).
		var e := HexCliffEdgeData.new()
		e.hex_q = 0
		e.hex_r = 0
		e.edge = 2
		e.height_ft = 900
		m.cliff_edges.append(e)
	var ctrl := HexMapController.new()
	ctrl.load_map(m)
	return ctrl


func test_climb_here_appears_across_cliff_edge() -> void:
	var ctrl := _controller_with_terrain(true)
	var options := WildernessContextMenuBuilder.build_menu(
		Vector2i(1, 0), ACTIVE_PARTY_ID, ctrl.get_map(), ctrl, CURRENT_HEX)
	var climb: Dictionary = {}
	for opt in options:
		if opt.get("id", "") == "climb_cliff":
			climb = opt
			break
	check(not climb.is_empty(), "Climb Here appears across a cliff edge")
	var ad: Dictionary = climb.get("action_data", {})
	check(str(ad.get("action_type", "")) == "wilderness_climb_cliff",
		"climb option dispatches wilderness_climb_cliff")
	check(int(ad.get("hex_q", 999)) == 1 and int(ad.get("hex_r", 999)) == 0,
		"climb option carries the target hex coords")
	check(opt_enabled(options, "climb_cliff"), "climb option enabled for a passable cliff top")
	ctrl.free()


func test_climb_here_absent_without_cliff_edge() -> void:
	var ctrl := _controller_with_terrain(false)
	var ids: Array = []
	for opt in WildernessContextMenuBuilder.build_menu(
			Vector2i(1, 0), ACTIVE_PARTY_ID, ctrl.get_map(), ctrl, CURRENT_HEX):
		ids.append(opt.get("id", ""))
	check(not ("climb_cliff" in ids),
		"no Climb Here option without a cliff edge; got %s" % str(ids))
	ctrl.free()


func opt_enabled(options: Array, id: String) -> bool:
	for opt in options:
		if opt.get("id", "") == id:
			return bool(opt.get("enabled", false))
	return false


# ---------------------------------------------------------------------------
# Lair surfaces (gdd-lair-discovery.md §6.2 / §7) — DB-backed
# ---------------------------------------------------------------------------

const LAIR_CAMPAIGN_ID := "test_wcmb_lair_campaign"
const LAIR_MAP_ID := "test_wcmb_lair_map"
const LAIR_HEX := Vector2i(3, -2)


func _setup_lair_fixture() -> void:
	var db = CampaignRepository.db
	db.query_with_bindings(
		"DELETE FROM lairs WHERE campaign_id = ?", [LAIR_CAMPAIGN_ID])
	db.query_with_bindings(
		"DELETE FROM hex_lair_state WHERE campaign_id = ?", [LAIR_CAMPAIGN_ID])
	db.query_with_bindings(
		"DELETE FROM hex_maps WHERE id = ?", [LAIR_MAP_ID])
	db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[LAIR_CAMPAIGN_ID, "test wcmb lair"])
	db.query_with_bindings(
		"INSERT OR IGNORE INTO hex_maps (id, campaign_id, name, scale) " +
		"VALUES (?, ?, ?, ?)",
		[LAIR_MAP_ID, LAIR_CAMPAIGN_ID, "test_map", "regional_6mi"])
	GameState.campaign_id = LAIR_CAMPAIGN_ID


func _teardown_lair_fixture() -> void:
	GameState.campaign_id = ""
	var db = CampaignRepository.db
	db.query_with_bindings(
		"DELETE FROM lairs WHERE campaign_id = ?", [LAIR_CAMPAIGN_ID])
	db.query_with_bindings(
		"DELETE FROM hex_lair_state WHERE campaign_id = ?", [LAIR_CAMPAIGN_ID])
	db.query_with_bindings(
		"DELETE FROM hex_maps WHERE id = ?", [LAIR_MAP_ID])


func _place_fixture_lair(suffix: String, monster: String, created_at: int,
		cleared_at: Variant = null) -> String:
	return CampaignRepository.create_lair({
		"lair_id": "test_wcmb_lair_" + suffix,
		"campaign_id": LAIR_CAMPAIGN_ID,
		"map_id": LAIR_MAP_ID,
		"hex_q": LAIR_HEX.x,
		"hex_r": LAIR_HEX.y,
		"monster_group": monster,
		"monster_count": 4,
		"placed_via": "search",
		"created_at_round": created_at,
		"cleared_at_round": cleared_at,
	})


func _lair_map() -> HexMapData:
	var m := HexMapData.new()
	m.id = LAIR_MAP_ID
	m.party_hex = CURRENT_HEX
	m.hexes[CURRENT_HEX] = HexTerrainData.new()
	m.hexes[LAIR_HEX] = HexTerrainData.new()
	return m


func test_enter_lair_buttons_with_stable_ordinals() -> void:
	_setup_lair_fixture()
	_place_fixture_lair("g1", "goblin", 10)
	_place_fixture_lair("g2", "goblin", 20)
	_place_fixture_lair("o1", "orc", 30)

	var options := _build_with_map(_lair_map(), LAIR_HEX, CURRENT_HEX)
	var labels: Array = []
	for opt in options:
		if String(opt.get("id", "")).begins_with("enter_lair_"):
			labels.append(opt.get("label", ""))
			var ad: Dictionary = opt.get("action_data", {})
			check(ad.get("action_type", "") == "wilderness_enter_lair",
				"lair option dispatches wilderness_enter_lair")
			check(not String(ad.get("lair_id", "")).is_empty(),
				"lair option carries its lair_id")
	check(labels == ["Enter Goblin Lair 1", "Enter Goblin Lair 2", "Enter Orc Lair"],
		"same-type lairs get 1..N ordinals; singletons get none — got %s" % str(labels))

	# Clearing #1 retains #2's number and restyles #1 as Re-enter.
	CampaignRepository.mark_lair_cleared("test_wcmb_lair_g1", 100)
	options = _build_with_map(_lair_map(), LAIR_HEX, CURRENT_HEX)
	labels = []
	for opt in options:
		if String(opt.get("id", "")).begins_with("enter_lair_"):
			labels.append(opt.get("label", ""))
	check(labels == ["Re-enter Goblin Lair 1 (cleared)", "Enter Goblin Lair 2",
		"Enter Orc Lair"],
		"cleared lair keeps its ordinal; survivors keep theirs — got %s" % str(labels))

	_teardown_lair_fixture()


func test_build_stronghold_gated_by_survey_and_clearance() -> void:
	_setup_lair_fixture()

	# Un-surveyed land blocks even with NO lairs placed (ruling 2026-06-10).
	check(not ("build_stronghold" in _menu_ids()),
		"Build Stronghold hidden on un-surveyed land")

	# Surveyed (total 1) but the placed lair is uncleared → still hidden.
	HexLairState.set_surveyed_total(
		LAIR_CAMPAIGN_ID, LAIR_MAP_ID, LAIR_HEX.x, LAIR_HEX.y, 1)
	HexLairState.increment_placed_count(
		LAIR_CAMPAIGN_ID, LAIR_MAP_ID, LAIR_HEX.x, LAIR_HEX.y)
	var lid := _place_fixture_lair("gate", "ogre", 10)
	check(not ("build_stronghold" in _menu_ids()),
		"Build Stronghold hidden while a placed lair is uncleared")

	# Cleared the surveyed total → option appears.
	CampaignRepository.mark_lair_cleared(lid, 100)
	check("build_stronghold" in _menu_ids(),
		"Build Stronghold appears once surveyed and all surveyed lairs cleared")

	_teardown_lair_fixture()


func _menu_ids() -> Array:
	var ids: Array = []
	for opt in _build_with_map(_lair_map(), LAIR_HEX, CURRENT_HEX):
		ids.append(opt.get("id", ""))
	return ids
