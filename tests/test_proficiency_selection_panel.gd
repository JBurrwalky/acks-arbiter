extends "res://tests/test_suite_base.gd"

## Focused tests for the character-creation proficiency selection panel.


func run_all_tests() -> void:
	test_gambling_can_rank_up_during_character_creation()
	if not has_failures():
		print("ProficiencySelectionPanel: all tests passed.")


func test_gambling_can_rank_up_during_character_creation() -> void:
	var panel := ProficiencySelectionPanel.new()
	var state := {
		"class_id": "fighter",
		"scores": {
			"STR": 12,
			"INT": 13,
			"WIS": 10,
			"DEX": 10,
			"CON": 11,
			"CHA": 9,
		},
		"traded_scores": {},
		"proficiencies": [
			{
				"proficiency_key": "adventuring",
				"rank": 1,
				"slot_type": "general",
				"selections_count": 1,
				"specialization": "",
			},
			{
				"proficiency_key": "gambling",
				"rank": 1,
				"slot_type": "general",
				"selections_count": 1,
				"specialization": "",
			},
			{
				"proficiency_key": "command",
				"rank": 1,
				"slot_type": "class",
				"selections_count": 1,
				"specialization": "",
			},
		],
	}
	panel.setup(state, ClassRegistry.new(), ProficiencyRegistry.new(SpecializationRegistry.new()))

	panel._tab_bar.current_tab = 1
	panel._on_add_proficiency("gambling", "general")

	var profs: Array = state.get("proficiencies", [])
	check(profs.size() == 3, "ranking up gambling should not add a second gambling record")
	check(int(profs[1].get("rank", 0)) == 2, "gambling should advance to rank 2 during character creation")
	check(int(profs[1].get("selections_count", 0)) == 2,
		"gambling selections_count should advance to 2 during character creation")
	print("  gambling_can_rank_up_during_character_creation: OK")
