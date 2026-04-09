extends "res://tests/test_suite_base.gd"

## Unit tests for CleaveResolver.


func run_all_tests() -> void:
	test_fighter_max_cleaves_equals_hd()
	test_cleric_max_cleaves_half_hd()
	test_thief_max_cleaves_half_hd()
	test_mage_cannot_cleave()
	test_normal_man_cannot_cleave()
	test_can_cleave_respects_budget()
	test_record_cleave_decrements_budget()
	test_reset_round_clears_budget()
	test_expanded_attack_sequence_respects_count()
	test_expanded_attack_sequence_single_attack()
	if not has_failures():
		print("CleaveResolver: all tests passed.")


func test_fighter_max_cleaves_equals_hd() -> void:
	var resolver := CleaveResolver.new()
	# 3 HD fighter-progression monster → 3 cleaves
	var monster := _make_monster_with_save("m1", 3, "F")
	check(resolver.get_max_cleaves(monster) == 3,
		"3 HD fighter should get 3 max cleaves, got %d" % resolver.get_max_cleaves(monster))

	# 6 HD fighter → 6 cleaves
	var troll := _make_monster_with_save("troll", 6, "F")
	check(resolver.get_max_cleaves(troll) == 6,
		"6 HD fighter should get 6 max cleaves")

	# 1 HD fighter → 1 cleave
	var orc := _make_monster_with_save("orc", 1, "F")
	check(resolver.get_max_cleaves(orc) == 1,
		"1 HD fighter should get 1 max cleave")


func test_cleric_max_cleaves_half_hd() -> void:
	var resolver := CleaveResolver.new()
	# 6 HD cleric-progression → 3 cleaves (6/2)
	var monster := _make_monster_with_save("c1", 6, "C")
	check(resolver.get_max_cleaves(monster) == 3,
		"6 HD cleric should get 3 max cleaves")

	# 5 HD cleric → 2 cleaves (5/2 = 2 floor)
	var monster2 := _make_monster_with_save("c2", 5, "C")
	check(resolver.get_max_cleaves(monster2) == 2,
		"5 HD cleric should get 2 max cleaves (floor)")

	# 1 HD cleric → 0 cleaves (1/2 = 0 floor)
	var monster3 := _make_monster_with_save("c3", 1, "C")
	check(resolver.get_max_cleaves(monster3) == 0,
		"1 HD cleric should get 0 max cleaves")


func test_thief_max_cleaves_half_hd() -> void:
	var resolver := CleaveResolver.new()
	# 4 HD thief → 2 cleaves
	var monster := _make_monster_with_save("t1", 4, "T")
	check(resolver.get_max_cleaves(monster) == 2,
		"4 HD thief should get 2 max cleaves")


func test_mage_cannot_cleave() -> void:
	var resolver := CleaveResolver.new()
	var monster := _make_monster_with_save("m1", 6, "M")
	check(resolver.get_max_cleaves(monster) == 0,
		"mage should get 0 max cleaves")
	check(not resolver.can_cleave(monster),
		"mage should not be able to cleave")


func test_normal_man_cannot_cleave() -> void:
	var resolver := CleaveResolver.new()
	# NM (goblins, kobolds) → 0 cleaves
	var goblin := _make_monster_with_save("gob", 1, "NM")
	check(resolver.get_max_cleaves(goblin) == 0,
		"NM should get 0 max cleaves")
	check(not resolver.can_cleave(goblin),
		"NM should not be able to cleave")


func test_can_cleave_respects_budget() -> void:
	var resolver := CleaveResolver.new()
	var monster := _make_monster_with_save("f1", 2, "F")
	check(resolver.can_cleave(monster),
		"2 HD fighter should be able to cleave initially")
	check(resolver.get_cleaves_remaining(monster) == 2,
		"should have 2 cleaves remaining")


func test_record_cleave_decrements_budget() -> void:
	var resolver := CleaveResolver.new()
	var monster := _make_monster_with_save("f1", 2, "F")
	resolver.record_cleave(monster.id)
	check(resolver.get_cleaves_remaining(monster) == 1,
		"should have 1 cleave remaining after 1 used")
	check(resolver.can_cleave(monster),
		"should still be able to cleave with 1 remaining")

	resolver.record_cleave(monster.id)
	check(resolver.get_cleaves_remaining(monster) == 0,
		"should have 0 cleaves remaining after 2 used")
	check(not resolver.can_cleave(monster),
		"should not be able to cleave with 0 remaining")


func test_reset_round_clears_budget() -> void:
	var resolver := CleaveResolver.new()
	var monster := _make_monster_with_save("f1", 2, "F")
	resolver.record_cleave(monster.id)
	resolver.record_cleave(monster.id)
	check(not resolver.can_cleave(monster),
		"should be exhausted before reset")

	resolver.reset_round()
	check(resolver.can_cleave(monster),
		"should be able to cleave again after reset")
	check(resolver.get_cleaves_remaining(monster) == 2,
		"should have full budget after reset")


func test_expanded_attack_sequence_respects_count() -> void:
	# Lizardman-style: claw(count:2) + bite(count:1) = 3 attacks
	var monster := _make_multi_attack_monster("liz", 2,
		[
			{"attack_type": "claw", "count": 2, "damage": "1d3", "to_hit_modifier": 0, "special_effect": null},
			{"attack_type": "bite", "count": 1, "damage": "1d8", "to_hit_modifier": 0, "special_effect": null},
		])
	var seq := monster.get_expanded_attack_sequence()
	check(seq.size() == 3,
		"claw(2)+bite(1) should expand to 3 attacks, got %d" % seq.size())
	check(seq[0]["attack_type"] == "claw", "attack 0 should be claw")
	check(seq[1]["attack_type"] == "claw", "attack 1 should be claw")
	check(seq[2]["attack_type"] == "bite", "attack 2 should be bite")
	check(seq[0]["damage"] == "1d3", "claw damage should be 1d3")
	check(seq[2]["damage"] == "1d8", "bite damage should be 1d8")
	check(seq[0]["source_index"] == 0, "claw source_index should be 0")
	check(seq[2]["source_index"] == 1, "bite source_index should be 1")


func test_expanded_attack_sequence_single_attack() -> void:
	# Simple monster: 1 weapon attack
	var monster := _make_multi_attack_monster("gob", 1,
		[
			{"attack_type": "weapon", "count": 1, "damage": "1d6", "to_hit_modifier": 0, "special_effect": null},
		])
	var seq := monster.get_expanded_attack_sequence()
	check(seq.size() == 1,
		"single weapon attack should expand to 1, got %d" % seq.size())
	check(seq[0]["attack_type"] == "weapon", "should be weapon")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_monster_with_save(id: String, hd: int, save_class: String) -> Combatant:
	var monster_data := {
		"id": id,
		"name": id,
		"hit_dice": {"base": hd, "modifier": 0},
		"armor_class": 3,
		"attack_routines": [
			{
				"routine_name": "melee",
				"usage": "default",
				"attacks": [
					{"attack_type": "weapon", "count": 1, "damage": "1d6", "to_hit_modifier": 0}
				]
			}
		],
		"save_as": {"class": save_class, "level": hd},
		"morale": 0,
		"movement": {"land": {"exploration": 120, "combat": 40}},
	}
	return Combatant.from_monster(monster_data, hd * 4, id, "test_group")


func _make_multi_attack_monster(id: String, hd: int, attacks: Array) -> Combatant:
	var monster_data := {
		"id": id,
		"name": id,
		"hit_dice": {"base": hd, "modifier": 0},
		"armor_class": 3,
		"attack_routines": [
			{
				"routine_name": "melee",
				"usage": "default",
				"attacks": attacks,
			}
		],
		"save_as": {"class": "F", "level": hd},
		"morale": 0,
		"movement": {"land": {"exploration": 120, "combat": 40}},
	}
	return Combatant.from_monster(monster_data, hd * 4, id, "test_group")
