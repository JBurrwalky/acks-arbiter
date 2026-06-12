class_name ManageHenchmenHandler
extends RefCounted

## manage_henchmen handler. Trivial ongoing activity per ax_campaign_play.xml
## §manage_henchmen L624-635. Phase 3 records completion in the ledger so the
## Active Projects tab can surface "managing henchmen this month"; existing
## henchman lifecycle handlers continue to drive loyalty checks. No additional
## mechanical effect is RAW-required at this layer.


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var character_id: String = String(state.get("character_id", ""))
	var domain_id: String = _resolve_domain_for_ruler(character_id)
	if not domain_id.is_empty():
		CampaignRepository.add_ledger_entry({
			"domain_id": domain_id,
			"calendar_day": _calendar_day(),
			"category": "other",
			"subcategory": "manage_henchmen_completed",
			"cp_amount": 0,
			"description": "Henchmen managed this period",
		})
	return {
		"summary": "Henchmen managed",
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
	return Timekeeping.get_calendar_day()
