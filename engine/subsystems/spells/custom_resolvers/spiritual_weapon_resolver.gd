class_name SpiritualWeaponResolver
extends RefCounted

## Spiritual Weapon (Divine L2) — first autonomous-attack entity custom resolver.
##
## ACKS RAW (acore_spell_catalog_k-w_summary.xml):
##   - 30' range, 1 round per caster level
##   - Creates a force weapon that attacks the chosen foe once per round
##   - Damage: 1d6 + 1 per 3 caster levels, max +4 (so +1 at L3, +2 at L6,
##     +3 at L9, +4 at L12+)
##   - Uses the caster's normal attack throws
##   - Strikes as a magical weapon (can damage creatures only hit by magic)
##   - Form is appropriate to the cleric and deity
##   - Disappears if: weapon moves beyond range, caster loses sight, or
##     caster ceases directing it (concentration)
##   - Cannot be attacked or harmed by physical attacks
##
## Resolver responsibilities:
##   - Compute the damage bonus from caster_level
##   - Build the weapon's runtime profile (id, target_id, damage_expression,
##     attack_throw, range, expiry round)
##   - Return the profile in the outcome so combat layer (CombatController +
##     scheduler) can spawn an autonomous-attack roster entry per round
##
## Note: the actual per-round attack execution is a combat-layer concern —
## this resolver produces the contract; CombatController reads the active
## effect to schedule the attack ticks and consume the caster's attack throw.
## Scene rendering of the floating weapon is also scene-layer.
##
## ~75 LOC, well under the 150 LOC custom-resolver budget.


func resolve(args: Dictionary) -> Dictionary:
	var target_descriptor = args.get("target_descriptor")
	var caster_context = args.get("caster_context")
	var spell_choice = args.get("spell_choice")

	if target_descriptor == null or caster_context == null:
		return {"applied": false, "reason": "spiritual_weapon: missing context or target"}

	if target_descriptor.target_ids.is_empty():
		return {"applied": false, "reason": "spiritual_weapon: no target chosen"}

	var caster_level: int = int(caster_context.caster_level)
	var damage_bonus: int = _compute_damage_bonus(caster_level)
	var damage_expression: String = "1d6"
	if damage_bonus > 0:
		damage_expression = "1d6+%d" % damage_bonus

	# Duration: 1 round per caster level. Encoded in rounds for the active
	# effect tracker's tick.
	var duration_rounds: int = caster_level

	# Build the weapon profile. CombatController consumes this when the spell
	# resolves to add a roster entry for the autonomous attacker.
	var weapon_profile: Dictionary = {
		"weapon_id": "spiritual_weapon:%s" % caster_context.caster_id,
		"caster_id": caster_context.caster_id,
		"target_id": target_descriptor.target_ids[0],
		"damage_expression": damage_expression,
		"damage_bonus": damage_bonus,
		"attack_strikes_as": "magical",
		"uses_caster_attack_throw": true,
		"range_feet": 30,
		"duration_rounds": duration_rounds,
		"end_conditions": ["beyond_range", "out_of_sight", "concentration_lost"],
		"physical_damage_immune": true,
	}

	return {
		"applied": true,
		"weapon_profile": weapon_profile,
		"caster_id": caster_context.caster_id,
		"spell_key": spell_choice.spell_key if spell_choice != null else "spiritual_weapon",
		"concentration": true,
		"duration_rounds": duration_rounds,
		# Session 9.6: persist the weapon_profile onto the active_effect's
		# metadata so SpellCombatHooks.on_round_end can iterate active effects
		# at end-of-round and fire the autonomous attack against the chosen
		# foe. Standard custom-resolver convention: resolvers that need
		# round-tick consumption emit `persist_metadata` for the resolver's
		# active_effect builder to splice in.
		"persist_metadata": {
			"weapon_profile": weapon_profile,
		},
	}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _compute_damage_bonus(caster_level: int) -> int:
	## ACKS RAW: +1 per 3 caster levels, max +4.
	## L1-2: +0, L3-5: +1, L6-8: +2, L9-11: +3, L12+: +4.
	@warning_ignore("integer_division")
	var bonus: int = caster_level / 3
	return mini(bonus, 4)
