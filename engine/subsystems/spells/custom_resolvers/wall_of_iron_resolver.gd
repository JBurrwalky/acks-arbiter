class_name WallOfIronResolver
extends RefCounted

## Wall of Iron (Arcane L6) — permanent flat iron wall, may tip and fall.
##
## ACKS RAW (acore_spell_catalog_k-w_summary.xml):
##   - 60' range, permanent.
##   - Normally 1" thick + up to 1,000 sq ft; thicker reduces area proportionally.
##   - May bond to surrounding nonliving material (caster's choice, sufficient area).
##   - May be created upright but unattached → can tip and fall.
##   - Tipping: random 50/50 direction unless creatures push it.
##   - Open Doors throw to push direction.
##   - Creatures with room to flee may save vs Blast to escape.
##   - Ogre-size or smaller failed save → 10d6 damage.
##   - Cannot be less than 1" thick.
##   - Cannot appear where objects/creatures already are.
##   - Always flat plane.
##   - Edges may be shaped to fit available space.
##   - Cannot crush larger-than-ogre creatures.
##   - Permanent unless destroyed or dispel magic.
##   - As ordinary iron, subject to rust, perforation, etc.
##
## Resolver responsibilities:
##   - Validate area cap (≤1000 sq ft @ 1" thick; reduce for thicker walls).
##   - Persist wall_profile with bonded / upright_unattached config + tipping rules.
##   - Tipping resolution + crush damage are consumer-side (combat hooks on tip).
##
## ~95 LOC.

const MAX_AREA_AT_1IN_THICK: int = 1000
const CELL_AREA_SQUARE_FEET: int = 25
const CRUSH_DAMAGE_DICE: String = "10d6"


func resolve(args: Dictionary) -> Dictionary:
	var caster_context = args.get("caster_context")
	var target_descriptor = args.get("target_descriptor")
	var spell_choice = args.get("spell_choice")
	var step_payload: Dictionary = args.get("step_payload", {})
	var resolver_args: Dictionary = step_payload.get("resolver_args", {})

	if caster_context == null or target_descriptor == null:
		return {"applied": false, "reason": "wall_of_iron_resolver: missing context"}

	var wall_segments: Array = resolver_args.get("wall_segments", target_descriptor.target_cells)
	if wall_segments == null:
		wall_segments = []

	# Thickness scaling: max area inversely proportional to thickness.
	# Default 1" → 1000 sq ft. 2" → 500. 4" → 250. etc.
	var thickness_inches: int = max(1, int(resolver_args.get("thickness_inches", 1)))
	var effective_max: int = int(MAX_AREA_AT_1IN_THICK / thickness_inches)
	var requested_area: int = wall_segments.size() * CELL_AREA_SQUARE_FEET

	if requested_area > effective_max:
		return {
			"applied": false,
			"reason": "wall_area_exceeds_max",
			"requested_area": requested_area,
			"effective_max": effective_max,
			"thickness_inches": thickness_inches,
		}

	var bonded := bool(resolver_args.get("bonded_to_surroundings", false))
	var upright_unattached := bool(resolver_args.get("upright_unattached", true))

	var wall_profile: Dictionary = {
		"wall_id": "wall_of_iron:%s" % caster_context.caster_id,
		"wall_type": "iron",
		"caster_id": caster_context.caster_id,
		"caster_level": caster_context.caster_level,
		"wall_segments": wall_segments,
		"thickness_inches": thickness_inches,
		"area_square_feet": requested_area,
		"effective_max_area": effective_max,
		"bonded_to_surroundings": bonded,
		"upright_unattached": upright_unattached and not bonded,
		"can_tip_and_fall": upright_unattached and not bonded,
		"tipping_direction_50_50_unless_pushed": true,
		"push_resolution": "open_doors_proficiency_throw",
		"crush_damage_dice": CRUSH_DAMAGE_DICE,
		"crush_save_category": "blast",
		"crush_size_cap": "ogre",
		"subject_to_rust_and_perforation": true,
		"banishable_by": ["dispel_magic", "physical_destruction"],
		"permanent": true,
	}

	return {
		"applied": true,
		"wall_segments": wall_segments,
		"wall_profile": wall_profile,
		"caster_id": caster_context.caster_id,
		"spell_key": spell_choice.spell_key if spell_choice != null else "wall_of_iron",
		"persist_metadata": {
			"wall_profile": wall_profile,
		},
	}
