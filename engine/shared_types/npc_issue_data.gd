class_name NpcIssueData
extends RefCounted

## Layer 3 / Track 2 of the NPC dialogue memory model (gdd-npc-dialogue.md §8.1,
## §6.5). One row per outstanding-or-resolved extraordinary ask. Carries its own
## per-issue influence ladder counter (`attempt_count` / `next_attempt_available_at`,
## §6.3) independent of the relationship-tone (Track 1) ladder, and the negotiated
## `terms` package. NOT consumed until dialogue Phase 3 — landed in Phase 1 per the
## "whole approved data model in one pass" precedent. Mirrors the `npc_issues`
## table. `offense_fired` is stored as INTEGER 0/1.

const STATUSES: Array = ["open", "granted", "refused", "withdrawn", "expired"]
const RESULTS: Array = ["refused", "negotiable", "accepted", "accepted_enthusiastic"]

var id: String = ""
var campaign_id: String = ""
var npc_id: String = ""
var party_id: String = ""
var issue_key: String = ""            # e.g. "request_action:perform_hijink:spying"
var status: String = "open"
var last_result: String = ""          # "" = unset (stored as SQL NULL)
var attempt_count: int = 0
var next_attempt_available_at: int = 0
var terms: Dictionary = {}            # negotiated package (payment, favors, conditions)
var offense_fired: bool = false
var created_day: int = 0
var resolved_day: int = -1            # -1 = unresolved (stored as SQL NULL)


static func from_dict(data: Dictionary) -> NpcIssueData:
	var i := NpcIssueData.new()
	i.id = data.get("id", "")
	i.campaign_id = data.get("campaign_id", "")
	i.npc_id = data.get("npc_id", "")
	i.party_id = data.get("party_id", "")
	i.issue_key = data.get("issue_key", "")
	i.status = data.get("status", "open")
	i.last_result = "" if data.get("last_result") == null else data.get("last_result", "")
	i.attempt_count = int(data.get("attempt_count", 0))
	i.next_attempt_available_at = int(data.get("next_attempt_available_at", 0))
	i.terms = _parse_terms(data.get("terms", {}))
	i.offense_fired = bool(int(data.get("offense_fired", 0)))
	i.created_day = int(data.get("created_day", 0))
	i.resolved_day = -1 if data.get("resolved_day") == null else int(data.get("resolved_day", -1))
	return i


func to_dict() -> Dictionary:
	return {
		"id": id,
		"campaign_id": campaign_id,
		"npc_id": npc_id,
		"party_id": party_id,
		"issue_key": issue_key,
		"status": status,
		"last_result": null if last_result.is_empty() else last_result,
		"attempt_count": attempt_count,
		"next_attempt_available_at": next_attempt_available_at,
		"terms": JSON.stringify(terms),
		"offense_fired": 1 if offense_fired else 0,
		"created_day": created_day,
		"resolved_day": null if resolved_day < 0 else resolved_day,
	}


static func _parse_terms(raw) -> Dictionary:
	if raw is Dictionary:
		return (raw as Dictionary).duplicate()
	if raw is String and not (raw as String).is_empty():
		var parsed = JSON.parse_string(raw)
		if parsed is Dictionary:
			return parsed
	return {}
