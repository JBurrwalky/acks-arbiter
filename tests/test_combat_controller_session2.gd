extends "res://tests/test_suite_base.gd"

## Integration tests for Session 2 combat wiring:
## spell hooks, ranged attacks, conditions, and spell interruption.


func run_all_tests() -> void:
	test_existing_melee_combat_still_works_with_hooks()
	test_backward_compat_null_hooks()
	test_ranged_attack_action()
	test_condition_blocks_action()
	test_cast_spell_interrupted_on_damage()
	test_cast_spell_resolves_without_damage()
	if not has_failures():
		print("CombatController Session 2: all tests passed.")


func test_existing_melee_combat_still_works_with_hooks() -> void:
	# Full combat with all Session 2 deps wired — melee only
	var controller := _make_controller_with_hooks(
		[{"id": "pc_0", "hp": 10, "ac": 0, "atk": 10, "str": 10}],
		[{"hd": 1, "ac": 0, "damage": "1d6", "hp": 4}],
		15)
	var result := _run_to_completion(controller)
	check(result.get("result", "") == "victory",
		"melee combat with hooks should still end in victory")


func test_backward_compat_null_hooks() -> void:
	# Session 1 style — null hooks, condition_manager, ranged_resolver
	var controller := _make_controller_no_hooks(
		[{"id": "pc_0", "hp": 10, "ac": 0, "atk": 10, "str": 10}],
		[{"hd": 1, "ac": 0, "damage": "1d6", "hp": 4}],
		15)
	var result := _run_to_completion(controller)
	check(result.get("result", "") == "victory",
		"null hooks should work identically to Session 1")


func test_ranged_attack_action() -> void:
	var controller := _make_controller_with_hooks(
		[{"id": "archer", "hp": 10, "ac": 0, "atk": 10, "str": 10}],
		[{"hd": 1, "ac": 0, "damage": "1d6", "hp": 1}],
		20)

	# Start combat and advance to PC's turn
	controller.advance()  # combat_started
	controller.advance()  # round_started
	controller.advance()  # initiative_rolled

	# Advance until PC turn
	var found_pc := false
	for i in range(20):
		var result := controller.advance()
		if result.get("status", "") == "waiting_for_pc_action":
			# Submit ranged attack
			controller.submit_pc_action("archer", "attack_ranged", {
				"weapon_data": {
					"range_short": 50, "range_medium": 100, "range_long": 150,
					"weapon_damage": "1d6",
				},
				"distance_ft": 30,
				"target_in_melee": false,
			})
			var action_result := controller.advance()
			check(action_result.get("status", "") == "action_resolved",
				"ranged attack should resolve")
			var inner: Dictionary = action_result.get("result", {})
			check(inner.get("hit", false) == true,
				"nat 20 ranged attack should hit")
			check(inner.get("range_band", "") == "short",
				"30ft should be short range")
			found_pc = true
			break

	check(found_pc, "should have found PC turn for ranged attack")


func test_condition_blocks_action() -> void:
	var catalog := ConditionCatalog.new()
	var cond_mgr := CombatConditionManager.new(catalog)
	var controller := _make_controller_with_deps(
		[{"id": "paralyzed_pc", "hp": 20, "ac": 5, "atk": 10, "str": 10}],
		[{"hd": 1, "ac": 0, "damage": "1d4", "hp": 50}],
		15, null, cond_mgr)

	# Apply paralyzed to the PC
	var pc := controller.roster.get_by_id("paralyzed_pc")
	check(pc != null, "should find PC combatant")
	cond_mgr.apply_condition(pc, "paralyzed", "test", -1)

	# Run combat — PC should be forced to pass every turn
	controller.advance()  # combat_started
	controller.advance()  # round_started
	controller.advance()  # initiative_rolled

	# Advance through actions — PC should never get "waiting_for_pc_action"
	# because paralyzed forces pass
	var pc_was_asked := false
	for i in range(30):
		var result := controller.advance()
		if result.get("status", "") == "waiting_for_pc_action":
			pc_was_asked = true
			break
		if result.get("status", "") == "combat_over":
			break
	check(not pc_was_asked,
		"paralyzed PC should be auto-passed, never asked for action")


func test_cast_spell_interrupted_on_damage() -> void:
	var hooks := SpellCombatHooks.new(null)
	var controller := _make_controller_with_deps(
		[{"id": "caster", "hp": 20, "ac": 0, "atk": 10, "str": 10}],
		[{"hd": 1, "ac": 0, "damage": "1d4", "hp": 20}],
		15, hooks, null)

	# Mark caster as having taken damage since declaration
	var caster := controller.roster.get_by_id("caster")
	caster.damaged_since_declaration = true

	controller.advance()  # combat_started
	controller.advance()  # round_started

	# Note: damaged_since_declaration was reset by declaration phase.
	# So re-set it after declaration resolves.
	caster.damaged_since_declaration = true

	controller.advance()  # initiative_rolled

	# Find caster's turn and submit cast_spell
	for i in range(20):
		var result := controller.advance()
		if result.get("status", "") == "waiting_for_pc_action":
			controller.submit_pc_action("caster", "cast_spell", {
				"spell_key": "fireball",
				"targets": ["monster_0"],
			})
			var action_result := controller.advance()
			var inner: Dictionary = action_result.get("result", {})
			check(inner.get("interrupted", false) == true,
				"spell should be interrupted when caster took damage")
			return
	check(false, "should have found caster's turn")


func test_cast_spell_resolves_without_damage() -> void:
	var hooks := SpellCombatHooks.new(null)
	var controller := _make_controller_with_deps(
		[{"id": "caster", "hp": 20, "ac": 0, "atk": 10, "str": 10}],
		[{"hd": 1, "ac": 0, "damage": "1d4", "hp": 20}],
		15, hooks, null)

	controller.advance()  # combat_started
	controller.advance()  # round_started
	controller.advance()  # initiative_rolled

	for i in range(20):
		var result := controller.advance()
		if result.get("status", "") == "waiting_for_pc_action":
			controller.submit_pc_action("caster", "cast_spell", {
				"spell_key": "magic_missile",
				"targets": ["monster_0"],
			})
			var action_result := controller.advance()
			var inner: Dictionary = action_result.get("result", {})
			check(inner.get("interrupted", false) == false,
				"spell should resolve when caster was not damaged")
			return
	check(false, "should have found caster's turn")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_controller_with_hooks(
		pc_configs: Array, monster_configs: Array,
		dice_value: int) -> CombatController:
	var hooks := SpellCombatHooks.new(null)
	var catalog := ConditionCatalog.new()
	var cond_mgr := CombatConditionManager.new(catalog)
	return _make_controller_with_deps(
		pc_configs, monster_configs, dice_value, hooks, cond_mgr)


func _make_controller_no_hooks(
		pc_configs: Array, monster_configs: Array,
		dice_value: int) -> CombatController:
	return _make_controller_with_deps(
		pc_configs, monster_configs, dice_value, null, null)


func _make_controller_with_deps(
		pc_configs: Array, monster_configs: Array,
		dice_value: int,
		hooks: SpellCombatHooks,
		cond_mgr: CombatConditionManager) -> CombatController:
	var roster := CombatRoster.new()

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
		roster.add_combatant(
			Combatant.from_monster(monster_data, hp, "monster_%d" % i, "test_group"))

	roster.enemy_count_at_start = monster_configs.size()

	var mock_dice := _MockDice.new(dice_value)
	var init_resolver := InitiativeResolver.new(mock_dice)
	var attack_resolver := AttackResolver.new(mock_dice, hooks)
	var ranged_resolver := RangedAttackResolver.new(mock_dice, hooks)

	return CombatController.new(
		roster, init_resolver, attack_resolver, hooks, cond_mgr, ranged_resolver)


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
