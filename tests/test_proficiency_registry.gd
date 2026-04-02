extends "res://tests/test_suite_base.gd"

## Unit tests for ProficiencyRegistry.
## Verifies catalog loading, lookup, metadata, effects access, level scaling,
## compound key resolution, and cross-validation against class JSON files.


func run_all_tests() -> void:
	test_catalog_loads()
	test_proficiency_count_reasonable()
	test_has_proficiency_true()
	test_has_proficiency_false()
	test_get_proficiency_divine_blessing()
	test_general_list_loads()
	test_general_list_has_all_entries()
	test_get_max_rank_ranked()
	test_get_max_rank_unranked()
	test_get_selection_rule_unique()
	test_get_selection_rule_specialization()
	test_get_selection_rule_stacking()
	test_effects_for_rank_non_ranked()
	test_effects_for_rank_ranked()
	test_effects_for_specialization()
	test_level_scaling_has_scaling()
	test_level_scaling_breakpoints()
	test_is_specialization()
	test_compound_key_single_segment()
	test_compound_key_multi_segment()
	test_all_class_json_keys_resolve()
	test_get_available_specializations_closed_list()
	test_get_available_specializations_registry()
	test_get_available_specializations_non_spec()
	test_get_available_specializations_no_registry()
	test_public_compound_key_method()
	test_public_resolve_key_method()
	test_specialization_display_name_via_registry()
	if not has_failures():
		print("ProficiencyRegistry: all tests passed.")


# ---------------------------------------------------------------------------

func test_catalog_loads() -> void:
	var reg := ProficiencyRegistry.new()
	check(reg.get_proficiency_count() > 0,
		"ProficiencyRegistry: catalog should have loaded at least 1 proficiency")


func test_proficiency_count_reasonable() -> void:
	var reg := ProficiencyRegistry.new()
	check(reg.get_proficiency_count() >= 100,
		"ProficiencyRegistry: catalog should have 100+ proficiencies, got %d" % reg.get_proficiency_count())


func test_has_proficiency_true() -> void:
	var reg := ProficiencyRegistry.new()
	check(reg.has_proficiency("divine_blessing"),
		"ProficiencyRegistry: divine_blessing should exist in catalog")
	check(reg.has_proficiency("healing"),
		"ProficiencyRegistry: healing should exist in catalog")


func test_has_proficiency_false() -> void:
	var reg := ProficiencyRegistry.new()
	check(not reg.has_proficiency("not_a_real_proficiency"),
		"ProficiencyRegistry: garbage key should not exist")


func test_get_proficiency_divine_blessing() -> void:
	var reg := ProficiencyRegistry.new()
	var entry := reg.get_proficiency("divine_blessing")
	check(not entry.is_empty(),
		"ProficiencyRegistry: divine_blessing entry should not be empty")
	check(entry.get("proficiency_name", "") == "Divine Blessing",
		"ProficiencyRegistry: divine_blessing name should be 'Divine Blessing', got '%s'" % entry.get("proficiency_name", ""))
	check(entry.get("max_rank", 0) == 1,
		"ProficiencyRegistry: divine_blessing max_rank should be 1")
	check(entry.get("selection_rule", "") == "unique",
		"ProficiencyRegistry: divine_blessing selection_rule should be unique")


func test_general_list_loads() -> void:
	var reg := ProficiencyRegistry.new()
	var glist := reg.get_general_proficiency_list()
	check(glist.size() > 0,
		"ProficiencyRegistry: general proficiency list should be non-empty")


func test_general_list_has_all_entries() -> void:
	var reg := ProficiencyRegistry.new()
	var glist := reg.get_general_proficiency_list()
	# ACKS Core has 38 general proficiencies
	check(glist.size() >= 38,
		"ProficiencyRegistry: general list should have 38+ entries, got %d" % glist.size())
	# Spot-check a few canonical general proficiencies
	check("adventuring" in glist,
		"ProficiencyRegistry: adventuring must be in general list")
	check("healing" in glist,
		"ProficiencyRegistry: healing must be in general list")
	check("leadership" in glist,
		"ProficiencyRegistry: leadership must be in general list")
	check("survival" in glist,
		"ProficiencyRegistry: survival must be in general list")


func test_get_max_rank_ranked() -> void:
	var reg := ProficiencyRegistry.new()
	check(reg.get_max_rank("healing") == 3,
		"ProficiencyRegistry: healing max_rank should be 3, got %d" % reg.get_max_rank("healing"))
	check(reg.get_max_rank("alchemy") == 3,
		"ProficiencyRegistry: alchemy max_rank should be 3, got %d" % reg.get_max_rank("alchemy"))


func test_get_max_rank_unranked() -> void:
	var reg := ProficiencyRegistry.new()
	check(reg.get_max_rank("divine_blessing") == 1,
		"ProficiencyRegistry: divine_blessing max_rank should be 1, got %d" % reg.get_max_rank("divine_blessing"))


func test_get_selection_rule_unique() -> void:
	var reg := ProficiencyRegistry.new()
	check(reg.get_selection_rule("divine_blessing") == "unique",
		"ProficiencyRegistry: divine_blessing should be 'unique'")


func test_get_selection_rule_specialization() -> void:
	var reg := ProficiencyRegistry.new()
	check(reg.get_selection_rule("fighting_style") == "specialization",
		"ProficiencyRegistry: fighting_style should be 'specialization'")
	check(reg.get_selection_rule("combat_trickery") == "specialization",
		"ProficiencyRegistry: combat_trickery should be 'specialization'")


func test_get_selection_rule_stacking() -> void:
	var reg := ProficiencyRegistry.new()
	check(reg.get_selection_rule("healing") == "stacking",
		"ProficiencyRegistry: healing should be 'stacking'")


func test_effects_for_rank_non_ranked() -> void:
	var reg := ProficiencyRegistry.new()
	var effects := reg.get_effects_for_rank("divine_blessing", 1)
	check(not effects.is_empty(),
		"ProficiencyRegistry: divine_blessing rank 1 effects should not be empty")
	var modifiers: Array = effects.get("modifiers", [])
	check(modifiers.size() == 5,
		"ProficiencyRegistry: divine_blessing should have 5 save modifiers, got %d" % modifiers.size())
	# All should be -2 add on saves
	for mod in modifiers:
		check(mod.get("value", 0) == -2,
			"ProficiencyRegistry: divine_blessing modifier value should be -2, got %d" % mod.get("value", 0))


func test_effects_for_rank_ranked() -> void:
	var reg := ProficiencyRegistry.new()
	var effects1 := reg.get_effects_for_rank("healing", 1)
	var effects2 := reg.get_effects_for_rank("healing", 2)
	var effects3 := reg.get_effects_for_rank("healing", 3)
	check(not effects1.is_empty(),
		"ProficiencyRegistry: healing rank 1 effects should not be empty")
	check(not effects2.is_empty(),
		"ProficiencyRegistry: healing rank 2 effects should not be empty")
	check(not effects3.is_empty(),
		"ProficiencyRegistry: healing rank 3 effects should not be empty")


func test_effects_for_specialization() -> void:
	var reg := ProficiencyRegistry.new()
	var effects := reg.get_effects_for_specialization("fighting_style", "missile")
	check(not effects.is_empty(),
		"ProficiencyRegistry: fighting_style/missile effects should not be empty")
	var modifiers: Array = effects.get("modifiers", [])
	check(modifiers.size() > 0,
		"ProficiencyRegistry: fighting_style/missile should have at least 1 modifier")


func test_level_scaling_has_scaling() -> void:
	var reg := ProficiencyRegistry.new()
	check(reg.has_level_scaling("swashbuckling"),
		"ProficiencyRegistry: swashbuckling should have level scaling")
	check(not reg.has_level_scaling("divine_blessing"),
		"ProficiencyRegistry: divine_blessing should not have level scaling")


func test_level_scaling_breakpoints() -> void:
	var reg := ProficiencyRegistry.new()
	# swashbuckling: +1 AC at level 1, +2 at level 7, +3 at level 13
	check(reg.get_scaled_bonus("swashbuckling", 1) == 1,
		"ProficiencyRegistry: swashbuckling at level 1 should give bonus 1, got %d" % reg.get_scaled_bonus("swashbuckling", 1))
	check(reg.get_scaled_bonus("swashbuckling", 7) == 2,
		"ProficiencyRegistry: swashbuckling at level 7 should give bonus 2, got %d" % reg.get_scaled_bonus("swashbuckling", 7))
	check(reg.get_scaled_bonus("swashbuckling", 13) == 3,
		"ProficiencyRegistry: swashbuckling at level 13 should give bonus 3, got %d" % reg.get_scaled_bonus("swashbuckling", 13))
	check(reg.get_scaled_bonus("divine_blessing", 5) == 0,
		"ProficiencyRegistry: divine_blessing at level 5 should give bonus 0 (no scaling)")


func test_is_specialization() -> void:
	var reg := ProficiencyRegistry.new()
	check(reg.is_specialization("fighting_style"),
		"ProficiencyRegistry: fighting_style should be a specialization proficiency")
	check(reg.is_specialization("combat_trickery"),
		"ProficiencyRegistry: combat_trickery should be a specialization proficiency")
	check(not reg.is_specialization("divine_blessing"),
		"ProficiencyRegistry: divine_blessing should NOT be a specialization proficiency")


func test_compound_key_single_segment() -> void:
	## Compound key with single underscore suffix: "combat_trickery_disarm"
	var reg := ProficiencyRegistry.new()
	check(reg.has_proficiency("combat_trickery_disarm"),
		"ProficiencyRegistry: combat_trickery_disarm should resolve via compound key")
	var entry := reg.get_proficiency("combat_trickery_disarm")
	check(entry.get("proficiency_key", "") == "combat_trickery",
		"ProficiencyRegistry: combat_trickery_disarm should resolve to base key 'combat_trickery'")


func test_compound_key_multi_segment() -> void:
	## Compound key with multi-underscore specialization: "combat_trickery_force_back"
	var reg := ProficiencyRegistry.new()
	check(reg.has_proficiency("combat_trickery_force_back"),
		"ProficiencyRegistry: combat_trickery_force_back should resolve (multi-segment spec)")
	check(reg.has_proficiency("combat_trickery_knock_down"),
		"ProficiencyRegistry: combat_trickery_knock_down should resolve (multi-segment spec)")
	# Effects for that specialization should be accessible
	var effects := reg.get_effects_for_specialization("combat_trickery", "force_back")
	check(not effects.is_empty(),
		"ProficiencyRegistry: combat_trickery/force_back effects should not be empty")


func test_all_class_json_keys_resolve() -> void:
	## Validates that every proficiency key in every class JSON resolves in the registry.
	## This catches typos and catalog gaps early.
	var reg := ProficiencyRegistry.new()
	var class_dir := "res://data/classes/"
	var dir := DirAccess.open(class_dir)
	if dir == null:
		push_error("ProficiencyRegistry test: cannot open %s" % class_dir)
		check(false, "ProficiencyRegistry: cannot open class data directory")
		return

	var failed_keys: Array[String] = []
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".json"):
			var path := class_dir + fname
			var file := FileAccess.open(path, FileAccess.READ)
			if file != null:
				var json := JSON.new()
				if json.parse(file.get_as_text()) == OK:
					var data: Dictionary = json.data
					var keys: Array = data.get("class_proficiency_list", [])
					for k in keys:
						if not reg.has_proficiency(k):
							failed_keys.append("%s (in %s)" % [k, fname])
				file.close()
		fname = dir.get_next()
	dir.list_dir_end()

	check(failed_keys.is_empty(),
		"ProficiencyRegistry: %d class JSON key(s) do not resolve in catalog: %s" % [
			failed_keys.size(), ", ".join(failed_keys)])


func test_get_available_specializations_closed_list() -> void:
	## Closed-list proficiencies (inline array) return their own array.
	var reg := ProficiencyRegistry.new()
	var specs := reg.get_available_specializations("combat_trickery")
	check(specs.size() > 0,
		"ProficiencyRegistry: combat_trickery should have available specializations (closed-list)")
	check("disarm" in specs,
		"ProficiencyRegistry: combat_trickery closed-list should include 'disarm'")


func test_get_available_specializations_registry() -> void:
	## Registry-backed proficiencies return IDs from SpecializationRegistry.
	var spec_reg := SpecializationRegistry.new()
	var reg := ProficiencyRegistry.new(spec_reg)
	var specs := reg.get_available_specializations("riding")
	check(specs.size() == 15,
		"ProficiencyRegistry: riding should have 15 available specializations, got %d" % specs.size())
	check("horses" in specs,
		"ProficiencyRegistry: riding should include 'horses'")
	# Reclassified proficiencies also work
	var naturalism_specs := reg.get_available_specializations("naturalism")
	check(naturalism_specs.size() == 11,
		"ProficiencyRegistry: naturalism should have 11 specializations, got %d" % naturalism_specs.size())


func test_get_available_specializations_non_spec() -> void:
	## Non-specialization proficiencies return empty array.
	var reg := ProficiencyRegistry.new()
	var specs := reg.get_available_specializations("divine_blessing")
	check(specs.is_empty(),
		"ProficiencyRegistry: divine_blessing should return empty specializations array")


func test_get_available_specializations_no_registry() -> void:
	## Registry-backed proficiencies without a wired SpecializationRegistry return empty.
	var reg := ProficiencyRegistry.new()  # no spec_registry passed
	var specs := reg.get_available_specializations("riding")
	check(specs.is_empty(),
		"ProficiencyRegistry: riding without SpecializationRegistry should return empty array")


func test_public_compound_key_method() -> void:
	## get_specialization_from_compound_key() is the public API.
	var reg := ProficiencyRegistry.new()
	check(reg.get_specialization_from_compound_key("knowledge_history") == "history",
		"ProficiencyRegistry: compound key 'knowledge_history' should yield spec 'history'")
	check(reg.get_specialization_from_compound_key("combat_trickery_force_back") == "force_back",
		"ProficiencyRegistry: compound key 'combat_trickery_force_back' should yield 'force_back'")
	check(reg.get_specialization_from_compound_key("divine_blessing") == "",
		"ProficiencyRegistry: non-compound key should return empty string")


func test_public_resolve_key_method() -> void:
	## resolve_key() is the public API for base key resolution.
	var reg := ProficiencyRegistry.new()
	check(reg.resolve_key("knowledge_history") == "knowledge",
		"ProficiencyRegistry: resolve_key('knowledge_history') should return 'knowledge'")
	check(reg.resolve_key("combat_trickery_disarm") == "combat_trickery",
		"ProficiencyRegistry: resolve_key('combat_trickery_disarm') should return 'combat_trickery'")
	check(reg.resolve_key("divine_blessing") == "divine_blessing",
		"ProficiencyRegistry: resolve_key of a plain key should return itself")
	check(reg.resolve_key("not_real_key_xyz") == "",
		"ProficiencyRegistry: resolve_key of unknown key should return empty string")


func test_specialization_display_name_via_registry() -> void:
	## get_specialization_display_name() uses SpecializationRegistry when available.
	var spec_reg := SpecializationRegistry.new()
	var reg := ProficiencyRegistry.new(spec_reg)
	check(reg.get_specialization_display_name("knowledge", "history") == "History",
		"ProficiencyRegistry: knowledge/history display name should be 'History'")
	# Closed-list fallback (no spec registry entry, just titlecase)
	var reg_no_spec := ProficiencyRegistry.new()
	var fallback := reg_no_spec.get_specialization_display_name("riding", "horses")
	check(not fallback.is_empty(),
		"ProficiencyRegistry: fallback display name for riding/horses should not be empty")
