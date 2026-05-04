extends "res://tests/test_suite_base.gd"

## Tests for FamiliarPicker — the Stage 3a UI component for choosing form,
## cosmetic variant, and name during familiar acquisition. Tests poke at
## the panel's internal state (`_form_buttons`, `_cosmetic_dropdown`, etc.)
## the same way the existing character-creation panel tests do.


var _root: Node


func run_all_tests() -> void:
	test_initial_state_is_incomplete()
	test_clicking_a_form_populates_state_and_emits_change()
	test_cosmetic_dropdown_auto_selects_first_variant()
	test_single_variant_form_disables_dropdown()
	test_multi_variant_form_lets_player_change_pick()
	test_typing_a_name_completes_the_picker()
	test_returning_to_step_restores_prior_state()
	test_form_detail_shows_ac_and_summary()
	test_picker_changed_signal_fires_on_form_select_cosmetic_and_name()

	# Cleanup any orphaned nodes attached to _root.
	if _root != null and is_instance_valid(_root):
		_root.queue_free()
		_root = null

	if not has_failures():
		print("FamiliarPicker: all tests passed.")


# --- Helpers ---

func _registry() -> FamiliarFormRegistry:
	return FamiliarFormRegistry.new(MonsterRegistry.new())


func _make_picker(state: Dictionary = {}) -> FamiliarPicker:
	# Picker UI builds on first setup; no parenting required for headless
	# tests but signals + theme overrides work fine in detached mode.
	var picker := FamiliarPicker.new()
	picker.setup(state, _registry())
	return picker


# --- Tests ---

func test_initial_state_is_incomplete() -> void:
	var p := _make_picker()
	check(p.is_complete() == false, "fresh picker with no fields filled is not complete")


func test_clicking_a_form_populates_state_and_emits_change() -> void:
	var state: Dictionary = {}
	var p := _make_picker(state)
	var changed_count := [0]
	p.picker_changed.connect(func(): changed_count[0] += 1)

	p._on_form_pressed("bat")

	check(state.get("form_key", "") == "bat", "form_key written to state")
	check(state.get("cosmetic_species", "") == "Bat", "single-variant form auto-selects 'Bat'")
	check(changed_count[0] >= 1, "picker_changed emitted on form select")


func test_cosmetic_dropdown_auto_selects_first_variant() -> void:
	var state: Dictionary = {}
	var p := _make_picker(state)
	p._on_form_pressed("hawk")
	check(p._cosmetic_dropdown.item_count == 5, "hawk surfaces all 5 cosmetic variants")
	check(state.get("cosmetic_species", "") == "Hawk", "first variant 'Hawk' auto-selected")


func test_single_variant_form_disables_dropdown() -> void:
	var state: Dictionary = {}
	var p := _make_picker(state)
	p._on_form_pressed("bat")
	check(p._cosmetic_dropdown.disabled == true,
		"single-variant form (bat) disables the dropdown — no choice to make")


func test_multi_variant_form_lets_player_change_pick() -> void:
	var state: Dictionary = {}
	var p := _make_picker(state)
	p._on_form_pressed("hawk")
	check(p._cosmetic_dropdown.disabled == false,
		"multi-variant form leaves the dropdown enabled")
	# Simulate the player picking the 3rd variant (Eagle, index 2).
	p._on_cosmetic_selected(2)
	check(state.get("cosmetic_species", "") == "Eagle",
		"selecting index 2 writes 'Eagle' to state")


func test_typing_a_name_completes_the_picker() -> void:
	var state: Dictionary = {}
	var p := _make_picker(state)
	p._on_form_pressed("hawk")
	# Hawk auto-selects "Hawk" cosmetic; just need a name now.
	check(p.is_complete() == false, "name still empty → not complete")
	p._on_name_changed("Skyfeather")
	check(state.get("name", "") == "Skyfeather", "name written to state")
	check(p.is_complete() == true, "all three fields filled → complete")


func test_returning_to_step_restores_prior_state() -> void:
	# Simulate the player navigating away and coming back: setup is called
	# again with a state that already has form/cosmetic/name from a prior visit.
	var state := {
		"form_key": "weasel",
		"cosmetic_species": "Ferret",
		"name": "Snipe",
	}
	var p := FamiliarPicker.new()
	p.setup(state, _registry())
	check(p._selected_form_key == "weasel", "form selection restored")
	check(p._name_field.text == "Snipe", "name field text restored")
	check(p.is_complete() == true, "picker reports complete after restore")


func test_form_detail_shows_ac_and_summary() -> void:
	var state: Dictionary = {}
	var p := _make_picker(state)
	p._on_form_pressed("cat")
	# Walk the detail area for an AC label and a summary label.
	var found_ac := false
	var found_summary := false
	for child in p._detail_area.get_children():
		if child is Label:
			var t: String = (child as Label).text
			if t.begins_with("AC: "):
				found_ac = true
			if "house cat" in t.to_lower() or "stalker" in t.to_lower():
				found_summary = true
	check(found_ac, "detail area renders an 'AC: ...' label")
	check(found_summary, "detail area renders the form summary text")


func test_picker_changed_signal_fires_on_form_select_cosmetic_and_name() -> void:
	var state: Dictionary = {}
	var p := _make_picker(state)
	var counter := [0]
	p.picker_changed.connect(func(): counter[0] += 1)

	p._on_form_pressed("hawk")           # +1
	p._on_cosmetic_selected(1)           # +1 (Raven)
	p._on_name_changed("Quoth")          # +1
	# Form select can emit twice (initial select + auto-cosmetic) depending on
	# implementation; we accept ≥3 to capture the lower bound.
	check(counter[0] >= 3, "picker_changed fires on each user-driven mutation, got %d" % counter[0])
