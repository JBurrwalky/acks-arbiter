extends "res://tests/test_suite_base.gd"

## Unit tests for the insufficient-stronghold morale tier.
##
## RAW: `acore_axioms_strongholds_and_domains.xml` §insufficient_stronghold L452-456:
##   * stronghold_value ≥ ½ minimum  → base morale -1
##   * stronghold_value ≥ ¼ minimum  → base morale -2
##   * stronghold_value <  ¼ minimum → base morale -3
##   * stronghold_value ≥ minimum    → no penalty
##
## Verified by holding all OTHER inputs constant (level 1 / 0 income → +1
## personal authority, civilized, neutral/neutral, no Leadership). The diff
## from baseline +1 isolates the stronghold contribution.


const MINIMUM_GP := 32000
const BASELINE_BASE_MORALE := 1


func run_all_tests() -> void:
	test_at_minimum_no_penalty()
	test_above_minimum_no_penalty()
	test_at_half_minimum_minus_one()
	test_just_above_half_minimum_minus_one()
	test_just_below_half_minimum_minus_two()
	test_at_quarter_minimum_minus_two()
	test_just_below_quarter_minimum_minus_three()
	test_zero_value_minus_three()
	if not has_failures():
		print("InsufficientStrongholdMorale: all tests passed.")


func _morale_at_value(value: int) -> int:
	var domain := {"territory_type": "civilized", "alignment": "neutral"}
	var ruler := {"cha_modifier": 0, "level": 1,
		"has_leadership_proficiency": false, "alignment": "neutral"}
	return DomainMoraleResolver.resolve_base_morale(domain, ruler, 0, value, MINIMUM_GP, 0)


func test_at_minimum_no_penalty() -> void:
	var b := _morale_at_value(MINIMUM_GP)
	check(b == BASELINE_BASE_MORALE, "at minimum: no penalty, expected %d, got %d" % [BASELINE_BASE_MORALE, b])


func test_above_minimum_no_penalty() -> void:
	var b := _morale_at_value(MINIMUM_GP + 1)
	check(b == BASELINE_BASE_MORALE, "above minimum: no penalty, got %d" % b)


func test_at_half_minimum_minus_one() -> void:
	var b := _morale_at_value(MINIMUM_GP / 2)
	check(b == BASELINE_BASE_MORALE - 1, "exactly ½ minimum: -1, got %d" % b)


func test_just_above_half_minimum_minus_one() -> void:
	var b := _morale_at_value((MINIMUM_GP / 2) + 1)
	check(b == BASELINE_BASE_MORALE - 1, "just above ½: still -1, got %d" % b)


func test_just_below_half_minimum_minus_two() -> void:
	var b := _morale_at_value((MINIMUM_GP / 2) - 1)
	check(b == BASELINE_BASE_MORALE - 2, "just below ½: -2, got %d" % b)


func test_at_quarter_minimum_minus_two() -> void:
	var b := _morale_at_value(MINIMUM_GP / 4)
	check(b == BASELINE_BASE_MORALE - 2, "exactly ¼ minimum: -2, got %d" % b)


func test_just_below_quarter_minimum_minus_three() -> void:
	var b := _morale_at_value((MINIMUM_GP / 4) - 1)
	check(b == BASELINE_BASE_MORALE - 3, "just below ¼: -3, got %d" % b)


func test_zero_value_minus_three() -> void:
	var b := _morale_at_value(0)
	check(b == BASELINE_BASE_MORALE - 3, "value 0: -3, got %d" % b)
