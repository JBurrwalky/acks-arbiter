extends "res://tests/test_suite_base.gd"

## DG-V1.E Scenario 4: Entrance floor in the middle of a 5-floor dungeon.
##
## entrance_tier=2, floor_count=5, efi=3 → per-floor tiers [4,3,2,3,4].
## The entrance floor (level_number==3) has is_entrance_floor==true; others false.
## Validates bidirectional tier formula + stair anchoring across the middle entrance.
##
## Fixed seed: 4001


func run_all_tests() -> void:
	test_entrance_in_middle()
	if not has_failures():
		print("Scenario.EntranceInMiddle: all tests passed.")


func test_entrance_in_middle() -> void:
	var req := DungeonGeneratorRequestV1.new()
	req.entrance_tier = 2
	req.floor_count = 5
	req.entrance_floor_index = 3
	req.dungeon_type = "wizards_dungeon"
	req.dungeon_size = "medium"
	req.seed = 4001
	req.persist = false

	var result: DungeonGeneratorResultV1 = DungeonGeneratorV1.generate(req)

	check(result != null, "generate() must return non-null")
	if result == null:
		return

	check(result.success,
		"entrance-in-middle: success must be true (errors: %s)" % str(result.errors))
	check(result.floors.size() == 5,
		"entrance-in-middle: floors.size() must be 5, got %d" % result.floors.size())

	# Per-floor tier check: et=2, efi=3, fc=5 → tiers [4,3,2,3,4].
	# Formula: tier = clamp(entrance_tier + abs(floor_index - entrance_floor_index), 1, 6)
	# floor 1: 2+|1-3|=4, floor 2: 2+|2-3|=3, floor 3: 2+|3-3|=2, floor 4: 2+|4-3|=3, floor 5: 2+|5-3|=4
	var expected_tiers: Array[int] = [4, 3, 2, 3, 4]
	for fi in range(min(result.floors.size(), 5)):
		var fl: DungeonLayout = result.floors[fi]
		check(fl.floor_tier == expected_tiers[fi],
			"floor %d floor_tier must be %d, got %d" % [fi + 1, expected_tiers[fi], fl.floor_tier])

	# Entrance floor is floor index 3 (1-based), which is floors[2] (0-based).
	for fi in range(result.floors.size()):
		var fl: DungeonLayout = result.floors[fi]
		var expected_entrance: bool = (fl.level_number == 3)
		check(fl.is_entrance_floor == expected_entrance,
			"floor level_number=%d: is_entrance_floor must be %s, got %s"
			% [fl.level_number, str(expected_entrance), str(fl.is_entrance_floor)])

	check(result.acceptance_report.get("hard_pass", false),
		"entrance-in-middle: hard_pass must be true (hard_failures: %s)"
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
	print("[DG-V1.E S4 seed=4001] floors=%d monster_groups=%d total_gp=%d placeholder_counts=%s xp_gp_ratio=%s"
		% [result.floors.size(), total_mg, total_gp,
		str(result.placeholder_counts),
		str(result.acceptance_report.get("xp_gp_ratio_per_floor", []))])
