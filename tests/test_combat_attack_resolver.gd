extends "res://tests/test_suite_base.gd"

## Unit tests for AttackResolver.


func run_all_tests() -> void:
	test_hit_when_roll_meets_target()
	test_miss_when_roll_below_target()
	test_natural_twenty_always_hits()
	test_natural_one_always_misses()
	test_damage_applied_on_hit()
	test_damage_minimum_one()
	test_str_modifier_added_to_damage()
	test_target_downed_on_zero_hp()
	test_miss_deals_no_damage()
	test_monster_attack_uses_routine()
	test_high_ac_target_harder_to_hit()
	# Magic weapon +N regression locks (RAW: acore_treasure_and_magic_items_rules.xml:231-235)
	test_magic_weapon_plus_n_adds_to_attack_throw()
	test_magic_weapon_plus_n_adds_to_damage()
	test_mundane_weapon_has_zero_magical_bonus()
	# Invulnerable monsters (RAW: acore_combat_and_wounds.xml:402-407)
	test_invulnerable_target_immune_to_mundane_pc_weapon()
	test_invulnerable_target_harmable_by_magic_weapon()
	test_invulnerable_target_harmable_by_5plus_hd_ferocity()
	test_invulnerable_target_safe_from_low_hd_mundane_monster()
	test_invulnerable_vs_invulnerable_can_harm()
	if not has_failures():
		print("AttackResolver: all tests passed.")


func test_hit_when_roll_meets_target() -> void:
	# Attacker: attack_throw 10, target AC 0. Need 1d20 >= 10.
	# With null DiceSystem, roll defaults to 10. 10 >= 10 = hit.
	var resolver := AttackResolver.new(null)
	var attacker := _make_fighter("att", 10, 10)
	var target := _make_fighter("def", 10, 0)
	var result := resolver.resolve_melee_attack(attacker, target)
	check(result["hit"] == true,
		"roll 10 vs target_number 10 should hit")


func test_miss_when_roll_below_target() -> void:
	# Attacker: attack_throw 10, target AC 5. Need 1d20 >= 15.
	# Default roll 10 < 15 = miss.
	var resolver := AttackResolver.new(null)
	var attacker := _make_fighter("att", 10, 10)
	var target := _make_fighter("def", 10, 5)
	var result := resolver.resolve_melee_attack(attacker, target)
	check(result["hit"] == false,
		"roll 10 vs target_number 15 should miss")


func test_natural_twenty_always_hits() -> void:
	# Even against impossible AC, nat 20 hits.
	var resolver := AttackResolver.new(_MockDice.new(20))
	var attacker := _make_fighter("att", 10, 20)  # attack_throw 20 = terrible
	var target := _make_fighter("def", 10, 9)     # AC 9
	var result := resolver.resolve_melee_attack(attacker, target)
	check(result["hit"] == true, "natural 20 should always hit")
	check(result["natural_twenty"] == true, "should flag natural_twenty")


func test_natural_one_always_misses() -> void:
	var resolver := AttackResolver.new(_MockDice.new(1))
	var attacker := _make_fighter("att", 10, 1)  # attack_throw 1 = excellent
	var target := _make_fighter("def", 10, 0)    # AC 0 = easy target
	var result := resolver.resolve_melee_attack(attacker, target)
	check(result["hit"] == false, "natural 1 should always miss")
	check(result["natural_one"] == true, "should flag natural_one")


func test_damage_applied_on_hit() -> void:
	var resolver := AttackResolver.new(_MockDice.new(15))  # high roll = hits
	var attacker := _make_fighter("att", 10, 10)
	var target := _make_fighter("def", 10, 0)
	target._character.hp_current = 20
	var result := resolver.resolve_melee_attack(attacker, target)
	check(result["hit"] == true, "should hit")
	check(result["damage_total"] > 0, "should deal damage")
	check(target.get_hp_current() < 20, "target HP should decrease")


func test_damage_minimum_one() -> void:
	# Even with negative modifiers, damage is at least 1
	var resolver := AttackResolver.new(_MockDice.new(20))  # nat 20 = hits
	var attacker := _make_fighter("att", 10, 10)
	attacker._character.strength = 3  # STR 3 = -3 modifier
	var target := _make_fighter("def", 10, 0)
	var result := resolver.resolve_melee_attack(attacker, target)
	check(result["hit"] == true, "nat 20 should hit")
	check(result["damage_total"] >= 1,
		"damage should be at least 1, got %d" % result["damage_total"])


func test_str_modifier_added_to_damage() -> void:
	# STR 18 = +3 modifier should add to damage
	var resolver := AttackResolver.new(_MockDice.new(20))
	var attacker := _make_fighter("att", 10, 10)
	attacker._character.strength = 18
	var target := _make_fighter("def", 20, 0)
	target._character.hp_current = 50
	# Run multiple times — damage should always include +3 from STR
	var result := resolver.resolve_melee_attack(attacker, target)
	# Default damage roll is 4 (from null fallback in mock's expression roll)
	# + 3 STR = 7
	check(result["damage_total"] >= 4,
		"damage with STR 18 should be at least 4, got %d" % result["damage_total"])


func test_target_downed_on_zero_hp() -> void:
	var resolver := AttackResolver.new(_MockDice.new(20))
	var attacker := _make_fighter("att", 10, 10)
	var target := _make_fighter("def", 1, 0)  # 1 HP
	target._character.hp_current = 1
	target._character.hp_max = 1
	var result := resolver.resolve_melee_attack(attacker, target)
	check(result["hit"] == true, "should hit")
	check(result["target_downed"] == true, "1 HP target should be downed")
	check(target.get_hp_current() == 0, "target HP should be 0")


func test_miss_deals_no_damage() -> void:
	var resolver := AttackResolver.new(_MockDice.new(1))  # nat 1 = miss
	var attacker := _make_fighter("att", 10, 10)
	var target := _make_fighter("def", 10, 0)
	target._character.hp_current = 10
	var result := resolver.resolve_melee_attack(attacker, target)
	check(result["hit"] == false, "should miss")
	check(result["damage_total"] == 0, "miss should deal 0 damage")
	check(target.get_hp_current() == 10, "target HP unchanged on miss")


func test_monster_attack_uses_routine() -> void:
	var resolver := AttackResolver.new(_MockDice.new(20))
	var monster := _make_monster("goblin_0", 1, 3, "1d6")
	var target := _make_fighter("def", 10, 0)
	var result := resolver.resolve_monster_attack(monster, target, 0)
	check(result["hit"] == true, "nat 20 should hit")
	check(result["damage_total"] >= 1, "monster should deal damage")


func test_high_ac_target_harder_to_hit() -> void:
	var resolver := AttackResolver.new(null)  # default roll 10
	var attacker := _make_fighter("att", 10, 10)
	var target_low_ac := _make_fighter("low_ac", 10, 0)
	var target_high_ac := _make_fighter("high_ac", 10, 7)
	var result_low := resolver.resolve_melee_attack(attacker, target_low_ac)
	var result_high := resolver.resolve_melee_attack(attacker, target_high_ac)
	# roll 10 vs (10+0)=10: hit. roll 10 vs (10+7)=17: miss.
	check(result_low["hit"] == true, "AC 0 should be hit with roll 10")
	check(result_high["hit"] == false, "AC 7 should be missed with roll 10")


# ---------------------------------------------------------------------------
# Magic weapon +N — regression locks
# RAW: rules/acore_treasure_and_magic_items_rules.xml:231-235 — "A plus value
# adds to attack and damage for weapons." attack_resolver.gd:67 adds it to
# the to-hit bonus; :147/163-165 adds it to damage_total. These tests pin
# both terms so a future combat refactor can't silently regress them.
# ---------------------------------------------------------------------------

func test_magic_weapon_plus_n_adds_to_attack_throw() -> void:
	# attack_throw 10, target AC 5 -> target_number = 15.
	# Mundane: roll 14 + 0 = 14 < 15 -> miss.
	# +2 weapon: roll 14 + 2 = 16 >= 15 -> hit.
	var resolver := AttackResolver.new(_MockDice.new(14))
	var attacker := _make_fighter("att", 10, 10)
	var target := _make_fighter("def", 10, 5)
	_equip_weapon(attacker, "1d6", 0)
	check(resolver.resolve_melee_attack(attacker, target)["hit"] == false,
		"mundane weapon: roll 14 vs target_number 15 should miss")
	_equip_weapon(attacker, "1d6", 2)
	check(resolver.resolve_melee_attack(attacker, target)["hit"] == true,
		"+2 weapon: 14 + 2 = 16 vs target_number 15 should hit")


func test_magic_weapon_plus_n_adds_to_damage() -> void:
	# Force roll 15: clean hit (not nat 20, no Weapon-Focus doubling). The mock
	# dice forces the damage roll value too, so the magic - mundane delta is
	# exactly the weapon's magical_bonus.
	var attacker_m := _make_fighter("att_m", 10, 10)
	_equip_weapon(attacker_m, "1d6", 0)
	var target_m := _make_fighter("def_m", 100, 0)
	target_m._character.hp_current = 100
	var mundane := AttackResolver.new(_MockDice.new(15)).resolve_melee_attack(attacker_m, target_m)

	var attacker_p := _make_fighter("att_p", 10, 10)
	_equip_weapon(attacker_p, "1d6", 2)
	var target_p := _make_fighter("def_p", 100, 0)
	target_p._character.hp_current = 100
	var magic := AttackResolver.new(_MockDice.new(15)).resolve_melee_attack(attacker_p, target_p)

	check(mundane["hit"] and magic["hit"], "both attacks should hit at roll 15 vs AC 0")
	check(int(magic["damage_total"]) - int(mundane["damage_total"]) == 2,
		"+2 weapon adds exactly 2 damage (mundane=%d, magic=%d)"
			% [int(mundane["damage_total"]), int(magic["damage_total"])])


func test_mundane_weapon_has_zero_magical_bonus() -> void:
	var attacker := _make_fighter("att", 10, 10)
	_equip_weapon(attacker, "1d6", 0)
	check(attacker.get_weapon_magical_bonus() == 0,
		"mundane weapon reports magical_bonus 0")


# ---------------------------------------------------------------------------
# Invulnerable monsters
# RAW: rules/acore_combat_and_wounds.xml:402-407 — some monsters can be harmed
# only by magical or silver weapons; weaker attackers without magical/silver
# weapons cannot harm them; monsters with 5+ HD harm them through natural
# ferocity; such monsters can always harm each other. The pre-roll check
# aborts the attack with cant_harm=true when the rule blocks it.
# ---------------------------------------------------------------------------

func test_invulnerable_target_immune_to_mundane_pc_weapon() -> void:
	var resolver := AttackResolver.new(_MockDice.new(20))  # nat 20 would normally hit
	var attacker := _make_fighter("att", 10, 10)
	_equip_weapon(attacker, "1d6", 0)
	var target := _make_invulnerable_monster("wraith", 4, 5, "1d6")
	var result := resolver.resolve_melee_attack(attacker, target)
	check(result["hit"] == false,
		"mundane PC weapon vs invulnerable monster should not hit")
	check(result.get("cant_harm", false) == true, "result should flag cant_harm")
	check(int(result["damage_total"]) == 0, "no damage on harmless attack")


func test_invulnerable_target_harmable_by_magic_weapon() -> void:
	var resolver := AttackResolver.new(_MockDice.new(20))
	var attacker := _make_fighter("att", 10, 10)
	_equip_weapon(attacker, "1d6", 1)
	var target := _make_invulnerable_monster("wraith", 4, 0, "1d6")
	var result := resolver.resolve_melee_attack(attacker, target)
	check(result.get("cant_harm", false) == false,
		"magic weapon should not be blocked by invulnerability")
	check(result["hit"] == true, "+1 weapon + nat 20 should hit AC 0")


func test_invulnerable_target_harmable_by_5plus_hd_ferocity() -> void:
	# 6 HD monster wielding a mundane natural weapon harms invulnerable target
	# via natural ferocity (RAW :405).
	var resolver := AttackResolver.new(_MockDice.new(20))
	var attacker := _make_monster("orc_chief", 6, 5, "1d8")
	var target := _make_invulnerable_monster("wraith", 4, 0, "1d6")
	var result := resolver.resolve_melee_attack(attacker, target)
	check(result.get("cant_harm", false) == false,
		"5+ HD monster harms invulnerable target via natural ferocity (RAW :405)")


func test_invulnerable_target_safe_from_low_hd_mundane_monster() -> void:
	# < 5 HD mundane monster cannot harm invulnerable target.
	var resolver := AttackResolver.new(_MockDice.new(20))
	var attacker := _make_monster("wolf", 3, 7, "1d4")
	var target := _make_invulnerable_monster("wraith", 4, 0, "1d6")
	var result := resolver.resolve_melee_attack(attacker, target)
	check(result.get("cant_harm", false) == true,
		"< 5 HD monster without magic cannot harm invulnerable target")


func test_invulnerable_vs_invulnerable_can_harm() -> void:
	# Such monsters can always harm each other (RAW :404).
	var resolver := AttackResolver.new(_MockDice.new(20))
	var attacker := _make_invulnerable_monster("wraith_a", 4, 0, "1d6")
	var target := _make_invulnerable_monster("wraith_b", 4, 0, "1d6")
	var result := resolver.resolve_melee_attack(attacker, target)
	check(result.get("cant_harm", false) == false,
		"such monsters can always harm each other (RAW :404)")


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


func _make_monster(id: String, hd: int, ac: int, damage: String) -> Combatant:
	var monster_data := {
		"id": id,
		"name": id,
		"hit_dice": {"base": hd, "modifier": 0},
		"armor_class": ac,
		"attack_routines": [
			{
				"routine_name": "melee",
				"usage": "default",
				"attacks": [
					{"attack_type": "weapon", "count": 1, "damage": damage, "to_hit_modifier": 0}
				]
			}
		],
		"save_as": {"class": "fighter", "level": hd},
		"morale": 0,
		"xp": 10,
		"movement": {"land": {"exploration": 120, "combat": 40}},
	}
	return Combatant.from_monster(monster_data, hd * 4, id, "test_group")


## Equip a test weapon on a Combatant for to-hit / damage / magical_bonus tests.
func _equip_weapon(c: Combatant, damage_expr: String, magical_bonus: int = 0) -> void:
	c._equipped_weapon = {
		"name": "test weapon",
		"item_key": "test_weapon",
		"item_id": "",
		"item_category": "weapon",
		"weapon_damage": damage_expr,
		"magical_bonus": magical_bonus,
		"damage_type": "physical",
		"weapon_tags": [],
		"range_short": 0, "range_medium": 0, "range_long": 0,
		"quantity": 1,
		"uses_remaining": -1,
	}


## A monster carrying the catalog flag `damaged_only_by_magic_or_silver`.
## RAW: rules/acore_combat_and_wounds.xml:402-407.
func _make_invulnerable_monster(id: String, hd: int, ac: int = 0, damage: String = "1d6") -> Combatant:
	var monster_data := {
		"id": id, "name": id,
		"hit_dice": {"base": hd, "modifier": 0},
		"armor_class": ac,
		"attack_routines": [
			{
				"routine_name": "melee", "usage": "default",
				"attacks": [
					{"attack_type": "weapon", "count": 1, "damage": damage, "to_hit_modifier": 0}
				]
			}
		],
		"save_as": {"class": "fighter", "level": hd},
		"morale": 0, "xp": 10,
		"movement": {"land": {"exploration": 120, "combat": 40}},
		"damaged_only_by_magic_or_silver": true,
	}
	return Combatant.from_monster(monster_data, hd * 4, id, "test_group")


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

	func roll_expression(expression: String, _roll_type: String = "") -> RollResult:
		# Parse and roll with forced value
		var r := RollResult.new()
		r.raw_total = _forced_value
		r.modified_total = _forced_value
		r.individual_results = [_forced_value]
		return r
