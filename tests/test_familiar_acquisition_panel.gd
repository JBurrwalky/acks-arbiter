extends "res://tests/test_suite_base.gd"

## Tests for FamiliarAcquisitionPanel — Stage 3c composite that wraps
## FamiliarPicker + FamiliarProficiencyPicker for the character-creation flow.
##
## Verifies budget derivation from master's proficiency selections, sub-state
## threading into the two pickers, completeness gating across both, and the
## restore-on-return invariant when the player navigates back to the step.


func run_all_tests() -> void:
	test_compute_master_proficiency_count_sums_selections()
	test_setup_initializes_familiar_substate()
	test_setup_threads_class_id_and_budget_into_proficiency_picker()
	test_is_complete_requires_both_sub_pickers()
	test_is_complete_with_zero_budget_master()
	test_returning_to_step_restores_prior_picks()
	test_familiar_substate_shared_with_creation_state()

	if not has_failures():
		print("FamiliarAcquisitionPanel: all tests passed.")


# --- Helpers ---

## Pass `master_picks = null` to use the default 2-pick set (familiar + adventuring).
## Pass an explicit Array (including `[]` for a zero-budget master) to override.
func _make_state(class_id: String = "mage", master_picks: Variant = null) -> Dictionary:
	var picks: Array
	if master_picks == null:
		picks = [
			{"proficiency_key": "familiar", "rank": 1, "slot_type": "class", "selections_count": 1, "specialization": ""},
			{"proficiency_key": "adventuring", "rank": 1, "slot_type": "general", "selections_count": 1, "specialization": ""},
		]
	else:
		picks = master_picks as Array
	return {
		"class_id": class_id,
		"proficiencies": picks,
	}


func _make_panel(state: Dictionary) -> FamiliarAcquisitionPanel:
	var p := FamiliarAcquisitionPanel.new()
	p.setup(state, FamiliarFormRegistry.new(), ClassRegistry.new(), ProficiencyRegistry.new())
	return p


# --- Tests ---

func test_compute_master_proficiency_count_sums_selections() -> void:
	# Mix of unique (selections_count=1) and stacked (selections_count > 1) picks.
	var picks: Array = [
		{"proficiency_key": "familiar", "selections_count": 1},
		{"proficiency_key": "alchemy", "selections_count": 2},     # stacked rank-2
		{"proficiency_key": "adventuring", "selections_count": 1},
		{"proficiency_key": "engineering", "selections_count": 3}, # stacked rank-3
	]
	var n := FamiliarAcquisitionPanel.compute_master_proficiency_count(picks)
	check(n == 7, "1 + 2 + 1 + 3 = 7, got %d" % n)


func test_setup_initializes_familiar_substate() -> void:
	var state := _make_state()
	check(not state.has("familiar") or (state.get("familiar", {}) as Dictionary).is_empty(),
		"pre-setup: state has no familiar substate")
	_make_panel(state)
	check(state.has("familiar"), "setup writes 'familiar' key into state")
	var fam: Dictionary = state["familiar"]
	check(fam.has("form_key"), "form_key initialized")
	check(fam.has("cosmetic_species"), "cosmetic_species initialized")
	check(fam.has("name"), "name initialized")
	check(fam.has("proficiencies_chosen"), "proficiencies_chosen initialized")
	check((fam["proficiencies_chosen"] as Array).is_empty(), "proficiencies_chosen starts empty")


func test_setup_threads_class_id_and_budget_into_proficiency_picker() -> void:
	var state := _make_state("mage", [
		{"proficiency_key": "familiar", "selections_count": 1},
		{"proficiency_key": "adventuring", "selections_count": 1},
		{"proficiency_key": "alchemy", "selections_count": 2},
	])
	var p := _make_panel(state)
	# Eligible list should include class proficiencies for mage (e.g. alchemy)
	# AND general proficiencies (e.g. adventuring) — confirms class_id was threaded.
	var eligible: Array[String] = p._proficiency_picker.get_eligible_keys()
	check("alchemy" in eligible, "mage class proficiency 'alchemy' is eligible")
	check("adventuring" in eligible, "general proficiency 'adventuring' is eligible")


func test_is_complete_requires_both_sub_pickers() -> void:
	var state := _make_state()
	var p := _make_panel(state)

	# Initially, neither sub-picker is complete.
	check(p.is_complete() == false, "fresh panel is not complete")

	# Drive the form picker to completion: bat (single variant auto-selected),
	# then a name.
	p._form_picker._on_form_pressed("bat")
	p._form_picker._on_name_changed("Echo")
	check(p._form_picker.is_complete() == true, "form picker complete")
	check(p.is_complete() == false, "still not complete — proficiency picker empty")

	# Pick proficiencies up to budget. Budget = 1 (familiar) + 1 (adventuring) = 2.
	# Pick two non-spec procs.
	# (Eligible list is sorted by display name; pick keys that exist for mage.)
	var eligible: Array[String] = p._proficiency_picker.get_eligible_keys()
	var picked := 0
	for k in eligible:
		if picked >= 2:
			break
		# Skip spec procs — they need a spec choice to count as complete.
		if p._proficiency_picker._proficiency_registry.is_specialization(k):
			continue
		p._proficiency_picker._on_eligible_pressed(k)
		picked += 1
	check(p._proficiency_picker.is_complete() == true,
		"proficiency picker complete after 2 picks")
	check(p.is_complete() == true, "panel complete when both sub-pickers complete")


func test_is_complete_with_zero_budget_master() -> void:
	# Edge case: master with no proficiency selections (budget = 0). The familiar
	# proficiency picker is trivially complete; just need form/cosmetic/name.
	var state := _make_state("mage", [])
	var p := _make_panel(state)
	check(p._proficiency_picker.is_complete() == true,
		"zero-budget proficiency picker is trivially complete")
	# Now drive the form picker.
	p._form_picker._on_form_pressed("hawk")
	p._form_picker._on_name_changed("Skyfeather")
	check(p.is_complete() == true,
		"panel with zero budget completes once form picker is done")


func test_returning_to_step_restores_prior_picks() -> void:
	# Simulate the player navigating away and back: state already carries the
	# familiar substate from a prior visit.
	var state := _make_state()
	state["familiar"] = {
		"form_key": "weasel",
		"cosmetic_species": "Ferret",
		"name": "Snipe",
		"proficiencies_chosen": [
			{"proficiency_key": "adventuring", "specialization": ""},
		],
	}
	var p := _make_panel(state)
	check(p._form_picker._selected_form_key == "weasel", "form selection restored")
	check(p._form_picker._name_field.text == "Snipe", "name field text restored")
	# Proficiency picker should reflect the prior pick.
	var picks_after: Array = state["familiar"]["proficiencies_chosen"]
	check(picks_after.size() == 1, "1 prior pick preserved")
	check(picks_after[0]["proficiency_key"] == "adventuring", "prior pick is 'adventuring'")


func test_familiar_substate_shared_with_creation_state() -> void:
	# `creation_state["familiar"]["proficiencies_chosen"]` must be the SAME
	# Array reference the proficiency picker mutates in-place. Otherwise
	# `_finalize_character()` reads stale picks. Verify by clicking a proficiency
	# and confirming the array on `state["familiar"]` reflects the addition.
	var state := _make_state()
	var p := _make_panel(state)
	var eligible: Array[String] = p._proficiency_picker.get_eligible_keys()
	# Pick a non-spec proficiency — first non-spec key in the eligible list.
	var first_non_spec := ""
	for k in eligible:
		if not p._proficiency_picker._proficiency_registry.is_specialization(k):
			first_non_spec = k
			break
	check(not first_non_spec.is_empty(), "found at least one non-spec eligible proficiency")
	p._proficiency_picker._on_eligible_pressed(first_non_spec)

	var fam_picks: Array = state["familiar"]["proficiencies_chosen"]
	check(fam_picks.size() == 1,
		"creation_state['familiar']['proficiencies_chosen'] reflects the click — got %d" % fam_picks.size())
	check(fam_picks[0]["proficiency_key"] == first_non_spec,
		"the picked key surfaces on the shared substate")
