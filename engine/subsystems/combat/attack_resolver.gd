class_name AttackResolver
extends RefCounted

## Resolves melee and basic attack throws.
##
## ACKS attack rule: 1d20 + modifiers >= attacker's attack_throw + target's effective_ac.
## Natural 20 always hits. Natural 1 always misses.
## Damage: roll weapon damage expression + STR modifier + damage_bonus from modifiers.
##
## SpellCombatHooks are called at: pre_attack, hit_confirmed, damage_dealt, combatant_downed.
## All hook calls are guarded by null checks for backward compatibility.

# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _dice_system = null  # DiceSystem autoload or mock
var _spell_hooks: SpellCombatHooks = null


func _init(dice_system = null, spell_hooks: SpellCombatHooks = null) -> void:
	_dice_system = dice_system
	_spell_hooks = spell_hooks


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Resolve a melee attack from [param attacker] against [param target].
## [param extra_attack_mod]: additional to-hit modifier from conditions, etc.
## Returns a result Dictionary (see _build_result).
func resolve_melee_attack(
		attacker: Combatant,
		target: Combatant,
		damage_expression: String = "",
		extra_attack_mod: int = 0) -> Dictionary:
	# Get the damage expression
	if damage_expression.is_empty():
		damage_expression = _get_melee_damage_expression(attacker)

	# Calculate attack modifiers
	var str_mod := attacker._get_ability_modifier("strength")
	# STR mod + weapon magical bonus + monster to-hit bonuses + condition/external modifiers
	var to_hit_bonus := str_mod + extra_attack_mod
	if attacker.is_character:
		to_hit_bonus += attacker.get_weapon_magical_bonus()
	else:
		to_hit_bonus += attacker.get_to_hit_modifier(0)

	# --- Spell hooks: on_pre_attack ---
	if _spell_hooks != null:
		var hook_result := _spell_hooks.on_pre_attack(attacker, target, "melee")
		if hook_result.get("cancel", false):
			return _build_miss_result(attacker, target, 0, to_hit_bonus, damage_expression)
		if hook_result.get("auto_hit", false):
			return _resolve_auto_hit_melee(attacker, target, str_mod, damage_expression)
		to_hit_bonus += int(hook_result.get("attack_modifier", 0))

	# Roll the attack
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
	var target_number: int = attacker.get_effective_attack_throw() + target.get_effective_ac()

	# Determine hit/miss
	var is_hit: bool
	var is_natural_twenty := (natural_roll == 20 and not attack_roll.was_overridden) \
		or attack_roll.natural_max
	var is_natural_one := (natural_roll == 1 and not attack_roll.was_overridden) \
		or attack_roll.natural_one

	if is_natural_twenty:
		is_hit = true
	elif is_natural_one:
		is_hit = false
	else:
		is_hit = total_attack >= target_number

	# Roll damage if hit
	var damage_total: int = 0
	var damage_roll: RollResult = null
	var damage_result: Dictionary = {}

	if is_hit:
		# --- Spell hooks: on_hit_confirmed ---
		var bonus_damage: int = 0
		if _spell_hooks != null:
			var hit_hook := _spell_hooks.on_hit_confirmed(attacker, target, 0)
			if hit_hook.get("cancel_hit", false):
				is_hit = false
			else:
				bonus_damage = int(hit_hook.get("bonus_damage", 0))

	if is_hit:
		var str_damage_mod := str_mod if attacker.is_character else 0
		var mod_bonus: int = attacker.get_modifiers().get_effective_value("damage_bonus", 0)

		if _dice_system != null:
			damage_roll = _dice_system.roll_expression(damage_expression, "damage")
		else:
			damage_roll = RollResult.new()
			damage_roll.raw_total = 4
			damage_roll.modified_total = 4

		var magic_dmg_bonus: int = attacker.get_weapon_magical_bonus() if attacker.is_character else 0
		damage_total = maxi(1, damage_roll.modified_total + str_damage_mod + mod_bonus + magic_dmg_bonus)

		# Apply damage through target's resistance pipeline
		damage_result = target.apply_damage(damage_total, "physical")

		# Track last attacker for retaliatory targeting
		target.last_attacker_id = attacker.id

		# Emit damage signal
		EventBus.damage_dealt.emit(
			target.id, damage_result.get("hp_damage", 0), "physical", attacker.id)

		# --- Spell hooks: on_damage_dealt ---
		if _spell_hooks != null:
			_spell_hooks.on_damage_dealt(
				target, damage_result.get("hp_damage", 0), attacker.id)

		# Check if target was downed
		if damage_result.get("is_downed", false):
			# Record damage type on the target for mortal wounds processing.
			# TODO: replace "slashing" with actual weapon damage type when equipment is wired.
			if target.is_character:
				target.killing_blow_damage_type = "slashing"
			EventBus.combatant_downed.emit(target.id, attacker.id)
			# --- Spell hooks: on_combatant_downed ---
			if _spell_hooks != null:
				var down_hook := _spell_hooks.on_combatant_downed(target)
				if down_hook.get("prevent_down", false):
					# Future: undo the downing (Death Ward etc.)
					pass

		# Emit HP change
		var old_hp: int = damage_result.get("new_hp", 0) + damage_result.get("hp_damage", 0)
		EventBus.hp_changed.emit(target.id, old_hp, damage_result.get("new_hp", 0))

	return _build_result(
		attacker, target, attack_roll, natural_roll, to_hit_bonus,
		total_attack, target_number, is_hit, is_natural_twenty, is_natural_one,
		damage_total, damage_expression, damage_roll, damage_result)


## Resolve a single monster attack (from a specific attack index in the routine).
## [param extra_attack_mod]: additional to-hit modifier from conditions, etc.
func resolve_monster_attack(
		attacker: Combatant,
		target: Combatant,
		attack_index: int = 0,
		extra_attack_mod: int = 0) -> Dictionary:
	var damage_expr := attacker.get_damage_expression(attack_index)
	var to_hit_mod := attacker.get_to_hit_modifier(attack_index) + extra_attack_mod

	# --- Spell hooks: on_pre_attack ---
	if _spell_hooks != null:
		var hook_result := _spell_hooks.on_pre_attack(attacker, target, "melee")
		if hook_result.get("cancel", false):
			return _build_miss_result(attacker, target, 0, to_hit_mod, damage_expr)
		to_hit_mod += int(hook_result.get("attack_modifier", 0))

	# Roll attack
	var attack_roll: RollResult
	if _dice_system != null:
		attack_roll = _dice_system.roll_digital(20, 1, 0, "attack")
	else:
		attack_roll = RollResult.new()
		attack_roll.raw_total = 10
		attack_roll.modified_total = 10
		attack_roll.individual_results = [10]

	var natural_roll: int = attack_roll.raw_total
	var total_attack: int = natural_roll + to_hit_mod
	var target_number: int = attacker.get_effective_attack_throw() + target.get_effective_ac()

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

	var damage_total: int = 0
	var damage_roll: RollResult = null
	var damage_result: Dictionary = {}

	if is_hit:
		if _spell_hooks != null:
			var hit_hook := _spell_hooks.on_hit_confirmed(attacker, target, 0)
			if hit_hook.get("cancel_hit", false):
				is_hit = false

	if is_hit:
		if _dice_system != null:
			damage_roll = _dice_system.roll_expression(damage_expr, "damage")
		else:
			damage_roll = RollResult.new()
			damage_roll.raw_total = 4
			damage_roll.modified_total = 4

		damage_total = maxi(1, damage_roll.modified_total)
		damage_result = target.apply_damage(damage_total, "physical")

		# Track last attacker for retaliatory targeting
		target.last_attacker_id = attacker.id

		EventBus.damage_dealt.emit(
			target.id, damage_result.get("hp_damage", 0), "physical", attacker.id)

		if _spell_hooks != null:
			_spell_hooks.on_damage_dealt(
				target, damage_result.get("hp_damage", 0), attacker.id)

		if damage_result.get("is_downed", false):
			if target.is_character:
				target.killing_blow_damage_type = "slashing"
			EventBus.combatant_downed.emit(target.id, attacker.id)
			if _spell_hooks != null:
				_spell_hooks.on_combatant_downed(target)

		var old_hp: int = damage_result.get("new_hp", 0) + damage_result.get("hp_damage", 0)
		EventBus.hp_changed.emit(target.id, old_hp, damage_result.get("new_hp", 0))

	return _build_result(
		attacker, target, attack_roll, natural_roll, to_hit_mod,
		total_attack, target_number, is_hit, is_natural_twenty, is_natural_one,
		damage_total, damage_expr, damage_roll, damage_result)


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

func _get_melee_damage_expression(attacker: Combatant) -> String:
	## Returns the damage expression for the attacker's melee weapon.
	## For characters: reads from equipped weapon, falls back to 1d3 (unarmed brawling).
	## For monsters: reads from attack_routines.
	if attacker.is_character:
		return attacker.get_weapon_damage()
	return attacker.get_damage_expression(0)


func _resolve_auto_hit_melee(
		attacker: Combatant, target: Combatant,
		str_mod: int, damage_expression: String) -> Dictionary:
	var str_damage_mod := str_mod if attacker.is_character else 0
	var mod_bonus: int = attacker.get_modifiers().get_effective_value("damage_bonus", 0)
	var damage_roll: RollResult
	if _dice_system != null:
		damage_roll = _dice_system.roll_expression(damage_expression, "damage")
	else:
		damage_roll = RollResult.new()
		damage_roll.raw_total = 4
		damage_roll.modified_total = 4
	var damage_total := maxi(1, damage_roll.modified_total + str_damage_mod + mod_bonus)
	var damage_result := target.apply_damage(damage_total, "physical")

	EventBus.damage_dealt.emit(
		target.id, damage_result.get("hp_damage", 0), "physical", attacker.id)
	if _spell_hooks != null:
		_spell_hooks.on_damage_dealt(
			target, damage_result.get("hp_damage", 0), attacker.id)
	if damage_result.get("is_downed", false):
		if target.is_character:
			target.killing_blow_damage_type = "slashing"
		EventBus.combatant_downed.emit(target.id, attacker.id)
		if _spell_hooks != null:
			_spell_hooks.on_combatant_downed(target)

	var old_hp: int = damage_result.get("new_hp", 0) + damage_result.get("hp_damage", 0)
	EventBus.hp_changed.emit(target.id, old_hp, damage_result.get("new_hp", 0))

	return _build_result(
		attacker, target, null, 0, 0, 0, 0, true, false, false,
		damage_total, damage_expression, damage_roll, damage_result)


static func _build_miss_result(
		attacker: Combatant, target: Combatant,
		natural_roll: int, to_hit_bonus: int,
		damage_expression: String) -> Dictionary:
	return {
		"attacker_id": attacker.id,
		"target_id": target.id,
		"hit": false,
		"natural_twenty": false,
		"natural_one": false,
		"attack_roll": natural_roll,
		"to_hit_bonus": to_hit_bonus,
		"total_attack": 0,
		"target_number": 0,
		"damage_expression": damage_expression,
		"damage_total": 0,
		"damage_result": {},
		"target_downed": false,
	}


static func _build_result(
		attacker: Combatant,
		target: Combatant,
		attack_roll: RollResult,
		natural_roll: int,
		to_hit_bonus: int,
		total_attack: int,
		target_number: int,
		is_hit: bool,
		is_natural_twenty: bool,
		is_natural_one: bool,
		damage_total: int,
		damage_expression: String,
		damage_roll: RollResult,
		damage_result: Dictionary) -> Dictionary:
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
	}
