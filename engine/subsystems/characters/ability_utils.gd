class_name AbilityUtils
extends RefCounted

## Utility functions for ACKS ability scores.
## CharacterData.ability_modifier() handles score -> modifier lookup.
## This class adds generation-time and gameplay calculations.


static func get_xp_adjustment(prime_requisite_scores: Array) -> int:
	## Returns XP adjustment percentage based on prime requisite scores.
	## Uses the LOWEST prime requisite score (per ACKS rules).
	## Returns: -10, -5, 0, +5, or +10
	if prime_requisite_scores.is_empty():
		return 0
	var lowest: int = 18
	for score in prime_requisite_scores:
		if int(score) < lowest:
			lowest = int(score)
	if lowest >= 16:
		return 10
	if lowest >= 13:
		return 5
	if lowest >= 9:
		return 0
	if lowest >= 6:
		return -5
	return -10


static func get_max_henchmen(cha_score: int) -> int:
	## Returns maximum henchmen allowed: 4 + CHA modifier, clamped [1, 7].
	var mod := CharacterData.ability_modifier(cha_score)
	return clampi(4 + mod, 1, 7)


static func get_loyalty_modifier(cha_score: int) -> int:
	## CHA modifier applied to henchman morale/loyalty rolls.
	return CharacterData.ability_modifier(cha_score)


static func get_reaction_modifier(cha_score: int) -> int:
	## CHA modifier applied to NPC reaction rolls.
	return CharacterData.ability_modifier(cha_score)


static func get_languages_bonus(int_score: int) -> int:
	## INT modifier determines bonus languages (minimum 0).
	return maxi(CharacterData.ability_modifier(int_score), 0)
