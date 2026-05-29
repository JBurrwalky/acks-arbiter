extends "res://tests/test_suite_base.gd"

## Tests for DungeonVoxelSerializer — the adapter that converts
## DungeonGeneratorResultV1 output into the voxel-JSON shape consumed by
## VoxelMapData.from_dict().
##
## Reference: engine/subsystems/generation/dungeon_generator_v1/dungeon_voxel_serializer.gd
##
## All test dungeons use persist=false to avoid DB writes.


func run_all_tests() -> void:
	test_cells_non_empty_and_spans_three_levels()
	test_door_mapping()
	test_multi_floor_stairs()
	test_round_trip_through_voxel_map_data()
	test_lever_links()
	if not has_failures():
		print("DungeonVoxelSerializer: all tests passed.")


# ---------------------------------------------------------------------------
# Shared helper
# ---------------------------------------------------------------------------

## Returns a deterministic 3-floor generation result for most tests.
func _make_result(p_seed: int = 12345) -> DungeonGeneratorResultV1:
	var req := DungeonGeneratorRequestV1.new()
	req.entrance_tier = 1
	req.floor_count = 3
	req.entrance_floor_index = 1
	req.dungeon_type = "wizards_dungeon"
	req.dungeon_size = "medium"
	req.seed = p_seed
	req.persist = false
	return DungeonGeneratorV1.generate(req)


# ---------------------------------------------------------------------------
# Test 1: basic structure + 3-level coverage
# ---------------------------------------------------------------------------

## Verifies that to_voxel_dict() emits a non-empty cells array and that the
## cells span exactly 3 distinct level values (one per floor), with at least
## one cell present at each level.
func test_cells_non_empty_and_spans_three_levels() -> void:
	var result: DungeonGeneratorResultV1 = _make_result()
	if result == null or not result.success:
		check(false, "test_cells_non_empty_and_spans_three_levels: generation failed")
		return

	var dict: Dictionary = DungeonVoxelSerializer.to_voxel_dict(result)

	# Must have a cells array.
	check(dict.has("cells"), "output dict must have 'cells' key")
	var cells: Array = dict.get("cells", [])
	check(cells.size() > 0, "cells array must be non-empty")

	# Must have an entry dict with col/row/level keys.
	check(dict.has("entry"), "output dict must have 'entry' key")
	var entry: Dictionary = dict.get("entry", {})
	check(entry.has("col"), "'entry' must have 'col'")
	check(entry.has("row"), "'entry' must have 'row'")
	check(entry.has("level"), "'entry' must have 'level'")

	# Cells must span 3 distinct level values.
	var level_set: Dictionary = {}
	for c in cells:
		level_set[c["level"]] = true
	check(level_set.size() == 3,
		"expected 3 distinct levels in cells, got %d" % level_set.size())

	# At least one cell at each expected level (0, 1, 2 for a 3-floor dungeon).
	for expected_level in [0, 1, 2]:
		check(level_set.has(expected_level),
			"no cells found at level %d" % expected_level)


# ---------------------------------------------------------------------------
# Test 2: door mapping
# ---------------------------------------------------------------------------

## Verifies that door overlays are applied: at least one cell has a non-empty
## door_type, and any secret door maps to door_type=="secret" + door_detected==false.
## Tries a couple of seeds to increase the chance of finding secret doors.
func test_door_mapping() -> void:
	# Confirm at least one door exists (any seed on a medium dungeon will have doors).
	var result: DungeonGeneratorResultV1 = _make_result(12345)
	if result == null or not result.success:
		check(false, "test_door_mapping: generation failed for seed 12345")
		return

	var dict: Dictionary = DungeonVoxelSerializer.to_voxel_dict(result)
	var cells: Array = dict.get("cells", [])

	var found_any_door := false
	for c in cells:
		if c.get("door_type", "") != "":
			found_any_door = true
			break
	check(found_any_door, "expected at least one cell with a non-empty door_type")

	# Try a spread of seeds to find a secret door; tolerate absence gracefully.
	var found_secret_correct := false
	var found_any_secret := false
	for seed_val in [12345, 99, 777, 42, 8888]:
		var r2: DungeonGeneratorResultV1 = _make_result(seed_val)
		if r2 == null or not r2.success:
			continue
		var d2: Dictionary = DungeonVoxelSerializer.to_voxel_dict(r2)
		for c in d2.get("cells", []):
			if c.get("door_type", "") == "secret":
				found_any_secret = true
				# A secret door must have door_detected == false.
				if c.get("door_detected", true) == false:
					found_secret_correct = true
				else:
					check(false,
						"secret door at (%d,%d,%d) has door_detected=true (expected false)"
						% [c["col"], c["row"], c["level"]])

	# Only assert the door_detected invariant if we actually found a secret door.
	if found_any_secret:
		check(found_secret_correct,
			"found at least one secret door but none had door_detected==false")
	# If no secret door was found across all seeds, that is a tolerated absence —
	# the §8.1 generator distributes them probabilistically.


# ---------------------------------------------------------------------------
# Test 3: multi-floor stair targets
# ---------------------------------------------------------------------------

## Verifies that at least one stair cell has a feature starting with "stairs_"
## and a stair_target_level != -1 (i.e. the cross-floor connection is set).
func test_multi_floor_stairs() -> void:
	var result: DungeonGeneratorResultV1 = _make_result(12345)
	if result == null or not result.success:
		check(false, "test_multi_floor_stairs: generation failed")
		return

	var dict: Dictionary = DungeonVoxelSerializer.to_voxel_dict(result)
	var cells: Array = dict.get("cells", [])

	var found_stair_with_target := false
	for c in cells:
		var feat: String = c.get("feature", "")
		if feat.begins_with("stairs_"):
			if c.get("stair_target_level", -1) != -1:
				found_stair_with_target = true
				break

	check(found_stair_with_target,
		"expected at least one stair cell with stair_target_level != -1")


# ---------------------------------------------------------------------------
# Test 4: round-trip through VoxelMapData.from_dict
# ---------------------------------------------------------------------------

## The key schema-correctness test: serialise a generated dungeon and feed the
## dict to VoxelMapData.from_dict().  Verifies the result is non-null and has
## cells populated — i.e. the schema produced by DungeonVoxelSerializer is
## accepted without error by the runtime loader.
func test_round_trip_through_voxel_map_data() -> void:
	var result: DungeonGeneratorResultV1 = _make_result(12345)
	if result == null or not result.success:
		check(false, "test_round_trip_through_voxel_map_data: generation failed")
		return

	var dict: Dictionary = DungeonVoxelSerializer.to_voxel_dict(result)

	# VoxelMapData.from_dict is a static method that also calls detect_rooms().
	var vm: VoxelMapData = VoxelMapData.from_dict(dict)
	check(vm != null, "VoxelMapData.from_dict() returned null")
	if vm == null:
		return

	# The map should have explicitly stored cells.
	check(vm.cell_count() > 0,
		"VoxelMapData has no stored cells after round-trip (cell_count == 0)")

	# The entry position should have been applied.
	var entry_dict: Dictionary = dict.get("entry", {})
	if not entry_dict.is_empty():
		var expected_entry := Vector3i(
			int(entry_dict.get("col", 0)),
			int(entry_dict.get("row", 0)),
			int(entry_dict.get("level", 0))
		)
		check(vm.entry_pos == expected_entry,
			"entry_pos mismatch: expected %s got %s" % [str(expected_entry), str(vm.entry_pos)])

	# detect_rooms() should have run and found at least one room.
	check(vm.rooms.size() > 0,
		"VoxelMapData.rooms is empty after round-trip (detect_rooms() found nothing)")


# ---------------------------------------------------------------------------
# Test 5: lever_links
# ---------------------------------------------------------------------------

## If any portcullis with a wired lever exists in the generated dungeon, checks
## that the serializer emits a matching lever_links entry and mutates the lever
## cell to feature=="lever".  Tolerates absence (portcullis+lever is probabilistic).
func test_lever_links() -> void:
	# Try a spread of seeds to increase the chance of finding a wired portcullis.
	var found_portcullis_lever := false
	for seed_val in [12345, 42, 999, 3141, 7777]:
		var result: DungeonGeneratorResultV1 = _make_result(seed_val)
		if result == null or not result.success:
			continue

		# Collect all wired portcullises from the source.
		var wired_portcullises: Array = []
		for floor_layout: DungeonLayout in result.floors:
			var voxel_level: int = floor_layout.level_number - 1
			for door: DungeonDoorData in floor_layout.doors:
				if door.type == DungeonDoorData.TYPE_PORTCULLIS and \
						door.wired_lever_position != Vector2i(-1, -1):
					wired_portcullises.append({
						"lever": door.wired_lever_position,
						"target": door.position,
						"level": voxel_level,
					})

		if wired_portcullises.is_empty():
			continue
		found_portcullis_lever = true

		var dict: Dictionary = DungeonVoxelSerializer.to_voxel_dict(result)
		var lever_links: Array = dict.get("lever_links", [])
		var cells: Array = dict.get("cells", [])

		for wp in wired_portcullises:
			var lx: int = wp["lever"].x
			var ly: int = wp["lever"].y
			var tx: int = wp["target"].x
			var ty: int = wp["target"].y
			var lvl: int = wp["level"]

			# Check that a matching lever_links entry exists.
			var link_found := false
			for link in lever_links:
				var la: Array = link.get("lever", [])
				var ta: Array = link.get("target", [])
				if la.size() == 3 and ta.size() == 3:
					if la[0] == lx and la[1] == ly and la[2] == lvl and \
							ta[0] == tx and ta[1] == ty and ta[2] == lvl:
						link_found = true
						break
			check(link_found,
				"no lever_links entry for lever at (%d,%d,%d)->target(%d,%d,%d)"
					% [lx, ly, lvl, tx, ty, lvl])

			# Check that the lever cell has feature=="lever".
			var lever_cell_found := false
			for c in cells:
				if c["col"] == lx and c["row"] == ly and c["level"] == lvl:
					lever_cell_found = true
					check(c.get("feature", "") == "lever",
						"lever cell at (%d,%d,%d) has feature='%s', expected 'lever'"
							% [lx, ly, lvl, c.get("feature", "")])
					break
			check(lever_cell_found,
				"lever cell at (%d,%d,%d) not found in cells array" % [lx, ly, lvl])

		# One seed with wired portcullises is enough.
		break

	if not found_portcullis_lever:
		# Tolerated absence — portcullis+lever placement is probabilistic.
		print("[DungeonVoxelSerializer] test_lever_links: no wired portcullises found across tested seeds (tolerated).")
