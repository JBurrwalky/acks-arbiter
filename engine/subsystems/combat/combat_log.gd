class_name CombatLog
extends RefCounted

## CombatLog — structured, queryable record of all events in a combat encounter.
##
## Replaces the raw _round_events / all_events arrays in CombatController.
## Provides typed entries and filter methods for UI display and post-combat summary.


# ---------------------------------------------------------------------------
# Entry type enum
# ---------------------------------------------------------------------------

enum EntryType {
	ROUND_START,
	ATTACK,
	DAMAGE,
	SPELL,
	MOVEMENT,
	MORALE,
	COMBATANT_DOWNED,
	MORTAL_WOUND,
	DEATH,
	FLEE,
	CLEAVE,
	COMBAT_END,
}


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _entries: Array = []
var _next_timestamp: int = 0


# ---------------------------------------------------------------------------
# Write API
# ---------------------------------------------------------------------------

func add_entry(
		type: int,
		round: int,
		actor_id: String,
		target_id: String,
		data: Dictionary) -> void:
	## Append a new log entry.
	_entries.append({
		"type":      type,
		"round":     round,
		"actor_id":  actor_id,
		"target_id": target_id,
		"data":      data,
		"timestamp": _next_timestamp,
	})
	_next_timestamp += 1


# ---------------------------------------------------------------------------
# Read API
# ---------------------------------------------------------------------------

func get_all_entries() -> Array:
	## Returns all log entries in insertion order.
	return _entries.duplicate()


func get_round_entries(round_number: int) -> Array:
	## Returns all entries from the specified round.
	var result: Array = []
	for entry in _entries:
		if entry["round"] == round_number:
			result.append(entry)
	return result


func get_entries_by_type(type: int) -> Array:
	## Returns all entries of the given EntryType.
	var result: Array = []
	for entry in _entries:
		if entry["type"] == type:
			result.append(entry)
	return result


func get_entries_for_combatant(combatant_id: String) -> Array:
	## Returns all entries where actor_id OR target_id matches.
	var result: Array = []
	for entry in _entries:
		if entry["actor_id"] == combatant_id or entry["target_id"] == combatant_id:
			result.append(entry)
	return result


func get_downed_entries() -> Array:
	## Convenience shortcut: entries where type == COMBATANT_DOWNED.
	return get_entries_by_type(EntryType.COMBATANT_DOWNED)


func get_mortal_wound_entries() -> Array:
	## Convenience shortcut: entries where type == MORTAL_WOUND.
	return get_entries_by_type(EntryType.MORTAL_WOUND)


func get_summary() -> Dictionary:
	## Returns a high-level summary of the combat.
	## Keys: rounds, attacks, kills, damage_dealt (Dict: combatant_id -> int), mortal_wounds (Array).
	var rounds: int = 0
	var attacks: int = 0
	var kills: int = 0
	var damage_dealt: Dictionary = {}
	var mortal_wounds: Array = []

	for entry in _entries:
		match entry["type"]:
			EntryType.ROUND_START:
				rounds += 1
			EntryType.ATTACK:
				attacks += 1
			EntryType.DEATH:
				kills += 1
			EntryType.DAMAGE:
				var target: String = entry["target_id"]
				var amount: int = int(entry["data"].get("amount", 0))
				if not damage_dealt.has(target):
					damage_dealt[target] = 0
				damage_dealt[target] += amount
			EntryType.MORTAL_WOUND:
				mortal_wounds.append(entry["data"])

	return {
		"rounds":       rounds,
		"attacks":      attacks,
		"kills":        kills,
		"damage_dealt": damage_dealt,
		"mortal_wounds": mortal_wounds,
	}


func to_array() -> Array:
	## Serializes all entries for persistence or signal payloads.
	## Returns a deep copy so callers cannot mutate internal state.
	return _entries.duplicate(true)
