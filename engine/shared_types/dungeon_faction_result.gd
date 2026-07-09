class_name DungeonFactionGenerationResult
extends RefCounted

## Output bundle of DungeonFactionGenerator.generate()
## (`gdd-dungeon-factions.md` §7). Holds the identified factions, their
## relationships, solitary threats, and the derived territory map. Consumed by
## FF-5, the combat/wandering/reaction subsystems, and DungeonFactionRepository
## (which persists the first three; the territory map is rebuilt on load).


var dungeon_id: String = ""
var seed: int = 0

var factions: Array[DungeonFaction] = []
var relationships: Array[DungeonFactionRelationship] = []
var solitary_threats: Array[DungeonSolitaryThreat] = []
var territory_map: DungeonTerritoryMap = null

var warnings: Array[String] = []


func faction_by_id(faction_id: String) -> DungeonFaction:
	for f in factions:
		if f.id == faction_id:
			return f
	return null


## The faction controlling [param room_id], or null (unclaimed / contested / threat).
func faction_controlling_room(room_id: int) -> DungeonFaction:
	if territory_map == null:
		return null
	var fid: String = territory_map.controller_of(room_id)
	if fid == "":
		return null
	return faction_by_id(fid)


## The relationship record for an unordered faction pair, or null if none.
func relationship_between(a_id: String, b_id: String) -> DungeonFactionRelationship:
	for r in relationships:
		if (r.faction_a_id == a_id and r.faction_b_id == b_id) \
				or (r.faction_a_id == b_id and r.faction_b_id == a_id):
			return r
	return null
