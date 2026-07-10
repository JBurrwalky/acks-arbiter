class_name FactionJournal
extends RefCounted

## The faction journal read-model (gdd-faction-framework.md §10.4 — FF-2.1).
## DATA CONTRACT ONLY (UI layout belongs to the journal-tab GDD). A public-
## knowledge view over the factions the party has MET: name, type, seat,
## leader-if-known, how the faction publicly regards the party (reputation tier —
## deeds-driven, public), and per-party-member membership/rank/standing.
##
## HARD RULE (§7.4 discovery-only): this NEVER reads faction_stances.true_stance,
## betrayal_condition, or plot rows. The payload is grep-proof — the string
## "true_stance" never appears in a returned key or value. "Met" = the party has
## a reputation_entries(scope='faction') row for the faction, OR a party member
## holds a membership in it.

## Return the journal entries for a party (met + public only). Each entry:
##   {
##     faction_id, name, faction_type, seat_settlement_id, seat_poi_id,
##     leader_npc_id, leader_name,               # leader_name "" if unknown
##     party_reputation_tier, party_reputation_score,   # how they regard the party (public)
##     memberships: [ {character_id, rank, rank_title, standing, status, is_secret} ],
##   }
static func entries_for_party(party_id: String) -> Array:
	if party_id.is_empty():
		return []
	var met: Dictionary = {}          # faction_id -> {tier, score}
	# 1) reputation-known factions
	for r in CampaignRepository.list_reputation_entries(party_id):
		if String((r as Dictionary).get("scope_type", "")) != "faction":
			continue
		var fid: String = String((r as Dictionary).get("scope_id", ""))
		if fid.is_empty():
			continue
		met[fid] = {
			"tier": String((r as Dictionary).get("tier", "neutral")),
			"score": int((r as Dictionary).get("score", 0)),
		}
	# 2) factions where a party member holds a membership
	var member_ids: Array = _party_member_ids(party_id)
	var memberships_by_faction: Dictionary = {}
	for cid in member_ids:
		for m in _memberships_for_character(String(cid)):
			var fid2: String = String((m as Dictionary).get("faction_id", ""))
			if fid2.is_empty():
				continue
			if not met.has(fid2):
				met[fid2] = {"tier": "neutral", "score": 0}
			if not memberships_by_faction.has(fid2):
				memberships_by_faction[fid2] = []
			(memberships_by_faction[fid2] as Array).append(m)

	var out: Array = []
	var keys: Array = met.keys()
	keys.sort()
	for fid_v in keys:
		var fid: String = String(fid_v)
		var faction: Dictionary = CampaignRepository.get_faction(fid)
		if faction.is_empty():
			continue
		var type: String = String(faction.get("faction_type", ""))
		var leader_id: String = StringUtils.s(faction.get("leader_npc_id"))
		var leader_name: String = ""
		if leader_id != "":
			var lch: Dictionary = CampaignRepository.get_character(leader_id)
			leader_name = String(lch.get("name", "")) if not lch.is_empty() else ""
		var memberships: Array = []
		for m in memberships_by_faction.get(fid, []):
			memberships.append({
				"character_id": String((m as Dictionary).get("npc_id", "")),
				"rank": int((m as Dictionary).get("rank", 0)),
				"rank_title": OrgTypeCatalog.rank_title(type, int((m as Dictionary).get("rank", 0))),
				"standing": int((m as Dictionary).get("standing", 0)),
				"status": String((m as Dictionary).get("status", "member")),
				"is_secret": int((m as Dictionary).get("is_secret", 0)) != 0,
			})
		out.append({
			"faction_id": fid,
			"name": String(faction.get("name", "")),
			"faction_type": type,
			"seat_settlement_id": StringUtils.s(faction.get("seat_settlement_id")),
			"seat_poi_id": StringUtils.s(faction.get("seat_poi_id")),
			"leader_npc_id": leader_id,
			"leader_name": leader_name,
			"party_reputation_tier": String((met[fid] as Dictionary).get("tier", "neutral")),
			"party_reputation_score": int((met[fid] as Dictionary).get("score", 0)),
			"memberships": memberships,
		})
	return out


# ---------------------------------------------------------------------------
# Internals (public knowledge only)
# ---------------------------------------------------------------------------

static func _party_member_ids(party_id: String) -> Array:
	if not CampaignRepository.db.query_with_bindings(
			"SELECT character_id FROM party_members WHERE party_id = ? ORDER BY character_id ASC",
			[party_id]):
		return []
	var out: Array = []
	for row in CampaignRepository.db.query_result:
		out.append(String((row as Dictionary).get("character_id", "")))
	return out


static func _memberships_for_character(character_id: String) -> Array:
	if not CampaignRepository.db.query_with_bindings(
			"SELECT * FROM faction_memberships WHERE npc_id = ? ORDER BY faction_id ASC",
			[character_id]):
		return []
	return CampaignRepository.db.query_result.duplicate()
