class_name BattleXPDistributor
extends RefCounted

## Distributes XP to characters and troop units after a field battle per
## daw_axioms_pitching_battle.xml §experience_points L630-645.
##
## RAW splits:
##   - Spoils XP: each participant earns 1 XP per gp personally collected.
##     Troops expect ≥50% of spoils distributed pro rata according to wages.
##     If unpaid, loyalty roll for unpaid troops (deferred to Phase 6A part 2).
##   - Combat XP: army commanders earn XP equal to value of enemy units
##     defeated minus value of friendly units defeated. 50% goes to army leader;
##     remaining 50% divided among commanders proportionate to units led.
##   - Personal XP: characters gain XP for creatures personally defeated
##     (heroic forays). Phase 6B part 2 deferred — combat sub-scene wires this.
##   - Troops gain XP only from spoils, not from combat.
##
## v1 distribution rules (RAW + project-design fill-in):
##   1. Compute spoils gp from monthly wages of destroyed/routed enemy units +
##      40 gp per prisoner. (Already done by `_calculate_spoils` in the
##      field-battle resolver; we accept the precomputed amount.)
##   2. 50% of spoils go to troops pro rata by monthly_wage_gp; credited as
##      unit_xp on troop_units.
##   3. 50% of spoils go to officers via:
##      - 50% of officer pool to army leader (= 25% of total spoils)
##      - 50% of officer pool divided among division_commanders proportionate
##        to units led (= 25% of total spoils total, distributed proportionally)
##   4. Combat XP = value of enemy units destroyed/routed minus friendly units
##      lost. Distributed similarly to spoils-officer-pool: 50% to army leader,
##      50% proportional among division_commanders.
##   5. Officers receive XP via XPAwardCalculator.apply_prime_req_adjustment
##      and EventBus.xp_awarded.emit signals; troops via direct
##      troop_units.unit_xp += amount.
##
## Public API:
##   distribute(battle_id, spoils_gp_total, calendar_day) -> Dictionary
##     {success, total_distributed_gp, attacker_distribution, defender_distribution}


static func distribute(battle_id: String, spoils_gp_total: int, calendar_day: int) -> Dictionary:
	if battle_id.is_empty():
		return {"success": false, "reason": "battle_id_required"}
	var battle: Dictionary = BattleRepository.get_battle(battle_id)
	if battle.is_empty():
		return {"success": false, "reason": "battle_not_found"}
	var outcome: String = String(battle.get("outcome", ""))

	# Determine winning and losing side.
	var attacker_won: bool = outcome.begins_with("attacker_") or outcome == "defender_voluntary_withdrawal" or outcome == "defender_annihilation"
	var defender_won: bool = outcome.begins_with("defender_") or outcome == "attacker_voluntary_withdrawal" or outcome == "attacker_annihilation"

	var winning_army_id: String = ""
	var losing_army_id: String = ""
	if attacker_won:
		winning_army_id = String(battle.get("attacker_army_id", ""))
		losing_army_id = String(battle.get("defender_army_id", ""))
	elif defender_won:
		winning_army_id = String(battle.get("defender_army_id", ""))
		losing_army_id = String(battle.get("attacker_army_id", ""))
	else:
		# Mutual withdrawal — no spoils.
		return {"success": true, "total_distributed_gp": 0, "reason": "mutual_withdrawal_no_spoils"}

	# Compute combat XP totals: value of enemy BR destroyed * combat_xp_per_br
	# minus value of friendly BR lost. v1 conversion: 1 gp value per BR point
	# of destroyed unit (rough proxy). The actual gp value is monthly wages,
	# already aggregated in spoils_gp_total. Combat XP = spoils_gp_total
	# (winners' commander earnings) minus value-of-friendly-losses.
	var winning_lost_value_gp: int = _compute_lost_unit_value_gp(battle_id, _side_for_army(battle, winning_army_id))
	var combat_xp_total: int = max(0, spoils_gp_total - winning_lost_value_gp)

	# Distribute to winning side only (losers get nothing per RAW).
	var winning_distribution: Dictionary = _distribute_to_side(
		winning_army_id, battle_id, _side_for_army(battle, winning_army_id),
		spoils_gp_total, combat_xp_total, calendar_day
	)

	return {
		"success": true,
		"battle_id": battle_id,
		"total_distributed_gp": int(winning_distribution.get("total_xp_credited", 0)),
		"winning_army_id": winning_army_id,
		"winning_distribution": winning_distribution,
		"combat_xp_total": combat_xp_total,
		"calendar_day": calendar_day,
	}


# ---------------------------------------------------------------------------
# Per-side distribution
# ---------------------------------------------------------------------------

static func _distribute_to_side(
	army_id: String, battle_id: String, side: String,
	spoils_gp_total: int, combat_xp_total: int, calendar_day: int
) -> Dictionary:
	if army_id.is_empty():
		return {"total_xp_credited": 0}
	var officers: Array = ArmyRepository.list_officers_for_army(army_id)
	var leader: Dictionary = ArmyRepository.get_army_leader(army_id)
	var leader_id: String = String(leader.get("character_id", ""))

	# Split spoils 50/50 troops vs. officers.
	var troops_pool: int = int(round(float(spoils_gp_total) * 0.5))
	var officers_pool: int = spoils_gp_total - troops_pool

	# Combine officer pool with combat XP (combat XP is officer-only per RAW).
	var officer_total_xp: int = officers_pool + combat_xp_total

	# Army leader gets 50% of officer total.
	var leader_xp: int = int(round(float(officer_total_xp) * 0.5))
	var commanders_xp_pool: int = officer_total_xp - leader_xp

	# Division commanders share commanders_xp_pool proportionate to units led.
	var dc_units: Dictionary = _count_units_per_division_commander(army_id, officers)
	var total_units_under_dcs: int = 0
	for dc_id in dc_units:
		total_units_under_dcs += int(dc_units[dc_id])

	var per_dc_xp: Dictionary = {}
	if total_units_under_dcs > 0:
		for dc_id in dc_units:
			var share: float = float(dc_units[dc_id]) / float(total_units_under_dcs)
			per_dc_xp[dc_id] = int(round(float(commanders_xp_pool) * share))
	else:
		# No DCs — collapse the commanders pool back to the leader.
		leader_xp += commanders_xp_pool

	# Credit XP to characters.
	var total_xp_credited: int = 0
	if not leader_id.is_empty() and leader_xp > 0:
		_credit_xp_to_character(leader_id, leader_xp)
		total_xp_credited += leader_xp

	var dc_credits: Array = []
	for dc_officer_id in per_dc_xp:
		var officer: Dictionary = _find_officer_in_list(officers, dc_officer_id)
		if officer.is_empty():
			continue
		var dc_char_id: String = String(officer.get("character_id", ""))
		var amount: int = int(per_dc_xp[dc_officer_id])
		if amount > 0 and not dc_char_id.is_empty():
			_credit_xp_to_character(dc_char_id, amount)
			total_xp_credited += amount
			dc_credits.append({"character_id": dc_char_id, "officer_id": dc_officer_id, "xp": amount})

	# Distribute troops_pool to troop_units pro rata by monthly_wage_gp.
	var troop_credits: Array = _distribute_troops_pool(army_id, troops_pool)
	for credit in troop_credits:
		total_xp_credited += int(credit.get("xp", 0))

	# Log to battle_log.
	BattleRepository.append_log(battle_id, "xp_distributed", 1, "aftermath", 0, side,
		{
			"side": side,
			"army_id": army_id,
			"spoils_gp_total": spoils_gp_total,
			"combat_xp_total": combat_xp_total,
			"troops_pool": troops_pool,
			"officers_pool": officers_pool,
			"leader_xp": leader_xp,
			"leader_id": leader_id,
			"dc_credits": dc_credits,
			"troop_credits": troop_credits,
		}, calendar_day)

	return {
		"side": side,
		"leader_id": leader_id,
		"leader_xp": leader_xp,
		"dc_credits": dc_credits,
		"troop_credits": troop_credits,
		"total_xp_credited": total_xp_credited,
	}


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _side_for_army(battle: Dictionary, army_id: String) -> String:
	if String(battle.get("attacker_army_id", "")) == army_id:
		return "attacker"
	return "defender"


static func _compute_lost_unit_value_gp(battle_id: String, side: String) -> int:
	## Sum of monthly_wage_gp of units on this side whose battle status is
	## destroyed or routed. Used as the "friendly units lost" subtractor for
	## combat XP per RAW L639.
	var states: Array = BattleRepository.list_unit_states_for_side(battle_id, side)
	var total: int = 0
	for s in states:
		var status: String = String(s.get("status", "engaged"))
		if status != "destroyed" and status != "routed":
			continue
		var unit_id: String = String(s.get("troop_unit_id", ""))
		if unit_id.is_empty():
			continue
		if not CampaignRepository.db.query_with_bindings(
			"SELECT monthly_wage_gp FROM troop_units WHERE id = ?", [unit_id]):
			continue
		if CampaignRepository.db.query_result.is_empty():
			continue
		total += int(CampaignRepository.db.query_result[0].get("monthly_wage_gp", 0))
	return total


static func _count_units_per_division_commander(army_id: String, officers: Array) -> Dictionary:
	## Returns Dictionary { division_commander_officer_id : unit_count }.
	## A unit's parent_officer_id may be a lieutenant or a division_commander.
	## Walk lieutenants up to their division_commander.
	var assignments: Array = ArmyRepository.list_active_assignments_for_army(army_id)
	var officer_by_id: Dictionary = {}
	for officer in officers:
		officer_by_id[String(officer.get("id", ""))] = officer

	var counts: Dictionary = {}
	for officer in officers:
		if String(officer.get("rank", "")) == "division_commander":
			counts[String(officer.get("id", ""))] = 0

	for assn in assignments:
		var parent_oid: String = String(assn.get("parent_officer_id", ""))
		var owner_officer: Dictionary = officer_by_id.get(parent_oid, {})
		if owner_officer.is_empty():
			continue
		var rank: String = String(owner_officer.get("rank", ""))
		var dc_id: String = ""
		if rank == "division_commander":
			dc_id = parent_oid
		elif rank == "lieutenant":
			dc_id = String(owner_officer.get("parent_officer_id", ""))
		if dc_id.is_empty():
			continue
		counts[dc_id] = int(counts.get(dc_id, 0)) + 1
	return counts


static func _find_officer_in_list(officers: Array, officer_id: String) -> Dictionary:
	for o in officers:
		if String(o.get("id", "")) == officer_id:
			return o
	return {}


static func _distribute_troops_pool(army_id: String, troops_pool_gp: int) -> Array:
	## Returns Array[{troop_unit_id, xp}] of credits made.
	if troops_pool_gp <= 0:
		return []
	var assignments: Array = ArmyRepository.list_active_assignments_for_army(army_id)
	if assignments.is_empty():
		return []
	# Compute total wage weight.
	var total_wage: int = 0
	var unit_wages: Array = []
	for assn in assignments:
		var unit_id: String = String(assn.get("troop_unit_id", ""))
		var wage: int = _get_unit_wage(unit_id)
		unit_wages.append({"troop_unit_id": unit_id, "wage": wage})
		total_wage += wage
	if total_wage <= 0:
		# Equal distribution if no wage data.
		var per_unit: int = int(troops_pool_gp / unit_wages.size())
		var credits: Array = []
		for entry in unit_wages:
			_credit_unit_xp(String(entry["troop_unit_id"]), per_unit)
			credits.append({"troop_unit_id": entry["troop_unit_id"], "xp": per_unit})
		return credits
	var credits: Array = []
	for entry in unit_wages:
		var share: float = float(entry["wage"]) / float(total_wage)
		var amount: int = int(round(float(troops_pool_gp) * share))
		if amount > 0:
			_credit_unit_xp(String(entry["troop_unit_id"]), amount)
			credits.append({"troop_unit_id": entry["troop_unit_id"], "xp": amount})
	return credits


static func _credit_xp_to_character(character_id: String, amount: int) -> void:
	if character_id.is_empty() or amount <= 0:
		return
	# Update characters.xp directly.
	if not CampaignRepository.db.query_with_bindings(
		"UPDATE characters SET xp = xp + ? WHERE id = ?", [amount, character_id]):
		return
	if EventBus.has_signal("xp_awarded"):
		EventBus.emit_signal("xp_awarded", character_id, amount)


static func _credit_unit_xp(troop_unit_id: String, amount: int) -> void:
	if troop_unit_id.is_empty() or amount <= 0:
		return
	# Update troop_units.unit_xp directly. The TroopUnitRepository whitelist
	# allows updating unit_xp.
	var unit: Dictionary = _get_unit(troop_unit_id)
	if unit.is_empty():
		return
	var new_xp: int = int(unit.get("unit_xp", 0)) + amount
	TroopUnitRepository.update_unit(troop_unit_id, {"unit_xp": new_xp})


static func _get_unit_wage(troop_unit_id: String) -> int:
	if troop_unit_id.is_empty():
		return 0
	if not CampaignRepository.db.query_with_bindings(
		"SELECT monthly_wage_gp FROM troop_units WHERE id = ?", [troop_unit_id]):
		return 0
	if CampaignRepository.db.query_result.is_empty():
		return 0
	return int(CampaignRepository.db.query_result[0].get("monthly_wage_gp", 0))


static func _get_unit(troop_unit_id: String) -> Dictionary:
	if troop_unit_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM troop_units WHERE id = ?", [troop_unit_id]):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()
