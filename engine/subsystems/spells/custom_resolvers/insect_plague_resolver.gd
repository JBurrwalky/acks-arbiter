class_name InsectPlagueResolver
extends RefCounted

## Insect Plague (Divine L5) — controllable swarming insect plague.
##
## ACKS RAW (acore_spell_catalog_a-i_summary.xml):
##   - 480' range, 1 day duration.
##   - 4 contiguous insect swarms, each 30'×30', each 4 HD.
##   - Swarms must be placed adjacent so they fill one contiguous area.
##   - May be summoned in spaces already occupied by other creatures.
##   - Each swarm attacks creatures in its area.
##   - Whole plague obscures vision.
##   - Creatures with <3 HD are AUTOMATICALLY driven off (no save).
##   - Caster must concentrate to maintain control for full duration.
##   - Loss of control: caster successfully attacked OR plague leaves spell range.
##   - While controlled: swarms move 20'/round.
##   - Once control lost: swarms become STATIONARY.
##
## Resolver responsibilities:
##   - Validate swarm placements from resolver_args.swarm_cells (must be 4 swarms,
##     each cell representing a 30'×30' area).
##   - Persist plague_profile (4 swarms, contiguous_layout, control_state,
##     auto_drive_off_threshold=3, etc.).
##   - SpellCombatHooks consumes the plague_profile for per-round attacks +
##     auto-drive-off + control loss handling.
##
## ~95 LOC.


const SWARM_HD: int = 4
const SWARM_AREA_FEET: int = 30
const AUTO_DRIVE_OFF_HD_THRESHOLD: int = 3
const SWARM_MOVEMENT_FEET_PER_ROUND_WHILE_CONTROLLED: int = 20
const NUM_SWARMS: int = 4


func resolve(args: Dictionary) -> Dictionary:
	var caster_context = args.get("caster_context")
	var target_descriptor = args.get("target_descriptor")
	var spell_choice = args.get("spell_choice")
	var step_payload: Dictionary = args.get("step_payload", {})
	var resolver_args: Dictionary = step_payload.get("resolver_args", {})

	if caster_context == null or target_descriptor == null:
		return {"applied": false, "reason": "insect_plague_resolver: missing context"}

	# Swarm placements: array of 4 cells from picker (each cell = 30'×30' area).
	# Default: place at target origin if picker doesn't supply.
	var swarm_cells: Array = resolver_args.get("swarm_cells", [])
	if swarm_cells.is_empty() and target_descriptor.origin_cell != null:
		# Auto-place 4 swarms in a 2×2 pattern starting at origin_cell.
		var ox: int = target_descriptor.origin_cell.x
		var oy: int = target_descriptor.origin_cell.y
		swarm_cells = [
			Vector3i(ox, oy, 0), Vector3i(ox + 1, oy, 0),
			Vector3i(ox, oy + 1, 0), Vector3i(ox + 1, oy + 1, 0),
		]

	if swarm_cells.size() != NUM_SWARMS:
		return {
			"applied": false,
			"reason": "insect_plague: must have exactly %d swarms" % NUM_SWARMS,
			"received": swarm_cells.size(),
		}

	# Swarm type drives which `swarmed_<type>` condition the runtime applies
	# (insect / rat / bat). Insect Plague always summons insect swarms, but
	# resolver_args may override (e.g. for future swarm-summoning spells).
	var swarm_type := String(resolver_args.get("swarm_type", "insect")).to_lower()
	if swarm_type not in ["insect", "rat", "bat"]:
		swarm_type = "insect"

	var swarms: Array = []
	for i in range(NUM_SWARMS):
		swarms.append({
			"swarm_id": "swarm_%s_%d" % [caster_context.caster_id, i],
			"swarm_index": i,
			"swarm_cell": swarm_cells[i],
			"swarm_hd": SWARM_HD,
			"area_feet": SWARM_AREA_FEET,
			"swarm_type": swarm_type,
		})

	var plague_profile: Dictionary = {
		"plague_id": "insect_plague:%s" % caster_context.caster_id,
		"caster_id": caster_context.caster_id,
		"caster_level": caster_context.caster_level,
		"swarms": swarms,
		"swarm_type": swarm_type,
		"contiguous_layout": true,
		"control_state": "controlled",
		"auto_drive_off_hd_threshold": AUTO_DRIVE_OFF_HD_THRESHOLD,
		"obscures_vision": true,
		"swarm_movement_feet_per_round_controlled": SWARM_MOVEMENT_FEET_PER_ROUND_WHILE_CONTROLLED,
		"becomes_stationary_on_control_loss": true,
		"loses_control_on_caster_attacked": true,
		"loses_control_on_leaving_spell_range": true,
		"spell_range_feet": 480,
		"swarm_persistence": {},
	}

	return {
		"applied": true,
		"plague_profile": plague_profile,
		"swarms_count": swarms.size(),
		"caster_id": caster_context.caster_id,
		"spell_key": spell_choice.spell_key if spell_choice != null else "insect_plague",
		"persist_metadata": {
			"plague_profile": plague_profile,
		},
	}
