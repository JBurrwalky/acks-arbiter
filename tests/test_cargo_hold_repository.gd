extends "res://tests/test_suite_base.gd"

## Unit tests for CargoHoldRepository — cargo persistence + typed inserts +
## transfer + delete_sold per Prereq.5b.
##
## Per generation/gdd-settlement-economy.md §9.12.

var _campaign_id: String = ""
var _map_id: String = ""
var _settlement_id: String = ""
var _party_id: String = ""
var _suffix: int = 0


func run_all_tests() -> void:
	_setup()
	test_insert_purchase_creates_row()
	test_insert_purchase_emits_signal()
	test_insert_hijink_yield_smuggled()
	test_insert_hijink_yield_stolen()
	test_insert_hijink_yield_invalid_kind_rejected()
	test_xor_constraint_both_carriers_rejected()
	test_xor_constraint_neither_carrier_rejected()
	test_list_for_draft_vehicle_filters_by_carrier()
	test_list_for_ship_filters_by_carrier()
	test_transfer_loads_partial()
	test_transfer_loads_full_deletes_source()
	test_transfer_loads_insufficient()
	test_delete_sold_removes_row_and_emits_signal()
	test_multiple_acquisitions_remain_separate_rows()
	test_load_weight_cached_from_registry()

	# Phase 10B.2 Wave 1 substrate amendments (§13.2 + §13.5)
	test_partial_sell_decrements_loads()
	test_partial_sell_delegates_to_delete_at_zero()
	test_partial_sell_rejects_over_sell()
	test_partial_sell_emits_cargo_sold()
	test_list_for_party_active_carriers_aggregates_both()
	test_list_for_party_active_carriers_filters_destroyed()

	if not has_failures():
		print("CargoHoldRepository: all %d tests passed." % test_count())


func _setup() -> void:
	_campaign_id = CampaignRepository.create_campaign("CargoHoldRepositoryTests", "World")
	_map_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO hex_maps (id, campaign_id, name, scale) VALUES (?, ?, ?, 'regional_6mi')",
		[_map_id, _campaign_id, "CHRMap"]
	)
	_settlement_id = "%s_dock" % _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_entrances
			(id, campaign_id, map_id, hex_q, hex_r, name, market_class)
		VALUES (?, ?, ?, 0, 0, 'TestPort', 3)
	""", [_settlement_id, _campaign_id, _map_id])
	_party_id = "%s_party" % _next_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO parties (id, campaign_id, name) VALUES (?, ?, 'P')",
		[_party_id, _campaign_id])


func _next_id() -> String:
	_suffix += 1
	return "chr_%d_%d" % [Time.get_ticks_msec(), _suffix]


func _make_wagon() -> String:
	var vid: String = "%s_wagon" % _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO draft_vehicles (id, campaign_id, party_id, item_key, name)
		VALUES (?, ?, ?, 'wagon', 'TestWagon')
	""", [vid, _campaign_id, _party_id])
	return vid


func _make_ship() -> String:
	return ShipRepository.create_ship(_party_id, "sailing_ship_small", _settlement_id)


# ---------------------------------------------------------------------------
# Insert paths
# ---------------------------------------------------------------------------

func test_insert_purchase_creates_row() -> void:
	var wagon: String = _make_wagon()
	var cid: String = CargoHoldRepository.insert_purchase(
		wagon, CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
		"silk", 5, 12000, _settlement_id, 100)
	check(not cid.is_empty(), "insert_purchase returns non-empty id")
	var row: Dictionary = CargoHoldRepository.get_cargo_hold(cid)
	check(str(row.get("merchandise_type", "")) == "silk", "merchandise_type persisted")
	check(int(row.get("loads_count", 0)) == 5, "loads_count = 5")
	check(int(row.get("market_value_at_acquisition_cp", 0)) == 12000, "market_value = 12000")
	check(str(row.get("source_acquisition_kind", "")) == "purchased", "source_kind = 'purchased'")
	check(str(row.get("draft_vehicle_id", "")) == wagon, "draft_vehicle_id set")
	check(row.get("ship_id", null) == null, "ship_id NULL (XOR)")
	check(int(row.get("acquired_at_calendar_day", 0)) == 100, "calendar day persisted")


func test_insert_purchase_emits_signal() -> void:
	var wagon: String = _make_wagon()
	var received := {"emitted": false, "cargo_id": "", "carrier": "", "merch": "", "loads": -1}
	var cb: Callable = func(cid: String, carrier: String, merch: String, loads: int) -> void:
		received["emitted"] = true
		received["cargo_id"] = cid
		received["carrier"] = carrier
		received["merch"] = merch
		received["loads"] = loads
	EventBus.cargo_loaded.connect(cb)
	var cid: String = CargoHoldRepository.insert_purchase(
		wagon, CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
		"grain_vegetables", 10, 100, _settlement_id, 0)
	EventBus.cargo_loaded.disconnect(cb)
	check(bool(received["emitted"]), "cargo_loaded fires on insert")
	check(str(received["cargo_id"]) == cid, "signal payload cargo_id matches")
	check(str(received["carrier"]) == wagon, "signal payload carrier matches")
	check(str(received["merch"]) == "grain_vegetables", "signal payload merch matches")
	check(int(received["loads"]) == 10, "signal payload loads = 10")


func test_insert_hijink_yield_smuggled() -> void:
	var ship: String = _make_ship()
	var cid: String = CargoHoldRepository.insert_hijink_yield(
		ship, CargoHoldRepository.CARRIER_SHIP,
		"spices", 30, 24000, _settlement_id, 50, "smuggled")
	check(not cid.is_empty(), "insert_hijink_yield smuggled returns id")
	var row: Dictionary = CargoHoldRepository.get_cargo_hold(cid)
	check(str(row.get("source_acquisition_kind", "")) == "smuggled", "source_kind = 'smuggled'")
	check(int(row.get("market_value_at_acquisition_cp", 0)) == 24000, "notional market_value = 24000")
	check(str(row.get("ship_id", "")) == ship, "ship_id set")
	check(row.get("draft_vehicle_id", null) == null, "draft_vehicle_id NULL")


func test_insert_hijink_yield_stolen() -> void:
	var wagon: String = _make_wagon()
	var cid: String = CargoHoldRepository.insert_hijink_yield(
		wagon, CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
		"metals_common", 6, 1800, _settlement_id, 10, "stolen")
	check(not cid.is_empty(), "stolen yield row created")
	var row: Dictionary = CargoHoldRepository.get_cargo_hold(cid)
	check(str(row.get("source_acquisition_kind", "")) == "stolen", "source_kind = 'stolen'")


func test_insert_hijink_yield_invalid_kind_rejected() -> void:
	var wagon: String = _make_wagon()
	var cid: String = CargoHoldRepository.insert_hijink_yield(
		wagon, CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
		"silk", 1, 100, _settlement_id, 0, "purchased")
	check(cid.is_empty(), "non-hijink kind 'purchased' should be rejected by hijink helper")


# ---------------------------------------------------------------------------
# XOR CHECK constraints
# ---------------------------------------------------------------------------

func test_xor_constraint_both_carriers_rejected() -> void:
	var wagon: String = _make_wagon()
	var ship: String = _make_ship()
	# Direct INSERT bypassing the typed helpers — both carrier FKs set.
	var ok: bool = CampaignRepository.db.query_with_bindings("""
		INSERT INTO cargo_holds
			(id, campaign_id, draft_vehicle_id, ship_id,
			 merchandise_type, loads_count, load_weight_stone,
			 market_value_at_acquisition_cp, source_acquisition_kind,
			 acquired_at_calendar_day)
		VALUES (?, ?, ?, ?, 'silk', 1, 20, 100, 'purchased', 0)
	""", ["%s_both" % _next_id(), _campaign_id, wagon, ship])
	check(not ok, "INSERT with BOTH draft_vehicle_id and ship_id should fail XOR CHECK")


func test_xor_constraint_neither_carrier_rejected() -> void:
	var ok: bool = CampaignRepository.db.query_with_bindings("""
		INSERT INTO cargo_holds
			(id, campaign_id, draft_vehicle_id, ship_id,
			 merchandise_type, loads_count, load_weight_stone,
			 market_value_at_acquisition_cp, source_acquisition_kind,
			 acquired_at_calendar_day)
		VALUES (?, ?, NULL, NULL, 'silk', 1, 20, 100, 'purchased', 0)
	""", ["%s_neither" % _next_id(), _campaign_id])
	check(not ok, "INSERT with NEITHER carrier should fail XOR CHECK")


# ---------------------------------------------------------------------------
# Reads
# ---------------------------------------------------------------------------

func test_list_for_draft_vehicle_filters_by_carrier() -> void:
	var wagon: String = _make_wagon()
	var ship: String = _make_ship()
	CargoHoldRepository.insert_purchase(wagon, CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
		"salt", 2, 200, _settlement_id, 0)
	CargoHoldRepository.insert_purchase(wagon, CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
		"silk", 3, 6000, _settlement_id, 0)
	CargoHoldRepository.insert_purchase(ship, CargoHoldRepository.CARRIER_SHIP,
		"spices", 5, 4000, _settlement_id, 0)
	check(CargoHoldRepository.list_for_draft_vehicle(wagon).size() == 2,
		"wagon list returns 2 rows, got %d" % CargoHoldRepository.list_for_draft_vehicle(wagon).size())
	check(CargoHoldRepository.list_for_ship(ship).size() == 1,
		"ship list returns 1 row")


func test_list_for_ship_filters_by_carrier() -> void:
	var ship: String = _make_ship()
	CargoHoldRepository.insert_purchase(ship, CargoHoldRepository.CARRIER_SHIP,
		"silk", 5, 10000, _settlement_id, 0)
	CargoHoldRepository.insert_purchase(ship, CargoHoldRepository.CARRIER_SHIP,
		"gems", 1, 3000, _settlement_id, 0)
	var rows: Array = CargoHoldRepository.list_for_ship(ship)
	check(rows.size() == 2, "ship list returns 2 rows")
	var types: Dictionary = {}
	for r in rows:
		types[str((r as Dictionary).get("merchandise_type", ""))] = true
	check(types.has("silk") and types.has("gems"), "both merchandise types present")


# ---------------------------------------------------------------------------
# Transfer
# ---------------------------------------------------------------------------

func test_transfer_loads_partial() -> void:
	var wagon: String = _make_wagon()
	var ship: String = _make_ship()
	var source_id: String = CargoHoldRepository.insert_purchase(
		wagon, CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
		"silk", 10, 20000, _settlement_id, 0)
	var result: Dictionary = CargoHoldRepository.transfer_loads(
		source_id, ship, CargoHoldRepository.CARRIER_SHIP, 4)
	check(bool(result.get("success", false)), "partial transfer succeeds")
	check(int(result.get("source_remaining", -1)) == 6, "source has 10-4 = 6 loads left")
	var target_id: String = str(result.get("target_cargo_hold_id", ""))
	check(not target_id.is_empty(), "target id present")
	var source: Dictionary = CargoHoldRepository.get_cargo_hold(source_id)
	check(int(source.get("loads_count", 0)) == 6, "source row updated to 6")
	var target: Dictionary = CargoHoldRepository.get_cargo_hold(target_id)
	check(int(target.get("loads_count", 0)) == 4, "target row has 4 loads")
	check(str(target.get("ship_id", "")) == ship, "target row on ship")
	check(target.get("draft_vehicle_id", null) == null, "target draft_vehicle_id NULL")
	# Provenance carried over.
	check(str(target.get("source_acquisition_kind", "")) == "purchased",
		"source_kind preserved across transfer")
	check(int(target.get("market_value_at_acquisition_cp", 0)) == 20000,
		"market_value preserved across transfer")


func test_transfer_loads_full_deletes_source() -> void:
	var wagon: String = _make_wagon()
	var ship: String = _make_ship()
	var source_id: String = CargoHoldRepository.insert_purchase(
		wagon, CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
		"silk", 3, 6000, _settlement_id, 0)
	var result: Dictionary = CargoHoldRepository.transfer_loads(
		source_id, ship, CargoHoldRepository.CARRIER_SHIP, 3)
	check(bool(result.get("success", false)), "full transfer succeeds")
	check(int(result.get("source_remaining", -1)) == 0, "source_remaining = 0")
	# Source row should be deleted.
	check(CargoHoldRepository.get_cargo_hold(source_id).is_empty(),
		"source row deleted after full transfer")


func test_transfer_loads_insufficient() -> void:
	var wagon: String = _make_wagon()
	var ship: String = _make_ship()
	var source_id: String = CargoHoldRepository.insert_purchase(
		wagon, CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
		"salt", 2, 200, _settlement_id, 0)
	var result: Dictionary = CargoHoldRepository.transfer_loads(
		source_id, ship, CargoHoldRepository.CARRIER_SHIP, 5)
	check(not bool(result.get("success", true)), "transfer of 5 from 2-load source fails")
	check(str(result.get("error", "")) == "insufficient_loads", "error = 'insufficient_loads'")
	# Source unchanged.
	var source: Dictionary = CargoHoldRepository.get_cargo_hold(source_id)
	check(int(source.get("loads_count", -1)) == 2, "source loads_count unchanged at 2")


# ---------------------------------------------------------------------------
# Delete on sale
# ---------------------------------------------------------------------------

func test_delete_sold_removes_row_and_emits_signal() -> void:
	var wagon: String = _make_wagon()
	var cid: String = CargoHoldRepository.insert_purchase(
		wagon, CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
		"silk", 5, 10000, _settlement_id, 0)
	var got_signal := {"emitted": false, "cargo_id": "", "cp": -1}
	var cb: Callable = func(c_id: String, cp: int) -> void:
		got_signal["emitted"] = true
		got_signal["cargo_id"] = c_id
		got_signal["cp"] = cp
	EventBus.cargo_sold.connect(cb)
	check(CargoHoldRepository.delete_sold(cid, 13500), "delete_sold returns true")
	EventBus.cargo_sold.disconnect(cb)
	check(CargoHoldRepository.get_cargo_hold(cid).is_empty(), "row removed from cache")
	check(bool(got_signal["emitted"]), "cargo_sold signal fired")
	check(str(got_signal["cargo_id"]) == cid, "signal payload cargo_id matches")
	check(int(got_signal["cp"]) == 13500, "signal payload cp_received = 13500")


# ---------------------------------------------------------------------------
# Multiple acquisitions
# ---------------------------------------------------------------------------

func test_multiple_acquisitions_remain_separate_rows() -> void:
	# Per §9.4 — different acquired_at_calendar_day or different source kind
	# means separate rows for the same merchandise_type.
	var wagon: String = _make_wagon()
	var cid1: String = CargoHoldRepository.insert_purchase(
		wagon, CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
		"grain_vegetables", 5, 50, _settlement_id, 10)
	var cid2: String = CargoHoldRepository.insert_purchase(
		wagon, CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
		"grain_vegetables", 5, 60, _settlement_id, 12)
	check(cid1 != cid2, "two purchases yield two distinct ids")
	var rows: Array = CargoHoldRepository.list_for_draft_vehicle(wagon)
	check(rows.size() == 2, "two separate rows persisted")
	# market_value per row preserves the per-acquisition snapshot.
	var by_day: Dictionary = {}
	for r in rows:
		by_day[int((r as Dictionary).get("acquired_at_calendar_day", -1))] = int((r as Dictionary).get("market_value_at_acquisition_cp", 0))
	check(int(by_day.get(10, -1)) == 50, "day-10 row has market_value = 50")
	check(int(by_day.get(12, -1)) == 60, "day-12 row has market_value = 60")


# ---------------------------------------------------------------------------
# Cached load_weight_stone
# ---------------------------------------------------------------------------

func test_load_weight_cached_from_registry() -> void:
	var wagon: String = _make_wagon()
	# silk: 20 stone/load per the merchandise registry.
	var cid_silk: String = CargoHoldRepository.insert_purchase(
		wagon, CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
		"silk", 1, 2000, _settlement_id, 0)
	var silk: Dictionary = CargoHoldRepository.get_cargo_hold(cid_silk)
	check(int(silk.get("load_weight_stone", 0)) == 20,
		"silk cached load_weight = 20 stone, got %d" % int(silk.get("load_weight_stone", 0)))
	# grain_vegetables: 80 stone/load.
	var cid_grain: String = CargoHoldRepository.insert_purchase(
		wagon, CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
		"grain_vegetables", 1, 10, _settlement_id, 0)
	var grain: Dictionary = CargoHoldRepository.get_cargo_hold(cid_grain)
	check(int(grain.get("load_weight_stone", 0)) == 80,
		"grain cached load_weight = 80 stone")


# ---------------------------------------------------------------------------
# Phase 10B.2 Wave 1 substrate amendments — partial_sell + list_for_party_active_carriers
# Per gdd-phase-10b-2-trade-block.md §13.2 + §13.5.
# ---------------------------------------------------------------------------

func test_partial_sell_decrements_loads() -> void:
	var wagon: String = _make_wagon()
	var cid: String = CargoHoldRepository.insert_purchase(
		wagon, CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
		"silk", 10, 20000, _settlement_id, 0)
	check(CargoHoldRepository.partial_sell(cid, 3, 6000), "partial_sell 3/10 returns true")
	var row: Dictionary = CargoHoldRepository.get_cargo_hold(cid)
	check(int(row.get("loads_count", 0)) == 7,
		"partial_sell decremented loads_count from 10 to 7, got %d" % int(row.get("loads_count", 0)))


func test_partial_sell_delegates_to_delete_at_zero() -> void:
	var wagon: String = _make_wagon()
	var cid: String = CargoHoldRepository.insert_purchase(
		wagon, CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
		"silk", 5, 10000, _settlement_id, 0)
	check(CargoHoldRepository.partial_sell(cid, 5, 13000),
		"partial_sell at full quantity returns true")
	check(CargoHoldRepository.get_cargo_hold(cid).is_empty(),
		"row deleted when partial_sell consumes full quantity")


func test_partial_sell_rejects_over_sell() -> void:
	var wagon: String = _make_wagon()
	var cid: String = CargoHoldRepository.insert_purchase(
		wagon, CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
		"silk", 5, 10000, _settlement_id, 0)
	check(not CargoHoldRepository.partial_sell(cid, 6, 12000),
		"partial_sell of 6/5 returns false")
	var row: Dictionary = CargoHoldRepository.get_cargo_hold(cid)
	check(int(row.get("loads_count", 0)) == 5,
		"row unchanged at 5 loads after rejected over-sell")
	check(not CargoHoldRepository.partial_sell(cid, 0, 0),
		"partial_sell with loads_to_sell=0 returns false")
	check(not CargoHoldRepository.partial_sell("", 1, 100),
		"partial_sell with empty cargo_hold_id returns false")
	check(not CargoHoldRepository.partial_sell("nonexistent_id", 1, 100),
		"partial_sell on missing row returns false")


func test_partial_sell_emits_cargo_sold() -> void:
	var wagon: String = _make_wagon()
	var cid: String = CargoHoldRepository.insert_purchase(
		wagon, CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
		"silk", 8, 16000, _settlement_id, 0)
	var captured := {"emitted": false, "cp": 0, "cid": ""}
	var cb: Callable = func(c_id: String, cp: int) -> void:
		captured["emitted"] = true
		captured["cp"] = cp
		captured["cid"] = c_id
	EventBus.cargo_sold.connect(cb)
	CargoHoldRepository.partial_sell(cid, 3, 7800)
	EventBus.cargo_sold.disconnect(cb)
	check(bool(captured["emitted"]), "partial_sell emits cargo_sold on partial path")
	check(int(captured["cp"]) == 7800, "signal payload cp_received = 7800")
	check(str(captured["cid"]) == cid, "signal payload cargo_id matches")


func test_list_for_party_active_carriers_aggregates_both() -> void:
	# Pattern 1: separate party so other suite-leftover rows don't bleed in.
	var party_id: String = "%s_party_active" % _next_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO parties (id, campaign_id, name) VALUES (?, ?, 'PActive')",
		[party_id, _campaign_id])
	# Wagon + ship attached to this isolated party.
	var wagon_id: String = "%s_wagon_active" % _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO draft_vehicles (id, campaign_id, party_id, item_key, name)
		VALUES (?, ?, ?, 'wagon', 'ActiveWagon')
	""", [wagon_id, _campaign_id, party_id])
	var ship_id: String = ShipRepository.create_ship(party_id, "sailing_ship_small", _settlement_id)
	# Two cargo rows — one per carrier.
	CargoHoldRepository.insert_purchase(wagon_id, CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
		"silk", 2, 4000, _settlement_id, 0)
	CargoHoldRepository.insert_purchase(ship_id, CargoHoldRepository.CARRIER_SHIP,
		"gems", 1, 3000, _settlement_id, 0)
	var rows: Array = CargoHoldRepository.list_for_party_active_carriers(party_id)
	check(rows.size() == 2,
		"list_for_party_active_carriers returns 2 rows across wagon + ship, got %d" % rows.size())
	var seen: Dictionary = {}
	for r in rows:
		seen[str((r as Dictionary).get("merchandise_type", ""))] = true
	check(seen.has("silk") and seen.has("gems"),
		"both wagon (silk) and ship (gems) cargo present in aggregation")


func test_list_for_party_active_carriers_filters_destroyed() -> void:
	var party_id: String = "%s_party_destroy" % _next_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO parties (id, campaign_id, name) VALUES (?, ?, 'PDestroy')",
		[party_id, _campaign_id])
	var alive_wagon: String = "%s_alive_wagon" % _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO draft_vehicles (id, campaign_id, party_id, item_key, name)
		VALUES (?, ?, ?, 'wagon', 'AliveWagon')
	""", [alive_wagon, _campaign_id, party_id])
	var dead_wagon: String = "%s_dead_wagon" % _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO draft_vehicles (id, campaign_id, party_id, item_key, name, is_destroyed)
		VALUES (?, ?, ?, 'wagon', 'DeadWagon', 1)
	""", [dead_wagon, _campaign_id, party_id])
	CargoHoldRepository.insert_purchase(alive_wagon, CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
		"silk", 1, 2000, _settlement_id, 0)
	# Insert on dead wagon BEFORE destruction would be the realistic order, but
	# the helper just rejects is_destroyed != 0 on read regardless.
	CargoHoldRepository.insert_purchase(dead_wagon, CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
		"gems", 1, 3000, _settlement_id, 0)
	var rows: Array = CargoHoldRepository.list_for_party_active_carriers(party_id)
	check(rows.size() == 1,
		"list_for_party_active_carriers filters destroyed wagon's cargo, got %d row(s)" % rows.size())
	check(str((rows[0] as Dictionary).get("merchandise_type", "")) == "silk",
		"surviving cargo is the silk on the alive wagon")
