extends "res://tests/test_suite_base.gd"

## Integration tests for CombatController with grid-based movement.
## Tests melee range gating, auto-move, ranged distance, charge, defensive movement.


func run_all_tests() -> void:
	test_no_grid_melee_works_as_before()
	test_grid_melee_adjacent_succeeds()
	test_grid_melee_out_of_range_fails()
	test_grid_melee_auto_move_to_engage()
	test_grid_ranged_uses_grid_distance()
	test_charge_action_succeeds()
	test_charge_too_close_fails()
	test_move_action_updates_position()
	test_fighting_withdrawal_action()
	test_full_retreat_applies_vulnerable()
	test_submit_declaration_fighting_withdrawal()
	test_engagement_condition_applied()
	if not has_failures():
		print("CombatControllerSession4: all tests passed.")


# ---------------------------------------------------------------------------
# Backward compatibility: no grid
# ---------------------------------------------------------------------------

func test_no_grid_melee_works_as_before() -> void:
	var env := _make_controller_no_grid(15)  # Roll 15 = likely hit
	_advance_to_action(env.ctrl)
	env.ctrl.submit_pc_action("pc_1", "attack_melee", {"target_id": "m_1"})
	var result: Dictionary = _advance_until_pc_resolved(env.ctrl)
	check(result["status"] == "action_resolved",
		"melee without grid should resolve normally")
	check(result.get("action", "") == "attack_melee",
		"action should be attack_melee")


# ---------------------------------------------------------------------------
# Grid-based melee
# ---------------------------------------------------------------------------

func test_grid_melee_adjacent_succeeds() -> void:
	var env := _make_controller_with_grid(15, 20, 20)
	# Place PC adjacent to monster
	env.map.set_entity_pos("pc_1", Vector2i(5, 5))
	env.pc.grid_position = Vector2i(5, 5)
	env.map.set_entity_pos("m_1", Vector2i(5, 6))
	env.monster.grid_position = Vector2i(5, 6)
	_advance_to_action(env.ctrl)
	env.ctrl.submit_pc_action("pc_1", "attack_melee", {"target_id": "m_1"})
	var result: Dictionary = _advance_until_pc_resolved(env.ctrl)
	check(result["status"] == "action_resolved", "should resolve action")
	check(result.get("action", "") == "attack_melee", "should be melee attack")
	# Should not have "out of range" note
	var note: String = result.get("result", {}).get("note", "")
	check(note == "" or "range" not in note,
		"adjacent melee should succeed, got note: %s" % note)


func test_grid_melee_out_of_range_fails() -> void:
	var env := _make_controller_with_grid(15, 30, 30)
	# Place PC far from monster (more than combat movement = 8 cells for 40ft move)
	env.map.set_entity_pos("pc_1", Vector2i(0, 0))
	env.pc.grid_position = Vector2i(0, 0)
	env.map.set_entity_pos("m_1", Vector2i(25, 25))
	env.monster.grid_position = Vector2i(25, 25)
	_advance_to_action(env.ctrl)
	env.ctrl.submit_pc_action("pc_1", "attack_melee", {"target_id": "m_1"})
	var result: Dictionary = _advance_until_pc_resolved(env.ctrl)
	var note: String = result.get("result", {}).get("note", "")
	check("range" in note or "reachable" in note or "adjacent" in note,
		"should fail with range/reachable note, got: %s" % note)


func test_grid_melee_auto_move_to_engage() -> void:
	# PC melee attack at distance should fail with "target not adjacent" —
	# PCs must move first (move+attack split turn), no auto-move.
	var env := _make_controller_with_grid(15, 20, 20)
	# Place PC 3 cells from monster (not adjacent)
	env.map.set_entity_pos("pc_1", Vector2i(2, 2))
	env.pc.grid_position = Vector2i(2, 2)
	env.map.set_entity_pos("m_1", Vector2i(5, 2))
	env.monster.grid_position = Vector2i(5, 2)
	_advance_to_action(env.ctrl)
	env.ctrl.submit_pc_action("pc_1", "attack_melee", {"target_id": "m_1"})
	var result: Dictionary = _advance_until_pc_resolved(env.ctrl)
	check(result["status"] == "action_resolved", "should resolve action")
	var note: String = result.get("result", {}).get("note", "")
	check(note == "target not adjacent",
		"non-adjacent melee attack should fail with 'target not adjacent', got '%s'" % note)


# ---------------------------------------------------------------------------
# Grid-based ranged
# ---------------------------------------------------------------------------

func test_grid_ranged_uses_grid_distance() -> void:
	var env := _make_controller_with_grid(15, 20, 20)
	env.map.set_entity_pos("pc_1", Vector2i(0, 0))
	env.pc.grid_position = Vector2i(0, 0)
	env.map.set_entity_pos("m_1", Vector2i(10, 0))
	env.monster.grid_position = Vector2i(10, 0)
	_advance_to_action(env.ctrl)
	# 10 cells * 5ft = 50ft distance
	env.ctrl.submit_pc_action("pc_1", "attack_ranged", {
		"target_id": "m_1",
		"weapon_data": {"range_short": 30, "range_medium": 60, "range_long": 90, "weapon_damage": "1d6"},
	})
	var result: Dictionary = _advance_until_pc_resolved(env.ctrl)
	check(result["status"] == "action_resolved", "ranged should resolve")


# ---------------------------------------------------------------------------
# Charge
# ---------------------------------------------------------------------------

func test_charge_action_succeeds() -> void:
	var env := _make_controller_with_grid(15, 20, 20)
	env.map.set_entity_pos("pc_1", Vector2i(0, 0))
	env.pc.grid_position = Vector2i(0, 0)
	env.map.set_entity_pos("m_1", Vector2i(6, 0))
	env.monster.grid_position = Vector2i(6, 0)
	_advance_to_action(env.ctrl)
	env.ctrl.submit_pc_action("pc_1", "charge", {"target_id": "m_1"})
	var result: Dictionary = _advance_until_pc_resolved(env.ctrl)
	check(result["status"] == "action_resolved", "charge should resolve")
	check(result.get("action", "") == "charge", "action should be charge")


func test_charge_too_close_fails() -> void:
	var env := _make_controller_with_grid(15, 20, 20)
	env.map.set_entity_pos("pc_1", Vector2i(3, 3))
	env.pc.grid_position = Vector2i(3, 3)
	env.map.set_entity_pos("m_1", Vector2i(5, 3))
	env.monster.grid_position = Vector2i(5, 3)
	_advance_to_action(env.ctrl)
	env.ctrl.submit_pc_action("pc_1", "charge", {"target_id": "m_1"})
	var result: Dictionary = _advance_until_pc_resolved(env.ctrl)
	var note: String = result.get("result", {}).get("note", "")
	check("too close" in note or "invalid" in note,
		"charge should fail when too close, got: %s" % note)


# ---------------------------------------------------------------------------
# Move action
# ---------------------------------------------------------------------------

func test_move_action_updates_position() -> void:
	var env := _make_controller_with_grid(15, 20, 20)
	env.map.set_entity_pos("pc_1", Vector2i(0, 0))
	env.pc.grid_position = Vector2i(0, 0)
	env.map.set_entity_pos("m_1", Vector2i(15, 15))
	env.monster.grid_position = Vector2i(15, 15)
	_advance_to_action(env.ctrl)
	env.ctrl.submit_pc_action("pc_1", "move", {"target_x": 5, "target_y": 0})
	var result: Dictionary = _advance_until_pc_resolved(env.ctrl)
	check(result.get("action", "") == "move", "should be move action")
	check(env.pc.has_moved_this_round == true, "should flag movement")


# ---------------------------------------------------------------------------
# Defensive movement
# ---------------------------------------------------------------------------

func test_fighting_withdrawal_action() -> void:
	var env := _make_controller_with_grid(15, 20, 20)
	env.map.set_entity_pos("pc_1", Vector2i(5, 5))
	env.pc.grid_position = Vector2i(5, 5)
	env.map.set_entity_pos("m_1", Vector2i(5, 6))
	env.monster.grid_position = Vector2i(5, 6)
	_advance_to_action(env.ctrl)
	env.ctrl.submit_pc_action("pc_1", "fighting_withdrawal", {})
	var result: Dictionary = _advance_until_pc_resolved(env.ctrl)
	check(result.get("action", "") == "fighting_withdrawal",
		"should be fighting_withdrawal action")


func test_full_retreat_applies_vulnerable() -> void:
	var env := _make_controller_with_grid(15, 20, 20)
	env.map.set_entity_pos("pc_1", Vector2i(5, 5))
	env.pc.grid_position = Vector2i(5, 5)
	env.map.set_entity_pos("m_1", Vector2i(5, 6))
	env.monster.grid_position = Vector2i(5, 6)
	_advance_to_action(env.ctrl)
	env.ctrl.submit_pc_action("pc_1", "full_retreat", {})
	var result: Dictionary = _advance_until_pc_resolved(env.ctrl)
	check(result.get("action", "") == "full_retreat", "should be full_retreat")
	check(env.pc.has_condition("vulnerable"),
		"full retreat should apply vulnerable condition")


# ---------------------------------------------------------------------------
# Declarations
# ---------------------------------------------------------------------------

func test_submit_declaration_fighting_withdrawal() -> void:
	var env := _make_controller_with_grid(15, 20, 20)
	env.map.set_entity_pos("pc_1", Vector2i(5, 5))
	env.pc.grid_position = Vector2i(5, 5)
	env.map.set_entity_pos("m_1", Vector2i(15, 15))
	env.monster.grid_position = Vector2i(15, 15)
	# Advance to declaration phase
	env.ctrl.advance()  # combat_started
	env.ctrl.submit_declaration("pc_1", "fighting_withdrawal")
	check(env.pc.declared_defensive_movement == "fighting_withdrawal",
		"declaration should set defensive movement")


# ---------------------------------------------------------------------------
# Engagement condition
# ---------------------------------------------------------------------------

func test_engagement_condition_applied() -> void:
	# Use low roll (5) so attacks miss — keeps both alive for engagement check
	var env := _make_controller_with_grid(5, 20, 20)
	env.map.set_entity_pos("pc_1", Vector2i(5, 5))
	env.pc.grid_position = Vector2i(5, 5)
	env.map.set_entity_pos("m_1", Vector2i(5, 6))
	env.monster.grid_position = Vector2i(5, 6)
	# Advance through to action phase
	_advance_to_action(env.ctrl)
	# PC attacks — miss expected but _update_engagement runs
	env.ctrl.submit_pc_action("pc_1", "attack_melee", {"target_id": "m_1"})
	_advance_until_pc_resolved(env.ctrl)
	# After melee action on adjacent target, engagement condition should exist
	check(env.pc.has_condition("engaged") or env.monster.has_condition("engaged"),
		"engagement condition should be applied when adjacent")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _advance_to_action(ctrl: CombatController) -> void:
	## Advance controller through start → declaration → initiative → action.
	ctrl.advance()  # combat_started
	ctrl.advance()  # round_started (declaration)
	ctrl.advance()  # initiative_rolled


func _advance_until_pc_resolved(ctrl: CombatController) -> Dictionary:
	## After submitting a PC action, advance until the PC's action is resolved.
	## Skips monster actions that may resolve first in simultaneous initiative.
	var max_steps := 20
	for _i in range(max_steps):
		var result: Dictionary = ctrl.advance()
		var status: String = result.get("status", "")
		if status == "combat_over" or status == "round_ended":
			return result
		if status == "action_resolved":
			# Check if this is the PC's action (not a monster's)
			var cid: String = result.get("combatant_id", "")
			if cid.begins_with("pc"):
				return result
		if status == "waiting_for_pc_action":
			return result
	return {"status": "timeout"}


func _make_controller_no_grid(forced_roll: int) -> Dictionary:
	var dice := _MockDice.new(forced_roll)
	var roster := CombatRoster.new()
	var pc := _make_pc("pc_1", 20, 3)
	var monster := _make_monster("m_1", 8, 3)
	roster.add_combatant(pc)
	roster.add_combatant(monster)
	roster.enemy_count_at_start = 1
	var init_resolver := InitiativeResolver.new(dice)
	var attack_resolver := AttackResolver.new(dice)
	var ctrl := CombatController.new(roster, init_resolver, attack_resolver)
	return {"ctrl": ctrl, "roster": roster, "pc": pc, "monster": monster}


func _make_controller_with_grid(forced_roll: int, w: int, h: int) -> Dictionary:
	var dice := _MockDice.new(forced_roll)
	var map := _make_open_map(w, h)
	var roster := CombatRoster.new()
	var pc := _make_pc("pc_1", 20, 3)
	var monster := _make_monster("m_1", 8, 3)
	roster.add_combatant(pc)
	roster.add_combatant(monster)
	roster.enemy_count_at_start = 1
	var init_resolver := InitiativeResolver.new(dice)
	var attack_resolver := AttackResolver.new(dice)
	var condition_catalog := ConditionCatalog.new()
	var condition_manager := CombatConditionManager.new(condition_catalog)
	var ranged_resolver := RangedAttackResolver.new(dice)
	var ctrl := CombatController.new(
		roster, init_resolver, attack_resolver,
		null, condition_manager, ranged_resolver,
		null, null, null, map)
	return {
		"ctrl": ctrl, "roster": roster, "pc": pc, "monster": monster,
		"map": map, "dice": dice,
	}


func _make_open_map(w: int, h: int) -> TacticalMapData:
	var cells_array: Array = []
	for col in range(w):
		for row in range(h):
			cells_array.append({
				"col": col, "row": row,
				"terrain_feature": "open",
				"elevation": 0,
			})
	return TacticalMapData.from_dict({
		"grid_width": w, "grid_height": h,
		"entry_col": 0, "entry_row": 0,
		"cells": cells_array,
	})


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
		"combat_behavior": {
			"primary_target_rule": "nearest",
			"target_tie_breaker": "nearest",
			"engagement_profile": "melee",
		},
	}
	return Combatant.from_monster(data, hp, id, "test_group")


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
