extends "res://tests/test_suite_base.gd"

## Unit tests for TrackingResolver (Wilderness closure Phase 5).
##
## SACRED tests against `acore_proficiencies_rules_and_catalog.xml`
## Tracking entry:
##   * Base 11+ on 1d20.
##   * Group-size +2/+4/+6/+8 (2-4 / 4-8 / 8-16 / 17+ creatures).
##   * Soft/muddy +4, hard/rocky -8.
##   * Bad lighting -4.
##   * -1 per 12 hours of good weather since trail was made.
##   * -4 per hour of rain or snow since trail was made.


# ---------------------------------------------------------------------------
# Fake DiceSystem — fixed return value
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
	test_no_proficiency_returns_empty_result()
	test_base_11_succeeds_with_no_modifiers()
	test_solo_target_no_group_bonus()
	test_group_size_2_to_4_plus_2()
	test_group_size_8_to_16_plus_6()
	test_group_size_17_plus_plus_8()
	test_soft_ground_plus_4()
	test_hard_ground_minus_8()
	test_bad_lighting_minus_4()
	test_weather_decay_calm_12h_minus_1()
	test_weather_decay_rainy_per_hour_minus_4()
	test_pick_tracker_prefers_proficient_member()
	if not has_failures():
		print("TrackingResolver: all tests passed.")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _make_tracker(with_proficiency: bool = true) -> CharacterData:
	var cd := CharacterData.new()
	cd.id = "test_phase5_tracker"
	cd.name = "Tracker"
	cd.hp_max = 10
	cd.hp_current = 10
	if with_proficiency:
		cd.proficiencies = [{"proficiency_key": "tracking", "rank": 1}]
	return cd


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_no_proficiency_returns_empty_result() -> void:
	var tracker := _make_tracker(false)
	var dice := _FixedDice.new(20)
	var r := TrackingResolver.attempt(tracker, 1, "normal", "good", 0, dice)
	check(not bool(r["succeeded"]), "ineligible tracker returns failure")
	check(int(r["roll"]) == 0, "no roll happened")


func test_base_11_succeeds_with_no_modifiers() -> void:
	var tracker := _make_tracker()
	var dice := _FixedDice.new(11)
	var r := TrackingResolver.attempt(tracker, 1, "normal", "good", 0, dice)
	check(int(r["target"]) == 11, "base target = 11")
	check(int(r["total"]) == 11, "11 + 0 = 11")
	check(bool(r["succeeded"]), "11 >= 11")


func test_solo_target_no_group_bonus() -> void:
	var tracker := _make_tracker()
	var dice := _FixedDice.new(11)
	var r := TrackingResolver.attempt(tracker, 1, "normal", "good", 0, dice)
	check(int(r["group_bonus"]) == 0, "solo target → no group bonus")


func test_group_size_2_to_4_plus_2() -> void:
	var tracker := _make_tracker()
	var dice := _FixedDice.new(9)  # 9 + 2 = 11 → success
	var r := TrackingResolver.attempt(tracker, 3, "normal", "good", 0, dice)
	check(int(r["group_bonus"]) == 2, "group 3 → +2")
	check(bool(r["succeeded"]), "9 + 2 = 11 succeeds")


func test_group_size_8_to_16_plus_6() -> void:
	var tracker := _make_tracker()
	var dice := _FixedDice.new(5)  # 5 + 6 = 11 → success
	var r := TrackingResolver.attempt(tracker, 12, "normal", "good", 0, dice)
	check(int(r["group_bonus"]) == 6, "group 12 → +6")
	check(bool(r["succeeded"]), "5 + 6 = 11 succeeds")


func test_group_size_17_plus_plus_8() -> void:
	var tracker := _make_tracker()
	var dice := _FixedDice.new(3)  # 3 + 8 = 11 → success
	var r := TrackingResolver.attempt(tracker, 25, "normal", "good", 0, dice)
	check(int(r["group_bonus"]) == 8, "group 25 → +8")
	check(bool(r["succeeded"]), "3 + 8 = 11 succeeds")


func test_soft_ground_plus_4() -> void:
	var tracker := _make_tracker()
	var dice := _FixedDice.new(7)  # 7 + 4 = 11
	var r := TrackingResolver.attempt(tracker, 1, "soft", "good", 0, dice)
	check(int(r["ground_modifier"]) == 4, "soft → +4")
	check(bool(r["succeeded"]), "7 + 4 = 11 succeeds")


func test_hard_ground_minus_8() -> void:
	var tracker := _make_tracker()
	var dice := _FixedDice.new(18)  # 18 - 8 = 10 < 11 → fail
	var r := TrackingResolver.attempt(tracker, 1, "hard", "good", 0, dice)
	check(int(r["ground_modifier"]) == -8, "hard → -8")
	check(not bool(r["succeeded"]), "18 - 8 = 10 fails")


func test_bad_lighting_minus_4() -> void:
	var tracker := _make_tracker()
	var dice := _FixedDice.new(14)  # 14 - 4 = 10 < 11 → fail
	var r := TrackingResolver.attempt(tracker, 1, "normal", "bad", 0, dice)
	check(int(r["lighting_modifier"]) == -4, "bad lighting → -4")
	check(not bool(r["succeeded"]), "14 - 4 = 10 fails")


func test_weather_decay_calm_12h_minus_1() -> void:
	# Calm/no-weather period → -1 per 12 hours. 24 hours → -2.
	var calm: WeatherStateData = null  # null → treated as good weather
	var d12 := TrackingResolver.compute_weather_decay(12.0, calm)
	check(d12 == -1, "12h calm → -1; got %d" % d12)
	var d24 := TrackingResolver.compute_weather_decay(24.0, calm)
	check(d24 == -2, "24h calm → -2; got %d" % d24)
	# Less than 12 hours → no decay (per RAW "per 12 hours" granularity).
	var d11 := TrackingResolver.compute_weather_decay(11.0, calm)
	check(d11 == 0, "11h calm → 0; got %d" % d11)


func test_weather_decay_rainy_per_hour_minus_4() -> void:
	# Rainy → -4 per hour. 1 hr → -4. 3 hr → -12.
	var rainy := WeatherStateData.new()
	rainy.atmosphere = WeatherStateData.ATMO_RAINY
	var d1 := TrackingResolver.compute_weather_decay(1.0, rainy)
	check(d1 == -4, "1h rain → -4; got %d" % d1)
	var d3 := TrackingResolver.compute_weather_decay(3.0, rainy)
	check(d3 == -12, "3h rain → -12; got %d" % d3)


func test_pick_tracker_prefers_proficient_member() -> void:
	var pd := PartyData.new()
	pd.id = "test_phase5_pick"
	var nontracker := CharacterData.new()
	nontracker.id = "pc_no"
	nontracker.name = "No Track"
	var tracker := _make_tracker()
	pd.character_data = [nontracker, tracker]
	var picked = TrackingResolver.pick_tracker(pd)
	check(picked != null and picked.id == tracker.id,
		"picks proficient member over first member")
	# Empty party / no tracker → null.
	var pd2 := PartyData.new()
	pd2.character_data = [nontracker]
	check(TrackingResolver.pick_tracker(pd2) == null,
		"no tracker → null")
