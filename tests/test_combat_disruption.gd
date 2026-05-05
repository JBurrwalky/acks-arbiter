extends "res://tests/test_suite_base.gd"

## Unit tests for the Session 2 combat-disruption seam:
## - Combatant.is_casting_spell_this_round / is_cast_disrupted_this_round
## - Combatant.clear_spell_declaration
## - CharacterData.get_effective_ac_vs (directional AC fallback)


func run_all_tests() -> void:
	test_combatant_not_casting_when_no_declared_spell()
	test_combatant_casting_when_declared_spell_set()
	test_disrupted_when_casting_and_damaged()
	test_not_disrupted_when_only_declared()
	test_clear_spell_declaration_resets_state()
	test_directional_ac_falls_back_to_omni()
	test_directional_ac_set_floor_higher_than_base()
	test_directional_ac_set_floor_does_not_degrade()
	if not has_failures():
		print("CombatDisruption: all tests passed.")


func _make_combatant() -> Combatant:
	# Use a minimal CharacterData wrapper for Combatant — avoids needing a
	# full monster catalog for these state-only tests.
	var c := Combatant.new()
	c.id = "test_combatant"
	c.display_name = "Test"
	return c


func test_combatant_not_casting_when_no_declared_spell() -> void:
	var c := _make_combatant()
	check(not c.is_casting_spell_this_round(),
		"is_casting_spell_this_round false when declared_spell empty")


func test_combatant_casting_when_declared_spell_set() -> void:
	var c := _make_combatant()
	c.declared_spell = "magic_missile"
	check(c.is_casting_spell_this_round(),
		"is_casting_spell_this_round true when declared_spell set")


func test_disrupted_when_casting_and_damaged() -> void:
	var c := _make_combatant()
	c.declared_spell = "magic_missile"
	c.damaged_since_declaration = true
	check(c.is_cast_disrupted_this_round(),
		"is_cast_disrupted_this_round true when casting + damaged")


func test_not_disrupted_when_only_declared() -> void:
	var c := _make_combatant()
	c.declared_spell = "magic_missile"
	c.damaged_since_declaration = false
	check(not c.is_cast_disrupted_this_round(),
		"is_cast_disrupted_this_round false when no damage")


func test_clear_spell_declaration_resets_state() -> void:
	var c := _make_combatant()
	c.declared_spell = "fireball"
	c.damaged_since_declaration = true
	c.clear_spell_declaration()
	check(c.declared_spell == "", "clear: declared_spell empty")
	check(not c.damaged_since_declaration, "clear: damaged_since_declaration false")
	check(not c.is_casting_spell_this_round(),
		"clear: not casting after reset")


func test_directional_ac_falls_back_to_omni() -> void:
	var cd := CharacterData.new()
	cd.armor_class = 5  # ascending AC: +5 over baseline
	check(cd.get_effective_ac_vs("missiles") == 5,
		"vs_missiles falls back to armor_class when no directional modifier, got %d" % cd.get_effective_ac_vs("missiles"))
	check(cd.get_effective_ac_vs("melee") == 5,
		"vs_melee falls back to armor_class when no directional modifier")


func test_directional_ac_set_floor_higher_than_base() -> void:
	var cd := CharacterData.new()
	cd.armor_class = 1
	# Shield: set_floor 2 vs missiles, set_floor 4 vs melee.
	cd.modifiers.add_modifier("armor_class_vs_missiles", {
		"source_id": "spell:shield:test",
		"source_type": "spell",
		"operation": "set_floor",
		"value": 2,
	})
	cd.modifiers.add_modifier("armor_class_vs_melee", {
		"source_id": "spell:shield:test",
		"source_type": "spell",
		"operation": "set_floor",
		"value": 4,
	})
	check(cd.get_effective_ac_vs("missiles") == 2,
		"Shield: vs_missiles = 2 (set_floor over base 1), got %d" % cd.get_effective_ac_vs("missiles"))
	check(cd.get_effective_ac_vs("melee") == 4,
		"Shield: vs_melee = 4 (set_floor over base 1), got %d" % cd.get_effective_ac_vs("melee"))


func test_directional_ac_set_floor_does_not_degrade() -> void:
	var cd := CharacterData.new()
	cd.armor_class = 6  # already better than Shield's floor of 4
	cd.modifiers.add_modifier("armor_class_vs_melee", {
		"source_id": "spell:shield:test",
		"source_type": "spell",
		"operation": "set_floor",
		"value": 4,
	})
	check(cd.get_effective_ac_vs("melee") == 6,
		"Shield set_floor doesn't degrade AC 6 to 4, got %d" % cd.get_effective_ac_vs("melee"))
