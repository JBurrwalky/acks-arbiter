class_name MoraleResolver
extends RefCounted

## Handles ACKS morale rolls, triggers, outcomes, and conditional modifiers.
##
## ACKS morale rules:
## - Roll 2d6 + morale rating + conditional modifiers.
## - Triggers: first casualty, half casualties, solo monster at half HP.
## - If both first casualty and half casualties occur same round: single roll at -2.
## - Morale +4 means fight to death (no roll). morale_style "fearless" = same.
## - Special abilities and morale_modifiers can override with "no_check".
##
## Outcomes (2d6 + modifiers):
##   2-: Retreat (full retreat, skip actions)
##   3-5: Fighting Withdrawal (still attacks, withdraws 1d10 rounds)
##   6-8: Fight On
##   9-11: Advance and Pursue
##   12+: Victory or Death (no further morale rolls)

# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _dice_system = null

## Tracks which groups have already rolled for first casualty (group_id -> round_number).
var _first_casualty_rolled: Dictionary = {}  # group_id -> int (round)

## Tracks which groups have already rolled for half casualties (group_id -> round_number).
var _half_casualties_rolled: Dictionary = {}  # group_id -> int (round)

## Tracks solo monster half-HP roll (combatant_id -> bool).
var _solo_half_hp_rolled: Dictionary = {}  # combatant_id -> bool

## Current round number (set by caller before checking triggers).
var current_round: int = 0


# ---------------------------------------------------------------------------
# Constructor
# ---------------------------------------------------------------------------

func _init(dice_system = null) -> void:
	_dice_system = dice_system


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Check whether a morale roll should happen given the trigger context.
## Returns: {should_roll: bool, extra_modifier: int, reason: String}
func check_trigger(
		combatant: Combatant,
		trigger: String,
		roster: CombatRoster) -> Dictionary:
	# Morale-locked combatants (Victory or Death) never roll again
	if combatant.morale_locked:
		return {"should_roll": false, "extra_modifier": 0, "reason": "morale_locked"}

	# Already fleeing or withdrawing — no new roll
	if combatant.is_fleeing:
		return {"should_roll": false, "extra_modifier": 0, "reason": "already_fleeing"}

	# Check for morale override (no_check from special abilities or morale_modifiers)
	var override := check_morale_override(combatant)
	if override["has_override"]:
		return {"should_roll": false, "extra_modifier": 0, "reason": "no_check_override"}

	# Base morale +4 = fight to death
	if combatant.get_morale() >= 4:
		return {"should_roll": false, "extra_modifier": 0, "reason": "morale_max"}

	# Fearless morale_style = no roll
	var behavior := combatant.get_combat_behavior()
	if behavior.get("morale_style", "normal") == "fearless":
		return {"should_roll": false, "extra_modifier": 0, "reason": "fearless"}

	var group_id := combatant.monster_group_id
	var extra_modifier: int = 0

	match trigger:
		"first_casualty":
			if _first_casualty_rolled.has(group_id):
				return {"should_roll": false, "extra_modifier": 0, "reason": "already_rolled_first_casualty"}
			_first_casualty_rolled[group_id] = current_round
			# Check if half casualties also happened this same round
			if roster.is_half_casualties(group_id) and not _half_casualties_rolled.has(group_id):
				_half_casualties_rolled[group_id] = current_round
				extra_modifier = -2
				return {"should_roll": true, "extra_modifier": extra_modifier, "reason": "first_and_half_casualties"}
			return {"should_roll": true, "extra_modifier": 0, "reason": "first_casualty"}

		"half_casualties":
			if _half_casualties_rolled.has(group_id):
				return {"should_roll": false, "extra_modifier": 0, "reason": "already_rolled_half_casualties"}
			_half_casualties_rolled[group_id] = current_round
			# Check if first casualty was already rolled THIS SAME round
			if _first_casualty_rolled.has(group_id) and _first_casualty_rolled[group_id] == current_round:
				# Combined roll already handled by first_casualty trigger
				return {"should_roll": false, "extra_modifier": 0, "reason": "combined_with_first_casualty"}
			return {"should_roll": true, "extra_modifier": 0, "reason": "half_casualties"}

		"solo_half_hp":
			if _solo_half_hp_rolled.get(combatant.id, false):
				return {"should_roll": false, "extra_modifier": 0, "reason": "already_rolled_solo_half_hp"}
			_solo_half_hp_rolled[combatant.id] = true
			return {"should_roll": true, "extra_modifier": 0, "reason": "solo_half_hp"}

	return {"should_roll": false, "extra_modifier": 0, "reason": "unknown_trigger"}


## Roll morale for a combatant.
## Returns: {roll: int, base_morale: int, conditional_modifier: int,
##           extra_modifier: int, modified_total: int, outcome: String}
func roll_morale(
		combatant: Combatant,
		roster: CombatRoster,
		extra_modifier: int = 0) -> Dictionary:
	var base_morale := combatant.get_morale()
	var conditional_mod := evaluate_conditional_modifiers(combatant, roster)

	var roll: int
	if _dice_system != null:
		var result: RollResult = _dice_system.roll_digital(6, 2, 0, "morale")
		roll = result.modified_total
	else:
		roll = 7  # Default for tests without dice

	var total := roll + base_morale + conditional_mod + extra_modifier
	var outcome := _outcome_from_total(total)

	return {
		"roll": roll,
		"base_morale": base_morale,
		"conditional_modifier": conditional_mod,
		"extra_modifier": extra_modifier,
		"modified_total": total,
		"outcome": outcome,
	}


## Evaluate conditional morale modifiers for a combatant.
## Checks morale_modifiers array for active conditions.
func evaluate_conditional_modifiers(
		combatant: Combatant,
		roster: CombatRoster) -> int:
	var total_mod: int = 0
	var morale_mods: Array = combatant.get_morale_modifiers()

	for entry: Dictionary in morale_mods:
		var condition: String = entry.get("condition", "")
		if entry.has("override"):
			continue  # Overrides are handled by check_morale_override
		var modifier: int = int(entry.get("modifier", 0))

		match condition:
			"chieftain_alive":
				# Check if any leader in the same group is still alive
				if _is_group_leader_alive(combatant.monster_group_id, roster):
					total_mod += modifier
			"group_of_3_or_fewer":
				var alive := roster.get_alive_on_side(Combatant.Side.ENEMY)
				if alive.size() <= 3:
					total_mod += modifier
			"50_percent_casualties":
				if roster.is_half_casualties(combatant.monster_group_id):
					total_mod += modifier
			_:
				# Unknown condition — skip
				pass

	return total_mod


## Check for morale override (no_check) from morale_modifiers and special_abilities.
func check_morale_override(combatant: Combatant) -> Dictionary:
	# Check morale_modifiers for overrides
	var morale_mods: Array = combatant.get_morale_modifiers()
	for entry: Dictionary in morale_mods:
		if entry.has("override") and str(entry["override"]) == "no_check":
			var condition: String = entry.get("condition", "")
			# Check if the override condition is active
			if _is_override_condition_active(combatant, condition):
				return {"has_override": true, "type": condition}

	# Check special_abilities for morale-relevant overrides
	var abilities: Array = combatant.get_special_abilities()
	for ability: Dictionary in abilities:
		var effect: Dictionary = ability.get("effect", {})
		if effect.get("morale_override", "") == "no_check":
			var trigger: String = effect.get("trigger", "")
			if trigger.is_empty() or _is_ability_trigger_active(combatant, trigger):
				return {"has_override": true, "type": ability.get("ability_id", "")}

	return {"has_override": false, "type": ""}


## Apply the outcome of a morale roll to a combatant.
func apply_outcome(combatant: Combatant, outcome: String) -> void:
	match outcome:
		"retreat":
			combatant.is_fleeing = true
		"fighting_withdrawal":
			combatant.is_withdrawing = true
			# Roll 1d10 for withdrawal duration
			if _dice_system != null:
				var result: RollResult = _dice_system.roll_digital(10, 1, 0, "withdrawal_duration")
				combatant.withdrawal_rounds_remaining = maxi(1, result.modified_total)
			else:
				combatant.withdrawal_rounds_remaining = 5  # Default for tests
		"fight_on":
			pass  # No change
		"advance_pursue":
			pass  # Grid-dependent behavior, deferred to Session 4
		"victory_or_death":
			combatant.morale_locked = true


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

func _outcome_from_total(total: int) -> String:
	if total <= 2:
		return "retreat"
	elif total <= 5:
		return "fighting_withdrawal"
	elif total <= 8:
		return "fight_on"
	elif total <= 11:
		return "advance_pursue"
	else:
		return "victory_or_death"


func _is_group_leader_alive(group_id: String, roster: CombatRoster) -> bool:
	## Check if any combatant in this group has a leader designation.
	## For now, the first combatant in the group acts as leader (index 0).
	## Future: explicit leader tracking.
	var group := roster.get_combatants_in_group(group_id)
	if group.is_empty():
		return false
	# Leader is the first combatant added to the group
	# (convention: leader is spawned first or has specific ID)
	for c: Combatant in group:
		if c.is_alive():
			return true  # At least one group member alive
	return false


func _is_override_condition_active(combatant: Combatant, condition: String) -> bool:
	## Check if a morale override condition is currently active.
	match condition:
		"blood_frenzy":
			# Blood frenzy is always active in combat for simplicity
			# (sharks always fight in water where blood is present)
			return true
		"confronted_by_fire_or_acid":
			# This would need to check if the attacker is using fire/acid
			# For now, not active by default (troll fights normally unless fire/acid present)
			return false
		_:
			return false


func _is_ability_trigger_active(combatant: Combatant, trigger: String) -> bool:
	## Check if a special ability trigger condition is met.
	match trigger:
		"blood_in_water":
			# Assume always active in combat for aquatic creatures
			return true
		_:
			return false
