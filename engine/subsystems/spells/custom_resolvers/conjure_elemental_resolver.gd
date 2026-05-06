class_name ConjureElementalResolver
extends RefCounted

## Conjure Elemental (Arcane L5) — summons an elemental of chosen type.
##
## ACKS RAW (acore_spell_catalog_a-i_summary.xml):
##   - 240' range, special duration (concentration-based).
##   - Summons elemental of Air, Earth, Fire, or Water.
##   - Serves indefinitely WHILE caster concentrates SOLELY on controlling it.
##   - Loss of concentration triggers: spellcasting, combat, movement >half rate.
##   - Once concentration lost: control is PERMANENTLY lost; elemental becomes
##     hostile to conjurer and all in its path.
##   - Caster may dismiss controlled elemental at will (caster's initiative).
##   - At most one elemental of each TYPE per day.
##   - Uncontrolled elemental: only dispel magic or dispel evil banishes.
##   - Uncontrolled elemental may choose to return home; will not stay long.
##
## Resolver responsibilities:
##   - Validate elemental type from resolver_args.elemental_type.
##   - Per-day-per-type cap enforcement: caller checks (picker), but resolver
##     records the elemental_type for the daily-cap subsystem.
##   - Spawn elemental entity via spawn_profile.
##   - Persist concentration_required + becomes_hostile_on_concentration_break
##     so SpellCombatHooks consumes those at hostile-flip time.
##
## ~95 LOC.

const VALID_ELEMENTAL_TYPES: Array = ["air", "earth", "fire", "water"]


func resolve(args: Dictionary) -> Dictionary:
	var caster_context = args.get("caster_context")
	var target_descriptor = args.get("target_descriptor")
	var spell_choice = args.get("spell_choice")
	var step_payload: Dictionary = args.get("step_payload", {})
	var resolver_args: Dictionary = step_payload.get("resolver_args", {})

	if caster_context == null:
		return {"applied": false, "reason": "conjure_elemental_resolver: missing caster_context"}

	var elemental_type := String(resolver_args.get("elemental_type", "earth")).to_lower()
	if elemental_type not in VALID_ELEMENTAL_TYPES:
		return {
			"applied": false,
			"reason": "invalid_elemental_type",
			"requested": elemental_type,
			"valid": VALID_ELEMENTAL_TYPES,
		}

	var spawn_profile: Dictionary = {
		"elemental_id": "elemental_%s:%s" % [elemental_type, caster_context.caster_id],
		"elemental_type": elemental_type,
		"caster_id": caster_context.caster_id,
		"caster_level": caster_context.caster_level,
		"summon_cell": target_descriptor.origin_cell if target_descriptor != null else Vector3i.ZERO,
		"loyalty": "controlled_via_concentration",
		"becomes_hostile_on_concentration_break": true,
		"banishable_only_by": ["dispel_magic", "dispel_evil"],
		"daily_cap_per_type": 1,
	}

	return {
		"applied": true,
		"elemental_type": elemental_type,
		"spawn_profile": spawn_profile,
		"caster_id": caster_context.caster_id,
		"spell_key": spell_choice.spell_key if spell_choice != null else "conjure_elemental",
		"persist_metadata": {
			"conjure_elemental_spawn_profile": spawn_profile,
		},
	}
