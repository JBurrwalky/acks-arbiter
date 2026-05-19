extends "res://tests/test_suite_base.gd"

## Unit tests for ShipRepository — ship CRUD, state changes (location +
## damage + destruction), and monthly operating-cost driver per Prereq.5a.
##
## Per generation/gdd-settlement-economy.md §9.12.

var _campaign_id: String = ""
var _map_id: String = ""
var _settlement_id: String = ""
var _party_id: String = ""
var _suffix: int = 0


func run_all_tests() -> void:
	_setup()
	test_create_ship_from_catalog()
	test_create_ship_unknown_vessel_fails()
	test_create_ship_emits_signal()
	test_list_ships_for_party_excludes_destroyed()
	test_set_ship_location_transitions()
	test_set_ship_location_invalid_kind_rejected()
	test_damage_ship_partial()
	test_damage_ship_destruction_at_zero()
	test_destroy_ship_explicit()
	test_destroy_ship_idempotent()
	test_monthly_cost_debits_correctly()
	test_monthly_cost_unpaid_emits_signal()
	test_monthly_cost_skips_destroyed_ships()
	test_monthly_cost_returns_total_debited()

	if not has_failures():
		print("ShipRepository: all %d tests passed." % test_count())


func _setup() -> void:
	_campaign_id = CampaignRepository.create_campaign("ShipRepositoryTests", "World")
	_map_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO hex_maps (id, campaign_id, name, scale) VALUES (?, ?, ?, 'regional_6mi')",
		[_map_id, _campaign_id, "ShipMap"]
	)
	# Settlement to moor ships at.
	_settlement_id = "%s_dock" % _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_entrances
			(id, campaign_id, map_id, hex_q, hex_r, name, market_class)
		VALUES (?, ?, ?, 0, 0, 'TestDock', 3)
	""", [_settlement_id, _campaign_id, _map_id])
	# Party for ship ownership.
	_party_id = "%s_party" % _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO parties (id, campaign_id, name) VALUES (?, ?, 'TestParty')
	""", [_party_id, _campaign_id])


func _next_id() -> String:
	_suffix += 1
	return "shr_%d_%d" % [Time.get_ticks_msec(), _suffix]


func _new_party() -> String:
	var pid: String = "%s_party" % _next_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO parties (id, campaign_id, name) VALUES (?, ?, 'P')", [pid, _campaign_id])
	return pid


# ---------------------------------------------------------------------------
# Create
# ---------------------------------------------------------------------------

func test_create_ship_from_catalog() -> void:
	var sid: String = ShipRepository.create_ship(_party_id, "sailing_ship_small", _settlement_id)
	check(not sid.is_empty(), "create_ship should return non-empty id")
	var ship: Dictionary = ShipRepository.get_ship(sid)
	check(not ship.is_empty(), "get_ship should return the row")
	check(str(ship.get("vessel_key", "")) == "sailing_ship_small", "vessel_key persisted")
	check(int(ship.get("shp_max", 0)) == 30, "shp_max from catalog = 30")
	check(int(ship.get("shp_current", 0)) == 30, "shp_current initialized to shp_max")
	check(int(ship.get("cargo_capacity_stone", 0)) == 10000, "cargo capacity = 10000")
	check(int(ship.get("crew_captain", 0)) == 1, "crew_captain = 1")
	check(int(ship.get("crew_sailors", 0)) == 12, "crew_sailors = 12 from catalog")
	check(int(ship.get("monthly_operating_cost_cp", 0)) == 32_500, "monthly cost = 32,500 cp (= 325 gp)")
	check(str(ship.get("current_location_kind", "")) == "moored", "starts moored")
	check(str(ship.get("moored_at_settlement_id", "")) == _settlement_id, "moored at correct settlement")
	check(int(ship.get("is_destroyed", -1)) == 0, "not destroyed")


func test_create_ship_unknown_vessel_fails() -> void:
	var sid: String = ShipRepository.create_ship(_party_id, "moon_yacht", _settlement_id)
	check(sid.is_empty(), "unknown vessel_key should return empty id")


func test_create_ship_emits_signal() -> void:
	var got_signal := {"emitted": false, "ship_id": "", "party_id": "", "vessel_key": ""}
	var cb: Callable = func(sid: String, pid: String, vk: String) -> void:
		got_signal["emitted"] = true
		got_signal["ship_id"] = sid
		got_signal["party_id"] = pid
		got_signal["vessel_key"] = vk
	EventBus.ship_created.connect(cb)
	var sid: String = ShipRepository.create_ship(_party_id, "sailing_ship_large", _settlement_id)
	EventBus.ship_created.disconnect(cb)
	check(bool(got_signal["emitted"]), "ship_created signal fires")
	check(str(got_signal["ship_id"]) == sid, "signal payload ship_id matches")
	check(str(got_signal["party_id"]) == _party_id, "signal payload party_id matches")
	check(str(got_signal["vessel_key"]) == "sailing_ship_large", "signal payload vessel_key matches")


# ---------------------------------------------------------------------------
# List
# ---------------------------------------------------------------------------

func test_list_ships_for_party_excludes_destroyed() -> void:
	var pid: String = _new_party()
	var s1: String = ShipRepository.create_ship(pid, "sailing_ship_small", _settlement_id)
	var s2: String = ShipRepository.create_ship(pid, "sailing_ship_large", _settlement_id)
	var s3: String = ShipRepository.create_ship(pid, "sailing_ship_small", _settlement_id)
	ShipRepository.destroy_ship(s2)
	var ships: Array = ShipRepository.list_ships_for_party(pid)
	check(ships.size() == 2, "list returns 2 non-destroyed ships, got %d" % ships.size())
	var seen_ids: Dictionary = {}
	for ship in ships:
		seen_ids[str((ship as Dictionary).get("id", ""))] = true
	check(seen_ids.has(s1) and seen_ids.has(s3), "non-destroyed ships present")
	check(not seen_ids.has(s2), "destroyed ship excluded")


# ---------------------------------------------------------------------------
# Location
# ---------------------------------------------------------------------------

func test_set_ship_location_transitions() -> void:
	var sid: String = ShipRepository.create_ship(_party_id, "sailing_ship_small", _settlement_id)
	# moored → at_sea
	check(ShipRepository.set_ship_location(sid, "at_sea", ""), "moored → at_sea succeeds")
	var ship: Dictionary = ShipRepository.get_ship(sid)
	check(str(ship.get("current_location_kind", "")) == "at_sea", "kind = at_sea")
	check(ship.get("moored_at_settlement_id", null) == null, "moored_at_settlement_id cleared")
	# at_sea → moored at a new settlement
	var new_dock: String = "%s_dock2" % _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_entrances (id, campaign_id, map_id, hex_q, hex_r, name, market_class)
		VALUES (?, ?, ?, 1, 0, 'OtherDock', 3)
	""", [new_dock, _campaign_id, _map_id])
	check(ShipRepository.set_ship_location(sid, "moored", new_dock), "at_sea → moored at new_dock")
	ship = ShipRepository.get_ship(sid)
	check(str(ship.get("current_location_kind", "")) == "moored", "kind = moored")
	check(str(ship.get("moored_at_settlement_id", "")) == new_dock, "moored at new dock")


func test_set_ship_location_invalid_kind_rejected() -> void:
	var sid: String = ShipRepository.create_ship(_party_id, "sailing_ship_small", _settlement_id)
	check(not ShipRepository.set_ship_location(sid, "in_orbit", ""),
		"invalid location_kind should return false")


# ---------------------------------------------------------------------------
# Damage / destruction
# ---------------------------------------------------------------------------

func test_damage_ship_partial() -> void:
	var sid: String = ShipRepository.create_ship(_party_id, "sailing_ship_large", _settlement_id)
	# Large sailing ship: shp_max = 50.
	check(ShipRepository.damage_ship(sid, 15), "damage_ship(15) succeeds")
	var ship: Dictionary = ShipRepository.get_ship(sid)
	check(int(ship.get("shp_current", 0)) == 35, "shp_current = 50 - 15 = 35")
	check(int(ship.get("is_destroyed", -1)) == 0, "still not destroyed")


func test_damage_ship_destruction_at_zero() -> void:
	var sid: String = ShipRepository.create_ship(_party_id, "sailing_ship_small", _settlement_id)
	# shp_max = 30. Damage 50 → should destroy.
	var got_signal := {"emitted": false}
	var cb: Callable = func(ship_id: String, party_id: String) -> void:
		if ship_id == sid:
			got_signal["emitted"] = true
	EventBus.ship_destroyed.connect(cb)
	check(ShipRepository.damage_ship(sid, 50), "damage_ship(50) on 30-SHP ship returns true")
	EventBus.ship_destroyed.disconnect(cb)
	var ship: Dictionary = ShipRepository.get_ship(sid)
	check(int(ship.get("shp_current", -1)) == 0, "shp_current clamped to 0")
	check(int(ship.get("is_destroyed", 0)) == 1, "is_destroyed = 1")
	check(str(ship.get("current_location_kind", "")) == "wrecked", "location flipped to wrecked")
	check(bool(got_signal["emitted"]), "ship_destroyed signal fired")


func test_destroy_ship_explicit() -> void:
	var sid: String = ShipRepository.create_ship(_party_id, "sailing_ship_small", _settlement_id)
	var got_signal := {"emitted": false}
	var cb: Callable = func(ship_id: String, party_id: String) -> void:
		if ship_id == sid:
			got_signal["emitted"] = true
	EventBus.ship_destroyed.connect(cb)
	check(ShipRepository.destroy_ship(sid), "destroy_ship returns true")
	EventBus.ship_destroyed.disconnect(cb)
	var ship: Dictionary = ShipRepository.get_ship(sid)
	check(int(ship.get("is_destroyed", 0)) == 1, "is_destroyed = 1")
	check(str(ship.get("current_location_kind", "")) == "wrecked", "location = wrecked")
	check(bool(got_signal["emitted"]), "ship_destroyed signal fired")


func test_destroy_ship_idempotent() -> void:
	var sid: String = ShipRepository.create_ship(_party_id, "sailing_ship_small", _settlement_id)
	check(ShipRepository.destroy_ship(sid), "first destroy succeeds")
	check(not ShipRepository.destroy_ship(sid), "second destroy returns false (already destroyed)")


# ---------------------------------------------------------------------------
# Monthly operating cost
# ---------------------------------------------------------------------------

func test_monthly_cost_debits_correctly() -> void:
	# Seed a party with a PC who has enough gold, run the sweep, verify
	# coin deduction.
	var pid: String = _new_party()
	var pc_id: String = "%s_pc" % _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type)
		VALUES (?, ?, 'CapitanPC', 'pc')
	""", [pc_id, _campaign_id])
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO party_members (party_id, character_id) VALUES (?, ?)
	""", [pid, pc_id])
	# Add 1000 gp = 100,000 cp to the PC via inventory_items.
	CampaignRepository.add_coins_cp(pc_id, 100_000)
	# Create a small sailing ship (325 gp/mo = 32,500 cp/mo).
	ShipRepository.create_ship(pid, "sailing_ship_small", _settlement_id)
	# Sweep.
	var total: int = ShipRepository.process_monthly_operating_costs_for_campaign(_campaign_id, 100)
	check(total >= 32_500, "sweep should debit at least 32,500 cp for the new ship, got %d" % total)
	# PC's wealth should have dropped by 32,500 cp.
	var remaining_cp: int = CampaignRepository.get_character_wealth_cp(pc_id)
	check(remaining_cp == 100_000 - 32_500,
		"PC wealth should drop by 32,500 cp, got remaining %d (expected %d)" % [remaining_cp, 100_000 - 32_500])


func test_monthly_cost_unpaid_emits_signal() -> void:
	# Party with no gold — sweep should emit unpaid signal.
	var pid: String = _new_party()
	var pc_id: String = "%s_brokepc" % _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type)
		VALUES (?, ?, 'BrokePC', 'pc')
	""", [pc_id, _campaign_id])
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO party_members (party_id, character_id) VALUES (?, ?)
	""", [pid, pc_id])
	var sid: String = ShipRepository.create_ship(pid, "sailing_ship_small", _settlement_id)
	var unpaid_events: Array = []
	var cb: Callable = func(ship_id: String, owed_gp: int) -> void:
		if ship_id == sid:
			unpaid_events.append({"ship_id": ship_id, "owed_gp": owed_gp})
	EventBus.ship_operating_cost_unpaid.connect(cb)
	ShipRepository.process_monthly_operating_costs_for_campaign(_campaign_id, 100)
	EventBus.ship_operating_cost_unpaid.disconnect(cb)
	check(unpaid_events.size() == 1,
		"unpaid signal should fire once for broke-party ship, got %d events" % unpaid_events.size())
	if unpaid_events.size() >= 1:
		check(int(unpaid_events[0]["owed_gp"]) == 32_500, "unpaid owed cost = 32,500 cp (= 325 gp)")
	# Ship should NOT be destroyed per §9.6.1 v1 policy.
	var ship: Dictionary = ShipRepository.get_ship(sid)
	check(int(ship.get("is_destroyed", -1)) == 0, "ship not destroyed for non-payment")


func test_monthly_cost_skips_destroyed_ships() -> void:
	# Create + destroy two ships; sweep should not emit any signals for them.
	var pid: String = _new_party()
	var pc_id: String = "%s_destpc" % _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type)
		VALUES (?, ?, 'DestPC', 'pc')
	""", [pc_id, _campaign_id])
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO party_members (party_id, character_id) VALUES (?, ?)
	""", [pid, pc_id])
	CampaignRepository.add_coins_cp(pc_id, 1000000)  # 10000 gp — plenty
	var s1: String = ShipRepository.create_ship(pid, "sailing_ship_small", _settlement_id)
	ShipRepository.destroy_ship(s1)
	var paid_events: Array = []
	var cb_paid: Callable = func(ship_id: String, cp_amount: int) -> void:
		if ship_id == s1:
			paid_events.append(ship_id)
	EventBus.ship_operating_cost_paid.connect(cb_paid)
	ShipRepository.process_monthly_operating_costs_for_campaign(_campaign_id, 100)
	EventBus.ship_operating_cost_paid.disconnect(cb_paid)
	check(paid_events.size() == 0, "destroyed ship should NOT receive any paid signal")


func test_monthly_cost_returns_total_debited() -> void:
	# Two ships: small (325) + large (525) = 850 total when both can be paid.
	var pid: String = _new_party()
	var pc_id: String = "%s_totalspc" % _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type)
		VALUES (?, ?, 'TotalsPC', 'pc')
	""", [pc_id, _campaign_id])
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO party_members (party_id, character_id) VALUES (?, ?)
	""", [pid, pc_id])
	CampaignRepository.add_coins_cp(pc_id, 200_000)  # 2,000 gp
	ShipRepository.create_ship(pid, "sailing_ship_small", _settlement_id)
	ShipRepository.create_ship(pid, "sailing_ship_large", _settlement_id)
	var total: int = ShipRepository.process_monthly_operating_costs_for_campaign(_campaign_id, 100)
	# 325 gp + 525 gp = 850 gp = 85,000 cp.
	check(total == 32_500 + 52_500,
		"sweep should debit 85,000 cp (= 850 gp) when both ships paid, got %d" % total)
