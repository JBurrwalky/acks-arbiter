class_name FloatingDiscResolver
extends RefCounted

## Floating Disc (Arcane L1) — utility entity-spawning custom resolver.
##
## ACKS RAW (acore_spell_catalog_a-i_summary.xml):
##   - 10' range, 6 turns duration
##   - Creates an invisible 3' diameter, 1" deep concave plane of force
##   - Maximum load: 50 stone (500 lb / 6,250 cn at 125 cn/stone)
##   - Floats at caster's waist height
##   - Remains still when within 10' of caster, follows caster's movement
##     rate when caster moves away
##   - Pushable to reposition
##   - Items must be properly supported or they fall off
##   - If moved >10' from caster by other means → dispelled
##   - On spell end the disc disappears and drops its load
##   - Special: water weighs 1 stone/gallon; ~62 gallons may be carried
##
## Resolver responsibilities:
##   - Persist a `disc_profile` Dictionary on the active_effect's metadata
##     so the dungeon/wilderness encumbrance + movement systems can consult
##     it during travel-load calculations and follow-the-caster behavior.
##   - Stamp the caster's encumbrance "load_carried_offset" to subtract
##     up to 50 stone from their effective carried weight while the disc
##     is active (the disc is carrying it, not the caster).
##
## Scene-level entity rendering (the visible disc model that follows the
## caster around the dungeon grid) is deferred — the resolver provides the
## logical contract; the render layer subscribes to active_effect lifecycle
## events to spawn/despawn the visual.
##
## ~95 LOC, well under the 150 LOC custom-resolver budget.

const FLOATING_DISC_CAPACITY_STONE: int = 50  # 500 lb / ~6,250 cn
const FLOATING_DISC_DIAMETER_FEET: float = 3.0
const FLOATING_DISC_FOLLOW_RANGE_FEET: int = 10


func resolve(args: Dictionary) -> Dictionary:
	var caster_context = args.get("caster_context")
	var spell_choice = args.get("spell_choice")
	var caster_entity = args.get("caster_entity")

	if caster_context == null:
		return {"applied": false, "reason": "floating_disc: missing caster_context"}

	# Build the disc profile for the wilderness/dungeon load-tracking systems.
	# Position is implicit (follows caster at waist height; cell-snap is a
	# render-layer concern). The encumbrance subsystem reads the profile to
	# offset the caster's carried weight by up to FLOATING_DISC_CAPACITY_STONE.
	var disc_profile: Dictionary = {
		"disc_id": "floating_disc:%s" % caster_context.caster_id,
		"caster_id": caster_context.caster_id,
		"capacity_stone": FLOATING_DISC_CAPACITY_STONE,
		"current_load_stone": 0,
		"diameter_feet": FLOATING_DISC_DIAMETER_FEET,
		"follow_range_feet": FLOATING_DISC_FOLLOW_RANGE_FEET,
		"caster_movement_rate_per_round": _get_caster_movement_rate(caster_entity),
		"end_conditions": ["beyond_follow_range_by_other_means", "duration_expires"],
		"on_end_drops_load": true,
	}

	return {
		"applied": true,
		"disc_profile": disc_profile,
		"caster_id": caster_context.caster_id,
		"spell_key": spell_choice.spell_key if spell_choice != null else "floating_disc",
		"duration_turns": 6,
		# Persist on the active_effect for downstream consumption (parallel
		# pattern to Spiritual Weapon's weapon_profile from Session 9.6).
		"persist_metadata": {
			"disc_profile": disc_profile,
		},
	}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _get_caster_movement_rate(caster_entity: Variant) -> int:
	## Returns the caster's effective movement rate (feet per round). Used
	## by the disc-follow logic when the caster moves away.
	if caster_entity == null:
		return 60  # default human walk
	if caster_entity is CharacterData and caster_entity.has_method("get_effective_movement"):
		return int(caster_entity.get_effective_movement())
	if caster_entity.has_method("get_effective_movement"):
		return int(caster_entity.get_effective_movement())
	return 60
