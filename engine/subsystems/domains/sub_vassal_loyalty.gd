class_name SubVassalLoyalty
extends RefCounted

## R-5 — when a domain changes hands, the vassals who hold their fiefs OF it get
## a new lord, and each decides whether he will serve the man who took his lord's
## place (Jedidiah ruling 2026-07-31).
##
## THE ROLL IS RAW'S, NOT A NEW ONE. `VassalLoyaltyResolver.roll_for_trigger`
## already performs the RAW §2.2 henchman-loyalty check plus the project's §5.2
## modifier stack, and its `project_modifier_breakdown` reads the liege straight
## off the assignment dictionary. So the mechanism here is a SWAPPED-LIEGE PROBE:
## copy the edge, put the NEW lord in it, and roll. Alignment, culture, religion,
## relative strength and grievance all re-evaluate against the new man for free.
##
## ⚠ THE ONE BUG TO AVOID. Do NOT add an alignment term to `extra_modifiers`.
## `project_modifier_breakdown(assignment)["alignment"]` ALREADY applies Jedidiah's
## "−1 per step of alignment difference" (`VassalLoyaltyResolver._alignment_mod`:
## same +1, one step −1, opposed −2). Adding it again double-counts it, and the
## double is invisible in the total. `alignment_steps()` below exists for
## REPORTING AND PREVIEW ONLY and is never summed into a roll.
##
## ACQUISITION METHOD IS A PARAMETER, NOT A COLUMN. Jedidiah's ruling gives
## conquest a −2 penalty, so the roll must know how the new lord came by the
## domain. That must NOT be stored on `domains.establishment_method`: that column
## is written once at founding, its enum is founding-specific, and it is
## LOAD-BEARING for the beastman-eligibility gate — `LifecycleHandler._conquest_eligible`
## and `DomainMoraleResolver` both infer a beastman population from it, so
## overwriting it on conquest would silently flip who is allowed to rule. The mode
## is statically known at every transfer site, so a parameter can never go stale.
##
## DEPTH: DIRECT sub-vassals only (Jedidiah ruling). A sub-vassal's own vassals
## still answer to him; his oath to the new overlord is his affair, not theirs.
##
## Public API:
##   roll_for_transfer(domain_id, prior_owner_id, new_owner_id, method, day, dice) -> Array
##   preview_modifier(sub_vassal_domain_id, new_owner_id, method) -> Dictionary
##   acquisition_penalty(method) -> int
##   alignment_steps(a, b) -> int

# --- Acquisition modes. Defined HERE, deliberately NOT in
#     `EstablishDomainFlow.VALID_METHODS` — that constant is the CHECK domain of
#     the `establishment_method` column and means "how this domain was founded",
#     a different question from "how this lord came by it".
const ACQ_CONQUEST := "conquest"
const ACQ_GRANT := "grant"
const ACQ_PURCHASE := "purchase"
const ACQ_INHERITANCE := "inheritance"
const ACQ_ABDICATION := "abdication"

## Jedidiah ruling 2026-07-31: a lord who took the domain by force starts at −2
## with the vassals he inherited. Grant, purchase, inheritance and abdication
## carry no penalty of their own — the alignment and §5.2 rows still apply.
const CONQUEST_LOYALTY_PENALTY := -2

const TRIGGER_NEW_LIEGE := "new_liege"


## The loyalty penalty attaching to how the new lord acquired the domain.
static func acquisition_penalty(method: String) -> int:
	return CONQUEST_LOYALTY_PENALTY if method == ACQ_CONQUEST else 0


## Steps of alignment difference: 0 same, 1 adjacent, 2 opposed (lawful↔chaotic).
##
## REPORTING AND PREVIEW ONLY — never summed into a roll. The roll's alignment
## term comes from `VassalLoyaltyResolver._alignment_mod` via
## `project_modifier_breakdown`; adding this on top would double it.
static func alignment_steps(a: String, b: String) -> int:
	var aa: String = a if a != "" else "neutral"
	var bb: String = b if b != "" else "neutral"
	if aa == bb:
		return 0
	if (aa == "lawful" and bb == "chaotic") or (aa == "chaotic" and bb == "lawful"):
		return 2
	return 1


## Roll every DIRECT sub-vassal of [param domain_id] against its new lord.
##
## Call this BEFORE emitting `domain_conquered`. The order matters: this re-points
## (or breaks) the transferred domain's sub-vassal edges, so by the time
## `VassalLoyaltyTriggers._on_domain_conquered` fires the prior owner's "my lord
## lost a stronghold" roll, those vassals are no longer his and cannot roll twice
## for one conquest.
##
## Returns one report per sub-vassal:
##   {sub_vassal_domain_id, vassal_character_id, outcome, behavior, result, roll}
## where `result` is "retained", "resignation_seeking", "revolted" or "skipped".
static func roll_for_transfer(
	domain_id: String,
	_prior_owner_id: String,   # retained for call-site clarity + future logging
	new_owner_id: String,
	acquisition_method: String,
	calendar_day: int,
	dice = null,
) -> Array:
	var reports: Array = []
	if domain_id.is_empty() or new_owner_id.is_empty():
		return reports
	var roll_dice = dice
	if roll_dice == null:
		# Deterministic per (domain, day, method) so a replay reproduces the same
		# transfer history, matching VassalLoyaltyTriggers' seeding discipline.
		roll_dice = SeededDice.for_monthly(
			domain_id, calendar_day, "sub_vassal_transfer_" + acquisition_method)

	var penalty: int = acquisition_penalty(acquisition_method)

	# PRE-PASS, before a single write. `_probe_for` resolves the new lord's range of
	# trade through `RealmAggregator.aggregate`, which folds in the settlements of
	# his CURRENTLY active vassals — so building the probes lazily inside the loop
	# below would let each sub-vassal re-pointed early enlarge the new lord's realm
	# for the ones rolled after him, making the RAW L394 −2/−4 depend on row order.
	# Measuring every probe against the pre-transfer state makes it order-free.
	var plan: Array = []
	for sub_domain_id in RealmGraph.direct_vassal_domains(domain_id):
		var assignment: Dictionary = _active_assignment_for_domain(String(sub_domain_id))
		if assignment.is_empty():
			continue
		plan.append({
			"sub_domain_id": String(sub_domain_id),
			"assignment": assignment,
			"probe": _probe_for(assignment, String(sub_domain_id), new_owner_id),
		})

	for step: Dictionary in plan:
		var sub_domain_id: String = String(step["sub_domain_id"])
		var assignment: Dictionary = step["assignment"]
		var vassal_character_id: String = String(assignment.get("vassal_character_id", ""))
		var report: Dictionary = {
			"sub_vassal_domain_id": sub_domain_id,
			"vassal_character_id": vassal_character_id,
			"result": "skipped",
		}
		# The new lord cannot be his own vassal. This is the ordinary dynastic case,
		# not an edge case: a landed henchman who inherits his lord's seat now holds
		# his own fief OF a domain he owns. End the oath AND clear the pointer —
		# both records move together (§135), or the fief is left permanently held of
		# itself, with no active edge and a liege it cannot be released from.
		if vassal_character_id == new_owner_id or vassal_character_id.is_empty():
			VassalRepository.update_status(
				String(assignment.get("id", "")), "departed", calendar_day)
			_clear_liege_pointer(sub_domain_id)
			report["result"] = "absorbed_by_new_lord"
			reports.append(report)
			continue

		var probe: Dictionary = step["probe"]
		var extra: Dictionary = {}
		if penalty != 0:
			extra["acquired_by_" + acquisition_method] = penalty
		var roll: Dictionary = VassalLoyaltyResolver.roll_for_trigger(
			probe, TRIGGER_NEW_LIEGE, calendar_day, roll_dice, extra)
		if not bool(roll.get("ok", false)):
			reports.append(report)
			continue
		report["outcome"] = String(roll.get("outcome", ""))
		report["behavior"] = String(roll.get("behavior", ""))
		report["roll"] = roll
		report["result"] = _apply_outcome(
			assignment, probe, String(roll.get("behavior", "")),
			new_owner_id, sub_domain_id, calendar_day)
		reports.append(report)
	return reports


## Both records move together (§135): a fief with no active oath must not keep
## pointing at a liege domain, or nothing can ever reach it again.
static func _clear_liege_pointer(sub_vassal_domain_id: String) -> void:
	if sub_vassal_domain_id.is_empty():
		return
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET liege_domain_id = NULL, updated_at = datetime('now') WHERE id = ?",
		[sub_vassal_domain_id])


## Move the DIRECT sub-vassal edges onto a new lord WITHOUT rolling.
##
## For succession. `_apply_heir` must re-point the edges — until it does, they name
## a DEAD ruler as liege — but it must NOT roll, because `resolve_succession` then
## emits `succession_resolved`, and `VassalLoyaltyTriggers._on_succession_resolved`
## already fires RAW §5.2's "liege succession" check over
## `list_active_for_liege(heir)`. Rolling here as well would roll the same vassal
## TWICE for one death, and the second roll would consume the one-shot RAW Grudging
## −1 carryover that the first had just written for the NEXT check.
##
## The conquest path does not have this problem and DOES roll here: its trigger
## (`_on_domain_conquered`) fires over the PRIOR owner, off whom these vassals have
## just moved, so they are no longer in that list. Succession's trigger fires over
## the NEW owner — the very lord this function hands them to.
##
## Re-pointing here is what makes that existing trigger work at all: before R-5 the
## inherited edges still named the dead ruler, so the heir's active list was empty
## and the §5.2 succession check rolled over nothing.
static func repoint_direct_sub_vassals(
	domain_id: String, new_owner_id: String, calendar_day: int) -> Array:
	var moved: Array = []
	if domain_id.is_empty() or new_owner_id.is_empty():
		return moved
	for sub_domain_id in RealmGraph.direct_vassal_domains(domain_id):
		var assignment: Dictionary = _active_assignment_for_domain(String(sub_domain_id))
		if assignment.is_empty():
			continue
		var assn_id: String = String(assignment.get("id", ""))
		if String(assignment.get("vassal_character_id", "")) == new_owner_id:
			# The heir already held this fief himself — he cannot be his own vassal.
			# Clear the pointer too (§135), or it is held of a domain he now owns.
			VassalRepository.update_status(assn_id, "departed", calendar_day)
			_clear_liege_pointer(String(sub_domain_id))
			continue
		if VassalRepository.repoint_liege(assn_id, new_owner_id, calendar_day):
			moved.append(assn_id)
		else:
			# Collision: he already served the heir through another fief, so the
			# edge was departed rather than moved. Do not strand the pointer.
			_clear_liege_pointer(String(sub_domain_id))
	return moved


## What the transfer WOULD do, without dice and without writes — the pre-commit
## warning surface `VassalAppointmentWarnings` was built for and never given.
## Returns {modifier_total, breakdown, acquisition_penalty, alignment_steps,
##          base_modifier}.
static func preview_modifier(
	sub_vassal_domain_id: String,
	new_owner_id: String,
	acquisition_method: String,
) -> Dictionary:
	var out: Dictionary = {
		"modifier_total": 0, "breakdown": {}, "acquisition_penalty": 0,
		"alignment_steps": 0, "base_modifier": 0,
	}
	var assignment: Dictionary = _active_assignment_for_domain(sub_vassal_domain_id)
	if assignment.is_empty() or new_owner_id.is_empty():
		return out
	var probe: Dictionary = _probe_for(assignment, sub_vassal_domain_id, new_owner_id)
	var breakdown: Dictionary = VassalLoyaltyResolver.project_modifier_breakdown(probe)
	var project_total: int = 0
	for k in breakdown:
		project_total += int(breakdown[k])
	var penalty: int = acquisition_penalty(acquisition_method)
	var base_mod: int = int(probe.get("base_loyalty_modifier", 0))
	var new_owner: Dictionary = CampaignRepository.get_character(new_owner_id)
	var vassal: Dictionary = CampaignRepository.get_character(
		String(assignment.get("vassal_character_id", "")))
	out["breakdown"] = breakdown
	out["acquisition_penalty"] = penalty
	out["base_modifier"] = base_mod
	out["alignment_steps"] = alignment_steps(
		String(new_owner.get("alignment", "neutral")), String(vassal.get("alignment", "neutral")))
	out["modifier_total"] = project_total + penalty + base_mod
	return out


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

## The swapped-liege probe: this edge as it WOULD be under the new lord.
##
## `base_loyalty_modifier` is recomputed for a non-henchman vassal because RAW
## §non_henchman_vassals L393-394 measures it against the LIEGE's largest urban
## settlement — a new lord means a new range of trade, so the stored −2/−4 belongs
## to the old lord and would be wrong for the new one. Henchman vassals keep their
## stored base (RAW gives them 0 regardless of geography).
static func _probe_for(
	assignment: Dictionary, sub_vassal_domain_id: String, new_owner_id: String) -> Dictionary:
	var probe: Dictionary = assignment.duplicate()
	probe["liege_character_id"] = new_owner_id
	if int(assignment.get("is_henchman_vassal", 1)) == 0:
		probe["base_loyalty_modifier"] = TradeRangeResolver.compute_non_henchman_base_loyalty(
			sub_vassal_domain_id, new_owner_id)
	return probe


## Map the §5.3 compliance band onto what actually happens to the edge.
##
## The bands come from RAW's loyalty table (`acore_equipment.xml:795-809`), but RAW
## says nothing about what a LAND-HOLDING vassal does when he "leaves" — so the
## three exit-shaped outcomes route through the project's existing §5.3 ladder
## rather than inventing a fourth vocabulary. `roll_for_trigger` has already
## written the compliance tag and the RAW dice-carryover flags; this only decides
## the edge's fate.
static func _apply_outcome(
	assignment: Dictionary,
	probe: Dictionary,
	behavior: String,
	new_owner_id: String,
	sub_vassal_domain_id: String,
	calendar_day: int,
) -> String:
	var assn_id: String = String(assignment.get("id", ""))
	if behavior == VassalLoyaltyResolver.BEHAVIOR_REBELLIOUS:
		# 2− Hostility: he breaks away outright. RAW makes him "a rival/enemy", so
		# the edge ends and the domain leaves the realm tree — both records, per
		# conventions §135, or the cascade could never reach the stale one.
		VassalRepository.update_status(assn_id, "revolted", calendar_day)
		_clear_liege_pointer(sub_vassal_domain_id)
		if EventBus.has_signal("vassal_revolted"):
			EventBus.vassal_revolted.emit(
				assn_id, String(assignment.get("vassal_character_id", "")), new_owner_id)
		VassalLoyaltyTriggers.route_compliance(probe, behavior, calendar_day)
		return "revolted"
	# Everything else STAYS — including Resignation, which seeks a LAWFUL exit and
	# is still bound while the petition is open (§5.3 gives it a 0.5 muster scalar).
	# Re-point rather than depart-and-remint so the loyalty history survives.
	if not VassalRepository.repoint_liege(assn_id, new_owner_id, calendar_day):
		# The partial unique index refused it: this vassal ALREADY held an active
		# oath to the new lord through another fief, so `repoint_liege` departed
		# this one instead. Reporting that as "retained" would be a lie, and
		# leaving the pointer set would strand the fief under a lord it has no
		# edge to.
		_clear_liege_pointer(sub_vassal_domain_id)
		return "absorbed_by_new_lord"
	# RAW L393-394 measures a non-henchman's base loyalty against the LIEGE's
	# largest urban settlement, so the stored −2/−4 belonged to the departing lord.
	# The probe recomputed it for the roll; persist it, or every FUTURE roll on this
	# edge would keep measuring against a lord who no longer holds the domain.
	if int(assignment.get("is_henchman_vassal", 1)) == 0:
		var new_base: int = int(probe.get("base_loyalty_modifier", 0))
		if new_base != int(assignment.get("base_loyalty_modifier", 0)):
			VassalRepository.update(assn_id, {"base_loyalty_modifier": new_base})
	if behavior == VassalLoyaltyResolver.BEHAVIOR_RESIGNATION:
		VassalLoyaltyTriggers.route_compliance(probe, behavior, calendar_day)
		return "resignation_seeking"
	return "retained"


static func _active_assignment_for_domain(domain_id: String) -> Dictionary:
	if domain_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings("""
		SELECT * FROM vassal_assignments
		WHERE vassal_domain_id = ? AND status = 'active' LIMIT 1
	""", [domain_id]) or CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()
