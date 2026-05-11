class_name MagicResearchThrowUtil
extends RefCounted

## Magic Research Throw helper (Phase 10A.2 — shared across consecrate_fields,
## consecrate_ruler, and Phase 10B.1 magic_research handlers).
##
## Per acore-campaign-general-and-magic-research.xml §general_magic_research_throw
## L53-61 + §magic_research_target_by_level L25-51:
##   - Target by class level: 18+ at L0, 16+ L1, 15+ L2, 14+ L3, 13+ L4,
##     12+ L5, 11+ L6, 10+ L7, 9+ L8, 8+ L9, 7+ L10, 6+ L11, 5+ L12, 4+ L13,
##     3+ L14+. Linear progression: target = max(3, 18 - level) for level 0-4
##     uses a slightly different curve; the table is the source of truth.
##   - Add caster's Intelligence bonus to the roll.
##   - Add Magical Engineering proficiency rank if any.
##   - Unmodified 1-3 always fails (regardless of modifiers).
##   - Returns:
##       { success: bool, natural_one: bool, raw_roll: int, modified_total: int,
##         target: int, breakdown: Array }
##
## Project-level extensions (project-designed, not RAW):
##   - For divine consecration activities, the caster's Wisdom bonus is used
##     instead of Intelligence (per the Q13-pattern: divine = WIS-modified
##     throws). The caller passes ability_mod_kind="wis" or "int" to control
##     which bonus applies.


const TARGET_BY_LEVEL := {
	0: 18,
	1: 16,
	2: 15,
	3: 14,
	4: 13,
	5: 12,
	6: 11,
	7: 10,
	8: 9,
	9: 8,
	10: 7,
	11: 6,
	12: 5,
	13: 4,
	14: 3,
}


## Returns the target value for a given caster level. Levels above 14 cap at 3.
static func target_for_level(level: int) -> int:
	if level >= 14:
		return 3
	if level < 0:
		return 18
	return int(TARGET_BY_LEVEL.get(level, 18))


## Performs a magic research throw and returns the resolution dict.
## ability_mod_kind: "int" (default) or "wis" — RAW uses INT; divine
## consecration activities pass "wis" per Q13-pattern.
## roll_type: name passed to DiceSystem.roll_digital for the dice log.
static func make_throw(
	caster_level: int,
	ability_modifier: int,
	magical_engineering_rank: int = 0,
	roll_type: String = "magic_research_throw",
) -> Dictionary:
	var target: int = target_for_level(caster_level)
	var roll_result: RollResult = DiceSystem.roll_digital(20, 1, 0, roll_type)
	var raw_roll: int = roll_result.modified_total
	var modified: int = raw_roll + ability_modifier + magical_engineering_rank
	var natural_one: bool = raw_roll == 1
	var natural_1_3: bool = raw_roll <= 3
	# RAW: unmodified 1-3 always fails. natural 1 may have stronger consequences
	# (e.g. consecrate_fields awry-result).
	var success: bool = (not natural_1_3) and (modified >= target)
	return {
		"success": success,
		"natural_one": natural_one,
		"natural_1_3": natural_1_3,
		"raw_roll": raw_roll,
		"modified_total": modified,
		"target": target,
		"ability_modifier": ability_modifier,
		"magical_engineering_rank": magical_engineering_rank,
	}


## Convenience: read INT modifier from a character row.
static func int_mod_for_character(character: Dictionary) -> int:
	return _ability_mod(int(character.get("intelligence", 10)))


## Convenience: read WIS modifier from a character row.
static func wis_mod_for_character(character: Dictionary) -> int:
	return _ability_mod(int(character.get("wisdom", 10)))


## ACKS ability modifier table: 3 → -3, 4-5 → -2, 6-8 → -1, 9-12 → 0,
## 13-15 → +1, 16-17 → +2, 18 → +3.
static func _ability_mod(score: int) -> int:
	if score <= 3:   return -3
	if score <= 5:   return -2
	if score <= 8:   return -1
	if score <= 12:  return 0
	if score <= 15:  return 1
	if score <= 17:  return 2
	return 3
