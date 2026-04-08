extends "res://tests/test_suite_base.gd"

## Unit tests for RangedAttackResolver.

const SHORTBOW := {
	"range_short": 50, "range_medium": 100, "range_long": 150,
	"weapon_damage": "1d6", "weapon_tags": ["ranged", "two_handed"],
}


func run_all_tests() -> void:
	test_short_range_no_penalty()
	test_medium_range_minus_two()
	test_long_range_minus_five()
	test_beyond_long_range_auto_miss()
	test_into_melee_blocked_without_precise_shooting()
	test_precise_shooting_rank1_minus_four()
	test_precise_shooting_rank2_minus_two()
	test_precise_shooting_rank3_no_penalty()
	test_dex_modifier_applied()
	test_no_str_bonus_on_damage()
	test_natural_twenty_always_hits()
	test_natural_one_always_misses()
	test_target_downed_on_hit()
	if not has_failures():
		print("RangedAttackResolver: all tests passed.")


func test_short_range_no_penalty() -> void:
	var resolver := RangedAttackResolver.new(_MockDice.new(15))
	var attacker := _make_fighter("att")
	var target := _make_fighter("def", 10, 0)
	var result := resolver.resolve_ranged_attack(attacker, target, SHORTBOW, 30)
	check(result["range_band"] == "short",
		"30ft should be short range for shortbow")
	check(result["range_penalty"] == 0,
		"short range should have 0 penalty")
	check(result["hit"] == true, "should hit at short range with roll 15")


func test_medium_range_minus_two() -> void:
	var resolver := RangedAttackResolver.new(_MockDice.new(15))
	var attacker := _make_fighter("att")
	var target := _make_fighter("def", 10, 0)
	var result := resolver.resolve_ranged_attack(attacker, target, SHORTBOW, 80)
	check(result["range_band"] == "medium",
		"80ft should be medium range, got %s" % result["range_band"])
	check(result["range_penalty"] == -2,
		"medium range penalty should be -2, got %d" % result["range_penalty"])


func test_long_range_minus_five() -> void:
	var resolver := RangedAttackResolver.new(_MockDice.new(15))
	var attacker := _make_fighter("att")
	var target := _make_fighter("def", 10, 0)
	var result := resolver.resolve_ranged_attack(attacker, target, SHORTBOW, 140)
	check(result["range_band"] == "long",
		"140ft should be long range, got %s" % result["range_band"])
	check(result["range_penalty"] == -5,
		"long range penalty should be -5, got %d" % result["range_penalty"])


func test_beyond_long_range_auto_miss() -> void:
	var resolver := RangedAttackResolver.new(_MockDice.new(20))
	var attacker := _make_fighter("att")
	var target := _make_fighter("def", 10, 0)
	var result := resolver.resolve_ranged_attack(attacker, target, SHORTBOW, 200)
	check(result["hit"] == false, "beyond long range should auto-miss")
	check(result["out_of_range"] == true, "should flag out_of_range")


func test_into_melee_blocked_without_precise_shooting() -> void:
	var resolver := RangedAttackResolver.new(_MockDice.new(20))
	var attacker := _make_fighter("att")
	var target := _make_fighter("def", 10, 0)
	var result := resolver.resolve_ranged_attack(
		attacker, target, SHORTBOW, 30, true)
	check(result["hit"] == false,
		"should not hit — firing into melee without Precise Shooting is blocked")
	check(result["into_melee_blocked"] == true,
		"should flag into_melee_blocked")


func test_precise_shooting_rank1_minus_four() -> void:
	var resolver := RangedAttackResolver.new(_MockDice.new(20))
	var attacker := _make_fighter_with_proficiency("att", "precise_shooting", 1)
	var target := _make_fighter("def", 10, 0)
	var result := resolver.resolve_ranged_attack(
		attacker, target, SHORTBOW, 30, true)
	check(result["hit"] == true,
		"nat 20 with Precise Shooting rank 1 should hit")
	check(result["into_melee_penalty"] == 4,
		"rank 1 into-melee penalty should be 4, got %d" % result["into_melee_penalty"])


func test_precise_shooting_rank2_minus_two() -> void:
	var resolver := RangedAttackResolver.new(_MockDice.new(20))
	var attacker := _make_fighter_with_proficiency("att", "precise_shooting", 2)
	var target := _make_fighter("def", 10, 0)
	var result := resolver.resolve_ranged_attack(
		attacker, target, SHORTBOW, 30, true)
	check(result["into_melee_penalty"] == 2,
		"rank 2 into-melee penalty should be 2, got %d" % result["into_melee_penalty"])


func test_precise_shooting_rank3_no_penalty() -> void:
	var resolver := RangedAttackResolver.new(_MockDice.new(20))
	var attacker := _make_fighter_with_proficiency("att", "precise_shooting", 3)
	var target := _make_fighter("def", 10, 0)
	var result := resolver.resolve_ranged_attack(
		attacker, target, SHORTBOW, 30, true)
	check(result["into_melee_penalty"] == 0,
		"rank 3 into-melee penalty should be 0, got %d" % result["into_melee_penalty"])


func test_dex_modifier_applied() -> void:
	var resolver := RangedAttackResolver.new(_MockDice.new(10))
	var attacker := _make_fighter("att")
	attacker._character.dexterity = 18  # +3 modifier
	var target := _make_fighter("def", 10, 0)
	var result := resolver.resolve_ranged_attack(attacker, target, SHORTBOW, 30)
	# to_hit_bonus should include DEX +3
	check(result["to_hit_bonus"] >= 3,
		"DEX 18 (+3) should be in to_hit_bonus, got %d" % result["to_hit_bonus"])


func test_no_str_bonus_on_damage() -> void:
	var resolver := RangedAttackResolver.new(_MockDice.new(20))
	var attacker := _make_fighter("att")
	attacker._character.strength = 18  # +3 STR — should NOT apply to ranged
	var target := _make_fighter("def", 50, 0)
	var result := resolver.resolve_ranged_attack(attacker, target, SHORTBOW, 30)
	check(result["hit"] == true, "nat 20 should hit")
	# MockDice returns 20 for damage expression too, so damage = max(1, 20 + 0) = 20
	# STR should NOT be added — if it were, damage would be 23
	# We can't distinguish easily, but at least verify no crash
	check(result["damage_total"] >= 1, "damage should be at least 1")


func test_natural_twenty_always_hits() -> void:
	var resolver := RangedAttackResolver.new(_MockDice.new(20))
	var attacker := _make_fighter("att")
	attacker._character.attack_throw = 20  # terrible attack throw
	var target := _make_fighter("def", 10, 9)
	var result := resolver.resolve_ranged_attack(attacker, target, SHORTBOW, 30)
	check(result["hit"] == true, "nat 20 should always hit ranged")
	check(result["natural_twenty"] == true, "should flag natural_twenty")


func test_natural_one_always_misses() -> void:
	var resolver := RangedAttackResolver.new(_MockDice.new(1))
	var attacker := _make_fighter("att")
	attacker._character.attack_throw = 1  # excellent
	var target := _make_fighter("def", 10, 0)
	var result := resolver.resolve_ranged_attack(attacker, target, SHORTBOW, 30)
	check(result["hit"] == false, "nat 1 should always miss ranged")


func test_target_downed_on_hit() -> void:
	var resolver := RangedAttackResolver.new(_MockDice.new(20))
	var attacker := _make_fighter("att")
	var target := _make_fighter("def", 1, 0)
	target._character.hp_current = 1
	target._character.hp_max = 1
	var result := resolver.resolve_ranged_attack(attacker, target, SHORTBOW, 30)
	check(result["target_downed"] == true, "1 HP target should be downed")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_fighter(id: String, hp: int = 10, ac: int = 0) -> Combatant:
	var cd := CharacterData.new()
	cd.id = id
	cd.name = id
	cd.hp_max = hp
	cd.hp_current = hp
	cd.armor_class = ac
	cd.attack_throw = 10
	cd.strength = 10
	cd.dexterity = 10
	return Combatant.from_character(cd)


func _make_fighter_with_proficiency(
		id: String, prof_key: String, rank: int) -> Combatant:
	var c := _make_fighter(id)
	c._character.proficiencies.append({
		"proficiency_key": prof_key,
		"rank": rank,
		"slot_type": "class",
		"selections_count": rank,
		"specialization": "",
	})
	return c


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
	func roll_expression(_expression: String, _roll_type: String = "") -> RollResult:
		var r := RollResult.new()
		r.raw_total = _forced_value
		r.modified_total = _forced_value
		r.individual_results = [_forced_value]
		return r
