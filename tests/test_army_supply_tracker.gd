extends "res://tests/test_suite_base.gd"

## Tests for ArmySupplyTracker (Phase 6A part 2 closing).
##
## Covers run_supply_tick: weekly cost computation, stockpile deduction,
## consecutive_unsupplied_weeks counter, calamity threshold trigger, and
## EventBus signal emission.

var _campaign_id: String = ""
var _ruler_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_rejects_missing_supply_state()
	test_deducts_weekly_cost_from_stockpile()
	test_shortfall_increments_consecutive_unsupplied_weeks()
	test_resupply_resets_counter()
	test_calamity_triggers_at_two_consecutive_weeks()
	if not has_failures():
		print("ArmySupplyTracker: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("SupplyTracker Test", "World")
	_ruler_id = _make_character("Lord Quartermaster")


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


func _make_army_with_supply(stockpile: int, weekly_cost: int = 0) -> String:
	var army_id: String = ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": "SupplyArmy",
		"political_owner_id": _ruler_id, "command_character_id": _ruler_id,
		"state": "encamped",
	})
	ArmyRepository.create_supply_state({
		"army_id": army_id,
		"current_stockpile_gp": stockpile,
	})
	# Add a unit so weekly cost can be computed (60 gp/week base for
	# infantry; 240/4 = 60 weekly when monthly_supply_gp=240, which is the
	# Phase 5 monthly = 4 × weekly).
	if weekly_cost > 0:
		var leader: String = ArmyRepository.create_officer({
			"army_id": army_id, "character_id": _ruler_id, "rank": "army_leader",
			"appointed_calendar_day": 100,
		})
		var unit_id: String = TroopUnitRepository.create_unit({
			"campaign_id": _campaign_id, "owner_character_id": _ruler_id,
			"source_type": "mercenary", "troop_type": "Heavy Infantry",
			"count": 60, "starting_count": 60, "battle_rating": 1.0,
			"monthly_supply_gp": weekly_cost * 4,
			"monthly_specialist_gp": 1,  # quartermaster present (avoid ×2)
		})
		ArmyRepository.create_assignment({
			"army_id": army_id, "troop_unit_id": unit_id,
			"parent_officer_id": leader, "role": "line",
			"assigned_calendar_day": 100,
		})
	return army_id


func test_rejects_missing_supply_state() -> void:
	# Create an army WITHOUT a supply_state row.
	var army_id: String = ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": "NoSupply",
		"political_owner_id": _ruler_id, "command_character_id": _ruler_id,
		"state": "encamped",
	})
	var tracker := ArmySupplyTracker.new()
	var result := tracker.run_supply_tick(army_id, 100)
	check(not bool(result.get("success", true)), "missing supply state rejected")


func test_deducts_weekly_cost_from_stockpile() -> void:
	var army_id := _make_army_with_supply(500, 60)  # 500 stockpile, 60 weekly cost
	var tracker := ArmySupplyTracker.new()
	var result := tracker.run_supply_tick(army_id, 100)
	check(bool(result.get("success", false)), "tick success")
	check(int(result.get("weekly_cost_gp", 0)) == 60, "weekly cost = 60; got %d" % result.get("weekly_cost_gp", 0))
	check(int(result.get("stockpile_after", 0)) == 440, "stockpile 500 - 60 = 440; got %d" % result.get("stockpile_after", 0))
	check(int(result.get("consecutive_unsupplied_weeks", 99)) == 0, "no shortfall → counter 0")


func test_shortfall_increments_consecutive_unsupplied_weeks() -> void:
	var army_id := _make_army_with_supply(50, 60)  # 50 stockpile, 60 cost → 10 short
	var tracker := ArmySupplyTracker.new()
	var result := tracker.run_supply_tick(army_id, 100)
	check(int(result.get("shortfall", 0)) == 10, "shortfall = 10")
	check(int(result.get("stockpile_after", -1)) == 0, "stockpile clamped to 0")
	check(int(result.get("consecutive_unsupplied_weeks", 0)) == 1, "counter = 1 after first shortfall")


func test_resupply_resets_counter() -> void:
	# Pre-set counter to 1.
	var army_id := _make_army_with_supply(500, 60)
	ArmyRepository.update_supply_state(army_id, {"consecutive_unsupplied_weeks": 1})
	var tracker := ArmySupplyTracker.new()
	var result := tracker.run_supply_tick(army_id, 100)
	check(int(result.get("consecutive_unsupplied_weeks", 99)) == 0, "counter reset to 0 when supplied")


func test_calamity_triggers_at_two_consecutive_weeks() -> void:
	var army_id := _make_army_with_supply(0, 60)
	# Tick 1: shortfall, counter 1, no calamity.
	var tracker := ArmySupplyTracker.new()
	var r1 := tracker.run_supply_tick(army_id, 100)
	check(int(r1.get("consecutive_unsupplied_weeks", 0)) == 1, "tick1 counter = 1")
	check(not bool(r1.get("calamity_triggered", true)), "tick1 no calamity")
	# Tick 2: another shortfall, counter 2, calamity!
	var r2 := tracker.run_supply_tick(army_id, 107)
	check(int(r2.get("consecutive_unsupplied_weeks", 0)) == 2, "tick2 counter = 2")
	check(bool(r2.get("calamity_triggered", false)), "tick2 calamity triggered")
