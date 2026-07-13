extends "res://tests/test_suite_base.gd"

## End-to-end acceptance tests for DungeonGeneratorV1.generate().
##
## Uses persist=false throughout to avoid DB writes in this suite.
## Seed is fixed for determinism (42 for most cases).
##
## Reference: gdd-dungeon-generator-v1.md §4, §5, §6, §9, §10, §14.


func run_all_tests() -> void:
	test_basic_3_floor_success()
	test_floor_count_equals_3()
	test_per_floor_tiers()
	test_locked_doors_have_keys_or_are_bashable()
	test_portcullis_has_lever_or_is_soft_warn_only()
	test_trap_placeholder_rooms()
	test_unique_placeholder_rooms()
	test_solvability_reaches_all_stairs()
	test_determinism_same_seed()
	test_1_floor_case()
	test_tier_clamp_case()
	test_invalid_floor_count()
	test_invalid_entrance_tier()
	test_invalid_entrance_floor_index()
	test_trap_room_gating_invariant_many_seeds()
	if not has_failures():
		print("DungeonGeneratorV1: all tests passed.")


# Multi-seed guard for the §11.4 trap-room fallback + the full stocking pipeline.
# Generates a spread of dungeons and asserts the §14.1.6 HARD invariant: every
# trap_placeholder room is gated by AT LEAST ONE secret+locked/trapped bordering
# door (0 = unplayable). Exactly-one is the stocker's target; >1 is a benign
# over-gate (usually a layout-generated secret door) — counted for the summary
# only, not asserted. Also exercises ~30 full generations so a crash in the
# monster / treasure / key pipeline (e.g. a null catalog field) is caught.
# Also asserts EVERY dungeon generates successfully: the layout/stair-connectivity
# robustness fixes (stair interior margin + single-seed connectivity check +
# top-level whole-dungeon retry, 2026-05-28) made multi-floor generation reliable.
func test_trap_room_gating_invariant_many_seeds() -> void:
	var sizes: Array[String] = ["small", "medium"]
	var total: int = 0
	var successes: int = 0
	var trap_rooms: int = 0
	var ungated: int = 0      # trap rooms with 0 qualifying doors (HARD violation)
	var over_gated: int = 0   # trap rooms with >1 qualifying doors (benign)
	for i in range(1, 31):
		var req := DungeonGeneratorRequestV1.new()
		req.entrance_tier = 1 + (i % 3)     # 1..3
		req.floor_count = 1 + (i % 3)       # 1..3 floors
		req.entrance_floor_index = 1
		req.dungeon_type = "wizards_dungeon"
		req.dungeon_size = sizes[i % sizes.size()]
		req.seed = 7000 + i
		req.persist = false
		var result: DungeonGeneratorResultV1 = DungeonGeneratorV1.generate(req)
		total += 1
		if result.success:
			successes += 1
		for floor_layout in result.floors:
			for room in floor_layout.rooms:
				if room.contents_kind != "trap_placeholder":
					continue
				trap_rooms += 1
				var q: int = 0
				for door in room.doors:
					if door.is_secret and (
						door.type == DungeonDoorData.TYPE_LOCKED
						or door.type == DungeonDoorData.TYPE_TRAPPED
					):
						q += 1
				if q < 1:
					ungated += 1
				elif q > 1:
					over_gated += 1
	print("[trap-gating] %d dungeons (%d generated ok); %d trap rooms, %d ungated, %d over-gated(>1)"
		% [total, successes, trap_rooms, ungated, over_gated])
	check(ungated == 0,
		"%d trap_placeholder rooms had 0 qualifying (secret+locked/trapped) doors — unplayable" % ungated)
	check(successes == total,
		"%d/%d dungeons failed to generate (expected all to succeed after the robustness fixes)"
			% [total - successes, total])


# ---------------------------------------------------------------------------
# Main acceptance-criteria tests (entrance_tier=1, floor_count=3, efi=1)
# ---------------------------------------------------------------------------

func _make_3_floor_request() -> DungeonGeneratorRequestV1:
	var req := DungeonGeneratorRequestV1.new()
	req.entrance_tier = 1
	req.floor_count = 3
	req.entrance_floor_index = 1
	req.dungeon_type = "wizards_dungeon"
	req.dungeon_size = "small"
	req.seed = 12345
	req.persist = false
	return req


func test_basic_3_floor_success() -> void:
	var req := _make_3_floor_request()
	var result: DungeonGeneratorResultV1 = DungeonGeneratorV1.generate(req)
	check(result != null, "generate() should return a non-null result")
	if result == null:
		return
	if not result.success:
		push_warning("DungeonGeneratorV1 test: generation failed. errors=%s warnings=%s" % [str(result.errors), str(result.warnings)])
	check(result.success, "generate() should return success==true (errors: %s)" % str(result.errors))


func test_floor_count_equals_3() -> void:
	var req := _make_3_floor_request()
	var result: DungeonGeneratorResultV1 = DungeonGeneratorV1.generate(req)
	if result == null:
		return
	check(result.floors.size() == 3,
		"result.floors.size() should be 3, got %d" % result.floors.size())


func test_per_floor_tiers() -> void:
	# entrance_tier=1, entrance_floor_index=1 -> tiers = [1, 2, 3]
	var req := _make_3_floor_request()
	var result: DungeonGeneratorResultV1 = DungeonGeneratorV1.generate(req)
	if result == null or result.floors.size() < 3:
		return
	var expected_tiers: Array[int] = [1, 2, 3]
	for fi in range(3):
		var floor_layout: DungeonLayout = result.floors[fi]
		check(floor_layout.floor_tier == expected_tiers[fi],
			"floor %d floor_tier should be %d, got %d" % [fi + 1, expected_tiers[fi], floor_layout.floor_tier])


func test_locked_doors_have_keys_or_are_bashable() -> void:
	var req := _make_3_floor_request()
	var result: DungeonGeneratorResultV1 = DungeonGeneratorV1.generate(req)
	if result == null or not result.success:
		return
	# Build lookup set of doors that have a key.
	var keyed: Dictionary = {}
	for ki in result.key_items:
		var k: KeyItemData = ki
		keyed["%d:%d,%d" % [k.opens_door_floor_index, k.opens_door_position.x, k.opens_door_position.y]] = true

	for fi in range(result.floors.size()):
		var floor_layout: DungeonLayout = result.floors[fi]
		var floor_num: int = floor_layout.level_number
		for d in floor_layout.doors:
			var door: DungeonDoorData = d
			if door.type != DungeonDoorData.TYPE_LOCKED:
				continue
			if DungeonDoorData.is_bashable(door.door_material):
				continue  # bashable wood needs no key
			var key_str: String = "%d:%d,%d" % [floor_num, door.position.x, door.position.y]
			check(keyed.has(key_str),
				"floor %d locked %s door at %s has no key and is not bashable"
				% [floor_num, door.door_material, str(door.position)])


func test_portcullis_has_lever_or_is_soft_warn_only() -> void:
	# Acceptance test 5: portcullises without levers are a SOFT warning only — not a
	# hard failure. This test just verifies the pipeline runs without hard errors.
	var req := _make_3_floor_request()
	var result: DungeonGeneratorResultV1 = DungeonGeneratorV1.generate(req)
	if result == null:
		return
	# Hard failures should not include any [T5] entries (those are T5-soft).
	var hard_failures: Array = result.acceptance_report.get("hard_failures", [])
	for hf in hard_failures:
		check(not str(hf).begins_with("[T5"),
			"portcullis without lever should be soft-only, not hard failure: %s" % str(hf))


func test_trap_placeholder_rooms() -> void:
	# Every trap_placeholder room must have exactly 1 secret+locked/trapped door.
	var req := _make_3_floor_request()
	var result: DungeonGeneratorResultV1 = DungeonGeneratorV1.generate(req)
	if result == null or not result.success:
		return
	var hard_failures: Array = result.acceptance_report.get("hard_failures", [])
	for hf in hard_failures:
		check(not str(hf).begins_with("[T6"),
			"trap_placeholder hard failure: %s" % str(hf))


func test_unique_placeholder_rooms() -> void:
	# Every unique_placeholder room must have monster_group_id != "".
	var req := _make_3_floor_request()
	var result: DungeonGeneratorResultV1 = DungeonGeneratorV1.generate(req)
	if result == null or not result.success:
		return
	var hard_failures: Array = result.acceptance_report.get("hard_failures", [])
	for hf in hard_failures:
		check(not str(hf).begins_with("[T7"),
			"unique_placeholder hard failure: %s" % str(hf))


func test_solvability_reaches_all_stairs() -> void:
	# Post-cutover (DG-C3D.F): vertical connectivity is the composed volume's
	# stairwells, not per-floor DungeonStairData — generate() itself gates
	# success on validate_composed_solvability (every zone + stairwell
	# reachable from the entrance in the initial door state). Assert the
	# composed contract here: a 3-floor dungeon carries a contiguous volume,
	# at least one stairwell per adjacent band pair, and success (which implies
	# the composed solvability pass held).
	var req := _make_3_floor_request()
	var result: DungeonGeneratorResultV1 = DungeonGeneratorV1.generate(req)
	if result == null:
		return
	check(result.success, "3-floor composed generation succeeds (errors: %s)" % str(result.errors))
	check(result.composed_volume != null, "result carries the composed volume")
	var pairs_covered: Dictionary = {}
	for sw in result.stairwells:
		var stairwell: StairwellData = sw
		pairs_covered["%d:%d" % [mini(stairwell.lower_band, stairwell.upper_band), maxi(stairwell.lower_band, stairwell.upper_band)]] = true
		check(not stairwell.run_cells.is_empty(),
			"stairwell %s has run cells" % stairwell.stairwell_id)
	check(pairs_covered.has("1:2") and pairs_covered.has("2:3"),
		"every adjacent band pair has at least one stairwell (covered: %s)" % str(pairs_covered.keys()))


func test_determinism_same_seed() -> void:
	var req1 := _make_3_floor_request()
	var req2 := _make_3_floor_request()
	var r1: DungeonGeneratorResultV1 = DungeonGeneratorV1.generate(req1)
	var r2: DungeonGeneratorResultV1 = DungeonGeneratorV1.generate(req2)
	if r1 == null or r2 == null:
		return
	check(r1.floors.size() == r2.floors.size(),
		"determinism: floor count should match (%d vs %d)" % [r1.floors.size(), r2.floors.size()])
	for fi in range(min(r1.floors.size(), r2.floors.size())):
		var f1: DungeonLayout = r1.floors[fi]
		var f2: DungeonLayout = r2.floors[fi]
		check(f1.rooms.size() == f2.rooms.size(),
			"determinism: floor %d room count should match (%d vs %d)"
			% [fi + 1, f1.rooms.size(), f2.rooms.size()])


# ---------------------------------------------------------------------------
# Additional cases
# ---------------------------------------------------------------------------

func test_1_floor_case() -> void:
	var req := DungeonGeneratorRequestV1.new()
	req.entrance_tier = 2
	req.floor_count = 1
	req.entrance_floor_index = 1
	req.dungeon_type = "wizards_dungeon"
	req.dungeon_size = "small"
	req.seed = 99
	req.persist = false

	var result: DungeonGeneratorResultV1 = DungeonGeneratorV1.generate(req)
	check(result != null, "1-floor generate() should return non-null")
	if result == null:
		return
	check(result.floors.size() == 1, "1-floor result.floors.size() should be 1")
	if result.success:
		check(result.floors[0].floor_tier == 2,
			"single-floor tier should be entrance_tier=2, got %d" % result.floors[0].floor_tier)


func test_tier_clamp_case() -> void:
	# entrance_tier=3, floor_count=6, efi=1 → expected tiers [3,4,5,6,6,6]
	var req := DungeonGeneratorRequestV1.new()
	req.entrance_tier = 3
	req.floor_count = 6
	req.entrance_floor_index = 1
	req.dungeon_type = "wizards_dungeon"
	req.dungeon_size = "small"  # small for reliable stair anchoring across 6 floors
	req.seed = 77
	req.persist = false

	var result: DungeonGeneratorResultV1 = DungeonGeneratorV1.generate(req)
	check(result != null, "tier-clamp generate() should return non-null")
	if result == null:
		return
	check(result.success, "tier-clamp case should succeed (errors: %s)" % str(result.errors))
	check(result.floors.size() == 6, "tier-clamp: should have 6 floors, got %d" % result.floors.size())

	var expected_tiers: Array[int] = [3, 4, 5, 6, 6, 6]
	for fi in range(min(result.floors.size(), 6)):
		var ft: int = result.floors[fi].floor_tier
		check(ft == expected_tiers[fi],
			"tier-clamp floor %d: expected tier %d, got %d" % [fi + 1, expected_tiers[fi], ft])

	# Clamp warning should be present.
	var has_clamp_warning := false
	for w in result.warnings:
		if str(w).contains("tier clamp"):
			has_clamp_warning = true
			break
	check(has_clamp_warning, "tier-clamp case should emit a 'tier clamp' warning")


# ---------------------------------------------------------------------------
# Validation edge cases
# ---------------------------------------------------------------------------

func test_invalid_floor_count() -> void:
	var req := DungeonGeneratorRequestV1.new()
	req.floor_count = 0
	req.entrance_tier = 1
	req.entrance_floor_index = 1
	req.seed = 1
	req.persist = false
	var result: DungeonGeneratorResultV1 = DungeonGeneratorV1.generate(req)
	check(result != null, "generate() with floor_count=0 should not return null")
	if result != null:
		check(not result.success, "floor_count=0 should fail")
		check(result.errors.size() > 0, "floor_count=0 should have errors")


func test_invalid_entrance_tier() -> void:
	var req := DungeonGeneratorRequestV1.new()
	req.floor_count = 1
	req.entrance_tier = 7
	req.entrance_floor_index = 1
	req.seed = 1
	req.persist = false
	var result: DungeonGeneratorResultV1 = DungeonGeneratorV1.generate(req)
	check(result != null, "generate() with entrance_tier=7 should not return null")
	if result != null:
		check(not result.success, "entrance_tier=7 should fail")
		check(result.errors.size() > 0, "entrance_tier=7 should have errors")


func test_invalid_entrance_floor_index() -> void:
	var req := DungeonGeneratorRequestV1.new()
	req.floor_count = 2
	req.entrance_tier = 1
	req.entrance_floor_index = 5  # out of range
	req.seed = 1
	req.persist = false
	var result: DungeonGeneratorResultV1 = DungeonGeneratorV1.generate(req)
	check(result != null, "generate() with out-of-range efi should not return null")
	if result != null:
		check(not result.success, "out-of-range entrance_floor_index should fail")
		check(result.errors.size() > 0, "out-of-range efi should have errors")
