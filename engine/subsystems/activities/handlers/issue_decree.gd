class_name IssueDecreeHandler
extends RefCounted

## issue_decree handler. Mutates the targeted domain setting (tax/liturgy/tithe
## rate, religion, alignment, etc.) immediately on completion. Per
## ax_campaign_play.xml §issue_decree L585-606, funds from tax adjustments
## land in the next month's revenue collection.
##
## params_json shape: { "domain_id": String, "decree_kind": String, "value": ... }


const _ALLOWED_DECREE_KINDS: Array = [
	"tax", "liturgy", "tithe", "religion_change", "rename", "other",
]


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var params: Dictionary = _parse_params(state)
	var character_id: String = String(state.get("character_id", ""))
	var domain_id: String = String(params.get("domain_id", ""))
	if domain_id.is_empty():
		domain_id = _resolve_domain_for_ruler(character_id)
	if domain_id.is_empty():
		return {"summary": "issue_decree: no domain resolved"}

	var kind: String = String(params.get("decree_kind", ""))
	if not _ALLOWED_DECREE_KINDS.has(kind):
		return {"summary": "issue_decree: unknown decree kind '%s'" % kind}

	var value: Variant = params.get("value", null)
	var summary: String = ""
	var settings: Dictionary = {}

	match kind:
		"tax":
			settings["tax_rate_cp_per_family"] = int(value) if value != null else 2
			summary = "Tax rate set to %d gp/family" % settings["tax_rate_cp_per_family"]
		"liturgy":
			settings["liturgy_rate_cp_per_family"] = int(value) if value != null else 1
			summary = "Liturgy rate set to %d gp/family" % settings["liturgy_rate_cp_per_family"]
		"tithe":
			settings["tithe_rate_cp_per_family"] = int(value) if value != null else 1
			summary = "Tithe rate set to %d gp/family" % settings["tithe_rate_cp_per_family"]
		"religion_change":
			settings["religion"] = String(value) if value != null else ""
			summary = "Religion changed to '%s' (-4 morale this month, -2 ongoing)" % settings["religion"]
		"rename":
			settings["name"] = String(value) if value != null else ""
			summary = "Domain renamed to '%s'" % settings["name"]
		_:
			summary = "Decree issued: %s" % kind

	if not settings.is_empty():
		CampaignRepository.update_domain_settings(domain_id, settings)

	CampaignRepository.add_ledger_entry({
		"domain_id": domain_id,
		"calendar_day": _calendar_day(),
		"category": "other",
		"subcategory": "decree_%s" % kind,
		"cp_amount": 0,
		"description": summary,
	})
	return {
		"summary": summary,
		"presentation": {"type": "toast", "text": summary},
	}


static func _parse_params(state: Dictionary) -> Dictionary:
	var raw: String = String(state.get("params_json", "{}"))
	var parsed: Variant = JSON.parse_string(raw)
	return parsed if parsed is Dictionary else {}


static func _resolve_domain_for_ruler(character_id: String) -> String:
	if character_id.is_empty():
		return ""
	if not CampaignRepository.db.query_with_bindings(
		"SELECT id FROM domains WHERE owner_character_id = ? LIMIT 1",
		[character_id]
	):
		return ""
	if CampaignRepository.db.query_result.is_empty():
		return ""
	return String(CampaignRepository.db.query_result[0].get("id", ""))


static func _calendar_day() -> int:
	return Timekeeping.get_calendar_day()
