extends "res://tests/test_suite_base.gd"

## Focused tests for character-creation HP roll panel state behavior.


func run_all_tests() -> void:
	test_fresh_state_is_incomplete()
	test_apply_hp_roll_marks_panel_complete()
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
