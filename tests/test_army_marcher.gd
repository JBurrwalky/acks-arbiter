extends "res://tests/test_suite_base.gd"

## Tests for ArmyMarcher (Phase 6A part 2 closing).
##
## Covers compute_army_daily_miles math, lookup_unit_daily_miles type
## resolution, march_army scheduling + leg_days computation,
## marching-extraction credit on leg arrival.

var _campaign_id: String = ""
var _ruler_id: String = ""
var _map_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_lookup_unit_daily_miles_heavy_infantry()
	test_lookup_unit_daily_miles_light_cavalry()
	test_lookup_unit_daily_miles_unknown_falls_back()
	test_compute_daily_miles_uses_slowest_unit()
	test_march_army_rejects_when_battling()
	test_march_army_schedules_event_with_correct_eta()
	test_march_army_forced_doubles_speed_via_multiplier()
	test_marching_extraction_credits_supply_on_arrival()
	if not has_failures():
		print("ArmyMarcher: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("Marcher Test", "World")
	_ruler_id = _make_character("Lord Marcher")
	_map_id = CampaignRepository.generate_id()


func _make_character(name: String) -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, ?, 'pc', 'full', 'human', 'fighter', 9,
			14, 12, 12, 12, 12, 12, 60, 60)
	""", [id, _campaign_id, name])
	return id


func _make_army_with_units(troop_types: Array, hex_q: int = 5, hex_r: int = 5) -> String:
	var army_id: String = ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": "TestArmy",
		"political_owner_id": _ruler_id, "command_character_id": _ruler_id,
		"state": "encamped", "map_id": _map_id, "hex_q": hex_q, "hex_r": hex_r,
	})
	ArmyRepository.create_supply_state({"army_id": army_id})
	var leader: String = ArmyRepository.create_officer({
		"army_id": army_id, "character_id": _ruler_id, "rank": "army_leader",
		"appointed_calendar_day": 100,
	})
	for troop_type in troop_types:
		var unit_id: String = TroopUnitRepository.create_unit({
			"campaign_id": _campaign_id, "owner_character_id": _ruler_id,
			"source_type": "mercenary", "troop_type": String(troop_type),
			"count": 60, "starting_count": 60, "battle_rating": 1.0,
		})
		ArmyRepository.create_assignment({
			"army_id": army_id, "troop_unit_id": unit_id,
			"parent_officer_id": leader, "role": "line",
			"assigned_calendar_day": 100,
		})
	return army_id


func test_lookup_unit_daily_miles_heavy_infantry() -> void:
	var marcher := ArmyMarcher.new()
	check(marcher.lookup_unit_daily_miles("Heavy Infantry") == 12, "Heavy Infantry → 12")
	check(marcher.lookup_unit_daily_miles("heavy_infantry") == 12, "heavy_infantry → 12")


func test_lookup_unit_daily_miles_light_cavalry() -> void:
	var marcher := ArmyMarcher.new()
	check(marcher.lookup_unit_daily_miles("Light Cavalry") == 48, "Light Cavalry → 48")


func test_lookup_unit_daily_miles_unknown_falls_back() -> void:
	var marcher := ArmyMarcher.new()
	check(marcher.lookup_unit_daily_miles("Mystery Type") == ArmyMarcher.DEFAULT_DAILY_MILES,
		"unknown → default %d" % ArmyMarcher.DEFAULT_DAILY_MILES)


func test_compute_daily_miles_uses_slowest_unit() -> void:
	# Mix Heavy Infantry (12) + Light Cavalry (48) → slowest is 12.
	var army_id := _make_army_with_units(["Heavy Infantry", "Light Cavalry"])
	var marcher := ArmyMarcher.new()
	# Default terrain (clear, not in hex_cells) → multiplier 1.0; <12000 troops → column 1.0.
	# Result = 12 × 1.0 × 1.0 × 1.0 = 12
	var miles := marcher.compute_army_daily_miles(army_id, "normal")
	check(miles == 12, "slowest = 12, got %d" % miles)


func test_march_army_rejects_when_battling() -> void:
	var army_id := _make_army_with_units(["Heavy Infantry", "Heavy Infantry"])
	ArmyRepository.update_army(army_id, {"state": "battling"})
	var scheduler := EventScheduler.new()
	var marcher := ArmyMarcher.new()
	var result := marcher.march_army(army_id, 6, 5, 0, scheduler)
	check(not bool(result.get("success", true)), "rejects battling army")
	check(String(result.get("error", "")) == "army_must_be_encamped_or_assembling", "error cited")


func test_march_army_schedules_event_with_correct_eta() -> void:
	var army_id := _make_army_with_units(["Heavy Infantry", "Heavy Infantry"])
	var scheduler := EventScheduler.new()
	var marcher := ArmyMarcher.new()
	var result := marcher.march_army(army_id, 6, 5, 0, scheduler, "normal")
	check(bool(result.get("success", false)), "march scheduled")
	# 6 miles / 12 daily_miles = 0.5 days → ceil = 1 day → 1 × ROUNDS_PER_DAY rounds.
	check(int(result.get("leg_days", 0)) == 1, "leg_days = 1")
	check(int(result.get("eta_round", 0)) == Timekeeping.ROUNDS_PER_DAY, "eta = 1 day in rounds")
	# Army state transitioned to marching.
	var army := ArmyRepository.get_army(army_id)
	check(String(army.get("state", "")) == "marching", "state=marching")


func test_march_army_forced_doubles_speed_via_multiplier() -> void:
	var army_id := _make_army_with_units(["Heavy Infantry", "Heavy Infantry"])
	var marcher := ArmyMarcher.new()
	var normal_miles := marcher.compute_army_daily_miles(army_id, "normal")
	var forced_miles := marcher.compute_army_daily_miles(army_id, "forced")
	# Forced march = 1.5× normal speed.
	check(forced_miles == int(round(float(normal_miles) * 1.5)),
		"forced = 1.5× normal; %d × 1.5 = %d, got %d" % [normal_miles, normal_miles * 1.5, forced_miles])


func test_marching_extraction_credits_supply_on_arrival() -> void:
	var army_id := _make_army_with_units(["Heavy Infantry", "Heavy Infantry"])
	# Phase B: marching extraction is domain-driven (RAW 40 gp/family). Seed a FRIENDLY
	# domain (same owner as the army) at the destination hex so requisition yields.
	var domain_id := CampaignRepository.create_domain({
		"campaign_id": _campaign_id, "name": "Marcher Domain",
		"owner_character_id": _ruler_id, "location_map_id": _map_id,
		"location_hex_q": 7, "location_hex_r": 5, "territory_type": "civilized",
	})
	CampaignRepository.update_domain_monthly_state(domain_id, {"peasant_families": 50})
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO domain_hexes (id, domain_id, map_id, hex_q, hex_r, land_value, families)
		VALUES (?, ?, ?, 7, 5, 5, 0)
	""", [CampaignRepository.generate_id(), domain_id, _map_id])
	var initial_stockpile := int(ArmyRepository.get_supply_state(army_id).get("current_stockpile_cp", 0))

	# Build a fake travel_leg event payload and call _handle_army_travel_leg directly.
	var marcher := ArmyMarcher.new()
	var event := ScheduledEvent.create(0, "army_travel_leg", army_id, {
		"army_id": army_id,
		"to_hex_q": 7, "to_hex_r": 5,
		"map_id": _map_id,
		"extraction_mode": "requisition",
	}, ScheduledEvent.PRIORITY_ARRIVAL)
	var result := marcher._handle_army_travel_leg(event)
	check(not result.is_empty(), "event handler returned result")
	var final_supply := ArmyRepository.get_supply_state(army_id)
	check(int(final_supply.get("current_stockpile_cp", 0)) > initial_stockpile,
		"stockpile increased after marching requisition of a friendly domain; before=%d after=%d" % [
			initial_stockpile, final_supply.get("current_stockpile_cp", 0)
		])
	# Army state transitioned to encamped at destination.
	var army := ArmyRepository.get_army(army_id)
	check(String(army.get("state", "")) == "encamped", "state=encamped after arrival")
	check(int(army.get("hex_q", 0)) == 7, "hex_q updated to destination")
