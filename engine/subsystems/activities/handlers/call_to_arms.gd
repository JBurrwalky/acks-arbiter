class_name CallToArmsHandler
extends RefCounted

## call_to_arms handler. Ongoing minor activity per ax_campaign_play.xml
## §call_to_arms L514-530. Each called vassal must muster a force at least
## equal to 1/2 the garrison of his realm. Muster delays per acore_axioms
## §muster_delay L373-382: Baron-Count = Week, Prince-Duke = Month,
## King-Emperor = Season.
##
## Phase 3 emitted EventBus.vassal_muster_called with the realm-size-based
## delay only.
## Phase 9C polish (2026-05-09): wire the decree to invoke CallToArmsMuster
## per active vassal — creates the vassal_obligations + call_to_arms_state
## rows and schedules the three tranche arrivals via the runner's scheduler.
## Default magnitude_pct = 50 (RAW minimum); UI may surface a slider in a
## future polish session for the lord to choose 50%-100%.


const _MUSTER_DELAY_BY_TITLE: Dictionary = {
	"Baron":   7,    # 1 week
	"Marquis": 7,
	"Count":   7,
	"Duke":    28,   # 1 month
	"Prince":  28,
	"King":    91,   # 1 season
	"Emperor": 91,
}


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var character_id: String = String(state.get("character_id", ""))
	var domain_id: String = _resolve_domain_for_ruler(character_id)
	if domain_id.is_empty():
		return {"summary": "call_to_arms: no domain resolved"}

	var domain: Dictionary = _get_domain(domain_id)
	var title: String = String(domain.get("realm_title", "Baron"))
	var delay_days: int = int(_MUSTER_DELAY_BY_TITLE.get(title, 7))
	var delay_rounds: int = delay_days * Timekeeping.ROUNDS_PER_DAY

	# Legacy signal — kept for backward compatibility with any UI/test that
	# listens for the muster-called notification.
	EventBus.vassal_muster_called.emit(domain_id, delay_rounds)

	# Phase 9C polish 2026-05-09: per-vassal magnitude_pct read from decree
	# params. Default 50 (RAW minimum half garrison) for backward compat
	# with any callers that don't supply it. UI now exposes a slider via
	# decrees_and_remote_orders_sub_tab; magnitude ≥ 100 counts as 2 duties.
	var params: Dictionary = _parse_params(state)
	var magnitude_pct: int = clampi(int(params.get("magnitude_pct", 50)), 50, 100)
	var calendar_day: int = _calendar_day()
	var scheduler = null
	if _runner != null and _runner.has_method("get_scheduler"):
		scheduler = _runner.get_scheduler()
	var active_assignments: Array = VassalRepository.list_active_for_liege(character_id)
	var vassals_called: Array = []
	for assn in active_assignments:
		var assn_id: String = String(assn.get("id", ""))
		var vassal_id: String = String(assn.get("vassal_character_id", ""))
		if assn_id.is_empty() or vassal_id.is_empty():
			continue
		# Create the obligation row. Status='active' so favors_duties_resolver
		# tracks it across monthly ticks.
		var obligation_id: String = VassalObligationsRepository.create({
			"vassal_assignment_id": assn_id,
			"kind": "duty",
			"type": "call_to_arms",
			"magnitude": 0,
			"gp_value": 0,
			"is_one_time": false,
			"issued_calendar_day": calendar_day,
			"status": "active",
			"loyalty_modifier_applied": 0,
			"magnitude_pct": magnitude_pct,
		})
		if obligation_id.is_empty():
			continue
		var state_id: String = CallToArmsMuster.issue_call(
			obligation_id, character_id, vassal_id,
			calendar_day, magnitude_pct, scheduler
		)
		vassals_called.append({"vassal_character_id": vassal_id,
			"obligation_id": obligation_id, "call_to_arms_state_id": state_id})

	CampaignRepository.add_ledger_entry({
		"domain_id": domain_id,
		"calendar_day": calendar_day,
		"category": "other",
		"subcategory": "vassal_muster_called",
		"gp_amount": 0,
		"description": "Call to arms — %s realm muster window: %d days; %d vassals called" % [
			title, delay_days, vassals_called.size()
		],
	})
	return {
		"summary": "Called %d vassal(s) to arms — muster window %d days" % [
			vassals_called.size(), delay_days
		],
		"vassals_called": vassals_called,
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


static func _get_domain(domain_id: String) -> Dictionary:
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM domains WHERE id = ? LIMIT 1", [domain_id]
	):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func _calendar_day() -> int:
	var date: Dictionary = Timekeeping.get_date()
	var year: int = int(date.get("year", 1))
	var month: int = int(date.get("month", 1))
	var day: int = int(date.get("day", 1))
	return ((year - 1) * 12 + (month - 1)) * Timekeeping.DAYS_PER_MONTH + day
