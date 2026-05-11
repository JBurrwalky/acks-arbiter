class_name SuperviseConstructionHandler
extends RefCounted

## supervise_construction handler. Ongoing major per ax_campaign_play.xml
## §supervise_construction L706-716. Acts as construction supervisor; combined
## with oversee_construction the rate goes +10% per L671. Phase 4 wires the
## rate bump directly via CommissionPipeline.bump_daily_construction_rate.
##
## RAW: "If the ruler is also supervising construction, increase construction
## rate by 10%." This handler applies the +10% on its own; if the ruler is
## also running oversee_construction concurrently the +5% from that handler
## stacks on top. Net effect when both are running: 1.10 * 1.05 = 1.155
## (~15.5%), close to but slightly above RAW's flat 10%; this is consistent
## with the project's compounding-rate-bump model.


const RATE_BUMP_PCT := 10


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var character_id: String = String(state.get("character_id", ""))
	var domain_id: String = _resolve_domain_for_ruler(character_id)
	if domain_id.is_empty():
		return {"summary": "supervise_construction: no domain resolved"}

	var commission: Dictionary = CommissionPipeline.get_in_progress_commission_for_domain(domain_id)
	if commission.is_empty():
		CampaignRepository.add_ledger_entry({
			"domain_id": domain_id,
			"calendar_day": _calendar_day(),
			"category": "other",
			"subcategory": "supervise_construction_no_active_commission",
			"gp_amount": 0,
			"description": "Supervised construction but no active commission to bump",
		})
		return {
			"summary": "Construction supervised — no active commission to accelerate",
		}

	var commission_id: String = String(commission.get("id", ""))
	var prior_rate: int = int(commission.get("daily_construction_rate_gp", 0))
	var new_rate: int = CommissionPipeline.bump_daily_construction_rate(
		commission_id, RATE_BUMP_PCT)

	CampaignRepository.add_ledger_entry({
		"domain_id": domain_id,
		"calendar_day": _calendar_day(),
		"category": "other",
		"subcategory": "supervise_construction_completed",
		"gp_amount": 0,
		"description": "Construction supervised: rate %d → %d gp/day (+%d%%)" % [
			prior_rate, new_rate, RATE_BUMP_PCT,
		],
	})
	return {
		"summary": "Construction rate bumped %d → %d gp/day" % [prior_rate, new_rate],
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
