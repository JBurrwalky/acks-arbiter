class_name DepartureLogRecorder
extends RefCounted

## CRUD for `domain_departure_log` (migration 121) per
## docs/phase-11-plan.md §11A and gdd-domain-tab.md §14.
##
## The Departure Log is the append-only chronicle of significant losses and
## lifecycle changes for every domain in a campaign. Phase 11A wires the
## already-detected transitions (classification advancement / regression,
## morale tier downgrades); Phase 11B-C add the new lifecycle transitions
## (conquest, abandonment, ruler death, succession resolution).
##
## Append-only contract: there is no `update_*` or `delete_*` method on this
## recorder, and there must never be one. Once a row commits, it is
## immutable. Tests and lints should grep this file for `UPDATE` / `DELETE`
## targeting `domain_departure_log` — any match is a bug.
##
## Public API:
##   record(campaign_id, domain_id, calendar_day, event_type,
##          summary, details, related_ledger_entry_ids,
##          related_encounter_ids) -> String  # returns the new entry id
##   list_for_domain(domain_id, limit = 0) -> Array
##   list_for_campaign(campaign_id, limit = 0) -> Array
##   get_entry(entry_id) -> Dictionary
##   export_as_markdown(domain_id) -> String
##   export_as_json(domain_id) -> String
##   export_as_txt(domain_id) -> String

## Mirror of the CHECK constraint in migration 121. Kept here as the
## source-of-truth list callers can use to validate event_type before insert.
## Adding a new event type requires BOTH this list and the migration's CHECK
## to be updated in lockstep — there's a test asserting they match.
const VALID_EVENT_TYPES := [
	"established",
	"classification_advanced",
	"classification_regressed",
	"territory_lost",
	"stronghold_lost",
	"defeat",
	"pillaged",
	"ruler_changed",
	"ruler_died",
	"succession_started",
	"succession_resolved",
	"succession_lapsed",
	"vassal_lost",
	"vassal_promoted",
	"religion_converted",
	"monster_settled",
	"calamity",
	"morale_tier_dropped",
	"conquered",
	"abandoned",
	"restored",
]


# ---------------------------------------------------------------------------
# Write
# ---------------------------------------------------------------------------

## Append a new entry to the departure log. Returns the new row id on success
## or "" on failure. Emits `EventBus.departure_log_entry_recorded` after the
## commit so live UI surfaces (sub-tab list) refresh incrementally.
##
## [param campaign_id] required — FK to campaigns(id).
## [param domain_id] required — NO FK at the schema layer, so an empty string
##   is technically valid SQL but is treated as an error here.
## [param calendar_day] absolute calendar-day of the event (from Timekeeping).
## [param event_type] must be one of VALID_EVENT_TYPES.
## [param summary] short one-line description shown in the chronological list.
## [param details] arbitrary Dictionary serialized to full_details_json.
## [param related_ledger_entry_ids] / [param related_encounter_ids] are JSON
##   arrays of related row ids; the Inspect modal renders cross-links from
##   these. Pass [] when not applicable.
static func record(
	campaign_id: String,
	domain_id: String,
	calendar_day: int,
	event_type: String,
	summary: String,
	details: Dictionary = {},
	related_ledger_entry_ids: Array = [],
	related_encounter_ids: Array = [],
) -> String:
	if campaign_id.is_empty():
		push_error("DepartureLogRecorder.record: campaign_id is required")
		return ""
	if domain_id.is_empty():
		push_error("DepartureLogRecorder.record: domain_id is required")
		return ""
	if not VALID_EVENT_TYPES.has(event_type):
		push_error("DepartureLogRecorder.record: invalid event_type '%s'" % event_type)
		return ""
	var id: String = CampaignRepository.generate_id()
	var sql := """
		INSERT INTO domain_departure_log
			(id, campaign_id, domain_id, calendar_day, event_type,
			 summary, full_details_json,
			 related_ledger_entry_ids, related_encounter_ids)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
	"""
	var bindings: Array = [
		id,
		campaign_id,
		domain_id,
		calendar_day,
		event_type,
		summary,
		JSON.stringify(details),
		JSON.stringify(related_ledger_entry_ids),
		JSON.stringify(related_encounter_ids),
	]
	if not CampaignRepository.db.query_with_bindings(sql, bindings):
		push_error("DepartureLogRecorder.record failed: domain=%s event=%s" % [
			domain_id, event_type])
		return ""
	EventBus.departure_log_entry_recorded.emit(domain_id, id, event_type)
	return id


# ---------------------------------------------------------------------------
# Monthly-tick transition detector (Phase 11A)
# ---------------------------------------------------------------------------

## Inspect a monthly_tick result dict and append a log entry for each
## transition it implies. Called from `DomainHandlers._handle_monthly_tick`
## right after `_emit_signals`. Scope intentionally tight — only events
## the monthly tick has ALREADY detected get logged here. Phase 11B
## lifecycle handler writes its own entries for conquest / abandonment /
## stronghold collapse; Phase 11C ruler-death handler writes ruler_died /
## succession_* entries.
##
## Returns the number of entries written (0+).
static func record_monthly_transitions(
	campaign_id: String,
	domain_data: Dictionary,
	result: Dictionary,
	calendar_day: int,
) -> int:
	var domain_id: String = String(domain_data.get("id", ""))
	if domain_id.is_empty() or campaign_id.is_empty():
		return 0
	var written: int = 0

	# Classification advance / regress.
	var class_change: Dictionary = result.get("classification_change", {})
	var prior_class: String = String(domain_data.get("territory_type", "wilderness"))
	var new_class: String = String(class_change.get("new_classification", prior_class))
	var reason: String = String(class_change.get("reason", ""))
	if bool(class_change.get("advanced", false)):
		var id := record(
			campaign_id, domain_id, calendar_day,
			"classification_advanced",
			"Advanced from %s to %s" % [prior_class, new_class],
			{
				"from": prior_class,
				"to": new_class,
				"reason": reason,
				"peasant_families": int(domain_data.get("peasant_families", 0)) + int(
					result.get("population_growth", 0)),
			})
		if not id.is_empty():
			written += 1
	elif bool(class_change.get("regressed", false)):
		var id := record(
			campaign_id, domain_id, calendar_day,
			"classification_regressed",
			"Regressed from %s to %s" % [prior_class, new_class],
			{
				"from": prior_class,
				"to": new_class,
				"reason": reason,
			})
		if not id.is_empty():
			written += 1

	# Morale tier transition (downward only). Compare named tiers — a move
	# within a single tier (e.g., -5 to -6 both Rebellious) is not a drop.
	var prior_morale: int = int(domain_data.get("morale", 0))
	var current_morale: int = int(result.get("current_morale", prior_morale))
	var prior_tier: String = DomainMoraleResolver.morale_tier(prior_morale)
	var current_tier: String = DomainMoraleResolver.morale_tier(current_morale)
	if prior_tier != current_tier and current_morale < prior_morale:
		var id := record(
			campaign_id, domain_id, calendar_day,
			"morale_tier_dropped",
			"Morale tier dropped: %s -> %s" % [prior_tier, current_tier],
			{
				"prior_tier": prior_tier,
				"new_tier": current_tier,
				"prior_morale": prior_morale,
				"new_morale": current_morale,
			})
		if not id.is_empty():
			written += 1

	return written


# ---------------------------------------------------------------------------
# Read
# ---------------------------------------------------------------------------

## List entries for a single domain, most-recent first. limit=0 means no cap.
static func list_for_domain(domain_id: String, limit: int = 0) -> Array:
	if domain_id.is_empty():
		return []
	var sql := """
		SELECT * FROM domain_departure_log
		WHERE domain_id = ?
		ORDER BY calendar_day DESC, created_at DESC
	"""
	if limit > 0:
		sql += " LIMIT %d" % limit
	if not CampaignRepository.db.query_with_bindings(sql, [domain_id]):
		return []
	return _normalize_rows(CampaignRepository.db.query_result)


## List entries for a whole campaign, most-recent first. limit=0 means no cap.
static func list_for_campaign(campaign_id: String, limit: int = 0) -> Array:
	if campaign_id.is_empty():
		return []
	var sql := """
		SELECT * FROM domain_departure_log
		WHERE campaign_id = ?
		ORDER BY calendar_day DESC, created_at DESC
	"""
	if limit > 0:
		sql += " LIMIT %d" % limit
	if not CampaignRepository.db.query_with_bindings(sql, [campaign_id]):
		return []
	return _normalize_rows(CampaignRepository.db.query_result)


static func get_entry(entry_id: String) -> Dictionary:
	if entry_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM domain_departure_log WHERE id = ?", [entry_id]
	):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return _normalize_row(CampaignRepository.db.query_result[0])


# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------

## Plain-text export — one line per entry, columns separated by tabs.
static func export_as_txt(domain_id: String) -> String:
	var rows: Array = list_for_domain(domain_id)
	if rows.is_empty():
		return ""
	var lines: PackedStringArray = PackedStringArray()
	lines.append("calendar_day\tevent_type\tsummary")
	for r: Dictionary in rows:
		lines.append("%d\t%s\t%s" % [
			int(r.get("calendar_day", 0)),
			String(r.get("event_type", "")),
			String(r.get("summary", "")),
		])
	return "\n".join(lines)


## Markdown export — readable chronological list grouped by event type.
## Most-recent first within each section.
static func export_as_markdown(domain_id: String) -> String:
	var rows: Array = list_for_domain(domain_id)
	if rows.is_empty():
		return ""
	var lines: PackedStringArray = PackedStringArray()
	lines.append("# Domain Departure Log")
	lines.append("")
	for r: Dictionary in rows:
		lines.append("## Day %d — %s" % [
			int(r.get("calendar_day", 0)),
			String(r.get("event_type", "")),
		])
		lines.append("")
		lines.append(String(r.get("summary", "")))
		lines.append("")
		var details: Dictionary = r.get("full_details", {})
		if not details.is_empty():
			lines.append("```json")
			lines.append(JSON.stringify(details, "  "))
			lines.append("```")
			lines.append("")
	return "\n".join(lines)


## JSON export — raw row array. Useful for tests or external tools.
static func export_as_json(domain_id: String) -> String:
	var rows: Array = list_for_domain(domain_id)
	return JSON.stringify(rows, "  ")


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

## Convert the JSON columns to native Dictionary/Array on read so callers
## don't have to parse repeatedly. Keeps raw_*_json fields too for export.
static func _normalize_row(row: Dictionary) -> Dictionary:
	var out: Dictionary = row.duplicate()
	out["full_details"] = _parse_json_object(String(row.get("full_details_json", "{}")))
	out["related_ledger_entry_ids_array"] = _parse_json_array(
		String(row.get("related_ledger_entry_ids", "[]")))
	out["related_encounter_ids_array"] = _parse_json_array(
		String(row.get("related_encounter_ids", "[]")))
	return out


static func _normalize_rows(rows: Array) -> Array:
	var out: Array = []
	for r in rows:
		out.append(_normalize_row(r))
	return out


static func _parse_json_object(s: String) -> Dictionary:
	if s.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(s)
	if parsed is Dictionary:
		return parsed
	return {}


static func _parse_json_array(s: String) -> Array:
	if s.is_empty():
		return []
	var parsed: Variant = JSON.parse_string(s)
	if parsed is Array:
		return parsed
	return []
