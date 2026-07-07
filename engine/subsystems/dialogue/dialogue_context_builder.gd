class_name DialogueContextBuilder
extends RefCounted

## Assembles a DialogueContext from repositories and providers
## (gdd-npc-dialogue.md §4.3). Phase 1 scope: the pieces the spine needs —
## scene, party side (designated speaker), npc side (spokesperson), the
## relationship row + first-meeting flag, top-K recalled memories, personality,
## and a minimal hooks block (rumor-pool availability; the rest are Phase 2/3).
##
## Two factory entry points wrap begin() (§4.2):
##   from_encounter(encounter_data, party_id) — seeds initial attitude from the
##       encounter's ALREADY-rolled reaction (do NOT double-roll, §6.1).
##   from_settlement_poi(poi, npc_id, party_id) — a settlement Talk activity.
##
## No LLM. Reads CampaignRepository + Timekeeping. Deterministic.

const RECALL_K := 6   # §8.3 top-K memories


## Build a context for an ENCOUNTER parley. The encounter's rolled reaction seeds
## the initial attitude (§6.1) — the caller passes EncounterData-shaped fields.
## [param npc_id] is the spokesperson NPC's character id (the encounter's leader).
static func from_encounter(encounter_data: Dictionary, party_id: String, npc_id: String) -> Dictionary:
	var campaign_id: String = GameState.campaign_id
	var ctx := _base_context(campaign_id, party_id, npc_id)
	ctx["scene"] = {
		"location_type": "encounter",
		"encounter_id": encounter_data.get("encounter_id", ""),
		"is_surprise": bool(encounter_data.get("is_surprise", false)),
		"poi_id": "",
	}
	ctx["npc_side"] = {
		"npc_ids": _encounter_npc_ids(encounter_data, npc_id),
		"spokesperson_npc_id": npc_id,
		"group_kind": "encounter_group",
	}
	# The encounter already rolled its reaction — carry it as the seed for a
	# first-ever meeting so DialogueSession never double-rolls (§6.1).
	ctx["encounter_seed"] = {
		"reaction_roll": int(encounter_data.get("reaction_roll", 7)),
		"behavioral_disposition": encounter_data.get("behavioral_disposition", "neutral"),
	}
	_attach_relationship_and_memories(ctx, campaign_id, npc_id, party_id)
	return ctx


## Build a context for a settlement PoI Talk activity (§4.2). No encounter seed —
## a first meeting here rolls an initial interaction via InteractionResolver.
static func from_settlement_poi(poi: Dictionary, npc_id: String, party_id: String) -> Dictionary:
	var campaign_id: String = GameState.campaign_id
	var ctx := _base_context(campaign_id, party_id, npc_id)
	ctx["scene"] = {
		"location_type": "settlement",
		"poi_id": poi.get("id", ""),
		"is_surprise": false,
		"encounter_id": "",
	}
	ctx["npc_side"] = {
		"npc_ids": [npc_id],
		"spokesperson_npc_id": npc_id,
		"group_kind": "individual",
	}
	ctx["encounter_seed"] = {}   # no pre-rolled reaction; roll initial on first meet
	_attach_relationship_and_memories(ctx, campaign_id, npc_id, party_id)
	return ctx


# ---------------------------------------------------------------------------
# Internal assembly
# ---------------------------------------------------------------------------

static func _base_context(campaign_id: String, party_id: String, npc_id: String) -> Dictionary:
	var speaker_id: String = _default_speaker_id(party_id)
	var personality: Dictionary = _npc_personality(npc_id)
	return {
		"session_id": _new_session_id(),
		"campaign_id": campaign_id,
		"party_side": {
			"party_id": party_id,
			"present_member_ids": _present_member_ids(party_id),
			"designated_speaker_id": speaker_id,
		},
		"personality": personality,
		"hooks": {
			"rumor_pool_ids": [],
			"has_rumor_pool": _npc_has_rumor_pool(npc_id, personality),
			"npc_receptive": _npc_is_receptive(personality),
			# Phase 2/3 hooks reserved but empty in Phase 1.
			"offerable_quests": [], "turn_in_ready": [], "knowledge_entries": [],
			"hireable_as": [], "requestable_actions": [],
			"ruler_seams_active": false, "army_context": {},
		},
	}


static func _attach_relationship_and_memories(ctx: Dictionary, campaign_id: String,
		npc_id: String, party_id: String) -> void:
	var row: Dictionary = CampaignRepository.get_npc_relationship(campaign_id, npc_id, party_id)
	ctx["is_first_meeting"] = row.is_empty()
	if row.is_empty():
		ctx["relationship"] = {}
	else:
		ctx["relationship"] = NpcRelationshipData.from_dict(row).to_dict()
	# Top-K recalled memories (§8.3): importance DESC then recency.
	var mems: Array = CampaignRepository.list_npc_memories(campaign_id, npc_id, RECALL_K)
	ctx["memories"] = mems


static func _encounter_npc_ids(encounter_data: Dictionary, spokesperson_id: String) -> Array:
	# Phase 1: the encounter's combatant/member ids if present, else just the
	# spokesperson. Full multi-NPC scene handling is Phase 3 (§13.7).
	var ids = encounter_data.get("npc_combatant_ids", [])
	if ids is Array and not (ids as Array).is_empty():
		return (ids as Array).duplicate()
	if not spokesperson_id.is_empty():
		return [spokesperson_id]
	return []


static func _default_speaker_id(party_id: String) -> String:
	# Highest-CHA present PC (ax_reactions:52). Phase 1: first PC party member.
	var members: Array = _present_member_ids(party_id)
	var best_id := ""
	var best_cha := -999
	for mid in members:
		var c: Dictionary = CampaignRepository.get_character(mid)
		if c.is_empty():
			continue
		if String(c.get("npc_role", "player")) != "player":
			continue
		var cha: int = int(c.get("charisma", 10))
		if cha > best_cha:
			best_cha = cha
			best_id = mid
	if best_id.is_empty() and not members.is_empty():
		best_id = members[0]
	return best_id


static func _present_member_ids(party_id: String) -> Array:
	if party_id.is_empty():
		return []
	# party_members rows key on character_id (no separate id column).
	var members: Array = CampaignRepository.get_party_members(party_id)
	var ids: Array = []
	for m in members:
		if m is Dictionary and m.has("character_id"):
			ids.append(m["character_id"])
		elif m is Dictionary and m.has("id"):
			ids.append(m["id"])
		elif m is String:
			ids.append(m)
	return ids


static func _npc_personality(npc_id: String) -> Dictionary:
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


static func _npc_has_rumor_pool(_npc_id: String, _personality: Dictionary) -> bool:
	# Phase 1: STUB — no live quest/rumor system yet (Wave 0 sequencing). The
	# adjudicator returns a stub rumor. Any NPC can offer the stub, so this is
	# true whenever we have a valid NPC. Phase 2 wires the real pool availability.
	return not _npc_id.is_empty()


static func _npc_is_receptive(personality: Dictionary) -> bool:
	# Seduction gate (§5.2 "NPC flagged receptive"). Phase 1: read an explicit
	# personality flag if present; default false (seduction stays off unless the
	# NPC data opts in). Deterministic, no roll.
	return bool(personality.get("seduction_receptive", false))


static func _new_session_id() -> String:
	# Deterministic-friendly id: repository id generator (seeded per campaign use).
	return "dlg_" + CampaignRepository.generate_id()
