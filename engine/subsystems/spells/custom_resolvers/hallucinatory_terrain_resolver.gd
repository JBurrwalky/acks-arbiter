class_name HallucinatoryTerrainResolver
extends RefCounted

## Hallucinatory Terrain (Arcane L4) — outdoor terrain illusion overlay.
##
## ACKS RAW (acore_spell_catalog_a-i_summary.xml):
##   - 240' range, 1 turn casting time, special duration.
##   - Makes outdoor terrain appear to be a different natural terrain type.
##   - Altered terrain looks, sounds, smells like the chosen terrain.
##   - The entire terrain feature to be disguised must be within range.
##   - Save vs Spells ONLY for creatures actively trying to disbelieve.
##   - Illusion ENDS when an intelligent creature physically enters and touches
##     the hallucinatory terrain.
##
## Resolver responsibilities:
##   - Record an `illusion_overlay` describing the disguise: source terrain
##     (real), target appearance (illusory), area cells, end_conditions.
##   - Per-viewer disbelieve state lives on the active_effect tracker; viewers
##     that actively try to disbelieve roll save vs Spells once.
##   - Active map/wilderness layer reads the overlay and renders illusory terrain
##     to viewers who haven't disbelieved.
##
## Note on persistence: persist_metadata splices `illusion_overlay` onto the
## active_effect.metadata so the wilderness/scenery rendering subsystem can
## consume it. Disbelief tracking is per-viewer (Dictionary keyed by viewer_id).
##
## ~95 LOC.


func resolve(args: Dictionary) -> Dictionary:
	var target_descriptor = args.get("target_descriptor")
	var caster_context = args.get("caster_context")
	var spell_choice = args.get("spell_choice")
	var step_payload: Dictionary = args.get("step_payload", {})
	var resolver_args: Dictionary = step_payload.get("resolver_args", {})

	if target_descriptor == null:
		return {"applied": false, "reason": "hallucinatory_terrain_resolver: missing target_descriptor"}

	# Disguise spec: caster picks the apparent terrain type via the targeting
	# UI. For Session 10, accept it from resolver_args; the picker layer fills
	# this in when the spell is cast.
	var apparent_terrain := String(resolver_args.get("apparent_terrain", "forest"))
	var area_cells: Array = target_descriptor.target_cells.duplicate() if target_descriptor.target_cells != null else []
	if area_cells.is_empty() and target_descriptor.origin_cell != null:
		area_cells = [target_descriptor.origin_cell]

	var illusion_overlay: Dictionary = {
		"overlay_id": "hallucinatory_terrain:%s" % (caster_context.caster_id if caster_context != null else "unknown"),
		"caster_id": caster_context.caster_id if caster_context != null else "",
		"caster_level": caster_context.caster_level if caster_context != null else 1,
		"apparent_terrain": apparent_terrain,
		"area_cells": area_cells,
		# Per-viewer disbelief is populated by the active_effect tracker as
		# viewers attempt save vs Spells.
		"viewers_disbelieved": {},
		"end_conditions": {
			"intelligent_touch": true,  # ends when intelligent creature enters
			"dispel_magic": true,
		},
	}

	return {
		"applied": true,
		"illusion_overlay": illusion_overlay,
		"area_cells": area_cells,
		"caster_id": caster_context.caster_id if caster_context != null else "",
		"spell_key": spell_choice.spell_key if spell_choice != null else "hallucinatory_terrain",
		"persist_metadata": {
			"illusion_overlay": illusion_overlay,
		},
	}
