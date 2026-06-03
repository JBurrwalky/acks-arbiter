class_name HornOfBlastingResolver
extends RefCounted

## Horn of Blasting (misc magic item, ACKS Core p.215+, Jedidiah-supplied
## RAW 2026-06-02). Used as the custom resolver for the horn_blast spell
## entry to which the Horn of Blasting item binds.
##
## RAW: "This horn appears to be a normal trumpet. When the instrument is
## played, once per turn it deals 2d6 points of damage to creatures within
## a cone 100' long and 20' wide at its termination point. The horn causes
## creatures to be deafened for 2d6 rounds (a saving throw versus Blast
## negates the deafening). Other objects may take damage in other ways, at
## the Judge's discretion. For example, a small hut might be completely
## leveled with a blast from the horn, but a portion of stone wall 10'
## wide might take three or four horn blasts. The horn may be blown once
## per turn."
##
## Resolver responsibilities:
##   - Apply 2d6 damage (no save vs damage) to each target in the cone.
##   - For each damaged target, roll save vs Blast; on FAIL apply the
##     `deafened` condition for 2d6 rounds; on SUCCESS no deafening.
##   - Object damage is Judge discretion and not enforced here.
##   - Once-per-turn limit is enforced by the catalog's default_charges=1
##     + misc_magic_consumable=false; refill fires from
##     `OncePerTurnRechargeService.recharge_for_campaign` on each
##     Timekeeping.turn_advanced (wired in SessionRunner._ready, 2026-06-03).
##     After one blast the Horn refuses subsequent activations until the
##     next 10-minute turn boundary; tests cover the round-trip use →
##     refused → tick → re-use.
##
## The cone target geometry (100' long × 20' wide at end) lives in the
## spell catalog's target_spec; the resolver receives the resolved
## target_ids in `target_descriptor.target_ids`.


func resolve(args: Dictionary) -> Dictionary:
	var caster_context = args.get("caster_context")
	var target_descriptor = args.get("target_descriptor")
	var targets_by_id: Dictionary = args.get("targets_by_id", {})
	var spell_choice = args.get("spell_choice")
	var step_payload: Dictionary = args.get("step_payload", {})
	var resolver_args: Dictionary = step_payload.get("resolver_args", {})
	# Tests inject a fake dice via resolver_args; production reads
	# args.dice forwarded from CastingResolver._dispatch_custom.
	var dice = resolver_args.get("dice", args.get("dice", null))

	if caster_context == null or target_descriptor == null:
		return {"applied": false, "reason": "horn_of_blasting_resolver: missing context"}

	var per_target: Dictionary = {}
	for tid in target_descriptor.target_ids:
		var entity = targets_by_id.get(tid, null)
		per_target[tid] = _resolve_single_target(entity, tid, dice)

	return {
		"applied": true,
		"per_target": per_target,
		"caster_id": caster_context.caster_id,
		"spell_key": spell_choice.spell_key if spell_choice != null else "horn_blast",
		"persist_metadata": {
			"horn_of_blasting_blast": true,
			"cone_length_feet": 100,
			"cone_width_feet": 20,
		},
	}


func _resolve_single_target(entity: Variant, target_id: String, dice: Variant) -> Dictionary:
	if entity == null:
		return {"applied": false, "reason": "target_not_found"}

	# (A) Damage step — 2d6, no save (the horn's blast damage is unsaveable
	# per RAW; only the deafening side-effect allows a save).
	var damage: int = 7  # 2d6 expected value default when no dice
	if dice != null:
		var r = dice.roll_expression("2d6", "horn_of_blasting_damage")
		damage = int(r.modified_total) if r != null else damage
	if entity.has_method("apply_damage"):
		entity.apply_damage(damage, "sonic", "horn_of_blasting")

	# (B) Deafening side-effect — save vs Blast/Breath negates; on fail
	# apply the `deafened` condition for 2d6 rounds.
	var save_target: int = 16
	if entity.has_method("get_effective_save"):
		save_target = int(entity.get_effective_save("save_blast_breath"))
	var save_roll: int = 16
	if dice != null:
		var r = dice.roll_digital(20, 1, 0, "save_blast_horn_of_blasting")
		save_roll = int(r.modified_total) if r != null else 0
	var saved: bool = save_roll >= save_target

	var deafen_duration: int = 7  # 2d6 expected default
	if dice != null:
		var rd = dice.roll_expression("2d6", "horn_of_blasting_deafen_duration")
		deafen_duration = int(rd.modified_total) if rd != null else deafen_duration

	var deafened_applied: bool = false
	if not saved and entity.has_method("add_condition"):
		entity.add_condition("deafened")
		deafened_applied = true

	return {
		"applied": true,
		"target_id": target_id,
		"damage_dealt": damage,
		"damage_type": "sonic",
		"deafening_save_roll": save_roll,
		"deafening_save_target": save_target,
		"deafening_saved": saved,
		"deafened_applied": deafened_applied,
		"deafen_duration_rounds": deafen_duration if deafened_applied else 0,
	}
