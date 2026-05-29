class_name DungeonKeyLeverPlacer
extends RefCounted

## Places keys and portcullis levers for locked stone/metal doors (§10) and
## portcullises (§10.3) across a multi-floor dungeon.
##
## place() runs the full §10 algorithm, returning an Array[KeyItemData] for
## locked doors that received keys.  Portcullis levers are embedded directly
## in DungeonDoorData.wired_lever_position (no KeyItem).
##
## finalize_key_placements() converts each key's PLACED_LOOSE placement into
## a specific sub-type (monster inventory, treasure hoard, or a forced hoard)
## per §5 step 7.
##
## Reference: gdd-dungeon-generator-v1.md §10.


# ---------------------------------------------------------------------------
# §10  place()
# ---------------------------------------------------------------------------

## Main entry point.  For every locked-stone/metal door and every portcullis
## across all floors, computes the §10.2 outside region and either assigns a
## key/lever or applies the §10.4 downgrade.
##
## Returns Array[KeyItemData] — keys only (levers live on DoorData).
static func place(
		floors: Array[DungeonLayout],
		entrance_floor_index: int,
		rng: RandomNumberGenerator) -> Array[KeyItemData]:

	var keys: Array[KeyItemData] = []

	# Collect entrance room id for filtering (§10.2 — drop entrance room from candidates).
	var entrance_room_id: int = _find_entrance_room_id(floors, entrance_floor_index)

	# Iterate every floor, every door.
	for floor_idx: int in range(1, floors.size() + 1):
		var layout: DungeonLayout = floors[floor_idx - 1]
		for door: DungeonDoorData in layout.doors:
			var needs_key: bool = _is_lockable_door(door)
			var is_portcullis: bool = door.type == DungeonDoorData.TYPE_PORTCULLIS

			if not needs_key and not is_portcullis:
				continue

			# §10.2: compute outside region with this door permanently blocked,
			# all other doors treated as passable (including secret/locked/portcullis).
			var outside: Dictionary = _compute_outside_region(
					floors, entrance_floor_index, floor_idx, door.position)

			# Check whether any candidate rooms exist (rooms entirely in outside,
			# excluding entrance room). _pick_weighted_room_full does this check
			# internally; pre-check here for the §10.4 downgrade guard.
			var probe_rooms: Array[DungeonRoomData] = []
			var probe_floors: Array = []
			_candidate_rooms_with_floors(floors, outside, entrance_room_id,
					entrance_floor_index, probe_rooms, probe_floors)

			if probe_rooms.is_empty():
				# §10.4 downgrade: no outside region usable.
				if needs_key:
					push_warning("DungeonKeyLeverPlacer: no outside region for locked door at floor %d %s — downgrading to unlocked wood_standard." % [floor_idx, door.position])
					# Change type, material, AND clear secret flag. A downgraded door
					# becomes an ordinary unlocked wood door — no key needed, not secret.
					# Keeping type=LOCKED with no key OR keeping is_secret=true would
					# make solvability treat the door as permanently blocking.
					door.door_material = DungeonDoorData.MATERIAL_WOOD_STANDARD
					door.type = DungeonDoorData.TYPE_UNLOCKED
					door.is_secret = false
					# If this door was the qualifying secret+locked door for a
					# trap_placeholder room, that room's trap mechanism no longer
					# exists — demote it to "empty" so Hard Test 6 stays consistent.
					for connected_room_id: int in door.connects:
						if connected_room_id < 0:
							continue
						var connected_room: DungeonRoomData = layout.find_room(connected_room_id)
						if connected_room == null or connected_room.contents_kind != "trap_placeholder":
							continue
						# Count remaining qualifying doors on this room after downgrade.
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
				elif is_portcullis:
					push_warning("DungeonKeyLeverPlacer: no outside region for portcullis at floor %d %s — downgrading to unlocked." % [floor_idx, door.position])
					door.type = DungeonDoorData.TYPE_UNLOCKED
					door.door_material = DungeonDoorData.MATERIAL_WOOD_STANDARD
				continue

			# Pick one room weighted by floor proximity to the door's floor.
			var pick: Dictionary = _pick_weighted_room_full(
					floors, outside, entrance_room_id, entrance_floor_index, floor_idx, rng)
			var chosen_room: DungeonRoomData = pick["room"]
			var chosen_floor_idx: int = pick["floor_idx"]

			if chosen_room == null:
				# Should not happen if candidates is non-empty, but guard.
				continue

			if needs_key:
				# Create KeyItemData.
				var k: KeyItemData = KeyItemData.new()
				k.id = CampaignRepository.generate_id()
				k.opens_door_floor_index = floor_idx
				k.opens_door_position = door.position
				k.placed_on_floor_index = chosen_floor_idx
				k.placed_in_room_id = chosen_room.id
				k.placed_in = KeyItemData.PLACED_LOOSE  # finalized later
				keys.append(k)

			elif is_portcullis:
				# Place lever: pick an adjacent-to-wall cell in the chosen room.
				var lever_pos: Vector2i = _pick_lever_cell(chosen_room, chosen_floor_idx, floors)
				if lever_pos != Vector2i(-1, -1):
					door.wired_lever_position = lever_pos
					# Stamp terrain_feature on the cell.
					var lever_layout: DungeonLayout = floors[chosen_floor_idx - 1]
					var lever_cell: DungeonCellData = lever_layout.get_cell_at(lever_pos)
					if lever_cell != null:
						lever_cell.terrain_feature = "lever_portcullis_%d_%d" % [door.position.x, door.position.y]
				# If no suitable cell found, leave wired_lever_position at (-1,-1)
				# (portcullis becomes forceable per §9.2 convention).

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
# Internal helpers
# ---------------------------------------------------------------------------

## True for locked or trapped doors that require a key.
##
## Non-secret wood doors: bashable (§10 preamble) → no key needed.
## Secret locked/trapped doors: the solvability BFS blocks on is_secret even for
## wood; a key ensures the fixed-point BFS can eventually unlock them.
## Non-bashable (stone / metal) doors always need a key.
static func _is_lockable_door(door: DungeonDoorData) -> bool:
	if door.type != DungeonDoorData.TYPE_LOCKED and door.type != DungeonDoorData.TYPE_TRAPPED:
		return false
	# Secret doors: always require a key regardless of material.
	# (Without a key, solvability BFS permanently blocks on is_secret.)
	if door.is_secret:
		return true
	# Non-secret: only stone/metal need a key (wood is bashable).
	return (door.door_material == DungeonDoorData.MATERIAL_STONE
		or door.door_material == DungeonDoorData.MATERIAL_METAL)


## BFS from the dungeon entrance across all floors with `target_door` permanently
## blocked.  All other doors (including secret, locked, portcullis) are treated
## as passable.  Stairs followed normally.
##
## Returns a Dictionary of encoded cell keys that are reachable:
##   "floor_idx:x:y" -> true.
static func _compute_outside_region(
		floors: Array[DungeonLayout],
		entrance_floor_index: int,
		target_door_floor: int,
		target_door_pos: Vector2i) -> Dictionary:

	var reachable: Dictionary = {}
	if entrance_floor_index < 1 or entrance_floor_index > floors.size():
		return reachable

	var entrance_floor: DungeonLayout = floors[entrance_floor_index - 1]
	var start: Vector2i = entrance_floor.entrance

	var queue: Array = []  # {floor_idx:int, pos:Vector2i}
	var start_key: String = _cell_key(entrance_floor_index, start)
	reachable[start_key] = true
	queue.append({"floor_idx": entrance_floor_index, "pos": start})

	while queue.size() > 0:
		var item: Dictionary = queue.pop_front()
		var fi: int = item["floor_idx"]
		var pos: Vector2i = item["pos"]
		var layout: DungeonLayout = floors[fi - 1]

		# Stair expansion.
		var cell: DungeonCellData = layout.get_cell_at(pos)
		if cell != null and cell.is_stair():
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
					var dest_key: String = _cell_key(dest_fi, pos)
					if not reachable.has(dest_key):
						reachable[dest_key] = true
						queue.append({"floor_idx": dest_fi, "pos": pos})

		# 4-neighbours.
		for nb: Vector2i in _neighbours(pos):
			if nb.x < 0 or nb.y < 0 or nb.x >= layout.grid_width or nb.y >= layout.grid_height:
				continue
			var nb_key: String = _cell_key(fi, nb)
			if reachable.has(nb_key):
				continue
			var nb_cell: DungeonCellData = layout.get_cell_at(nb)
			if nb_cell == null:
				continue
			# The target door is permanently blocked.
			if fi == target_door_floor and nb == target_door_pos:
				continue
			# Solid walls / rock: not traversable.
			if not nb_cell.passable and not nb_cell.is_door() and not nb_cell.is_stair():
				continue
			# Secret doors are treated as IMPASSABLE (same as solvability §9.2).
			# This prevents keys from being placed in rooms only accessible via
			# other secret doors, which would create circular key dependencies that
			# the solvability fixed-point BFS cannot resolve.
			if nb_cell.is_door():
				var nb_door: DungeonDoorData = (floors[fi - 1] as DungeonLayout).find_door_at(nb)
				if nb_door != null and nb_door.is_secret:
					continue
			reachable[nb_key] = true
			queue.append({"floor_idx": fi, "pos": nb})

	return reachable


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


## Fills both `rooms_out` and `floor_idxs_out` in lockstep so callers can
## retrieve the floor index for each room.
static func _candidate_rooms_with_floors(
		floors: Array[DungeonLayout],
		outside: Dictionary,
		entrance_room_id: int,
		entrance_floor_index: int,
		rooms_out: Array[DungeonRoomData],
		floor_idxs_out: Array) -> void:
	for floor_idx: int in range(1, floors.size() + 1):
		var layout: DungeonLayout = floors[floor_idx - 1]
		for room: DungeonRoomData in layout.rooms:
			# Drop the entrance room.
			if floor_idx == entrance_floor_index and room.id == entrance_room_id:
				continue
			# All room cells must be in outside region.
			var all_in := true
			for rc: Vector2i in room.cells:
				if not outside.has(_cell_key(floor_idx, rc)):
					all_in = false
					break
			if all_in and room.cells.size() > 0:
				rooms_out.append(room)
				floor_idxs_out.append(floor_idx)


## Selects one room from the outside region weighted by floor proximity.
## Returns {room, floor_idx} or {room:null, floor_idx:-1}.
## Weights: same floor as door = 5, |Δfloor|==1 = 2, else = 1.
static func _pick_weighted_room_full(
		floors: Array[DungeonLayout],
		outside: Dictionary,
		entrance_room_id: int,
		entrance_floor_index: int,
		door_floor_idx: int,
		rng: RandomNumberGenerator) -> Dictionary:
	var rooms: Array[DungeonRoomData] = []
	var floor_idxs: Array = []
	_candidate_rooms_with_floors(floors, outside, entrance_room_id,
			entrance_floor_index, rooms, floor_idxs)

	if rooms.is_empty():
		return {"room": null, "floor_idx": -1}

	# Compute weights.
	var weights: Array[int] = []
	var total_weight := 0
	for i: int in range(rooms.size()):
		var fi: int = floor_idxs[i]
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

	if total_weight <= 0:
		return {"room": null, "floor_idx": -1}

	var roll: int = rng.randi_range(0, total_weight - 1)
	var acc := 0
	for i: int in range(rooms.size()):
		acc += weights[i]
		if roll < acc:
			return {"room": rooms[i], "floor_idx": floor_idxs[i]}

	return {"room": rooms[rooms.size() - 1], "floor_idx": floor_idxs[floor_idxs.size() - 1]}


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
