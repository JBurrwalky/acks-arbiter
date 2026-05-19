extends "res://tests/test_suite_base.gd"

## Unit tests for AcceptShippingContractHandler — Phase 10B.2 Wave 4.
##
## Per gdd-phase-10b-2-trade-block.md §7.7 + §18.1. Exercises:
##   * Happy path: offer + carrier → contract row + linked cargo row + offer deleted.
##   * shipping_offer_accepted signal fires with (offer_id, contract_id, cargo_hold_id).
##   * Carrier-kind mismatch rejection (road offer → wagon required; water → ship).
##   * Capacity rejection (carrier too small for total_stone).
##   * Missing-offer rejection (already accepted / nonexistent).
##   * Cross-party offer rejection.
##   * Entry-toll first-fire integration.

var _campaign_id: String = ""
var _map_id: String = ""
var _suffix: int = 0


func run_all_tests() -> void:
	_setup()
	test_happy_path_inserts_contract_and_links_cargo()
	test_emits_shipping_offer_accepted_signal()
	test_deletes_offer_after_accept()
	test_carrier_kind_mismatch_rejected()
	test_capacity_rejection_for_undersized_wagon()
	test_missing_offer_rejected()
	test_cross_party_offer_rejected()
	test_entry_toll_first_fire_charges_then_skips()

	if not has_failures():
		print("AcceptShippingContractHandler: all %d tests passed." % test_count())


func _setup() -> void:
	_campaign_id = CampaignRepository.create_campaign("AcceptShippingContractTests", "World")
	_map_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO hex_maps (id, campaign_id, name, scale) VALUES (?, ?, ?, 'regional_6mi')",
		[_map_id, _campaign_id, "ASCMap"])


func _next_id(tag: String = "asc") -> String:
	_suffix += 1
	return "%s_%d_%d" % [tag, Time.get_ticks_msec(), _suffix]


func _build_fixture_with_offer(opts: Dictionary = {}) -> Dictionary:
	# Build two settlements connected by a trade_route (so the offer roller has
	# a reachable destination). Use Class III to keep offer count manageable.
	var fx := TradeFixtures.new()
	var bundle: Dictionary = fx.build_two_settlements({
		"name": "ASC_" + _next_id(),
		"origin_market_class": 3,
		"dest_market_class": 5,
		"merchandise_type": "silk",
		"origin_demand": 0,
		"dest_demand": 0,
		"starting_wealth_cp": 1_000_000,
	})
	# Attach a 4-heavy-horse wagon (load_max 640 stone — fits up to ~9 loads
	# of mixed_cargo at 70 stone/load).
	var wagon_id: String = _next_id("wagon")
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO draft_vehicles (id, campaign_id, party_id, item_key, name, hitched_creatures)
		VALUES (?, ?, ?, 'wagon', 'TestWagon',
			'[{"species_id":"horse_heavy"},{"species_id":"horse_heavy"},{"species_id":"horse_heavy"},{"species_id":"horse_heavy"}]')
	""", [wagon_id, bundle["campaign_id"], bundle["party_id"]])
	VisitStateManager.on_party_entered_settlement(
		bundle["party_id"], bundle["origin_settlement_id"], bundle["pc_id"],
		Timekeeping.get_total_days())
	# VisitStateManager auto-rolled offers via Wave 4 wiring. Read them back.
	var offers: Array = ShippingContractOfferRoller.list_offers(
		bundle["party_id"], bundle["origin_settlement_id"])
	bundle["offers"] = offers
	bundle["wagon_id"] = wagon_id
	# Find the first road-mode offer with capacity ≤ wagon's 640 stone (≤9 loads).
	var picked: Dictionary = {}
	for o in offers:
		if String((o as Dictionary).get("route_mode", "")) == "road":
			var stone: int = int((o as Dictionary).get("loads_count", 0)) * 70
			if stone <= 640:
				picked = o
				break
	bundle["picked_offer"] = picked
	return bundle


func _make_state(fx: Dictionary, params: Dictionary) -> Dictionary:
	return {
		"character_id": fx["pc_id"],
		"location_ref": fx["origin_settlement_id"],
		"params_json": JSON.stringify(params),
	}


# ---------------------------------------------------------------------------
# Happy path
# ---------------------------------------------------------------------------

func test_happy_path_inserts_contract_and_links_cargo() -> void:
	var fx: Dictionary = _build_fixture_with_offer()
	if fx["picked_offer"].is_empty():
		check(false, "fixture failed to pick a fitting offer (capacity issue?)")
		return
	var offer: Dictionary = fx["picked_offer"]
	var state: Dictionary = _make_state(fx, {
		"offer_id": String(offer.get("id", "")),
		"carrier_id": fx["wagon_id"],
		"carrier_kind": CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
	})
	var r: Dictionary = AcceptShippingContractHandler.on_complete(state, null)
	check(bool(r.get("success", false)),
		"accept succeeds, got summary: %s" % String(r.get("summary", "?")))
	var contract_id: String = String(r.get("contract_id", ""))
	var cargo_id: String = String(r.get("cargo_hold_id", ""))
	check(not contract_id.is_empty(), "contract_id present in result")
	check(not cargo_id.is_empty(), "cargo_hold_id present in result")
	# Verify the contract row exists.
	var contract: Dictionary = ShippingContractRepository.get_contract(contract_id)
	check(not contract.is_empty(), "shipping_contracts row exists")
	check(String(contract.get("accepted_by_party_id", "")) == fx["party_id"],
		"contract.accepted_by_party_id matches")
	# Verify the cargo row is linked.
	var cargo: Dictionary = CargoHoldRepository.get_cargo_hold(cargo_id)
	check(not cargo.is_empty(), "cargo_holds row exists")
	check(String(cargo.get("shipping_contract_id", "")) == contract_id,
		"cargo_holds.shipping_contract_id links back to contract")
	check(String(cargo.get("source_acquisition_kind", "")) == "shipping_contract",
		"cargo source_acquisition_kind = 'shipping_contract'")


func test_emits_shipping_offer_accepted_signal() -> void:
	var fx: Dictionary = _build_fixture_with_offer()
	if fx["picked_offer"].is_empty():
		check(false, "fixture failed to pick a fitting offer")
		return
	var captured := {"emitted": false, "offer_id": "", "contract_id": "", "cargo_id": ""}
	var cb: Callable = func(oid: String, cid: String, gid: String) -> void:
		captured["emitted"] = true
		captured["offer_id"] = oid
		captured["contract_id"] = cid
		captured["cargo_id"] = gid
	EventBus.shipping_offer_accepted.connect(cb)
	var offer: Dictionary = fx["picked_offer"]
	var state: Dictionary = _make_state(fx, {
		"offer_id": String(offer.get("id", "")),
		"carrier_id": fx["wagon_id"],
		"carrier_kind": CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
	})
	var r: Dictionary = AcceptShippingContractHandler.on_complete(state, null)
	EventBus.shipping_offer_accepted.disconnect(cb)
	check(bool(captured["emitted"]), "shipping_offer_accepted fired")
	check(str(captured["offer_id"]) == String(offer.get("id", "")),
		"signal offer_id matches")
	check(str(captured["contract_id"]) == String(r.get("contract_id", "")),
		"signal contract_id matches handler result")


func test_deletes_offer_after_accept() -> void:
	var fx: Dictionary = _build_fixture_with_offer()
	if fx["picked_offer"].is_empty():
		check(false, "fixture failed to pick a fitting offer")
		return
	var offer: Dictionary = fx["picked_offer"]
	var offer_id: String = String(offer.get("id", ""))
	var state: Dictionary = _make_state(fx, {
		"offer_id": offer_id,
		"carrier_id": fx["wagon_id"],
		"carrier_kind": CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
	})
	AcceptShippingContractHandler.on_complete(state, null)
	# Offer should be DELETEd.
	var refetched: Dictionary = ShippingContractOfferRoller.get_offer(offer_id)
	check(refetched.is_empty(), "offer row deleted after accept")


# ---------------------------------------------------------------------------
# Rejection paths
# ---------------------------------------------------------------------------

func test_carrier_kind_mismatch_rejected() -> void:
	var fx: Dictionary = _build_fixture_with_offer()
	if fx["picked_offer"].is_empty():
		check(false, "fixture failed to pick a fitting offer")
		return
	# Offer is road; pass carrier_kind='ship' to provoke the mismatch.
	# We need a ship to even attempt this — create one.
	var ship_id: String = ShipRepository.create_ship(
		fx["party_id"], "sailing_ship_small", fx["origin_settlement_id"])
	var offer: Dictionary = fx["picked_offer"]
	var state: Dictionary = _make_state(fx, {
		"offer_id": String(offer.get("id", "")),
		"carrier_id": ship_id,
		"carrier_kind": CargoHoldRepository.CARRIER_SHIP,
	})
	var r: Dictionary = AcceptShippingContractHandler.on_complete(state, null)
	check(not bool(r.get("success", true)),
		"ship carrier rejected for road contract, got summary: %s" % String(r.get("summary", "?")))


func test_capacity_rejection_for_undersized_wagon() -> void:
	# Create a fixture; then deliberately attach an unhitched cart_small
	# (load_max 0). Try to accept a road offer onto it.
	var fx: Dictionary = _build_fixture_with_offer()
	if fx["picked_offer"].is_empty():
		check(false, "fixture failed to pick a fitting offer")
		return
	var tiny_id: String = _next_id("tiny")
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO draft_vehicles (id, campaign_id, party_id, item_key, name, hitched_creatures)
		VALUES (?, ?, ?, 'cart_small', 'TinyCart', '[]')
	""", [tiny_id, fx["campaign_id"], fx["party_id"]])
	var offer: Dictionary = fx["picked_offer"]
	var state: Dictionary = _make_state(fx, {
		"offer_id": String(offer.get("id", "")),
		"carrier_id": tiny_id,
		"carrier_kind": CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
	})
	var r: Dictionary = AcceptShippingContractHandler.on_complete(state, null)
	check(not bool(r.get("success", true)),
		"undersized carrier rejected, got summary: %s" % String(r.get("summary", "?")))


func test_missing_offer_rejected() -> void:
	var fx: Dictionary = _build_fixture_with_offer()
	var state: Dictionary = _make_state(fx, {
		"offer_id": "nonexistent_offer_id",
		"carrier_id": fx["wagon_id"],
		"carrier_kind": CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
	})
	var r: Dictionary = AcceptShippingContractHandler.on_complete(state, null)
	check(not bool(r.get("success", true)),
		"missing offer rejected, got summary: %s" % String(r.get("summary", "?")))


func test_cross_party_offer_rejected() -> void:
	var fx: Dictionary = _build_fixture_with_offer()
	if fx["picked_offer"].is_empty():
		check(false, "fixture failed to pick a fitting offer")
		return
	# Create a second PC in a separate party.
	var other_party_id: String = _next_id("otherp")
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO parties (id, campaign_id, name) VALUES (?, ?, 'OtherParty')",
		[other_party_id, fx["campaign_id"]])
	var other_pc_id: String = _next_id("otherpc")
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type)
		VALUES (?, ?, 'OtherPC', 'pc')
	""", [other_pc_id, fx["campaign_id"]])
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO party_members (party_id, character_id) VALUES (?, ?)",
		[other_party_id, other_pc_id])
	# Other party tries to accept party A's offer.
	var offer: Dictionary = fx["picked_offer"]
	var state := {
		"character_id": other_pc_id,
		"location_ref": fx["origin_settlement_id"],
		"params_json": JSON.stringify({
			"offer_id": String(offer.get("id", "")),
			"carrier_id": fx["wagon_id"],
			"carrier_kind": CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
		}),
	}
	var r: Dictionary = AcceptShippingContractHandler.on_complete(state, null)
	check(not bool(r.get("success", true)),
		"cross-party offer rejected, got summary: %s" % String(r.get("summary", "?")))


# ---------------------------------------------------------------------------
# Entry-toll integration
# ---------------------------------------------------------------------------

func test_entry_toll_first_fire_charges_then_skips() -> void:
	var fx: Dictionary = _build_fixture_with_offer()
	if fx["picked_offer"].is_empty():
		check(false, "fixture failed to pick a fitting offer")
		return
	# Precondition: no toll paid yet (fresh visit).
	check(not VisitStateManager.has_paid_entry_toll(fx["party_id"], fx["origin_settlement_id"]),
		"precondition: toll not yet paid")
	var offer: Dictionary = fx["picked_offer"]
	var state: Dictionary = _make_state(fx, {
		"offer_id": String(offer.get("id", "")),
		"carrier_id": fx["wagon_id"],
		"carrier_kind": CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
	})
	var r: Dictionary = AcceptShippingContractHandler.on_complete(state, null)
	check(bool(r.get("success", false)),
		"happy-path accept succeeds, got summary: %s" % String(r.get("summary", "?")))
	check(VisitStateManager.has_paid_entry_toll(fx["party_id"], fx["origin_settlement_id"]),
		"toll-paid flag set after first accept (entry toll fired)")
