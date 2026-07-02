class_name RulerAI
extends RefCounted

## The NPC ruler behavior planner's monthly decide→execute loop —
## gdd-ruler-ai.md §6.1, run inside the existing monthly cadence (§3.2) and
## mirroring the NpcSyndicateMonthlyResolver batch pattern: stateless static,
## processes every active-set ruler, no UI interrupt, no auto_pause, no LLM.
##
## Per active ruler, ONE turn on their PERSONAL domain — RAW: a ruler
## directly manages one personal domain; all others go to vassals
## (acore_axioms_strongholds_and_domains.xml:265-272). The personal domain is
## resolved with the SAME deterministic query every activity handler uses
## (owner_character_id, ORDER BY created_at, id, LIMIT 1), so the domain the
## planner scores is provably the domain the dispatched handlers act on.
##   1. candidates = RulerActionCatalog.available_for(...)   # §5, gated
##   2. utility = base x weight x §6.2 modifiers              # RulerActionScorer
##   3. (crisis_response bias — Phase 3)
##   4. top-N by realm scale (§6.1 step 4), distinct candidates
##   5. execute deterministically via the mapped handler — no LLM
##   6. emit EventBus.ruler_action_taken (RulerActionNarrator narrates it
##      retroactively when the player observes the outcome — §9.1)
##
## Dispatch is the §5 contract: `state.character_id = ruler_npc_id`, params as
## params_json; handlers resolve owner_character_id -> domain themselves.
## `hold` executes as a no-op by design (§5.2 — no handler); `withstand_siege`
## is recorded but not dispatched until the Phase-3 siege path.
##
## LOD: the ACTIVE SET is a caller-supplied Array of ruler character_ids.
## Phase 3's RulerLodManager computes the real §8.1 set (6-mile window +
## 10-hex buffer, full-tier-gated); until then provisional_active_set()
## offers the full-tier-NPC-ruler approximation. Backdrop rulers are simply
## absent from the set — their domains get RulerBackdropStabilizer instead.

## Actions the planner records but must not dispatch (no handler yet / ever).
const _NO_DISPATCH := ["hold", "withstand_siege"]


## Decide + execute for every active-set NPC ruler. [param active_set] is an
## Array of ruler character_ids; [param domain_results] optionally carries the
## tick's per-domain result dicts (keyed lookup by domain_id) so threat
## context comes from THIS month's resolution (§3.2). Returns an Array of
## per-ruler-per-domain reports.
static func process_campaign_month(campaign_id: String, calendar_day: int,
		active_set: Array, domain_results: Array = []) -> Array:
	var reports: Array = []
	if campaign_id.is_empty() or active_set.is_empty():
		return reports
	var results_by_domain: Dictionary = {}
	for r in domain_results:
		if r is Dictionary:
			results_by_domain[String((r as Dictionary).get("domain_id", ""))] = r

	for ruler_id_v in active_set:
		var ruler_id: String = String(ruler_id_v)
		if ruler_id.is_empty():
			continue
		var ruler: Dictionary = CampaignRepository.get_character(ruler_id)
		# Never plan for PCs, nor for henchmen (a henchman heir on a player-side
		# domain is player-managed; NPC-lord henchman-vassal autonomy is a
		# Phase-3+ LOD question).
		if ruler.is_empty() \
				or String(ruler.get("character_type", "")) in ["pc", "henchman"]:
			continue
		# Lazy-ensure the disposition (gdd-ruler-ai.md §8.2: build on activation
		# if not cached).
		var disposition: StrategicDisposition = RulerDispositionRepository.get_disposition(ruler_id)
		if disposition == null:
			disposition = StrategicDispositionBuilder.build_and_persist_for_character(ruler_id)
		if disposition == null:
			reports.append({"ruler_id": ruler_id, "skipped_reason": "no_disposition"})
			continue

		var domain: Dictionary = _personal_domain_for_ruler(ruler_id)
		if domain.is_empty():
			reports.append({"ruler_id": ruler_id, "skipped_reason": "no_plannable_domain"})
			continue
		var report: Dictionary = _take_turn(
			ruler, domain, disposition, calendar_day,
			results_by_domain.get(String(domain.get("id", "")), {}))
		reports.append(report)
		_record_turn_state(campaign_id, ruler_id, calendar_day, report)
	return reports


## Provisional Phase-2 active set pending Phase 3's RulerLodManager: every
## full-persistence-tier NPC ruler that owns a domain in the campaign.
## Full-tier is the §8.1 hard gate (the buffer never promotes a named/abstract
## ruler); the missing piece is the 6-mile-window geometry, which needs the
## LOD manager. [PROVISIONAL — replace in Phase 3.]
static func provisional_active_set(campaign_id: String) -> Array:
	if campaign_id.is_empty():
		return []
	if not CampaignRepository.db.query_with_bindings("""
		SELECT DISTINCT c.id FROM characters c
		WHERE c.campaign_id = ?
		  AND c.character_type NOT IN ('pc', 'henchman')
		  AND c.persistence_tier = 'full'
		  AND c.is_dead = 0
		  AND c.id IN (SELECT owner_character_id FROM domains
		               WHERE campaign_id = ? AND owner_character_id IS NOT NULL)
		ORDER BY c.created_at, c.id
	""", [campaign_id, campaign_id]):
		return []
	var out: Array = []
	for row in CampaignRepository.db.query_result:
		out.append(String((row as Dictionary).get("id", "")))
	return out


## Persist the §10 ruler_ai_state turn stamp: the day this ruler last planned
## and the TOP-SCORED executed action id (actions append in scored order; ""
## when the turn produced no candidates).
static func _record_turn_state(campaign_id: String, ruler_id: String,
		calendar_day: int, report: Dictionary) -> void:
	var actions: Array = report.get("actions", [])
	var top_action: String = ""
	if not actions.is_empty():
		top_action = String((actions[0] as Dictionary).get("action_id", ""))
	RulerAiStateRepository.upsert(campaign_id, ruler_id, {
		"last_strategic_turn_day": calendar_day,
		"last_action_id": top_action,
	})


# ---------------------------------------------------------------------------
# One ruler-domain turn
# ---------------------------------------------------------------------------

static func _take_turn(ruler: Dictionary, domain: Dictionary,
		disposition: StrategicDisposition, calendar_day: int,
		month_result: Dictionary) -> Dictionary:
	var ruler_id: String = String(ruler.get("id", ""))
	var domain_id: String = String(domain.get("id", ""))
	var report: Dictionary = {
		"ruler_id": ruler_id,
		"domain_id": domain_id,
		"actions": [],
	}

	# §7: classify the threat set once; it drives the catalog's world_state,
	# the §6.2 threat modifiers, and the §7.1/§7.2/§7.4 crisis biases.
	var threats: Dictionary = RulerCrisisResponder.detect_threats(domain, month_result)
	var world_state: Dictionary = {
		"threat_present": bool(threats.get("threat_present", false)),
		"extraction_underway": bool(threats.get("hostile_army", false)),
		"besieged": bool(threats.get("besieged", false)),
	}
	var candidates: Array = RulerActionCatalog.available_for(ruler, domain, world_state)
	if candidates.is_empty():
		report["skipped_reason"] = "no_candidates"
		return report

	var ctx: Dictionary = _scoring_context(domain, world_state)
	# Seam B (§9.2): a validated LLM reassessment is a ONE-TURN situational
	# modifier — an optional posture override for this turn's §7.1 bias row
	# plus extra multiplicative biases riding the same crisis_biases channel
	# (and its safety gates, e.g. the tax direction gate). Popped here so a
	# nudge affects exactly one monthly turn; empty under the mock provider.
	var pending: Dictionary = RulerStrategyReassessor.consume_pending(ruler_id)
	var posture: String = String(pending.get("posture", ""))
	if posture.is_empty():
		posture = disposition.crisis_response
	var biases: Dictionary = RulerCrisisResponder.posture_biases(posture, threats)
	for bias_key in pending.get("biases", {}):
		biases[bias_key] = float(biases.get(bias_key, 1.0)) 			* float((pending["biases"] as Dictionary)[bias_key])
	ctx["crisis_biases"] = biases
	var rng: RandomNumberGenerator = RulerActionScorer.monthly_rng(ruler_id, calendar_day)
	var scored: Array = RulerActionScorer.score_candidates(candidates, disposition, ctx, rng)
	var take: int = RulerActionScorer.actions_for_scale(RealmAggregator.aggregate(ruler_id))

	var picked: int = 0
	var seen: Dictionary = {}
	for cand_v in scored:
		if picked >= take:
			break
		var cand: Dictionary = cand_v
		# Distinctness by (action, decree kind) — NOT by full params: when both
		# tax-decree variants (lower + raise) are candidates, only the
		# top-scored one may execute (running both in one month would just be
		# last-write-wins on the tax rate).
		var cand_params: Dictionary = cand.get("params", {})
		var key: String = String(cand.get("action_id", "")) + "|" \
			+ String(cand_params.get("decree_kind", ""))
		if seen.has(key):
			continue
		seen[key] = true
		picked += 1
		var action_id: String = String(cand.get("action_id", ""))
		# The resistance decision needs the offending army (§7.3); thread the
		# detected hostile army into the handler params.
		if action_id == "defensive_resistance" \
				and not String(threats.get("hostile_army_id", "")).is_empty():
			var enriched: Dictionary = (cand.get("params", {}) as Dictionary).duplicate()
			enriched["attacker_army_id"] = String(threats.get("hostile_army_id", ""))
			enriched["defending_own_stronghold"] = bool(threats.get("besieged", false))
			cand = cand.duplicate()
			cand["params"] = enriched
		var outcome: Dictionary = _execute(ruler_id, cand, domain_id, calendar_day)
		(report["actions"] as Array).append({
			"action_id": action_id,
			"params": cand.get("params", {}),
			"utility": cand.get("utility", 0.0),
			"outcome": outcome,
		})
		EventBus.ruler_action_taken.emit(ruler_id, domain_id, action_id, outcome)
	return report


## Deterministic handler dispatch per the §5 contract. The static map mirrors
## DomainActivityHandlersRegistration (the planner cannot reach the
## SessionRunner-owned registry instance from a static batch, and the GDD's
## contract is a direct on_complete call with state.character_id set).
## [param domain_id] is the planned personal domain — provably the same row
## the handlers resolve (identical ORDER BY query); issue_decree additionally
## gets it as an explicit param, and the planner (as the LAUNCHER) owns the
## oversee_investment treasury debit per the handler's launch-debit contract.
static func _execute(ruler_id: String, candidate: Dictionary, domain_id: String,
		calendar_day: int) -> Dictionary:
	var action_id: String = String(candidate.get("action_id", ""))
	if _NO_DISPATCH.has(action_id):
		return {
			"summary": "%s: recorded without dispatch (%s)" % [
				action_id,
				"deliberate no-op" if action_id == "hold" else "Phase-3 siege path",
			],
			"dispatched": false,
		}
	var state: Dictionary = {"character_id": ruler_id}
	var params: Dictionary = (candidate.get("params", {}) as Dictionary).duplicate()
	if action_id == "issue_decree":
		params["domain_id"] = domain_id
	if not params.is_empty():
		state["params_json"] = JSON.stringify(params)
		# oversee_investment reads cp_committed directly off state (Phase 3
		# handler contract), not params_json.
		if params.has("cp_committed"):
			state["cp_committed"] = int(params.get("cp_committed", 0))
	match action_id:
		"administer_domain":
			return AdministerDomainHandler.on_complete(state, null)
		"oversee_investment":
			# The handler's contract assumes the LAUNCHER debits the treasury
			# ("Treasury was already debited at launch"). The planner is the
			# launcher here, so it pays first — no free growth. (NOTE: the
			# PLAYER launch path does not actually perform this debit today —
			# a pre-existing hole flagged separately; do not mirror it here.)
			# Category "expense" so the handler's own +cp_committed
			# "investment" ledger row keeps its meaning and the category sums
			# reconcile (spend on the expense side, commitment on the
			# investment side).
			var cp_committed: int = int(params.get("cp_committed", 0))
			var withdrawal: Dictionary = DomainTreasury.withdraw(
				domain_id, cp_committed, calendar_day, "expense",
				"oversee_investment_committed",
				"NPC ruler committed %d cp to agricultural investment" % cp_committed)
			if not bool(withdrawal.get("ok", false)):
				return {
					"summary": "oversee_investment: treasury withdrawal failed (%s)"
						% String(withdrawal.get("reason", "")),
					"blocked_reason": String(withdrawal.get("reason", "")),
					"dispatched": false,
				}
			return OverseeInvestmentHandler.on_complete(state, null)
		"issue_decree":
			return IssueDecreeHandler.on_complete(state, null)
		"raise_garrison":
			return RaiseGarrisonHandler.on_complete(state, null)
		"repress_population":
			return RepressPopulationHandler.on_complete(state, null)
		"train_troops":
			return TrainTroopsHandler.on_complete(state, null)
		"manage_stronghold":
			return ManageStrongholdHandler.on_complete(state, null)
		"defensive_resistance":
			return DefensiveResistanceHandler.on_complete(state, null)
		"call_to_arms":
			# The §5.3 composite muster is Phase-3 crisis work (CallToArmsMuster
			# needs obligation/vassal routing); recorded until then.
			return {"summary": "call_to_arms: routing lands with Phase 3", "dispatched": false}
	return {"summary": "%s: no dispatch mapping" % action_id, "dispatched": false}


# ---------------------------------------------------------------------------
# Context assembly
# ---------------------------------------------------------------------------

## The ruler's PERSONAL domain (RAW acore_axioms_strongholds_and_domains.xml
## :265-272 — a ruler directly manages one domain), resolved with the SAME
## deterministic query every activity handler uses so plan and execution
## provably target the same row. Empty when the resolved row is in a
## terminal / ruler-less lifecycle (fresh post-_save_domain read).
static func _personal_domain_for_ruler(ruler_id: String) -> Dictionary:
	if not CampaignRepository.db.query_with_bindings(
		"SELECT id FROM domains WHERE owner_character_id = ? ORDER BY created_at, id LIMIT 1",
		[ruler_id]
	) or CampaignRepository.db.query_result.is_empty():
		return {}
	var domain_id: String = String(CampaignRepository.db.query_result[0].get("id", ""))
	var domain: Dictionary = CampaignRepository.get_domain(domain_id)
	if domain.is_empty():
		return {}
	if String(domain.get("lifecycle_state", "active")) in [
			"abandoned", "salted_to_ruin", "succession_pending"]:
		return {}
	return domain


static func _scoring_context(domain: Dictionary, world_state: Dictionary) -> Dictionary:
	var domain_id: String = String(domain.get("id", ""))
	var garrison: Dictionary = GarrisonExpenditureCalculator.compute_from_domain(domain)
	var hex_count: int = StrongholdRepository.get_effective_hex_count_for_domain(domain_id)
	var minimum_cp: int = StrongholdRepository.classification_minimum_gp(
		String(domain.get("territory_type", "wilderness")), hex_count)
	var value_cp: int = StrongholdRepository.get_stronghold_value_for_domain(domain_id)
	return {
		"morale": int(domain.get("morale", 0)),
		"treasury_cp": int(domain.get("treasury_cp", 0)),
		"monthly_expenses_cp": int(domain.get("expenses_cp", 0)),
		"current_tax_cp": int(domain.get("tax_rate_cp_per_family", 200)),
		"garrison_needs_raising": RulerActionCatalog.garrison_needs_raising(garrison),
		"stronghold_below_minimum": minimum_cp - value_cp >= 100,
		"stronghold_ruined": String(domain.get("lifecycle_state", "active")) == "ruined_stronghold",
		"threat_present": bool(world_state.get("threat_present", false)),
	}
