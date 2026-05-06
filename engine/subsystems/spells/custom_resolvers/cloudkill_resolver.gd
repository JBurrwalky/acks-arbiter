class_name CloudkillResolver
extends RefCounted

## Cloudkill (Arcane L5) — moving cloud of poisonous gas.
##
## ACKS RAW (acore_spell_catalog_a-i_summary.xml):
##   - Special range, 6 turns duration.
##   - 30' diameter cloud.
##   - Spreads from caster's fingertips.
##   - Moves 20' per round AWAY from the caster.
##   - Heavier than air: sinks down holes, slides downhill.
##   - Trees / thick vegetation break up the cloud.
##   - >=5 HD creatures take 1 point damage per round in cloud.
##   - <5 HD creatures: save vs Poison or DIE per round in cloud; even on
##     successful save still take 1 point damage.
##   - Persists full duration even if caster stops concentrating.
##
## Resolver responsibilities:
##   - Record cloud_profile (diameter, drift_direction, hd_threshold, damage,
##     death_save_threshold).
##   - persist_metadata.cloud_profile splices to active_effect; on_round_end
##     consumer (SpellCombatHooks) advances the cloud, computes which creatures
##     are inside this round, and rolls the damage / death save per RAW.
##
## ~85 LOC.


func resolve(args: Dictionary) -> Dictionary:
	var caster_context = args.get("caster_context")
	var target_descriptor = args.get("target_descriptor")
	var spell_choice = args.get("spell_choice")
	var step_payload: Dictionary = args.get("step_payload", {})
	var resolver_args: Dictionary = step_payload.get("resolver_args", {})

	if caster_context == null or target_descriptor == null:
		return {"applied": false, "reason": "cloudkill_resolver: missing context"}

	# Drift direction: defaults to "away_from_caster"; picker may override.
	var drift_direction := String(resolver_args.get("drift_direction", "away_from_caster"))
	var origin_cell: Vector3i = target_descriptor.origin_cell
	var cloud_profile: Dictionary = {
		"cloud_id": "cloudkill:%s" % caster_context.caster_id,
		"caster_id": caster_context.caster_id,
		"caster_level": caster_context.caster_level,
		"diameter_feet": 30,
		"origin_cell": origin_cell,
		"drift_direction": drift_direction,
		"drift_feet_per_round": 20,
		"persists_without_concentration": true,
		# Damage profile per RAW.
		"damage_per_round": 1,
		"damage_type": "poison",
		"hd_threshold_for_death_save": 5,  # <5 HD save vs Poison or die
		"save_category": "poison_death",
		# Heavier-than-air interaction tags for the runtime layer.
		"sinks_down_holes": true,
		"slides_downhill": true,
		"broken_by_vegetation": true,
	}

	return {
		"applied": true,
		"cloud_profile": cloud_profile,
		"caster_id": caster_context.caster_id,
		"spell_key": spell_choice.spell_key if spell_choice != null else "cloudkill",
		"persist_metadata": {
			"cloud_profile": cloud_profile,
		},
	}
