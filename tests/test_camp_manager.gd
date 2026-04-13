extends "res://tests/test_suite_base.gd"

## Tests for CampManager — validates watch assignment, encounter checks,
## armed sleeper checks, and rest recovery.


func run_all_tests() -> void:
	test_validate_watch_assignment_valid()
	test_validate_watch_assignment_empty_watch()
	test_validate_watch_assignment_duplicate()
	test_validate_watch_assignment_missing_member()
	test_compute_rest_recovery()
	test_compute_rest_recovery_with_failed_sleepers()
	test_ration_consumption()
	test_town_rest()

	if not has_failures():
		print("CampManager: all %d checks passed" % test_count())


func test_validate_watch_assignment_valid() -> void:
	var assignments := [["a", "b"], ["c", "d"], ["e"]]
	var party := ["a", "b", "c", "d", "e"]
	var result := CampManager.validate_watch_assignment(assignments, party)
	check(result == "", "valid assignment should return empty string, got: %s" % result)


func test_validate_watch_assignment_empty_watch() -> void:
	var assignments := [["a", "b"], [], ["c"]]
	var party := ["a", "b", "c"]
	var result := CampManager.validate_watch_assignment(assignments, party)
	check(result != "", "empty watch should fail validation")


func test_validate_watch_assignment_duplicate() -> void:
	var assignments := [["a", "b"], ["b", "c"], ["d"]]
	var party := ["a", "b", "c", "d"]
	var result := CampManager.validate_watch_assignment(assignments, party)
	check(result != "", "duplicate assignment should fail")


func test_validate_watch_assignment_missing_member() -> void:
	var assignments := [["a"], ["b"], ["c"]]
	var party := ["a", "b", "c", "d"]
	var result := CampManager.validate_watch_assignment(assignments, party)
	check(result != "", "missing member should fail")


func test_compute_rest_recovery() -> void:
	var members := [
		{"id": "fighter1", "hp_current": 8, "hp_max": 10},
		{"id": "cleric1", "hp_current": 6, "hp_max": 6},
	]
	var recovery := CampManager.compute_rest_recovery(members)
	check(recovery.has("fighter1"), "should have fighter1 recovery")
	check(recovery.has("cleric1"), "should have cleric1 recovery")
	check(recovery["fighter1"]["hp_recovered"] == 1, "fighter should recover 1 HP")
	check(recovery["cleric1"]["hp_recovered"] == 0, "full HP cleric recovers 0")
	check(recovery["fighter1"]["spells_recovered"] == true, "spells should be recovered")


func test_compute_rest_recovery_with_failed_sleepers() -> void:
	var members := [
		{"id": "fighter1", "hp_current": 5, "hp_max": 10},
	]
	var recovery := CampManager.compute_rest_recovery(members, ["fighter1"])
	check(recovery["fighter1"]["hp_recovered"] == 0, "failed sleeper should not recover HP")
	check(recovery["fighter1"]["spells_recovered"] == false, "failed sleeper should not recover spells")


func test_ration_consumption() -> void:
	check(CampManager.compute_ration_consumption(4) == 4, "4 members = 4 rations")
	check(CampManager.compute_ration_consumption(1) == 1, "1 member = 1 ration")


func test_town_rest() -> void:
	var members := [
		{"id": "pc1", "hp_current": 3, "hp_max": 8},
	]
	var result := CampManager.resolve_town_rest(members)
	check(result.get("is_town_rest", false) == true, "should be marked as town rest")
	check(result.get("total_hours", 0) == 12, "total hours should be 12")
	check(result.get("watches", []).is_empty(), "town rest should have no watches")
	check(result.get("rations_consumed", 0) == 1, "1 member = 1 ration")
	var rec: Dictionary = result.get("rest_recovery", {})
	check(rec.has("pc1"), "should have pc1 recovery")
	check(rec["pc1"]["hp_recovered"] == 1, "should recover 1 HP")
