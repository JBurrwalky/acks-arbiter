extends "res://tests/test_suite_base.gd"

## Focused tests for character-creation HP roll panel state behavior.


func run_all_tests() -> void:
	test_fresh_state_is_incomplete()
	test_apply_hp_roll_marks_panel_complete()
	test_max_hp_override_uses_max_die_plus_con()
	test_max_hp_override_respects_minimum_one()
	test_zero_hp_roll_keeps_panel_incomplete()
	if not has_failures():
		print("HpRollPanel: all tests passed.")


func test_fresh_state_is_incomplete() -> void:
	var panel := _make_panel()
	var state := _make_state()

	panel.setup(state, ClassRegistry.new())

	check(not panel.is_complete(), "fresh HP panel should be incomplete before the first roll")
	check(not state.has("hp_rolled"), "fresh HP state should not seed hp_rolled before a real roll")
	check(panel._roll_button.visible, "fresh HP panel should show the roll button")
	print("  fresh_state_is_incomplete: OK")


func test_apply_hp_roll_marks_panel_complete() -> void:
	var panel := _make_panel()
	var state := _make_state()

	panel.setup(state, ClassRegistry.new())
	panel._apply_hp_roll_total(5)

	check(panel.is_complete(), "resolved HP roll should mark the panel complete")
	check(int(state.get("hp_raw_roll", 0)) == 5, "resolved HP roll should store the raw die total")
	check(int(state.get("hp_rolled", 0)) == 6,
		"fighter CON +1 should turn a raw 5 into 6 HP")
	check(not panel._roll_button.visible, "resolved HP roll should hide the initial roll button")
	print("  apply_hp_roll_marks_panel_complete: OK")


func test_max_hp_override_uses_max_die_plus_con() -> void:
	var panel := _make_panel()
	var state := _make_state({
		"class_id": "cleric",
		"scores": {"CON": 13},
	})

	panel.setup(state, ClassRegistry.new())
	panel._on_max_hp_toggled(true)

	check(panel.is_complete(), "max HP override should mark the panel complete")
	check(int(state.get("hp_raw_roll", 0)) == 6,
		"1d6 max HP override should store raw die face 6")
	check(int(state.get("hp_rolled", 0)) == 7,
		"1d6 max HP override with CON +1 should resolve to 7 HP")
	check(panel._result_label.text.contains("max 6 + CON +1 = 7"),
		"max HP explanation should show max die plus CON, got: %s" % panel._result_label.text)
	check(panel._max_hp_check.text == "Max Hit Die at Level 1 (house rule; CON still applies)",
		"checkbox text should clarify that CON still applies")
	print("  max_hp_override_uses_max_die_plus_con: OK")


func test_max_hp_override_respects_minimum_one() -> void:
	var panel := _make_panel()
	var state := _make_state({
		"class_id": "mage",
		"scores": {"CON": 3},
	})

	panel.setup(state, ClassRegistry.new())
	panel._on_max_hp_toggled(true)

	check(panel.is_complete(), "max HP override should still complete for low-CON characters")
	check(int(state.get("hp_raw_roll", 0)) == 4,
		"1d4 max HP override should store raw die face 4")
	check(int(state.get("hp_rolled", 0)) == 1,
		"1d4 max HP override with CON -3 should clamp to 1 HP")
	check(panel._result_label.text.contains("max 4 + CON -3 = 1"),
		"low-CON max HP explanation should show the clamped result, got: %s" % panel._result_label.text)
	print("  max_hp_override_respects_minimum_one: OK")


func test_zero_hp_roll_keeps_panel_incomplete() -> void:
	var panel := _make_panel()
	var state := _make_state({"hp_rolled": 4, "hp_raw_roll": 3})

	panel.setup(state, ClassRegistry.new())
	panel._apply_hp_roll_total(0)

	check(not panel.is_complete(), "zero/cancelled HP result should leave the panel incomplete")
	check(not state.has("hp_rolled"), "zero/cancelled HP result should clear rolled HP state")
	check(not state.has("hp_raw_roll"), "zero/cancelled HP result should clear the stored raw total")
	check(panel._roll_button.visible, "zero/cancelled HP result should return to the pre-roll UI")
	check(not panel._rolling, "zero/cancelled HP result should clear in-flight rolling state")
	print("  zero_hp_roll_keeps_panel_incomplete: OK")


func _make_panel() -> HpRollPanel:
	return HpRollPanel.new()


func _make_state(overrides: Dictionary = {}) -> Dictionary:
	var state := {
		"class_id": "fighter",
		"scores": {"CON": 13},
		"traded_scores": {},
		"max_hp_override": false,
		"character": null,
	}
	for key in overrides.keys():
		state[key] = overrides[key]
	return state
