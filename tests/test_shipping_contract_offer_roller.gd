extends "res://tests/test_suite_base.gd"

## Unit tests for ShippingContractOfferRoller — Phase 10B.2 Wave 4.
##
## Per gdd-phase-10b-2-trade-block.md §7 + §18.1. Exercises:
##   * roll_for_visit produces per-class quantity dice.
##   * Idempotency: re-calling roll_for_visit doesn't re-roll.
##   * Destination resolution picks from reachable settlements only.
##   * Fee formula (RAW L817-819): road 1gp/10stone/150mi; sea 1gp/10stone/500mi.
##   * Deadline calculation: round-trip × 2 + 7 buffer.
##   * clear_for_party_at_settlement removes all offers + returns count.
##   * Signals: shipping_offer_rolled (per offer) + shipping_offer_cleared.
##   * Zero-class settlement → zero offers (Class V/VI 1d4-1 / 1d3-1 may roll 0).
##   * Empty reachable set → zero offers.

var _campaign_id: String = ""
var _map_id: String = ""
var _suffix: int = 0


func run_all_tests() -> void:
	_setup()
	test_compute_fee_road_formula()
	test_compute_fee_water_formula()
	test_compute_fee_rounds_up_per_RAW()
	test_compute_fee_zero_inputs()
	test_compute_deadline_road_formula()
	test_compute_deadline_water_formula()
	test_roll_for_visit_produces_offers()
	test_roll_for_visit_idempotent_on_reentry()
	test_roll_for_visit_zero_when_no_reachable_destination()
	test_roll_for_visit_emits_shipping_offer_rolled_per_offer()
	test_clear_for_party_removes_all_offers()
	test_clear_for_party_emits_cleared_signal()
	test_clear_for_party_returns_zero_when_empty()
	test_list_offers_scoped_to_party_and_settlement()
	test_get_offer_returns_full_row()
	test_offers_use_mixed_cargo_70_stone_per_load()

	if not has_failures():
		print("ShippingContractOfferRoller: all %d tests passed." % test_count())


func _setup() -> void:
	_campaign_id = CampaignRepository.create_campaign("ShippingOfferRollerTests", "World")
	_map_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO hex_maps (id, campaign_id, name, scale) VALUES (?, ?, ?, 'regional_6mi')",
		[_map_id, _campaign_id, "SCORMap"])


func _next_id(tag: String = "scor") -> String:
	_suffix += 1
	return "%s_%d_%d" % [tag, Time.get_ticks_msec(), _suffix]


func _build_two_settlements_with_road(opts: Dictionary = {}) -> Dictionary:
	# Build origin + destination + a trade_routes row connecting them.
	# Avoids the substrate's BFS detection (which needs road overlays + the
	# proper hex_cells geometry); for tests we just need compute_road_distance
	# to return a positive value.
	var fx := TradeFixtures.new()
	var bundle: Dictionary = fx.build_two_settlements({
		"name": "SCOR_" + _next_id(),
		"origin_market_class": int(opts.get("origin_market_class", 3)),
		"dest_market_class": int(opts.get("dest_market_class", 5)),
		"merchandise_type": "silk",
		"origin_demand": 0,
		"dest_demand": 0,
		"starting_wealth_cp": 1_000_000,
	})
	return bundle


func _read_compute_distance_via_fixture(origin_id: String, dest_id: String) -> int:
	# Sanity helper: substrate's compute_road_distance reads trade_routes
	# directly when we've manually inserted a row (per build_two_settlements).
	return TradeRouteDetector.compute_road_distance(origin_id, dest_id)


# ---------------------------------------------------------------------------
# Pure-function tests
# ---------------------------------------------------------------------------

func test_compute_fee_road_formula() -> void:
	# 700 stone × 300 mi road: ceili(700/10) = 70; ceili(300/150) = 2; fee = 140 gp = 14,000 cp.
	check(ShippingContractOfferRoller.compute_fee_cp(700, 300, "road") == 14000,
		"road 700 stone × 300 mi = 14,000 cp (= 140 gp)")
	# 100 stone × 75 mi road: ceili(100/10) = 10; ceili(75/150) = 1; fee = 10 gp = 1000 cp.
	check(ShippingContractOfferRoller.compute_fee_cp(100, 75, "road") == 1000,
		"road 100 stone × 75 mi = 1000 cp (= 10 gp)")


func test_compute_fee_water_formula() -> void:
	# 700 stone × 300 mi water: ceili(700/10) = 70; ceili(300/500) = 1; fee = 70 gp = 7000 cp.
	check(ShippingContractOfferRoller.compute_fee_cp(700, 300, "water") == 7000,
		"water 700 stone × 300 mi = 7000 cp (= 70 gp)")
	# 1400 stone × 1000 mi water: ceili(1400/10) = 140; ceili(1000/500) = 2; fee = 280 gp = 28,000 cp.
	check(ShippingContractOfferRoller.compute_fee_cp(1400, 1000, "water") == 28000,
		"water 1400 stone × 1000 mi = 28,000 cp (= 280 gp)")


func test_compute_fee_rounds_up_per_RAW() -> void:
	# 75 stone × 100 mi road: ceili(75/10) = 8; ceili(100/150) = 1; fee = 8 gp = 800 cp.
	check(ShippingContractOfferRoller.compute_fee_cp(75, 100, "road") == 800,
		"75 stone rounds up to 8 units × 1 distance unit = 800 cp")
	# 100 stone × 200 mi road: ceili(100/10) = 10; ceili(200/150) = 2; fee = 20 gp = 2000 cp.
	check(ShippingContractOfferRoller.compute_fee_cp(100, 200, "road") == 2000,
		"200 mi rounds up to 2 distance units → 10 × 2 × 100 = 2000 cp")


func test_compute_fee_zero_inputs() -> void:
	check(ShippingContractOfferRoller.compute_fee_cp(0, 100, "road") == 0,
		"zero stone → 0 fee")
	check(ShippingContractOfferRoller.compute_fee_cp(100, 0, "road") == 0,
		"zero distance → 0 fee")


func test_compute_deadline_road_formula() -> void:
	# 180 mi road @ 18 mi/day = 10 travel days × 2 + 7 = 27 day window.
	# deadline = current_day + 27.
	var deadline: int = ShippingContractOfferRoller.compute_deadline_calendar_day(100, 180, "road")
	check(deadline == 100 + 27, "road 180 mi → deadline current+27, got %d" % (deadline - 100))


func test_compute_deadline_water_formula() -> void:
	# 480 mi water @ 48 mi/day = 10 travel days × 2 + 7 = 27 day window.
	var deadline: int = ShippingContractOfferRoller.compute_deadline_calendar_day(100, 480, "water")
	check(deadline == 100 + 27, "water 480 mi → deadline current+27, got %d" % (deadline - 100))


# ---------------------------------------------------------------------------
# roll_for_visit
# ---------------------------------------------------------------------------

func test_roll_for_visit_produces_offers() -> void:
	var fx: Dictionary = _build_two_settlements_with_road({"origin_market_class": 1})
	var current_day: int = Timekeeping.get_total_days()
	var offers: Array = ShippingContractOfferRoller.roll_for_visit(
		fx["origin_settlement_id"], fx["party_id"], current_day)
	# Class I rolls 2d6+2 → 4-14 contracts.
	check(offers.size() >= 4 and offers.size() <= 14,
		"Class I rolls 4-14 offers, got %d" % offers.size())
	# Each offer should be `mixed_cargo` at 70 stone/load.
	var first: Dictionary = offers[0]
	check(String(first.get("merchandise_type", "")) == "mixed_cargo",
		"offer merchandise_type = 'mixed_cargo'")
	check(int(first.get("load_weight_stone", 0)) == 70,
		"offer load_weight_stone = 70 (RAW L822)")


func test_roll_for_visit_idempotent_on_reentry() -> void:
	var fx: Dictionary = _build_two_settlements_with_road({"origin_market_class": 3})
	var current_day: int = Timekeeping.get_total_days()
	var offers_a: Array = ShippingContractOfferRoller.roll_for_visit(
		fx["origin_settlement_id"], fx["party_id"], current_day)
	# Capture the IDs.
	var ids_a: Array = []
	for o in offers_a:
		ids_a.append(String((o as Dictionary).get("id", "")))
	# Re-call with same (party, settlement, day) — should NOT re-roll.
	var offers_b: Array = ShippingContractOfferRoller.roll_for_visit(
		fx["origin_settlement_id"], fx["party_id"], current_day)
	check(offers_b.size() == offers_a.size(),
		"re-roll returns same count (idempotent)")
	for o in offers_b:
		check(ids_a.has(String((o as Dictionary).get("id", ""))),
			"every re-rolled offer id matches an original")


func test_roll_for_visit_zero_when_no_reachable_destination() -> void:
	# Build a fixture with only ONE settlement (no connectivity).
	var fx := TradeFixtures.new()
	var f: Dictionary = fx.build_bare({
		"name": "SCOR_orphan_" + _next_id(),
		"market_class": 3,
		"starting_wealth_cp": 1_000_000,
	})
	# Call roll_for_visit at this orphan settlement — no candidates.
	var offers: Array = ShippingContractOfferRoller.roll_for_visit(
		f["settlement_id"], f["party_id"], Timekeeping.get_total_days())
	check(offers.is_empty(),
		"orphan settlement (no reachable destinations) → 0 offers, got %d" % offers.size())


func test_roll_for_visit_emits_shipping_offer_rolled_per_offer() -> void:
	var fx: Dictionary = _build_two_settlements_with_road({"origin_market_class": 3})
	var current_day: int = Timekeeping.get_total_days()
	# Use a Dictionary for the counter — Dictionaries capture by reference in
	# GDScript lambdas; primitive ints capture by value.
	var captured := {"count": 0}
	var target_party: String = fx["party_id"]
	var target_set: String = fx["origin_settlement_id"]
	var cb: Callable = func(_offer_id: String, party_id: String, set_id: String) -> void:
		if party_id == target_party and set_id == target_set:
			captured["count"] = int(captured["count"]) + 1
	EventBus.shipping_offer_rolled.connect(cb)
	var offers: Array = ShippingContractOfferRoller.roll_for_visit(
		fx["origin_settlement_id"], fx["party_id"], current_day)
	EventBus.shipping_offer_rolled.disconnect(cb)
	check(int(captured["count"]) == offers.size(),
		"shipping_offer_rolled emit count matches offer count (%d emits, %d offers)" % [
			int(captured["count"]), offers.size()])


# ---------------------------------------------------------------------------
# clear_for_party_at_settlement
# ---------------------------------------------------------------------------

func test_clear_for_party_removes_all_offers() -> void:
	var fx: Dictionary = _build_two_settlements_with_road({"origin_market_class": 3})
	var current_day: int = Timekeeping.get_total_days()
	var offers: Array = ShippingContractOfferRoller.roll_for_visit(
		fx["origin_settlement_id"], fx["party_id"], current_day)
	check(offers.size() > 0, "precondition: offers exist")
	var cleared: int = ShippingContractOfferRoller.clear_for_party_at_settlement(
		fx["party_id"], fx["origin_settlement_id"])
	check(cleared == offers.size(),
		"cleared count matches rolled count (cleared=%d, rolled=%d)" % [cleared, offers.size()])
	check(ShippingContractOfferRoller.list_offers(
			fx["party_id"], fx["origin_settlement_id"]).is_empty(),
		"list_offers empty after clear")


func test_clear_for_party_emits_cleared_signal() -> void:
	var fx: Dictionary = _build_two_settlements_with_road({"origin_market_class": 3})
	ShippingContractOfferRoller.roll_for_visit(
		fx["origin_settlement_id"], fx["party_id"], Timekeeping.get_total_days())
	var captured := {"emitted": false, "count": -1}
	var cb: Callable = func(_party_id: String, _set_id: String, n: int) -> void:
		captured["emitted"] = true
		captured["count"] = n
	EventBus.shipping_offer_cleared.connect(cb)
	var cleared: int = ShippingContractOfferRoller.clear_for_party_at_settlement(
		fx["party_id"], fx["origin_settlement_id"])
	EventBus.shipping_offer_cleared.disconnect(cb)
	check(bool(captured["emitted"]), "shipping_offer_cleared emitted")
	check(int(captured["count"]) == cleared,
		"signal payload count matches return value (%d == %d)" % [int(captured["count"]), cleared])


func test_clear_for_party_returns_zero_when_empty() -> void:
	var fx: Dictionary = _build_two_settlements_with_road()
	# No prior roll — clear should be a no-op.
	var cleared: int = ShippingContractOfferRoller.clear_for_party_at_settlement(
		fx["party_id"], fx["origin_settlement_id"])
	check(cleared == 0, "clear with no offers returns 0, got %d" % cleared)


# ---------------------------------------------------------------------------
# Reads
# ---------------------------------------------------------------------------

func test_list_offers_scoped_to_party_and_settlement() -> void:
	var fx: Dictionary = _build_two_settlements_with_road({"origin_market_class": 3})
	ShippingContractOfferRoller.roll_for_visit(
		fx["origin_settlement_id"], fx["party_id"], Timekeeping.get_total_days())
	# Build a DIFFERENT party in the same campaign and verify their list is empty.
	var other_party_id: String = "%s_otherp" % _next_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO parties (id, campaign_id, name) VALUES (?, ?, 'Other')",
		[other_party_id, fx["campaign_id"]])
	var our_offers: Array = ShippingContractOfferRoller.list_offers(
		fx["party_id"], fx["origin_settlement_id"])
	var other_offers: Array = ShippingContractOfferRoller.list_offers(
		other_party_id, fx["origin_settlement_id"])
	check(our_offers.size() > 0, "our offers present")
	check(other_offers.is_empty(), "other party sees no offers (scoping respected)")


func test_get_offer_returns_full_row() -> void:
	var fx: Dictionary = _build_two_settlements_with_road({"origin_market_class": 3})
	var offers: Array = ShippingContractOfferRoller.roll_for_visit(
		fx["origin_settlement_id"], fx["party_id"], Timekeeping.get_total_days())
	check(offers.size() > 0, "precondition: at least one offer")
	var first_id: String = String((offers[0] as Dictionary).get("id", ""))
	var fetched: Dictionary = ShippingContractOfferRoller.get_offer(first_id)
	check(not fetched.is_empty(), "get_offer returns the row")
	check(String(fetched.get("id", "")) == first_id, "fetched id matches")
	# get_offer with empty/missing id returns {}.
	check(ShippingContractOfferRoller.get_offer("nonexistent").is_empty(),
		"missing id returns empty Dict")
	check(ShippingContractOfferRoller.get_offer("").is_empty(),
		"empty id returns empty Dict")


# ---------------------------------------------------------------------------
# Mixed-cargo invariant
# ---------------------------------------------------------------------------

func test_offers_use_mixed_cargo_70_stone_per_load() -> void:
	var fx: Dictionary = _build_two_settlements_with_road({"origin_market_class": 3})
	var offers: Array = ShippingContractOfferRoller.roll_for_visit(
		fx["origin_settlement_id"], fx["party_id"], Timekeeping.get_total_days())
	for o in offers:
		check(String((o as Dictionary).get("merchandise_type", "")) == "mixed_cargo",
			"every offer's merchandise_type = 'mixed_cargo'")
		check(int((o as Dictionary).get("load_weight_stone", 0)) == 70,
			"every offer's load_weight_stone = 70 (RAW L822)")
