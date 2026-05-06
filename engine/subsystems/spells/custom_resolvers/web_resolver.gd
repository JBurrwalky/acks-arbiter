class_name WebResolver
extends RefCounted

## Web (Arcane L2) — first wall-style spell custom resolver.
##
## ACKS RAW (acore_spell_catalog_k-w_summary.xml):
##   - 10' range, 48 turns duration
##   - 10' × 10' × 10' cube of sticky strands
##   - Creatures in the area become entangled (cannot move or run/charge)
##   - Attacking a creature in the web does NOT entangle the attacker;
##     moving through the area DOES
##   - Strands are flammable — if ignited, creatures inside take fire damage
##     for 2 rounds then are freed if they survive
##   - Escape time by strength category:
##       Normal/weak    → 2d4 turns
##       STR 13-17      → 1 turn
##       STR 18+        → 4 rounds
##       Giant/great    → 2 rounds
##
## Resolver responsibilities:
##   - Apply `webbed` condition to every creature in the cube
##   - Compute escape_rounds for each entangled creature (stored in metadata
##     so future polish can tick it down)
##   - Return per-target outcomes for the resolver pipeline
##
## ~85 LOC, well under the 150 LOC custom-resolver budget.

const STR_CATEGORY_GIANT_THRESHOLD: int = 19   # STR 19+ counts as "giant strength"
const STR_CATEGORY_STRONG_THRESHOLD: int = 18  # STR 18 = exceptional
const STR_CATEGORY_BRAWNY_LOW: int = 13        # STR 13-17 = strong


func resolve(args: Dictionary) -> Dictionary:
	var target_descriptor = args.get("target_descriptor")
	var targets_by_id: Dictionary = args.get("targets_by_id", {})
	var caster_context = args.get("caster_context")
	var spell_choice = args.get("spell_choice")

	if target_descriptor == null:
		return {"applied": false, "reason": "web_resolver: missing target_descriptor"}

	var per_target: Dictionary = {}
	var entangled_ids: Array = []
	for tid in target_descriptor.target_ids:
		var entity = targets_by_id.get(tid, null)
		var escape_rounds: int = _compute_escape_rounds(entity)
		# Apply webbed condition through the standard entity API.
		if entity != null and entity.has_method("add_condition"):
			entity.add_condition("webbed")
			entangled_ids.append(tid)
			per_target[tid] = {
				"applied": true,
				"condition_key": "webbed",
				"escape_rounds": escape_rounds,
				"strength_category": _describe_strength(_get_strength(entity)),
			}
		else:
			per_target[tid] = {"applied": false, "reason": "no add_condition method"}

	return {
		"applied": true,
		"per_target": per_target,
		"entangled_ids": entangled_ids,
		"area_cells": target_descriptor.target_cells,
		"caster_id": caster_context.caster_id if caster_context != null else "",
		"spell_key": spell_choice.spell_key if spell_choice != null else "web",
		"flammable": true,
	}


# ---------------------------------------------------------------------------
# Strength-based escape time per RAW
# ---------------------------------------------------------------------------

static func _compute_escape_rounds(entity: Variant) -> int:
	## Returns escape time in rounds. RAW is in mixed turns + rounds; we
	## normalize to rounds for the active_effect tick. 1 turn = 60 rounds
	## (Timekeeping ROUNDS_PER_TURN). Giant strength frees in 2 rounds.
	var strength: int = _get_strength(entity)
	if strength >= STR_CATEGORY_GIANT_THRESHOLD:
		return 2
	if strength >= STR_CATEGORY_STRONG_THRESHOLD:
		return 4
	if strength >= STR_CATEGORY_BRAWNY_LOW:
		return 60  # 1 turn = 60 rounds
	# Normal human / weaker: 2d4 turns. Use the average (5 turns = 300 rounds).
	# A future polish can roll this per-creature for variance.
	return 300


static func _get_strength(entity: Variant) -> int:
	if entity == null:
		return 9  # average human
	if entity is CharacterData:
		return int(entity.get_effective_ability_score("strength")) \
			if entity.has_method("get_effective_ability_score") \
			else int(entity.strength)
	if entity.has_method("get_effective_ability_score"):
		return int(entity.get_effective_ability_score("strength"))
	# Monsters: assume normal-strength bracket unless explicitly exceptional.
	return 9


static func _describe_strength(strength: int) -> String:
	if strength >= STR_CATEGORY_GIANT_THRESHOLD:
		return "giant"
	if strength >= STR_CATEGORY_STRONG_THRESHOLD:
		return "exceptional"
	if strength >= STR_CATEGORY_BRAWNY_LOW:
		return "strong"
	return "normal"
