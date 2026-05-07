extends "res://tests/test_suite_base.gd"

## Session P8 — AI Subsystem Polish.
##
## Validates four behavioral hooks layered onto MonsterAI / CombatRoster /
## SpellCombatHooks / SpawnRosterIntegrator:
##   - Charm AI gate (caster excluded from charmed target's selection)
##   - Sanctuary redirect (failed-save attacker skips warded target)
##   - elemental_uncontrolled subscriber (flips side to ENEMY via roster)
##   - Invisible Stalker reliability check (failed → hostile-to-caster)
##   - CombatRoster.move_to_side (lookup-and-flip without re-indexing)


class _FakeDice extends RefCounted:
	var fixed: Dictionary = {}
	func roll_expression(e: String, t: String = "") -> RollResult:
		var r := RollResult.new()
		r.modified_total = int(fixed.get(t, fixed.get(e, 0)))
		r.raw_total = r.modified_total
		return r
	func roll_digital(s: int, c: int = 1, m: int = 0, t: String = "") -> RollResult:
		var r := RollResult.new()
		r.modified_total = int(fixed.get(t, c * s)) + m
		r.raw_total = r.modified_total - m
		return r


func run_all_tests() -> void:
	test_charmed_creature_does_not_target_caster()
	test_charmed_creature_targets_other_enemies()
	test_charm_effect_removed_lifts_filter()
	test_multiple_charm_effects_exclude_all_casters()
	test_elemental_uncontrolled_flips_to_enemy_side()
	test_re_rostered_elemental_targets_former_caster_side()
	test_sanctuary_cancel_marks_attacker_blocked()
	test_sanctuary_blocked_attacker_skips_warded_target()
	test_sanctuary_blocked_targets_clears_at_round_end()
	test_invisible_stalker_loyal_on_reliability_success()
	test_invisible_stalker_hostile_on_reliability_failure()
	test_invisible_stalker_failure_emits_uncontrolled_signal()
	test_roster_move_to_side_flips_and_no_op_on_no_change()
	test_ai_fallback_when_all_candidates_filtered()
	test_charm_gate_no_op_without_active_effects_tracker()
	if not has_failures():
		print("SessionP8AIPolish: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_party_combatant(id: String) -> Combatant:
	var monster_data: Dictionary = {
		"name": id,
		"hit_dice": {"base": 1, "modifier": 0},
		"armor_class": 0,
		"attack_routines": [{"routine_name": "melee", "usage": "default",
			"attacks": [{"attack_type": "natural", "count": 1, "damage": "1d4", "to_hit_modifier": 0, "special_effect": null}]}],
		"save_as": {"class": "F", "level": 1},
		"morale": 0, "xp": 5,
		"movement": {"land": {"exploration": 60, "combat": 20}},
		"morale_modifiers": [], "special_abilities": [],
		"immunities": [], "resistances": [], "vulnerabilities": [],
		"combat_behavior": {"primary_target_rule": "nearest", "target_tie_breaker": "stable"},
	}
	var c := Combatant.from_monster(monster_data, 6, id, "test_party")
	c.side = Combatant.Side.PARTY
	return c


func _make_enemy_combatant(id: String) -> Combatant:
	var c := _make_party_combatant(id)
	c.side = Combatant.Side.ENEMY
	return c


func _make_charm_effect(caster_id: String, target_id: String, spell_key: String = "charm_person") -> Dictionary:
	return {
		"effect_id": "fx_%s_%s" % [spell_key, target_id],
		"spell_key": spell_key,
		"caster_id": caster_id,
		"caster_level": 5,
		"target_ids": [target_id],
		"effect_type": "condition",
		"applied_modifiers": [], "applied_flags": [], "applied_conditions": [],
		"duration_type": "days", "duration_remaining": 1,
		"requires_concentration": false, "is_active": 1,
		"metadata": {}, "created_at_round": 0,
	}


func _build_ai_with(roster: CombatRoster, tracker: ActiveEffectTracker) -> MonsterAI:
	return MonsterAI.new(roster, null, null, tracker)


# ---------------------------------------------------------------------------
# Charm AI gate
# ---------------------------------------------------------------------------

func test_charmed_creature_does_not_target_caster() -> void:
	# Setup: an enemy goblin "g_charm" charmed by PC "wizard". Without the
	# gate the goblin targets the wizard (only PARTY-side combatant).
	var roster := CombatRoster.new()
	var wizard := _make_party_combatant("wizard")
	var bard := _make_party_combatant("bard")
	var goblin := _make_enemy_combatant("g_charm")
	roster.add_combatant(wizard)
	roster.add_combatant(bard)
	roster.add_combatant(goblin)
	var tracker := ActiveEffectTracker.new()
	tracker.add_effect(_make_charm_effect("wizard", "g_charm"))
	var ai := _build_ai_with(roster, tracker)
	var target := ai.select_target(goblin, goblin.get_combat_behavior())
	check(target != null, "charmed goblin still picks SOMEONE (the bard)")
	if target != null:
		check(target.id != "wizard",
			"charmed goblin does NOT target charm caster, got '%s'" % target.id)
		check(target.id == "bard",
			"charmed goblin targets the only non-caster ally, got '%s'" % target.id)


func test_charmed_creature_targets_other_enemies() -> void:
	# When the charmed creature has multiple non-caster targets, the gate
	# only filters out the caster — primary scoring still picks among the
	# remaining candidates.
	var roster := CombatRoster.new()
	var wizard := _make_party_combatant("wizard_2")
	var bard := _make_party_combatant("bard_2")
	var fighter := _make_party_combatant("fighter_2")
	var goblin := _make_enemy_combatant("g_charm_2")
	roster.add_combatant(wizard)
	roster.add_combatant(bard)
	roster.add_combatant(fighter)
	roster.add_combatant(goblin)
	var tracker := ActiveEffectTracker.new()
	tracker.add_effect(_make_charm_effect("wizard_2", "g_charm_2"))
	var ai := _build_ai_with(roster, tracker)
	var target := ai.select_target(goblin, goblin.get_combat_behavior())
	check(target != null and target.id != "wizard_2",
		"charmed goblin avoids caster, picks among other PCs")


func test_charm_effect_removed_lifts_filter() -> void:
	# After the charm effect is removed (e.g., duration expired / dispelled),
	# the gate is empty and the goblin can target the former caster again.
	var roster := CombatRoster.new()
	var wizard := _make_party_combatant("wizard_3")
	var goblin := _make_enemy_combatant("g_charm_3")
	roster.add_combatant(wizard)
	roster.add_combatant(goblin)
	var tracker := ActiveEffectTracker.new()
	var charm := _make_charm_effect("wizard_3", "g_charm_3")
	tracker.add_effect(charm)
	tracker.remove_effect(charm.effect_id)
	var ai := _build_ai_with(roster, tracker)
	var target := ai.select_target(goblin, goblin.get_combat_behavior())
	check(target != null and target.id == "wizard_3",
		"charm removed → wizard targetable again, got '%s'" %
		(target.id if target else "<null>"))


func test_multiple_charm_effects_exclude_all_casters() -> void:
	# Two casters charmed the same goblin (rare but possible). Both casters
	# excluded; the goblin picks a third PC.
	var roster := CombatRoster.new()
	var w1 := _make_party_combatant("wiz_a")
	var w2 := _make_party_combatant("wiz_b")
	var bard := _make_party_combatant("bard_4")
	var goblin := _make_enemy_combatant("g_double_charm")
	roster.add_combatant(w1)
	roster.add_combatant(w2)
	roster.add_combatant(bard)
	roster.add_combatant(goblin)
	var tracker := ActiveEffectTracker.new()
	tracker.add_effect(_make_charm_effect("wiz_a", "g_double_charm"))
	tracker.add_effect(_make_charm_effect("wiz_b", "g_double_charm", "charm_monster"))
	var ai := _build_ai_with(roster, tracker)
	var target := ai.select_target(goblin, goblin.get_combat_behavior())
	check(target != null and target.id == "bard_4",
		"both charm casters excluded; bard picked, got '%s'" %
		(target.id if target else "<null>"))


func test_charm_gate_no_op_without_active_effects_tracker() -> void:
	# AI built without a tracker (pre-P8 wiring) does not apply the charm
	# gate — ensures backward compatibility.
	var roster := CombatRoster.new()
	var wizard := _make_party_combatant("wiz_5")
	var goblin := _make_enemy_combatant("g_no_tracker")
	roster.add_combatant(wizard)
	roster.add_combatant(goblin)
	var ai := MonsterAI.new(roster)  # no tracker arg
	var target := ai.select_target(goblin, goblin.get_combat_behavior())
	check(target != null and target.id == "wiz_5",
		"no tracker = no gate; goblin targets wizard normally")


# ---------------------------------------------------------------------------
# elemental_uncontrolled subscriber + roster.move_to_side
# ---------------------------------------------------------------------------

func test_elemental_uncontrolled_flips_to_enemy_side() -> void:
	var roster := CombatRoster.new()
	var elem := _make_party_combatant("elem_fire_x")
	roster.add_combatant(elem)
	var ai := MonsterAI.new(roster)
	ai.connect_signals()
	# Direct emit — subscriber should flip side.
	EventBus.elemental_uncontrolled.emit("elem_fire_x", "fire", "caster_x")
	check(elem.side == Combatant.Side.ENEMY,
		"elemental side flipped to ENEMY, got %d" % elem.side)
	ai.disconnect_signals()


func test_re_rostered_elemental_targets_former_caster_side() -> void:
	var roster := CombatRoster.new()
	var caster := _make_party_combatant("caster_re")
	var ally := _make_party_combatant("ally_re")
	var elem := _make_party_combatant("elem_re")
	roster.add_combatant(caster)
	roster.add_combatant(ally)
	roster.add_combatant(elem)
	var ai := MonsterAI.new(roster)
	ai.connect_signals()
	EventBus.elemental_uncontrolled.emit("elem_re", "earth", "caster_re")
	# Elem now ENEMY. select_target on the elemental picks PARTY-side targets.
	var target := ai.select_target(elem, elem.get_combat_behavior())
	check(target != null
			and (target.id == "caster_re" or target.id == "ally_re"),
		"flipped elemental targets a PARTY combatant, got '%s'" %
		(target.id if target else "<null>"))
	ai.disconnect_signals()


func test_roster_move_to_side_flips_and_no_op_on_no_change() -> void:
	var roster := CombatRoster.new()
	var c := _make_party_combatant("rms_a")
	roster.add_combatant(c)
	check(roster.move_to_side("rms_a", Combatant.Side.ENEMY),
		"flip PARTY→ENEMY succeeds")
	check(c.side == Combatant.Side.ENEMY, "side reads as ENEMY now")
	check(not roster.move_to_side("rms_a", Combatant.Side.ENEMY),
		"flip to same side returns false")
	check(not roster.move_to_side("missing_id", Combatant.Side.ENEMY),
		"missing id returns false")


# ---------------------------------------------------------------------------
# Sanctuary AI redirect
# ---------------------------------------------------------------------------

func test_sanctuary_cancel_marks_attacker_blocked() -> void:
	# Build attacker + sanctuary'd target. Force the dice path so the save
	# fails (attacker low save_target makes any roll succeed; we want fail).
	var dice := _FakeDice.new()
	dice.fixed["save_spells_sanctuary"] = 1  # auto-fail save → cancel attack
	var hooks := SpellCombatHooks.new(null, dice)
	var attacker := _make_enemy_combatant("attacker_p8")
	var target := _make_party_combatant("warded_p8")
	# Bypass save_target lookup: combatant.get_effective_save returns 17 by
	# default for monsters. With fixed roll=1, save fails → attack cancels.
	target.get_flags().set_flag("cannot_be_targeted_by_attacks",
		"spell:sanctuary:caster_p8", {"caster_level": 5})
	var result: Dictionary = hooks.on_pre_attack(attacker, target, "melee")
	check(bool(result.get("cancel", false)),
		"sanctuary cancels the attack on failed save")
	check("warded_p8" in attacker.sanctuary_blocked_targets,
		"target id recorded on attacker.sanctuary_blocked_targets, got %s" %
		str(attacker.sanctuary_blocked_targets))


func test_sanctuary_blocked_attacker_skips_warded_target() -> void:
	# Once the attacker carries `warded` in sanctuary_blocked_targets, the
	# AI's select_target filters it out.
	var roster := CombatRoster.new()
	var warded := _make_party_combatant("warded_skip")
	var fallback := _make_party_combatant("other_pc")
	var goblin := _make_enemy_combatant("g_redir")
	goblin.sanctuary_blocked_targets = ["warded_skip"]
	roster.add_combatant(warded)
	roster.add_combatant(fallback)
	roster.add_combatant(goblin)
	var ai := MonsterAI.new(roster)
	var target := ai.select_target(goblin, goblin.get_combat_behavior())
	check(target != null and target.id == "other_pc",
		"sanctuary-blocked goblin retargets to non-blocked PC, got '%s'" %
		(target.id if target else "<null>"))


func test_sanctuary_blocked_targets_clears_at_round_end() -> void:
	var hooks := SpellCombatHooks.new(null, null)
	var roster := CombatRoster.new()
	var attacker := _make_enemy_combatant("att_clr")
	attacker.sanctuary_blocked_targets = ["warded_clr"]
	roster.add_combatant(attacker)
	# on_round_end iterates roster.get_alive() and clears the per-round list.
	hooks.on_round_end(1, roster)
	check(attacker.sanctuary_blocked_targets.is_empty(),
		"sanctuary_blocked_targets cleared at round end, got %s" %
		str(attacker.sanctuary_blocked_targets))


# ---------------------------------------------------------------------------
# AI fallback when every candidate filtered
# ---------------------------------------------------------------------------

func test_ai_fallback_when_all_candidates_filtered() -> void:
	# Goblin charmed by the only PC. With caster filtered out, no candidates
	# remain — AI must return null (caller falls back to "pass").
	var roster := CombatRoster.new()
	var solo := _make_party_combatant("solo_caster")
	var goblin := _make_enemy_combatant("g_filtered")
	roster.add_combatant(solo)
	roster.add_combatant(goblin)
	var tracker := ActiveEffectTracker.new()
	tracker.add_effect(_make_charm_effect("solo_caster", "g_filtered"))
	var ai := _build_ai_with(roster, tracker)
	var target := ai.select_target(goblin, goblin.get_combat_behavior())
	check(target == null,
		"AI returns null when all candidates filtered (caller passes)")


# ---------------------------------------------------------------------------
# Invisible Stalker reliability
# ---------------------------------------------------------------------------

func test_invisible_stalker_loyal_on_reliability_success() -> void:
	var roster := CombatRoster.new()
	var voxel_map: VoxelMapData = VoxelMapData.generate_open_field(20, 20)
	var mr := MovementResolver.new(roster)
	mr.set_voxel_map(voxel_map)
	var caster := _make_party_combatant("caster_loyal")
	roster.add_combatant(caster)
	var tracker := ActiveEffectTracker.new()
	var registry := MonsterRegistry.new()
	var integrator := SpawnRosterIntegrator.new(roster, mr, tracker, registry, null)
	var profile: Dictionary = {
		"stalker_id": "stalker_loyal",
		"caster_id": "caster_loyal",
		"caster_charisma_modifier": 2,
		"reliability_override": true,  # force success path
	}
	var effect: Dictionary = {
		"effect_id": "fx_stalker_loy", "spell_key": "invisible_stalker",
		"caster_id": "caster_loyal", "target_ids": [],
		"applied_modifiers": [], "applied_flags": [], "applied_conditions": [],
		"duration_type": "permanent", "duration_remaining": -1,
		"requires_concentration": 0, "is_active": 1,
		"metadata": {"invisible_stalker_spawn_profile": profile},
		"created_at_round": 0,
	}
	tracker.add_effect(effect)
	var spawned: Array[String] = integrator.process_effect(effect, "invisible_stalker")
	check(spawned.size() == 1, "stalker spawned")
	if spawned.size() == 1:
		var c: Combatant = roster.get_by_id(spawned[0])
		check(c.side == Combatant.Side.PARTY,
			"loyal stalker on PARTY side, got %d" % c.side)
		var flags := c.get_flags()
		check(flags != null and not flags.has_flag("is_hostile_to_caster"),
			"loyal stalker has no is_hostile_to_caster flag")


func test_invisible_stalker_hostile_on_reliability_failure() -> void:
	var roster := CombatRoster.new()
	var voxel_map: VoxelMapData = VoxelMapData.generate_open_field(20, 20)
	var mr := MovementResolver.new(roster)
	mr.set_voxel_map(voxel_map)
	var caster := _make_party_combatant("caster_unreliable")
	roster.add_combatant(caster)
	var tracker := ActiveEffectTracker.new()
	var registry := MonsterRegistry.new()
	var integrator := SpawnRosterIntegrator.new(roster, mr, tracker, registry, null)
	var profile: Dictionary = {
		"stalker_id": "stalker_hostile",
		"caster_id": "caster_unreliable",
		"caster_charisma_modifier": -2,
		"reliability_override": false,  # force failure path
	}
	var effect: Dictionary = {
		"effect_id": "fx_stalker_un", "spell_key": "invisible_stalker",
		"caster_id": "caster_unreliable", "target_ids": [],
		"applied_modifiers": [], "applied_flags": [], "applied_conditions": [],
		"duration_type": "permanent", "duration_remaining": -1,
		"requires_concentration": 0, "is_active": 1,
		"metadata": {"invisible_stalker_spawn_profile": profile},
		"created_at_round": 0,
	}
	tracker.add_effect(effect)
	var spawned: Array[String] = integrator.process_effect(effect, "invisible_stalker")
	check(spawned.size() == 1, "stalker spawned even on reliability failure")
	if spawned.size() == 1:
		var c: Combatant = roster.get_by_id(spawned[0])
		check(c.side == Combatant.Side.ENEMY,
			"unreliable stalker flipped to ENEMY, got %d" % c.side)
		var flags := c.get_flags()
		check(flags != null and flags.has_flag("is_hostile_to_caster"),
			"unreliable stalker carries is_hostile_to_caster flag")


func test_invisible_stalker_failure_emits_uncontrolled_signal() -> void:
	# The reliability-failure path emits elemental_uncontrolled (re-using
	# that signal so existing MonsterAI subscribers handle it uniformly).
	var roster := CombatRoster.new()
	var voxel_map: VoxelMapData = VoxelMapData.generate_open_field(20, 20)
	var mr := MovementResolver.new(roster)
	mr.set_voxel_map(voxel_map)
	roster.add_combatant(_make_party_combatant("caster_sig"))
	var tracker := ActiveEffectTracker.new()
	var registry := MonsterRegistry.new()
	var integrator := SpawnRosterIntegrator.new(roster, mr, tracker, registry, null)
	var profile: Dictionary = {
		"stalker_id": "stalker_sig",
		"caster_id": "caster_sig",
		"reliability_override": false,
	}
	var effect: Dictionary = {
		"effect_id": "fx_stalker_sig", "spell_key": "invisible_stalker",
		"caster_id": "caster_sig", "target_ids": [],
		"applied_modifiers": [], "applied_flags": [], "applied_conditions": [],
		"duration_type": "permanent", "duration_remaining": -1,
		"requires_concentration": 0, "is_active": 1,
		"metadata": {"invisible_stalker_spawn_profile": profile},
		"created_at_round": 0,
	}
	tracker.add_effect(effect)
	var captured: Array = []
	var on_uncontrolled := func(eid: String, etype: String, fcid: String) -> void:
		captured.append({"id": eid, "type": etype, "former_caster": fcid})
	EventBus.elemental_uncontrolled.connect(on_uncontrolled)
	integrator.process_effect(effect, "invisible_stalker")
	if EventBus.elemental_uncontrolled.is_connected(on_uncontrolled):
		EventBus.elemental_uncontrolled.disconnect(on_uncontrolled)
	check(captured.size() == 1, "uncontrolled signal fired once")
	if captured.size() == 1:
		check(captured[0].id == "stalker_sig", "stalker id propagated")
		check(captured[0].type == "stalker", "etype is 'stalker'")
		check(captured[0].former_caster == "caster_sig",
			"former_caster_id propagated")
