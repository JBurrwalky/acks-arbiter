extends "res://tests/test_suite_base.gd"

## Integration tests for Session 2.5: declared spells route through
## CastingResolver on the caster's initiative tick.


# Reuse the FakeDice / FakeRepo pattern from test_casting_resolver.gd. Inline
# here so this suite is self-contained.
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
		r.roll_type = roll_type
		r.sides = sides
		r.count = count
		r.modifier = modifier
		# When a deterministic value is queued, use it; else default to mid-roll.
		if fixed.has(roll_type):
			r.modified_total = int(fixed[roll_type])
		else:
			r.modified_total = count * (sides / 2 + 1) + modifier
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
	test_pc_cast_routes_through_resolver()
	test_pc_cast_disrupted_consumes_slot_no_effect()
	test_targeting_controller_emits_selection_changed()
	if not has_failures():
		print("CombatCastRouting: all tests passed.")


# ---------------------------------------------------------------------------
# Integration helpers
# ---------------------------------------------------------------------------

func _make_resolver(dice) -> Dictionary:
	var repo := _FakeRepo.new()
	var spell_registry := SpellRegistry.new()
	var effect_registry := SpellEffectRegistry.new(spell_registry)
	var effect_tracker := ActiveEffectTracker.new()
	var condition_catalog := ConditionCatalog.new()
	var custom_resolvers := CustomResolverRegistry.new()
	var resolver := CastingResolver.new(
		spell_registry, effect_registry, effect_tracker,
		condition_catalog, custom_resolvers, null, repo, dice)
	return {
		"resolver": resolver,
		"repo": repo,
		"effect_registry": effect_registry,
		"spell_registry": spell_registry,
	}


func _make_pc(id: String, level: int = 5) -> Combatant:
	var cd := CharacterData.new()
	cd.id = id
	cd.name = id
	cd.character_class = "mage"
	cd.combat_progression = "mage"
	cd.level = level
	cd.hp_max = 20
	cd.hp_current = 20
	cd.intelligence = 13
	return Combatant.from_character(cd)


func _make_goblin_combatant(id: String, hp: int = 30) -> Combatant:
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
	return Combatant.from_monster(monster_data, hp, id, "goblin_group")


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_pc_cast_routes_through_resolver() -> void:
	var dice := _FakeDice.new()
	dice.set_fixed("spell_damage", 5)
	var bundle := _make_resolver(dice)
	var resolver: CastingResolver = bundle.resolver
	var repo: _FakeRepo = bundle.repo

	var pc := _make_pc("mage_1", 5)
	var goblin := _make_goblin_combatant("g1", 30)
	var roster := CombatRoster.new()
	roster.add_combatant(pc)
	roster.add_combatant(goblin)

	var init_resolver := InitiativeResolver.new(dice)
	var attack_resolver := AttackResolver.new(dice)
	var controller := CombatController.new(
		roster, init_resolver, attack_resolver,
		null, null, null, null, null, null, null, null, resolver)

	# Submit cast_spell declaration with Magic Missile.
	controller.advance()  # NOT_STARTED → DECLARATION
	var choice := SpellChoice.new("magic_missile", 1, false, -1)
	controller.submit_declaration(pc.id, "cast_spell", {"spell_choice": choice})
	check(pc.is_casting_spell_this_round(),
		"PC has declared spell: is_casting_spell_this_round true")
	check(pc.declared_spell == "magic_missile",
		"declared_spell carries spell_key")

	# Advance through declaration → initiative → action.
	# We loop until we hit either waiting_for_pc_spell_target (good) or
	# action_resolved for the spell cast (also good — depends on initiative).
	var hit_target_wait := false
	var hit_resolution := false
	var goblin_hp_before := goblin.get_hp_current()
	for _i in range(20):
		var result := controller.advance()
		var status: String = result.get("status", "")
		if status == "waiting_for_pc_spell_target":
			hit_target_wait = true
			# Submit the target descriptor: Magic Missile single-target on g1.
			var td := TargetDescriptor.new()
			td.kind = "single_creature"
			td.target_ids = ["g1"]
			# The combatant's CharacterData is the target wrapper for the resolver.
			var goblin_cd := _build_goblin_cd_for_resolver("g1", goblin.get_hp_current())
			# Sync hp back to combatant after damage.
			controller.submit_pc_spell_action(pc.id, td, {"g1": goblin_cd})
			# Run advance once more to consume the pending target.
			result = controller.advance()
			status = result.get("status", "")
			# Check that the goblin CD was damaged (resolver writes to it).
			check(goblin_cd.hp_current < 30,
				"goblin took spell damage; hp now %d" % goblin_cd.hp_current)
			hit_resolution = true
			break
		if status == "waiting_for_pc_action":
			# Mage has no melee action declared; just pass to keep loop alive.
			controller.submit_pc_action(result.get("combatant_id", ""), "pass")
			continue
		if result.get("phase", "") == "end_round":
			break

	check(hit_target_wait, "controller paused at waiting_for_pc_spell_target")
	check(hit_resolution, "spell resolved through CastingResolver")
	check(repo.get_expended_slots("mage_1").get(1, 0) == 1,
		"L1 slot expended after successful cast")


func test_pc_cast_disrupted_consumes_slot_no_effect() -> void:
	var dice := _FakeDice.new()
	var bundle := _make_resolver(dice)
	var resolver: CastingResolver = bundle.resolver
	var repo: _FakeRepo = bundle.repo

	var pc := _make_pc("mage_2", 3)
	var goblin := _make_goblin_combatant("g2", 30)
	var roster := CombatRoster.new()
	roster.add_combatant(pc)
	roster.add_combatant(goblin)

	var init_resolver := InitiativeResolver.new(dice)
	var attack_resolver := AttackResolver.new(dice)
	var controller := CombatController.new(
		roster, init_resolver, attack_resolver,
		null, null, null, null, null, null, null, null, resolver)

	controller.advance()  # → DECLARATION
	var choice := SpellChoice.new("fireball", 3, false, -1)
	controller.submit_declaration(pc.id, "cast_spell", {"spell_choice": choice})
	# Damage the caster — sets damaged_since_declaration.
	pc.damaged_since_declaration = true
	check(pc.is_cast_disrupted_this_round(),
		"PC is disrupted (declared + damaged)")

	var resolved_disrupted := false
	for _i in range(20):
		var result := controller.advance()
		var status: String = result.get("status", "")
		var action_result: Dictionary = result.get("result", {})
		if status == "action_resolved" and action_result.get("interrupted", false):
			resolved_disrupted = true
			break
		if status == "waiting_for_pc_action":
			controller.submit_pc_action(result.get("combatant_id", ""), "pass")
			continue
		if result.get("phase", "") == "end_round":
			break

	check(resolved_disrupted, "disrupted cast resolved with interrupted=true")
	check(repo.get_expended_slots("mage_2").get(3, 0) == 1,
		"disrupted cast still consumed L3 slot per ACKS")


func test_targeting_controller_emits_selection_changed() -> void:
	var spec := {"kind": "single_creature", "count": 1}
	var dice := _FakeDice.new()
	var ctl := TargetingController.new(spec, Vector3i(0, 0, 0), 1, dice)
	var goblin := {"hit_dice": {"base": 1, "modifier": 0}, "name": "Goblin"}
	ctl.add_candidate("g1", goblin, Vector3i(1, 0, 0))
	ctl.begin()

	var emit_count := [0]
	ctl.selection_changed.connect(func() -> void: emit_count[0] += 1)

	ctl.try_select("g1")
	check(emit_count[0] == 1, "selection_changed emits on select")

	ctl.deselect("g1")
	check(emit_count[0] == 2, "selection_changed emits on deselect")

	ctl.try_select("g1")
	ctl.reset_selection()
	check(emit_count[0] == 4, "selection_changed emits on select + reset")


# Helper: build a CharacterData proxy for the goblin so the resolver's
# damage application has a target with apply_damage. Combatants don't expose
# apply_damage directly to the resolver, so we use a CharacterData stand-in
# initialized to the same hp.
func _build_goblin_cd_for_resolver(id: String, hp: int) -> CharacterData:
	var cd := CharacterData.new()
	cd.id = id
	cd.name = id
	cd.hp_max = hp if hp > 0 else 1
	cd.hp_current = hp
	return cd
