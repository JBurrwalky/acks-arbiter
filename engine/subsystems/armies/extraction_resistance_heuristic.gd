class_name ExtractionResistanceHeuristic
extends RefCounted

## Realm AI decision: should the local domain owner resist a Requisition or
## Loot order with battle?
##
## Per gdd-army-warfare.md §4.3.3 + O-A-9 resolution: domain owner attacks
## the requisitioning / looting army if and only if he can bring at least
## 50% of the offending army's BR to bear from his own personal-domain
## garrison + any vassal forces within muster range. Lord-vassal cases (a
## lord's army looting a vassal's domain) follow the same heuristic but
## trigger an additional henchman-morale roll on the vassal per
## acore_axioms_strongholds_and_domains.xml favors-and-duties before commit.
##
## Phase 7 implementation (replaces the prior v1 50% BR placeholder):
## federates vassal forces via RealmGraph + VassalRepository within the
## muster-delay window of the local domain's apex (Baron-Count = Week,
## Prince-Duke = Month, King-Emperor = Season per acore_axioms §muster_delay
## L373-382). Each summoned vassal performs a Henchman Loyalty roll
## (HenchmanLoyaltyResolver); on Resignation/Hostility the vassal's force
## does NOT muster and the vassal_assignment is flagged via
## EventBus.vassal_revolted. Non-henchman vassals roll at the RAW base
## loyalty -2 (or -4 if outside the trade range of the ruler's largest urban
## settlement) per §non_henchman_vassals L392-397.
##
## Public API:
##   evaluate(domain_id, attacker_army_id, calendar_day, dice) -> Dictionary
##     `dice` follows the HenchmanLoyaltyResolver convention: a node-like
##     object with a `roll(count, sides) -> int` method (typically a test
##     FakeDice or a runtime DiceSystem-like service). Pass null to use
##     pseudo-random.
##     Returns:
##     {
##       will_resist: bool,
##       attacker_br: float,
##       defender_br: float,            # personal garrison + mustered vassal forces
##       threshold_br: float,            # 0.5 × attacker_br
##       resistance_force: Dict,
##       vassals_responding: Array,      # [{vassal_assignment_id, br, outcome}]
##       vassals_refusing: Array,        # [{vassal_assignment_id, br, outcome}]
##       reason: String,
##       calendar_day: int,
##     }

const RESISTANCE_THRESHOLD_FRACTION := 0.5  # 50% per O-A-9


static func evaluate(
	domain_id: String,
	attacker_army_id: String,
	calendar_day: int,
	dice = null
) -> Dictionary:
	var attacker_br: float = _compute_army_br(attacker_army_id)
	var personal_br: float = _compute_local_garrison_br(domain_id)
	var federation: Dictionary = _federate_vassal_forces(domain_id, calendar_day, dice)
	var vassal_br: float = float(federation.get("br_total", 0.0))
	var defender_br: float = personal_br + vassal_br
	var threshold_br: float = attacker_br * RESISTANCE_THRESHOLD_FRACTION
	var will_resist: bool = defender_br >= threshold_br and defender_br > 0.0
	var reason: String = ""
	if not will_resist:
		if defender_br <= 0.0:
			reason = "no_local_garrison"
		else:
			reason = "garrison_below_50pct_threshold"
	else:
		reason = "garrison_meets_50pct_threshold"

	return {
		"will_resist": will_resist,
		"available_br": defender_br,
		"personal_br": personal_br,
		"vassal_br": vassal_br,
		"attacker_br": attacker_br,
		"threshold_br": threshold_br,
		"resistance_force": _describe_resistance_force(domain_id),
		"vassals_responding": federation.get("responding", []),
		"vassals_refusing": federation.get("refusing", []),
		"reason": reason,
		"calendar_day": calendar_day,
	}


# ---------------------------------------------------------------------------
# Internal computations
# ---------------------------------------------------------------------------

static func _compute_army_br(army_id: String) -> float:
	if army_id.is_empty():
		return 0.0
	var assignments: Array = ArmyRepository.list_active_assignments_for_army(army_id)
	var total: float = 0.0
	for assn in assignments:
		var unit: Dictionary = _get_troop_unit(String(assn.get("troop_unit_id", "")))
		if unit.is_empty():
			continue
		total += float(unit.get("battle_rating", 0.0))
	return total


static func _compute_local_garrison_br(domain_id: String) -> float:
	if domain_id.is_empty():
		return 0.0
	if not CampaignRepository.db.query_with_bindings("""
		SELECT tu.battle_rating, tu.id AS unit_id FROM troop_units tu
		WHERE tu.assigned_domain_id = ?
		  AND tu.status = 'active'
		  AND tu.assignment_kind = 'garrison'
	""", [domain_id]):
		return 0.0
	var rows: Array = CampaignRepository.db.query_result.duplicate()
	var total: float = 0.0
	for row in rows:
		var unit_id: String = str(row.get("unit_id", ""))
		var assn: Dictionary = ArmyRepository.get_active_assignment_for_unit(unit_id)
		if not assn.is_empty():
			continue
		total += float(row.get("battle_rating", 0.0))
	return total


# ---------------------------------------------------------------------------
# Phase 7 Realm-AI: federate vassal forces within muster range
# ---------------------------------------------------------------------------

static func _federate_vassal_forces(
	domain_id: String,
	calendar_day: int,
	dice
) -> Dictionary:
	var responding: Array = []
	var refusing: Array = []
	var br_total: float = 0.0
	if domain_id.is_empty():
		return {"responding": responding, "refusing": refusing, "br_total": 0.0}

	var domain: Dictionary = CampaignRepository.get_domain(domain_id)
	if domain.is_empty():
		return {"responding": responding, "refusing": refusing, "br_total": 0.0}
	var liege_character_id: String = String(domain.get("owner_character_id", ""))
	if liege_character_id.is_empty():
		return {"responding": responding, "refusing": refusing, "br_total": 0.0}

	# Muster cadence per acore_axioms §muster_delay L373-382 — derived from
	# the apex's realm_title. v1 simplification: any vassal within the apex's
	# nominal muster window can respond. Geographic distance gating (full
	# muster_delay table) is a Phase 8 polish item.
	var apex_id: String = RealmGraph.apex_for_character(liege_character_id)
	var muster_period: String = RealmGraph.muster_delay_period_for_apex(apex_id)
	var _muster_period_days: int = _period_to_days(muster_period)

	var assignments: Array = VassalRepository.list_active_for_liege(liege_character_id)
	for assn in assignments:
		var assn_id: String = String(assn.get("id", ""))
		var vassal_character_id: String = String(assn.get("vassal_character_id", ""))
		var is_henchman: bool = int(assn.get("is_henchman_vassal", 1)) == 1
		var base_mod: int = int(assn.get("base_loyalty_modifier", 0))
		var v_domain_id: String = String(assn.get("vassal_domain_id", ""))

		# Loyalty roll for muster — Call-to-Arms ask. Loyalty modifier: vassal's
		# stored base_loyalty_modifier (typically 0 for henchman, -2 or -4 for
		# non-henchman per RAW §non_henchman_vassals). Phase 8 polish: also
		# applies Office bonus per RAW L369 (+1 if vassal's liege holds an
		# active office).
		var combined_mod: int = base_mod + FavorsDutiesResolver.office_bonus_for_vassal_roll(vassal_character_id)
		var roll_outcome: Dictionary = HenchmanLoyaltyResolver.resolve_loyalty_check(
			combined_mod, false, false, dice
		)
		var outcome: String = String(roll_outcome.get("outcome", ""))
		VassalRepository.record_loyalty_roll(assn_id, outcome, calendar_day)

		var vassal_br: float = _vassal_garrison_br(v_domain_id)
		if bool(roll_outcome.get("departs", false)):
			# Resignation / hostility: vassal does NOT muster. Per RAW the
			# vassalage itself is at risk; we mark the assignment revolted
			# and emit the signal. Phase 8 Favors & Duties may add nuance
			# (e.g., grace period before revolt).
			VassalRepository.update_status(assn_id, "revolted", calendar_day)
			if EventBus.has_signal("vassal_revolted"):
				EventBus.emit_signal("vassal_revolted",
					assn_id, vassal_character_id, liege_character_id)
			refusing.append({
				"vassal_assignment_id": assn_id,
				"vassal_character_id": vassal_character_id,
				"is_henchman": is_henchman,
				"br": vassal_br,
				"outcome": outcome,
			})
		else:
			br_total += vassal_br
			responding.append({
				"vassal_assignment_id": assn_id,
				"vassal_character_id": vassal_character_id,
				"is_henchman": is_henchman,
				"br": vassal_br,
				"outcome": outcome,
			})

	return {
		"responding": responding,
		"refusing": refusing,
		"br_total": br_total,
		"muster_period": muster_period,
	}


static func _vassal_garrison_br(domain_id: String) -> float:
	# Sum BR of garrison units assigned to the vassal's domain that are not
	# already in another active army.
	return _compute_local_garrison_br(domain_id)


static func _period_to_days(period: String) -> int:
	match period:
		"Week": return 7
		"Month": return 30
		"Season": return 90
		_: return 7


# ---------------------------------------------------------------------------
# Resistance force descriptor
# ---------------------------------------------------------------------------

static func _describe_resistance_force(domain_id: String) -> Dictionary:
	if domain_id.is_empty():
		return {"unit_ids": []}
	if not CampaignRepository.db.query_with_bindings("""
		SELECT id FROM troop_units
		WHERE assigned_domain_id = ?
		  AND status = 'active'
		  AND assignment_kind = 'garrison'
	""", [domain_id]):
		return {"unit_ids": []}
	var ids: Array = []
	for row in CampaignRepository.db.query_result:
		ids.append(str(row.get("id", "")))
	return {"unit_ids": ids}


static func _get_troop_unit(troop_unit_id: String) -> Dictionary:
	if troop_unit_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM troop_units WHERE id = ?", [troop_unit_id]):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()
