extends "res://tests/test_suite_base.gd"

## Unit tests for ManeuverResolver: all 8 ACKS combat maneuvers.


func run_all_tests() -> void:
	test_brawl_punch_deals_nonlethal()
	test_brawl_monster_cannot_brawl()
	test_brawl_metal_armor_reflects_damage()
	test_brawl_metal_vs_metal_no_reflection()
	test_disarm_on_hit_and_failed_save()
	test_disarm_target_saves()
	test_force_back_pushes_target()
	test_force_back_target_saves()
	test_incapacitate_deals_nonlethal()
	test_incapacitate_miss()
	test_knock_down_applies_prone()
	test_knock_down_target_saves()
	test_overrun_does_not_consume_attack()
	test_sunder_breaks_weapon()
	test_sunder_magic_item_resists()
	test_wrestle_applies_grappled()
	test_wrestle_target_saves()
	test_wrestling_hold_skip_attack_throw()
	test_combat_trickery_reduces_penalty()
	test_nonlethal_damage_accumulates()
	if not has_failures():
		print("ManeuverResolver: all tests passed.")


# ---------------------------------------------------------------------------
# Brawling
# ---------------------------------------------------------------------------

func test_brawl_punch_deals_nonlethal() -> void:
	var env := _make_env(20)  # High roll = hit
	var result: Dictionary = env.resolver.resolve_maneuver(env.pc, env.monster, "brawl", {})
	check(result.get("maneuver") == "brawl", "should be brawl maneuver")
	check(result.get("nonlethal") == true, "brawl should be nonlethal")


func test_brawl_monster_cannot_brawl() -> void:
	var env := _make_env(20)
	var result: Dictionary = env.resolver.resolve_maneuver(env.monster, env.pc, "brawl", {})
	check(result.get("success") == false, "monsters should not be able to brawl")


func test_brawl_metal_armor_reflects_damage() -> void:
	# Attacker in leather (non-metal), target in metal → damage reflects to attacker
	var env := _make_env(20)  # Hit
	env.pc._equipped_armor_material = "leather"
	env.monster._equipped_armor_material = "metal"
	var pc_hp_before: int = env.pc.get_hp_current()
	var monster_hp_before: int = env.monster.get_hp_current()
	var result: Dictionary = env.resolver.resolve_maneuver(env.pc, env.monster, "brawl", {})
	check(result.get("reflected") == true, "damage should reflect to attacker")
	check(env.monster.get_hp_current() == monster_hp_before,
		"target HP should be unchanged after reflection")
	check(env.pc.get_hp_current() < pc_hp_before,
		"attacker should take reflected damage")


func test_brawl_metal_vs_metal_no_reflection() -> void:
	# Both in metal armor → no reflection
	var env := _make_env(20)
	env.pc._equipped_armor_material = "metal"
	env.monster._equipped_armor_material = "metal"
	var monster_hp_before: int = env.monster.get_hp_current()
	var result: Dictionary = env.resolver.resolve_maneuver(env.pc, env.monster, "brawl", {})
	check(result.get("reflected", false) == false, "should not reflect when both in metal")
	check(env.monster.get_hp_current() < monster_hp_before,
		"target should take damage normally")


# ---------------------------------------------------------------------------
# Disarm
# ---------------------------------------------------------------------------

func test_disarm_on_hit_and_failed_save() -> void:
	# Roll 20 = hit, save roll 1 = fail (save_petrification is 15 for F1)
	var env := _make_env_sequence([20, 4, 1])  # attack, damage, save
	var result: Dictionary = env.resolver.resolve_maneuver(env.pc, env.monster, "disarm", {})
	check(result.get("disarmed") == true,
		"disarm should succeed when attack hits and save fails")


func test_disarm_target_saves() -> void:
	# Roll 20 = hit, save roll 20 = succeeds
	var env := _make_env_sequence([20, 4, 20])
	var result: Dictionary = env.resolver.resolve_maneuver(env.pc, env.monster, "disarm", {})
	check(result.get("disarmed") == false,
		"disarm should fail when target saves")
	check(result.get("saved") == true, "should flag saved")


# ---------------------------------------------------------------------------
# Force Back
# ---------------------------------------------------------------------------

func test_force_back_pushes_target() -> void:
	var env := _make_env_sequence([20, 4, 1, 3])  # attack, damage(miss?), save(fail), push_roll
	var result: Dictionary = env.resolver.resolve_maneuver(env.pc, env.monster, "force_back", {})
	check(result.get("forced_back") == true,
		"force back should succeed when attack hits and save fails")
	check(result.get("push_distance_ft", 0) > 0,
		"push distance should be > 0")


func test_force_back_target_saves() -> void:
	var env := _make_env_sequence([20, 4, 20])
	var result: Dictionary = env.resolver.resolve_maneuver(env.pc, env.monster, "force_back", {})
	check(result.get("forced_back") == false,
		"force back should fail when target saves")


# ---------------------------------------------------------------------------
# Incapacitate
# ---------------------------------------------------------------------------

func test_incapacitate_deals_nonlethal() -> void:
	var env := _make_env(20)  # High roll = hit
	var result: Dictionary = env.resolver.resolve_maneuver(env.pc, env.monster, "incapacitate", {})
	check(result.get("maneuver") == "incapacitate", "should be incapacitate maneuver")
	check(result.get("nonlethal") == true, "incapacitate hit should be nonlethal")
	check(result.get("hit") == true, "should hit on natural 20")


func test_incapacitate_miss() -> void:
	var env := _make_env(1)  # Natural 1 = miss
	var result: Dictionary = env.resolver.resolve_maneuver(env.pc, env.monster, "incapacitate", {})
	check(result.get("maneuver") == "incapacitate", "should be incapacitate maneuver")
	check(result.get("nonlethal") == false, "miss should not flag nonlethal")
	check(result.get("hit") == false, "should miss on natural 1")


# ---------------------------------------------------------------------------
# Knock Down
# ---------------------------------------------------------------------------

func test_knock_down_applies_prone() -> void:
	var env := _make_env_sequence([20, 4, 1])
	var result: Dictionary = env.resolver.resolve_maneuver(env.pc, env.monster, "knock_down", {})
	check(result.get("knocked_down") == true,
		"knock down should succeed when attack hits and save fails")


func test_knock_down_target_saves() -> void:
	var env := _make_env_sequence([20, 4, 20])
	var result: Dictionary = env.resolver.resolve_maneuver(env.pc, env.monster, "knock_down", {})
	check(result.get("knocked_down") == false,
		"knock down should fail when target saves")


# ---------------------------------------------------------------------------
# Overrun
# ---------------------------------------------------------------------------

func test_overrun_does_not_consume_attack() -> void:
	var env := _make_env_sequence([20, 4, 1])  # attack, damage, save(fail)
	var result: Dictionary = env.resolver.resolve_maneuver(env.pc, env.monster, "overrun", {})
	check(result.get("does_not_consume_attack") == true,
		"overrun should not consume the attacker's attack")


# ---------------------------------------------------------------------------
# Sunder
# ---------------------------------------------------------------------------

func test_sunder_breaks_weapon() -> void:
	# High attack roll = hit, low save = item broken
	var env := _make_env_sequence([20, 4, 1])
	var result: Dictionary = env.resolver.resolve_maneuver(env.pc, env.monster, "sunder",
		{"sunder_target": "weapon", "weapon_type": "staff_spear_polearm"})
	check(result.get("sundered") == true,
		"sunder should succeed when attack hits and save fails")


func test_sunder_magic_item_resists() -> void:
	var env := _make_env_sequence([20, 4])
	var result: Dictionary = env.resolver.resolve_maneuver(env.pc, env.monster, "sunder",
		{"sunder_target": "weapon", "attacker_magic_bonus": 0, "target_item_magic_bonus": 2})
	check(result.get("sundered") == false,
		"non-magic weapon should not sunder +2 magic item")
	check("too weak" in result.get("reason", ""),
		"should explain why sunder failed")


# ---------------------------------------------------------------------------
# Wrestling
# ---------------------------------------------------------------------------

func test_wrestle_applies_grappled() -> void:
	var env := _make_env_sequence([20, 4, 1])
	var result: Dictionary = env.resolver.resolve_maneuver(env.pc, env.monster, "wrestle", {})
	check(result.get("held") == true,
		"wrestle should succeed when attack hits and save fails")
	check(env.monster.held_by_id == env.pc.id,
		"monster should be held by PC")


func test_wrestle_target_saves() -> void:
	var env := _make_env_sequence([20, 4, 20])
	var result: Dictionary = env.resolver.resolve_maneuver(env.pc, env.monster, "wrestle", {})
	check(result.get("held") == false,
		"wrestle should fail when target saves")


func test_wrestling_hold_skip_attack_throw() -> void:
	# When target is already held, disarm should skip the attack throw
	var env := _make_env_sequence([1])  # Save roll = 1 (fail)
	env.monster.held_by_id = env.pc.id
	var result: Dictionary = env.resolver.resolve_maneuver(env.pc, env.monster, "disarm", {})
	check(result.get("disarmed") == true,
		"disarm on held target should skip attack throw and succeed on failed save")


# ---------------------------------------------------------------------------
# Combat Trickery
# ---------------------------------------------------------------------------

func test_combat_trickery_reduces_penalty() -> void:
	# With Combat Trickery, the attack penalty should be -2 instead of -4.
	# Use STR 10 (modifier 0) so to_hit_bonus is purely the maneuver penalty.
	var env := _make_env(20)  # Hit regardless
	env.pc._character.strength = 10  # Modifier 0
	env.pc._character.proficiencies = [{"proficiency_key": "combat_trickery", "rank": 1}]
	var result: Dictionary = env.resolver.resolve_maneuver(env.pc, env.monster, "disarm", {})
	var hit_result: Dictionary = result.get("hit_result", {})
	check(hit_result.get("to_hit_bonus", -99) == -2,
		"combat trickery should reduce maneuver penalty from -4 to -2 (got %d)" % hit_result.get("to_hit_bonus", -99))


# ---------------------------------------------------------------------------
# Nonlethal damage tracking
# ---------------------------------------------------------------------------

func test_nonlethal_damage_accumulates() -> void:
	# Brawl and incapacitate both flag nonlethal. Verify the combatant tracker.
	var env := _make_env(20)  # Hit
	check(env.monster.nonlethal_damage_taken == 0, "should start at 0")
	# Simulate what CombatController does: check for nonlethal flag and accumulate
	var result: Dictionary = env.resolver.resolve_maneuver(env.pc, env.monster, "brawl", {})
	if result.get("nonlethal", false) and result.get("hit", false):
		var hp_dmg: int = result.get("damage_result", {}).get("hp_damage", 0)
		if hp_dmg > 0:
			env.monster.add_nonlethal_damage(hp_dmg)
	check(env.monster.nonlethal_damage_taken > 0,
		"nonlethal damage should accumulate after brawl hit")


# ---------------------------------------------------------------------------
# Test helpers
# ---------------------------------------------------------------------------

func _make_env(forced_roll: int) -> Dictionary:
	var dice := _MockDice.new(forced_roll)
	var attack_resolver := AttackResolver.new(dice)
	var resolver := ManeuverResolver.new(dice, attack_resolver, null, null)
	var pc := _make_pc("pc_1", 10, 3)
	var monster := _make_monster("m_1", 8, 3)
	return {"resolver": resolver, "pc": pc, "monster": monster, "dice": dice}


func _make_env_sequence(rolls: Array) -> Dictionary:
	var dice := _SequenceDice.new(rolls)
	var attack_resolver := AttackResolver.new(dice)
	var resolver := ManeuverResolver.new(dice, attack_resolver, null, null)
	var pc := _make_pc("pc_1", 10, 3)
	var monster := _make_monster("m_1", 8, 3)
	return {"resolver": resolver, "pc": pc, "monster": monster, "dice": dice}


func _make_pc(id: String, hp: int, ac: int) -> Combatant:
	var cd := CharacterData.new()
	cd.id = id
	cd.name = id
	cd.hp_max = hp
	cd.hp_current = hp
	cd.armor_class = ac
	cd.attack_throw = 10
	cd.combat_progression = "fighter"
	cd.level = 3
	cd.strength = 12
	cd.dexterity = 10
	cd.constitution = 10
	cd.intelligence = 10
	cd.wisdom = 10
	cd.charisma = 10
	cd.base_movement = 120
	return Combatant.from_character(cd)


func _make_monster(id: String, hp: int, ac: int) -> Combatant:
	var data := {
		"name": "Orc",
		"hit_dice": {"base": 1, "modifier": 0},
		"armor_class": ac,
		"attack_routines": [{"routine_name": "melee", "usage": "default",
			"attacks": [{"attack_type": "weapon", "count": 1, "damage": "1d6", "to_hit_modifier": 0}]}],
		"save_as": {"class": "F", "level": 1},
		"morale": 0,
		"movement": {"land": {"exploration": 120, "combat": 40}},
	}
	return Combatant.from_monster(data, hp, id, "test_group")


# ---------------------------------------------------------------------------
# Mock dice
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
		var r := RollResult.new()
		r.raw_total = _forced_value
		r.modified_total = _forced_value
		return r


class _SequenceDice:
	extends RefCounted
	var _rolls: Array
	var _index: int = 0
	func _init(rolls: Array) -> void:
		_rolls = rolls
	func _next() -> int:
		var val: int = _rolls[_index % _rolls.size()]
		_index += 1
		return val
	func roll_digital(
			sides: int, count: int = 1, modifier: int = 0,
			_roll_type: String = "") -> RollResult:
		var val := _next()
		var r := RollResult.new()
		r.sides = sides
		r.count = count
		r.modifier = modifier
		r.individual_results = [val]
		r.raw_total = val
		r.modified_total = val + modifier
		r.natural_one = (val == 1 and sides == 20 and count == 1)
		r.natural_max = (val == sides and count == 1)
		return r
	func roll_expression(expression: String, _roll_type: String = "") -> RollResult:
		var val := _next()
		var r := RollResult.new()
		r.raw_total = val
		r.modified_total = val
		return r
