class_name DeathSpellResolver
extends RefCounted

## Death Spell (Arcane L6) — kills HD-budget of low-HD creatures.
##
## ACKS RAW (acore_spell_catalog_a-i_summary.xml):
##   - 240' range, instantaneous, 30' radius sphere centered anywhere within range.
##   - Kills up to 4d8 HD of creatures.
##   - If more HD present than can be killed, WEAKEST creatures die first.
##   - Hit Dice insufficient to affect a creature are wasted.
##   - Save vs Death may avoid (each affected creature).
##   - Creatures with 8+ HD/levels are IMMUNE.
##   - Undead, golems, and any creature not truly alive are IMMUNE.
##
## Resolver responsibilities:
##   - Roll 4d8 to compute HD budget.
##   - Sort eligible targets (HD < 8, alive) by HD ascending.
##   - Walk targets: roll save vs Death; on fail, attempt to spend HD; if budget
##     covers the cost, mark dead and decrement budget.
##   - Persist kill_log per target.
##
## ~95 LOC.


func resolve(args: Dictionary) -> Dictionary:
	var caster_context = args.get("caster_context")
	var target_descriptor = args.get("target_descriptor")
	var targets_by_id: Dictionary = args.get("targets_by_id", {})
	var spell_choice = args.get("spell_choice")
	var step_payload: Dictionary = args.get("step_payload", {})
	var resolver_args: Dictionary = step_payload.get("resolver_args", {})
	var dice = resolver_args.get("dice", null)

	if caster_context == null or target_descriptor == null:
		return {"applied": false, "reason": "death_spell_resolver: missing context"}

	# Roll 4d8 HD budget.
	var hd_budget: int = 16  # default average (4 * 4.5 ≈ 18; use 16 for headless)
	if dice != null:
		var r = dice.roll_expression("4d8", "spell_death_spell_budget")
		hd_budget = int(r.modified_total) if r != null else 16

	# Build eligible target list with HD lookup; filter immune (8+ HD, undead, golem).
	var eligible: Array = []
	for tid in target_descriptor.target_ids:
		var entity = targets_by_id.get(tid, null)
		if entity == null:
			continue
		var hd: int = 1
		if entity.has_method("get_hit_dice"):
			hd = int(entity.get_hit_dice())
		elif "hit_dice" in entity:
			hd = int(entity.hit_dice)
		elif "level" in entity:
			hd = int(entity.level)
		if hd >= 8:
			continue
		# Type filter — undead/golem immune. Picker should pre-filter; we
		# accept a creature_type string if exposed.
		var ctype: String = ""
		if "creature_type" in entity:
			ctype = String(entity.creature_type).to_lower()
		if ctype in ["undead", "golem", "construct"]:
			continue
		eligible.append({"id": tid, "entity": entity, "hd": hd})

	# Sort eligible by HD ascending — weakest first per RAW.
	eligible.sort_custom(func(a, b): return int(a["hd"]) < int(b["hd"]))

	# Walk targets, spending HD budget.
	var per_target: Dictionary = {}
	var killed_ids: Array = []
	var hd_spent: int = 0
	for entry in eligible:
		var tid: String = entry["id"]
		var entity = entry["entity"]
		var cost: int = max(1, int(entry["hd"]))
		if hd_spent + cost > hd_budget:
			per_target[tid] = {"applied": false, "reason": "out_of_budget", "hd": cost}
			continue
		# Save vs Death roll.
		var save_target: int = 17
		if entity.has_method("get_effective_save"):
			save_target = int(entity.get_effective_save("save_poison_death"))
		var saved: bool = true
		if dice != null:
			var sr = dice.roll_digital(20, 1, 0, "spell_save_death_spell")
			saved = int(sr.modified_total) >= save_target
		if saved:
			per_target[tid] = {"applied": false, "reason": "saved", "hd": cost}
			continue
		# Failed save — kill via add_condition (consumer-side cleanup).
		hd_spent += cost
		killed_ids.append(tid)
		if entity.has_method("add_condition"):
			entity.add_condition("dispel_destroyed")
		per_target[tid] = {"applied": true, "outcome": "killed", "hd_cost": cost}

	return {
		"applied": true,
		"hd_budget": hd_budget,
		"hd_spent": hd_spent,
		"per_target": per_target,
		"killed_ids": killed_ids,
		"caster_id": caster_context.caster_id,
		"spell_key": spell_choice.spell_key if spell_choice != null else "death_spell",
	}
