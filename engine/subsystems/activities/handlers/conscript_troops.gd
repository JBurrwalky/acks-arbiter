class_name ConscriptTroopsHandler
extends RefCounted

## conscript_troops handler. Ongoing minor activity per ax_campaign_play.xml
## §conscript_troops L532-546. Up to 1 conscript per 10 peasant families.
## Phase 5 wires this to materialize an actual troop_units row of source_type
## 'conscript' assigned to the ruler's domain. Untrained baseline: hp 1d4, no
## armor, fight as normal men, morale -2, wage 3gp/month per
## daw_armies_recruitment.xml §conscripts and the Untrained Conscripts/Militia
## row in daw_campaigns_troop_tables_summary.xml.
##
## Conscripts cannot voluntarily leave (loyalty failure = desertion); release
## flow returns trained conscripts as mercenaries/brigands, untrained to
## farms. Phase 5 only handles initial muster; release flow is Phase 11+.

const UNTRAINED_TEMPLATE_ID := "untrained_conscripts"
const UNIT_SIZE := 120  # company size; if requested < 120 the unit ships at requested count
const WAGE_CP_PER_SOLDIER := 300    # RAW 3 gp/month per soldier
const SUPPLY_CP_PER_SOLDIER_PER_WEEK := 100  # RAW 1 gp/week per soldier


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var character_id: String = String(state.get("character_id", ""))
	var domain_id: String = _resolve_domain_for_ruler(character_id)
	if domain_id.is_empty():
		return {"summary": "conscript_troops: no domain resolved"}

	var domain: Dictionary = _get_domain(domain_id)
	# Phase 11D.2: chieftains of clanhold-style domains may NOT conscript
	# peasants per RAW ax_domains_of_chaos.xml:36 (clanhold military section).
	# Tribal warrior levy (Phase 11D.5) is the clanhold-style equivalent path.
	if String(domain.get("domain_style", "civilized")) == "clanhold":
		return {
			"summary": "conscript_troops: blocked — clanhold-style chieftains "
				+ "cannot conscript peasants (RAW ax_domains_of_chaos.xml:36). "
				+ "Use Levy Tribal Warriors instead (Phase 11D.5).",
			"blocked_reason": "clanhold_style_no_conscription",
		}
	var peasants: int = int(domain.get("peasant_families", 0))
	@warning_ignore("integer_division")
	var max_conscripts: int = peasants / 10
	var requested: int = int(_parse_params(state).get("count", max_conscripts))
	var count: int = mini(maxi(0, requested), max_conscripts)
	if count <= 0:
		return {"summary": "conscript_troops: insufficient peasants for levy"}

	var character: Dictionary = CampaignRepository.get_character(character_id)
	var calendar_day: int = _calendar_day()
	var ids: Array = _spawn_conscript_units(
		character, domain_id, count, calendar_day)

	# category MUST be one of the ledger CHECK enum (revenue/expense/tribute_in/
	# tribute_out/investment/other) — 'other' is the record-only bucket (cp_amount 0;
	# a conscript levy is a record, not a cp transaction). subcategory carries the tag.
	CampaignRepository.add_ledger_entry({
		"domain_id": domain_id,
		"calendar_day": calendar_day,
		"category": "other",
		"subcategory": "conscript_levy",
		"cp_amount": 0,
		"description": "Levied %d conscripts (untrained, %d unit(s))" % [count, ids.size()],
	})
	return {
		"summary": "%d conscripts levied (%d unit(s))" % [count, ids.size()],
		"unit_ids": ids,
	}


static func _spawn_conscript_units(character: Dictionary, domain_id: String,
		count: int, calendar_day: int) -> Array:
	var ids: Array = []
	var remaining: int = count
	var campaign_id: String = String(character.get("campaign_id", ""))
	var owner_id: String = String(character.get("id", ""))
	while remaining > 0:
		var unit_count: int = mini(remaining, UNIT_SIZE)
		var monthly_wage_cp: int = WAGE_CP_PER_SOLDIER * unit_count
		var monthly_supply_cp: int = SUPPLY_CP_PER_SOLDIER_PER_WEEK * 4 * unit_count
		var monthly_cost_cp: int = monthly_wage_cp + monthly_supply_cp
		var unit_id: String = TroopUnitRepository.create_unit({
			"campaign_id": campaign_id,
			"owner_character_id": owner_id,
			"assigned_domain_id": domain_id,
			"source_type": "conscript",
			"troop_type": "Untrained Conscripts",
			"race": "human",
			"tier": "untrained",
			"starting_count": unit_count,
			"count": unit_count,
			"battle_rating": 0.003 * unit_count,
			"monthly_wage_cp": monthly_wage_cp,
			"monthly_supply_cp": monthly_supply_cp,
			"monthly_specialist_cp": 0,
			"monthly_cost_cp": monthly_cost_cp,
			"morale": -2,
			"is_veteran": false,
			"is_trained": false,
			"unit_xp": 0,
			"assignment_kind": "garrison",
			"hire_calendar_day": calendar_day,
			"equipment_kit": "improvised — no training, fight as normal men",
		})
		if not unit_id.is_empty():
			ids.append(unit_id)
		remaining -= unit_count
	return ids


static func _parse_params(state: Dictionary) -> Dictionary:
	var raw: String = String(state.get("params_json", "{}"))
	var parsed: Variant = JSON.parse_string(raw)
	return parsed if parsed is Dictionary else {}


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
