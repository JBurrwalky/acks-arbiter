extends "res://tests/test_suite_base.gd"

## Unit tests for SettlementNavigation (navigation throw system)
## and SettlementEncounterScheduler (encounter check event scheduling).


const TEST_CAMPAIGN := "test_nav_campaign"
const TEST_SETTLEMENT := "test_nav_settlement"
const TEST_POI_A := "poi_nav_a"
const TEST_POI_B := "poi_nav_b"
const TEST_PARTY := "test_nav_party"


func run_all_tests() -> void:
	_cleanup_test_data()
	_setup_test_data()

	# Navigation tests
	test_known_route_is_exempt()
	test_unknown_route_requires_throw()
	test_visited_destination_gives_bonus()
	test_navigation_proficiency_gives_bonus()
	test_both_bonuses_stack()
	test_high_roll_succeeds()
	test_low_roll_fails()
	test_deviation_roll_range()

	# Encounter scheduler tests
	test_streets_day_interval()
	test_streets_night_interval()
	test_alleys_day_interval()
	test_alleys_night_interval()
	test_no_checks_for_short_travel()
	test_multiple_checks_for_long_travel()
	test_looking_for_trouble_in_event_data()

	_cleanup_test_data()

	if not has_failures():
		print("SettlementNavigation + SettlementEncounterScheduler: all tests passed.")


func _setup_test_data() -> void:
	# Create minimal campaign and settlement data for route/poi lookups.
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[TEST_CAMPAIGN, "Nav Test"])


func _cleanup_test_data() -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM known_city_routes WHERE campaign_id = ?", [TEST_CAMPAIGN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM visited_pois WHERE campaign_id = ?", [TEST_CAMPAIGN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [TEST_CAMPAIGN])
	# Clear any dice overrides we set.
	GameState.dice_overrides.clear()


# ---------------------------------------------------------------------------
# Navigation throw tests
# ---------------------------------------------------------------------------

func test_known_route_is_exempt() -> void:
	# Record a known route, then check navigation — should be exempt.
	CampaignRepository.record_city_route(TEST_CAMPAIGN, TEST_SETTLEMENT, TEST_POI_A, TEST_POI_B)
	var result := SettlementNavigation.check_navigation(
		TEST_CAMPAIGN, TEST_SETTLEMENT, TEST_POI_A, TEST_POI_B, [])
	check(result["exempt"] == true, "known route should be exempt")
	check(result["succeeded"] == true, "exempt route should succeed")


func test_unknown_route_requires_throw() -> void:
	# No known route, no visited poi — should require a throw.
	var result := SettlementNavigation.check_navigation(
		TEST_CAMPAIGN, TEST_SETTLEMENT, "poi_unknown_a", "poi_unknown_b", [])
	check(result["exempt"] == false, "unknown route should not be exempt")


func test_visited_destination_gives_bonus() -> void:
	# Mark destination as visited.
	CampaignRepository.record_visited_poi(TEST_CAMPAIGN, TEST_SETTLEMENT, "poi_visited_dest", 100)
	# Force a roll of 7 (should fail without bonus: 7 < 11, but succeed with +4: 11 >= 11).
	GameState.dice_overrides["navigation_check"] = 7
	var result := SettlementNavigation.check_navigation(
		TEST_CAMPAIGN, TEST_SETTLEMENT, "poi_new_origin", "poi_visited_dest", [])
	check(result["modifier"] >= 4, "visited destination should give +4, got %d" % result["modifier"])
	check(result["succeeded"] == true, "roll 7 + 4 = 11 should succeed")
	GameState.dice_overrides.clear()


func test_navigation_proficiency_gives_bonus() -> void:
	# Create a mock character with Navigation proficiency.
	var char_data := CharacterData.new()
	char_data.name = "Navigator"
	char_data.proficiencies = [{"proficiency_key": "navigation", "rank": 1, "slot_type": "general", "selections_count": 1}]

	# Force a roll of 7.
	GameState.dice_overrides["navigation_check"] = 7
	var result := SettlementNavigation.check_navigation(
		TEST_CAMPAIGN, TEST_SETTLEMENT, "poi_prof_a", "poi_prof_b", [char_data])
	check(result["modifier"] >= 4, "navigation proficiency should give +4, got %d" % result["modifier"])
	check(result["succeeded"] == true, "roll 7 + 4 = 11 should succeed")
	GameState.dice_overrides.clear()


func test_both_bonuses_stack() -> void:
	# Visited destination + Navigation proficiency = +8.
	CampaignRepository.record_visited_poi(TEST_CAMPAIGN, TEST_SETTLEMENT, "poi_stack_dest", 100)
	var char_data := CharacterData.new()
	char_data.name = "Navigator"
	char_data.proficiencies = [{"proficiency_key": "navigation", "rank": 1, "slot_type": "general", "selections_count": 1}]

	# Force a roll of 3 (3 + 8 = 11, should succeed).
	GameState.dice_overrides["navigation_check"] = 3
	var result := SettlementNavigation.check_navigation(
		TEST_CAMPAIGN, TEST_SETTLEMENT, "poi_stack_origin", "poi_stack_dest", [char_data])
	check(result["modifier"] == 8, "both bonuses should stack to +8, got %d" % result["modifier"])
	check(result["succeeded"] == true, "roll 3 + 8 = 11 should succeed")
	GameState.dice_overrides.clear()


func test_high_roll_succeeds() -> void:
	GameState.dice_overrides["navigation_check"] = 15
	var result := SettlementNavigation.check_navigation(
		TEST_CAMPAIGN, TEST_SETTLEMENT, "poi_h_a", "poi_h_b", [])
	check(result["succeeded"] == true, "roll 15 should succeed (>= 11)")
	GameState.dice_overrides.clear()


func test_low_roll_fails() -> void:
	GameState.dice_overrides["navigation_check"] = 5
	var result := SettlementNavigation.check_navigation(
		TEST_CAMPAIGN, TEST_SETTLEMENT, "poi_l_a", "poi_l_b", [])
	check(result["succeeded"] == false, "roll 5 should fail (< 11)")
	GameState.dice_overrides.clear()


func test_deviation_roll_range() -> void:
	# Deviation is 1d4+1, range 2-5.
	for i in range(10):
		GameState.dice_overrides["navigation_deviation"] = i % 4 + 2  # 2, 3, 4, 5, 2, ...
		var dev: int = SettlementNavigation.roll_deviation()
		check(dev >= 2 and dev <= 5,
			"deviation should be 2-5, got %d" % dev)
	GameState.dice_overrides.clear()


# ---------------------------------------------------------------------------
# Encounter scheduler tests
# ---------------------------------------------------------------------------

func test_streets_day_interval() -> void:
	var interval := SettlementEncounterScheduler.get_interval_for_context(false, false)
	check(interval == 360, "streets day interval should be 360 rounds, got %d" % interval)


func test_streets_night_interval() -> void:
	var interval := SettlementEncounterScheduler.get_interval_for_context(false, true)
	check(interval == 180, "streets night interval should be 180 rounds, got %d" % interval)


func test_alleys_day_interval() -> void:
	var interval := SettlementEncounterScheduler.get_interval_for_context(true, false)
	check(interval == 180, "alleys day interval should be 180 rounds, got %d" % interval)


func test_alleys_night_interval() -> void:
	var interval := SettlementEncounterScheduler.get_interval_for_context(true, true)
	check(interval == 60, "alleys night interval should be 60 rounds, got %d" % interval)


func test_no_checks_for_short_travel() -> void:
	# Travel of 100 rounds on streets by day (interval 360). No checks should fire.
	var scheduler := EventScheduler.new()
	var ids := SettlementEncounterScheduler.schedule_encounter_checks(
		scheduler, TEST_PARTY, 0, 100, false, false, false)
	check(ids.size() == 0,
		"100-round daytime street travel should have 0 encounter checks, got %d" % ids.size())


func test_multiple_checks_for_long_travel() -> void:
	# Travel of 800 rounds on streets by day (interval 360).
	# Checks at round 360 and 720 — two checks.
	var scheduler := EventScheduler.new()
	var ids := SettlementEncounterScheduler.schedule_encounter_checks(
		scheduler, TEST_PARTY, 0, 800, false, false, false)
	check(ids.size() == 2,
		"800-round daytime street travel should have 2 encounter checks, got %d" % ids.size())

	# Verify event fire times.
	var events := scheduler.get_events_for_owner(TEST_PARTY)
	check(events.size() == 2, "scheduler should have 2 events")
	if events.size() >= 2:
		check(events[0].fire_time == 360, "first check at 360, got %d" % events[0].fire_time)
		check(events[1].fire_time == 720, "second check at 720, got %d" % events[1].fire_time)


func test_looking_for_trouble_in_event_data() -> void:
	var scheduler := EventScheduler.new()
	var ids := SettlementEncounterScheduler.schedule_encounter_checks(
		scheduler, TEST_PARTY, 0, 400, false, false, true)
	check(ids.size() == 1, "should have 1 check")
	if ids.size() > 0:
		var events := scheduler.get_events_for_owner(TEST_PARTY)
		var data: Dictionary = events[0].data
		check(data.get("threshold", 0) == 5,
			"looking for trouble should set threshold to 5, got %d" % data.get("threshold", 0))
		check(data.get("looking_for_trouble", false) == true,
			"looking_for_trouble flag should be true")
