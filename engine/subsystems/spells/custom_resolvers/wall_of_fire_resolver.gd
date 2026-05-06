class_name WallOfFireResolver
extends RefCounted

## Wall of Fire (Arcane L4) — persistent area-damage wall.
##
## ACKS RAW (acore_spell_catalog_k-w_summary.xml):
##   - 60' range, 2 turns duration.
##   - Up to 1,200 square feet; straight or curved into a protective circle.
##   - Immobile opaque wall of violet flame.
##   - Creatures with MORE than 4 HD take 1d6 damage when passing through.
##   - Impenetrable to monsters with FEWER than 4 HD (they cannot pass).
##   - Deals DOUBLE damage to undead and creatures that use cold or are
##     accustomed to cold.
##   - Cannot appear where objects or creatures already are.
##
## Resolver responsibilities:
##   - Record a `wall_segments` list (the targeting picker layer fills the
##     specific cells from a free-shaping placement; resolver_args.segments).
##   - Compute area total; reject if > 1200 sq ft.
##   - Persist wall_profile via persist_metadata so the round-tick / movement
##     subsystem can fire 1d6 fire damage when a creature crosses a segment.
##   - Round-tick consumption fires from SpellCombatHooks on_round_end (parallel
##     to Spiritual Weapon) — when a combatant's path crosses a segment cell,
##     the wall's damage triggers. Path-crossing detection is the consumer's
##     responsibility; resolver records the segments + damage profile.
##
## ~95 LOC.


const MAX_AREA_SQUARE_FEET: int = 1200
const CELL_AREA_SQUARE_FEET: int = 25  # 5'x5' cell standard


func resolve(args: Dictionary) -> Dictionary:
	var caster_context = args.get("caster_context")
	var target_descriptor = args.get("target_descriptor")
	var spell_choice = args.get("spell_choice")
	var step_payload: Dictionary = args.get("step_payload", {})
	var resolver_args: Dictionary = step_payload.get("resolver_args", {})

	if caster_context == null or target_descriptor == null:
		return {"applied": false, "reason": "wall_of_fire_resolver: missing context"}

	# Wall segments: array of cells the wall occupies. Resolved by the picker.
	var wall_segments: Array = resolver_args.get("wall_segments", target_descriptor.target_cells)
	if wall_segments == null:
		wall_segments = []

	# Reject if total area exceeds RAW cap.
	var total_area: int = wall_segments.size() * CELL_AREA_SQUARE_FEET
	if total_area > MAX_AREA_SQUARE_FEET:
		return {
			"applied": false,
			"reason": "wall_area_exceeds_max",
			"requested_area": total_area,
			"max_area": MAX_AREA_SQUARE_FEET,
		}

	var wall_profile: Dictionary = {
		"wall_id": "wall_of_fire:%s" % caster_context.caster_id,
		"wall_type": "fire",
		"caster_id": caster_context.caster_id,
		"caster_level": caster_context.caster_level,
		"wall_segments": wall_segments,
		"area_square_feet": total_area,
		"damage_dice": "1d6",
		"damage_type": "fire",
		# Per RAW: ≤4 HD creatures CANNOT pass; >4 HD take 1d6 on crossing.
		"min_hd_to_pass": 5,
		# Double damage to undead and cold-using creatures.
		"double_damage_creature_types": ["undead", "cold_using"],
		"opaque": true,
	}

	return {
		"applied": true,
		"wall_segments": wall_segments,
		"wall_profile": wall_profile,
		"caster_id": caster_context.caster_id,
		"spell_key": spell_choice.spell_key if spell_choice != null else "wall_of_fire",
		"persist_metadata": {
			"wall_profile": wall_profile,
		},
	}
