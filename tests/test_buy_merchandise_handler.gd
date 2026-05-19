extends "res://tests/test_suite_base.gd"

## Unit tests for BuyMerchandiseHandler — Phase 10B.2 Wave 2.
##
## Per gdd-phase-10b-2-trade-block.md §3.2. Exercises the handler's pipeline:
## merchant validation → toll first-fire → price computation → labor + capacity
## → affordability → cargo insert + merchant deplete → receipt + signal.

var _campaign_id: String = ""
var _map_id: String = ""
var _suffix: int = 0
var _pre_existing_visits: Array = []


func run_all_tests() -> void:
	_setup()
	test_happy_path_buy_inserts_cargo_and_debits_wallet()
	test_emits_merchandise_purchased_signal()
	test_subsequent_buy_skips_toll_within_same_visit()
	test_rejects_when_merchant_lacks_loads()
	test_rejects_when_merchant_type_mismatches()
	test_rejects_when_carrier_capacity_exceeded()
	test_rejects_when_insufficient_funds()
	test_rejects_when_merchant_inactive()
	test_decrements_merchant_loads_available()

	if not has_failures():
		print("BuyMerchandiseHandler: all %d tests passed." % test_count())


func _setup() -> void:
	_campaign_id = CampaignRepository.create_campaign("BuyMerchandiseHandlerTests", "World")
	_map_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO hex_maps (id, campaign_id, name, scale) VALUES (?, ?, ?, 'regional_6mi')",
		[_map_id, _campaign_id, "BMHMap"])


func _next_id(tag: String = "bmh") -> String:
	_suffix += 1
	return "%s_%d_%d" % [tag, Time.get_ticks_msec(), _suffix]


func _build_fixture(opts: Dictionary = {}) -> Dictionary:
	var fx := TradeFixtures.new()
	var f: Dictionary = fx.build_bare({
		"name": "BMH_" + _next_id(),
		"market_class": int(opts.get("market_class", 3)),
		"starting_wealth_cp": int(opts.get("starting_wealth_cp", 10_000_000)),
		"pc_owns_parent_domain": bool(opts.get("pc_owns_parent_domain", false)),
		"customs_duty_rate_pct": 4,
	})
	# Seed demand cache for silk so MarketPriceResolver returns deterministic value.
	CampaignRepository.db.query_with_bindings("""
		INSERT OR REPLACE INTO settlement_merchandise_demand
			(settlement_entrance_id, merchandise_type,
			 demand_modifier, pre_trade_route_shift_value,
			 dice_4d4_value, dice_last_rolled_calendar_day,
			 source_kind, generated_at_calendar_day)
		VALUES (?, 'silk', 0, 0, 10, 0, 'manual', 0)
	""", [f["settlement_id"]])
	# Insert a visible silk merchant with 10 loads.
	var merchant_id: String = _next_id("merch")
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO merchant_pool
			(id, campaign_id, settlement_entrance_id, merchandise_type,
			 loads_available, loads_initial, created_at_calendar_day,
			 expires_at_calendar_day, becomes_visible_calendar_day, status, source_kind)
		VALUES (?, ?, ?, 'silk', 10, 10, 0, 999, 0, 'active', 'monthly_refresh')
	""", [merchant_id, f["campaign_id"], f["settlement_id"]])
	# Attach a wagon with 4 heavy horses (load_max 640 stone — easily handles silk).
	var wagon_id: String = _next_id("wagon")
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO draft_vehicles (id, campaign_id, party_id, item_key, name, hitched_creatures)
		VALUES (?, ?, ?, 'wagon', 'TestWagon',
			'[{"species_id":"horse_heavy"},{"species_id":"horse_heavy"},{"species_id":"horse_heavy"},{"species_id":"horse_heavy"}]')
	""", [wagon_id, f["campaign_id"], f["party_id"]])
	# Open the visit so the handler doesn't auto-open one with arbitrary defaults.
	VisitStateManager.on_party_entered_settlement(
		f["party_id"], f["settlement_id"], f["pc_id"], 0)
	f["merchant_id"] = merchant_id
	f["wagon_id"] = wagon_id
	return f


func _make_state(fx: Dictionary, params: Dictionary) -> Dictionary:
	return {
		"character_id": fx["pc_id"],
		"location_ref": fx["settlement_id"],
		"params_json": JSON.stringify(params),
	}


# ---------------------------------------------------------------------------
# Happy path
# ---------------------------------------------------------------------------

func test_happy_path_buy_inserts_cargo_and_debits_wallet() -> void:
	var fx: Dictionary = _build_fixture()
	var wealth_before: int = CampaignRepository.get_character_wealth_cp(fx["pc_id"])
	var state: Dictionary = _make_state(fx, {
		"merchant_id": fx["merchant_id"],
		"merchandise_type": "silk",
		"loads_count": 5,
		"carrier_id": fx["wagon_id"],
		"carrier_kind": CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
	})
	var result: Dictionary = BuyMerchandiseHandler.on_complete(state, null)
	check(bool(result.get("success", false)),
		"happy-path buy reports success, got summary: %s" % String(result.get("summary", "?")))
	check(not String(result.get("cargo_hold_id", "")).is_empty(),
		"result includes cargo_hold_id")
	var rows: Array = CargoHoldRepository.list_for_draft_vehicle(fx["wagon_id"])
	check(rows.size() == 1, "cargo row inserted on wagon, got %d" % rows.size())
	check(str((rows[0] as Dictionary).get("merchandise_type", "")) == "silk",
		"cargo merchandise_type = silk")
	check(int((rows[0] as Dictionary).get("loads_count", 0)) == 5,
		"cargo loads_count = 5")
	# Wallet was debited (we don't pin to an exact value since toll dice are random;
	# just verify a debit occurred).
	var wealth_after: int = CampaignRepository.get_character_wealth_cp(fx["pc_id"])
	check(wealth_after < wealth_before,
		"wallet debited (before=%d cp, after=%d cp)" % [wealth_before, wealth_after])


func test_emits_merchandise_purchased_signal() -> void:
	var fx: Dictionary = _build_fixture()
	var captured := {"emitted": false, "type": "", "loads": -1}
	var cb: Callable = func(_cargo: String, _set: String, mtype: String, loads: int, _cp: int) -> void:
		captured["emitted"] = true
		captured["type"] = mtype
		captured["loads"] = loads
	EventBus.merchandise_purchased.connect(cb)
	var state: Dictionary = _make_state(fx, {
		"merchant_id": fx["merchant_id"],
		"merchandise_type": "silk",
		"loads_count": 2,
		"carrier_id": fx["wagon_id"],
		"carrier_kind": CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
	})
	BuyMerchandiseHandler.on_complete(state, null)
	EventBus.merchandise_purchased.disconnect(cb)
	check(bool(captured["emitted"]), "merchandise_purchased signal fired")
	check(str(captured["type"]) == "silk", "signal merchandise_type = silk")
	check(int(captured["loads"]) == 2, "signal loads_count = 2")


# ---------------------------------------------------------------------------
# Entry toll first-fire
# ---------------------------------------------------------------------------

func test_subsequent_buy_skips_toll_within_same_visit() -> void:
	var fx: Dictionary = _build_fixture()
	# First buy — toll fires.
	var state_a: Dictionary = _make_state(fx, {
		"merchant_id": fx["merchant_id"],
		"merchandise_type": "silk",
		"loads_count": 1,
		"carrier_id": fx["wagon_id"],
		"carrier_kind": CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
	})
	BuyMerchandiseHandler.on_complete(state_a, null)
	check(VisitStateManager.has_paid_entry_toll(fx["party_id"], fx["settlement_id"]),
		"toll-paid flag set after first transaction")
	var wealth_mid: int = CampaignRepository.get_character_wealth_cp(fx["pc_id"])

	# Second buy — toll should be 0; only purchase + labor debit.
	var state_b: Dictionary = _make_state(fx, {
		"merchant_id": fx["merchant_id"],
		"merchandise_type": "silk",
		"loads_count": 1,
		"carrier_id": fx["wagon_id"],
		"carrier_kind": CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
	})
	var r2: Dictionary = BuyMerchandiseHandler.on_complete(state_b, null)
	check(bool(r2.get("success", false)), "second buy succeeds")
	var receipt2: Dictionary = r2.get("receipt", {})
	check(int(receipt2.get("entry_toll_cp", -1)) == 0,
		"second buy receipt entry_toll_cp = 0 (already paid this visit), got %d" % int(receipt2.get("entry_toll_cp", -1)))
	# Sanity: wallet still debits for second purchase.
	var wealth_after: int = CampaignRepository.get_character_wealth_cp(fx["pc_id"])
	check(wealth_after < wealth_mid, "second buy still debits wallet")


# ---------------------------------------------------------------------------
# Validation failures
# ---------------------------------------------------------------------------

func test_rejects_when_merchant_lacks_loads() -> void:
	var fx: Dictionary = _build_fixture()
	var state: Dictionary = _make_state(fx, {
		"merchant_id": fx["merchant_id"],
		"merchandise_type": "silk",
		"loads_count": 100,  # > 10 available
		"carrier_id": fx["wagon_id"],
		"carrier_kind": CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
	})
	var r: Dictionary = BuyMerchandiseHandler.on_complete(state, null)
	check(not bool(r.get("success", true)),
		"loads_count > merchant.loads_available rejected")
	check(String(r.get("summary", "")).contains("loads_available")
			or String(r.get("summary", "")).contains("max"),
		"summary mentions max: '%s'" % String(r.get("summary", "")))


func test_rejects_when_merchant_type_mismatches() -> void:
	var fx: Dictionary = _build_fixture()
	var state: Dictionary = _make_state(fx, {
		"merchant_id": fx["merchant_id"],
		"merchandise_type": "salt",  # merchant deals in silk
		"loads_count": 1,
		"carrier_id": fx["wagon_id"],
		"carrier_kind": CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
	})
	var r: Dictionary = BuyMerchandiseHandler.on_complete(state, null)
	check(not bool(r.get("success", true)),
		"merchandise_type mismatch rejected")


func test_rejects_when_carrier_capacity_exceeded() -> void:
	var fx: Dictionary = _build_fixture()
	# Replace wagon with an unhitched one (load_max = 0 → no capacity).
	var tiny_id: String = _next_id("tiny")
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO draft_vehicles (id, campaign_id, party_id, item_key, name, hitched_creatures)
		VALUES (?, ?, ?, 'cart_small', 'TinyCart', '[]')
	""", [tiny_id, fx["campaign_id"], fx["party_id"]])
	var state: Dictionary = _make_state(fx, {
		"merchant_id": fx["merchant_id"],
		"merchandise_type": "silk",
		"loads_count": 10,  # 200 stone — exceeds unhitched cart
		"carrier_id": tiny_id,
		"carrier_kind": CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
	})
	var r: Dictionary = BuyMerchandiseHandler.on_complete(state, null)
	check(not bool(r.get("success", true)),
		"carrier capacity exceeded rejected, got summary: %s" % String(r.get("summary", "?")))


func test_rejects_when_insufficient_funds() -> void:
	var fx: Dictionary = _build_fixture({"starting_wealth_cp": 50})  # 0.5 gp
	var state: Dictionary = _make_state(fx, {
		"merchant_id": fx["merchant_id"],
		"merchandise_type": "silk",
		"loads_count": 1,  # 1 silk load is thousands of gp
		"carrier_id": fx["wagon_id"],
		"carrier_kind": CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
	})
	var r: Dictionary = BuyMerchandiseHandler.on_complete(state, null)
	check(not bool(r.get("success", true)),
		"insufficient funds rejected, got summary: %s" % String(r.get("summary", "?")))


func test_rejects_when_merchant_inactive() -> void:
	var fx: Dictionary = _build_fixture()
	# Flip the merchant to 'depleted'.
	CampaignRepository.db.query_with_bindings(
		"UPDATE merchant_pool SET status = 'depleted' WHERE id = ?", [fx["merchant_id"]])
	var state: Dictionary = _make_state(fx, {
		"merchant_id": fx["merchant_id"],
		"merchandise_type": "silk",
		"loads_count": 1,
		"carrier_id": fx["wagon_id"],
		"carrier_kind": CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
	})
	var r: Dictionary = BuyMerchandiseHandler.on_complete(state, null)
	check(not bool(r.get("success", true)),
		"depleted merchant rejected, got summary: %s" % String(r.get("summary", "?")))


# ---------------------------------------------------------------------------
# Side-effect verification
# ---------------------------------------------------------------------------

func test_decrements_merchant_loads_available() -> void:
	var fx: Dictionary = _build_fixture()
	var state: Dictionary = _make_state(fx, {
		"merchant_id": fx["merchant_id"],
		"merchandise_type": "silk",
		"loads_count": 3,
		"carrier_id": fx["wagon_id"],
		"carrier_kind": CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
	})
	BuyMerchandiseHandler.on_complete(state, null)
	var merchant: Dictionary = MerchantPoolRepository.get_merchant(fx["merchant_id"])
	check(int(merchant.get("loads_available", -1)) == 7,
		"merchant.loads_available decremented from 10 to 7, got %d" % int(merchant.get("loads_available", -1)))
