class_name WallOfStoneResolver
extends RefCounted

## Wall of Stone (Arcane L5) — permanent shaped stone wall.
##
## ACKS RAW (acore_spell_catalog_k-w_summary.xml):
##   - 60' range, permanent until dispel/destroy.
##   - Up to 1,000 cubic feet.
##   - May take almost any shape; can be bridge, ramp, structure.
##   - Can be crudely shaped with crenellations, battlements.
##   - Cannot appear where objects/creatures already are.
##   - Must rest on a solid surface.
##   - Non-vertical / unsupported forms must merge with + be supported by
##     existing stone.
##   - Spans >20': must be arched + buttressed → effective area halved.
##   - Crenellations / shaping reduce area further.
##
## Resolver responsibilities:
##   - Validate volume cap (≤1000 cubic feet).
##   - Apply span / shaping reductions.
##   - Persist wall_profile (segments, shape_type, cubic_feet, support tags).
##   - Persistent: no duration tick; only dispel_magic or physical destruction.
##
## ~85 LOC.

const MAX_VOLUME_CUBIC_FEET: int = 1000
const CELL_VOLUME_CUBIC_FEET: int = 125  # 5'x5'x5' cell


func resolve(args: Dictionary) -> Dictionary:
	var caster_context = args.get("caster_context")
	var target_descriptor = args.get("target_descriptor")
	var spell_choice = args.get("spell_choice")
	var step_payload: Dictionary = args.get("step_payload", {})
	var resolver_args: Dictionary = step_payload.get("resolver_args", {})

	if caster_context == null or target_descriptor == null:
		return {"applied": false, "reason": "wall_of_stone_resolver: missing context"}

	var wall_segments: Array = resolver_args.get("wall_segments", target_descriptor.target_cells)
	if wall_segments == null:
		wall_segments = []

	# Volume budget check (with span/shaping reductions).
	var span_feet: int = int(resolver_args.get("span_feet", 0))
	var has_shaping: bool = bool(resolver_args.get("has_crenellations", false))
	var requested_volume: int = wall_segments.size() * CELL_VOLUME_CUBIC_FEET
	var effective_max: int = MAX_VOLUME_CUBIC_FEET
	if span_feet > 20:
		# Spans >20' must be arched + buttressed → effective area halved.
		effective_max /= 2
	if has_shaping:
		# Crenellations / shaping further reduce — apply 25% reduction.
		effective_max = int(effective_max * 0.75)

	if requested_volume > effective_max:
		return {
			"applied": false,
			"reason": "wall_volume_exceeds_max",
			"requested_volume": requested_volume,
			"effective_max": effective_max,
			"span_feet": span_feet,
			"has_crenellations": has_shaping,
		}

	var wall_profile: Dictionary = {
		"wall_id": "wall_of_stone:%s" % caster_context.caster_id,
		"wall_type": "stone",
		"caster_id": caster_context.caster_id,
		"caster_level": caster_context.caster_level,
		"wall_segments": wall_segments,
		"cubic_feet": requested_volume,
		"effective_max_volume": effective_max,
		"span_feet": span_feet,
		"has_crenellations": has_shaping,
		"shape_type": String(resolver_args.get("shape_type", "wall")),
		"requires_solid_surface": true,
		"merges_with_stone": true,
		"banishable_by": ["dispel_magic", "physical_destruction"],
		"permanent": true,
	}

	return {
		"applied": true,
		"wall_segments": wall_segments,
		"wall_profile": wall_profile,
		"caster_id": caster_context.caster_id,
		"spell_key": spell_choice.spell_key if spell_choice != null else "wall_of_stone",
		"persist_metadata": {
			"wall_profile": wall_profile,
		},
	}
