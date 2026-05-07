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
## ACKS Core gives elementals three power tiers keyed to summoning method:
## staff (8 HD), miscellaneous magic item (12 HD), spell (16 HD). Conjure
## Elemental is a 5th-level magic-user spell so it summons spell-tier (16 HD)
## by default. Future non-spell summoning paths can override via resolver_args.
const VALID_TIERS: Array = ["8hd", "12hd", "16hd"]
const DEFAULT_TIER: String = "16hd"


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

	var tier := String(resolver_args.get("tier", DEFAULT_TIER)).to_lower()
	if tier not in VALID_TIERS:
		return {
			"applied": false,
			"reason": "invalid_tier",
			"requested": tier,
			"valid": VALID_TIERS,
		}

	var spawn_profile: Dictionary = {
		"elemental_id": "elemental_%s_%s:%s" % [elemental_type, tier, caster_context.caster_id],
		"elemental_type": elemental_type,
		"tier": tier,
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
		"tier": tier,
		"spawn_profile": spawn_profile,
		"caster_id": caster_context.caster_id,
		"spell_key": spell_choice.spell_key if spell_choice != null else "conjure_elemental",
		"persist_metadata": {
			"conjure_elemental_spawn_profile": spawn_profile,
		},
	}


## P7 — expiration callback. Dismisses the summoned elemental back to its
## native plane on every cleanup cause EXCEPT concentration_broken (which
## flips control to hostile per RAW; the elemental remains on the roster
## as an enemy via the elemental_uncontrolled path in SpellCombatHooks).
## record_casualty is NOT called per RAW.
static func on_expiration(
		effect: Dictionary, cause: String, _target_lookup: Callable) -> void:
	var meta: Dictionary = effect.get("metadata", {})
	var profile: Dictionary = meta.get("conjure_elemental_spawn_profile", {})
	if profile.is_empty():
		return
	# Concentration loss → uncontrolled-hostile path, not dismissal.
	if cause == "concentration_broken":
		return
	var elemental_id := String(profile.get("elemental_id", ""))
	var elemental_type := String(profile.get("elemental_type", "earth"))
	if elemental_id.is_empty():
		return
	EventBus.combatant_dismissed_to_native_plane.emit(elemental_id, elemental_type, cause)
