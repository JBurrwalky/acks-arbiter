class_name RangedAttackResolver
extends RefCounted

## Resolves ranged/missile attack throws.
##
## ACKS ranged rules:
## - Range bands: short (no penalty), medium (-2), long (-5), beyond long (auto-miss).
## - Into-melee: BLOCKED without Precise Shooting. With Precise Shooting:
##   rank 1 = -4, rank 2 = -2, rank 3 = 0.
## - DEX modifier on attack (not STR).
## - No STR modifier on ranged damage (ACKS rule).
## - Natural 20 always hits, natural 1 always misses.
##
## weapon_data matches equipment catalog shape:
##   {range_short, range_medium, range_long, weapon_damage, weapon_tags}

# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _dice_system = null
var _spell_hooks: SpellCombatHooks = null


# ---------------------------------------------------------------------------
# Constructor
# ---------------------------------------------------------------------------

func _init(dice_system = null, spell_hooks: SpellCombatHooks = null) -> void:
	_dice_system = dice_system
	_spell_hooks = spell_hooks


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Resolve a ranged attack.
## [param weapon_data]: Dictionary with range_short, range_medium, range_long, weapon_damage.
## [param distance_ft]: distance to target in feet.
## [param target_in_melee]: whether the target is currently engaged in melee.
## [param extra_attack_mod]: additional modifier from conditions etc.
func resolve_ranged_attack(
		attacker: Combatant,
		target: Combatant,
		weapon_data: Dictionary,
		distance_ft: int,
		target_in_melee: bool = false,
		extra_attack_mod: int = 0) -> Dictionary:

	# --- Range band ---
	var range_info := _determine_range_band(distance_ft, weapon_data)
	if range_info["out_of_range"]:
		return _build_out_of_range_result(attacker, target, distance_ft, weapon_data)

	var range_penalty: int = range_info["penalty"]

	# --- Into-melee check ---
	var into_melee_penalty: int = 0
	var into_melee_blocked: bool = false
	if target_in_melee:
		var ps_rank := attacker.get_proficiency_rank("precise_shooting")
		if ps_rank <= 0:
			# Cannot fire into melee without Precise Shooting
			into_melee_blocked = true
			return _build_blocked_result(attacker, target, "no_precise_shooting")
		else:
			# Rank 1: -4, Rank 2: -2, Rank 3+: 0
			into_melee_penalty = maxi(0, 4 - (ps_rank - 1) * 2)

	# --- DEX modifier (not STR for ranged) ---
	var dex_mod := attacker._get_ability_modifier("dexterity")
	var to_hit_bonus: int = dex_mod + range_penalty - into_melee_penalty + extra_attack_mod

	# Monster to-hit bonus (if applicable)
	if not attacker.is_character:
		to_hit_bonus += attacker.get_to_hit_modifier(0)

	# --- Spell hooks: on_pre_attack ---
	if _spell_hooks != null:
		var hook_result := _spell_hooks.on_pre_attack(attacker, target, "ranged")
		if hook_result.get("cancel", false):
			return _build_cancelled_result(attacker, target)
		if hook_result.get("auto_hit", false):
			return _resolve_auto_hit(attacker, target, weapon_data, range_info, into_melee_penalty)
		to_hit_bonus += int(hook_result.get("attack_modifier", 0))

	# --- Roll attack ---
	var attack_roll: RollResult
	if _dice_system != null:
		attack_roll = _dice_system.roll_digital(20, 1, 0, "attack")
	else:
		attack_roll = RollResult.new()
		attack_roll.raw_total = 10
		attack_roll.modified_total = 10
		attack_roll.individual_results = [10]

	var natural_roll: int = attack_roll.raw_total
	var total_attack: int = natural_roll + to_hit_bonus
	# Conditional fighting-style attack-throw modifiers (Missile FS, ...)
	# are stored in the catalog as a negative attack_throw delta — i.e. lowering
	# the target number is equivalent to a positive to-hit bonus.
	var prof_attack_mod := ProficiencyCombatHooks.aggregate_modifier(
		attacker, "attack_throw", {"phase": "ranged_attack", "target": target})
	var target_number: int = attacker.get_effective_attack_throw() \
		+ target.get_effective_ac_vs("missiles") + prof_attack_mod

	# --- Determine hit/miss ---
	var is_natural_twenty := (natural_roll == 20 and not attack_roll.was_overridden) \
		or attack_roll.natural_max
	var is_natural_one := (natural_roll == 1 and not attack_roll.was_overridden) \
		or attack_roll.natural_one

	var is_hit: bool
	if is_natural_twenty:
		is_hit = true
	elif is_natural_one:
		is_hit = false
	else:
		is_hit = total_attack >= target_number

	# --- Resolve damage if hit ---
	var damage_total: int = 0
	var damage_roll: RollResult = null
	var damage_result: Dictionary = {}
	var damage_expression: String = weapon_data.get("weapon_damage", "1d6")

	if is_hit:
		# Spell hooks: on_hit_confirmed
		var bonus_damage: int = 0
		if _spell_hooks != null:
			var hit_hook := _spell_hooks.on_hit_confirmed(attacker, target, 0)
			if hit_hook.get("cancel_hit", false):
				is_hit = false
			else:
				bonus_damage = int(hit_hook.get("bonus_damage", 0))

	if is_hit:
		if _dice_system != null:
			damage_roll = _dice_system.roll_expression(damage_expression, "damage")
		else:
			damage_roll = RollResult.new()
			damage_roll.raw_total = 4
			damage_roll.modified_total = 4

		# No STR modifier on ranged damage (ACKS rule)
		var bonus_damage: int = attacker.get_modifiers().get_effective_value("damage_bonus", 0)
		# Conditional fighting-style ranged damage bonuses, if any. Today this is
		# a no-op (Missile FS only adds to-hit, not damage), but the hook keeps
		# the resolver future-proof and consistent with the melee path.
		var prof_damage_mod := ProficiencyCombatHooks.aggregate_modifier(
			attacker, "damage_bonus", {"phase": "ranged_attack", "target": target})
		damage_total = maxi(1, damage_roll.modified_total + bonus_damage + prof_damage_mod)

		# Weapon Focus: unmodified natural 20 doubles damage when the character
		# has Weapon Focus selected for the wielded weapon's family.
		if is_natural_twenty and attacker.is_character:
			var weapon_family := attacker.get_weapon_focus_family()
			if weapon_family != "" and ProficiencyCombatHooks.has_active_enabler(
					attacker, "natural_20_double_damage",
					{"weapon_category": weapon_family}):
				damage_total *= 2

		damage_result = target.apply_damage(damage_total, "physical")

		EventBus.damage_dealt.emit(
			target.id, damage_result.get("hp_damage", 0), "physical", attacker.id)

		if damage_result.get("is_downed", false):
			EventBus.combatant_downed.emit(target.id, attacker.id)

		var old_hp: int = damage_result.get("new_hp", 0) + damage_result.get("hp_damage", 0)
		EventBus.hp_changed.emit(target.id, old_hp, damage_result.get("new_hp", 0))

		# Spell hooks: on_damage_dealt
		if _spell_hooks != null:
			_spell_hooks.on_damage_dealt(
				target, damage_result.get("hp_damage", 0), attacker.id)

		# Spell hooks: on_combatant_downed
		if damage_result.get("is_downed", false) and _spell_hooks != null:
			_spell_hooks.on_combatant_downed(target)

	return {
		"attacker_id": attacker.id,
		"target_id": target.id,
		"hit": is_hit,
		"natural_twenty": is_natural_twenty,
		"natural_one": is_natural_one,
		"attack_roll": natural_roll,
		"to_hit_bonus": to_hit_bonus,
		"total_attack": total_attack,
		"target_number": target_number,
		"damage_expression": damage_expression,
		"damage_total": damage_total,
		"damage_result": damage_result,
		"target_downed": damage_result.get("is_downed", false),
		"range_band": range_info["band"],
		"range_penalty": range_penalty,
		"into_melee_penalty": into_melee_penalty,
		"out_of_range": false,
		"into_melee_blocked": false,
	}


# ---------------------------------------------------------------------------
# Range band calculation
# ---------------------------------------------------------------------------

static func _determine_range_band(
		distance_ft: int, weapon_data: Dictionary) -> Dictionary:
	var short_range: int = int(weapon_data.get("range_short", 0))
	var medium_range: int = int(weapon_data.get("range_medium", 0))
	var long_range: int = int(weapon_data.get("range_long", 0))

	if short_range == 0 and medium_range == 0 and long_range == 0:
		# Melee-only weapon used at range — always out of range
		return {"band": "none", "penalty": 0, "out_of_range": true}

	if distance_ft <= short_range:
		return {"band": "short", "penalty": 0, "out_of_range": false}
	elif distance_ft <= medium_range:
		return {"band": "medium", "penalty": -2, "out_of_range": false}
	elif distance_ft <= long_range:
		return {"band": "long", "penalty": -5, "out_of_range": false}
	else:
		return {"band": "beyond", "penalty": 0, "out_of_range": true}


# ---------------------------------------------------------------------------
# Special result builders
# ---------------------------------------------------------------------------

static func _build_out_of_range_result(
		attacker: Combatant, target: Combatant,
		distance_ft: int, weapon_data: Dictionary) -> Dictionary:
	return {
		"attacker_id": attacker.id,
		"target_id": target.id,
		"hit": false,
		"natural_twenty": false,
		"natural_one": false,
		"attack_roll": 0,
		"to_hit_bonus": 0,
		"total_attack": 0,
		"target_number": 0,
		"damage_expression": weapon_data.get("weapon_damage", ""),
		"damage_total": 0,
		"damage_result": {},
		"target_downed": false,
		"range_band": "beyond",
		"range_penalty": 0,
		"into_melee_penalty": 0,
		"out_of_range": true,
		"into_melee_blocked": false,
	}


static func _build_blocked_result(
		attacker: Combatant, target: Combatant, reason: String) -> Dictionary:
	return {
		"attacker_id": attacker.id,
		"target_id": target.id,
		"hit": false,
		"natural_twenty": false,
		"natural_one": false,
		"attack_roll": 0,
		"to_hit_bonus": 0,
		"total_attack": 0,
		"target_number": 0,
		"damage_expression": "",
		"damage_total": 0,
		"damage_result": {},
		"target_downed": false,
		"range_band": "",
		"range_penalty": 0,
		"into_melee_penalty": 0,
		"out_of_range": false,
		"into_melee_blocked": true,
		"blocked_reason": reason,
	}


func _build_cancelled_result(
		attacker: Combatant, target: Combatant) -> Dictionary:
	return _build_blocked_result(attacker, target, "spell_cancelled")


func _resolve_auto_hit(
		attacker: Combatant, target: Combatant,
		weapon_data: Dictionary, range_info: Dictionary,
		into_melee_penalty: int) -> Dictionary:
	# Auto-hit from spell hook — roll damage only
	var damage_expression: String = weapon_data.get("weapon_damage", "1d6")
	var damage_roll: RollResult
	if _dice_system != null:
		damage_roll = _dice_system.roll_expression(damage_expression, "damage")
	else:
		damage_roll = RollResult.new()
		damage_roll.raw_total = 4
		damage_roll.modified_total = 4

	var damage_total := maxi(1, damage_roll.modified_total)
	var damage_result := target.apply_damage(damage_total, "physical")

	EventBus.damage_dealt.emit(
		target.id, damage_result.get("hp_damage", 0), "physical", attacker.id)
	if damage_result.get("is_downed", false):
		EventBus.combatant_downed.emit(target.id, attacker.id)

	return {
		"attacker_id": attacker.id,
		"target_id": target.id,
		"hit": true,
		"natural_twenty": false,
		"natural_one": false,
		"attack_roll": 0,
		"to_hit_bonus": 0,
		"total_attack": 0,
		"target_number": 0,
		"damage_expression": damage_expression,
		"damage_total": damage_total,
		"damage_result": damage_result,
		"target_downed": damage_result.get("is_downed", false),
		"range_band": range_info["band"],
		"range_penalty": range_info["penalty"],
		"into_melee_penalty": into_melee_penalty,
		"out_of_range": false,
		"into_melee_blocked": false,
	}
