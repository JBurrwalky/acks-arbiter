class_name WallOfIceResolver
extends RefCounted

## Wall of Ice (Arcane L4) — persistent area-blocking wall.
##
## ACKS RAW (acore_spell_catalog_k-w_summary.xml):
##   - 120' range, 2 turns duration.
##   - Up to 1,200 square feet; straight or curved into a protective circle.
##   - Immobile translucent wall of ice.
##   - Creatures with MORE than 4 HD take 1d6 damage when BREAKING through
##     (damage applies on the attempt to break, not on passing freely — there
##     is no passing through; one must break).
##   - Impenetrable to monsters with FEWER than 4 HD.
##   - Deals DOUBLE damage to creatures that use fire or are accustomed to hot
##     conditions.
##   - Cannot appear where objects or creatures already are.
##   - Must rest on a solid surface.
##
## Distinguishing from Wall of Fire:
##   - Translucent (not opaque) — line of sight passes through.
##   - Damage trigger is "break through" (a strength check or attack), not just
##     passing.
##   - Double-damage targets are FIRE-using/hot-accustomed (mirror of fire wall's
##     cold-using bonus).
##   - Must rest on solid surface (cannot float in mid-air).
##
## ~95 LOC.


const MAX_AREA_SQUARE_FEET: int = 1200
const CELL_AREA_SQUARE_FEET: int = 25


func resolve(args: Dictionary) -> Dictionary:
	var caster_context = args.get("caster_context")
	var target_descriptor = args.get("target_descriptor")
	var spell_choice = args.get("spell_choice")
	var step_payload: Dictionary = args.get("step_payload", {})
	var resolver_args: Dictionary = step_payload.get("resolver_args", {})

	if caster_context == null or target_descriptor == null:
		return {"applied": false, "reason": "wall_of_ice_resolver: missing context"}

	var wall_segments: Array = resolver_args.get("wall_segments", target_descriptor.target_cells)
	if wall_segments == null:
		wall_segments = []

	var total_area: int = wall_segments.size() * CELL_AREA_SQUARE_FEET
	if total_area > MAX_AREA_SQUARE_FEET:
		return {
			"applied": false,
			"reason": "wall_area_exceeds_max",
			"requested_area": total_area,
			"max_area": MAX_AREA_SQUARE_FEET,
		}

	var wall_profile: Dictionary = {
		"wall_id": "wall_of_ice:%s" % caster_context.caster_id,
		"wall_type": "ice",
		"caster_id": caster_context.caster_id,
		"caster_level": caster_context.caster_level,
		"wall_segments": wall_segments,
		"area_square_feet": total_area,
		"damage_dice": "1d6",
		"damage_type": "cold",
		# Per RAW: ≤4 HD creatures CANNOT pass; >4 HD take 1d6 on breaking.
		"min_hd_to_break": 5,
		# Trigger: damage on BREAKING through, not on passing (no free passage).
		"damage_trigger": "break_through",
		# Double damage to fire-using and hot-accustomed creatures.
		"double_damage_creature_types": ["fire_using", "hot_accustomed"],
		"opaque": false,
		"requires_solid_surface": true,
	}

	return {
		"applied": true,
		"wall_segments": wall_segments,
		"wall_profile": wall_profile,
		"caster_id": caster_context.caster_id,
		"spell_key": spell_choice.spell_key if spell_choice != null else "wall_of_ice",
		"persist_metadata": {
			"wall_profile": wall_profile,
		},
	}
