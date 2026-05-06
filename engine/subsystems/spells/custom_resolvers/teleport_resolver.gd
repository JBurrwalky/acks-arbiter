class_name TeleportResolver
extends RefCounted

## Teleport (Arcane L5) — long-range teleport with familiarity-based error.
##
## ACKS RAW (acore_spell_catalog_a-i_summary.xml):
##   - Touch range, instantaneous.
##   - Subject (carrying up to full encumbrance) transported to designated dest.
##   - On success: arrives at ground level in suitable open place.
##   - Save vs Spells negates if unwilling.
##   - Familiarity table (d% roll):
##       Very familiar     → on 01-95, off 96-99, lost 00
##       Studied carefully → on 01-80, off 81-90, lost 91-00
##       Seen casually     → on 01-50, off 51-75, lost 76-00
##       Viewed once       → on 01-20, off 21-60, lost 61-00
##   - Off-target into solid matter: subject INSTANTLY KILLED.
##   - Off-target above ground: takes falling damage.
##   - Lost subjects DO NOT REAPPEAR.
##   - Caster cannot intentionally teleport into thin air, off target, or solid.
##
## Resolver responsibilities:
##   - Roll d% against the familiarity threshold (resolver_args.familiarity).
##   - Determine outcome: on_target / off_target / lost.
##   - Record destination_cell (or scattered cell on off_target).
##   - Persist outcome on per_target so the runtime layer can apply movement +
##     damage / death effects.
##
## ~95 LOC.

const FAMILIARITY_TABLE: Dictionary = {
	"very_familiar":   {"on_max": 95, "off_max": 99},
	"studied":         {"on_max": 80, "off_max": 90},
	"seen_casually":   {"on_max": 50, "off_max": 75},
	"viewed_once":     {"on_max": 20, "off_max": 60},
}


func resolve(args: Dictionary) -> Dictionary:
	var caster_context = args.get("caster_context")
	var target_descriptor = args.get("target_descriptor")
	var spell_choice = args.get("spell_choice")
	var step_payload: Dictionary = args.get("step_payload", {})
	var resolver_args: Dictionary = step_payload.get("resolver_args", {})
	var dice = resolver_args.get("dice", null)

	if caster_context == null or target_descriptor == null:
		return {"applied": false, "reason": "teleport_resolver: missing context"}

	var familiarity := String(resolver_args.get("familiarity", "studied"))
	var thresholds: Dictionary = FAMILIARITY_TABLE.get(familiarity, FAMILIARITY_TABLE["studied"])
	var destination_cell: Vector3i = target_descriptor.origin_cell
	var per_target: Dictionary = {}

	for tid in target_descriptor.target_ids:
		# Roll d% (1-100). If no dice injected, default to "on_target" (50).
		var pct: int = 50
		if dice != null:
			var roll = dice.roll_digital(100, 1, 0, "spell_teleport_familiarity")
			pct = int(roll.modified_total) if roll != null else 50
		var outcome_kind := "on_target"
		var actual_dest: Vector3i = destination_cell
		if pct <= int(thresholds["on_max"]):
			outcome_kind = "on_target"
		elif pct <= int(thresholds["off_max"]):
			outcome_kind = "off_target"
			# Off target: scatter 1d10 cells; runtime layer determines whether
			# this lands in solid matter (instant kill) or above ground (fall).
			if dice != null:
				var sx = int(dice.roll_digital(10, 1, -5, "spell_teleport_off_dx").modified_total)
				var sy = int(dice.roll_digital(10, 1, -5, "spell_teleport_off_dy").modified_total)
				actual_dest += Vector3i(sx, sy, 0)
		else:
			outcome_kind = "lost"
		per_target[tid] = {
			"applied": outcome_kind != "lost",
			"outcome_kind": outcome_kind,
			"destination_cell": actual_dest,
			"familiarity": familiarity,
			"familiarity_roll": pct,
			"target_id": tid,
		}

	return {
		"applied": true,
		"per_target": per_target,
		"familiarity": familiarity,
		"caster_id": caster_context.caster_id,
		"spell_key": spell_choice.spell_key if spell_choice != null else "teleport",
	}
