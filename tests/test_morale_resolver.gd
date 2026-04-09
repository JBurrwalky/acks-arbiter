extends "res://tests/test_suite_base.gd"

## Unit tests for MoraleResolver.


func run_all_tests() -> void:
	test_first_casualty_triggers_roll()
	test_half_casualties_triggers_roll()
	test_both_triggers_same_round_single_roll_minus_2()
	test_solo_monster_half_hp_triggers_roll()
	test_morale_locked_skips_roll()
	test_fearless_skips_roll()
	test_morale_plus_4_skips_roll()
	test_retreat_sets_fleeing()
	test_fighting_withdrawal_sets_withdrawing()
	test_victory_or_death_locks_morale()
	test_chieftain_alive_modifier()
	test_no_check_override_blood_frenzy()
	if not has_failures():
		print("MoraleResolver: all tests passed.")


func test_first_casualty_triggers_roll() -> void:
	var resolver := MoraleResolver.new(null)
	var roster := _make_roster_with_monsters(3)
	var monster := roster.get_enemy_combatants()[0]

	# Record first casualty in round 1
	resolver.current_round = 1
	var killed := roster.get_enemy_combatants()[2]
	killed.set_hp_current(0)
	roster.record_casualty(killed, 1)

	var trigger_result := resolver.check_trigger(monster, "first_casualty", roster)
	check(trigger_result["should_roll"] == true,
		"first casualty should trigger morale roll")
	check(trigger_result["reason"] == "first_casualty",
		"reason should be first_casualty")


func test_half_casualties_triggers_roll() -> void:
	var resolver := MoraleResolver.new(null)
	var roster := _make_roster_with_monsters(4)
	var enemies := roster.get_enemy_combatants()
	var monster := enemies[0]

	# Kill first in round 1 — triggers first casualty
	resolver.current_round = 1
	enemies[3].set_hp_current(0)
	roster.record_casualty(enemies[3], 1)
	resolver.check_trigger(monster, "first_casualty", roster)

	# Kill second in round 2 — triggers half casualties (2 of 4)
	resolver.current_round = 2
	enemies[2].set_hp_current(0)
	roster.record_casualty(enemies[2], 2)

	var trigger_result := resolver.check_trigger(monster, "half_casualties", roster)
	check(trigger_result["should_roll"] == true,
		"half casualties should trigger morale roll")


func test_both_triggers_same_round_single_roll_minus_2() -> void:
	var resolver := MoraleResolver.new(null)
	# 2 monsters: killing 1 = first casualty AND half casualties
	var roster := _make_roster_with_monsters(2)
	var enemies := roster.get_enemy_combatants()
	var survivor := enemies[0]

	resolver.current_round = 1
	enemies[1].set_hp_current(0)
	roster.record_casualty(enemies[1], 1)

	var trigger_result := resolver.check_trigger(survivor, "first_casualty", roster)
	check(trigger_result["should_roll"] == true,
		"should roll for first casualty")
	check(trigger_result["extra_modifier"] == -2,
		"combined trigger should have -2 modifier, got %d" % trigger_result["extra_modifier"])
	check(trigger_result["reason"] == "first_and_half_casualties",
		"reason should indicate combined trigger")


func test_solo_monster_half_hp_triggers_roll() -> void:
	var resolver := MoraleResolver.new(null)
	var roster := _make_roster_with_monsters(1)
	var monster := roster.get_enemy_combatants()[0]

	var trigger_result := resolver.check_trigger(monster, "solo_half_hp", roster)
	check(trigger_result["should_roll"] == true,
		"solo monster at half HP should trigger morale")

	# Second check should not roll again
	var trigger2 := resolver.check_trigger(monster, "solo_half_hp", roster)
	check(trigger2["should_roll"] == false,
		"should not roll solo_half_hp twice")


func test_morale_locked_skips_roll() -> void:
	var resolver := MoraleResolver.new(null)
	var roster := _make_roster_with_monsters(3)
	var monster := roster.get_enemy_combatants()[0]
	monster.morale_locked = true

	var trigger_result := resolver.check_trigger(monster, "first_casualty", roster)
	check(trigger_result["should_roll"] == false,
		"morale_locked combatant should not roll")
	check(trigger_result["reason"] == "morale_locked",
		"reason should be morale_locked")


func test_fearless_skips_roll() -> void:
	var resolver := MoraleResolver.new(null)
	var roster := CombatRoster.new()
	# Add a PC
	var cd := CharacterData.new()
	cd.id = "pc1"
	cd.name = "Fighter"
	cd.hp_max = 10
	cd.hp_current = 10
	roster.add_combatant(Combatant.from_character(cd))

	# Add fearless monster
	var monster := _make_monster_with_behavior("scorpion", 2, {
		"morale_style": "fearless",
	})
	roster.add_combatant(monster)
	roster.enemy_count_at_start = 1

	var trigger_result := resolver.check_trigger(monster, "solo_half_hp", roster)
	check(trigger_result["should_roll"] == false,
		"fearless monster should not roll morale")
	check(trigger_result["reason"] == "fearless",
		"reason should be fearless")


func test_morale_plus_4_skips_roll() -> void:
	var resolver := MoraleResolver.new(null)
	var roster := _make_roster_with_monsters(1)
	var monster := roster.get_enemy_combatants()[0]
	# Override morale to +4
	monster._monster_data["morale"] = 4

	var trigger_result := resolver.check_trigger(monster, "solo_half_hp", roster)
	check(trigger_result["should_roll"] == false,
		"morale +4 should not roll")
	check(trigger_result["reason"] == "morale_max",
		"reason should be morale_max")


func test_retreat_sets_fleeing() -> void:
	var resolver := MoraleResolver.new(null)
	var roster := _make_roster_with_monsters(1)
	var monster := roster.get_enemy_combatants()[0]

	resolver.apply_outcome(monster, "retreat")
	check(monster.is_fleeing == true,
		"retreat should set is_fleeing")
	check(monster.is_withdrawing == false,
		"retreat should not set is_withdrawing")


func test_fighting_withdrawal_sets_withdrawing() -> void:
	var resolver := MoraleResolver.new(null)
	var roster := _make_roster_with_monsters(1)
	var monster := roster.get_enemy_combatants()[0]

	resolver.apply_outcome(monster, "fighting_withdrawal")
	check(monster.is_withdrawing == true,
		"fighting_withdrawal should set is_withdrawing")
	check(monster.is_fleeing == false,
		"fighting_withdrawal should not set is_fleeing")
	check(monster.withdrawal_rounds_remaining > 0,
		"should have withdrawal rounds remaining")


func test_victory_or_death_locks_morale() -> void:
	var resolver := MoraleResolver.new(null)
	var roster := _make_roster_with_monsters(1)
	var monster := roster.get_enemy_combatants()[0]

	resolver.apply_outcome(monster, "victory_or_death")
	check(monster.morale_locked == true,
		"victory_or_death should set morale_locked")

	# Verify locked combatant skips future rolls
	var trigger_result := resolver.check_trigger(monster, "solo_half_hp", roster)
	check(trigger_result["should_roll"] == false,
		"morale_locked should prevent future rolls")


func test_chieftain_alive_modifier() -> void:
	var resolver := MoraleResolver.new(null)
	var roster := CombatRoster.new()

	# Add a PC
	var cd := CharacterData.new()
	cd.id = "pc1"
	cd.name = "Fighter"
	cd.hp_max = 10
	cd.hp_current = 10
	roster.add_combatant(Combatant.from_character(cd))

	# Add monsters with chieftain_alive modifier
	var m1 := _make_monster_with_morale_mods("gob_0", 1, 0,
		[{"condition": "chieftain_alive", "modifier": 2}])
	var m2 := _make_monster_with_morale_mods("gob_1", 1, 0,
		[{"condition": "chieftain_alive", "modifier": 2}])
	roster.add_combatant(m1)
	roster.add_combatant(m2)
	roster.enemy_count_at_start = 2
	roster._casualties_by_group["gob_group"] = 0

	# With leader alive, modifier should be +2
	var mod := resolver.evaluate_conditional_modifiers(m1, roster)
	check(mod == 2,
		"chieftain_alive should add +2 when group has alive members, got %d" % mod)


func test_no_check_override_blood_frenzy() -> void:
	var resolver := MoraleResolver.new(null)
	var roster := _make_roster_with_monsters(1)

	# Make a shark with blood_frenzy
	var shark := _make_monster_with_abilities("shark", 2, [
		{
			"ability_id": "blood_frenzy",
			"description": "Fights to death",
			"hook_type": "special",
			"effect": {"morale_override": "no_check", "trigger": "blood_in_water"},
		}
	])
	roster.add_combatant(shark)

	var override := resolver.check_morale_override(shark)
	check(override["has_override"] == true,
		"blood_frenzy should create no_check override")

	var trigger_result := resolver.check_trigger(shark, "solo_half_hp", roster)
	check(trigger_result["should_roll"] == false,
		"shark with blood_frenzy should not roll morale")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_roster_with_monsters(count: int) -> CombatRoster:
	var roster := CombatRoster.new()
	# Add a PC
	var cd := CharacterData.new()
	cd.id = "pc1"
	cd.name = "Fighter"
	cd.hp_max = 10
	cd.hp_current = 10
	roster.add_combatant(Combatant.from_character(cd))

	# Add monsters
	var group_id := "test_group"
	for i in range(count):
		var monster_data := {
			"name": "Monster",
			"hit_dice": {"base": 1, "modifier": 0},
			"armor_class": 3,
			"attack_routines": [{"routine_name": "melee", "usage": "default",
				"attacks": [{"attack_type": "weapon", "count": 1, "damage": "1d6", "to_hit_modifier": 0}]}],
			"save_as": {"class": "F", "level": 1},
			"morale": 0,
			"movement": {"land": {"exploration": 120, "combat": 40}},
			"combat_behavior": {"morale_style": "normal"},
			"morale_modifiers": [],
			"special_abilities": [],
		}
		var cid := "monster_%d" % i
		var c := Combatant.from_monster(monster_data, 4, cid, group_id)
		roster.add_combatant(c)

	roster.enemy_count_at_start = count
	roster._casualties_by_group[group_id] = 0
	return roster


func _make_monster_with_behavior(id: String, hd: int, behavior: Dictionary) -> Combatant:
	var full_behavior := {
		"formation_discipline": "loose",
		"aggression_posture": "medium",
		"engagement_profile": "melee",
		"spellcasting_timing": "none",
		"consumable_timing": "none",
		"primary_target_rule": "nearest",
		"target_tie_breaker": "nearest",
		"morale_style": "normal",
	}
	full_behavior.merge(behavior, true)

	var monster_data := {
		"name": id,
		"hit_dice": {"base": hd, "modifier": 0},
		"armor_class": 3,
		"attack_routines": [{"routine_name": "melee", "usage": "default",
			"attacks": [{"attack_type": "weapon", "count": 1, "damage": "1d6", "to_hit_modifier": 0}]}],
		"save_as": {"class": "F", "level": hd},
		"morale": 0,
		"movement": {"land": {"exploration": 120, "combat": 40}},
		"combat_behavior": full_behavior,
		"morale_modifiers": [],
		"special_abilities": [],
	}
	return Combatant.from_monster(monster_data, hd * 4, id, "test_group")


func _make_monster_with_morale_mods(
		id: String, hd: int, base_morale: int,
		morale_mods: Array) -> Combatant:
	var monster_data := {
		"name": id,
		"hit_dice": {"base": hd, "modifier": 0},
		"armor_class": 3,
		"attack_routines": [{"routine_name": "melee", "usage": "default",
			"attacks": [{"attack_type": "weapon", "count": 1, "damage": "1d6", "to_hit_modifier": 0}]}],
		"save_as": {"class": "F", "level": hd},
		"morale": base_morale,
		"movement": {"land": {"exploration": 120, "combat": 40}},
		"combat_behavior": {"morale_style": "normal"},
		"morale_modifiers": morale_mods,
		"special_abilities": [],
	}
	return Combatant.from_monster(monster_data, hd * 4, id, "gob_group")


func _make_monster_with_abilities(
		id: String, hd: int, abilities: Array) -> Combatant:
	var monster_data := {
		"name": id,
		"hit_dice": {"base": hd, "modifier": 0},
		"armor_class": 3,
		"attack_routines": [{"routine_name": "melee", "usage": "default",
			"attacks": [{"attack_type": "bite", "count": 1, "damage": "2d4", "to_hit_modifier": 0}]}],
		"save_as": {"class": "F", "level": hd},
		"morale": -1,
		"movement": {"land": {"exploration": 120, "combat": 40}},
		"combat_behavior": {"morale_style": "normal"},
		"morale_modifiers": [{"condition": "blood_frenzy", "override": "no_check"}],
		"special_abilities": abilities,
	}
	return Combatant.from_monster(monster_data, hd * 4, id, "shark_group")
