class_name HenchmanLoyaltyResolver
extends RefCounted

## Phase G-2: Loyalty check resolution per rules/acore_equipment.xml:761-814.
##
## Morale base = 0 + employer's CHA modifier.
## Command proficiency: +2.
## +1 per level-up while in service.
## -1 per calamity.
## Grudging: next roll -1.
## Fanatic: +2 all future rolls.
##
## Loyalty roll: 2d6 + morale score.
## Outcomes: hostility, resignation, grudging, loyal, fanatic.

## Calculates the base morale score for a newly hired henchman.
## [param employer_cha_mod] is the employer's CHA ability modifier.
## [param employer_has_command] is true if the employer has Command proficiency.
static func base_morale(employer_cha_mod: int, employer_has_command: bool = false) -> int:
	var score := employer_cha_mod
	if employer_has_command:
		score += 2
	return score


## Assembles the total modifier for a loyalty roll from the henchman's current
## morale state.
static func loyalty_modifier(morale_score: int, is_grudging: bool = false,
		is_fanatic: bool = false) -> int:
	var total := morale_score
	if is_grudging:
		total -= 1
	if is_fanatic:
		total += 2
	return total


## Resolves a loyalty check: rolls 2d6 + total_modifier and returns a result
## Dictionary with keys: {roll, modifier, extra_modifier_breakdown, total,
## outcome, morale_delta, clear_grudging, set_fanatic, departs}.
##
## [param extra_modifiers] (Prereq.7 extension per gdd-settlement-economy.md §11.2):
## optional `{source_label: int_modifier}` dict that contributes additional
## integer adjustments on top of morale + grudging + fanatic. Phase 10B.3's
## order_hijink handler uses this for the RAW hijink-overload (-1 per extra
## hijink beyond one per month per acore-campaign-hijinks.xml:488-494) and
## underboss-strain (-1 per additional 10% over the 20% threshold per
## ax_campaign_play.xml:1213-1214) modifiers. Empty dict (the default) makes
## this a no-op — existing callers are unaffected.
##
## The [param dice] fixture seam is preserved unchanged. The new modifier
## path is summed in this function's body, OUTSIDE `loyalty_modifier(...)`,
## so direct callers of the helper keep the same RAW morale+grudging+fanatic
## semantic.
static func resolve_loyalty_check(morale_score: int, is_grudging: bool = false,
		is_fanatic: bool = false, dice = null,
		extra_modifiers: Dictionary = {}) -> Dictionary:
	var mod := loyalty_modifier(morale_score, is_grudging, is_fanatic)
	for source in extra_modifiers:
		mod += int(extra_modifiers[source])
	var roll := _roll_2d6(dice)
	var total := roll + mod
	var outcome: String = HenchmanTables.loyalty_result(total)

	var result := {
		"roll": roll,
		"modifier": mod,
		"extra_modifier_breakdown": extra_modifiers.duplicate(),
		"total": total,
		"outcome": outcome,
		"morale_delta": 0,
		"clear_grudging": false,
		"set_fanatic": false,
		"departs": false,
	}

	match outcome:
		HenchmanTables.LOYALTY_HOSTILITY:
			result["departs"] = true
		HenchmanTables.LOYALTY_RESIGNATION:
			result["departs"] = true
		HenchmanTables.LOYALTY_GRUDGING:
			pass  # caller marks is_grudging on henchman_state
		HenchmanTables.LOYALTY_LOYAL:
			result["clear_grudging"] = true
		HenchmanTables.LOYALTY_FANATIC:
			result["set_fanatic"] = true
			result["clear_grudging"] = true

	return result


## Resolves a hiring reaction roll: 2d6 + CHA modifier + situational mods.
## Returns {roll, modifier, total, outcome, morale_bonus}.
static func resolve_hiring_reaction(cha_modifier: int, situational_mod: int = 0,
		dice = null) -> Dictionary:
	var roll := _roll_2d6(dice)
	var mod := cha_modifier + situational_mod
	var total := roll + mod
	var outcome: String = HenchmanTables.hiring_reaction(total)
	var morale_bonus := 1 if outcome == HenchmanTables.HIRE_ACCEPT_ELAN else 0

	return {
		"roll": roll,
		"modifier": mod,
		"total": total,
		"outcome": outcome,
		"morale_bonus": morale_bonus,
	}


static func _roll_2d6(dice) -> int:
	if dice != null and dice.has_method("roll"):
		return int(dice.roll(2, 6))
	return (randi() % 6 + 1) + (randi() % 6 + 1)
