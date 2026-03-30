extends Node

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
	print("ProficiencyRegistry: all tests passed.")


# ---------------------------------------------------------------------------

func test_catalog_loads() -> void:
	var reg := ProficiencyRegistry.new()
	assert(reg.get_proficiency_count() > 0,
		"ProficiencyRegistry: catalog should have loaded at least 1 proficiency")


func test_proficiency_count_reasonable() -> void:
	var reg := ProficiencyRegistry.new()
	assert(reg.get_proficiency_count() >= 100,
		"ProficiencyRegistry: catalog should have 100+ proficiencies, got %d" % reg.get_proficiency_count())


func test_has_proficiency_true() -> void:
	var reg := ProficiencyRegistry.new()
	assert(reg.has_proficiency("divine_blessing"),
		"ProficiencyRegistry: divine_blessing should exist in catalog")
	assert(reg.has_proficiency("healing"),
		"ProficiencyRegistry: healing should exist in catalog")


func test_has_proficiency_false() -> void:
	var reg := ProficiencyRegistry.new()
	assert(not reg.has_proficiency("not_a_real_proficiency"),
		"ProficiencyRegistry: garbage key should not exist")


func test_get_proficiency_divine_blessing() -> void:
	var reg := ProficiencyRegistry.new()
	var entry := reg.get_proficiency("divine_blessing")
	assert(not entry.is_empty(),
		"ProficiencyRegistry: divine_blessing entry should not be empty")
	assert(entry.get("proficiency_name", "") == "Divine Blessing",
		"ProficiencyRegistry: divine_blessing name should be 'Divine Blessing', got '%s'" % entry.get("proficiency_name", ""))
	assert(entry.get("max_rank", 0) == 1,
		"ProficiencyRegistry: divine_blessing max_rank should be 1")
	assert(entry.get("selection_rule", "") == "unique",
		"ProficiencyRegistry: divine_blessing selection_rule should be unique")


func test_general_list_loads() -> void:
	var reg := ProficiencyRegistry.new()
	var glist := reg.get_general_proficiency_list()
	assert(glist.size() > 0,
		"ProficiencyRegistry: general proficiency list should be non-empty")


func test_general_list_has_all_entries() -> void:
	var reg := ProficiencyRegistry.new()
	var glist := reg.get_general_proficiency_list()
	# ACKS Core has 38 general proficiencies
	assert(glist.size() >= 38,
		"ProficiencyRegistry: general list should have 38+ entries, got %d" % glist.size())
	# Spot-check a few canonical general proficiencies
	assert("adventuring" in glist,
		"ProficiencyRegistry: adventuring must be in general list")
	assert("healing" in glist,
		"ProficiencyRegistry: healing must be in general list")
	assert("leadership" in glist,
		"ProficiencyRegistry: leadership must be in general list")
	assert("survival" in glist,
		"ProficiencyRegistry: survival must be in general list")


func test_get_max_rank_ranked() -> void:
	var reg := ProficiencyRegistry.new()
	assert(reg.get_max_rank("healing") == 3,
		"ProficiencyRegistry: healing max_rank should be 3, got %d" % reg.get_max_rank("healing"))
	assert(reg.get_max_rank("alchemy") == 3,
		"ProficiencyRegistry: alchemy max_rank should be 3, got %d" % reg.get_max_rank("alchemy"))


func test_get_max_rank_unranked() -> void:
	var reg := ProficiencyRegistry.new()
	assert(reg.get_max_rank("divine_blessing") == 1,
		"ProficiencyRegistry: divine_blessing max_rank should be 1, got %d" % reg.get_max_rank("divine_blessing"))


func test_get_selection_rule_unique() -> void:
	var reg := ProficiencyRegistry.new()
	assert(reg.get_selection_rule("divine_blessing") == "unique",
		"ProficiencyRegistry: divine_blessing should be 'unique'")


func test_get_selection_rule_specialization() -> void:
	var reg := ProficiencyRegistry.new()
	assert(reg.get_selection_rule("fighting_style") == "specialization",
		"ProficiencyRegistry: fighting_style should be 'specialization'")
	assert(reg.get_selection_rule("combat_trickery") == "specialization",
		"ProficiencyRegistry: combat_trickery should be 'specialization'")


func test_get_selection_rule_stacking() -> void:
	var reg := ProficiencyRegistry.new()
	assert(reg.get_selection_rule("healing") == "stacking",
		"ProficiencyRegistry: healing should be 'stacking'")


func test_effects_for_rank_non_ranked() -> void:
	var reg := ProficiencyRegistry.new()
	var effects := reg.get_effects_for_rank("divine_blessing", 1)
	assert(not effects.is_empty(),
		"ProficiencyRegistry: divine_blessing rank 1 effects should not be empty")
	var modifiers: Array = effects.get("modifiers", [])
	assert(modifiers.size() == 5,
		"ProficiencyRegistry: divine_blessing should have 5 save modifiers, got %d" % modifiers.size())
	# All should be -2 add on saves
	for mod in modifiers:
		assert(mod.get("value", 0) == -2,
			"ProficiencyRegistry: divine_blessing modifier value should be -2, got %d" % mod.get("value", 0))


func test_effects_for_rank_ranked() -> void:
	var reg := ProficiencyRegistry.new()
	var effects1 := reg.get_effects_for_rank("healing", 1)
	var effects2 := reg.get_effects_for_rank("healing", 2)
	var effects3 := reg.get_effects_for_rank("healing", 3)
	assert(not effects1.is_empty(),
		"ProficiencyRegistry: healing rank 1 effects should not be empty")
	assert(not effects2.is_empty(),
		"ProficiencyRegistry: healing rank 2 effects should not be empty")
	assert(not effects3.is_empty(),
		"ProficiencyRegistry: healing rank 3 effects should not be empty")


func test_effects_for_specialization() -> void:
	var reg := ProficiencyRegistry.new()
	var effects := reg.get_effects_for_specialization("fighting_style", "missile")
	assert(not effects.is_empty(),
		"ProficiencyRegistry: fighting_style/missile effects should not be empty")
	var modifiers: Array = effects.get("modifiers", [])
	assert(modifiers.size() > 0,
		"ProficiencyRegistry: fighting_style/missile should have at least 1 modifier")


func test_level_scaling_has_scaling() -> void:
	var reg := ProficiencyRegistry.new()
	assert(reg.has_level_scaling("swashbuckling"),
		"ProficiencyRegistry: swashbuckling should have level scaling")
	assert(not reg.has_level_scaling("divine_blessing"),
		"ProficiencyRegistry: divine_blessing should not have level scaling")


func test_level_scaling_breakpoints() -> void:
	var reg := ProficiencyRegistry.new()
	# swashbuckling: +1 AC at level 1, +2 at level 7, +3 at level 13
	assert(reg.get_scaled_bonus("swashbuckling", 1) == 1,
		"ProficiencyRegistry: swashbuckling at level 1 should give bonus 1, got %d" % reg.get_scaled_bonus("swashbuckling", 1))
	assert(reg.get_scaled_bonus("swashbuckling", 7) == 2,
		"ProficiencyRegistry: swashbuckling at level 7 should give bonus 2, got %d" % reg.get_scaled_bonus("swashbuckling", 7))
	assert(reg.get_scaled_bonus("swashbuckling", 13) == 3,
		"ProficiencyRegistry: swashbuckling at level 13 should give bonus 3, got %d" % reg.get_scaled_bonus("swashbuckling", 13))
	assert(reg.get_scaled_bonus("divine_blessing", 5) == 0,
		"ProficiencyRegistry: divine_blessing at level 5 should give bonus 0 (no scaling)")


func test_is_specialization() -> void:
	var reg := ProficiencyRegistry.new()
	assert(reg.is_specialization("fighting_style"),
		"ProficiencyRegistry: fighting_style should be a specialization proficiency")
	assert(reg.is_specialization("combat_trickery"),
		"ProficiencyRegistry: combat_trickery should be a specialization proficiency")
	assert(not reg.is_specialization("divine_blessing"),
		"ProficiencyRegistry: divine_blessing should NOT be a specialization proficiency")


func test_compound_key_single_segment() -> void:
	## Compound key with single underscore suffix: "combat_trickery_disarm"
	var reg := ProficiencyRegistry.new()
	assert(reg.has_proficiency("combat_trickery_disarm"),
		"ProficiencyRegistry: combat_trickery_disarm should resolve via compound key")
	var entry := reg.get_proficiency("combat_trickery_disarm")
	assert(entry.get("proficiency_key", "") == "combat_trickery",
		"ProficiencyRegistry: combat_trickery_disarm should resolve to base key 'combat_trickery'")


func test_compound_key_multi_segment() -> void:
	## Compound key with multi-underscore specialization: "combat_trickery_force_back"
	var reg := ProficiencyRegistry.new()
	assert(reg.has_proficiency("combat_trickery_force_back"),
		"ProficiencyRegistry: combat_trickery_force_back should resolve (multi-segment spec)")
	assert(reg.has_proficiency("combat_trickery_knock_down"),
		"ProficiencyRegistry: combat_trickery_knock_down should resolve (multi-segment spec)")
	# Effects for that specialization should be accessible
	var effects := reg.get_effects_for_specialization("combat_trickery", "force_back")
	assert(not effects.is_empty(),
		"ProficiencyRegistry: combat_trickery/force_back effects should not be empty")


func test_all_class_json_keys_resolve() -> void:
	## Validates that every proficiency key in every class JSON resolves in the registry.
	## This catches typos and catalog gaps early.
	var reg := ProficiencyRegistry.new()
	var class_dir := "res://data/classes/"
	var dir := DirAccess.open(class_dir)
	if dir == null:
		push_error("ProficiencyRegistry test: cannot open %s" % class_dir)
		assert(false, "ProficiencyRegistry: cannot open class data directory")
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

	assert(failed_keys.is_empty(),
		"ProficiencyRegistry: %d class JSON key(s) do not resolve in catalog: %s" % [
			failed_keys.size(), ", ".join(failed_keys)])
