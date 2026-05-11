class_name SiegeSpoilsResolver
extends RefCounted

## Spoils calculation per rules/daw_sieges.xml §spoils_of_sieges L805-811.
##
##   Victorious siege spoils equal one month's wages of each defeated unit.
##   Each prisoner captured is worth 40gp if sold as a slave or ransomed.
##   Experience points are assigned as with a battle.
##   The stronghold and domain may also be pillaged for additional plunder.
##
## All amounts in cp per project convention. 40 gp = 4,000 cp.
##
## Public API:
##   compute_spoils(siege_id, casualty_assessment) -> Dictionary
##     {wages_cp, prisoner_value_cp, total_spoils_cp, pillage_pending}

const PRISONER_VALUE_CP: int = 4_000          # RAW L807: 40 gp = 4,000 cp


static func compute_spoils(siege_id: String, casualty_assessment: Dictionary) -> Dictionary:
	var siege: Dictionary = SiegeRepository.get_siege(siege_id)
	var outcome: String = String(siege.get("outcome", ""))
	if outcome != "captured" and outcome != "destroyed" and outcome != "surrendered":
		return {"wages_cp": 0, "prisoner_value_cp": 0, "total_spoils_cp": 0, "pillage_pending": false}
	# Wages: one month's wages per defeated unit. Pull from the related battle's
	# defeated unit states by joining troop_units → monthly wage.
	var wages_cp: int = _sum_monthly_wages_of_defeated_units(siege_id)
	var prisoners: int = int(casualty_assessment.get("prisoner_count_total", 0))
	var prisoner_value: int = prisoners * PRISONER_VALUE_CP
	return {
		"wages_cp": wages_cp,
		"prisoner_value_cp": prisoner_value,
		"total_spoils_cp": wages_cp + prisoner_value,
		"pillage_pending": true,  # additional plunder to be resolved by domain pillage UI
	}


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _sum_monthly_wages_of_defeated_units(siege_id: String) -> int:
	## Find the siege's related battle id (most recent assault_turn ledger row),
	## then sum monthly_wage_cp for defeated units in that battle.
	if not CampaignRepository.db.query_with_bindings("""
		SELECT related_battle_id FROM siege_actions
		WHERE siege_id = ? AND action_type = 'assault_turn'
		      AND related_battle_id IS NOT NULL
		ORDER BY calendar_day DESC, created_at DESC
		LIMIT 1
	""", [siege_id]):
		return 0
	if CampaignRepository.db.query_result.is_empty():
		return 0
	var battle_id: String = String(CampaignRepository.db.query_result[0].get("related_battle_id", ""))
	if battle_id.is_empty():
		return 0
	# Sum monthly wages for defeated units in that battle. troop_units stores
	# wages as monthly_wage_gp (legacy column, predates the cp convention);
	# convert to cp by ×100. Defeated = status IN ('routed', 'destroyed') per
	# migration 076 L20-21.
	if not CampaignRepository.db.query_with_bindings("""
		SELECT COALESCE(SUM(tu.monthly_wage_gp), 0) AS total_gp
		FROM battle_unit_states bus
		JOIN troop_units tu ON tu.id = bus.troop_unit_id
		WHERE bus.battle_id = ? AND bus.status IN ('routed', 'destroyed')
	""", [battle_id]):
		return 0
	if CampaignRepository.db.query_result.is_empty():
		return 0
	return int(CampaignRepository.db.query_result[0].get("total_gp", 0)) * 100
