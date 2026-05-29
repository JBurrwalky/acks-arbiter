class_name DungeonLayoutGenerator
extends RefCounted

## Top-level orchestrator for single-floor dungeon layout generation.
##
## Implements `gdd-dungeon-layout.md` §4.1 pipeline (rev 2026-05-27):
##   1. SEED PARAMETERS — derive grid_size, target_room_count, room_size_range
##                        from request + theme
##   2-7. ROOM/CORRIDOR/DOOR/STAIR PLANNING + ROOM PURPOSES
##        — delegated to DungeonRoomComposer
##   8.   RASTERIZE — delegated to DungeonLayoutRasterizer
##   9.   VERIFY — BFS sanity check that every room is reachable from a stair
##                 (doors treated as passable); warns if not
##   10.  OUTPUT — DungeonLayout per §11
##
## The generator itself is a thin orchestrator. Each phase lives in its own
## module so they can be tested independently and so the composer's geometric
## plan can be inspected before rasterization.


# ---------------------------------------------------------------------------
# Per-size constants
# ---------------------------------------------------------------------------

# Grid sizes per layout GDD §4.3.
const _GRID_SIZES := {
	DungeonLayoutRequest.SIZE_LAIR: Vector2i(21, 21),
	DungeonLayoutRequest.SIZE_SMALL: Vector2i(31, 31),
	DungeonLayoutRequest.SIZE_MEDIUM: Vector2i(51, 51),
	DungeonLayoutRequest.SIZE_LARGE: Vector2i(79, 79),
}

# Target room counts (midpoint of layout GDD §3 ranges).
const _TARGET_ROOM_COUNTS := {
	DungeonLayoutRequest.SIZE_LAIR: 5,    # 3-6 range
	DungeonLayoutRequest.SIZE_SMALL: 10,  # 8-12 range
	DungeonLayoutRequest.SIZE_MEDIUM: 20, # 15-25 range
	DungeonLayoutRequest.SIZE_LARGE: 40,  # 30-50 range
}

# Room size ranges (min, max in 5' cells) per layout GDD §6.1.
const _ROOM_SIZE_RANGES := {
	DungeonTheme.BIAS_SMALL: Vector2i(2, 4),
	DungeonTheme.BIAS_MIXED: Vector2i(2, 6),
	DungeonTheme.BIAS_LARGE: Vector2i(3, 8),
	DungeonTheme.BIAS_HUGE: Vector2i(4, 10),
}


# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------

## Generate one floor of dungeon layout per [param request]. Returns a fully-
## populated DungeonLayout. Returns null on hard failure (invalid request,
## grid initialization failure, etc.) with an error logged.
static func generate(request: DungeonLayoutRequest) -> DungeonLayout:
	if request == null:
		push_error("DungeonLayoutGenerator: null request.")
		return null
	if not request.dungeon_size in DungeonLayoutRequest.VALID_SIZES:
		push_warning("DungeonLayoutGenerator: invalid dungeon_size '%s'; defaulting to 'medium'." % request.dungeon_size)
		request.dungeon_size = DungeonLayoutRequest.SIZE_MEDIUM

	# Resolve theme (with V1 universal-fallback per V1 GDD §7.1).
	var theme: DungeonTheme = DungeonThemeCatalog.get_theme(request.dungeon_type)
	if theme == null:
		push_error("DungeonLayoutGenerator: theme catalog returned null for '%s'." % request.dungeon_type)
		return null

	# Resolve grid sizing + room sizing.
	var grid_size: Vector2i = _GRID_SIZES[request.dungeon_size]
	var target_room_count: int = _TARGET_ROOM_COUNTS[request.dungeon_size]
	var room_size_range: Vector2i = _ROOM_SIZE_RANGES.get(theme.room_size_bias, Vector2i(2, 6))

	# Seeded RNG so the same (request, seed) yields byte-identical output.
	var rng := RandomNumberGenerator.new()
	rng.seed = request.seed

	# Phase 2-7: planning. The composer accepts floor_tier (for §8.3 door
	# materials) and required_stair_positions (for §9.3 stair anchors).
	var composer := DungeonRoomComposer.new()
	var placed: int = composer.compose(
		grid_size.x, grid_size.y,
		target_room_count, room_size_range,
		theme,
		request.stairs_up, request.stairs_down,
		rng,
		request.floor_tier,
		request.required_stair_positions,
	)
	if placed < 0:
		push_error("DungeonLayoutGenerator: composer rejected the request (invalid stair anchors); aborting.")
		return null
	if placed == 0:
		push_warning("DungeonLayoutGenerator: composer placed 0 rooms for seed %d." % request.seed)

	# Phase 8: rasterize geometric plan onto a DungeonCellData grid.
	var cells: Array[Array] = DungeonLayoutRasterizer.rasterize_cells(composer)
	var rooms: Array[DungeonRoomData] = DungeonLayoutRasterizer.build_room_data(composer)
	var doors: Array[DungeonDoorData] = DungeonLayoutRasterizer.build_door_data(composer)
	var stairs: Array[DungeonStairData] = DungeonLayoutRasterizer.build_stair_data(composer)
	DungeonLayoutRasterizer.attach_doors_to_rooms(rooms, doors)

	# Pick the entrance cell — the up-stair on the entrance floor.
	var entrance: Vector2i = Vector2i(-1, -1)
	if request.is_entrance_floor:
		for s in stairs:
			if s.direction == DungeonStairData.DIRECTION_UP:
				s.is_entrance_stair = true
				entrance = s.position
				break

	# Phase 9: navigability check. BFS from a stair across all open cells
	# (doors treated as passable). Warn if any room is unreachable; the V1
	# orchestrator (DG-V1.D) can retry / repair per V1 GDD §9.1.
	if not _check_layout_navigability(cells, rooms, stairs, grid_size.x, grid_size.y):
		push_warning("DungeonLayoutGenerator: navigability check failed for level %d (some rooms unreachable). DG-V1.D's retry/repair path will need to recover." % request.level_number)

	# Phase 10: bundle output.
	var layout := DungeonLayout.new()
	layout.dungeon_id = ""  # caller assigns
	layout.dungeon_type = request.dungeon_type
	layout.dungeon_size = request.dungeon_size
	layout.structure_type = theme.structure_type
	layout.level_number = request.level_number
	layout.floor_tier = request.floor_tier
	layout.is_entrance_floor = request.is_entrance_floor
	layout.grid_width = grid_size.x
	layout.grid_height = grid_size.y
	layout.cells = cells
	layout.rooms = rooms
	layout.doors = doors
	layout.stairs = stairs
	layout.entrance = entrance
	layout.theme = theme
	layout.generation_seed = request.seed
	return layout


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

## §9.1 layout-level navigability check. BFS from the first stair cell (or
## any room cell if no stairs) with EVERY door treated as PASSABLE — this
## tests structural connectivity only, not the lock/key puzzle layer (which
## the V1 generator handles in its own §9.2 pass during DG-V1.D).
##
## Returns true if every detected room has at least one of its cells reached
## by the BFS. False otherwise.
static func _check_layout_navigability(
	cells: Array[Array],
	rooms: Array[DungeonRoomData],
	stairs: Array[DungeonStairData],
	grid_width: int,
	grid_height: int,
) -> bool:
	if rooms.is_empty():
		return true  # vacuously connected
	var start: Vector2i = Vector2i(-1, -1)
	if not stairs.is_empty():
		start = stairs[0].position
	else:
		start = rooms[0].cells[0]
	if start.x < 0:
		return false
	var visited: Dictionary = {}
	var queue: Array[Vector2i] = [start]
	visited[start] = true
	var dirs: Array[Vector2i] = [
		Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
	]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		for dir in dirs:
			var n: Vector2i = cur + dir
			if visited.has(n):
				continue
			if n.x < 0 or n.y < 0 or n.x >= grid_width or n.y >= grid_height:
				continue
			var cd: DungeonCellData = cells[n.x][n.y]
			if cd == null:
				continue
			# For navigability we treat doors as passable.
			if not cd.passable and not cd.is_door():
				continue
			visited[n] = true
			queue.append(n)
	for room in rooms:
		var reached: bool = false
		for c in room.cells:
			if visited.has(c):
				reached = true
				break
		if not reached:
			return false
	return true
