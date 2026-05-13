extends "res://tests/test_suite_base.gd"

## End-to-end commerce integration test — reproduces the §12 Ashford/Thornwall
## worked example through the live commerce services. Three scenarios per
## generation/gdd-settlement-economy.md §12.7:
##   * Baseline (Ashford customs at 4%) → +8,940 gp delta
##   * Scenario B (Ashford customs at 16%) → +5,820 gp delta
##   * Scenario C (PC-owned Ashford domain) → +9,992 gp delta
##
## The §12 numbers are the regression anchor: if a future refactor produces
## different outputs, this test fails and the diff points to the broken stage.
##
## What this test exercises end-to-end:
##   * MerchandiseRegistry (silk base price 2000 gp, load weight 20 stone)
##   * DemandModifierGenerator.get_demand_modifier (cache read)
##   * MarketPriceResolver.compute_market_price (full RAW 8-step formula)
##   * MarketFeesCalculator (toll dice / labor / customs / stabling)
##   * CargoHoldRepository (insert_purchase + delete_sold)
##   * PartyWallet.pay + CampaignRepository.add_coins_cp (gold movement)
##
## What this test pins (per §12.7 RNG-fixture rationale):
##   * Demand modifiers seeded directly into settlement_merchandise_demand
##     (Ashford silk = +3 post-shift; Thornwall silk = -1 post-shift). Skips
##     the §4.1 base roll + §4.4 land-revenue shuffle dice paths — those have
##     dedicated unit tests in test_demand_modifier_generator.gd.
##   * 4d4 dice forced to 10 for silk at both settlements (the §12.4 pinned value).
##   * Annual customs rate set directly on settlement_entrances rows.
##   * Entry-toll dice probed for the §12.5 specified values (Class V toll 4;
##     Class III toll 10 from 1d8+5 with d8=5). Probe is fast (< 256 iterations).


# ---------------------------------------------------------------------------
# Fixture state — rebuilt per scenario so each test runs in isolation.
# ---------------------------------------------------------------------------

var _suffix: int = 0


func run_all_tests() -> void:
	test_baseline_round_trip_delta_is_plus_8940()
	test_scenario_b_customs_16pct_delta_is_plus_5820()
	test_scenario_c_pc_owned_ashford_delta_is_plus_9992()

	if not has_failures():
		print("CommerceIntegration: all %d tests passed." % test_count())


# ---------------------------------------------------------------------------
# Scenario A — baseline (Ashford customs at 4%, no PC ownership)
# ---------------------------------------------------------------------------

func test_baseline_round_trip_delta_is_plus_8940() -> void:
	var fx: Dictionary = _build_fixture("Baseline", 4, false)
	var delta: int = _run_round_trip(fx, 4, false)
	check(delta == 8940,
		"Baseline scenario: round-trip delta should be +8,940 gp, got %+d" % delta)


# ---------------------------------------------------------------------------
# Scenario B — Ashford customs at 16% (rolled high)
# ---------------------------------------------------------------------------

func test_scenario_b_customs_16pct_delta_is_plus_5820() -> void:
	var fx: Dictionary = _build_fixture("ScenarioB", 16, false)
	var delta: int = _run_round_trip(fx, 16, false)
	check(delta == 5820,
		"Scenario B (16%% customs): round-trip delta should be +5,820 gp, got %+d" % delta)


# ---------------------------------------------------------------------------
# Scenario C — PC-owned Ashford (entry toll + customs + stabling exempt;
# labor NOT exempt per §8.8)
# ---------------------------------------------------------------------------

func test_scenario_c_pc_owned_ashford_delta_is_plus_9992() -> void:
	# Customs rate is ignored for the PC-owner case (exempt regardless), but
	# we set it to 4% to mirror the baseline parameters cleanly.
	var fx: Dictionary = _build_fixture("ScenarioC", 4, true)
	var delta: int = _run_round_trip(fx, 4, true)
	check(delta == 9992,
		"Scenario C (PC-owned Ashford): round-trip delta should be +9,992 gp, got %+d" % delta)


# ---------------------------------------------------------------------------
# Fixture builder
# ---------------------------------------------------------------------------

## Constructs a fresh campaign with Ashford + Thornwall, a wagon, a PC with
## 100,000 gp of starting wealth, demand modifiers seeded for silk, dice
## cache forced to 10 for silk at both markets, and customs rates set.
##
## [param customs_pct] — Ashford's customs_duty_rate_pct.
## [param pc_owns_ashford] — when true, makes Ashford's parent domain owned
## by the PC (triggers domain-owner exemption in §8.8).
##
## Returns dict with: campaign_id, ashford_id, thornwall_id, wagon_id, pc_id, party_id.
func _build_fixture(name_suffix: String, customs_pct: int, pc_owns_ashford: bool) -> Dictionary:
	var campaign_id: String = CampaignRepository.create_campaign("CommerceIntegration_%s" % name_suffix, "World")
	var map_id: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO hex_maps (id, campaign_id, name, scale) VALUES (?, ?, ?, 'regional_6mi')",
		[map_id, campaign_id, "AshfordMap_%s" % name_suffix])

	# PC character.
	var pc_id: String = "%s_pc" % _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type)
		VALUES (?, ?, 'Merchant Adventurer', 'pc')
	""", [pc_id, campaign_id])

	# Party + membership.
	var party_id: String = "%s_party" % _next_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO parties (id, campaign_id, name) VALUES (?, ?, 'Trading Party')",
		[party_id, campaign_id])
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO party_members (party_id, character_id) VALUES (?, ?)",
		[party_id, pc_id])

	# Seed PC with 100,000 gp = 10,000,000 cp — comfortably above the
	# 16,000-gp buy capital outlay.
	CampaignRepository.add_coins_cp(pc_id, 10_000_000)

	# Domains: Ashford has a parent domain (so PC-ownership test works);
	# Thornwall stays unowned (parent_domain_id NULL).
	var ashford_domain_id: String = CampaignRepository.create_domain({
		"campaign_id": campaign_id,
		"name": "Ashford Domain %s" % name_suffix,
		"owner_character_id": pc_id if pc_owns_ashford else null,
	})

	# Settlements.
	var ashford_id: String = "%s_ashford" % _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_entrances
			(id, campaign_id, map_id, hex_q, hex_r, name, market_class,
			 urban_families, age_years, dominant_race, parent_domain_id,
			 customs_duty_rate_pct)
		VALUES (?, ?, ?, 0, 0, 'Ashford', 3, 2400, 500, 'human', ?, ?)
	""", [ashford_id, campaign_id, map_id, ashford_domain_id, customs_pct])

	var thornwall_id: String = "%s_thornwall" % _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_entrances
			(id, campaign_id, map_id, hex_q, hex_r, name, market_class,
			 urban_families, age_years, dominant_race,
			 customs_duty_rate_pct)
		VALUES (?, ?, ?, 2, 1, 'Thornwall', 5, 400, 200, 'human', 8)
	""", [thornwall_id, campaign_id, map_id])

	# Demand modifier cache: post-shift values per §12.3 (Ashford silk +3,
	# Thornwall silk -1). Seeded with pre_trade_route_shift_value == demand_modifier
	# (the post-shift values are what compute_market_price reads).
	for sid in [ashford_id]:
		_seed_demand(sid, "silk", 3)
	for sid in [thornwall_id]:
		_seed_demand(sid, "silk", -1)

	# Force the 4d4 dice to 10 at both markets (the §12.4 pinned value).
	_force_dice(ashford_id, "silk", 10, 0)
	_force_dice(thornwall_id, "silk", 10, 0)

	# Wagon (owned by the party). hitched_creatures = 4 heavy horses for full
	# wagon capacity (load_max = 640 stone — easily covers 200 stone of silk).
	var wagon_id: String = "%s_wagon" % _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO draft_vehicles (id, campaign_id, party_id, item_key, name, hitched_creatures)
		VALUES (?, ?, ?, 'wagon', 'Merchant Wagon',
			'[{"species_id":"horse_heavy"},{"species_id":"horse_heavy"},{"species_id":"horse_heavy"},{"species_id":"horse_heavy"}]')
	""", [wagon_id, campaign_id, party_id])

	# Trade route (manually inserted — equivalent to TradeRouteDetector having
	# detected the road path; the §5 detector is exercised by its own unit tests).
	var route_id: String = CampaignRepository.generate_id()
	var pair_a: String = ashford_id
	var pair_b: String = thornwall_id
	if pair_a > pair_b:
		var tmp: String = pair_a
		pair_a = pair_b
		pair_b = tmp
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO trade_routes
			(id, campaign_id, settlement_a_id, settlement_b_id,
			 path_kind, distance_hexes, discovered_at_calendar_day, invalidated)
		VALUES (?, ?, ?, ?, 'road', 3, 0, 0)
	""", [route_id, campaign_id, pair_a, pair_b])

	return {
		"campaign_id": campaign_id,
		"ashford_id": ashford_id,
		"thornwall_id": thornwall_id,
		"wagon_id": wagon_id,
		"pc_id": pc_id,
		"party_id": party_id,
	}


# ---------------------------------------------------------------------------
# Round-trip runner — buys 10 loads of silk at Thornwall, transports, sells
# at Ashford. Returns the round-trip gp delta (final - initial wealth).
# ---------------------------------------------------------------------------

func _run_round_trip(fx: Dictionary, ashford_customs_pct: int, pc_owns_ashford: bool) -> int:
	var ashford_id: String = fx["ashford_id"]
	var thornwall_id: String = fx["thornwall_id"]
	var wagon_id: String = fx["wagon_id"]
	var pc_id: String = fx["pc_id"]
	var party_id: String = fx["party_id"]

	# Sanity-check the pricing inputs match §12.4 expectations.
	var thornwall_price_result: Dictionary = MarketPriceResolver.compute_market_price(
		"silk", thornwall_id, 0, 0, null, 0)
	check(int(thornwall_price_result["gp_per_load"]) == 1600,
		"Thornwall silk price should be 1,600 gp/load, got %d" % int(thornwall_price_result["gp_per_load"]))

	var ashford_price_result: Dictionary = MarketPriceResolver.compute_market_price(
		"silk", ashford_id, 0, 0, null, 0)
	check(int(ashford_price_result["gp_per_load"]) == 2600,
		"Ashford silk price should be 2,600 gp/load, got %d" % int(ashford_price_result["gp_per_load"]))

	# --- Phase 1: Buy at Thornwall (10 loads × 1,600 gp = 16,000 gp) ---
	var wealth_before: int = CampaignRepository.get_character_wealth_cp(pc_id)
	var thornwall_total_price: int = 10 * 1600

	# Debit purchase price.
	var pay_result: Dictionary = PartyWallet.pay(thornwall_total_price * 100, party_id, pc_id)
	check(bool(pay_result.get("ok", false)), "Thornwall silk purchase debit should succeed")

	# Pay Thornwall entry toll. Per §12.5: pinned 1d6 roll = 4. At Thornwall the
	# party is BUYING, so is_selling=false (no per-load minimum applies).
	var thornwall_toll_rng: RandomNumberGenerator = _probed_rng_for_d6_equals(4)
	var thornwall_toll: int = MarketFeesCalculator.entry_toll_gp(5, false, 0, thornwall_toll_rng, false)
	check(thornwall_toll == 4,
		"Thornwall Class V toll with pinned d6=4 should be 4 gp, got %d" % thornwall_toll)
	PartyWallet.pay(thornwall_toll * 100, party_id, pc_id)

	# Loading labor: 10 loads × 20 stone = 200 stone → 1 gp.
	var thornwall_labor: int = MarketFeesCalculator.labor_fee_gp(200)
	check(thornwall_labor == 1, "Thornwall loading labor for 200 stone = 1 gp")
	PartyWallet.pay(thornwall_labor * 100, party_id, pc_id)

	# Stabling at Thornwall during loading: 1 wagon × 1 day = 2 gp.
	var thornwall_stabling: int = MarketFeesCalculator.stabling_gp_total({"wagon": 1}, 1, false)
	check(thornwall_stabling == 2, "Thornwall stabling 1 wagon × 1 day = 2 gp")
	PartyWallet.pay(thornwall_stabling * 100, party_id, pc_id)

	# Insert cargo onto the wagon.
	var cargo_id: String = CargoHoldRepository.insert_purchase(
		wagon_id, CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
		"silk", 10, thornwall_total_price, thornwall_id, 0)
	check(not cargo_id.is_empty(), "Silk cargo inserted on wagon")

	# --- Phase 2: Transport (wilderness movement — no commerce fees) ---
	# Calendar advances ~3 days; the commerce flow doesn't model wilderness travel.

	# --- Phase 3: Sell at Ashford (10 loads × 2,600 gp = 26,000 gp) ---
	var ashford_total_price: int = 10 * 2600

	# Ashford entry toll: pinned 1d8 = 5 → toll = 5 + 5 = 10 (or 0 if PC-owned).
	var ashford_toll_rng: RandomNumberGenerator = _probed_rng_for_d8_equals(5)
	var ashford_toll: int = MarketFeesCalculator.entry_toll_gp(3, true, 10, ashford_toll_rng, pc_owns_ashford)
	if pc_owns_ashford:
		check(ashford_toll == 0, "PC-owner Ashford toll exempt → 0 gp")
	else:
		check(ashford_toll == 10, "Ashford Class III toll with pinned d8=5 = 1d8+5 = 10 gp")
	PartyWallet.pay(ashford_toll * 100, party_id, pc_id)

	# Unloading labor (NOT exempt for domain owner per §8.8): 200 stone → 1 gp.
	var ashford_labor: int = MarketFeesCalculator.labor_fee_gp(200)
	check(ashford_labor == 1, "Ashford unloading labor = 1 gp (labor NOT domain-owner exempt)")
	PartyWallet.pay(ashford_labor * 100, party_id, pc_id)

	# Customs duty at Ashford (exempt for PC-owner; else customs_pct × sell_price).
	var ashford_customs: int = MarketFeesCalculator.customs_duty_gp(
		ashford_total_price, ashford_id, pc_owns_ashford)
	if pc_owns_ashford:
		check(ashford_customs == 0, "PC-owner Ashford customs exempt → 0 gp")
	elif ashford_customs_pct == 4:
		check(ashford_customs == 1040, "Ashford customs at 4%% of 26,000 = 1,040 gp")
	elif ashford_customs_pct == 16:
		check(ashford_customs == 4160, "Ashford customs at 16%% of 26,000 = 4,160 gp")
	PartyWallet.pay(ashford_customs * 100, party_id, pc_id)

	# Stabling at Ashford during sale: 1 wagon × 1 day = 2 gp (exempt for PC-owner).
	var ashford_stabling: int = MarketFeesCalculator.stabling_gp_total(
		{"wagon": 1}, 1, pc_owns_ashford)
	if pc_owns_ashford:
		check(ashford_stabling == 0, "PC-owner Ashford stabling exempt → 0 gp")
	else:
		check(ashford_stabling == 2, "Ashford stabling 1 wagon × 1 day = 2 gp")
	PartyWallet.pay(ashford_stabling * 100, party_id, pc_id)

	# Credit the sale + delete the cargo row.
	CampaignRepository.add_coins_cp(pc_id, ashford_total_price * 100)
	check(CargoHoldRepository.delete_sold(cargo_id, ashford_total_price),
		"Cargo deleted on sell")

	# Compute round-trip delta in gp.
	var wealth_after: int = CampaignRepository.get_character_wealth_cp(pc_id)
	return int((wealth_after - wealth_before) / 100)


# ---------------------------------------------------------------------------
# Cache seeding helpers (mirroring the test_market_price_resolver pattern)
# ---------------------------------------------------------------------------

func _seed_demand(settlement_id: String, merchandise_type: String, value: int) -> void:
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
	# Ensure a row exists without clobbering an existing demand_modifier.
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO settlement_merchandise_demand
			(settlement_entrance_id, merchandise_type, demand_modifier,
			 generated_at_calendar_day, source_kind, pre_trade_route_shift_value)
		VALUES (?, ?, 0, 0, 'generated', 0)
	""", [settlement_id, merchandise_type])
	CampaignRepository.db.query_with_bindings("""
		UPDATE settlement_merchandise_demand
		SET dice_4d4_value = ?, dice_last_rolled_calendar_day = ?
		WHERE settlement_entrance_id = ? AND merchandise_type = ?
	""", [dice, rolled_day, settlement_id, merchandise_type])


# ---------------------------------------------------------------------------
# RNG seed probes — find a seed where the FIRST randi_range call returns the
# target value. Brute-force search bounded at 256 iterations (Godot 4's RNG
# distribution makes any [1, N] target almost-certainly findable within N×8
# seeds).
# ---------------------------------------------------------------------------

func _probed_rng_for_d6_equals(target: int) -> RandomNumberGenerator:
	return _probed_rng(6, target)


func _probed_rng_for_d8_equals(target: int) -> RandomNumberGenerator:
	return _probed_rng(8, target)


func _probed_rng(sides: int, target: int) -> RandomNumberGenerator:
	for seed_val in range(1, 1024):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_val
		var roll: int = rng.randi_range(1, sides)
		if roll == target:
			# Reset to fresh state — the probe consumed the first call.
			var fresh := RandomNumberGenerator.new()
			fresh.seed = seed_val
			return fresh
	push_error("_probed_rng: could not find seed for d%d=%d within 1024 tries" % [sides, target])
	var fallback := RandomNumberGenerator.new()
	fallback.randomize()
	return fallback


func _next_id() -> String:
	_suffix += 1
	return "comm_int_%d_%d" % [Time.get_ticks_msec(), _suffix]
