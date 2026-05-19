class_name FavorsDutiesResolver
extends RefCounted

## Phase 8: Favors & Duties monthly resolution per
## acore_axioms_strongholds_and_domains.xml §favors_and_duties L352-372.
##
## Each month, for each active vassal_assignment, the lord rolls 1d20:
##   1     construction      duty,   ongoing
##   2     scutage           duty,   ongoing
##   3-4   call_to_council   duty,   ongoing
##   5-6   call_to_arms      duty,   ongoing
##   7-8   loan              duty,   ongoing
##   9-12  revoke            (sub-roll 1d6: 1=revoke favor, 2-6=revoke duty)
##   13-14 charter_of_monopoly  favor, ongoing
##   15-16 gift              favor, one-time
##   17-18 office            favor, ongoing
##   19    troops            favor, ongoing
##   20    grant_of_land     favor, one-time
##
## Safe-duty threshold per RAW L353-358:
##   safe_total = 1 + ongoing_favors + one_time_favors_this_month
## Each duty BEYOND safe_total triggers a HenchmanLoyaltyResolver check with
## cumulative -1 penalty per excess duty. On Resignation/Hostility, the
## vassal_assignment.status flips to "revolted" and EventBus emits
## vassal_revolted (signal landed in Phase 7).
##
## Non-henchman vassals per RAW L395 ("only one duty per favor; no free duty"):
##   safe_total = ongoing_favors + one_time_favors_this_month   (no +1)
##
## Mechanical effects per result:
##   gift:    immediate treasury transfer (lord gp -value, vassal gp +value).
##   loan:    lord gets +1gp/family one-time at issue (vassal gp -value;
##            repayment chance per CHA% deferred to future polish).
##   scutage: monthly gp expense for vassal — domain_handlers reads via
##            list_active_duties_for_assignment when computing expenses.
##   construction: ongoing — total expenditure target is recorded as
##            magnitude; v1 doesn't auto-expend (signal-only).
##   call_to_arms / call_to_council / charter_of_monopoly / office /
##   troops / grant_of_land:  signal-only (deferred to Phase 9/10/11).
##   revoke:  set most-recent-active obligation status='revoked'.
##
## Public API:
##   roll_monthly_loan_repayments(vassal_assignment_id, calendar_day, dice = null) -> Array
##     Per RAW L365: "monthly chance of repayment equals the adventurer's CHA
##     as a percentage; no interest." For each active loan owed to the lord
##     by this vassal, roll 1d100 vs the LORD's CHA%. On success, transfer
##     gp_value back vassal→lord and mark obligation status='completed'.
##     Returns array of repayment results.
##
##   roll_monthly(vassal_assignment_id, calendar_day, dice = null) -> Dictionary
##     Returns:
##       {success, vassal_assignment_id, roll, result_key, kind, type,
##        is_one_time, magnitude, gp_value, summary,
##        applied: bool,
##        loyalty_penalty_applied: int,   (cumulative -N if duty over threshold)
##        loyalty_outcome: String,        (set if a loyalty roll fired)
##        revolted: bool,
##        obligation_id: String}          (if a new obligation was created)
##
##   classify_roll(roll: int) -> Dictionary
##     {result_key: String, kind: String, type: String, is_one_time: bool}
##     for testability + UI preview.
##
##   office_bonus_for_vassal_roll(rolling_character_id) -> int
##     Returns +1 if the rolling character's liege holds an active "office"
##     favor (per RAW L369: "Office: vassal gains a ceremonial office;
##     grants +1 on loyalty rolls by the officeholder's own vassals"). Used
##     by every vassal-context HenchmanLoyaltyResolver call site.

const TABLE := [
	{"min":  1, "max":  1, "result_key": "construction",        "kind": "duty",  "type": "construction",        "is_one_time": false},
	{"min":  2, "max":  2, "result_key": "scutage",             "kind": "duty",  "type": "scutage",             "is_one_time": false},
	{"min":  3, "max":  4, "result_key": "call_to_council",     "kind": "duty",  "type": "call_to_council",     "is_one_time": false},
	{"min":  5, "max":  6, "result_key": "call_to_arms",        "kind": "duty",  "type": "call_to_arms",        "is_one_time": false},
	{"min":  7, "max":  8, "result_key": "loan",                "kind": "duty",  "type": "loan",                "is_one_time": false},
	{"min":  9, "max": 12, "result_key": "revoke",              "kind": "",      "type": "",                    "is_one_time": false},
	{"min": 13, "max": 14, "result_key": "charter_of_monopoly", "kind": "favor", "type": "charter_of_monopoly", "is_one_time": false},
	{"min": 15, "max": 16, "result_key": "gift",                "kind": "favor", "type": "gift",                "is_one_time": true},
	{"min": 17, "max": 18, "result_key": "office",              "kind": "favor", "type": "office",              "is_one_time": false},
	{"min": 19, "max": 19, "result_key": "troops",              "kind": "favor", "type": "troops",              "is_one_time": false},
	{"min": 20, "max": 20, "result_key": "grant_of_land",       "kind": "favor", "type": "grant_of_land",       "is_one_time": true},
]


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

static func classify_roll(roll: int) -> Dictionary:
	for entry in TABLE:
		if roll >= int(entry["min"]) and roll <= int(entry["max"]):
			return {
				"result_key": String(entry["result_key"]),
				"kind": String(entry["kind"]),
				"type": String(entry["type"]),
				"is_one_time": bool(entry["is_one_time"]),
			}
	return {"result_key": "construction", "kind": "duty", "type": "construction", "is_one_time": false}


static func roll_monthly(
	vassal_assignment_id: String,
	calendar_day: int,
	dice = null,
	scheduler = null
) -> Dictionary:
	## Phase 9C polish: scheduler param threaded through to CallToArmsMuster
	## so call_to_arms_tranche_arrival events actually schedule. Production
	## domain_handlers passes the runner's scheduler; tests pass null.
	if vassal_assignment_id.is_empty():
		return {"success": false, "error": "assignment_id_required"}
	var assignment: Dictionary = VassalRepository.get_assignment(vassal_assignment_id)
	if assignment.is_empty() or String(assignment.get("status", "")) != "active":
		return {"success": false, "error": "assignment_not_active"}

	var roll: int = _roll_d20(dice)
	var classification: Dictionary = classify_roll(roll)
	var result_key: String = String(classification["result_key"])

	var outcome: Dictionary
	match result_key:
		"revoke":
			outcome = _apply_revoke(assignment, roll, calendar_day, dice)
		_:
			outcome = _apply_obligation(assignment, classification, calendar_day, dice, scheduler)

	outcome["success"] = true
	outcome["vassal_assignment_id"] = vassal_assignment_id
	outcome["roll"] = roll
	outcome["result_key"] = result_key
	outcome["calendar_day"] = calendar_day

	if EventBus.has_signal("favor_or_duty_resolved"):
		EventBus.emit_signal("favor_or_duty_resolved",
			vassal_assignment_id, result_key, outcome)

	return outcome


# ---------------------------------------------------------------------------
# Obligation issuance (favors + duties)
# ---------------------------------------------------------------------------

static func _apply_obligation(
	assignment: Dictionary,
	classification: Dictionary,
	calendar_day: int,
	dice,
	scheduler = null
) -> Dictionary:
	var assn_id: String = String(assignment.get("id", ""))
	var kind: String = String(classification["kind"])
	var type: String = String(classification["type"])
	var is_one_time: bool = bool(classification["is_one_time"])

	# Compute magnitude / gp_value per RAW per type. Internal math stays in gp
	# to mirror RAW; conversion to cp happens at the column-write boundary
	# (Migration 116: vassal_obligations.cp_value).
	var sizing: Dictionary = _size_obligation(assignment, type, calendar_day)
	var magnitude: int = int(sizing.get("magnitude", 0))
	var gp_value: int = int(sizing.get("gp_value", 0))
	var cp_value: int = gp_value * 100

	# Duty-specific safe-threshold + cumulative loyalty roll per RAW L353-358.
	var loyalty_penalty: int = 0
	var loyalty_outcome: String = ""
	var revolted: bool = false
	if kind == "duty":
		var threshold: Dictionary = _compute_safe_duty_threshold(assignment, calendar_day)
		var safe_total: int = int(threshold["safe_total"])
		var existing_active: int = int(threshold["active_duty_count"])
		var prospective_count: int = existing_active + 1
		if prospective_count > safe_total:
			# This duty puts the vassal over the safe-total. Cumulative -1
			# per excess duty: the FIRST excess duty triggers a roll at -1
			# (the "additional duty after the duty that triggers a roll"
			# per RAW L356); subsequent excess duties at -2, -3, etc.
			var excess_index: int = prospective_count - safe_total  # 1, 2, 3, ...
			loyalty_penalty = -excess_index
			var loyalty_result: Dictionary = _run_loyalty_check(
				assignment, loyalty_penalty, dice)
			loyalty_outcome = String(loyalty_result.get("outcome", ""))
			if bool(loyalty_result.get("departs", false)):
				revolted = true
				VassalRepository.update_status(assn_id, "revolted", calendar_day)
				if EventBus.has_signal("vassal_revolted"):
					EventBus.emit_signal("vassal_revolted",
						assn_id,
						String(assignment.get("vassal_character_id", "")),
						String(assignment.get("liege_character_id", "")))

	# Persist the obligation. If revolted, we still record the obligation
	# (with status='active') for audit trail; the vassal_assignment is
	# revolted, so future monthly ticks won't roll on this assignment.
	# Phase 9C: call_to_arms defaults to magnitude_pct=50 (RAW minimum half
	# garrison). Future UI work may surface a slider for the lord to choose
	# 50%-100% with the ≥100% case adding the second-duty cost.
	var obligation_id: String = ""
	var call_to_arms_magnitude_pct: int = 50
	if not revolted or kind == "favor":
		obligation_id = VassalObligationsRepository.create({
			"vassal_assignment_id": assn_id,
			"kind": kind,
			"type": type,
			"magnitude": magnitude,
			"cp_value": cp_value,
			"is_one_time": is_one_time,
			"issued_calendar_day": calendar_day,
			"status": "completed" if is_one_time else "active",
			"loyalty_modifier_applied": loyalty_penalty,
			"magnitude_pct": call_to_arms_magnitude_pct if type == "call_to_arms" else 50,
		})

	# Phase 9C: call_to_arms triggers troop materialization + scheduler tranches.
	# CallToArmsMuster.issue_call returns a call_to_arms_state_id; the three
	# tranches arrive on the EventScheduler at +1/+2/+3 muster periods.
	var call_to_arms_state_id: String = ""
	if type == "call_to_arms" and not obligation_id.is_empty():
		call_to_arms_state_id = CallToArmsMuster.issue_call(
			obligation_id,
			String(assignment.get("liege_character_id", "")),
			String(assignment.get("vassal_character_id", "")),
			calendar_day,
			call_to_arms_magnitude_pct,
			scheduler  # Phase 9C polish: real scheduler from caller; null in tests.
		)

	# Mechanical effects. Treasury columns are cp (Migration 111), so pass cp.
	var applied: bool = _apply_mechanical_effect(
		assignment, type, magnitude, cp_value, calendar_day)

	# Tier 3 sweep 2026-05-19: removed the legacy "gp_value" key. UI consumers
	# now read cp_value directly via Currency.format_cost. The internal gp_value
	# local stays as the gp-native sizing-math intermediate.
	return {
		"kind": kind,
		"type": type,
		"is_one_time": is_one_time,
		"magnitude": magnitude,
		"cp_value": cp_value,
		"summary": _summary_for(type, magnitude, gp_value),
		"applied": applied,
		"loyalty_penalty_applied": loyalty_penalty,
		"loyalty_outcome": loyalty_outcome,
		"revolted": revolted,
		"obligation_id": obligation_id,
		"call_to_arms_state_id": call_to_arms_state_id,
	}


# ---------------------------------------------------------------------------
# Revoke handler (RAW L366: "9-12 Most recently granted favor or duty is
# revoked; if 1, revoke a favor; if 2-6, revoke a duty.")
# Project interpretation: sub-roll 1d6; on 1 revoke favor, on 2-6 revoke duty.
# ---------------------------------------------------------------------------

static func _apply_revoke(
	assignment: Dictionary,
	_d20_roll: int,
	calendar_day: int,
	dice
) -> Dictionary:
	var assn_id: String = String(assignment.get("id", ""))
	var sub_roll: int = _roll_d6(dice)
	var revoke_kind: String = "favor" if sub_roll == 1 else "duty"
	var most_recent: Dictionary = VassalObligationsRepository.most_recent_active(
		assn_id, revoke_kind)
	if most_recent.is_empty():
		# Nothing to revoke of that kind — RAW silent on this case;
		# treat as no-effect.
		return {
			"kind": "revoke",
			"type": "revoke_%s" % revoke_kind,
			"is_one_time": false,
			"magnitude": 0,
			"cp_value": 0,
			"summary": "Revoke %s rolled (sub-roll %d) but no active %s exists." % [revoke_kind, sub_roll, revoke_kind],
			"applied": true,
			"loyalty_penalty_applied": 0,
			"loyalty_outcome": "",
			"revolted": false,
			"obligation_id": "",
			"sub_roll": sub_roll,
		}
	var revoked_id: String = String(most_recent.get("id", ""))
	VassalObligationsRepository.set_status(revoked_id, "revoked", calendar_day)
	# Phase 9C: revoking a call_to_arms returns troops to the vassal's garrison.
	if String(most_recent.get("type", "")) == "call_to_arms":
		var revoked_call_id: String = _find_active_call_to_arms_for_obligation(revoked_id)
		if not revoked_call_id.is_empty():
			CallToArmsMuster.resolve_revocation(revoked_call_id, calendar_day)
	if EventBus.has_signal("obligation_revoked"):
		EventBus.emit_signal("obligation_revoked",
			revoked_id, revoke_kind, String(most_recent.get("type", "")))
	return {
		"kind": "revoke",
		"type": "revoke_%s" % revoke_kind,
		"is_one_time": false,
		"magnitude": 0,
		"cp_value": 0,
		"summary": "Revoked most recent %s: %s." % [
			revoke_kind, String(most_recent.get("type", ""))],
		"applied": true,
		"loyalty_penalty_applied": 0,
		"loyalty_outcome": "",
		"revolted": false,
		"obligation_id": revoked_id,
		"sub_roll": sub_roll,
	}


# ---------------------------------------------------------------------------
# Magnitude / gp_value sizing (per RAW per type)
# ---------------------------------------------------------------------------

static func _size_obligation(assignment: Dictionary, type: String, _calendar_day: int) -> Dictionary:
	var vassal_id: String = String(assignment.get("vassal_character_id", ""))
	var aggregate: Dictionary = RealmAggregator.aggregate(vassal_id)
	var realm_families: int = int(aggregate.get("all_realm_families", 0))
	match type:
		"construction":
			# RAW L361: 15000 gp per 6-mile hex in the realm. v1: count hexes
			# of the vassal's personal domain only (sub-vassal hexes belong
			# to those vassals' obligations).
			var hex_count: int = _count_hexes_for_character(vassal_id)
			return {"magnitude": 15000 * hex_count, "gp_value": 0}
		"scutage":
			# RAW L362: 1 gp per family in the realm per month.
			return {"magnitude": realm_families, "gp_value": 0}
		"call_to_arms":
			# RAW L364: muster troops with wages = 1 gp per family in the realm.
			return {"magnitude": realm_families, "gp_value": 0}
		"loan":
			# RAW L365: loan = 1 gp per family in the realm.
			return {"magnitude": realm_families, "gp_value": realm_families}
		"gift":
			# RAW L368: "at least 1gp per family in the vassal's realm".
			# v1: fixed at 1 gp/family (the "at least" can be policy-overridden later).
			return {"magnitude": realm_families, "gp_value": realm_families}
		"troops":
			# RAW L370: "garrison worth at least 1gp per family". Magnitude
			# is the wages the lord pays each month while the favor is active.
			return {"magnitude": realm_families, "gp_value": 0}
		"call_to_council", "charter_of_monopoly", "office", "grant_of_land":
			return {"magnitude": 0, "gp_value": 0}
		_:
			return {"magnitude": 0, "gp_value": 0}


# ---------------------------------------------------------------------------
# Mechanical effects (immediate state mutations)
# ---------------------------------------------------------------------------

static func _apply_mechanical_effect(
	assignment: Dictionary,
	type: String,
	_magnitude: int,
	cp_value: int,
	_calendar_day: int
) -> bool:
	match type:
		"gift":
			# Immediate transfer: lord domain treasury -cp, vassal +cp.
			# RAW L368 also says "increases the recipient's domain income for XP
			# purposes and decreases the grantor's" — XP accounting deferred
			# to v1.1 (would need a per-character XP-domain-income tracker).
			return _transfer_gp_lord_to_vassal(assignment, cp_value)
		"loan":
			# RAW L365: "Loan: lord demands a loan equal to 1gp per family in
			# the realm; the loan is repaid when revoked." VASSAL pays lord
			# at issue (loan flows TO the lord, not from). Repayment when
			# revoked is deferred (v1: signal-only on revoke).
			return _transfer_gp_vassal_to_lord(assignment, cp_value)
		_:
			# Other types are signal-only at issue; their ongoing effects are
			# read by domain_handlers monthly (e.g. scutage as expense).
			return true


# ---------------------------------------------------------------------------
# Safe-duty threshold (RAW L353-358 + L395 non-henchman)
# ---------------------------------------------------------------------------

static func _compute_safe_duty_threshold(assignment: Dictionary, calendar_day: int) -> Dictionary:
	var assn_id: String = String(assignment.get("id", ""))
	var is_henchman: bool = int(assignment.get("is_henchman_vassal", 1)) == 1
	var ongoing_favors: Array = VassalObligationsRepository.list_active_favors_for_assignment(assn_id)
	var ongoing_count: int = 0
	for f in ongoing_favors:
		if int(f.get("is_one_time", 0)) == 0:
			ongoing_count += 1
	var one_time_this_month: Array = VassalObligationsRepository.list_one_time_favors_issued_in_month(
		assn_id, calendar_day)
	var one_time_count: int = one_time_this_month.size()

	# Henchman: 1 free duty + 1 per ongoing favor + 1 per one-time favor this month.
	# Non-henchman per RAW L395: no free duty (1-per-favor only).
	var safe_total: int = ongoing_count + one_time_count
	if is_henchman:
		safe_total += 1

	var active_duties: Array = VassalObligationsRepository.list_active_duties_for_assignment(assn_id)
	return {
		"safe_total": safe_total,
		"ongoing_favor_count": ongoing_count,
		"one_time_favor_count": one_time_count,
		"active_duty_count": active_duties.size(),
		"is_henchman": is_henchman,
	}


# ---------------------------------------------------------------------------
# Loyalty check helper
# ---------------------------------------------------------------------------

static func _run_loyalty_check(assignment: Dictionary, penalty: int, dice) -> Dictionary:
	var base_mod: int = int(assignment.get("base_loyalty_modifier", 0))
	var combined_mod: int = base_mod + penalty
	# Office bonus: if the rolling vassal's liege holds an active "office"
	# favor, the rolling vassal gets +1 to loyalty rolls per RAW L369.
	var rolling_character_id: String = String(assignment.get("vassal_character_id", ""))
	combined_mod += office_bonus_for_vassal_roll(rolling_character_id)
	# Consecrate Ruler buff propagation (Phase 10A.2 / bucket-A item #94):
	# if the LIEGE's domain has an active consecrate_ruler_buff, the buff's
	# vassal_loyalty_bonus (+1 success / -1 natural-1 failure) applies to
	# this loyalty roll. Wired 2026-05-19.
	combined_mod += consecrate_ruler_vassal_loyalty_bonus_for_assignment(assignment)
	return HenchmanLoyaltyResolver.resolve_loyalty_check(combined_mod, false, false, dice)


# ---------------------------------------------------------------------------
# Consecrate Ruler buff propagation (Phase 10A.2 / bucket-A item #94)
# ---------------------------------------------------------------------------

## Returns the vassal_loyalty_bonus contributed by an active
## consecrate_ruler_buff on the assignment's liege's primary domain.
## Returns 0 when no active buff exists.
static func consecrate_ruler_vassal_loyalty_bonus_for_assignment(assignment: Dictionary) -> int:
	var liege_id: String = String(assignment.get("liege_character_id", ""))
	if liege_id.is_empty():
		return 0
	var liege_domain: Dictionary = _primary_domain_for_character(liege_id)
	if liege_domain.is_empty():
		return 0
	var domain_id: String = String(liege_domain.get("id", ""))
	if domain_id.is_empty():
		return 0
	var payload: Dictionary = _active_consecrate_ruler_payload(domain_id)
	if payload.is_empty():
		return 0
	return int(payload.get("vassal_loyalty_bonus", 0))


## Reads the active consecrate_ruler_buff payload for a domain, if any.
## Returns the parsed JSON payload or {} when no active buff exists.
## "Active" = status='applied' AND expires_at_calendar_day > current_day.
static func _active_consecrate_ruler_payload(domain_id: String) -> Dictionary:
	if domain_id.is_empty():
		return {}
	var current_day: int = _current_calendar_day()
	if not CampaignRepository.db.query_with_bindings("""
		SELECT effect_payload_json FROM pending_divine_effects
		WHERE domain_id = ?
		  AND effect_kind = 'consecrate_ruler_buff'
		  AND status = 'applied'
		  AND expires_at_calendar_day > ?
		ORDER BY applies_at_calendar_day DESC
		LIMIT 1
	""", [domain_id, current_day]):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	var raw: String = String(CampaignRepository.db.query_result[0].get("effect_payload_json", "{}"))
	var parsed: Variant = JSON.parse_string(raw)
	return parsed if parsed is Dictionary else {}


static func _current_calendar_day() -> int:
	if not Engine.has_singleton("Timekeeping"):
		return 0
	return Timekeeping.get_total_days()


# ---------------------------------------------------------------------------
# Loan repayment monthly tick (Phase 8 polish — RAW L365)
# ---------------------------------------------------------------------------

## Per RAW L365: "monthly chance of repayment equals the adventurer's CHA as
## a percentage; no interest." For each active loan owed to the lord by
## this vassal, roll 1d100 vs the LORD's CHA% (RAW says "the adventurer's
## CHA"; project interpretation: the lord-character's raw CHA). On success,
## transfer gp_value back vassal→lord and mark the loan obligation
## status='completed'.
##
## Returns Array of per-loan results:
##   {obligation_id, loan_gp, roll, cha_pct, repaid: bool, summary}
static func roll_monthly_loan_repayments(
	vassal_assignment_id: String,
	calendar_day: int,
	dice = null
) -> Array:
	var results: Array = []
	if vassal_assignment_id.is_empty():
		return results
	var assignment: Dictionary = VassalRepository.get_assignment(vassal_assignment_id)
	if assignment.is_empty() or String(assignment.get("status", "")) != "active":
		return results
	# Find all active loan obligations on this assignment.
	var duties: Array = VassalObligationsRepository.list_active_duties_for_assignment(vassal_assignment_id)
	var loan_obligations: Array = []
	for d in duties:
		if String(d.get("type", "")) == "loan":
			loan_obligations.append(d)
	if loan_obligations.is_empty():
		return results
	# Lord's CHA from the characters table.
	var liege_id: String = String(assignment.get("liege_character_id", ""))
	var lord_cha: int = _get_character_cha(liege_id)
	for loan in loan_obligations:
		var roll: int = _roll_d100(dice)
		var repaid: bool = roll <= lord_cha
		# Migration 116: vassal_obligations column is cp_value (gp × 100).
		var loan_cp: int = int(loan.get("cp_value", 0))
		var loan_gp: int = loan_cp / 100
		var obligation_id: String = String(loan.get("id", ""))
		if repaid:
			# Transfer cp_value back vassal → lord and complete the obligation.
			# Note: at issue the loan flowed VASSAL → LORD (lord demanded loan).
			# At repayment, the LORD returns the principal to the VASSAL... wait,
			# RAW L365: "the loan is repaid when revoked" — repayment means
			# vassal gets their money back. Actually re-reading: the loan was
			# FROM vassal TO lord. Repaying the loan means lord gives money
			# back to vassal. But the rule says "monthly chance of repayment
			# equals the adventurer's CHA as a percentage" — the adventurer
			# being the LORD who took the loan. So lord's CHA% = chance lord
			# pays vassal back.
			_transfer_gp_lord_to_vassal(assignment, loan_cp)
			VassalObligationsRepository.set_status(obligation_id, "completed", calendar_day)
			if EventBus.has_signal("obligation_revoked"):
				EventBus.emit_signal("obligation_revoked",
					obligation_id, "duty", "loan")
		results.append({
			"obligation_id": obligation_id,
			"loan_gp": loan_gp,
			"loan_cp": loan_cp,
			"roll": roll,
			"cha_pct": lord_cha,
			"repaid": repaid,
			"summary": ("Loan repaid (1d100=%d ≤ CHA%%=%d)." if repaid else "Loan still outstanding (1d100=%d > CHA%%=%d).") % [roll, lord_cha],
		})
	return results


# ---------------------------------------------------------------------------
# Construction auto-expenditure (Phase 8 polish — RAW L361)
# ---------------------------------------------------------------------------

## Per RAW L361: "vassal constructs infrastructure in the realm, expending
## gp each month equal to monthly tribute; duty ends after total expenditure
## of 15000gp per 6-mile hex in the realm."
##
## For each active construction duty on this vassal_assignment:
##   1. Determine this month's tribute amount (TributeCalculator on the
##      vassal's realm size).
##   2. Increment the obligation's running gp_value by the tribute amount,
##      AND deduct that amount from the vassal's domain treasury.
##   3. If running gp_value ≥ magnitude (15000 × hex_count), mark
##      status='completed'.
##
## Returns Array of per-construction-obligation results:
##   {obligation_id, monthly_expenditure, total_expended, target, completed}
static func roll_monthly_construction_expenditure(
	vassal_assignment_id: String,
	calendar_day: int
) -> Array:
	var results: Array = []
	if vassal_assignment_id.is_empty():
		return results
	var assignment: Dictionary = VassalRepository.get_assignment(vassal_assignment_id)
	if assignment.is_empty() or String(assignment.get("status", "")) != "active":
		return results
	var duties: Array = VassalObligationsRepository.list_active_duties_for_assignment(vassal_assignment_id)
	var construction_obligations: Array = []
	for d in duties:
		if String(d.get("type", "")) == "construction":
			construction_obligations.append(d)
	if construction_obligations.is_empty():
		return results
	# Compute monthly tribute for this vassal's realm (= the per-month rate
	# the vassal owes their liege under normal conditions; per RAW the
	# construction expenditure equals "monthly tribute").
	var vassal_id: String = String(assignment.get("vassal_character_id", ""))
	var aggregate: Dictionary = RealmAggregator.aggregate(vassal_id)
	var monthly_tribute: int = TributeCalculator.compute_tribute_base_gp(
		int(aggregate.get("all_realm_families", 0)))
	if monthly_tribute <= 0:
		return results
	# Vassal's primary domain — to deduct treasury.
	# Migration 116: vassal_obligations column is cp_value; the running total
	# tracked here is in cp. monthly_tribute is gp from TributeCalculator.
	var monthly_tribute_cp: int = monthly_tribute * 100
	var vassal_dom: Dictionary = _primary_domain_for_character(vassal_id)
	for obligation in construction_obligations:
		var obligation_id: String = String(obligation.get("id", ""))
		var prior_total_cp: int = int(obligation.get("cp_value", 0))
		var target: int = int(obligation.get("magnitude", 0))
		# magnitude is in gp (RAW 15000 × hex_count); compare against cp running total.
		var target_cp: int = target * 100
		var new_total_cp: int = prior_total_cp + monthly_tribute_cp
		var completed: bool = (target_cp > 0 and new_total_cp >= target_cp)
		# Deduct from vassal treasury (also cp).
		if not vassal_dom.is_empty():
			var prior_treasury: int = int(vassal_dom.get("treasury_cp", 0))
			CampaignRepository.update_domain_monthly_state(
				String(vassal_dom.get("id", "")),
				{"treasury_cp": prior_treasury - monthly_tribute_cp}
			)
			# Refresh local cache for the next iteration.
			vassal_dom["treasury_cp"] = prior_treasury - monthly_tribute_cp
		# Persist running total + status if completed.
		var update_fields: Dictionary = {"cp_value": new_total_cp}
		VassalObligationsRepository.update(obligation_id, update_fields)
		if completed:
			VassalObligationsRepository.set_status(obligation_id, "completed", calendar_day)
			if EventBus.has_signal("obligation_revoked"):
				EventBus.emit_signal("obligation_revoked",
					obligation_id, "duty", "construction")
		results.append({
			"obligation_id": obligation_id,
			"monthly_expenditure": monthly_tribute,
			"total_expended": new_total_cp / 100,  # gp for caller display
			"total_expended_cp": new_total_cp,
			"target": target,
			"completed": completed,
		})
	return results


# ---------------------------------------------------------------------------
# Helper: get character's CHA score from characters table.
# ---------------------------------------------------------------------------

static func _get_character_cha(character_id: String) -> int:
	if character_id.is_empty():
		return 10
	if not CampaignRepository.db.query_with_bindings(
		"SELECT charisma FROM characters WHERE id = ?", [character_id]):
		return 10
	if CampaignRepository.db.query_result.is_empty():
		return 10
	return int(CampaignRepository.db.query_result[0].get("charisma", 10))


static func _roll_d100(dice) -> int:
	if dice != null and dice.has_method("roll"):
		return int(dice.roll(1, 100))
	return randi_range(1, 100)


# ---------------------------------------------------------------------------
# Office bonus propagation (Phase 8 polish)
# ---------------------------------------------------------------------------

static func office_bonus_for_vassal_roll(rolling_character_id: String) -> int:
	## Per RAW §favors_and_duties L369: "Office: vassal gains a ceremonial
	## office; grants +1 on loyalty rolls by the officeholder's own vassals."
	## Implementation: find the rolling character's liege, then check if the
	## liege holds an active "office" favor (granted to the liege from THEIR
	## own upper-liege).
	if rolling_character_id.is_empty():
		return 0
	# 1. Find the rolling character's vassal_assignment as VASSAL.
	var v_assn: Dictionary = VassalRepository.get_active_assignment_for_vassal(rolling_character_id)
	if v_assn.is_empty():
		return 0
	var liege_id: String = String(v_assn.get("liege_character_id", ""))
	if liege_id.is_empty():
		return 0
	# 2. Find LIEGE's vassal_assignment as vassal — which carries the favors
	#    granted to the liege from their upper-liege.
	var l_assn: Dictionary = VassalRepository.get_active_assignment_for_vassal(liege_id)
	if l_assn.is_empty():
		return 0
	# 3. Check if the liege holds any active "office" favor.
	var favors: Array = VassalObligationsRepository.list_active_favors_for_assignment(
		String(l_assn.get("id", "")))
	for f in favors:
		if String(f.get("type", "")) == "office":
			return 1
	return 0


# ---------------------------------------------------------------------------
# Treasury transfers
# ---------------------------------------------------------------------------

static func _transfer_gp_lord_to_vassal(assignment: Dictionary, cp_value: int) -> bool:
	if cp_value <= 0:
		return true
	var liege_id: String = String(assignment.get("liege_character_id", ""))
	var vassal_id: String = String(assignment.get("vassal_character_id", ""))
	var liege_domain: Dictionary = _primary_domain_for_character(liege_id)
	var vassal_domain: Dictionary = _primary_domain_for_character(vassal_id)
	if liege_domain.is_empty() or vassal_domain.is_empty():
		return false
	var liege_cp: int = int(liege_domain.get("treasury_cp", 0))
	var vassal_cp: int = int(vassal_domain.get("treasury_cp", 0))
	# v1 simplification: allow negative lord treasury (lord still owes the gift even if
	# they can't pay this month). Phase 8 polish: gate behind affordability check.
	CampaignRepository.update_domain_monthly_state(String(liege_domain.get("id", "")), {
		"treasury_cp": liege_cp - cp_value,
	})
	CampaignRepository.update_domain_monthly_state(String(vassal_domain.get("id", "")), {
		"treasury_cp": vassal_cp + cp_value,
	})
	return true


static func _transfer_gp_vassal_to_lord(assignment: Dictionary, cp_value: int) -> bool:
	if cp_value <= 0:
		return true
	var liege_id: String = String(assignment.get("liege_character_id", ""))
	var vassal_id: String = String(assignment.get("vassal_character_id", ""))
	var liege_domain: Dictionary = _primary_domain_for_character(liege_id)
	var vassal_domain: Dictionary = _primary_domain_for_character(vassal_id)
	if liege_domain.is_empty() or vassal_domain.is_empty():
		return false
	var liege_cp: int = int(liege_domain.get("treasury_cp", 0))
	var vassal_cp: int = int(vassal_domain.get("treasury_cp", 0))
	CampaignRepository.update_domain_monthly_state(String(liege_domain.get("id", "")), {
		"treasury_cp": liege_cp + cp_value,
	})
	CampaignRepository.update_domain_monthly_state(String(vassal_domain.get("id", "")), {
		"treasury_cp": vassal_cp - cp_value,
	})
	return true


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _primary_domain_for_character(character_id: String) -> Dictionary:
	if character_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings("""
		SELECT * FROM domains WHERE owner_character_id = ?
		ORDER BY created_at LIMIT 1
	""", [character_id]):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func _count_hexes_for_character(character_id: String) -> int:
	if character_id.is_empty():
		return 0
	if not CampaignRepository.db.query_with_bindings("""
		SELECT COUNT(*) AS cnt FROM domain_hexes dh
		JOIN domains d ON d.id = dh.domain_id
		WHERE d.owner_character_id = ?
	""", [character_id]):
		return 0
	if CampaignRepository.db.query_result.is_empty():
		return 0
	return int(CampaignRepository.db.query_result[0].get("cnt", 0))


static func _summary_for(type: String, magnitude: int, gp_value: int) -> String:
	match type:
		"construction":
			return "Construction duty: total expenditure target %d gp." % magnitude
		"scutage":
			return "Scutage duty: %d gp/month in lieu of military service." % magnitude
		"call_to_council":
			return "Call to Council: vassal must travel to lord's domain until revoked."
		"call_to_arms":
			return "Call to Arms: muster %d gp/month of wages." % magnitude
		"loan":
			return "Loan: vassal pays lord %d gp now (repaid when duty revoked)." % gp_value
		"charter_of_monopoly":
			return "Charter of Monopoly granted: ongoing favor."
		"gift":
			return "Gift: lord transfers %d gp to vassal." % gp_value
		"office":
			return "Office: ongoing favor; +1 to officeholder's vassals' loyalty rolls."
		"troops":
			return "Troops: lord sends garrison worth %d gp/month." % magnitude
		"grant_of_land":
			return "Grant of Land: vassal receives a new domain (manual setup)."
		_:
			return "Favor or duty resolved."


static func _find_active_call_to_arms_for_obligation(obligation_id: String) -> String:
	## Phase 9C: locate the active call_to_arms_state for an obligation.
	if obligation_id.is_empty():
		return ""
	if not CampaignRepository.db.query_with_bindings("""
		SELECT id FROM call_to_arms_state
		WHERE obligation_id = ? AND revoked_calendar_day = 0
		LIMIT 1
	""", [obligation_id]):
		return ""
	if CampaignRepository.db.query_result.is_empty():
		return ""
	return String(CampaignRepository.db.query_result[0].get("id", ""))


static func _roll_d20(dice) -> int:
	if dice != null and dice.has_method("roll"):
		return int(dice.roll(1, 20))
	return randi_range(1, 20)


static func _roll_d6(dice) -> int:
	if dice != null and dice.has_method("roll"):
		return int(dice.roll(1, 6))
	return randi_range(1, 6)
