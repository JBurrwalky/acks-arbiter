extends "res://tests/test_suite_base.gd"

## Unit tests for EvasionResolver (Wilderness closure Phase 5).
##
## SACRED tests against `acore_adventures_and_encounters.xml`
## §chases_in_the_wilderness:
##   * Wilderness Evasion table by evader size (≤4 / 5-12 / 13-24 / 25+).
##   * Pursuer-ratio modifiers (≤25% / 26-75% / 76%+).
##   * 5% minimum_escape_chance (modeled as natural-20-always-succeeds).
##   * Catch-up roll: 11+ on d20, only when pursuer is faster.


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
	test_small_party_base_target_11()
	test_medium_party_base_target_14()
	test_large_party_base_target_16()
	test_huge_party_base_target_19()
	test_low_pursuer_ratio_no_bonus()
	test_mid_pursuer_ratio_bonus_3_or_4()
	test_high_pursuer_ratio_bonus_8_for_small_party()
	test_judge_modifier_passes_through()
	test_natural_20_always_succeeds_5pct_floor()
	test_catch_up_skipped_when_pursuer_not_faster()
	test_catch_up_d20_target_11()
	test_catch_up_below_11_falls_back()
	if not has_failures():
		print("EvasionResolver: all tests passed.")


# ---------------------------------------------------------------------------
# Tests — wilderness_evasion_table
# ---------------------------------------------------------------------------

func test_small_party_base_target_11() -> void:
	# RAW row 1: party of up to 4 → 11+ base.
	var r := EvasionResolver.attempt(4, 1, 0, _FixedDice.new(11))
	check(int(r["base_target"]) == 11, "≤4 evaders → 11+ base")
	check(bool(r["succeeded"]), "11 ≥ 11 succeeds")


func test_medium_party_base_target_14() -> void:
	# RAW row 2: 5-12 → 14+ base.
	var r := EvasionResolver.attempt(8, 2, 0, _FixedDice.new(14))
	check(int(r["base_target"]) == 14, "5-12 evaders → 14+ base")
	check(bool(r["succeeded"]), "14 ≥ 14 succeeds")


func test_large_party_base_target_16() -> void:
	# RAW row 3: 13-24 → 16+ base.
	var r := EvasionResolver.attempt(20, 5, 0, _FixedDice.new(15))
	check(int(r["base_target"]) == 16, "13-24 evaders → 16+ base")
	check(not bool(r["succeeded"]), "15 < 16 fails")


func test_huge_party_base_target_19() -> void:
	# RAW row 4: 25+ → 19+ base.
	var r := EvasionResolver.attempt(50, 12, 0, _FixedDice.new(18))
	check(int(r["base_target"]) == 19, "25+ evaders → 19+ base")
	check(not bool(r["succeeded"]), "18 < 19 fails")


# ---------------------------------------------------------------------------
# Tests — ratio modifiers
# ---------------------------------------------------------------------------

func test_low_pursuer_ratio_no_bonus() -> void:
	# 4 evaders, 1 pursuer = 25% → "low" band → +0 bonus.
	var r := EvasionResolver.attempt(4, 1, 0, _FixedDice.new(11))
	check(r["ratio_band"] == "low", "25% → low band")
	check(int(r["bonus"]) == 0, "low band → +0")


func test_mid_pursuer_ratio_bonus_3_or_4() -> void:
	# 4 evaders, 2 pursuers = 50% → mid (+4 on row 1).
	var r1 := EvasionResolver.attempt(4, 2, 0, _FixedDice.new(7))
	check(r1["ratio_band"] == "mid", "50% → mid")
	check(int(r1["bonus"]) == 4, "row 1 mid → +4")
	check(bool(r1["succeeded"]), "7 + 4 = 11 succeeds")
	# 8 evaders, 4 pursuers = 50% → mid on row 2 (+3).
	var r2 := EvasionResolver.attempt(8, 4, 0, _FixedDice.new(11))
	check(int(r2["bonus"]) == 3, "row 2 mid → +3")
	check(bool(r2["succeeded"]), "11 + 3 = 14 succeeds")


func test_high_pursuer_ratio_bonus_8_for_small_party() -> void:
	# 4 evaders, 5 pursuers = 125% → high band → +8 on row 1.
	var r := EvasionResolver.attempt(4, 5, 0, _FixedDice.new(3))
	check(r["ratio_band"] == "high", "125% → high")
	check(int(r["bonus"]) == 8, "row 1 high → +8")
	check(bool(r["succeeded"]), "3 + 8 = 11 succeeds")


func test_judge_modifier_passes_through() -> void:
	# +2 judge modifier (e.g. dense forest) carries the throw.
	var r := EvasionResolver.attempt(4, 1, 2, _FixedDice.new(9))
	check(int(r["judge_modifier"]) == 2, "judge mod stored")
	check(int(r["total"]) == 11, "9 + 0 + 2 = 11")
	check(bool(r["succeeded"]), "judge mod carries to target")


func test_natural_20_always_succeeds_5pct_floor() -> void:
	# 25-evader row with high target (19+) and 0 bonuses; rolling 20 alone is
	# 20 < 19+ false (actually 20 ≥ 19 so it succeeds normally). Force a case
	# where natural-20 + a NEGATIVE judge_modifier still wouldn't pass without
	# the floor — judge_mod = -10 → total 10, but the natural-20 floor flips
	# the result to true.
	var r := EvasionResolver.attempt(50, 1, -10, _FixedDice.new(20))
	check(bool(r["floor_applied"]), "natural-20 with negative modifier triggers floor")
	check(bool(r["succeeded"]), "5%% floor flips to success")


# ---------------------------------------------------------------------------
# Tests — catch_up
# ---------------------------------------------------------------------------

func test_catch_up_skipped_when_pursuer_not_faster() -> void:
	var r := EvasionResolver.catch_up(0, _FixedDice.new(20))
	check(not bool(r["eligible"]), "no advantage → ineligible")
	check(not bool(r["caught"]), "no roll → not caught")
	check(int(r["roll"]) == 0, "no roll happened")


func test_catch_up_d20_target_11() -> void:
	var r := EvasionResolver.catch_up(5, _FixedDice.new(11))
	check(bool(r["eligible"]), "advantage > 0 → eligible")
	check(int(r["target"]) == 11, "RAW target 11+")
	check(bool(r["caught"]), "11 ≥ 11 caught")


func test_catch_up_below_11_falls_back() -> void:
	var r := EvasionResolver.catch_up(5, _FixedDice.new(10))
	check(bool(r["eligible"]), "advantage > 0 → eligible")
	check(not bool(r["caught"]), "10 < 11 not caught")
