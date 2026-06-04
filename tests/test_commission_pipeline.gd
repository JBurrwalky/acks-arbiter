extends "res://tests/test_suite_base.gd"

## Unit tests for CommissionPipeline (Domain Phase 1).
##
## Verifies the start_commission validation, the advance_commissions daily
## crossing logic (halfway / completed), and pause behavior on engineer
## shortfall. Uses CampaignRepository directly to insert / read commission
## rows.


var _campaign_id: String = ""


func run_all_tests() -> void:
	_setup_campaign()
	test_start_commission_inserts_rows_and_emits_signal()
	test_start_commission_rejects_on_engineer_shortage()
	test_start_commission_rejects_on_explorer_in_civilized()
	test_start_commission_rejects_syndicate_class()
	test_start_commission_rejects_venturer_class()
	test_advance_commission_progresses_gp()
	test_advance_commission_fires_halfway_signal()
	test_advance_commission_fires_completed_signal()
	test_advance_commission_idempotent_on_completed()
	test_recheck_engineer_requirement_pauses()
	if not has_failures():
		print("CommissionPipeline: all tests passed.")


# ----- Setup -----

func _setup_campaign() -> void:
	# Reseed the RNG so generate_id() doesn't collide with campaign IDs from
	# prior test runs (the campaign.db persists across runs in user://).
	randomize()
	_campaign_id = CampaignRepository.create_campaign(
		"Test Commission Pipeline", "TestWorld")
	check(not _campaign_id.is_empty(), "campaign created")


func _make_test_domain() -> String:
	return CampaignRepository.create_domain({
		"campaign_id": _campaign_id,
		"name": "TestDomain",
		"territory_type": "wilderness",
	})


func _baseline_stronghold_data(domain_id: String) -> Dictionary:
	return {
		"domain_id": domain_id,
		"owner_character_id": null,
		"archetype": "fortress",
		"archetype_power_id": "stronghold_castle",
		"structure_type": "keep",
		"engineers_assigned": 1,
		"location_map_id": null,
		"location_hex_q": 0,
		"location_hex_r": 0,
	}


func _baseline_cost_breakdown(gp_committed: int, daily_rate: int) -> Dictionary:
	return {
		"base_structure_cost": gp_committed,
		"accessory_cost": 0,
		"discounted_base_cost": gp_committed,
		"speed_tier_pct": 100,
		"speed_premium_gp": 0,
		"gp_committed": gp_committed,
		"daily_construction_rate_gp": daily_rate,
		"magic_rate_modifier_pct": 100,
		"engineers_required": maxi(1, int(ceil(float(gp_committed) / 100000.0))),
		"engineer_monthly_wage_cp": maxi(1, int(ceil(float(gp_committed) / 100000.0))) * 250,
		"estimated_duration_days": int(ceil(float(gp_committed) / float(daily_rate))),
		"class_cost_reduction_pct": 0,
	}


# ----- Start commission -----

func test_start_commission_inserts_rows_and_emits_signal() -> void:
	var domain_id := _make_test_domain()
	var sh_data := _baseline_stronghold_data(domain_id)
	var cost := _baseline_cost_breakdown(5000, 500)

	var signaled: Array[Array] = []
	var conn := func(stronghold_id: String, sig_domain: String, cp: int, expected_day: int):
		signaled.append([stronghold_id, sig_domain, cp, expected_day])
	EventBus.stronghold_commission_started.connect(conn)

	var result := CommissionPipeline.start_commission(sh_data, cost, 0)

	check(result["errors"].is_empty(),
		"no errors, got %s" % str(result["errors"]))
	check(not result["stronghold_id"].is_empty(), "stronghold inserted")
	check(not result["commission_id"].is_empty(), "commission inserted")
	check(result["expected_completion_day"] == 10,
		"5000gp / 500gp/day = 10 days, got %d" % result["expected_completion_day"])
	check(signaled.size() == 1, "stronghold_commission_started fired exactly once")
	if signaled.size() > 0:
		check(signaled[0][2] == 500000, "signal carries cp_committed = 500000 (5000 gp × 100)")
	EventBus.stronghold_commission_started.disconnect(conn)


func test_start_commission_rejects_on_engineer_shortage() -> void:
	var domain_id := _make_test_domain()
	var sh_data := _baseline_stronghold_data(domain_id)
	# 200,000 gp commitment requires 2 engineers; we only assign 1.
	sh_data["engineers_assigned"] = 1
	var cost := _baseline_cost_breakdown(200000, 500)
	cost["engineers_required"] = 2

	var result := CommissionPipeline.start_commission(sh_data, cost, 0)
	check(result["errors"].has("insufficient_engineers"),
		"errors contains insufficient_engineers, got %s" % str(result["errors"]))
	check(result["stronghold_id"].is_empty(), "no stronghold inserted on rejection")
	check(result["commission_id"].is_empty(), "no commission inserted on rejection")


func test_start_commission_rejects_on_explorer_in_civilized() -> void:
	var domain_id := _make_test_domain()
	var sh_data := _baseline_stronghold_data(domain_id)
	sh_data["archetype"] = "fortress"
	sh_data["archetype_power_id"] = "stronghold_border_fort"
	var cost := _baseline_cost_breakdown(5000, 500)

	var result := CommissionPipeline.start_commission(
		sh_data, cost, 0,
		"civilized", "human", false)
	check(result["errors"].has("explorer_borderlands_or_wilderness_only"),
		"explorer-in-civilized rejected, got %s" % str(result["errors"]))


func _create_thief() -> String:
	var id: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters
			(id, campaign_id, name, character_type, persistence_tier, race,
			 character_class, level, strength, intelligence, wisdom,
			 dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, ?, 'pc', 'full', 'human', 'thief', 9,
			10, 10, 10, 13, 10, 10, 20, 20)
	""", [id, _campaign_id, "Test Thief"])
	return id


func test_start_commission_rejects_syndicate_class() -> void:
	# Thief→Syndicate refactor: a thief owner cannot commission a domain-securing
	# stronghold. The guard resolves the owner's class from owner_character_id.
	var domain_id := _make_test_domain()
	var thief_id := _create_thief()
	var sh_data := _baseline_stronghold_data(domain_id)
	sh_data["owner_character_id"] = thief_id
	var cost := _baseline_cost_breakdown(5000, 500)
	var result := CommissionPipeline.start_commission(sh_data, cost, 0)
	check(result["errors"].has("syndicate_class_cannot_build_stronghold"),
		"thief blocked from commissioning a stronghold, got %s" % str(result["errors"]))
	check(result["stronghold_id"].is_empty(),
		"no stronghold inserted for a blocked syndicate class")


func _create_venturer() -> String:
	var id: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters
			(id, campaign_id, name, character_type, persistence_tier, race,
			 character_class, level, strength, intelligence, wisdom,
			 dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, ?, 'pc', 'full', 'human', 'venturer', 9,
			10, 10, 10, 10, 10, 13, 20, 20)
	""", [id, _campaign_id, "Test Venturer"])
	return id


func test_start_commission_rejects_venturer_class() -> void:
	# Venturer→Guildhouse refactor: a venturer owner cannot commission a
	# domain-securing stronghold (their guildhouse is its own entity).
	var domain_id := _make_test_domain()
	var venturer_id := _create_venturer()
	var sh_data := _baseline_stronghold_data(domain_id)
	sh_data["owner_character_id"] = venturer_id
	var cost := _baseline_cost_breakdown(5000, 500)
	var result := CommissionPipeline.start_commission(sh_data, cost, 0)
	check(result["errors"].has("venturer_class_cannot_build_stronghold"),
		"venturer blocked from commissioning a stronghold, got %s" % str(result["errors"]))
	check(result["stronghold_id"].is_empty(),
		"no stronghold inserted for a blocked venturer")


# ----- Advance commission -----

func test_advance_commission_progresses_gp() -> void:
	var domain_id := _make_test_domain()
	var sh_data := _baseline_stronghold_data(domain_id)
	# 10,000 gp at 500 gp/day = 20 days. After 1 day: gp_progressed = 500.
	var cost := _baseline_cost_breakdown(10000, 500)
	var result := CommissionPipeline.start_commission(sh_data, cost, 0)
	var commission_id: String = result["commission_id"]

	CommissionPipeline.advance_commissions(1)
	var commission := CampaignRepository.get_commission(commission_id)
	check(int(commission.get("cp_progressed", 0)) == 50000,
		"after day 1: 50,000 cp progressed (500 gp × 100), got %d" % int(commission.get("cp_progressed", 0)))


func test_advance_commission_fires_halfway_signal() -> void:
	var domain_id := _make_test_domain()
	var sh_data := _baseline_stronghold_data(domain_id)
	# 1000 gp at 500 gp/day = 2 days. Halfway crossed on day 1 (500 gp).
	var cost := _baseline_cost_breakdown(1000, 500)
	var result := CommissionPipeline.start_commission(sh_data, cost, 0)
	var commission_id: String = result["commission_id"]

	var fired: Array[Array] = []
	var conn := func(stronghold_id: String, completion_pct: int, milestone: String):
		fired.append([stronghold_id, completion_pct, milestone])
	EventBus.stronghold_construction_progressed.connect(conn)

	# Day 1 (after one tick of 500 gp): we hit exactly 500 (halfway threshold
	# for a 1000 gp build), so halfway fires on day 1.
	CommissionPipeline.advance_commissions(1)
	var milestones: Array = []
	for f in fired:
		milestones.append(f[2])
	check(milestones.has("halfway"),
		"halfway milestone fired, got %s" % str(milestones))

	var commission := CampaignRepository.get_commission(commission_id)
	check(bool(commission.get("halfway_signal_fired", false)) == true,
		"halfway_signal_fired flag set")
	EventBus.stronghold_construction_progressed.disconnect(conn)


func test_advance_commission_fires_completed_signal() -> void:
	var domain_id := _make_test_domain()
	var sh_data := _baseline_stronghold_data(domain_id)
	# 500 gp at 500 gp/day = 1 day. Both halfway AND completed fire on day 1.
	var cost := _baseline_cost_breakdown(500, 500)
	var result := CommissionPipeline.start_commission(sh_data, cost, 0)
	var commission_id: String = result["commission_id"]
	var stronghold_id: String = result["stronghold_id"]

	var prog_fired: Array[String] = []
	var prog_conn := func(_sid: String, _pct: int, milestone: String):
		prog_fired.append(milestone)
	EventBus.stronghold_construction_progressed.connect(prog_conn)

	var completed_fired: Array[String] = []
	var completed_conn := func(sid: String):
		completed_fired.append(sid)
	EventBus.stronghold_completed.connect(completed_conn)

	# Day 1: 500 gp progressed = full commit → both milestones.
	CommissionPipeline.advance_commissions(1)
	check(prog_fired.has("halfway"), "halfway milestone fired")
	check(prog_fired.has("completed"), "completed milestone fired")
	check(completed_fired.has(stronghold_id),
		"stronghold_completed fired with the correct id")

	# Verify DB state.
	var commission := CampaignRepository.get_commission(commission_id)
	check(String(commission.get("status", "")) == "completed",
		"commission status = completed")
	check(int(commission.get("completed_calendar_day", -1)) == 1,
		"completed_calendar_day = 1")
	var stronghold := CampaignRepository.get_stronghold(stronghold_id)
	check(int(stronghold.get("completion_pct", 0)) == 100,
		"stronghold completion_pct = 100")
	check(String(stronghold.get("status", "")) == "completed",
		"stronghold status = completed")

	EventBus.stronghold_construction_progressed.disconnect(prog_conn)
	EventBus.stronghold_completed.disconnect(completed_conn)


func test_advance_commission_idempotent_on_completed() -> void:
	var domain_id := _make_test_domain()
	var sh_data := _baseline_stronghold_data(domain_id)
	var cost := _baseline_cost_breakdown(500, 500)
	var result := CommissionPipeline.start_commission(sh_data, cost, 0)
	var stronghold_id: String = result["stronghold_id"]

	# Day 1 — completes.
	CommissionPipeline.advance_commissions(1)

	# Filter to this test's stronghold so signals from leftover commissions
	# in the shared DB don't pollute the assertion.
	var fired: Array[Array] = []
	var conn := func(sid: String, pct: int, milestone: String):
		if sid == stronghold_id:
			fired.append([sid, pct, milestone])
	EventBus.stronghold_construction_progressed.connect(conn)

	# Day 2 — should NOT re-fire (commission no longer in_progress).
	CommissionPipeline.advance_commissions(2)
	check(fired.size() == 0,
		"no re-fire for THIS stronghold on day 2 (status=completed), got %d signals" % fired.size())

	EventBus.stronghold_construction_progressed.disconnect(conn)


# ----- Engineer shortfall pause -----

func test_recheck_engineer_requirement_pauses() -> void:
	var domain_id := _make_test_domain()
	var sh_data := _baseline_stronghold_data(domain_id)
	sh_data["engineers_assigned"] = 2  # required for 200k gp
	var cost := _baseline_cost_breakdown(200000, 500)
	cost["engineers_required"] = 2

	var result := CommissionPipeline.start_commission(sh_data, cost, 0)
	check(result["errors"].is_empty(),
		"start with 2 engineers OK, got %s" % str(result["errors"]))
	var commission_id: String = result["commission_id"]

	# Simulate one engineer leaving.
	CampaignRepository.update_commission(commission_id, {"engineers_assigned": 1})

	var paused := CommissionPipeline.recheck_engineer_requirement(commission_id)
	check(paused == true, "recheck pauses commission")
	var commission := CampaignRepository.get_commission(commission_id)
	check(String(commission.get("status", "")) == "paused_engineers",
		"status = paused_engineers, got %s" % str(commission.get("status", "")))
