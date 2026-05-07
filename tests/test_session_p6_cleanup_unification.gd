extends "res://tests/test_suite_base.gd"

## Session P6 — ActiveEffectTracker Cleanup Unification.
##
## Validates:
##   - Concentration break unwinds modifiers + flags (not just erases the row)
##   - Dispel check unwinds modifiers + conditions
##   - spell_effect_removed fires on all three end paths
##   - active_effect_expired fires ONLY on duration-tick expiry
##   - Per-spell expiration_callback fires with cause label on every path
##   - Backward compat: tracker without callback still erases
##   - CustomResolverRegistry.clear() drops both resolvers + expiration callbacks


# Capture EventBus emissions for assertions.
class _SignalListener extends RefCounted:
	var removed: Array = []   # [{effect_id, spell_key}]
	var expired: Array = []   # [{character_id, effect_id}]
	var conditions: Array = [] # [{character_id, change}]
	func on_removed(eid: String, sk: String) -> void:
		removed.append({"effect_id": eid, "spell_key": sk})
	func on_expired(cid: String, eid: String) -> void:
		expired.append({"character_id": cid, "effect_id": eid})
	func on_condition(cid: String, change: Dictionary) -> void:
		conditions.append({"character_id": cid, "change": change})


# Captures expiration callback invocations.
class _ExpirationCapture extends RefCounted:
	var calls: Array = []  # [{spell_key, effect, cause, lookup}]
	# P7 added a target_lookup arg to the callback signature.
	func make_callback(spell_key: String) -> Callable:
		return func(effect: Dictionary, cause: String, lookup: Callable) -> void:
			calls.append({
				"spell_key": spell_key, "effect": effect,
				"cause": cause, "lookup": lookup,
			})


func run_all_tests() -> void:
	test_concentration_break_unwinds_modifiers()
	test_concentration_break_unwinds_flags()
	test_dispel_check_unwinds_modifiers()
	test_dispel_check_unwinds_conditions()
	test_spell_effect_removed_fires_on_all_three_paths()
	test_active_effect_expired_fires_only_on_duration_end()
	test_expiration_callback_fires_on_duration_end()
	test_expiration_callback_fires_on_concentration_break()
	test_expiration_callback_fires_on_dispel()
	test_tracker_without_callback_falls_back_to_direct_erase()
	test_registry_clear_drops_resolvers_and_expiration_callbacks()
	test_per_spell_callback_replaces_existing_registration()
	if not has_failures():
		print("SessionP6CleanupUnification: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _attach_listener() -> _SignalListener:
	var listener := _SignalListener.new()
	EventBus.spell_effect_removed.connect(listener.on_removed)
	EventBus.active_effect_expired.connect(listener.on_expired)
	EventBus.condition_changed.connect(listener.on_condition)
	return listener


func _detach_listener(listener: _SignalListener) -> void:
	if EventBus.spell_effect_removed.is_connected(listener.on_removed):
		EventBus.spell_effect_removed.disconnect(listener.on_removed)
	if EventBus.active_effect_expired.is_connected(listener.on_expired):
		EventBus.active_effect_expired.disconnect(listener.on_expired)
	if EventBus.condition_changed.is_connected(listener.on_condition):
		EventBus.condition_changed.disconnect(listener.on_condition)


func _make_resolver() -> Dictionary:
	# Returns dict with tracker, resolver, custom_registry, listener for tests.
	var tracker := ActiveEffectTracker.new()
	var custom := CustomResolverRegistry.new()
	# Build a CastingResolver shell — most fields can be null because we only
	# exercise the unwind/cleanup path, not the full resolve() pipeline.
	var resolver := CastingResolver.new(null, null, tracker, null, custom, null, null, null)
	return {"tracker": tracker, "resolver": resolver, "custom": custom}


func _make_target() -> CharacterData:
	var c := CharacterData.new()
	c.id = "tgt_p6"
	c.name = "Target"
	c.hp_max = 8
	c.hp_current = 8
	return c


func _bless_effect(target_id: String, source_id: String, concentration: bool) -> Dictionary:
	# A Bless-style modifier effect: +1 attack_throw on target.
	return {
		"effect_id": "fx_bless",
		"spell_key": "bless",
		"caster_id": "caster_p6",
		"caster_level": 5,
		"target_ids": [target_id],
		"effect_type": "modifier",
		"applied_modifiers": [{
			"character_id": target_id,
			"stat_key": "attack_throw",
			"source_id": source_id,
		}],
		"applied_conditions": [],
		"applied_flags": [],
		"duration_type": "concentration" if concentration else "rounds",
		"duration_remaining": -1 if concentration else 6,
		"requires_concentration": concentration,
		"is_active": 1,
		"metadata": {},
		"created_at_round": 0,
	}


# ---------------------------------------------------------------------------
# Concentration break — unwinds modifiers + flags
# ---------------------------------------------------------------------------

func test_concentration_break_unwinds_modifiers() -> void:
	var env := _make_resolver()
	var target := _make_target()
	# Apply Bless modifier directly so the unwind path has something to remove.
	var source_id := "spell:bless:caster_p6"
	target.modifiers.add_modifier("attack_throw", {
		"source_id": source_id, "source_type": "spell",
		"operation": "add", "value": 1, "stacking_group": "",
	})
	check(target.modifiers.get_effective_value("attack_throw", 10) == 11,
		"baseline: bless +1 active before break")
	env.tracker.add_effect(_bless_effect(target.id, source_id, true))
	# Wire a target lookup so the resolver can find the target.
	env.resolver.set_default_target_lookup(func(tid: String) -> Variant:
		return target if tid == target.id else null)
	env.tracker.break_concentration("caster_p6")
	check(target.modifiers.get_effective_value("attack_throw", 10) == 10,
		"break_concentration unwinds modifier, +1 cleared, got %d" %
		target.modifiers.get_effective_value("attack_throw", 10))
	check(not env.tracker.has_effect("fx_bless"), "tracker erased the effect row")


func test_concentration_break_unwinds_flags() -> void:
	var env := _make_resolver()
	var target := _make_target()
	var source_id := "spell:invisibility:caster_p6"
	target.flags.set_flag("is_invisible", source_id, {})
	check(target.flags.has_flag("is_invisible"), "baseline: invisible flag set")
	var effect: Dictionary = {
		"effect_id": "fx_invis", "spell_key": "invisibility",
		"caster_id": "caster_p6", "caster_level": 4, "target_ids": [target.id],
		"effect_type": "flag",
		"applied_modifiers": [], "applied_conditions": [],
		"applied_flags": [{
			"character_id": target.id, "flag_key": "is_invisible",
			"source_id": source_id,
		}],
		"duration_type": "concentration", "duration_remaining": -1,
		"requires_concentration": true, "is_active": 1, "metadata": {},
		"created_at_round": 0,
	}
	env.tracker.add_effect(effect)
	env.resolver.set_default_target_lookup(func(tid: String) -> Variant:
		return target if tid == target.id else null)
	env.tracker.break_concentration("caster_p6")
	check(not target.flags.has_flag("is_invisible"),
		"break_concentration unwinds flag, is_invisible cleared")


# ---------------------------------------------------------------------------
# Dispel check — unwinds modifiers + conditions
# ---------------------------------------------------------------------------

func test_dispel_check_unwinds_modifiers() -> void:
	var env := _make_resolver()
	var target := _make_target()
	var source_id := "spell:bless:caster_p6"
	target.modifiers.add_modifier("attack_throw", {
		"source_id": source_id, "source_type": "spell",
		"operation": "add", "value": 1, "stacking_group": "",
	})
	env.tracker.add_effect(_bless_effect(target.id, source_id, false))
	env.resolver.set_default_target_lookup(func(tid: String) -> Variant:
		return target if tid == target.id else null)
	# Dispel by an L9 mage — auto-succeeds vs L5 effect.
	var results: Array = env.tracker.dispel_check(target.id, 9)
	check(results.size() == 1, "one dispel result returned")
	check(bool(results[0].get("dispelled", false)), "dispel succeeded vs lower-level effect")
	check(target.modifiers.get_effective_value("attack_throw", 10) == 10,
		"dispel unwinds modifier, +1 cleared")


func test_dispel_check_unwinds_conditions() -> void:
	var env := _make_resolver()
	var target := _make_target()
	# Hold Person paralyzed condition.
	var effect: Dictionary = {
		"effect_id": "fx_hold", "spell_key": "hold_person",
		"caster_id": "caster_p6", "caster_level": 5, "target_ids": [target.id],
		"effect_type": "condition",
		"applied_modifiers": [], "applied_flags": [],
		"applied_conditions": [{
			"character_id": target.id, "condition_key": "paralyzed",
		}],
		"duration_type": "rounds", "duration_remaining": 9,
		"requires_concentration": false, "is_active": 1, "metadata": {},
		"created_at_round": 0,
	}
	env.tracker.add_effect(effect)
	env.resolver.set_default_target_lookup(func(tid: String) -> Variant:
		return target if tid == target.id else null)
	var listener := _attach_listener()
	env.tracker.dispel_check(target.id, 9)
	# condition_changed(applied=false) fired for the condition.
	var found := false
	for ev in listener.conditions:
		var ch: Dictionary = ev.change
		if ev.character_id == target.id and ch.get("condition") == "paralyzed" \
				and not bool(ch.get("applied", true)):
			found = true
			break
	check(found, "dispel emitted condition_changed(applied=false) for paralyzed")
	_detach_listener(listener)


# ---------------------------------------------------------------------------
# Signal semantics — spell_effect_removed unified, active_effect_expired duration-only
# ---------------------------------------------------------------------------

func test_spell_effect_removed_fires_on_all_three_paths() -> void:
	# Path 1: duration expiry (via tick_and_cleanup)
	# Path 2: concentration break
	# Path 3: dispel
	var env := _make_resolver()
	var t1 := _make_target(); t1.id = "tgt_dur"
	var t2 := _make_target(); t2.id = "tgt_conc"
	var t3 := _make_target(); t3.id = "tgt_disp"
	env.tracker.add_effect({
		"effect_id": "fx_dur", "spell_key": "bless", "caster_id": "c",
		"caster_level": 1, "target_ids": [t1.id], "effect_type": "modifier",
		"applied_modifiers": [], "applied_flags": [], "applied_conditions": [],
		"duration_type": "rounds", "duration_remaining": 1,
		"requires_concentration": false, "is_active": 1, "metadata": {},
		"created_at_round": 0,
	})
	env.tracker.add_effect({
		"effect_id": "fx_conc", "spell_key": "bless", "caster_id": "c_conc",
		"caster_level": 1, "target_ids": [t2.id], "effect_type": "modifier",
		"applied_modifiers": [], "applied_flags": [], "applied_conditions": [],
		"duration_type": "concentration", "duration_remaining": -1,
		"requires_concentration": true, "is_active": 1, "metadata": {},
		"created_at_round": 0,
	})
	env.tracker.add_effect({
		"effect_id": "fx_disp", "spell_key": "bless", "caster_id": "c_disp",
		"caster_level": 1, "target_ids": [t3.id], "effect_type": "modifier",
		"applied_modifiers": [], "applied_flags": [], "applied_conditions": [],
		"duration_type": "rounds", "duration_remaining": 5,
		"requires_concentration": false, "is_active": 1, "metadata": {},
		"created_at_round": 0,
	})
	env.resolver.set_default_target_lookup(func(_tid: String) -> Variant: return null)
	var listener := _attach_listener()
	# Path 1
	env.resolver.tick_and_cleanup("rounds", 1, func(_tid: String) -> Variant: return null)
	# Path 2
	env.tracker.break_concentration("c_conc")
	# Path 3
	env.tracker.dispel_check(t3.id, 9)
	var ids: Array = []
	for ev in listener.removed:
		ids.append(ev.effect_id)
	check(ids.has("fx_dur"), "spell_effect_removed fired for duration expiry")
	check(ids.has("fx_conc"), "spell_effect_removed fired for concentration break")
	check(ids.has("fx_disp"), "spell_effect_removed fired for dispel")
	_detach_listener(listener)


func test_active_effect_expired_fires_only_on_duration_end() -> void:
	var env := _make_resolver()
	env.tracker.add_effect({
		"effect_id": "fx_dur2", "spell_key": "bless", "caster_id": "c",
		"caster_level": 1, "target_ids": [], "effect_type": "modifier",
		"applied_modifiers": [], "applied_flags": [], "applied_conditions": [],
		"duration_type": "rounds", "duration_remaining": 1,
		"requires_concentration": false, "is_active": 1, "metadata": {},
		"created_at_round": 0,
	})
	env.tracker.add_effect({
		"effect_id": "fx_conc2", "spell_key": "bless", "caster_id": "c2",
		"caster_level": 1, "target_ids": [], "effect_type": "modifier",
		"applied_modifiers": [], "applied_flags": [], "applied_conditions": [],
		"duration_type": "concentration", "duration_remaining": -1,
		"requires_concentration": true, "is_active": 1, "metadata": {},
		"created_at_round": 0,
	})
	env.resolver.set_default_target_lookup(func(_tid: String) -> Variant: return null)
	var listener := _attach_listener()
	env.resolver.tick_and_cleanup("rounds", 1, func(_tid: String) -> Variant: return null)
	env.tracker.break_concentration("c2")
	# active_effect_expired should fire ONCE (only for the duration tick).
	check(listener.expired.size() == 1,
		"active_effect_expired fires only on duration-tick path, got %d" %
		listener.expired.size())
	if listener.expired.size() == 1:
		check(listener.expired[0].effect_id == "fx_dur2",
			"the lone active_effect_expired emission is for the duration effect")
	_detach_listener(listener)


# ---------------------------------------------------------------------------
# Per-spell expiration callbacks fire on every path with correct cause label
# ---------------------------------------------------------------------------

func test_expiration_callback_fires_on_duration_end() -> void:
	var env := _make_resolver()
	var capture := _ExpirationCapture.new()
	env.custom.register_expiration_callback("polymorph_self", capture.make_callback("polymorph_self"))
	env.tracker.add_effect({
		"effect_id": "fx_poly_dur", "spell_key": "polymorph_self", "caster_id": "c",
		"caster_level": 5, "target_ids": [], "effect_type": "flag",
		"applied_modifiers": [], "applied_flags": [], "applied_conditions": [],
		"duration_type": "rounds", "duration_remaining": 1,
		"requires_concentration": false, "is_active": 1, "metadata": {"snap": "x"},
		"created_at_round": 0,
	})
	env.resolver.tick_and_cleanup("rounds", 1, func(_tid: String) -> Variant: return null)
	check(capture.calls.size() == 1, "expiration callback called once on duration expiry")
	if capture.calls.size() == 1:
		check(String(capture.calls[0].cause) == "duration_expired",
			"cause is 'duration_expired', got '%s'" % capture.calls[0].cause)


func test_expiration_callback_fires_on_concentration_break() -> void:
	var env := _make_resolver()
	var capture := _ExpirationCapture.new()
	env.custom.register_expiration_callback("polymorph_self", capture.make_callback("polymorph_self"))
	env.tracker.add_effect({
		"effect_id": "fx_poly_conc", "spell_key": "polymorph_self", "caster_id": "c_pc",
		"caster_level": 5, "target_ids": [], "effect_type": "flag",
		"applied_modifiers": [], "applied_flags": [], "applied_conditions": [],
		"duration_type": "concentration", "duration_remaining": -1,
		"requires_concentration": true, "is_active": 1, "metadata": {},
		"created_at_round": 0,
	})
	env.resolver.set_default_target_lookup(func(_tid: String) -> Variant: return null)
	env.tracker.break_concentration("c_pc")
	check(capture.calls.size() == 1, "expiration callback called once on concentration break")
	if capture.calls.size() == 1:
		check(String(capture.calls[0].cause) == "concentration_broken",
			"cause is 'concentration_broken', got '%s'" % capture.calls[0].cause)


func test_expiration_callback_fires_on_dispel() -> void:
	var env := _make_resolver()
	var capture := _ExpirationCapture.new()
	env.custom.register_expiration_callback("polymorph_self", capture.make_callback("polymorph_self"))
	env.tracker.add_effect({
		"effect_id": "fx_poly_disp", "spell_key": "polymorph_self", "caster_id": "c_pd",
		"caster_level": 3, "target_ids": ["self"], "effect_type": "flag",
		"applied_modifiers": [], "applied_flags": [], "applied_conditions": [],
		"duration_type": "turns", "duration_remaining": 6,
		"requires_concentration": false, "is_active": 1, "metadata": {},
		"created_at_round": 0,
	})
	env.resolver.set_default_target_lookup(func(_tid: String) -> Variant: return null)
	env.tracker.dispel_check("self", 9)
	check(capture.calls.size() == 1, "expiration callback called once on dispel")
	if capture.calls.size() == 1:
		check(String(capture.calls[0].cause) == "dispelled",
			"cause is 'dispelled', got '%s'" % capture.calls[0].cause)


# ---------------------------------------------------------------------------
# Backward compatibility + registry teardown
# ---------------------------------------------------------------------------

func test_tracker_without_callback_falls_back_to_direct_erase() -> void:
	var tracker := ActiveEffectTracker.new()
	# No CastingResolver — no cleanup_callback registered.
	tracker.add_effect({
		"effect_id": "fx_bare", "spell_key": "bless", "caster_id": "bare",
		"caster_level": 1, "target_ids": [], "effect_type": "modifier",
		"applied_modifiers": [], "applied_flags": [], "applied_conditions": [],
		"duration_type": "concentration", "duration_remaining": -1,
		"requires_concentration": true, "is_active": 1, "metadata": {},
		"created_at_round": 0,
	})
	check(tracker.has_effect("fx_bare"), "baseline: effect added")
	var ended: Array = tracker.break_concentration("bare")
	check(ended.size() == 1 and not tracker.has_effect("fx_bare"),
		"break_concentration without callback still erases, got %d ended" % ended.size())


func test_registry_clear_drops_resolvers_and_expiration_callbacks() -> void:
	var registry := CustomResolverRegistry.new()
	var dummy := RefCounted.new()
	registry.register("foo_resolver", dummy)
	registry.register_expiration_callback("foo_spell",
		func(_e: Dictionary, _c: String, _l: Callable) -> void: pass)
	check(registry.has_resolver("foo_resolver"), "baseline: resolver registered")
	check(registry.has_expiration_callback("foo_spell"),
		"baseline: expiration callback registered")
	registry.clear()
	check(not registry.has_resolver("foo_resolver"),
		"clear() drops resolver registration")
	check(not registry.has_expiration_callback("foo_spell"),
		"clear() drops expiration callback registration")


func test_per_spell_callback_replaces_existing_registration() -> void:
	var registry := CustomResolverRegistry.new()
	var first := _ExpirationCapture.new()
	var second := _ExpirationCapture.new()
	registry.register_expiration_callback("polymorph_self", first.make_callback("first"))
	registry.register_expiration_callback("polymorph_self", second.make_callback("second"))
	registry.invoke_expiration_callback("polymorph_self", {}, "duration_expired")
	check(first.calls.is_empty(),
		"replaced first callback no longer fires")
	check(second.calls.size() == 1,
		"second callback fires once after replacement")
