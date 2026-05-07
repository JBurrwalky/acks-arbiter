extends "res://tests/test_suite_base.gd"

## Phase 1 acceptance test: end-to-end stronghold lifecycle from commission
## through completion to sufficiency-driven income-gate release.
##
## Verifies:
##   * Commission a 32,000 gp wilderness stronghold at 1 engineer + base speed
##     (500 gp/day) → expected_completion_day = started + 64 days.
##   * Daily ticks advance progress; halfway signal fires at day +32, completed
##     signal fires at day +64.
##   * stronghold_sufficiency_changed emits at completion (cache flip false→true).
##   * Cost-reduction path: cleric Fortified Church gets 50% off.
##   * Speed-tier path: 200 → 1000 gp/day.
##   * Claim path: claim a 22,500 gp ruin in a borderlands hex; sufficiency
##     flips on the same call.


var _campaign_id: String = ""


func run_all_tests() -> void:
	_setup_campaign()
	test_full_construction_lifecycle_wilderness()
	test_cleric_50pct_discount_reduces_duration()
	test_speed_tier_200_doubles_rate()
	test_claim_path_immediate_sufficiency()
	if not has_failures():
		print("StrongholdPhase1Integration: all tests passed.")


# ----- Setup -----

func _setup_campaign() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign(
		"Test Stronghold Phase 1 Integration", "TestWorld")
	check(not _campaign_id.is_empty(), "campaign created")
	StrongholdRepository._clear_sufficiency_cache_for_test()


func _make_test_domain(territory_type: String) -> String:
	return CampaignRepository.create_domain({
		"campaign_id": _campaign_id,
		"name": "TestDomain_%s" % territory_type,
		"territory_type": territory_type,
	})


# ----- Full lifecycle -----

func test_full_construction_lifecycle_wilderness() -> void:
	var domain_id := _make_test_domain("wilderness")
	StrongholdRepository._set_sufficiency_cache_for_test(domain_id, false)

	# Build the cost breakdown for a 32,000 gp wilderness stronghold at base
	# speed (500 gp/day) and 1 engineer.
	var preset := {"class_cost_reduction_pct": 0}
	var structures: Array = [{"gp_cost": 32000}]
	var cost := StrongholdCostCalculator.calculate_total_cost(preset, structures, [], 100, 100)
	check(cost["gp_committed"] == 32000, "gp_committed = 32,000")
	check(cost["daily_construction_rate_gp"] == 500, "rate = 500 gp/day")
	check(cost["estimated_duration_days"] == 64, "duration = 64 days")
	check(cost["engineers_required"] == 1, "1 engineer required")

	var sh_data := {
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
	var result := CommissionPipeline.start_commission(sh_data, cost, 0,
		"wilderness", "human", false)
	check(result["errors"].is_empty(),
		"commission started, got %s" % str(result["errors"]))
	check(result["expected_completion_day"] == 64,
		"expected_completion_day = 64")
	check(result["expected_halfway_day"] == 32,
		"expected_halfway_day = 32")
	var stronghold_id: String = result["stronghold_id"]

	# Track sufficiency signal — filter to this test's domain.
	var sufficiency_fired: Array[Array] = []
	var suff_conn := func(d_id: String, is_sufficient: bool, value_gp: int, minimum_gp: int):
		if d_id == domain_id:
			sufficiency_fired.append([d_id, is_sufficient, value_gp, minimum_gp])
	EventBus.stronghold_sufficiency_changed.connect(suff_conn)

	# Track milestones — filter to this test's stronghold so signals from
	# leftover commissions (from prior unit-test runs that left rows in the
	# shared DB) don't pollute the assertion set.
	var milestones: Array[String] = []
	var prog_conn := func(sid: String, _pct: int, milestone: String):
		if sid == stronghold_id:
			milestones.append(milestone)
	EventBus.stronghold_construction_progressed.connect(prog_conn)

	var completed: Array[String] = []
	var completed_conn := func(sid: String):
		if sid == stronghold_id:
			completed.append(sid)
	EventBus.stronghold_completed.connect(completed_conn)

	# Tick 64 days.
	for day in range(1, 65):
		CommissionPipeline.advance_commissions(day)

	check(milestones.has("halfway"), "halfway milestone fired during run")
	check(milestones.has("completed"), "completed milestone fired during run")
	check(completed.has(stronghold_id), "stronghold_completed fired")

	# Sufficiency should have flipped from false to true.
	check(sufficiency_fired.size() == 1,
		"sufficiency flipped exactly once, got %d" % sufficiency_fired.size())
	if sufficiency_fired.size() > 0:
		check(sufficiency_fired[0][1] == true,
			"sufficiency now true")
		check(sufficiency_fired[0][2] == 32000,
			"value_gp = 32,000")

	# Verify final DB state.
	var sh: Dictionary = CampaignRepository.get_stronghold(stronghold_id)
	check(int(sh.get("completion_pct", 0)) == 100, "completion_pct = 100")
	check(String(sh.get("status", "")) == "completed", "status = completed")

	EventBus.stronghold_sufficiency_changed.disconnect(suff_conn)
	EventBus.stronghold_construction_progressed.disconnect(prog_conn)
	EventBus.stronghold_completed.disconnect(completed_conn)


# ----- Cost reduction path -----

func test_cleric_50pct_discount_reduces_duration() -> void:
	# 30,000 gp Fortified Church → 50% off → discounted_base 15,000 gp.
	# At base rate 500 gp/day → 30 days.
	var preset := {"class_cost_reduction_pct": 50}
	var structures: Array = [{"gp_cost": 30000}]
	var cost := StrongholdCostCalculator.calculate_total_cost(preset, structures, [], 100, 100)
	check(cost["discounted_base_cost"] == 15000,
		"discounted_base = 15,000, got %d" % cost["discounted_base_cost"])
	check(cost["gp_committed"] == 15000,
		"gp_committed = 15,000 (no speed premium), got %d" % cost["gp_committed"])
	check(cost["estimated_duration_days"] == 30,
		"duration = 30 days at base rate, got %d" % cost["estimated_duration_days"])


# ----- Speed tier path -----

func test_speed_tier_200_doubles_rate() -> void:
	# 30,000 gp at speed tier 200 → premium 30,000 → committed 60,000.
	# Daily rate 1,000 gp/day → 60 days.
	var preset := {"class_cost_reduction_pct": 0}
	var structures: Array = [{"gp_cost": 30000}]
	var cost := StrongholdCostCalculator.calculate_total_cost(preset, structures, [], 200, 100)
	check(cost["daily_construction_rate_gp"] == 1000,
		"tier 200 → 1000 gp/day, got %d" % cost["daily_construction_rate_gp"])
	check(cost["gp_committed"] == 60000, "gp_committed = 60,000")
	check(cost["estimated_duration_days"] == 60,
		"60,000 / 1,000 = 60 days, got %d" % cost["estimated_duration_days"])


# ----- Claim path -----

func test_claim_path_immediate_sufficiency() -> void:
	var domain_id := _make_test_domain("borderlands")
	StrongholdRepository._set_sufficiency_cache_for_test(domain_id, false)

	var fired: Array[Array] = []
	var conn := func(d_id: String, is_sufficient: bool, value_gp: int, minimum_gp: int):
		fired.append([d_id, is_sufficient, value_gp, minimum_gp])
	EventBus.stronghold_sufficiency_changed.connect(conn)

	# Borderlands minimum is 22,500 / hex × 1 hex. Claim a 22,500 gp ruin → flips sufficient.
	var result := ClaimingResolver.claim_existing(
		domain_id, "char_1", "fortress", "stronghold_castle",
		22500, "ruin", 0, 0, "")
	check(result["errors"].is_empty(),
		"claim succeeds, got %s" % str(result["errors"]))

	check(fired.size() == 1, "sufficiency_changed fired on claim")
	if fired.size() > 0:
		check(fired[0][1] == true, "sufficiency = true after claim")
	check(StrongholdRepository.is_sufficient_for_domain(domain_id) == true,
		"is_sufficient_for_domain returns true post-claim")

	EventBus.stronghold_sufficiency_changed.disconnect(conn)
