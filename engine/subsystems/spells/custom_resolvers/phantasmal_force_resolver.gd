class_name PhantasmalForceResolver
extends RefCounted

## Phantasmal Force (Arcane L2) — first illusion custom resolver.
##
## ACKS RAW (acore_spell_catalog_k-w_summary.xml):
##   - 240' range, concentration duration
##   - Up to 20'×20'×20' visual illusion (object, creature, or force)
##   - Caster moves the image within the area while concentrating
##   - Illusory creatures have AC 0 and disappear when hit
##   - If used to simulate an attack, deals illusory damage equal to the
##     normal damage of the simulated attack form
##   - Save vs Spells avoids all illusory damage (per viewer, on save success)
##   - Limits: no sound/smell/texture/temperature; illusory damage isn't real
##
## Resolver responsibilities:
##   - Roll save vs Spells per viewer in the target area
##   - Track per-viewer disbelief state (savers see through; failers are
##     affected by illusory damage if any)
##   - Return per-viewer outcomes for the resolver pipeline + an active_effect
##     payload the dungeon/combat layer can consume
##
## Note: the actual illusion entity (the image moving in the world) is a
## scene-level concern handled by the same scene that consumes the
## active_effect. This resolver handles the disbelief state machine.
##
## ~95 LOC, well under the 150 LOC custom-resolver budget.


func resolve(args: Dictionary) -> Dictionary:
	var target_descriptor = args.get("target_descriptor")
	var targets_by_id: Dictionary = args.get("targets_by_id", {})
	var caster_context = args.get("caster_context")
	var spell_choice = args.get("spell_choice")
	var step_payload: Dictionary = args.get("step_payload", {})

	if target_descriptor == null:
		return {"applied": false, "reason": "phantasmal_force: missing target_descriptor"}

	var save_target_default: int = 17
	var disbelief_by_viewer: Dictionary = {}
	for tid in target_descriptor.target_ids:
		var entity = targets_by_id.get(tid, null)
		var save_target: int = save_target_default
		if entity != null and entity.has_method("get_effective_save"):
			save_target = int(entity.get_effective_save("save_spells"))
		var rolled: int = _roll_save(args)
		var disbelieves: bool = rolled >= save_target
		disbelief_by_viewer[tid] = {
			"rolled": rolled,
			"target": save_target,
			"disbelieves": disbelieves,
		}

	# The illusion's payload — what the caster envisioned. Scene layer reads
	# this from the active_effect to render the appropriate visual.
	var illusion_payload: Dictionary = step_payload.get("illusion_payload", {})

	return {
		"applied": true,
		"per_viewer": disbelief_by_viewer,
		"caster_id": caster_context.caster_id if caster_context != null else "",
		"spell_key": spell_choice.spell_key if spell_choice != null else "phantasmal_force",
		"area_cells": target_descriptor.target_cells,
		"origin_cell": target_descriptor.origin_cell,
		"illusion_payload": illusion_payload,
		"concentration": true,
	}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _roll_save(args: Dictionary) -> int:
	## Pulls the dice system out of the casting resolver context if available.
	## Custom resolvers don't get the resolver directly; they roll via the
	## standard DiceSystem autoload when present. For tests, the args dict may
	## carry a `dice_override` key with a fixed roll value.
	if args.has("dice_override"):
		return int(args["dice_override"])
	# In a real cast, DiceSystem is the autoload.
	if Engine.has_singleton("DiceSystem"):
		var dice = Engine.get_singleton("DiceSystem")
		var roll = dice.roll_digital(20, 1, 0, "spell_save_phantasmal_force")
		return int(roll.modified_total) if roll != null else 10
	# Fallback: a deterministic mid-roll for headless tests.
	return 10
