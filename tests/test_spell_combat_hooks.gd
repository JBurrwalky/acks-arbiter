extends "res://tests/test_suite_base.gd"

## Unit tests for SpellCombatHooks.


func run_all_tests() -> void:
	test_no_op_hooks_return_defaults()
	test_on_damage_dealt_sets_damaged_flag()
	test_on_damage_dealt_safe_with_null_tracker()
	test_on_damage_dealt_breaks_concentration()
	test_on_damage_dealt_no_concentration_is_safe()
	test_on_damage_dealt_multiple_concentration()
	if not has_failures():
		print("SpellCombatHooks: all tests passed.")


func test_no_op_hooks_return_defaults() -> void:
	var hooks := SpellCombatHooks.new(null)
	var combatant := _make_fighter("test")
	var roster := CombatRoster.new()

	# Void hooks — just verify no crash
	hooks.on_combat_start(roster)
	hooks.on_round_start(1, roster)
	hooks.on_round_end(1, roster)
	hooks.on_after_action(combatant, {})
	hooks.on_spell_declared(combatant, "fireball", [])
	hooks.on_spell_interrupted(combatant, "fireball")

	# Dict hooks — verify return empty
	check(hooks.on_declaration_phase(combatant) == {},
		"on_declaration_phase should return {}")
	check(hooks.on_pre_initiative(combatant) == 0,
		"on_pre_initiative should return 0")
	check(hooks.on_pre_attack(combatant, combatant, "melee") == {},
		"on_pre_attack should return {}")
	check(hooks.on_hit_confirmed(combatant, combatant, 5) == {},
		"on_hit_confirmed should return {}")
	check(hooks.on_combatant_downed(combatant) == {},
		"on_combatant_downed should return {}")
	check(hooks.on_before_action(combatant) == {},
		"on_before_action should return {}")
	check(hooks.on_spell_resolves(combatant, "fireball", []) == {},
		"on_spell_resolves should return {}")


func test_on_damage_dealt_sets_damaged_flag() -> void:
	var hooks := SpellCombatHooks.new(null)
	var combatant := _make_fighter("test")
	combatant.damaged_since_declaration = false
	hooks.on_damage_dealt(combatant, 5, "attacker")
	check(combatant.damaged_since_declaration == true,
		"on_damage_dealt should set damaged_since_declaration")


func test_on_damage_dealt_safe_with_null_tracker() -> void:
	var hooks := SpellCombatHooks.new(null)
	var combatant := _make_fighter("test")
	# Should not crash
	hooks.on_damage_dealt(combatant, 5, "attacker")
	check(true, "on_damage_dealt with null tracker should not crash")


func test_on_damage_dealt_breaks_concentration() -> void:
	var tracker := ActiveEffectTracker.new()
	var hooks := SpellCombatHooks.new(tracker)

	# Add a concentration effect where the target is the caster
	tracker.add_effect({
		"effect_id": "eff_1",
		"spell_key": "hold_person",
		"caster_id": "caster_1",
		"caster_level": 5,
		"target_ids": ["enemy_1"],
		"effect_type": "condition",
		"applied_modifiers": [],
		"applied_conditions": [],
		"applied_flags": [],
		"duration_type": "concentration",
		"duration_remaining": -1,
		"requires_concentration": true,
		"is_active": true,
		"metadata": {},
	})

	var caster := _make_fighter("caster_1")
	check(tracker.get_concentration_effects("caster_1").size() == 1,
		"should have 1 concentration effect before damage")

	hooks.on_damage_dealt(caster, 5, "enemy_1")

	check(tracker.get_concentration_effects("caster_1").size() == 0,
		"concentration should be broken after damage")


func test_on_damage_dealt_no_concentration_is_safe() -> void:
	var tracker := ActiveEffectTracker.new()
	var hooks := SpellCombatHooks.new(tracker)
	var combatant := _make_fighter("test")

	# No concentration effects — should not crash
	hooks.on_damage_dealt(combatant, 5, "attacker")
	check(true, "on_damage_dealt with no concentration effects should not crash")


func test_on_damage_dealt_multiple_concentration() -> void:
	var tracker := ActiveEffectTracker.new()
	var hooks := SpellCombatHooks.new(tracker)

	# Caster holds two concentration spells
	for i in range(2):
		tracker.add_effect({
			"effect_id": "eff_%d" % i,
			"spell_key": "spell_%d" % i,
			"caster_id": "caster_1",
			"caster_level": 5,
			"target_ids": ["enemy_%d" % i],
			"effect_type": "condition",
			"applied_modifiers": [],
			"applied_conditions": [],
			"applied_flags": [],
			"duration_type": "concentration",
			"duration_remaining": -1,
			"requires_concentration": true,
			"is_active": true,
			"metadata": {},
		})

	var caster := _make_fighter("caster_1")
	hooks.on_damage_dealt(caster, 5, "enemy_1")

	check(tracker.get_concentration_effects("caster_1").size() == 0,
		"all concentration effects should be broken")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_fighter(id: String) -> Combatant:
	var cd := CharacterData.new()
	cd.id = id
	cd.name = id
	cd.hp_current = 10
	cd.hp_max = 10
	return Combatant.from_character(cd)
