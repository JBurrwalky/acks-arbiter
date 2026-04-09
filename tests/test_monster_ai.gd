extends "res://tests/test_suite_base.gd"

## Unit tests for MonsterAI target selection and action selection.


func run_all_tests() -> void:
	test_nearest_rule_uses_stable_order()
	test_weakest_targets_lowest_hp()
	test_most_dangerous_targets_highest_threat()
	test_most_exposed_targets_lowest_ac()
	test_retaliatory_targets_last_attacker()
	test_role_mage_targets_mages()
	test_role_missile_targets_ranged()
	test_tiebreaker_lowest_ac()
	test_tiebreaker_lowest_hp()
	test_tiebreaker_last_attacker()
	test_tiebreaker_random()
	test_pack_focus_fire_bonus()
	test_fleeing_combatant_passes()
	test_withdrawing_combatant_still_acts()
	test_default_behavior_selects_melee()
	if not has_failures():
		print("MonsterAI: all tests passed.")


func test_nearest_rule_uses_stable_order() -> void:
	var roster := _make_test_roster()
	var ai := MonsterAI.new(roster)
	var monster := roster.get_enemy_combatants()[0]
	var behavior := {"primary_target_rule": "nearest", "target_tie_breaker": "nearest"}

	var target := ai.select_target(monster, behavior)
	check(target != null, "should select a target")
	# All equidistant pre-grid, so stable tiebreak by lowest ID
	# PCs are: pc_a, pc_b, pc_c
	check(target.id == "pc_a",
		"nearest pre-grid should pick lowest ID (pc_a), got %s" % target.id)


func test_weakest_targets_lowest_hp() -> void:
	var roster := _make_test_roster()
	# Set PC hp values: pc_a=10, pc_b=3, pc_c=8
	roster.get_by_id("pc_b")._character.hp_current = 3
	roster.get_by_id("pc_c")._character.hp_current = 8

	var ai := MonsterAI.new(roster)
	var monster := roster.get_enemy_combatants()[0]
	var behavior := {"primary_target_rule": "weakest", "target_tie_breaker": "nearest"}

	var target := ai.select_target(monster, behavior)
	check(target.id == "pc_b",
		"weakest should target pc_b (3 HP), got %s" % target.id)


func test_most_dangerous_targets_highest_threat() -> void:
	var roster := _make_roster_with_varied_pcs()
	var ai := MonsterAI.new(roster)
	var monster := roster.get_enemy_combatants()[0]
	var behavior := {"primary_target_rule": "most_dangerous", "target_tie_breaker": "nearest"}

	var target := ai.select_target(monster, behavior)
	# PC "warrior" has level 5, "mage" has level 3, "thief" has level 2
	# most_dangerous = attack_count * level_or_hd → warrior(1*5)=5, mage(1*3)=3, thief(1*2)=2
	check(target.id == "warrior",
		"most_dangerous should target warrior (highest threat), got %s" % target.id)


func test_most_exposed_targets_lowest_ac() -> void:
	var roster := _make_test_roster()
	# Set ACs: pc_a=5, pc_b=2, pc_c=7
	roster.get_by_id("pc_a")._character.armor_class = 5
	roster.get_by_id("pc_b")._character.armor_class = 2
	roster.get_by_id("pc_c")._character.armor_class = 7

	var ai := MonsterAI.new(roster)
	var monster := roster.get_enemy_combatants()[0]
	var behavior := {"primary_target_rule": "most_exposed", "target_tie_breaker": "nearest"}

	var target := ai.select_target(monster, behavior)
	# most_exposed = 10 - AC. pc_b(10-2=8) > pc_a(10-5=5) > pc_c(10-7=3)
	check(target.id == "pc_b",
		"most_exposed should target pc_b (lowest AC=2), got %s" % target.id)


func test_retaliatory_targets_last_attacker() -> void:
	var roster := _make_test_roster()
	var ai := MonsterAI.new(roster)
	var monster := roster.get_enemy_combatants()[0]
	monster.last_attacker_id = "pc_c"
	var behavior := {"primary_target_rule": "retaliatory", "target_tie_breaker": "nearest"}

	var target := ai.select_target(monster, behavior)
	check(target.id == "pc_c",
		"retaliatory should target last attacker pc_c, got %s" % target.id)


func test_role_mage_targets_mages() -> void:
	var roster := _make_roster_with_varied_pcs()
	var ai := MonsterAI.new(roster)
	var monster := roster.get_enemy_combatants()[0]
	var behavior := {"primary_target_rule": "role_mage", "target_tie_breaker": "nearest"}

	var target := ai.select_target(monster, behavior)
	check(target.id == "mage",
		"role_mage should target the mage, got %s" % target.id)


func test_role_missile_targets_ranged() -> void:
	# All current test PCs are melee — role_missile should fall through to tiebreaker
	var roster := _make_test_roster()
	var ai := MonsterAI.new(roster)
	var monster := roster.get_enemy_combatants()[0]
	var behavior := {"primary_target_rule": "role_missile", "target_tie_breaker": "lowest_hp"}

	# Set hp: pc_a=10, pc_b=5, pc_c=8
	roster.get_by_id("pc_b")._character.hp_current = 5

	var target := ai.select_target(monster, behavior)
	# No missile users, all score 0, tiebreaker = lowest_hp = pc_b
	check(target.id == "pc_b",
		"role_missile with no ranged PCs should use tiebreaker (lowest_hp=pc_b), got %s" % target.id)


func test_tiebreaker_lowest_ac() -> void:
	var roster := _make_test_roster()
	# Set ACs: pc_a=5, pc_b=2, pc_c=7
	roster.get_by_id("pc_a")._character.armor_class = 5
	roster.get_by_id("pc_b")._character.armor_class = 2
	roster.get_by_id("pc_c")._character.armor_class = 7

	var ai := MonsterAI.new(roster)
	var monster := roster.get_enemy_combatants()[0]
	# "nearest" primary rule: all score 0 (equidistant), then tiebreak by lowest_ac
	var behavior := {"primary_target_rule": "nearest", "target_tie_breaker": "lowest_ac"}

	var target := ai.select_target(monster, behavior)
	check(target.id == "pc_b",
		"lowest_ac tiebreaker should pick pc_b (AC 2), got %s" % target.id)


func test_tiebreaker_lowest_hp() -> void:
	var roster := _make_test_roster()
	roster.get_by_id("pc_a")._character.hp_current = 10
	roster.get_by_id("pc_b")._character.hp_current = 4
	roster.get_by_id("pc_c")._character.hp_current = 8

	var ai := MonsterAI.new(roster)
	var monster := roster.get_enemy_combatants()[0]
	var behavior := {"primary_target_rule": "nearest", "target_tie_breaker": "lowest_hp"}

	var target := ai.select_target(monster, behavior)
	check(target.id == "pc_b",
		"lowest_hp tiebreaker should pick pc_b (4 HP), got %s" % target.id)


func test_tiebreaker_last_attacker() -> void:
	var roster := _make_test_roster()
	var ai := MonsterAI.new(roster)
	var monster := roster.get_enemy_combatants()[0]
	monster.last_attacker_id = "pc_b"
	var behavior := {"primary_target_rule": "nearest", "target_tie_breaker": "last_attacker"}

	var target := ai.select_target(monster, behavior)
	check(target.id == "pc_b",
		"last_attacker tiebreaker should pick pc_b, got %s" % target.id)


func test_tiebreaker_random() -> void:
	var roster := _make_test_roster()
	# Force dice to pick index 2 (roll 3 on d3)
	var ai := MonsterAI.new(roster, _MockDice.new(3))
	var monster := roster.get_enemy_combatants()[0]
	var behavior := {"primary_target_rule": "nearest", "target_tie_breaker": "random"}

	var target := ai.select_target(monster, behavior)
	# With 3 candidates and roll=3, idx=2 → pc_c
	check(target.id == "pc_c",
		"random tiebreaker with roll 3 should pick pc_c, got %s" % target.id)


func test_pack_focus_fire_bonus() -> void:
	var roster := _make_test_roster_with_pack()
	var ai := MonsterAI.new(roster)

	# Simulate: wolf_1 already attacked pc_b (set pc_b's last_attacker)
	roster.get_by_id("pc_b").last_attacker_id = "wolf_1"

	var wolf_0 := roster.get_by_id("wolf_0")
	# Using "nearest" primary (all score 0) — pack bonus should boost pc_b
	var behavior := {
		"primary_target_rule": "nearest",
		"target_tie_breaker": "nearest",
		"formation_discipline": "pack",
	}

	var target := ai.select_target(wolf_0, behavior)
	check(target.id == "pc_b",
		"pack focus should boost pc_b (attacked by packmate), got %s" % target.id)


func test_fleeing_combatant_passes() -> void:
	var roster := _make_test_roster()
	var ai := MonsterAI.new(roster)
	var monster := roster.get_enemy_combatants()[0]
	monster.is_fleeing = true

	var action := ai.select_action(monster)
	check(action["action_id"] == "pass",
		"fleeing monster should pass, got %s" % action["action_id"])


func test_withdrawing_combatant_still_acts() -> void:
	var roster := _make_test_roster()
	var ai := MonsterAI.new(roster)
	var monster := roster.get_enemy_combatants()[0]
	monster.is_withdrawing = true
	monster.withdrawal_rounds_remaining = 3

	var action := ai.select_action(monster)
	check(action["action_id"] == "attack_melee",
		"withdrawing monster should still attack, got %s" % action["action_id"])


func test_default_behavior_selects_melee() -> void:
	var roster := _make_test_roster()
	var ai := MonsterAI.new(roster)
	var monster := roster.get_enemy_combatants()[0]

	var action := ai.select_action(monster)
	check(action["action_id"] == "attack_melee",
		"default engagement should be attack_melee, got %s" % action["action_id"])
	check(action["parameters"].has("target_id"),
		"action should have target_id parameter")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_test_roster() -> CombatRoster:
	var roster := CombatRoster.new()

	# Add 3 PCs
	for id in ["pc_a", "pc_b", "pc_c"]:
		var cd := CharacterData.new()
		cd.id = id
		cd.name = id
		cd.hp_max = 10
		cd.hp_current = 10
		cd.armor_class = 3
		cd.attack_throw = 10
		cd.combat_progression = "fighter"
		roster.add_combatant(Combatant.from_character(cd))

	# Add 1 monster
	var monster_data := {
		"name": "Orc",
		"hit_dice": {"base": 1, "modifier": 0},
		"armor_class": 3,
		"attack_routines": [{"routine_name": "melee", "usage": "default",
			"attacks": [{"attack_type": "weapon", "count": 1, "damage": "1d6", "to_hit_modifier": 0}]}],
		"save_as": {"class": "F", "level": 1},
		"morale": 0,
		"movement": {"land": {"exploration": 120, "combat": 40}},
		"combat_behavior": {
			"formation_discipline": "loose",
			"aggression_posture": "medium",
			"engagement_profile": "melee",
			"primary_target_rule": "nearest",
			"target_tie_breaker": "nearest",
			"morale_style": "normal",
		},
	}
	roster.add_combatant(Combatant.from_monster(monster_data, 4, "orc_0", "orc_group"))
	roster.enemy_count_at_start = 1
	return roster


func _make_roster_with_varied_pcs() -> CombatRoster:
	var roster := CombatRoster.new()

	# Warrior: level 5, fighter progression
	var warrior_cd := CharacterData.new()
	warrior_cd.id = "warrior"
	warrior_cd.name = "Warrior"
	warrior_cd.hp_max = 30
	warrior_cd.hp_current = 30
	warrior_cd.armor_class = 6
	warrior_cd.attack_throw = 6
	warrior_cd.level = 5
	warrior_cd.combat_progression = "fighter"
	roster.add_combatant(Combatant.from_character(warrior_cd))

	# Mage: level 3, mage progression
	var mage_cd := CharacterData.new()
	mage_cd.id = "mage"
	mage_cd.name = "Mage"
	mage_cd.hp_max = 8
	mage_cd.hp_current = 8
	mage_cd.armor_class = 0
	mage_cd.attack_throw = 10
	mage_cd.level = 3
	mage_cd.combat_progression = "mage"
	roster.add_combatant(Combatant.from_character(mage_cd))

	# Thief: level 2, thief progression
	var thief_cd := CharacterData.new()
	thief_cd.id = "thief"
	thief_cd.name = "Thief"
	thief_cd.hp_max = 12
	thief_cd.hp_current = 12
	thief_cd.armor_class = 3
	thief_cd.attack_throw = 10
	thief_cd.level = 2
	thief_cd.combat_progression = "thief"
	roster.add_combatant(Combatant.from_character(thief_cd))

	# Add 1 monster
	var monster_data := {
		"name": "Centaur",
		"hit_dice": {"base": 4, "modifier": 0},
		"armor_class": 4,
		"attack_routines": [{"routine_name": "melee", "usage": "default",
			"attacks": [
				{"attack_type": "hoof", "count": 2, "damage": "1d6", "to_hit_modifier": 0},
				{"attack_type": "weapon", "count": 1, "damage": "1d8", "to_hit_modifier": 0},
			]}],
		"save_as": {"class": "F", "level": 4},
		"morale": 0,
		"movement": {"land": {"exploration": 180, "combat": 60}},
		"combat_behavior": {
			"formation_discipline": "disciplined",
			"aggression_posture": "low",
			"engagement_profile": "melee",
			"primary_target_rule": "most_dangerous",
			"target_tie_breaker": "lowest_ac",
			"morale_style": "normal",
		},
	}
	roster.add_combatant(Combatant.from_monster(monster_data, 16, "centaur_0", "centaur_group"))
	roster.enemy_count_at_start = 1
	return roster


func _make_test_roster_with_pack() -> CombatRoster:
	var roster := CombatRoster.new()

	# Add 3 PCs
	for id in ["pc_a", "pc_b", "pc_c"]:
		var cd := CharacterData.new()
		cd.id = id
		cd.name = id
		cd.hp_max = 10
		cd.hp_current = 10
		cd.armor_class = 3
		cd.attack_throw = 10
		cd.combat_progression = "fighter"
		roster.add_combatant(Combatant.from_character(cd))

	# Add 2 wolves (pack formation)
	var wolf_data := {
		"name": "Wolf",
		"hit_dice": {"base": 1, "modifier": 0},
		"armor_class": 2,
		"attack_routines": [{"routine_name": "melee", "usage": "default",
			"attacks": [{"attack_type": "bite", "count": 1, "damage": "1d6", "to_hit_modifier": 0}]}],
		"save_as": {"class": "F", "level": 1},
		"morale": 0,
		"movement": {"land": {"exploration": 180, "combat": 60}},
		"combat_behavior": {
			"formation_discipline": "pack",
			"aggression_posture": "medium",
			"engagement_profile": "melee",
			"primary_target_rule": "weakest",
			"target_tie_breaker": "nearest",
			"morale_style": "normal",
		},
	}
	roster.add_combatant(Combatant.from_monster(wolf_data.duplicate(true), 4, "wolf_0", "wolf_pack"))
	roster.add_combatant(Combatant.from_monster(wolf_data.duplicate(true), 4, "wolf_1", "wolf_pack"))
	roster.enemy_count_at_start = 2
	return roster


# ---------------------------------------------------------------------------
# Mock DiceSystem
# ---------------------------------------------------------------------------

class _MockDice:
	extends RefCounted

	var _forced_value: int

	func _init(forced: int) -> void:
		_forced_value = forced

	func roll_digital(
			sides: int, count: int = 1, modifier: int = 0,
			_roll_type: String = "") -> RollResult:
		var r := RollResult.new()
		r.sides = sides
		r.count = count
		r.modifier = modifier
		r.individual_results = [_forced_value]
		r.raw_total = _forced_value
		r.modified_total = _forced_value + modifier
		r.natural_one = (_forced_value == 1 and sides == 20 and count == 1)
		r.natural_max = (_forced_value == sides and count == 1)
		return r
