class_name DispelMagicResolver
extends RefCounted

## Dispel Magic (Arcane L3 / Divine L4) — caster-vs-caster effect cancellation.
##
## ACKS RAW (acore_spell_catalog_a-i_summary.xml):
##   - 120' range, instantaneous, 20' cube area effect
##   - Targets one creature/object OR an area
##   - Effects cast by a character of equal or lower level than the dispeller
##     end automatically
##   - For each higher-level effect, 5% chance of failure per level the
##     effect's caster_level exceeds the dispeller's caster_level
##   - Cannot end magical disease, geas, quest
##
## Resolver responsibilities:
##   - Iterate active_effects on each target (delegates to ActiveEffectTracker)
##   - For each effect: roll dispel_check (auto-succeed if dispeller_level >=
##     effect.caster_level; else 5% per-level fail)
##   - Return per-target list of dispelled effect_ids + spell_keys
##
## ~70 LOC, well under the 150 LOC budget.


func resolve(args: Dictionary) -> Dictionary:
	var target_descriptor = args.get("target_descriptor")
	var caster_context = args.get("caster_context")
	var spell_choice = args.get("spell_choice")
	var step_payload: Dictionary = args.get("step_payload", {})

	if target_descriptor == null or caster_context == null:
		return {"applied": false, "reason": "dispel_magic: missing context"}

	var dispeller_level: int = int(caster_context.caster_level)
	var per_target: Dictionary = {}
	var total_dispelled: int = 0

	# The active_effect_tracker handle is provided by the resolver via the
	# args dict (CastingResolver passes its own _effect_tracker reference
	# when dispatching custom resolvers — see below for fallback).
	var tracker = args.get("effect_tracker", null)
	if tracker == null:
		# Custom resolvers don't currently receive the tracker via args. Read
		# the spell-specific override from step_payload instead, or fall back
		# to a no-op + diagnostic outcome.
		tracker = step_payload.get("effect_tracker_override", null)

	for tid in target_descriptor.target_ids:
		if tracker == null or not tracker.has_method("dispel_check"):
			per_target[tid] = {
				"applied": false,
				"reason": "no effect_tracker available — dispel infrastructure required",
			}
			continue
		var results: Array = tracker.dispel_check(tid, dispeller_level)
		var dispelled_ids: Array = []
		for r in results:
			if bool(r.get("dispelled", false)):
				dispelled_ids.append(r.get("effect_id", ""))
				total_dispelled += 1
		per_target[tid] = {
			"applied": true,
			"dispel_results": results,
			"dispelled_effect_ids": dispelled_ids,
		}

	return {
		"applied": true,
		"per_target": per_target,
		"total_dispelled": total_dispelled,
		"dispeller_level": dispeller_level,
		"caster_id": caster_context.caster_id,
		"spell_key": spell_choice.spell_key if spell_choice != null else "dispel_magic",
	}
