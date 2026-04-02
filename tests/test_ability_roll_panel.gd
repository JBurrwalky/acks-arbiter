extends "res://tests/test_suite_base.gd"

## Focused tests for the character creation ability-roll panel state behavior.


func run_all_tests() -> void:
	test_selection_updates_active_scores()
	test_setup_restores_selected_array()
	if not has_failures():
		print("AbilityRollPanel: all tests passed.")


func test_selection_updates_active_scores() -> void:
	var panel := AbilityRollPanel.new()
	var state := {
		"score_options": [
			{"STR": 9, "INT": 10, "WIS": 11, "DEX": 12, "CON": 13, "CHA": 14},
			{"STR": 15, "INT": 14, "WIS": 13, "DEX": 12, "CON": 11, "CHA": 10},
		],
		"selected_score_index": 0,
		"scores": {"STR": 9, "INT": 10, "WIS": 11, "DEX": 12, "CON": 13, "CHA": 14},
		"traded_scores": {"STR": 10},
	}
	panel.setup(state, CharacterGenerator.new(ClassRegistry.new(), PowerRegistry.new()))

	panel.select_score_option(1)

	check(int(state["selected_score_index"]) == 1, "selected_score_index should update to 1")
	check(int(state["scores"]["STR"]) == 15, "selected scores should switch to the chosen array")
	check(int(state["scores"]["CHA"]) == 10, "selected scores should copy the chosen array")
	check((state["traded_scores"] as Dictionary).is_empty(),
		"changing arrays should clear traded_scores")
	print("  selection_updates_active_scores: OK")


func test_setup_restores_selected_array() -> void:
	var panel := AbilityRollPanel.new()
	var state := {
		"score_options": [
			{"STR": 8, "INT": 9, "WIS": 10, "DEX": 11, "CON": 12, "CHA": 13},
			{"STR": 13, "INT": 12, "WIS": 11, "DEX": 10, "CON": 9, "CHA": 8},
		],
		"selected_score_index": 1,
		"scores": {"STR": 13, "INT": 12, "WIS": 11, "DEX": 10, "CON": 9, "CHA": 8},
		"traded_scores": {},
	}
	panel.setup(state, CharacterGenerator.new(ClassRegistry.new(), PowerRegistry.new()))

	check(panel.is_complete(), "panel should be complete when a score array has been selected")
	check(int(state["scores"]["INT"]) == 12, "setup should preserve the selected score array")
	check(int(state["selected_score_index"]) == 1, "setup should preserve selected_score_index")
	print("  setup_restores_selected_array: OK")
