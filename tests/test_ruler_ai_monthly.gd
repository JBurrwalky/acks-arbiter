extends "res://tests/test_suite_base.gd"
## Ruler AI Phase 2 tests (gdd-ruler-ai.md §6/§8.4/§12): scorer determinism +
## §6.2 modifiers, the §6.3 worked-example scenario (Turbulent + oppressive
## ruler -> raise garrison then repress), multi-month morale trend, backdrop
## auto-stabilize, the mixed active/backdrop batch with no auto_pause for NPC
## rulers, and realm-scale action counts.
##
## Follows the scenario_runner_base white-box precedent: the morale roll is
## injected directly (DomainMoraleResolver takes roll_2d6 as a parameter), so
## every multi-month trend here is deterministic.

var _campaign_id: String = ""


func run_all_tests() -> void:
	_campaign_id = CampaignRepository.create_campaign("Ruler AI Monthly Tests", "World")

	test_scorer_determinism()
	test_scorer_morale_tier_modifiers()
	test_scorer_treasury_modifiers()
	test_scorer_threat_modifiers()
	test_scorer_hold_is_flat_floor()
	test_actions_for_scale()
	test_worked_example_iron_fisted_baron()
	test_morale_trends_up_over_months()
	test_backdrop_stabilizer_statics()
	test_backdrop_neglect_floor_keeps_prior_damage()
	test_mixed_batch_active_acts_backdrop_does_not()
	test_provisional_active_set_excludes_pc_named_dead()
	test_monthly_tick_integration()
	test_favors_duties_rolls_once_per_ruler_and_only_at_active_lod()  # R-1
	test_tribute_in_is_credited_once_per_seat_with_realm_wide_efficiency()
	test_monthly_tick_no_pause_without_player_domain()

	if not has_failures():
		print("RulerAiMonthly: all tests passed (%d checks)." % test_count())


## Minimal SessionRunner stand-in — DomainHandlers only ever calls
## get_campaign_id() (its one other _runner use is has_method-guarded).
class FakeRunner:
	var campaign_id: String
	func _init(cid: String) -> void:
		campaign_id = cid
	func get_campaign_id() -> String:
		return campaign_id


func _monthly_tick_event() -> ScheduledEvent:
	var ev := ScheduledEvent.new()
	ev.fire_time = Timekeeping.get_total_rounds()
	ev.event_type = "domain_monthly_tick"
	ev.owner_id = "domain_global"
	return ev


# ---------------------------------------------------------------------------
# Fixtures / helpers
# ---------------------------------------------------------------------------

## The §8.3 Lawful baron (golden disposition: military .846, oppression .801).
func _baron_disposition() -> StrategicDisposition:
	var p := NpcPersonality.new()
	p.axes = {
		"epistemic_curiosity": 3, "societal_orthodoxy": 9, "affective_compassion": 2,
		"stress_reactivity": 7, "self_interest": 4, "in_group_loyalty": 8, "mysticism": 3,
	}
	p.motivation_primary = "power"
	p.motivation_secondary = "security"
	return StrategicDispositionBuilder.build(p, "lawful")


func _make_ruler_with_domain(tag: String, opts: Dictionary = {}) -> Dictionary:
	var ruler_id := CampaignRepository.create_character({
		"campaign_id": _campaign_id,
		"name": "Ruler %s" % tag,
		"character_type": String(opts.get("character_type", "npc")),
		"persistence_tier": String(opts.get("persistence_tier", "full")),
		"alignment": "lawful",
		"personality": NpcPersonality.new().to_json(),
	})
	var domain_id := CampaignRepository.create_domain({
		"campaign_id": _campaign_id,
		"name": "Domain %s" % tag,
		"owner_character_id": ruler_id,
		"territory_type": String(opts.get("territory_type", "civilized")),
	})
	CampaignRepository.db.query_with_bindings("""
		UPDATE domains SET peasant_families = ?, treasury_cp = ?, morale = ?,
			expenses_cp = ? WHERE id = ?
	""", [
		int(opts.get("peasants", 100)), int(opts.get("treasury_cp", 0)),
		int(opts.get("morale", 0)), int(opts.get("expenses_cp", 0)), domain_id,
	])
	return {"ruler_id": ruler_id, "domain_id": domain_id}


func _cands(ids: Array) -> Array:
	var out: Array = []
	for id_v in ids:
		out.append({
			"action_id": String(id_v), "base_value": 0.3,
			"weight_key": "economic_weight", "crisis_modulated": false, "params": {},
		})
	return out


func _find_utility(scored: Array, action_id: String, decree_kind: String = "") -> float:
	for row in scored:
		if String((row as Dictionary).get("action_id", "")) != action_id:
			continue
		var kind := String(((row as Dictionary).get("params", {}) as Dictionary)
			.get("decree_kind", ""))
		if decree_kind.is_empty() or kind == decree_kind:
			return float((row as Dictionary).get("utility", -1.0))
	return -1.0


## White-box event-modifier sum for the trend test (mirrors
## domain_handlers._union_event_modifiers_sum's garrison + administer terms — the
## only terms these fixtures exercise; scenario_runner_base precedent).
func _event_mods(domain: Dictionary) -> int:
	var garrison: Dictionary = GarrisonExpenditureCalculator.compute_from_domain(domain)
	var sum: int = -int(garrison.get("gp_below_minimum_per_family", 0))
	if int(domain.get("administer_domain_completed_this_month", 0)) == 1:
		sum += 1
	return sum


# ---------------------------------------------------------------------------
# Scorer (§6.1/§6.2)
# ---------------------------------------------------------------------------

func test_scorer_determinism() -> void:
	var d := _baron_disposition()
	var ctx := {"morale": -2, "treasury_cp": 10000, "monthly_expenses_cp": 20000,
		"garrison_needs_raising": true, "threat_present": false}
	var candidates := _cands(["administer_domain", "raise_garrison", "hold"])
	var a := RulerActionScorer.score_candidates(
		candidates, d, ctx, RulerActionScorer.monthly_rng("ruler_x", 336))
	var b := RulerActionScorer.score_candidates(
		candidates, d, ctx, RulerActionScorer.monthly_rng("ruler_x", 336))
	check(JSON.stringify(a) == JSON.stringify(b),
		"identical (ruler, domain, seed) -> identical scored order")


func test_scorer_morale_tier_modifiers() -> void:
	var d := _baron_disposition()
	var cand := [{"action_id": "administer_domain", "base_value": 0.45,
		"weight_key": "economic_weight", "crisis_modulated": false, "params": {}}]
	var rng := RulerActionScorer.monthly_rng("r", 1)
	var loyal := _find_utility(RulerActionScorer.score_candidates(
		cand, d, {"morale": 2}, rng), "administer_domain")
	var rebellious := _find_utility(RulerActionScorer.score_candidates(
		cand, d, {"morale": -4}, rng), "administer_domain")
	# §6.2: administer x1.0 at Loyal+, x1.8 at Defiant/Rebellious.
	check(absf(rebellious / loyal - 1.8) < 0.0001,
		"administer modifier scales 1.0 -> 1.8 across morale bands (ratio %f)"
			% (rebellious / loyal))
	# repress: x0.2 at Loyal+, x1.5 at Rebellious.
	var rep := [{"action_id": "repress_population", "base_value": 0.15,
		"weight_key": "oppression_weight", "crisis_modulated": false, "params": {}}]
	var rep_loyal := _find_utility(RulerActionScorer.score_candidates(
		rep, d, {"morale": 2}, rng), "repress_population")
	var rep_reb := _find_utility(RulerActionScorer.score_candidates(
		rep, d, {"morale": -4}, rng), "repress_population")
	check(absf(rep_reb / rep_loyal - 7.5) < 0.0001,
		"repress modifier scales 0.2 -> 1.5 across morale bands (ratio %f)"
			% (rep_reb / rep_loyal))


func test_scorer_treasury_modifiers() -> void:
	var d := _baron_disposition()
	var rng := RulerActionScorer.monthly_rng("r", 2)
	var invest := [{"action_id": "oversee_investment", "base_value": 0.35,
		"weight_key": "economic_weight", "crisis_modulated": false, "params": {}}]
	# Poor (< 2 months buffer): x0.4. Rich (> 6 months): x1.4. Neutral between.
	var poor := _find_utility(RulerActionScorer.score_candidates(
		invest, d, {"morale": 0, "treasury_cp": 10000, "monthly_expenses_cp": 10000},
		rng), "oversee_investment")
	var neutral := _find_utility(RulerActionScorer.score_candidates(
		invest, d, {"morale": 0, "treasury_cp": 40000, "monthly_expenses_cp": 10000},
		rng), "oversee_investment")
	var rich := _find_utility(RulerActionScorer.score_candidates(
		invest, d, {"morale": 0, "treasury_cp": 100000, "monthly_expenses_cp": 10000},
		rng), "oversee_investment")
	check(absf(poor / neutral - 0.4) < 0.0001, "poor treasury throttles investment x0.4")
	check(absf(rich / neutral - 1.4) < 0.0001, "rich treasury boosts investment x1.4")
	# The broke boost applies only to a RAISING tax decree (value > current).
	var tax_raise := [{"action_id": "issue_decree", "base_value": 0.20,
		"weight_key": "economic_weight", "crisis_modulated": false,
		"params": {"decree_kind": "tax", "value": 300}}]
	var tax_poor := _find_utility(RulerActionScorer.score_candidates(
		tax_raise, d, {"morale": 0, "treasury_cp": 0, "monthly_expenses_cp": 10000,
			"current_tax_cp": 200}, rng), "issue_decree", "tax")
	var tax_neutral := _find_utility(RulerActionScorer.score_candidates(
		tax_raise, d, {"morale": 0, "treasury_cp": 40000, "monthly_expenses_cp": 10000,
			"current_tax_cp": 200}, rng), "issue_decree", "tax")
	check(absf(tax_poor / tax_neutral - 1.5) < 0.0001,
		"poor treasury boosts the RAISING tax decree x1.5")
	# A LOWERING decree never gets the broke boost, but does get the §6.2
	# "decree(lower tax)" morale column (x1.4 at Turbulent vs x1.0 neutral).
	var tax_lower := [{"action_id": "issue_decree", "base_value": 0.20,
		"weight_key": "economic_weight", "crisis_modulated": false,
		"params": {"decree_kind": "tax", "value": 200}}]
	var lower_poor := _find_utility(RulerActionScorer.score_candidates(
		tax_lower, d, {"morale": 0, "treasury_cp": 0, "monthly_expenses_cp": 10000,
			"current_tax_cp": 300}, rng), "issue_decree", "tax")
	var lower_neutral := _find_utility(RulerActionScorer.score_candidates(
		tax_lower, d, {"morale": 0, "treasury_cp": 40000, "monthly_expenses_cp": 10000,
			"current_tax_cp": 300}, rng), "issue_decree", "tax")
	check(absf(lower_poor / lower_neutral - 1.0) < 0.0001,
		"the lowering decree never gets the broke boost")
	var lower_turbulent := _find_utility(RulerActionScorer.score_candidates(
		tax_lower, d, {"morale": -2, "current_tax_cp": 300}, rng), "issue_decree", "tax")
	var lower_apathetic := _find_utility(RulerActionScorer.score_candidates(
		tax_lower, d, {"morale": 0, "current_tax_cp": 300}, rng), "issue_decree", "tax")
	check(absf(lower_turbulent / lower_apathetic - 1.4) < 0.0001,
		"the lowering decree gets the §6.2 morale column (1.4 at Turbulent)")


func test_scorer_threat_modifiers() -> void:
	var d := _baron_disposition()
	var rng := RulerActionScorer.monthly_rng("r", 3)
	var cands := [
		{"action_id": "defensive_resistance", "base_value": 0.50,
			"weight_key": "military_weight", "crisis_modulated": true, "params": {}},
		{"action_id": "oversee_investment", "base_value": 0.35,
			"weight_key": "economic_weight", "crisis_modulated": false, "params": {}},
	]
	var calm := RulerActionScorer.score_candidates(cands, d, {"morale": 0}, rng)
	var threat := RulerActionScorer.score_candidates(
		cands, d, {"morale": 0, "threat_present": true}, rng)
	check(absf(_find_utility(threat, "defensive_resistance")
			/ _find_utility(calm, "defensive_resistance") - 2.0) < 0.0001,
		"threat doubles defensive actions")
	check(absf(_find_utility(threat, "oversee_investment")
			/ _find_utility(calm, "oversee_investment") - 0.5) < 0.0001,
		"threat halves investment")


func test_scorer_hold_is_flat_floor() -> void:
	var d := _baron_disposition()
	var hold := [{"action_id": "hold", "base_value": 0.10,
		"weight_key": "", "crisis_modulated": false, "params": {}}]
	var scored := RulerActionScorer.score_candidates(
		hold, d, {"morale": -4, "threat_present": true, "treasury_cp": 0,
			"monthly_expenses_cp": 99999}, RulerActionScorer.monthly_rng("r", 4))
	check(absf(_find_utility(scored, "hold") - 0.10) < 0.0000001,
		"hold utility is the unmodified 0.10 floor in every context")


func test_actions_for_scale() -> void:
	check(RulerActionScorer.actions_for_scale({"domains_ruled": 1, "all_realm_families": 100}) == 1,
		"small realm acts once")
	check(RulerActionScorer.actions_for_scale({"domains_ruled": 3, "all_realm_families": 100}) == 2,
		"3 domains -> 2 actions")
	check(RulerActionScorer.actions_for_scale({"domains_ruled": 1, "all_realm_families": 12000}) == 3,
		"large family count -> 3 actions")


# ---------------------------------------------------------------------------
# §6.3 worked example + the acceptance-bar scenario (§12)
# ---------------------------------------------------------------------------

func test_worked_example_iron_fisted_baron() -> void:
	# Turbulent (-2) domain, under-garrison, with a mercenary force present so
	# repress is offered. The §6.3 prediction: raise_garrison dominates,
	# repress is the strong secondary, administer trails.
	var fx := _make_ruler_with_domain("ironfist", {"morale": -2, "peasants": 100})
	TroopUnitRepository.create_unit({
		"campaign_id": _campaign_id, "owner_character_id": fx.ruler_id,
		"assigned_domain_id": fx.domain_id, "source_type": "mercenary",
		"troop_type": "Fixture Guards", "race": "human", "tier": "average",
		"starting_count": 10, "count": 10, "battle_rating": 0.1,
		"monthly_wage_cp": 1000, "monthly_supply_cp": 0, "monthly_specialist_cp": 0,
		"monthly_cost_cp": 1000, "morale": 0, "is_veteran": false, "is_trained": true,
		"unit_xp": 0, "assignment_kind": "garrison", "hire_calendar_day": 0,
		"equipment_kit": "fixture",
	})
	var ruler: Dictionary = CampaignRepository.get_character(fx.ruler_id)
	var domain: Dictionary = CampaignRepository.get_domain(fx.domain_id)
	var candidates := RulerActionCatalog.available_for(ruler, domain, {})
	var d := _baron_disposition()
	var garrison := GarrisonExpenditureCalculator.compute_from_domain(domain)
	var ctx := {
		"morale": -2,
		"treasury_cp": 0, "monthly_expenses_cp": 0,
		"garrison_needs_raising": RulerActionCatalog.garrison_needs_raising(garrison),
		"stronghold_below_minimum": true, "stronghold_ruined": false,
		"threat_present": false,
	}
	var scored := RulerActionScorer.score_candidates(
		candidates, d, ctx, RulerActionScorer.monthly_rng(fx.ruler_id, 100))
	check(String((scored[0] as Dictionary).get("action_id", "")) == "raise_garrison",
		"§6.3: raise_garrison dominates for the Turbulent under-garrisoned baron (got %s)"
			% String((scored[0] as Dictionary).get("action_id", "")))
	var rg := _find_utility(scored, "raise_garrison")
	var rp := _find_utility(scored, "repress_population")
	var ad := _find_utility(scored, "administer_domain")
	check(rp > ad, "§6.3: repress is the oppressive baron's strong secondary (%f > %f)" % [rp, ad])
	check(rg > rp, "§6.3: garrison first, repression second (%f > %f)" % [rg, rp])


func test_morale_trends_up_over_months() -> void:
	# §12 integration bar: Turbulent domain + oppressive ruler -> the planner
	# raises the garrison then represses; morale trends up over a few months.
	# White-box month loop with an injected mid-band roll (7) per the
	# scenario_runner_base precedent.
	var fx := _make_ruler_with_domain("trend", {"morale": -2, "peasants": 100})
	var disposition := _baron_disposition()
	RulerDispositionRepository.save_disposition(_campaign_id, fx.ruler_id, disposition)
	var base_morale := 0  # neutral base for the drift band
	var morale_now := -2
	for month in range(3):
		var calendar_day: int = 1 + month * 28
		var reports := RulerAI.process_campaign_month(
			_campaign_id, calendar_day, [fx.ruler_id])
		check(reports.size() >= 1, "month %d: planner produced a report" % month)
		var domain: Dictionary = CampaignRepository.get_domain(fx.domain_id)
		var mods := _event_mods(domain)
		var is_repressed := bool(domain.get("is_repressed_this_month", 0))
		var repression_bonus: int = int(domain.get("repression_cp_per_family_this_month", 0))
		var morale_result := DomainMoraleResolver.resolve_current_morale(
			domain, base_morale, mods, repression_bonus, is_repressed, 7)
		morale_now = int(morale_result.get("current_morale", morale_now))
		CampaignRepository.db.query_with_bindings(
			"UPDATE domains SET morale = ?, administer_domain_completed_this_month = 0, "
			+ "is_repressed_this_month = 0, repression_cp_per_family_this_month = 0 "
			+ "WHERE id = ?", [morale_now, fx.domain_id])
	check(morale_now > -2,
		"morale trends up from Turbulent under the planner (now %d)" % morale_now)
	var units := TroopUnitRepository.list_active_for_domain(fx.domain_id)
	check(not units.is_empty(), "planner raised the garrison during the trend months")


# ---------------------------------------------------------------------------
# §8.4 backdrop auto-stabilize
# ---------------------------------------------------------------------------

func test_backdrop_stabilizer_statics() -> void:
	# Garrison suppression: the roll-side summary zeroes the shortfall; the
	# original is untouched.
	var garrison := {"gp_below_minimum_per_family": 2, "cp_below_minimum_per_family": 200}
	var adjusted := RulerBackdropStabilizer.adjust_garrison_summary(garrison)
	check(int(adjusted.get("gp_below_minimum_per_family", -1)) == 0,
		"stabilizer suppresses the under-garrison morale penalty")
	check(int(garrison.get("gp_below_minimum_per_family", 0)) == 2,
		"original garrison summary untouched (expenses stay real)")
	# The administer assumption rides the opts flag (never the dict flag — the
	# dict flag would leak the +5% XP bonus through _save_domain).
	var opts := RulerBackdropStabilizer.resolution_options()
	check(bool(opts.get(RulerBackdropStabilizer.OPT_ASSUME_ADMINISTERED, false)),
		"stabilizer opts assume routine administration (+1 morale roll only)")
	# Neglect floor: a bad roll cannot take a healthy backdrop domain below 0
	# when the remaining modifiers are non-negative (pure neglect).
	var bad_roll := {"current_morale": -2, "morale_change": -2}
	var floored := RulerBackdropStabilizer.apply_neglect_floor(bad_roll, 0, 1)
	check(int(floored.get("current_morale", -99)) == 0,
		"neglect floor holds backdrop morale at Apathetic")
	check(bool(floored.get("neglect_floor_applied", false)), "floor marker set")
	# Substantive damage (negative modifiers: challenger pillage, lair, taxes)
	# is NOT neglect — the floor must not bind.
	var damaged := RulerBackdropStabilizer.apply_neglect_floor(bad_roll, 0, -4)
	check(int(damaged.get("current_morale", -99)) == -2,
		"damage-class modifiers bypass the neglect floor (§8.4: apply in full)")


func test_backdrop_neglect_floor_keeps_prior_damage() -> void:
	# A domain that left camera at -2 (e.g. player-caused) keeps its damage:
	# the floor is min(prior, 0) = -2 — it cannot DEEPEN from neglect, and a
	# result above the floor passes through untouched.
	var worse := RulerBackdropStabilizer.apply_neglect_floor(
		{"current_morale": -3, "morale_change": -1}, -2, 0)
	check(int(worse.get("current_morale", -99)) == -2,
		"pre-existing damage is preserved but not deepened")
	var recovering := RulerBackdropStabilizer.apply_neglect_floor(
		{"current_morale": -1, "morale_change": 1}, -2, 0)
	check(int(recovering.get("current_morale", -99)) == -1,
		"recovery above the floor passes through")
	check(not recovering.has("neglect_floor_applied"),
		"no marker when the floor did not bind")


# ---------------------------------------------------------------------------
# Mixed batch (§12) + the provisional active set
# ---------------------------------------------------------------------------

func test_mixed_batch_active_acts_backdrop_does_not() -> void:
	var active := _make_ruler_with_domain("active", {"peasants": 100})
	var backdrop := _make_ruler_with_domain("backdrop",
		{"peasants": 100, "persistence_tier": "named"})
	var actions_seen: Array = []
	var handler := func(ruler_npc_id: String, _domain_id: String, action_id: String,
			_outcome: Dictionary) -> void:
		actions_seen.append({"ruler": ruler_npc_id, "action": action_id})
	EventBus.ruler_action_taken.connect(handler)
	var reports := RulerAI.process_campaign_month(
		_campaign_id, 500, [active.ruler_id])
	EventBus.ruler_action_taken.disconnect(handler)

	var active_acted := false
	var backdrop_acted := false
	for a in actions_seen:
		if String((a as Dictionary).get("ruler", "")) == active.ruler_id:
			active_acted = true
		if String((a as Dictionary).get("ruler", "")) == backdrop.ruler_id:
			backdrop_acted = true
	check(active_acted, "active-set ruler took at least one action (ruler_action_taken emitted)")
	check(not backdrop_acted, "backdrop ruler took NO discretionary action")
	check(reports.size() >= 1 and not (reports[0] as Dictionary).has("skipped_reason"),
		"active ruler report has actions")
	# The disposition was lazily ensured for the active ruler (§8.2).
	check(RulerDispositionRepository.has_disposition(active.ruler_id),
		"disposition lazily built on first planner turn")


## The §12 mixed-batch integration bar, exercised through the REAL
## _handle_monthly_tick (the [NEEDS-OPUS-REVIEW] integration): the PC domain
## pauses the clock, the active NPC ruler acts, the backdrop domain only
## auto-stabilizes, and the repression transients reset.
func test_monthly_tick_integration() -> void:
	var camp := CampaignRepository.create_campaign("Tick Integration", "World")
	var save := _campaign_id
	_campaign_id = camp
	var pc := _make_ruler_with_domain("it_pc", {"character_type": "pc"})
	var active := _make_ruler_with_domain("it_active", {"morale": -2, "peasants": 100})
	var backdrop := _make_ruler_with_domain("it_backdrop",
		{"morale": 2, "peasants": 100, "persistence_tier": "named"})
	_campaign_id = save
	# The active ruler repressed last month — the tick must consume + reset it.
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET is_repressed_this_month = 1, "
		+ "repression_cp_per_family_this_month = 1 WHERE id = ?", [active.domain_id])

	var handlers := DomainHandlers.new(FakeRunner.new(camp))
	var result: Dictionary = handlers._handle_monthly_tick(_monthly_tick_event())

	check(bool(result.get("auto_pause", false)),
		"monthly report pauses when the player owns a domain")
	# R-1 wiring: the hoisted Favors & Duties pass is reached by the real tick, and
	# the key no longer rides on each domain's result. Both are true regardless of
	# what any die shows, so this is the deterministic half of the hoist's coverage —
	# the counts live in test_favors_duties_rolls_once_per_ruler_and_only_at_active_lod.
	check(result.has("favors_duties_reports"),
		"the tick reports Favors & Duties per RULER")
	for d in (result.get("presentation", {}) as Dictionary).get("domain_results", []):
		check(not (d as Dictionary).has("favors_duties"),
			"favors_duties is no longer a per-domain key")
	var reports: Array = result.get("ruler_reports", [])
	var active_report: Dictionary = {}
	for r in reports:
		if r is Dictionary and String((r as Dictionary).get("ruler_id", "")) == active.ruler_id:
			active_report = r
		check(String((r as Dictionary).get("ruler_id", "")) != backdrop.ruler_id,
			"backdrop (named-tier) ruler took no planner turn")
		check(String((r as Dictionary).get("ruler_id", "")) != pc.ruler_id,
			"the PC took no planner turn")
	check(not active_report.is_empty()
			and not (active_report.get("actions", []) as Array).is_empty(),
		"active-set NPC ruler acted through the real tick")
	# Backdrop §8.4: morale floored at Apathetic under pure neglect (garrison
	# suppressed + administration assumed -> modifiers >= 0, so even a
	# natural 2 cannot take it below 0).
	var backdrop_domain := CampaignRepository.get_domain(backdrop.domain_id)
	check(int(backdrop_domain.get("morale", -99)) >= 0,
		"backdrop domain held at/above Apathetic (got %d)"
			% int(backdrop_domain.get("morale", -99)))
	check(int(backdrop_domain.get("administer_domain_completed_this_month", 1)) == 0,
		"no phantom administer flag persisted for the backdrop domain")
	# Repression transients consumed + reset by the tick (monthly stance).
	var active_domain := CampaignRepository.get_domain(active.domain_id)
	check(int(active_domain.get("is_repressed_this_month", 1)) == 0,
		"is_repressed_this_month reset after consumption")
	check(int(active_domain.get("repression_cp_per_family_this_month", 1)) == 0,
		"repression_cp_per_family_this_month reset after consumption")


## Tribute-in keys on TWO different scopes, and the split is the point
## (Jedidiah ruling 2026-08-04):
##   * the RAW inefficiency penalty is CHARACTER-wide — "the sum-total of ALL
##     vassals paying tribute to a single character, regardless of which domain
##     seat they are paying to";
##   * the credit is DOMAIN-scoped — each vassal's tribute lands in the seat his
##     fief is actually held of.
##
## Before this, the ruler's ENTIRE tribute was credited to every domain he held,
## so a two-domain lord banked his realm's tribute twice (and twice the domain XP).
## Fixture: one lord, two seats, one vassal under each.
func test_tribute_in_is_credited_once_per_seat_with_realm_wide_efficiency() -> void:
	var camp := CampaignRepository.create_campaign("Tribute Split", "World")
	var save := _campaign_id
	_campaign_id = camp
	var lord := _make_ruler_with_domain("tr_lord", {"character_type": "pc"})
	var seat_b := CampaignRepository.create_domain({
		"campaign_id": camp, "name": "Second Seat",
		"owner_character_id": lord.ruler_id, "territory_type": "civilized",
	})
	var vassal_a := _make_ruler_with_domain("tr_va", {"persistence_tier": "named"})
	var vassal_b := _make_ruler_with_domain("tr_vb", {"persistence_tier": "named"})
	_campaign_id = save

	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET liege_domain_id = ? WHERE id = ?", [lord.domain_id, vassal_a.domain_id])
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET liege_domain_id = ? WHERE id = ?", [seat_b, vassal_b.domain_id])
	for pair in [[vassal_a.ruler_id, vassal_a.domain_id], [vassal_b.ruler_id, vassal_b.domain_id]]:
		VassalRepository.create_assignment({
			"campaign_id": camp,
			"liege_character_id": lord.ruler_id,
			"vassal_character_id": str(pair[0]),
			"vassal_domain_id": str(pair[1]),
			"assigned_calendar_day": 0, "status": "active",
			"is_henchman_vassal": false, "base_loyalty_modifier": -2,
		})

	var handlers := DomainHandlers.new(FakeRunner.new(camp))
	var a: Dictionary = handlers._compute_tribute_in_for_domain(
		CampaignRepository.get_domain(lord.domain_id))
	var b: Dictionary = handlers._compute_tribute_in_for_domain(
		CampaignRepository.get_domain(seat_b))

	# CHARACTER-wide: both seats see a TWO-vassal lord. A per-domain count would
	# report 1 here, and would put a 9-vassal lord in the wrong RAW band.
	check(int(a.get("direct_vassal_count", -1)) == 2,
		"seat A sees the lord's realm-wide vassal count (got %d)" % int(a.get("direct_vassal_count", -1)))
	check(int(b.get("direct_vassal_count", -1)) == 2,
		"seat B sees the lord's realm-wide vassal count (got %d)" % int(b.get("direct_vassal_count", -1)))

	# DOMAIN-scoped credit: each seat banks exactly its own vassal.
	var a_cp: int = int(a.get("total_received_cp", 0))
	var b_cp: int = int(b.get("total_received_cp", 0))
	var realm_cp: int = int(a.get("realm_total_received_cp", 0))
	check(a_cp > 0 and b_cp > 0, "each seat receives its own vassal's tribute (%d / %d)" % [a_cp, b_cp])
	check(realm_cp == int(b.get("realm_total_received_cp", 0)),
		"both seats agree on the lord's total realm intake")
	check(a_cp + b_cp == realm_cp,
		"the seats PARTITION the realm intake — no double credit (%d + %d vs %d)"
			% [a_cp, b_cp, realm_cp])
	check(a_cp < realm_cp,
		"one seat alone does NOT bank the whole realm's tribute (the old bug)")
	check((a.get("per_vassal", []) as Array).size() == 1,
		"seat A itemizes exactly its own one vassal")


## R-1: the Favors & Duties roll is once per RULER and LOD-gated.
##
## It used to run inside the per-domain loop keyed on `owner_character_id`, so a
## ruler holding N domains rolled the full RAW table for every one of his vassals N
## times a month. That was invisible only because world generation left
## `vassal_assignments` empty; R-1 fills it, so the multiplication had to go first.
##
## Fixture: a PC lord holding TWO domains with ONE vassal — the old code would
## report two rolls — plus a backdrop NPC lord with his own vassal, who must not
## roll at all.
##
## Driven through `_resolve_favors_and_duties_for_rulers` DIRECTLY rather than
## through `_handle_monthly_tick`. The first version of this test ran the whole tick
## and was FLAKY: because the hoisted pass now runs after the domain loop, it sees
## post-loyalty-roll state, and a tick's stochastic loyalty rolls can route through
## the resignation/rebellion paths — which (as of this same wave) depart the very
## vassal edge the assertion counts. That is correct behaviour and a genuinely
## unstable thing to assert on. The dedupe and the LOD gate are what R-1 changed, so
## that is what this exercises; `test_monthly_tick_integration` covers the wiring.
func test_favors_duties_rolls_once_per_ruler_and_only_at_active_lod() -> void:
	var camp := CampaignRepository.create_campaign("FD Hoist", "World")
	var save := _campaign_id
	_campaign_id = camp
	var lord := _make_ruler_with_domain("fd_pc", {"character_type": "pc"})
	var second_domain := CampaignRepository.create_domain({
		"campaign_id": camp,
		"name": "Second Seat",
		"owner_character_id": lord.ruler_id,
		"territory_type": "civilized",
	})
	var vassal := _make_ruler_with_domain("fd_vassal", {"persistence_tier": "named"})
	var backdrop := _make_ruler_with_domain("fd_backdrop", {"persistence_tier": "named"})
	var backdrop_vassal := _make_ruler_with_domain("fd_bd_vassal",
		{"persistence_tier": "named"})
	_campaign_id = save

	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET liege_domain_id = ? WHERE id = ?", [lord.domain_id, vassal.domain_id])
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET liege_domain_id = ? WHERE id = ?",
		[backdrop.domain_id, backdrop_vassal.domain_id])
	for pair in [[lord.ruler_id, vassal.ruler_id, vassal.domain_id],
			[backdrop.ruler_id, backdrop_vassal.ruler_id, backdrop_vassal.domain_id]]:
		VassalRepository.create_assignment({
			"campaign_id": camp,
			"liege_character_id": str(pair[0]),
			"vassal_character_id": str(pair[1]),
			"vassal_domain_id": str(pair[2]),
			"assigned_calendar_day": 0,
			"status": "active",
			"is_henchman_vassal": false,
			"base_loyalty_modifier": -2,
		})

	check(not second_domain.is_empty(), "the lord's second domain was created")
	var domains: Array = CampaignRepository.list_campaign_domains(camp)
	var lord_domains: int = 0
	for d in domains:
		if str_field((d as Dictionary), "owner_character_id") == lord.ruler_id:
			lord_domains += 1
	check(lord_domains == 2,
		"the lord holds TWO domains, so a per-domain roll would double (got %d)" % lord_domains)

	var handlers := DomainHandlers.new(FakeRunner.new(camp))
	# The lord is PC-side; the backdrop lord is in neither set, which is the gate.
	var reports: Array = handlers._resolve_favors_and_duties_for_rulers(
		domains, {lord.ruler_id: true}, [], 100)

	var lord_reports: int = 0
	var lord_rolls: int = 0
	for r in reports:
		var row: Dictionary = r
		var rid := String(row.get("ruler_character_id", ""))
		check(rid != backdrop.ruler_id,
			"a backdrop-LOD lord does not hold court (no F&D roll off camera)")
		if rid == lord.ruler_id:
			lord_reports += 1
			lord_rolls += (row.get("results", []) as Array).size()
	check(lord_reports == 1,
		"the two-domain lord is reported ONCE, not once per domain (got %d)" % lord_reports)
	check(lord_rolls == 1,
		"one roll per VASSAL, not per (vassal x domain) (got %d)" % lord_rolls)


func test_monthly_tick_no_pause_without_player_domain() -> void:
	var camp := CampaignRepository.create_campaign("Tick NPC Only", "World")
	var save := _campaign_id
	_campaign_id = camp
	var npc := _make_ruler_with_domain("np_only", {"persistence_tier": "named"})
	_campaign_id = save
	check(not npc.domain_id.is_empty(), "NPC-only fixture created")
	var handlers := DomainHandlers.new(FakeRunner.new(camp))
	var result: Dictionary = handlers._handle_monthly_tick(_monthly_tick_event())
	check(not bool(result.get("auto_pause", false)),
		"no auto_pause when no player-side domain exists (gdd-ruler-ai.md §3.2)")
	check(not (result.get("next_events", []) as Array).is_empty(),
		"the tick still reschedules itself")


func test_provisional_active_set_excludes_pc_named_dead() -> void:
	var camp := CampaignRepository.create_campaign("Active Set Fixture", "World")
	var save := _campaign_id
	_campaign_id = camp
	var full_npc := _make_ruler_with_domain("as_full")
	var named_npc := _make_ruler_with_domain("as_named", {"persistence_tier": "named"})
	var pc := _make_ruler_with_domain("as_pc", {"character_type": "pc"})
	var dead := _make_ruler_with_domain("as_dead")
	CampaignRepository.db.query_with_bindings(
		"UPDATE characters SET is_dead = 1 WHERE id = ?", [dead.ruler_id])
	_campaign_id = save

	var active := RulerAI.provisional_active_set(camp)
	check(active.has(full_npc.ruler_id), "full-tier NPC ruler is active")
	check(not active.has(named_npc.ruler_id), "named-tier ruler stays backdrop (§8.1 gate)")
	check(not active.has(pc.ruler_id), "PC is never in the active set")
	check(not active.has(dead.ruler_id), "dead ruler is not active")
