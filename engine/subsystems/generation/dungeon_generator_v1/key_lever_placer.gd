class_name DungeonKeyLeverPlacer
extends RefCounted

## Places keys and portcullis levers for locked stone/metal doors (§10) and
## portcullises (§10.3) across a multi-floor dungeon.
##
## place() runs the full §10 algorithm, returning an Array[KeyItemData] for
## locked doors that received keys.  Portcullis levers are embedded directly
## in DungeonDoorData.wired_lever_position (no KeyItem).
##
## ALGORITHM (rewritten 2026-06-10 — discovery-order placement):
## A single multi-floor fixpoint BFS from the dungeon entrance, using the SAME
## door-passability model as DungeonNavigabilityValidator.validate_solvability.
## When the frontier hits a gated door (locked/trapped stone-metal, any
## secret+locked/trapped, or a portcullis), its key/lever is placed in a room
## that is ALREADY fully discovered — so every key is reachable before its door
## by construction and circular key dependencies (key A behind door B whose key
## is behind door A) cannot occur. The previous implementation computed a
## per-door "outside region" that treated all OTHER locked doors as passable,
## which allowed those circles; the solvability fixpoint then failed and the
## orchestrator burned its stocking/dungeon retries re-rolling placements
## (observed at ~15-20% of attempts, and ~90% of total generation CPU went to
## the per-door BFS sweeps). This rewrite is one BFS total and deadlock-free.
##
## §10.4 downgrades are preserved: a gated door hit before ANY candidate room
## exists is on the sole entrance path and downgrades to plain unlocked wood.
## Additionally, if after the fixpoint some stair/room remains unreached and a
## frontier secret+unlocked door is what blocks it (those doors are
## model-impassable and carry no key), that door's is_secret flag is cleared —
## the same §10.4 philosophy applied to the one door class the key system
## cannot otherwise repair. Optional pockets behind secret doors that the BFS
## can reach another way keep their secret doors untouched.
##
## finalize_key_placements() converts each key's PLACED_LOOSE placement into
## a specific sub-type (monster inventory, treasure hoard, or a forced hoard)
## per §5 step 7.
##
## Reference: gdd-dungeon-generator-v1.md §10.


# ---------------------------------------------------------------------------
# §10  place()
# ---------------------------------------------------------------------------

## Main entry point.  Walks the dungeon from the entrance in one fixpoint BFS,
## assigning keys/levers to gated doors as the frontier reaches them, applying
## the §10.4 downgrade when no candidate room exists.
##
## Returns Array[KeyItemData] — keys only (levers live on DoorData).
static func place(
		floors: Array[DungeonLayout],
		entrance_floor_index: int,
		rng: RandomNumberGenerator) -> Array[KeyItemData]:

	var keys: Array[KeyItemData] = []
	if floors.is_empty() or entrance_floor_index < 1 or entrance_floor_index > floors.size():
		return keys

	var entrance_room_id: int = _find_entrance_room_id(floors, entrance_floor_index)

	# Per-room index + cell totals ("fi:room_id" -> room / total), built once.
	var room_index: Dictionary = {}
	for fi: int in range(1, floors.size() + 1):
		for room: DungeonRoomData in floors[fi - 1].rooms:
			room_index["%d:%d" % [fi, room.id]] = room

	# Discovery state. All dictionaries key on _cell_key(fi, pos).
	var st: Dictionary = {
		"reachable": {},          # cell key -> true
		"queue": [],              # [{floor_idx, pos}]
		"pending": [],            # [{floor_idx, door}] gated doors awaiting key/lever, hit order
		"pending_set": {},        # cell key -> true
		"secret_blockers": [],    # [{floor_idx, door}] secret+unlocked doors, hit order
		"secret_blocker_set": {}, # cell key -> true
		"room_reached": {},       # "fi:room_id" -> reached cell count
		"full_rooms": [],         # [{room, floor_idx}] fully-discovered rooms, discovery order
		"full_room_set": {},      # "fi:room_id" -> true
		"room_index": room_index,
	}

	# Seed from the entrance cell (or the entrance floor's first stair as a
	# fallback, mirroring the pre-stocking connectivity guard's seeding).
	var entrance_floor: DungeonLayout = floors[entrance_floor_index - 1]
	var start: Vector2i = entrance_floor.entrance
	if start == Vector2i(-1, -1) or entrance_floor.get_cell_at(start) == null:
		if entrance_floor.stairs.size() > 0:
			start = (entrance_floor.stairs[0] as DungeonStairData).position
		else:
			push_warning("DungeonKeyLeverPlacer: no entrance or stair cell to seed placement BFS — skipping key placement.")
			return keys
	_mark_reached(floors, entrance_floor_index, start, st)

	# Fixpoint: drain the frontier, then resolve or downgrade gated doors,
	# repeat until full coverage or no repair is possible. Each outer iteration
	# permanently opens at least one door or ends the loop, so iterations are
	# bounded by the dungeon's total door count.
	while true:
		_drain(floors, st)

		if not (st["pending"] as Array).is_empty():
			var candidates: Array = _candidate_rooms(st, entrance_room_id, entrance_floor_index)
			if candidates.is_empty():
				# §10.4 — a gated door hit before any room has been discovered
				# sits on the sole entrance path. Downgrade ONLY the first one,
				# then re-drain: the opened door may reveal rooms that let the
				# remaining gated doors keep their keys/levers.
				var first: Dictionary = (st["pending"] as Array).pop_front()
				var ffi: int = first["floor_idx"]
				var fdoor: DungeonDoorData = first["door"]
				(st["pending_set"] as Dictionary).erase(_cell_key(ffi, fdoor.position))
				_downgrade_gated_door(floors[ffi - 1], fdoor, ffi)
				_mark_reached(floors, ffi, fdoor.position, st)
				continue
			for entry in st["pending"]:
				var fi: int = entry["floor_idx"]
				var door: DungeonDoorData = entry["door"]
				if door.type == DungeonDoorData.TYPE_PORTCULLIS:
					_wire_lever(floors, fi, door, candidates, entrance_floor_index, rng)
				else:
					keys.append(_make_key(fi, door, candidates, entrance_floor_index, rng))
				# The door is now model-passable — walk through it.
				_mark_reached(floors, fi, door.position, st)
			(st["pending"] as Array).clear()
			st["pending_set"] = {}
			continue

		# Frontier exhausted, nothing gated left. Done — unless mandatory
		# content (a stair or an entire room) is still unreached behind a
		# secret+unlocked door, which carries no key and is model-impassable.
		if _coverage_complete(floors, st):
			break
		if not _downgrade_one_blocking_secret(floors, st):
			# No secret door borders the unreached region either: structural
			# disconnection. The orchestrator's §9.1 carving / retry path owns
			# this case; solvability will flag it.
			push_warning("DungeonKeyLeverPlacer: unreached cells remain and no blocking secret door found — layout is structurally disconnected.")
			break

	return keys


# ---------------------------------------------------------------------------
# §5 step 7  finalize_key_placements()
# ---------------------------------------------------------------------------

## For each key, assign its final placed_in type based on what is present in
## its chosen room.  May force a type-"A" hoard onto empty rooms.
static func finalize_key_placements(
		keys: Array[KeyItemData],
		floors: Array[DungeonLayout],
		loader: DungeonDataLoader,
		rng: RandomNumberGenerator) -> void:

	for k: KeyItemData in keys:
		if k.placed_on_floor_index < 1 or k.placed_on_floor_index > floors.size():
			continue
		var layout: DungeonLayout = floors[k.placed_on_floor_index - 1]
		var room: DungeonRoomData = layout.find_room(k.placed_in_room_id)
		if room == null:
			continue

		if room.monster_group_id != "":
			# Room has a monster: key goes in monster inventory.
			k.placed_in = KeyItemData.PLACED_MONSTER_INV
			# Append key to the group's initial_inventory.
			_append_key_to_monster_group(layout, room.monster_group_id, k.id)

		elif room.treasure_hoard_id != "":
			k.placed_in = KeyItemData.PLACED_TREASURE_HOARD

		elif room.monster_group_id == "" and room.treasure_hoard_id == "":
			# Empty room: force a type-"A" hoard.
			var h: TreasureHoardData = DungeonTreasureResolver.resolve_treasure_type("A", loader, rng)
			h.id = CampaignRepository.generate_id()
			h.floor_index = k.placed_on_floor_index
			h.room_id = room.id
			h.source = TreasureHoardData.SOURCE_LAIR
			layout.treasure_hoards.append(h)
			room.treasure_hoard_id = h.id
			k.placed_in = KeyItemData.PLACED_TREASURE_HOARD

		else:
			k.placed_in = KeyItemData.PLACED_LOOSE


# ---------------------------------------------------------------------------
# Discovery BFS internals
# ---------------------------------------------------------------------------

## Mark (fi, pos) reached: update the reachable set, the per-room discovery
## counts (promoting rooms to full when their last cell is reached), enqueue
## the cell for neighbour expansion, and follow stairs to the adjacent floor.
static func _mark_reached(
		floors: Array[DungeonLayout],
		fi: int,
		pos: Vector2i,
		st: Dictionary) -> void:
	var ck: String = _cell_key(fi, pos)
	if (st["reachable"] as Dictionary).has(ck):
		return
	st["reachable"][ck] = true
	(st["queue"] as Array).append({"floor_idx": fi, "pos": pos})

	var layout: DungeonLayout = floors[fi - 1]
	var cell: DungeonCellData = layout.get_cell_at(pos)
	if cell == null:
		return

	# Room discovery bookkeeping.
	if cell.room_id >= 0:
		var rk: String = "%d:%d" % [fi, cell.room_id]
		var count: int = int((st["room_reached"] as Dictionary).get(rk, 0)) + 1
		st["room_reached"][rk] = count
		var room: DungeonRoomData = (st["room_index"] as Dictionary).get(rk, null)
		if room != null and count >= room.cells.size() and not (st["full_room_set"] as Dictionary).has(rk):
			st["full_room_set"][rk] = true
			(st["full_rooms"] as Array).append({"room": room, "floor_idx": fi})

	# Stair: the matching stair on the adjacent floor joins the frontier
	# (same convention as DungeonNavigabilityValidator._expand_stair).
	if cell.is_stair():
		var stair_data: DungeonStairData = null
		for s: DungeonStairData in layout.stairs:
			if s.position == pos:
				stair_data = s
				break
		if stair_data != null:
			var dest_fi: int
			if stair_data.connects_to_level > 0:
				dest_fi = stair_data.connects_to_level
			elif stair_data.direction == DungeonStairData.DIRECTION_DOWN:
				dest_fi = fi + 1
			else:
				dest_fi = fi - 1
			if dest_fi >= 1 and dest_fi <= floors.size():
				var dest_cell: DungeonCellData = (floors[dest_fi - 1] as DungeonLayout).get_cell_at(pos)
				if dest_cell != null and dest_cell.is_stair():
					_mark_reached(floors, dest_fi, pos, st)


## Drain the BFS queue. Walkable neighbours are marked reached; gated doors
## (key/lever required) are recorded in `pending`; secret+unlocked doors are
## recorded in `secret_blockers`; walls are skipped.
static func _drain(floors: Array[DungeonLayout], st: Dictionary) -> void:
	var queue: Array = st["queue"]
	while not queue.is_empty():
		var item: Dictionary = queue.pop_front()
		var fi: int = item["floor_idx"]
		var pos: Vector2i = item["pos"]
		var layout: DungeonLayout = floors[fi - 1]

		for nb: Vector2i in _neighbours(pos):
			if nb.x < 0 or nb.y < 0 or nb.x >= layout.grid_width or nb.y >= layout.grid_height:
				continue
			var nb_key: String = _cell_key(fi, nb)
			if (st["reachable"] as Dictionary).has(nb_key):
				continue
			var nb_cell: DungeonCellData = layout.get_cell_at(nb)
			if nb_cell == null:
				continue

			if nb_cell.is_door():
				var door: DungeonDoorData = layout.find_door_at(nb)
				if door == null:
					# Door cell with no DoorData — treat as passable (mirrors
					# validate_solvability's fallthrough).
					_mark_reached(floors, fi, nb, st)
				elif _door_initially_passable(door):
					_mark_reached(floors, fi, nb, st)
				elif door.is_secret and not _needs_key(door):
					# Secret+unlocked: model-impassable, carries no key. Record
					# for the coverage repair; do not traverse.
					if not (st["secret_blocker_set"] as Dictionary).has(nb_key):
						st["secret_blocker_set"][nb_key] = true
						(st["secret_blockers"] as Array).append({"floor_idx": fi, "door": door})
				else:
					# Gated: locked/trapped needing a key, or a portcullis
					# awaiting a lever. Queue for placement.
					if not (st["pending_set"] as Dictionary).has(nb_key):
						st["pending_set"][nb_key] = true
						(st["pending"] as Array).append({"floor_idx": fi, "door": door})
			elif nb_cell.passable or nb_cell.is_stair():
				_mark_reached(floors, fi, nb, st)
			# else: wall / rock — skip.


## A door the player can pass in its INITIAL state with no key/lever placed:
## arches, curtains, plain unlocked doors, bashable (wood) non-secret
## locked/trapped doors. Portcullises and key-needing doors return false (the
## placer wires/keys them when the frontier arrives). Secret doors return
## false in all cases (handled by the caller's secret/gated branches).
static func _door_initially_passable(door: DungeonDoorData) -> bool:
	if door.is_secret:
		return false
	if door.type == DungeonDoorData.TYPE_ARCH or DungeonDoorData.is_curtain(door.door_material):
		return true
	if door.type == DungeonDoorData.TYPE_UNLOCKED:
		return true
	if door.type == DungeonDoorData.TYPE_LOCKED or door.type == DungeonDoorData.TYPE_TRAPPED:
		return DungeonDoorData.is_bashable(door.door_material)
	return false


## True for doors that require a placed key (mirrors the §10.1 inventory rule):
## locked/trapped AND (secret OR stone/metal material).
static func _needs_key(door: DungeonDoorData) -> bool:
	if door.type != DungeonDoorData.TYPE_LOCKED and door.type != DungeonDoorData.TYPE_TRAPPED:
		return false
	if door.is_secret:
		return true
	return (door.door_material == DungeonDoorData.MATERIAL_STONE
		or door.door_material == DungeonDoorData.MATERIAL_METAL)


# ---------------------------------------------------------------------------
# Key / lever resolution against discovered rooms
# ---------------------------------------------------------------------------

## Candidate rooms for key/lever placement: rooms whose every cell has been
## discovered (fully outside all still-closed doors), excluding the entrance
## room per §10.3 step 2. Returned in discovery order (deterministic).
static func _candidate_rooms(
		st: Dictionary,
		entrance_room_id: int,
		entrance_floor_index: int) -> Array:
	var out: Array = []
	for entry in st["full_rooms"]:
		var room: DungeonRoomData = entry["room"]
		var fi: int = entry["floor_idx"]
		if fi == entrance_floor_index and room.id == entrance_room_id:
			continue
		if room.cells.is_empty():
			continue
		out.append(entry)
	return out


## Create the KeyItemData for a gated door, choosing the key room from the
## candidates weighted by floor proximity (§10.3 step 3: same floor 5,
## adjacent floor 2, further 1).
static func _make_key(
		door_floor_idx: int,
		door: DungeonDoorData,
		candidates: Array,
		_entrance_floor_index: int,
		rng: RandomNumberGenerator) -> KeyItemData:
	var pick: Dictionary = _pick_weighted_candidate(candidates, door_floor_idx, rng)
	var k: KeyItemData = KeyItemData.new()
	k.id = CampaignRepository.generate_id()
	k.opens_door_floor_index = door_floor_idx
	k.opens_door_position = door.position
	k.placed_on_floor_index = pick["floor_idx"]
	k.placed_in_room_id = (pick["room"] as DungeonRoomData).id
	k.placed_in = KeyItemData.PLACED_LOOSE  # finalized later
	return k


## Wire a portcullis to a lever cell in a discovered room (§10.3 step 6).
## If the chosen room yields no usable cell the portcullis is left unwired —
## forceable per §9.2, a soft acceptance warning only.
static func _wire_lever(
		floors: Array[DungeonLayout],
		door_floor_idx: int,
		door: DungeonDoorData,
		candidates: Array,
		_entrance_floor_index: int,
		rng: RandomNumberGenerator) -> void:
	var pick: Dictionary = _pick_weighted_candidate(candidates, door_floor_idx, rng)
	var chosen_room: DungeonRoomData = pick["room"]
	var chosen_floor_idx: int = pick["floor_idx"]
	var lever_pos: Vector2i = _pick_lever_cell(chosen_room, chosen_floor_idx, floors)
	if lever_pos == Vector2i(-1, -1):
		return  # unwired portcullis: forceable per §9.2
	door.wired_lever_position = lever_pos
	var lever_layout: DungeonLayout = floors[chosen_floor_idx - 1]
	var lever_cell: DungeonCellData = lever_layout.get_cell_at(lever_pos)
	if lever_cell != null:
		lever_cell.terrain_feature = "lever_portcullis_%d_%d" % [door.position.x, door.position.y]


## Weighted pick among candidate rooms by floor proximity to the door.
## Weights: same floor = 5, |Δfloor| == 1 = 2, else 1.
static func _pick_weighted_candidate(
		candidates: Array,
		door_floor_idx: int,
		rng: RandomNumberGenerator) -> Dictionary:
	var weights: Array[int] = []
	var total_weight := 0
	for entry in candidates:
		var fi: int = entry["floor_idx"]
		var delta: int = absi(fi - door_floor_idx)
		var w: int
		if delta == 0:
			w = 5
		elif delta == 1:
			w = 2
		else:
			w = 1
		weights.append(w)
		total_weight += w
	var roll: int = rng.randi_range(0, total_weight - 1)
	var acc := 0
	for i: int in range(candidates.size()):
		acc += weights[i]
		if roll < acc:
			return candidates[i]
	return candidates[candidates.size() - 1]


# ---------------------------------------------------------------------------
# §10.4 downgrades and secret-door coverage repair
# ---------------------------------------------------------------------------

## §10.4: a gated door hit before any candidate room exists sits on the sole
## entrance path. Downgrade it to a plain unlocked wood door (no key, not
## secret). A downgraded trap-room gate demotes the room to "empty" when it
## was the room's only qualifying door, keeping Hard Test 6 consistent.
static func _downgrade_gated_door(
		layout: DungeonLayout,
		door: DungeonDoorData,
		floor_idx: int) -> void:
	push_warning("DungeonKeyLeverPlacer: no candidate room for %s door at floor %d %s — downgrading to unlocked wood_standard." % [door.type, floor_idx, door.position])
	var was_qualifying: bool = door.is_secret and (
		door.type == DungeonDoorData.TYPE_LOCKED or door.type == DungeonDoorData.TYPE_TRAPPED)
	door.type = DungeonDoorData.TYPE_UNLOCKED
	door.door_material = DungeonDoorData.MATERIAL_WOOD_STANDARD
	door.is_secret = false
	door.wired_lever_position = Vector2i(-1, -1)
	if was_qualifying:
		_demote_ungated_trap_rooms(layout, door)


## If `door` was a trap room's qualifying gate, demote any connected
## trap_placeholder room that now has zero qualifying doors to "empty"
## (mirrors the §10.4 / §11.4 consistency rule).
static func _demote_ungated_trap_rooms(layout: DungeonLayout, door: DungeonDoorData) -> void:
	for connected_room_id: int in door.connects:
		if connected_room_id < 0:
			continue
		var connected_room: DungeonRoomData = layout.find_room(connected_room_id)
		if connected_room == null or connected_room.contents_kind != "trap_placeholder":
			continue
		var remaining_qualifying := 0
		for rd: DungeonDoorData in connected_room.doors:
			if rd.is_secret and (
				rd.type == DungeonDoorData.TYPE_LOCKED
				or rd.type == DungeonDoorData.TYPE_TRAPPED
			):
				remaining_qualifying += 1
		if remaining_qualifying == 0:
			connected_room.contents_kind = "empty"
			connected_room.current_purpose = connected_room.original_purpose


## True when every stair and every room (>= 1 cell) on every floor has been
## reached — the same criteria validate_solvability enforces.
static func _coverage_complete(floors: Array[DungeonLayout], st: Dictionary) -> bool:
	var reachable: Dictionary = st["reachable"]
	for fi: int in range(1, floors.size() + 1):
		var layout: DungeonLayout = floors[fi - 1]
		for stair: DungeonStairData in layout.stairs:
			if not reachable.has(_cell_key(fi, stair.position)):
				return false
		for room: DungeonRoomData in layout.rooms:
			var any_reached := false
			for rc: Vector2i in room.cells:
				if reachable.has(_cell_key(fi, rc)):
					any_reached = true
					break
			if not any_reached and not room.cells.is_empty():
				return false
	return true


## Open ONE recorded secret+unlocked frontier door whose far side is still
## unreached (clear is_secret; type stays unlocked, material stays wood per
## §8.3 step 2). Returns true if a door was opened (the caller re-drains).
## Doors guarding pockets the BFS already reached another way are left secret.
static func _downgrade_one_blocking_secret(floors: Array[DungeonLayout], st: Dictionary) -> bool:
	var reachable: Dictionary = st["reachable"]
	for entry in st["secret_blockers"]:
		var fi: int = entry["floor_idx"]
		var door: DungeonDoorData = entry["door"]
		if not door.is_secret:
			continue  # already opened by an earlier repair pass
		var layout: DungeonLayout = floors[fi - 1]
		var blocks_unreached := false
		for nb: Vector2i in _neighbours(door.position):
			if reachable.has(_cell_key(fi, nb)):
				continue
			var nb_cell: DungeonCellData = layout.get_cell_at(nb)
			if nb_cell != null and (nb_cell.passable or nb_cell.is_door() or nb_cell.is_stair()):
				blocks_unreached = true
				break
		if not blocks_unreached:
			continue
		push_warning("DungeonKeyLeverPlacer: secret door at floor %d %s gates mandatory content with no key path — clearing is_secret (§10.4 repair)." % [fi, door.position])
		door.is_secret = false
		_mark_reached(floors, fi, door.position, st)
		return true
	return false


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

## Find the room id on the entrance floor that contains the entrance cell (or
## is adjacent to it).  Returns -1 if not determinable.
static func _find_entrance_room_id(
		floors: Array[DungeonLayout],
		entrance_floor_index: int) -> int:
	if entrance_floor_index < 1 or entrance_floor_index > floors.size():
		return -1
	var layout: DungeonLayout = floors[entrance_floor_index - 1]
	var entrance_cell: DungeonCellData = layout.get_cell_at(layout.entrance)
	if entrance_cell != null and entrance_cell.room_id >= 0:
		return entrance_cell.room_id
	# Check neighbours.
	for nb: Vector2i in _neighbours(layout.entrance):
		var nb_cell: DungeonCellData = layout.get_cell_at(nb)
		if nb_cell != null and nb_cell.room_id >= 0:
			return nb_cell.room_id
	return -1


## Pick a cell in the chosen room that is adjacent to an impassable/wall cell.
## Returns Vector2i(-1,-1) if none found.
static func _pick_lever_cell(
		room: DungeonRoomData,
		floor_idx: int,
		floors: Array[DungeonLayout]) -> Vector2i:
	if floor_idx < 1 or floor_idx > floors.size():
		return Vector2i(-1, -1)
	var layout: DungeonLayout = floors[floor_idx - 1]

	var candidates: Array[Vector2i] = []
	for rc: Vector2i in room.cells:
		for nb: Vector2i in _neighbours(rc):
			var nb_cell: DungeonCellData = layout.get_cell_at(nb)
			if nb_cell == null or not nb_cell.passable:
				# This room cell is adjacent to a wall/impassable cell.
				candidates.append(rc)
				break

	if candidates.is_empty():
		# Fallback: just use the first room cell.
		if room.cells.size() > 0:
			return room.cells[0]
		return Vector2i(-1, -1)

	# Pick the first candidate (deterministic; rng not threaded here to avoid
	# changing the caller's rng state unexpectedly — the choice among wall-adjacent
	# cells within a room has no strategic significance).
	return candidates[0]


## Append a key entry to the monster group's initial_inventory.
static func _append_key_to_monster_group(
		layout: DungeonLayout,
		monster_group_id: String,
		key_id: String) -> void:
	for mg: MonsterGroupData in layout.monster_groups:
		if mg.id == monster_group_id:
			mg.initial_inventory.append({"item_type": "key", "key_id": key_id})
			return


## 4-neighbourhood.
static func _neighbours(pos: Vector2i) -> Array[Vector2i]:
	return [
		Vector2i(pos.x - 1, pos.y),
		Vector2i(pos.x + 1, pos.y),
		Vector2i(pos.x, pos.y - 1),
		Vector2i(pos.x, pos.y + 1),
	]


## Encoded cell key for multi-floor dictionaries.
static func _cell_key(floor_idx: int, pos: Vector2i) -> String:
	return "%d:%d:%d" % [floor_idx, pos.x, pos.y]
