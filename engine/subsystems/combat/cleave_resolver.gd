class_name CleaveResolver
extends RefCounted

## Manages cleave eligibility and budget per round.
##
## ACKS cleave rules:
## - Trigger: kill or incapacitate with melee or missile attack.
## - Fighter progression: up to HD cleave attacks per round.
## - Cleric/Thief progression: up to HD/2 (floor) per round.
## - Mage progression: no cleave.
## - Normal Man (NM): no cleave.
## - Cleave cap is per-round across all attacks in the routine.

# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

## Tracks cleaves used this round per combatant.
var _cleaves_used: Dictionary = {}  # combatant_id -> int


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Reset all cleave budgets for a new round.
func reset_round() -> void:
	_cleaves_used.clear()


## Returns the maximum number of cleave attacks this combatant can make per round.
func get_max_cleaves(combatant: Combatant) -> int:
	var progression := combatant.get_combat_progression()
	var hd := combatant.get_level_or_hd()
	match progression:
		"fighter":
			return hd
		"cleric", "thief":
			return hd / 2  # Integer division = floor
		"mage", "normal_man":
			return 0
		_:
			return 0


## Returns whether this combatant can still cleave this round.
func can_cleave(combatant: Combatant) -> bool:
	var max_cleaves := get_max_cleaves(combatant)
	if max_cleaves <= 0:
		return false
	var used: int = _cleaves_used.get(combatant.id, 0)
	return used < max_cleaves


## Record that a cleave attack was made.
func record_cleave(combatant_id: String) -> void:
	if not _cleaves_used.has(combatant_id):
		_cleaves_used[combatant_id] = 0
	_cleaves_used[combatant_id] += 1


## Returns the number of cleaves remaining for this combatant this round.
func get_cleaves_remaining(combatant: Combatant) -> int:
	var max_cleaves := get_max_cleaves(combatant)
	var used: int = _cleaves_used.get(combatant.id, 0)
	return maxi(0, max_cleaves - used)
