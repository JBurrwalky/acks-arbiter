class_name RumorData
extends RefCounted

## A rumor in the runtime `rumors` table. Session Q-1 schema.
## generation/gdd-quest-rumor-system.md §4.1 (rumor runtime fields), §12.
##
## RumorRegistry is the one writer of rumor state. No `reliability` field —
## accuracy is discoverable only by verification (§4.4/O-Q3).

const SOURCE_TYPES: Array = [
	"poi", "dungeon", "lair", "political", "settlement", "npc",
	"quest", "historical",
]

const ACCURACY_TIERS: Array = [
	"true", "exaggerated", "understated", "misleading", "false",
]

const KNOWLEDGE_CATEGORIES: Array = [
	"local", "professional", "political", "criminal", "religious",
	"military", "dungeon", "personal", "historical",
]

const NPC_TIERS: Array = ["C", "B", "A"]
const FRESHNESS_STATES: Array = ["persistent", "current", "stale"]

var id: String = ""
var campaign_id: String = ""
var source_type: String = ""
var source_id: String = ""
var source_quest_id: String = ""
var content_hint: String = ""
var narrated_text: String = ""
var accuracy: String = "true"
var accuracy_detail: String = ""
var knowledge_category: String = "local"
var origin_hex: String = ""
var settlement_range: int = 5
var min_npc_tier: String = "C"
var freshness: String = "current"
# runtime state
var known_to_party: bool = false
var verified: bool = false
var first_heard_day: int = -1  # -1 = null (not yet heard)
var created_day: int = 0
var expires_day: int = -1  # -1 = null (persistent)


static func from_dict(data: Dictionary) -> RumorData:
	var r := RumorData.new()
	r.id = data.get("id", "")
	r.campaign_id = data.get("campaign_id", "")
	r.source_type = data.get("source_type", "")
	r.source_id = data.get("source_id", "")
	r.source_quest_id = _str_or_empty(data.get("source_quest_id"))
	r.content_hint = data.get("content_hint", "")
	r.narrated_text = data.get("narrated_text", "")
	r.accuracy = data.get("accuracy", "true")
	r.accuracy_detail = data.get("accuracy_detail", "")
	r.knowledge_category = data.get("knowledge_category", "local")
	r.origin_hex = data.get("origin_hex", "")
	r.settlement_range = int(data.get("settlement_range", 5))
	r.min_npc_tier = data.get("min_npc_tier", "C")
	r.freshness = data.get("freshness", "current")
	r.known_to_party = bool(int(data.get("known_to_party", 0)))
	r.verified = bool(int(data.get("verified", 0)))
	r.first_heard_day = _int_or_default(data.get("first_heard_day"), -1)
	r.created_day = int(data.get("created_day", 0))
	r.expires_day = _int_or_default(data.get("expires_day"), -1)
	return r


func to_dict() -> Dictionary:
	return {
		"id": id,
		"campaign_id": campaign_id,
		"source_type": source_type,
		"source_id": source_id,
		"source_quest_id": source_quest_id,
		"content_hint": content_hint,
		"narrated_text": narrated_text,
		"accuracy": accuracy,
		"accuracy_detail": accuracy_detail,
		"knowledge_category": knowledge_category,
		"origin_hex": origin_hex,
		"settlement_range": settlement_range,
		"min_npc_tier": min_npc_tier,
		"freshness": freshness,
		"known_to_party": 1 if known_to_party else 0,
		"verified": 1 if verified else 0,
		"first_heard_day": first_heard_day,
		"created_day": created_day,
		"expires_day": expires_day,
	}


static func _str_or_empty(v) -> String:
	return "" if v == null else String(v)


static func _int_or_default(v, default_value: int) -> int:
	return default_value if v == null else int(v)
