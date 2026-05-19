class_name RepressPopulationHandler
extends RefCounted

## repress_population handler [RAW PATCH]. Sets domains.is_repressed_this_month
## and domains.repression_cp_per_family_this_month per acore_axioms §repression
## L510-516 and §monthly_event_modifiers L488-491. Militia troops are not
## eligible to repress per L511; the executor's location_kind / params validate
## this at launch time.
##
## Per §L515, current morale cannot exceed 0 while repressed. Phase 0 morale
## resolver consumes both columns and applies the cap.
##
## params_json shape: { "repressing_troops_gp_per_family": int (>= 1) }
##
## Note: repression is conventionally launched as Ongoing for one month; the
## monthly tick reads/applies/resets the columns. Setting the columns here
## sets the state for the IN-FLIGHT month — handler completion at end-of-month
## means the next monthly tick will see them. Players who launch mid-month and
## want immediate effect should pair this with administer_domain or wait.


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var character_id: String = String(state.get("character_id", ""))
	var domain_id: String = _resolve_domain_for_ruler(character_id)
	if domain_id.is_empty():
		return {"summary": "repress_population: no domain resolved"}

	var params: Dictionary = _parse_params(state)
	var gp_per_family: int = maxi(0, int(params.get("repressing_troops_gp_per_family", 0)))
	if gp_per_family < 1:
		return {"summary": "repress_population: 0 gp/family assigned (no effect)"}

	CampaignRepository.update_domain_monthly_state(domain_id, {
		"is_repressed_this_month": 1,
		"repression_cp_per_family_this_month": gp_per_family,
	})
	CampaignRepository.add_ledger_entry({
		"domain_id": domain_id,
		"calendar_day": _calendar_day(),
		"category": "other",
		"subcategory": "repression_active",
		"cp_amount": 0,
		"description": "Population repressed (%d gp/family) — morale capped at 0" % gp_per_family,
	})
	return {
		"summary": "Population repressed (+%d gp/family) — current morale capped at 0" % gp_per_family,
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
	var date: Dictionary = Timekeeping.get_date()
	var year: int = int(date.get("year", 1))
	var month: int = int(date.get("month", 1))
	var day: int = int(date.get("day", 1))
	return ((year - 1) * 12 + (month - 1)) * Timekeeping.DAYS_PER_MONTH + day
