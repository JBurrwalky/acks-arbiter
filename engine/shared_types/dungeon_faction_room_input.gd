class_name DungeonFactionRoomInput
extends RefCounted

## One room node in the faction generator's input graph
## (`gdd-dungeon-factions.md` §3 / §4). Carries the room's stocked monster
## placements and its outgoing graph edges. Built by DungeonFactionInputBuilder
## from a DungeonLayout, or by hand in fixtures/tests.


var id: int = -1
var level: int = 1                                 ## dungeon level this room is on (§10 multi-level)
var original_purpose: String = ""                  ## flavor for naming (§9), optional

var placements: Array[DungeonFactionMonsterPlacement] = []
var neighbors: Array[DungeonFactionEdge] = []


## True if any placement in this room is flagged as a lair.
func has_lair() -> bool:
	for p in placements:
		if p.is_lair:
			return true
	return false


## True if the room currently holds any stocked monster (of any kind).
func is_occupied() -> bool:
	return not placements.is_empty()


## Total number-appearing across all placements in this room.
func total_monsters() -> int:
	var n: int = 0
	for p in placements:
		n += p.number
	return n
