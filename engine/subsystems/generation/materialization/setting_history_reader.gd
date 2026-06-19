class_name SettingHistoryReader
extends RefCounted

## Read-only access to the FROZEN world chronicle for the LLM narrator / NPC
## roleplayer (gdd-setting-runtime-materialization §15.3, Jedidiah principle 3:
## "preserve & apply world history").
##
## The full `setting_events` log persists in the campaign DB permanently — it is in
## CampaignRepository's savegame scope (`_SCOPE_DIRECT_CAMPAIGN`) — so the materializer
## makes NO copy of it. This class is a thin, filtered accessor over that frozen data,
## the access API the narrator/NPC layer keys on. All methods are static + read-only;
## behavior wiring is deferred to M5.
##
## Per-entity digests the materializer already persisted (the narrator reads these
## first, the full chronicle second): settlement_entrances.history_context (past
## ruling cultures + founding), dungeon_entrances.dungeon_data.provenance, and
## domains.subjugated_since_tick.

## The whole chronicle, oldest-first. limit <= 0 = all events.
static func chronicle(campaign_id: String, limit: int = 0) -> Array:
	var db = CampaignRepository.db
	var sql := "SELECT id, tick, year_before_start, type, polity_ids, culture_ids, hexes, region_hint, severity, significance, summary_key FROM setting_events WHERE campaign_id = ? ORDER BY tick ASC, id ASC"
	if limit > 0:
		sql += " LIMIT %d" % limit
	db.query_with_bindings(sql, [campaign_id])
	return db.query_result.duplicate(true)


## Events that involve a polity (it appears in the event's polity_ids), oldest-first.
static func events_for_polity(campaign_id: String, polity_id: String) -> Array:
	if polity_id.is_empty():
		return []
	var db = CampaignRepository.db
	# polity_ids is a JSON array of quoted ids; match the quoted token to avoid
	# partial-id collisions.
	db.query_with_bindings(
		"SELECT id, tick, year_before_start, type, polity_ids, culture_ids, hexes, summary_key FROM setting_events WHERE campaign_id = ? AND polity_ids LIKE ? ORDER BY tick ASC, id ASC",
		[campaign_id, "%\"" + polity_id + "\"%"])
	return db.query_result.duplicate(true)


## Events whose hex set touches (q,r), oldest-first. hexes is JSON, filtered in GDScript.
static func events_for_hex(campaign_id: String, q: int, r: int) -> Array:
	var db = CampaignRepository.db
	db.query_with_bindings(
		"SELECT id, tick, year_before_start, type, polity_ids, culture_ids, hexes, summary_key FROM setting_events WHERE campaign_id = ? ORDER BY tick ASC, id ASC",
		[campaign_id])
	var out: Array = []
	for e in db.query_result:
		if _hexes_contain(str(e.get("hexes", "[]")), q, r):
			out.append((e as Dictionary).duplicate(true))
	return out


## The fallen realm (if any) whose heartland once held (q,r): {polity_id, toponym_root,
## era_tick}, or {} if none. Lets the narrator say "this was once the heart of X".
static func fallen_realm_for_hex(campaign_id: String, q: int, r: int) -> Dictionary:
	var db = CampaignRepository.db
	db.query_with_bindings(
		"SELECT polity_id, toponym_root, era_tick, hexes FROM setting_fallen_polities WHERE campaign_id = ?",
		[campaign_id])
	for fp in db.query_result:
		if _hexes_contain(str(fp.get("hexes", "[]")), q, r):
			return {
				"polity_id": str(fp.get("polity_id", "")),
				"toponym_root": str(fp.get("toponym_root", "")),
				"era_tick": int(fp.get("era_tick", 0)),
			}
	return {}


static func _hexes_contain(hexes_json: String, q: int, r: int) -> bool:
	var hx = JSON.parse_string(hexes_json)
	if not (hx is Array):
		return false
	for h in hx:
		if h is Array and (h as Array).size() == 2 and int(h[0]) == q and int(h[1]) == r:
			return true
	return false
