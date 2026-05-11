extends "res://tests/test_suite_base.gd"

## Tests for EncounterScaler (Phase 6A).
##
## Covers the 20-man-equivalent sub-unit threshold per O-A-10 / RAW
## daw_armies_recruitment.xml §units L723.


func run_all_tests() -> void:
	test_below_threshold_offers_three_options()
	test_at_threshold_runs_field_battle()
	test_size_factor_increases_man_equivalent()
	test_destroy_no_flee_eliminates_all()
	test_destroy_flees_keeps_creatures()
	if not has_failures():
		print("EncounterScaler: all tests passed.")


func test_below_threshold_offers_three_options() -> void:
	var encounter := {"creature_count": 5, "creature_size_factor": 1.0}
	var result := EncounterScaler.classify(encounter, "army_001")
	check(bool(result.get("is_sub_unit", false)), "5 creatures → sub-unit")
	var options: Array = result.get("options", [])
	check(options.size() == 3, "3 options offered, got %d" % options.size())
	check(options.has(EncounterScaler.OPTION_IGNORE), "options include ignore")
	check(options.has(EncounterScaler.OPTION_ENGAGE_WITH_PARTY), "options include engage_with_party")
	check(options.has(EncounterScaler.OPTION_DESTROY_WITH_ARMY), "options include destroy_with_army")
	check(String(result.get("recommended_default", "")) == EncounterScaler.OPTION_IGNORE,
		"default recommendation = ignore")


func test_at_threshold_runs_field_battle() -> void:
	var encounter := {"creature_count": 20, "creature_size_factor": 1.0}
	var result := EncounterScaler.classify(encounter, "army_001")
	check(not bool(result.get("is_sub_unit", true)), "20 creatures → not sub-unit")
	check(String(result.get("recommended_default", "")) == "field_battle",
		"recommends field_battle at threshold")


func test_size_factor_increases_man_equivalent() -> void:
	# 5 creatures × size_factor 4.0 = 20 man-equivalent → at threshold
	var encounter := {"creature_count": 5, "creature_size_factor": 4.0}
	var result := EncounterScaler.classify(encounter, "army_001")
	check(int(result.get("man_equivalent_count", 0)) == 20, "5×4 = 20 man-equivalent")
	check(not bool(result.get("is_sub_unit", true)), "20 man-equivalent → not sub-unit")


func test_destroy_no_flee_eliminates_all() -> void:
	var encounter := {"creature_count": 6, "flee_chance": 0.0}
	var result := EncounterScaler.resolve_destroy_outcome(
		encounter, "army_001",
		func(_count, _sides): return 50  # 50/100 > flee_chance 0.0
	)
	check(int(result.get("creatures_eliminated", 0)) == 6, "all eliminated; got %d" % result.get("creatures_eliminated", 0))
	check(int(result.get("creatures_fled", 0)) == 0, "none fled")


func test_destroy_flees_keeps_creatures() -> void:
	var encounter := {"creature_count": 6, "flee_chance": 1.0}
	var result := EncounterScaler.resolve_destroy_outcome(
		encounter, "army_001",
		func(_count, _sides): return 1  # roll 1/100 < flee_chance 1.0
	)
	check(int(result.get("creatures_fled", 0)) == 6, "all fled when flee_chance=1.0")
	check(int(result.get("creatures_eliminated", 0)) == 0, "none eliminated")
