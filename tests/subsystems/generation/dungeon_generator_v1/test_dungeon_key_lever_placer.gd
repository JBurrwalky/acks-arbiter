extends "res://tests/test_suite_base.gd"

## Tests for DungeonKeyLeverPlacer.
##
## Constructs small hand-authored DungeonLayout stacks to verify §10 key
## and lever placement behaviour, including the §10.4 downgrade path.
##
## Reference: gdd-dungeon-generator-v1.md §10.


func run_all_tests() -> void:
	# --- place() ---
	test_place_locked_stone_door_creates_key()
	test_place_locked_wood_door_skipped()
	test_place_portcullis_sets_lever_position()
	test_place_10_4_downgrade_stone_door_no_outside_region()
	test_place_10_4_downgrade_portcullis_no_outside_region()
	test_place_key_lands_in_outside_region()

	if not has_failures():
		print("DungeonKeyLeverPlacer: all tests passed.")


# ===========================================================================
# place() tests
# ===========================================================================

## A locked stone door with a reachable outside region produces one KeyItemData.
func test_place_locked_stone_door_creates_key() -> void:
	# Layout: [entrance(0,0)] -- [room0(1,0)] -- [DOOR(2,0)] -- [room1(3,0)]
	# Room 0 is outside (reachable from entrance without crossing the door).
	# Room 1 is inside (behind the door).
	var floors: Array[DungeonLayout] = [_make_single_floor_with_stone_door()]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 42

	var keys: Array[KeyItemData] = DungeonKeyLeverPlacer.place(floors, 1, rng)

	check(keys.size() == 1,
		"One locked stone door should produce one key; got %d" % keys.size())
	if keys.size() >= 1:
		var k: KeyItemData = keys[0]
		check(k.opens_door_floor_index == 1,
			"Key should open door on floor 1; got %d" % k.opens_door_floor_index)
		check(k.opens_door_position == Vector2i(4, 0),
			"Key should open door at (4,0); got %s" % str(k.opens_door_position))
		check(k.placed_on_floor_index == 1,
			"Key placed_on_floor_index should be 1; got %d" % k.placed_on_floor_index)
		check(k.placed_in == KeyItemData.PLACED_LOOSE,
			"Key should start as PLACED_LOOSE before finalization")
		# Key must be placed in a room that is in the outside region (room 0, not room 1).
		check(k.placed_in_room_id == 0,
			"Key should be in room 0 (outside/entrance side); got room %d" % k.placed_in_room_id)


## A locked WOOD door is bashable — §10 preamble says no key needed. Placer
## must NOT generate a key for it.
func test_place_locked_wood_door_skipped() -> void:
	var floors: Array[DungeonLayout] = [_make_single_floor_with_wood_door()]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 43

	var keys: Array[KeyItemData] = DungeonKeyLeverPlacer.place(floors, 1, rng)

	check(keys.is_empty(),
		"Locked wood door (bashable) should produce no key; got %d" % keys.size())


## A portcullis with a valid outside region gets wired_lever_position set.
func test_place_portcullis_sets_lever_position() -> void:
	var floors: Array[DungeonLayout] = [_make_single_floor_with_portcullis()]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 44

	var keys: Array[KeyItemData] = DungeonKeyLeverPlacer.place(floors, 1, rng)

	# No keys for portcullises.
	check(keys.is_empty(),
		"Portcullis should produce no KeyItemData; got %d" % keys.size())

	var layout: DungeonLayout = floors[0]
	var door: DungeonDoorData = layout.doors[0]
	check(door.wired_lever_position != Vector2i(-1, -1),
		"Portcullis with outside region should have wired_lever_position set; got %s" % str(door.wired_lever_position))
	# The lever must be inside the outside region (room 0 — entrance side).
	# Room 0 now occupies only cell (3,0), so lever must be there.
	var lever: Vector2i = door.wired_lever_position
	check(lever == Vector2i(3, 0),
		"Lever should be placed in room 0 cell (3,0) (outside region); got %s" % str(lever))


## §10.4: When a locked stone door sits on the ONLY path (no outside region
## beyond the entrance), it downgrades to wood_standard and NO key is produced.
func test_place_10_4_downgrade_stone_door_no_outside_region() -> void:
	# Layout: [entrance(0,0)] == [DOOR(1,0)] -- [room1(2,0)]
	# There is no room outside (entrance cell has no room_id, entrance room filter
	# removes it). The door is on the only path from the entrance.
	var layout: DungeonLayout = _make_door_on_only_path_stone()
	var floors: Array[DungeonLayout] = [layout]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 45

	var keys: Array[KeyItemData] = DungeonKeyLeverPlacer.place(floors, 1, rng)

	check(keys.is_empty(),
		"§10.4 downgrade: no key should be produced when door has no outside region; got %d" % keys.size())
	check(layout.doors[0].door_material == DungeonDoorData.MATERIAL_WOOD_STANDARD,
		"§10.4 downgrade: door material should become wood_standard; got '%s'" % layout.doors[0].door_material)


## §10.4: Portcullis on the only path becomes TYPE_UNLOCKED with wood_standard material.
func test_place_10_4_downgrade_portcullis_no_outside_region() -> void:
	var layout: DungeonLayout = _make_portcullis_on_only_path()
	var floors: Array[DungeonLayout] = [layout]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 46

	var keys: Array[KeyItemData] = DungeonKeyLeverPlacer.place(floors, 1, rng)

	check(keys.is_empty(),
		"§10.4 downgrade: portcullis should produce no key; got %d" % keys.size())
	check(layout.doors[0].type == DungeonDoorData.TYPE_UNLOCKED,
		"§10.4 downgrade: portcullis type should become unlocked; got '%s'" % layout.doors[0].type)
	check(layout.doors[0].door_material == DungeonDoorData.MATERIAL_WOOD_STANDARD,
		"§10.4 downgrade: portcullis material should become wood_standard; got '%s'" % layout.doors[0].door_material)


## Key must be placed in a room that is fully within the outside region — not
## behind the door it unlocks.
func test_place_key_lands_in_outside_region() -> void:
	var layout: DungeonLayout = _make_single_floor_with_stone_door()
	var floors: Array[DungeonLayout] = [layout]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 47

	var keys: Array[KeyItemData] = DungeonKeyLeverPlacer.place(floors, 1, rng)
	check(keys.size() == 1, "Expected 1 key")
	if keys.size() >= 1:
		# Room 0 is entrance-side (outside); room 1 is behind the door (inside).
		# Key MUST be placed in room 0 (outside region), not room 1 (inside).
		check(keys[0].placed_in_room_id == 0,
			"Key must be placed in room 0 (outside region), not behind door; got room %d" % keys[0].placed_in_room_id)


# ===========================================================================
# Layout construction helpers
# ===========================================================================

## 7×1 layout:
##  (0,0) entrance corridor — NOT in any room; (1,0) also unassigned so
##          _find_entrance_room_id's neighbour check doesn't capture room 0.
##  (1,0) corridor cell (unassigned)
##  (2,0) corridor cell (unassigned)
##  (3,0) room 0 cell — in the OUTSIDE region (entrance-side of the door)
##  (4,0) locked STONE door
##  (5,0) room 1 cell — INSIDE region (behind the door)
##  (6,0) room 1 cell — INSIDE region
func _make_single_floor_with_stone_door() -> DungeonLayout:
	var layout: DungeonLayout = _make_open_corridor(7)
	layout.is_entrance_floor = true
	layout.entrance = Vector2i(0, 0)
	layout.level_number = 1

	_set_door_cell(layout, Vector2i(4, 0), DungeonDoorData.TYPE_LOCKED, DungeonDoorData.MATERIAL_STONE, false)

	var room0: DungeonRoomData = _make_room(0, [Vector2i(3, 0)])
	var room1: DungeonRoomData = _make_room(1, [Vector2i(5, 0), Vector2i(6, 0)])
	layout.get_cell_at(Vector2i(3, 0)).room_id = 0
	layout.get_cell_at(Vector2i(5, 0)).room_id = 1
	layout.get_cell_at(Vector2i(6, 0)).room_id = 1
	layout.rooms = [room0, room1]

	return layout


## 7×1 layout identical to above but door material is WOOD_STANDARD (bashable).
func _make_single_floor_with_wood_door() -> DungeonLayout:
	var layout: DungeonLayout = _make_open_corridor(7)
	layout.is_entrance_floor = true
	layout.entrance = Vector2i(0, 0)
	layout.level_number = 1

	_set_door_cell(layout, Vector2i(4, 0), DungeonDoorData.TYPE_LOCKED, DungeonDoorData.MATERIAL_WOOD_STANDARD, false)

	var room0: DungeonRoomData = _make_room(0, [Vector2i(3, 0)])
	var room1: DungeonRoomData = _make_room(1, [Vector2i(5, 0), Vector2i(6, 0)])
	layout.get_cell_at(Vector2i(3, 0)).room_id = 0
	layout.get_cell_at(Vector2i(5, 0)).room_id = 1
	layout.get_cell_at(Vector2i(6, 0)).room_id = 1
	layout.rooms = [room0, room1]

	return layout


## 7×1 layout with a portcullis at (4,0).
func _make_single_floor_with_portcullis() -> DungeonLayout:
	var layout: DungeonLayout = _make_open_corridor(7)
	layout.is_entrance_floor = true
	layout.entrance = Vector2i(0, 0)
	layout.level_number = 1

	_set_door_cell(layout, Vector2i(4, 0), DungeonDoorData.TYPE_PORTCULLIS, DungeonDoorData.MATERIAL_METAL, false)

	var room0: DungeonRoomData = _make_room(0, [Vector2i(3, 0)])
	var room1: DungeonRoomData = _make_room(1, [Vector2i(5, 0), Vector2i(6, 0)])
	layout.get_cell_at(Vector2i(3, 0)).room_id = 0
	layout.get_cell_at(Vector2i(5, 0)).room_id = 1
	layout.get_cell_at(Vector2i(6, 0)).room_id = 1
	layout.rooms = [room0, room1]

	return layout


## 3×1 layout for §10.4 downgrade tests (stone door, no outside-region room):
##  (0,0) entrance — NOT assigned to a room (no outside room to place key)
##  (1,0) STONE locked door
##  (2,0) room 1 (inside / behind door)
## The BFS from entrance can only expand to cell (0,0) before hitting the door.
## No room is entirely within that trivial outside region.
func _make_door_on_only_path_stone() -> DungeonLayout:
	var layout: DungeonLayout = _make_open_corridor(3)
	layout.is_entrance_floor = true
	layout.entrance = Vector2i(0, 0)
	layout.level_number = 1

	# entrance cell not assigned to any room.
	_set_door_cell(layout, Vector2i(1, 0), DungeonDoorData.TYPE_LOCKED, DungeonDoorData.MATERIAL_STONE, false)

	var room1: DungeonRoomData = _make_room(1, [Vector2i(2, 0)])
	layout.get_cell_at(Vector2i(2, 0)).room_id = 1
	layout.rooms = [room1]

	return layout


## Same geometry but portcullis instead of locked door.
func _make_portcullis_on_only_path() -> DungeonLayout:
	var layout: DungeonLayout = _make_open_corridor(3)
	layout.is_entrance_floor = true
	layout.entrance = Vector2i(0, 0)
	layout.level_number = 1

	_set_door_cell(layout, Vector2i(1, 0), DungeonDoorData.TYPE_PORTCULLIS, DungeonDoorData.MATERIAL_METAL, false)

	var room1: DungeonRoomData = _make_room(1, [Vector2i(2, 0)])
	layout.get_cell_at(Vector2i(2, 0)).room_id = 1
	layout.rooms = [room1]

	return layout


# ---------------------------------------------------------------------------
# Primitives
# ---------------------------------------------------------------------------

## Create a 1×N passable open corridor (y=0 throughout).
func _make_open_corridor(width: int) -> DungeonLayout:
	var layout: DungeonLayout = DungeonLayout.new()
	layout.grid_width = width
	layout.grid_height = 1
	layout.cells = []
	for x: int in range(width):
		var col: Array = []
		var cell: DungeonCellData = DungeonCellData.new()
		cell.terrain_feature = DungeonCellData.FEATURE_OPEN
		cell.passable = true
		cell.blocks_los = false
		cell.room_id = -1
		col.append(cell)
		layout.cells.append(col)
	return layout


## Convert a cell in the layout to a door, add DoorData to layout.doors.
func _set_door_cell(
		layout: DungeonLayout,
		pos: Vector2i,
		door_type: String,
		door_material: String,
		is_secret: bool) -> void:
	var cell: DungeonCellData = layout.get_cell_at(pos)
	cell.passable = false  # doors block initial passable flag
	match door_type:
		DungeonDoorData.TYPE_PORTCULLIS:
			cell.terrain_feature = DungeonCellData.FEATURE_PORTCULLIS
		DungeonDoorData.TYPE_LOCKED, DungeonDoorData.TYPE_TRAPPED:
			cell.terrain_feature = DungeonCellData.FEATURE_DOOR_LOCKED
		_:
			cell.terrain_feature = DungeonCellData.FEATURE_DOOR

	var door: DungeonDoorData = DungeonDoorData.new()
	door.position = pos
	door.type = door_type
	door.door_material = door_material
	door.is_secret = is_secret
	if layout.doors == null:
		layout.doors = []
	layout.doors.append(door)


func _make_room(id: int, cell_positions: Array) -> DungeonRoomData:
	var room: DungeonRoomData = DungeonRoomData.new()
	room.id = id
	for p: Vector2i in cell_positions:
		room.cells.append(p)
	if room.cells.size() > 0:
		room.center = room.cells[0]
	return room
