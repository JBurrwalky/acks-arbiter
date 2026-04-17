extends "res://tests/test_suite_base.gd"

## Focused tests for the character-creation proficiency selection panel.


func run_all_tests() -> void:
	test_available_click_populates_detail_box()
	test_selected_click_populates_detail_box()
	test_compound_key_click_uses_base_description()
	test_detail_selection_survives_refresh()
	test_gambling_can_rank_up_during_character_creation()
	if not has_failures():
		print("ProficiencySelectionPanel: all tests passed.")


func test_available_click_populates_detail_box() -> void:
	var panel := ProficiencySelectionPanel.new()
	var state := _make_state("fighter")
	panel.setup(state, ClassRegistry.new(), ProficiencyRegistry.new(SpecializationRegistry.new()))

	panel._on_available_proficiency_clicked("healing")

	check(panel._detail_title_label.text == "Healing",
		"clicking an available proficiency should show its display name in the detail pane")
	check(panel._detail_body_edit.text.contains("especially skilled at treating wounds"),
		"clicking an available proficiency should show imported long-form rules text")
	print("  available_click_populates_detail_box: OK")


func test_selected_click_populates_detail_box() -> void:
	var panel := ProficiencySelectionPanel.new()
	var state := _make_state("cleric")
	state["proficiencies"] = [
		{
			"proficiency_key": "knowledge",
			"rank": 1,
			"slot_type": "class",
			"selections_count": 1,
			"specialization": "history",
		},
	]
	panel.setup(state, ClassRegistry.new(), ProficiencyRegistry.new(SpecializationRegistry.new()))

	panel._on_selected_proficiency_clicked("knowledge", 1, "history")

	check(panel._detail_title_label.text == "Knowledge (History)",
		"clicking a selected specialization should show the specialized display name")
	check(panel._detail_body_edit.text.contains("specialized study of a particular field"),
		"selected proficiency clicks should populate the detail pane")
	print("  selected_click_populates_detail_box: OK")


func test_compound_key_click_uses_base_description() -> void:
	var panel := ProficiencySelectionPanel.new()
	var state := _make_state("cleric")
	panel.setup(state, ClassRegistry.new(), ProficiencyRegistry.new(SpecializationRegistry.new()))

	panel._on_available_proficiency_clicked("knowledge_history")

	check(panel._detail_title_label.text == "Knowledge (History)",
		"compound-key available clicks should show the locked specialization in the title")
	check(panel._detail_body_edit.text.contains("specialized study of a particular field"),
		"compound-key available clicks should use the base proficiency description")
	print("  compound_key_click_uses_base_description: OK")


func test_detail_selection_survives_refresh() -> void:
	var panel := ProficiencySelectionPanel.new()
	var state := _make_state("fighter")
	panel.setup(state, ClassRegistry.new(), ProficiencyRegistry.new(SpecializationRegistry.new()))

	panel._on_available_proficiency_clicked("healing")
	panel._refresh_all()

	check(panel._detail_title_label.text == "Healing",
		"refreshing the panel should not clear the inspected proficiency title")
	check(panel._detail_body_edit.text.contains("especially skilled at treating wounds"),
		"refreshing the panel should preserve the inspected proficiency description")
	print("  detail_selection_survives_refresh: OK")


func test_gambling_can_rank_up_during_character_creation() -> void:
	var panel := ProficiencySelectionPanel.new()
	var state := _make_state("fighter")
	state["scores"]["INT"] = 13
	state["proficiencies"] = [
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
	]
	panel.setup(state, ClassRegistry.new(), ProficiencyRegistry.new(SpecializationRegistry.new()))

	panel._tab_bar.current_tab = 1
	panel._on_add_proficiency("gambling", "general")

	var profs: Array = state.get("proficiencies", [])
	check(profs.size() == 3, "ranking up gambling should not add a second gambling record")
	check(int(profs[1].get("rank", 0)) == 2, "gambling should advance to rank 2 during character creation")
	check(int(profs[1].get("selections_count", 0)) == 2,
		"gambling selections_count should advance to 2 during character creation")
	print("  gambling_can_rank_up_during_character_creation: OK")


func _make_state(class_id: String) -> Dictionary:
	return {
		"class_id": class_id,
		"scores": {
			"STR": 12,
			"INT": 10,
			"WIS": 10,
			"DEX": 10,
			"CON": 11,
			"CHA": 9,
		},
		"traded_scores": {},
		"proficiencies": [],
		"bonus_proficiencies": [],
	}
