class_name OverseeInvestmentHandler
extends RefCounted

## oversee_investment handler. Ongoing minor per ax_campaign_play.xml
## §oversee_investment L650-659: investment attracts 1d10+1 new families per
## 1,000gp instead of the usual 1d10. Phase 3 writes cp_committed into
## domains.pending_investment_cp; the next monthly tick (Phase 0) consumes it
## via DomainGrowthResolver and resets it.


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var character_id: String = String(state.get("character_id", ""))
	var domain_id: String = _resolve_domain_for_ruler(character_id)
	if domain_id.is_empty():
		return {"summary": "oversee_investment: no domain resolved"}

	var cp_committed: int = int(state.get("cp_committed", 0))
	if cp_committed <= 0:
		return {"summary": "oversee_investment completed (no cp committed)"}

	var domain: Dictionary = _get_domain(domain_id)
	var prior_pending: int = int(domain.get("pending_investment_cp", 0))
	CampaignRepository.update_domain_monthly_state(domain_id, {
		"pending_investment_cp": prior_pending + cp_committed,
	})
	# Treasury was already debited at launch (the player committed cp). Just
	# ledger the investment to make it visible.
	CampaignRepository.add_ledger_entry({
		"domain_id": domain_id,
		"calendar_day": _calendar_day(),
		"category": "investment",
		"subcategory": "oversee_investment",
		"cp_amount": cp_committed,
		"description": "Oversee investment %s (1d10+1 families per 1,000gp)" % Currency.format_cost(cp_committed),
	})
	return {
		"summary": "Investment of %s overseen — bonus family recruitment" % Currency.format_cost(cp_committed),
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


static func _get_domain(domain_id: String) -> Dictionary:
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM domains WHERE id = ? LIMIT 1", [domain_id]
	):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func _calendar_day() -> int:
	return Timekeeping.get_calendar_day()
