class_name ActiveEffectTracker
extends RefCounted

## Tracks all currently active spell effects on entities.
##
## This is the central system that:
##   - Records what spell effects are active, on whom, and for how long
##   - Handles duration ticking (rounds/turns/hours via Timekeeping signals)
##   - Resolves dispel checks (ACKS: auto if dispeller_level >= effect caster_level;
##     5% cumulative fail per level that caster_level exceeds dispeller_level)
##   - Reports expired effects for upstream cleanup
##
## The tracker itself does NOT apply/remove modifiers or flags from CharacterData.
## The caller (spell resolution engine) reads applied_modifiers/applied_flags from
## the effect dict to know what to remove when an effect expires.
##
## ActiveEffect structure (Dictionary):
##   effect_id:            String
##   spell_key:            String
##   caster_id:            String
##   caster_level:         int
##   target_ids:           Array[String]
##   effect_type:          String  — "modifier"|"flag"|"entity"|"condition"|"instant"
##   applied_modifiers:    Array   — [{ "character_id", "stat_key", "source_id" }, ...]
##   applied_conditions:   Array   — [{ "character_id", "condition_key" }, ...]
##   applied_flags:        Array   — [{ "character_id", "flag_key", "source_id" }, ...]
##   duration_type:        String  — "rounds"|"turns"|"hours"|"days"|"permanent"|"concentration"
##   duration_remaining:   int     — -1 for permanent; ignored for concentration
##   requires_concentration: bool
##   is_active:            bool
##   metadata:             Dictionary  — spell-specific extras (mirror_images, etc.)
##   dispatch_cleanup_on_tick: bool   — OPT-IN: when true, on tick-expiry the
##                                       cleanup_callback fires with
##                                       cause="tick_expired" before erasure,
##                                       so applied modifiers/flags are unwound.
##                                       Defaults false for backward compat with
##                                       legacy spells whose cleanup is wired
##                                       elsewhere (e.g. via EventBus listeners
##                                       on spell_effect_removed). Added 2026-06-03
##                                       for the level-boost / Giant-Strength /
##                                       Invulnerability potion batch — those
##                                       potions stamp modifiers via the cleanup
##                                       callback's standard `_unwind_effect_state`
##                                       so they need this wired to clean up on
##                                       turn/day boundary expiry.

# _effects: effect_id -> Dictionary
var _effects: Dictionary = {}

## Optional cleanup callback invoked before erasure on the
## break_concentration / dispel_check end paths (P6). Signature:
##   func(effect: Dictionary, cause: String) -> void
## Where cause is one of "concentration_broken" | "dispelled".
## CastingResolver registers itself as this callback at boot so the
## modifier / flag / condition state is unwound in lockstep with removal.
## Falls back to direct erase when no callback is registered.
var _cleanup_callback: Callable = Callable()


## Registers (or replaces) the cleanup callback. CastingResolver._init wires
## itself; tests can override to capture invocations.
func set_cleanup_callback(cb: Callable) -> void:
	_cleanup_callback = cb


## Clears the cleanup callback. Used in test teardown so the static
## ActiveEffectTracker (in autoload contexts) doesn't keep a stale reference.
func clear_cleanup_callback() -> void:
	_cleanup_callback = Callable()


func add_effect(effect: Dictionary) -> String:
	## Registers a new active effect. Caller must supply effect_id.
	## Returns the effect_id.
	var eid: String = effect.get("effect_id", "")
	if eid.is_empty():
		push_error("ActiveEffectTracker.add_effect: effect_id is required")
		return ""
	_effects[eid] = effect.duplicate(true)
	_effects[eid]["is_active"] = true
	return eid


func remove_effect(effect_id: String) -> Dictionary:
	## Removes and returns the effect dict (so caller can clean up modifiers/flags).
	## Returns {} if not found.
	if not _effects.has(effect_id):
		return {}
	var effect: Dictionary = _effects[effect_id]
	_effects.erase(effect_id)
	return effect


func get_effect(effect_id: String) -> Dictionary:
	return _effects.get(effect_id, {})


func has_effect(effect_id: String) -> bool:
	return _effects.has(effect_id)


func get_effects_on_target(target_id: String) -> Array:
	## Returns all active effects that list target_id in their target_ids array.
	var result: Array = []
	for effect in _effects.values():
		if target_id in effect.get("target_ids", []):
			result.append(effect)
	return result


func get_effects_by_caster(caster_id: String) -> Array:
	## Returns all active effects cast by caster_id.
	var result: Array = []
	for effect in _effects.values():
		if effect.get("caster_id", "") == caster_id:
			result.append(effect)
	return result


func get_concentration_effects(caster_id: String) -> Array:
	## Returns all concentration effects currently held by caster_id.
	var result: Array = []
	for effect in _effects.values():
		if effect.get("caster_id", "") == caster_id and effect.get("requires_concentration", false):
			result.append(effect)
	return result


func get_all_effects() -> Array:
	return _effects.values()


func tick_rounds(n: int) -> Array[String]:
	## Decrements duration_remaining for all "rounds" effects.
	## Returns Array[String] of expired effect_ids (duration reached 0).
	return _tick_duration("rounds", n)


func tick_turns(n: int) -> Array[String]:
	return _tick_duration("turns", n)


func tick_hours(n: int) -> Array[String]:
	return _tick_duration("hours", n)


func tick_days(n: int) -> Array[String]:
	return _tick_duration("days", n)


func break_concentration(caster_id: String) -> Array[String]:
	## Ends all concentration effects held by caster_id.
	## Returns the effect_ids of the ended effects.
	##
	## P6: when a cleanup_callback is registered (CastingResolver), each ended
	## effect is passed to it BEFORE erasure with cause="concentration_broken"
	## so the resolver can unwind modifier / flag / condition state and emit
	## EventBus.spell_effect_removed. Without a callback, falls back to direct
	## erase (legacy behavior).
	var ended: Array[String] = []
	var snapshots: Array[Dictionary] = []
	for effect_id in _effects.keys():
		var effect: Dictionary = _effects[effect_id]
		if effect.get("caster_id", "") == caster_id and effect.get("requires_concentration", false):
			ended.append(effect_id)
			snapshots.append(effect)
	for snapshot in snapshots:
		if _cleanup_callback.is_valid():
			_cleanup_callback.call(snapshot, "concentration_broken")
	for eid in ended:
		_effects.erase(eid)
	return ended


func dispel_check(target_id: String, dispeller_level: int) -> Array[Dictionary]:
	## Resolves ACKS dispel magic against all effects on target_id.
	## ACKS rule: auto-succeed if dispeller_level >= effect's caster_level.
	## If caster_level > dispeller_level: 5% cumulative fail per level difference.
	## Returns Array of { "effect_id", "spell_key", "dispelled": bool, "roll": int }.
	##
	## P6: dispelled effects route through cleanup_callback (cause="dispelled")
	## before erasure so modifiers / flags / conditions are unwound. Without a
	## callback, falls back to direct erase.
	var results: Array[Dictionary] = []
	var to_erase: Array[String] = []
	var snapshots: Array[Dictionary] = []
	for effect_id in _effects.keys():
		var effect: Dictionary = _effects[effect_id]
		if target_id not in effect.get("target_ids", []):
			continue
		var caster_level: int = effect.get("caster_level", 1)
		var dispelled := false
		var roll := 0
		if dispeller_level >= caster_level:
			dispelled = true
			roll = 100
		else:
			var level_diff: int = caster_level - dispeller_level
			var fail_chance: int = level_diff * 5  # 5% per level difference
			roll = randi_range(1, 100)
			dispelled = roll > fail_chance
		results.append({
			"effect_id": effect_id,
			"spell_key": effect.get("spell_key", ""),
			"dispelled": dispelled,
			"roll": roll,
		})
		if dispelled:
			to_erase.append(effect_id)
			snapshots.append(effect)
	for snapshot in snapshots:
		if _cleanup_callback.is_valid():
			_cleanup_callback.call(snapshot, "dispelled")
	for eid in to_erase:
		_effects.erase(eid)
	return results


func clear() -> void:
	_effects.clear()


# --- Private ---

func _tick_duration(duration_type: String, n: int) -> Array[String]:
	var expired: Array[String] = []
	for effect_id in _effects.keys():
		var effect: Dictionary = _effects[effect_id]
		if effect.get("duration_type", "") != duration_type:
			continue
		var remaining: int = effect.get("duration_remaining", -1)
		if remaining < 0:
			continue  # permanent
		remaining -= n
		if remaining <= 0:
			expired.append(effect_id)
		else:
			_effects[effect_id]["duration_remaining"] = remaining
	# Snapshot opt-in cleanup-dispatch effects BEFORE erasure so the cleanup
	# callback can unwind applied modifiers/flags/conditions. Effects without
	# `dispatch_cleanup_on_tick: true` keep the legacy direct-erase behavior
	# (their cleanup, if any, fires via EventBus.spell_effect_removed
	# subscribers on the EffectTicker side). The opt-in field was added
	# 2026-06-03 for the level-boost / Giant Strength / Invulnerability potion
	# batch so their modifier sweep fires on turn/day-boundary expiry, parallel
	# to the concentration_broken / dispelled paths.
	#
	# The cleanup callback (CastingResolver._on_tracker_removed_effect) fires
	# EventBus.spell_effect_removed itself, so we strip cleanup-dispatched ids
	# from the returned array to keep EffectTicker's legacy emit from firing
	# the same signal twice for the same effect_id.
	var cleanup_snapshots: Array[Dictionary] = []
	var cleanup_dispatched_ids: Dictionary = {}  # effect_id -> true (set semantics)
	for eid in expired:
		var effect: Dictionary = _effects[eid]
		if bool(effect.get("dispatch_cleanup_on_tick", false)):
			cleanup_snapshots.append(effect)
			cleanup_dispatched_ids[eid] = true
	for snapshot in cleanup_snapshots:
		if _cleanup_callback.is_valid():
			_cleanup_callback.call(snapshot, "tick_expired")
	for eid in expired:
		_effects.erase(eid)
	# Filter out cleanup-dispatched ids so EffectTicker doesn't double-emit.
	if cleanup_dispatched_ids.is_empty():
		return expired
	var legacy_only: Array[String] = []
	for eid in expired:
		if not cleanup_dispatched_ids.has(eid):
			legacy_only.append(eid)
	return legacy_only
