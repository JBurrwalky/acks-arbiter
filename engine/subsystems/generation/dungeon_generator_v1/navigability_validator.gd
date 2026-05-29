class_name DungeonNavigabilityValidator
extends RefCounted

## Validates spatial reachability for a generated dungeon.
##
## §9.1 validate_layout — single-floor BFS: every room cell must be reachable
## from the entrance (or from all stair cells on non-entrance floors).
## Doors are treated as traversable regardless of type/state.
##
## §9.2 validate_solvability — multi-floor fixed-point BFS: given the full
## floor stack and all placed key items, can every room and stair cell be
## reached in the dungeon's INITIAL state (doors locked/portcullised until
## their guard condition is satisfied by already-reached content)?
##
## Reference: gdd-dungeon-generator-v1.md §9.


# ---------------------------------------------------------------------------
# §9.1  validate_layout — single-floor reachability
# ---------------------------------------------------------------------------

## BFS from the entrance (entrance floor) or all stair cells (other floors).
## Door cells are traversable regardless of door type or lock state.
## A cell "belongs to a room" when its room_id >= 0.
## Returns {ok:bool, unreachable_room_ids:Array[int], message:String}.
static func validate_layout(layout: DungeonLayout) -> Dictionary:
	var visited: Dictionary = {}  # Vector2i -> true

	# ---- seed BFS -------------------------------------------------------
	var queue: Array[Vector2i] = []
	if layout.is_entrance_floor and layout.entrance != Vector2i(-1, -1):
		_enqueue(layout, layout.entrance, visited, queue)
	else:
		# Non-entrance floor: start from every stair cell so reachability
		# is floor-local (the multi-floor check belongs to validate_solvability).
		for stair: DungeonStairData in layout.stairs:
			_enqueue(layout, stair.position, visited, queue)

	# ---- BFS -------------------------------------------------------------
	while queue.size() > 0:
		var pos: Vector2i = queue.pop_front()
		for nb: Vector2i in _neighbours(pos):
			_enqueue(layout, nb, visited, queue)

	# ---- collect unreachable rooms ---------------------------------------
	var unreachable: Array[int] = []
	for room: DungeonRoomData in layout.rooms:
		var any_reached := false
		for cell_pos: Vector2i in room.cells:
			if visited.has(cell_pos):
				any_reached = true
				break
		if not any_reached:
			unreachable.append(room.id)

	var ok := unreachable.is_empty()
	var msg: String
	if ok:
		msg = "All rooms reachable on floor %d." % layout.level_number
	else:
		msg = ("Floor %d: %d unreachable room(s): %s"
			% [layout.level_number, unreachable.size(), str(unreachable)])

	return {
		"ok": ok,
		"unreachable_room_ids": unreachable,
		"message": msg,
	}


# ---------------------------------------------------------------------------
# §9.2  validate_solvability — multi-floor fixed-point BFS
# ---------------------------------------------------------------------------

## Multi-floor fixed-point BFS from the entrance cell on the entrance floor.
##
## Door passability in INITIAL state:
##   arch / curtain         -> always passable
##   unlocked               -> passable
##   locked / trapped       -> blocked UNLESS a matching key is already in the
##                             reachable region (key's room cells must be reached)
##   secret (is_secret)     -> blocked (conservative: player must Search first)
##   portcullis             -> blocked UNLESS its wired_lever_position cell is
##                             reached; a portcullis with no wired lever is
##                             treated as forceable (Force Portcullis always
##                             available per gdd-dungeon-map-ui.md) and thus
##                             passable.
##
## Stairs: stepping onto a stair cell adds the matching stair on the adjacent
## floor (same grid position, opposite direction) to the frontier.
##
## Iterates to a fixed point — re-expands when a newly reached cell unlocks
## a door (key now reachable / lever now reachable).
##
## secret_gated_treasure_per_floor: count of treasure hoards only reachable
## by passing a secret door.  This implementation returns 0 per floor — full
## secret-gating analysis requires a second BFS with secrets open, which is
## expensive and low-value for V1 acceptance; documented here.
##
## Returns {ok:bool, failures:Array[String], reached_all_stairs:bool,
##          unreachable_stairs:Array, secret_gated_treasure_per_floor:Array[int]}.
static func validate_solvability(
		floors: Array[DungeonLayout],
		key_items: Array[KeyItemData],
		entrance_floor_index: int) -> Dictionary:

	if floors.is_empty():
		return {
			"ok": false,
			"failures": ["No floors provided."],
			"reached_all_stairs": false,
			"unreachable_stairs": [],
			"secret_gated_treasure_per_floor": [],
		}

	# Map of "floor_idx:room_id" -> Array[KeyItemData] for door-unlock checks.
	var keys_by_room: Dictionary = {}  # room_key -> Array[KeyItemData]
	for k: KeyItemData in key_items:
		if k.placed_on_floor_index < 1 or k.placed_on_floor_index > floors.size():
			continue
		var room_key: String = "%d:%d" % [k.placed_on_floor_index, k.placed_in_room_id]
		if not keys_by_room.has(room_key):
			keys_by_room[room_key] = []
		keys_by_room[room_key].append(k)

	# ---- reachable set: "floor_index:x:y" strings -------------------------
	var reachable: Dictionary = {}  # encoded cell key -> true

	# ---- seed ---------------------------------------------------------------
	var entrance_fl_idx := entrance_floor_index  # 1-based
	if entrance_fl_idx < 1 or entrance_fl_idx > floors.size():
		return {
			"ok": false,
			"failures": ["entrance_floor_index %d out of range." % entrance_floor_index],
			"reached_all_stairs": false,
			"unreachable_stairs": [],
			"secret_gated_treasure_per_floor": [],
		}

	var entrance_floor: DungeonLayout = floors[entrance_fl_idx - 1]
	var start: Vector2i = entrance_floor.entrance

	var queue: Array = []  # Array of {floor_idx:int, pos:Vector2i}
	var cell_key: String = _cell_key(entrance_fl_idx, start)
	reachable[cell_key] = true
	queue.append({"floor_idx": entrance_fl_idx, "pos": start})

	# ---- fixed-point BFS ----------------------------------------------------
	# Each pass drains the queue. If the reachable set grew this pass (new keys
	# or levers became accessible, potentially unlocking previously blocked doors),
	# we reseed from the full reachable set and run another pass.  Terminates
	# because reachable is monotonically growing and bounded by grid size.
	var prev_size := 0
	while reachable.size() > prev_size:
		prev_size = reachable.size()

		while queue.size() > 0:
			var item: Dictionary = queue.pop_front()
			var fi: int = item["floor_idx"]
			var pos: Vector2i = item["pos"]
			var layout: DungeonLayout = floors[fi - 1]

			# Handle stair: add matching stair on adjacent floor.
			var here: DungeonCellData = layout.get_cell_at(pos)
			if here != null and here.is_stair():
				_expand_stair(floors, fi, pos, reachable, queue)

			# Expand 4-neighbours.
			for nb: Vector2i in _neighbours(pos):
				if not _can_traverse_solvability(layout, fi, nb, reachable, floors, keys_by_room):
					continue
				var nb_key: String = _cell_key(fi, nb)
				if not reachable.has(nb_key):
					reachable[nb_key] = true
					queue.append({"floor_idx": fi, "pos": nb})

		# If reachable grew, reseed queue from the entire reachable set so newly
		# accessible cells adjacent to locked doors can be re-evaluated now that
		# their keys/levers may have entered the reachable region.
		if reachable.size() > prev_size:
			queue.clear()
			for ck: String in reachable.keys():
				var parts: PackedStringArray = ck.split(":")
				var fi2: int = int(parts[0])
				var x2: int = int(parts[1])
				var y2: int = int(parts[2])
				queue.append({"floor_idx": fi2, "pos": Vector2i(x2, y2)})

	# ---- check all stair cells -----------------------------------------------
	var unreachable_stairs: Array = []
	var reached_all_stairs := true
	for f: DungeonLayout in floors:
		for stair: DungeonStairData in f.stairs:
			var sk: String = _cell_key(f.level_number, stair.position)
			if not reachable.has(sk):
				reached_all_stairs = false
				unreachable_stairs.append({
					"floor": f.level_number,
					"pos": stair.position,
					"direction": stair.direction,
				})

	# ---- check all room cells -----------------------------------------------
	var failures: Array[String] = []
	for f: DungeonLayout in floors:
		for room: DungeonRoomData in f.rooms:
			var any_room_cell_reached := false
			for rc: Vector2i in room.cells:
				if reachable.has(_cell_key(f.level_number, rc)):
					any_room_cell_reached = true
					break
			if not any_room_cell_reached:
				failures.append("Floor %d room %d unreachable." % [f.level_number, room.id])

	# ---- secret-gated treasure (best-effort 0s — documented) ---------------
	# Full analysis requires a second BFS with is_secret doors open minus the
	# primary BFS result. Deferred for V1 — returns 0 per floor.
	var secret_gated: Array[int] = []
	for _f: DungeonLayout in floors:
		secret_gated.append(0)

	var ok := failures.is_empty() and reached_all_stairs

	return {
		"ok": ok,
		"failures": failures,
		"reached_all_stairs": reached_all_stairs,
		"unreachable_stairs": unreachable_stairs,
		"secret_gated_treasure_per_floor": secret_gated,
	}


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

## 4-neighbourhood for grid movement.
static func _neighbours(pos: Vector2i) -> Array[Vector2i]:
	return [
		Vector2i(pos.x - 1, pos.y),
		Vector2i(pos.x + 1, pos.y),
		Vector2i(pos.x, pos.y - 1),
		Vector2i(pos.x, pos.y + 1),
	]


## Attempt to add pos to the BFS queue if in-bounds and passable for validate_layout.
## Door cells are always traversable (regardless of lock state) for single-floor
## layout validation (§9.1).
static func _enqueue(
		layout: DungeonLayout,
		pos: Vector2i,
		visited: Dictionary,
		queue: Array[Vector2i]) -> void:
	if pos.x < 0 or pos.y < 0 or pos.x >= layout.grid_width or pos.y >= layout.grid_height:
		return
	if visited.has(pos):
		return
	var cell: DungeonCellData = layout.get_cell_at(pos)
	if cell == null:
		return
	# Walkable: passable flag true, OR any door cell (doors are traversable for
	# layout validation regardless of type/state per §9.1).
	if not cell.passable and not cell.is_door():
		return
	visited[pos] = true
	queue.append(pos)


## Encoded key for multi-floor reachable dictionary.
static func _cell_key(floor_idx: int, pos: Vector2i) -> String:
	return "%d:%d:%d" % [floor_idx, pos.x, pos.y]


## True if any KeyItem that unlocks door at (fi, pos) has any room cell reached.
## Requires the floors array for room cell lookup.
static func _key_for_door_is_reachable_with_floors(
		fi: int,
		pos: Vector2i,
		reachable: Dictionary,
		keys_by_room: Dictionary,
		floors: Array[DungeonLayout]) -> bool:
	for room_key: String in keys_by_room.keys():
		var keys: Array = keys_by_room[room_key]
		for k: KeyItemData in keys:
			if k.opens_door_floor_index != fi or k.opens_door_position != pos:
				continue
			# Key found — is its room reachable?
			var kfi: int = k.placed_on_floor_index
			if kfi < 1 or kfi > floors.size():
				continue
			var key_layout: DungeonLayout = floors[kfi - 1]
			var key_room: DungeonRoomData = key_layout.find_room(k.placed_in_room_id)
			if key_room == null:
				continue
			for rc: Vector2i in key_room.cells:
				if reachable.has(_cell_key(kfi, rc)):
					return true
	return false


## Whether a cell at pos on floor fi is traversable for solvability BFS.
## Returns false for out-of-bounds, solid walls, and locked/secret doors whose
## guard condition is not yet met.
static func _can_traverse_solvability(
		layout: DungeonLayout,
		fi: int,
		pos: Vector2i,
		reachable: Dictionary,
		floors: Array[DungeonLayout],
		keys_by_room: Dictionary) -> bool:
	if pos.x < 0 or pos.y < 0 or pos.x >= layout.grid_width or pos.y >= layout.grid_height:
		return false
	var cell: DungeonCellData = layout.get_cell_at(pos)
	if cell == null:
		return false
	# Solid walls and rock are not traversable.
	if not cell.passable and not cell.is_door() and not cell.is_stair():
		return false
	# Door cells: check initial passability with full key/lever logic.
	if cell.is_door():
		var door: DungeonDoorData = layout.find_door_at(pos)
		if door != null:
			# Secret doors: conservative §9.2 model — player must Search first.
			# secret+locked/trapped with a reachable key: passable (Search then key).
			# All other secret door states: blocked (Search required, no fallback).
			if door.is_secret:
				if door.type == DungeonDoorData.TYPE_LOCKED or door.type == DungeonDoorData.TYPE_TRAPPED:
					return _key_for_door_is_reachable_with_floors(fi, pos, reachable, keys_by_room, floors)
				return false
			# Arch / curtain: passable.
			if DungeonDoorData.is_curtain(door.door_material) or door.type == DungeonDoorData.TYPE_ARCH:
				return true
			# Unlocked: passable.
			if door.type == DungeonDoorData.TYPE_UNLOCKED:
				return true
			# Portcullis.
			if door.type == DungeonDoorData.TYPE_PORTCULLIS:
				if door.wired_lever_position == Vector2i(-1, -1):
					return true  # no lever -> Force Portcullis available
				return reachable.has(_cell_key(fi, door.wired_lever_position))
			# Non-bashable locked / trapped (stone or metal): need key.
			# Bashable (wood_standard / wood_thick): always passable per §10 preamble.
			# Note: secret+bashable doors are handled above (blocked until Search).
			if door.type == DungeonDoorData.TYPE_LOCKED or door.type == DungeonDoorData.TYPE_TRAPPED:
				if DungeonDoorData.is_bashable(door.door_material):
					return true  # wood door: bash available, no key needed
				return _key_for_door_is_reachable_with_floors(fi, pos, reachable, keys_by_room, floors)
	return true


## Follow a stair at (fi, pos) to the matching stair on the adjacent floor.
## Convention: stair-down on floor i at pos P matches stair-up on floor i+1 at pos P.
## If connects_to_level is set on DungeonStairData, uses that; otherwise infers
## from direction (down -> fi+1, up -> fi-1).
## Returns true if a new cell was added to the reachable set.
static func _expand_stair(
		floors: Array[DungeonLayout],
		fi: int,
		pos: Vector2i,
		reachable: Dictionary,
		queue: Array) -> bool:
	var layout: DungeonLayout = floors[fi - 1]
	var cell: DungeonCellData = layout.get_cell_at(pos)
	if cell == null or not cell.is_stair():
		return false

	# Find the DungeonStairData for this position.
	var stair_data: DungeonStairData = null
	for s: DungeonStairData in layout.stairs:
		if s.position == pos:
			stair_data = s
			break
	if stair_data == null:
		return false

	# Determine destination floor index.
	var dest_fi: int
	if stair_data.connects_to_level > 0:
		dest_fi = stair_data.connects_to_level
	elif stair_data.direction == DungeonStairData.DIRECTION_DOWN:
		dest_fi = fi + 1
	else:
		dest_fi = fi - 1

	if dest_fi < 1 or dest_fi > floors.size():
		return false  # no destination floor (surface stair)

	var dest_layout: DungeonLayout = floors[dest_fi - 1]
	# The matching stair is at the same grid position, opposite direction.
	var dest_cell: DungeonCellData = dest_layout.get_cell_at(pos)
	if dest_cell == null or not dest_cell.is_stair():
		return false

	var dest_key: String = _cell_key(dest_fi, pos)
	if reachable.has(dest_key):
		return false

	reachable[dest_key] = true
	queue.append({"floor_idx": dest_fi, "pos": pos})
	return true
