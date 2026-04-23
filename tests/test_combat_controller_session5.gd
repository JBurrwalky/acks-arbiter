extends "res://tests/test_suite_base.gd"

## Integration tests for F-1 Session 5: mortal wounds, XP awards, combat log,
## and end-of-combat lifecycle.


func run_all_tests() -> void:
	test_victory_result_includes_monster_xp()
	test_defeat_result_has_zero_xp()
	test_downed_pc_gets_mortal_wound_result()
	test_downed_pc_condition_is_valid()
	test_dead_pc_flagged_on_instantly_killed()
	test_alive_pc_gets_xp_on_victory()
	test_no_xp_on_defeat()
	test_combat_log_has_round_start()
	test_combat_log_has_attack_entries()
	test_combat_ended_signal_payload()
	if not has_failures():
		print("CombatController Session5: all tests passed.")


# ---------------------------------------------------------------------------
# Test helpers
# ---------------------------------------------------------------------------

class _MockDice:
	extends RefCounted
	var _forced: int

	func _init(v: int) -> void:
		_forced = v

	func roll_digital(sides: int, _count: int = 1, _mod: int = 0,
			_type: String = "") -> RollResult:
		var r := RollResult.new()
		r.raw_total = _forced
		r.modified_total = _forced
		r.individual_results = [_forced]
		r.natural_one  = (_forced == 1 and sides == 20)
		r.natural_max  = (_forced == sides)
		return r

	func roll_expression(_expr: String, _type: String = "") -> RollResult:
		var r := RollResult.new()
		r.raw_total = _forced
		r.modified_total = _forced
		r.individual_results = [_forced]
		return r


## Fixed-value dice that returns a specific value for d20 and d6 rolls separately.
class _SplitDice:
	extends RefCounted
	var _d20_val: int
	var _d6_val: int

	func _init(d20: int, d6: int) -> void:
		_d20_val = d20
		_d6_val = d6

	func roll_digital(sides: int, _count: int = 1, _mod: int = 0,
			_type: String = "") -> RollResult:
		var r := RollResult.new()
		var v := _d20_val if sides == 20 else _d6_val
		r.raw_total = v
		r.modified_total = v
		r.individual_results = [v]
		return r

	func roll_expression(_expr: String, _type: String = "") -> RollResult:
		var r := RollResult.new()
		r.raw_total = _d6_val
		r.modified_total = _d6_val
		r.individual_results = [_d6_val]
		return r


func _make_controller_with_mortal_wounds(
		pc_hp: int, monster_hp: int,
		attack_dice_value: int,
		mw_d20_val: int, mw_d6_val: int) -> CombatController:
	var roster := CombatRoster.new()

	var cd := CharacterData.new()
	cd.id = "pc_0"
	cd.name = "Fighter"
	cd.hp_max = pc_hp
	cd.hp_current = pc_hp
	cd.armor_class = 0
	cd.attack_throw = 10
	cd.strength = 10
	cd.constitution = 10
	cd.hit_die_type = "1d8"
	roster.add_combatant(Combatant.from_character(cd, "pc_0"))

	var monster_data := {
		"id": "goblin_0", "name": "Goblin",
		"hit_dice": {"base": 1, "modifier": 0},
		"armor_class": 0,
		"attack_routines": [{"routine_name": "melee", "usage": "default", "attacks": [
			{"attack_type": "weapon", "count": 1, "damage": "1d6", "to_hit_modifier": 0}
		]}],
		"save_as": {"class": "fighter", "level": 1},
		"morale": 0,
		"xp": 10,
		"movement": {"land": {"exploration": 120, "combat": 40}},
	}
	roster.add_combatant(Combatant.from_monster(monster_data, monster_hp, "goblin_0", "goblins"))
	roster.enemy_count_at_start = 1

	var attack_dice := _MockDice.new(attack_dice_value)
	var init_resolver := InitiativeResolver.new(attack_dice)
	var attack_resolver := AttackResolver.new(attack_dice)

	var mw_dice := _SplitDice.new(mw_d20_val, mw_d6_val)
	var mw_resolver := MortalWoundsResolver.new(mw_dice)

	return CombatController.new(
		roster, init_resolver, attack_resolver,
		null, null, null, null, null, null,
		mw_resolver)


func _run_to_completion(controller: CombatController) -> Dictionary:
	var max_iter := 300
	var i := 0
	while i < max_iter:
		var result := controller.advance()
		var status: String = result.get("status", "")
		if status == "waiting_for_pc_action":
			controller.submit_pc_action(result["combatant_id"], "attack_melee")
			continue
		if status == "combat_over":
			return result
		i += 1
	check(false, "combat did not complete in %d iterations" % max_iter)
	return {"result": "timeout", "rounds": 0, "monster_xp_total": 0, "downed_pcs": []}


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_victory_result_includes_monster_xp() -> void:
	# PC has lots of HP (won't die). Monster dies fast. Should get xp_total = 10.
	var controller := _make_controller_with_mortal_wounds(30, 1, 15, 10, 3)
	var result := _run_to_completion(controller)
	check(result.get("result") == "victory",
		"expected victory, got %s" % result.get("result"))
	check(result.get("monster_xp_total", 0) == 10,
		"monster_xp_total should be 10 (1 goblin with xp=10), got %d" \
			% result.get("monster_xp_total", 0))


func test_defeat_result_has_zero_xp() -> void:
	# PC has 1 HP, monster has lots of HP. PC dies first.
	var controller := _make_controller_with_mortal_wounds(1, 50, 15, 10, 3)
	var result := _run_to_completion(controller)
	check(result.get("result") == "defeat",
		"expected defeat, got %s" % result.get("result"))
	# XP is tallied from defeated enemies only; monster is still alive → 0.
	check(result.get("monster_xp_total", 0) == 0,
		"no xp on defeat when monster still alive")


func test_downed_pc_gets_mortal_wound_result() -> void:
	# PC 1 HP → dies first round. Check downed_pcs array is populated.
	# Mortal wounds are now deferred — entries have needs_mortal_wound_check instead
	# of mortal_wound_result.
	var controller := _make_controller_with_mortal_wounds(1, 50, 15, 10, 3)
	var result := _run_to_completion(controller)
	var downed: Array = result.get("downed_pcs", [])
	check(downed.size() >= 1,
		"downed_pcs should have at least 1 entry when PC is downed, got %d" % downed.size())
	if downed.size() >= 1:
		var entry: Dictionary = downed[0]
		check(entry.has("combatant_id"),
			"downed_pcs entry should have combatant_id")
		check(entry.get("needs_mortal_wound_check", false) == true,
			"downed_pcs entry should have needs_mortal_wound_check = true")


func test_downed_pc_condition_is_valid() -> void:
	# With deferred mortal wounds, the downed_pcs entries now contain
	# needs_mortal_wound_check + raw data for future resolution.
	# Verify the deferred data includes the fields needed for later resolution.
	var controller := _make_controller_with_mortal_wounds(1, 50, 15, 10, 3)
	var result := _run_to_completion(controller)
	var downed: Array = result.get("downed_pcs", [])
	if downed.size() >= 1:
		var entry: Dictionary = downed[0]
		check(entry.has("hp_when_downed"),
			"deferred mortal wound entry should have hp_when_downed")
		check(entry.has("killing_blow_damage_type"),
			"deferred mortal wound entry should have killing_blow_damage_type")
		check(entry.has("round_downed"),
			"deferred mortal wound entry should have round_downed")


func test_dead_pc_flagged_on_instantly_killed() -> void:
	# With deferred mortal wounds, downed PCs are NOT auto-killed.
	# Verify that the entry is marked for deferred check instead.
	# The actual mortal wound resolution (and is_dead flag) will happen
	# when another character inspects the downed unit via future UI.
	var controller := _make_controller_with_mortal_wounds(1, 50, 15, 1, 3)
	var result := _run_to_completion(controller)
	var downed: Array = result.get("downed_pcs", [])
	if downed.size() >= 1:
		check(downed[0].get("needs_mortal_wound_check", false) == true,
			"downed PC should be marked needs_mortal_wound_check, not auto-resolved")


func test_alive_pc_gets_xp_on_victory() -> void:
	# PC survives (lots of HP), kills goblin. XP should be in result.
	var controller := _make_controller_with_mortal_wounds(30, 1, 15, 10, 3)
	var result := _run_to_completion(controller)
	check(result.get("result") == "victory",
		"expected victory for xp test")
	check(result.get("monster_xp_total", 0) > 0,
		"monster_xp_total should be > 0 on victory, got %d" \
			% result.get("monster_xp_total", 0))


func test_no_xp_on_defeat() -> void:
	var controller := _make_controller_with_mortal_wounds(1, 50, 15, 10, 3)
	var result := _run_to_completion(controller)
	check(result.get("result") == "defeat", "expected defeat")
	# monster_xp_total is 0 because no enemies were defeated
	check(result.get("monster_xp_total", 0) == 0,
		"no enemies defeated on defeat → xp=0, got %d" \
			% result.get("monster_xp_total", 0))


func test_combat_log_has_round_start() -> void:
	var controller := _make_controller_with_mortal_wounds(30, 1, 15, 10, 3)
	_run_to_completion(controller)
	var log_entries: Array = controller.combat_log.get_entries_by_type(CombatLog.EntryType.ROUND_START)
	check(log_entries.size() >= 1,
		"combat_log should have at least 1 ROUND_START entry, got %d" % log_entries.size())


func test_combat_log_has_attack_entries() -> void:
	var controller := _make_controller_with_mortal_wounds(30, 1, 15, 10, 3)
	_run_to_completion(controller)
	var attacks: Array = controller.combat_log.get_entries_by_type(CombatLog.EntryType.ATTACK)
	check(attacks.size() >= 1,
		"combat_log should have at least 1 ATTACK entry, got %d" % attacks.size())


func test_combat_ended_signal_payload() -> void:
	var controller := _make_controller_with_mortal_wounds(30, 1, 15, 10, 3)
	var signal_payloads: Array = []
	var _listener := func(_eid: String, outcome: Dictionary) -> void:
		signal_payloads.append(outcome)
	EventBus.combat_ended.connect(_listener)

	_run_to_completion(controller)

	EventBus.combat_ended.disconnect(_listener)

	check(signal_payloads.size() == 1,
		"combat_ended should fire exactly once, got %d" % signal_payloads.size())
	if signal_payloads.size() >= 1:
		var payload: Dictionary = signal_payloads[0]
		check(payload.has("result"),     "payload should have 'result'")
		check(payload.has("rounds"),     "payload should have 'rounds'")
		check(payload.has("monster_xp_total"), "payload should have 'monster_xp_total'")
		check(payload.has("downed_pcs"), "payload should have 'downed_pcs'")
		check(payload.has("combat_log"), "payload should have 'combat_log'")
