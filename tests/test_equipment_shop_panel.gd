extends "res://tests/test_suite_base.gd"

## Focused tests for the character creation equipment-shop panel state behavior.


func run_all_tests() -> void:
	test_setup_shows_roll_button_for_fresh_state()
	test_setup_resets_reused_panel_after_prior_roll_state()
	test_setup_refreshes_placeholder_after_gold_is_cleared()
	test_apply_starting_gold_roll_marks_panel_complete()
	test_zero_starting_gold_roll_keeps_panel_unrolled()
	if not has_failures():
		print("EquipmentShopPanel: all tests passed.")


func test_setup_shows_roll_button_for_fresh_state() -> void:
	var panel := _make_panel()
	var state := _make_state()

	panel.setup(state, EquipmentCatalog.new(), ClassRegistry.new())

	check(panel._roll_btn.visible, "roll button should be visible before starting gold is rolled")
	check(not panel._roll_btn.disabled, "roll button should be enabled before starting gold is rolled")
	check(not panel.is_complete(), "panel should be incomplete before starting gold is rolled")
	check(panel._starting_gold_cp == 0, "fresh state should restore zero starting gold")
	check(panel._gold_remaining_cp == 0, "fresh state should restore zero remaining gold")
	print("  setup_shows_roll_button_for_fresh_state: OK")


func test_setup_resets_reused_panel_after_prior_roll_state() -> void:
	var panel := _make_panel()
	var rolled_state := _make_state({
		"starting_gold_cp": 1100,
		"gold_remaining_cp": 400,
	})
	panel.setup(rolled_state, EquipmentCatalog.new(), ClassRegistry.new())

	panel._roll_btn.visible = false
	panel._roll_btn.disabled = true
	panel._status_label.text = "stale status"

	var fresh_state := _make_state()
	panel.setup(fresh_state, EquipmentCatalog.new(), ClassRegistry.new())

	check(panel._roll_btn.visible, "fresh setup should re-show the roll button on a reused panel")
	check(not panel._roll_btn.disabled, "fresh setup should re-enable the roll button on a reused panel")
	check(panel._status_label.text.is_empty(), "fresh setup should clear stale status text")
	check(panel._tab_bar.current_tab == 0, "fresh setup should reset the shop tab to the first category")
	print("  setup_resets_reused_panel_after_prior_roll_state: OK")


func test_setup_refreshes_placeholder_after_gold_is_cleared() -> void:
	var panel := _make_panel()
	var rolled_state := _make_state({
		"starting_gold_cp": 1500,
		"gold_remaining_cp": 1300,
	})
	panel.setup(rolled_state, EquipmentCatalog.new(), ClassRegistry.new())

	var fresh_state := _make_state()
	panel.setup(fresh_state, EquipmentCatalog.new(), ClassRegistry.new())

	var children := panel._item_list_container.get_children()
	check(not children.is_empty(), "item list should contain a placeholder message before the gold roll")
	var last_child = children.back()
	check(last_child is Label, "placeholder row should be a label")
	check((last_child as Label).text.contains("Roll your starting gold"),
		"fresh setup should rebuild the pre-roll placeholder message")
	print("  setup_refreshes_placeholder_after_gold_is_cleared: OK")


func test_apply_starting_gold_roll_marks_panel_complete() -> void:
	var panel := _make_panel()
	var state := _make_state()
	panel.setup(state, EquipmentCatalog.new(), ClassRegistry.new())

	panel._apply_starting_gold_roll_total(11)

	check(panel._starting_gold_cp == 11000, "11 on 3d6 should become 110gp (11000cp)")
	check(panel._gold_remaining_cp == 11000, "remaining gold should match starting gold immediately after the roll")
	check(not panel._roll_btn.visible, "roll button should hide after a successful starting-gold roll")
	check(panel.is_complete(), "panel should be complete after a successful starting-gold roll")
	check(int(state.get("starting_gold_cp", 0)) == 11000, "state should persist starting gold after the roll")
	print("  apply_starting_gold_roll_marks_panel_complete: OK")


func test_zero_starting_gold_roll_keeps_panel_unrolled() -> void:
	var panel := _make_panel()
	var state := _make_state()
	panel.setup(state, EquipmentCatalog.new(), ClassRegistry.new())

	panel._apply_starting_gold_roll_total(0)

	check(panel._roll_btn.visible, "zero/cancelled result should leave the roll button visible")
	check(not panel._roll_btn.disabled, "zero/cancelled result should re-enable the roll button")
	check(not panel.is_complete(), "zero/cancelled result should not mark the panel complete")
	check(not panel._rolling, "zero/cancelled result should clear in-flight rolling state")
	check(int(state.get("starting_gold_cp", 0)) == 0, "zero/cancelled result should keep starting gold at 0")
	check(panel._status_label.text.contains("cancelled"),
		"zero/cancelled result should explain why shopping has not started")
	print("  zero_starting_gold_roll_keeps_panel_unrolled: OK")


func _make_panel() -> EquipmentShopPanel:
	var panel := EquipmentShopPanel.new()
	panel.setup(_make_state(), EquipmentCatalog.new(), ClassRegistry.new())
	return panel


func _make_state(overrides: Dictionary = {}) -> Dictionary:
	var state := {
		"class_id": "fighter",
		"starting_gold_cp": 0,
		"gold_remaining_cp": 0,
		"inventory": [],
	}
	for key in overrides.keys():
		state[key] = overrides[key]
	return state
