class_name VassalRepository
extends RefCounted

## CRUD for vassal_assignments per docs/domain-roadmap-corrected.md Phase 7.
##
## Records each vassalage relationship (liege_character_id ↔ vassal_character_id
## with optional vassal_domain_id). The inverse pointer `domains.liege_domain_id`
## is the source of truth for the realm-graph apex walk; this table records
## the *appointment* + loyalty/status state of each vassal.
##
## Public API:
##   create_assignment(data) -> String
##   get_assignment(id) -> Dictionary
##   get_active_assignment_for_vassal(vassal_character_id) -> Dictionary
##   list_active_for_liege(liege_character_id) -> Array
##   list_for_campaign(campaign_id) -> Array
##   update_status(id, status, calendar_day) -> bool
##   record_loyalty_roll(id, outcome, calendar_day) -> bool
##
## Status transitions write a `last_loyalty_roll_day` even for "active" (no
## roll required) so consumers can compute days-since-last-check.

const _UPDATE_FIELDS := [
	"vassal_domain_id",
	"status",
	"base_loyalty_modifier",
	"last_loyalty_roll_day",
	"last_loyalty_outcome",
	# --- Faction FF-3: realm diplomacy & rebellion (§5.3 compliance ladder) ---
	"compliance_behavior",
	# --- RAW §2.2 loyalty dice carryover (migration 194) ---
	"loyalty_is_fanatic",
	"loyalty_grudging_pending",
]


# ---------------------------------------------------------------------------
# CRUD
# ---------------------------------------------------------------------------

static func create_assignment(data: Dictionary) -> String:
	var id: String = str(data.get("id", ""))
	if id.is_empty():
		id = CampaignRepository.generate_id()

	var sql := """
		INSERT INTO vassal_assignments
			(id, campaign_id, liege_character_id, vassal_character_id,
			 vassal_domain_id, assigned_calendar_day, status,
			 is_henchman_vassal, base_loyalty_modifier,
			 last_loyalty_roll_day, last_loyalty_outcome)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	"""
	var domain_v: Variant = data.get("vassal_domain_id", null)
	if domain_v != null and String(domain_v).is_empty():
		domain_v = null
	var bindings: Array = [
		id,
		str(data.get("campaign_id", "")),
		str(data.get("liege_character_id", "")),
		str(data.get("vassal_character_id", "")),
		domain_v,
		int(data.get("assigned_calendar_day", 0)),
		str(data.get("status", "active")),
		1 if bool(data.get("is_henchman_vassal", true)) else 0,
		int(data.get("base_loyalty_modifier", 0)),
		int(data.get("last_loyalty_roll_day", 0)),
		str(data.get("last_loyalty_outcome", "")),
	]
	if not CampaignRepository.db.query_with_bindings(sql, bindings):
		push_error("VassalRepository.create_assignment failed: liege=%s vassal=%s" % [
			data.get("liege_character_id", ""),
			data.get("vassal_character_id", ""),
		])
		return ""
	return id


static func get_assignment(id: String) -> Dictionary:
	if id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM vassal_assignments WHERE id = ?", [id]
	):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func get_active_assignment_for_vassal(vassal_character_id: String) -> Dictionary:
	if vassal_character_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings("""
		SELECT * FROM vassal_assignments
		WHERE vassal_character_id = ? AND status = 'active'
		LIMIT 1
	""", [vassal_character_id]):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func list_active_for_liege(liege_character_id: String) -> Array:
	if liege_character_id.is_empty():
		return []
	if not CampaignRepository.db.query_with_bindings("""
		SELECT * FROM vassal_assignments
		WHERE liege_character_id = ? AND status = 'active'
		ORDER BY assigned_calendar_day
	""", [liege_character_id]):
		return []
	return CampaignRepository.db.query_result.duplicate()


static func list_for_campaign(campaign_id: String) -> Array:
	if campaign_id.is_empty():
		return []
	if not CampaignRepository.db.query_with_bindings("""
		SELECT * FROM vassal_assignments
		WHERE campaign_id = ?
		ORDER BY assigned_calendar_day
	""", [campaign_id]):
		return []
	return CampaignRepository.db.query_result.duplicate()


static func update_status(id: String, status: String, calendar_day: int) -> bool:
	if id.is_empty():
		return false
	return CampaignRepository.db.query_with_bindings("""
		UPDATE vassal_assignments
		SET status = ?, last_loyalty_roll_day = ?, updated_at = datetime('now')
		WHERE id = ?
	""", [status, calendar_day, id])


static func record_loyalty_roll(id: String, outcome: String, calendar_day: int) -> bool:
	if id.is_empty():
		return false
	return CampaignRepository.db.query_with_bindings("""
		UPDATE vassal_assignments
		SET last_loyalty_outcome = ?, last_loyalty_roll_day = ?, updated_at = datetime('now')
		WHERE id = ?
	""", [outcome, calendar_day, id])


## RAW §2.2 loyalty dice carryover (migration 194): persist the PERSISTENT
## Fanatic flag (+2 all future rolls) and the ONE-SHOT Grudging flag (−1 next
## roll) on the vassal edge, mirroring henchman_state.is_fanatic / is_grudging.
## bool→SQLite is written as 1/0.
static func record_loyalty_state(id: String, is_fanatic: bool, grudging_pending: bool) -> bool:
	if id.is_empty():
		return false
	return CampaignRepository.db.query_with_bindings("""
		UPDATE vassal_assignments
		SET loyalty_is_fanatic = ?, loyalty_grudging_pending = ?, updated_at = datetime('now')
		WHERE id = ?
	""", [1 if is_fanatic else 0, 1 if grudging_pending else 0, id])


# --- Faction FF-3: realm diplomacy & rebellion (§5.3 compliance ladder) ---
## Write the §5.3 compliance-behavior tag onto the vassal edge. Thin wrapper over
## update() so VassalLoyaltyResolver need not know the whitelist mechanics.
static func db_set_compliance(id: String, behavior: String) -> bool:
	if id.is_empty():
		return false
	return update(id, {"compliance_behavior": behavior})


static func update(id: String, fields: Dictionary) -> bool:
	if id.is_empty() or fields.is_empty():
		return false
	var set_clauses: Array = []
	var values: Array = []
	for key in fields.keys():
		var k: String = String(key)
		if not _UPDATE_FIELDS.has(k):
			push_error("VassalRepository.update: rejected non-whitelisted field '%s'" % k)
			continue
		set_clauses.append("%s = ?" % k)
		values.append(fields[key])
	if set_clauses.is_empty():
		return false
	set_clauses.append("updated_at = datetime('now')")
	values.append(id)
	var sql := "UPDATE vassal_assignments SET %s WHERE id = ?" % ", ".join(set_clauses)
	return CampaignRepository.db.query_with_bindings(sql, values)
