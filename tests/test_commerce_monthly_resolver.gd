extends "res://tests/test_suite_base.gd"

## Unit tests for CommerceMonthlyResolver — Phase 10B.2 Wave 5.
##
## Per gdd-phase-10b-2-trade-block.md §11 + §18.1. Exercises:
##   * process_for_campaign fires all 4 drivers in canonical order
##     (customs → ships → merchants → drift).
##   * Returns result Dict with per-driver counters + emits
##     commerce_monthly_tick_completed.
##   * _maybe_roll_annual_customs (Y-Option 3): fires only when
##     current_year > campaigns.last_customs_roll_year; substrate updates the
##     stamp; repeat calls in same year are no-ops.
##   * Deterministic seeded RNG: seeded_monthly_rng((campaign, day)) produces
##     identical seeds for identical inputs.
##   * Empty-input guards: empty campaign_id or null rng → skip flag returned.
##   * Drivers tolerate empty campaign (no merchants / ships / settlements).

var _campaign_id: String = ""
var _map_id: String = ""
var _suffix: int = 0


func run_all_tests() -> void:
	_setup()
	test_process_for_campaign_returns_results_dict()
	test_process_for_campaign_emits_completion_signal()
	test_process_for_campaign_empty_campaign_id_returns_skipped()
	test_process_for_campaign_null_rng_returns_skipped()
	test_process_for_campaign_handles_empty_campaign_gracefully()
	test_seeded_monthly_rng_deterministic_per_inputs()
	test_seeded_monthly_rng_differs_across_days()
	test_maybe_roll_annual_customs_fires_on_year_advance()
	test_maybe_roll_annual_customs_no_op_within_year()
	test_maybe_roll_annual_customs_updates_last_customs_roll_year()
	test_process_for_campaign_invokes_substrate_drivers()

	if not has_failures():
		print("CommerceMonthlyResolver: all %d tests passed." % test_count())


func _setup() -> void:
	_campaign_id = CampaignRepository.create_campaign("CommerceMonthlyResolverTests", "World")
	_map_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO hex_maps (id, campaign_id, name, scale) VALUES (?, ?, ?, 'regional_6mi')",
		[_map_id, _campaign_id, "CMRMap"])


func _next_id(tag: String = "cmr") -> String:
	_suffix += 1
	return "%s_%d_%d" % [tag, Time.get_ticks_msec(), _suffix]


# ---------------------------------------------------------------------------
# process_for_campaign return-shape
# ---------------------------------------------------------------------------

func test_process_for_campaign_returns_results_dict() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var r: Dictionary = CommerceMonthlyResolver.process_for_campaign(
		_campaign_id, 100, 1, rng)
	check(String(r.get("campaign_id", "")) == _campaign_id,
		"results dict carries campaign_id")
	check(int(r.get("calendar_day", -1)) == 100, "results.calendar_day = 100")
	check(int(r.get("year", -1)) == 1, "results.year = 1")
	for key in ["customs_rolled", "ship_cp_debited", "merchants_generated", "prices_drifted"]:
		check(r.has(key), "results has key '%s'" % key)


func test_process_for_campaign_emits_completion_signal() -> void:
	var captured := {"emitted": false, "campaign_id": "", "results": {}}
	var cb: Callable = func(cid: String, results: Dictionary) -> void:
		captured["emitted"] = true
		captured["campaign_id"] = cid
		captured["results"] = results
	EventBus.commerce_monthly_tick_completed.connect(cb)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	CommerceMonthlyResolver.process_for_campaign(_campaign_id, 50, 1, rng)
	EventBus.commerce_monthly_tick_completed.disconnect(cb)
	check(bool(captured["emitted"]), "commerce_monthly_tick_completed emits")
	check(str(captured["campaign_id"]) == _campaign_id,
		"signal payload campaign_id matches")
	check(captured["results"] is Dictionary, "signal payload results is Dictionary")


func test_process_for_campaign_empty_campaign_id_returns_skipped() -> void:
	var rng := RandomNumberGenerator.new()
	var r: Dictionary = CommerceMonthlyResolver.process_for_campaign("", 100, 1, rng)
	check(bool(r.get("skipped", false)), "empty campaign_id → skipped flag set")
	check(int(r.get("customs_rolled", -1)) == 0, "no work counted")


func test_process_for_campaign_null_rng_returns_skipped() -> void:
	var r: Dictionary = CommerceMonthlyResolver.process_for_campaign(
		_campaign_id, 100, 1, null)
	check(bool(r.get("skipped", false)), "null rng → skipped flag set")


func test_process_for_campaign_handles_empty_campaign_gracefully() -> void:
	# Campaign has no ships / no settlements / no merchants. The substrate
	# drivers all return 0 gracefully. Verify no crash + result dict shape.
	var fresh_id: String = CampaignRepository.create_campaign("CMR_empty_" + _next_id(), "World")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var r: Dictionary = CommerceMonthlyResolver.process_for_campaign(fresh_id, 1, 1, rng)
	check(int(r.get("ship_cp_debited", -1)) == 0,
		"empty campaign → 0 ship costs debited")
	check(int(r.get("merchants_generated", -1)) == 0,
		"empty campaign → 0 merchants generated")
	check(int(r.get("prices_drifted", -1)) == 0,
		"empty campaign → 0 prices drifted")


# ---------------------------------------------------------------------------
# Seeded RNG determinism
# ---------------------------------------------------------------------------

func test_seeded_monthly_rng_deterministic_per_inputs() -> void:
	var a: RandomNumberGenerator = CommerceMonthlyResolver.seeded_monthly_rng("camp_x", 100)
	var b: RandomNumberGenerator = CommerceMonthlyResolver.seeded_monthly_rng("camp_x", 100)
	check(a.seed == b.seed,
		"same (campaign, day) → identical seed (a=%d b=%d)" % [a.seed, b.seed])
	check(a.randi_range(1, 1000) == b.randi_range(1, 1000),
		"same seed → identical first roll")


func test_seeded_monthly_rng_differs_across_days() -> void:
	var d100: RandomNumberGenerator = CommerceMonthlyResolver.seeded_monthly_rng("camp_x", 100)
	var d128: RandomNumberGenerator = CommerceMonthlyResolver.seeded_monthly_rng("camp_x", 128)
	check(d100.seed != d128.seed,
		"different days produce different seeds")


# ---------------------------------------------------------------------------
# Annual customs roll (Y-Option 3)
# ---------------------------------------------------------------------------

func test_maybe_roll_annual_customs_fires_on_year_advance() -> void:
	# Make a campaign with one settlement so the substrate has something to roll.
	var camp_id: String = CampaignRepository.create_campaign("CMR_customs_" + _next_id(), "World")
	var sid: String = _next_id("s")
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_entrances
			(id, campaign_id, map_id, hex_q, hex_r, name, market_class, customs_duty_rate_pct)
		VALUES (?, ?, ?, 0, 0, 'CustomsTown', 3, 4)
	""", [sid, camp_id, _map_id])
	# campaigns.last_customs_roll_year starts at 0 → year 1 should fire.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var r: Dictionary = CommerceMonthlyResolver.process_for_campaign(camp_id, 50, 1, rng)
	check(int(r.get("customs_rolled", 0)) >= 1,
		"customs roll fires when current_year > last_customs_roll_year, got %d" % int(r.get("customs_rolled", 0)))


func test_maybe_roll_annual_customs_no_op_within_year() -> void:
	var camp_id: String = CampaignRepository.create_campaign("CMR_customs_noop_" + _next_id(), "World")
	var sid: String = _next_id("s")
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_entrances
			(id, campaign_id, map_id, hex_q, hex_r, name, market_class, customs_duty_rate_pct)
		VALUES (?, ?, ?, 0, 0, 'NoOpTown', 3, 4)
	""", [sid, camp_id, _map_id])
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	# First pass — fires.
	var r1: Dictionary = CommerceMonthlyResolver.process_for_campaign(camp_id, 50, 1, rng)
	check(int(r1.get("customs_rolled", 0)) >= 1, "first call fires customs roll")
	# Second pass within the same year — no-op.
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 2
	var r2: Dictionary = CommerceMonthlyResolver.process_for_campaign(camp_id, 80, 1, rng2)
	check(int(r2.get("customs_rolled", -1)) == 0,
		"second call within same year is a no-op, got customs_rolled=%d" % int(r2.get("customs_rolled", -1)))


func test_maybe_roll_annual_customs_updates_last_customs_roll_year() -> void:
	var camp_id: String = CampaignRepository.create_campaign("CMR_customs_stamp_" + _next_id(), "World")
	var sid: String = _next_id("s")
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_entrances
			(id, campaign_id, map_id, hex_q, hex_r, name, market_class, customs_duty_rate_pct)
		VALUES (?, ?, ?, 0, 0, 'StampTown', 3, 4)
	""", [sid, camp_id, _map_id])
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	CommerceMonthlyResolver.process_for_campaign(camp_id, 50, 5, rng)
	# Read back last_customs_roll_year.
	CampaignRepository.db.query_with_bindings(
		"SELECT last_customs_roll_year FROM campaigns WHERE id = ?", [camp_id])
	var stamped: int = int(CampaignRepository.db.query_result[0].get("last_customs_roll_year", 0))
	check(stamped == 5,
		"last_customs_roll_year stamped to 5, got %d" % stamped)


# ---------------------------------------------------------------------------
# Substrate driver invocation (smoke)
# ---------------------------------------------------------------------------

func test_process_for_campaign_invokes_substrate_drivers() -> void:
	# Build a settlement + a ship to exercise both ships + merchants paths.
	var camp_id: String = CampaignRepository.create_campaign("CMR_drivers_" + _next_id(), "World")
	var sid: String = _next_id("s")
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_entrances
			(id, campaign_id, map_id, hex_q, hex_r, name, market_class)
		VALUES (?, ?, ?, 0, 0, 'DriversTown', 3)
	""", [sid, camp_id, _map_id])
	var party_id: String = _next_id("party")
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO parties (id, campaign_id, name) VALUES (?, ?, 'DriverParty')",
		[party_id, camp_id])
	# Ship at settlement.
	ShipRepository.create_ship(party_id, "sailing_ship_small", sid)
	# Process.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var r: Dictionary = CommerceMonthlyResolver.process_for_campaign(camp_id, 50, 1, rng)
	# Merchant pool refresh generates Class III = 8 merchants.
	check(int(r.get("merchants_generated", 0)) == 8,
		"Class III merchant pool refresh generates 8, got %d" % int(r.get("merchants_generated", 0)))
	# Ship operating cost: sailing_ship_small has monthly_operating_cost_cp > 0
	# but party has no wealth, so unpaid signal fires (but ship_cp_debited = 0).
	check(int(r.get("ship_cp_debited", -1)) >= 0,
		"ship_cp_debited present (may be 0 if party has no funds)")
