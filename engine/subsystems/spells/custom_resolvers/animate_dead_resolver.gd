class_name AnimateDeadResolver
extends RefCounted

## Animate Dead — divine L4 reverse of Smite Undead, also published as the L5
## Arcane spell of the same name (acore_spell_catalog_a-i_summary.xml line 64
## carries the catalog entry; the Smite Undead reversed_form points here).
##
## ACKS RAW (acore_spell_catalog_k-w_summary.xml — Smite Undead reversed_form,
## and acore_spell_catalog_a-i_summary.xml — Animate Dead summary):
##   - Touch range, special duration.
##   - Animates dead remains as obedient skeletons or zombies.
##   - Animate up to 2 × caster level Hit Dice of undead per casting.
##   - Skeletons and zombies obey the caster's commands until destroyed or
##     turned (Turn Undead) by a cleric of higher level.
##
## Resolver responsibilities:
##   - Compute HD-budget (caster_level × 2) and allocate to skeleton/zombie
##     stat blocks. Picker layer supplies the corpses-to-animate roster
##     (resolver_args.corpses); resolver enforces the budget.
##   - Spawn entities into the active combat roster / party reserve via the
##     spawn_request channel (consumed by the runtime layer).
##   - Persist the spawn_profile so the spawned entities' allegiance + leash
##     to the caster persists through the active_effect tracker.
##
## ~95 LOC.
##
## DEFERRED: dynamic HD scaling per source corpse. RAW says human and
## demi-human skeletons always have 1 HD regardless of the deceased
## character's level, while zombies have HD equal to (creature-in-life +1).
## For non-humanoid sources, both skeleton and zombie scale with the source
## corpse's HD. Today this resolver passes hd_cost through to the integrator
## but the spawned combatant uses the catalog's static skeleton (1 HD) /
## zombie (2 HD = humanoid case) template. Three options sketched in the
## plan:
##   A — per-corpse generation: resolver looks up the source corpse's HD,
##       computes new HD, and overrides HP / save_as.level / attack_throw
##       on the spawned combatant via a new
##       Combatant.from_monster_with_overrides path. Catalog stays small.
##   B — multi-entry catalog: skeleton_1hd, skeleton_2hd, ..., zombie_2hd,
##       zombie_3hd, .... Resolver picks by HD. Bloats catalog; matches the
##       elemental-tier multi-entry pattern.
##   C — template + scaling rule: catalog gains a `scaling: { drives:
##       ["hit_dice","save_as","attack_throw"], from: "source_hd" }` field;
##       Combatant.from_monster reads the rule and adjusts at spawn time.
## Recommend revisit after the elemental tier multi-entry pattern (option
## B equivalent) ships in production.


const HD_PER_CASTER_LEVEL: int = 2


func resolve(args: Dictionary) -> Dictionary:
	var caster_context = args.get("caster_context")
	var spell_choice = args.get("spell_choice")
	var step_payload: Dictionary = args.get("step_payload", {})
	var resolver_args: Dictionary = step_payload.get("resolver_args", {})

	if caster_context == null:
		return {"applied": false, "reason": "animate_dead_resolver: missing caster_context"}

	var hd_budget: int = caster_context.caster_level * HD_PER_CASTER_LEVEL
	# corpses_to_animate: array of dicts {corpse_id, undead_template, hd_cost}
	# Picker layer fills this from clicked corpses on the dungeon map.
	var corpses: Array = resolver_args.get("corpses_to_animate", [])

	# Allocate corpses to budget in submission order (picker may pre-sort).
	var animated: Array = []
	var hd_spent: int = 0
	for corpse_raw in corpses:
		if not (corpse_raw is Dictionary):
			continue
		var corpse: Dictionary = corpse_raw
		var hd_cost: int = int(corpse.get("hd_cost", 1))
		if hd_spent + hd_cost > hd_budget:
			# Budget exhausted; subsequent corpses rejected.
			continue
		hd_spent += hd_cost
		animated.append({
			"undead_id": "undead_animated:%s:%s" % [
				caster_context.caster_id, String(corpse.get("corpse_id", "anon"))],
			"corpse_id": String(corpse.get("corpse_id", "")),
			"undead_template": String(corpse.get("undead_template", "skeleton")),
			"hd_cost": hd_cost,
			"caster_id": caster_context.caster_id,
			"loyalty": "obedient_until_destroyed_or_turned",
		})

	var spawn_profile: Dictionary = {
		"caster_id": caster_context.caster_id,
		"caster_level": caster_context.caster_level,
		"hd_budget": hd_budget,
		"hd_spent": hd_spent,
		"animated": animated,
	}

	return {
		"applied": true,
		"spawn_profile": spawn_profile,
		"animated_count": animated.size(),
		"hd_budget": hd_budget,
		"hd_spent": hd_spent,
		"caster_id": caster_context.caster_id,
		"spell_key": spell_choice.spell_key if spell_choice != null else "animate_dead",
		"persist_metadata": {
			"animate_dead_spawn_profile": spawn_profile,
		},
	}
