extends "res://tests/test_suite_base.gd"

## DG-V1.E Scenario 3: 6-floor dungeon with tier clamp.
##
## entrance_tier=3, floor_count=6, efi=1 → expected tiers [3,4,5,6,6,6].
## Verifies success, 6 floors, correct clamped tiers, hard_pass.
## Soft observation: logs the fraction of metal/stone/portcullis doors on the
## two deepest (tier-6) floors per §8.3.2 — not a hard assertion.
##
## Fixed seed: 3001


func run_all_tests() -> void:
	test_six_floor_tier_clamp()
	if not has_failures():
		print("Scenario.SixFloorTierClamp: all tests passed.")


func test_six_floor_tier_clamp() -> void:
	var req := DungeonGeneratorRequestV1.new()
	req.entrance_tier = 3
	req.floor_count = 6
	req.entrance_floor_index = 1
	req.dungeon_type = "wizards_dungeon"
	req.dungeon_size = "large"
	req.seed = 3001
	req.persist = false

	var result: DungeonGeneratorResultV1 = DungeonGeneratorV1.generate(req)

	check(result != null, "generate() must return non-null")
	if result == null:
		return

	check(result.success,
		"6-floor tier-clamp: success must be true (errors: %s)" % str(result.errors))
	check(result.floors.size() == 6,
		"6-floor tier-clamp: floors.size() must be 6, got %d" % result.floors.size())

	# Per-floor tier check: et=3, efi=1, fc=6 → tiers [3,4,5,6,6,6].
	var expected_tiers: Array[int] = [3, 4, 5, 6, 6, 6]
	for fi in range(min(result.floors.size(), 6)):
		var fl: DungeonLayout = result.floors[fi]
		check(fl.floor_tier == expected_tiers[fi],
			"floor %d floor_tier must be %d, got %d" % [fi + 1, expected_tiers[fi], fl.floor_tier])

	check(result.acceptance_report.get("hard_pass", false),
		"6-floor tier-clamp: hard_pass must be true (hard_failures: %s)"
		% str(result.acceptance_report.get("hard_failures", [])))

	# Soft observation: heavy door fraction on the two deepest (tier-6) floors.
	# §8.3.2 expects metal/stone/portcullis to appear more at high tiers.
	# We log this as an observation, not a hard assertion.
	var deep_total: int = 0
	var deep_heavy: int = 0
	for fi in range(min(result.floors.size(), 6)):
		if result.floors[fi].floor_tier < 6:
			continue
		var fl: DungeonLayout = result.floors[fi]
		for d in fl.doors:
			var door: DungeonDoorData = d
			deep_total += 1
			if (door.door_material == DungeonDoorData.MATERIAL_METAL
					or door.door_material == DungeonDoorData.MATERIAL_STONE
					or door.type == DungeonDoorData.TYPE_PORTCULLIS):
				deep_heavy += 1
	var heavy_pct: float = 0.0
	if deep_total > 0:
		heavy_pct = float(deep_heavy) / float(deep_total) * 100.0
	print("[DG-V1.E S3 §8.3.2 soft] tier-6 floors: %d doors total, %d metal/stone/portcullis (%.1f%%)" % [deep_total, deep_heavy, heavy_pct])

	# Traceability summary.
	var total_mg: int = 0
	var total_gp: int = 0
	for fl in result.floors:
		var floor_layout: DungeonLayout = fl
		total_mg += floor_layout.monster_groups.size()
		for th in floor_layout.treasure_hoards:
			var hoard: TreasureHoardData = th
			total_gp += hoard.total_gp_value
	print("[DG-V1.E S3 seed=3001] floors=%d monster_groups=%d total_gp=%d placeholder_counts=%s xp_gp_ratio=%s"
		% [result.floors.size(), total_mg, total_gp,
		str(result.placeholder_counts),
		str(result.acceptance_report.get("xp_gp_ratio_per_floor", []))])
