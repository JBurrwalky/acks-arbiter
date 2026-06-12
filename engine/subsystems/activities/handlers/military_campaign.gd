class_name MilitaryCampaignHandler
extends RefCounted

## military_campaign handler. Ongoing major STRENUOUS per ax_campaign_play.xml
## §military_campaign L637-648. Daily resolution per battle procedures (or
## weekly if no opponents within 1 week's movement). Phase 3 lands the
## executor wrapper; actual battle resolution is out of scope (cross-references
## daw_battles.xml work in a future phase).


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var character_id: String = String(state.get("character_id", ""))
	var domain_id: String = _resolve_domain_for_ruler(character_id)
	if not domain_id.is_empty():
		CampaignRepository.add_ledger_entry({
			"domain_id": domain_id,
			"calendar_day": _calendar_day(),
			"category": "other",
			"subcategory": "military_campaign_pending",
			"cp_amount": 0,
			"description": "Military campaign concluded (battle resolution deferred)",
		})
	return {
		"summary": "Military campaign concluded",
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
