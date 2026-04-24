extends "res://tests/test_suite_base.gd"

## Focused tests for the character-creation class selection panel.


func run_all_tests() -> void:
	test_ineligible_classes_use_dark_disabled_text()
	test_priestess_button_uses_generic_display_name()
	test_class_details_show_alignment_and_sex_restrictions()
	test_sex_and_alignment_restrictions_do_not_disable_eligible_classes()
	test_disabled_classes_are_hidden_from_roster()
	if not has_failures():
		print("ClassSelectionPanel: all tests passed.")


func test_ineligible_classes_use_dark_disabled_text() -> void:
	var panel := ClassSelectionPanel.new()
	var state := {
		"scores": {
			"STR": 12,
			"INT": 8,
			"WIS": 10,
			"DEX": 10,
			"CON": 11,
			"CHA": 9,
		},
		"class_id": "",
		"race": "human",
	}
	panel.setup(state, ClassRegistry.new())

	var fighter_btn := panel._class_buttons.get("fighter") as Button
	var mage_btn := panel._class_buttons.get("mage") as Button

	check(fighter_btn != null, "fighter button should exist in the class list")
	check(mage_btn != null, "mage button should exist in the class list")
	if fighter_btn == null or mage_btn == null:
		return

	check(not fighter_btn.disabled, "fighter should stay selectable with STR 12")
	check(not fighter_btn.has_theme_color_override("font_disabled_color"),
		"eligible class buttons should keep the default enabled button text styling")

	check(mage_btn.disabled, "mage should be blocked when INT is below the prime requisite minimum")
	check(mage_btn.has_theme_color_override("font_disabled_color"),
		"blocked class buttons should override the disabled font color for vellum contrast")
	check(mage_btn.get_theme_color("font_disabled_color", "Button")
		== ClassSelectionPanel.INELIGIBLE_CLASS_TEXT_COLOR,
		"blocked class buttons should use the shared dark disabled text color")

	panel._select_class("fighter", true)
	check(fighter_btn.has_theme_color_override("font_color"),
		"selected class buttons should still apply the gold selected-state text override")
	check(fighter_btn.get_theme_color("font_color", "Button")
		== ClassSelectionPanel.SELECTED_CLASS_TEXT_COLOR,
		"selected class buttons should keep the gold selected-state text color")
	print("  ineligible_classes_use_dark_disabled_text: OK")


func test_priestess_button_uses_generic_display_name() -> void:
	var panel := ClassSelectionPanel.new()
	panel.setup(_make_state(_elite_scores()), ClassRegistry.new())

	var priestess_btn := panel._class_buttons.get("priestess") as Button
	check(priestess_btn != null, "priestess button should exist in the class list")
	if priestess_btn != null:
		check(priestess_btn.text == "Priest/Priestess",
			"priestess button should use the generic display label in the class list")
	print("  priestess_button_uses_generic_display_name: OK")


func test_class_details_show_alignment_and_sex_restrictions() -> void:
	var panel := ClassSelectionPanel.new()
	panel.setup(_make_state(_elite_scores()), ClassRegistry.new())

	panel._select_class("bladedancer", true)
	check(_find_detail_value(panel, "Sex:") == "Female",
		"bladedancer detail panel should show the female-only restriction")

	panel._select_class("paladin", true)
	check(_find_detail_value(panel, "Alignment:") == "Lawful",
		"paladin detail panel should show the lawful-only restriction")
	print("  class_details_show_alignment_and_sex_restrictions: OK")


func test_sex_and_alignment_restrictions_do_not_disable_eligible_classes() -> void:
	var panel := ClassSelectionPanel.new()
	panel.setup(_make_state(_elite_scores()), ClassRegistry.new())

	var witch_btn := panel._class_buttons.get("witch") as Button
	var bladedancer_btn := panel._class_buttons.get("bladedancer") as Button

	check(witch_btn != null, "witch button should exist in the class list")
	check(bladedancer_btn != null, "bladedancer button should exist in the class list")
	if witch_btn == null or bladedancer_btn == null:
		return

	check(not witch_btn.disabled,
		"witch should stay selectable in step 2 when ability scores qualify")
	check(not bladedancer_btn.disabled,
		"bladedancer should stay selectable in step 2 when ability scores qualify")
	print("  sex_and_alignment_restrictions_do_not_disable_eligible_classes: OK")


func test_disabled_classes_are_hidden_from_roster() -> void:
	var panel := ClassSelectionPanel.new()
	panel.setup(_make_state(_elite_scores()), ClassRegistry.new())

	for disabled_id in ["warlock", "anti_paladin", "elven_ranger", "elven_courtier", "dwarven_delver"]:
		check(not panel._class_buttons.has(disabled_id),
			"%s is disabled and must not appear as a selectable class button" % disabled_id)
	print("  disabled_classes_are_hidden_from_roster: OK")


func _make_state(scores: Dictionary) -> Dictionary:
	return {
		"scores": scores,
		"class_id": "",
		"race": "human",
	}


func _elite_scores() -> Dictionary:
	return {
		"STR": 18,
		"INT": 18,
		"WIS": 18,
		"DEX": 18,
		"CON": 18,
		"CHA": 18,
	}


func _find_detail_value(panel: ClassSelectionPanel, label_text: String) -> String:
	for child in panel._detail_area.get_children():
		if child is HBoxContainer and child.get_child_count() >= 2:
			var key := child.get_child(0) as Label
			var value := child.get_child(1) as Label
			if key != null and value != null and key.text == label_text:
				return value.text
	return ""
