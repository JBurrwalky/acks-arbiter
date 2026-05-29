class_name DungeonLayoutRasterizer
extends RefCounted

## Stamps the geometric output of DungeonRoomComposer onto a 2D
## DungeonCellData grid per `gdd-dungeon-layout.md` §10.1 (rasterization).
##
## Also produces the typed output arrays the V1 generator orchestrator
## consumes: Array[DungeonRoomData], Array[DungeonDoorData],
## Array[DungeonStairData] — built from the composer's plans rather than
## flood-fill detection (we already know the rooms; flood-fill would only
## be useful as a verification check, which §10.2 describes as optional and
## debug-only).


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Stamp the composer's plan onto a 2D `Array[Array[DungeonCellData]]` grid
## of size `composer.grid_width × composer.grid_height`. Returns the grid.
static func rasterize_cells(composer: DungeonRoomComposer) -> Array[Array]:
	var w: int = composer.grid_width
	var h: int = composer.grid_height
	# Allocate every cell as solid rock (the safe default).
	var cells: Array[Array] = []
	cells.resize(w)
	for x in w:
		var col: Array[DungeonCellData] = []
		col.resize(h)
		for y in h:
			col[y] = _new_rock_cell()
		cells[x] = col

	_stamp_room_interiors(composer, cells)
	_stamp_corridor_centerlines(composer, cells)
	_stamp_walls_around_openings(composer, cells)
	_stamp_doors(composer, cells)
	_stamp_stairs(composer, cells)
	return cells


## Convert composer.rooms into Array[DungeonRoomData] with id, cells, bounds,
## area_sqft, center, original_purpose. Doors are attached separately.
static func build_room_data(composer: DungeonRoomComposer) -> Array[DungeonRoomData]:
	var out: Array[DungeonRoomData] = []
	for r in composer.rooms:
		var room: DungeonRoomComposer.RoomPlan = r
		var rd := DungeonRoomData.new()
		rd.id = room.id
		rd.bounds = room.bounds
		rd.original_purpose = room.original_purpose
		rd.current_purpose = ""  # populated by V1 stocking later
		# Enumerate cells inside the bounds.
		var b: Rect2i = room.bounds
		for x in range(b.position.x, b.position.x + b.size.x):
			for y in range(b.position.y, b.position.y + b.size.y):
				rd.cells.append(Vector2i(x, y))
		rd.area_sqft = rd.cells.size() * 25  # 5'×5' per cell
		rd.center = Vector2i(
			b.position.x + b.size.x / 2,
			b.position.y + b.size.y / 2,
		)
		out.append(rd)
	return out


static func build_door_data(composer: DungeonRoomComposer) -> Array[DungeonDoorData]:
	var out: Array[DungeonDoorData] = []
	for d in composer.doors:
		var door: DungeonRoomComposer.DoorPlan = d
		var dd := DungeonDoorData.new()
		dd.position = door.position
		dd.type = door.type
		dd.connects = [door.room_id_a, door.room_id_b]
		dd.is_secret = door.is_secret
		# door_material was populated by the composer's §8.3 pass for every door
		# (MATERIAL_NONE for arches, MATERIAL_METAL for portcullises, etc.).
		# Propagate it verbatim — including the MATERIAL_NONE empty string for
		# arches, which is a legal VALID_MATERIALS value.
		dd.door_material = door.door_material
		out.append(dd)
	return out


static func build_stair_data(composer: DungeonRoomComposer) -> Array[DungeonStairData]:
	var out: Array[DungeonStairData] = []
	for s in composer.stairs:
		var stair: DungeonRoomComposer.StairPlan = s
		var sd := DungeonStairData.new()
		sd.position = stair.position
		sd.direction = stair.direction
		out.append(sd)
	return out


## After build_room_data + build_door_data, attach each door to its connected
## room(s). The same DoorData object ends up in DungeonLayout.doors AND in
## each connected DungeonRoomData.doors (by reference).
static func attach_doors_to_rooms(rooms: Array[DungeonRoomData], doors: Array[DungeonDoorData]) -> void:
	for d in doors:
		for room_id in d.connects:
			if room_id < 0:
				continue
			for r in rooms:
				if r.id == room_id:
					r.doors.append(d)
					break


# ---------------------------------------------------------------------------
# Cell construction
# ---------------------------------------------------------------------------

static func _new_rock_cell() -> DungeonCellData:
	var c := DungeonCellData.new()
	c.terrain_feature = DungeonCellData.FEATURE_ROCK
	c.passable = false
	c.blocks_los = true
	c.is_corridor = false
	c.room_id = -1
	return c


# ---------------------------------------------------------------------------
# Stamping passes
# ---------------------------------------------------------------------------

## Stamp every cell inside each room's bounds as open room floor.
static func _stamp_room_interiors(composer: DungeonRoomComposer, cells: Array[Array]) -> void:
	for r in composer.rooms:
		var room: DungeonRoomComposer.RoomPlan = r
		var b: Rect2i = room.bounds
		for x in range(b.position.x, b.position.x + b.size.x):
			for y in range(b.position.y, b.position.y + b.size.y):
				if x < 0 or y < 0 or x >= composer.grid_width or y >= composer.grid_height:
					continue
				var cell: DungeonCellData = cells[x][y]
				cell.terrain_feature = DungeonCellData.FEATURE_OPEN
				cell.passable = true
				cell.blocks_los = false
				cell.room_id = room.id
				cell.is_corridor = false


## Stamp every cell on each corridor's centerline as open corridor floor.
## Stays away from room interiors (corridors that crossed a room per the
## §7.3 step 4 fallback would override room cells; flag those as a warning).
static func _stamp_corridor_centerlines(composer: DungeonRoomComposer, cells: Array[Array]) -> void:
	for c in composer.corridors:
		var corridor: DungeonRoomComposer.CorridorPlan = c
		for cell_pos in corridor.centerline:
			if cell_pos.x < 0 or cell_pos.y < 0 or cell_pos.x >= composer.grid_width or cell_pos.y >= composer.grid_height:
				continue
			var cell: DungeonCellData = cells[cell_pos.x][cell_pos.y]
			# If the corridor passes through a room (the §7.3 step 4 fallback),
			# the room cell stays as a room cell — corridor doesn't overwrite.
			# The connection is then "the corridor enters at one wall and
			# exits at the other," with doors at both transitions.
			if cell.room_id >= 0:
				continue
			cell.terrain_feature = DungeonCellData.FEATURE_OPEN
			cell.passable = true
			cell.blocks_los = false
			cell.is_corridor = true
			cell.room_id = -1


## After rooms and corridors are stamped, walk the grid: any cell that is
## still default-rock but adjacent to an open cell becomes a wall (visible
## boundary). Cells that remain rock are "far from anything" — outside the
## dungeon proper.
static func _stamp_walls_around_openings(composer: DungeonRoomComposer, cells: Array[Array]) -> void:
	var w: int = composer.grid_width
	var h: int = composer.grid_height
	var dirs: Array[Vector2i] = [
		Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
		Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1),
	]
	for x in w:
		for y in h:
			var cell: DungeonCellData = cells[x][y]
			if cell.terrain_feature != DungeonCellData.FEATURE_ROCK:
				continue
			# Check 8-neighbourhood; promote to wall if any neighbour is open
			# (room interior or corridor).
			for d in dirs:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var n: DungeonCellData = cells[nx][ny]
				if n.passable and (n.room_id >= 0 or n.is_corridor):
					cell.terrain_feature = DungeonCellData.FEATURE_WALL_STONE
					cell.passable = false  # already false
					cell.blocks_los = true  # already true
					break


## Stamp doors. The door cell may currently be a corridor cell (corridor-to-
## room transition), a wall cell (adjacent-room shared wall), or — rarely —
## a room interior cell (if the placer happened to land on one; we leave it
## as room interior in that case).
static func _stamp_doors(composer: DungeonRoomComposer, cells: Array[Array]) -> void:
	for d in composer.doors:
		var door: DungeonRoomComposer.DoorPlan = d
		if door.position.x < 0 or door.position.y < 0:
			continue
		if door.position.x >= composer.grid_width or door.position.y >= composer.grid_height:
			continue
		var cell: DungeonCellData = cells[door.position.x][door.position.y]
		_apply_door_feature(cell, door.type, door.is_secret)


## Stamp the cell-level appearance of a door. `door_type` is the underlying
## type (arch / unlocked / locked / trapped / portcullis — never "secret"
## post-2026-05-27 refactor). `is_secret` overrides cell appearance to
## FEATURE_DOOR_SECRET (the door appears as wall until detected, regardless
## of its underlying access type).
static func _apply_door_feature(cell: DungeonCellData, door_type: String, is_secret: bool) -> void:
	# Secret overlay takes precedence for cell-level appearance. The
	# underlying type still governs the door's MECHANICAL behavior once
	# detected (it's recorded on DoorData.type, not on the cell), but the
	# pre-detection cell looks like a secret door.
	if is_secret:
		cell.terrain_feature = DungeonCellData.FEATURE_DOOR_SECRET
		cell.passable = false
		cell.blocks_los = true
		cell.door_state = "closed"
		cell.door_detected = false
		return
	match door_type:
		DungeonDoorData.TYPE_ARCH:
			# Open passage — passable, no door object visually.
			cell.terrain_feature = DungeonCellData.FEATURE_DOOR
			cell.passable = true
			cell.blocks_los = false
			cell.door_state = "open"
		DungeonDoorData.TYPE_UNLOCKED:
			cell.terrain_feature = DungeonCellData.FEATURE_DOOR
			cell.passable = false  # closed by default; runtime opens
			cell.blocks_los = true
			cell.door_state = "closed"
		DungeonDoorData.TYPE_LOCKED:
			cell.terrain_feature = DungeonCellData.FEATURE_DOOR_LOCKED
			cell.passable = false
			cell.blocks_los = true
			cell.door_state = "locked"
		DungeonDoorData.TYPE_TRAPPED:
			# Per V1 GDD §10.5 trapped doors behave as Locked in V1.
			cell.terrain_feature = DungeonCellData.FEATURE_DOOR_LOCKED
			cell.passable = false
			cell.blocks_los = true
			cell.door_state = "locked"
		DungeonDoorData.TYPE_PORTCULLIS:
			cell.terrain_feature = DungeonCellData.FEATURE_PORTCULLIS
			cell.passable = false
			cell.blocks_los = false  # portcullis blocks movement, not LOS
			cell.door_state = "closed"
		_:
			# Defensive default — treat as unlocked.
			cell.terrain_feature = DungeonCellData.FEATURE_DOOR
			cell.passable = false
			cell.blocks_los = true
			cell.door_state = "closed"


static func _stamp_stairs(composer: DungeonRoomComposer, cells: Array[Array]) -> void:
	for s in composer.stairs:
		var stair: DungeonRoomComposer.StairPlan = s
		if stair.position.x < 0 or stair.position.y < 0:
			continue
		if stair.position.x >= composer.grid_width or stair.position.y >= composer.grid_height:
			continue
		var cell: DungeonCellData = cells[stair.position.x][stair.position.y]
		if stair.direction == DungeonStairData.DIRECTION_UP:
			cell.terrain_feature = DungeonCellData.FEATURE_STAIRS_UP
		else:
			cell.terrain_feature = DungeonCellData.FEATURE_STAIRS_DOWN
		cell.passable = true
		cell.blocks_los = false
		# Stairs sit inside rooms; room_id was set during _stamp_room_interiors
		# and is preserved.
