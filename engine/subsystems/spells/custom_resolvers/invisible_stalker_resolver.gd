class_name InvisibleStalkerResolver
extends RefCounted

## Invisible Stalker (Arcane L6) — summons a hunting invisible creature.
##
## ACKS RAW (acore_spell_catalog_a-i_summary.xml):
##   - 10' range, special duration.
##   - Summons an invisible stalker to perform the caster's bidding.
##   - Stalker appears anywhere within range.
##   - Spell lasts until: dispel evil cast on the stalker, the stalker is slain,
##     or the assigned task is completed.
##   - Stalker may not always be a reliable servant — consult monster entry.
##
## Resolver responsibilities:
##   - Spawn an invisible_stalker entity with the assigned task.
##   - Persist spawn_profile (task, end_conditions, reliability_check_required).
##   - Loyalty + reliability handling is consumer-side.
##
## ~75 LOC.


func resolve(args: Dictionary) -> Dictionary:
	var caster_context = args.get("caster_context")
	var target_descriptor = args.get("target_descriptor")
	var spell_choice = args.get("spell_choice")
	var step_payload: Dictionary = args.get("step_payload", {})
	var resolver_args: Dictionary = step_payload.get("resolver_args", {})

	if caster_context == null:
		return {"applied": false, "reason": "invisible_stalker_resolver: missing caster_context"}

	var assigned_task := String(resolver_args.get("assigned_task", "guard_caster"))
	var spawn_cell: Vector3i = target_descriptor.origin_cell if target_descriptor != null else Vector3i.ZERO

	var spawn_profile: Dictionary = {
		"stalker_id": "invisible_stalker:%s" % caster_context.caster_id,
		"caster_id": caster_context.caster_id,
		"caster_level": caster_context.caster_level,
		"spawn_cell": spawn_cell,
		"is_invisible": true,
		"assigned_task": assigned_task,
		"end_conditions": {
			"dispel_evil_cast_on_stalker": true,
			"stalker_slain": true,
			"task_completed": true,
		},
		"reliability_check_required": true,
		"banishable_only_by": ["dispel_evil"],
	}

	return {
		"applied": true,
		"spawn_profile": spawn_profile,
		"assigned_task": assigned_task,
		"caster_id": caster_context.caster_id,
		"spell_key": spell_choice.spell_key if spell_choice != null else "invisible_stalker",
		"persist_metadata": {
			"invisible_stalker_spawn_profile": spawn_profile,
		},
	}
