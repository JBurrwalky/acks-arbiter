extends "res://tests/test_suite_base.gd"

## Unit tests for Phase E-1: PartyData, TravelSpeedCalculator, getting-lost checks,
## forced march eligibility, and formation grid.
## Run via test_runner.tscn.


func run_all_tests() -> void:
	test_party_data_from_db()
	test_party_data_to_state_dict()
	test_party_slowest_movement()
	test_party_has_member()
	test_formation_grid_placement()
	test_formation_grid_queries()
	test_formation_marching_order()
	test_formation_swap()
	test_travel_clear_terrain()
	test_travel_forest_terrain()
	test_travel_mountains_terrain()
	test_travel_road_override()
	test_travel_forced_march()
	test_getting_lost_clear_no_nav()
	test_getting_lost_swamp_with_nav()
	test_getting_lost_road_auto_pass()
	test_forced_march_no_endurance()
	test_forced_march_with_endurance()
	test_rest_requirement()
	test_rest_penalty()
	test_bankers_rounding()
	if not has_failures():
		print("PartyManagement: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_character(char_id: String, char_name: String, movement: int = 120,
		profs: Array = []) -> CharacterData:
	var cd := CharacterData.new()
	cd.id = char_id
	cd.name = char_name
	cd.base_movement = movement
	cd.constitution = 10  # +0 modifier
	cd.proficiencies = profs
	return cd


func _make_party(members_data: Array = [],
		force_march: bool = false) -> PartyData:
	var pd := PartyData.new()
	pd.id = "test_party"
	pd.campaign_id = "test_campaign"
	pd.name = "Test Party"
	pd.is_force_marching = force_march
	for cd: CharacterData in members_data:
		pd.members.append({
			"character_id": cd.id,
			"formation_col": PartyData.UNASSIGNED,
			"formation_row": PartyData.UNASSIGNED,
		})
		pd.character_data.append(cd)
	return pd


# ---------------------------------------------------------------------------
# PartyData tests
# ---------------------------------------------------------------------------

func test_party_data_from_db() -> void:
	var party_row := {
		"id": "p1", "campaign_id": "c1", "name": "Heroes",
		"current_map_id": "m1", "current_hex_q": 3, "current_hex_r": 5,
		"current_location_type": "wilderness",
	}
	var member_rows := [
		{"character_id": "ch1", "formation_slot": "front", "formation_col": 2, "formation_row": 0},
		{"character_id": "ch2", "formation_slot": "rear", "formation_col": 2, "formation_row": 5},
	]
	var state_row := {
		"marching_order": "[]",
		"is_lost": 1, "is_force_marching": 0,
		"force_march_days_used": 0, "days_since_rest": 3,
		"rations_days_remaining": 10, "current_mount_type": "",
	}
	var pd := PartyData.from_db(party_row, member_rows, state_row)
	check(pd.id == "p1", "from_db: id")
	check(pd.name == "Heroes", "from_db: name")
	check(pd.members.size() == 2, "from_db: 2 members")
	check(pd.members[0]["formation_col"] == 2, "from_db: ch1 col=2")
	check(pd.members[0]["formation_row"] == 0, "from_db: ch1 row=0")
	check(pd.is_lost == true, "from_db: is_lost")
	check(pd.days_since_rest == 3, "from_db: days_since_rest")
	check(pd.get_hex() == Vector2i(3, 5), "from_db: hex position")
	print("  party_data_from_db: OK")


func test_party_data_to_state_dict() -> void:
	var pd := PartyData.new()
	pd.id = "p1"
	pd.is_lost = true
	pd.days_since_rest = 4
	var d := pd.to_state_dict()
	check(d["party_id"] == "p1", "to_state_dict: party_id")
	check(d["is_lost"] == 1, "to_state_dict: is_lost as int")
	print("  party_data_to_state_dict: OK")


func test_party_slowest_movement() -> void:
	var c1 := _make_character("c1", "Fast", 120)
	var c2 := _make_character("c2", "Slow", 60)
	var party := _make_party([c1, c2])
	check(party.get_slowest_movement() == 60, "slowest movement = 60")
	print("  party_slowest_movement: OK")


func test_party_has_member() -> void:
	var c1 := _make_character("c1", "Alice")
	var party := _make_party([c1])
	check(party.has_member("c1") == true, "has_member: c1 present")
	check(party.has_member("c999") == false, "has_member: c999 absent")
	print("  party_has_member: OK")


# ---------------------------------------------------------------------------
# Formation grid tests
# ---------------------------------------------------------------------------

func test_formation_grid_placement() -> void:
	var c1 := _make_character("c1", "Alice")
	var c2 := _make_character("c2", "Bob")
	var party := _make_party([c1, c2])
	# Both start unplaced
	check(party.get_unplaced_members().size() == 2, "grid: both unplaced initially")
	check(party.get_placed_members().size() == 0, "grid: none placed initially")
	# Place c1 at (2, 0) — front center
	party.set_formation_pos("c1", 2, 0)
	check(party.get_formation_pos("c1") == Vector2i(2, 0), "grid: c1 at (2,0)")
	check(party.get_character_at(2, 0) == "c1", "grid: cell (2,0) = c1")
	check(party.get_placed_members().size() == 1, "grid: 1 placed")
	check(party.get_unplaced_members().size() == 1, "grid: 1 unplaced")
	# Unplace c1
	party.unplace_character("c1")
	check(party.get_formation_pos("c1") == Vector2i(-1, -1), "grid: c1 unplaced")
	check(party.get_character_at(2, 0) == "", "grid: cell (2,0) empty")
	print("  formation_grid_placement: OK")


func test_formation_grid_queries() -> void:
	var pd := PartyData.new()
	pd.members = [
		{"character_id": "c1", "formation_col": 0, "formation_row": 0},
		{"character_id": "c2", "formation_col": 4, "formation_row": 0},
		{"character_id": "c3", "formation_col": 2, "formation_row": 5},
		{"character_id": "c4", "formation_col": -1, "formation_row": -1},
	]
	check(pd.get_character_at(0, 0) == "c1", "query: (0,0) = c1")
	check(pd.get_character_at(4, 0) == "c2", "query: (4,0) = c2")
	check(pd.get_character_at(2, 5) == "c3", "query: (2,5) = c3")
	check(pd.get_character_at(1, 1) == "", "query: (1,1) = empty")
	check(pd.get_placed_members().size() == 3, "query: 3 placed")
	check(pd.get_unplaced_members().size() == 1, "query: 1 unplaced")
	check(pd.get_unplaced_members()[0] == "c4", "query: c4 unplaced")
	print("  formation_grid_queries: OK")


func test_formation_marching_order() -> void:
	var pd := PartyData.new()
	pd.members = [
		{"character_id": "rear_right", "formation_col": 4, "formation_row": 3},
		{"character_id": "front_left", "formation_col": 0, "formation_row": 0},
		{"character_id": "front_right", "formation_col": 4, "formation_row": 0},
		{"character_id": "unplaced", "formation_col": -1, "formation_row": -1},
		{"character_id": "mid_center", "formation_col": 2, "formation_row": 1},
	]
	var order: Array = pd.get_marching_order()
	# Row 0: front_left (col 0), front_right (col 4)
	# Row 1: mid_center (col 2)
	# Row 3: rear_right (col 4)
	# Then unplaced
	check(order[0] == "front_left", "march: front_left first")
	check(order[1] == "front_right", "march: front_right second")
	check(order[2] == "mid_center", "march: mid_center third")
	check(order[3] == "rear_right", "march: rear_right fourth")
	check(order[4] == "unplaced", "march: unplaced last")
	print("  formation_marching_order: OK")


func test_formation_swap() -> void:
	var pd := PartyData.new()
	pd.members = [
		{"character_id": "c1", "formation_col": 0, "formation_row": 0},
		{"character_id": "c2", "formation_col": 4, "formation_row": 3},
	]
	pd.swap_positions("c1", "c2")
	check(pd.get_formation_pos("c1") == Vector2i(4, 3), "swap: c1 moved to (4,3)")
	check(pd.get_formation_pos("c2") == Vector2i(0, 0), "swap: c2 moved to (0,0)")
	print("  formation_swap: OK")


# ---------------------------------------------------------------------------
# TravelSpeedCalculator tests
# ---------------------------------------------------------------------------

func test_travel_clear_terrain() -> void:
	# 120'/turn × 0.2 × 1.0 (clear) = 24 mi/day
	var c1 := _make_character("c1", "Walker", 120)
	var party := _make_party([c1])
	var result := TravelSpeedCalculator.calculate_party_speed(party, "clear")
	check(result["base_exploration_speed"] == 120, "clear: base 120")
	check(result["miles_per_day"] == 24.0, "clear: 24 mi/day, got %.1f" % result["miles_per_day"])
	print("  travel_clear_terrain: OK")


func test_travel_forest_terrain() -> void:
	# 120'/turn × 0.2 × 2/3 (woods) = 16 mi/day
	var c1 := _make_character("c1", "Walker", 120)
	var party := _make_party([c1])
	var result := TravelSpeedCalculator.calculate_party_speed(party, "woods")
	check(result["miles_per_day"] == 16.0, "woods: 16 mi/day, got %.1f" % result["miles_per_day"])
	print("  travel_forest_terrain: OK")


func test_travel_mountains_terrain() -> void:
	# 120'/turn × 0.2 × 0.5 (mountains) = 12 mi/day
	var c1 := _make_character("c1", "Walker", 120)
	var party := _make_party([c1])
	var result := TravelSpeedCalculator.calculate_party_speed(party, "mountains")
	check(result["miles_per_day"] == 12.0, "mountains: 12 mi/day, got %.1f" % result["miles_per_day"])
	print("  travel_mountains_terrain: OK")


func test_travel_road_override() -> void:
	# 120'/turn × 0.2 × 1.5 (road) = 36 mi/day
	var c1 := _make_character("c1", "Walker", 120)
	var party := _make_party([c1])
	var result := TravelSpeedCalculator.calculate_party_speed(party, "mountains", true)
	check(result["miles_per_day"] == 36.0, "road: 36 mi/day (overrides mountains), got %.1f" % result["miles_per_day"])
	check(result["on_road"] == true, "road: on_road flag")
	print("  travel_road_override: OK")


func test_travel_forced_march() -> void:
	# 120'/turn × 0.2 × 1.0 × 1.5 (forced) = 36 mi/day
	var c1 := _make_character("c1", "Walker", 120)
	var party := _make_party([c1], true)
	var result := TravelSpeedCalculator.calculate_party_speed(party, "clear")
	check(result["miles_per_day"] == 36.0, "forced march: 36 mi/day, got %.1f" % result["miles_per_day"])
	check(result["is_forced_march"] == true, "forced march: flag set")
	print("  travel_forced_march: OK")


# ---------------------------------------------------------------------------
# Getting lost tests
# ---------------------------------------------------------------------------

func test_getting_lost_clear_no_nav() -> void:
	# Clear terrain target = 4. Roll 4 with no nav = pass.
	var party := _make_party([_make_character("c1", "NoNav")])
	var result := TravelSpeedCalculator.check_getting_lost(party, "clear", 4)
	check(result["target"] == 4, "lost clear: target 4")
	check(result["modifier"] == 0, "lost clear: no nav modifier")
	check(result["succeeded"] == true, "lost clear: roll 4 >= 4 succeeds")
	# Roll 3 should fail
	var result2 := TravelSpeedCalculator.check_getting_lost(party, "clear", 3)
	check(result2["succeeded"] == false, "lost clear: roll 3 < 4 fails")
	print("  getting_lost_clear_no_nav: OK")


func test_getting_lost_swamp_with_nav() -> void:
	# Swamp target = 11. Navigation gives +4. Roll 7 + 4 = 11 = pass.
	var nav_prof := [{"proficiency_key": "navigation", "rank": 1}]
	var c1 := _make_character("c1", "Navigator", 120, nav_prof)
	var party := _make_party([c1])
	var result := TravelSpeedCalculator.check_getting_lost(party, "swamp", 7)
	check(result["target"] == 11, "lost swamp+nav: target 11")
	check(result["modifier"] == 4, "lost swamp+nav: +4 modifier")
	check(result["succeeded"] == true, "lost swamp+nav: 7+4=11 >= 11 succeeds")
	# Roll 6 + 4 = 10 < 11 = fail
	var result2 := TravelSpeedCalculator.check_getting_lost(party, "swamp", 6)
	check(result2["succeeded"] == false, "lost swamp+nav: 6+4=10 < 11 fails")
	print("  getting_lost_swamp_with_nav: OK")


func test_getting_lost_road_auto_pass() -> void:
	# Roads auto-succeed regardless of roll
	var party := _make_party([_make_character("c1", "Lost")])
	var result := TravelSpeedCalculator.check_getting_lost(party, "jungle", 1, true)
	check(result["succeeded"] == true, "road: auto-succeed even with roll 1 in jungle")
	print("  getting_lost_road_auto_pass: OK")


# ---------------------------------------------------------------------------
# Forced march tests
# ---------------------------------------------------------------------------

func test_forced_march_no_endurance() -> void:
	# Without Endurance: max 1 day, then must rest
	var party := _make_party([_make_character("c1", "NoEnd")])
	var elig := TravelSpeedCalculator.check_force_march_eligibility(party)
	check(elig["max_days"] == 1, "no endurance: max 1 day")
	check(elig["can_continue"] == true, "no endurance: can start (0 used)")
	check(elig["must_rest_after"] == true, "no endurance: must rest after 1 day")
	# After 1 day used
	party.force_march_days_used = 1
	var elig2 := TravelSpeedCalculator.check_force_march_eligibility(party)
	check(elig2["can_continue"] == false, "no endurance: can't continue after 1 day")
	print("  forced_march_no_endurance: OK")


func test_forced_march_with_endurance() -> void:
	# With Endurance + CON 14 (+1 modifier): 1 + 1 = 2 days
	var end_prof := [{"proficiency_key": "endurance", "rank": 1}]
	var c1 := _make_character("c1", "Endurer", 120, end_prof)
	c1.constitution = 14  # +1 modifier in ACKS
	var party := _make_party([c1])
	var elig := TravelSpeedCalculator.check_force_march_eligibility(party)
	check(elig["max_days"] == 2, "endurance CON14: max 2 days, got %d" % elig["max_days"])
	check(elig["can_continue"] == true, "endurance: can start")
	# After 1 day
	party.force_march_days_used = 1
	var elig2 := TravelSpeedCalculator.check_force_march_eligibility(party)
	check(elig2["can_continue"] == true, "endurance: can continue after 1 day")
	check(elig2["must_rest_after"] == true, "endurance: must rest after day 2")
	# After 2 days
	party.force_march_days_used = 2
	var elig3 := TravelSpeedCalculator.check_force_march_eligibility(party)
	check(elig3["can_continue"] == false, "endurance: can't continue after 2 days")
	print("  forced_march_with_endurance: OK")


# ---------------------------------------------------------------------------
# Rest tests
# ---------------------------------------------------------------------------

func test_rest_requirement() -> void:
	var party := _make_party([_make_character("c1", "Tired")])
	party.days_since_rest = 5
	check(party.needs_rest() == false, "5 days: no rest needed yet")
	party.days_since_rest = 6
	check(party.needs_rest() == true, "6 days: rest needed")
	# With endurance, never needs rest
	var end_prof := [{"proficiency_key": "endurance", "rank": 1}]
	var c2 := _make_character("c2", "Endurer", 120, end_prof)
	var party2 := _make_party([c2])
	party2.days_since_rest = 10
	check(party2.needs_rest() == false, "endurance: no rest needed even at 10 days")
	print("  rest_requirement: OK")


func test_rest_penalty() -> void:
	var party := _make_party([_make_character("c1", "Tired")])
	party.days_since_rest = 5
	check(TravelSpeedCalculator.rest_penalty(party) == 0, "5 days: no penalty")
	party.days_since_rest = 6
	check(TravelSpeedCalculator.rest_penalty(party) == 1, "6 days: -1 penalty")
	party.days_since_rest = 8
	check(TravelSpeedCalculator.rest_penalty(party) == 3, "8 days: -3 penalty")
	print("  rest_penalty: OK")


# ---------------------------------------------------------------------------
# Banker's rounding
# ---------------------------------------------------------------------------

func test_bankers_rounding() -> void:
	# 2026-05-19 bucket-A sweep: private TravelSpeedCalculator._bankers_round
	# helper was consolidated to canonical XPAwardCalculator.bankers_round.
	# That helper returns int (not float), so the assertions compare ints.
	check(XPAwardCalculator.bankers_round(2.5) == 2, "2.5 → 2 (even)")
	check(XPAwardCalculator.bankers_round(3.5) == 4, "3.5 → 4 (even)")
	check(XPAwardCalculator.bankers_round(2.4) == 2, "2.4 → 2")
	check(XPAwardCalculator.bankers_round(2.6) == 3, "2.6 → 3")
	check(XPAwardCalculator.bankers_round(0.5) == 0, "0.5 → 0 (even)")
	check(XPAwardCalculator.bankers_round(1.5) == 2, "1.5 → 2 (even)")
	print("  bankers_rounding: OK")
