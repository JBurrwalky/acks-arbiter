extends "res://tests/test_suite_base.gd"

## Round-trip persistence tests for DungeonGeneratorRepository.
##
## Generates real layouts via DungeonLayoutGenerator, persists them, reloads,
## and asserts structural equality (metadata + full cell grid + rooms + doors
## + stairs). The dungeon-generator tables are self-contained (no campaign_id
## FK), so no campaign fixture is needed — just a unique dungeon_id.


func run_all_tests() -> void:
	test_single_floor_roundtrip()
	test_multi_floor_roundtrip()
	test_get_floor_by_id()
	test_list_floors_metadata()
	test_resave_is_idempotent()
	if not has_failures():
		print("DungeonRepositoryRoundtrip: all tests passed.")


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_single_floor_roundtrip() -> void:
	var dungeon_id := _unique_id("rt_single")
	var layout := _gen("small", 4242, 3, 1, true)
	var ok := DungeonGeneratorRepository.insert_dungeon_layout(dungeon_id, [layout])
	check(ok, "insert_dungeon_layout should succeed")
	var loaded := DungeonGeneratorRepository.get_dungeon_layout(dungeon_id)
	check(loaded.size() == 1, "should reload exactly 1 floor, got %d" % loaded.size())
	if loaded.size() == 1:
		_assert_layouts_equal(layout, loaded[0])
	DungeonGeneratorRepository.delete_dungeon_layout(dungeon_id)


func test_multi_floor_roundtrip() -> void:
	# Three floors with distinct tiers + level numbers, like a real DG-V1.D dungeon.
	var dungeon_id := _unique_id("rt_multi")
	var f1 := _gen("small", 100, 1, 1, true)
	var f2 := _gen("small", 200, 2, 2, false)
	var f3 := _gen("small", 300, 3, 3, false)
	var ok := DungeonGeneratorRepository.insert_dungeon_layout(dungeon_id, [f1, f2, f3])
	check(ok, "multi-floor insert should succeed")
	var loaded := DungeonGeneratorRepository.get_dungeon_layout(dungeon_id)
	check(loaded.size() == 3, "should reload 3 floors, got %d" % loaded.size())
	if loaded.size() == 3:
		# Floors come back ordered by floor_index.
		check(loaded[0].level_number == 1, "floor 0 level_number should be 1")
		check(loaded[1].level_number == 2, "floor 1 level_number should be 2")
		check(loaded[2].level_number == 3, "floor 2 level_number should be 3")
		check(loaded[0].floor_tier == 1, "floor 0 tier should be 1")
		check(loaded[2].floor_tier == 3, "floor 2 tier should be 3")
		check(loaded[0].is_entrance_floor, "floor 0 should be entrance floor")
		check(not loaded[1].is_entrance_floor, "floor 1 should NOT be entrance floor")
		_assert_layouts_equal(f2, loaded[1])
	DungeonGeneratorRepository.delete_dungeon_layout(dungeon_id)


func test_get_floor_by_id() -> void:
	var dungeon_id := _unique_id("rt_floorid")
	var layout := _gen("lair", 55, 2, 1, true)
	DungeonGeneratorRepository.insert_dungeon_layout(dungeon_id, [layout])
	var metas := DungeonGeneratorRepository.list_floors(dungeon_id)
	check(metas.size() == 1, "list_floors should return 1 meta")
	if metas.size() == 1:
		var floor_id := str(metas[0]["id"])
		var l2 := DungeonGeneratorRepository.get_floor(floor_id)
		check(l2 != null, "get_floor should return a layout")
		if l2 != null:
			_assert_layouts_equal(layout, l2)
	DungeonGeneratorRepository.delete_dungeon_layout(dungeon_id)


func test_list_floors_metadata() -> void:
	var dungeon_id := _unique_id("rt_list")
	var f1 := _gen("lair", 11, 1, 1, true)
	var f2 := _gen("lair", 22, 2, 2, false)
	DungeonGeneratorRepository.insert_dungeon_layout(dungeon_id, [f1, f2])
	var metas := DungeonGeneratorRepository.list_floors(dungeon_id)
	check(metas.size() == 2, "should list 2 floor metas, got %d" % metas.size())
	if metas.size() == 2:
		check(int(metas[0]["floor_index"]) == 1, "first meta floor_index 1")
		check(int(metas[1]["floor_index"]) == 2, "second meta floor_index 2")
		check(int(metas[0]["grid_width"]) == 21, "lair grid_width 21")
	DungeonGeneratorRepository.delete_dungeon_layout(dungeon_id)


func test_resave_is_idempotent() -> void:
	# Re-saving the same dungeon_id should replace, not accumulate.
	var dungeon_id := _unique_id("rt_resave")
	var layout := _gen("small", 9, 1, 1, true)
	DungeonGeneratorRepository.insert_dungeon_layout(dungeon_id, [layout])
	var first_room_count := _count_rows("dungeon_rooms", dungeon_id)
	# Save again.
	DungeonGeneratorRepository.insert_dungeon_layout(dungeon_id, [layout])
	var second_room_count := _count_rows("dungeon_rooms", dungeon_id)
	check(first_room_count == second_room_count,
		"re-save should not accumulate rows: %d vs %d" % [first_room_count, second_room_count])
	check(_count_rows("dungeon_floors", dungeon_id) == 1,
		"should still be exactly 1 floor after re-save")
	DungeonGeneratorRepository.delete_dungeon_layout(dungeon_id)


# ---------------------------------------------------------------------------
# Structural equality
# ---------------------------------------------------------------------------

func _assert_layouts_equal(a: DungeonLayout, b: DungeonLayout) -> void:
	check(a.grid_width == b.grid_width, "grid_width: %d vs %d" % [a.grid_width, b.grid_width])
	check(a.grid_height == b.grid_height, "grid_height mismatch")
	check(a.dungeon_type == b.dungeon_type, "dungeon_type mismatch")
	check(a.dungeon_size == b.dungeon_size, "dungeon_size mismatch")
	check(a.structure_type == b.structure_type, "structure_type mismatch")
	check(a.level_number == b.level_number, "level_number mismatch")
	check(a.floor_tier == b.floor_tier, "floor_tier mismatch")
	check(a.is_entrance_floor == b.is_entrance_floor, "is_entrance_floor mismatch")
	check(a.entrance == b.entrance, "entrance %s vs %s" % [a.entrance, b.entrance])
	check(a.generation_seed == b.generation_seed, "generation_seed mismatch")

	# Cells — full grid comparison.
	var cell_mismatches := 0
	for x in a.grid_width:
		for y in a.grid_height:
			var ca: DungeonCellData = a.cells[x][y]
			var cb: DungeonCellData = b.cells[x][y]
			if (ca.terrain_feature != cb.terrain_feature
					or ca.passable != cb.passable
					or ca.blocks_los != cb.blocks_los
					or ca.door_state != cb.door_state
					or ca.door_detected != cb.door_detected
					or ca.room_id != cb.room_id
					or ca.is_corridor != cb.is_corridor
					or ca.elevation != cb.elevation):
				cell_mismatches += 1
	check(cell_mismatches == 0, "cell grid mismatch count: %d" % cell_mismatches)

	# Rooms — match by id.
	check(a.rooms.size() == b.rooms.size(), "room count: %d vs %d" % [a.rooms.size(), b.rooms.size()])
	var b_rooms_by_id: Dictionary = {}
	for r in b.rooms:
		b_rooms_by_id[r.id] = r
	for ra in a.rooms:
		check(b_rooms_by_id.has(ra.id), "room id %d missing after reload" % ra.id)
		if b_rooms_by_id.has(ra.id):
			var rb: DungeonRoomData = b_rooms_by_id[ra.id]
			check(ra.bounds == rb.bounds, "room %d bounds %s vs %s" % [ra.id, ra.bounds, rb.bounds])
			check(ra.area_sqft == rb.area_sqft, "room %d area mismatch" % ra.id)
			check(ra.center == rb.center, "room %d center mismatch" % ra.id)
			check(ra.original_purpose == rb.original_purpose, "room %d original_purpose mismatch" % ra.id)
			check(ra.contents_kind == rb.contents_kind, "room %d contents_kind mismatch" % ra.id)
			check(ra.cells.size() == rb.cells.size(), "room %d cell count mismatch" % ra.id)

	# Doors — match by position.
	check(a.doors.size() == b.doors.size(), "door count: %d vs %d" % [a.doors.size(), b.doors.size()])
	var b_doors_by_pos: Dictionary = {}
	for d in b.doors:
		b_doors_by_pos[d.position] = d
	for da in a.doors:
		check(b_doors_by_pos.has(da.position), "door at %s missing after reload" % da.position)
		if b_doors_by_pos.has(da.position):
			var db_door: DungeonDoorData = b_doors_by_pos[da.position]
			check(da.type == db_door.type, "door %s type %s vs %s" % [da.position, da.type, db_door.type])
			check(da.is_secret == db_door.is_secret, "door %s is_secret mismatch" % da.position)
			check(da.door_material == db_door.door_material, "door %s material %s vs %s" % [da.position, da.door_material, db_door.door_material])
			check(da.is_evil == db_door.is_evil, "door %s is_evil mismatch" % da.position)
			check(da.connects == db_door.connects, "door %s connects %s vs %s" % [da.position, da.connects, db_door.connects])

	# Stairs — match by position+direction.
	check(a.stairs.size() == b.stairs.size(), "stair count: %d vs %d" % [a.stairs.size(), b.stairs.size()])
	var b_stair_keys: Dictionary = {}
	for s in b.stairs:
		b_stair_keys["%s_%s" % [s.position, s.direction]] = s
	for sa in a.stairs:
		var key := "%s_%s" % [sa.position, sa.direction]
		check(b_stair_keys.has(key), "stair %s (%s) missing after reload" % [sa.position, sa.direction])


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _gen(size: String, seed: int, tier: int, level: int, entrance: bool) -> DungeonLayout:
	var req := DungeonLayoutRequest.new()
	req.dungeon_type = "wizards_dungeon"
	req.dungeon_size = size
	req.seed = seed
	req.floor_tier = tier
	req.level_number = level
	req.stairs_up = 1
	req.stairs_down = 1
	req.is_entrance_floor = entrance
	return DungeonLayoutGenerator.generate(req)


func _unique_id(prefix: String) -> String:
	return "test_dg_%s_%d" % [prefix, randi()]


func _count_rows(table: String, dungeon_id: String) -> int:
	if not CampaignRepository.db.query_with_bindings(
			"SELECT COUNT(*) AS n FROM %s WHERE dungeon_id = ?" % table, [dungeon_id]):
		return -1
	return int(CampaignRepository.db.query_result[0]["n"])
