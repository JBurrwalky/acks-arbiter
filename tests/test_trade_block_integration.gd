extends "res://tests/test_suite_base.gd"

## End-to-end Trade-block integration test — Phase 10B.2 Wave 6 (close-out).
##
## Per gdd-phase-10b-2-trade-block.md §18.3 + §19.6. Reproduces the §12
## Ashford/Thornwall worked example THROUGH the new buy/sell handlers
## (not the direct substrate calls covered by Prereq.8's
## test_commerce_integration.gd).
##
## Three scenarios (regression anchors from §12.7):
##   * Baseline (Ashford customs 4%): +8,940 gp delta
##   * Scenario B (Ashford customs 16%): +5,820 gp delta
##   * Scenario C (PC-owned Ashford): +9,992 gp delta
##
## The handler-routed flow:
##   1. VisitStateManager.on_party_entered_settlement(Thornwall) — auto-rolls
##      offers (irrelevant here) + creates visit row.
##   2. Pre-charge Thornwall toll (4 gp, Class V 1d6 pinned via probed RNG)
##      + mark_entry_toll_paid so the BuyMerchandiseHandler's internal toll
##      computation short-circuits to 0.
##   3. BuyMerchandiseHandler.on_complete → purchase 10 silk @ 1,600 gp/load
##      + labor (1 gp). Toll already paid above.
##   4. VisitStateManager.on_party_departed_settlement(Thornwall) — debits
##      2 gp stabling (1 wagon × 1 day).
##   5. VisitStateManager.on_party_entered_settlement(Ashford) — fresh visit.
##   6. Pre-charge Ashford toll (10 gp Class III 1d8+5 with d8=5; OR 0 gp
##      PC-owner exempt).
##   7. SellMerchandiseHandler.on_complete → sell 10 silk @ 2,600 gp/load -
##      labor (1 gp) - customs (4% / 16% / 0).
##   8. VisitStateManager.on_party_departed_settlement(Ashford) — debits
##      2 gp stabling (or 0 PC-owner exempt).
##
## Pre-charging the toll is the test-fixture's way of pinning specific roll
## values when the handler's transaction_rng is internally seeded via hash().
## The handler's `BuySellCommon.charge_entry_toll_if_first_visit` checks
## `VisitStateManager.has_paid_entry_toll` and returns 0 if already paid.
## Externally pre-charging via the substrate's MarketFeesCalculator + a
## probed RNG matches Prereq.8's pinned-roll discipline.


var _suffix: int = 0


func run_all_tests() -> void:
	test_baseline_handler_routed_delta_is_plus_8940()
	test_scenario_b_customs_16pct_handler_routed_delta_is_plus_5820()
	test_scenario_c_pc_owned_ashford_handler_routed_delta_is_plus_9992()

	if not has_failures():
		print("TradeBlockIntegration: all %d tests passed." % test_count())


# ---------------------------------------------------------------------------
# Scenarios
# ---------------------------------------------------------------------------

func test_baseline_handler_routed_delta_is_plus_8940() -> void:
	var fx: Dictionary = _build_fixture("Baseline", 4, false)
	var delta: int = _run_round_trip(fx, 4, false)
	check(delta == 8940,
		"Baseline (4%% customs, handler-routed): delta should be +8,940 gp, got %+d" % delta)


func test_scenario_b_customs_16pct_handler_routed_delta_is_plus_5820() -> void:
	var fx: Dictionary = _build_fixture("ScenarioB", 16, false)
	var delta: int = _run_round_trip(fx, 16, false)
	check(delta == 5820,
		"Scenario B (16%% customs, handler-routed): delta should be +5,820 gp, got %+d" % delta)


func test_scenario_c_pc_owned_ashford_handler_routed_delta_is_plus_9992() -> void:
	var fx: Dictionary = _build_fixture("ScenarioC", 4, true)
	var delta: int = _run_round_trip(fx, 4, true)
	check(delta == 9992,
		"Scenario C (PC-owned Ashford, handler-routed): delta should be +9,992 gp, got %+d" % delta)


# ---------------------------------------------------------------------------
# Fixture builder — campaign + 2 settlements + trade route + wagon + 1 silk
# merchant at each market with enough loads_available.
# ---------------------------------------------------------------------------

func _build_fixture(name_suffix: String, customs_pct: int, pc_owns_ashford: bool) -> Dictionary:
	var campaign_id: String = CampaignRepository.create_campaign("TradeBlockIntegration_" + name_suffix, "World")
	var map_id: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO hex_maps (id, campaign_id, name, scale) VALUES (?, ?, ?, 'regional_6mi')",
		[map_id, campaign_id, "TBIMap_" + name_suffix])

	var pc_id: String = "%s_pc" % _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type)
		VALUES (?, ?, 'Handler Trader', 'pc')
	""", [pc_id, campaign_id])

	var party_id: String = "%s_party" % _next_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO parties (id, campaign_id, name) VALUES (?, ?, 'Trading Party')",
		[party_id, campaign_id])
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO party_members (party_id, character_id) VALUES (?, ?)",
		[party_id, pc_id])

	# 10,000 gp = 1,000,000 cp starting wealth — comfortably above the
	# 16,000 gp purchase. We need a LOT — pre-Wave-6 attempts had wealth
	# issues. Use 100,000 gp like Prereq.8.
	CampaignRepository.add_coins_cp(pc_id, 10_000_000)

	# Ashford domain (PC-owned in Scenario C).
	var ashford_domain_id: String = CampaignRepository.create_domain({
		"campaign_id": campaign_id,
		"name": "Ashford Domain " + name_suffix,
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

	# Demand cache: Ashford silk +3, Thornwall silk -1 (post-shift values).
	_seed_demand(ashford_id, "silk", 3)
	_seed_demand(thornwall_id, "silk", -1)

	# 4d4 cache → 10 at both markets (§12.4 pinned).
	_force_dice(ashford_id, "silk", 10)
	_force_dice(thornwall_id, "silk", 10)

	# Wagon (4 heavy horses = 640 stone load_max).
	var wagon_id: String = "%s_wagon" % _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO draft_vehicles (id, campaign_id, party_id, item_key, name, hitched_creatures)
		VALUES (?, ?, ?, 'wagon', 'Merchant Wagon',
			'[{"species_id":"horse_heavy"},{"species_id":"horse_heavy"},{"species_id":"horse_heavy"},{"species_id":"horse_heavy"}]')
	""", [wagon_id, campaign_id, party_id])

	# Trade route (manually inserted; canonical (a, b) ordering).
	var pair_a: String = ashford_id
	var pair_b: String = thornwall_id
	if pair_a > pair_b:
		var tmp: String = pair_a
		pair_a = pair_b
		pair_b = tmp
	var route_id: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO trade_routes
			(id, campaign_id, settlement_a_id, settlement_b_id,
			 path_kind, distance_hexes, discovered_at_calendar_day, invalidated)
		VALUES (?, ?, ?, ?, 'road', 3, 0, 0)
	""", [route_id, campaign_id, pair_a, pair_b])

	# Silk merchant at each market — both visible immediately (no solicit
	# needed), 20 loads_available each (enough for a 10-load buy + future sells).
	var thornwall_merchant_id: String = "%s_t_merch" % _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO merchant_pool
			(id, campaign_id, settlement_entrance_id, merchandise_type,
			 loads_available, loads_initial, created_at_calendar_day,
			 expires_at_calendar_day, becomes_visible_calendar_day, status, source_kind)
		VALUES (?, ?, ?, 'silk', 20, 20, 0, 999999, 0, 'active', 'monthly_refresh')
	""", [thornwall_merchant_id, campaign_id, thornwall_id])

	var ashford_merchant_id: String = "%s_a_merch" % _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO merchant_pool
			(id, campaign_id, settlement_entrance_id, merchandise_type,
			 loads_available, loads_initial, created_at_calendar_day,
			 expires_at_calendar_day, becomes_visible_calendar_day, status, source_kind)
		VALUES (?, ?, ?, 'silk', 20, 20, 0, 999999, 0, 'active', 'monthly_refresh')
	""", [ashford_merchant_id, campaign_id, ashford_id])

	return {
		"campaign_id": campaign_id,
		"ashford_id": ashford_id,
		"thornwall_id": thornwall_id,
		"wagon_id": wagon_id,
		"pc_id": pc_id,
		"party_id": party_id,
		"thornwall_merchant_id": thornwall_merchant_id,
		"ashford_merchant_id": ashford_merchant_id,
	}


# ---------------------------------------------------------------------------
# Round-trip runner — handler-routed equivalent of Prereq.8's _run_round_trip.
# ---------------------------------------------------------------------------

func _run_round_trip(fx: Dictionary, ashford_customs_pct: int, pc_owns_ashford: bool) -> int:
	var ashford_id: String = fx["ashford_id"]
	var thornwall_id: String = fx["thornwall_id"]
	var wagon_id: String = fx["wagon_id"]
	var pc_id: String = fx["pc_id"]
	var party_id: String = fx["party_id"]
	var thornwall_merchant_id: String = fx["thornwall_merchant_id"]
	var ashford_merchant_id: String = fx["ashford_merchant_id"]

	# Sanity-check pricing matches §12.4 — resolver returns cp_per_load.
	var thornwall_price: Dictionary = MarketPriceResolver.compute_market_price(
		"silk", thornwall_id, 0, 0, null, 0)
	check(int(thornwall_price.get("cp_per_load", 0)) == 160000,
		"Thornwall silk = 160,000 cp/load (1,600 gp), got %d" % int(thornwall_price.get("cp_per_load", 0)))
	var ashford_price: Dictionary = MarketPriceResolver.compute_market_price(
		"silk", ashford_id, 0, 0, null, 0)
	check(int(ashford_price.get("cp_per_load", 0)) == 260000,
		"Ashford silk = 260,000 cp/load (2,600 gp), got %d" % int(ashford_price.get("cp_per_load", 0)))

	var wealth_before: int = CampaignRepository.get_character_wealth_cp(pc_id)
	var current_day: int = Timekeeping.get_total_days()

	# --- Phase 1: Thornwall buy ---
	# Open visit row first (handler's defensive auto-open would otherwise fire
	# with arbitrary defaults).
	VisitStateManager.on_party_entered_settlement(party_id, thornwall_id, pc_id, current_day)

	# Pre-charge the toll: probed d6=4 → MarketFeesCalculator.entry_toll_cp returns 400 cp.
	# Debit via PartyWallet, mark via VisitStateManager. Handler's internal
	# toll computation will then short-circuit.
	var thornwall_toll_rng: RandomNumberGenerator = _probed_rng_for_d_equals(6, 4)
	var thornwall_toll_cp: int = MarketFeesCalculator.entry_toll_cp(
		5, false, 0, thornwall_toll_rng, false)
	check(thornwall_toll_cp == 400,
		"pre-charge: Thornwall Class V toll with d6=4 = 400 cp (= 4 gp), got %d" % thornwall_toll_cp)
	PartyWallet.pay(thornwall_toll_cp, party_id, pc_id)
	VisitStateManager.mark_entry_toll_paid(party_id, thornwall_id, thornwall_toll_cp)

	# Buy via the handler.
	var buy_state := {
		"character_id": pc_id,
		"location_ref": thornwall_id,
		"params_json": JSON.stringify({
			"merchant_id": thornwall_merchant_id,
			"merchandise_type": "silk",
			"loads_count": 10,
			"carrier_id": wagon_id,
			"carrier_kind": CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
		}),
	}
	var buy_result: Dictionary = BuyMerchandiseHandler.on_complete(buy_state, null)
	check(bool(buy_result.get("success", false)),
		"buy_merchandise handler succeeds, got: %s" % String(buy_result.get("summary", "?")))
	var receipt_b: Dictionary = buy_result.get("receipt", {})
	check(int(receipt_b.get("entry_toll_cp", -1)) == 0,
		"buy receipt entry_toll_cp = 0 (pre-charged externally), got %d" % int(receipt_b.get("entry_toll_cp", -1)))
	check(int(receipt_b.get("labor_fee_cp", -1)) == 100,
		"buy receipt labor_fee_cp = 100 (200 stone × 0.5 cp/stone)")
	var cargo_id: String = String(buy_result.get("cargo_hold_id", ""))
	check(not cargo_id.is_empty(), "cargo_hold_id from buy handler")

	# Depart Thornwall — debits stabling (1 wagon × 1 day = 200 cp = 2 gp).
	var thornwall_depart: Dictionary = VisitStateManager.on_party_departed_settlement(
		party_id, thornwall_id, current_day)
	check(int(thornwall_depart.get("stabling_cp", 0)) == 200,
		"Thornwall stabling on depart = 200 cp, got %d" % int(thornwall_depart.get("stabling_cp", 0)))

	# --- Phase 2: Transport (no commerce fees) ---

	# --- Phase 3: Ashford sell ---
	VisitStateManager.on_party_entered_settlement(party_id, ashford_id, pc_id, current_day)

	# Pre-charge Ashford toll: d8=5 + 5 (Class III 1d8+5) = 10 gp = 1000 cp. Or 0 for PC-owner.
	var ashford_toll_rng: RandomNumberGenerator = _probed_rng_for_d_equals(8, 5)
	var ashford_toll_cp: int = MarketFeesCalculator.entry_toll_cp(
		3, true, 10, ashford_toll_rng, pc_owns_ashford)
	if pc_owns_ashford:
		check(ashford_toll_cp == 0, "PC-owner Ashford toll exempt → 0 cp")
	else:
		check(ashford_toll_cp == 1000, "Ashford Class III toll d8+5 with d8=5 = 1000 cp")
	if ashford_toll_cp > 0:
		PartyWallet.pay(ashford_toll_cp, party_id, pc_id)
	VisitStateManager.mark_entry_toll_paid(party_id, ashford_id, ashford_toll_cp)

	# Sell via the handler. Sell handler will internally compute customs +
	# labor + (skipped) toll, then credit/debit accordingly.
	var sell_state := {
		"character_id": pc_id,
		"location_ref": ashford_id,
		"params_json": JSON.stringify({
			"merchant_id": ashford_merchant_id,
			"cargo_hold_id": cargo_id,
			"loads_to_sell": 10,
		}),
	}
	var sell_result: Dictionary = SellMerchandiseHandler.on_complete(sell_state, null)
	check(bool(sell_result.get("success", false)),
		"sell_merchandise handler succeeds, got: %s" % String(sell_result.get("summary", "?")))
	var receipt_s: Dictionary = sell_result.get("receipt", {})
	check(int(receipt_s.get("labor_fee_cp", -1)) == 100,
		"sell receipt labor_fee_cp = 100 (NOT domain-owner exempt per §8.8)")
	# Customs in cp: 4% / 16% of 2,600,000 cp = 104,000 cp / 416,000 cp.
	var expected_customs_cp: int = 0
	if pc_owns_ashford:
		expected_customs_cp = 0
	elif ashford_customs_pct == 4:
		expected_customs_cp = 104000
	elif ashford_customs_pct == 16:
		expected_customs_cp = 416000
	check(int(receipt_s.get("customs_duty_cp", -1)) == expected_customs_cp,
		"sell receipt customs_duty_cp = %d, got %d" % [
			expected_customs_cp, int(receipt_s.get("customs_duty_cp", -1))])
	check(bool(receipt_s.get("domain_owner_exempt", false)) == pc_owns_ashford,
		"receipt.domain_owner_exempt = %s" % pc_owns_ashford)

	# Depart Ashford — debits stabling (0 for PC-owner, 200 cp for non-owner: 1 wagon × 1 day).
	var ashford_depart: Dictionary = VisitStateManager.on_party_departed_settlement(
		party_id, ashford_id, current_day)
	var expected_ashford_stabling: int = 0 if pc_owns_ashford else 200
	check(int(ashford_depart.get("stabling_cp", -1)) == expected_ashford_stabling,
		"Ashford stabling on depart = %d cp (pc_owns=%s)" % [
			expected_ashford_stabling, pc_owns_ashford])

	# Final delta in gp.
	var wealth_after: int = CampaignRepository.get_character_wealth_cp(pc_id)
	return int((wealth_after - wealth_before) / 100)


# ---------------------------------------------------------------------------
# Cache-seeding helpers (mirroring test_commerce_integration.gd)
# ---------------------------------------------------------------------------

func _seed_demand(settlement_id: String, merchandise_type: String, value: int) -> void:
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_merchandise_demand
			(settlement_entrance_id, merchandise_type, demand_modifier,
			 generated_at_calendar_day, source_kind, pre_trade_route_shift_value)
		VALUES (?, ?, ?, 0, 'generated', ?)
		ON CONFLICT(settlement_entrance_id, merchandise_type) DO UPDATE SET
			demand_modifier = excluded.demand_modifier,
			pre_trade_route_shift_value = excluded.pre_trade_route_shift_value
	""", [settlement_id, merchandise_type, value, value])


func _force_dice(settlement_id: String, merchandise_type: String, dice: int) -> void:
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO settlement_merchandise_demand
			(settlement_entrance_id, merchandise_type, demand_modifier,
			 generated_at_calendar_day, source_kind, pre_trade_route_shift_value)
		VALUES (?, ?, 0, 0, 'generated', 0)
	""", [settlement_id, merchandise_type])
	CampaignRepository.db.query_with_bindings("""
		UPDATE settlement_merchandise_demand
		SET dice_4d4_value = ?, dice_last_rolled_calendar_day = 0
		WHERE settlement_entrance_id = ? AND merchandise_type = ?
	""", [dice, settlement_id, merchandise_type])


# ---------------------------------------------------------------------------
# RNG seed probe (mirrors test_commerce_integration.gd:_probed_rng).
# ---------------------------------------------------------------------------

func _probed_rng_for_d_equals(sides: int, target: int) -> RandomNumberGenerator:
	for seed_val in range(1, 1024):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_val
		if rng.randi_range(1, sides) == target:
			var fresh := RandomNumberGenerator.new()
			fresh.seed = seed_val
			return fresh
	push_error("_probed_rng_for_d_equals: no seed for d%d=%d within 1024" % [sides, target])
	var fallback := RandomNumberGenerator.new()
	fallback.randomize()
	return fallback


func _next_id() -> String:
	_suffix += 1
	return "tbi_%d_%d" % [Time.get_ticks_msec(), _suffix]
