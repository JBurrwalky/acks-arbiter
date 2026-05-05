extends "res://tests/test_suite_base.gd"

## Tests for FamiliarProficiencyPicker — class/general slot split + stacking.
## State Dict shape:
##   {class_slot_budget, general_slot_budget, master_class_id, proficiencies_chosen}


func run_all_tests() -> void:
	test_eligible_class_list_is_master_class_only()
	test_eligible_general_list_excludes_class_specific_keys()
	test_eligible_lists_drop_unknown_keys()
	test_zero_budget_means_complete_immediately()
	test_class_pick_appends_to_state_with_slot_type()
	test_general_pick_appends_to_state_with_slot_type()
	test_class_budget_full_blocks_further_class_picks_only()
	test_general_budget_independent_of_class_budget()
	test_stacking_proficiency_advances_rank_on_repick()
	test_stacking_capped_at_max_rank()
	test_unique_proficiency_blocked_after_first_pick()
	test_specialization_pick_initially_incomplete()
	test_specialization_pick_completes_when_spec_chosen()
	test_specialization_supports_multiple_variant_picks()
	test_remove_pick_frees_the_slot()
	test_returning_to_step_restores_prior_picks()
	test_picks_independent_of_master_actual_selections()

	if not has_failures():
		print("FamiliarProficiencyPicker: all tests passed.")


# --- Helpers ---

func _make_picker(state: Dictionary) -> FamiliarProficiencyPicker:
	var p := FamiliarProficiencyPicker.new()
	p.setup(state, ClassRegistry.new(), ProficiencyRegistry.new())
	return p


func _new_state(class_id: String = "mage", class_budget: int = 2, general_budget: int = 2) -> Dictionary:
	return {
		"class_slot_budget": class_budget,
		"general_slot_budget": general_budget,
		"master_class_id": class_id,
		"proficiencies_chosen": [],
	}


func _first_non_spec_class_key(p: FamiliarProficiencyPicker, exclude: Array = []) -> String:
	for k in p.get_eligible_class_keys():
		if k in exclude:
			continue
		if p._proficiency_registry.is_specialization(k):
			continue
		if p._proficiency_registry.get_selection_rule(k) == "stacking":
			continue
		return k
	return ""


func _first_unique_general_key(p: FamiliarProficiencyPicker) -> String:
	for k in p.get_eligible_general_keys():
		if p._proficiency_registry.is_specialization(k):
			continue
		if p._proficiency_registry.get_selection_rule(k) == "stacking":
			continue
		return k
	return ""


# --- Tests ---

func test_eligible_class_list_is_master_class_only() -> void:
	var p := _make_picker(_new_state("mage"))
	var class_keys := p.get_eligible_class_keys()
	# Mage class proficiency list includes "alchemy", "familiar", "knowledge" etc.
	check("alchemy" in class_keys, "mage class proficiency 'alchemy' is in class list")
	check("familiar" in class_keys, "mage class proficiency 'familiar' is in class list")


func test_eligible_general_list_excludes_class_specific_keys() -> void:
	var p := _make_picker(_new_state("mage"))
	var general_keys := p.get_eligible_general_keys()
	# General list includes "adventuring", "endurance", etc. The exact members
	# vary, but a class-only proficiency like "battle_magic" should NOT appear.
	check("battle_magic" not in general_keys,
		"class-only proficiency 'battle_magic' is NOT in general list")
	# At least one canonical general entry should be present.
	check("adventuring" in general_keys, "'adventuring' is a general proficiency")


func test_eligible_lists_drop_unknown_keys() -> void:
	var p := _make_picker(_new_state("mage"))
	var prof_reg := ProficiencyRegistry.new()
	for k in p.get_eligible_class_keys():
		check(prof_reg.has_proficiency(k), "class list entry '%s' is in catalog" % k)
	for k in p.get_eligible_general_keys():
		check(prof_reg.has_proficiency(k), "general list entry '%s' is in catalog" % k)


func test_zero_budget_means_complete_immediately() -> void:
	var p := _make_picker(_new_state("mage", 0, 0))
	check(p.is_complete() == true,
		"both budgets zero → trivially complete")


func test_class_pick_appends_to_state_with_slot_type() -> void:
	var state := _new_state("mage", 2, 2)
	var p := _make_picker(state)
	var key := _first_non_spec_class_key(p)
	check(not key.is_empty(), "found a non-spec, non-stacking class key")
	p._on_eligible_pressed(key, FamiliarProficiencyPicker.SLOT_TYPE_CLASS)
	var picks: Array = state["proficiencies_chosen"]
	check(picks.size() == 1, "1 pick after class click")
	check(String(picks[0]["slot_type"]) == "class", "slot_type recorded as 'class'")
	check(int(picks[0]["selections_count"]) == 1, "selections_count = 1")


func test_general_pick_appends_to_state_with_slot_type() -> void:
	var state := _new_state("mage", 2, 2)
	var p := _make_picker(state)
	var key := _first_unique_general_key(p)
	check(not key.is_empty(), "found a non-spec, non-stacking general key")
	p._on_eligible_pressed(key, FamiliarProficiencyPicker.SLOT_TYPE_GENERAL)
	var picks: Array = state["proficiencies_chosen"]
	check(picks.size() == 1, "1 pick after general click")
	check(String(picks[0]["slot_type"]) == "general", "slot_type recorded as 'general'")


func test_class_budget_full_blocks_further_class_picks_only() -> void:
	var state := _new_state("mage", 1, 2)
	var p := _make_picker(state)
	# Spend the one class slot.
	var class_key := _first_non_spec_class_key(p)
	p._on_eligible_pressed(class_key, "class")
	# Try to pick another class proficiency — should be a no-op (or rank-up if stacking).
	var another := _first_non_spec_class_key(p, [class_key])
	if not another.is_empty():
		p._on_eligible_pressed(another, "class")
		# Class slots used should still be 1 (no-op for unique procs).
		check(p._class_slots_used == 1, "second class pick blocked when class budget full")
	# But general slots should still accept picks.
	var gen_key := _first_unique_general_key(p)
	p._on_eligible_pressed(gen_key, "general")
	check(p._general_slots_used == 1, "general slot still accepts picks despite class budget full")


func test_general_budget_independent_of_class_budget() -> void:
	var state := _new_state("mage", 2, 0)  # general budget 0
	var p := _make_picker(state)
	var gen_key := _first_unique_general_key(p)
	p._on_eligible_pressed(gen_key, "general")
	check(p._general_slots_used == 0,
		"general pick blocked when general budget is 0 — got %d" % p._general_slots_used)
	check((state["proficiencies_chosen"] as Array).is_empty(),
		"no picks when general budget is zero")


func test_stacking_proficiency_advances_rank_on_repick() -> void:
	var state := _new_state("mage", 3, 2)
	var p := _make_picker(state)
	# Alchemy is selection_rule="stacking" with max_rank=3 — pick it twice.
	p._on_eligible_pressed("alchemy", "class")
	p._on_eligible_pressed("alchemy", "class")
	var picks: Array = state["proficiencies_chosen"]
	check(picks.size() == 1, "second alchemy click should NOT add a new entry, got %d" % picks.size())
	check(int(picks[0]["rank"]) == 2, "rank advanced to 2, got %d" % picks[0]["rank"])
	check(int(picks[0]["selections_count"]) == 2,
		"selections_count = 2 (uses two slots), got %d" % picks[0]["selections_count"])
	check(p._class_slots_used == 2, "class slots used = 2")


func test_stacking_capped_at_max_rank() -> void:
	# Alchemy has max_rank = 3. Try four picks; the 4th should be a no-op.
	var state := _new_state("mage", 4, 2)
	var p := _make_picker(state)
	p._on_eligible_pressed("alchemy", "class")
	p._on_eligible_pressed("alchemy", "class")
	p._on_eligible_pressed("alchemy", "class")
	p._on_eligible_pressed("alchemy", "class")
	var picks: Array = state["proficiencies_chosen"]
	check(picks.size() == 1, "still one entry")
	check(int(picks[0]["rank"]) == 3, "rank capped at max_rank=3, got %d" % picks[0]["rank"])
	check(p._class_slots_used == 3, "only 3 slots consumed (4th pick rejected)")


func test_unique_proficiency_blocked_after_first_pick() -> void:
	var state := _new_state("mage", 3, 2)
	var p := _make_picker(state)
	# Familiar is selection_rule="unique" with max_rank=1.
	p._on_eligible_pressed("familiar", "class")
	p._on_eligible_pressed("familiar", "class")
	var picks: Array = state["proficiencies_chosen"]
	check(picks.size() == 1, "second click on unique 'familiar' is rejected")
	check(int(picks[0]["rank"]) == 1, "rank stays at 1 for unique procs")


func test_specialization_pick_initially_incomplete() -> void:
	var state := _new_state("mage", 1, 0)
	var p := _make_picker(state)
	# Knowledge is selection_rule="specialization".
	p._on_eligible_pressed("knowledge", "class")
	check((state["proficiencies_chosen"] as Array).size() == 1,
		"knowledge picked (with empty spec)")
	check(p.is_complete() == false,
		"is_complete=false because spec proficiency has empty specialization")


func test_specialization_pick_completes_when_spec_chosen() -> void:
	var state := _new_state("mage", 1, 0)
	var p := _make_picker(state)
	p._on_eligible_pressed("knowledge", "class")
	var specs: Array = ProficiencyRegistry.new().get_available_specializations("knowledge")
	if not specs.is_empty():
		# Dropdown index 1 = first spec (idx 0 is the (choose…) sentinel).
		p._on_spec_selected(1, 0, specs)
		var pick: Dictionary = state["proficiencies_chosen"][0]
		check(String(pick.get("specialization", "")) == String(specs[0]),
			"first specialization stored on pick")
		check(p.is_complete() == true,
			"is_complete=true once spec is chosen")


func test_specialization_supports_multiple_variant_picks() -> void:
	# Knowledge has max_selections > 1 (stacking allowed across different specs).
	# Two clicks should add two separate entries.
	var state := _new_state("mage", 2, 0)
	var p := _make_picker(state)
	p._on_eligible_pressed("knowledge", "class")
	p._on_eligible_pressed("knowledge", "class")
	check((state["proficiencies_chosen"] as Array).size() == 2,
		"two clicks on Knowledge → two separate entries (different specs)")


func test_remove_pick_frees_the_slot() -> void:
	var state := _new_state("mage", 2, 2)
	var p := _make_picker(state)
	var class_key := _first_non_spec_class_key(p)
	p._on_eligible_pressed(class_key, "class")
	check(p._class_slots_used == 1, "1 class slot used")
	p._on_remove_pressed(0)
	check((state["proficiencies_chosen"] as Array).is_empty(), "pick removed")
	check(p._class_slots_used == 0, "class slot freed")


func test_returning_to_step_restores_prior_picks() -> void:
	var state := _new_state("mage", 2, 2)
	state["proficiencies_chosen"] = [
		{"proficiency_key": "alchemy", "slot_type": "class", "rank": 2, "selections_count": 2, "specialization": ""},
		{"proficiency_key": "adventuring", "slot_type": "general", "rank": 1, "selections_count": 1, "specialization": ""},
	]
	var p := _make_picker(state)
	check(p._class_slots_used == 2, "class slots restored from prior picks")
	check(p._general_slots_used == 1, "general slots restored from prior picks")
	check(p.is_complete() == false,
		"3/4 budget filled (1 general slot remains) → not complete")


func test_picks_independent_of_master_actual_selections() -> void:
	# Eligible list depends only on master_class_id, not master's actual picks.
	var p_a := _make_picker(_new_state("mage", 2, 2))
	var p_b := _make_picker(_new_state("mage", 2, 2))
	check(p_a.get_eligible_class_keys() == p_b.get_eligible_class_keys(),
		"eligible class list is deterministic from class_id alone")
	check(p_a.get_eligible_general_keys() == p_b.get_eligible_general_keys(),
		"eligible general list is deterministic")
