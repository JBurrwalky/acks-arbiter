class_name DungeonFactionRelationship
extends RefCounted

## An inter-faction relationship on a single dungeon level
## (`gdd-dungeon-factions.md` §5.1 / §7.3). One record per unordered faction
## pair. Consumed by the reaction-roll system (relationship reaction modifiers),
## alert propagation (allied/vassal alert crossing), and the wandering-monster
## system (contested-zone 50/50 source selection).


# ---------------------------------------------------------------------------
# Relationship vocabulary (§5.1)
# ---------------------------------------------------------------------------

const REL_ALLIED := "allied"
const REL_NEUTRAL := "neutral"
const REL_RIVAL := "rival"
const REL_HOSTILE := "hostile"
const REL_VASSAL := "vassal"
const REL_UNAWARE := "unaware"

const VALID_RELATIONSHIPS: Array[String] = [
	REL_ALLIED, REL_NEUTRAL, REL_RIVAL, REL_HOSTILE, REL_VASSAL, REL_UNAWARE,
]


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var id: String = ""
var dungeon_id: String = ""

## Unordered pair. For `vassal`, faction_a is the MASTER and faction_b the
## VASSAL (directional within an otherwise-unordered record).
var faction_a_id: String = ""
var faction_b_id: String = ""
var relationship: String = REL_NEUTRAL

## Rooms disputed between the two (populated for rival/hostile). These become
## higher-frequency contested wandering zones (§4.4, §6.1).
var contested_room_ids: Array[int] = []

var notes: String = ""


# ---------------------------------------------------------------------------
# Convenience
# ---------------------------------------------------------------------------

## True if this record concerns the given faction id.
func involves(faction_id: String) -> bool:
	return faction_a_id == faction_id or faction_b_id == faction_id


## The other faction id in the pair, or "" if [param faction_id] isn't in it.
func other(faction_id: String) -> String:
	if faction_a_id == faction_id:
		return faction_b_id
	if faction_b_id == faction_id:
		return faction_a_id
	return ""


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

func to_row() -> Dictionary:
	return {
		"id": id,
		"dungeon_id": dungeon_id,
		"faction_a_id": faction_a_id,
		"faction_b_id": faction_b_id,
		"relationship": relationship,
		"contested_room_ids": JSON.stringify(contested_room_ids),
		"notes": notes,
	}


static func from_row(data: Dictionary) -> DungeonFactionRelationship:
	var r := DungeonFactionRelationship.new()
	r.id = _s(data, "id")
	r.dungeon_id = _s(data, "dungeon_id")
	r.faction_a_id = _s(data, "faction_a_id")
	r.faction_b_id = _s(data, "faction_b_id")
	r.relationship = _s(data, "relationship", REL_NEUTRAL)
	r.contested_room_ids = DungeonFaction._decode_int_array(_s(data, "contested_room_ids"))
	r.notes = _s(data, "notes")
	return r


static func _s(data: Dictionary, key: String, default_val: String = "") -> String:
	var v: Variant = data.get(key, default_val)
	return String(v) if v != null else default_val
