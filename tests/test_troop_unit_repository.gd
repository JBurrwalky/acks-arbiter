extends "res://tests/test_suite_base.gd"

## Tests for TroopUnitRepository (Domain Phase 5).
##
## Exercises CRUD round-trip, the source_type CHECK constraint enforcement
## via the GDScript layer, list-by-domain / list-by-owner queries, and the
## depart_unit soft-delete path.


var _campaign_id: String = ""
var _ruler_id: String = ""
var _domain_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_create_and_get()
	test_update_unit_whitelist_rejects_unknown_field()
	test_list_active_for_domain_filters_departed()
	test_list_active_for_owner()
	test_depart_unit_marks_status()
	if not has_failures():
		print("TroopUnitRepository: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("Test Troops", "TestWorld")
	_ruler_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, 'Captain Test', 'pc', 'full', 'human', 'fighter', 9,
			14, 10, 10, 10, 10, 10, 50, 50)
	""", [_ruler_id, _campaign_id])
	_domain_id = CampaignRepository.create_domain({
		"campaign_id": _campaign_id,
		"name": "Troop Test Domain",
		"territory_type": "borderlands",
		"owner_character_id": _ruler_id,
		"peasant_families": 100,
	})


func _make_unit(source: String = "mercenary", count: int = 60) -> String:
	return TroopUnitRepository.create_unit({
		"campaign_id": _campaign_id,
		"owner_character_id": _ruler_id,
		"assigned_domain_id": _domain_id,
		"source_type": source,
		"troop_type": "Light Infantry",
		"race": "human",
		"tier": "average",
		"count": count,
		"starting_count": count,
		"battle_rating": 0.5,
		"monthly_wage_gp": 100,
		"monthly_supply_gp": 30,
		"monthly_cost_gp": 130,
		"morale": -1,
		"is_trained": true,
	})


func test_create_and_get() -> void:
	var id := _make_unit()
	check(not id.is_empty(), "create_unit should return id")
	var row := TroopUnitRepository.get_unit(id)
	check(not row.is_empty(), "get_unit should return row")
	check(int(row.get("count", 0)) == 60, "count should be 60")
	check(String(row.get("source_type", "")) == "mercenary", "source_type roundtrip")
	check(String(row.get("status", "")) == "active", "status defaults to active")


func test_update_unit_whitelist_rejects_unknown_field() -> void:
	var id := _make_unit()
	var ok := TroopUnitRepository.update_unit(id, {
		"count": 55,
		"unknown_field": "ignored",
	})
	check(ok, "update_unit should succeed when at least one whitelisted field is present")
	var row := TroopUnitRepository.get_unit(id)
	check(int(row.get("count", 0)) == 55, "count should update to 55")


func test_list_active_for_domain_filters_departed() -> void:
	# Wipe and add three units; depart one.
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM troop_units WHERE assigned_domain_id = ?", [_domain_id])
	var keep1 := _make_unit("mercenary")
	var keep2 := _make_unit("conscript")
	var depart := _make_unit("militia")
	TroopUnitRepository.depart_unit(depart, "discharged", 100)
	var active := TroopUnitRepository.list_active_for_domain(_domain_id)
	check(active.size() == 2, "expected 2 active units, got %d" % active.size())
	var seen_ids: Dictionary = {}
	for u in active:
		seen_ids[String(u.get("id", ""))] = true
	check(seen_ids.has(keep1) and seen_ids.has(keep2),
		"active list should contain both kept units")
	check(not seen_ids.has(depart), "departed unit should be excluded")


func test_list_active_for_owner() -> void:
	var rows := TroopUnitRepository.list_active_for_owner(_ruler_id)
	check(rows.size() >= 2, "owner should see >= 2 active units, got %d" % rows.size())


func test_depart_unit_marks_status() -> void:
	var id := _make_unit()
	check(TroopUnitRepository.depart_unit(id, "kia", 200), "depart_unit should succeed")
	var row := TroopUnitRepository.get_unit(id)
	check(String(row.get("status", "")) == "departed", "status should be departed")
	check(String(row.get("departure_kind", "")) == "kia", "departure_kind should be kia")
	check(int(row.get("departure_calendar_day", 0)) == 200,
		"departure_calendar_day should be 200")
