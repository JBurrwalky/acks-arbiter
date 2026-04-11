extends "res://tests/test_suite_base.gd"

## Unit tests for DraftVehicleService.


func run_all_tests() -> void:
	test_team_equivalents()
	test_cart_small_capacity()
	test_cart_large_capacity()
	test_wagon_capacity()
	test_insufficient_team()
	test_vehicle_mobility()
	test_overload_detection()
	test_hitch_validation_no_draft_saddle()
	test_hitch_validation_double_hitch()
	test_vehicle_load_calculation()

	if not has_failures():
		print("DraftVehicleService: all tests passed.")


# --- Helpers ---

func _make_creature(species: String = "mule", saddle_type: String = "draft") -> TrainedCreatureData:
	var c := TrainedCreatureData.new()
	c.id = "creature_%d" % randi()
	c.species_id = species
	c.role = "WB"
	c.is_alive = true
	c.monster_data = {
		"size_category": "large",
		"movement": {"land": {"exploration": 120, "combat": 40}},
		"special_abilities": [],
	}
	if not saddle_type.is_empty():
		c.inventory = [{"item_key": "saddle_%s" % saddle_type, "is_equipped": 1, "slot": "mount"}]
	else:
		c.inventory = []
	return c


func _make_vehicle(item_key: String = "cart_small", hitched: Array = []) -> Dictionary:
	return {
		"id": "vehicle_%d" % randi(),
		"item_key": item_key,
		"hitched_creatures": JSON.stringify(hitched),
	}


# --- Team equivalents ---

func test_team_equivalents() -> void:
	var mule := _make_creature("mule")
	var heavy := _make_creature("horse_heavy")
	var ox := _make_creature("ox")

	check(is_equal_approx(DraftVehicleService.calculate_team_equivalents([mule]), 0.5),
		"1 mule = 0.5 equiv")
	check(is_equal_approx(DraftVehicleService.calculate_team_equivalents([mule, mule]), 1.0),
		"2 mules = 1.0 equiv")
	check(is_equal_approx(DraftVehicleService.calculate_team_equivalents([heavy]), 1.0),
		"1 heavy horse = 1.0 equiv")
	check(is_equal_approx(DraftVehicleService.calculate_team_equivalents([heavy, heavy]), 2.0),
		"2 heavy horses = 2.0 equiv")
	check(is_equal_approx(DraftVehicleService.calculate_team_equivalents([ox]), 1.0),
		"1 ox = 1.0 equiv")
	print("  team_equivalents: OK")


# --- Cart small capacity ---

func test_cart_small_capacity() -> void:
	# 0.5 equiv (1 mule) -> 35/70
	var cap := DraftVehicleService.get_vehicle_capacity("cart_small", 0.5)
	check(cap.get("load_normal", 0) == 35, "cart_small 0.5 equiv normal = 35")
	check(cap.get("load_max", 0) == 70, "cart_small 0.5 equiv max = 70")

	# 1.0 equiv (2 mules) -> 80/160
	cap = DraftVehicleService.get_vehicle_capacity("cart_small", 1.0)
	check(cap.get("load_normal", 0) == 80, "cart_small 1.0 equiv normal = 80")
	check(cap.get("load_max", 0) == 160, "cart_small 1.0 equiv max = 160")
	print("  cart_small_capacity: OK")


# --- Cart large capacity ---

func test_cart_large_capacity() -> void:
	# 1.0 equiv -> 80/160
	var cap := DraftVehicleService.get_vehicle_capacity("cart_large", 1.0)
	check(cap.get("load_normal", 0) == 80, "cart_large 1.0 equiv normal = 80")

	# 2.0 equiv -> 120/240
	cap = DraftVehicleService.get_vehicle_capacity("cart_large", 2.0)
	check(cap.get("load_normal", 0) == 120, "cart_large 2.0 equiv normal = 120")
	check(cap.get("load_max", 0) == 240, "cart_large 2.0 equiv max = 240")
	print("  cart_large_capacity: OK")


# --- Wagon capacity ---

func test_wagon_capacity() -> void:
	# 2.0 equiv -> 160/320
	var cap := DraftVehicleService.get_vehicle_capacity("wagon", 2.0)
	check(cap.get("load_normal", 0) == 160, "wagon 2.0 equiv normal = 160")

	# 4.0 equiv -> 320/640
	cap = DraftVehicleService.get_vehicle_capacity("wagon", 4.0)
	check(cap.get("load_normal", 0) == 320, "wagon 4.0 equiv normal = 320")
	check(cap.get("load_max", 0) == 640, "wagon 4.0 equiv max = 640")
	print("  wagon_capacity: OK")


# --- Insufficient team ---

func test_insufficient_team() -> void:
	# Cart large with 0.5 equiv -> no matching tier
	var cap := DraftVehicleService.get_vehicle_capacity("cart_large", 0.4)
	check(cap.is_empty(), "cart_large with 0.4 equiv should have no capacity")

	# Wagon with 1.0 equiv -> no matching tier
	cap = DraftVehicleService.get_vehicle_capacity("wagon", 1.0)
	check(cap.is_empty(), "wagon with 1.0 equiv should have no capacity")
	print("  insufficient_team: OK")


# --- Mobility ---

func test_vehicle_mobility() -> void:
	check(DraftVehicleService.is_vehicle_mobile("cart_small", 0.5), "cart_small with 0.5 equiv should be mobile")
	check(not DraftVehicleService.is_vehicle_mobile("cart_large", 0.4), "cart_large with 0.4 equiv should be immobile")
	check(DraftVehicleService.is_vehicle_mobile("wagon", 2.0), "wagon with 2.0 equiv should be mobile")
	check(not DraftVehicleService.is_vehicle_mobile("wagon", 1.5), "wagon with 1.5 equiv should be immobile")
	print("  vehicle_mobility: OK")


# --- Overload ---

func test_overload_detection() -> void:
	# Cart small with 1 mule: max 70 stone = 70000 units
	check(not DraftVehicleService.is_overloaded("cart_small", 0.5, 69000), "69 stone should not be overloaded")
	check(DraftVehicleService.is_overloaded("cart_small", 0.5, 71000), "71 stone should be overloaded")
	print("  overload_detection: OK")


# --- Hitch validation ---

func test_hitch_validation_no_draft_saddle() -> void:
	var c := _make_creature("mule", "riding")  # riding saddle, not draft
	var v := _make_vehicle()
	var result := DraftVehicleService.validate_hitch(v, c, [v])
	check(result != "", "hitch without draft saddle should fail")
	print("  hitch_no_draft_saddle: OK")


func test_hitch_validation_double_hitch() -> void:
	var c := _make_creature("mule", "draft")
	var v1 := _make_vehicle("cart_small", [c.id])
	var v2 := _make_vehicle("cart_large")
	var result := DraftVehicleService.validate_hitch(v2, c, [v1, v2])
	check(result != "", "double-hitch should fail")
	print("  hitch_double: OK")


# --- Load calculation ---

func test_vehicle_load_calculation() -> void:
	var items := [
		{"encumbrance_units": 1000, "quantity": 10},  # 10 stone
		{"encumbrance_units": 500, "quantity": 4},     # 2 stone
	]
	var total := DraftVehicleService.calculate_vehicle_load_units(items)
	check(total == 12000, "vehicle load should be 12000 units, got %d" % total)
	print("  vehicle_load_calculation: OK")
