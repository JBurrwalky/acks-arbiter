extends "res://tests/test_suite_base.gd"

## Tests for DungeonNavigabilityValidator.
##
## Constructs minimal hand-authored DungeonLayout objects to verify §9.1
## (validate_layout) and §9.2 (validate_solvability) behaviour.
##
## Reference: gdd-dungeon-generator-v1.md §9.


func run_all_tests() -> void:
	# --- validate_layout ---
	test_validate_layout_two_rooms_reachable()
	test_validate_layout_unreachable_room_detected()
	test_validate_layout_single_room_entrance_floor()
	test_validate_layout_door_cell_is_traversable()

	# --- validate_solvability ---
	test_validate_solvability_unlocked_door_passes()
	test_validate_solvability_locked_door_with_key_in_reachable_room_passes()
	test_validate_solvability_locked_door_without_key_fails()
	test_validate_solvability_secret_door_blocks()
	test_validate_solvability_portcullis_no_lever_passable()
	test_validate_solvability_portcullis_lever_reached_passable()
	test_validate_solvability_portcullis_lever_unreached_blocked()

	if not has_failures():
		print("DungeonNavigabilityValidator: all tests passed.")


# ===========================================================================
# validate_layout (§9.1)
# ===========================================================================

## Simple 5×1 layout: entrance at (0,0), corridor cells (0-4,0), two rooms.
## Room 0 occupies (1,0); room 1 occupies (3,0). Both should be reachable.
func test_validate_layout_two_rooms_reachable() -> void:
	var layout: DungeonLayout = _make_corridor_layout(5, 1)
	layout.is_entrance_floor = true
	layout.entrance = Vector2i(0, 0)

	var room0: DungeonRoomData = _make_room(0, [Vector2i(1, 0)])
	var room1: DungeonRoomData = _make_room(1, [Vector2i(3, 0)])
	layout.rooms = [room0, room1]

	# Mark room cells in the grid.
	layout.get_cell_at(Vector2i(1, 0)).room_id = 0
	layout.get_cell_at(Vector2i(3, 0)).room_id = 1

	var result: Dictionary = DungeonNavigabilityValidator.validate_layout(layout)
	check(result["ok"] == true,
		"Two-room corridor layout should be fully reachable; got: %s" % result["message"])
	check((result["unreachable_room_ids"] as Array).is_empty(),
		"unreachable_room_ids should be empty")


## Same layout but room 1 is walled off (cell (3,0) set to impassable rock).
## Room 1 should be flagged as unreachable.
func test_validate_layout_unreachable_room_detected() -> void:
	var layout: DungeonLayout = _make_corridor_layout(5, 1)
	layout.is_entrance_floor = true
	layout.entrance = Vector2i(0, 0)

	var room0: DungeonRoomData = _make_room(0, [Vector2i(1, 0)])
	var room1: DungeonRoomData = _make_room(1, [Vector2i(3, 0)])
	layout.rooms = [room0, room1]

	layout.get_cell_at(Vector2i(1, 0)).room_id = 0
	# Wall off room 1: set its cell to impassable rock.
	var walled: DungeonCellData = layout.get_cell_at(Vector2i(3, 0))
	walled.room_id = 1
	walled.passable = false
	walled.terrain_feature = DungeonCellData.FEATURE_ROCK
	# Also block the corridor cell before it so BFS cannot reach it.
	var blocker: DungeonCellData = layout.get_cell_at(Vector2i(2, 0))
	blocker.passable = false
	blocker.terrain_feature = DungeonCellData.FEATURE_WALL_STONE

	var result: Dictionary = DungeonNavigabilityValidator.validate_layout(layout)
	check(result["ok"] == false,
		"Walled-off room should make layout invalid")
	check((result["unreachable_room_ids"] as Array).has(1),
		"Room 1 should appear in unreachable_room_ids, got: %s" % str(result["unreachable_room_ids"]))


## Single-room entrance floor: room contains entrance cell directly.
func test_validate_layout_single_room_entrance_floor() -> void:
	var layout: DungeonLayout = _make_3x3_open_layout()
	layout.is_entrance_floor = true
	layout.entrance = Vector2i(1, 1)

	var room0: DungeonRoomData = _make_room(0, [Vector2i(1, 1), Vector2i(1, 0), Vector2i(0, 1)])
	layout.rooms = [room0]
	for rc: Vector2i in room0.cells:
		layout.get_cell_at(rc).room_id = 0

	var result: Dictionary = DungeonNavigabilityValidator.validate_layout(layout)
	check(result["ok"] == true,
		"Single-room entrance layout should pass; message: %s" % result["message"])


## A locked door cell (is_door() == true) should be traversable in §9.1 BFS
## regardless of its lock state, allowing access to the room beyond.
func test_validate_layout_door_cell_is_traversable() -> void:
	# Layout: [entrance]--[door]--[room0]  (3 cells, 1×3 corridor)
	var layout: DungeonLayout = _make_corridor_layout(3, 1)
	layout.is_entrance_floor = true
	layout.entrance = Vector2i(0, 0)

	# Cell (1,0) becomes a locked door.
	var door_cell: DungeonCellData = layout.get_cell_at(Vector2i(1, 0))
	door_cell.terrain_feature = DungeonCellData.FEATURE_DOOR_LOCKED
	door_cell.passable = false  # locked doors are not passable in runtime state

	# Room 0 is behind the door.
	var room0: DungeonRoomData = _make_room(0, [Vector2i(2, 0)])
	layout.rooms = [room0]
	layout.get_cell_at(Vector2i(2, 0)).room_id = 0

	var door_data: DungeonDoorData = DungeonDoorData.new()
	door_data.position = Vector2i(1, 0)
	door_data.type = DungeonDoorData.TYPE_LOCKED
	door_data.door_material = DungeonDoorData.MATERIAL_STONE
	layout.doors = [door_data]

	var result: Dictionary = DungeonNavigabilityValidator.validate_layout(layout)
	check(result["ok"] == true,
		"Door cell should be traversable in §9.1 regardless of lock; got: %s" % result["message"])


# ===========================================================================
# validate_solvability (§9.2)
# ===========================================================================

## 2-room layout, unlocked door between them. No keys needed. Should pass.
func test_validate_solvability_unlocked_door_passes() -> void:
	var layout: DungeonLayout = _make_two_room_locked_door_layout(DungeonDoorData.TYPE_UNLOCKED, DungeonDoorData.MATERIAL_WOOD_STANDARD)
	var keys: Array[KeyItemData] = []
	var result: Dictionary = DungeonNavigabilityValidator.validate_solvability([layout], keys, 1)
	check(result["ok"] == true,
		"Unlocked-door 2-room layout should be solvable; failures: %s" % str(result["failures"]))


## Locked stone door + matching key placed in the reachable entrance room. Should pass.
func test_validate_solvability_locked_door_with_key_in_reachable_room_passes() -> void:
	var layout: DungeonLayout = _make_two_room_locked_door_layout(DungeonDoorData.TYPE_LOCKED, DungeonDoorData.MATERIAL_STONE)

	# Key lives in room 0 (the entrance-side room, cells reachable from entrance).
	var k: KeyItemData = KeyItemData.new()
	k.id = "key_001"
	k.opens_door_floor_index = 1
	k.opens_door_position = Vector2i(2, 0)  # door position in the layout
	k.placed_on_floor_index = 1
	k.placed_in_room_id = 0  # room 0 is entrance-side
	k.placed_in = KeyItemData.PLACED_LOOSE

	var keys: Array[KeyItemData] = [k]
	var result: Dictionary = DungeonNavigabilityValidator.validate_solvability([layout], keys, 1)
	check(result["ok"] == true,
		"Locked door with reachable key should be solvable; failures: %s" % str(result["failures"]))


## Same layout but no key provided. The locked door should block room 1.
func test_validate_solvability_locked_door_without_key_fails() -> void:
	var layout: DungeonLayout = _make_two_room_locked_door_layout(DungeonDoorData.TYPE_LOCKED, DungeonDoorData.MATERIAL_STONE)
	var keys: Array[KeyItemData] = []
	var result: Dictionary = DungeonNavigabilityValidator.validate_solvability([layout], keys, 1)
	check(result["ok"] == false,
		"Locked door with no key should make layout unsolvable")
	check((result["failures"] as Array).size() > 0,
		"failures should be non-empty when room is blocked by locked door")


## Secret door should block even without a key requirement (conservative §9.2).
func test_validate_solvability_secret_door_blocks() -> void:
	var layout: DungeonLayout = _make_two_room_locked_door_layout(DungeonDoorData.TYPE_UNLOCKED, DungeonDoorData.MATERIAL_WOOD_STANDARD)
	# Mark door as secret.
	layout.doors[0].is_secret = true
	# Also update cell terrain.
	layout.get_cell_at(Vector2i(2, 0)).terrain_feature = DungeonCellData.FEATURE_DOOR_SECRET

	var keys: Array[KeyItemData] = []
	var result: Dictionary = DungeonNavigabilityValidator.validate_solvability([layout], keys, 1)
	check(result["ok"] == false,
		"Secret door should block in solvability BFS (conservative)")


## Portcullis with no wired lever: Force Portcullis always available -> passable.
func test_validate_solvability_portcullis_no_lever_passable() -> void:
	var layout: DungeonLayout = _make_two_room_locked_door_layout(DungeonDoorData.TYPE_PORTCULLIS, DungeonDoorData.MATERIAL_METAL)
	# Ensure wired_lever_position is the default (-1,-1).
	layout.doors[0].wired_lever_position = Vector2i(-1, -1)

	var keys: Array[KeyItemData] = []
	var result: Dictionary = DungeonNavigabilityValidator.validate_solvability([layout], keys, 1)
	check(result["ok"] == true,
		"Portcullis with no lever should be passable (Force Portcullis available); failures: %s" % str(result["failures"]))


## Portcullis with lever in entrance-side room (reachable) -> passable.
func test_validate_solvability_portcullis_lever_reached_passable() -> void:
	var layout: DungeonLayout = _make_two_room_locked_door_layout(DungeonDoorData.TYPE_PORTCULLIS, DungeonDoorData.MATERIAL_METAL)
	# Place lever at (1,0) — inside room 0 (entrance side, always reachable).
	layout.doors[0].wired_lever_position = Vector2i(1, 0)

	var keys: Array[KeyItemData] = []
	var result: Dictionary = DungeonNavigabilityValidator.validate_solvability([layout], keys, 1)
	check(result["ok"] == true,
		"Portcullis with lever in reachable room should be passable; failures: %s" % str(result["failures"]))


## Portcullis with lever in the BLOCKED side room -> lever unreachable -> blocked.
func test_validate_solvability_portcullis_lever_unreached_blocked() -> void:
	var layout: DungeonLayout = _make_two_room_locked_door_layout(DungeonDoorData.TYPE_PORTCULLIS, DungeonDoorData.MATERIAL_METAL)
	# Place lever at (3,0) — inside room 1 (behind the portcullis, not initially reachable).
	layout.doors[0].wired_lever_position = Vector2i(3, 0)

	var keys: Array[KeyItemData] = []
	var result: Dictionary = DungeonNavigabilityValidator.validate_solvability([layout], keys, 1)
	check(result["ok"] == false,
		"Portcullis with lever behind itself should be unsolvable")


# ===========================================================================
# Layout construction helpers
# ===========================================================================

## 1×N open corridor layout. Cells (0,0)..(width-1, 0) are all passable.
func _make_corridor_layout(width: int, height: int) -> DungeonLayout:
	var layout: DungeonLayout = DungeonLayout.new()
	layout.grid_width = width
	layout.grid_height = height
	layout.level_number = 1
	layout.cells = []
	for x: int in range(width):
		var col: Array = []
		for y: int in range(height):
			var cell: DungeonCellData = DungeonCellData.new()
			cell.terrain_feature = DungeonCellData.FEATURE_OPEN
			cell.passable = true
			cell.blocks_los = false
			cell.room_id = -1
			col.append(cell)
		layout.cells.append(col)
	return layout


## 3×3 fully open layout.
func _make_3x3_open_layout() -> DungeonLayout:
	return _make_corridor_layout(3, 3)


## 5×1 layout:
##  (0,0) open entrance
##  (1,0) open room0 cell
##  (2,0) door cell
##  (3,0) open room1 cell
##  (4,0) open
## Used by validate_solvability tests; parameterised on door type + material.
func _make_two_room_locked_door_layout(door_type: String, door_material: String) -> DungeonLayout:
	var layout: DungeonLayout = _make_corridor_layout(5, 1)
	layout.is_entrance_floor = true
	layout.entrance = Vector2i(0, 0)
	layout.level_number = 1

	# Door at (2,0).
	var door_cell: DungeonCellData = layout.get_cell_at(Vector2i(2, 0))
	door_cell.passable = false
	door_cell.terrain_feature = _door_feature_for_type(door_type)

	var door: DungeonDoorData = DungeonDoorData.new()
	door.position = Vector2i(2, 0)
	door.type = door_type
	door.door_material = door_material
	layout.doors = [door]

	# Room 0: cells (0,0) and (1,0) — entrance side.
	var room0: DungeonRoomData = _make_room(0, [Vector2i(0, 0), Vector2i(1, 0)])
	layout.get_cell_at(Vector2i(0, 0)).room_id = 0
	layout.get_cell_at(Vector2i(1, 0)).room_id = 0

	# Room 1: cells (3,0) and (4,0) — behind the door.
	var room1: DungeonRoomData = _make_room(1, [Vector2i(3, 0), Vector2i(4, 0)])
	layout.get_cell_at(Vector2i(3, 0)).room_id = 1
	layout.get_cell_at(Vector2i(4, 0)).room_id = 1

	layout.rooms = [room0, room1]
	return layout


func _door_feature_for_type(type: String) -> String:
	match type:
		DungeonDoorData.TYPE_LOCKED, DungeonDoorData.TYPE_TRAPPED:
			return DungeonCellData.FEATURE_DOOR_LOCKED
		DungeonDoorData.TYPE_PORTCULLIS:
			return DungeonCellData.FEATURE_PORTCULLIS
		_:
			return DungeonCellData.FEATURE_DOOR


func _make_room(id: int, cell_positions: Array) -> DungeonRoomData:
	var room: DungeonRoomData = DungeonRoomData.new()
	room.id = id
	for p: Vector2i in cell_positions:
		room.cells.append(p)
	if room.cells.size() > 0:
		room.center = room.cells[0]
	return room
