extends "res://tests/test_suite_base.gd"

## Unit tests for MarketPriceResolver — RAW 8-step price formula + dice cache
## + monthly drift mechanism per Prereq.2c.
##
## Per generation/gdd-settlement-economy.md §6.10.

var _campaign_id: String = ""
var _map_id: String = ""
var _suffix: int = 0
var _drift_events: Array = []


func run_all_tests() -> void:
	_setup()
	# Pure-function step tests
	test_class_size_adjust_table()
	test_roll_4d4_range()
	test_compute_percentage_arithmetic()
	test_compute_market_price_cp_precision()

	# Cache + dice behavior
	test_first_read_rolls_fresh()
	test_dice_persistence_across_calls()
	test_monopolist_favor_direction()
	test_judge_modifier_pass_through()

	# Drift behavior
	test_no_drift_within_month()
	test_drift_triggered_at_month_one()
	test_drift_forced_at_month_ten()
	test_drift_resets_cumulative()
	test_drift_emits_signal()

	# End-to-end worked examples
	test_worked_example_a_neutral_market()
	test_worked_example_b_class_ii_monopolist_spices()
	test_worked_example_c_class_vi_grain_with_war()

	# Campaign-wide drift sweep
	test_process_monthly_drift_for_campaign()

	if not has_failures():
		print("MarketPriceResolver: all %d tests passed." % test_count())


func _setup() -> void:
	_campaign_id = CampaignRepository.create_campaign("MarketPriceResolverTests", "World")
	_map_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO hex_maps (id, campaign_id, name, scale) VALUES (?, ?, ?, 'regional_6mi')",
		[_map_id, _campaign_id, "MPRMap"]
	)


func _next_id() -> String:
	_suffix += 1
	return "mpr_%d_%d" % [Time.get_ticks_msec(), _suffix]


func _make_settlement(market_class: int, name: String = "Town") -> String:
	var id: String = _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_entrances
			(id, campaign_id, map_id, hex_q, hex_r, name, market_class)
		VALUES (?, ?, ?, ?, ?, ?, ?)
	""", [id, _campaign_id, _map_id, _suffix, 0, name, market_class])
	return id


func _seed_modifier(settlement_id: String, merchandise_type: String, value: int) -> void:
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_merchandise_demand
			(settlement_entrance_id, merchandise_type, demand_modifier,
			 generated_at_calendar_day, source_kind,
			 pre_trade_route_shift_value)
		VALUES (?, ?, ?, 0, 'generated', ?)
		ON CONFLICT(settlement_entrance_id, merchandise_type) DO UPDATE SET
			demand_modifier = excluded.demand_modifier,
			pre_trade_route_shift_value = excluded.pre_trade_route_shift_value
	""", [settlement_id, merchandise_type, value, value])


func _force_dice(settlement_id: String, merchandise_type: String, dice: int, rolled_day: int) -> void:
	# Ensure a row exists without clobbering the demand_modifier value (which
	# the caller may have set via _seed_modifier just before this call).
	# INSERT-only-if-absent then UPDATE the dice fields.
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO settlement_merchandise_demand
			(settlement_entrance_id, merchandise_type, demand_modifier,
			 generated_at_calendar_day, source_kind,
			 pre_trade_route_shift_value)
		VALUES (?, ?, 0, 0, 'generated', 0)
	""", [settlement_id, merchandise_type])
	CampaignRepository.db.query_with_bindings("""
		UPDATE settlement_merchandise_demand
		SET dice_4d4_value = ?, dice_last_rolled_calendar_day = ?
		WHERE settlement_entrance_id = ? AND merchandise_type = ?
	""", [dice, rolled_day, settlement_id, merchandise_type])


func _seeded_rng(seed_val: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	return rng


# ---------------------------------------------------------------------------
# Pure-function step tests
# ---------------------------------------------------------------------------

func test_class_size_adjust_table() -> void:
	check(MarketPriceResolver.class_size_adjust(1) == 1, "Class I → +1")
	check(MarketPriceResolver.class_size_adjust(2) == 1, "Class II → +1")
	check(MarketPriceResolver.class_size_adjust(3) == 0, "Class III → 0")
	check(MarketPriceResolver.class_size_adjust(4) == 0, "Class IV → 0")
	check(MarketPriceResolver.class_size_adjust(5) == -1, "Class V → -1")
	check(MarketPriceResolver.class_size_adjust(6) == -1, "Class VI → -1")
	check(MarketPriceResolver.class_size_adjust(0) == 0, "out-of-range → 0")


func test_roll_4d4_range() -> void:
	# Run many samples; assert every result is in [4, 16].
	var rng: RandomNumberGenerator = _seeded_rng(1234)
	var min_seen: int = 999
	var max_seen: int = 0
	for _i in 5000:
		var v: int = MarketPriceResolver.roll_4d4(rng)
		if v < min_seen:
			min_seen = v
		if v > max_seen:
			max_seen = v
	check(min_seen >= 4, "min 4d4 should be ≥ 4 (got %d)" % min_seen)
	check(max_seen <= 16, "max 4d4 should be ≤ 16 (got %d)" % max_seen)
	check(min_seen == 4, "min 4d4 should be 4 (low-rolls eventually appear)")
	check(max_seen == 16, "max 4d4 should be 16 (high-rolls eventually appear)")


func test_compute_percentage_arithmetic() -> void:
	# (dice + demand + class_adj + monopoly + judge) * 10
	check(MarketPriceResolver.compute_percentage(10, 1, 0, 0, 0) == 110,
		"baseline (10, 1, 0, 0, 0) → 110")
	check(MarketPriceResolver.compute_percentage(10, 0, 1, 1, 0) == 120,
		"(10, 0, 1, 1, 0) → 120")
	check(MarketPriceResolver.compute_percentage(8, -2, -1, 0, -3) == 20,
		"(8, -2, -1, 0, -3) → 20")
	check(MarketPriceResolver.compute_percentage(14, 2, 1, 1, 0) == 180,
		"(14, 2, 1, 1, 0) → 180")


func test_compute_market_price_cp_precision() -> void:
	# Set up a settlement with class III, demand 0, dice forced.
	# Per the 2026-05-15 currency-precision rule, cp_per_load is exact —
	# base_price_cp × percentage / 100 is exact integer for whole-gp catalog entries.
	var s: String = _make_settlement(3, "CpPrecision")
	_seed_modifier(s, "grain_vegetables", 1)  # base 10, but we'll use the resolver call
	# Use the silk fixture: base 2000.
	_seed_modifier(s, "silk", 1)
	# Force dice = 11 → percentage = (11 + 1 + 0 + 0 + 0) * 10 = 120 → 2000 gp × 1.20
	# = 2400 gp = 240,000 cp (exact, no rounding needed cp-native).
	_force_dice(s, "silk", 11, 0)
	var r: Dictionary = MarketPriceResolver.compute_market_price("silk", s, 0, 0, _seeded_rng(1), 0)
	check(int(r.get("cp_per_load", 0)) == 240000, "silk 2000 gp × 120%% → 240,000 cp, got %d" % int(r.get("cp_per_load", 0)))
	# salt base 100 gp, dice 11 → 110% → 110 gp = 11,000 cp.
	var s2: String = _make_settlement(3, "BankerRound2")
	_seed_modifier(s2, "salt", 0)  # salt base = 100
	_force_dice(s2, "salt", 11, 0)
	var r2: Dictionary = MarketPriceResolver.compute_market_price("salt", s2, 0, 0, _seeded_rng(1), 0)
	check(int(r2.get("cp_per_load", 0)) == 11000, "salt 100 gp × 110%% → 11,000 cp")


# ---------------------------------------------------------------------------
# Cache + dice behavior
# ---------------------------------------------------------------------------

func test_first_read_rolls_fresh() -> void:
	# No cache row → compute_market_price rolls dice, inserts row.
	var s: String = _make_settlement(3, "FreshRoll")
	# Don't seed any demand modifier yet — the resolver's _ensure_dice_row
	# should still create a row with demand_modifier=0 default.
	var r: Dictionary = MarketPriceResolver.compute_market_price("silk", s, 0, 0, _seeded_rng(42), 0)
	check(int(r.get("cp_per_load", -1)) >= 0, "first read should produce a price, got %d" % int(r.get("cp_per_load", -1)))
	# Verify a cache row now exists with a non-zero dice value.
	CampaignRepository.db.query_with_bindings("""
		SELECT dice_4d4_value FROM settlement_merchandise_demand
		WHERE settlement_entrance_id = ? AND merchandise_type = 'silk'
	""", [s])
	check(not CampaignRepository.db.query_result.is_empty(),
		"first read should have created the cache row")
	var dice: int = int(CampaignRepository.db.query_result[0].get("dice_4d4_value", 0))
	check(dice >= 4 and dice <= 16,
		"first-read dice should be in [4, 16], got %d" % dice)


func test_dice_persistence_across_calls() -> void:
	# Two consecutive calls with the same inputs should return identical dice
	# and identical price.
	var s: String = _make_settlement(3, "Persistence")
	_seed_modifier(s, "salt", 0)
	var r1: Dictionary = MarketPriceResolver.compute_market_price("salt", s, 0, 0, _seeded_rng(7), 0)
	var r2: Dictionary = MarketPriceResolver.compute_market_price("salt", s, 0, 0, _seeded_rng(7), 0)
	check(int(r1["breakdown"]["dice_4d4"]) == int(r2["breakdown"]["dice_4d4"]),
		"persistence: dice should match across calls")
	check(int(r1["cp_per_load"]) == int(r2["cp_per_load"]),
		"persistence: cp_per_load should match")
	check(not bool(r2.get("drift_occurred", true)),
		"second call same day → no drift")


func test_monopolist_favor_direction() -> void:
	var s: String = _make_settlement(3, "Monopoly")
	_seed_modifier(s, "silk", 0)
	_force_dice(s, "silk", 10, 0)
	# baseline: percentage = (10+0+0+0+0)*10 = 100 → 2000 gp = 200,000 cp.
	var base: Dictionary = MarketPriceResolver.compute_market_price("silk", s, 0, 0, _seeded_rng(1), 0)
	check(int(base["percentage"]) == 100, "baseline percentage = 100")
	# selling monopolist (+1): percentage = 110 → 220,000 cp.
	var sell: Dictionary = MarketPriceResolver.compute_market_price("silk", s, 1, 0, _seeded_rng(1), 0)
	check(int(sell["percentage"]) == 110, "monopolist selling adds 10 to percentage")
	check(int(sell["cp_per_load"]) == 220000, "silk × 110%% = 220,000 cp")
	# buying monopolist (-1): percentage = 90 → 180,000 cp.
	var buy: Dictionary = MarketPriceResolver.compute_market_price("silk", s, -1, 0, _seeded_rng(1), 0)
	check(int(buy["percentage"]) == 90, "monopolist buying subtracts 10 from percentage")
	check(int(buy["cp_per_load"]) == 180000, "silk × 90%% = 180,000 cp")


func test_judge_modifier_pass_through() -> void:
	var s: String = _make_settlement(3, "JudgeMod")
	_seed_modifier(s, "salt", 0)
	_force_dice(s, "salt", 10, 0)
	# Baseline: 100 gp × 100% = 100 gp = 10,000 cp.
	var base: Dictionary = MarketPriceResolver.compute_market_price("salt", s, 0, 0, _seeded_rng(1), 0)
	check(int(base["percentage"]) == 100, "baseline 100")
	# Judge -3: percentage = 70 → 70 gp = 7000 cp.
	var penalty: Dictionary = MarketPriceResolver.compute_market_price("salt", s, 0, -3, _seeded_rng(1), 0)
	check(int(penalty["percentage"]) == 70, "judge -3 reduces percentage to 70")
	check(int(penalty["cp_per_load"]) == 7000, "salt × 70%% = 7000 cp")
	# Judge +5: percentage = 150 → 150 gp = 15,000 cp.
	var bonus: Dictionary = MarketPriceResolver.compute_market_price("salt", s, 0, 5, _seeded_rng(1), 0)
	check(int(bonus["percentage"]) == 150, "judge +5 increases percentage to 150")
	check(int(bonus["cp_per_load"]) == 15000, "salt × 150%% = 15,000 cp")


# ---------------------------------------------------------------------------
# Drift behavior
# ---------------------------------------------------------------------------

func test_no_drift_within_month() -> void:
	var s: String = _make_settlement(3, "NoDrift")
	_seed_modifier(s, "salt", 0)
	_force_dice(s, "salt", 10, 0)
	# Day 0 → call at day 5 (still within month). months_since = 0 → no drift.
	var rng: RandomNumberGenerator = _seeded_rng(1)
	check(not MarketPriceResolver.check_and_apply_drift(s, "salt", 5, rng),
		"day 5 (months_since=0) → no drift")
	# Day 0 → call at day 27 (still within first 28-day month).
	check(not MarketPriceResolver.check_and_apply_drift(s, "salt", 27, rng),
		"day 27 (months_since=0) → no drift")


func test_drift_triggered_at_month_one() -> void:
	var s: String = _make_settlement(3, "DriftMonth1Low")
	_seed_modifier(s, "salt", 0)
	_force_dice(s, "salt", 10, 0)
	# At month 1 (day 28), cumulative_pct = 10. An RNG that rolls ≤ 10
	# triggers drift; > 10 does not.
	# Seed 1's first randi_range(1, 100) gives a value; let's find a seed that
	# produces a low first roll. Manual probing: seed 7 gives first roll < 10
	# in practice. For determinism we'll use a small custom RNG via direct
	# value-injection: monkey-patch via state.
	# Instead, just verify the *probabilistic* contract by checking many trials.
	var triggers: int = 0
	var non_triggers: int = 0
	for trial in 1000:
		_force_dice(s, "salt", 10, 0)  # reset dice + last_rolled
		var rng: RandomNumberGenerator = _seeded_rng(trial * 1000 + 1)
		if MarketPriceResolver.check_and_apply_drift(s, "salt", 28, rng):
			triggers += 1
		else:
			non_triggers += 1
	# Expected ~10% triggers (100 of 1000). Allow ±50 jitter.
	check(triggers >= 50 and triggers <= 150,
		"month-1 drift should fire ~10%% of the time; got %d/1000 (expected ~100)" % triggers)


func test_drift_forced_at_month_ten() -> void:
	var s: String = _make_settlement(3, "DriftForced")
	_seed_modifier(s, "salt", 0)
	# Force dice at day 0, then check at day 280 (10 months × 28).
	# cumulative_pct = 100; any RNG roll ≤ 100, so drift always fires.
	for trial in 100:
		_force_dice(s, "salt", 10, 0)
		var rng: RandomNumberGenerator = _seeded_rng(trial)
		check(MarketPriceResolver.check_and_apply_drift(s, "salt", 280, rng),
			"month 10+ (day 280) → forced drift, trial %d" % trial)


func test_drift_resets_cumulative() -> void:
	var s: String = _make_settlement(3, "DriftReset")
	_seed_modifier(s, "salt", 0)
	# Force dice rolled on day 0; drift fires at day 280 (forced). After the
	# re-roll, dice_last_rolled_calendar_day is reset to 280. Another check
	# at day 280+27=307 should NOT fire (months_since=0 from new baseline).
	_force_dice(s, "salt", 10, 0)
	var rng: RandomNumberGenerator = _seeded_rng(42)
	check(MarketPriceResolver.check_and_apply_drift(s, "salt", 280, rng),
		"forced drift at day 280")
	# Verify dice_last_rolled_calendar_day got updated.
	CampaignRepository.db.query_with_bindings("""
		SELECT dice_last_rolled_calendar_day FROM settlement_merchandise_demand
		WHERE settlement_entrance_id = ? AND merchandise_type = 'salt'
	""", [s])
	check(int(CampaignRepository.db.query_result[0].get("dice_last_rolled_calendar_day", 0)) == 280,
		"dice_last_rolled_calendar_day reset to 280 post-drift")
	# Next check at day 307 (27 days later, still within new month).
	check(not MarketPriceResolver.check_and_apply_drift(s, "salt", 307, rng),
		"day 307 (27 days after re-roll) → no drift")


func test_drift_emits_signal() -> void:
	var s: String = _make_settlement(3, "DriftSignal")
	_seed_modifier(s, "salt", 0)
	_force_dice(s, "salt", 10, 0)
	# Connect to the signal.
	_drift_events.clear()
	var cb: Callable = _on_drift_event
	EventBus.market_price_drifted.connect(cb)
	# Force drift at day 280.
	var rng: RandomNumberGenerator = _seeded_rng(42)
	MarketPriceResolver.check_and_apply_drift(s, "salt", 280, rng)
	EventBus.market_price_drifted.disconnect(cb)
	check(_drift_events.size() == 1,
		"drift should emit exactly 1 signal, got %d" % _drift_events.size())
	if _drift_events.size() >= 1:
		var evt: Dictionary = _drift_events[0]
		check(str(evt.get("settlement_id", "")) == s, "signal payload settlement_id matches")
		check(str(evt.get("merchandise_type", "")) == "salt", "signal payload merchandise_type matches")
		check(int(evt.get("old_dice", 0)) == 10, "signal payload old_dice = 10")
		check(int(evt.get("new_dice", 0)) >= 4 and int(evt.get("new_dice", 0)) <= 16,
			"signal payload new_dice in [4, 16]")


func _on_drift_event(settlement_id: String, merchandise_type: String, old_dice: int, new_dice: int) -> void:
	_drift_events.append({
		"settlement_id": settlement_id,
		"merchandise_type": merchandise_type,
		"old_dice": old_dice,
		"new_dice": new_dice,
	})


# ---------------------------------------------------------------------------
# Worked examples from §6.9
# ---------------------------------------------------------------------------

func test_worked_example_a_neutral_market() -> void:
	# wood_common base 50 gp, class III, demand=-1, dice=10, no modifiers.
	# percentage = (10 + -1 + 0 + 0 + 0) * 10 = 90 → 50 gp × 0.90 = 45 gp = 4500 cp.
	var s: String = _make_settlement(3, "ExampleA")
	_seed_modifier(s, "wood_common", -1)
	_force_dice(s, "wood_common", 10, 0)
	var r: Dictionary = MarketPriceResolver.compute_market_price("wood_common", s, 0, 0, _seeded_rng(1), 0)
	check(int(r["percentage"]) == 90, "Example A percentage = 90")
	check(int(r["cp_per_load"]) == 4500, "Example A cp_per_load = 4500, got %d" % int(r["cp_per_load"]))


func test_worked_example_b_class_ii_monopolist_spices() -> void:
	# spices base 800 gp, class II, demand=+2, dice=12, monopolist=+1, judge=0.
	# percentage = (12 + 2 + 1 + 1 + 0) * 10 = 160 → 800 gp × 1.60 = 1280 gp = 128,000 cp.
	var s: String = _make_settlement(2, "ExampleB")
	_seed_modifier(s, "spices", 2)
	_force_dice(s, "spices", 12, 0)
	var r: Dictionary = MarketPriceResolver.compute_market_price("spices", s, 1, 0, _seeded_rng(1), 0)
	check(int(r["percentage"]) == 160, "Example B percentage = 160")
	check(int(r["cp_per_load"]) == 128000, "Example B cp_per_load = 128,000, got %d" % int(r["cp_per_load"]))


func test_worked_example_c_class_vi_grain_with_war() -> void:
	# grain_vegetables base 10 gp, class VI, demand=+2, dice=14, judge=-2.
	# percentage = (14 + 2 + -1 + 0 + -2) * 10 = 130 → 10 gp × 1.30 = 13 gp = 1300 cp.
	var s: String = _make_settlement(6, "ExampleC")
	_seed_modifier(s, "grain_vegetables", 2)
	_force_dice(s, "grain_vegetables", 14, 0)
	var r: Dictionary = MarketPriceResolver.compute_market_price("grain_vegetables", s, 0, -2, _seeded_rng(1), 0)
	check(int(r["percentage"]) == 130, "Example C percentage = 130")
	check(int(r["cp_per_load"]) == 1300, "Example C cp_per_load = 1300, got %d" % int(r["cp_per_load"]))


# ---------------------------------------------------------------------------
# Campaign-wide drift sweep
# ---------------------------------------------------------------------------

func test_process_monthly_drift_for_campaign() -> void:
	# Two settlements with seeded dice. At day 280 (forced drift), the sweep
	# should re-roll both.
	var cid: String = CampaignRepository.create_campaign("DriftSweepCampaign", "")
	var map_id: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO hex_maps (id, campaign_id, name, scale) VALUES (?, ?, ?, 'regional_6mi')",
		[map_id, cid, "SweepMap"]
	)
	var s1: String = "%s_sweep1" % _next_id()
	var s2: String = "%s_sweep2" % _next_id()
	for tup in [[s1, "Sweep1"], [s2, "Sweep2"]]:
		CampaignRepository.db.query_with_bindings("""
			INSERT INTO settlement_entrances
				(id, campaign_id, map_id, hex_q, hex_r, name, market_class)
			VALUES (?, ?, ?, 0, 0, ?, 3)
		""", [tup[0], cid, map_id, tup[1]])
	# Seed dice for two merchandise per settlement.
	for s in [s1, s2]:
		for merch in ["salt", "silk"]:
			CampaignRepository.db.query_with_bindings("""
				INSERT INTO settlement_merchandise_demand
					(settlement_entrance_id, merchandise_type, demand_modifier,
					 generated_at_calendar_day, source_kind,
					 pre_trade_route_shift_value,
					 dice_4d4_value, dice_last_rolled_calendar_day)
				VALUES (?, ?, 0, 0, 'generated', 0, 10, 0)
			""", [s, merch])
	# Day 280 → forced drift for all 4 pairs.
	var rng: RandomNumberGenerator = _seeded_rng(1)
	var count: int = MarketPriceResolver.process_monthly_drift_for_campaign(cid, 280, rng)
	check(count == 4,
		"campaign sweep at month 10 should re-roll all 4 pairs, got %d" % count)
	# Verify all four have new dice_last_rolled_calendar_day = 280.
	CampaignRepository.db.query_with_bindings("""
		SELECT COUNT(*) AS n FROM settlement_merchandise_demand smd
		JOIN settlement_entrances se ON smd.settlement_entrance_id = se.id
		WHERE se.campaign_id = ? AND smd.dice_last_rolled_calendar_day = 280
	""", [cid])
	check(int(CampaignRepository.db.query_result[0].get("n", 0)) == 4,
		"all 4 sweep rows should have last_rolled_day = 280")
