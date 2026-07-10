class_name DialogueFactionContext
extends RefCounted

## The Faction↔Dialogue seam (gdd-faction-framework.md §10.2, §7.4;
## gdd-npc-dialogue.md §4.3). Assembles the `faction_context` block that enters
## a responding NPC's dialogue prompt — PUBLIC information ONLY.
##
## HARD RULE (§7.4 discovery-only): `true_stance`, `betrayal_condition`, and plot
## rows NEVER reach this block. By construction this module reads only:
##   - faction_memberships (no secret column beyond `is_secret`, which we HONOR by
##     dropping is_secret=1 rows entirely),
##   - CampaignRepository.get_faction() rows (name/type/goal/status — all public),
##   - FactionStanceService.get_stance() (which returns the PUBLIC projection —
##     it strips true_stance itself; we never call get_stance_full_for_audit).
## The string "true_stance" cannot appear in any value this module emits — a
## grep-proof test asserts it (test_dialogue_p4_prompt_and_validation.gd).
##
## The LLM never DECIDES a disclosure. When the engine decides a faction secret
## leaks (a bought spy secret delivered, a Grudging member's willingness met, a
## per-issue extraction roll won — all decided OUTSIDE this module), it calls
## inject_reveal_directive() with the exact fact string to reveal; the performer
## then instructs the model to disclose that one fact. Prompt-side secrecy
## ("know this but don't tell") is prohibited (§10.2).
##
## Static. Deterministic. No LLM. No new autoload.

## Band → in-fiction WORDS (§10.2: "band words, not numbers"). The numeric
## grievance_score is DELIBERATELY never surfaced.
const _STANCE_WORDS := {
	"hostile": "openly hostile",
	"unfriendly": "cool and wary",
	"neutral": "guarded",
	"indifferent": "indifferent",
	"friendly": "warmly disposed",
	"allied": "allied",
}

## Public org-goal id → short color phrase (never a secret; goal_primary is the
## faction's declared aim). Unknown goals fall through to a generic phrase.
const _GOAL_PHRASES := {
	"expand_influence": "pressing to widen its influence",
	"accumulate_wealth": "chasing coin",
	"defend_patron": "shielding its patron",
	"suppress_rival": "at odds with a rival",
	"convert_populace": "winning souls",
	"survive": "struggling to keep its doors open",
	"raise_funds": "short of funds",
}


## Build the faction_context block for [param npc_id] as it faces [param party_id]
## on game [param day]. Returns the §10.2 shape; empty arrays / "" when the NPC
## belongs to nothing public. NEVER contains numbers-as-stance or any secret.
static func build(npc_id: String, party_id: String, day: int = 0) -> Dictionary:
	var out := {
		"memberships": [],                          # [{faction_name, type, rank_title, is_leader}]
		"public_stances_toward_party_factions": [], # [{faction_name, party_faction_name, stance}]
		"current_conflict_posture": "",             # PUBLIC declared posture, or ""
		"directives": [],                           # engine-chosen color (public)
		"reveal_directives": [],                    # engine-injected explicit leaks (start empty)
	}
	if npc_id.is_empty():
		return out

	var npc_faction_ids: Array = []
	for m in _public_memberships_for(npc_id):
		var fid: String = String((m as Dictionary).get("faction_id", ""))
		if fid.is_empty():
			continue
		var faction: Dictionary = CampaignRepository.get_faction(fid)
		if faction.is_empty():
			continue
		var type: String = String(faction.get("faction_type", ""))
		out["memberships"].append({
			"faction_name": String(faction.get("name", "")),
			"type": type,
			"rank_title": OrgTypeCatalog.rank_title(type, int((m as Dictionary).get("rank", 0))),
			# leader_npc_id is nullable (§106 — never String(null)).
			"is_leader": StringUtils.s(faction.get("leader_npc_id")) == npc_id,
		})
		npc_faction_ids.append(fid)
		# Public color derived from PUBLIC faction fields only.
		_append_goal_directive(out["directives"], faction)
		if String(faction.get("status", "active")) == "underground":
			_append_unique(out["directives"], "operates in the shadows now")

	# Public stances of the NPC's factions toward the party's own factions.
	var party_faction_ids: Array = _party_faction_ids(party_id)
	var strongest_posture := ""
	for a in npc_faction_ids:
		for b in party_faction_ids:
			if String(a) == String(b):
				continue
			var stance: Dictionary = FactionStanceService.get_stance(String(a), String(b), day)
			var band: String = String(stance.get("public_stance", "neutral"))
			var party_faction: Dictionary = CampaignRepository.get_faction(String(b))
			var entry := {
				"faction_name": String(CampaignRepository.get_faction(String(a)).get("name", "")),
				"party_faction_name": String(party_faction.get("name", "")),
				"stance": _stance_words(band),
			}
			out["public_stances_toward_party_factions"].append(entry)
			# A publicly hostile/allied stance is a declared conflict posture.
			if band == "hostile" and strongest_posture.is_empty():
				strongest_posture = "at odds with %s" % entry["party_faction_name"]
			elif band == "allied":
				strongest_posture = "declared alongside %s" % entry["party_faction_name"]
	out["current_conflict_posture"] = strongest_posture
	return out


## The engine's ONLY channel for a faction-secret disclosure (§10.2): appends an
## explicit fact string the LLM must perform. Callers pass the fact as a literal
## (the spy-op payload, the extracted knowledge entry) — never read from
## true_stance. Idempotent-friendly: duplicates are collapsed.
static func inject_reveal_directive(faction_context: Dictionary, fact_text: String) -> void:
	if fact_text.strip_edges().is_empty():
		return
	if not faction_context.has("reveal_directives"):
		faction_context["reveal_directives"] = []
	_append_unique(faction_context["reveal_directives"], fact_text.strip_edges())


# ---------------------------------------------------------------------------
# Internals (public knowledge only)
# ---------------------------------------------------------------------------

## Active, NON-secret memberships for a character. is_secret=1 rows are dropped
## outright — a covert membership is never surfaced to the LLM (§7.4).
static func _public_memberships_for(npc_id: String) -> Array:
	if not CampaignRepository.db.query_with_bindings(
			"SELECT faction_id, rank, is_secret, status FROM faction_memberships "
			+ "WHERE npc_id = ? AND is_secret = 0 AND status = 'member' ORDER BY faction_id ASC",
			[npc_id]):
		return []
	return CampaignRepository.db.query_result.duplicate()


## Factions the party is PUBLICLY tied to: any reputation_entries(scope=faction)
## row, plus any faction a party member holds a (non-secret) membership in.
## Mirrors FactionJournal's "met" logic on the party side.
static func _party_faction_ids(party_id: String) -> Array:
	var ids := {}
	if party_id.is_empty():
		return []
	for r in CampaignRepository.list_reputation_entries(party_id):
		if String((r as Dictionary).get("scope_type", "")) == "faction":
			var fid: String = String((r as Dictionary).get("scope_id", ""))
			if not fid.is_empty():
				ids[fid] = true
	for cid in _party_member_ids(party_id):
		if not CampaignRepository.db.query_with_bindings(
				"SELECT faction_id FROM faction_memberships "
				+ "WHERE npc_id = ? AND is_secret = 0 AND status = 'member'", [String(cid)]):
			continue
		for row in CampaignRepository.db.query_result:
			var fid2: String = String((row as Dictionary).get("faction_id", ""))
			if not fid2.is_empty():
				ids[fid2] = true
	var out: Array = ids.keys()
	out.sort()
	return out


static func _party_member_ids(party_id: String) -> Array:
	var out: Array = []
	for m in CampaignRepository.get_party_members(party_id):
		if m is Dictionary and (m as Dictionary).has("character_id"):
			out.append(String((m as Dictionary)["character_id"]))
		elif m is String:
			out.append(String(m))
	return out


static func _stance_words(band: String) -> String:
	return String(_STANCE_WORDS.get(band, "guarded"))


static func _append_goal_directive(directives: Array, faction: Dictionary) -> void:
	# goal_primary is nullable (§106 — never String(null)).
	var goal: String = StringUtils.s(faction.get("goal_primary")).strip_edges()
	if goal.is_empty():
		return
	var phrase: String = String(_GOAL_PHRASES.get(goal, "pursuing its aims"))
	_append_unique(directives, phrase)


static func _append_unique(arr: Array, value: String) -> void:
	if not arr.has(value):
		arr.append(value)
