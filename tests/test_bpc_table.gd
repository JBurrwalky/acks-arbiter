extends "res://tests/test_suite_base.gd"

## Tests for BpcTable per daw_axioms_pitching_battle.xml §battle_preparation
## .set_battle_phase_countdown L24-101.


func run_all_tests() -> void:
	test_clear_or_grass_buckets()
	test_mountains_buckets()
	test_swamp_buckets()
	test_heavy_rain_increments()
	test_unknown_terrain_falls_back_to_clear()
	test_roll_starting_bpc_returns_dict()
	if not has_failures():
		print("BpcTable: all tests passed.")


func test_clear_or_grass_buckets() -> void:
	# RAW: clear_or_grass row → 1, 1, 1, 2 for buckets 1, 2-4, 5-7, 8.
	check(BpcTable.lookup_bpc("clear_or_grass", 1) == 1, "clear roll 1 = 1")
	check(BpcTable.lookup_bpc("clear_or_grass", 3) == 1, "clear roll 3 = 1")
	check(BpcTable.lookup_bpc("clear_or_grass", 6) == 1, "clear roll 6 = 1")
	check(BpcTable.lookup_bpc("clear_or_grass", 8) == 2, "clear roll 8 = 2")


func test_mountains_buckets() -> void:
	# RAW: mountains row → 1, 2, 2, 3.
	check(BpcTable.lookup_bpc("mountains", 1) == 1, "mountains roll 1 = 1")
	check(BpcTable.lookup_bpc("mountains", 2) == 2, "mountains roll 2 = 2")
	check(BpcTable.lookup_bpc("mountains", 5) == 2, "mountains roll 5 = 2")
	check(BpcTable.lookup_bpc("mountains", 8) == 3, "mountains roll 8 = 3")


func test_swamp_buckets() -> void:
	# RAW: swamp row → 1, 2, 2, 3.
	check(BpcTable.lookup_bpc("swamp", 1) == 1, "swamp roll 1 = 1")
	check(BpcTable.lookup_bpc("swamp", 4) == 2, "swamp roll 4 = 2")
	check(BpcTable.lookup_bpc("swamp", 8) == 3, "swamp roll 8 = 3")


func test_heavy_rain_increments() -> void:
	# RAW L27: heavy rain or snow increases the terrain minimum by 1.
	check(BpcTable.lookup_bpc("clear_or_grass", 1, "heavy_rain") == 2, "clear + heavy_rain roll 1 = 2")
	check(BpcTable.lookup_bpc("clear_or_grass", 8, "heavy_rain") == 3, "clear + heavy_rain roll 8 = 3")
	check(BpcTable.lookup_bpc("mountains", 8, "heavy_rain") == 4, "mountains + heavy_rain roll 8 = 4")


func test_unknown_terrain_falls_back_to_clear() -> void:
	# Unknown terrain key → fallback to clear_or_grass row.
	check(BpcTable.lookup_bpc("alien_landscape", 1) == 1, "unknown roll 1 = 1")
	check(BpcTable.lookup_bpc("alien_landscape", 8) == 2, "unknown roll 8 = 2")


func test_roll_starting_bpc_returns_dict() -> void:
	var result := BpcTable.roll_starting_bpc("hills", "calm",
		func(_count, _sides): return 5)
	check(int(result.get("roll", 0)) == 5, "roll captured")
	check(int(result.get("bpc", 0)) == 1, "hills roll 5 = 1")
	check(String(result.get("terrain", "")) == "hills", "terrain echoed")
