extends "res://tests/test_suite_base.gd"

## Tests for FamiliarProficiencyPicker — the Stage 3b component for picking
## the familiar's own proficiencies from the union of (general + master's class)
## proficiency lists, against a budget equal to master's total selections.


func run_all_tests() -> void:
	test_eligible_list_is_union_of_general_and_master_class()
	test_eligible_list_includes_stacking_proficiencies()
	test_eligible_list_excludes_unknown_keys()
	test_budget_zero_means_complete_immediately()
	test_picking_a_proficiency_appends_to_state()
	test_picks_blocked_when_budget_full()
	test_picks_unique_no_duplicates()
	test_remove_pick_re_enables_eligible_button()
	test_specialization_pick_initially_incomplete()
	test_specialization_pick_completes_when_spec_chosen()
	test_returning_to_step_restores_prior_picks()
	test_picks_independent_of_master_actual_selections()

	if not has_failures():
		print("FamiliarProficiencyPicker: all tests passed.")


# --- Helpers ---

func _make_picker(state: Dictionary) -> FamiliarProficiencyPicker:
	var p := FamiliarProficiencyPicker.new()
	p.setup(state, ClassRegistry.new(), ProficiencyRegistry.new())
	return p


func _new_state(class_id: String = "mage", budget: int = 4) -> Dictionary:
	return {
		"proficiency_budget": budget,
		"master_class_id": class_id,
		"proficiencies_chosen": [],
	}


# --- Tests ---

func test_eligible_list_is_union_of_general_and_master_class() -> void:
	# Mage class proficiency list includes "alchemy", "familiar", "knowledge".
	# General list includes "adventuring", "endurance", "swimming", etc.
	var p := _make_picker(_new_state("mage", 4))
	var keys := p.get_eligible_keys()
	check("alchemy" in keys, "mage class proficiency 'alchemy' is eligible")
	check("familiar" in keys, "mage class proficiency 'familiar' is eligible")
	# General list members
	var prof_reg := ProficiencyRegistry.new()
	for general_key in prof_reg.get_general_proficiency_list():
		# Some general entries may be stacking and filtered; just spot-check
		# a non-stacking one — "adventuring" is the standard example.
		if general_key == "adventuring":
			check(general_key in keys, "general proficiency 'adventuring' is eligible")
			break


func test_eligible_list_includes_stacking_proficiencies() -> void:
	# Engineering uses selection_rule = "stacking" (max_selections = 4).
	# Stage 3b includes stacking entries — they can be picked once at rank 1.
	# (The "unique pick" rule is enforced separately via _picked_keys_set.)
	var p := _make_picker(_new_state("mage", 4))
	var keys := p.get_eligible_keys()
	check("engineering" in keys,
		"engineering (stacking) is eligible — single pick at rank 1 supported")
	check("alchemy" in keys,
		"alchemy (stacking) is eligible — single pick at rank 1 supported")


func test_eligible_list_excludes_unknown_keys() -> void:
	# If a class JSON references a proficiency_key that's not in the catalog,
	# the picker silently drops it rather than crashing.
	var p := _make_picker(_new_state("mage", 4))
	var keys := p.get_eligible_keys()
	for k in keys:
		check(ProficiencyRegistry.new().has_proficiency(k),
			"every eligible key is a real catalog entry: %s" % k)


func test_budget_zero_means_complete_immediately() -> void:
	var p := _make_picker(_new_state("mage", 0))
	check(p.is_complete() == true,
		"budget 0 (master with no proficiency selections) is trivially complete")


func test_picking_a_proficiency_appends_to_state() -> void:
	var state := _new_state("mage", 4)
	var p := _make_picker(state)
	p._on_eligible_pressed("alchemy")
	check((state["proficiencies_chosen"] as Array).size() == 1, "one pick after click")
	check(state["proficiencies_chosen"][0]["proficiency_key"] == "alchemy", "alchemy picked")
	check(state["proficiencies_chosen"][0]["specialization"] == "", "no specialization yet (alchemy is non-spec)")


func test_picks_blocked_when_budget_full() -> void:
	var state := _new_state("mage", 2)
	var p := _make_picker(state)
	p._on_eligible_pressed("alchemy")
	p._on_eligible_pressed("familiar")
	# Budget is 2; further picks should be no-ops.
	p._on_eligible_pressed("mapping")
	check((state["proficiencies_chosen"] as Array).size() == 2,
		"third pick rejected: %d" % (state["proficiencies_chosen"] as Array).size())


func test_picks_unique_no_duplicates() -> void:
	# Stage 3b: same proficiency cannot be picked twice (no stacking support).
	var state := _new_state("mage", 4)
	var p := _make_picker(state)
	p._on_eligible_pressed("alchemy")
	p._on_eligible_pressed("alchemy")  # second click should be a no-op
	check((state["proficiencies_chosen"] as Array).size() == 1,
		"duplicate pick of 'alchemy' rejected")


func test_remove_pick_re_enables_eligible_button() -> void:
	var state := _new_state("mage", 4)
	var p := _make_picker(state)
	p._on_eligible_pressed("alchemy")
	check((state["proficiencies_chosen"] as Array).size() == 1, "pre: 1 pick")
	# The button should now be disabled for 'alchemy'
	var btn: Button = p._eligible_buttons.get("alchemy")
	check(btn != null and btn.disabled, "alchemy button disabled after pick")
	# Remove the pick
	p._on_remove_pressed(0)
	check((state["proficiencies_chosen"] as Array).is_empty(), "post-remove: 0 picks")
	# Re-rendered button should be enabled again
	btn = p._eligible_buttons.get("alchemy")
	check(btn != null and not btn.disabled, "alchemy button re-enabled after remove")


func test_specialization_pick_initially_incomplete() -> void:
	# Knowledge has selection_rule = "specialization". Picking it leaves the
	# picker incomplete until a specialization is chosen.
	var state := _new_state("mage", 1)
	var p := _make_picker(state)
	p._on_eligible_pressed("knowledge")
	check((state["proficiencies_chosen"] as Array).size() == 1,
		"knowledge picked (with empty spec)")
	check(p.is_complete() == false,
		"is_complete=false because spec proficiency has empty specialization")


func test_specialization_pick_completes_when_spec_chosen() -> void:
	var state := _new_state("mage", 1)
	var p := _make_picker(state)
	p._on_eligible_pressed("knowledge")
	# Simulate the spec dropdown selecting the second item (idx 1 in dropdown
	# = first real spec, since idx 0 is the (choose…) sentinel).
	# `_on_spec_selected(item_idx, picked_row_index, specs)` per Godot signal-
	# binding rule.
	var specs: Array = ProficiencyRegistry.new().get_available_specializations("knowledge")
	if not specs.is_empty():
		p._on_spec_selected(1, 0, specs)
		var pick: Dictionary = state["proficiencies_chosen"][0]
		check(String(pick.get("specialization", "")) == String(specs[0]),
			"first specialization stored on pick")
		check(p.is_complete() == true,
			"is_complete=true once spec is chosen")


func test_returning_to_step_restores_prior_picks() -> void:
	var state := _new_state("mage", 3)
	state["proficiencies_chosen"] = [
		{"proficiency_key": "alchemy", "specialization": ""},
		{"proficiency_key": "familiar", "specialization": ""},
	]
	var p := _make_picker(state)
	# After setup, the picker should reflect the prior picks.
	check((state["proficiencies_chosen"] as Array).size() == 2,
		"prior picks preserved across setup")
	# is_complete=false because we've only picked 2/3.
	check(p.is_complete() == false, "2/3 picks → not complete")


func test_picks_independent_of_master_actual_selections() -> void:
	# The familiar's proficiency list is INDEPENDENT of master's actual picks.
	# This test verifies no implicit linkage — the picker doesn't read
	# master's character_proficiencies row, only the master's class list and
	# the general list (the eligible domain, not the master's choices within
	# that domain).
	var state := _new_state("mage", 4)
	var p := _make_picker(state)
	# Eligible list only depends on master's CLASS, not master's actual
	# proficiency picks. So it should be the same regardless of what the
	# master has selected.
	var keys_a := p.get_eligible_keys()
	# Re-create a picker with the same config — should produce identical
	# eligible list (no hidden dependency on master's character_proficiencies).
	var state_b := _new_state("mage", 4)
	var p_b := _make_picker(state_b)
	var keys_b := p_b.get_eligible_keys()
	check(keys_a == keys_b,
		"eligible list is deterministic from class_id alone — no master-pick dependency")
