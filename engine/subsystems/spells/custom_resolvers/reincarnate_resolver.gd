class_name ReincarnateResolver
extends RefCounted

## Reincarnate (Arcane L6) — returns dead character in newly created body.
##
## ACKS RAW (acore_spell_catalog_k-w_summary.xml):
##   - Touch range, instantaneous.
##   - Returns dead character to life in newly created young adult body.
##   - All physical ills / afflictions repaired.
##   - Body condition doesn't matter so long as some small portion still exists.
##   - Roll on Reincarnation table to determine new form.
##   - Reincarnated character recalls most of former life and form.
##   - If human/demi-human result: same class level w/ minimum XP, keep INT/WIS/CHA,
##     reroll STR/DEX/CON.
##   - If monster result: roll on alignment-appropriate column; gain abilities of
##     new form; doesn't auto-know language; HD raised to former class level if lower.
##
## Resolver responsibilities:
##   - Verify body presence (resolver_args.body_present).
##   - Roll on reincarnation_table (resolver_args.dice).
##   - Persist reincarnation_outcome (new_form, new_form_kind, ability_score_changes).
##   - Actual identity rebuild is consumer-side (character_subsystem reads outcome).
##
## ~95 LOC. Reincarnation table itself is a stub here — picker/runtime resolves.


func resolve(args: Dictionary) -> Dictionary:
	var caster_context = args.get("caster_context")
	var target_descriptor = args.get("target_descriptor")
	var targets_by_id: Dictionary = args.get("targets_by_id", {})
	var spell_choice = args.get("spell_choice")
	var step_payload: Dictionary = args.get("step_payload", {})
	var resolver_args: Dictionary = step_payload.get("resolver_args", {})
	var dice = resolver_args.get("dice", null)

	if caster_context == null or target_descriptor == null:
		return {"applied": false, "reason": "reincarnate_resolver: missing context"}

	var per_target: Dictionary = {}
	for tid in target_descriptor.target_ids:
		var entity = targets_by_id.get(tid, null)
		var body_present := bool(resolver_args.get("body_present", true))
		if not body_present:
			per_target[tid] = {
				"applied": false, "reason": "no_body_remnant_present"}
			continue
		# Roll d10 for the new-form table; default to "human" on no-dice (slot 1).
		var roll_d10: int = 1
		if dice != null:
			var r = dice.roll_digital(10, 1, 0, "spell_reincarnate_form")
			roll_d10 = int(r.modified_total) if r != null else 1
		# Picker / character subsystem owns the actual table lookup; resolver
		# records the roll + alignment context for downstream consumption.
		var alignment := "neutral"
		if entity != null and "alignment" in entity:
			alignment = String(entity.alignment)
		var outcome: Dictionary = {
			"applied": true,
			"reincarnation_roll": roll_d10,
			"reincarnation_alignment_column": alignment,
			"new_form_kind_pending_table_lookup": true,
			"reroll_str_dex_con": true,
			"keep_int_wis_cha": true,
			"min_xp_for_class_level": true,
			"recalls_former_life": true,
		}
		per_target[tid] = outcome

	return {
		"applied": true,
		"per_target": per_target,
		"caster_id": caster_context.caster_id,
		"spell_key": spell_choice.spell_key if spell_choice != null else "reincarnate",
	}
