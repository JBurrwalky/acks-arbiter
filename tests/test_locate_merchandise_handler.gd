extends "res://tests/test_suite_base.gd"

## Unit tests for LocateMerchandiseHandler — Phase 10B.2 Wave 3.
##
## Per gdd-phase-10b-2-trade-block.md §6 + §18.1. Exercises the three
## outcomes per §6.1:
##   * Visible match → no-op success (surfaced_now=false).
##   * Invisible match → surface one merchant (surfaced_now=true), substrate
##     emits merchant_surfaced_via_locate.
##   * No match → failure with no_merchant_of_type; entry toll still charged.
##
## Toll-first-fire integration verified.

var _campaign_id: String = ""
var _map_id: String = ""
var _suffix: int = 0


func run_all_tests() -> void:
	_setup()
	test_visible_match_returns_no_op_success()
	test_invisible_match_surfaces_merchant()
	test_invisible_match_emits_substrate_signal()
	test_no_match_returns_failure()
	test_rejects_missing_merchandise_type()
	test_entry_toll_first_fire_charges()
	test_subsequent_locate_skips_toll()

	if not has_failures():
		print("LocateMerchandiseHandler: all %d tests passed." % test_count())


func _setup() -> void:
	_campaign_id = CampaignRepository.create_campaign("LocateMerchandiseTests", "World")
	_map_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO hex_maps (id, campaign_id, name, scale) VALUES (?, ?, ?, 'regional_6mi')",
		[_map_id, _campaign_id, "LMHMap"])


func _next_id(tag: String = "lm") -> String:
	_suffix += 1
	return "%s_%d_%d" % [tag, Time.get_ticks_msec(), _suffix]


func _build_fixture(opts: Dictionary = {}) -> Dictionary:
	var fx := TradeFixtures.new()
	var f: Dictionary = fx.build_bare({
		"name": "LM_" + _next_id(),
		"market_class": int(opts.get("market_class", 3)),
		"starting_wealth_cp": 1_000_000,
	})
	VisitStateManager.on_party_entered_settlement(
		f["party_id"], f["settlement_id"], f["pc_id"], 0)
	return f


func _insert_merchant(settlement_id: String, merchandise_type: String, visible_day: int) -> String:
	var mid: String = _next_id("merch")
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO merchant_pool
			(id, campaign_id, settlement_entrance_id, merchandise_type,
			 loads_available, loads_initial, created_at_calendar_day,
			 expires_at_calendar_day, becomes_visible_calendar_day, status, source_kind)
		VALUES (?, ?, ?, ?, 5, 5, 0, 999, ?, 'active', 'monthly_refresh')
	""", [mid, _campaign_id, settlement_id, merchandise_type, visible_day])
	return mid


func _make_state(fx: Dictionary, params: Dictionary) -> Dictionary:
	return {
		"character_id": fx["pc_id"],
		"location_ref": fx["settlement_id"],
		"params_json": JSON.stringify(params),
	}


# ---------------------------------------------------------------------------
# Three outcomes
# ---------------------------------------------------------------------------

func test_visible_match_returns_no_op_success() -> void:
	var fx: Dictionary = _build_fixture()
	var visible_mid: String = _insert_merchant(fx["settlement_id"], "silk", 0)
	var state: Dictionary = _make_state(fx, {"merchandise_type": "silk"})
	var r: Dictionary = LocateMerchandiseHandler.on_complete(state, null)
	check(bool(r.get("success", false)), "visible match → success")
	check(not bool(r.get("surfaced_now", true)),
		"surfaced_now=false (already visible)")
	check(str(r.get("merchant_id", "")) == visible_mid,
		"merchant_id matches the visible row")


func test_invisible_match_surfaces_merchant() -> void:
	var fx: Dictionary = _build_fixture()
	var invisible_mid: String = _insert_merchant(
		fx["settlement_id"], "silk", MerchantPoolRepository.INVISIBLE_SENTINEL)
	var state: Dictionary = _make_state(fx, {"merchandise_type": "silk"})
	var r: Dictionary = LocateMerchandiseHandler.on_complete(state, null)
	check(bool(r.get("success", false)), "invisible match → success")
	check(bool(r.get("surfaced_now", false)),
		"surfaced_now=true (newly revealed)")
	check(str(r.get("merchant_id", "")) == invisible_mid,
		"merchant_id matches the surfaced row")
	# The row's becomes_visible_calendar_day should now be current_day (0 in tests).
	var merchant: Dictionary = MerchantPoolRepository.get_merchant(invisible_mid)
	check(int(merchant.get("becomes_visible_calendar_day", -1)) == Timekeeping.get_total_days(),
		"becomes_visible_calendar_day reset to current_day, got %d" % int(merchant.get("becomes_visible_calendar_day", -1)))


func test_invisible_match_emits_substrate_signal() -> void:
	var fx: Dictionary = _build_fixture()
	_insert_merchant(fx["settlement_id"], "spices", MerchantPoolRepository.INVISIBLE_SENTINEL)
	var captured := {"emitted": false, "type": ""}
	var cb: Callable = func(_mid: String, _sid: String, mtype: String) -> void:
		captured["emitted"] = true
		captured["type"] = mtype
	EventBus.merchant_surfaced_via_locate.connect(cb)
	var state: Dictionary = _make_state(fx, {"merchandise_type": "spices"})
	LocateMerchandiseHandler.on_complete(state, null)
	EventBus.merchant_surfaced_via_locate.disconnect(cb)
	check(bool(captured["emitted"]), "merchant_surfaced_via_locate emits")
	check(str(captured["type"]) == "spices", "signal merchandise_type = 'spices'")


func test_no_match_returns_failure() -> void:
	var fx: Dictionary = _build_fixture()
	# Pool has only salt merchants.
	_insert_merchant(fx["settlement_id"], "salt", 0)
	var state: Dictionary = _make_state(fx, {"merchandise_type": "gems"})
	var r: Dictionary = LocateMerchandiseHandler.on_complete(state, null)
	check(not bool(r.get("success", true)), "no match → failure")
	check(String(r.get("summary", "")).contains("No gems")
			or String(r.get("summary", "")).contains("persuad"),
		"summary mentions persuade fallback: '%s'" % String(r.get("summary", "")))


func test_rejects_missing_merchandise_type() -> void:
	var fx: Dictionary = _build_fixture()
	var state: Dictionary = _make_state(fx, {})
	var r: Dictionary = LocateMerchandiseHandler.on_complete(state, null)
	check(not bool(r.get("success", true)),
		"empty merchandise_type rejected")


# ---------------------------------------------------------------------------
# Entry-toll integration
# ---------------------------------------------------------------------------

func test_entry_toll_first_fire_charges() -> void:
	# Use a fresh fixture without pre-toll'd visit. NOTE: _build_fixture
	# pre-opens a visit but doesn't charge the toll yet; first locate fires it.
	var fx: Dictionary = _build_fixture({"market_class": 5})
	check(not VisitStateManager.has_paid_entry_toll(fx["party_id"], fx["settlement_id"]),
		"toll not yet paid (precondition)")
	_insert_merchant(fx["settlement_id"], "silk", 0)
	var state: Dictionary = _make_state(fx, {"merchandise_type": "silk"})
	var r: Dictionary = LocateMerchandiseHandler.on_complete(state, null)
	check(int(r.get("entry_toll_cp", -1)) >= 0,
		"entry_toll_cp present in return (paid this visit), got %d" % int(r.get("entry_toll_cp", -1)))
	check(VisitStateManager.has_paid_entry_toll(fx["party_id"], fx["settlement_id"]),
		"toll-paid flag set after locate")


func test_subsequent_locate_skips_toll() -> void:
	var fx: Dictionary = _build_fixture({"market_class": 3})
	_insert_merchant(fx["settlement_id"], "silk", 0)
	# First locate fires the toll.
	var state_a: Dictionary = _make_state(fx, {"merchandise_type": "silk"})
	LocateMerchandiseHandler.on_complete(state_a, null)
	# Second locate skips the toll (returns 0).
	_insert_merchant(fx["settlement_id"], "salt", 0)
	var state_b: Dictionary = _make_state(fx, {"merchandise_type": "salt"})
	var r2: Dictionary = LocateMerchandiseHandler.on_complete(state_b, null)
	check(int(r2.get("entry_toll_cp", -1)) == 0,
		"second locate within visit returns entry_toll_cp = 0, got %d" % int(r2.get("entry_toll_cp", -1)))
