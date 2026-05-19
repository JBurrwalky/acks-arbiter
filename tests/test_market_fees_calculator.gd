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
	test_customs_duty_fractional_cp_rounds_bankers()
	test_customs_duty_zero_price()
	test_customs_duty_domain_owner_exemption()
	test_annual_customs_roll_determinism()
	test_annual_customs_roll_range()
	test_process_annual_customs_roll_for_campaign()

	# Labor
	test_labor_fee_exact_multiples()
	test_labor_fee_cp_precision_below_gp()
	test_labor_fee_odd_stone_banker_rounds_to_whole_cp()
	test_labor_fee_zero_and_negative()

	# Moorage
	test_moorage_per_day()
	test_moorage_multi_day_aggregate()
	test_moorage_domain_owner_exemption()

	# Stabling
	test_stabling_mixed_mounts_per_day()
	test_stabling_multi_day_aggregate()
	test_stabling_warhorse_premium_rate()
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
# Entry toll — returns cp per the 2026-05-15 currency-precision rule.
# RAW dice rolls produce whole-gp values; cp result = rolled_gp × 100 (exact).
# ---------------------------------------------------------------------------

func test_entry_toll_dice_range_class_i() -> void:
	# Class I toll = 1d6+15 gp → [16, 21] gp = [1600, 2100] cp.
	var rng: RandomNumberGenerator = _seeded_rng(1)
	var min_seen: int = 99999
	var max_seen: int = 0
	for _i in 500:
		var v: int = MarketFeesCalculator.entry_toll_cp(1, false, 0, rng, false)
		if v < min_seen:
			min_seen = v
		if v > max_seen:
			max_seen = v
	check(min_seen >= 1600, "Class I toll min should be ≥ 1600 cp, got %d" % min_seen)
	check(max_seen <= 2100, "Class I toll max should be ≤ 2100 cp, got %d" % max_seen)


func test_entry_toll_selling_minimum_kicks_in() -> void:
	# Class VI roll = 1d3 gp → 1..3 gp = 100..300 cp. Sell 10 loads → minimum
	# 10 gp = 1000 cp dominates.
	for trial in range(10):
		var rng: RandomNumberGenerator = _seeded_rng(trial * 7 + 1)
		var v: int = MarketFeesCalculator.entry_toll_cp(6, true, 10, rng, false)
		check(v == 1000,
			"selling minimum: VI roll ≤ 300 cp, 10-load minimum 1000 cp dominates → 1000, got %d (seed %d)" % [v, trial])


func test_entry_toll_selling_dice_exceeds_minimum() -> void:
	# Class I roll = 1d6+15 gp → ≥ 1600 cp. Sell 5 loads → 500 cp min < dice.
	for trial in range(10):
		var rng: RandomNumberGenerator = _seeded_rng(trial)
		var v: int = MarketFeesCalculator.entry_toll_cp(1, true, 5, rng, false)
		check(v >= 1600, "dice exceeds minimum: result should be ≥ 1600 cp, got %d" % v)


func test_entry_toll_domain_owner_exemption() -> void:
	var rng: RandomNumberGenerator = _seeded_rng(42)
	check(MarketFeesCalculator.entry_toll_cp(1, false, 0, rng, true) == 0,
		"domain owner pays 0 toll regardless of class")
	check(MarketFeesCalculator.entry_toll_cp(1, true, 100, rng, true) == 0,
		"domain owner pays 0 toll even when selling 100 loads")


# ---------------------------------------------------------------------------
# Customs duty — cp-native. rate_pct × price_cp / 100 = rate_pct × price_gp
# (when input is a whole-gp price). Banker's rounding only fires on
# fractional cp (e.g., odd-cp prices × odd-pct rate).
# ---------------------------------------------------------------------------

func test_customs_duty_uses_cached_rate() -> void:
	# 15% of 1000 gp = 150 gp = 15,000 cp (exact).
	var s: String = _make_settlement({"customs_duty_rate_pct": 15, "name": "Customs15"})
	check(MarketFeesCalculator.customs_duty_cp(100000, s, false) == 15000,
		"customs at 15%% on 100,000 cp → 15,000, got %d" % MarketFeesCalculator.customs_duty_cp(100000, s, false))
	# 12% of 333 gp = 12% of 33,300 cp = 3,996 cp (exact).
	var s2: String = _make_settlement({"customs_duty_rate_pct": 12, "name": "Customs12"})
	check(MarketFeesCalculator.customs_duty_cp(33300, s2, false) == 3996,
		"customs at 12%% on 33,300 cp → 3996, got %d" % MarketFeesCalculator.customs_duty_cp(33300, s2, false))


func test_customs_duty_fractional_cp_rounds_bankers() -> void:
	# 7% of 13 cp = 0.91 cp → banker → 1 cp (closer to 1 than 0).
	var s: String = _make_settlement({"customs_duty_rate_pct": 7, "name": "Customs7Frac"})
	check(MarketFeesCalculator.customs_duty_cp(13, s, false) == 1,
		"7%% × 13 cp = 0.91 cp → banker 1, got %d" % MarketFeesCalculator.customs_duty_cp(13, s, false))
	# 5% of 50 cp = 2.5 cp → banker → 2 cp (2 is even).
	var s2: String = _make_settlement({"customs_duty_rate_pct": 5, "name": "Customs5Half"})
	check(MarketFeesCalculator.customs_duty_cp(50, s2, false) == 2,
		"5%% × 50 cp = 2.5 cp → banker 2, got %d" % MarketFeesCalculator.customs_duty_cp(50, s2, false))


func test_customs_duty_zero_price() -> void:
	var s: String = _make_settlement({"customs_duty_rate_pct": 20, "name": "Customs20Zero"})
	check(MarketFeesCalculator.customs_duty_cp(0, s, false) == 0,
		"customs on 0 cp price → 0")


func test_customs_duty_domain_owner_exemption() -> void:
	var s: String = _make_settlement({"customs_duty_rate_pct": 15, "name": "Customs15Owner"})
	check(MarketFeesCalculator.customs_duty_cp(100000, s, true) == 0,
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
# Labor — cp-native. 1 gp per 200 stone = 100 cp / 200 stone = stone / 2 cp.
# Even stone is exact; odd stone produces fractional cp resolved by banker's.
# ---------------------------------------------------------------------------

func test_labor_fee_exact_multiples() -> void:
	check(MarketFeesCalculator.labor_fee_cp(200) == 100, "200 stone → 100 cp (= 1 gp)")
	check(MarketFeesCalculator.labor_fee_cp(400) == 200, "400 stone → 200 cp (= 2 gp)")
	check(MarketFeesCalculator.labor_fee_cp(2000) == 1000, "2000 stone → 1000 cp (= 10 gp)")


func test_labor_fee_cp_precision_below_gp() -> void:
	# 100 stone = 50 cp exact (no rounding — was banker→0 gp under the old gp path).
	check(MarketFeesCalculator.labor_fee_cp(100) == 50,
		"100 stone → 50 cp (exact, no rounding), got %d" % MarketFeesCalculator.labor_fee_cp(100))
	# 300 stone = 150 cp exact (was banker→2 gp under the old gp path).
	check(MarketFeesCalculator.labor_fee_cp(300) == 150,
		"300 stone → 150 cp exact, got %d" % MarketFeesCalculator.labor_fee_cp(300))
	# 3760 stone = 1880 cp exact (was banker→19 gp = 1900 cp under the old gp path).
	check(MarketFeesCalculator.labor_fee_cp(3760) == 1880,
		"3760 stone → 1880 cp exact, got %d" % MarketFeesCalculator.labor_fee_cp(3760))


func test_labor_fee_odd_stone_banker_rounds_to_whole_cp() -> void:
	# 1 stone = 0.5 cp → banker → 0 (0 is even).
	check(MarketFeesCalculator.labor_fee_cp(1) == 0,
		"1 stone → 0.5 cp → banker 0, got %d" % MarketFeesCalculator.labor_fee_cp(1))
	# 3 stone = 1.5 cp → banker → 2 (closer-to-even resolves up).
	check(MarketFeesCalculator.labor_fee_cp(3) == 2,
		"3 stone → 1.5 cp → banker 2, got %d" % MarketFeesCalculator.labor_fee_cp(3))
	# 5 stone = 2.5 cp → banker → 2 (2 is even).
	check(MarketFeesCalculator.labor_fee_cp(5) == 2,
		"5 stone → 2.5 cp → banker 2, got %d" % MarketFeesCalculator.labor_fee_cp(5))


func test_labor_fee_zero_and_negative() -> void:
	check(MarketFeesCalculator.labor_fee_cp(0) == 0, "0 stone → 0 cp")
	check(MarketFeesCalculator.labor_fee_cp(-50) == 0, "negative → 0 (defensive)")


# ---------------------------------------------------------------------------
# Moorage — cp is the project's base currency; values are exact integers per
# the 2026-05-15 currency-precision rule (no banker's rounding on fractional gp).
# ---------------------------------------------------------------------------

func test_moorage_per_day() -> void:
	# RAW: 1 gp per 10 SHP per day = 10 cp per SHP per day.
	check(MarketFeesCalculator.moorage_cp_per_day(30, false) == 300, "30 SHP → 300 cp/day")
	check(MarketFeesCalculator.moorage_cp_per_day(5, false) == 50, "5 SHP → 50 cp/day (no rounding)")
	check(MarketFeesCalculator.moorage_cp_per_day(15, false) == 150, "15 SHP → 150 cp/day")
	check(MarketFeesCalculator.moorage_cp_per_day(0, false) == 0, "0 SHP → 0")


func test_moorage_multi_day_aggregate() -> void:
	# 5 SHP × 7 days × 10 cp = 350 cp (was 3.5 gp under old banker logic).
	check(MarketFeesCalculator.moorage_cp_total(5, 7, false) == 350,
		"5 SHP × 7 days → 350 cp, got %d" % MarketFeesCalculator.moorage_cp_total(5, 7, false))
	# 30 SHP × 14 days × 10 cp = 4200 cp (= 42 gp clean).
	check(MarketFeesCalculator.moorage_cp_total(30, 14, false) == 4200,
		"30 SHP × 14 days → 4200 cp")


func test_moorage_domain_owner_exemption() -> void:
	check(MarketFeesCalculator.moorage_cp_per_day(30, true) == 0,
		"domain owner pays 0 moorage per day")
	check(MarketFeesCalculator.moorage_cp_total(30, 14, true) == 0,
		"domain owner pays 0 moorage total")


# ---------------------------------------------------------------------------
# Stabling — cp variants only. Rates are whole-cp integers per the
# 2026-05-15 currency-precision rule.
# ---------------------------------------------------------------------------

func test_stabling_mixed_mounts_per_day() -> void:
	# 5 mules × 20 cp + 2 horses × 50 cp = 100 + 100 = 200 cp/day.
	var mounts := {"mule": 5, "horse": 2}
	check(MarketFeesCalculator.stabling_cp_per_day(mounts, false) == 200,
		"5 mules + 2 horses → 200 cp/day, got %d" % MarketFeesCalculator.stabling_cp_per_day(mounts, false))
	# 1 horse → 50 cp/day (no rounding; this is an exact integer).
	check(MarketFeesCalculator.stabling_cp_per_day({"horse": 1}, false) == 50,
		"1 horse → 50 cp/day")
	# 1 horse × 2 days = 100 cp.
	check(MarketFeesCalculator.stabling_cp_total({"horse": 1}, 2, false) == 100,
		"1 horse × 2 days → 100 cp")
	# 1 horse × 7 days = 350 cp (no rounding — exact).
	check(MarketFeesCalculator.stabling_cp_total({"horse": 1}, 7, false) == 350,
		"1 horse × 7 days → 350 cp, got %d" % MarketFeesCalculator.stabling_cp_total({"horse": 1}, 7, false))


func test_stabling_multi_day_aggregate() -> void:
	# 4 oxen × 80 cp × 7 days = 2240 cp.
	check(MarketFeesCalculator.stabling_cp_total({"ox": 4}, 7, false) == 2240,
		"4 oxen × 7 days → 2240 cp, got %d" % MarketFeesCalculator.stabling_cp_total({"ox": 4}, 7, false))
	# 3 wagons × 200 cp × 14 days = 8400 cp.
	check(MarketFeesCalculator.stabling_cp_total({"wagon": 3}, 14, false) == 8400,
		"3 wagons × 14 days → 8400 cp")
	# Mix: 5 mule + 2 horse + 1 wagon × 7 days
	# = (5×20 + 2×50 + 1×200) × 7 = (100 + 100 + 200) × 7 = 2800 cp.
	check(MarketFeesCalculator.stabling_cp_total({"mule": 5, "horse": 2, "wagon": 1}, 7, false) == 2800,
		"5 mule + 2 horse + 1 wagon × 7 days → 2800 cp")
	# Test the donkey/camel aliases.
	check(MarketFeesCalculator.stabling_cp_total({"donkey": 5}, 10, false) ==
			MarketFeesCalculator.stabling_cp_total({"mule": 5}, 10, false),
		"donkey rate matches mule rate (project-design fill)")
	check(MarketFeesCalculator.stabling_cp_total({"camel": 4}, 5, false) ==
			MarketFeesCalculator.stabling_cp_total({"horse": 4}, 5, false),
		"camel rate matches horse rate")


func test_stabling_warhorse_premium_rate() -> void:
	# Per RAW, war horses stable at 1 gp/night = 100 cp/night.
	# 1 warhorse × 3 days = 300 cp.
	check(MarketFeesCalculator.stabling_cp_total({"warhorse": 1}, 3, false) == 300,
		"1 warhorse × 3 days = 300 cp (100 cp/night), got %d" %
			MarketFeesCalculator.stabling_cp_total({"warhorse": 1}, 3, false))
	# 2 warhorses + 1 horse × 1 day = 2×100 + 50 = 250 cp (exact, no rounding).
	check(MarketFeesCalculator.stabling_cp_total({"warhorse": 2, "horse": 1}, 1, false) == 250,
		"mixed warhorse + horse → 250 cp exact, got %d" %
			MarketFeesCalculator.stabling_cp_total({"warhorse": 2, "horse": 1}, 1, false))


func test_stabling_unknown_key_contributes_zero() -> void:
	# Genuinely unknown key — caller is expected to map species to canonical
	# keys before calling stabling_cp_total; unmapped values silently 0.
	check(MarketFeesCalculator.stabling_cp_total({"chimera": 100}, 30, false) == 0,
		"unknown key 'chimera' contributes 0 (caller must map to canonical key)")
	# Mixed with known keys: known keys still contribute correctly.
	check(MarketFeesCalculator.stabling_cp_total({"chimera": 5, "horse": 2}, 1, false) ==
			MarketFeesCalculator.stabling_cp_total({"horse": 2}, 1, false),
		"unknown key in mix doesn't affect known key's contribution")


func test_stabling_domain_owner_exemption() -> void:
	check(MarketFeesCalculator.stabling_cp_per_day({"horse": 10, "wagon": 5}, true) == 0,
		"domain owner pays 0 stabling per day")
	check(MarketFeesCalculator.stabling_cp_total({"horse": 10, "wagon": 5}, 14, true) == 0,
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
