class_name PerformCeremonialSacrificeHandler
extends RefCounted

## perform_ceremonial_sacrifice handler (Phase 10A.2 — Faith block).
##
## Restricted minor activity, **Lawful-only**. Per ax_campaign_play.xml
## §perform_ceremonial_sacrifice L489-499:
##   - May not be performed more than once per day (restricted_period = 8640).
##   - Track gp value of ceremonial sacrifices and apply it to next month's
##     congregant growth.
##
## State.params_json shape: {"gp_value_total": <int>}.


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var character_id: String = String(state.get("character_id", ""))
	if character_id.is_empty():
		return {"summary": "perform_ceremonial_sacrifice: no character_id"}

	var character := _get_character(character_id)
	if String(character.get("alignment", "neutral")) != "lawful":
		return {"summary": "perform_ceremonial_sacrifice failed: lawful alignment required"}

	var params := _parse_params(state)
	var gp_value: int = int(params.get("gp_value_total", 0))
	if gp_value <= 0:
		return {"summary": "perform_ceremonial_sacrifice completed (no gp value tracked)"}

	CampaignRepository.add_congregant_pending_gp(character_id, gp_value)

	# Ledger entry on the ruler's domain (if any) — treasury was debited at
	# launch for the offering gp.
	var domain_id: String = _resolve_domain_for_character(character_id)
	if not domain_id.is_empty():
		CampaignRepository.add_ledger_entry({
			"domain_id": domain_id,
			"calendar_day": _calendar_day(),
			"category": "expense",
			"subcategory": "ceremonial_sacrifice",
			"gp_amount": gp_value,
			"description": "Ceremonial sacrifice — %d gp; rolls into next-month congregant growth" % gp_value,
		})

	return {
		"summary": "Ceremonial sacrifice: %d gp tracked for next-month growth" % gp_value,
		"presentation": {"type": "toast", "text": "Ceremonial sacrifice (%d gp)" % gp_value},
	}


static func _parse_params(state: Dictionary) -> Dictionary:
	var raw: String = String(state.get("params_json", "{}"))
	if raw.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(raw)
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}


static func _get_character(character_id: String) -> Dictionary:
	if not CampaignRepository.db.query_with_bindings(
		"SELECT id, alignment FROM characters WHERE id = ? LIMIT 1",
		[character_id]
	):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0]


static func _resolve_domain_for_character(character_id: String) -> String:
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
