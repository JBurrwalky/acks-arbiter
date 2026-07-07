class_name SolicitMercenariesHandler
extends RefCounted

## solicit_mercenaries handler. Ongoing minor per ax_campaign_play.xml
## §solicit_mercenaries L689-704. Phase 3 rolls 2d6 reaction (per L569-style
## table) and writes a 'mercenary_offers_pending' deferred ledger row that the
## Settlement HiringPanel and Phase 5 will materialize into actual offers.


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var character_id: String = String(state.get("character_id", ""))
	var domain_id: String = _resolve_domain_for_ruler(character_id)
	if domain_id.is_empty():
		return {"summary": "solicit_mercenaries: no domain resolved"}

	var reaction: int = DiceSystem.roll_digital(6, 2, 0, "solicit_mercenaries").modified_total

	CampaignRepository.add_ledger_entry({
		"domain_id": domain_id,
		"calendar_day": _calendar_day(),
		"category": "other",
		"subcategory": "mercenary_offers_pending",
		"cp_amount": 0,
		"description": "Mercenary solicitation 2d6 reaction = %d" % reaction,
	})
	return {
		"summary": "Mercenary solicitation reaction roll: %d" % reaction,
	}


static func _resolve_domain_for_ruler(character_id: String) -> String:
	if character_id.is_empty():
		return ""
	if not CampaignRepository.db.query_with_bindings(
		"SELECT id FROM domains WHERE owner_character_id = ? ORDER BY created_at, id LIMIT 1",
		[character_id]
	):
		return ""
	if CampaignRepository.db.query_result.is_empty():
		return ""
	return String(CampaignRepository.db.query_result[0].get("id", ""))


static func _calendar_day() -> int:
	return Timekeeping.get_calendar_day()
