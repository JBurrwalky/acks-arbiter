class_name NpcMemoryStore
extends RefCounted

## Memory read/write for the dialogue subsystem (gdd-npc-dialogue.md §8).
## Wraps CampaignRepository's npc_relationships / npc_memories CRUD and owns the
## DETERMINISTIC summarizer (§8.2): the move log is ground truth, so a faithful
## summary requires no LLM at all. At COMMIT, summarize_move_log() converts the
## engine-adjudicated move log into `facts` tags + a template `summary`, writes an
## npc_memories row, updates the relationship's last_interaction_day/attitude, and
## emits npc_memory_written. The LLM rewrite (§8.2 step 2) is Phase 4 — it may
## only replace the summary prose, never the engine-derived facts.
##
## No LLM. Deterministic. Reads Timekeeping for the current day.


## Recall: top-K memories for an NPC (§8.3) as NpcMemoryData objects.
static func recall(campaign_id: String, npc_id: String, k: int = 6) -> Array:
	var rows: Array = CampaignRepository.list_npc_memories(campaign_id, npc_id, k)
	var out: Array = []
	for r in rows:
		out.append(NpcMemoryData.from_dict(r))
	return out


## Load or create the relationship row for an NPC x party. Returns a
## NpcRelationshipData. If no row exists, returns a fresh (unsaved) default with
## the caller-supplied initial attitude; is_first_meeting distinguishes the two.
static func load_relationship(campaign_id: String, npc_id: String, party_id: String,
		default_attitude: String = "neutral") -> NpcRelationshipData:
	var row: Dictionary = CampaignRepository.get_npc_relationship(campaign_id, npc_id, party_id)
	if not row.is_empty():
		return NpcRelationshipData.from_dict(row)
	var rel := NpcRelationshipData.new()
	rel.campaign_id = campaign_id
	rel.npc_id = npc_id
	rel.party_id = party_id
	rel.attitude = default_attitude
	rel.first_met_day = _current_day()
	return rel


## Persist a relationship row (upsert). Returns the row id.
static func save_relationship(rel: NpcRelationshipData) -> String:
	return CampaignRepository.save_npc_relationship(rel)


## Write a single memory row and emit npc_memory_written. Returns the row id.
static func write_memory(mem: NpcMemoryData) -> String:
	if mem.created_day == 0:
		mem.created_day = _current_day()
	var id := CampaignRepository.save_npc_memory(mem)
	if not id.is_empty():
		EventBus.npc_memory_written.emit(mem.npc_id, id, mem.kind)
	return id


## The deterministic summarizer (§8.2). Converts a move log into a memory row.
## [param move_log] is an Array of Dictionaries, each entry:
##   { move_id, speaker_name, prior_attitude, new_attitude, kind, rumor_text? }
## Returns the written memory id ("" on failure or empty log).
##
## [param summary_override] is the Phase-4 LLM rewrite hook (§8.2 step 2): when
## non-empty it REPLACES the template summary PROSE only — the engine-derived
## `facts` are ground truth and are NEVER touched by the LLM (§104). The
## deterministic call omits it and stays byte-identical to before.
static func summarize_move_log(campaign_id: String, npc_id: String, party_id: String,
		session_id: String, move_log: Array, final_attitude: String,
		summary_override: String = "") -> String:
	if move_log.is_empty():
		return ""
	var facts := _facts_from_log(move_log)
	var summary := _summary_from_log(move_log, final_attitude)
	if not summary_override.strip_edges().is_empty():
		summary = summary_override.strip_edges()
	var kind := _dominant_kind(move_log)
	var mem := NpcMemoryData.new()
	mem.campaign_id = campaign_id
	mem.npc_id = npc_id
	mem.party_id = party_id
	mem.kind = kind
	mem.summary = summary
	mem.facts = facts
	mem.attitude_after = final_attitude
	mem.importance = _importance_from_log(move_log, kind)
	mem.created_day = _current_day()
	mem.source_session_id = session_id
	return write_memory(mem)


## Public: the engine-derived facts as short human strings, for the Phase-4
## summary PROMPT grounding (§8.2). Pure — same input the deterministic
## summarizer uses, so the LLM rewrite can never drift from the facts.
static func fact_lines_from_log(move_log: Array) -> Array:
	var out: Array = []
	for f in _facts_from_log(move_log):
		if not (f is Dictionary):
			continue
		var d: Dictionary = f
		if d.has("influenced"):
			out.append("They tried to sway me (result: %s)." % String(d.get("result", "")))
		elif d.has("provoked"):
			out.append("They provoked me toward %s." % String(d.get("toward", "")))
		elif d.has("shared_rumor"):
			out.append("I shared a rumor: %s" % String(d.get("shared_rumor", "")))
		elif d.has("conversed"):
			out.append("We spoke.")
	return out


# ---------------------------------------------------------------------------
# Internal — deterministic summarization
# ---------------------------------------------------------------------------

static func _facts_from_log(move_log: Array) -> Array:
	var facts: Array = []
	for entry in move_log:
		var move_id: String = entry.get("move_id", "")
		match move_id:
			"influence_diplomatic", "influence_intimidate", "influence_seduce":
				facts.append({"influenced": move_id, "result": entry.get("new_attitude", "")})
			"provoke":
				facts.append({"provoked": true, "toward": entry.get("new_attitude", "")})
			"ask_rumor":
				facts.append({"shared_rumor": entry.get("rumor_text", "")})
			"converse":
				facts.append({"conversed": true})
			"farewell":
				pass  # farewell is not itself a remembered fact
	return facts


static func _summary_from_log(move_log: Array, final_attitude: String) -> String:
	# Template summary (§8.2 step 1). Terse, human-readable, no LLM.
	var prior := ""
	var speaker := "The party"
	var did_provoke := false
	var did_influence := false
	var did_rumor := false
	for entry in move_log:
		if prior.is_empty():
			prior = entry.get("prior_attitude", "")
		if entry.get("speaker_name", "") != "":
			speaker = entry.get("speaker_name", speaker)
		match entry.get("move_id", ""):
			"provoke": did_provoke = true
			"influence_diplomatic", "influence_intimidate", "influence_seduce": did_influence = true
			"ask_rumor": did_rumor = true
	var parts: Array = []
	if prior.is_empty():
		parts.append("Met %s." % speaker)
	if did_influence:
		parts.append("%s tried to sway me." % speaker)
	if did_rumor:
		parts.append("I shared a rumor.")
	if did_provoke:
		parts.append("%s provoked me." % speaker)
	if parts.is_empty():
		parts.append("Spoke with %s." % speaker)
	var tail := "Attitude"
	if not prior.is_empty() and prior != final_attitude:
		tail = "Attitude: %s -> %s." % [prior, final_attitude]
	else:
		tail = "Attitude: %s." % final_attitude
	return " ".join(parts) + " " + tail


static func _dominant_kind(move_log: Array) -> String:
	# grudge if provoked into hostility; conversation otherwise. (Phase 1 kinds.)
	for entry in move_log:
		if entry.get("move_id", "") == "provoke" and entry.get("new_attitude", "") == "hostile":
			return "grudge"
	for entry in move_log:
		if entry.get("becomes_combat", false):
			return "grudge"
	return "conversation"


static func _importance_from_log(move_log: Array, kind: String) -> int:
	# 1..5. Grudges/combat are memorable; plain chats are low. (§8.1 importance.)
	if kind == "grudge":
		return 4
	var importance := 1
	for entry in move_log:
		if entry.get("move_id", "").begins_with("influence_"):
			importance = maxi(importance, 2)
		if entry.get("move_id", "") == "ask_rumor":
			importance = maxi(importance, 2)
	return importance


static func _current_day() -> int:
	# Absolute calendar day since campaign start. Timekeeping is the single shared
	# clock (conventions §6.8); get_total_days() is the canonical day serial.
	return Timekeeping.get_total_days()
