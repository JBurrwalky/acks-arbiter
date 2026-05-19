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


## 2026-05-16 army wage cp pass: stockpile_cp + weekly_cost_cp; fixture sig
## takes cp magnitudes directly.
func _make_army_with_supply(stockpile_cp: int, weekly_cost_cp: int = 0) -> String:
	var army_id: String = ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": "SupplyArmy",
		"political_owner_id": _ruler_id, "command_character_id": _ruler_id,
		"state": "encamped",
	})
	ArmyRepository.create_supply_state({
		"army_id": army_id,
		"current_stockpile_cp": stockpile_cp,
	})
	# Add a unit so weekly cost can be computed. Phase 5 stores
	# monthly_supply_cp; supply_calculator divides by 4 to get weekly cp
	# (cp-native end-to-end per this pass).
	if weekly_cost_cp > 0:
		var leader: String = ArmyRepository.create_officer({
			"army_id": army_id, "character_id": _ruler_id, "rank": "army_leader",
			"appointed_calendar_day": 100,
		})
		var unit_id: String = TroopUnitRepository.create_unit({
			"campaign_id": _campaign_id, "owner_character_id": _ruler_id,
			"source_type": "mercenary", "troop_type": "Heavy Infantry",
			"count": 60, "starting_count": 60, "battle_rating": 1.0,
			"monthly_supply_cp": weekly_cost_cp * 4,
			"monthly_specialist_cp": 100,  # quartermaster present (avoid ×2; >0 flag)
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
	# 500 cp stockpile, 60 cp weekly cost.
	var army_id := _make_army_with_supply(500, 60)
	var tracker := ArmySupplyTracker.new()
	var result := tracker.run_supply_tick(army_id, 100)
	check(bool(result.get("success", false)), "tick success")
	check(int(result.get("weekly_cost_cp", 0)) == 60, "weekly cost = 60 cp; got %d" % result.get("weekly_cost_cp", 0))
	check(int(result.get("stockpile_after", 0)) == 440, "stockpile 500 - 60 = 440 cp; got %d" % result.get("stockpile_after", 0))
	check(int(result.get("consecutive_unsupplied_weeks", 99)) == 0, "no shortfall → counter 0")


func test_shortfall_increments_consecutive_unsupplied_weeks() -> void:
	# 50 cp stockpile, 60 cp cost → 10 cp short.
	var army_id := _make_army_with_supply(50, 60)
	var tracker := ArmySupplyTracker.new()
	var result := tracker.run_supply_tick(army_id, 100)
	check(int(result.get("shortfall", 0)) == 10, "shortfall = 10 cp")
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
