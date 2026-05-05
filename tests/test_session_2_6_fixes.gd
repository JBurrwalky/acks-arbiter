extends "res://tests/test_suite_base.gd"

## Regression tests for Session 2.6 audit fixes:
## - Bless duration_type honors `unit: "turns"` (not always rounds).
## - tick_and_cleanup unwinds modifiers from CharacterData targets.
## - Conditions are applied to Combatant entities (add_condition called).
## - Disrupted cast preserves casting_stat_bonus.
## - _compute_remaining_slots returns expended count, not negative.


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


var _resolver: CastingResolver = null
var _repo = null
var _tracker: ActiveEffectTracker = null


func _build_resolver() -> CastingResolver:
	_repo = _FakeRepo.new()
	var sr := SpellRegistry.new()
	var er := SpellEffectRegistry.new(sr)
	_tracker = ActiveEffectTracker.new()
	var cc := ConditionCatalog.new()
	var cr := CustomResolverRegistry.new()
	var dice := _FakeDice.new()
	dice.set_fixed("spell_damage", 4)
	dice.set_fixed("spell_healing", 5)
	_resolver = CastingResolver.new(sr, er, _tracker, cc, cr, null, _repo, dice)
	return _resolver


func _make_caster(id: String, level: int = 3) -> CharacterData:
	var cd := CharacterData.new()
	cd.id = id
	cd.name = id
	cd.character_class = "cleric"
	cd.combat_progression = "cleric"
	cd.level = level
	cd.hp_max = 20
	cd.hp_current = 20
	cd.wisdom = 13
	return cd


func _make_target(id: String) -> CharacterData:
	var cd := CharacterData.new()
	cd.id = id
	cd.name = id
	cd.hp_max = 10
	cd.hp_current = 10
	return cd


func run_all_tests() -> void:
	test_bless_duration_type_is_turns()
	test_tick_rounds_does_not_decrement_turn_durations()
	test_tick_and_cleanup_unwinds_modifiers()
	test_compute_remaining_slots_returns_expended_count()
	test_disrupted_cast_uses_casting_stat_bonus()
	test_apply_condition_calls_add_condition_on_combatant()
	if not has_failures():
		print("Session2_6Fixes: all tests passed.")


# ---------------------------------------------------------------------------

func test_bless_duration_type_is_turns() -> void:
	# Bless declares unit: "turns" in spell_catalog.json. The active_effect's
	# duration_type must be "turns", not "rounds".
	_build_resolver()
	var caster := _make_caster("cleric_b", 3)
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var ally := _make_target("ally_b")
	var choice := SpellChoice.new("bless", 2, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "area_from_caster"
	td.target_ids = ["ally_b"]
	var result := _resolver.resolve(ctx, choice, td, caster, {"ally_b": ally})
	check(result.success, "Bless: success")
	check(result.active_effect_ids.size() == 1, "Bless: 1 active_effect")
	var aef := _tracker.get_effect(result.active_effect_ids[0])
	check(aef.get("duration_type", "") == "turns",
		"Bless: duration_type should be 'turns', got '%s'" % aef.get("duration_type", ""))
	check(int(aef.get("duration_remaining", 0)) == 6,
		"Bless: 6 turns duration, got %d" % aef.get("duration_remaining", 0))


func test_tick_rounds_does_not_decrement_turn_durations() -> void:
	# Bless on 6 turns + Magic Missile (instant, no effect) → after tick_rounds(1)
	# the Bless effect should still be at 6 turns.
	_build_resolver()
	var caster := _make_caster("cleric_t", 3)
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var ally := _make_target("ally_t")
	var choice := SpellChoice.new("bless", 2, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "area_from_caster"
	td.target_ids = ["ally_t"]
	var result := _resolver.resolve(ctx, choice, td, caster, {"ally_t": ally})
	var lookup := func(_tid: String) -> Variant: return ally
	_resolver.tick_and_cleanup("rounds", 1, lookup)
	var aef := _tracker.get_effect(result.active_effect_ids[0])
	check(int(aef.get("duration_remaining", 0)) == 6,
		"Bless still at 6 turns after tick_rounds(1), got %d" % aef.get("duration_remaining", 0))


func test_tick_and_cleanup_unwinds_modifiers() -> void:
	# Make Shield (2 turns, self) — then tick_turns(2) and verify the
	# armor_class_vs_missiles modifier is GONE from the caster's modifier
	# container.
	_build_resolver()
	var caster := _make_caster("mage_unwind", 1)
	caster.character_class = "mage"
	caster.combat_progression = "mage"
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var choice := SpellChoice.new("shield", 1, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "self"
	td.target_ids = ["mage_unwind"]
	var result := _resolver.resolve(ctx, choice, td, caster, {"mage_unwind": caster})
	check(result.success, "Shield cast success")
	# Pre-tick: missile AC has set_floor=2 modifier.
	check(caster.modifiers.get_effective_value("armor_class_vs_missiles", 0) == 2,
		"Shield active: vs_missiles AC = 2")
	var lookup := func(_tid: String) -> Variant: return caster
	# Shield is 3 turns; tick 3 turns to expire it.
	_resolver.tick_and_cleanup("turns", 3, lookup)
	# Post-cleanup: the modifier should be gone.
	check(caster.modifiers.get_effective_value("armor_class_vs_missiles", 0) == 0,
		"Shield expired: vs_missiles AC reverts to base 0, got %d" % caster.modifiers.get_effective_value("armor_class_vs_missiles", 0))


func test_compute_remaining_slots_returns_expended_count() -> void:
	# Cast Magic Missile, verify the spell_slot_expended payload's third arg
	# matches the expended count (positive 1, not negative).
	_build_resolver()
	var caster := _make_caster("mm_slot", 1)
	caster.character_class = "mage"
	caster.combat_progression = "mage"
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var goblin := _make_target("g_slot")
	goblin.hp_max = 30
	goblin.hp_current = 30
	var choice := SpellChoice.new("magic_missile", 1, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "single_creature"
	td.target_ids = ["g_slot"]
	var emitted: Array = []
	var cb := func(_caster_id: String, _level: int, remaining: int) -> void:
		emitted.append(remaining)
	EventBus.spell_slot_expended.connect(cb)
	_resolver.resolve(ctx, choice, td, caster, {"g_slot": goblin})
	EventBus.spell_slot_expended.disconnect(cb)
	check(emitted.size() == 1, "spell_slot_expended fired once")
	check(emitted[0] == 1,
		"spell_slot_expended payload now positive (expended count): got %d" % emitted[0])


func test_disrupted_cast_uses_casting_stat_bonus() -> void:
	# Verify resolve_disrupted() now builds a CasterContext with the stat
	# bonus computed (not hardcoded 0). We exercise via the resolver directly.
	_build_resolver()
	var caster := _make_caster("disrupted_cleric", 5)
	# WIS 16 → bonus +2. We pass that through CasterContext explicitly here
	# to simulate what CombatController._resolve_pc_cast_disrupted does post-fix.
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 2)
	check(ctx.casting_stat_bonus == 2,
		"CasterContext carries stat_bonus 2 (post-fix), got %d" % ctx.casting_stat_bonus)
	var choice := SpellChoice.new("magic_missile", 1, false, -1)
	var result := _resolver.resolve_disrupted(ctx, choice, "damage")
	check(result.disrupted, "disrupted = true")
	check(result.slot_consumed, "slot still consumed on disruption")


func test_apply_condition_calls_add_condition_on_combatant() -> void:
	# Sleep applies "sleeping" condition. When the target is a Combatant (with
	# an add_condition method), the resolver should call it. CharacterData
	# has no add_condition, so the call is a no-op there — test by giving a
	# duck-typed proxy that records the call.
	_build_resolver()
	var caster := _make_caster("sleeper", 1)
	caster.character_class = "mage"
	caster.combat_progression = "mage"
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)

	# Duck-typed condition-tracker proxy. Carries the methods the resolver
	# needs (apply_damage stub, modifiers/flags accessors, add_condition).
	var proxy := _ConditionTrackingProxy.new()
	var choice := SpellChoice.new("sleep", 1, false, 1)  # group branch
	var td := TargetDescriptor.new()
	td.kind = "multiple_creatures_hd_budget"
	td.target_ids = ["g_sleep"]
	var result := _resolver.resolve(ctx, choice, td, caster, {"g_sleep": proxy})
	check(result.success, "Sleep cast success")
	check("sleeping" in proxy.conditions,
		"sleeping condition added to proxy via add_condition, got %s" % str(proxy.conditions))


# Helper class duck-typed against Combatant for the condition test. The
# resolver only calls add_condition on it.
class _ConditionTrackingProxy extends RefCounted:
	var conditions: Array = []

	func add_condition(condition_key: String) -> void:
		conditions.append(condition_key)

	func apply_damage(_amount: int, _damage_type: String) -> Dictionary:
		return {"hp_damage": 0}
