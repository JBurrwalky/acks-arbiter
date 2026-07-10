class_name BetrayalResolver
extends RefCounted

## Feign -> betrayal execution (gdd-faction-framework.md §7.3 — FF-4). A feigning
## faction (public_stance = professed side, hidden true_stance = truly-preferred side)
## carries a BETRAYAL CONDITION on the stance toward the side it professes loyalty to.
## When a world event satisfies that condition, the faction executes the flip on its
## next turn: stance swap + one prepared free §6.7 covert op at +4 against the betrayed
## side + a `betrayal_executed` ledger entry that NEVER expires (§4.5).
##
## The condition enum (§7.3), parameterized:
##   side_loses_field_battle       — flip when the professed side loses a field battle
##   siege_of_seat_begins          — flip when the professed side's seat is besieged
##   patron_payment_missed(n)      — flip when the patron misses n months' stipend
##   rival_org_declares_for(side)  — flip when a rival org declares for the other side
##   power_ratio_crosses(x)        — flip when the power ratio crosses a threshold
##   evidence_of_persecution_plan  — flip on proof the professed side plans persecution
##
## Deterministic: firing is driven by explicit game events + day; the free op uses the
## shared `dice` seam. No wall-clock, no un-seeded randi().

const COND_SIDE_LOSES_FIELD_BATTLE: String = "side_loses_field_battle"
const COND_SIEGE_OF_SEAT_BEGINS: String = "siege_of_seat_begins"
const COND_PATRON_PAYMENT_MISSED: String = "patron_payment_missed"
const COND_RIVAL_ORG_DECLARES_FOR: String = "rival_org_declares_for"
const COND_POWER_RATIO_CROSSES: String = "power_ratio_crosses"
const COND_EVIDENCE_OF_PERSECUTION_PLAN: String = "evidence_of_persecution_plan"

const CONDITION_KINDS: Array = [
	COND_SIDE_LOSES_FIELD_BATTLE, COND_SIEGE_OF_SEAT_BEGINS, COND_PATRON_PAYMENT_MISSED,
	COND_RIVAL_ORG_DECLARES_FOR, COND_POWER_RATIO_CROSSES, COND_EVIDENCE_OF_PERSECUTION_PLAN,
]

## The betrayal grievance magnitude (never expires, §4.5).
const BETRAYAL_MAGNITUDE: int = -6


# ---------------------------------------------------------------------------
# Condition generation (called by AllegianceEvaluator on a feign)
# ---------------------------------------------------------------------------

## Generate the betrayal condition a fresh feign arms. Default: flip when the
## PROFESSED (seat) side loses a field battle — the §7.5 Orso outcome
## (`side_loses_field_battle(Orso)`). A caller may steer the choice with
## conflict.betrayal_hint (one of CONDITION_KINDS). Returns a JSON-ready Dictionary
## carrying the professed/true mirror ids so firing can execute the swap.
static func generate_condition(faction: Dictionary, professed_side_mirror: String,
		true_side_mirror: String, conflict: Dictionary) -> Dictionary:
	var professed_realm: String = FactionRegistry.realm_id_of_mirror(professed_side_mirror)
	var kind: String = StringUtils.s(conflict.get("betrayal_hint"))
	if not CONDITION_KINDS.has(kind):
		kind = COND_SIDE_LOSES_FIELD_BATTLE   # the §7.5 default
	var params: Dictionary = {
		"side_mirror": professed_side_mirror,
		"side_realm_id": professed_realm,
	}
	match kind:
		COND_PATRON_PAYMENT_MISSED:
			params["n_months"] = int(conflict.get("patron_grace_months", 2))
		COND_POWER_RATIO_CROSSES:
			params["x"] = float(conflict.get("power_ratio_x", 0.4))
		COND_RIVAL_ORG_DECLARES_FOR:
			params["declared_side_mirror"] = true_side_mirror
	return {
		"kind": kind,
		"params": params,
		"professed_mirror": professed_side_mirror,
		"true_mirror": true_side_mirror,
		"conflict_id": StringUtils.s(conflict.get("conflict_id")),
	}


# ---------------------------------------------------------------------------
# Firing (called by the event bus / conflict dispatcher on a world event)
# ---------------------------------------------------------------------------

## Scan every instantiated stance carrying a betrayal condition and fire the flip on
## the ones this [param event_kind]/[param event_data] satisfies. Returns an Array of
## per-betrayal reports. [param campaign_id] scopes the scan.
static func check_and_fire(campaign_id: String, event_kind: String, event_data: Dictionary,
		day: int, dice = null) -> Array:
	var fired: Array = []
	for row in CampaignRepository.ff_list_stances_with_betrayal(campaign_id):
		var r: Dictionary = row
		var cond: Dictionary = _parse_json(StringUtils.s(r.get("betrayal_condition")))
		if cond.is_empty():
			continue
		if condition_matches(cond, event_kind, event_data):
			var res: Dictionary = execute_betrayal(campaign_id, r, cond, day, dice)
			if bool(res.get("ok", false)):
				fired.append(res)
	return fired


## Does [param event_kind]/[param event_data] satisfy [param cond]? Pure predicate.
static func condition_matches(cond: Dictionary, event_kind: String, event_data: Dictionary) -> bool:
	var params: Dictionary = cond.get("params", {})
	match String(cond.get("kind", "")):
		COND_SIDE_LOSES_FIELD_BATTLE:
			if event_kind != "field_battle_resolved":
				return false
			return _matches_side(event_data, "loser_realm_id", "loser_mirror", params)
		COND_SIEGE_OF_SEAT_BEGINS:
			if event_kind != "siege_begun":
				return false
			return _matches_side(event_data, "besieged_realm_id", "besieged_mirror", params)
		COND_PATRON_PAYMENT_MISSED:
			if event_kind != "patron_payment_missed":
				return false
			if StringUtils.s(event_data.get("patron_mirror")) != StringUtils.s(params.get("side_mirror")):
				return false
			return int(event_data.get("months_missed", 0)) >= int(params.get("n_months", 1))
		COND_RIVAL_ORG_DECLARES_FOR:
			if event_kind != "rival_org_declared":
				return false
			return StringUtils.s(event_data.get("declared_side_mirror")) == StringUtils.s(params.get("declared_side_mirror"))
		COND_POWER_RATIO_CROSSES:
			if event_kind != "power_ratio_update":
				return false
			return float(event_data.get("ratio", 1.0)) <= float(params.get("x", 0.0))
		COND_EVIDENCE_OF_PERSECUTION_PLAN:
			if event_kind != "persecution_plan_evidence":
				return false
			return StringUtils.s(event_data.get("target_mirror")) == StringUtils.s(params.get("side_mirror")) \
				or StringUtils.s(event_data.get("planner_mirror")) == StringUtils.s(params.get("side_mirror"))
		_:
			return false


## Execute the flip for a feigning [param stance_row] whose condition just fired.
## Drops the mask (professed side -> now openly hostile), sides openly with the true
## preference, runs one prepared free op at +4, and writes the permanent betrayal.
static func execute_betrayal(campaign_id: String, stance_row: Dictionary, cond: Dictionary,
		day: int, dice = null) -> Dictionary:
	var faction_id: String = StringUtils.s(stance_row.get("faction_a_id"))
	var professed_mirror: String = StringUtils.s(stance_row.get("faction_b_id"))
	var true_mirror: String = StringUtils.s(cond.get("true_mirror"))
	if faction_id == "" or professed_mirror == "":
		return {"ok": false, "error": "empty_id"}
	if dice == null:
		dice = SeededDice.for_monthly(faction_id + "|betray|" + professed_mirror, day, "betrayal")

	# 1) Stance swap: the mask drops. Now openly hostile to the betrayed side; openly
	#    friendly to the side truly favored all along. Clearing true_stance +
	#    betrayal_condition (pass "") realizes the treachery in the open ledger.
	FactionStanceService.set_conflict_stance(campaign_id, faction_id, professed_mirror,
		"hostile", "", "", "betrayal executed", day)
	if true_mirror != "":
		FactionStanceService.set_conflict_stance(campaign_id, faction_id, true_mirror,
			"friendly", "", "", "betrayal: revealed true allegiance", day)

	# 2) One prepared free covert op at +4 against the betrayed side (gates opened,
	#    garrison intel delivered, funds withheld — §7.3).
	var faction: Dictionary = CampaignRepository.get_faction(faction_id)
	var op_report: Dictionary = CovertOps.run_op(campaign_id, "sabotage", faction,
		professed_mirror, day, dice, {"throw_bonus": CovertOps.BETRAYAL_OP_BONUS})

	# 3) The permanent ledger entry: betrayal is never forgiven (§4.5 — never expires).
	FactionEventLedger.record(campaign_id, day, faction_id, professed_mirror,
		"betrayal_executed", BETRAYAL_MAGNITUDE,
		JSON.stringify({"condition": cond.get("kind", ""), "true_side": true_mirror}))

	if EventBus.has_signal("betrayal_executed"):
		EventBus.emit_signal("betrayal_executed", faction_id, professed_mirror)
	PoliticalAudit.record("betrayal_executed", {
		"caller": "betrayal_resolver", "faction": faction_id,
		"betrayed": professed_mirror, "sided_with": true_mirror,
		"condition": cond.get("kind", ""), "day": day,
		"op_success": op_report.get("success", false),
	})
	PoliticalAudit.bump_counter("betrayals_fired")
	return {"ok": true, "faction_id": faction_id, "betrayed": professed_mirror,
		"sided_with": true_mirror, "op": op_report, "condition_kind": cond.get("kind", "")}


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

## Match a side by realm-id OR mirror-id, whichever the event carries.
static func _matches_side(event_data: Dictionary, realm_key: String, mirror_key: String,
		params: Dictionary) -> bool:
	var target_realm: String = StringUtils.s(params.get("side_realm_id"))
	var target_mirror: String = StringUtils.s(params.get("side_mirror"))
	var ev_realm: String = StringUtils.s(event_data.get(realm_key))
	var ev_mirror: String = StringUtils.s(event_data.get(mirror_key))
	if target_realm != "" and ev_realm != "" and target_realm == ev_realm:
		return true
	if target_mirror != "" and ev_mirror != "" and target_mirror == ev_mirror:
		return true
	return false


static func _parse_json(s: String) -> Dictionary:
	if s == "":
		return {}
	var parsed: Variant = JSON.parse_string(s)
	return parsed if parsed is Dictionary else {}
