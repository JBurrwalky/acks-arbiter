class_name QuestData
extends RefCounted

## A quest in the runtime `quests` table. Session Q-1 schema.
## generation/gdd-quest-rumor-system.md §6.6 (fields), §12 (SQLite shape).
##
## QuestRegistry is the one writer of quest state; this is the plain data
## carrier between CampaignRepository rows and callers.

const STATUSES: Array = [
	"available", "accepted", "completed", "failed", "expired", "abandoned",
]

const THREAT_TYPES: Array = [
	"monster_lair", "dungeon", "brigand", "creature_bounty", "recovery",
	"escort", "delivery", "domain_conquest", "reconnaissance", "faction_goal",
]

const COMPLETION_TYPES: Array = [
	"clear_dungeon", "clear_lair", "kill_target", "retrieve_item",
	"escort_npc", "deliver_item", "hold_territory", "scout_hex",
	"build_structure", "faction_goal",
]

const COMPLETION_VERIFIED_BY: Array = ["questgiver_report", "automatic", "witness"]
const POSTING_TYPES: Array = ["personal", "posted", "broadcast"]

var id: String = ""
var campaign_id: String = ""
var status: String = "available"
# questgiver
var questgiver_id: String = ""
var questgiver_faction_id: String = ""
var questgiver_settlement_id: String = ""
var questgiver_motivation: String = ""
# the problem
var threat_type: String = ""
var threat_source_id: String = ""
var threat_hex: String = ""
var threat_description_hint: String = ""
# completion
var completion_type: String = ""
var completion_target_id: String = ""
var completion_verified_by: String = "automatic"
var is_complete: bool = false
var progress: Dictionary = {}
# narration (LLM/template; *_placeholder value until filled)
var title: String = ""
var description: String = ""
var questgiver_dialogue: String = ""
var completion_dialogue: String = ""
# distribution
var posting_type: String = "posted"
var posting_range: int = 8
# timing
var created_day: int = 0
var expires_day: int = -1  # -1 = null (never expires)
var accepted_day: int = -1
var completed_day: int = -1
# party tracking
var accepting_pc_id: String = ""
var reward_recipient_pc_id: String = ""
# faction bridge (§7.9/§11.2)
var faction_goal_id: String = ""


static func from_dict(data: Dictionary) -> QuestData:
	var q := QuestData.new()
	q.id = data.get("id", "")
	q.campaign_id = data.get("campaign_id", "")
	q.status = data.get("status", "available")
	q.questgiver_id = _str_or_empty(data.get("questgiver_id"))
	q.questgiver_faction_id = _str_or_empty(data.get("questgiver_faction_id"))
	q.questgiver_settlement_id = _str_or_empty(data.get("questgiver_settlement_id"))
	q.questgiver_motivation = data.get("questgiver_motivation", "")
	q.threat_type = data.get("threat_type", "")
	q.threat_source_id = data.get("threat_source_id", "")
	q.threat_hex = data.get("threat_hex", "")
	q.threat_description_hint = data.get("threat_description_hint", "")
	q.completion_type = data.get("completion_type", "")
	q.completion_target_id = data.get("completion_target_id", "")
	q.completion_verified_by = data.get("completion_verified_by", "automatic")
	q.is_complete = bool(int(data.get("is_complete", 0)))
	q.progress = _parse_json_dict(data.get("progress", "{}"))
	q.title = data.get("title", "")
	q.description = data.get("description", "")
	q.questgiver_dialogue = data.get("questgiver_dialogue", "")
	q.completion_dialogue = data.get("completion_dialogue", "")
	q.posting_type = data.get("posting_type", "posted")
	q.posting_range = int(data.get("posting_range", 8))
	q.created_day = int(data.get("created_day", 0))
	q.expires_day = _int_or_default(data.get("expires_day"), -1)
	q.accepted_day = _int_or_default(data.get("accepted_day"), -1)
	q.completed_day = _int_or_default(data.get("completed_day"), -1)
	q.accepting_pc_id = _str_or_empty(data.get("accepting_pc_id"))
	q.reward_recipient_pc_id = _str_or_empty(data.get("reward_recipient_pc_id"))
	q.faction_goal_id = data.get("faction_goal_id", "")
	return q


func to_dict() -> Dictionary:
	return {
		"id": id,
		"campaign_id": campaign_id,
		"status": status,
		"questgiver_id": questgiver_id,
		"questgiver_faction_id": questgiver_faction_id,
		"questgiver_settlement_id": questgiver_settlement_id,
		"questgiver_motivation": questgiver_motivation,
		"threat_type": threat_type,
		"threat_source_id": threat_source_id,
		"threat_hex": threat_hex,
		"threat_description_hint": threat_description_hint,
		"completion_type": completion_type,
		"completion_target_id": completion_target_id,
		"completion_verified_by": completion_verified_by,
		"is_complete": 1 if is_complete else 0,
		"progress": JSON.stringify(progress),
		"title": title,
		"description": description,
		"questgiver_dialogue": questgiver_dialogue,
		"completion_dialogue": completion_dialogue,
		"posting_type": posting_type,
		"posting_range": posting_range,
		"created_day": created_day,
		"expires_day": expires_day,
		"accepted_day": accepted_day,
		"completed_day": completed_day,
		"accepting_pc_id": accepting_pc_id,
		"reward_recipient_pc_id": reward_recipient_pc_id,
		"faction_goal_id": faction_goal_id,
	}


static func _str_or_empty(v) -> String:
	return "" if v == null else String(v)


static func _int_or_default(v, default_value: int) -> int:
	return default_value if v == null else int(v)


static func _parse_json_dict(raw) -> Dictionary:
	if raw == null:
		return {}
	var parsed = JSON.parse_string(String(raw))
	return parsed if parsed is Dictionary else {}
