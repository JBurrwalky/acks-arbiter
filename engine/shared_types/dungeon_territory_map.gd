class_name DungeonTerritoryMap
extends RefCounted

## Room-id → DungeonTerritoryEntry lookup for one dungeon level
## (`gdd-dungeon-factions.md` §7.4). Derived output of territory assignment;
## rebuildable from the faction/threat/relationship records, so it is not
## independently persisted.


## { room_id: int -> DungeonTerritoryEntry }
var room_assignments: Dictionary = {}


## Return the entry for [param room_id]. Rooms never touched by assignment
## default to a fresh UNCLAIMED entry (never null).
func entry_for(room_id: int) -> DungeonTerritoryEntry:
	if room_assignments.has(room_id):
		return room_assignments[room_id]
	var e := DungeonTerritoryEntry.new()
	return e


func set_entry(room_id: int, entry: DungeonTerritoryEntry) -> void:
	room_assignments[room_id] = entry


## The status string for [param room_id] (UNCLAIMED if unassigned).
func status_of(room_id: int) -> String:
	return entry_for(room_id).status


## The controlling faction id for [param room_id] ("" if none).
func controller_of(room_id: int) -> String:
	return entry_for(room_id).controlling_faction_id


## All room ids assigned to [param faction_id] in any controlling status.
func rooms_of(faction_id: String) -> Array[int]:
	var out: Array[int] = []
	for rid in room_assignments:
		var e: DungeonTerritoryEntry = room_assignments[rid]
		if e.controlling_faction_id == faction_id:
			out.append(int(rid))
	out.sort()
	return out
