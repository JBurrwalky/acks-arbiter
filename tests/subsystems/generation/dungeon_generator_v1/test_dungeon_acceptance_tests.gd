extends "res://tests/test_suite_base.gd"

## Tests for DungeonAcceptanceTests.run() (gdd-dungeon-generator-v1.md §14).
##
## Hand-builds minimal DungeonGeneratorResultV1 objects to exercise each hard
## and soft check, then verifies the return Dictionary shape and logic.


func run_all_tests() -> void:
	test_return_dictionary_has_required_keys()
	test_empty_result_hard_passes()
	test_hard_fail_locked_door_no_key_unbashable()
	test_locked_bashable_door_passes_without_key()
	test_locked_door_with_key_passes()
	test_hard_fail_trap_placeholder_missing_secret_door()
	test_trap_placeholder_with_secret_locked_door_passes()
	test_hard_fail_unique_placeholder_missing_monster_group()
	test_unique_placeholder_with_group_passes()
	test_portcullis_without_lever_is_soft_warning_not_hard_fail()
	test_placeholder_counts_are_correct()
	test_xp_gp_ratio_per_floor_length_matches_floor_count()

	if not has_failures():
		print("DungeonAcceptanceTests: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Build a minimal result with one floor containing the supplied rooms and doors.
## key_items defaults to empty; pass override_key_items to supply keys.
func _make_result(
		rooms: Array[DungeonRoomData],
		doors: Array[DungeonDoorData],
		groups: Array[MonsterGroupData] = [],
		hoards: Array[TreasureHoardData] = [],
		key_items: Array[KeyItemData] = []) -> DungeonGeneratorResultV1:

	var floor := DungeonLayout.new()
	floor.level_number = 1
	floor.floor_tier = 1
	floor.rooms = rooms
	floor.doors = doors
	floor.monster_groups = groups
	floor.treasure_hoards = hoards

	var result := DungeonGeneratorResultV1.new()
	result.success = true
	result.floors.append(floor)
	result.key_items = key_items
	return result


## Build a DungeonDoorData with specific type, material, and position.
func _make_door(
		pos: Vector2i,
		type: String,
		material: String,
		is_secret: bool = false) -> DungeonDoorData:
	var door := DungeonDoorData.new()
	door.position = pos
	door.type = type
	door.door_material = material
	door.is_secret = is_secret
	return door


## Build a DungeonRoomData with a specific contents_kind, group_id, and doors.
func _make_room(
		id: int,
		kind: String,
		group_id: String = "",
		room_doors: Array[DungeonDoorData] = []) -> DungeonRoomData:
	var room := DungeonRoomData.new()
	room.id = id
	room.contents_kind = kind
	room.monster_group_id = group_id
	room.doors = room_doors
	return room


## Build a KeyItem that opens a door at the given floor_index and position.
func _make_key(floor_index: int, pos: Vector2i) -> KeyItemData:
	var ki := KeyItemData.new()
	ki.opens_door_floor_index = floor_index
	ki.opens_door_position = pos
	ki.placed_in = KeyItemData.PLACED_LOOSE
	ki.placed_in_room_id = 0
	ki.placed_on_floor_index = floor_index
	return ki


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

## The return dictionary must always contain all 5 required keys.
func test_return_dictionary_has_required_keys() -> void:
	var result := DungeonGeneratorResultV1.new()
	result.success = true
	var report: Dictionary = DungeonAcceptanceTests.run(result)

	check(report.has("hard_pass"),              "report must have 'hard_pass'")
	check(report.has("hard_failures"),          "report must have 'hard_failures'")
	check(report.has("soft_warnings"),          "report must have 'soft_warnings'")
	check(report.has("placeholder_counts"),     "report must have 'placeholder_counts'")
	check(report.has("xp_gp_ratio_per_floor"),  "report must have 'xp_gp_ratio_per_floor'")


## A result with no floors and no key_items should pass hard tests.
func test_empty_result_hard_passes() -> void:
	var result := DungeonGeneratorResultV1.new()
	result.success = true
	var report: Dictionary = DungeonAcceptanceTests.run(result)
	check(report["hard_pass"] == true, "empty result should hard_pass")
	check((report["hard_failures"] as Array).is_empty(),
		"empty result should have no hard_failures")


## A locked metal door (unbashable) with no KeyItem is a hard failure.
func test_hard_fail_locked_door_no_key_unbashable() -> void:
	var pos := Vector2i(5, 5)
	var door := _make_door(pos, DungeonDoorData.TYPE_LOCKED, DungeonDoorData.MATERIAL_METAL)
	var room := _make_room(0, "empty")
	var result := _make_result([room], [door])
	var report: Dictionary = DungeonAcceptanceTests.run(result)

	check(report["hard_pass"] == false,
		"locked metal door with no key should fail")
	check((report["hard_failures"] as Array).size() >= 1,
		"should have at least one hard failure entry")


## A locked wood_standard door (bashable) without a key should still pass.
func test_locked_bashable_door_passes_without_key() -> void:
	var pos := Vector2i(3, 3)
	var door := _make_door(pos, DungeonDoorData.TYPE_LOCKED, DungeonDoorData.MATERIAL_WOOD_STANDARD)
	var room := _make_room(0, "empty")
	var result := _make_result([room], [door])
	var report: Dictionary = DungeonAcceptanceTests.run(result)

	check(report["hard_pass"] == true,
		"locked wood_standard door without key should pass (bashable)")


## A locked metal door WITH a matching KeyItem should pass test 4.
func test_locked_door_with_key_passes() -> void:
	var pos := Vector2i(7, 7)
	var door := _make_door(pos, DungeonDoorData.TYPE_LOCKED, DungeonDoorData.MATERIAL_STONE)
	var room := _make_room(0, "empty")
	var key := _make_key(1, pos)
	var result := _make_result([room], [door], [], [], [key])
	var report: Dictionary = DungeonAcceptanceTests.run(result)

	check(report["hard_pass"] == true,
		"locked stone door with a matching key should pass")


## A trap_placeholder room with no secret+locked/trapped door is a hard failure.
func test_hard_fail_trap_placeholder_missing_secret_door() -> void:
	# Provide a non-secret unlocked door — should fail test 6.
	var door := _make_door(Vector2i(2, 2), DungeonDoorData.TYPE_UNLOCKED, DungeonDoorData.MATERIAL_WOOD_STANDARD)
	var room := _make_room(0, "trap_placeholder", "", [door])
	var result := _make_result([room], [door])
	var report: Dictionary = DungeonAcceptanceTests.run(result)

	check(report["hard_pass"] == false,
		"trap_placeholder with only a non-secret door should fail")


## A trap_placeholder room with exactly one secret+locked door should pass test 6.
func test_trap_placeholder_with_secret_locked_door_passes() -> void:
	var door := _make_door(
		Vector2i(4, 4), DungeonDoorData.TYPE_LOCKED, DungeonDoorData.MATERIAL_WOOD_STANDARD, true)
	# Also supply a matching key so test 4 doesn't interfere (locked wood is bashable — but
	# to be safe, use wood_standard which is bashable and won't trigger test 4).
	var room := _make_room(0, "trap_placeholder", "", [door])
	var result := _make_result([room], [door])
	var report: Dictionary = DungeonAcceptanceTests.run(result)

	check(report["hard_pass"] == true,
		"trap_placeholder with one secret+locked bashable door should pass")


## A unique_placeholder room with empty monster_group_id is a hard failure.
func test_hard_fail_unique_placeholder_missing_monster_group() -> void:
	var room := _make_room(0, "unique_placeholder", "")
	var result := _make_result([room], [])
	var report: Dictionary = DungeonAcceptanceTests.run(result)

	check(report["hard_pass"] == false,
		"unique_placeholder without monster_group_id should fail")


## A unique_placeholder room with a non-empty monster_group_id should pass test 7.
func test_unique_placeholder_with_group_passes() -> void:
	var room := _make_room(0, "unique_placeholder", "some-uuid-123")
	var result := _make_result([room], [])
	var report: Dictionary = DungeonAcceptanceTests.run(result)

	check(report["hard_pass"] == true,
		"unique_placeholder with monster_group_id should pass")


## A portcullis without a wired lever produces a soft warning, NOT a hard failure.
func test_portcullis_without_lever_is_soft_warning_not_hard_fail() -> void:
	var door := DungeonDoorData.new()
	door.position = Vector2i(9, 9)
	door.type = DungeonDoorData.TYPE_PORTCULLIS
	door.door_material = DungeonDoorData.MATERIAL_METAL
	door.wired_lever_position = Vector2i(-1, -1)  # no lever

	var room := _make_room(0, "empty")
	var result := _make_result([room], [door])
	var report: Dictionary = DungeonAcceptanceTests.run(result)

	check(report["hard_pass"] == true,
		"portcullis without lever should NOT be a hard failure")
	var soft: Array = report["soft_warnings"]
	var has_portcullis_warning: bool = false
	for w in soft:
		if "portcullis" in str(w):
			has_portcullis_warning = true
	check(has_portcullis_warning,
		"portcullis without lever should produce a soft warning")


## placeholder_counts entries should accurately count rooms and doors.
func test_placeholder_counts_are_correct() -> void:
	# Two trap rooms, one unique room, one TRAPPED door, no magic item placeholders.
	var trap1 := _make_room(0, "trap_placeholder", "")
	var trap2 := _make_room(1, "trap_placeholder", "")
	var unique1 := _make_room(2, "unique_placeholder", "grp-id-001")

	var trapped_door := DungeonDoorData.new()
	trapped_door.position = Vector2i(1, 1)
	trapped_door.type = DungeonDoorData.TYPE_TRAPPED
	trapped_door.door_material = DungeonDoorData.MATERIAL_WOOD_STANDARD

	# Provide a secret+locked door for each trap room so test 6 passes.
	var sd1 := _make_door(Vector2i(2, 2), DungeonDoorData.TYPE_LOCKED, DungeonDoorData.MATERIAL_WOOD_STANDARD, true)
	var sd2 := _make_door(Vector2i(3, 3), DungeonDoorData.TYPE_LOCKED, DungeonDoorData.MATERIAL_WOOD_STANDARD, true)
	trap1.doors = [sd1]
	trap2.doors = [sd2]

	var rooms: Array[DungeonRoomData] = [trap1, trap2, unique1]
	var doors: Array[DungeonDoorData] = [trapped_door, sd1, sd2]
	var result := _make_result(rooms, doors)
	var report: Dictionary = DungeonAcceptanceTests.run(result)

	var pc: Dictionary = report["placeholder_counts"]
	check(pc.has("trap_placeholder"),       "placeholder_counts must have 'trap_placeholder'")
	check(pc.has("unique_placeholder"),     "placeholder_counts must have 'unique_placeholder'")
	check(pc.has("trapped_door"),           "placeholder_counts must have 'trapped_door'")
	check(pc.has("magic_item_placeholder"), "placeholder_counts must have 'magic_item_placeholder'")
	check(pc["trap_placeholder"] == 2,
		"expected 2 trap_placeholder rooms, got %d" % pc["trap_placeholder"])
	check(pc["unique_placeholder"] == 1,
		"expected 1 unique_placeholder room, got %d" % pc["unique_placeholder"])
	check(pc["trapped_door"] == 1,
		"expected 1 trapped door, got %d" % pc["trapped_door"])
	check(pc["magic_item_placeholder"] == 0,
		"expected 0 magic_item_placeholder, got %d" % pc["magic_item_placeholder"])


## xp_gp_ratio_per_floor length matches the number of floors.
func test_xp_gp_ratio_per_floor_length_matches_floor_count() -> void:
	# Two-floor result.
	var floor_a := DungeonLayout.new()
	floor_a.level_number = 1
	floor_a.floor_tier = 1

	var floor_b := DungeonLayout.new()
	floor_b.level_number = 2
	floor_b.floor_tier = 2

	var result := DungeonGeneratorResultV1.new()
	result.success = true
	result.floors.append(floor_a)
	result.floors.append(floor_b)

	var report: Dictionary = DungeonAcceptanceTests.run(result)
	var ratios: Array = report["xp_gp_ratio_per_floor"]
	check(ratios.size() == 2,
		"xp_gp_ratio_per_floor length should equal floor count (2), got %d" % ratios.size())
