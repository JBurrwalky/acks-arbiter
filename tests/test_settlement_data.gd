extends "res://tests/test_suite_base.gd"

## Unit tests for the slim SettlementMapData (V2 — districts + PoIs only).
## See gdd-settlement-layout.md v2 §8 and gdd-settlement-exploration-ui.md v2.


func run_all_tests() -> void:
	test_from_dict_basic_fields()
	test_district_and_poi_lookups()
	test_get_pois_in_district()
	test_get_entry_exit_pois()
	test_same_district_true_and_false()
	test_same_district_with_unknown_id()
	test_empty_settlement_does_not_crash()
	if not has_failures():
		print("SettlementData: all tests passed.")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _make_settlement_dict() -> Dictionary:
	return {
		"id": "test_city",
		"name": "Test City",
		"market_class": 4,
		"population_families": 800,
		"terrain_context": "crossroads",
		"culture_id": "auran",
		"generation_seed": 7,
		"districts": [
			{
				"id": "market",
				"name": "Market District",
				"type": "market",
				"encounter_modifier": "default",
				"pois": [
					{"id": "main_gate", "name": "Main Gate", "type": "gate",
						"is_entry_exit": true, "importance": "major"},
					{"id": "town_square", "name": "Town Square", "type": "market",
						"is_entry_exit": false, "importance": "major"},
				],
			},
			{
				"id": "temple_district",
				"name": "Temple District",
				"type": "temple_district",
				"encounter_modifier": "default",
				"pois": [
					{"id": "high_temple", "name": "High Temple", "type": "temple",
						"is_entry_exit": false, "importance": "major"},
					{"id": "side_gate", "name": "Side Gate", "type": "gate",
						"is_entry_exit": true, "importance": "minor"},
				],
			},
		],
		"undercity_pois": [],
		"transitions": [],
	}


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_from_dict_basic_fields() -> void:
	var s := SettlementMapData.from_dict(_make_settlement_dict())
	check(s.id == "test_city", "id roundtrip")
	check(s.name == "Test City", "name roundtrip")
	check(s.market_class == 4, "market_class roundtrip")
	check(s.population_families == 800, "population_families roundtrip")
	check(s.terrain_context == "crossroads", "terrain_context roundtrip")
	check(s.culture_id == "auran", "culture_id roundtrip")
	check(s.districts.size() == 2, "two districts parsed, got %d" % s.districts.size())
	check(s.pois.size() == 4, "four PoIs flattened, got %d" % s.pois.size())
	print("  from_dict_basic_fields: OK")


func test_district_and_poi_lookups() -> void:
	var s := SettlementMapData.from_dict(_make_settlement_dict())
	var market := s.get_district("market")
	check(market.get("name", "") == "Market District",
		"get_district('market') returns Market District, got %s" % market.get("name", ""))

	var unknown := s.get_district("nonexistent")
	check(unknown.is_empty(),
		"get_district('nonexistent') returns empty dict")

	var temple := s.get_poi("high_temple")
	check(temple.get("type", "") == "temple",
		"get_poi('high_temple') returns temple PoI")
	check(temple.get("district_id", "") == "temple_district",
		"PoI district_id is denormalized onto the PoI dict")

	check(s.get_poi("nonexistent").is_empty(),
		"get_poi for unknown id returns empty dict")
	print("  district_and_poi_lookups: OK")


func test_get_pois_in_district() -> void:
	var s := SettlementMapData.from_dict(_make_settlement_dict())
	var market_pois: Array = s.get_pois_in_district("market")
	check(market_pois.size() == 2, "market district has 2 PoIs, got %d" % market_pois.size())
	check(s.get_pois_in_district("nonexistent").is_empty(),
		"unknown district returns empty PoI list")
	print("  get_pois_in_district: OK")


func test_get_entry_exit_pois() -> void:
	var s := SettlementMapData.from_dict(_make_settlement_dict())
	var entries: Array = s.get_entry_exit_pois()
	check(entries.size() == 2,
		"two entry/exit PoIs across all districts, got %d" % entries.size())
	# Verify both gates are returned regardless of district
	var ids: Array = []
	for e in entries:
		ids.append(e.get("id", ""))
	check("main_gate" in ids and "side_gate" in ids,
		"both gate ids present, got %s" % str(ids))
	print("  get_entry_exit_pois: OK")


func test_same_district_true_and_false() -> void:
	var s := SettlementMapData.from_dict(_make_settlement_dict())
	check(s.same_district("main_gate", "town_square"),
		"main_gate and town_square are both in 'market'")
	check(not s.same_district("main_gate", "high_temple"),
		"main_gate (market) and high_temple (temple_district) differ")
	print("  same_district_true_and_false: OK")


func test_same_district_with_unknown_id() -> void:
	var s := SettlementMapData.from_dict(_make_settlement_dict())
	check(not s.same_district("main_gate", "nonexistent"),
		"unknown PoI id returns false")
	check(not s.same_district("nonexistent", "town_square"),
		"unknown PoI id returns false (other side)")
	print("  same_district_with_unknown_id: OK")


func test_empty_settlement_does_not_crash() -> void:
	var s := SettlementMapData.from_dict({})
	check(s.id == "", "empty dict yields empty id")
	check(s.districts.is_empty(), "empty dict yields no districts")
	check(s.pois.is_empty(), "empty dict yields no PoIs")
	check(s.get_entry_exit_pois().is_empty(), "no entry/exit PoIs on empty")
	print("  empty_settlement_does_not_crash: OK")
