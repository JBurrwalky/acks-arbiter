extends "res://tests/test_suite_base.gd"

## DG-V1.E Scenario 5: Placeholder fallbacks active.
##
## Searches a fixed set of candidate seeds (range 5100..5199) to find ONE that
## produces >= 1 trap_placeholder room AND >= 1 unique_placeholder room across
## a medium 3-floor dungeon (et=1, fc=3, efi=1). Once found, that seed is used
## for all assertions. The first-found seed is printed so it can be hardcoded in
## a later session if desired.
##
## Asserts:
##   - At least one trap_placeholder room exists.
##   - At least one unique_placeholder room exists.
##   - Every trap_placeholder room has >= 1 bordering door with is_secret==true
##     AND type in [TYPE_LOCKED, TYPE_TRAPPED] (§14.1.6 HARD invariant).
##   - Every unique_placeholder room has monster_group_id != "".
##
## NOTE: monster_xp_each may be 0 for statless placeholders — per V1 design,
## this is valid. Do NOT assert nonzero XP.


func run_all_tests() -> void:
	test_placeholder_fallbacks_active()
	if not has_failures():
		print("Scenario.PlaceholderFallbacksActive: all tests passed.")


func test_placeholder_fallbacks_active() -> void:
	# Search a fixed candidate range.
	# Candidate seeds 5100..5199 — a deterministic set that guarantees reproducibility.
	var chosen_seed: int = -1
	var chosen_result: DungeonGeneratorResultV1 = null

	for candidate in range(5100, 5200):
		var req := DungeonGeneratorRequestV1.new()
		req.entrance_tier = 1
		req.floor_count = 3
		req.entrance_floor_index = 1
		req.dungeon_type = "wizards_dungeon"
		req.dungeon_size = "medium"
		req.seed = candidate
		req.persist = false

		var r: DungeonGeneratorResultV1 = DungeonGeneratorV1.generate(req)
		if r == null or not r.success:
			continue

		var has_trap: bool = false
		var has_unique: bool = false
		for fl in r.floors:
			var floor_layout: DungeonLayout = fl
			for room in floor_layout.rooms:
				var rm: DungeonRoomData = room
				if rm.contents_kind == "trap_placeholder":
					has_trap = true
				elif rm.contents_kind == "unique_placeholder":
					has_unique = true
			if has_trap and has_unique:
				break
		if has_trap and has_unique:
			chosen_seed = candidate
			chosen_result = r
			break

	if chosen_seed == -1:
		check(false,
			"Could not find any seed in 5100..5199 that produces both trap_placeholder AND unique_placeholder rooms; expand the search range or investigate the stocker distribution")
		return

	print("[DG-V1.E S5] found qualifying seed=%d — use this as the hardcoded seed." % chosen_seed)

	# Now run assertions against the chosen result.
	check(chosen_result.success,
		"seed=%d: success must be true (errors: %s)" % [chosen_seed, str(chosen_result.errors)])
	check(chosen_result.acceptance_report.get("hard_pass", false),
		"seed=%d: hard_pass must be true" % chosen_seed)

	# Collect all rooms across all floors, keyed by (floor_layout, room).
	var trap_rooms: Array = []
	var unique_rooms: Array = []
	for fl in chosen_result.floors:
		var floor_layout: DungeonLayout = fl
		for room in floor_layout.rooms:
			var rm: DungeonRoomData = room
			if rm.contents_kind == "trap_placeholder":
				trap_rooms.append({"floor": floor_layout, "room": rm})
			elif rm.contents_kind == "unique_placeholder":
				unique_rooms.append({"floor": floor_layout, "room": rm})

	check(trap_rooms.size() >= 1,
		"seed=%d: must have >= 1 trap_placeholder room; got %d" % [chosen_seed, trap_rooms.size()])
	check(unique_rooms.size() >= 1,
		"seed=%d: must have >= 1 unique_placeholder room; got %d" % [chosen_seed, unique_rooms.size()])

	# Every trap_placeholder room: >= 1 bordering door with is_secret==true
	# AND type in [TYPE_LOCKED, TYPE_TRAPPED] (§14.1.6 HARD invariant, >=1).
	for entry in trap_rooms:
		var rm: DungeonRoomData = entry["room"]
		var qualifying: int = 0
		for d in rm.doors:
			var door: DungeonDoorData = d
			if door.is_secret and (
				door.type == DungeonDoorData.TYPE_LOCKED
				or door.type == DungeonDoorData.TYPE_TRAPPED
			):
				qualifying += 1
		check(qualifying >= 1,
			"seed=%d: trap_placeholder room id=%d has %d qualifying (secret+locked/trapped) doors; need >= 1"
			% [chosen_seed, rm.id, qualifying])

	# Every unique_placeholder room: monster_group_id must be non-empty.
	for entry in unique_rooms:
		var rm: DungeonRoomData = entry["room"]
		check(rm.monster_group_id != "",
			"seed=%d: unique_placeholder room id=%d has empty monster_group_id"
			% [chosen_seed, rm.id])

	# Traceability summary.
	var total_mg: int = 0
	var total_gp: int = 0
	for fl in chosen_result.floors:
		var floor_layout: DungeonLayout = fl
		total_mg += floor_layout.monster_groups.size()
		for th in floor_layout.treasure_hoards:
			var hoard: TreasureHoardData = th
			total_gp += hoard.total_gp_value
	print("[DG-V1.E S5 seed=%d] floors=%d trap_rooms=%d unique_rooms=%d monster_groups=%d total_gp=%d placeholder_counts=%s xp_gp_ratio=%s"
		% [chosen_seed, chosen_result.floors.size(), trap_rooms.size(), unique_rooms.size(),
		total_mg, total_gp, str(chosen_result.placeholder_counts),
		str(chosen_result.acceptance_report.get("xp_gp_ratio_per_floor", []))])
