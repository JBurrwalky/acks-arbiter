extends "res://tests/test_suite_base.gd"

## Unit tests for GrazingRules — diet classification, the per-diet × terrain
## grazing/hunting waiver, and per-size fodder need (provisions Phase 3,
## gdd-rations-foodstuffs.md §5.3; RAW le_monster_training_rules.xml:415).


func run_all_tests() -> void:
	test_diet_classification()
	test_diet_override_from_monster_data()
	test_herbivore_grazes_pasture_not_desert()
	test_barren_subtype_denies_all()
	test_carnivore_hunts_swamp_not_desert()
	test_omnivore_uses_either()
	test_daily_fodder_by_size()
	if not has_failures():
		print("GrazingRules: all tests passed.")


func test_diet_classification() -> void:
	check(GrazingRules.diet_for_species("horse_heavy") == GrazingRules.DIET_HERBIVORE,
		"horse is herbivore")
	check(GrazingRules.diet_for_species("mule") == GrazingRules.DIET_HERBIVORE,
		"mule is herbivore")
	check(GrazingRules.diet_for_species("war_dog") == GrazingRules.DIET_CARNIVORE,
		"war dog is carnivore")
	check(GrazingRules.diet_for_species("cat_lion") == GrazingRules.DIET_CARNIVORE,
		"lion is carnivore")
	check(GrazingRules.diet_for_species("boar_giant") == GrazingRules.DIET_OMNIVORE,
		"boar is omnivore")
	check(GrazingRules.diet_for_species("unknown_beast") == GrazingRules.DIET_HERBIVORE,
		"unknown beast of burden defaults to herbivore")


func test_diet_override_from_monster_data() -> void:
	# An explicit graze_diet on the monster record wins over keyword inference.
	check(GrazingRules.diet_for_species("horse", {"graze_diet": "carnivore"})
			== GrazingRules.DIET_CARNIVORE,
		"explicit graze_diet override wins")


func test_herbivore_grazes_pasture_not_desert() -> void:
	check(GrazingRules.can_graze(GrazingRules.DIET_HERBIVORE,
			HexTerrainData.BIOME_CLEAR, ""), "herbivore grazes clear pasture")
	check(GrazingRules.can_graze(GrazingRules.DIET_HERBIVORE,
			HexTerrainData.BIOME_WOODS, ""), "herbivore browses woods")
	check(not GrazingRules.can_graze(GrazingRules.DIET_HERBIVORE,
			HexTerrainData.BIOME_DESERT, ""), "herbivore cannot graze desert")
	check(not GrazingRules.can_graze(GrazingRules.DIET_HERBIVORE,
			HexTerrainData.BIOME_SWAMP, ""), "herbivore cannot graze marsh")


func test_barren_subtype_denies_all() -> void:
	# Even on a clear biome, a winter/barren subtype offers no forage.
	check(not GrazingRules.can_graze(GrazingRules.DIET_HERBIVORE,
			HexTerrainData.BIOME_CLEAR, HexTerrainData.SUBTYPE_CLEAR_TUNDRA),
		"tundra denies grazing")
	check(not GrazingRules.can_graze(GrazingRules.DIET_CARNIVORE,
			HexTerrainData.BIOME_CLEAR, HexTerrainData.SUBTYPE_MOUNTAINS_GLACIAL),
		"glacial denies hunting")


func test_carnivore_hunts_swamp_not_desert() -> void:
	check(GrazingRules.can_graze(GrazingRules.DIET_CARNIVORE,
			HexTerrainData.BIOME_SWAMP, ""), "carnivore hunts swamp game")
	check(GrazingRules.can_graze(GrazingRules.DIET_CARNIVORE,
			HexTerrainData.BIOME_WOODS, ""), "carnivore hunts woods game")
	check(not GrazingRules.can_graze(GrazingRules.DIET_CARNIVORE,
			HexTerrainData.BIOME_DESERT, ""), "carnivore cannot hunt barren desert")


func test_omnivore_uses_either() -> void:
	check(GrazingRules.can_graze(GrazingRules.DIET_OMNIVORE,
			HexTerrainData.BIOME_SWAMP, ""),
		"omnivore feeds in swamp (hunt range)")
	check(GrazingRules.can_graze(GrazingRules.DIET_OMNIVORE,
			HexTerrainData.BIOME_CLEAR, ""),
		"omnivore feeds in clear (graze)")
	check(not GrazingRules.can_graze(GrazingRules.DIET_OMNIVORE,
			HexTerrainData.BIOME_DESERT, ""),
		"omnivore still cannot feed in barren desert")


func test_daily_fodder_by_size() -> void:
	check(GrazingRules.daily_fodder_units("large") == 1, "standard mount: 1 fodder/day")
	check(GrazingRules.daily_fodder_units("man_sized") == 1, "man-sized: 1 fodder/day")
	check(GrazingRules.daily_fodder_units("huge") == 4, "huge (elephant): 4 fodder/day")
	check(GrazingRules.daily_fodder_units("gigantic") == 8, "gigantic: 8 fodder/day")
