class_name SticksToSnakesResolver
extends RefCounted

## Sticks to Snakes (Divine L4) — transmutes sticks into commanded snakes.
##
## ACKS RAW (acore_spell_catalog_k-w_summary.xml):
##   - 120' range, 6 turns duration.
##   - Targets: normal wooden sticks (NOT magical sticks like enchanted staffs).
##   - Transforms 2d8 sticks per every 4 caster levels.
##   - 50% chance the snakes are poisonous.
##   - The snakes obey the caster's commands.
##   - When snakes are slain, dispelled, or the spell expires, they revert to
##     their original stick form.
##
## Resolver responsibilities:
##   - Compute snake count: 2d8 per (caster_level / 4) brackets, rounded down.
##     L1-L3 → 2d8, L4-L7 → 4d8, L8-L11 → 6d8, etc.
##   - Per snake, roll 50% poisonous coin flip.
##   - Persist spawn profile for the active_effect.
##   - On dispel / death / expiration, the runtime layer reads the spawn_profile
##     and reverts the snakes back to sticks (handled by the active_effect
##     tracker's expiration callback chain).
##
## ~95 LOC.


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

	# Per-snake poison roll.
	var snakes: Array = []
	for i in range(snake_count):
		var poisonous: bool = false
		if dice != null:
			var pr = dice.roll_digital(2, 1, 0, "spell_sticks_to_snakes_poison")
			poisonous = int(pr.modified_total) >= 2  # 50% chance (roll of 2 on 1d2)
		else:
			poisonous = (i % 2 == 0)  # deterministic alternating fallback
		snakes.append({
			"snake_id": "snake_from_stick:%s:%d" % [caster_context.caster_id, i],
			"poisonous": poisonous,
			"obeys_caster_id": caster_context.caster_id,
			"reverts_to_stick_on_death": true,
		})

	var spawn_profile: Dictionary = {
		"caster_id": caster_context.caster_id,
		"caster_level": caster_context.caster_level,
		"brackets": brackets,
		"snake_count": snake_count,
		"snakes": snakes,
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
