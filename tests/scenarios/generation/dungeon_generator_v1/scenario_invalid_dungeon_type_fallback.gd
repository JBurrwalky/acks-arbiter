extends "res://tests/test_suite_base.gd"

## DG-V1.E Scenario 6: Invalid dungeon_type falls back to Wizard's Dungeon (§7.1).
##
## Two generations: dungeon_type="tomb" and dungeon_type="garbage"
## (both with et=1, fc=2, efi=1).
##
## For each: asserts success, non-empty floors, and that the produced theme
## fell back to Wizard's Dungeon (floors[0].theme != null AND
## floors[0].theme.type_name == "Wizard's Dungeon").
##
## Fixed seeds: 6001 ("tomb"), 6002 ("garbage").


func run_all_tests() -> void:
	test_tomb_type_fallback()
	test_garbage_type_fallback()
	if not has_failures():
		print("Scenario.InvalidDungeonTypeFallback: all tests passed.")


func _run_fallback_test(dungeon_type: String, seed: int) -> void:
	var req := DungeonGeneratorRequestV1.new()
	req.entrance_tier = 1
	req.floor_count = 2
	req.entrance_floor_index = 1
	req.dungeon_type = dungeon_type
	req.dungeon_size = "medium"
	req.seed = seed
	req.persist = false

	var result: DungeonGeneratorResultV1 = DungeonGeneratorV1.generate(req)

	check(result != null,
		"dungeon_type='%s': generate() must return non-null" % dungeon_type)
	if result == null:
		return

	check(result.success,
		"dungeon_type='%s': generation must succeed (errors: %s)" % [dungeon_type, str(result.errors)])
	check(result.floors.size() > 0,
		"dungeon_type='%s': floors must be non-empty" % dungeon_type)

	if result.floors.size() > 0:
		var floor0: DungeonLayout = result.floors[0]
		check(floor0.theme != null,
			"dungeon_type='%s': floors[0].theme must not be null" % dungeon_type)
		if floor0.theme != null:
			check(floor0.theme.type_name == "Wizard's Dungeon",
				"dungeon_type='%s': §7.1 fallback: floors[0].theme.type_name must be 'Wizard's Dungeon', got '%s'"
				% [dungeon_type, floor0.theme.type_name])

	# Traceability summary.
	var total_mg: int = 0
	var total_gp: int = 0
	for fl in result.floors:
		var floor_layout: DungeonLayout = fl
		total_mg += floor_layout.monster_groups.size()
		for th in floor_layout.treasure_hoards:
			var hoard: TreasureHoardData = th
			total_gp += hoard.total_gp_value
	print("[DG-V1.E S6 dungeon_type='%s' seed=%d] floors=%d monster_groups=%d total_gp=%d placeholder_counts=%s xp_gp_ratio=%s"
		% [dungeon_type, seed, result.floors.size(), total_mg, total_gp,
		str(result.placeholder_counts),
		str(result.acceptance_report.get("xp_gp_ratio_per_floor", []))])


func test_tomb_type_fallback() -> void:
	_run_fallback_test("tomb", 6001)


func test_garbage_type_fallback() -> void:
	_run_fallback_test("garbage", 6002)
