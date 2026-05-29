extends "res://tests/test_suite_base.gd"

## Unit tests for DungeonLayoutRasterizer — the geometric-plan → cell-grid
## conversion layer.


func run_all_tests() -> void:
	test_rasterize_produces_correct_grid_shape()
	test_rasterize_room_interior_cells()
	test_rasterize_walls_appear_around_open_areas()
	test_rasterize_far_cells_stay_as_rock()
	test_rasterize_corridor_cells()
	test_rasterize_doors_have_correct_features()
	test_rasterize_secret_overlay_uses_secret_feature()
	test_rasterize_portcullis_blocks_movement_not_los()
	test_rasterize_stairs()
	test_build_room_data_preserves_bounds_and_cells()
	test_build_door_data_preserves_type_and_connections()
	test_build_door_data_preserves_is_secret_and_material()
	test_attach_doors_to_rooms_populates_room_door_lists()
	if not has_failures():
		print("DungeonLayoutRasterizer: all tests passed.")


# ---------------------------------------------------------------------------
# Grid shape
# ---------------------------------------------------------------------------

func test_rasterize_produces_correct_grid_shape() -> void:
	var composer := _composer_with_one_room(11, 7, Rect2i(2, 2, 3, 3))
	var cells: Array[Array] = DungeonLayoutRasterizer.rasterize_cells(composer)
	check(cells.size() == 11, "outer size: expected 11, got %d" % cells.size())
	check(cells[0].size() == 7, "inner size: expected 7, got %d" % cells[0].size())
	check(cells[0][0] is DungeonCellData, "each entry should be a DungeonCellData")


# ---------------------------------------------------------------------------
# Room interiors
# ---------------------------------------------------------------------------

func test_rasterize_room_interior_cells() -> void:
	var composer := _composer_with_one_room(11, 7, Rect2i(2, 2, 3, 3))
	var cells: Array[Array] = DungeonLayoutRasterizer.rasterize_cells(composer)
	for x in range(2, 5):
		for y in range(2, 5):
			var c: DungeonCellData = cells[x][y]
			check(c.terrain_feature == DungeonCellData.FEATURE_OPEN,
				"room interior (%d,%d) should be FEATURE_OPEN, got %s"
					% [x, y, c.terrain_feature])
			check(c.passable, "room interior (%d,%d) should be passable" % [x, y])
			check(c.room_id == 0, "room interior (%d,%d) room_id should be 0, got %d"
				% [x, y, c.room_id])


# ---------------------------------------------------------------------------
# Walls
# ---------------------------------------------------------------------------

func test_rasterize_walls_appear_around_open_areas() -> void:
	# A 3x3 room at (2,2)-(4,4). Cells in the 1-cell ring (1-5, 1-5) that
	# aren't room interior should be walls. Cells beyond the ring (0, 6, etc.)
	# should remain rock.
	var composer := _composer_with_one_room(11, 11, Rect2i(2, 2, 3, 3))
	var cells: Array[Array] = DungeonLayoutRasterizer.rasterize_cells(composer)
	# Test a few perimeter cells.
	for x in range(1, 6):
		for y in [1, 5]:
			var c: DungeonCellData = cells[x][y]
			check(c.terrain_feature == DungeonCellData.FEATURE_WALL_STONE,
				"perimeter cell (%d,%d) should be WALL_STONE, got %s"
					% [x, y, c.terrain_feature])
			check(not c.passable, "perimeter cell (%d,%d) should not be passable" % [x, y])


func test_rasterize_far_cells_stay_as_rock() -> void:
	var composer := _composer_with_one_room(11, 11, Rect2i(2, 2, 3, 3))
	var cells: Array[Array] = DungeonLayoutRasterizer.rasterize_cells(composer)
	# (10, 10) is far from the room — should still be rock.
	check(cells[10][10].terrain_feature == DungeonCellData.FEATURE_ROCK,
		"far cell (10,10) should be FEATURE_ROCK, got %s"
			% cells[10][10].terrain_feature)
	check(not cells[10][10].passable, "far cell should not be passable")


# ---------------------------------------------------------------------------
# Corridors
# ---------------------------------------------------------------------------

func test_rasterize_corridor_cells() -> void:
	# Hand-build: 1 room + 1 corridor of 3 cells next to it.
	var composer := _composer_with_one_room(11, 7, Rect2i(2, 2, 3, 3))
	# Add a corridor at y=3 from x=5 to x=7 (just outside the room).
	var corridor := DungeonRoomComposer.CorridorPlan.new()
	corridor.centerline = [Vector2i(5, 3), Vector2i(6, 3), Vector2i(7, 3)]
	corridor.width = 1
	corridor.room_id_a = 0
	corridor.room_id_b = -1
	composer.corridors.append(corridor)
	var cells: Array[Array] = DungeonLayoutRasterizer.rasterize_cells(composer)
	for cp in corridor.centerline:
		var c: DungeonCellData = cells[cp.x][cp.y]
		check(c.terrain_feature == DungeonCellData.FEATURE_OPEN,
			"corridor cell %s should be FEATURE_OPEN, got %s" % [cp, c.terrain_feature])
		check(c.passable, "corridor cell %s should be passable" % cp)
		check(c.is_corridor, "corridor cell %s is_corridor should be true" % cp)
		check(c.room_id == -1, "corridor cell %s room_id should be -1" % cp)


# ---------------------------------------------------------------------------
# Doors
# ---------------------------------------------------------------------------

func test_rasterize_doors_have_correct_features() -> void:
	var composer := _composer_with_one_room(11, 7, Rect2i(2, 2, 3, 3))
	# Place every door type on cells around the room. After the §8.1 step-5
	# secret-as-overlay refactor (2026-05-27), the secret door is tested
	# separately via test_rasterize_secret_overlay_uses_secret_feature.
	var positions: Array[Vector2i] = [
		Vector2i(5, 2), Vector2i(5, 3), Vector2i(5, 4), Vector2i(1, 2),
	]
	var types: Array[String] = [
		DungeonDoorData.TYPE_ARCH,
		DungeonDoorData.TYPE_UNLOCKED,
		DungeonDoorData.TYPE_LOCKED,
		DungeonDoorData.TYPE_TRAPPED,
	]
	for i in positions.size():
		var d := DungeonRoomComposer.DoorPlan.new()
		d.position = positions[i]
		d.type = types[i]
		d.room_id_a = 0
		d.room_id_b = -1
		composer.doors.append(d)
	var cells: Array[Array] = DungeonLayoutRasterizer.rasterize_cells(composer)
	# ARCH → open passable
	check(cells[5][2].terrain_feature == DungeonCellData.FEATURE_DOOR
		and cells[5][2].passable, "ARCH should be FEATURE_DOOR + passable")
	# UNLOCKED → closed, impassable
	check(cells[5][3].terrain_feature == DungeonCellData.FEATURE_DOOR
		and not cells[5][3].passable
		and cells[5][3].door_state == "closed",
		"UNLOCKED door should be FEATURE_DOOR + impassable + state=closed")
	# LOCKED → locked feature, state=locked
	check(cells[5][4].terrain_feature == DungeonCellData.FEATURE_DOOR_LOCKED
		and cells[5][4].door_state == "locked",
		"LOCKED should be FEATURE_DOOR_LOCKED + state=locked")
	# TRAPPED → falls back to LOCKED per V1 GDD §10.5
	check(cells[1][2].terrain_feature == DungeonCellData.FEATURE_DOOR_LOCKED
		and cells[1][2].door_state == "locked",
		"TRAPPED should fall back to FEATURE_DOOR_LOCKED + state=locked (V1 §10.5)")


func test_rasterize_secret_overlay_uses_secret_feature() -> void:
	# Per §8.1 step 5: a secret door has an underlying type (unlocked / locked /
	# trapped) PLUS is_secret = true. The cell appearance is FEATURE_DOOR_SECRET
	# regardless of underlying type; the underlying type still appears on
	# DoorData.type for runtime behavior once detected.
	var composer := _composer_with_one_room(11, 7, Rect2i(2, 2, 3, 3))
	# Locked+Secret
	var d1 := DungeonRoomComposer.DoorPlan.new()
	d1.position = Vector2i(5, 2)
	d1.type = DungeonDoorData.TYPE_LOCKED
	d1.is_secret = true
	d1.room_id_a = 0
	d1.room_id_b = -1
	composer.doors.append(d1)
	# Unlocked+Secret
	var d2 := DungeonRoomComposer.DoorPlan.new()
	d2.position = Vector2i(5, 4)
	d2.type = DungeonDoorData.TYPE_UNLOCKED
	d2.is_secret = true
	d2.room_id_a = 0
	d2.room_id_b = -1
	composer.doors.append(d2)
	var cells: Array[Array] = DungeonLayoutRasterizer.rasterize_cells(composer)
	check(cells[5][2].terrain_feature == DungeonCellData.FEATURE_DOOR_SECRET,
		"Locked+Secret cell should be FEATURE_DOOR_SECRET, got %s" % cells[5][2].terrain_feature)
	check(not cells[5][2].door_detected, "Locked+Secret cell door_detected should be false")
	check(cells[5][4].terrain_feature == DungeonCellData.FEATURE_DOOR_SECRET,
		"Unlocked+Secret cell should be FEATURE_DOOR_SECRET, got %s" % cells[5][4].terrain_feature)
	# Underlying door type is preserved on DoorData (via build_door_data)
	var doors: Array[DungeonDoorData] = DungeonLayoutRasterizer.build_door_data(composer)
	var by_pos: Dictionary = {}
	for dd in doors:
		by_pos[dd.position] = dd
	check(by_pos[Vector2i(5, 2)].type == DungeonDoorData.TYPE_LOCKED
		and by_pos[Vector2i(5, 2)].is_secret,
		"DoorData at (5,2) should preserve type=locked + is_secret=true")
	check(by_pos[Vector2i(5, 4)].type == DungeonDoorData.TYPE_UNLOCKED
		and by_pos[Vector2i(5, 4)].is_secret,
		"DoorData at (5,4) should preserve type=unlocked + is_secret=true")


func test_rasterize_portcullis_blocks_movement_not_los() -> void:
	var composer := _composer_with_one_room(11, 7, Rect2i(2, 2, 3, 3))
	var d := DungeonRoomComposer.DoorPlan.new()
	d.position = Vector2i(5, 3)
	d.type = DungeonDoorData.TYPE_PORTCULLIS
	d.room_id_a = 0
	d.room_id_b = -1
	composer.doors.append(d)
	var cells: Array[Array] = DungeonLayoutRasterizer.rasterize_cells(composer)
	var c: DungeonCellData = cells[5][3]
	check(c.terrain_feature == DungeonCellData.FEATURE_PORTCULLIS,
		"PORTCULLIS should be FEATURE_PORTCULLIS")
	check(not c.passable, "PORTCULLIS should not be passable")
	check(not c.blocks_los, "PORTCULLIS should NOT block LOS (you can see through bars)")


# ---------------------------------------------------------------------------
# Stairs
# ---------------------------------------------------------------------------

func test_rasterize_stairs() -> void:
	var composer := _composer_with_one_room(11, 7, Rect2i(2, 2, 3, 3))
	var sup := DungeonRoomComposer.StairPlan.new()
	sup.position = Vector2i(3, 3)
	sup.direction = DungeonStairData.DIRECTION_UP
	composer.stairs.append(sup)
	var sdn := DungeonRoomComposer.StairPlan.new()
	sdn.position = Vector2i(4, 3)
	sdn.direction = DungeonStairData.DIRECTION_DOWN
	composer.stairs.append(sdn)
	var cells: Array[Array] = DungeonLayoutRasterizer.rasterize_cells(composer)
	check(cells[3][3].terrain_feature == DungeonCellData.FEATURE_STAIRS_UP,
		"up stair should be FEATURE_STAIRS_UP")
	check(cells[3][3].passable, "stairs should be passable")
	check(cells[3][3].room_id == 0,
		"stair cell room_id should be preserved from room (0), got %d"
			% cells[3][3].room_id)
	check(cells[4][3].terrain_feature == DungeonCellData.FEATURE_STAIRS_DOWN,
		"down stair should be FEATURE_STAIRS_DOWN")


# ---------------------------------------------------------------------------
# build_room_data / build_door_data / attach
# ---------------------------------------------------------------------------

func test_build_room_data_preserves_bounds_and_cells() -> void:
	var composer := _composer_with_one_room(11, 7, Rect2i(2, 2, 3, 4))
	var rooms: Array[DungeonRoomData] = DungeonLayoutRasterizer.build_room_data(composer)
	check(rooms.size() == 1, "expected 1 room, got %d" % rooms.size())
	var r: DungeonRoomData = rooms[0]
	check(r.id == 0, "room id should be 0, got %d" % r.id)
	check(r.bounds == Rect2i(2, 2, 3, 4),
		"room bounds should be (2,2,3,4), got %s" % r.bounds)
	check(r.area_sqft == 12 * 25,
		"room area_sqft should be 12 cells × 25 = 300, got %d" % r.area_sqft)
	check(r.cells.size() == 12, "room cell count should be 12, got %d" % r.cells.size())


func test_build_door_data_preserves_type_and_connections() -> void:
	var composer := _composer_with_one_room(11, 7, Rect2i(2, 2, 3, 3))
	var dp := DungeonRoomComposer.DoorPlan.new()
	dp.position = Vector2i(5, 3)
	dp.type = DungeonDoorData.TYPE_LOCKED
	dp.room_id_a = 0
	dp.room_id_b = -1
	composer.doors.append(dp)
	var doors: Array[DungeonDoorData] = DungeonLayoutRasterizer.build_door_data(composer)
	check(doors.size() == 1, "expected 1 door, got %d" % doors.size())
	var d: DungeonDoorData = doors[0]
	check(d.position == Vector2i(5, 3), "door position preserved")
	check(d.type == DungeonDoorData.TYPE_LOCKED, "door type preserved")
	check(d.connects.size() == 2,
		"door.connects should have 2 entries (room + pseudo-room), got %s" % str(d.connects))
	check(0 in d.connects and -1 in d.connects,
		"door should connect room 0 and -1, got %s" % str(d.connects))


func test_build_door_data_preserves_is_secret_and_material() -> void:
	# DungeonRoomComposer's §8.3 pass writes door.door_material; the rasterizer
	# must propagate that (and is_secret) onto DungeonDoorData.
	var composer := _composer_with_one_room(11, 7, Rect2i(2, 2, 3, 3))
	var dp := DungeonRoomComposer.DoorPlan.new()
	dp.position = Vector2i(5, 3)
	dp.type = DungeonDoorData.TYPE_LOCKED
	dp.is_secret = true
	dp.door_material = DungeonDoorData.MATERIAL_WOOD_STANDARD
	dp.room_id_a = 0
	dp.room_id_b = -1
	composer.doors.append(dp)
	var doors: Array[DungeonDoorData] = DungeonLayoutRasterizer.build_door_data(composer)
	check(doors.size() == 1, "expected 1 door, got %d" % doors.size())
	var d: DungeonDoorData = doors[0]
	check(d.is_secret, "is_secret should be propagated as true")
	check(d.door_material == DungeonDoorData.MATERIAL_WOOD_STANDARD,
		"door_material should be propagated; got '%s'" % d.door_material)


func test_attach_doors_to_rooms_populates_room_door_lists() -> void:
	# Two rooms, one door connecting them.
	var composer := DungeonRoomComposer.new()
	composer.grid_width = 11
	composer.grid_height = 7
	var a := DungeonRoomComposer.RoomPlan.new()
	a.id = 0
	a.bounds = Rect2i(1, 1, 3, 3)
	composer.rooms.append(a)
	var b := DungeonRoomComposer.RoomPlan.new()
	b.id = 1
	b.bounds = Rect2i(5, 1, 3, 3)
	composer.rooms.append(b)
	var dp := DungeonRoomComposer.DoorPlan.new()
	dp.position = Vector2i(4, 2)
	dp.type = DungeonDoorData.TYPE_UNLOCKED
	dp.room_id_a = 0
	dp.room_id_b = 1
	composer.doors.append(dp)
	var rooms: Array[DungeonRoomData] = DungeonLayoutRasterizer.build_room_data(composer)
	var doors: Array[DungeonDoorData] = DungeonLayoutRasterizer.build_door_data(composer)
	DungeonLayoutRasterizer.attach_doors_to_rooms(rooms, doors)
	check(rooms[0].doors.size() == 1, "room 0 should have 1 door, got %d" % rooms[0].doors.size())
	check(rooms[1].doors.size() == 1, "room 1 should have 1 door, got %d" % rooms[1].doors.size())


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _composer_with_one_room(grid_w: int, grid_h: int, room_bounds: Rect2i) -> DungeonRoomComposer:
	var c := DungeonRoomComposer.new()
	c.grid_width = grid_w
	c.grid_height = grid_h
	var r := DungeonRoomComposer.RoomPlan.new()
	r.id = 0
	r.bounds = room_bounds
	c.rooms.append(r)
	return c
