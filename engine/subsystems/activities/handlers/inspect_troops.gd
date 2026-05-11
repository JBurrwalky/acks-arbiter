class_name InspectTroopsHandler
extends RefCounted

## inspect_troops handler. Singular minor activity per ax_campaign_play.xml
## §inspect_troops L573-583. Inspected troops gain +1 to first morale roll
## within one game day.
##
## Phase 5 wires this as a transient morale buff stamped onto every garrison-
## assigned troop_units row in the ruler's domain. The +1 stacks into the
## row's `morale` column directly. Future Phase (11+ Calamities / loyalty)
## owns the "first roll consumes the buff" mechanic; v1 keeps it as a
## permanent +1 since loyalty rolls aren't yet implemented and the +1 here
## is the only way the inspect activity can have a visible effect.
##
## When loyalty rolls are introduced, this handler should be revised to set
## a one-shot "inspected_buff_calendar_day" column instead of permanently
## modifying morale.


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var character_id: String = String(state.get("character_id", ""))
	var domain_id: String = _resolve_domain_for_ruler(character_id)
	if domain_id.is_empty():
		return {"summary": "inspect_troops: no domain resolved"}

	var units: Array = TroopUnitRepository.list_active_for_domain(domain_id)
	var bumped: int = 0
	for u in units:
		if not (u is Dictionary):
			continue
		if String(u.get("assignment_kind", "")) != "garrison":
			continue
		var current: int = int(u.get("morale", 0))
		TroopUnitRepository.update_unit(String(u.get("id", "")), {
			"morale": current + 1,
		})
		bumped += 1

	CampaignRepository.add_ledger_entry({
		"domain_id": domain_id,
		"calendar_day": _calendar_day(),
		"category": "garrison",
		"subcategory": "inspect_troops",
		"gp_amount": 0,
		"description": "Inspected %d garrison units (+1 morale each)" % bumped,
	})
	return {
		"summary": "Inspected %d garrison units (+1 morale)" % bumped,
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
