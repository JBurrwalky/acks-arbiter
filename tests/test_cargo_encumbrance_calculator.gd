extends "res://tests/test_suite_base.gd"

## Unit tests for CargoEncumbranceCalculator — integrating inventory_items
## + cargo_holds into a single per-carrier capacity limit per Q-MERC-17.
##
## Per generation/gdd-settlement-economy.md §9.12 (calculator section).

var _campaign_id: String = ""
var _map_id: String = ""
var _settlement_id: String = ""
var _party_id: String = ""
var _suffix: int = 0


func run_all_tests() -> void:
	_setup()
	test_empty_cart_used_zero()
	test_cart_inventory_only()
	test_cart_cargo_only()
	test_cart_inventory_and_cargo_combined()
	test_capacity_check_is_over_normal_max_and_speed()
	test_ship_capacity_check()
	test_inventory_stone_banker_rounded()
	test_ship_used_stone_ignores_draft_vehicle_cargo()

	if not has_failures():
		print("CargoEncumbranceCalculator: all %d tests passed." % test_count())


func _setup() -> void:
	_campaign_id = CampaignRepository.create_campaign("CargoEncumbranceCalculatorTests", "World")
	_map_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO hex_maps (id, campaign_id, name, scale) VALUES (?, ?, ?, 'regional_6mi')",
		[_map_id, _campaign_id, "CECMap"]
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
	return "cec_%d_%d" % [Time.get_ticks_msec(), _suffix]


## Creates a cart_small with one horse_heavy hitched (team_equiv = 1.0 →
## load_normal=80, load_max=160 per acore_equipment.xml).
func _make_cart_small() -> String:
	var vid: String = "%s_cart" % _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO draft_vehicles (id, campaign_id, party_id, item_key, name, hitched_creatures)
		VALUES (?, ?, ?, 'cart_small', 'TestCart',
			'[{"species_id":"horse_heavy"}]')
	""", [vid, _campaign_id, _party_id])
	return vid


## Creates a wagon with two horse_heavy hitched (team_equiv = 2.0 →
## load_normal=160, load_max=320).
func _make_wagon_two_horses() -> String:
	var vid: String = "%s_wagon" % _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO draft_vehicles (id, campaign_id, party_id, item_key, name, hitched_creatures)
		VALUES (?, ?, ?, 'wagon', 'TestWagon',
			'[{"species_id":"horse_heavy"},{"species_id":"horse_heavy"}]')
	""", [vid, _campaign_id, _party_id])
	return vid


func _make_ship() -> String:
	return ShipRepository.create_ship(_party_id, "sailing_ship_small", _settlement_id)


func _seed_inventory_item(vehicle_id: String, encumbrance_units: int, quantity: int = 1) -> String:
	# A character is required by inventory_items.character_id FK; create a dummy one.
	var char_id: String = "%s_inv_char" % _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type)
		VALUES (?, ?, 'InvDummy', 'pc')
	""", [char_id, _campaign_id])
	var item_id: String = "%s_item" % _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO inventory_items
			(id, character_id, item_key, name, quantity, encumbrance_units, vehicle_id)
		VALUES (?, ?, 'test_item', 'TestItem', ?, ?, ?)
	""", [item_id, char_id, quantity, encumbrance_units, vehicle_id])
	return item_id


# ---------------------------------------------------------------------------
# Draft vehicles
# ---------------------------------------------------------------------------

func test_empty_cart_used_zero() -> void:
	var cart: String = _make_cart_small()
	check(CargoEncumbranceCalculator.draft_vehicle_used_stone(cart) == 0,
		"empty cart used_stone = 0")
	var check_dict: Dictionary = CargoEncumbranceCalculator.draft_vehicle_capacity_check(cart)
	check(int(check_dict.get("used_stone", -1)) == 0, "capacity_check used_stone = 0")
	check(int(check_dict.get("load_normal_stone", 0)) == 80, "load_normal = 80 stone")
	check(int(check_dict.get("load_max_stone", 0)) == 160, "load_max = 160 stone")
	check(not bool(check_dict.get("is_over_normal", true)), "not over normal")
	check(not bool(check_dict.get("is_over_max", true)), "not over max")
	check(int(check_dict.get("speed", 0)) == 60, "normal speed = 60 ft/turn")
	check(int(check_dict.get("free_stone", 0)) == 160, "free = 160")


func test_cart_inventory_only() -> void:
	var cart: String = _make_cart_small()
	# 30000 encumbrance_units = 30 stone (clean integer; no banker rounding involved).
	_seed_inventory_item(cart, 30000, 1)
	check(CargoEncumbranceCalculator.draft_vehicle_used_stone(cart) == 30,
		"inventory 30000 eu = 30 stone")


func test_cart_cargo_only() -> void:
	var cart: String = _make_cart_small()
	# silk: 20 stone/load × 3 loads = 60 stone.
	CargoHoldRepository.insert_purchase(
		cart, CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
		"silk", 3, 6000, _settlement_id, 0)
	check(CargoEncumbranceCalculator.draft_vehicle_used_stone(cart) == 60,
		"3 silk loads × 20 stone = 60")


func test_cart_inventory_and_cargo_combined() -> void:
	var cart: String = _make_cart_small()
	# 50000 eu = 50 stone inventory
	_seed_inventory_item(cart, 50000, 1)
	# silk: 2 loads × 20 = 40 stone cargo
	CargoHoldRepository.insert_purchase(
		cart, CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
		"silk", 2, 4000, _settlement_id, 0)
	# Total = 50 + 40 = 90 stone
	check(CargoEncumbranceCalculator.draft_vehicle_used_stone(cart) == 90,
		"50 inventory + 40 cargo = 90 stone, got %d" % CargoEncumbranceCalculator.draft_vehicle_used_stone(cart))


func test_capacity_check_is_over_normal_max_and_speed() -> void:
	var wagon: String = _make_wagon_two_horses()
	# Wagon at team_equiv=2.0: load_normal=160, load_max=320.
	# Load 200 stone of grain (80 stone/load × 3 loads = 240). Wait, 80×3=240, over max=320 is no.
	# Let me use silk loads: 20 stone/load.
	# 9 silk loads = 180 stone. Over normal (160), under max (320). Expect speed = speed_loaded.
	CargoHoldRepository.insert_purchase(
		wagon, CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
		"silk", 9, 18000, _settlement_id, 0)
	var check_dict: Dictionary = CargoEncumbranceCalculator.draft_vehicle_capacity_check(wagon)
	check(int(check_dict.get("used_stone", 0)) == 180, "used = 180 stone")
	check(bool(check_dict.get("is_over_normal", false)), "180 > 160 → over normal")
	check(not bool(check_dict.get("is_over_max", true)), "180 < 320 → not over max")
	check(int(check_dict.get("speed", 0)) == 30, "speed_loaded = 30 when over normal")
	check(int(check_dict.get("free_stone", 0)) == 140, "free = 320 - 180 = 140")
	# Push over max: add 8 more silk = 160 more stone = 340 total > 320 max.
	CargoHoldRepository.insert_purchase(
		wagon, CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
		"silk", 8, 16000, _settlement_id, 0)
	check_dict = CargoEncumbranceCalculator.draft_vehicle_capacity_check(wagon)
	check(int(check_dict.get("used_stone", 0)) == 340, "used = 340 stone after second load")
	check(bool(check_dict.get("is_over_max", false)), "340 > 320 → over max")
	check(int(check_dict.get("free_stone", -1)) == 0, "free clamped to 0 when over max")


# ---------------------------------------------------------------------------
# Ships
# ---------------------------------------------------------------------------

func test_ship_capacity_check() -> void:
	var ship: String = _make_ship()
	# Small sailing ship: cargo_capacity_stone = 10000.
	# Load 6 silk × 20 = 120 stone.
	CargoHoldRepository.insert_purchase(
		ship, CargoHoldRepository.CARRIER_SHIP,
		"silk", 6, 12000, _settlement_id, 0)
	var check_dict: Dictionary = CargoEncumbranceCalculator.ship_capacity_check(ship)
	check(int(check_dict.get("used_stone", -1)) == 120, "ship used = 120 stone")
	check(int(check_dict.get("cargo_capacity_stone", 0)) == 10000, "capacity = 10000")
	check(not bool(check_dict.get("is_over_capacity", true)), "120 < 10000 → not over")
	check(int(check_dict.get("free_stone", 0)) == 9880, "free = 10000 - 120 = 9880")


# ---------------------------------------------------------------------------
# Banker rounding (inventory conversion only)
# ---------------------------------------------------------------------------

func test_inventory_stone_banker_rounded() -> void:
	# 500 encumbrance_units = 0.5 stone → banker rounds to even 0.
	var cart: String = _make_cart_small()
	_seed_inventory_item(cart, 500, 1)
	check(CargoEncumbranceCalculator.draft_vehicle_used_stone(cart) == 0,
		"500 eu = 0.5 stone → banker → 0")
	# 1500 eu = 1.5 stone → banker → 2.
	var cart2: String = _make_cart_small()
	_seed_inventory_item(cart2, 1500, 1)
	check(CargoEncumbranceCalculator.draft_vehicle_used_stone(cart2) == 2,
		"1500 eu = 1.5 stone → banker → 2")
	# 2500 eu = 2.5 → banker → 2 (round to even).
	var cart3: String = _make_cart_small()
	_seed_inventory_item(cart3, 2500, 1)
	check(CargoEncumbranceCalculator.draft_vehicle_used_stone(cart3) == 2,
		"2500 eu = 2.5 stone → banker → 2 (even)")


# ---------------------------------------------------------------------------
# Carrier isolation
# ---------------------------------------------------------------------------

func test_ship_used_stone_ignores_draft_vehicle_cargo() -> void:
	# A cart with cargo + a ship with no cargo. ship_used_stone should be 0.
	var cart: String = _make_cart_small()
	var ship: String = _make_ship()
	CargoHoldRepository.insert_purchase(
		cart, CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
		"silk", 5, 10000, _settlement_id, 0)
	check(CargoEncumbranceCalculator.draft_vehicle_used_stone(cart) == 100,
		"cart used = 100 stone (5×20)")
	check(CargoEncumbranceCalculator.ship_used_stone(ship) == 0,
		"ship used = 0 (no cargo on ship)")
