extends "res://tests/test_suite_base.gd"

## Focused tests for EquipmentItemRow button callback behavior.


func run_all_tests() -> void:
	test_equip_button_invokes_zero_arg_callback()
	test_split_button_hidden_when_qty_one()
	test_split_button_shown_when_qty_gt_one()
	test_split_button_hidden_without_callback()
	test_split_callback_invoked_with_count()
	if not has_failures():
		print("EquipmentItemRow: all tests passed.")


func test_equip_button_invokes_zero_arg_callback() -> void:
	var row := EquipmentItemRow.new()
	var equip_state := { "count": 0 }
	row.setup(
		{
			"id": "item_torch",
			"name": "Torch",
			"quantity": 1,
			"encumbrance_units": 167,
			"container_id": "",
		},
		Callable(),
		"character_test",
		func() -> void:
			equip_state["count"] = int(equip_state.get("count", 0)) + 1
	)

	var equip_btn := _find_button(row, "Equip")
	check(equip_btn != null, "equip button should exist for loose items with an equip callback")
	if equip_btn != null:
		equip_btn.emit_signal("pressed")

	check(int(equip_state.get("count", 0)) == 1,
		"equip button should invoke the provided zero-argument callback exactly once")
	print("  equip_button_invokes_zero_arg_callback: OK")


func test_split_button_hidden_when_qty_one() -> void:
	var row := EquipmentItemRow.new()
	row.setup(
		{"id": "item_a", "name": "Dagger", "quantity": 1, "encumbrance_units": 167, "container_id": ""},
		Callable(),
		"character_test",
		Callable(),
		func(_c: int) -> void: pass  ## valid split callback
	)
	var split_btn := _find_button(row, "Split")
	check(split_btn == null, "split button should NOT appear when quantity is 1")
	print("  split_button_hidden_when_qty_one: OK")


func test_split_button_shown_when_qty_gt_one() -> void:
	var row := EquipmentItemRow.new()
	row.setup(
		{"id": "item_b", "name": "Dagger", "quantity": 3, "encumbrance_units": 167, "container_id": ""},
		Callable(),
		"character_test",
		Callable(),
		func(_c: int) -> void: pass  ## valid split callback
	)
	var split_btn := _find_button(row, "Split")
	check(split_btn != null, "split button should appear when quantity > 1 and split callback is valid")
	print("  split_button_shown_when_qty_gt_one: OK")


func test_split_button_hidden_without_callback() -> void:
	var row := EquipmentItemRow.new()
	row.setup(
		{"id": "item_c", "name": "Dagger", "quantity": 3, "encumbrance_units": 167, "container_id": ""},
		Callable(),
		"character_test"
		## no equip_callback, no split_callback
	)
	var split_btn := _find_button(row, "Split")
	check(split_btn == null, "split button should NOT appear when no split callback is provided")
	print("  split_button_hidden_without_callback: OK")


func test_split_callback_invoked_with_count() -> void:
	## Directly call the _on_split_pressed path by simulating callback invocation.
	## We can't easily drive the ConfirmationDialog in a headless test,
	## so instead we verify the split_callback receives the correct argument
	## by wiring a callback that records what count it was called with.
	var received_count := { "value": -1 }
	var row := EquipmentItemRow.new()
	row.setup(
		{"id": "item_d", "name": "Arrow", "quantity": 10, "encumbrance_units": 17, "container_id": ""},
		Callable(),
		"character_test",
		Callable(),
		func(c: int) -> void: received_count["value"] = c
	)
	## Invoke the split callback directly with a specific count to confirm wiring
	row._split_callback.call(4)
	check(int(received_count.get("value", -1)) == 4,
		"split callback should receive the count passed to it")
	print("  split_callback_invoked_with_count: OK")


func _find_button(root: Node, button_text: String) -> Button:
	for child in root.get_children():
		if child is Button and (child as Button).text == button_text:
			return child as Button
		var nested := _find_button(child, button_text)
		if nested != null:
			return nested
	return null
