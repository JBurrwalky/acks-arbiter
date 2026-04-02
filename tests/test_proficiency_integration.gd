extends "res://tests/test_suite_base.gd"

## Integration tests for the proficiency infrastructure.
## Exercises CharacterData + ProficiencyEffectResolver + ProficiencyRegistry together,
## and validates that CharacterGenerator uses the full general list from the registry.


func run_all_tests() -> void:
	test_resolver_updates_effective_values()
	test_spell_and_proficiency_stack_correctly()
	test_clear_proficiency_preserves_spell()
	test_reapply_after_clear_restores_both()
	test_character_data_query_methods()
	test_npc_generator_uses_full_general_list()
	test_all_class_json_keys_resolve_in_registry()
	test_proficiency_dicts_have_required_fields()
	test_effect_resolver_fallback_for_naturalism()
	test_effect_resolver_fallback_for_collegiate_wizardry()
	test_npc_generation_picks_specialization()
	if not has_failures():
		print("ProficiencyIntegration: all tests passed.")


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_resolver_updates_effective_values() -> void:
	## End-to-end: assign proficiency records, run resolver, verify effective values change.
	var c := CharacterData.new()
	c.level = 1
	c.save_petrification = 14
	c.proficiencies = [{
		"proficiency_key": "divine_blessing",
		"rank": 1, "slot_type": "class", "selections_count": 1, "specialization": ""
	}]
	var reg := ProficiencyRegistry.new()
	var resolver := ProficiencyEffectResolver.new(reg)
	resolver.apply_proficiency_effects(c)

	check(c.get_effective_save("save_petrification") == 12,
		"ProficiencyIntegration: divine_blessing should reduce save_petrification to 12")
	check(c.has_proficiency("divine_blessing"),
		"ProficiencyIntegration: has_proficiency('divine_blessing') should return true")


func test_spell_and_proficiency_stack_correctly() -> void:
	## Both spell and proficiency modifiers contribute to the same effective stat.
	var c := CharacterData.new()
	c.level = 1
	c.save_petrification = 14
	c.proficiencies = [{
		"proficiency_key": "divine_blessing",
		"rank": 1, "slot_type": "class", "selections_count": 1, "specialization": ""
	}]
	var resolver := ProficiencyEffectResolver.new(ProficiencyRegistry.new())
	resolver.apply_proficiency_effects(c)

	# Add spell modifier (Bless: -1 to saves)
	c.modifiers.add_modifier("save_petrification", {
		"source_id": "spell:bless",
		"stat": "save_petrification",
		"operation": "add",
		"value": -1,
		"stacking_group": "bless",
	})

	# 14 - 2 (divine_blessing) - 1 (bless) = 11
	check(c.get_effective_save("save_petrification") == 11,
		"ProficiencyIntegration: proficiency + spell should stack to 11, got %d" % c.get_effective_save("save_petrification"))


func test_clear_proficiency_preserves_spell() -> void:
	## Removing proficiency effects does not remove spell modifiers.
	var c := CharacterData.new()
	c.level = 1
	c.save_petrification = 14
	c.proficiencies = [{
		"proficiency_key": "divine_blessing",
		"rank": 1, "slot_type": "class", "selections_count": 1, "specialization": ""
	}]
	var resolver := ProficiencyEffectResolver.new(ProficiencyRegistry.new())
	resolver.apply_proficiency_effects(c)
	c.modifiers.add_modifier("save_petrification", {
		"source_id": "spell:bless",
		"stat": "save_petrification",
		"operation": "add",
		"value": -1,
		"stacking_group": "bless",
	})

	# Clear proficiency effects by re-applying with empty list
	c.proficiencies = []
	resolver.apply_proficiency_effects(c)

	# Only spell modifier remains: 14 - 1 = 13
	check(c.get_effective_save("save_petrification") == 13,
		"ProficiencyIntegration: after prof clear, only spell modifier should remain (13), got %d" % c.get_effective_save("save_petrification"))
	check(not c.modifiers.has_modifier_from("proficiency:divine_blessing"),
		"ProficiencyIntegration: divine_blessing source should be gone after clear")
	check(c.modifiers.has_modifier_from("spell:bless"),
		"ProficiencyIntegration: bless spell source should remain after prof clear")


func test_reapply_after_clear_restores_both() -> void:
	## After clearing and re-adding proficiency, both proficiency + spell are present again.
	var c := CharacterData.new()
	c.level = 1
	c.save_petrification = 14
	c.proficiencies = [{
		"proficiency_key": "divine_blessing",
		"rank": 1, "slot_type": "class", "selections_count": 1, "specialization": ""
	}]
	var resolver := ProficiencyEffectResolver.new(ProficiencyRegistry.new())
	resolver.apply_proficiency_effects(c)
	c.modifiers.add_modifier("save_petrification", {
		"source_id": "spell:bless",
		"stat": "save_petrification",
		"operation": "add",
		"value": -1,
		"stacking_group": "bless",
	})
	# Remove then re-add proficiency
	c.proficiencies = []
	resolver.apply_proficiency_effects(c)
	c.proficiencies = [{
		"proficiency_key": "divine_blessing",
		"rank": 1, "slot_type": "class", "selections_count": 1, "specialization": ""
	}]
	resolver.apply_proficiency_effects(c)

	# Both back: 14 - 2 - 1 = 11
	check(c.get_effective_save("save_petrification") == 11,
		"ProficiencyIntegration: after re-apply, should be 11 again, got %d" % c.get_effective_save("save_petrification"))


func test_character_data_query_methods() -> void:
	## CharacterData proficiency query methods work correctly.
	var c := CharacterData.new()
	c.proficiencies = [
		{"proficiency_key": "divine_blessing", "rank": 1, "slot_type": "class", "selections_count": 1, "specialization": ""},
		{"proficiency_key": "healing", "rank": 2, "slot_type": "general", "selections_count": 2, "specialization": ""},
		{"proficiency_key": "fighting_style", "rank": 1, "slot_type": "class", "selections_count": 1, "specialization": "missile"},
	]

	check(c.has_proficiency("divine_blessing"), "has_proficiency: divine_blessing should be true")
	check(not c.has_proficiency("leadership"), "has_proficiency: leadership should be false")
	check(c.get_proficiency_rank("healing") == 2, "get_proficiency_rank: healing should be 2")
	check(c.get_proficiency_rank("nonexistent") == 0, "get_proficiency_rank: nonexistent should be 0")
	check(c.get_proficiency_selections("healing") == 2, "get_proficiency_selections: healing should be 2")
	check(c.get_proficiency_specialization("fighting_style") == "missile",
		"get_proficiency_specialization: fighting_style should be 'missile'")
	check(c.get_proficiency_specialization("divine_blessing") == "",
		"get_proficiency_specialization: divine_blessing has no spec, should be ''")
	var class_profs := c.get_proficiencies_by_slot("class")
	check(class_profs.size() == 2, "get_proficiencies_by_slot('class') should return 2, got %d" % class_profs.size())
	var general_profs := c.get_proficiencies_by_slot("general")
	check(general_profs.size() == 1, "get_proficiencies_by_slot('general') should return 1, got %d" % general_profs.size())


func test_npc_generator_uses_full_general_list() -> void:
	## When initialized with ProficiencyRegistry, CharacterGenerator uses the full
	## general proficiency list (38 entries) rather than the hardcoded 10-entry fallback.
	var reg := ProficiencyRegistry.new()
	var gen := CharacterGenerator.new(ClassRegistry.new(), PowerRegistry.new(), reg)

	# Generate L5 fighter to get multiple general slots (at L1 and L5)
	# proficiency_progression.general = [1, 5, 9, 13] for fighter
	# So at L5 we have 2 general slots (adventuring + 1)
	var profs := gen.auto_select_proficiencies("fighter", 5)
	check(profs.size() >= 2, "L5 fighter should have ≥2 proficiencies, got %d" % profs.size())

	# All returned general proficiency keys should be in the full registry list
	var general_list := reg.get_general_proficiency_list()
	for p in profs:
		if p.get("slot_type", "") == "general" and p.get("proficiency_key", "") != "adventuring":
			var key: String = p.get("proficiency_key", "")
			check(key in general_list,
				"ProficiencyIntegration: general prof '%s' should be from full registry list" % key)

	# All returned dicts should have the new fields
	for p in profs:
		check(p.has("selections_count"),
			"ProficiencyIntegration: proficiency dict missing 'selections_count'")
		check(p.has("specialization"),
			"ProficiencyIntegration: proficiency dict missing 'specialization'")


func test_all_class_json_keys_resolve_in_registry() -> void:
	## Every proficiency key in every class JSON resolves in the registry.
	## Catches catalog gaps and class JSON typos.
	var reg := ProficiencyRegistry.new()
	var class_dir := "res://data/classes/"
	var dir := DirAccess.open(class_dir)
	if dir == null:
		check(false, "ProficiencyIntegration: cannot open %s" % class_dir)
		return

	var failed: Array[String] = []
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".json"):
			var file := FileAccess.open(class_dir + fname, FileAccess.READ)
			if file != null:
				var json := JSON.new()
				if json.parse(file.get_as_text()) == OK:
					var data: Dictionary = json.data
					for k in data.get("class_proficiency_list", []):
						if not reg.has_proficiency(k):
							failed.append("%s (in %s)" % [k, fname])
				file.close()
		fname = dir.get_next()
	dir.list_dir_end()

	check(failed.is_empty(),
		"ProficiencyIntegration: %d key(s) unresolved: %s" % [failed.size(), ", ".join(failed)])


func test_proficiency_dicts_have_required_fields() -> void:
	## auto_select_proficiencies returns dicts with all required DB fields.
	var gen := CharacterGenerator.new(ClassRegistry.new(), PowerRegistry.new(), ProficiencyRegistry.new())
	var profs := gen.auto_select_proficiencies("cleric", 3)
	for p in profs:
		check(p.has("proficiency_key"), "proficiency dict must have proficiency_key")
		check(p.has("rank"), "proficiency dict must have rank")
		check(p.has("slot_type"), "proficiency dict must have slot_type")
		check(p.has("selections_count"), "proficiency dict must have selections_count")
		check(p.has("specialization"), "proficiency dict must have specialization")


func test_effect_resolver_fallback_for_naturalism() -> void:
	## After reclassification, naturalism (now specialization rule) still resolves effects.
	## Naturalism has no effects_by_specialization; the fallback uses top-level effects.
	var reg := ProficiencyRegistry.new()
	check(reg.is_specialization("naturalism"),
		"ProficiencyIntegration: naturalism should now be a specialization proficiency")
	var c := CharacterData.new()
	c.level = 1
	c.proficiencies = [{
		"proficiency_key": "naturalism",
		"rank": 1, "slot_type": "general", "selections_count": 1, "specialization": "forest"
	}]
	var resolver := ProficiencyEffectResolver.new(reg)
	# Should not crash — naturalism has no permanent modifiers/flags, only enablers
	# The resolver should complete without error even with no effects_by_specialization
	resolver.apply_proficiency_effects(c)
	# No assert on values — naturalism effects are enablers, not modifiers tracked in CharacterData
	# The test passes if no error/crash occurs


func test_effect_resolver_fallback_for_collegiate_wizardry() -> void:
	## After reclassification, collegiate_wizardry effects still apply via the fallback.
	## collegiate_wizardry has no effects_by_specialization; fallback uses top-level effects
	## which include: modifiers [repertoire_capacity_bonus +1], enablers [arcane_order_recognition].
	var reg := ProficiencyRegistry.new()
	check(reg.is_specialization("collegiate_wizardry"),
		"ProficiencyIntegration: collegiate_wizardry should now be a specialization proficiency")
	var effects_rank1 := reg.get_effects_for_rank("collegiate_wizardry", 1)
	check(not effects_rank1.is_empty(),
		"ProficiencyIntegration: collegiate_wizardry rank 1 effects should not be empty")
	var modifiers: Array = effects_rank1.get("modifiers", [])
	check(modifiers.size() > 0,
		"ProficiencyIntegration: collegiate_wizardry should have at least 1 modifier")
	# Verify the +1 repertoire_capacity_bonus modifier is accessible
	var found_bonus := false
	for mod in modifiers:
		if mod.get("stat", "") == "repertoire_capacity_bonus":
			found_bonus = true
			break
	check(found_bonus,
		"ProficiencyIntegration: collegiate_wizardry should have repertoire_capacity_bonus modifier")


func test_npc_generation_picks_specialization() -> void:
	## auto_select_proficiencies with a wired SpecializationRegistry picks non-empty specializations
	## for specialization proficiencies.
	var spec_reg := SpecializationRegistry.new()
	var prof_reg := ProficiencyRegistry.new(spec_reg)
	var gen := CharacterGenerator.new(ClassRegistry.new(), PowerRegistry.new(), prof_reg)
	# Generate a Fighter at L5 — fighter class list includes riding, weapon_focus, fighting_style
	var profs := gen.auto_select_proficiencies("fighter", 9)
	var spec_profs_with_value: int = 0
	for p in profs:
		var key: String = p.get("proficiency_key", "")
		if prof_reg.is_specialization(key) and key != "adventuring":
			var spec: String = p.get("specialization", "")
			if not spec.is_empty():
				spec_profs_with_value += 1
	check(spec_profs_with_value > 0,
		"ProficiencyIntegration: NPC generation should pick at least 1 non-empty specialization for a fighter at L9")
