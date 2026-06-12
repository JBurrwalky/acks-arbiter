class_name OverseeTroopTrainingHandler
extends RefCounted

## oversee_troop_training handler. Ongoing minor per ax_campaign_play.xml
## §oversee_troop_training L674-687. Per 60 troops; troops gain permanent +1
## morale while in ruler's service; finish as veterans if ruler also trains.
##
## Phase 5 wires this to a +1 morale stamp on up to 60 garrison-assigned
## soldiers. When the ruler also runs train_troops on the same units (via
## the combined-flag check), the unit's tier auto-promotes from 'average' to
## 'veteran' and is_veteran flips. v1 detects the "ruler also trains" case by
## checking that the unit's most recent train_troops ledger row is within the
## past 28 days — a coarse heuristic until concurrent activity tracking lands.

const OVERSEE_CAP_PER_ACTIVITY := 60


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var character_id: String = String(state.get("character_id", ""))
	var domain_id: String = _resolve_domain_for_ruler(character_id)
	if domain_id.is_empty():
		return {"summary": "oversee_troop_training: no domain resolved"}

	var ruler_also_training: bool = _ruler_recently_trained_troops(domain_id)
	var units: Array = TroopUnitRepository.list_active_for_domain(domain_id)
	var soldiers_remaining: int = OVERSEE_CAP_PER_ACTIVITY
	var bumped_units: int = 0
	for u in units:
		if not (u is Dictionary):
			continue
		if soldiers_remaining <= 0:
			break
		if String(u.get("assignment_kind", "")) != "garrison":
			continue
		var unit_count: int = int(u.get("count", 0))
		if unit_count <= 0:
			continue
		if unit_count > soldiers_remaining:
			continue
		var fields: Dictionary = {
			"morale": int(u.get("morale", 0)) + 1,
		}
		if ruler_also_training and int(u.get("is_trained", 0)) != 0:
			fields["tier"] = "veteran"
			fields["is_veteran"] = 1
		TroopUnitRepository.update_unit(String(u.get("id", "")), fields)
		soldiers_remaining -= unit_count
		bumped_units += 1

	var summary_suffix: String = " + veteran promotion" if ruler_also_training else ""
	CampaignRepository.add_ledger_entry({
		"domain_id": domain_id,
		"calendar_day": _calendar_day(),
		# Per ledger_entries CHECK constraint: 'garrison' is not valid; use
		# 'other' for the informational audit row (no gp moves).
		"category": "other",
		"subcategory": "oversee_troop_training",
		"cp_amount": 0,
		"description": "Oversaw training of %d unit(s); +1 permanent morale%s" % [
			bumped_units, summary_suffix,
		],
	})
	return {
		"summary": "Oversaw training: +1 morale on %d unit(s)%s" % [
			bumped_units, summary_suffix,
		],
	}


static func _ruler_recently_trained_troops(domain_id: String) -> bool:
	var since_day: int = _calendar_day() - Timekeeping.DAYS_PER_MONTH
	if not CampaignRepository.db.query_with_bindings("""
		SELECT 1 FROM ledger_entries
		WHERE domain_id = ? AND subcategory = 'train_troops'
		  AND calendar_day >= ?
		LIMIT 1
	""", [domain_id, since_day]):
		return false
	return not CampaignRepository.db.query_result.is_empty()


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
