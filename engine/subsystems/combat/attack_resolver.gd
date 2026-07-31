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
	# Phase 10B.3 #6: hard-block invalid attacks based on permanent wounds
	# per RAW acore-campaign-hijinks.xml L342-398 (corporal punishment
	# effects) and ax_mortal_wounds_and_tampering.xml (combat-relevant MW
	# outcomes). The aggregator returns an Empty Dictionary if the character
	# has no wounds, so this check is free for unwounded combatants.
	if attacker.is_character:
		var block: Dictionary = _wound_blocks_attack(attacker)
		if not block.is_empty():
			var miss := _build_miss_result(attacker, target, 0, 0, damage_expression)
			miss["wound_blocked"] = true
			miss["wound_block_reason"] = block.get("reason", "")
			return miss

	# Get the damage expression
	if damage_expression.is_empty():
		damage_expression = _get_melee_damage_expression(attacker)

	# RAW: rules/acore_combat_and_wounds.xml:402-407 (invulnerableMonsters) —
	# some monsters can be harmed only by magical or silver weapons; weaker
	# attackers without magical/silver weapons cannot harm them. Monsters with
	# 5+ HD harm them through natural ferocity; such monsters can always harm
	# each other. Abort BEFORE the d20 roll: no chance to hit means no roll.
	if target.is_damaged_only_by_magic_or_silver() and not attacker.can_harm_invulnerable_target():
		var harmless := _build_miss_result(attacker, target, 0, 0, damage_expression)
		harmless["cant_harm"] = true
		harmless["cant_harm_reason"] = "target can be harmed only by magical or silver weapons"
		return harmless

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
		# Magic swords with vs-creature-type conditional bonuses
		# (Flame Tongue +2/+3, Frost Brand +6 via the +3 base). Applies
		# both to-hit and damage per RAW. See _get_sword_bonus_vs_creature.
		to_hit_bonus += _get_sword_bonus_vs_creature(attacker, target)
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
		# Magic swords with vs-creature-type conditional damage bonus.
		if attacker.is_character:
			magic_dmg_bonus += _get_sword_bonus_vs_creature(attacker, target)
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

		# Vorpal Sword nat-20 hook (RAW
		# acore_treasure_and_magic_items_rules.xml:277): "On a natural 20
		# attack throw, decapitates a struck target unless it saves
		# versus Death. If the save succeeds, or if the target has no
		# head, the attack instead deals double normal damage." V1 implementation:
		# nat-20 + attacker is wielding vorpal_sword → target rolls
		# save_poison_death (the ACKS 'vs Death' save category); failure
		# = instant kill (damage = current HP + 1 buffer to ensure death);
		# success = damage doubled. Stacks multiplicatively with Weapon
		# Focus if both fire (×4 on the rare nat-20 with a vorpal sword
		# AND Weapon Focus on swords).
		if is_natural_twenty and attacker.is_character \
				and str(attacker.get_equipped_weapon().get("item_key", "")) == "vorpal_sword":
			var save_target: int = target.get_effective_save("save_poison_death")
			var save_roll_result: int = 20
			if _dice_system != null:
				var sr: RollResult = _dice_system.roll_digital(
					20, 1, 0, "vorpal_save_vs_death")
				save_roll_result = sr.modified_total
			var passed: bool = save_roll_result >= save_target
			if not passed:
				# Instant kill: deal enough damage to drop the target.
				damage_total = max(damage_total, int(target.hp_current) + 1)
				EventBus.damage_dealt.emit(
					target.id,
					damage_total,
					"vorpal_decapitation",
					attacker.id)
			else:
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
			# Attacking a swarm with a torch/weapon IS "warding it off": flag the
			# attacker so the swarm's damage tick halves and its confusion/paralysis
			# saves gain +4 (SwarmDriver / SpellCombatHooks read is_warding). Cleared
			# at round start by SwarmDriver.on_round_start.
			var a_flags: EntityFlags = attacker.get_flags() if attacker.has_method("get_flags") else null
			if a_flags != null:
				a_flags.set_flag("is_warding", "swarm_ward")

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

## Returns extra to-hit AND damage bonus for magic swords whose RAW
## bonus is conditional on the target's creature type. Called from both
## the to-hit calculation and the damage calculation (the same bonus
## applies to both per RAW: "Functions as sword +6" means +6 on both).
##
## V1 wired items (RAW citations from
## `acore_treasure_and_magic_items_rules.xml:273-277`):
##   - **flame_tongue** (`:273`): "+2 versus regenerating or avian monsters
##     and +3 versus undead or plant-like monsters." Higher bonus wins when
##     multiple categories match (avian undead = +3, not +5).
##   - **frost_brand** (`:276`): "Functions as sword +6 versus creatures
##     from hot environments or with fire-based attacks." Frost Brand's
##     base is +3; +6 vs hot/fire is therefore an EXTRA +3 on those targets.
##
## The base `magical_bonus` is applied separately via
## `get_weapon_magical_bonus()`; this helper returns only the EXTRA delta
## on top of the base for the conditional cases. Returns 0 for any other
## weapon (non-magical or non-matching magic sword).
func _get_sword_bonus_vs_creature(attacker: Combatant, target: Combatant) -> int:
	var weapon: Dictionary = attacker.get_equipped_weapon()
	var item_key: String = str(weapon.get("item_key", ""))
	if item_key.is_empty():
		return 0
	# Monster-only target checks — the helpers all return false for PCs.
	# Even Vorpal isn't gated through here; only the conditional bonuses are.
	if target.is_character:
		return 0
	match item_key:
		"flame_tongue":
			# Higher bonus wins (RAW silent on stacking; conservative).
			# +3 categories: undead or plant-like.
			if target.is_creature_type("undead") or target.is_plant_like():
				return 3
			# +2 categories: regenerating or avian.
			if target.has_regeneration() or target.is_avian():
				return 2
			return 0
		"frost_brand":
			# +6 total vs hot environment or fire-based attacks; base is
			# +3 (stamped via EXPLICIT_BONUS in the extractor); so extra +3.
			if target.is_from_hot_environment() or target.has_fire_based_attacks():
				return 3
			return 0
		_:
			return 0


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


## Phase 10B.3 #6: returns {reason: String} if the attacker's permanent wounds
## prevent the attack outright per RAW. Empty dict = no block.
##
## Blocks (RAW acore-campaign-hijinks.xml L372 + MW table):
##   * both_hands_amputated → cannot use weapons of any kind
##   * one_hand_amputated wielding a two-handed weapon → invalid combination
##   * one_hand_amputated dual-wielding → invalid combination
##
## Numeric penalties (blindness -4, etc.) are handled inside the to_hit_bonus
## computation; this helper only handles the binary "cannot perform" blocks.
static func _wound_blocks_attack(attacker: Combatant) -> Dictionary:
	var agg: Dictionary = WoundEffectAggregator.compute(attacker.id)
	if int(agg.get("wound_count", 0)) == 0:
		return {}
	if bool(agg.get("cannot_use_weapons", false)):
		return {"reason": "both hands amputated — cannot use weapons"}
	if bool(agg.get("cannot_use_two_handed_weapons", false)) and attacker.is_wielding_two_handed():
		return {"reason": "one hand amputated — cannot use two-handed weapons"}
	if bool(agg.get("cannot_dual_wield", false)) and attacker.is_dual_wielding():
		return {"reason": "one hand amputated — cannot dual wield"}
	return {}
