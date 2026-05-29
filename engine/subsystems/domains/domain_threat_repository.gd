class_name DomainThreatRepository
extends RefCounted

## CRUD for `domain_threats` (migration 082) and `market_class_modifiers`
## (migration 083) per docs/domain-roadmap-corrected.md Phase 9A.
##
## A "threat" is any active hostile / lingering / pillaging force in a
## domain whose presence affects revenue, morale, or requires player action.
## Kinds: encounter, bandit_swarm, npc_challenger, settled_lair.
##
## Public API:
##   create_threat(data: Dictionary) -> String
##   get_threat(id: String) -> Dictionary
##   list_active_threats_for_domain(domain_id: String) -> Array
##   list_active_threats_for_campaign(campaign_id: String) -> Array
##   get_active_bandit_swarm_for_domain(domain_id: String) -> Dictionary
##   get_active_challenger_for_domain(domain_id: String) -> Dictionary
##   update(id: String, fields: Dictionary) -> bool
##   set_status(id: String, status: String, calendar_day: int) -> bool
##
##   create_market_modifier(data: Dictionary) -> String
##   list_active_modifiers_for_settlement(settlement_id: String) -> Array
##   sum_market_class_delta(settlement_id: String) -> int
##   sum_price_multiplier_pct(settlement_id: String, category: String) -> int
##   expire_modifiers_for_campaign(campaign_id: String, calendar_day: int) -> int

const _THREAT_UPDATE_FIELDS := [
	"status", "creature_count", "platoon_br", "is_lingering",
	"reaction", "bandit_count", "challenger_character_id",
	"challenger_level", "linked_army_id", "linked_hex_q", "linked_hex_r",
	"morale_penalty", "resolved_calendar_day", "payload_json",
]


# ---------------------------------------------------------------------------
# Threats CRUD
# ---------------------------------------------------------------------------

static func create_threat(data: Dictionary) -> String:
	var id: String = str(data.get("id", ""))
	if id.is_empty():
		id = CampaignRepository.generate_id()
	var sql := """
		INSERT INTO domain_threats
			(id, campaign_id, domain_id, kind, status,
			 creature_key, creature_count, platoon_br, is_lair, is_lingering,
			 reaction, bandit_count,
			 challenger_character_id, challenger_level,
			 linked_army_id, linked_hex_q, linked_hex_r,
			 morale_penalty, spawned_calendar_day, payload_json)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	"""
	var bindings: Array = [
		id,
		str(data.get("campaign_id", "")),
		str(data.get("domain_id", "")),
		str(data.get("kind", "encounter")),
		str(data.get("status", "active")),
		str(data.get("creature_key", "")),
		int(data.get("creature_count", 0)),
		float(data.get("platoon_br", 0.0)),
		1 if bool(data.get("is_lair", false)) else 0,
		1 if bool(data.get("is_lingering", false)) else 0,
		str(data.get("reaction", "")),
		int(data.get("bandit_count", 0)),
		_null_or_string(data.get("challenger_character_id")),
		int(data.get("challenger_level", 0)),
		_null_or_string(data.get("linked_army_id")),
		_null_or_int(data.get("linked_hex_q")),
		_null_or_int(data.get("linked_hex_r")),
		int(data.get("morale_penalty", 0)),
		int(data.get("spawned_calendar_day", 0)),
		str(data.get("payload_json", "{}")),
	]
	if not CampaignRepository.db.query_with_bindings(sql, bindings):
		push_error("DomainThreatRepository.create_threat failed: kind=%s domain=%s" % [
			data.get("kind", ""), data.get("domain_id", "")])
		return ""
	return id


static func get_threat(id: String) -> Dictionary:
	if id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM domain_threats WHERE id = ?", [id]
	):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func list_active_threats_for_domain(domain_id: String) -> Array:
	if domain_id.is_empty():
		return []
	if not CampaignRepository.db.query_with_bindings("""
		SELECT * FROM domain_threats
		WHERE domain_id = ? AND status = 'active'
		ORDER BY spawned_calendar_day, kind
	""", [domain_id]):
		return []
	return CampaignRepository.db.query_result.duplicate()


static func list_active_threats_for_campaign(campaign_id: String) -> Array:
	if campaign_id.is_empty():
		return []
	if not CampaignRepository.db.query_with_bindings("""
		SELECT * FROM domain_threats
		WHERE campaign_id = ? AND status = 'active'
		ORDER BY domain_id, spawned_calendar_day
	""", [campaign_id]):
		return []
	return CampaignRepository.db.query_result.duplicate()


static func get_active_bandit_swarm_for_domain(domain_id: String) -> Dictionary:
	if domain_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings("""
		SELECT * FROM domain_threats
		WHERE domain_id = ? AND kind = 'bandit_swarm' AND status = 'active'
		LIMIT 1
	""", [domain_id]):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func list_active_settled_lairs_for_domain(domain_id: String) -> Array:
	## Phase 9C polish round 4 2026-05-09: returns all active threats in the
	## domain with kind='settled_lair'. Used by the domain morale modifier
	## sum (DomainEncounterResolver.compute_settled_lair_morale_penalty) and
	## by the encounters_threats_sub_tab UI. Multiple settled lairs may
	## coexist per domain (no partial-unique-active constraint, unlike
	## bandit_swarm / npc_challenger).
	if domain_id.is_empty():
		return []
	if not CampaignRepository.db.query_with_bindings("""
		SELECT * FROM domain_threats
		WHERE domain_id = ? AND kind = 'settled_lair' AND status = 'active'
		ORDER BY spawned_calendar_day, id
	""", [domain_id]):
		return []
	return CampaignRepository.db.query_result.duplicate()


static func get_active_challenger_for_domain(domain_id: String) -> Dictionary:
	if domain_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings("""
		SELECT * FROM domain_threats
		WHERE domain_id = ? AND kind = 'npc_challenger' AND status = 'active'
		LIMIT 1
	""", [domain_id]):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func update(id: String, fields: Dictionary) -> bool:
	if id.is_empty() or fields.is_empty():
		return false
	var set_clauses: Array = []
	var values: Array = []
	for key in fields.keys():
		var k: String = String(key)
		if not _THREAT_UPDATE_FIELDS.has(k):
			push_error("DomainThreatRepository.update: rejected non-whitelisted '%s'" % k)
			continue
		set_clauses.append("%s = ?" % k)
		values.append(fields[key])
	if set_clauses.is_empty():
		return false
	set_clauses.append("updated_at = datetime('now')")
	values.append(id)
	var sql := "UPDATE domain_threats SET %s WHERE id = ?" % ", ".join(set_clauses)
	return CampaignRepository.db.query_with_bindings(sql, values)


static func set_status(id: String, status: String, calendar_day: int) -> bool:
	return update(id, {
		"status": status,
		"resolved_calendar_day": calendar_day,
	})


# ---------------------------------------------------------------------------
# Market-class modifiers CRUD
# ---------------------------------------------------------------------------

static func create_market_modifier(data: Dictionary) -> String:
	var id: String = str(data.get("id", ""))
	if id.is_empty():
		id = CampaignRepository.generate_id()
	var sql := """
		INSERT INTO market_class_modifiers
			(id, campaign_id, settlement_entrance_id, source_kind,
			 delta, price_multiplier_pct, affected_categories,
			 issued_calendar_day, expires_calendar_day, status, payload_json)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	"""
	var bindings: Array = [
		id,
		str(data.get("campaign_id", "")),
		_null_or_string(data.get("settlement_entrance_id")),
		str(data.get("source_kind", "unknown")),
		int(data.get("delta", 0)),
		int(data.get("price_multiplier_pct", 100)),
		str(data.get("affected_categories", "")),
		int(data.get("issued_calendar_day", 0)),
		int(data.get("expires_calendar_day", 0)),
		str(data.get("status", "active")),
		str(data.get("payload_json", "{}")),
	]
	if not CampaignRepository.db.query_with_bindings(sql, bindings):
		push_error("DomainThreatRepository.create_market_modifier failed: source=%s" % data.get("source_kind", ""))
		return ""
	return id


static func list_active_modifiers_for_settlement(settlement_id: String) -> Array:
	if settlement_id.is_empty():
		return []
	if not CampaignRepository.db.query_with_bindings("""
		SELECT * FROM market_class_modifiers
		WHERE settlement_entrance_id = ? AND status = 'active'
		ORDER BY issued_calendar_day
	""", [settlement_id]):
		return []
	return CampaignRepository.db.query_result.duplicate()


static func sum_market_class_delta(settlement_id: String) -> int:
	if settlement_id.is_empty():
		return 0
	if not CampaignRepository.db.query_with_bindings("""
		SELECT COALESCE(SUM(delta), 0) AS total FROM market_class_modifiers
		WHERE settlement_entrance_id = ? AND status = 'active'
	""", [settlement_id]):
		return 0
	if CampaignRepository.db.query_result.is_empty():
		return 0
	return int(CampaignRepository.db.query_result[0].get("total", 0))


static func sum_price_multiplier_pct(settlement_id: String, category: String) -> int:
	## Returns the COMPOUND multiplier (in percent) of all active war_profiteers
	## modifiers affecting this settlement + category. Each modifier contributes
	## its `price_multiplier_pct` (e.g. 110 = +10%); the total is multiplied
	## together. Empty category matches modifiers whose CSV is empty (universal).
	if settlement_id.is_empty():
		return 100
	var rows: Array = list_active_modifiers_for_settlement(settlement_id)
	if rows.is_empty():
		return 100
	var compound: float = 1.0
	for row in rows:
		var pct: int = int(row.get("price_multiplier_pct", 100))
		if pct == 100 or pct == 0:
			continue
		var cats_csv: String = str(row.get("affected_categories", ""))
		if cats_csv.is_empty() or _csv_contains(cats_csv, category):
			compound *= float(pct) / 100.0
	return int(round(compound * 100.0))


static func expire_modifiers_for_campaign(campaign_id: String, calendar_day: int) -> int:
	## Mark all active market_class_modifiers whose `expires_calendar_day`
	## has passed as status='expired'. Returns the count expired.
	if campaign_id.is_empty():
		return 0
	if not CampaignRepository.db.query_with_bindings("""
		SELECT id FROM market_class_modifiers
		WHERE campaign_id = ?
		  AND status = 'active'
		  AND expires_calendar_day <= ?
		  AND expires_calendar_day > 0
	""", [campaign_id, calendar_day]):
		return 0
	var ids: Array = []
	for row in CampaignRepository.db.query_result:
		ids.append(str(row.get("id", "")))
	for mod_id in ids:
		CampaignRepository.db.query_with_bindings("""
			UPDATE market_class_modifiers
			SET status = 'expired', updated_at = datetime('now')
			WHERE id = ?
		""", [mod_id])
	return ids.size()


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _null_or_string(v: Variant) -> Variant:
	if v == null:
		return null
	var s: String = String(v)
	if s.is_empty():
		return null
	return s


static func _null_or_int(v: Variant) -> Variant:
	if v == null:
		return null
	return int(v)


static func _csv_contains(csv: String, value: String) -> bool:
	if value.is_empty():
		return true  # caller wants any match
	for part in csv.split(",", false):
		if String(part).strip_edges() == value:
			return true
	return false
