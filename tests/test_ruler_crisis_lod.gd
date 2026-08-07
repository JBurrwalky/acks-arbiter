extends "res://tests/test_suite_base.gd"
## Ruler AI Phase 3 tests (gdd-ruler-ai.md §7/§8/§12): the §7.3 disposition-
## modulated extraction-resistance threshold (with the 50% no-disposition
## regression anchor), the §7.1/§7.2/§7.4 crisis-posture biases, threat
## detection, the real defensive_resistance handler, and RulerLodManager's
## geometry + tier gate + promote/demote signals (incl. the §8.1
## materialization-safety guarantee).

var _campaign_id: String = ""


func run_all_tests() -> void:
	_campaign_id = CampaignRepository.create_campaign("Ruler Crisis LOD Tests", "World")
	RulerLodManager.clear_cache()

	test_resistance_threshold_values()
	test_resistance_threshold_clamps()
	test_evaluate_disposition_shifts_both_ways()
	test_defensive_resistance_handler()
	test_posture_biases_table()
	test_scorer_consumes_crisis_biases()
	test_detect_threats()
	test_ruined_stronghold_prioritized()
	test_lod_geometry_and_tier_gate()
	test_lod_fixture_fallback()
	test_lod_sync_signals_and_lazy_disposition()

	if not has_failures():
		print("RulerCrisisLod: all tests passed (%d checks)." % test_count())


# ---------------------------------------------------------------------------
# Fixtures / helpers
# ---------------------------------------------------------------------------

## The §8.3 Lawful baron (military 0.84611, crisis aggressive at stress 7 /
## self-interest 4).
func _baron_disposition(stress: int = 7, self_interest: int = 4) -> StrategicDisposition:
	var p := NpcPersonality.new()
	p.axes = {
		"epistemic_curiosity": 3, "societal_orthodoxy": 9, "affective_compassion": 2,
		"stress_reactivity": stress, "self_interest": self_interest,
		"in_group_loyalty": 8, "mysticism": 3,
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
		"territory_type": "civilized",
	})
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET peasant_families = 100 WHERE id = ?", [domain_id])
	if opts.has("location_map_id"):
		CampaignRepository.db.query_with_bindings(
			"UPDATE domains SET location_map_id = ?, location_hex_q = 1, "
			+ "location_hex_r = 1 WHERE id = ?",
			[str_field(opts, "location_map_id"), domain_id])
	return {"ruler_id": ruler_id, "domain_id": domain_id}


## Mirrors test_extraction_resistance_realm_ai's attacker fixture.
func _make_attacker_army(br: float) -> String:
	var commander := CampaignRepository.create_character({
		"campaign_id": _campaign_id, "name": "Attacker",
		"character_type": "npc", "persistence_tier": "named",
	})
	var army_id: String = ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": "Raider Host",
		"political_owner_id": commander, "command_character_id": commander,
		"state": "marching", "formed_calendar_day": 100,
	})
	ArmyRepository.create_supply_state({"army_id": army_id})
	var leader := ArmyRepository.create_officer({
		"army_id": army_id, "character_id": commander, "rank": "army_leader",
		"appointed_calendar_day": 100,
	})
	var unit_id: String = TroopUnitRepository.create_unit({
		"campaign_id": _campaign_id, "owner_character_id": commander,
		"source_type": "mercenary", "troop_type": "Raider Foot",
		"count": 60, "starting_count": 60, "battle_rating": br,
		"monthly_wage_cp": 600,
	})
	ArmyRepository.create_assignment({
		"army_id": army_id, "troop_unit_id": unit_id,
		"parent_officer_id": leader, "role": "line",
		"assigned_calendar_day": 100,
	})
	return army_id


func _add_garrison(ruler_id: String, domain_id: String, br: float) -> void:
	TroopUnitRepository.create_unit({
		"campaign_id": _campaign_id, "owner_character_id": ruler_id,
		"assigned_domain_id": domain_id, "source_type": "mercenary",
		"troop_type": "Garrison", "count": 60, "starting_count": 60,
		"battle_rating": br, "assignment_kind": "garrison",
	})


func _region_map(campaign_id: String) -> String:
	var map_id := "%s_region6mi" % campaign_id
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO hex_maps (id, campaign_id, name, scale) VALUES (?, ?, ?, 'regional_6mi')",
		[map_id, campaign_id, "LOD Region"])
	return map_id


# ---------------------------------------------------------------------------
# §7.3 resistance threshold
# ---------------------------------------------------------------------------

func test_resistance_threshold_values() -> void:
	# The regression anchor: NO disposition -> exactly the 0.50 placeholder.
	check(absf(RulerCrisisResponder.resistance_threshold(null) - 0.5) < 0.000001,
		"null disposition anchors at 0.50")
	check(absf(RulerCrisisResponder.resistance_threshold(null, true) - 0.6) < 0.000001,
		"defending own stronghold adds +0.10")
	# Aggressive baron: 0.50 - 0.15 x 0.84611 - 0.10 = 0.27308.
	var aggressive := _baron_disposition(7, 4)
	check(aggressive.crisis_response == "aggressive", "baron variant is aggressive")
	_approx(RulerCrisisResponder.resistance_threshold(aggressive),
		0.5 - 0.15 * aggressive.military_weight - 0.10, "aggressive threshold")
	# Cautious variant (stress 7, self 6): +0.15 instead of -0.10.
	var cautious := _baron_disposition(7, 6)
	check(cautious.crisis_response == "cautious", "baron variant is cautious")
	_approx(RulerCrisisResponder.resistance_threshold(cautious),
		0.5 - 0.15 * cautious.military_weight + 0.15, "cautious threshold")
	# Diplomatic degrades to cautious (§7.1).
	var diplomatic := _baron_disposition(5, 4)
	check(diplomatic.crisis_response == "diplomatic", "baron variant is diplomatic")
	_approx(RulerCrisisResponder.resistance_threshold(diplomatic),
		0.5 - 0.15 * diplomatic.military_weight + 0.15,
		"diplomatic threshold degrades to the cautious shift")


func test_resistance_threshold_clamps() -> void:
	# Clamp bounds via direct struct manipulation (the builder cannot produce
	# out-of-range weights; the clamp guards future tuning).
	var extreme := StrategicDisposition.new()
	extreme.military_weight = 3.0
	extreme.crisis_response = "aggressive"
	check(absf(RulerCrisisResponder.resistance_threshold(extreme) - 0.2) < 0.000001,
		"lower clamp at 0.2")
	extreme.military_weight = -3.0
	extreme.crisis_response = "cautious"
	check(absf(RulerCrisisResponder.resistance_threshold(extreme, true) - 0.9) < 0.000001,
		"upper clamp at 0.9")


func test_evaluate_disposition_shifts_both_ways() -> void:
	var fx := _make_ruler_with_domain("shift")
	var attacker := _make_attacker_army(10.0)
	_add_garrison(fx.ruler_id, fx.domain_id, 3.0)
	# 3 BR vs threshold 5.0 -> the placeholder declines...
	var plain: Dictionary = ExtractionResistanceHeuristic.evaluate(
		fx.domain_id, attacker, 100)
	check(not bool(plain.get("will_resist", true)),
		"placeholder declines at 30% of attacker BR")
	# ...but the aggressive baron (threshold ~0.273 -> 2.73 BR) resists.
	var aggressive: Dictionary = ExtractionResistanceHeuristic.evaluate(
		fx.domain_id, attacker, 100, null, {"disposition": _baron_disposition(7, 4)})
	check(bool(aggressive.get("will_resist", false)),
		"aggressive baron resists from 30%% of attacker BR (threshold %0.3f)"
			% float(aggressive.get("threshold_ratio", 0.0)))
	# Cautious shifts the other way: 5 BR meets the placeholder but not the
	# cautious bar (~0.523 -> 5.23 BR).
	_add_garrison(fx.ruler_id, fx.domain_id, 2.0)  # total 5.0
	var at_half: Dictionary = ExtractionResistanceHeuristic.evaluate(
		fx.domain_id, attacker, 100)
	check(bool(at_half.get("will_resist", false)), "placeholder resists at exactly 50%")
	var cautious: Dictionary = ExtractionResistanceHeuristic.evaluate(
		fx.domain_id, attacker, 100, null, {"disposition": _baron_disposition(7, 6)})
	check(not bool(cautious.get("will_resist", true)),
		"cautious baron declines at 50%% of attacker BR (threshold %0.3f)"
			% float(cautious.get("threshold_ratio", 0.0)))


func test_defensive_resistance_handler() -> void:
	var fx := _make_ruler_with_domain("handler")
	var attacker := _make_attacker_army(4.0)
	_add_garrison(fx.ruler_id, fx.domain_id, 3.0)
	RulerDispositionRepository.save_disposition(
		_campaign_id, fx.ruler_id, _baron_disposition(7, 4))
	var result: Dictionary = DefensiveResistanceHandler.on_complete({
		"character_id": fx.ruler_id,
		"params_json": JSON.stringify({"attacker_army_id": attacker}),
	}, null)
	check(result.has("will_resist"), "handler returns the §7.3 decision")
	check(bool(result.get("will_resist", false)),
		"3 BR vs 4 BR attacker resists under the aggressive baron")
	check((result.get("evaluation", {}) as Dictionary).has("threshold_ratio"),
		"evaluation carries the modulated ratio")
	# No attacker identified -> blocked, no crash.
	var bare: Dictionary = DefensiveResistanceHandler.on_complete(
		{"character_id": fx.ruler_id}, null)
	check(String(bare.get("blocked_reason", "")) == "no_attacker_army",
		"bare call blocks with no_attacker_army")


# ---------------------------------------------------------------------------
# §7.1/§7.2/§7.4 biases + threat detection
# ---------------------------------------------------------------------------

func test_posture_biases_table() -> void:
	var active_threat := {"threat_present": true}
	var aggressive := RulerCrisisResponder.posture_biases("aggressive", active_threat)
	check(absf(float(aggressive.get("defensive_resistance", 0.0)) - 1.5) < 0.0001,
		"aggressive biases resistance")
	check(absf(float(aggressive.get("call_to_arms", 0.0)) - 1.5) < 0.0001,
		"aggressive biases call to arms")
	var cautious := RulerCrisisResponder.posture_biases("cautious", active_threat)
	check(cautious.has("hold") and cautious.has("raise_garrison"),
		"cautious hoards and over-prepares")
	var diplomatic := RulerCrisisResponder.posture_biases("diplomatic", active_threat)
	check(JSON.stringify(diplomatic) == JSON.stringify(cautious),
		"diplomatic degrades to cautious (§7.1)")
	# §7.2 accumulating challenger -> stability bias even without an active foe.
	var accumulating := RulerCrisisResponder.posture_biases(
		"defensive", {"challenger_accumulating": true})
	check(accumulating.has("administer_domain") and accumulating.has("issue_decree|tax"),
		"accumulating challenger biases stability actions")
	# An emerged challenger with NO army is stability pressure too (§7.2 keys
	# defensive routing on "materialized AS AN ARMY").
	var unfielded := RulerCrisisResponder.posture_biases(
		"defensive", {"challenger_materialized": true, "hostile_army": false})
	check(unfielded.has("administer_domain"),
		"emerged-but-unfielded challenger biases stability, not defense")
	var collapsing := RulerCrisisResponder.posture_biases(
		"defensive", {"morale_collapse": true})
	check(collapsing.has("administer_domain"), "morale collapse biases stability")
	# §7.4 ruin urgency by posture.
	var hard := RulerCrisisResponder.posture_biases(
		"defensive", {"ruined_stronghold": true})
	var soft := RulerCrisisResponder.posture_biases(
		"cautious", {"ruined_stronghold": true})
	check(float(hard.get("manage_stronghold", 0.0)) > float(soft.get("manage_stronghold", 0.0)),
		"aggressive/defensive rebuild harder than cautious")
	check(RulerCrisisResponder.posture_biases("defensive", {}).is_empty(),
		"no threats -> no biases")


func test_scorer_consumes_crisis_biases() -> void:
	var d := _baron_disposition()
	var rng := RulerActionScorer.monthly_rng("crisis", 7)
	var hold := [{"action_id": "hold", "base_value": 0.10,
		"weight_key": "", "crisis_modulated": false, "params": {}}]
	var plain := RulerActionScorer.score_candidates(hold, d, {}, rng)
	var biased := RulerActionScorer.score_candidates(
		hold, d, {"crisis_biases": {"hold": 1.5}}, rng)
	_approx(float((biased[0] as Dictionary).get("utility", 0.0))
		/ float((plain[0] as Dictionary).get("utility", 1.0)), 1.5,
		"crisis bias applies to hold's flat floor")
	var resist := [{"action_id": "defensive_resistance", "base_value": 0.50,
		"weight_key": "military_weight", "crisis_modulated": true, "params": {}}]
	var r_plain := RulerActionScorer.score_candidates(resist, d, {"morale": 0}, rng)
	var r_biased := RulerActionScorer.score_candidates(
		resist, d, {"morale": 0, "crisis_biases": {"defensive_resistance": 1.5}}, rng)
	_approx(float((r_biased[0] as Dictionary).get("utility", 0.0))
		/ float((r_plain[0] as Dictionary).get("utility", 1.0)), 1.5,
		"crisis bias multiplies scored utility")


func test_detect_threats() -> void:
	var fx := _make_ruler_with_domain("threats")
	var domain: Dictionary = CampaignRepository.get_domain(fx.domain_id)
	var calm := RulerCrisisResponder.detect_threats(domain, {})
	check(not bool(calm.get("threat_present", true)), "calm domain has no threats")
	# Accumulating challenger via the month result.
	var accumulating := RulerCrisisResponder.detect_threats(
		domain, {"challenger_summary": {"action": "accumulated"}})
	check(bool(accumulating.get("challenger_accumulating", false)),
		"accumulation detected from the month result")
	check(not bool(accumulating.get("threat_present", true)),
		"an accumulator is not yet an active foe")
	# Emerged challenger WITHOUT an army: stability pressure, NOT an active
	# foe (§7.2 keys defensive routing on "materialized as an army" — a bare
	# threat row must never top-score an undispatchable defensive_resistance).
	var threat_id: String = DomainThreatRepository.create_threat({
		"campaign_id": _campaign_id, "domain_id": fx.domain_id,
		"kind": "npc_challenger", "status": "active",
		"challenger_character_id": fx.ruler_id, "challenger_level": 5,
		"reaction": "hostile", "spawned_calendar_day": 1,
	})
	check(not threat_id.is_empty(), "challenger threat fixture created")
	var unfielded := RulerCrisisResponder.detect_threats(domain, {})
	check(bool(unfielded.get("challenger_materialized", false)),
		"emerged challenger detected")
	check(not bool(unfielded.get("hostile_army", true)), "no army linked yet")
	check(not bool(unfielded.get("threat_present", true)),
		"an unfielded challenger is not an active foe")
	# Fielded as an army (the Phase-9B materialization) -> active foe.
	CampaignRepository.db.query_with_bindings(
		"UPDATE domain_threats SET linked_army_id = 'army_x' WHERE id = ?", [threat_id])
	var hostile := RulerCrisisResponder.detect_threats(domain, {})
	check(bool(hostile.get("hostile_army", false)), "linked army detected")
	check(String(hostile.get("hostile_army_id", "")) == "army_x", "army id surfaced")
	check(bool(hostile.get("threat_present", false)), "fielded challenger is present")
	# Besieged via a non-concluded siege row; the besieging army becomes the
	# resistance decision's attacker when no threat row supplied one.
	var siege_fx := _make_ruler_with_domain("siegetgt")
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO sieges (id, campaign_id, stronghold_id, domain_id,
			besieging_army_id, starting_shp, current_shp, unit_capacity,
			stored_supplies_cp, started_calendar_day)
		VALUES (?, ?, 'sh_x', ?, 'siege_army_y', 100, 100, 10, 0, 1)
	""", [CampaignRepository.generate_id(), _campaign_id, siege_fx.domain_id])
	var besieged := RulerCrisisResponder.detect_threats(
		CampaignRepository.get_domain(siege_fx.domain_id), {})
	check(bool(besieged.get("besieged", false)), "active siege detected")
	check(String(besieged.get("hostile_army_id", "")) == "siege_army_y",
		"the besieging army is threaded as the resistance target")
	check(bool(besieged.get("threat_present", false)), "a siege is an active foe")


func test_ruined_stronghold_prioritized() -> void:
	# §7.4 + §6.2: a ruined domain's manage_stronghold (x3.0 scorer, x2.0
	# hard-posture bias) outranks everything for the defensive baron
	# (stress 5 / self-interest 6 -> "defensive" per §8.4).
	var d := _baron_disposition(5, 6)
	check(d.crisis_response == "defensive", "baron variant is defensive")
	var threats := {"ruined_stronghold": true, "threat_present": false}
	var ctx := {
		"morale": 0, "treasury_cp": 100000, "monthly_expenses_cp": 10000,
		"stronghold_ruined": true, "stronghold_below_minimum": true,
		"crisis_biases": RulerCrisisResponder.posture_biases(d.crisis_response, threats),
	}
	var candidates := [
		{"action_id": "manage_stronghold", "base_value": 0.45,
			"weight_key": "fortification_weight", "crisis_modulated": false, "params": {}},
		{"action_id": "administer_domain", "base_value": 0.45,
			"weight_key": "economic_weight", "crisis_modulated": false, "params": {}},
		{"action_id": "hold", "base_value": 0.10,
			"weight_key": "", "crisis_modulated": false, "params": {}},
	]
	var scored := RulerActionScorer.score_candidates(
		candidates, d, ctx, RulerActionScorer.monthly_rng("ruin", 9))
	check(String((scored[0] as Dictionary).get("action_id", "")) == "manage_stronghold",
		"ruined domain prioritizes the rebuild (got %s)"
			% String((scored[0] as Dictionary).get("action_id", "")))


# ---------------------------------------------------------------------------
# §8 Regional LOD
# ---------------------------------------------------------------------------

func test_lod_geometry_and_tier_gate() -> void:
	var camp := CampaignRepository.create_campaign("LOD Geometry", "World")
	var save := _campaign_id
	_campaign_id = camp
	var map_id := _region_map(camp)
	var on_map_full := _make_ruler_with_domain("lod_full", {"location_map_id": map_id})
	var on_map_named := _make_ruler_with_domain("lod_named",
		{"location_map_id": map_id, "persistence_tier": "named"})
	var abstract_full := _make_ruler_with_domain("lod_abstract")
	var on_map_pc := _make_ruler_with_domain("lod_pc",
		{"location_map_id": map_id, "character_type": "pc"})
	_campaign_id = save

	var active := RulerLodManager.active_set(camp)
	check(active.has(on_map_full.ruler_id), "full-tier ruler on the play map is active")
	check(not active.has(on_map_named.ruler_id),
		"materialization safety: a named-tier ruler in the window is NEVER promoted (§8.1)")
	check(not active.has(abstract_full.ruler_id),
		"abstract (off-window) domain stays backdrop when a play map exists")
	check(not active.has(on_map_pc.ruler_id), "the PC is never in the active set")
	# The conflict hook widens the set but keeps the tier gate.
	var with_extra := RulerLodManager.active_set(
		camp, [abstract_full.ruler_id, on_map_named.ruler_id])
	check(with_extra.has(abstract_full.ruler_id),
		"conflict-involved full-tier ruler joins the active set")
	check(not with_extra.has(on_map_named.ruler_id),
		"the conflict hook cannot bypass the full-tier gate")


func test_lod_fixture_fallback() -> void:
	var camp := CampaignRepository.create_campaign("LOD Fixture Fallback", "World")
	var save := _campaign_id
	_campaign_id = camp
	var abstract_full := _make_ruler_with_domain("fb_full")
	var abstract_named := _make_ruler_with_domain("fb_named", {"persistence_tier": "named"})
	_campaign_id = save
	var active := RulerLodManager.active_set(camp)
	check(active.has(abstract_full.ruler_id),
		"no play map -> fixture fallback keeps full-tier rulers active")
	check(not active.has(abstract_named.ruler_id),
		"fixture fallback still gates on full tier")


func test_lod_sync_signals_and_lazy_disposition() -> void:
	var camp := CampaignRepository.create_campaign("LOD Sync", "World")
	var save := _campaign_id
	_campaign_id = camp
	var fx := _make_ruler_with_domain("sync_full")
	_campaign_id = save
	RulerLodManager.clear_cache()

	var activated: Array = []
	var deactivated: Array = []
	var on_up := func(rid: String) -> void: activated.append(rid)
	var on_down := func(rid: String) -> void: deactivated.append(rid)
	EventBus.ruler_activated_for_lod.connect(on_up)
	EventBus.ruler_deactivated_for_lod.connect(on_down)

	var first := RulerLodManager.sync(camp)
	check((first.get("promoted", []) as Array).has(fx.ruler_id), "first sync promotes")
	check(activated.has(fx.ruler_id), "ruler_activated_for_lod emitted")
	check(RulerDispositionRepository.has_disposition(fx.ruler_id),
		"disposition lazily built on promotion (§8.2)")
	var second := RulerLodManager.sync(camp)
	check((second.get("promoted", []) as Array).is_empty()
			and (second.get("demoted", []) as Array).is_empty(),
		"steady-state sync emits nothing")
	# Demote by re-tiering the ruler (e.g. a future demotion pass); a supplied
	# scheduler gets the defensive strategic-turn cancellation (§8.2).
	CampaignRepository.db.query_with_bindings(
		"UPDATE characters SET persistence_tier = 'named' WHERE id = ?", [fx.ruler_id])
	var fake_scheduler := FakeScheduler.new()
	var third := RulerLodManager.sync(camp, fake_scheduler)
	check((third.get("demoted", []) as Array).has(fx.ruler_id), "tier loss demotes")
	check(deactivated.has(fx.ruler_id), "ruler_deactivated_for_lod emitted")
	check(fake_scheduler.cancelled.has(fx.ruler_id + "|" + RulerLodManager.STRATEGIC_TURN_EVENT),
		"demotion cancels the ruler's strategic-turn events")

	EventBus.ruler_activated_for_lod.disconnect(on_up)
	EventBus.ruler_deactivated_for_lod.disconnect(on_down)


## Captures cancel_all_for_owner calls for the demotion test.
class FakeScheduler:
	var cancelled: Array = []
	func cancel_all_for_owner(owner_id: String, event_type: String = "") -> int:
		cancelled.append(owner_id + "|" + event_type)
		return 0


func _approx(actual: float, expected: float, label: String, tol: float = 0.0005) -> void:
	check(absf(actual - expected) < tol,
		"%s: expected %f got %f" % [label, expected, actual])
