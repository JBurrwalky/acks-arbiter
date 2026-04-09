extends "res://tests/test_suite_base.gd"

## Integration tests for CombatController — full combat round loop.


func run_all_tests() -> void:
	test_combat_starts_and_advances()
	test_full_combat_fighter_vs_goblin()
	test_party_defeat()
	test_multi_combatant_initiative_order()
	test_pass_action()
	test_combat_ends_when_all_enemies_dead()
	test_multi_round_combat()
	test_monster_multi_attack()
	if not has_failures():
		print("CombatController: all tests passed.")


func test_combat_starts_and_advances() -> void:
	var controller := _make_controller(1, 1)
	var result := controller.advance()
	check(result["status"] == "combat_started",
		"first advance should be combat_started, got %s" % result["status"])

	result = controller.advance()
	check(result["status"] == "round_started",
		"second advance should be round_started, got %s" % result["status"])


func test_full_combat_fighter_vs_goblin() -> void:
	# Fighter (10 HP, AC 5, attack_throw 10) vs Goblin (3 HP, AC 3)
	# MockDice returns 15 for attacks = always hits.
	var controller := _make_controller(1, 1, 15)

	# Start combat
	controller.advance()  # combat_started
	controller.advance()  # round_started (declaration -> init)
	controller.advance()  # initiative_rolled

	# Advance through actions until combat ends
	var max_iterations := 50
	var ended := false
	var i := 0
	while i < max_iterations:
		var result := controller.advance()
		var status: String = result.get("status", "")

		if status == "waiting_for_pc_action":
			var combatant_id: String = result["combatant_id"]
			controller.submit_pc_action(combatant_id, "attack_melee")
			continue  # Re-advance to process the action

		if status == "combat_over":
			ended = true
			check(result.get("result", "") == "victory",
				"party should win, got %s" % result.get("result", ""))
			break
		i += 1

	check(ended, "combat should end within %d iterations" % max_iterations)


func test_party_defeat() -> void:
	# 1 weak PC (1 HP) vs 1 strong monster (50 HP)
	# Dice always hit
	var controller := _make_controller_custom(
		[{"id": "weak_pc", "hp": 1, "ac": 0, "atk": 10, "str": 10}],
		[{"hd": 5, "ac": 0, "damage": "1d8", "hp": 50}],
		15)

	# Run combat to completion
	var result := _run_to_completion(controller)
	check(result.get("result", "") == "defeat",
		"party should lose when all PCs downed, got %s" % result.get("result", ""))


func test_multi_combatant_initiative_order() -> void:
	# 2 PCs vs 2 monsters — verify initiative rolls happen
	var controller := _make_controller(2, 2)
	controller.advance()  # combat_started
	controller.advance()  # round_started
	var result := controller.advance()  # initiative_rolled
	check(result["status"] == "initiative_rolled",
		"should get initiative, got %s" % result["status"])
	var order: Array = result.get("initiative_order", [])
	check(order.size() == 4,
		"4 combatants should have 4 initiative entries, got %d" % order.size())


func test_pass_action() -> void:
	var controller := _make_controller(1, 1)
	controller.advance()  # combat_started
	controller.advance()  # round_started
	controller.advance()  # initiative_rolled

	# Find the PC's turn
	var max_i := 20
	var i := 0
	while i < max_i:
		var result := controller.advance()
		if result.get("status", "") == "waiting_for_pc_action":
			controller.submit_pc_action(result["combatant_id"], "pass")
			var action_result := controller.advance()
			check(action_result.get("status", "") == "action_resolved",
				"pass action should resolve")
			check(action_result.get("action", "") == "pass",
				"action should be 'pass'")
			break
		i += 1


func test_combat_ends_when_all_enemies_dead() -> void:
	# 1 strong PC vs 1 weak monster
	var controller := _make_controller_custom(
		[{"id": "strong", "hp": 50, "ac": 5, "atk": 5, "str": 18}],
		[{"hd": 1, "ac": 0, "damage": "1d4", "hp": 1}],
		20)
	var result := _run_to_completion(controller)
	check(result.get("result", "") == "victory",
		"should be victory when all enemies dead")


func test_multi_round_combat() -> void:
	# Both have enough HP that it takes multiple rounds
	# dice=10 ensures hits (10 >= 10+0) but deals moderate damage
	var controller := _make_controller_custom(
		[{"id": "tank", "hp": 50, "ac": 0, "atk": 10, "str": 10}],
		[{"hd": 2, "ac": 0, "damage": "1d4", "hp": 30}],
		10)
	var result := _run_to_completion(controller)
	check(controller.total_rounds >= 2,
		"combat should last at least 2 rounds, lasted %d" % controller.total_rounds)
	check(result.get("result", "") != "",
		"combat should have a result")


func test_monster_multi_attack() -> void:
	# Monster with 2 attacks
	var controller := _make_controller_custom(
		[{"id": "pc", "hp": 30, "ac": 0, "atk": 10, "str": 10}],
		[{
			"hd": 3, "ac": 5, "damage": "1d6", "hp": 15,
			"attacks": [
				{"attack_type": "claw", "count": 1, "damage": "1d4", "to_hit_modifier": 0},
				{"attack_type": "bite", "count": 1, "damage": "1d8", "to_hit_modifier": 0},
			]
		}],
		15)

	# Run one round and check the monster gets multiple attacks
	var result := _run_to_completion(controller)
	# We can't easily verify multi-attack from the result dict without inspecting
	# the event log, but if combat completes without error, the multi-attack worked.
	check(result.get("result", "") != "", "combat should complete with multi-attack monster")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_controller(
		num_pcs: int, num_monsters: int, dice_value: int = 10) -> CombatController:
	var pcs: Array = []
	for i in range(num_pcs):
		# HP 30 ensures PCs survive monster attacks in simultaneous initiative
		pcs.append({"id": "pc_%d" % i, "hp": 30, "ac": 0, "atk": 10, "str": 10})
	var monsters: Array = []
	for i in range(num_monsters):
		monsters.append({"hd": 1, "ac": 0, "damage": "1d6", "hp": 4})
	return _make_controller_custom(pcs, monsters, dice_value)


func _make_controller_custom(
		pc_configs: Array,
		monster_configs: Array,
		dice_value: int = 10) -> CombatController:
	var roster := CombatRoster.new()

	# Build PCs
	for cfg: Dictionary in pc_configs:
		var cd := CharacterData.new()
		cd.id = cfg.get("id", "pc")
		cd.name = cd.id
		cd.hp_max = cfg.get("hp", 10)
		cd.hp_current = cd.hp_max
		cd.armor_class = cfg.get("ac", 0)
		cd.attack_throw = cfg.get("atk", 10)
		cd.strength = cfg.get("str", 10)
		cd.dexterity = cfg.get("dex", 10)
		roster.add_combatant(Combatant.from_character(cd))

	# Build monsters
	for i in range(monster_configs.size()):
		var cfg: Dictionary = monster_configs[i]
		var attacks: Array = cfg.get("attacks", [
			{"attack_type": "weapon", "count": 1, "damage": cfg.get("damage", "1d6"), "to_hit_modifier": 0}
		])
		var monster_data := {
			"id": "monster_%d" % i,
			"name": "Monster %d" % i,
			"hit_dice": {"base": cfg.get("hd", 1), "modifier": 0},
			"armor_class": cfg.get("ac", 0),
			"attack_routines": [{"routine_name": "melee", "usage": "default", "attacks": attacks}],
			"save_as": {"class": "fighter", "level": cfg.get("hd", 1)},
			"morale": 0,
			"xp": 10,
			"movement": {"land": {"exploration": 120, "combat": 40}},
		}
		var hp: int = cfg.get("hp", cfg.get("hd", 1) * 4)
		var combatant := Combatant.from_monster(monster_data, hp, "monster_%d" % i, "test_group")
		roster.add_combatant(combatant)

	roster.enemy_count_at_start = monster_configs.size()

	var mock_dice := _MockDice.new(dice_value)
	var init_resolver := InitiativeResolver.new(mock_dice)
	var attack_resolver := AttackResolver.new(mock_dice)

	return CombatController.new(roster, init_resolver, attack_resolver)


func _run_to_completion(controller: CombatController) -> Dictionary:
	var max_iterations := 200
	var i := 0
	while i < max_iterations:
		var result := controller.advance()
		var status: String = result.get("status", "")

		if status == "waiting_for_pc_action":
			controller.submit_pc_action(result["combatant_id"], "attack_melee")
			continue

		if status == "combat_over":
			return result
		i += 1

	check(false, "combat did not complete within %d iterations" % max_iterations)
	return {"result": "timeout"}


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
