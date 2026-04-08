class_name InitiativeResolver
extends RefCounted

## Resolves initiative order for a combat round.
##
## ACKS initiative: each combatant rolls 1d6 + DEX modifier + initiative modifiers.
## Highest acts first. Ties act simultaneously (both act, damage applied after both).
## Uses DiceSystem for rolls (respects dice mode and overrides).

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

## Result for a single combatant's initiative.
## { combatant_id: String, roll: int, modifier: int, total: int }

# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _dice_system = null  # DiceSystem autoload or mock


func _init(dice_system = null) -> void:
	_dice_system = dice_system


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Roll initiative for all alive combatants and return sorted results.
## Returns Array[Dictionary] sorted by total (highest first).
## Ties share the same total — the caller handles simultaneous resolution.
func resolve(combatants: Array[Combatant]) -> Array[Dictionary]:
	var results: Array[Dictionary] = []

	for c in combatants:
		if not c.is_alive():
			continue

		var roll: int
		var modifier := c.get_initiative_modifier()

		if _dice_system != null:
			var result: RollResult = _dice_system.roll_digital(6, 1, 0, "initiative")
			roll = result.raw_total
		else:
			# Deterministic fallback for tests without DiceSystem
			roll = 3

		var total := roll + modifier

		results.append({
			"combatant_id": c.id,
			"roll": roll,
			"modifier": modifier,
			"total": total,
		})

	# Sort by total descending (highest first)
	results.sort_custom(_sort_by_total_desc)
	return results


## Groups initiative results by total for simultaneous resolution.
## Returns Array[Array[Dictionary]] — each inner array is a group of
## combatants that act simultaneously.
func group_simultaneous(initiative_order: Array[Dictionary]) -> Array:
	if initiative_order.is_empty():
		return []

	var groups: Array = []
	var current_group: Array = [initiative_order[0]]
	var current_total: int = initiative_order[0]["total"]

	for i in range(1, initiative_order.size()):
		if initiative_order[i]["total"] == current_total:
			current_group.append(initiative_order[i])
		else:
			groups.append(current_group)
			current_group = [initiative_order[i]]
			current_total = initiative_order[i]["total"]

	groups.append(current_group)
	return groups


# ---------------------------------------------------------------------------
# Private
# ---------------------------------------------------------------------------

static func _sort_by_total_desc(a: Dictionary, b: Dictionary) -> bool:
	if a["total"] != b["total"]:
		return a["total"] > b["total"]
	# Stable tie-break by combatant_id for determinism
	return a["combatant_id"] < b["combatant_id"]
