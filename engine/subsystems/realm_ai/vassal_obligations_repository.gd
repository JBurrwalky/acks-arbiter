class_name VassalObligationsRepository
extends RefCounted

## CRUD for vassal_obligations per docs/domain-roadmap-corrected.md Phase 8.
##
## Records each favor or duty issued from a liege to a vassal per RAW
## §favors_and_duties L352-372. Active obligations drive the safe-duty
## threshold computation; revoked / completed / defaulted obligations are
## kept for history.
##
## Public API:
##   create(data) -> String
##   get(id) -> Dictionary
##   list_for_assignment(assignment_id, kind: String = "") -> Array
##   list_active_favors_for_assignment(assignment_id) -> Array
##   list_active_duties_for_assignment(assignment_id) -> Array
##   list_one_time_favors_issued_in_month(assignment_id, calendar_day) -> Array
##   most_recent_active(assignment_id, kind) -> Dictionary
##   update(id, fields) -> bool   (whitelist enforced)
##   set_status(id, status, calendar_day) -> bool

const _UPDATE_FIELDS := [
	"status",
	"magnitude",
	"cp_value",
	"due_calendar_day",
	"loyalty_modifier_applied",
	"magnitude_pct",  # Phase 9C: % of vassal realm garrison for call_to_arms.
]


# ---------------------------------------------------------------------------
# CRUD
# ---------------------------------------------------------------------------

static func create(data: Dictionary) -> String:
	var id: String = str(data.get("id", ""))
	if id.is_empty():
		id = CampaignRepository.generate_id()
	var sql := """
		INSERT INTO vassal_obligations
			(id, vassal_assignment_id, kind, type, magnitude, cp_value,
			 is_one_time, issued_calendar_day, due_calendar_day, status,
			 loyalty_modifier_applied, magnitude_pct)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	"""
	var bindings: Array = [
		id,
		str(data.get("vassal_assignment_id", "")),
		str(data.get("kind", "duty")),
		str(data.get("type", "")),
		int(data.get("magnitude", 0)),
		int(data.get("cp_value", 0)),
		1 if bool(data.get("is_one_time", false)) else 0,
		int(data.get("issued_calendar_day", 0)),
		int(data.get("due_calendar_day", 0)),
		str(data.get("status", "active")),
		int(data.get("loyalty_modifier_applied", 0)),
		int(data.get("magnitude_pct", 50)),  # Phase 9C: default 50% per RAW minimum
	]
	if not CampaignRepository.db.query_with_bindings(sql, bindings):
		push_error("VassalObligationsRepository.create failed: %s" % data)
		return ""
	return id


static func get_obligation(id: String) -> Dictionary:
	if id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM vassal_obligations WHERE id = ?", [id]
	):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func list_for_assignment(assignment_id: String, kind: String = "") -> Array:
	if assignment_id.is_empty():
		return []
	if kind.is_empty():
		if not CampaignRepository.db.query_with_bindings("""
			SELECT * FROM vassal_obligations
			WHERE vassal_assignment_id = ?
			ORDER BY issued_calendar_day DESC, created_at DESC
		""", [assignment_id]):
			return []
	else:
		if not CampaignRepository.db.query_with_bindings("""
			SELECT * FROM vassal_obligations
			WHERE vassal_assignment_id = ? AND kind = ?
			ORDER BY issued_calendar_day DESC, created_at DESC
		""", [assignment_id, kind]):
			return []
	return CampaignRepository.db.query_result.duplicate()


static func list_active_favors_for_assignment(assignment_id: String) -> Array:
	if assignment_id.is_empty():
		return []
	if not CampaignRepository.db.query_with_bindings("""
		SELECT * FROM vassal_obligations
		WHERE vassal_assignment_id = ?
		  AND kind = 'favor'
		  AND status = 'active'
		ORDER BY issued_calendar_day DESC
	""", [assignment_id]):
		return []
	return CampaignRepository.db.query_result.duplicate()


static func list_active_duties_for_assignment(assignment_id: String) -> Array:
	if assignment_id.is_empty():
		return []
	if not CampaignRepository.db.query_with_bindings("""
		SELECT * FROM vassal_obligations
		WHERE vassal_assignment_id = ?
		  AND kind = 'duty'
		  AND status = 'active'
		ORDER BY issued_calendar_day DESC
	""", [assignment_id]):
		return []
	return CampaignRepository.db.query_result.duplicate()


static func list_one_time_favors_issued_in_month(assignment_id: String, calendar_day: int) -> Array:
	## "One-time favor offsets only during the month it is given" per RAW L357.
	## A "month" here is the calendar month containing calendar_day; we use
	## a 30-day window for determinism and engine simplicity.
	if assignment_id.is_empty():
		return []
	var floor_day: int = maxi(0, calendar_day - 30)
	if not CampaignRepository.db.query_with_bindings("""
		SELECT * FROM vassal_obligations
		WHERE vassal_assignment_id = ?
		  AND kind = 'favor'
		  AND is_one_time = 1
		  AND issued_calendar_day >= ?
		  AND issued_calendar_day <= ?
		ORDER BY issued_calendar_day DESC
	""", [assignment_id, floor_day, calendar_day]):
		return []
	return CampaignRepository.db.query_result.duplicate()


static func most_recent_active(assignment_id: String, kind: String) -> Dictionary:
	if assignment_id.is_empty() or kind.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings("""
		SELECT * FROM vassal_obligations
		WHERE vassal_assignment_id = ?
		  AND kind = ?
		  AND status = 'active'
		ORDER BY issued_calendar_day DESC, created_at DESC
		LIMIT 1
	""", [assignment_id, kind]):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func set_status(id: String, status: String, _calendar_day: int = 0) -> bool:
	if id.is_empty():
		return false
	return CampaignRepository.db.query_with_bindings("""
		UPDATE vassal_obligations
		SET status = ?, updated_at = datetime('now')
		WHERE id = ?
	""", [status, id])


static func update(id: String, fields: Dictionary) -> bool:
	if id.is_empty() or fields.is_empty():
		return false
	var set_clauses: Array = []
	var values: Array = []
	for key in fields.keys():
		var k: String = String(key)
		if not _UPDATE_FIELDS.has(k):
			push_error("VassalObligationsRepository.update: rejected non-whitelisted field '%s'" % k)
			continue
		set_clauses.append("%s = ?" % k)
		values.append(fields[key])
	if set_clauses.is_empty():
		return false
	set_clauses.append("updated_at = datetime('now')")
	values.append(id)
	var sql := "UPDATE vassal_obligations SET %s WHERE id = ?" % ", ".join(set_clauses)
	return CampaignRepository.db.query_with_bindings(sql, values)
