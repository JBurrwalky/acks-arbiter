extends "res://tests/test_suite_base.gd"

## Unit tests for SellMerchandiseHandler — Phase 10B.2 Wave 2.
##
## Per gdd-phase-10b-2-trade-block.md §3.3. Exercises the handler's pipeline:
## cargo + merchant validation → toll first-fire → price → labor + customs →
## net proceeds credit/debit → cargo mutation (full vs partial) → receipt + signal.

var _campaign_id: String = ""
var _map_id: String = ""
var _suffix: int = 0


func run_all_tests() -> void:
	_setup()
	test_full_sell_deletes_cargo_and_credits_proceeds()
	test_partial_sell_decrements_cargo()
	test_emits_merchandise_sold_signal()
	test_rejects_merchant_type_mismatch()
	test_rejects_loads_to_sell_exceeds_cargo()
	test_rejects_when_merchant_missing()
	test_rejects_when_cargo_missing()
	test_pc_owner_customs_exempt()

	if not has_failures():
		print("SellMerchandiseHandler: all %d tests passed." % test_count())


func _setup() -> void:
	_campaign_id = CampaignRepository.create_campaign("SellMerchandiseHandlerTests", "World")
	_map_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO hex_maps (id, campaign_id, name, scale) VALUES (?, ?, ?, 'regional_6mi')",
		[_map_id, _campaign_id, "SMHMap"])


func _next_id(tag: String = "smh") -> String:
	_suffix += 1
	return "%s_%d_%d" % [tag, Time.get_ticks_msec(), _suffix]


func _build_fixture(opts: Dictionary = {}) -> Dictionary:
	var fx := TradeFixtures.new()
	var f: Dictionary = fx.build_bare({
		"name": "SMH_" + _next_id(),
		"market_class": int(opts.get("market_class", 3)),
		"customs_duty_rate_pct": int(opts.get("customs_duty_rate_pct", 4)),
		"pc_owns_parent_domain": bool(opts.get("pc_owns_parent_domain", false)),
		"starting_wealth_cp": int(opts.get("starting_wealth_cp", 10_000_000)),
	})
	CampaignRepository.db.query_with_bindings("""
		INSERT OR REPLACE INTO settlement_merchandise_demand
			(settlement_entrance_id, merchandise_type,
			 demand_modifier, pre_trade_route_shift_value,
			 dice_4d4_value, dice_last_rolled_calendar_day,
			 source_kind, generated_at_calendar_day)
		VALUES (?, 'silk', 0, 0, 10, 0, 'manual', 0)
	""", [f["settlement_id"]])
	var merchant_id: String = _next_id("merch")
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO merchant_pool
			(id, campaign_id, settlement_entrance_id, merchandise_type,
			 loads_available, loads_initial, created_at_calendar_day,
			 expires_at_calendar_day, becomes_visible_calendar_day, status, source_kind)
		VALUES (?, ?, ?, 'silk', 20, 20, 0, 999, 0, 'active', 'monthly_refresh')
	""", [merchant_id, f["campaign_id"], f["settlement_id"]])
	var wagon_id: String = _next_id("wagon")
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO draft_vehicles (id, campaign_id, party_id, item_key, name, hitched_creatures)
		VALUES (?, ?, ?, 'wagon', 'TestWagon',
			'[{"species_id":"horse_heavy"},{"species_id":"horse_heavy"},{"species_id":"horse_heavy"},{"species_id":"horse_heavy"}]')
	""", [wagon_id, f["campaign_id"], f["party_id"]])
	# Seed cargo (10 loads of silk on the wagon).
	var cargo_id: String = CargoHoldRepository.insert_purchase(
		wagon_id, CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
		"silk", 10, 16000, f["settlement_id"], 0)
	VisitStateManager.on_party_entered_settlement(
		f["party_id"], f["settlement_id"], f["pc_id"], 0)
	f["merchant_id"] = merchant_id
	f["wagon_id"] = wagon_id
	f["cargo_id"] = cargo_id
	return f


func _make_state(fx: Dictionary, params: Dictionary) -> Dictionary:
	return {
		"character_id": fx["pc_id"],
		"location_ref": fx["settlement_id"],
		"params_json": JSON.stringify(params),
	}


# ---------------------------------------------------------------------------
# Happy path / partial sell
# ---------------------------------------------------------------------------

func test_full_sell_deletes_cargo_and_credits_proceeds() -> void:
	var fx: Dictionary = _build_fixture()
	var wealth_before: int = CampaignRepository.get_character_wealth_cp(fx["pc_id"])
	var state: Dictionary = _make_state(fx, {
		"merchant_id": fx["merchant_id"],
		"cargo_hold_id": fx["cargo_id"],
		"loads_to_sell": 10,  # full sell
	})
	var r: Dictionary = SellMerchandiseHandler.on_complete(state, null)
	check(bool(r.get("success", false)),
		"full sell succeeds, got summary: %s" % String(r.get("summary", "?")))
	check(CargoHoldRepository.get_cargo_hold(fx["cargo_id"]).is_empty(),
		"cargo row deleted on full sell")
	var wealth_after: int = CampaignRepository.get_character_wealth_cp(fx["pc_id"])
	check(wealth_after > wealth_before,
		"wallet credited (before=%d cp, after=%d cp)" % [wealth_before, wealth_after])


func test_partial_sell_decrements_cargo() -> void:
	var fx: Dictionary = _build_fixture()
	var state: Dictionary = _make_state(fx, {
		"merchant_id": fx["merchant_id"],
		"cargo_hold_id": fx["cargo_id"],
		"loads_to_sell": 3,
	})
	var r: Dictionary = SellMerchandiseHandler.on_complete(state, null)
	check(bool(r.get("success", false)), "partial sell succeeds")
	var row: Dictionary = CargoHoldRepository.get_cargo_hold(fx["cargo_id"])
	check(int(row.get("loads_count", 0)) == 7,
		"cargo loads_count decremented from 10 to 7, got %d" % int(row.get("loads_count", 0)))


# ---------------------------------------------------------------------------
# Signal emission
# ---------------------------------------------------------------------------

func test_emits_merchandise_sold_signal() -> void:
	var fx: Dictionary = _build_fixture()
	var captured := {"emitted": false, "type": "", "loads": -1}
	var cb: Callable = func(_cargo: String, _set: String, mtype: String, loads: int, _cp: int) -> void:
		captured["emitted"] = true
		captured["type"] = mtype
		captured["loads"] = loads
	EventBus.merchandise_sold.connect(cb)
	var state: Dictionary = _make_state(fx, {
		"merchant_id": fx["merchant_id"],
		"cargo_hold_id": fx["cargo_id"],
		"loads_to_sell": 5,
	})
	SellMerchandiseHandler.on_complete(state, null)
	EventBus.merchandise_sold.disconnect(cb)
	check(bool(captured["emitted"]), "merchandise_sold signal fired")
	check(str(captured["type"]) == "silk", "signal merchandise_type = silk")
	check(int(captured["loads"]) == 5, "signal loads_count = 5")


# ---------------------------------------------------------------------------
# Validation failures
# ---------------------------------------------------------------------------

func test_rejects_merchant_type_mismatch() -> void:
	var fx: Dictionary = _build_fixture()
	# Swap merchant's type away from silk.
	CampaignRepository.db.query_with_bindings(
		"UPDATE merchant_pool SET merchandise_type = 'salt' WHERE id = ?", [fx["merchant_id"]])
	var state: Dictionary = _make_state(fx, {
		"merchant_id": fx["merchant_id"],
		"cargo_hold_id": fx["cargo_id"],
		"loads_to_sell": 1,
	})
	var r: Dictionary = SellMerchandiseHandler.on_complete(state, null)
	check(not bool(r.get("success", true)),
		"merchant type mismatch rejected, got summary: %s" % String(r.get("summary", "?")))


func test_rejects_loads_to_sell_exceeds_cargo() -> void:
	var fx: Dictionary = _build_fixture()
	var state: Dictionary = _make_state(fx, {
		"merchant_id": fx["merchant_id"],
		"cargo_hold_id": fx["cargo_id"],
		"loads_to_sell": 50,  # > 10
	})
	var r: Dictionary = SellMerchandiseHandler.on_complete(state, null)
	check(not bool(r.get("success", true)),
		"loads_to_sell > cargo loads rejected")


func test_rejects_when_merchant_missing() -> void:
	var fx: Dictionary = _build_fixture()
	var state: Dictionary = _make_state(fx, {
		"merchant_id": "nonexistent_merchant_id",
		"cargo_hold_id": fx["cargo_id"],
		"loads_to_sell": 1,
	})
	var r: Dictionary = SellMerchandiseHandler.on_complete(state, null)
	check(not bool(r.get("success", true)), "missing merchant rejected")


func test_rejects_when_cargo_missing() -> void:
	var fx: Dictionary = _build_fixture()
	var state: Dictionary = _make_state(fx, {
		"merchant_id": fx["merchant_id"],
		"cargo_hold_id": "nonexistent_cargo_id",
		"loads_to_sell": 1,
	})
	var r: Dictionary = SellMerchandiseHandler.on_complete(state, null)
	check(not bool(r.get("success", true)), "missing cargo rejected")


# ---------------------------------------------------------------------------
# Domain-owner exemption (§8.8)
# ---------------------------------------------------------------------------

func test_pc_owner_customs_exempt() -> void:
	var fx: Dictionary = _build_fixture({"pc_owns_parent_domain": true})
	var state: Dictionary = _make_state(fx, {
		"merchant_id": fx["merchant_id"],
		"cargo_hold_id": fx["cargo_id"],
		"loads_to_sell": 5,
	})
	var r: Dictionary = SellMerchandiseHandler.on_complete(state, null)
	check(bool(r.get("success", false)),
		"PC-owner sell succeeds, got summary: %s" % String(r.get("summary", "?")))
	var receipt: Dictionary = r.get("receipt", {})
	check(int(receipt.get("customs_duty_cp", -1)) == 0,
		"PC-owner customs_duty_cp = 0, got %d" % int(receipt.get("customs_duty_cp", -1)))
	check(bool(receipt.get("domain_owner_exempt", false)),
		"receipt flags domain_owner_exempt")
