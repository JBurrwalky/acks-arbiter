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
	# Weapon Finesse: substitute DEX for STR on to-hit (not damage) when the
	# character has the proficiency flag and is wielding a one-handed melee weapon.
	var attack_ability_mod := str_mod
	if attacker.is_character and attacker.is_wielding_one_handed_melee():
		var flags := attacker.get_flags()
		if flags != null and flags.has_flag("dex_for_attack_throws"):
			attack_ability_mod = attacker._get_ability_modifier("dexterity")
	# STR/DEX mod + weapon magical bonus + monster to-hit bonuses + condition/external modifiers
	var to_hit_bonus := attack_ability_mod + extra_attack_mod
	if attacker.is_character:
		to_hit_bonus += attacker.get_weapon_magical_bonus()
		# Strenuous-day penalty per ax_campaign_play §effort_rules L166-172.
		# Cumulative -1/day past the 6-day grace window applies to attack
		# throws, damage, and proficiency throws until rest is taken.
		to_hit_bonus -= StrenuousAccountant.get_attack_throw_penalty(attacker.id)
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
	# Conditional fighting-style attack-throw modifiers (single_weapon, two_weapons, ...)
	# are stored in the catalog as a negative attack_throw delta — i.e. lowering the
	# target number is equivalent to a positive to-hit bonus.
	var prof_attack_mod := ProficiencyCombatHooks.aggregate_modifier(
		attacker, "attack_throw", {"phase": "melee_attack", "target": target})
	var target_number: int = attacker.get_effective_attack_throw() \
		+ target.get_effective_ac_vs("melee") + prof_attack_mod

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
		# Conditional fighting-style damage bonus (two-handed weapon, ...).
		var prof_damage_mod := ProficiencyCombatHooks.aggregate_modifier(
			attacker, "damage_bonus", {"phase": "melee_attack", "target": target})

		if _dice_system != null:
			damage_roll = _dice_system.roll_expression(damage_expression, "damage")
		else:
			damage_roll = RollResult.new()
			damage_roll.raw_total = 4
			damage_roll.modified_total = 4

		var magic_dmg_bonus: int = attacker.get_weapon_magical_bonus() if attacker.is_character else 0
		# Striking custom resolver (Session 9) writes damage_bonus_dice="1d6"
		# and strikes_as_magical to the wielded weapon item via
		# apply_modifier_to_item. Session 9.6 polish: consume those item-side
		# bonuses here. Roll the bonus dice fresh each strike per RAW
		# (acore_spell_catalog_k-w_summary.xml: "Each successful attack with
		# the weapon deals +1d6 damage").
		var item_bonus: Dictionary = {}
		if _spell_hooks != null and _spell_hooks.has_method("get_item_attack_bonuses"):
			item_bonus = _spell_hooks.get_item_attack_bonuses(attacker)
		var striking_bonus: int = int(item_bonus.get("bonus_damage", 0))
		# Strenuous-day penalty applies to damage rolls per
		# ax_campaign_play §effort_rules L168.
		var strenuous_dmg: int = 0
		if attacker.is_character:
			strenuous_dmg = StrenuousAccountant.get_attack_throw_penalty(attacker.id)
		damage_total = maxi(1, damage_roll.modified_total + str_damage_mod \
			+ mod_bonus + prof_damage_mod + magic_dmg_bonus + striking_bonus \
			- strenuous_dmg)

		# Weapon Focus: unmodified natural 20 doubles damage when the character
		# has Weapon Focus selected for the wielded weapon's family.
		if is_natural_twenty and attacker.is_character:
			var weapon_family := attacker.get_weapon_focus_family()
			if weapon_family != "" and ProficiencyCombatHooks.has_active_enabler(
					attacker, "natural_20_double_damage",
					{"weapon_category": weapon_family}):
				damage_total *= 2

		# Warding-attack clamp: ordinary weapon attacks against a swarm replace
		# their damage roll with a fresh 1d4, per RAW (le_monster_catalog_2_summary.xml
		# swarm_attack_resolution: "Warding off a swarm with a torch or weapon
		# inflicts 1d4 damage to the swarm. Fire-based and cold-based attacks
		# damage a swarm."). Magical-rider damage discrimination (Striking flame
		# sword retaining its fire die) is deferred until damage-type per-bonus
		# accounting lands; for now, only spells that pre-set the damage_type
		# to fire/cold bypass the clamp.
		if target.is_swarm():
			var clamped: int = 4
			if _dice_system != null:
				var d = _dice_system.roll_expression("1d4", "swarm_warding_attack")
				clamped = int(d.modified_total) if d != null else 4
			damage_total = maxi(1, clamped)

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
	var target_number: int = attacker.get_effective_attack_throw() + target.get_effective_ac_vs("melee")

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
