class_name SticksToSnakesResolver
extends RefCounted

## Sticks to Snakes (Divine L4) — transmutes sticks into commanded snakes.
##
## ACKS RAW (acore_spell_catalog_k-w_summary.xml) + project design layer:
##   - 120' range, 6 turns duration.
##   - Targets: normal wooden sticks. Project-defined eligible weapon list
##     (`eligible_stick_types`, see below).
##   - Transforms 2d8 sticks per every 4 caster levels.
##   - Caster picks ONE snake species per cast (`spitting_cobra` or
##     `pit_viper`). 50% per-snake chance the species' poison is disabled
##     (project rule — covers cobra spit poison too).
##   - Snakes spawn as close to the original item's owner as legally possible
##     and act immediately after the caster's initiative tick on the cast round.
##   - Snakes are blue-team (PARTY-side, AI-controlled) for now; 3rd-party
##     allegiance category is a future migration target.
##   - When snakes are slain, dispelled, or the spell expires, they revert to
##     their original stick form (resolver persists the removed-stick snapshot
##     so the integrator's expiration callback can restore the right items).
##
## Resolver responsibilities:
##   - Compute snake count.
##   - Per snake, roll 50% poison-disabled coin (replaces the previous
##     boolean `poisonous` field).
##   - Persist `snake_species`, `eligible_stick_types`, `selected_stick_item_ids`,
##     `spawn_anchor`, `act_immediately_after_caster` on the spawn_profile.
##
## ~120 LOC.

const VALID_SNAKE_SPECIES: Array = ["spitting_cobra", "pit_viper"]
const ELIGIBLE_STICK_TYPES: Array = [
	"long_bow", "short_bow", "composite_bow", "quarterstaff",
	"spear", "polearm", "10ft_pole", "javelin",
]


func resolve(args: Dictionary) -> Dictionary:
	var caster_context = args.get("caster_context")
	var spell_choice = args.get("spell_choice")
	var step_payload: Dictionary = args.get("step_payload", {})
	var resolver_args: Dictionary = step_payload.get("resolver_args", {})
	# DiceSystem for the 2d8 + per-snake poison roll. The parent resolver
	# usually injects this; for direct unit-test calls the resolver_args may
	# carry a 'dice' override.
	var dice = resolver_args.get("dice", null)

	if caster_context == null:
		return {"applied": false, "reason": "sticks_to_snakes_resolver: missing caster_context"}

	# Caster's chosen snake species (one species per cast). Default to the
	# pre-refactor "poisonous" path (pit_viper) when unspecified so older
	# spell-pickers continue to work.
	var snake_species := String(resolver_args.get("snake_species", "pit_viper")).to_lower()
	if snake_species not in VALID_SNAKE_SPECIES:
		return {
			"applied": false,
			"reason": "invalid_snake_species",
			"requested": snake_species,
			"valid": VALID_SNAKE_SPECIES,
		}

	# Brackets: 1 bracket per 4 caster levels, minimum 1 (L1-L3 still gets 2d8).
	var brackets: int = max(1, int(caster_context.caster_level / 4) + (1 if caster_context.caster_level % 4 != 0 else 0))
	# Equivalent to: ceil(caster_level / 4) with minimum 1.
	if caster_context.caster_level <= 4:
		brackets = 1

	# Roll snake count.
	var snake_count: int = 0
	if dice != null:
		for i in range(brackets):
			var roll = dice.roll_expression("2d8", "spell_sticks_to_snakes_count")
			snake_count += int(roll.modified_total) if roll != null else 0
	else:
		# Headless / no-dice path: use average (9 per bracket).
		snake_count = brackets * 9

	# Per-snake poison-disabled roll. RAW + project rule: 50% chance the chosen
	# species' poison is suppressed for this individual snake. Includes the
	# cobra's spit attack poison when the species is spitting_cobra.
	var snakes: Array = []
	for i in range(snake_count):
		var poison_disabled: bool = false
		if dice != null:
			var pr = dice.roll_digital(2, 1, 0, "spell_sticks_to_snakes_poison_disable")
			poison_disabled = int(pr.modified_total) >= 2  # 50% chance (roll of 2 on 1d2)
		else:
			poison_disabled = (i % 2 == 0)  # deterministic alternating fallback
		snakes.append({
			"snake_id": "snake_from_stick:%s:%d" % [caster_context.caster_id, i],
			"snake_species": snake_species,
			"poison_disabled": poison_disabled,
			"obeys_caster_id": caster_context.caster_id,
			"reverts_to_stick_on_death": true,
		})

	# Eligible stick types — the inventory-picker UI (deferred) uses this to
	# filter the caster's selection; the resolver carries the list for the
	# integrator + expire callback.
	var selected_stick_item_ids: Array = resolver_args.get("selected_stick_item_ids", [])

	var spawn_profile: Dictionary = {
		"caster_id": caster_context.caster_id,
		"caster_level": caster_context.caster_level,
		"brackets": brackets,
		"snake_count": snake_count,
		"snake_species": snake_species,
		"snakes": snakes,
		"eligible_stick_types": ELIGIBLE_STICK_TYPES,
		"selected_stick_item_ids": selected_stick_item_ids,
		# Spawn placement: snakes appear at each stick-bearer's cell. When the
		# selected_stick_item_ids list is empty (caster cast without using the
		# UI picker), the integrator falls back to the caster cell.
		"spawn_anchor": "item_owner",
		# Initiative: snakes act immediately after the caster's tick on the
		# cast round. Initiative scheduler honors this when the API exists;
		# otherwise the integrator inserts them at the top of the next round.
		"act_immediately_after_caster": true,
		# Allegiance: blue-team (PARTY) for now. TODO third-party combat layer.
		"allegiance": "blue",
	}

	return {
		"applied": true,
		"spawn_profile": spawn_profile,
		"snake_count": snake_count,
		"brackets": brackets,
		"caster_id": caster_context.caster_id,
		"spell_key": spell_choice.spell_key if spell_choice != null else "sticks_to_snakes",
		"persist_metadata": {
			"sticks_to_snakes_spawn_profile": spawn_profile,
		},
	}


## P7 — expiration callback. Per RAW: "When snakes are slain, dispelled, or
## the spell expires, they revert to their original stick form." Iterates
## the spawned snakes and emits combatant_reverted_to_object for each so
## downstream subscribers (combat roster integrator, inventory subsystem)
## remove the combatant + recreate the stick item. P3 SpawnRosterIntegrator
## records spawned_combatant_ids on the effect.metadata; either key (those
## ids OR the resolver-side spawn_profile.snakes) is a valid source.
static func on_expiration(
		effect: Dictionary, _cause: String, _target_lookup: Callable) -> void:
	var meta: Dictionary = effect.get("metadata", {})
	var profile: Dictionary = meta.get("sticks_to_snakes_spawn_profile", {})
	var emitted: Dictionary = {}
	for sid_v in meta.get("spawned_combatant_ids", []):
		var sid := String(sid_v)
		if sid.is_empty() or emitted.has(sid):
			continue
		EventBus.combatant_reverted_to_object.emit(sid, "stick")
		emitted[sid] = true
	for entry in profile.get("snakes", []):
		var sid := String(entry.get("snake_id", ""))
		if sid.is_empty() or emitted.has(sid):
			continue
		EventBus.combatant_reverted_to_object.emit(sid, "stick")
		emitted[sid] = true
