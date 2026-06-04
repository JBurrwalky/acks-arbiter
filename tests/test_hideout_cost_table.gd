extends "res://tests/test_suite_base.gd"

## Tests for HideoutCostTable — RAW `ax_thief_skill_update.xml`
## `hideout_size_and_cost` (Thief→Syndicate refactor). Pure-function; no DB.


func run_all_tests() -> void:
	test_minimum_cost_gp_all_classes()
	test_max_syndicate_all_classes()
	test_cp_conversion()
	test_unknown_class_returns_zero()
	test_is_valid_market_class()
	if not has_failures():
		print("HideoutCostTable: all tests passed.")


func test_minimum_cost_gp_all_classes() -> void:
	# market_class (INTEGER) → minimum hideout cost in gp, per RAW.
	var expected := {6: 5000, 5: 10000, 4: 20000, 3: 75000, 2: 150000, 1: 600000}
	for mc: int in expected:
		var got := HideoutCostTable.minimum_cost_gp_for_market_class(mc)
		check(got == expected[mc],
			"min gp for class %d should be %d, got %d" % [mc, expected[mc], got])


func test_max_syndicate_all_classes() -> void:
	var expected := {6: 25, 5: 50, 4: 100, 3: 375, 2: 750, 1: 3000}
	for mc: int in expected:
		var got := HideoutCostTable.max_syndicate_for_market_class(mc)
		check(got == expected[mc],
			"max syndicate for class %d should be %d, got %d" % [mc, expected[mc], got])


func test_cp_conversion() -> void:
	# Class I min = 600,000 gp = 60,000,000 cp; Class VI = 5,000 gp = 500,000 cp.
	check(HideoutCostTable.minimum_cost_cp_for_market_class(1) == 60000000,
		"Class I min cp should be 60,000,000, got %d" % HideoutCostTable.minimum_cost_cp_for_market_class(1))
	check(HideoutCostTable.minimum_cost_cp_for_market_class(6) == 500000,
		"Class VI min cp should be 500,000, got %d" % HideoutCostTable.minimum_cost_cp_for_market_class(6))


func test_unknown_class_returns_zero() -> void:
	check(HideoutCostTable.minimum_cost_gp_for_market_class(0) == 0, "unknown class → 0 gp")
	check(HideoutCostTable.max_syndicate_for_market_class(7) == 0, "unknown class → 0 max")
	check(HideoutCostTable.minimum_cost_cp_for_market_class(99) == 0, "unknown class → 0 cp")


func test_is_valid_market_class() -> void:
	for mc: int in [1, 2, 3, 4, 5, 6]:
		check(HideoutCostTable.is_valid_market_class(mc), "class %d should be valid" % mc)
	check(not HideoutCostTable.is_valid_market_class(0), "class 0 invalid")
	check(not HideoutCostTable.is_valid_market_class(7), "class 7 invalid")
