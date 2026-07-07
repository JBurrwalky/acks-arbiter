class_name NpcRelationshipData
extends RefCounted

## Layer 1 of the NPC dialogue memory model (gdd-npc-dialogue.md §8.1).
##
## One row per NPC x party — the mechanical spine of the two-track attitude
## model. `attitude` is the 7-state vocabulary: the diplomatic five
## (hostile / unfriendly / neutral / indifferent / friendly) plus intimidation's
## fearful / cowed variants (Attitude.FEARFUL / Attitude.COWED). `influence_*`
## fields drive the Track-1 (relationship-tone) time ladder counter only —
## per-issue (Track-2) ladders live in NpcIssueData. Mirrors the
## `npc_relationships` table. Boolean `is_intimidated` stored as INTEGER 0/1.

const ATTITUDES: Array = [
	"hostile", "unfriendly", "neutral", "indifferent", "friendly", "fearful", "cowed",
]

var id: String = ""
var campaign_id: String = ""
var npc_id: String = ""
var party_id: String = ""
var attitude: String = "neutral"
var is_intimidated: bool = false
var influence_attempt_count: int = 0
var next_attempt_available_at: int = 0
var favors_owed_to_party: int = 0
var favors_owed_by_party: int = 0
var first_met_day: int = -1          # -1 = unknown/unset (stored as SQL NULL)
var last_interaction_day: int = -1   # -1 = unknown/unset (stored as SQL NULL)
var role_tags: Array = []            # e.g. ["employer", "quest_giver", "rival"]


static func from_dict(data: Dictionary) -> NpcRelationshipData:
	var r := NpcRelationshipData.new()
	r.id = data.get("id", "")
	r.campaign_id = data.get("campaign_id", "")
	r.npc_id = data.get("npc_id", "")
	r.party_id = data.get("party_id", "")
	r.attitude = data.get("attitude", "neutral")
	r.is_intimidated = bool(int(data.get("is_intimidated", 0)))
	r.influence_attempt_count = int(data.get("influence_attempt_count", 0))
	r.next_attempt_available_at = int(data.get("next_attempt_available_at", 0))
	r.favors_owed_to_party = int(data.get("favors_owed_to_party", 0))
	r.favors_owed_by_party = int(data.get("favors_owed_by_party", 0))
	r.first_met_day = -1 if data.get("first_met_day") == null else int(data.get("first_met_day", -1))
	r.last_interaction_day = -1 if data.get("last_interaction_day") == null else int(data.get("last_interaction_day", -1))
	r.role_tags = _parse_tags(data.get("role_tags", []))
	return r


func to_dict() -> Dictionary:
	return {
		"id": id,
		"campaign_id": campaign_id,
		"npc_id": npc_id,
		"party_id": party_id,
		"attitude": attitude,
		"is_intimidated": 1 if is_intimidated else 0,
		"influence_attempt_count": influence_attempt_count,
		"next_attempt_available_at": next_attempt_available_at,
		"favors_owed_to_party": favors_owed_to_party,
		"favors_owed_by_party": favors_owed_by_party,
		"first_met_day": null if first_met_day < 0 else first_met_day,
		"last_interaction_day": null if last_interaction_day < 0 else last_interaction_day,
		"role_tags": JSON.stringify(role_tags),
	}


## role_tags round-trips as a JSON string in the DB but as an Array in memory.
static func _parse_tags(raw) -> Array:
	if raw is Array:
		return (raw as Array).duplicate()
	if raw is String and not (raw as String).is_empty():
		var parsed = JSON.parse_string(raw)
		if parsed is Array:
			return parsed
	return []
