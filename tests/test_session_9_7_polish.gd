extends "res://tests/test_suite_base.gd"

## Session 9.7 — Polish-pass bundle (post-Sessions 12-14).
##
## Closes 7 build-now polish items:
##   1. Anti-Magic Shell pre-resolve gate (CastingResolver)
##   2. Globe of Invulnerability pre-resolve gate (CastingResolver)
##   3. Cloudkill on_round_end consumer (SpellCombatHooks._tick_cloudkill)
##   4. Striking ranged_attack_resolver consumption (RangedAttackResolver)
##   5. Death Spell / Disintegrate combat removal (SpellCombatHooks._sweep_destroyed_entities)
##   6. Telekinesis caster constraints (CombatController.get_available_actions + new is_telekinesis_caster flag)
##   7. Conjure Elemental hostility-flip signal (EventBus.elemental_uncontrolled)


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


class _FakeRepo extends RefCounted:
	var expended: Dictionary = {}
	func increment_expended_slot(c: String, l: int) -> bool:
		if not expended.has(c): expended[c] = {}
		expended[c][l] = int(expended[c].get(l, 0)) + 1
		return true
	func reset_expended_slots(c: String) -> bool: expended[c] = {}; return true
	func get_expended_slots(c: String) -> Dictionary:
		return expended.get(c, {})


# Lightweight combatant fixture for the SpellCombatHooks round-tick tests.
class _MockCombatant extends RefCounted:
	var id: String = ""
	var hp_max: int = 6
	var hp_current: int = 6
	var hit_dice: int = 1
	var conditions: Array[String] = []
	func add_condition(k: String) -> void:
		if k not in conditions: conditions.append(k)
	func has_condition(k: String) -> bool: return k in conditions
	func is_alive() -> bool: return hp_current > 0
	func get_hit_dice() -> int: return hit_dice
	func get_effective_save(_key: String) -> int: return 14
	func apply_damage(amt: int, _t: String = "", _src: String = "") -> Dictionary:
		hp_current = max(0, hp_current - amt)
		return {"hp_damage": amt, "new_hp": hp_current, "is_downed": hp_current <= 0}


class _MockRoster extends RefCounted:
	var combatants: Array = []
	func get_all_alive() -> Array:
		return combatants.filter(func(c): return c.is_alive())
	func get_by_id(id: String):
		for c in combatants:
			if c.id == id: return c
		return null


func run_all_tests() -> void:
	test_anti_magic_shell_blocks_external_spell()
	test_anti_magic_shell_self_cast_passes_through()
	test_globe_blocks_low_level_spell()
	test_globe_does_not_block_higher_level_spell()
	test_cloudkill_low_hd_dies_on_failed_save()
	test_cloudkill_high_hd_takes_one_point()
	test_cloudkill_skips_caster()
	test_destruction_sweep_drops_dispel_destroyed_to_zero()
	test_destruction_sweep_drops_disintegrated_to_zero()
	test_telekinesis_caster_flag_blocks_attacks_and_spells()
	test_elemental_uncontrolled_signal_fires_on_concentration_break()
	test_apply_flag_target_caster_only_field()
	if not has_failures():
		print("Session9_7Polish: all tests passed.")


# ---------------------------------------------------------------------------
# Anti-Magic Shell + Globe pre-resolve gates
# ---------------------------------------------------------------------------

func test_anti_magic_shell_blocks_external_spell() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage("c_ams")
	var target := CharacterData.new()
	target.id = "t_ams"; target.hp_max = 8; target.hp_current = 8
	# Pre-apply the shell to target.
	target.flags.set_flag("has_anti_magic_shell", "spell:setup", {"radius_feet": 10})
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	# Cast Magic Missile (L1 arcane) at the shielded target.
	var choice := SpellChoice.new("magic_missile", 1, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "single_creature"; td.target_ids = [target.id]
	# Force d20 attack roll high so any non-blocked path would hit.
	harness.dice.fixed["spell_damage"] = 4
	var result = harness.resolver.resolve(ctx, choice, td, caster, {target.id: target})
	check(not result.success, "anti-magic shell blocks Magic Missile from outside")
	check(int(target.hp_current) == 8, "shielded target took NO damage")


func test_anti_magic_shell_self_cast_passes_through() -> void:
	# Per RAW: "Self-range and touch-range spells used by the caster on himself
	# are not blocked." Caster has shell + casts Shield on self → still works.
	var harness := _make_harness()
	var caster := _make_caster_mage("c_ams2")
	caster.flags.set_flag("has_anti_magic_shell", "spell:setup", {"radius_feet": 10})
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	# Shield is L1 arcane self-target.
	var choice := SpellChoice.new("shield", 1, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "self"; td.target_ids = [caster.id]
	var result = harness.resolver.resolve(ctx, choice, td, caster, {caster.id: caster})
	check(result.success, "self-cast on protected caster passes through shell per RAW")


func test_globe_blocks_low_level_spell() -> void:
	# Globe of Invulnerability blocks ≤4-level spells.
	var harness := _make_harness()
	var caster := _make_caster_mage("c_globe")
	var target := CharacterData.new()
	target.id = "t_globe"; target.hp_max = 8; target.hp_current = 8
	target.flags.set_flag("has_globe_of_invulnerability", "spell:setup", {
		"blocks_spell_levels_up_to": 4})
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	# Magic Missile is L1 arcane; ≤4 → blocked.
	var choice := SpellChoice.new("magic_missile", 1, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "single_creature"; td.target_ids = [target.id]
	var result = harness.resolver.resolve(ctx, choice, td, caster, {target.id: target})
	check(not result.success, "globe blocks L1 Magic Missile (≤4 cap)")


func test_globe_does_not_block_higher_level_spell() -> void:
	# Globe of Invulnerability with blocks_spell_levels_up_to=4 does NOT
	# block L5+ spells. Cast a L5 Cone of Cold at globed target → resolves.
	var harness := _make_harness()
	var caster := _make_caster_mage("c_globe2")
	caster.level = 9
	var target := CharacterData.new()
	target.id = "t_globe2"; target.hp_max = 30; target.hp_current = 30
	target.flags.set_flag("has_globe_of_invulnerability", "spell:setup", {
		"blocks_spell_levels_up_to": 4})
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	# Cone of Cold (L5 arcane) > 4 → not blocked by globe.
	var choice := SpellChoice.new("cone_of_cold", 5, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "area_from_caster"; td.target_ids = [target.id]
	harness.dice.fixed["spell_damage"] = 4
	harness.dice.fixed["spell_save_blast"] = 1
	var result = harness.resolver.resolve(ctx, choice, td, caster, {target.id: target})
	check(result.success,
		"globe (≤4 cap) does NOT block L5 Cone of Cold")


# ---------------------------------------------------------------------------
# Cloudkill round-tick
# ---------------------------------------------------------------------------

func test_cloudkill_low_hd_dies_on_failed_save() -> void:
	var dice := _FakeDice.new()
	var tracker := ActiveEffectTracker.new()
	var hooks := SpellCombatHooks.new(tracker, dice)
	var goblin := _MockCombatant.new()
	goblin.id = "g_ck"; goblin.hp_max = 4; goblin.hp_current = 4; goblin.hit_dice = 1
	var roster := _MockRoster.new()
	roster.combatants = [goblin]
	# Set up the cloudkill active_effect.
	tracker.add_effect({
		"effect_id": "fx_cloudkill_1",
		"spell_key": "cloudkill",
		"caster_id": "caster_ck",
		"target_ids": [],
		"effect_type": "area",
		"applied_modifiers": [], "applied_conditions": [], "applied_flags": [],
		"duration_type": "turns", "duration_remaining": 6,
		"requires_concentration": 0, "is_active": 1,
		"metadata": {
			"cloud_profile": {
				"caster_id": "caster_ck",
				"hd_threshold_for_death_save": 5,
				"area_cells": [],  # empty = apply to all
			}
		},
		"created_at_round": 0,
	})
	# Force save fail (target=14, modified=1 → fail).
	dice.fixed["spell_save_cloudkill"] = 1
	hooks.on_round_end(2, roster)
	check(int(goblin.hp_current) == 0,
		"low-HD failed save → dead, hp went 4 → 0, got %d" % goblin.hp_current)


func test_cloudkill_high_hd_takes_one_point() -> void:
	var dice := _FakeDice.new()
	var tracker := ActiveEffectTracker.new()
	var hooks := SpellCombatHooks.new(tracker, dice)
	var ogre := _MockCombatant.new()
	ogre.id = "o_ck"; ogre.hp_max = 30; ogre.hp_current = 30; ogre.hit_dice = 5
	var roster := _MockRoster.new()
	roster.combatants = [ogre]
	tracker.add_effect({
		"effect_id": "fx_cloudkill_2",
		"spell_key": "cloudkill",
		"caster_id": "caster_ck2",
		"target_ids": [],
		"effect_type": "area",
		"applied_modifiers": [], "applied_conditions": [], "applied_flags": [],
		"duration_type": "turns", "duration_remaining": 6,
		"requires_concentration": 0, "is_active": 1,
		"metadata": {
			"cloud_profile": {
				"caster_id": "caster_ck2",
				"hd_threshold_for_death_save": 5,
				"area_cells": [],
			}
		},
		"created_at_round": 0,
	})
	hooks.on_round_end(2, roster)
	check(int(ogre.hp_current) == 29,
		"5-HD ogre takes 1 hp/round (≥ threshold), hp went 30 → 29, got %d" % ogre.hp_current)


func test_cloudkill_skips_caster() -> void:
	var dice := _FakeDice.new()
	var tracker := ActiveEffectTracker.new()
	var hooks := SpellCombatHooks.new(tracker, dice)
	var caster_combatant := _MockCombatant.new()
	caster_combatant.id = "caster_ck3"; caster_combatant.hp_max = 12; caster_combatant.hp_current = 12
	var roster := _MockRoster.new()
	roster.combatants = [caster_combatant]
	tracker.add_effect({
		"effect_id": "fx_cloudkill_3",
		"spell_key": "cloudkill",
		"caster_id": "caster_ck3",  # same as the only combatant
		"target_ids": [],
		"effect_type": "area",
		"applied_modifiers": [], "applied_conditions": [], "applied_flags": [],
		"duration_type": "turns", "duration_remaining": 6,
		"requires_concentration": 0, "is_active": 1,
		"metadata": {
			"cloud_profile": {
				"caster_id": "caster_ck3",
				"hd_threshold_for_death_save": 5,
				"area_cells": [],
			}
		},
		"created_at_round": 0,
	})
	hooks.on_round_end(2, roster)
	check(int(caster_combatant.hp_current) == 12,
		"caster takes no damage (cloud drifts AWAY from caster per RAW)")


# ---------------------------------------------------------------------------
# Destruction sweep (Death Spell + Disintegrate)
# ---------------------------------------------------------------------------

func test_destruction_sweep_drops_dispel_destroyed_to_zero() -> void:
	var hooks := SpellCombatHooks.new(ActiveEffectTracker.new(), _FakeDice.new())
	var skel := _MockCombatant.new()
	skel.id = "skel_d"; skel.hp_max = 8; skel.hp_current = 8
	skel.add_condition("dispel_destroyed")
	var roster := _MockRoster.new()
	roster.combatants = [skel]
	hooks.on_round_end(1, roster)
	check(int(skel.hp_current) == 0,
		"dispel_destroyed → hp=0, got %d" % skel.hp_current)


func test_destruction_sweep_drops_disintegrated_to_zero() -> void:
	var hooks := SpellCombatHooks.new(ActiveEffectTracker.new(), _FakeDice.new())
	var enemy := _MockCombatant.new()
	enemy.id = "e_dis"; enemy.hp_max = 30; enemy.hp_current = 30
	enemy.add_condition("disintegrated")
	var roster := _MockRoster.new()
	roster.combatants = [enemy]
	hooks.on_round_end(1, roster)
	check(int(enemy.hp_current) == 0,
		"disintegrated → hp=0, got %d" % enemy.hp_current)


# ---------------------------------------------------------------------------
# Telekinesis caster flag
# ---------------------------------------------------------------------------

func test_telekinesis_caster_flag_blocks_attacks_and_spells() -> void:
	# Verify the catalog wiring sets is_telekinesis_caster on the caster via
	# the new target_caster_only field on apply_flag.
	var harness := _make_harness()
	var caster := _make_caster_mage("c_tk")
	caster.level = 5
	var obj := CharacterData.new()
	obj.id = "obj_tk"; obj.hp_max = 1; obj.hp_current = 1
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var choice := SpellChoice.new("telekinesis", 5, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "single_object_or_creature"; td.target_ids = [obj.id]
	harness.resolver.resolve(ctx, choice, td, caster, {obj.id: obj})
	check(caster.flags.has_flag("is_telekinesis_caster"),
		"caster gains is_telekinesis_caster flag")
	var meta: Dictionary = caster.flags.get_flag_source_entries("is_telekinesis_caster")[0].get("metadata", {})
	check(bool(meta.get("blocked_from_attacks", false)),
		"blocked_from_attacks=true per RAW")
	check(bool(meta.get("blocked_from_spells", false)),
		"blocked_from_spells=true per RAW")


# ---------------------------------------------------------------------------
# Conjure Elemental hostility-flip
# ---------------------------------------------------------------------------

func test_elemental_uncontrolled_signal_fires_on_concentration_break() -> void:
	# Pre-register a conjure_elemental concentration effect, then trigger
	# concentration break via on_damage_dealt, and verify the signal fires
	# with the right elemental_id + type.
	var tracker := ActiveEffectTracker.new()
	var hooks := SpellCombatHooks.new(tracker, _FakeDice.new())
	var caster := _MockCombatant.new()
	caster.id = "caster_ce"; caster.hp_max = 18; caster.hp_current = 18
	tracker.add_effect({
		"effect_id": "fx_ce_1",
		"spell_key": "conjure_elemental",
		"caster_id": caster.id,
		"target_ids": [],
		"effect_type": "summon",
		"applied_modifiers": [], "applied_conditions": [], "applied_flags": [],
		"duration_type": "concentration", "duration_remaining": -1,
		"requires_concentration": 1, "is_active": 1,
		"metadata": {
			"conjure_elemental_spawn_profile": {
				"elemental_id": "elemental_fire:caster_ce",
				"elemental_type": "fire",
				"caster_id": caster.id,
			}
		},
		"created_at_round": 0,
		"concentration_caster_id": caster.id,
	})
	# Subscribe to the signal.
	var captured: Array = []
	var sub = func(eid: String, etype: String, fcaster: String):
		captured.append({"elemental_id": eid, "elemental_type": etype, "caster_id": fcaster})
	EventBus.elemental_uncontrolled.connect(sub)
	# Damage the caster → triggers on_damage_dealt → break_concentration → signal.
	hooks.on_damage_dealt(caster, 5, "attacker_id")
	EventBus.elemental_uncontrolled.disconnect(sub)
	check(captured.size() == 1,
		"elemental_uncontrolled fired once on concentration break, got %d" % captured.size())
	if captured.size() > 0:
		check(String(captured[0]["elemental_type"]) == "fire",
			"signal carries elemental_type='fire'")


# ---------------------------------------------------------------------------
# apply_flag target_caster_only
# ---------------------------------------------------------------------------

func test_apply_flag_target_caster_only_field() -> void:
	# Direct unit test of the new target_caster_only field on _apply_flag.
	var harness := _make_harness()
	var caster := _make_caster_mage("c_tco")
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var choice := SpellChoice.new("test", 1, false, -1)
	var td := TargetDescriptor.new()
	td.target_ids = ["unrelated_target"]
	var step := {
		"kind": "apply_flag",
		"flag_key": "test_caster_flag",
		"target_caster_only": true,
		"metadata": {"foo": "bar"},
	}
	harness.resolver._apply_flag(step, choice, td, {}, caster, ctx)
	check(caster.flags.has_flag("test_caster_flag"),
		"target_caster_only=true applies flag to caster, not to target_descriptor.target_ids")


# ---------------------------------------------------------------------------
# Test helpers
# ---------------------------------------------------------------------------

class _Harness extends RefCounted:
	var dice = null
	var repo = null
	var resolver = null


func _make_harness() -> _Harness:
	var h := _Harness.new()
	h.dice = _FakeDice.new()
	h.repo = _FakeRepo.new()
	var sr := SpellRegistry.new()
	var er := SpellEffectRegistry.new(sr)
	var tracker := ActiveEffectTracker.new()
	var cc := ConditionCatalog.new()
	var cr := CustomResolverRegistry.new()
	h.resolver = CastingResolver.new(sr, er, tracker, cc, cr, null, h.repo, h.dice)
	return h


func _make_caster_mage(id: String) -> CharacterData:
	var cd := CharacterData.new()
	cd.id = id
	cd.name = "Test Mage"
	cd.character_class = "mage"
	cd.combat_progression = "mage"
	cd.level = 5
	cd.intelligence = 14
	cd.hp_max = 12; cd.hp_current = 12
	return cd
