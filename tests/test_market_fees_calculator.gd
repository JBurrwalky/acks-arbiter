extends "res://tests/test_suite_base.gd"

## Unit tests for MarketFeesCalculator — entry toll, customs duty, labor,
## moorage, stabling, and domain-owner exemption per Prereq.3.
##
## Per generation/gdd-settlement-economy.md §8.10.

var _campaign_id: String = ""
var _map_id: String = ""
var _suffix: int = 0


func run_all_tests() -> void:
	_setup()
	# Entry toll
	test_entry_toll_dice_range_class_i()
	test_entry_toll_selling_minimum_kicks_in()
	test_entry_toll_selling_dice_exceeds_minimum()
	test_entry_toll_domain_owner_exemption()

	# Customs duty
	test_customs_duty_uses_cached_rate()
	test_customs_duty_zero_price()
	test_customs_duty_domain_owner_exemption()
	test_annual_customs_roll_determinism()
	test_annual_customs_roll_range()
	test_process_annual_customs_roll_for_campaign()

	# Labor
	test_labor_fee_exact_multiples()
	test_labor_fee_aggregate_then_round()
	test_labor_fee_zero_and_below_threshold()

	# Moorage
	test_moorage_per_day()
	test_moorage_multi_day_aggregate()
	test_moorage_domain_owner_exemption()

	# Stabling
	test_stabling_mixed_mounts_per_day()
	test_stabling_multi_day_aggregate()
	test_stabling_unknown_key_contributes_zero()
	test_stabling_domain_owner_exemption()

	# Predicate
	test_is_domain_owner_in_own_market()

	if not has_failures():
		print("MarketFeesCalculator: all %d tests passed." % test_count())


func _setup() -> void:
	_campaign_id = CampaignRepository.create_campaign("MarketFeesCalculatorTests", "World")
	_map_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO hex_maps (id, campaign_id, name, scale) VALUES (?, ?, ?, 'regional_6mi')",
		[_map_id, _campaign_id, "MFCMap"]
	)


func _next_id() -> String:
	_suffix += 1
	return "mfc_%d_%d" % [Time.get_ticks_msec(), _suffix]


func _make_settlement(args: Dictionary) -> String:
	var id: String = _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_entrances
			(id, campaign_id, map_id, hex_q, hex_r, name, market_class,
			 customs_duty_rate_pct, parent_domain_id)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		id, _campaign_id, _map_id,
		int(args.get("hex_q", _suffix)), int(args.get("hex_r", 0)),
		str(args.get("name", "MFCTown")),
		int(args.get("market_class", 3)),
		int(args.get("customs_duty_rate_pct", 0)),
		args.get("parent_domain_id", null),
	])
	return id


func _seeded_rng(seed_val: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	return rng


# ---------------------------------------------------------------------------
# Entry toll
# ---------------------------------------------------------------------------

func test_entry_toll_dice_range_class_i() -> void:
	# Class I toll = 1d6+15 → [16, 21].
	var rng: RandomNumberGenerator = _seeded_rng(1)
	var min_seen: int = 999
	var max_seen: int = 0
	for _i in 500:
		var v: int = MarketFeesCalculator.entry_toll_gp(1, false, 0, rng, false)
		if v < min_seen:
			min_seen = v
		if v > max_seen:
			max_seen = v
	check(min_seen >= 16, "Class I toll min should be ≥ 16, got %d" % min_seen)
	check(max_seen <= 21, "Class I toll max should be ≤ 21, got %d" % max_seen)


func test_entry_toll_selling_minimum_kicks_in() -> void:
	# Force a low Class VI roll (1d3 → 1..3). Sell 10 loads → minimum is 10.
	# Use a seed that produces a low roll then verify result.
	# Try multiple seeds; the minimum applies regardless.
	for trial in range(10):
		var rng: RandomNumberGenerator = _seeded_rng(trial * 7 + 1)
		var v: int = MarketFeesCalculator.entry_toll_gp(6, true, 10, rng, false)
		check(v >= 10, "selling minimum: VI + 10 loads should yield ≥ 10, got %d (seed %d)" % [v, trial])
		check(v <= 10, "selling minimum: VI roll ≤ 3, so 10-load minimum dominates → 10, got %d" % v)


func test_entry_toll_selling_dice_exceeds_minimum() -> void:
	# Class I roll (1d6+15 → ≥16). Sell 5 loads → minimum 5 < dice → dice wins.
	for trial in range(10):
		var rng: RandomNumberGenerator = _seeded_rng(trial)
		var v: int = MarketFeesCalculator.entry_toll_gp(1, true, 5, rng, false)
		check(v >= 16, "dice exceeds minimum: result should be ≥ 16, got %d" % v)


func test_entry_toll_domain_owner_exemption() -> void:
	var rng: RandomNumberGenerator = _seeded_rng(42)
	check(MarketFeesCalculator.entry_toll_gp(1, false, 0, rng, true) == 0,
		"domain owner pays 0 toll regardless of class")
	check(MarketFeesCalculator.entry_toll_gp(1, true, 100, rng, true) == 0,
		"domain owner pays 0 toll even when selling 100 loads")


# ---------------------------------------------------------------------------
# Customs duty
# ---------------------------------------------------------------------------

func test_customs_duty_uses_cached_rate() -> void:
	var s: String = _make_settlement({"customs_duty_rate_pct": 15, "name": "Customs15"})
	check(MarketFeesCalculator.customs_duty_gp(1000, s, false) == 150,
		"customs at 15%% on 1000gp → 150, got %d" % MarketFeesCalculator.customs_duty_gp(1000, s, false))
	# Boundary: 12% rate, 333 gp → 39.96 → 40 banker
	var s2: String = _make_settlement({"customs_duty_rate_pct": 12, "name": "Customs12"})
	check(MarketFeesCalculator.customs_duty_gp(333, s2, false) == 40,
		"customs at 12%% on 333gp → 39.96 → 40, got %d" % MarketFeesCalculator.customs_duty_gp(333, s2, false))


func test_customs_duty_zero_price() -> void:
	var s: String = _make_settlement({"customs_duty_rate_pct": 20, "name": "Customs20Zero"})
	check(MarketFeesCalculator.customs_duty_gp(0, s, false) == 0,
		"customs on 0 gp price → 0")


func test_customs_duty_domain_owner_exemption() -> void:
	var s: String = _make_settlement({"customs_duty_rate_pct": 15, "name": "Customs15Owner"})
	check(MarketFeesCalculator.customs_duty_gp(1000, s, true) == 0,
		"domain owner pays 0 customs (project extension per §8.8)")


func test_annual_customs_roll_determinism() -> void:
	# Same (settlement, year) → same value.
	var a1: int = MarketFeesCalculator.roll_annual_customs_rate("settle_xyz", 1234)
	var a2: int = MarketFeesCalculator.roll_annual_customs_rate("settle_xyz", 1234)
	check(a1 == a2, "same seed → same rate on repeat call")
	# Different settlement, same year — typically different value.
	var b: int = MarketFeesCalculator.roll_annual_customs_rate("settle_other", 1234)
	check(a1 != b,
		"different settlements at same year usually yield different rates (a=%d, b=%d)" % [a1, b])
	# Same settlement, different year — typically different value.
	var c: int = MarketFeesCalculator.roll_annual_customs_rate("settle_xyz", 1235)
	check(a1 != c,
		"same settlement at different years usually yield different rates")


func test_annual_customs_roll_range() -> void:
	# 1d10 + 1d10 = [2, 20].
	var min_seen: int = 999
	var max_seen: int = 0
	for year in range(1, 1001):
		var v: int = MarketFeesCalculator.roll_annual_customs_rate("range_settle", year)
		if v < min_seen:
			min_seen = v
		if v > max_seen:
			max_seen = v
	check(min_seen >= 2, "1d10+1d10 minimum ≥ 2 (got %d)" % min_seen)
	check(max_seen <= 20, "1d10+1d10 maximum ≤ 20 (got %d)" % max_seen)


func test_process_annual_customs_roll_for_campaign() -> void:
	# Three settlements in a fresh campaign with last_customs_roll_year = 0.
	# After processing for year 1234, all three should have new rates and
	# campaigns.last_customs_roll_year = 1234.
	var cid: String = CampaignRepository.create_campaign("AnnualRollCampaign", "")
	var map_id: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO hex_maps (id, campaign_id, name, scale) VALUES (?, ?, ?, 'regional_6mi')",
		[map_id, cid, "AnnualMap"]
	)
	var ids: Array = []
	for i in range(3):
		var sid: String = "%s_ann_%d" % [_next_id(), i]
		CampaignRepository.db.query_with_bindings("""
			INSERT INTO settlement_entrances
				(id, campaign_id, map_id, hex_q, hex_r, name, market_class)
			VALUES (?, ?, ?, ?, 0, ?, 3)
		""", [sid, cid, map_id, i, "Ann%d" % i])
		ids.append(sid)
	var count: int = MarketFeesCalculator.process_annual_customs_roll_for_campaign(cid, 1234)
	check(count == 3, "process should update 3 settlements, got %d" % count)
	# All rates in [2, 20] and match what `roll_annual_customs_rate` would produce.
	for sid in ids:
		CampaignRepository.db.query_with_bindings(
			"SELECT customs_duty_rate_pct FROM settlement_entrances WHERE id = ?", [sid])
		var rate: int = int(CampaignRepository.db.query_result[0].get("customs_duty_rate_pct", -1))
		var expected: int = MarketFeesCalculator.roll_annual_customs_rate(sid, 1234)
		check(rate == expected,
			"%s rate should match deterministic roll (expected %d, got %d)" % [sid, expected, rate])
		check(rate >= 2 and rate <= 20, "%s rate in [2, 20], got %d" % [sid, rate])
	# campaigns.last_customs_roll_year advanced.
	CampaignRepository.db.query_with_bindings(
		"SELECT last_customs_roll_year FROM campaigns WHERE id = ?", [cid])
	check(int(CampaignRepository.db.query_result[0].get("last_customs_roll_year", 0)) == 1234,
		"campaigns.last_customs_roll_year should advance to 1234")


# ---------------------------------------------------------------------------
# Labor
# ---------------------------------------------------------------------------

func test_labor_fee_exact_multiples() -> void:
	check(MarketFeesCalculator.labor_fee_gp(200) == 1, "200 stone → 1 gp")
	check(MarketFeesCalculator.labor_fee_gp(400) == 2, "400 stone → 2 gp")
	check(MarketFeesCalculator.labor_fee_gp(2000) == 10, "2000 stone → 10 gp")


func test_labor_fee_aggregate_then_round() -> void:
	# 100 stone → 0.5 gp → banker rounds to even 0
	check(MarketFeesCalculator.labor_fee_gp(100) == 0,
		"100 stone → 0.5 gp banker → 0, got %d" % MarketFeesCalculator.labor_fee_gp(100))
	# 300 stone → 1.5 gp → banker rounds to even 2
	check(MarketFeesCalculator.labor_fee_gp(300) == 2,
		"300 stone → 1.5 gp banker → 2, got %d" % MarketFeesCalculator.labor_fee_gp(300))
	# 3760 stone → 18.8 gp → 19
	check(MarketFeesCalculator.labor_fee_gp(3760) == 19,
		"3760 stone → 18.8 gp → 19, got %d" % MarketFeesCalculator.labor_fee_gp(3760))


func test_labor_fee_zero_and_below_threshold() -> void:
	check(MarketFeesCalculator.labor_fee_gp(0) == 0, "0 stone → 0 gp")
	check(MarketFeesCalculator.labor_fee_gp(30) == 0, "30 stone (one hides load) → 0 gp (below threshold)")
	check(MarketFeesCalculator.labor_fee_gp(-50) == 0, "negative → 0 (defensive)")


# ---------------------------------------------------------------------------
# Moorage
# ---------------------------------------------------------------------------

func test_moorage_per_day() -> void:
	check(MarketFeesCalculator.moorage_gp_per_day(30, false) == 3, "30 SHP → 3 gp/day")
	check(MarketFeesCalculator.moorage_gp_per_day(5, false) == 0, "5 SHP → 0.5 banker → 0 gp/day")
	check(MarketFeesCalculator.moorage_gp_per_day(15, false) == 2, "15 SHP → 1.5 banker → 2 gp/day")
	check(MarketFeesCalculator.moorage_gp_per_day(0, false) == 0, "0 SHP → 0")


func test_moorage_multi_day_aggregate() -> void:
	# 5 SHP × 7 days = 35/10 = 3.5 → banker → 4
	check(MarketFeesCalculator.moorage_gp_total(5, 7, false) == 4,
		"5 SHP × 7 days → 3.5 → 4, got %d" % MarketFeesCalculator.moorage_gp_total(5, 7, false))
	# 30 × 14 = 420/10 = 42 (clean)
	check(MarketFeesCalculator.moorage_gp_total(30, 14, false) == 42,
		"30 SHP × 14 days → 42")


func test_moorage_domain_owner_exemption() -> void:
	check(MarketFeesCalculator.moorage_gp_per_day(30, true) == 0,
		"domain owner pays 0 moorage per day")
	check(MarketFeesCalculator.moorage_gp_total(30, 14, true) == 0,
		"domain owner pays 0 moorage total")


# ---------------------------------------------------------------------------
# Stabling
# ---------------------------------------------------------------------------

func test_stabling_mixed_mounts_per_day() -> void:
	# 5 mules × 0.2 + 2 horses × 0.5 = 1.0 + 1.0 = 2.0 → 2 gp/day
	var mounts := {"mule": 5, "horse": 2}
	check(MarketFeesCalculator.stabling_gp_per_day(mounts, false) == 2,
		"5 mules + 2 horses → 2 gp/day, got %d" % MarketFeesCalculator.stabling_gp_per_day(mounts, false))
	# 1 horse → 0.5 → banker → 0
	check(MarketFeesCalculator.stabling_gp_per_day({"horse": 1}, false) == 0,
		"1 horse alone → 0.5 → banker 0 gp/day")
	# 1 horse × 2 days → 1.0 → 1
	check(MarketFeesCalculator.stabling_gp_total({"horse": 1}, 2, false) == 1,
		"1 horse × 2 days → 1.0 → 1")
	# 1 horse × 7 days → 3.5 → 4
	check(MarketFeesCalculator.stabling_gp_total({"horse": 1}, 7, false) == 4,
		"1 horse × 7 days → 3.5 → 4, got %d" % MarketFeesCalculator.stabling_gp_total({"horse": 1}, 7, false))


func test_stabling_multi_day_aggregate() -> void:
	# 4 oxen × 0.8 × 7 days = 22.4 → 22
	check(MarketFeesCalculator.stabling_gp_total({"ox": 4}, 7, false) == 22,
		"4 oxen × 7 days → 22.4 → 22, got %d" % MarketFeesCalculator.stabling_gp_total({"ox": 4}, 7, false))
	# 3 wagons × 2 × 14 = 84 (clean)
	check(MarketFeesCalculator.stabling_gp_total({"wagon": 3}, 14, false) == 84,
		"3 wagons × 14 days → 84")
	# Mix per §8.10 test 13: 5 mule + 2 horse + 1 wagon × 7 days
	# = (5×0.2 + 2×0.5 + 1×2.0) × 7 = (1 + 1 + 2) × 7 = 4 × 7 = 28
	check(MarketFeesCalculator.stabling_gp_total({"mule": 5, "horse": 2, "wagon": 1}, 7, false) == 28,
		"5 mule + 2 horse + 1 wagon × 7 days → 28")
	# Test the donkey/camel/cart aliases.
	check(MarketFeesCalculator.stabling_gp_total({"donkey": 5}, 10, false) ==
			MarketFeesCalculator.stabling_gp_total({"mule": 5}, 10, false),
		"donkey rate matches mule rate (project-design fill)")
	check(MarketFeesCalculator.stabling_gp_total({"camel": 4}, 5, false) ==
			MarketFeesCalculator.stabling_gp_total({"horse": 4}, 5, false),
		"camel rate matches horse rate")


func test_stabling_unknown_key_contributes_zero() -> void:
	# Unknown key like "warhorse" should contribute 0.
	check(MarketFeesCalculator.stabling_gp_total({"warhorse": 100}, 30, false) == 0,
		"unknown key contributes 0 (caller maps to canonical key)")
	# Mixed with known key: known key still contributes correctly.
	check(MarketFeesCalculator.stabling_gp_total({"warhorse": 5, "horse": 2}, 1, false) ==
			MarketFeesCalculator.stabling_gp_total({"horse": 2}, 1, false),
		"unknown key in mix doesn't affect known key's contribution")


func test_stabling_domain_owner_exemption() -> void:
	check(MarketFeesCalculator.stabling_gp_per_day({"horse": 10, "wagon": 5}, true) == 0,
		"domain owner pays 0 stabling per day")
	check(MarketFeesCalculator.stabling_gp_total({"horse": 10, "wagon": 5}, 14, true) == 0,
		"domain owner pays 0 stabling total")


# ---------------------------------------------------------------------------
# Predicate
# ---------------------------------------------------------------------------

func test_is_domain_owner_in_own_market() -> void:
	# Make a character, a domain owned by the character, a settlement with
	# parent_domain pointing at the domain.
	var owner_id: String = "%s_owner" % _next_id()
	# Insert a minimal characters row so the FK from domains.owner_character_id holds.
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name)
		VALUES (?, ?, 'OwnerChar')
	""", [owner_id, _campaign_id])
	var domain_id: String = CampaignRepository.create_domain({
		"campaign_id": _campaign_id, "name": "OwnedDomain",
		"owner_character_id": owner_id,
	})
	var s: String = _make_settlement({
		"name": "OwnedSettlement", "parent_domain_id": domain_id,
	})
	check(MarketFeesCalculator.is_domain_owner_in_own_market(owner_id, s),
		"owner of parent_domain should test true")
	# Other character is not the owner.
	var other_id: String = "%s_other" % _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name)
		VALUES (?, ?, 'OtherChar')
	""", [other_id, _campaign_id])
	check(not MarketFeesCalculator.is_domain_owner_in_own_market(other_id, s),
		"non-owner should test false")
	# Settlement without parent_domain.
	var unowned: String = _make_settlement({"name": "NoParentSettlement"})
	check(not MarketFeesCalculator.is_domain_owner_in_own_market(owner_id, unowned),
		"settlement with NULL parent_domain_id → false")
