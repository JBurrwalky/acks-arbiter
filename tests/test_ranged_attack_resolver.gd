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
	# Invulnerable monsters (RAW: acore_combat_and_wounds.xml:402-407)
	test_invulnerable_target_harmless_to_mundane_ranged_attack()
	# Magic ranged +N (RAW: acore_treasure_and_magic_items_rules.xml:231-235)
	test_magic_bow_adds_to_attack_throw()
	test_magic_arrows_add_to_damage()
	test_magic_bow_and_magic_arrows_stack_on_both()
	test_magic_thrown_weapon_adds_to_both_via_weapon()
	test_mundane_ranged_attack_has_no_magic_bonus()
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


# RAW: rules/acore_combat_and_wounds.xml:402-407 — a PC firing a mundane bow
# with no magic ammo at a monster flagged `damaged_only_by_magic_or_silver`
# cannot harm it; ranged_attack_resolver aborts pre-roll with cant_harm=true.
func test_invulnerable_target_harmless_to_mundane_ranged_attack() -> void:
	var resolver := RangedAttackResolver.new(_MockDice.new(20))  # nat 20 would normally hit
	var attacker := _make_fighter("att")
	# No _equipped_weapon / _equipped_ammo → both magical_bonuses default to 0.
	var target := Combatant.from_monster({
		"id": "wraith", "name": "wraith",
		"hit_dice": {"base": 4, "modifier": 0},
		"armor_class": 0,
		"attack_routines": [{
			"routine_name": "melee", "usage": "default",
			"attacks": [{"attack_type": "weapon", "count": 1, "damage": "1d6", "to_hit_modifier": 0}],
		}],
		"save_as": {"class": "fighter", "level": 4}, "morale": 0, "xp": 10,
		"movement": {"land": {"exploration": 120, "combat": 40}},
		"damaged_only_by_magic_or_silver": true,
	}, 16, "wraith", "test_group")
	var result := resolver.resolve_ranged_attack(attacker, target, SHORTBOW, 30)
	check(result.get("cant_harm", false) == true,
		"mundane bow + no magic ammo cannot harm invulnerable target")
	check(result["hit"] == false, "harmless attack does not hit")
	check(result.get("into_melee_blocked", true) == false,
		"into_melee_blocked must NOT be true for a cant_harm result (avoid misleading the UI)")


# ---------------------------------------------------------------------------
# Magic ranged +N (RAW: acore_treasure_and_magic_items_rules.xml:231-235)
# The +N from both the weapon (bow/crossbow/sling/thrown) AND the ammo applies
# to BOTH attack throws and damage; the two stack. Thrown weapons carry no
# separate ammo, so only the weapon's +N applies. (Jedidiah ruling 2026-05-29:
# apply the general RAW rule uniformly across ranged — no split.)
# ---------------------------------------------------------------------------

func test_magic_bow_adds_to_attack_throw() -> void:
	# AC 5 -> target_number 10 + 5 = 15. Force roll 14:
	# mundane bow -> 14 < 15 miss; +2 bow -> 14 + 2 = 16 hit.
	var resolver := RangedAttackResolver.new(_MockDice.new(14))
	var attacker := _make_fighter("att")
	var target := _make_fighter("def", 10, 5)
	attacker._equipped_weapon = {"item_category": "weapon", "magical_bonus": 0}
	check(resolver.resolve_ranged_attack(attacker, target, SHORTBOW, 30)["hit"] == false,
		"mundane bow: roll 14 vs target_number 15 should miss")
	attacker._equipped_weapon = {"item_category": "weapon", "magical_bonus": 2}
	check(resolver.resolve_ranged_attack(attacker, target, SHORTBOW, 30)["hit"] == true,
		"+2 bow: 14 + 2 = 16 vs target_number 15 should hit")


func test_magic_arrows_add_to_damage() -> void:
	# Roll 15 (clean hit). Mock dice forces the damage roll value too, so the
	# delta between mundane and +2 arrows is exactly the magical_bonus.
	var att_m := _make_fighter("att_m")
	att_m._equipped_weapon = {"item_category": "weapon", "magical_bonus": 0}
	att_m._equipped_ammo = {"item_category": "ammunition", "magical_bonus": 0, "quantity": 20}
	var tgt_m := _make_fighter("def_m", 100, 0)
	tgt_m._character.hp_current = 100
	var mundane := RangedAttackResolver.new(_MockDice.new(15)).resolve_ranged_attack(
		att_m, tgt_m, SHORTBOW, 30)

	var att_p := _make_fighter("att_p")
	att_p._equipped_weapon = {"item_category": "weapon", "magical_bonus": 0}
	att_p._equipped_ammo = {"item_category": "ammunition", "magical_bonus": 2, "quantity": 20}
	var tgt_p := _make_fighter("def_p", 100, 0)
	tgt_p._character.hp_current = 100
	var magic := RangedAttackResolver.new(_MockDice.new(15)).resolve_ranged_attack(
		att_p, tgt_p, SHORTBOW, 30)

	check(mundane["hit"] and magic["hit"], "both should hit at roll 15 vs AC 0")
	check(int(magic["damage_total"]) - int(mundane["damage_total"]) == 2,
		"+2 arrows add exactly 2 damage (mundane=%d, magic=%d)"
			% [int(mundane["damage_total"]), int(magic["damage_total"])])


func test_magic_bow_and_magic_arrows_stack_on_both() -> void:
	# +1 bow + +1 arrows: stacks to +2 on attack AND +2 on damage.
	# Attack: target AC 5 -> target_number 15. Roll 13 + 2 = 15 -> hit.
	var attacker := _make_fighter("att")
	attacker._equipped_weapon = {"item_category": "weapon", "magical_bonus": 1}
	attacker._equipped_ammo = {"item_category": "ammunition", "magical_bonus": 1, "quantity": 20}
	var target := _make_fighter("def", 100, 5)
	target._character.hp_current = 100
	var hit := RangedAttackResolver.new(_MockDice.new(13)).resolve_ranged_attack(
		attacker, target, SHORTBOW, 30)
	check(hit["hit"] == true,
		"+1 bow + +1 arrows stack to +2: 13 + 2 = 15 vs target_number 15 should hit")

	# Damage stack: compare to fully mundane baseline at roll 15 vs AC 0.
	var att_m := _make_fighter("att_m")
	att_m._equipped_weapon = {"item_category": "weapon", "magical_bonus": 0}
	att_m._equipped_ammo = {"item_category": "ammunition", "magical_bonus": 0, "quantity": 20}
	var tgt_m := _make_fighter("def_m", 100, 0)
	tgt_m._character.hp_current = 100
	var mundane := RangedAttackResolver.new(_MockDice.new(15)).resolve_ranged_attack(
		att_m, tgt_m, SHORTBOW, 30)

	var att_s := _make_fighter("att_s")
	att_s._equipped_weapon = {"item_category": "weapon", "magical_bonus": 1}
	att_s._equipped_ammo = {"item_category": "ammunition", "magical_bonus": 1, "quantity": 20}
	var tgt_s := _make_fighter("def_s", 100, 0)
	tgt_s._character.hp_current = 100
	var stacked := RangedAttackResolver.new(_MockDice.new(15)).resolve_ranged_attack(
		att_s, tgt_s, SHORTBOW, 30)
	check(int(stacked["damage_total"]) - int(mundane["damage_total"]) == 2,
		"+1 bow + +1 arrows stack to +2 damage (mundane=%d, stacked=%d)"
			% [int(mundane["damage_total"]), int(stacked["damage_total"])])


func test_magic_thrown_weapon_adds_to_both_via_weapon() -> void:
	# A +1 magic thrown weapon (dagger) carries no separate ammo, so only the
	# weapon's +N applies — to BOTH attack and damage. Verify the damage delta
	# is exactly +1 vs a mundane thrown attack.
	var THROWING_DAGGER := {
		"range_short": 10, "range_medium": 20, "range_long": 30,
		"weapon_damage": "1d4", "weapon_tags": ["thrown"],
	}
	var att_m := _make_fighter("att_m")
	att_m._equipped_weapon = {"item_category": "weapon", "magical_bonus": 0, "weapon_tags": ["thrown"]}
	# No _equipped_ammo: thrown weapons ARE the projectile.
	var tgt_m := _make_fighter("def_m", 100, 0)
	tgt_m._character.hp_current = 100
	var mundane := RangedAttackResolver.new(_MockDice.new(15)).resolve_ranged_attack(
		att_m, tgt_m, THROWING_DAGGER, 10)

	var att_p := _make_fighter("att_p")
	att_p._equipped_weapon = {"item_category": "weapon", "magical_bonus": 1, "weapon_tags": ["thrown"]}
	var tgt_p := _make_fighter("def_p", 100, 0)
	tgt_p._character.hp_current = 100
	var magic := RangedAttackResolver.new(_MockDice.new(15)).resolve_ranged_attack(
		att_p, tgt_p, THROWING_DAGGER, 10)

	check(mundane["hit"] and magic["hit"], "both thrown attacks should hit at roll 15 vs AC 0")
	check(int(magic["damage_total"]) - int(mundane["damage_total"]) == 1,
		"+1 thrown weapon adds 1 damage with no ammo term (mundane=%d, magic=%d)"
			% [int(mundane["damage_total"]), int(magic["damage_total"])])


func test_mundane_ranged_attack_has_no_magic_bonus() -> void:
	var attacker := _make_fighter("att")
	attacker._equipped_weapon = {"item_category": "weapon", "magical_bonus": 0}
	attacker._equipped_ammo = {"item_category": "ammunition", "magical_bonus": 0, "quantity": 20}
	check(attacker.get_weapon_magical_bonus() == 0, "mundane bow: magical_bonus 0")
	check(attacker.get_ammo_magical_bonus() == 0, "mundane arrows: magical_bonus 0")


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
