class_name ProjectedImageResolver
extends RefCounted

## Projected Image (Arcane L6) — quasi-real illusory caster duplicate.
##
## ACKS RAW (acore_spell_catalog_k-w_summary.xml):
##   - 240' range, 6 turns duration.
##   - Image looks/sounds/smells like the caster.
##   - Mimics gestures, actions, speech.
##   - FURTHER SPELLS CAST BY CASTER APPEAR TO ORIGINATE FROM THE IMAGE.
##   - Spell ENDS when LoS broken between caster and image OR image is struck.
##   - Grants no additional sensory capability.
##   - Spell ranges measured from caster's actual position, NOT image's.
##   - Dimension Door / Teleport / similar that break LoS dispel the image.
##
## Resolver responsibilities:
##   - Spawn image entity at target cell within 240'.
##   - Persist image_profile with end_conditions (LoS_broken, struck_in_combat).
##   - Spell-origin redirect is the casting subsystem's job (consumer reads
##     image_profile to override visual spell origin to image's position).
##
## ~75 LOC.


func resolve(args: Dictionary) -> Dictionary:
	var caster_context = args.get("caster_context")
	var target_descriptor = args.get("target_descriptor")
	var spell_choice = args.get("spell_choice")
	var step_payload: Dictionary = args.get("step_payload", {})
	var resolver_args: Dictionary = step_payload.get("resolver_args", {})

	if caster_context == null:
		return {"applied": false, "reason": "projected_image_resolver: missing caster_context"}

	var image_cell: Vector3i = target_descriptor.origin_cell if target_descriptor != null else Vector3i.ZERO

	var image_profile: Dictionary = {
		"image_id": "projected_image:%s" % caster_context.caster_id,
		"caster_id": caster_context.caster_id,
		"caster_level": caster_context.caster_level,
		"image_cell": image_cell,
		"redirects_spell_origin_visually": true,
		"actual_spell_origin_cell": "caster_actual_position",
		"end_conditions": {
			"line_of_sight_broken": true,
			"image_struck_in_combat": true,
			"caster_teleports": true,
		},
		"grants_no_sensory_capability": true,
	}

	return {
		"applied": true,
		"image_profile": image_profile,
		"caster_id": caster_context.caster_id,
		"spell_key": spell_choice.spell_key if spell_choice != null else "projected_image",
		"persist_metadata": {
			"projected_image_profile": image_profile,
		},
	}
