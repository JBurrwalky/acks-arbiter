extends "res://tests/test_suite_base.gd"

## Focused tests for the character-creation class selection panel.


func run_all_tests() -> void:
	test_ineligible_classes_use_dark_disabled_text()
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
