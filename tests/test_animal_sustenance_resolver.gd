extends "res://tests/test_suite_base.gd"

## Unit tests for AnimalSustenanceResolver — the fodder/grazing daily tick for
## trained creatures (provisions Phase 3, gdd-rations-foodstuffs.md §5.3).
## Verifies the grazing/hunting waiver, fodder consumption by size, and the
## per-animal starvation HP curve (same as PCs per Jedidiah's 2026-06-08 ruling).


func run_all_tests() -> void:
	test_grazing_animal_needs_no_fodder()
	test_non_grazing_animal_eats_fodder()
	test_huge_animal_eats_four_fodder()
	test_insufficient_fodder_starves_on_pc_curve()
	test_grazing_resets_starvation_counter()
	test_dead_animal_skipped()
	if not has_failures():
		print("AnimalSustenanceResolver: all tests passed.")


func _make_creature(id: String, species: String, size: String, hp: int = 10) -> TrainedCreatureData:
	var c := TrainedCreatureData.new()
	c.id = id
	c.species_id = species
	c.monster_data = {"size_category": size}
	c.hp_current = hp
	c.hp_max = hp
	c.is_alive = true
	c.fodder_starvation_days = 0
	return c


func test_grazing_animal_needs_no_fodder() -> void:
	# A horse on grassland grazes — consumes no fodder even with a full pool.
	var horse := _make_creature("h1", "horse_heavy", "large")
	var r := AnimalSustenanceResolver.apply_daily(
		[horse], HexTerrainData.BIOME_CLEAR, "", 10)
	check(int(r.get("fodder_consumed", -1)) == 0, "grazing horse eats no fodder")
	check(int(r.get("grazed_count", -1)) == 1, "one animal grazed")
	check(horse.fodder_starvation_days == 0, "no starvation accrued")


func test_non_grazing_animal_eats_fodder() -> void:
	# Same horse in a desert (cannot graze) eats 1 fodder-day from the pool.
	var horse := _make_creature("h1", "horse_heavy", "large")
	var r := AnimalSustenanceResolver.apply_daily(
		[horse], HexTerrainData.BIOME_DESERT, "", 5)
	check(int(r.get("fodder_consumed", -1)) == 1, "desert horse eats 1 fodder-day")
	check(int(r.get("fed_count", -1)) == 1, "one animal fed from fodder")
	check(horse.fodder_starvation_days == 0, "fed animal has no starvation")


func test_huge_animal_eats_four_fodder() -> void:
	var elephant := _make_creature("e1", "elephant", "huge")
	var r := AnimalSustenanceResolver.apply_daily(
		[elephant], HexTerrainData.BIOME_DESERT, "", 10)
	check(int(r.get("fodder_consumed", -1)) == 4, "huge animal eats 4 fodder-days")


func test_insufficient_fodder_starves_on_pc_curve() -> void:
	# Horse in desert, no fodder. 2-day grace, then 1 hp/day (PC curve).
	var horse := _make_creature("h1", "horse_heavy", "large")
	var r1 := AnimalSustenanceResolver.apply_daily([horse], HexTerrainData.BIOME_DESERT, "", 0)
	check(horse.fodder_starvation_days == 1, "day 1: starvation_days=1")
	check(int(r1.get("total_hp_lost", -1)) == 0, "day 1: no HP loss (grace)")
	var r2 := AnimalSustenanceResolver.apply_daily([horse], HexTerrainData.BIOME_DESERT, "", 0)
	check(horse.fodder_starvation_days == 2, "day 2: starvation_days=2")
	check(int(r2.get("total_hp_lost", -1)) == 0, "day 2: still grace")
	var r3 := AnimalSustenanceResolver.apply_daily([horse], HexTerrainData.BIOME_DESERT, "", 0)
	check(horse.fodder_starvation_days == 3, "day 3: starvation_days=3")
	check(int(r3.get("total_hp_lost", -1)) == 1, "day 3: 1 hp lost past grace")
	check(r3.get("hp_loss_per_creature", {}).get("h1", -1) == 1, "horse h1 lost 1 hp")


func test_grazing_resets_starvation_counter() -> void:
	# Starve a bit, then reach pasture — the counter resets.
	var horse := _make_creature("h1", "horse_heavy", "large")
	AnimalSustenanceResolver.apply_daily([horse], HexTerrainData.BIOME_DESERT, "", 0)
	AnimalSustenanceResolver.apply_daily([horse], HexTerrainData.BIOME_DESERT, "", 0)
	check(horse.fodder_starvation_days == 2, "fixture: 2 hungry days")
	AnimalSustenanceResolver.apply_daily([horse], HexTerrainData.BIOME_CLEAR, "", 0)
	check(horse.fodder_starvation_days == 0, "grazing resets the starvation counter")


func test_dead_animal_skipped() -> void:
	var horse := _make_creature("h1", "horse_heavy", "large")
	horse.is_alive = false
	var r := AnimalSustenanceResolver.apply_daily([horse], HexTerrainData.BIOME_DESERT, "", 0)
	check(int(r.get("fodder_consumed", -1)) == 0, "dead animal eats nothing")
	check(int(r.get("starved_count", -1)) == 0, "dead animal is skipped, not starved")
