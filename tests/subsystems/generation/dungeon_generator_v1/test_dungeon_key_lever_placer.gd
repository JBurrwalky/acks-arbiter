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
	# --- discovery-order placement (§10.2 rev 2026-06-10) ---
	test_place_series_doors_never_circular()
	test_place_secret_unlocked_blocking_stair_is_opened()
	test_place_secret_unlocked_optional_pocket_stays_secret()

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


## §10.2 discovery-order placement: two locked stone doors in SERIES must get
## keys that respect the dependency order — key 1 entrance-side of door 1, key
## 2 entrance-side of door 2 — so the solvability fixpoint always resolves.
## (The superseded outside-region model could cross-place them: key 1 behind
## door 2 AND key 2 behind door 1, an unsolvable circle.)
func test_place_series_doors_never_circular() -> void:
	# 10×1: entrance(0,0) corridor(1-2) [room0(3)] DOOR1(4) [room1(5,6)] DOOR2(7) [room2(8,9)]
	var layout: DungeonLayout = _make_open_corridor(10)
	layout.is_entrance_floor = true
	layout.entrance = Vector2i(0, 0)
	layout.level_number = 1
	_set_door_cell(layout, Vector2i(4, 0), DungeonDoorData.TYPE_LOCKED, DungeonDoorData.MATERIAL_STONE, false)
	_set_door_cell(layout, Vector2i(7, 0), DungeonDoorData.TYPE_LOCKED, DungeonDoorData.MATERIAL_STONE, false)
	var room0: DungeonRoomData = _make_room(0, [Vector2i(3, 0)])
	var room1: DungeonRoomData = _make_room(1, [Vector2i(5, 0), Vector2i(6, 0)])
	var room2: DungeonRoomData = _make_room(2, [Vector2i(8, 0), Vector2i(9, 0)])
	layout.get_cell_at(Vector2i(3, 0)).room_id = 0
	layout.get_cell_at(Vector2i(5, 0)).room_id = 1
	layout.get_cell_at(Vector2i(6, 0)).room_id = 1
	layout.get_cell_at(Vector2i(8, 0)).room_id = 2
	layout.get_cell_at(Vector2i(9, 0)).room_id = 2
	layout.rooms = [room0, room1, room2]
	var floors: Array[DungeonLayout] = [layout]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 48

	var keys: Array[KeyItemData] = DungeonKeyLeverPlacer.place(floors, 1, rng)

	check(keys.size() == 2, "Two locked stone doors should produce two keys; got %d" % keys.size())
	for k: KeyItemData in keys:
		if k.opens_door_position == Vector2i(4, 0):
			check(k.placed_in_room_id == 0,
				"Key for door 1 must be in room 0 (the only room before it); got room %d" % k.placed_in_room_id)
		elif k.opens_door_position == Vector2i(7, 0):
			check(k.placed_in_room_id == 0 or k.placed_in_room_id == 1,
				"Key for door 2 must be entrance-side of door 2 (room 0 or 1); got room %d" % k.placed_in_room_id)
	# The whole point: the solvability fixpoint must resolve the chain.
	var solv: Dictionary = DungeonNavigabilityValidator.validate_solvability(floors, keys, 1)
	check(solv["ok"], "Series-door layout must be solvable after placement: %s" % str(solv["failures"]))


## A secret+unlocked door (no key concept, model-impassable) that gates a STAIR
## must be opened by the coverage repair (is_secret cleared), or the dungeon
## can never pass §9.2.
func test_place_secret_unlocked_blocking_stair_is_opened() -> void:
	# 7×1: entrance(0,0) corridor(1,2) [room0(3)] SECRET-UNLOCKED(4) [room1(5)] stair(6)
	var layout: DungeonLayout = _make_open_corridor(7)
	layout.is_entrance_floor = true
	layout.entrance = Vector2i(0, 0)
	layout.level_number = 1
	_set_door_cell(layout, Vector2i(4, 0), DungeonDoorData.TYPE_UNLOCKED, DungeonDoorData.MATERIAL_WOOD_STANDARD, true)
	var room0: DungeonRoomData = _make_room(0, [Vector2i(3, 0)])
	var room1: DungeonRoomData = _make_room(1, [Vector2i(5, 0)])
	layout.get_cell_at(Vector2i(3, 0)).room_id = 0
	layout.get_cell_at(Vector2i(5, 0)).room_id = 1
	layout.rooms = [room0, room1]
	_set_stair_cell(layout, Vector2i(6, 0))
	var floors: Array[DungeonLayout] = [layout]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 49

	var keys: Array[KeyItemData] = DungeonKeyLeverPlacer.place(floors, 1, rng)

	check(keys.is_empty(), "Secret+unlocked door carries no key; got %d" % keys.size())
	check(not layout.doors[0].is_secret,
		"Secret+unlocked door gating a stair must have is_secret cleared by the coverage repair")
	var solv: Dictionary = DungeonNavigabilityValidator.validate_solvability(floors, keys, 1)
	check(solv["ok"], "Layout must be solvable after the secret-door repair: %s" % str(solv["failures"]))


## A secret+unlocked door guarding a room the BFS reaches ANOTHER way must be
## left secret — optional secret content survives the coverage repair.
func test_place_secret_unlocked_optional_pocket_stays_secret() -> void:
	# 7×2 grid. Row 0 is an open corridor (entrance at (0,0)). Room 1 spans
	# (5,1)-(6,1) with TWO ways in: a secret+unlocked door at (4,1) and a plain
	# open cell adjacency at (6,0)->(6,1). Room 0 at (3,1) keeps a candidate
	# room available.
	var layout: DungeonLayout = _make_open_grid(7, 2)
	layout.is_entrance_floor = true
	layout.entrance = Vector2i(0, 0)
	layout.level_number = 1
	# Row 1 starts as rock except the cells we open explicitly.
	for x: int in range(7):
		var cell: DungeonCellData = layout.get_cell_at(Vector2i(x, 1))
		cell.passable = false
		cell.terrain_feature = DungeonCellData.FEATURE_ROCK
		cell.blocks_los = true
	for pos: Vector2i in [Vector2i(3, 1), Vector2i(5, 1), Vector2i(6, 1)]:
		var cell: DungeonCellData = layout.get_cell_at(pos)
		cell.passable = true
		cell.terrain_feature = DungeonCellData.FEATURE_OPEN
		cell.blocks_los = false
	_set_door_cell(layout, Vector2i(4, 1), DungeonDoorData.TYPE_UNLOCKED, DungeonDoorData.MATERIAL_WOOD_STANDARD, true)
	var room0: DungeonRoomData = _make_room(0, [Vector2i(3, 1)])
	var room1: DungeonRoomData = _make_room(1, [Vector2i(5, 1), Vector2i(6, 1)])
	layout.get_cell_at(Vector2i(3, 1)).room_id = 0
	layout.get_cell_at(Vector2i(5, 1)).room_id = 1
	layout.get_cell_at(Vector2i(6, 1)).room_id = 1
	layout.rooms = [room0, room1]
	var floors: Array[DungeonLayout] = [layout]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 50

	var keys: Array[KeyItemData] = DungeonKeyLeverPlacer.place(floors, 1, rng)

	check(keys.is_empty(), "No gated doors here; got %d keys" % keys.size())
	check(layout.doors[0].is_secret,
		"Secret door to an otherwise-reachable room must STAY secret (optional content)")
	var solv: Dictionary = DungeonNavigabilityValidator.validate_solvability(floors, keys, 1)
	check(solv["ok"], "Loop layout must be solvable without touching the secret door: %s" % str(solv["failures"]))


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
	return _make_open_grid(width, 1)


## Create a W×H grid of passable open cells.
func _make_open_grid(width: int, height: int) -> DungeonLayout:
	var layout: DungeonLayout = DungeonLayout.new()
	layout.grid_width = width
	layout.grid_height = height
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


## Convert a cell to a down-stair and register the matching DungeonStairData.
func _set_stair_cell(layout: DungeonLayout, pos: Vector2i) -> void:
	var cell: DungeonCellData = layout.get_cell_at(pos)
	cell.terrain_feature = DungeonCellData.FEATURE_STAIRS_DOWN
	cell.passable = true
	cell.blocks_los = false
	var stair: DungeonStairData = DungeonStairData.new()
	stair.position = pos
	stair.direction = DungeonStairData.DIRECTION_DOWN
	layout.stairs.append(stair)


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
