extends "res://tests/test_suite_base.gd"

## DG-V1.E Scenario 2: Medium 3-floor subterranean dungeon (canonical DG-V1.D case).
##
## Verifies: success, 3 floors, per-floor tiers [1,2,3], hard_pass,
## key_items well-formed (each KeyItemData has a valid opens_door_position).
##
## Fixed seed: 2001


func run_all_tests() -> void:
	test_medium_three_floor_subterranean()
	if not has_failures():
		print("Scenario.MediumThreeFloorSubterranean: all tests passed.")


func test_medium_three_floor_subterranean() -> void:
	var req := DungeonGeneratorRequestV1.new()
	req.entrance_tier = 1
	req.floor_count = 3
	req.entrance_floor_index = 1
	req.dungeon_type = "wizards_dungeon"
	req.dungeon_size = "medium"
	req.seed = 2001
	req.persist = false

	var result: DungeonGeneratorResultV1 = DungeonGeneratorV1.generate(req)

	check(result != null, "generate() must return non-null")
	if result == null:
		return

	check(result.success,
		"medium 3-floor: success must be true (errors: %s)" % str(result.errors))
	check(result.floors.size() == 3,
		"medium 3-floor: floors.size() must be 3, got %d" % result.floors.size())

	# Per-floor tier check: efi=1, et=1 → tiers [1,2,3].
	var expected_tiers: Array[int] = [1, 2, 3]
	for fi in range(min(result.floors.size(), 3)):
		var fl: DungeonLayout = result.floors[fi]
		check(fl.floor_tier == expected_tiers[fi],
			"floor %d floor_tier must be %d, got %d" % [fi + 1, expected_tiers[fi], fl.floor_tier])

	check(result.acceptance_report.get("hard_pass", false),
		"medium 3-floor: hard_pass must be true (hard_failures: %s)"
		% str(result.acceptance_report.get("hard_failures", [])))

	# key_items well-formed: every KeyItemData must have a valid opens_door_position.
	for ki in result.key_items:
		var k: KeyItemData = ki
		check(k.opens_door_position != Vector2i(-1, -1),
			"key_item has invalid opens_door_position (-1,-1); opens_door_floor_index=%d"
			% k.opens_door_floor_index)

	# Traceability summary.
	var total_mg: int = 0
	var total_gp: int = 0
	for fl in result.floors:
		var floor_layout: DungeonLayout = fl
		total_mg += floor_layout.monster_groups.size()
		for th in floor_layout.treasure_hoards:
			var hoard: TreasureHoardData = th
			total_gp += hoard.total_gp_value
	print("[DG-V1.E S2 seed=2001] floors=%d monster_groups=%d total_gp=%d placeholder_counts=%s xp_gp_ratio=%s"
		% [result.floors.size(), total_mg, total_gp,
		str(result.placeholder_counts),
		str(result.acceptance_report.get("xp_gp_ratio_per_floor", []))])
