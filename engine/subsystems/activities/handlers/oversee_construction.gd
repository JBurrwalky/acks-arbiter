class_name OverseeConstructionHandler
extends RefCounted

## oversee_construction handler. Ongoing minor per ax_campaign_play.xml
## §oversee_construction L661-672: increases construction rate by 5% (10% if
## ruler is also supervising). Phase 4 wires the actual rate-bump on the
## domain's in-progress commission via CommissionPipeline.bump_daily_construction_rate.


const RATE_BUMP_PCT := 5


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var character_id: String = String(state.get("character_id", ""))
	var domain_id: String = _resolve_domain_for_ruler(character_id)
	if domain_id.is_empty():
		return {"summary": "oversee_construction: no domain resolved"}

	var commission: Dictionary = CommissionPipeline.get_in_progress_commission_for_domain(domain_id)
	if commission.is_empty():
		CampaignRepository.add_ledger_entry({
			"domain_id": domain_id,
			"calendar_day": _calendar_day(),
			"category": "other",
			"subcategory": "oversee_construction_no_active_commission",
			"cp_amount": 0,
			"description": "Oversaw construction but no active commission to bump",
		})
		return {
			"summary": "Construction overseen — no active commission to accelerate",
		}

	var commission_id: String = String(commission.get("id", ""))
	var prior_rate_cp: int = int(commission.get("daily_construction_rate_cp", 0))
	var new_rate_cp: int = CommissionPipeline.bump_daily_construction_rate(
		commission_id, RATE_BUMP_PCT)

	CampaignRepository.add_ledger_entry({
		"domain_id": domain_id,
		"calendar_day": _calendar_day(),
		"category": "other",
		"subcategory": "oversee_construction_completed",
		"cp_amount": 0,
		"description": "Construction overseen: rate %s → %s/day (+%d%%)" % [
			Currency.format_cost(prior_rate_cp), Currency.format_cost(new_rate_cp), RATE_BUMP_PCT,
		],
	})
	return {
		"summary": "Construction rate bumped %s → %s/day" % [
			Currency.format_cost(prior_rate_cp), Currency.format_cost(new_rate_cp),
		],
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
