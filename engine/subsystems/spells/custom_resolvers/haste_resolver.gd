class_name HasteResolver
extends RefCounted

## Haste / Slow (Arcane L3, reversible) — first speed-modification custom resolver.
##
## ACKS RAW (acore_spell_catalog_a-i_summary.xml):
##   Forward (Haste):
##     - 240' range, 3 turns duration
##     - 1 creature per caster level
##     - Movement rates double
##     - Attacks per round double
##     - Spellcasting NOT accelerated
##     - Magic items (wands etc.) still once per round
##     - Multiple haste/speed effects do NOT stack — apply only most powerful
##       or longest-lasting
##   Reversed (Slow):
##     - Movement at half speed
##     - Attacks half as often (every other round)
##     - Half-move per round
##   Interaction:
##     - Haste and Slow dispel each other
##
## NOTE on aging: the Sessions 2.9 → 19 roadmap §15.3 row 8 mentioned "Haste
## ages target by 1 year on every cast" — this is a 3.5e/Pathfinder rule, NOT
## ACKS RAW. The acore catalog does NOT include aging in the Haste effects
## list. Per CLAUDE.md SACRED-vs-GDD precedence, we follow ACKS — no aging
## mechanic. Documented as a deviation in the spell catalog notes.
##
## Resolver responsibilities:
##   - For each target, set is_hasted (forward) or is_slowed (reverse) flag
##     with metadata.movement_multiplier + metadata.attacks_multiplier
##   - Detect existing haste/slow effects on the target and dispel them per
##     RAW interaction (forward dispels existing slow; reverse dispels haste)
##   - Apply the appropriate movement_mode_grant / attack_speed modifier
##
## ~95 LOC, well under the 150 LOC budget.


func resolve(args: Dictionary) -> Dictionary:
	var target_descriptor = args.get("target_descriptor")
	var caster_context = args.get("caster_context")
	var spell_choice = args.get("spell_choice")
	var targets_by_id: Dictionary = args.get("targets_by_id", {})

	if target_descriptor == null or spell_choice == null:
		return {"applied": false, "reason": "haste_resolver: missing context"}

	var is_slowed_branch: bool = bool(spell_choice.is_reversed)
	var flag_to_set: String = "is_slowed" if is_slowed_branch else "is_hasted"
	var flag_to_dispel: String = "is_hasted" if is_slowed_branch else "is_slowed"
	var movement_multiplier: float = 0.5 if is_slowed_branch else 2.0
	var attacks_multiplier: float = 0.5 if is_slowed_branch else 2.0

	var per_target: Dictionary = {}
	for tid in target_descriptor.target_ids:
		var entity = targets_by_id.get(tid, null)
		if entity == null:
			per_target[tid] = {"applied": false, "reason": "no_target_data"}
			continue
		var entity_flags = entity.flags if "flags" in entity else null
		if entity_flags == null and entity.has_method("get_flags"):
			entity_flags = entity.get_flags()
		if entity_flags == null:
			per_target[tid] = {"applied": false, "reason": "no_flags"}
			continue

		# RAW interaction: Haste and Slow dispel each other. Clear opposite
		# before applying the new one.
		var dispelled_opposite: bool = entity_flags.has_flag(flag_to_dispel)
		if dispelled_opposite:
			# Remove ALL sources of the opposite flag (every Haste/Slow caster
			# that wrote to this entity loses their effect).
			var sources: Array = entity_flags.get_flag_sources(flag_to_dispel)
			for source_id in sources:
				entity_flags.clear_flag(flag_to_dispel, source_id)

		# Set the new flag with metadata.
		var source_id := "spell:%s:%s" % [
			spell_choice.spell_key,
			caster_context.caster_id if caster_context != null else "unknown"
		]
		entity_flags.set_flag(flag_to_set, source_id, {
			"movement_multiplier": movement_multiplier,
			"attacks_multiplier": attacks_multiplier,
			"caster_id": caster_context.caster_id if caster_context != null else "",
			"caster_level": caster_context.caster_level if caster_context != null else 1,
		})

		per_target[tid] = {
			"applied": true,
			"flag_set": flag_to_set,
			"movement_multiplier": movement_multiplier,
			"attacks_multiplier": attacks_multiplier,
			"dispelled_opposite": dispelled_opposite,
		}

	return {
		"applied": true,
		"per_target": per_target,
		"is_slow": is_slowed_branch,
		"caster_id": caster_context.caster_id if caster_context != null else "",
		"spell_key": spell_choice.spell_key,
	}
