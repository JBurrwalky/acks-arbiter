extends Node

## Unit tests for DiceSystem.
##
## Tests cover: digital rolling, modifier application, expression parsing,
## manual result validation, override consumption, natural-one/max flags,
## and RollResult field population.
##
## Tests run entirely in DIGITAL mode so no player prompt or await is needed.
## Override tests manipulate GameState.dice_overrides directly (same path
## as OverrideManager.queue_dice_override).

func run_all_tests() -> void:
	test_roll_digital_d6_in_range()
	test_roll_digital_d20_in_range()
	test_roll_digital_d100_in_range()
	test_roll_digital_d3_in_range()
	test_roll_digital_d4_in_range()
	test_roll_digital_d8_in_range()
	test_roll_digital_d10_in_range()
	test_roll_digital_d12_in_range()
	test_roll_digital_multi_die_sum()
	test_roll_digital_positive_modifier()
	test_roll_digital_negative_modifier()
	test_roll_digital_zero_modifier()
	test_roll_result_fields_populated()
	test_natural_one_flag()
	test_natural_max_flag()
	test_natural_flags_false_on_multi_die()
	test_override_consumed_on_matching_type()
	test_override_not_consumed_on_different_type()
	test_override_single_use()
	test_override_modifies_modified_total_only()
	test_override_was_overridden_flag()
	test_expression_parse_simple()
	test_expression_parse_with_positive_modifier()
	test_expression_parse_with_negative_modifier()
	test_expression_parse_invalid_returns_zeroed_result()
	test_is_valid_manual_result_in_range()
	test_is_valid_manual_result_at_min()
	test_is_valid_manual_result_at_max()
	test_is_valid_manual_result_below_min()
	test_is_valid_manual_result_above_max()
	# player_roll() async path tested manually — see note at bottom of file
	print("DiceSystemTests: all tests passed")


# ---------------------------------------------------------------------------
# roll_digital — die range
# ---------------------------------------------------------------------------

func test_roll_digital_d6_in_range() -> void:
	for i in 20:
		var r := DiceSystem.roll_digital(6)
		assert(r.modified_total >= 1 and r.modified_total <= 6,
			"d6 result out of range: %d" % r.modified_total)

func test_roll_digital_d20_in_range() -> void:
	for i in 20:
		var r := DiceSystem.roll_digital(20)
		assert(r.modified_total >= 1 and r.modified_total <= 20,
			"d20 result out of range: %d" % r.modified_total)

func test_roll_digital_d100_in_range() -> void:
	for i in 20:
		var r := DiceSystem.roll_digital(100)
		assert(r.modified_total >= 1 and r.modified_total <= 100,
			"d100 result out of range: %d" % r.modified_total)

func test_roll_digital_d3_in_range() -> void:
	for i in 20:
		var r := DiceSystem.roll_digital(3)
		assert(r.modified_total >= 1 and r.modified_total <= 3,
			"d3 result out of range: %d" % r.modified_total)

func test_roll_digital_d4_in_range() -> void:
	for i in 20:
		var r := DiceSystem.roll_digital(4)
		assert(r.modified_total >= 1 and r.modified_total <= 4,
			"d4 result out of range: %d" % r.modified_total)

func test_roll_digital_d8_in_range() -> void:
	for i in 20:
		var r := DiceSystem.roll_digital(8)
		assert(r.modified_total >= 1 and r.modified_total <= 8,
			"d8 result out of range: %d" % r.modified_total)

func test_roll_digital_d10_in_range() -> void:
	for i in 20:
		var r := DiceSystem.roll_digital(10)
		assert(r.modified_total >= 1 and r.modified_total <= 10,
			"d10 result out of range: %d" % r.modified_total)

func test_roll_digital_d12_in_range() -> void:
	for i in 20:
		var r := DiceSystem.roll_digital(12)
		assert(r.modified_total >= 1 and r.modified_total <= 12,
			"d12 result out of range: %d" % r.modified_total)


# ---------------------------------------------------------------------------
# roll_digital — multi-die and modifiers
# ---------------------------------------------------------------------------

func test_roll_digital_multi_die_sum() -> void:
	for i in 20:
		var r := DiceSystem.roll_digital(6, 3)
		assert(r.individual_results.size() == 3,
			"3d6 should have 3 individual results, got %d" % r.individual_results.size())
		assert(r.modified_total >= 3 and r.modified_total <= 18,
			"3d6 total out of range: %d" % r.modified_total)
		var computed_raw := 0
		for v in r.individual_results:
			computed_raw += v
		assert(r.raw_total == computed_raw,
			"raw_total mismatch: expected %d, got %d" % [computed_raw, r.raw_total])

func test_roll_digital_positive_modifier() -> void:
	for i in 20:
		var r := DiceSystem.roll_digital(6, 1, 2)
		assert(r.modified_total == r.raw_total + 2,
			"modifier +2 not applied: raw=%d modified=%d" % [r.raw_total, r.modified_total])
		assert(r.modified_total >= 3 and r.modified_total <= 8,
			"1d6+2 total out of range: %d" % r.modified_total)

func test_roll_digital_negative_modifier() -> void:
	for i in 20:
		var r := DiceSystem.roll_digital(8, 1, -1)
		assert(r.modified_total == r.raw_total - 1,
			"modifier -1 not applied: raw=%d modified=%d" % [r.raw_total, r.modified_total])

func test_roll_digital_zero_modifier() -> void:
	var r := DiceSystem.roll_digital(6, 1, 0)
	assert(r.modified_total == r.raw_total,
		"zero modifier changed total: raw=%d modified=%d" % [r.raw_total, r.modified_total])


# ---------------------------------------------------------------------------
# RollResult field population
# ---------------------------------------------------------------------------

func test_roll_result_fields_populated() -> void:
	var r := DiceSystem.roll_digital(20, 1, 3, "attack_throw")
	assert(r.roll_type == "attack_throw", "roll_type not set")
	assert(r.sides == 20, "sides not set")
	assert(r.count == 1, "count not set")
	assert(r.modifier == 3, "modifier not set")
	assert(r.individual_results.size() == 1, "individual_results should have 1 entry")
	assert(r.raw_total >= 1 and r.raw_total <= 20, "raw_total out of range")
	assert(r.modified_total == r.raw_total + 3, "modified_total wrong")
	assert(not r.was_overridden, "was_overridden should be false")
	assert(not r.was_player_entered, "was_player_entered should be false")


# ---------------------------------------------------------------------------
# Natural one / natural max flags
# ---------------------------------------------------------------------------

func test_natural_one_flag() -> void:
	# Force a 1 via override so we can test the flag deterministically
	GameState.dice_overrides["test_nat_one"] = 1  # override = modified_total; modifier=0
	var r := DiceSystem.roll_digital(20, 1, 0, "test_nat_one")
	assert(r.natural_one, "natural_one should be true when result is 1")
	assert(not r.natural_max, "natural_max should be false when result is 1")

func test_natural_max_flag() -> void:
	GameState.dice_overrides["test_nat_max"] = 20  # d20, no modifier
	var r := DiceSystem.roll_digital(20, 1, 0, "test_nat_max")
	assert(r.natural_max, "natural_max should be true when d20 result is 20")
	assert(not r.natural_one, "natural_one should be false when result is 20")

func test_natural_flags_false_on_multi_die() -> void:
	# Multi-die rolls never set natural_one / natural_max regardless of total
	for i in 20:
		var r := DiceSystem.roll_digital(6, 3)
		assert(not r.natural_one, "natural_one should always be false for 3d6")
		assert(not r.natural_max, "natural_max should always be false for 3d6")


# ---------------------------------------------------------------------------
# Override consumption
# ---------------------------------------------------------------------------

func test_override_consumed_on_matching_type() -> void:
	GameState.dice_overrides["damage_roll"] = 7
	var r := DiceSystem.roll_digital(6, 2, 0, "damage_roll")
	assert(r.was_overridden, "was_overridden should be true")
	assert(r.modified_total == 7, "override forced value not used: got %d" % r.modified_total)
	assert(not GameState.dice_overrides.has("damage_roll"),
		"override not cleared after consumption")

func test_override_not_consumed_on_different_type() -> void:
	GameState.dice_overrides["morale_check"] = 5
	var _r := DiceSystem.roll_digital(20, 1, 0, "attack_throw")
	assert(GameState.dice_overrides.has("morale_check"),
		"morale_check override should remain — different roll type was called")
	# Clean up
	GameState.dice_overrides.erase("morale_check")

func test_override_single_use() -> void:
	GameState.dice_overrides["initiative"] = 4
	var r1 := DiceSystem.roll_digital(6, 1, 0, "initiative")
	assert(r1.was_overridden, "first roll should use override")
	var r2 := DiceSystem.roll_digital(6, 1, 0, "initiative")
	assert(not r2.was_overridden, "second roll should NOT use override — already consumed")

func test_override_modifies_modified_total_only() -> void:
	# Override value is the final modified_total; raw_total = override - modifier
	GameState.dice_overrides["saving_throw_poison"] = 15
	var r := DiceSystem.roll_digital(20, 1, 2, "saving_throw_poison")
	assert(r.modified_total == 15,
		"modified_total should be the forced value 15, got %d" % r.modified_total)
	assert(r.raw_total == 13,
		"raw_total should be 15-2=13, got %d" % r.raw_total)

func test_override_was_overridden_flag() -> void:
	GameState.dice_overrides["reaction_roll"] = 8
	var r := DiceSystem.roll_digital(6, 2, 0, "reaction_roll")
	assert(r.was_overridden, "was_overridden must be true for forced roll")
	assert(not r.was_player_entered, "was_player_entered must be false for override")


# ---------------------------------------------------------------------------
# Expression parsing
# ---------------------------------------------------------------------------

func test_expression_parse_simple() -> void:
	var r := DiceSystem.roll_expression("2d6")
	assert(r.count == 2, "2d6 count should be 2, got %d" % r.count)
	assert(r.sides == 6, "2d6 sides should be 6, got %d" % r.sides)
	assert(r.modifier == 0, "2d6 modifier should be 0")
	assert(r.modified_total >= 2 and r.modified_total <= 12,
		"2d6 total out of range: %d" % r.modified_total)

func test_expression_parse_with_positive_modifier() -> void:
	var r := DiceSystem.roll_expression("1d8+3")
	assert(r.modifier == 3, "1d8+3 modifier should be 3, got %d" % r.modifier)
	assert(r.modified_total >= 4 and r.modified_total <= 11,
		"1d8+3 total out of range: %d" % r.modified_total)

func test_expression_parse_with_negative_modifier() -> void:
	var r := DiceSystem.roll_expression("3d6-2")
	assert(r.modifier == -2, "3d6-2 modifier should be -2, got %d" % r.modifier)
	assert(r.modified_total >= 1 and r.modified_total <= 16,
		"3d6-2 total out of range: %d" % r.modified_total)

func test_expression_parse_invalid_returns_zeroed_result() -> void:
	var r := DiceSystem.roll_expression("notadice")
	assert(r.modified_total == 0,
		"invalid expression should return zeroed result, got %d" % r.modified_total)
	assert(r.sides == 6, "invalid expression zeroed result should have default sides=6")


# ---------------------------------------------------------------------------
# is_valid_manual_result
# ---------------------------------------------------------------------------

func test_is_valid_manual_result_in_range() -> void:
	assert(DiceSystem.is_valid_manual_result(10, 20, 1),
		"10 should be valid for 1d20")

func test_is_valid_manual_result_at_min() -> void:
	assert(DiceSystem.is_valid_manual_result(1, 6, 1),
		"1 should be valid for 1d6 (minimum)")

func test_is_valid_manual_result_at_max() -> void:
	assert(DiceSystem.is_valid_manual_result(12, 6, 2),
		"12 should be valid for 2d6 (maximum)")

func test_is_valid_manual_result_below_min() -> void:
	assert(not DiceSystem.is_valid_manual_result(0, 6, 1),
		"0 should be invalid for 1d6 (below minimum of 1)")

func test_is_valid_manual_result_above_max() -> void:
	assert(not DiceSystem.is_valid_manual_result(13, 6, 2),
		"13 should be invalid for 2d6 (above maximum of 12)")


# ---------------------------------------------------------------------------
# NOTE: player_roll() async path
# ---------------------------------------------------------------------------
# player_roll() contains `await` in its body, making it a GDScript coroutine.
# GDScript requires `await` at every call site — even the DIGITAL branch that
# never actually suspends. A synchronous test runner cannot call coroutines.
#
# The player_roll() / DicePrompt integration is verified manually:
#   1. Set GameState.dice_mode = DiceMode.HYBRID in main_scene.gd _ready()
#   2. Call: var r := await DiceSystem.player_roll(20, 1, 2, "attack_throw", "Test")
#   3. Confirm DicePrompt appears, "Roll Dice" and manual entry both resolve correctly.
#
# All underlying logic (override consumption, modifier application, RollResult fields)
# is already covered by the roll_digital() tests above, which share the same private
# _do_roll(), _build_overridden_result(), and _build_prompted_result() helpers.
