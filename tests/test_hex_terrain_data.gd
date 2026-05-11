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
	# Subtype tests (GDD §3.4)
	test_subtype_forest_dense_movement_jungle_tier()
	test_subtype_forest_dense_keeps_woods_column()
	test_subtype_badlands_uses_barren_column()
	test_subtype_badlands_flat_uses_hills_tier_movement()
	test_subtype_tundra_uses_clear_column()
	test_subtype_volcanic_uses_mountains_column()
	test_subtype_glacial_rejects_woods_biome()
	test_subtype_volcanic_allows_jungle()
	test_subtype_savanna_rejects_mountains_elevation()
	test_subtype_water_hex_rejects_subtype()
	test_subtype_encounter_distance_dense_forest()
	test_subtype_encounter_distance_badlands()
	test_subtype_tilt_taiga_boosts_animal()
	test_subtype_tilt_volcanic_boosts_dragon()
	test_subtype_tilt_empty_for_grassland()
	test_resolver_picks_woods_for_dense_forest()
	test_resolver_apply_tilt_zeroes_out()
	test_from_dict_roundtrips_subtype()
	if not has_failures():
		print("HexTerrainData: all tests passed.")


# ---------------------------------------------------------------------------
# Subtype tests
# ---------------------------------------------------------------------------

func test_subtype_forest_dense_movement_jungle_tier() -> void:
	var t := HexTerrainData.new()
	t.biome = HexTerrainData.BIOME_WOODS
	t.biome_subtype = HexTerrainData.SUBTYPE_FOREST_DENSE
	check(t.movement_cost_category() == "dense_forest",
		"flat dense forest should use dense_forest movement bucket, got %s" % t.movement_cost_category())


func test_subtype_forest_dense_keeps_woods_column() -> void:
	var t := HexTerrainData.new()
	t.biome = HexTerrainData.BIOME_WOODS
	t.biome_subtype = HexTerrainData.SUBTYPE_FOREST_DENSE
	var weights := t.encounter_table_weights()
	check(weights.get("woods", 0) == 100, "flat dense forest should be 100% woods column")


func test_subtype_badlands_uses_barren_column() -> void:
	var t := HexTerrainData.new()
	t.biome = HexTerrainData.BIOME_DESERT
	t.biome_subtype = HexTerrainData.SUBTYPE_DESERT_BADLANDS
	var weights := t.encounter_table_weights()
	check(weights.get("barren_desert", 0) == 100, "badlands should be 100% barren_desert")
	# Critically: subtype overrides the desert+hills 60/40 split.
	t.elevation = HexTerrainData.ELEVATION_HILLS
	weights = t.encounter_table_weights()
	check(weights.get("barren_desert", 0) == 100, "hills badlands should still be 100% barren_desert (subtype overrides)")


func test_subtype_badlands_flat_uses_hills_tier_movement() -> void:
	var t := HexTerrainData.new()
	t.biome = HexTerrainData.BIOME_DESERT
	t.biome_subtype = HexTerrainData.SUBTYPE_DESERT_BADLANDS
	check(t.movement_cost_category() == "badlands",
		"flat badlands should use badlands movement bucket (hills-tier), got %s" % t.movement_cost_category())


func test_subtype_tundra_uses_clear_column() -> void:
	var t := HexTerrainData.new()
	t.biome = HexTerrainData.BIOME_CLEAR
	t.biome_subtype = HexTerrainData.SUBTYPE_CLEAR_TUNDRA
	var weights := t.encounter_table_weights()
	check(weights.get("clear_grass_scrub", 0) == 100, "flat tundra should be 100% clear_grass_scrub")


func test_subtype_volcanic_uses_mountains_column() -> void:
	var t := HexTerrainData.new()
	t.elevation = HexTerrainData.ELEVATION_MOUNTAINS
	t.biome = HexTerrainData.BIOME_CLEAR
	t.biome_subtype = HexTerrainData.SUBTYPE_MOUNTAINS_VOLCANIC
	var weights := t.encounter_table_weights()
	check(weights.get("mountains_hills", 0) == 100, "volcanic should be 100% mountains_hills")


func test_subtype_glacial_rejects_woods_biome() -> void:
	var t := HexTerrainData.new()
	t.elevation = HexTerrainData.ELEVATION_MOUNTAINS
	t.biome = HexTerrainData.BIOME_WOODS
	t.biome_subtype = HexTerrainData.SUBTYPE_MOUNTAINS_GLACIAL
	check(not t.is_valid(), "glacial mountains may not have woods biome")


func test_subtype_volcanic_allows_jungle() -> void:
	var t := HexTerrainData.new()
	t.elevation = HexTerrainData.ELEVATION_MOUNTAINS
	t.biome = HexTerrainData.BIOME_JUNGLE
	t.biome_subtype = HexTerrainData.SUBTYPE_MOUNTAINS_VOLCANIC
	check(t.is_valid(), "tropical volcanic island = mountains+jungle+volcanic should be valid")


func test_subtype_savanna_rejects_mountains_elevation() -> void:
	var t := HexTerrainData.new()
	t.elevation = HexTerrainData.ELEVATION_MOUNTAINS
	t.biome = HexTerrainData.BIOME_CLEAR
	t.biome_subtype = HexTerrainData.SUBTYPE_CLEAR_SAVANNA
	check(not t.is_valid(), "savanna is flat/hills only — mountains should be rejected")


func test_subtype_water_hex_rejects_subtype() -> void:
	var t := HexTerrainData.new()
	t.water = HexTerrainData.WATER_OCEAN
	t.biome_subtype = HexTerrainData.SUBTYPE_CLEAR_GRASSLAND
	check(not t.is_valid(), "ocean hex must not carry a biome subtype")


func test_subtype_encounter_distance_dense_forest() -> void:
	var t := HexTerrainData.new()
	t.biome = HexTerrainData.BIOME_WOODS
	t.biome_subtype = HexTerrainData.SUBTYPE_FOREST_DENSE
	check(t.encounter_distance_dice() == "5d4",
		"forest_dense encounter distance should be 5d4 yards (RAW Forest Heavy)")


func test_subtype_encounter_distance_badlands() -> void:
	var t := HexTerrainData.new()
	t.biome = HexTerrainData.BIOME_DESERT
	t.biome_subtype = HexTerrainData.SUBTYPE_DESERT_BADLANDS
	check(t.encounter_distance_dice() == "2d6x10",
		"desert_badlands encounter distance should be 2d6x10 yards (RAW Badlands)")


func test_subtype_tilt_taiga_boosts_animal() -> void:
	var t := HexTerrainData.new()
	t.biome = HexTerrainData.BIOME_WOODS
	t.biome_subtype = HexTerrainData.SUBTYPE_FOREST_TAIGA
	var tilt := t.creature_type_tilt()
	check(float(tilt.get("Animal", 0.0)) > 1.0, "taiga should boost Animal")
	check(float(tilt.get("Humanoid", 0.0)) < 1.0, "taiga should reduce Humanoid")


func test_subtype_tilt_volcanic_boosts_dragon() -> void:
	var t := HexTerrainData.new()
	t.elevation = HexTerrainData.ELEVATION_MOUNTAINS
	t.biome_subtype = HexTerrainData.SUBTYPE_MOUNTAINS_VOLCANIC
	var tilt := t.creature_type_tilt()
	check(float(tilt.get("Dragon", 0.0)) > 1.0, "volcanic should boost Dragon (red dragons, salamanders)")


func test_subtype_tilt_empty_for_grassland() -> void:
	var t := HexTerrainData.new()
	t.biome_subtype = HexTerrainData.SUBTYPE_CLEAR_GRASSLAND
	check(t.creature_type_tilt().is_empty(), "grassland is RAW baseline — no tilt")


func test_resolver_picks_woods_for_dense_forest() -> void:
	var t := HexTerrainData.new()
	t.biome = HexTerrainData.BIOME_WOODS
	t.biome_subtype = HexTerrainData.SUBTYPE_FOREST_DENSE
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var column := EncounterTerrainResolver.resolve_column(t, rng)
	check(column == "woods", "dense forest resolver should pick woods column, got %s" % column)


func test_resolver_apply_tilt_zeroes_out() -> void:
	# A multiplier of 0.0 should remove the creature type entirely.
	var base := {"Men": 1, "Animal": 2, "Dragon": 1}
	var tilt := {"Dragon": 0.0}
	var out := EncounterTerrainResolver.apply_tilt(base, tilt)
	check(not out.has("Dragon"), "tilt of 0.0 should remove the creature type")
	check(out.get("Men", 0) > 0, "untilted types should remain")


func test_from_dict_roundtrips_subtype() -> void:
	var t := HexTerrainData.from_dict({
		"elevation": "mountains",
		"biome": "jungle",
		"biome_subtype": "mountains_volcanic",
	})
	check(t.biome_subtype == HexTerrainData.SUBTYPE_MOUNTAINS_VOLCANIC,
		"from_dict should preserve biome_subtype")
	check(t.is_valid(), "volcanic jungle mountains should be valid")


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
