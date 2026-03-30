extends Node

## Unit tests for ProficiencyEffectResolver.
## Verifies that permanent, unconditional proficiency effects are applied correctly,
## conditional effects are skipped, and proficiency/spell modifiers coexist.


func run_all_tests() -> void:
	test_divine_blessing_applies_saves()
	test_divine_health_sets_flag()
	test_apply_is_idempotent()
	test_conditional_modifier_not_applied()
	test_unknown_proficiency_does_not_crash()
	test_stub_proficiency_does_not_crash()
	test_source_id_format()
	test_spell_and_proficiency_modifiers_coexist()
	test_clear_proficiency_leaves_spell_effects()
	test_alertness_applies_modifiers()
	test_leadership_applies_henchman_cap()
	test_collegiate_wizardry_applies_repertoire_bonus()
	print("ProficiencyEffectResolver: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_character_with_proficiency(proficiency_key: String, rank: int = 1, specialization: String = "") -> CharacterData:
	var c := CharacterData.new()
	c.level = 1
	c.proficiencies = [{
		"proficiency_key": proficiency_key,
		"rank": rank,
		"slot_type": "class",
		"selections_count": 1,
		"specialization": specialization,
	}]
	return c


func _make_resolver() -> ProficiencyEffectResolver:
	return ProficiencyEffectResolver.new(ProficiencyRegistry.new())


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_divine_blessing_applies_saves() -> void:
	var c := _make_character_with_proficiency("divine_blessing")
	c.save_petrification = 14
	c.save_poison_death = 14
	c.save_blast_breath = 16
	c.save_staffs_wands = 16
	c.save_spells = 17

	_make_resolver().apply_proficiency_effects(c)

	assert(c.get_effective_save("save_petrification") == 12,
		"ProficiencyEffectResolver: divine_blessing should lower save_petrification to 12, got %d" % c.get_effective_save("save_petrification"))
	assert(c.get_effective_save("save_poison_death") == 12,
		"ProficiencyEffectResolver: divine_blessing should lower save_poison_death to 12, got %d" % c.get_effective_save("save_poison_death"))
	assert(c.get_effective_save("save_blast_breath") == 14,
		"ProficiencyEffectResolver: divine_blessing should lower save_blast_breath to 14, got %d" % c.get_effective_save("save_blast_breath"))
	assert(c.get_effective_save("save_staffs_wands") == 14,
		"ProficiencyEffectResolver: divine_blessing should lower save_staffs_wands to 14, got %d" % c.get_effective_save("save_staffs_wands"))
	assert(c.get_effective_save("save_spells") == 15,
		"ProficiencyEffectResolver: divine_blessing should lower save_spells to 15, got %d" % c.get_effective_save("save_spells"))


func test_divine_health_sets_flag() -> void:
	var c := _make_character_with_proficiency("divine_health")
	_make_resolver().apply_proficiency_effects(c)
	assert(c.flags.has_flag("disease_immunity"),
		"ProficiencyEffectResolver: divine_health should set disease_immunity flag")


func test_apply_is_idempotent() -> void:
	## Applying twice should give the same result as applying once.
	var c := _make_character_with_proficiency("divine_blessing")
	c.save_petrification = 14
	var resolver := _make_resolver()
	resolver.apply_proficiency_effects(c)
	resolver.apply_proficiency_effects(c)  # second apply

	assert(c.get_effective_save("save_petrification") == 12,
		"ProficiencyEffectResolver: double-apply should still give 12, got %d" % c.get_effective_save("save_petrification"))


func test_conditional_modifier_not_applied() -> void:
	## Fighting Style modifiers are all conditional — none should be applied.
	var c := _make_character_with_proficiency("fighting_style", 1, "missile")
	c.attack_throw = 10
	_make_resolver().apply_proficiency_effects(c)
	assert(c.get_effective_attack_throw() == 10,
		"ProficiencyEffectResolver: conditional fighting_style modifier must NOT be applied unconditionally")


func test_unknown_proficiency_does_not_crash() -> void:
	## An unrecognized proficiency key should be silently skipped.
	var c := CharacterData.new()
	c.proficiencies = [{"proficiency_key": "completely_fake_proficiency", "rank": 1, "slot_type": "general", "selections_count": 1, "specialization": ""}]
	_make_resolver().apply_proficiency_effects(c)
	# If we reach here without crashing, the test passes.
	assert(true, "ProficiencyEffectResolver: unknown proficiency key should not crash")


func test_stub_proficiency_does_not_crash() -> void:
	## A catalog entry with empty effects (stub) should apply cleanly without crash.
	var c := _make_character_with_proficiency("adventuring")
	_make_resolver().apply_proficiency_effects(c)
	assert(true, "ProficiencyEffectResolver: stub proficiency should not crash")


func test_source_id_format() -> void:
	## The source_id stored in ModifierContainer should follow "proficiency:<key>" format.
	var c := _make_character_with_proficiency("divine_blessing")
	_make_resolver().apply_proficiency_effects(c)
	assert(c.modifiers.has_modifier_from("proficiency:divine_blessing"),
		"ProficiencyEffectResolver: source ID should be 'proficiency:divine_blessing'")


func test_spell_and_proficiency_modifiers_coexist() -> void:
	## Proficiency modifier and spell modifier on the same stat must both contribute.
	var c := CharacterData.new()
	c.level = 1
	c.save_petrification = 14
	c.proficiencies = [{
		"proficiency_key": "divine_blessing",
		"rank": 1, "slot_type": "class", "selections_count": 1, "specialization": ""
	}]
	# Apply proficiency effects (-2 to saves)
	_make_resolver().apply_proficiency_effects(c)

	# Simulate a spell modifier: +1 bonus to petrification save (value -1, lowers target)
	c.modifiers.add_modifier("save_petrification", {
		"source_id": "spell:bless",
		"stat": "save_petrification",
		"operation": "add",
		"value": -1,
		"stacking_group": "bless",
	})

	# Combined: base 14 - 2 (proficiency) - 1 (spell) = 11
	assert(c.get_effective_save("save_petrification") == 11,
		"ProficiencyEffectResolver: spell + proficiency should stack to 11, got %d" % c.get_effective_save("save_petrification"))


func test_clear_proficiency_leaves_spell_effects() -> void:
	## Clearing proficiency effects must not remove spell modifiers.
	var c := CharacterData.new()
	c.level = 1
	c.save_petrification = 14
	c.proficiencies = [{
		"proficiency_key": "divine_blessing",
		"rank": 1, "slot_type": "class", "selections_count": 1, "specialization": ""
	}]
	var resolver := _make_resolver()
	resolver.apply_proficiency_effects(c)

	# Add a spell modifier
	c.modifiers.add_modifier("save_petrification", {
		"source_id": "spell:bless",
		"stat": "save_petrification",
		"operation": "add",
		"value": -1,
		"stacking_group": "bless",
	})

	# Now remove proficiencies and re-apply with empty list
	c.proficiencies = []
	resolver.apply_proficiency_effects(c)

	# Spell modifier should remain: base 14 - 1 (spell) = 13
	assert(c.get_effective_save("save_petrification") == 13,
		"ProficiencyEffectResolver: spell modifier should remain after proficiency clear, got %d" % c.get_effective_save("save_petrification"))
	# Proficiency modifier should be gone
	assert(not c.modifiers.has_modifier_from("proficiency:divine_blessing"),
		"ProficiencyEffectResolver: proficiency modifier should be cleared")


func test_alertness_applies_modifiers() -> void:
	## Alertness gives +4 hear noise modifier and +4 detect secret doors modifier.
	var c := _make_character_with_proficiency("alertness")
	_make_resolver().apply_proficiency_effects(c)
	var hear_bonus: int = c.modifiers.get_effective_value("hear_noise_modifier", 0)
	assert(hear_bonus == 4,
		"ProficiencyEffectResolver: alertness hear_noise_modifier should be +4, got %d" % hear_bonus)
	var detect_bonus: int = c.modifiers.get_effective_value("detect_secret_doors_modifier", 0)
	assert(detect_bonus == 4,
		"ProficiencyEffectResolver: alertness detect_secret_doors_modifier should be +4, got %d" % detect_bonus)


func test_leadership_applies_henchman_cap() -> void:
	## Leadership gives +1 to henchman_cap_bonus.
	var c := _make_character_with_proficiency("leadership")
	_make_resolver().apply_proficiency_effects(c)
	var bonus: int = c.modifiers.get_effective_value("henchman_cap_bonus", 0)
	assert(bonus == 1,
		"ProficiencyEffectResolver: leadership henchman_cap_bonus should be +1, got %d" % bonus)


func test_collegiate_wizardry_applies_repertoire_bonus() -> void:
	## Collegiate Wizardry gives +1 to repertoire_capacity_bonus.
	var c := _make_character_with_proficiency("collegiate_wizardry")
	_make_resolver().apply_proficiency_effects(c)
	var bonus: int = c.modifiers.get_effective_value("repertoire_capacity_bonus", 0)
	assert(bonus == 1,
		"ProficiencyEffectResolver: collegiate_wizardry repertoire_capacity_bonus should be +1, got %d" % bonus)
