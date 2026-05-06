class_name DispelEvilResolver
extends RefCounted

## Dispel Evil (Divine L5) — destroys/repels undead and enchanted creatures.
##
## ACKS RAW (acore_spell_catalog_a-i_summary.xml):
##   - 30' range, 1 turn duration.
##   - Two modes: area (default) or single-target.
##   - Area: undead + enchanted creatures entering within 30' must save vs Death
##     or be destroyed.
##   - On successful save: such creatures FLEE the affected area.
##   - Single-target mode: that monster saves at -2.
##   - Caster must take no other action and concentrate for entire duration.
##   - Special: casting on unholy place / shrine may rid evil (Judge discretion).
##   - May remove cursed item from being within range; doing so DISCHARGES + ends spell.
##
## Resolver responsibilities:
##   - Determine mode from resolver_args.target_mode ("area" or "single").
##   - For each target: identify undead/enchanted; roll save vs Death (-2 if single).
##   - Failed save → destroyed; succeeded save → fleeing flag applied.
##   - Concentration-required active_effect; loss → spell ends.
##
## ~95 LOC.


func resolve(args: Dictionary) -> Dictionary:
	var caster_context = args.get("caster_context")
	var target_descriptor = args.get("target_descriptor")
	var targets_by_id: Dictionary = args.get("targets_by_id", {})
	var spell_choice = args.get("spell_choice")
	var step_payload: Dictionary = args.get("step_payload", {})
	var resolver_args: Dictionary = step_payload.get("resolver_args", {})

	if caster_context == null or target_descriptor == null:
		return {"applied": false, "reason": "dispel_evil_resolver: missing context"}

	var target_mode := String(resolver_args.get("target_mode", "area"))
	var save_modifier: int = -2 if target_mode == "single" else 0

	var per_target: Dictionary = {}
	var destroyed_ids: Array = []
	var fleeing_ids: Array = []
	for tid in target_descriptor.target_ids:
		var entity = targets_by_id.get(tid, null)
		# Per RAW: only undead + enchanted-creature types are valid targets.
		# We accept any entity passed (picker validates type) but record the
		# type assertion for log clarity.
		var save_target: int = 17  # default; entity may override
		if entity != null and entity.has_method("get_effective_save"):
			save_target = int(entity.get_effective_save("save_poison_death"))
		# Save roll proxied through the args.dice if injected; fallback fixed.
		var dice = resolver_args.get("dice", null)
		var roll: int = 17  # default = save succeeds at boundary
		if dice != null:
			var r = dice.roll_digital(20, 1, save_modifier, "spell_save_dispel_evil")
			roll = int(r.modified_total) if r != null else 0
		var saved: bool = roll >= save_target
		if saved:
			fleeing_ids.append(tid)
			# Apply fleeing flag if the entity supports it.
			if entity != null and "flags" in entity:
				entity.flags.set_flag("fleeing_dispel_evil", "spell:dispel_evil:%s" % caster_context.caster_id, {
					"caster_id": caster_context.caster_id, "ends_with_spell": true})
			per_target[tid] = {"applied": true, "outcome": "fleeing", "save_roll": roll, "save_target": save_target}
		else:
			destroyed_ids.append(tid)
			# Apply destroyed via add_condition (the destruction routine is
			# consumer-side; we tag the entity as 'dispel_destroyed').
			if entity != null and entity.has_method("add_condition"):
				entity.add_condition("dispel_destroyed")
			per_target[tid] = {"applied": true, "outcome": "destroyed", "save_roll": roll, "save_target": save_target}

	return {
		"applied": true,
		"target_mode": target_mode,
		"per_target": per_target,
		"destroyed_ids": destroyed_ids,
		"fleeing_ids": fleeing_ids,
		"save_modifier": save_modifier,
		"caster_id": caster_context.caster_id,
		"spell_key": spell_choice.spell_key if spell_choice != null else "dispel_evil",
		"persist_metadata": {
			"dispel_evil_mode": target_mode,
		},
	}
