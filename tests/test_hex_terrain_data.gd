extends "res://tests/test_suite_base.gd"

## Plain GDScript unit tests for HexTerrainData.


func run_all_tests() -> void:
	test_flat_clear_wilderness_returns_100_clear()
	test_hills_woods_wilderness_weights()
	test_hills_clear_wilderness_reversed_weights()
	test_mountains_swamp_weights()
	test_civilized_returns_100_inhabited()
	test_city_overrides_all()
	test_borderlands_returns_50_inhabited_50_natural()
	test_ocean_water_returns_ocean()
	test_movement_cost_mountains_beats_swamp()
	test_movement_cost_swamp_beats_jungle()
	test_movement_cost_jungle_beats_woods()
	test_movement_cost_hills_woods_returns_woods()
	test_movement_cost_flat_desert_returns_desert()
	test_is_valid_accepts_valid_terrain()
	test_is_valid_rejects_invalid_elevation()
	if not has_failures():
		print("HexTerrainData: all tests passed.")


func test_flat_clear_wilderness_returns_100_clear() -> void:
	var t := HexTerrainData.new()
	# defaults: flat, clear, wilderness
	var weights := t.encounter_table_weights()
	check(weights.get("clear_grass_scrub", 0) == 100, "flat/clear/wilderness should be 100% clear_grass_scrub")


func test_hills_woods_wilderness_weights() -> void:
	var t := HexTerrainData.new()
	t.elevation = HexTerrainData.ELEVATION_HILLS
	t.biome = HexTerrainData.BIOME_WOODS
	var weights := t.encounter_table_weights()
	check(weights.get("woods", 0) == 60, "hills/woods should be 60% woods")
	check(weights.get("mountains_hills", 0) == 40, "hills/woods should be 40% mountains_hills")


func test_hills_clear_wilderness_reversed_weights() -> void:
	# hills/clear is the "pure hills" case — reversed weights
	var t := HexTerrainData.new()
	t.elevation = HexTerrainData.ELEVATION_HILLS
	t.biome = HexTerrainData.BIOME_CLEAR
	var weights := t.encounter_table_weights()
	check(weights.get("clear_grass_scrub", 0) == 40, "hills/clear should be 40% clear")
	check(weights.get("mountains_hills", 0) == 60, "hills/clear should be 60% mountains_hills")


func test_mountains_swamp_weights() -> void:
	var t := HexTerrainData.new()
	t.elevation = HexTerrainData.ELEVATION_MOUNTAINS
	t.biome = HexTerrainData.BIOME_SWAMP
	var weights := t.encounter_table_weights()
	check(weights.get("swamp", 0) == 60)
	check(weights.get("mountains_hills", 0) == 40)


func test_civilized_returns_100_inhabited() -> void:
	var t := HexTerrainData.new()
	t.civilization = HexTerrainData.TERRITORY_CIVILIZED
	var weights := t.encounter_table_weights()
	check(weights.get("inhabited", 0) == 100)


func test_city_overrides_all() -> void:
	var t := HexTerrainData.new()
	t.civilization = HexTerrainData.TERRITORY_WILDERNESS  # wilderness — but has_city overrides
	t.has_city = true
	var weights := t.encounter_table_weights()
	check(weights.get("city", 0) == 100, "has_city should override everything")


func test_borderlands_returns_50_inhabited_50_natural() -> void:
	var t := HexTerrainData.new()
	t.civilization = HexTerrainData.TERRITORY_BORDERLANDS
	var weights := t.encounter_table_weights()
	check(weights.get("inhabited", 0) == 50)
	check(weights.get("_natural", 0) == 50)


func test_ocean_water_returns_ocean() -> void:
	var t := HexTerrainData.new()
	t.water = HexTerrainData.WATER_OCEAN
	var weights := t.encounter_table_weights()
	check(weights.get("ocean", 0) == 100)


func test_movement_cost_mountains_beats_swamp() -> void:
	var t := HexTerrainData.new()
	t.elevation = HexTerrainData.ELEVATION_MOUNTAINS
	t.biome = HexTerrainData.BIOME_SWAMP
	check(t.movement_cost_category() == "mountains")


func test_movement_cost_swamp_beats_jungle() -> void:
	var t := HexTerrainData.new()
	t.biome = HexTerrainData.BIOME_SWAMP
	check(t.movement_cost_category() == "swamp")


func test_movement_cost_jungle_beats_woods() -> void:
	var t := HexTerrainData.new()
	t.biome = HexTerrainData.BIOME_JUNGLE
	check(t.movement_cost_category() == "jungle")


func test_movement_cost_hills_woods_returns_woods() -> void:
	var t := HexTerrainData.new()
	t.elevation = HexTerrainData.ELEVATION_HILLS
	t.biome = HexTerrainData.BIOME_WOODS
	check(t.movement_cost_category() == "woods")


func test_movement_cost_flat_desert_returns_desert() -> void:
	var t := HexTerrainData.new()
	t.biome = HexTerrainData.BIOME_DESERT
	check(t.movement_cost_category() == "desert")


func test_is_valid_accepts_valid_terrain() -> void:
	var t := HexTerrainData.new()
	check(t.is_valid(), "default terrain should be valid")


func test_is_valid_rejects_invalid_elevation() -> void:
	var t := HexTerrainData.new()
	t.elevation = "slope"  # not a valid value
	check(not t.is_valid())
