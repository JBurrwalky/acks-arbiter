extends "res://tests/test_suite_base.gd"

## Integration test: specialist bonuses flow through Phase 4/5 resolvers
## (Wilderness closure Phase 6).
##
## Verifies that the Phase 6 `optional_specialist_bonus` parameters added
## across LairSearchResolver / SurveyingResolver / TrackingResolver actually
## change the throw outcome — the load-bearing reason Phase 6 exists.
##
## Per the plan: "integration test that lair search with Pathfinder beats
## lair search without."


# ---------------------------------------------------------------------------
# Fake DiceSystem
# ---------------------------------------------------------------------------

class _FixedDice:
	extends RefCounted
	var _value: int = 11
	func _init(v: int = 11) -> void:
		_value = v
	func roll_digital(sides: int, count: int = 1, modifier: int = 0,
			_roll_type: String = "") -> RollResult:
		var r := RollResult.new()
		r.sides = sides
		r.count = count
		r.modifier = modifier
		r.individual_results = []
		var total := 0
		for _i in range(count):
			r.individual_results.append(_value)
			total += _value
		r.raw_total = total
		r.modified_total = total + modifier
		r.natural_one = (_value == 1 and sides == 20 and count == 1)
		r.natural_max = (_value == sides and count == 1)
		return r


func run_all_tests() -> void:
	test_lair_search_with_pathfinder_beats_without()
	test_passive_lair_check_with_pathfinder_beats_without()
	test_surveying_with_land_surveyor_beats_without()
	test_tracking_with_pathfinder_beats_without()
	test_zero_specialist_bonus_matches_legacy_behavior()
	if not has_failures():
		print("SpecialistIntegration: all tests passed.")


func _make_party(member_count: int, with_proficiency: String = "") -> PartyData:
	var pd := PartyData.new()
	pd.id = "test_phase6_int"
	pd.character_data = []
	for i in range(member_count):
		var cd := CharacterData.new()
		cd.id = "pc_%d" % i
		cd.name = "PC %d" % i
		cd.hp_max = 10
		cd.hp_current = 10
		if not with_proficiency.is_empty() and i == 0:
			cd.proficiencies = [{"proficiency_key": with_proficiency, "rank": 1}]
		pd.character_data.append(cd)
	return pd


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_lair_search_with_pathfinder_beats_without() -> void:
	# Roll 14, no Tracking, target 18+ → fail without specialist (14 < 18),
	# pass with Pathfinder bonus +4 (14 + 4 = 18 ≥ 18).
	var party := _make_party(3)
	var dice := _FixedDice.new(14)
	var without := LairSearchResolver.search_hour(party, 0, 1, dice, 0)
	check(not bool(without["succeeded"]), "no Pathfinder → 14 < 18 fails")

	var dice2 := _FixedDice.new(14)
	var with_pf := LairSearchResolver.search_hour(
		party, 0, 1, dice2, SpecialistCatalog.bonus_for_resolver(
			"pathfinder", SpecialistCatalog.KIND_LAIR_SEARCH))
	check(bool(with_pf["succeeded"]),
		"with Pathfinder → 14 + 4 = 18 succeeds")
	check(int(with_pf["specialist_bonus"]) == 4,
		"specialist_bonus stored in result")


func test_passive_lair_check_with_pathfinder_beats_without() -> void:
	# 24 mi/day → target 16+. Roll 12, +4 specialist = 16 → success.
	var party := _make_party(4)
	var dice := _FixedDice.new(12)
	var without := LairSearchResolver.passive_check(party, 24, 1, dice, 0)
	check(not bool(without["succeeded"]), "no Pathfinder passive: 12 < 16")

	var dice2 := _FixedDice.new(12)
	var bonus: int = SpecialistCatalog.bonus_for_resolver(
		"pathfinder", SpecialistCatalog.KIND_LAIR_SEARCH_PASSIVE)
	var with_pf := LairSearchResolver.passive_check(party, 24, 1, dice2, bonus)
	check(bool(with_pf["succeeded"]),
		"with Pathfinder passive: 12 + 4 = 16 succeeds")
	check(bool(with_pf["lair_found"]),
		"successful passive with lairs present → lair_found")


func test_surveying_with_land_surveyor_beats_without() -> void:
	# Land Surveying assess. First-arrival target 18+. Roll 14, no specialist
	# → 14 < 18 fail. Roll 14 + 4 Land Surveyor → 18 ≥ 18 success.
	var party := _make_party(3, "land_surveying")
	var dice := _FixedDice.new(14)
	var without := SurveyingResolver.assess(party, 0, 5, dice, 0)
	check(not bool(without["succeeded"]),
		"no Land Surveyor specialist: 14 < 18 fails")

	var dice2 := _FixedDice.new(14)
	var bonus: int = SpecialistCatalog.bonus_for_resolver(
		"land_surveyor", SpecialistCatalog.KIND_SURVEYING)
	var with_ls := SurveyingResolver.assess(party, 0, 5, dice2, bonus)
	check(bool(with_ls["succeeded"]),
		"with Land Surveyor: 14 + 4 = 18 succeeds")
	check(int(with_ls["specialist_bonus"]) == 4,
		"specialist_bonus stored in result")
	check(int(with_ls["estimate"]) == 5, "success → reveals actual count 5")


func test_tracking_with_pathfinder_beats_without() -> void:
	# Tracking base 11. Roll 7, no specialist → 7 < 11 fail.
	# Roll 7 + 4 Pathfinder → 11 ≥ 11 success.
	var tracker := CharacterData.new()
	tracker.id = "pc_tracker"
	tracker.name = "Tracker"
	tracker.hp_max = 10
	tracker.hp_current = 10
	tracker.proficiencies = [{"proficiency_key": "tracking", "rank": 1}]

	var dice := _FixedDice.new(7)
	var without := TrackingResolver.attempt(tracker, 1, "normal", "good", 0, dice, 0)
	check(not bool(without["succeeded"]),
		"no Pathfinder: 7 < 11 fails")

	var dice2 := _FixedDice.new(7)
	var bonus: int = SpecialistCatalog.bonus_for_resolver(
		"pathfinder", SpecialistCatalog.KIND_TRACKING)
	var with_pf := TrackingResolver.attempt(
		tracker, 1, "normal", "good", 0, dice2, bonus)
	check(bool(with_pf["succeeded"]),
		"with Pathfinder: 7 + 4 = 11 succeeds")
	check(int(with_pf["specialist_bonus"]) == 4,
		"specialist_bonus stored in result")


func test_zero_specialist_bonus_matches_legacy_behavior() -> void:
	# Verify default-value parameter (caller omits the bonus) matches an
	# explicit 0. This is the pre-Phase-6 contract — must remain stable.
	var party := _make_party(2)
	var dice_a := _FixedDice.new(18)
	var legacy := LairSearchResolver.search_hour(party, 0, 1, dice_a)
	var dice_b := _FixedDice.new(18)
	var explicit_zero := LairSearchResolver.search_hour(party, 0, 1, dice_b, 0)
	check(legacy["succeeded"] == explicit_zero["succeeded"],
		"omitting specialist_bonus matches passing 0")
	check(int(legacy["specialist_bonus"]) == 0,
		"default bonus = 0")
