class_name NpcMemoryData
extends RefCounted

## Layer 2 of the NPC dialogue memory model (gdd-npc-dialogue.md §8.1, §8.2).
##
## An episodic memory an NPC holds about a party. `summary` is a human-readable
## 1-3 sentence line (the deterministic summarizer writes it from the move log;
## an LLM may later rewrite it in voice but never overwrites `facts`). `facts`
## is a JSON array of tag Dictionaries (rumor-compatible for future gossip
## propagation, §8.4). `importance` 1..5 drives top-K recall (§8.3). Mirrors the
## `npc_memories` table.

const KINDS: Array = [
	"conversation", "event", "promise", "debt", "grudge",
	"gift", "deception_by_npc", "deception_suffered",
]

var id: String = ""
var campaign_id: String = ""
var npc_id: String = ""
var party_id: String = ""
var kind: String = "conversation"
var summary: String = ""
var facts: Array = []                 # Array of Dictionaries: [{"promised": "escort to Karn"}]
var attitude_after: String = ""       # "" = unset (stored as SQL NULL)
var importance: int = 1
var created_day: int = 0
var last_recalled_day: int = -1       # -1 = never recalled (stored as SQL NULL)
var source_session_id: String = ""


static func from_dict(data: Dictionary) -> NpcMemoryData:
	var m := NpcMemoryData.new()
	m.id = data.get("id", "")
	m.campaign_id = data.get("campaign_id", "")
	m.npc_id = data.get("npc_id", "")
	m.party_id = "" if data.get("party_id") == null else data.get("party_id", "")
	m.kind = data.get("kind", "conversation")
	m.summary = data.get("summary", "")
	m.facts = _parse_facts(data.get("facts", []))
	m.attitude_after = "" if data.get("attitude_after") == null else data.get("attitude_after", "")
	m.importance = int(data.get("importance", 1))
	m.created_day = int(data.get("created_day", 0))
	m.last_recalled_day = -1 if data.get("last_recalled_day") == null else int(data.get("last_recalled_day", -1))
	m.source_session_id = "" if data.get("source_session_id") == null else data.get("source_session_id", "")
	return m


func to_dict() -> Dictionary:
	return {
		"id": id,
		"campaign_id": campaign_id,
		"npc_id": npc_id,
		"party_id": null if party_id.is_empty() else party_id,
		"kind": kind,
		"summary": summary,
		"facts": JSON.stringify(facts),
		"attitude_after": null if attitude_after.is_empty() else attitude_after,
		"importance": importance,
		"created_day": created_day,
		"last_recalled_day": null if last_recalled_day < 0 else last_recalled_day,
		"source_session_id": null if source_session_id.is_empty() else source_session_id,
	}


static func _parse_facts(raw) -> Array:
	if raw is Array:
		return (raw as Array).duplicate()
	if raw is String and not (raw as String).is_empty():
		var parsed = JSON.parse_string(raw)
		if parsed is Array:
			return parsed
	return []
