extends "res://tests/test_suite_base.gd"

## Unit tests for SettlementLayoutGenerator.
##
## Verifies the generated settlement_data JSON satisfies what the Enter
## Settlement flow consumes: at least one district with at least one
## entry/exit POI, plus market-class-scaled service POIs.


func run_all_tests() -> void:
	test_hamlet_produces_baseline_pois()
	test_city_produces_more_pois_than_hamlet()
	test_at_least_one_entry_exit_poi()
	test_seed_is_deterministic()
	test_required_fields_present()
	if not has_failures():
		print("SettlementLayoutGenerator: all tests passed.")


func test_hamlet_produces_baseline_pois() -> void:
	var gen := SettlementLayoutGenerator.new()
	var d: Dictionary = gen.generate({
		"id": "settlement_test_hamlet",
		"name": "Smallville",
		"market_class": 6,
		"seed": 1,
	})
	var districts: Array = d.get("districts", [])
	check(districts.size() == 1, "hamlet should have 1 district")
	var pois: Array = (districts[0] as Dictionary).get("pois", [])
	check(pois.size() >= 5, "hamlet should have at least 5 POIs (2 gates + 3 baseline); got %d" % pois.size())
	print("  hamlet_produces_baseline_pois: OK")


func test_city_produces_more_pois_than_hamlet() -> void:
	var gen := SettlementLayoutGenerator.new()
	var hamlet: Dictionary = gen.generate({"id": "h", "name": "H", "market_class": 6, "seed": 1})
	var city: Dictionary = gen.generate({"id": "c", "name": "C", "market_class": 2, "seed": 1})
	var hamlet_pois: int = ((hamlet["districts"][0] as Dictionary)["pois"] as Array).size()
	var city_pois: int = ((city["districts"][0] as Dictionary)["pois"] as Array).size()
	check(city_pois > hamlet_pois,
		"city (mc=2) should have more POIs than hamlet (mc=6); got %d vs %d" % [city_pois, hamlet_pois])
	print("  city_produces_more_pois_than_hamlet: OK")


func test_at_least_one_entry_exit_poi() -> void:
	var gen := SettlementLayoutGenerator.new()
	for mc in [1, 2, 3, 4, 5, 6]:
		var d: Dictionary = gen.generate({"id": "s_%d" % mc, "name": "S", "market_class": mc, "seed": 1})
		var entry_count := 0
		for district_v in d.get("districts", []):
			var district: Dictionary = district_v
			for poi_v in district.get("pois", []):
				var poi: Dictionary = poi_v
				if bool(poi.get("is_entry_exit", false)):
					entry_count += 1
		check(entry_count >= 1,
			"market_class %d settlement must have at least one entry/exit POI; got %d" % [mc, entry_count])
	print("  at_least_one_entry_exit_poi: OK")


func test_seed_is_deterministic() -> void:
	var gen := SettlementLayoutGenerator.new()
	var opts := {"id": "settlement_avalon", "name": "Avalon", "market_class": 3, "seed": 12345}
	var a: Dictionary = gen.generate(opts)
	var b: Dictionary = gen.generate(opts)
	check(JSON.stringify(a) == JSON.stringify(b),
		"same opts must produce identical layout")
	print("  seed_is_deterministic: OK")


func test_required_fields_present() -> void:
	var gen := SettlementLayoutGenerator.new()
	var d: Dictionary = gen.generate({"id": "s", "name": "S", "market_class": 4, "seed": 1})
	# Fields the Enter Settlement flow consumes (per gdd-settlement-layout.md v2 §6.4).
	check(d.has("id"), "missing id")
	check(d.has("name"), "missing name")
	check(d.has("market_class"), "missing market_class")
	check(d.has("districts"), "missing districts")
	check(d.has("undercity_pois"), "missing undercity_pois")
	check(d.has("transitions"), "missing transitions")
	for district_v in d["districts"]:
		var district: Dictionary = district_v
		check(district.has("id"), "district missing id")
		check(district.has("pois"), "district missing pois")
		for poi_v in district["pois"]:
			var poi: Dictionary = poi_v
			check(poi.has("id"), "poi missing id")
			check(poi.has("name"), "poi missing name")
			check(poi.has("type"), "poi missing type")
			check(poi.has("district_id"), "poi missing district_id")
			check(poi.has("is_entry_exit"), "poi missing is_entry_exit")
	print("  required_fields_present: OK")
