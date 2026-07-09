class_name DungeonTerritoryEntry
extends RefCounted

## One room's faction-control status in a DungeonTerritoryMap
## (`gdd-dungeon-factions.md` §7.4). A derived lookup value — rebuilt from the
## faction/threat/relationship records, not independently persisted.


# ---------------------------------------------------------------------------
# Status vocabulary (§4 / §7.4)
# ---------------------------------------------------------------------------

const STATUS_CORE := "core"                       ## lair + rooms with faction members
const STATUS_PATROL := "patrol"                   ## empty rooms the faction controls
const STATUS_FRONTIER := "frontier"               ## edge rooms adjacent to another faction/zone
const STATUS_CONTESTED := "contested"             ## overlapping expansion of two factions
const STATUS_UNCLAIMED := "unclaimed"             ## no faction controls this room
const STATUS_SOLITARY_THREAT := "solitary_threat_zone"

const VALID_STATUSES: Array[String] = [
	STATUS_CORE, STATUS_PATROL, STATUS_FRONTIER, STATUS_CONTESTED,
	STATUS_UNCLAIMED, STATUS_SOLITARY_THREAT,
]


var status: String = STATUS_UNCLAIMED
var controlling_faction_id: String = ""           ## "" for unclaimed / contested / threat
var contesting_faction_ids: Array[String] = []    ## for contested rooms
var solitary_threat_id: String = ""               ## for solitary_threat_zone rooms
