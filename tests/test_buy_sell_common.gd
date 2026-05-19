extends "res://tests/test_suite_base.gd"

## Unit tests for BuySellCommon — Phase 10B.2 Wave 1.
##
## Per generation/gdd-phase-10b-2-trade-block.md §3.4 + §18.1.

var _campaign_id: String = ""
var _map_id: String = ""
var _suffix: int = 0


func run_all_tests() -> void:
	_setup()
	test_resolve_party_for_character_happy_path()
	test_resolve_party_for_character_empty_input()
	test_resolve_party_for_character_unlinked_returns_empty()
	test_transaction_rng_deterministic_per_day()
	test_transaction_rng_differs_across_inputs()
	test_carrier_has_capacity_under_limit_true()
	test_carrier_has_capacity_over_limit_false()
	test_carrier_has_capacity_unknown_kind_false()
	test_charge_entry_toll_first_fire_records_state()
	test_charge_entry_toll_subsequent_calls_return_zero()
	test_charge_entry_toll_no_settlement_returns_zero()
	test_build_buy_receipt_totals()
	test_build_sell_receipt_totals()

	if not has_failures():
		print("BuySellCommon: all %d tests passed." % test_count())


func _setup() -> void:
	_campaign_id = CampaignRepository.create_campaign("BuySellCommonTests", "World")
	_map_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO hex_maps (id, campaign_id, name, scale) VALUES (?, ?, ?, 'regional_6mi')",
		[_map_id, _campaign_id, "BSCMap"])


func _next_id(tag: String = "bsc") -> String:
	_suffix += 1
	return "%s_%d_%d" % [tag, Time.get_ticks_msec(), _suffix]


func _make_party_with_pc(starting_wealth_cp: int = 1_000_000) -> Dictionary:
	var pc_id: String = _next_id("char")
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type)
		VALUES (?, ?, ?, 'pc')
	""", [pc_id, _campaign_id, "PC_" + pc_id])
	var party_id: String = _next_id("party")
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO parties (id, campaign_id, name) VALUES (?, ?, ?)",
		[party_id, _campaign_id, "Party_" + party_id])
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO party_members (party_id, character_id) VALUES (?, ?)",
		[party_id, pc_id])
	if starting_wealth_cp > 0:
		CampaignRepository.add_coins_cp(pc_id, starting_wealth_cp)
	return {"party_id": party_id, "pc_id": pc_id}


func _make_settlement(market_class: int = 3) -> String:
	var sid: String = _next_id("set")
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_entrances
			(id, campaign_id, map_id, hex_q, hex_r, name, market_class)
		VALUES (?, ?, ?, ?, 0, ?, ?)
	""", [sid, _campaign_id, _map_id, _suffix, "Settlement_" + sid, market_class])
	return sid


func _attach_wagon(party_id: String) -> String:
	var vid: String = _next_id("wagon")
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO draft_vehicles (id, campaign_id, party_id, item_key, name, hitched_creatures)
		VALUES (?, ?, ?, 'wagon', 'TestWagon',
			'[{"species_id":"horse_heavy"},{"species_id":"horse_heavy"}]')
	""", [vid, _campaign_id, party_id])
	return vid


# ---------------------------------------------------------------------------
# Party resolution
# ---------------------------------------------------------------------------

func test_resolve_party_for_character_happy_path() -> void:
	var p: Dictionary = _make_party_with_pc()
	check(BuySellCommon.resolve_party_for_character(p["pc_id"]) == p["party_id"],
		"resolve_party_for_character returns the joined party_id")


func test_resolve_party_for_character_empty_input() -> void:
	check(BuySellCommon.resolve_party_for_character("") == "",
		"empty character_id returns ''")


func test_resolve_party_for_character_unlinked_returns_empty() -> void:
	# Create a PC NOT in any party.
	var lonely_id: String = _next_id("lonely")
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type)
		VALUES (?, ?, 'Lonely', 'pc')
	""", [lonely_id, _campaign_id])
	check(BuySellCommon.resolve_party_for_character(lonely_id) == "",
		"PC not in any party returns ''")


# ---------------------------------------------------------------------------
# Transaction RNG
# ---------------------------------------------------------------------------

func test_transaction_rng_deterministic_per_day() -> void:
	# Same (party, settlement, day) → same RNG state → same first roll.
	var rng_a: RandomNumberGenerator = BuySellCommon.transaction_rng("p1", "s1")
	var rng_b: RandomNumberGenerator = BuySellCommon.transaction_rng("p1", "s1")
	var roll_a: int = rng_a.randi_range(1, 100)
	var roll_b: int = rng_b.randi_range(1, 100)
	check(roll_a == roll_b,
		"identical inputs produce identical first roll (got %d vs %d)" % [roll_a, roll_b])


func test_transaction_rng_differs_across_inputs() -> void:
	# Different inputs should produce different seeds (high probability — not
	# bit-for-bit guaranteed but vanishingly unlikely to collide for distinct strings).
	var rng_a: RandomNumberGenerator = BuySellCommon.transaction_rng("partyA", "settA")
	var rng_b: RandomNumberGenerator = BuySellCommon.transaction_rng("partyB", "settA")
	check(rng_a.seed != rng_b.seed,
		"different party_id produces different seed (a=%d b=%d)" % [rng_a.seed, rng_b.seed])


# ---------------------------------------------------------------------------
# Carrier capacity check
# ---------------------------------------------------------------------------

func test_carrier_has_capacity_under_limit_true() -> void:
	var p: Dictionary = _make_party_with_pc()
	var wagon: String = _attach_wagon(p["party_id"])
	# Wagon hitched with 2 heavy horses: load_max = 2 × 160 = 320 stone (per
	# substrate draft-vehicle table). 100 stone request should fit.
	check(BuySellCommon.carrier_has_capacity(wagon, CargoHoldRepository.CARRIER_DRAFT_VEHICLE, 100),
		"wagon has capacity for 100 stone")


func test_carrier_has_capacity_over_limit_false() -> void:
	var p: Dictionary = _make_party_with_pc()
	var wagon: String = _attach_wagon(p["party_id"])
	# Far over capacity — 100,000 stone shouldn't fit any wagon.
	check(not BuySellCommon.carrier_has_capacity(wagon, CargoHoldRepository.CARRIER_DRAFT_VEHICLE, 100_000),
		"wagon rejects 100,000 stone")


func test_carrier_has_capacity_unknown_kind_false() -> void:
	check(not BuySellCommon.carrier_has_capacity("anything", "elephant", 5),
		"unknown carrier_kind returns false")
	check(not BuySellCommon.carrier_has_capacity("", CargoHoldRepository.CARRIER_DRAFT_VEHICLE, 5),
		"empty carrier_id returns false")
	check(not BuySellCommon.carrier_has_capacity("any", CargoHoldRepository.CARRIER_DRAFT_VEHICLE, -1),
		"negative incremental_stone returns false")


# ---------------------------------------------------------------------------
# Entry toll first-fire integration with VisitStateManager
# ---------------------------------------------------------------------------

func test_charge_entry_toll_first_fire_records_state() -> void:
	var p: Dictionary = _make_party_with_pc()
	var s: String = _make_settlement(5)  # Class V → toll 1d6
	VisitStateManager.on_party_entered_settlement(p["party_id"], s, p["pc_id"], 10)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var charged: int = BuySellCommon.charge_entry_toll_if_first_visit(
		p["party_id"], s, false, 0, rng)
	check(charged >= 0,
		"toll is non-negative (got %d)" % charged)
	check(VisitStateManager.has_paid_entry_toll(p["party_id"], s),
		"toll-paid flag set after first charge")


func test_charge_entry_toll_subsequent_calls_return_zero() -> void:
	var p: Dictionary = _make_party_with_pc()
	var s: String = _make_settlement(3)
	VisitStateManager.on_party_entered_settlement(p["party_id"], s, p["pc_id"], 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	BuySellCommon.charge_entry_toll_if_first_visit(p["party_id"], s, false, 0, rng)
	# Second call within same visit should be 0.
	var second: int = BuySellCommon.charge_entry_toll_if_first_visit(
		p["party_id"], s, true, 5, rng)
	check(second == 0, "subsequent toll call returns 0 (got %d)" % second)


func test_charge_entry_toll_no_settlement_returns_zero() -> void:
	# settlement_id empty or settlement market_class = 0 should be a no-op.
	var rng := RandomNumberGenerator.new()
	check(BuySellCommon.charge_entry_toll_if_first_visit("", "anything", false, 0, rng) == 0,
		"empty party_id → 0 toll")
	check(BuySellCommon.charge_entry_toll_if_first_visit("party", "", false, 0, rng) == 0,
		"empty settlement_id → 0 toll")


# ---------------------------------------------------------------------------
# Receipt builders
# ---------------------------------------------------------------------------

func test_build_buy_receipt_totals() -> void:
	# Inputs are cp: total_purchase_cp = 800,000, toll_cp = 400, labor_cp = 100.
	var receipt: Dictionary = BuySellCommon.build_buy_receipt(
		"silk", 5, 1600, 800000, 400, 100, 0)
	check(str(receipt.get("kind", "")) == "buy", "kind = buy")
	check(int(receipt.get("loads_count", -1)) == 5, "loads_count = 5")
	check(int(receipt.get("grand_total_cp", 0)) == 800500,
		"grand_total_cp = 800,000 + 400 + 100 = 800,500, got %d" % int(receipt.get("grand_total_cp", 0)))


func test_build_sell_receipt_totals() -> void:
	# Inputs are cp: gross=1,300,000, toll=1000, labor=100, customs=52,000.
	var receipt: Dictionary = BuySellCommon.build_sell_receipt(
		"silk", 5, 2600, 1300000, 1000, 100, 52000, 0, false)
	check(str(receipt.get("kind", "")) == "sell", "kind = sell")
	check(int(receipt.get("net_proceeds_cp", 0)) == 1246900,
		"net_proceeds_cp = 1,300,000 - 1000 - 100 - 52,000 = 1,246,900, got %d" % int(receipt.get("net_proceeds_cp", 0)))
	check(not bool(receipt.get("domain_owner_exempt", true)),
		"domain_owner_exempt = false")
