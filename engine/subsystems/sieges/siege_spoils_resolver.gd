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
##   distribute_to_units(spoils_dict, victor_unit_ids) -> Dictionary
##     {<unit_id>: share_cp, ...}
##     Phase 11D.5 polish: per-warrior-headcount split of total_spoils_cp
##     across the victor units, used by the tribal-warrior retention tick to
##     decide which units met the qualifying-spoils threshold this month.

const PRISONER_VALUE_CP: int = 4_000          # RAW L807: 40 gp = 4,000 cp


## Phase 11D.5 polish — apply a spoils distribution to tribal-warrior units +
## reset months_without_qualifying_spoils for units whose share met the
## qualifying threshold per `gdd-tribal-warriors.md` §7 + Q-TW-1.
##
## Qualifying threshold: `share_cp >= unit.monthly_wage_cp × unit.count`. Units
## with qualifying shares get their counter reset to 0. Non-qualifying units
## are unchanged here; the monthly tick increments them.
##
## Returns a list of unit_ids whose counters were reset.
static func apply_spoils_to_tribal_warriors(
	distribution: Dictionary, calendar_day: int
) -> Array:
	var reset_unit_ids: Array = []
	for unit_id_v in distribution.keys():
		var unit_id: String = String(unit_id_v)
		var share_cp: int = int(distribution[unit_id_v])
		var unit: Dictionary = TroopUnitRepository.get_unit(unit_id)
		if unit.is_empty():
			continue
		if String(unit.get("source_type", "")) != "tribal_warrior":
			continue
		var wage_per: int = int(unit.get("monthly_wage_cp", 0))
		var count: int = int(unit.get("count", 0))
		var required_share: int = wage_per * count
		if share_cp >= required_share and required_share > 0:
			TroopUnitRepository.update_unit(unit_id, {
				"months_without_qualifying_spoils": 0,
			})
			reset_unit_ids.append(unit_id)
	if not reset_unit_ids.is_empty() and calendar_day > 0:
		# Defensive — calendar_day is currently unused but logged here for
		# future polish (per-unit last_qualifying_spoils_day column would
		# enable a more nuanced same-month-overrides-prior-month semantics).
		pass
	return reset_unit_ids


## Phase 11D.5 polish — distribute spoils across the victor's surviving units
## by per-warrior-headcount split. Used by the tribal-warrior retention tick
## (gdd-tribal-warriors.md §7 + Q-TW-1) to determine which units received a
## qualifying share (share ≥ unit's monthly_wage_cp × unit.count) this month.
##
## Returns Dictionary keyed by `troop_unit_id` → `share_cp`. Units not in the
## victor list don't appear in the result.
##
## Distribution: `total_spoils_cp × (unit.count / total_victor_count)`,
## floored. Banker's rounding isn't necessary here — the distribution is
## already lossy (the floor at each unit) and the residual goes nowhere in
## v1 (a future polish may credit the residual to the chieftain / domain
## treasury per `gdd-tribal-warriors.md` §6.3 chieftain-share rules).
static func distribute_to_units(spoils_dict: Dictionary, victor_unit_ids: Array) -> Dictionary:
	var result: Dictionary = {}
	if victor_unit_ids.is_empty():
		return result
	var total_spoils_cp: int = int(spoils_dict.get("total_spoils_cp", 0))
	if total_spoils_cp <= 0:
		for uid in victor_unit_ids:
			result[String(uid)] = 0
		return result
	# Sum total counts across all victor units to derive per-warrior share.
	var unit_counts: Dictionary = {}
	var total_count: int = 0
	for uid in victor_unit_ids:
		var unit: Dictionary = TroopUnitRepository.get_unit(String(uid))
		var c: int = int(unit.get("count", 0)) if not unit.is_empty() else 0
		unit_counts[String(uid)] = c
		total_count += c
	if total_count <= 0:
		for uid in victor_unit_ids:
			result[String(uid)] = 0
		return result
	# Per-headcount split, floored per-unit.
	for uid in victor_unit_ids:
		var uid_s: String = String(uid)
		var c: int = int(unit_counts.get(uid_s, 0))
		@warning_ignore("integer_division")
		result[uid_s] = (total_spoils_cp * c) / total_count
	return result


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
	# wages as monthly_wage_cp (2026-05-16 cp pass); spoils total is cp-native
	# so no conversion needed. Defeated = status IN ('routed', 'destroyed') per
	# migration 076 L20-21.
	if not CampaignRepository.db.query_with_bindings("""
		SELECT COALESCE(SUM(tu.monthly_wage_cp), 0) AS total_cp
		FROM battle_unit_states bus
		JOIN troop_units tu ON tu.id = bus.troop_unit_id
		WHERE bus.battle_id = ? AND bus.status IN ('routed', 'destroyed')
	""", [battle_id]):
		return 0
	if CampaignRepository.db.query_result.is_empty():
		return 0
	return int(CampaignRepository.db.query_result[0].get("total_cp", 0))
