class_name AdministerDomainHandler
extends RefCounted

## administer_domain handler. Sets domains.administer_domain_completed_this_month
## so the next monthly tick applies +1 morale roll and +5% domain XP per
## acore_axioms §administration L499 and ax_campaign_play.xml §administer_domain
## L503-512.


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var character_id: String = String(state.get("character_id", ""))
	var domain_id: String = _resolve_domain_for_ruler(character_id)
	if domain_id.is_empty():
		return {"summary": "administer_domain completed but ruler has no domain"}
	CampaignRepository.update_domain_monthly_state(domain_id, {
		"administer_domain_completed_this_month": 1,
	})
	CampaignRepository.add_ledger_entry({
		"domain_id": domain_id,
		"calendar_day": _calendar_day(),
		"category": "other",
		"subcategory": "administer_domain_completed",
		"cp_amount": 0,
		"description": "Ruler administered the domain this month (+1 morale roll, +5% XP)",
	})
	return {
		"summary": "Domain administered: +1 morale roll, +5%% XP this month",
		"presentation": {"type": "toast", "text": "Domain administered (+1 morale, +5%% XP)"},
	}


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
	var date: Dictionary = Timekeeping.get_date()
	var year: int = int(date.get("year", 1))
	var month: int = int(date.get("month", 1))
	var day: int = int(date.get("day", 1))
	return ((year - 1) * 12 + (month - 1)) * Timekeeping.DAYS_PER_MONTH + day
