class_name DispatchMissionariesHandler
extends RefCounted

## dispatch_missionaries handler (Phase 10A.2 — Faith block).
##
## Restricted minor activity. Per ax_campaign_play.xml §dispatch_missionaries
## L383-394: dispatch hirelings to perform evangelical deeds for a month.
## Track the gp value of wages paid and apply it to next month's congregant
## growth roll (1d10 + Cha mod per 1,000 gp per §congregant_growth L20-22).
##
## State.params_json shape: {"gp_committed": <int>}  (launcher captures gp).
## Treasury was already debited at launch. The handler accrues the cp into
## congregants.monthly_growth_pending_cp.


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var character_id: String = String(state.get("character_id", ""))
	if character_id.is_empty():
		return {"summary": "dispatch_missionaries: no character_id"}

	# Since Migration 115 the activity_state column is cp-native. Fall back to
	# params.gp_committed (launcher gp input, × 100 to cp) if the state column
	# is empty.
	var cp_committed: int = int(state.get("cp_committed", 0))
	if cp_committed == 0:
		var params := _parse_params(state)
		cp_committed = int(params.get("gp_committed", 0)) * 100
	if cp_committed <= 0:
		return {"summary": "dispatch_missionaries completed (no cp committed)"}

	CampaignRepository.add_congregant_pending_cp(character_id, cp_committed)
	EventBus.missionary_dispatch_recorded.emit(character_id, cp_committed)

	# Ledger entry on the ruler's domain (if any) so the Treasury sub-tab
	# shows the expenditure trail.
	var domain_id: String = _resolve_domain_for_character(character_id)
	if not domain_id.is_empty():
		CampaignRepository.add_ledger_entry({
			"domain_id": domain_id,
			"calendar_day": _calendar_day(),
			"category": "expense",
			"subcategory": "missionary_wages",
			"cp_amount": cp_committed,
			"description": "Missionary wages — %s committed; rolls into next-month congregant growth" % Currency.format_cost(cp_committed),
		})

	var pretty := Currency.format_cost(cp_committed)
	return {
		"summary": "Missionaries dispatched: %s tracked for next-month growth" % pretty,
		"presentation": {"type": "toast", "text": "Missionaries dispatched (%s)" % pretty},
	}


static func _parse_params(state: Dictionary) -> Dictionary:
	var raw: String = String(state.get("params_json", "{}"))
	if raw.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(raw)
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}


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
