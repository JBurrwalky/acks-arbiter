extends "res://tests/test_suite_base.gd"

## Army-warfare Phase B (handoff §4) — RAW requisition/loot extraction (gdd-army-warfare.md
## §4.3; daw_campaigning_armies.xml §requisition_and_looting L324-347). Golden tests for
## ExtractionResolver, the marching-extraction rewrite (army_marcher), the movement-halving
## fix, and the encamped requisition_leg save/load survival.

const MAP_ID := "test_extract_map_1"

var _campaign_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_requisition_yields_40_per_family_and_stamps_cooldown()
	test_second_requisition_rejected_within_cooldown()
	test_loot_ceiling_and_full_family_loss()
	test_loot_partial_family_loss_floor_and_pro_rate()
	test_ceiling_resets_after_six_months()
	test_marching_pro_rate_loot_across_two_domains()
	test_marching_requisition_skips_enemy_domain()
	test_extraction_leg_halves_movement()
	test_resolve_without_supply_row_charges_nothing()
	test_preview_cooldown_consistent_after_period_expiry()
	test_encamped_requisition_leg_survives_save_load()
	if not has_failures():
		print("ExtractionResolver: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("Extraction Test", "World")


func _make_character(cname: String, ctype: String = "npc") -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, ?, ?, 'full', 'human', 'fighter', 9, 14, 12, 12, 12, 12, 14, 60, 60)
	""", [id, _campaign_id, cname, ctype])
	return id


func _make_domain(owner_id: String, families: int, q: int = 0, r: int = 0) -> String:
	var did := CampaignRepository.create_domain({
		"campaign_id": _campaign_id, "name": "Domain %s" % owner_id.substr(0, 4),
		"owner_character_id": owner_id, "location_map_id": MAP_ID,
		"location_hex_q": q, "location_hex_r": r, "territory_type": "civilized",
	})
	CampaignRepository.update_domain_monthly_state(did, {"peasant_families": families})
	# A domain_hex so ExtractionResolver.domain_for_hex resolves the owner at (q,r).
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO domain_hexes (id, domain_id, map_id, hex_q, hex_r, land_value, families)
		VALUES (?, ?, ?, ?, ?, 5, 0)
	""", [CampaignRepository.generate_id(), did, MAP_ID, q, r])
	return did


func _make_army(owner_id: String, q: int = 0, r: int = 0, state: String = "encamped") -> String:
	var aid := ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": "Host",
		"political_owner_id": owner_id, "command_character_id": owner_id,
		"state": state, "map_id": MAP_ID, "hex_q": q, "hex_r": r, "unit_scale": "company",
	})
	ArmyRepository.create_supply_state({
		"army_id": aid, "current_stockpile_cp": 0, "weekly_supply_cost_cp": 0})
	var leader := ArmyRepository.create_officer({
		"army_id": aid, "character_id": owner_id, "rank": "army_leader",
		"appointed_calendar_day": 0})
	for i in range(3):
		var unit := TroopUnitRepository.create_unit({
			"campaign_id": _campaign_id, "owner_character_id": owner_id,
			"source_type": "mercenary", "troop_type": "Heavy Infantry",
			"count": 30, "starting_count": 30, "battle_rating": 1.0, "monthly_wage_cp": 600})
		ArmyRepository.create_assignment({
			"army_id": aid, "troop_unit_id": unit, "parent_officer_id": leader,
			"role": "line", "assigned_calendar_day": 0})
	return aid


func _stockpile(army_id: String) -> int:
	return int(ArmyRepository.get_supply_state(army_id).get("current_stockpile_cp", 0))


func _families(domain_id: String) -> int:
	return int(CampaignRepository.get_domain(domain_id).get("peasant_families", 0))


# ---------------------------------------------------------------------------

func test_requisition_yields_40_per_family_and_stamps_cooldown() -> void:
	var lord := _make_character("Lord")
	var domain := _make_domain(lord, 100)
	var army := _make_army(lord)
	var res := ExtractionResolver.resolve(army, domain, "requisition", 100)
	check(bool(res.get("success", false)), "requisition succeeds")
	check(int(res.get("gp_yield_cp", 0)) == 400000,
		"40 gp/family × 100 × 100 = 400000 cp (4000 gp); got %d" % int(res.get("gp_yield_cp", 0)))
	check(_stockpile(army) == 400000, "army stockpile credited 400000 cp")
	check(int(res.get("families_lost", 0)) == 0, "requisition loses no families")
	check(_families(domain) == 100, "domain families unchanged by requisition")


func test_second_requisition_rejected_within_cooldown() -> void:
	var lord := _make_character("Lord2")
	var domain := _make_domain(lord, 100)
	var army := _make_army(lord)
	ExtractionResolver.resolve(army, domain, "requisition", 100)
	var res2 := ExtractionResolver.resolve(army, domain, "requisition", 130)   # +30 days (< 180)
	check(not bool(res2.get("success", true)), "2nd requisition within 6 months rejected")
	check(String(res2.get("error", "")) == "requisition_cooldown", "error is requisition_cooldown")


func test_loot_ceiling_and_full_family_loss() -> void:
	var lord := _make_character("Lord3")
	var domain := _make_domain(lord, 100)
	var army := _make_army(lord)
	ExtractionResolver.resolve(army, domain, "requisition", 100)     # cumulative 40 gp/family
	var loot := ExtractionResolver.resolve(army, domain, "loot", 100)
	check(bool(loot.get("success", false)), "loot succeeds after requisition")
	check(is_equal_approx(float(loot.get("gp_per_family", 0.0)), 20.0),
		"loot capped at 20 gp/family (60-40 headroom)")
	check(int(loot.get("gp_yield_cp", 0)) == 200000, "20 × 100 × 100 = 200000 cp")
	check(int(loot.get("families_lost", 0)) == 100, "2000 gp / 20 = 100 families lost (all)")
	check(_families(domain) == 0, "domain reduced to zero families")
	var over := ExtractionResolver.resolve(army, domain, "loot", 100)
	check(not bool(over.get("success", true)), "extraction blocked at the 60 gp/family ceiling")
	check(String(over.get("error", "")) == "ceiling_reached", "error is ceiling_reached")


func test_loot_partial_family_loss_floor_and_pro_rate() -> void:
	var lord := _make_character("Lord4")
	var domain := _make_domain(lord, 101)
	var army := _make_army(lord)
	# pro_rate_divisor 2 → 10 gp/family; 10 × 101 = 1010 gp; floor(1010/20) = 50 families.
	var res := ExtractionResolver.resolve(army, domain, "loot", 100, 2)
	check(is_equal_approx(float(res.get("gp_per_family", 0.0)), 10.0), "pro-rated loot 20/2 = 10 gp/family")
	check(int(res.get("gp_yield_cp", 0)) == 101000, "10 × 101 × 100 = 101000 cp")
	check(int(res.get("families_lost", 0)) == 50,
		"floor(1010/20) = 50 (a partial 20gp doesn't cost a family)")
	check(_families(domain) == 51, "101 - 50 = 51 families remain")


func test_ceiling_resets_after_six_months() -> void:
	var lord := _make_character("Lord5")
	var domain := _make_domain(lord, 100)
	var army := _make_army(lord)
	check(bool(ExtractionResolver.resolve(army, domain, "requisition", 0).get("success", false)),
		"day 0 requisition")
	check(not bool(ExtractionResolver.resolve(army, domain, "requisition", 100).get("success", true)),
		"day 100 requisition still on cooldown")
	var reset := ExtractionResolver.resolve(army, domain, "requisition", 200)   # >= 180 → period reset
	check(bool(reset.get("success", false)), "day 200 requisition allowed (6-month reset)")
	check(int(reset.get("gp_yield_cp", 0)) == 400000, "fresh period yields full 40/family")


func test_marching_pro_rate_loot_across_two_domains() -> void:
	var pc := _make_character("Reaver", "pc")
	var a_owner := _make_character("VictimA")
	var b_owner := _make_character("VictimB")
	var domain_a := _make_domain(a_owner, 100, 5, 5)
	var domain_b := _make_domain(b_owner, 60, 6, 5)
	var army := _make_army(pc, 5, 5)
	var marcher := ArmyMarcher.new()
	var ev := ScheduledEvent.create(0, "army_travel_leg", army, {
		"army_id": army, "from_hex_q": 5, "from_hex_r": 5,
		"to_hex_q": 6, "to_hex_r": 5, "map_id": MAP_ID, "extraction_mode": "loot",
	}, ScheduledEvent.PRIORITY_ARRIVAL)
	marcher._handle_army_travel_leg(ev)
	# Loot pro-rated 20/2 = 10 gp/family; A: 10×100×100=100000, B: 10×60×100=60000; total 160000.
	check(_stockpile(army) == 160000,
		"loot pro-rated A(100)+B(60) at 10/family = 160000 cp; got %d" % _stockpile(army))
	check(_families(domain_a) == 50, "A loses floor(1000/20)=50 families")
	check(_families(domain_b) == 30, "B loses floor(600/20)=30 families")


func test_marching_requisition_skips_enemy_domain() -> void:
	var pc := _make_character("Marcher", "pc")
	var enemy := _make_character("Foe")
	var enemy_domain := _make_domain(enemy, 100, 9, 9)
	var army := _make_army(pc, 9, 9)
	var marcher := ArmyMarcher.new()
	var ev := ScheduledEvent.create(0, "army_travel_leg", army, {
		"army_id": army, "from_hex_q": 9, "from_hex_r": 9,
		"to_hex_q": 9, "to_hex_r": 9, "map_id": MAP_ID, "extraction_mode": "requisition",
	}, ScheduledEvent.PRIORITY_ARRIVAL)
	marcher._handle_army_travel_leg(ev)
	check(_stockpile(army) == 0, "requisition skips enemy (non-friendly) territory — no yield")
	check(_families(enemy_domain) == 100, "enemy domain untouched by the skipped requisition")


func test_extraction_leg_halves_movement() -> void:
	var lord := _make_character("Slow")
	var _domain := _make_domain(lord, 50, 3, 3)
	var army := _make_army(lord, 3, 3)   # has units, so daily_miles is a real value
	var marcher := ArmyMarcher.new()
	var normal := marcher.compute_army_daily_miles(army, "normal", "none")
	var extracting := marcher.compute_army_daily_miles(army, "normal", "requisition")
	check(normal >= 2, "baseline daily miles is measurable (got %d)" % normal)
	check(extracting < normal,
		"extraction_mode halves movement (was a no-op before Phase B): normal=%d extracting=%d" % [normal, extracting])


func test_resolve_without_supply_row_charges_nothing() -> void:
	# Review finding: a supply-less army (bandit/challenger pattern, created via create_army
	# with no supply-state row) must NOT charge the domain for a yield it can't be credited.
	var lord := _make_character("PoorLord")
	var domain := _make_domain(lord, 100)
	var army := ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": "Supply-less Host",
		"political_owner_id": lord, "command_character_id": lord,
		"state": "encamped", "map_id": MAP_ID, "hex_q": 0, "hex_r": 0})
	var res := ExtractionResolver.resolve(army, domain, "loot", 100)
	check(not bool(res.get("success", true)), "resolve fails when the army has no supply-state row")
	check(String(res.get("error", "")) == "no_supply_state", "error is no_supply_state")
	check(_families(domain) == 100, "domain NOT charged (no family loss) when the yield can't land")
	# Ledger untouched → a properly-supplied army still gets the full requisition.
	var army2 := _make_army(lord)
	var res2 := ExtractionResolver.resolve(army2, domain, "requisition", 100)
	check(bool(res2.get("success", false)) and int(res2.get("gp_yield_cp", 0)) == 400000,
		"ledger untouched: a supplied army still gets the full requisition after")


func test_preview_cooldown_consistent_after_period_expiry() -> void:
	# Review finding: preview must honor the requisition cooldown even when the (independent)
	# ceiling period has expired — otherwise the menu enables an order resolve() then rejects.
	var lord := _make_character("CooldownLord")
	var domain := _make_domain(lord, 100)
	var army := _make_army(lord)
	ExtractionResolver.resolve(army, domain, "loot", 0)            # anchor=0, last_req=-1
	ExtractionResolver.resolve(army, domain, "requisition", 100)   # last_req=100, anchor still 0
	# Day 185: ceiling period expired (185-0>=180) but requisition cooldown NOT (185-100<180).
	var p := ExtractionResolver.preview(domain, "requisition", 185)
	check(not bool(p.get("eligible", true)),
		"preview honors the requisition cooldown even after the ceiling period expires")
	check(String(p.get("reason", "")) == "requisition_cooldown", "preview reason is requisition_cooldown")
	var r := ExtractionResolver.resolve(army, domain, "requisition", 185)
	check(not bool(r.get("success", true)) and String(r.get("error", "")) == "requisition_cooldown",
		"resolve agrees with preview: still on requisition cooldown at day 185")


func test_encamped_requisition_leg_survives_save_load() -> void:
	var lord := _make_character("EncampLord")
	var domain := _make_domain(lord, 100, 8, 8)
	var army := _make_army(lord, 8, 8, "encamped")
	var es := ExtractionScheduler.new()
	var sched := EventScheduler.new()
	var begin := es.begin_requisition(army, 0, sched)
	check(bool(begin.get("success", false)), "begin_requisition schedules the leg")
	check(String(ArmyRepository.get_army(army).get("state", "")) == "requisitioning",
		"army state -> requisitioning during the leg")
	# Round-trip the scheduler (save/load mid-leg).
	var sched2 := EventScheduler.new()
	sched2.load_from_dicts(sched.to_dicts())
	check(sched2.has_event_for_owner(army, ExtractionScheduler.EVENT_REQUISITION_LEG),
		"requisition_leg survives save/load")
	var leg: ScheduledEvent = null
	for e in sched2.get_events_for_owner(army):
		if e.event_type == ExtractionScheduler.EVENT_REQUISITION_LEG:
			leg = e
	check(leg != null, "restored leg present")
	if leg != null:
		es._handle_requisition_leg(leg)
	check(String(ArmyRepository.get_army(army).get("state", "")) == "encamped",
		"state -> encamped on leg completion")
	check(_stockpile(army) == 400000, "requisition credited on leg completion (100 × 40)")
	var _unused := domain
