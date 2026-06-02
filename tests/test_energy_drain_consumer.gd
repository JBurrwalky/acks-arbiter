extends "res://tests/test_suite_base.gd"

## 2026-06-02 — EnergyDrainConsumer tests.
##
## Verifies that drained levels stamped on the `is_energy_drained`
## EntityFlag are reflected as ModifierContainer entries on PC
## CharacterData (attack_throw + 5 saves). The Restore Life and Limb
## resolver's clear-flag path then sweeps the modifiers via the
## `energy_drain:` source prefix.


func run_all_tests() -> void:
	test_no_drain_no_modifiers()
	test_single_source_drain_applies_to_attack_throw()
	test_single_source_drain_applies_to_all_5_saves()
	test_multi_source_drain_stacks_levels()
	test_clear_flag_then_refresh_removes_modifiers()
	test_refresh_is_idempotent()
	test_get_total_drained_levels_helper()
	test_null_character_no_crash()
	test_restore_life_and_limb_clears_modifiers_via_resolver()
	if not has_failures():
		print("EnergyDrainConsumer: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_pc() -> CharacterData:
	var cd := CharacterData.new()
	cd.id = "pc_drain_test"
	cd.name = "Drain Subject"
	cd.character_class = "fighter"
	cd.combat_progression = "fighter"
	cd.level = 9
	cd.attack_throw = 8
	cd.save_petrification = 11
	cd.save_poison_death = 11
	cd.save_blast_breath = 13
	cd.save_staffs_wands = 12
	cd.save_spells = 14
	return cd


func _set_drain(cd: CharacterData, source_id: String, levels: int) -> void:
	cd.flags.set_flag("is_energy_drained", source_id, {
		"drained_levels": levels,
		"source_kind": "test",
	})


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_no_drain_no_modifiers() -> void:
	var cd := _make_pc()
	EnergyDrainConsumer.refresh_modifiers(cd)
	check(not cd.modifiers.has_modifier_for_stat("attack_throw"),
		"no drain → no attack_throw modifier")
	check(not cd.modifiers.has_modifier_for_stat("save_poison_death"),
		"no drain → no save_poison_death modifier")


func test_single_source_drain_applies_to_attack_throw() -> void:
	var cd := _make_pc()
	_set_drain(cd, "life_drinker:sword1", 1)
	EnergyDrainConsumer.refresh_modifiers(cd)
	# +1 to attack_throw target (worse = higher).
	var effective: int = int(cd.modifiers.get_effective_value("attack_throw", cd.attack_throw))
	check(effective == 9,
		"+1 drain raises attack_throw from 8 to 9, got %d" % effective)


func test_single_source_drain_applies_to_all_5_saves() -> void:
	var cd := _make_pc()
	_set_drain(cd, "wraith:w1", 2)
	EnergyDrainConsumer.refresh_modifiers(cd)
	var pet: int = int(cd.modifiers.get_effective_value("save_petrification", cd.save_petrification))
	var poi: int = int(cd.modifiers.get_effective_value("save_poison_death", cd.save_poison_death))
	var blast: int = int(cd.modifiers.get_effective_value("save_blast_breath", cd.save_blast_breath))
	var staff: int = int(cd.modifiers.get_effective_value("save_staffs_wands", cd.save_staffs_wands))
	var spell: int = int(cd.modifiers.get_effective_value("save_spells", cd.save_spells))
	check(pet == 13, "+2 drain raises save_petrification 11→13, got %d" % pet)
	check(poi == 13, "+2 drain raises save_poison_death 11→13, got %d" % poi)
	check(blast == 15, "+2 drain raises save_blast_breath 13→15, got %d" % blast)
	check(staff == 14, "+2 drain raises save_staffs_wands 12→14, got %d" % staff)
	check(spell == 16, "+2 drain raises save_spells 14→16, got %d" % spell)


func test_multi_source_drain_stacks_levels() -> void:
	# Life Drinker + Wraith both drain — modifiers reflect the sum.
	var cd := _make_pc()
	_set_drain(cd, "life_drinker:ld1", 1)
	_set_drain(cd, "wraith:w1", 2)
	EnergyDrainConsumer.refresh_modifiers(cd)
	var attack: int = int(cd.modifiers.get_effective_value("attack_throw", cd.attack_throw))
	check(attack == 11,
		"1 + 2 = 3 drain raises attack_throw 8→11, got %d" % attack)


func test_clear_flag_then_refresh_removes_modifiers() -> void:
	# Apply drain, then clear flag, then refresh — modifiers gone.
	var cd := _make_pc()
	_set_drain(cd, "life_drinker:s1", 2)
	EnergyDrainConsumer.refresh_modifiers(cd)
	check(int(cd.modifiers.get_effective_value("attack_throw", cd.attack_throw)) == 10,
		"drain landed: attack_throw 8→10")
	# Clear the flag.
	cd.flags.clear_flag("is_energy_drained", "life_drinker:s1")
	# Refresh — modifiers should clear because flag total is now 0.
	EnergyDrainConsumer.refresh_modifiers(cd)
	check(int(cd.modifiers.get_effective_value("attack_throw", cd.attack_throw)) == 8,
		"after clear: attack_throw back to 8")
	check(not cd.modifiers.has_modifier_for_stat("save_spells"),
		"after clear: no save_spells modifier")


func test_refresh_is_idempotent() -> void:
	# Calling refresh multiple times doesn't double-apply.
	var cd := _make_pc()
	_set_drain(cd, "life_drinker:i1", 1)
	EnergyDrainConsumer.refresh_modifiers(cd)
	EnergyDrainConsumer.refresh_modifiers(cd)
	EnergyDrainConsumer.refresh_modifiers(cd)
	check(int(cd.modifiers.get_effective_value("attack_throw", cd.attack_throw)) == 9,
		"idempotent: 3× refresh still yields +1, attack_throw 8→9")


func test_get_total_drained_levels_helper() -> void:
	var cd := _make_pc()
	_set_drain(cd, "src_a", 1)
	_set_drain(cd, "src_b", 2)
	_set_drain(cd, "src_c", 3)
	check(EnergyDrainConsumer.get_total_drained_levels(cd) == 6,
		"sum across 3 sources = 6")


func test_null_character_no_crash() -> void:
	EnergyDrainConsumer.refresh_modifiers(null)
	check(EnergyDrainConsumer.get_total_drained_levels(null) == 0,
		"null character: total = 0")


func test_restore_life_and_limb_clears_modifiers_via_resolver() -> void:
	# End-to-end: Restore Life and Limb resolver clears the flag AND
	# the modifiers (via its _clear_energy_drain → refresh_modifiers chain).
	const RLR := preload(
		"res://engine/subsystems/spells/custom_resolvers/restore_life_and_limb_resolver.gd")
	var cd := _make_pc()
	_set_drain(cd, "life_drinker:end2end", 1)
	EnergyDrainConsumer.refresh_modifiers(cd)
	check(int(cd.modifiers.get_effective_value("attack_throw", cd.attack_throw)) == 9,
		"setup: attack_throw 8→9 after drain")

	# Build resolver args manually (mirrors test_restore_life_and_limb pattern).
	var resolver = RLR.new()
	var caster := CharacterData.new()
	caster.id = "cleric_end2end"; caster.level = 9
	caster.character_class = "cleric"; caster.combat_progression = "cleric"
	caster.hp_max = 24; caster.hp_current = 24
	var ctx := CasterContext.from_character_data(
		caster, "combat_grid", "divine", 1)
	var td := TargetDescriptor.new()
	td.kind = "touch_creature"
	td.target_ids = [cd.id]
	resolver.resolve({
		"caster_context": ctx,
		"target_descriptor": td,
		"targets_by_id": {cd.id: cd},
		"spell_choice": SpellChoice.new("restore_life_and_limb", 5, false, -1),
		"step_payload": {"resolver_args": {}},
	})
	check(not cd.flags.has_flag("is_energy_drained"),
		"resolver cleared the flag")
	check(int(cd.modifiers.get_effective_value("attack_throw", cd.attack_throw)) == 8,
		"resolver chain auto-cleared the modifier — attack_throw back to 8")
