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

# _effects: effect_id -> Dictionary
var _effects: Dictionary = {}


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
	## Returns the effect_ids of the ended effects (caller should clean up).
	var ended: Array[String] = []
	for effect_id in _effects.keys():
		var effect: Dictionary = _effects[effect_id]
		if effect.get("caster_id", "") == caster_id and effect.get("requires_concentration", false):
			ended.append(effect_id)
	for eid in ended:
		_effects.erase(eid)
	return ended


func dispel_check(target_id: String, dispeller_level: int) -> Array[Dictionary]:
	## Resolves ACKS dispel magic against all effects on target_id.
	## ACKS rule: auto-succeed if dispeller_level >= effect's caster_level.
	## If caster_level > dispeller_level: 5% cumulative fail per level difference.
	## Returns Array of { "effect_id", "spell_key", "dispelled": bool, "roll": int }.
	var results: Array[Dictionary] = []
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
			_effects.erase(effect_id)
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
	for eid in expired:
		_effects.erase(eid)
	return expired
