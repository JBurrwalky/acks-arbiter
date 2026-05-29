extends "res://tests/test_suite_base.gd"

## DG-V1.E Scenario 1: Lair, single floor, tier 1.
##
## The smallest possible dungeon — proves the basic path from request to result
## works for a lair-sized single-floor dungeon at the lowest difficulty tier.
##
## Fixed seed: 1001


func run_all_tests() -> void:
	test_lair_single_floor_tier1()
	if not has_failures():
		print("Scenario.LairSingleFloorTier1: all tests passed.")


func test_lair_single_floor_tier1() -> void:
	var req := DungeonGeneratorRequestV1.new()
	req.entrance_tier = 1
	req.floor_count = 1
	req.entrance_floor_index = 1
	req.dungeon_type = "wizards_dungeon"
	req.dungeon_size = "lair"
	req.seed = 1001
	req.persist = false

	var result: DungeonGeneratorResultV1 = DungeonGeneratorV1.generate(req)

	check(result != null, "generate() must return non-null")
	if result == null:
		return

	check(result.success,
		"lair single-floor tier-1: success must be true (errors: %s)" % str(result.errors))
	check(result.floors.size() == 1,
		"lair single-floor: floors.size() must be 1, got %d" % result.floors.size())

	if result.floors.size() >= 1:
		var floor0: DungeonLayout = result.floors[0]
		check(floor0.floor_tier == 1,
			"lair floor_tier must be 1, got %d" % floor0.floor_tier)

	check(result.acceptance_report.get("hard_pass", false),
		"lair single-floor: acceptance_report hard_pass must be true (hard_failures: %s)"
		% str(result.acceptance_report.get("hard_failures", [])))

	# Traceability summary.
	var total_mg: int = 0
	var total_gp: int = 0
	for fl in result.floors:
		var floor_layout: DungeonLayout = fl
		total_mg += floor_layout.monster_groups.size()
		for th in floor_layout.treasure_hoards:
			var hoard: TreasureHoardData = th
			total_gp += hoard.total_gp_value
	print("[DG-V1.E S1 seed=1001] floors=%d monster_groups=%d total_gp=%d placeholder_counts=%s xp_gp_ratio=%s"
		% [result.floors.size(), total_mg, total_gp,
		str(result.placeholder_counts),
		str(result.acceptance_report.get("xp_gp_ratio_per_floor", []))])
