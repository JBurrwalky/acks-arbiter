extends "res://tests/test_suite_base.gd"

## Tests for DayBudgetManager — validates slot management, validation,
## travel estimation, and serialization.


func run_all_tests() -> void:
	test_default_plan()
	test_set_and_get_slot()
	test_validate_ok()
	test_validate_not_enough_rest()
	test_count_slots()
	test_travel_estimation()
	test_encounter_checks()
	test_serialization()

	if not has_failures():
		print("DayBudgetManager: all %d checks passed" % test_count())


func test_default_plan() -> void:
	var budget := DayBudgetManager.new()
	check(budget.slots.size() == 8, "default plan should have 8 slots")
	check(budget.count_slots(DayBudgetManager.SlotType.MARCH) == 4, "default has 4 march")
	check(budget.count_slots(DayBudgetManager.SlotType.EXPLORE) == 2, "default has 2 explore")
	check(budget.count_slots(DayBudgetManager.SlotType.REST) == 2, "default has 2 rest")


func test_set_and_get_slot() -> void:
	var budget := DayBudgetManager.new()
	budget.set_slot(0, DayBudgetManager.SlotType.FORAGE)
	check(budget.get_slot(0) == DayBudgetManager.SlotType.FORAGE, "slot 0 should be FORAGE")
	# Out of bounds.
	budget.set_slot(-1, DayBudgetManager.SlotType.MARCH)
	budget.set_slot(99, DayBudgetManager.SlotType.MARCH)
	check(budget.get_slot(-1) == DayBudgetManager.SlotType.FREE, "out of bounds returns FREE")


func test_validate_ok() -> void:
	var budget := DayBudgetManager.new()
	var error := budget.validate()
	check(error == "", "default plan should validate, got: %s" % error)


func test_validate_not_enough_rest() -> void:
	var budget := DayBudgetManager.new()
	# Replace all REST with MARCH.
	for i in range(8):
		budget.set_slot(i, DayBudgetManager.SlotType.MARCH)
	var error := budget.validate()
	check(error != "", "no rest slots should fail validation")


func test_count_slots() -> void:
	var budget := DayBudgetManager.new()
	check(budget.count_slots(DayBudgetManager.SlotType.MARCH) == 4, "4 march slots")
	budget.set_slot(0, DayBudgetManager.SlotType.REST)
	check(budget.count_slots(DayBudgetManager.SlotType.MARCH) == 3, "3 march after change")
	check(budget.count_slots(DayBudgetManager.SlotType.REST) == 3, "3 rest after change")


func test_travel_estimation() -> void:
	var budget := DayBudgetManager.new()
	# 4 march slots out of 8 = half the daily rate.
	var miles := budget.estimate_travel_distance(24.0)
	check(absf(miles - 12.0) < 0.01, "4 march slots = 12 miles at 24 mi/day, got %f" % miles)


func test_encounter_checks() -> void:
	var budget := DayBudgetManager.new()
	# 4 march + 2 explore = 6 encounter checks.
	check(budget.estimate_encounter_checks() == 6, "should be 6 encounter checks")


func test_serialization() -> void:
	var budget := DayBudgetManager.new()
	budget.set_slot(0, DayBudgetManager.SlotType.HUNT)
	var arr := budget.to_array()
	check(arr.size() == 8, "serialized array should have 8 elements")
	check(arr[0] == DayBudgetManager.SlotType.HUNT, "slot 0 should be HUNT in array")

	var budget2 := DayBudgetManager.new()
	budget2.from_array(arr)
	check(budget2.get_slot(0) == DayBudgetManager.SlotType.HUNT, "deserialized slot 0 should be HUNT")
	check(budget2.slots.size() == 8, "deserialized should have 8 slots")
