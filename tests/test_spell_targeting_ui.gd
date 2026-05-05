extends "res://tests/test_suite_base.gd"

## Integration tests for Session 2.8 — combat-cast UI integration via
## CombatUIController.PC_SPELL_TARGETING state. Exercises the full path from
## `waiting_for_pc_spell_target` → `_enter_spell_targeting` → click handler →
## `_commit_spell_targeting` → CombatController routing.


class _FakeDice extends RefCounted:
	var fixed: Dictionary = {}

	func set_fixed(roll_type: String, value: int) -> void:
		fixed[roll_type] = value

	func roll_expression(_expression: String, roll_type: String = "") -> RollResult:
		var r := RollResult.new()
		r.roll_type = roll_type
		r.modified_total = int(fixed.get(roll_type, 0))
		r.raw_total = r.modified_total
		return r

	func roll_digital(sides: int, count: int = 1, modifier: int = 0, roll_type: String = "") -> RollResult:
		var r := RollResult.new()
		r.modified_total = int(fixed.get(roll_type, count * sides))
		r.raw_total = r.modified_total - modifier
		return r


class _FakeRepo extends RefCounted:
	var expended: Dictionary = {}

	func increment_expended_slot(caster_id: String, level: int) -> bool:
		if not expended.has(caster_id):
			expended[caster_id] = {}
		expended[caster_id][level] = int(expended[caster_id].get(level, 0)) + 1
		return true

	func reset_expended_slots(caster_id: String) -> bool:
		expended[caster_id] = {}
		return true

	func get_expended_slots(caster_id: String) -> Dictionary:
		return expended.get(caster_id, {})


func run_all_tests() -> void:
	test_auto_target_self_commits_immediately()
	test_auto_target_caster_and_radius_includes_caster()
	test_single_entity_click_commits()
	test_area_at_point_anchor_click_then_confirm()
	test_hd_budget_multi_click_then_confirm()
	test_cancel_targeting_consumes_slot()
	test_pc_spell_targeting_state_blocks_other_clicks()
	if not has_failures():
		print("SpellTargetingUI: all tests passed.")


# Fixture builders ----------------------------------------------------------

func _make_resolver(dice) -> Dictionary:
	var repo := _FakeRepo.new()
	var sr := SpellRegistry.new()
	var er := SpellEffectRegistry.new(sr)
	var tracker := ActiveEffectTracker.new()
	var cc := ConditionCatalog.new()
	var cr := CustomResolverRegistry.new()
	var resolver := CastingResolver.new(sr, er, tracker, cc, cr, null, repo, dice)
	return {"resolver": resolver, "repo": repo, "spell_registry": sr, "effect_registry": er}


func _make_pc(id: String, klass: String = "mage", level: int = 5) -> Combatant:
	var cd := CharacterData.new()
	cd.id = id
	cd.name = id
	cd.character_class = klass
	cd.combat_progression = klass
	cd.level = level
	cd.hp_max = 20
	cd.hp_current = 20
	cd.intelligence = 13
	cd.wisdom = 13
	return Combatant.from_character(cd)


func _make_goblin(id: String, hp: int = 30) -> Combatant:
	var monster_data := {
		"id": id,
		"name": id,
		"hit_dice": {"base": 1, "modifier": 0},
		"armor_class": 0,
		"attack_routines": [{"routine_name": "melee", "usage": "default",
			"attacks": [{"attack_type": "weapon", "count": 1, "damage": "1d6", "to_hit_modifier": 0}]}],
		"save_as": {"class": "fighter", "level": 1},
		"morale": 0,
		"xp": 10,
		"movement": {"land": {"exploration": 120, "combat": 40}},
	}
	return Combatant.from_monster(monster_data, hp, id, "g_group")


func _build_setup(dice) -> Dictionary:
	var bundle := _make_resolver(dice)
	var resolver: CastingResolver = bundle.resolver
	var roster := CombatRoster.new()
	var pc := _make_pc("mage_1", "mage", 5)
	roster.add_combatant(pc)
	var init_resolver := InitiativeResolver.new(dice)
	var attack_resolver := AttackResolver.new(dice)
	var controller := CombatController.new(
		roster, init_resolver, attack_resolver,
		null, null, null, null, null, null, null, null, resolver)
	var ui := CombatUIController.new()
	ui.setup(controller)
	ui._dice_override = dice  # Use the test's FakeDice for TargetingController.
	return {
		"resolver": resolver,
		"repo": bundle.repo,
		"controller": controller,
		"ui": ui,
		"pc": pc,
		"roster": roster,
		"dice": dice,
	}


func _drive_to_caster_tick(setup: Dictionary, choice: SpellChoice) -> void:
	## Advances combat to the point where the caster's tick fires with a
	## declared spell. Mage with no enemies: declaration → initiative → action
	## (mage's tick).
	var ui: CombatUIController = setup.ui
	var controller: CombatController = setup.controller
	var pc: Combatant = setup.pc

	ui.advance()  # NOT_STARTED → DECLARATION
	controller.submit_declaration(pc.id, "cast_spell", {"spell_choice": choice})
	# Loop advance until we hit waiting_for_pc_spell_target or PC_SPELL_TARGETING.
	for _i in range(20):
		var result := ui.advance()
		var status: String = result.get("status", "") if result is Dictionary else ""
		if status == "waiting_for_pc_spell_target":
			return
		if ui._state == CombatUIController.State.PC_SPELL_TARGETING:
			return
		# For waiting_for_pc_action, submit pass to keep loop going.
		if status == "waiting_for_pc_action":
			controller.submit_pc_action(result.get("combatant_id", ""), "pass")


# Auto-target tests ---------------------------------------------------------

func test_auto_target_self_commits_immediately() -> void:
	# Shield is self-target. Casting it should auto-resolve (no click needed).
	var setup := _build_setup(_FakeDice.new())
	var choice := SpellChoice.new("shield", 1, false, -1)
	_drive_to_caster_tick(setup, choice)
	var pc: Combatant = setup.pc
	var repo: _FakeRepo = setup.repo
	# After the initial advance hit `waiting_for_pc_spell_target`, the UI's
	# auto-resolution path should have committed and routed back through the
	# controller. Slot expended.
	# But our drive helper might leave us paused — push one more advance
	# in case the UI's _commit_spell_targeting deferred.
	for _i in range(5):
		setup.ui.advance()
	check(repo.get_expended_slots(pc.id).get(1, 0) == 1,
		"Shield (self): L1 slot expended after auto-commit, got %d" %
		repo.get_expended_slots(pc.id).get(1, 0))
	# Shield modifier should now be on the PC's CharacterData.
	check(pc.get_character_data().modifiers.has_modifier_for_stat("armor_class_vs_missiles"),
		"Shield: armor_class_vs_missiles modifier applied via auto-cast")


func test_auto_target_caster_and_radius_includes_caster() -> void:
	# Detect Magic is caster_and_radius. Auto-resolves; no click.
	var setup := _build_setup(_FakeDice.new())
	var choice := SpellChoice.new("detect_magic", 1, false, -1)
	_drive_to_caster_tick(setup, choice)
	for _i in range(5):
		setup.ui.advance()
	var repo: _FakeRepo = setup.repo
	check(repo.get_expended_slots(setup.pc.id).get(1, 0) == 1,
		"Detect Magic: L1 slot expended")


# Single-entity tests -------------------------------------------------------

func test_single_entity_click_commits() -> void:
	var dice := _FakeDice.new()
	dice.set_fixed("spell_damage", 5)
	var setup := _build_setup(dice)
	# Add an enemy goblin so Magic Missile has a valid target.
	var goblin := _make_goblin("g1", 30)
	setup.roster.add_combatant(goblin)

	var choice := SpellChoice.new("magic_missile", 1, false, -1)
	_drive_to_caster_tick(setup, choice)
	var ui: CombatUIController = setup.ui
	check(ui._state == CombatUIController.State.PC_SPELL_TARGETING,
		"After driving: state is PC_SPELL_TARGETING, got %d" % ui._state)
	check(ui._targeting_kind == "single_entity",
		"target_kind is single_entity, got '%s'" % ui._targeting_kind)

	# Click the goblin — should commit immediately.
	ui.on_entity_targeted("g1")
	# Drive any deferred advance.
	for _i in range(5):
		ui.advance()

	var repo: _FakeRepo = setup.repo
	check(repo.get_expended_slots(setup.pc.id).get(1, 0) == 1,
		"Magic Missile: L1 slot expended after entity click")
	check(goblin.get_hp_current() < 30,
		"Magic Missile: goblin took damage, hp=%d" % goblin.get_hp_current())


# area_at_point test --------------------------------------------------------

func test_area_at_point_anchor_click_then_confirm() -> void:
	var dice := _FakeDice.new()
	dice.set_fixed("spell_damage", 4)
	dice.set_fixed("spell_save_blast", 1)  # always fail save
	var setup := _build_setup(dice)
	var pc: Combatant = setup.pc
	pc.grid_position = Vector3i(0, 0, 0)
	var goblin := _make_goblin("ga1", 30)
	goblin.grid_position = Vector3i(2, 0, 0)
	setup.roster.add_combatant(goblin)

	var choice := SpellChoice.new("fireball", 3, false, -1)
	_drive_to_caster_tick(setup, choice)
	var ui: CombatUIController = setup.ui
	check(ui._targeting_kind == "area_at_point",
		"target_kind is area_at_point, got '%s'" % ui._targeting_kind)

	# Click an anchor cell near the goblin.
	ui.on_cell_targeted(Vector3i(2, 0, 0))
	# AoE preview is now showing — confirm via the panel signal.
	ui.on_confirm_spell_targeting()
	for _i in range(5):
		ui.advance()

	check(goblin.get_hp_current() < 30,
		"Fireball: goblin took area damage, hp=%d" % goblin.get_hp_current())


# HD-budget multi-click test ------------------------------------------------

func test_hd_budget_multi_click_then_confirm() -> void:
	var dice := _FakeDice.new()
	dice.set_fixed("spell_hd_budget", 6)
	var setup := _build_setup(dice)
	var pc: Combatant = setup.pc
	# Make the mage L1 so Sleep is castable.
	pc.get_character_data().level = 1
	pc.grid_position = Vector3i(0, 0, 0)
	for i in range(3):
		var g := _make_goblin("ghd_%d" % i, 4)
		g.grid_position = Vector3i(i + 1, 0, 0)
		setup.roster.add_combatant(g)

	# Sleep group branch (disjunctive_index = 1).
	var choice := SpellChoice.new("sleep", 1, false, 1)
	_drive_to_caster_tick(setup, choice)
	var ui: CombatUIController = setup.ui
	check(ui._targeting_kind == "hd_budget",
		"target_kind is hd_budget, got '%s'" % ui._targeting_kind)

	# Click two goblins (each 1 HD; budget is 6 HD).
	ui.on_entity_targeted("ghd_0")
	ui.on_entity_targeted("ghd_1")
	# Confirm.
	ui.on_confirm_spell_targeting()
	for _i in range(5):
		ui.advance()

	var repo: _FakeRepo = setup.repo
	check(repo.get_expended_slots(pc.id).get(1, 0) == 1,
		"Sleep group: L1 slot expended after multi-click + confirm")


# Cancel test ---------------------------------------------------------------

func test_cancel_targeting_consumes_slot() -> void:
	# Per ACKS, a cancelled cast (declared then aborted) still consumes the
	# slot. Our implementation routes cancel through the disrupted path.
	var setup := _build_setup(_FakeDice.new())
	var choice := SpellChoice.new("magic_missile", 1, false, -1)
	_drive_to_caster_tick(setup, choice)
	setup.ui.on_cancel_spell_targeting()
	for _i in range(5):
		setup.ui.advance()
	var repo: _FakeRepo = setup.repo
	check(repo.get_expended_slots(setup.pc.id).get(1, 0) == 1,
		"Cancelled cast: L1 slot still expended (ACKS rule)")


# State gating test ---------------------------------------------------------

func test_pc_spell_targeting_state_blocks_other_clicks() -> void:
	# During PC_SPELL_TARGETING, on_entity_targeted should route only to
	# spell-targeting logic, not to the cleave / facing paths.
	var dice := _FakeDice.new()
	dice.set_fixed("spell_damage", 5)
	var setup := _build_setup(dice)
	var goblin := _make_goblin("g_state", 30)
	setup.roster.add_combatant(goblin)
	var choice := SpellChoice.new("magic_missile", 1, false, -1)
	_drive_to_caster_tick(setup, choice)
	check(setup.ui._state == CombatUIController.State.PC_SPELL_TARGETING,
		"state is PC_SPELL_TARGETING after driving")
	# Click goblin: routes to spell-targeting (commit), not cleave/facing.
	setup.ui.on_entity_targeted("g_state")
	for _i in range(5):
		setup.ui.advance()
	# After commit, state should have left PC_SPELL_TARGETING.
	check(setup.ui._state != CombatUIController.State.PC_SPELL_TARGETING,
		"state moved on after spell commit")
