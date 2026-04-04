extends "res://tests/test_suite_base.gd"

## Focused tests for the inline level-up proficiency picker.

const LEVEL_UP_PROFICIENCY_PICKER := preload("res://scenes/ui/character_sheet/tabs/level_up_proficiency_picker.gd")


func run_all_tests() -> void:
	test_rank_up_existing_general_proficiency()
	test_rank_up_gambling_to_project_cap()
	test_select_specialized_general_proficiency()
	if not has_failures():
		print("LevelUpProficiencyPicker: all tests passed.")


func test_rank_up_existing_general_proficiency() -> void:
	var picker = LEVEL_UP_PROFICIENCY_PICKER.new()
	var prof_registry := ProficiencyRegistry.new(SpecializationRegistry.new())
	var existing := [
		{
			"proficiency_key": "healing",
			"rank": 1,
			"slot_type": "general",
			"selections_count": 1,
			"specialization": "",
		},
	]
	picker.setup(
		"fighter",
		existing,
		0,
		1,
		ClassRegistry.new(),
		prof_registry
	)

	picker._on_add_proficiency("healing", "general")

	var final_profs: Array = picker.get_final_proficiencies()
	check(picker.is_complete(), "picker should be complete after spending the pending general slot")
	check(final_profs.size() == 1, "healing rank-up should not add a second record")
	check(int(final_profs[0].get("rank", 0)) == 2, "healing should advance to rank 2")
	check(int(final_profs[0].get("selections_count", 0)) == 2, "healing selections_count should advance to 2")
	print("  rank_up_existing_general_proficiency: OK")


func test_rank_up_gambling_to_project_cap() -> void:
	var picker = LEVEL_UP_PROFICIENCY_PICKER.new()
	var prof_registry := ProficiencyRegistry.new(SpecializationRegistry.new())
	var existing := [
		{
			"proficiency_key": "gambling",
			"rank": 1,
			"slot_type": "general",
			"selections_count": 1,
			"specialization": "",
		},
	]
	picker.setup(
		"fighter",
		existing,
		0,
		4,
		ClassRegistry.new(),
		prof_registry
	)

	for _i in range(4):
		picker._on_add_proficiency("gambling", "general")
	picker._on_add_proficiency("gambling", "general")

	var final_profs: Array = picker.get_final_proficiencies()
	check(picker.is_complete(), "picker should be complete after spending four pending gambling ranks")
	check(final_profs.size() == 1, "gambling rank-ups should stay on a single record")
	check(int(final_profs[0].get("rank", 0)) == 5, "gambling should stop at rank 5")
	check(int(final_profs[0].get("selections_count", 0)) == 5, "gambling selections_count should stop at 5")
	print("  rank_up_gambling_to_project_cap: OK")


func test_select_specialized_general_proficiency() -> void:
	var picker = LEVEL_UP_PROFICIENCY_PICKER.new()
	var prof_registry := ProficiencyRegistry.new(SpecializationRegistry.new())
	picker.setup(
		"fighter",
		[],
		0,
		1,
		ClassRegistry.new(),
		prof_registry
	)

	picker._on_add_proficiency("language", "general")
	picker._on_specialization_selected("elvish")

	var final_profs: Array = picker.get_final_proficiencies()
	check(picker.is_complete(), "picker should be complete after choosing a language specialization")
	check(final_profs.size() == 1, "expected one new language proficiency record")
	check(final_profs[0].get("proficiency_key", "") == "language", "record should store the base language key")
	check(final_profs[0].get("specialization", "") == "elvish", "record should store the chosen specialization")
	print("  select_specialized_general_proficiency: OK")
