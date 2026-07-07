extends "res://tests/test_suite_base.gd"

## Army-warfare Phase D (handoff §6) — the two remaining ruler-AI dispatch stubs made real:
## call_to_arms routes each vassal through FavorsDutiesResolver.trigger_call_to_arms into
## CallToArmsMuster (obligation + tranches + cumulative loyalty), and withstand_siege sets the
## defender posture on the active siege (the resolver's voluntary sally branch respects it) and
## holds the ruler's armies at the hex. Both return real dispatch dicts (dispatched:true).

const MAP_ID := "test_phase_d_map"

class FakeDice:
	extends RefCounted
	var fixed_total: int = 12
	func roll(_count: int, _sides: int) -> int:
		return fixed_total

var _campaign_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_call_to_arms_dispatches_and_musters_vassals()
	test_call_to_arms_schedules_three_tranches_per_vassal()
	test_call_to_arms_no_vassals_not_dispatched()
	test_call_to_arms_loyalty_fires_and_revolts_beyond_safe_total()
	test_withstand_siege_sets_hold_fast_posture()
	test_withstand_siege_no_siege_not_dispatched()
	test_hold_fast_posture_blocks_sally()
	test_besieged_ruler_routes_to_real_defensive_dispatch_end_to_end()
	if not has_failures():
		print("RulerDispatchPhaseD: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("Phase D Dispatch", "World")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _make_npc(cname: String) -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, ?, 'npc', 'full', 'human', 'fighter', 9, 14, 12, 12, 12, 12, 14, 60, 60)
	""", [id, _campaign_id, cname])
	return id


func _make_domain(owner_id: String, q: int, r: int) -> String:
	return CampaignRepository.create_domain({
		"campaign_id": _campaign_id, "name": "Domain %s" % owner_id.substr(0, 4),
		"owner_character_id": owner_id, "location_map_id": MAP_ID,
		"location_hex_q": q, "location_hex_r": r, "territory_type": "civilized",
	})


## A garrison ARMY owned by `owner_id` with `unit_count` units (assignment_kind='garrison',
## in the army via army_unit_assignments) — the representation CallToArmsMuster.
## compute_realm_garrison_unit_count counts (units in a garrison army, NOT loose
## troop_units.assignment_kind). A garrison_stronghold_id is set (the muster reads it).
func _make_garrison_army(owner_id: String, unit_count: int) -> String:
	var stronghold := _make_stronghold(owner_id)
	var army := ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": "Garrison of %s" % owner_id.substr(0, 4),
		"political_owner_id": owner_id, "command_character_id": owner_id,
		"state": "encamped", "garrison_stronghold_id": stronghold, "formed_calendar_day": 0})
	var officer := ArmyRepository.create_officer({
		"army_id": army, "character_id": owner_id, "rank": "army_leader", "appointed_calendar_day": 0})
	for _i in range(unit_count):
		var uid := TroopUnitRepository.create_unit({
			"campaign_id": _campaign_id, "owner_character_id": owner_id,
			"source_type": "conscript", "troop_type": "Light Infantry",
			"count": 30, "starting_count": 30, "battle_rating": 1.0, "monthly_wage_cp": 0})
		ArmyRepository.create_assignment({
			"army_id": army, "troop_unit_id": uid, "parent_officer_id": officer,
			"role": "line", "assigned_calendar_day": 0})
		CampaignRepository.db.query_with_bindings(
			"UPDATE troop_units SET assignment_kind = 'garrison' WHERE id = ?", [uid])
	return army


## A vassal of `liege_id` with a garrison army; returns the vassal_assignment row dict.
func _make_vassal(liege_id: String, garrison_units: int, is_henchman: bool = true,
		base_loyalty: int = 4, q: int = 0, r: int = 0) -> Dictionary:
	var vassal := _make_npc("Vassal %d" % garrison_units)
	var vdom := _make_domain(vassal, q, r)
	_make_garrison_army(vassal, garrison_units)
	var assn_id := VassalRepository.create_assignment({
		"campaign_id": _campaign_id, "liege_character_id": liege_id,
		"vassal_character_id": vassal, "vassal_domain_id": vdom,
		"assigned_calendar_day": 1, "is_henchman_vassal": is_henchman,
		"base_loyalty_modifier": base_loyalty})
	return VassalRepository.get_assignment(assn_id)


func _make_stronghold(owner_id: String) -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO strongholds (id, owner_character_id, structure_type, cp_value, shp,
			ac, garrison_capacity, completion_pct, status)
		VALUES (?, ?, 'keep', 500000, 500, 6, 0, 100, 'completed')
	""", [id, owner_id])
	return id


func _make_enemy_army(q: int, r: int) -> String:
	var enemy := _make_npc("Besieger")
	return ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": "Besieging Host",
		"political_owner_id": enemy, "command_character_id": enemy,
		"state": "besieging", "map_id": MAP_ID, "hex_q": q, "hex_r": r})


func _make_siege_on(domain_id: String, stronghold_id: String, q: int, r: int) -> String:
	return SiegeRepository.create_siege({
		"campaign_id": _campaign_id, "stronghold_id": stronghold_id, "domain_id": domain_id,
		"besieging_army_id": _make_enemy_army(q, r), "map_id": MAP_ID, "hex_q": q, "hex_r": r,
		"resolution_mode": "simplified", "current_phase": "blockade",
		"starting_shp": 500, "current_shp": 500, "unit_capacity": 4,
		"stored_supplies_cp": 60000, "started_calendar_day": 90, "simplified_total_days": 30})


func _count_call_to_arms_states() -> int:
	CampaignRepository.db.query("SELECT COUNT(*) AS n FROM call_to_arms_state")
	return int(CampaignRepository.db.query_result[0].get("n", 0))


func _count_tranche_events(sched: EventScheduler) -> int:
	var n := 0
	for e in sched.to_dicts():
		if String((e as Dictionary).get("event_type", "")) == "call_to_arms_tranche_arrival":
			n += 1
	return n


# ---------------------------------------------------------------------------
# call_to_arms
# ---------------------------------------------------------------------------

func test_call_to_arms_dispatches_and_musters_vassals() -> void:
	var ruler := _make_npc("CtaLord")
	var domain := _make_domain(ruler, 1, 1)
	_make_vassal(ruler, 3, true, 4, 2, 1)
	_make_vassal(ruler, 2, true, 4, 3, 1)
	var before := _count_call_to_arms_states()
	var out := RulerAI._execute(ruler, {"action_id": "call_to_arms", "params": {}}, domain, 100, EventScheduler.new())
	check(bool(out.get("dispatched", false)), "call_to_arms dispatches for real (dispatched:true)")
	check(int(out.get("vassals_called", 0)) == 2, "both vassals mustered; got %d" % int(out.get("vassals_called", 0)))
	check(_count_call_to_arms_states() - before == 2, "one call_to_arms_state row per vassal")
	check(not String(out.get("lord_army_id", "")).is_empty(), "the muster targets a lord army (merge point)")


func test_call_to_arms_schedules_three_tranches_per_vassal() -> void:
	var ruler := _make_npc("TrancheLord")
	var domain := _make_domain(ruler, 4, 4)
	_make_vassal(ruler, 3, true, 4, 5, 4)
	var sched := EventScheduler.new()
	RulerAI._execute(ruler, {"action_id": "call_to_arms", "params": {}}, domain, 100, sched)
	check(_count_tranche_events(sched) == 3,
		"3 tranche arrival events scheduled for the one vassal; got %d" % _count_tranche_events(sched))


func test_call_to_arms_no_vassals_not_dispatched() -> void:
	var ruler := _make_npc("LonelyLord")
	var domain := _make_domain(ruler, 6, 6)
	var out := RulerAI._execute(ruler, {"action_id": "call_to_arms", "params": {}}, domain, 100, null)
	check(not bool(out.get("dispatched", true)), "no vassals → not dispatched")
	check(String(out.get("blocked_reason", "")) == "no_vassals", "blocked_reason is no_vassals")


func test_call_to_arms_loyalty_fires_and_revolts_beyond_safe_total() -> void:
	# A NON-henchman vassal has NO free duty (RAW L395): the very first call_to_arms duty is
	# already beyond the safe total, so the cumulative loyalty check fires. A low base loyalty +
	# a low roll makes the vassal refuse (revolt) — deterministic via FakeDice on the public
	# trigger (the _execute path uses pseudo-random dice).
	var ruler := _make_npc("HarshLord")
	var _domain := _make_domain(ruler, 7, 7)
	var assn := _make_vassal(ruler, 2, false, -4, 8, 7)   # non-henchman, disloyal
	var dice := FakeDice.new()
	dice.fixed_total = 2   # 2 + base(-4) + penalty(-1) = -3 → refuse
	var res := FavorsDutiesResolver.trigger_call_to_arms(assn, 100, 50, null, dice, "")
	check(not String(res.get("loyalty_outcome", "")).is_empty(),
		"a loyalty check fired (non-henchman is over the safe total on the first duty)")
	check(bool(res.get("revolted", false)), "the disloyal vassal refused the call and revolted")
	check(not bool(res.get("success", true)), "a revolted vassal does not muster")


# ---------------------------------------------------------------------------
# withstand_siege
# ---------------------------------------------------------------------------

func test_withstand_siege_sets_hold_fast_posture() -> void:
	var ruler := _make_npc("HoldLord")
	var domain := _make_domain(ruler, 9, 9)
	var stronghold := _make_stronghold(ruler)
	var siege_id := _make_siege_on(domain, stronghold, 9, 9)
	var out := RulerAI._execute(ruler, {"action_id": "withstand_siege", "params": {}}, domain, 100, EventScheduler.new())
	check(bool(out.get("dispatched", false)), "withstand_siege dispatches for real")
	check(String(out.get("siege_id", "")) == siege_id, "the active siege was targeted")
	check(String(SiegeRepository.get_siege(siege_id).get("defender_posture", "")) == "hold_fast",
		"defender posture set to hold_fast on the siege row")
	# The siege itself is unchanged — still an active blockade.
	check(String(SiegeRepository.get_siege(siege_id).get("current_phase", "")) == "blockade",
		"the siege proceeds unchanged (still blockade)")


func test_withstand_siege_no_siege_not_dispatched() -> void:
	var ruler := _make_npc("CalmLord")
	var domain := _make_domain(ruler, 11, 11)
	var out := RulerAI._execute(ruler, {"action_id": "withstand_siege", "params": {}}, domain, 100, null)
	check(not bool(out.get("dispatched", true)), "no active siege → not dispatched")
	check(String(out.get("blocked_reason", "")) == "no_active_siege", "blocked_reason is no_active_siege")


func test_hold_fast_posture_blocks_sally() -> void:
	var ruler := _make_npc("WallLord")
	var domain := _make_domain(ruler, 13, 13)
	var stronghold := _make_stronghold(ruler)
	var siege_id := _make_siege_on(domain, stronghold, 13, 13)
	# Default 'undecided' does NOT posture-block a sally (existing behavior preserved).
	var res_default := SiegeResolver.apply_method(siege_id, "sally", {}, Callable())
	check(String(res_default.get("error", "")) != "defender_holding_fast",
		"an 'undecided' defender is not posture-blocked from sallying")
	# After withstand_siege commits the garrison, a sally is refused.
	SiegeRepository.update(siege_id, {"defender_posture": "hold_fast"})
	var res_hold := SiegeResolver.apply_method(siege_id, "sally", {}, Callable())
	check(not bool(res_hold.get("ok", true)), "a hold_fast defender cannot sally")
	check(String(res_hold.get("error", "")) == "defender_holding_fast", "sally blocked by the hold_fast posture")


# ---------------------------------------------------------------------------
# End-to-end pick under a fielded threat (a siege sets besieged + threat_present)
# ---------------------------------------------------------------------------

func test_besieged_ruler_routes_to_real_defensive_dispatch_end_to_end() -> void:
	var ruler := _make_npc("WarLord")
	var domain := _make_domain(ruler, 15, 15)
	_make_vassal(ruler, 3, true, 4, 16, 15)
	var stronghold := _make_stronghold(ruler)
	_make_siege_on(domain, stronghold, 15, 15)
	# A martial/defensive disposition so the crisis defensive actions top-score under the siege.
	RulerDispositionRepository.save_disposition(_campaign_id, ruler,
		StrategicDisposition.from_dict({"crisis_response": "defensive", "military_weight": 0.9}))
	var reports := RulerAI.process_campaign_month(_campaign_id, 100, [ruler], [], EventScheduler.new())
	var actions: Array = []
	for rep in reports:
		if String((rep as Dictionary).get("ruler_id", "")) == ruler:
			actions = (rep as Dictionary).get("actions", [])
	check(actions.size() > 0, "the besieged ruler takes at least one action")
	# The besieged ruler routes to a defensive action end-to-end. The two Phase-D actions carry
	# the {dispatched:true} contract (verify it when picked); defensive_resistance is the Phase-3
	# resistance-DECISION handler with a different outcome shape ({will_resist, evaluation}), so it
	# counts as defensive routing but is not asserted against the dispatched flag here.
	var routed_defensively := false
	for a in actions:
		var aid := String((a as Dictionary).get("action_id", ""))
		if aid in ["call_to_arms", "withstand_siege", "defensive_resistance"]:
			routed_defensively = true
		if aid == "call_to_arms" or aid == "withstand_siege":
			check(bool(((a as Dictionary).get("outcome", {}) as Dictionary).get("dispatched", false)),
				"%s dispatched:true end-to-end (Phase-D real dispatch)" % aid)
	check(routed_defensively, "a besieged ruler routes to a defensive action end-to-end")
	# ...and BOTH Phase-D actions are in the candidate pool the scorer picks from under the siege.
	var world_state := {"threat_present": true, "besieged": true, "extraction_underway": false}
	var candidate_ids: Array = []
	for c in RulerActionCatalog.available_for(
			CampaignRepository.get_character(ruler), CampaignRepository.get_domain(domain), world_state):
		candidate_ids.append(String((c as Dictionary).get("action_id", "")))
	check("call_to_arms" in candidate_ids, "call_to_arms is an available candidate under the siege")
	check("withstand_siege" in candidate_ids, "withstand_siege is an available candidate under the siege")
