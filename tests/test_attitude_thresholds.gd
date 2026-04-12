extends "res://tests/test_suite_base.gd"

## Phase G-1: Attitude score-to-tier mapping and reaction-modifier table.


func run_all_tests() -> void:
	test_score_to_tier_boundaries()
	test_score_to_tier_extremes()
	test_tier_to_modifier()
	test_shift_tier_clamps()
	test_clamp_score()
	if not has_failures():
		print("Attitude: all tests passed.")


func test_score_to_tier_boundaries() -> void:
	# Sacred thresholds: -60 hostile, -20 unfriendly, 19 neutral, 59 indifferent, 60 friendly.
	check(Attitude.score_to_tier(-100) == Attitude.HOSTILE, "min score = hostile")
	check(Attitude.score_to_tier(-60) == Attitude.HOSTILE, "-60 = hostile (top of band)")
	check(Attitude.score_to_tier(-59) == Attitude.UNFRIENDLY, "-59 = unfriendly (start)")
	check(Attitude.score_to_tier(-20) == Attitude.UNFRIENDLY, "-20 = unfriendly (top)")
	check(Attitude.score_to_tier(-19) == Attitude.NEUTRAL, "-19 = neutral (start)")
	check(Attitude.score_to_tier(0) == Attitude.NEUTRAL, "0 = neutral")
	check(Attitude.score_to_tier(19) == Attitude.NEUTRAL, "19 = neutral (top)")
	check(Attitude.score_to_tier(20) == Attitude.INDIFFERENT, "20 = indifferent (start)")
	check(Attitude.score_to_tier(59) == Attitude.INDIFFERENT, "59 = indifferent (top)")
	check(Attitude.score_to_tier(60) == Attitude.FRIENDLY, "60 = friendly (start)")
	check(Attitude.score_to_tier(100) == Attitude.FRIENDLY, "max score = friendly")


func test_score_to_tier_extremes() -> void:
	check(Attitude.score_to_tier(-9999) == Attitude.HOSTILE, "extreme negative still hostile")
	check(Attitude.score_to_tier(9999) == Attitude.FRIENDLY, "extreme positive still friendly")


func test_tier_to_modifier() -> void:
	check(Attitude.tier_to_modifier(Attitude.HOSTILE) == -2, "hostile -> -2")
	check(Attitude.tier_to_modifier(Attitude.UNFRIENDLY) == -1, "unfriendly -> -1")
	check(Attitude.tier_to_modifier(Attitude.NEUTRAL) == 0, "neutral -> 0")
	check(Attitude.tier_to_modifier(Attitude.INDIFFERENT) == 1, "indifferent -> +1")
	check(Attitude.tier_to_modifier(Attitude.FRIENDLY) == 2, "friendly -> +2")
	check(Attitude.tier_to_modifier(Attitude.FEARFUL) == 1, "fearful -> +1 (intim variant)")
	check(Attitude.tier_to_modifier(Attitude.COWED) == 2, "cowed -> +2 (intim variant)")


func test_shift_tier_clamps() -> void:
	check(Attitude.shift_tier(Attitude.NEUTRAL, 1) == Attitude.INDIFFERENT, "neutral +1")
	check(Attitude.shift_tier(Attitude.NEUTRAL, -1) == Attitude.UNFRIENDLY, "neutral -1")
	check(Attitude.shift_tier(Attitude.NEUTRAL, 2) == Attitude.FRIENDLY, "neutral +2")
	check(Attitude.shift_tier(Attitude.HOSTILE, -5) == Attitude.HOSTILE, "hostile clamps low")
	check(Attitude.shift_tier(Attitude.FRIENDLY, 5) == Attitude.FRIENDLY, "friendly clamps high")
	check(Attitude.shift_tier(Attitude.UNFRIENDLY, 2) == Attitude.INDIFFERENT, "unfriendly +2")


func test_clamp_score() -> void:
	check(Attitude.clamp_score(150) == 100, "clamp positive")
	check(Attitude.clamp_score(-150) == -100, "clamp negative")
	check(Attitude.clamp_score(50) == 50, "in-band passthrough")
