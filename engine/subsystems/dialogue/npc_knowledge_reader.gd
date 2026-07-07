class_name NpcKnowledgeReader
extends RefCounted

## Minimal read interface over NPC knowledge for the ask_question move
## (gdd-npc-dialogue.md §9.1). Reads KnowledgeEntry records from
## `characters.personality.knowledge` (the home defined by gdd-npc-personality.md
## §6.4 / §7.1). The npc-personality KNOWLEDGE GENERATOR (§6) is NOT built yet
## (only the axes are — build_log 2026-06-14), so MOST NPCs will have an empty
## knowledge list; this reader tolerates sparse/empty knowledge without crashing.
## When RG-2 lands and populates the list, ask_question starts returning real
## disclosures with no code change here.
##
## KnowledgeEntry shape (§6.4):
##   { npc_id, category, fact, accuracy, source, willingness_to_share, shared_with_party }
##
## Willingness vocabulary: "freely" | "if_trusted" | "if_paid" | "never".
## Accuracy: "true" | "partially_true" | "false" | "outdated" — flows through
## UNCHANGED (NPCs confidently share what they BELIEVE, acore_equipment:964-965).
##
## No LLM. Deterministic. No writes.

const WILLINGNESS_FREELY := "freely"
const WILLINGNESS_IF_TRUSTED := "if_trusted"
const WILLINGNESS_IF_PAID := "if_paid"
const WILLINGNESS_NEVER := "never"


## All KnowledgeEntry dicts an NPC holds (from personality JSON). Empty when the
## NPC has no knowledge yet (the common Phase-2 case until RG-2 lands).
static func entries_for_npc(npc_id: String, personality: Dictionary = {}) -> Array:
	var p := personality
	if p.is_empty():
		p = _load_personality(npc_id)
	var raw = p.get("knowledge", [])
	if raw is String:
		raw = JSON.parse_string(raw)
	if not (raw is Array):
		return []
	var out: Array = []
	for e in raw:
		if e is Dictionary:
			out.append(e)
	return out


## The KnowledgeEntry dicts matching a topic/category (case-insensitive substring
## match on category OR fact). Filters out already-shared entries so a topic isn't
## repeated (§6.4 `shared_with_party`).
static func entries_for_topic(npc_id: String, topic: String, personality: Dictionary = {}) -> Array:
	var t := topic.strip_edges().to_lower()
	var out: Array = []
	for e in entries_for_npc(npc_id, personality):
		if bool(e.get("shared_with_party", false)):
			continue
		var cat := String(e.get("category", "")).to_lower()
		var fact := String(e.get("fact", "")).to_lower()
		if t.is_empty() or cat.contains(t) or fact.contains(t) or t.contains(cat) and cat != "":
			out.append(e)
	return out


## The willingness tier for a topic: the STRICTEST willingness among the matching
## entries (an NPC who has a `never` fact about a topic guards it even if they also
## know a `freely` fact) — but only among UNSHARED entries. Returns "" when the NPC
## has NO matching knowledge (the caller treats this as "knows nothing", not a
## refusal). PROJECT CALL: strictest-wins keeps disclosure conservative.
static func willingness_for_topic(npc_id: String, topic: String, personality: Dictionary = {}) -> String:
	var matches := entries_for_topic(npc_id, topic, personality)
	if matches.is_empty():
		return ""
	var order := {
		WILLINGNESS_FREELY: 0, WILLINGNESS_IF_TRUSTED: 1,
		WILLINGNESS_IF_PAID: 2, WILLINGNESS_NEVER: 3,
	}
	var strictest := WILLINGNESS_FREELY
	var strictest_rank := -1
	for e in matches:
		var w := String(e.get("willingness_to_share", WILLINGNESS_FREELY))
		var rank := int(order.get(w, 0))
		if rank > strictest_rank:
			strictest_rank = rank
			strictest = w
	return strictest


## The single entry to disclose for a topic once willingness is satisfied: the
## first UNSHARED matching entry. Returns {} when there is nothing to disclose.
static func disclosable_entry(npc_id: String, topic: String, personality: Dictionary = {}) -> Dictionary:
	var matches := entries_for_topic(npc_id, topic, personality)
	if matches.is_empty():
		return {}
	return (matches[0] as Dictionary).duplicate()


static func _load_personality(npc_id: String) -> Dictionary:
	if npc_id.is_empty():
		return {}
	var c: Dictionary = CampaignRepository.get_character(npc_id)
	if c.is_empty():
		return {}
	var raw = c.get("personality", {})
	if raw is String and not (raw as String).is_empty():
		var parsed = JSON.parse_string(raw)
		if parsed is Dictionary:
			return parsed
	if raw is Dictionary:
		return raw
	return {}
