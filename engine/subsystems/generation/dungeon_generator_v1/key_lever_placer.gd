class_name DungeonKeyLeverPlacer
extends RefCounted

## Places keys and portcullis levers for locked stone/metal doors (§10) and
## portcullises (§10.3) across the composed contiguous-3D dungeon volume.
##
## place_composed() runs the §10 algorithm as a single discovery-order fixpoint
## BFS over the composed VoxelMapData, using MovementRules for step legality (the
## SAME predicate DungeonNavigabilityValidator consumes — no independent
## stair/support logic here). When the frontier hits a gated door (locked/trapped
## stone-metal, any secret+locked/trapped, or a portcullis), its key/lever is
## placed in a ZONE that is ALREADY fully discovered (excluding the entrance zone
## and every circulation-room zone) — so every key is reachable before its door by
## construction and circular key dependencies cannot occur. Repair ladder per
## contiguous GDD §10.3 (sole-path downgrade, frontier secret-clear, rule-3
## structural hard-fail). Returns key records + wired levers; the generator
## converts them to KeyItemData via composed_keys_to_items().
##
## finalize_key_placements_composed() converts each key's PLACED_LOOSE placement
## into a specific sub-type (monster inventory, treasure hoard, or a forced hoard)
## per §5 step 7, resolving containment against the key's ZONE.
##
## (The legacy per-floor 2D place()/finalize BFS was removed at DG-C3D.F.3; the
## composed pipeline is the only path. finalize_key_placements() survives as the
## defensive room-based fallback finalize_key_placements_composed() invokes when a
## zone record is unexpectedly absent.)
##
## Reference: gdd-dungeon-generator-v1.md §10; gdd-dungeon-contiguous-3d.md §10.3.


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


## Zone-aware §5-step-7 finalize (DG-C3D.F.2d): each key's containment
## resolves against its ZONE's stocking (a key placed on a balcony embeds in
## the balcony's monster/hoard, not the room's main floor). For zone-0 keys
## this is draw-for-draw identical to the legacy finalize above — zone 0's
## stocking fields mirror the room's (map_band_stocking_to_zones runs first),
## so the branch decisions and the forced-hoard RNG draws match exactly.
##
## Forced type-"A" hoards for keys in EMPTY zones attach per the §121 id
## model: a zone-0 key's hoard goes on the room's home band layout with the
## LOCAL room id + updates the room back-link (legacy behavior); a balcony
## key's hoard goes on the ZONE's band layout with the GLOBAL room id + the
## zone back-link. Forced hoards are unplaced (no cell) in both cases,
## matching the legacy finalize.
static func finalize_key_placements_composed(
		keys: Array[KeyItemData],
		floors: Array[DungeonLayout],
		zones: Array,
		loader: DungeonDataLoader,
		rng: RandomNumberGenerator) -> void:
	var layout_by_floor: Dictionary = {}
	for fl in floors:
		layout_by_floor[(fl as DungeonLayout).level_number] = fl
	var zone_by_key: Dictionary = {}
	for z in zones:
		var zone: RoomZone = z
		zone_by_key["%d:%d" % [zone.room_id, zone.zone_index]] = zone

	for k: KeyItemData in keys:
		if k.placed_on_floor_index < 1 or k.placed_on_floor_index > floors.size():
			continue
		var home_layout: DungeonLayout = floors[k.placed_on_floor_index - 1]
		var room: DungeonRoomData = home_layout.find_room(k.placed_in_room_id)
		if room == null:
			continue
		var global_room: int = (k.placed_on_floor_index - 1) * DungeonVolumeComposer.ROOM_ID_STRIDE + k.placed_in_room_id
		var zone_index: int = maxi(k.placed_in_zone_index, 0)
		var zone: RoomZone = zone_by_key.get("%d:%d" % [global_room, zone_index], null)
		if zone == null:
			# No composed zone record (defensive) — legacy room-based fallback.
			push_warning("DungeonKeyLeverPlacer.finalize_key_placements_composed: no zone (room %d, zone %d) for a key — falling back to room fields." % [global_room, zone_index])
			var single: Array[KeyItemData] = [k]
			finalize_key_placements(single, floors, loader, rng)
			continue
		var content_layout: DungeonLayout = layout_by_floor.get(zone.band, home_layout)

		if zone.monster_group_id != "":
			k.placed_in = KeyItemData.PLACED_MONSTER_INV
			_append_key_to_monster_group(content_layout, zone.monster_group_id, k.id)
		elif zone.treasure_hoard_id != "":
			k.placed_in = KeyItemData.PLACED_TREASURE_HOARD
		else:
			# Empty zone: force a type-"A" hoard into it.
			var h: TreasureHoardData = DungeonTreasureResolver.resolve_treasure_type("A", loader, rng)
			h.id = CampaignRepository.generate_id()
			h.source = TreasureHoardData.SOURCE_LAIR
			if zone.zone_index == 0:
				h.floor_index = k.placed_on_floor_index
				h.room_id = room.id
				home_layout.treasure_hoards.append(h)
				room.treasure_hoard_id = h.id
			else:
				h.floor_index = zone.band
				h.room_id = zone.room_id  # global (zone_index >= 1 — §121)
				content_layout.treasure_hoards.append(h)
			zone.treasure_hoard_id = h.id
			k.placed_in = KeyItemData.PLACED_TREASURE_HOARD


# ---------------------------------------------------------------------------
# §10.4 downgrades and secret-door coverage repair
# ---------------------------------------------------------------------------

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


## Append a key entry to the monster group's initial_inventory.
static func _append_key_to_monster_group(
		layout: DungeonLayout,
		monster_group_id: String,
		key_id: String) -> void:
	for mg: MonsterGroupData in layout.monster_groups:
		if mg.id == monster_group_id:
			mg.initial_inventory.append({"item_type": "key", "key_id": key_id})
			return


# =========================================================================
# DG-C3D.E — composed-volume discovery-order placement (over zones)
# =========================================================================
#
# A single discovery-order fixpoint over the composed 3D volume, using
# MovementRules for step legality (the SAME predicate the navigability
# validator uses — no independent stair/support logic here). When the frontier
# reaches a gated door its key/lever is placed in a fully-discovered ZONE
# (excluding the entrance zone and circulation-room zones), so every key is
# reachable before its door by construction. Repair ladder per contiguous GDD
# §10.3. Mutates door cells + records in place. (The legacy per-floor 2D place()
# was removed at DG-C3D.F.3 — this is the only key/lever path.)

## Returns {keys: Array[Dictionary], wired_levers: Dictionary, solved: bool,
##          warnings: Array}. Each key = {opens_door_cell: Vector3i, room_id,
## band, zone_index, zone_cells: Array[Vector3i]}. wired_levers maps a portcullis
## door cell -> its lever cell.
static func place_composed(
		volume: VoxelMapData,
		zones: Array[RoomZone],
		stairwells: Array[StairwellData],
		rooms: Array[DungeonRoomData],
		doors: Array,
		band_walk: Dictionary,
		entrance_pos: Vector3i,
		rng: RandomNumberGenerator) -> Dictionary:
	var out_keys: Array = []
	var wired_levers: Dictionary = {}
	var warnings: Array = []

	# Zone bookkeeping: zone_key "room:zone" -> {band, total}; cell -> zone_key.
	var zone_meta: Dictionary = {}
	var cell_to_zone: Dictionary = {}
	for z: RoomZone in zones:
		var zk: String = "%d:%d" % [z.room_id, z.zone_index]
		var walk: int = int(band_walk.get(z.band, 0))
		var vcells: Array[Vector3i] = []
		for c: Vector2i in z.cells:
			var vc := Vector3i(c.x, c.y, walk)
			vcells.append(vc)
			cell_to_zone[vc] = zk
		zone_meta[zk] = {"band": z.band, "total": z.cells.size(), "room_id": z.room_id, "zone_index": z.zone_index, "walk": walk, "cells": vcells}

	var kind_by_room: Dictionary = {}
	for r: DungeonRoomData in rooms:
		kind_by_room[r.id] = r.kind

	var doors_by_cell: Dictionary = {}
	for rec in doors:
		doors_by_cell[rec["cell"]] = rec

	var st: Dictionary = {
		"reachable": {},          # Vector3i -> true
		"queue": [],              # Array[Vector3i]
		"reached_count": {},      # zone_key -> int
		"full_zones": [],         # [zone_key] discovery order
		"full_set": {},           # zone_key -> true
		"pending": [],            # [Vector3i] gated door cells, hit order
		"pending_set": {},
		"secret_blockers": [],    # [Vector3i] secret+unlocked door cells
		"secret_blocker_set": {},
		"zone_meta": zone_meta,
		"cell_to_zone": cell_to_zone,
		"doors_by_cell": doors_by_cell,
	}

	var entrance_zone_key: String = str(cell_to_zone.get(entrance_pos, ""))
	_mark_reached_3d(volume, entrance_pos, st)

	var guard: int = 0
	var max_iters: int = doors.size() + zones.size() + 4
	while true:
		guard += 1
		if guard > max_iters:
			push_error("DungeonKeyLeverPlacer.place_composed: iteration cap %d exceeded — bailing." % max_iters)
			break
		_drain_3d(volume, st)

		if not (st["pending"] as Array).is_empty():
			var candidates: Array = _candidate_zones(st, entrance_zone_key, kind_by_room)
			if candidates.is_empty():
				# §10.4 — gated door on the sole entrance path: downgrade the first.
				var first_cell: Vector3i = (st["pending"] as Array).pop_front()
				(st["pending_set"] as Dictionary).erase(first_cell)
				_downgrade_composed_door(volume, doors_by_cell[first_cell])
				_mark_reached_3d(volume, first_cell, st)
				continue
			for door_cell: Vector3i in st["pending"]:
				var rec: Dictionary = doors_by_cell[door_cell]
				if rec["type"] == DungeonDoorData.TYPE_PORTCULLIS:
					_wire_lever_composed(volume, door_cell, candidates, st, rng, wired_levers)
				else:
					out_keys.append(_make_key_composed(door_cell, rec, candidates, st, rng))
				_mark_reached_3d(volume, door_cell, st)
			(st["pending"] as Array).clear()
			st["pending_set"] = {}
			continue

		# Frontier exhausted, nothing gated. Done unless mandatory content is
		# still unreached behind a secret+unlocked door (no key concept).
		if _coverage_complete_composed(volume, st, zones, stairwells, band_walk):
			return {"keys": out_keys, "wired_levers": wired_levers, "solved": true, "warnings": warnings}
		if not _clear_one_blocking_secret_composed(volume, st):
			# Rule 3: unreached content with no frontier door explaining it — a
			# structural composition defect. Never geometric-repair from the key
			# layer; the whole-dungeon re-seed ladder (DG-C3D.F) owns this.
			warnings.append("DungeonKeyLeverPlacer.place_composed: unreached content with no frontier secret door — structural defect (rule 3), re-seed required.")
			return {"keys": out_keys, "wired_levers": wired_levers, "solved": false, "warnings": warnings}

	return {"keys": out_keys, "wired_levers": wired_levers, "solved": false, "warnings": warnings}


## Mark a composed cell reached; update zone discovery counts (promoting a zone
## to "full" when its last cell is reached) and enqueue for neighbour expansion.
static func _mark_reached_3d(volume: VoxelMapData, pos: Vector3i, st: Dictionary) -> void:
	if (st["reachable"] as Dictionary).has(pos):
		return
	st["reachable"][pos] = true
	(st["queue"] as Array).append(pos)
	var zk: String = str((st["cell_to_zone"] as Dictionary).get(pos, ""))
	if zk == "":
		return
	var count: int = int((st["reached_count"] as Dictionary).get(zk, 0)) + 1
	st["reached_count"][zk] = count
	var meta: Dictionary = st["zone_meta"][zk]
	if count >= int(meta["total"]) and not (st["full_set"] as Dictionary).has(zk):
		st["full_set"][zk] = true
		(st["full_zones"] as Array).append(zk)


## Drain the frontier: walkable open neighbours are reached; door cells are
## classified (initially-passable -> traverse; secret+unlocked -> blocker;
## gated -> pending) using the door record, not per-cell state.
static func _drain_3d(volume: VoxelMapData, st: Dictionary) -> void:
	var queue: Array = st["queue"]
	var doors_by_cell: Dictionary = st["doors_by_cell"]
	while not queue.is_empty():
		var cur: Vector3i = queue.pop_front()
		for nb: Vector3i in VoxelGrid.get_neighbors_3d(cur):
			if (st["reachable"] as Dictionary).has(nb):
				continue
			if not MovementRules.is_ground_step_open(volume, cur, nb):
				continue
			if doors_by_cell.has(nb):
				var rec: Dictionary = doors_by_cell[nb]
				if _rec_initially_passable(rec):
					_mark_reached_3d(volume, nb, st)
				elif rec["is_secret"] and not _rec_needs_key(rec):
					if not (st["secret_blocker_set"] as Dictionary).has(nb):
						st["secret_blocker_set"][nb] = true
						(st["secret_blockers"] as Array).append(nb)
				else:
					if not (st["pending_set"] as Dictionary).has(nb):
						st["pending_set"][nb] = true
						(st["pending"] as Array).append(nb)
			else:
				_mark_reached_3d(volume, nb, st)


## Door record initially passable with no key/lever: arch, curtain, unlocked,
## bashable (wood) non-secret locked/trapped.
static func _rec_initially_passable(rec: Dictionary) -> bool:
	if rec["is_secret"]:
		return false
	var t: String = rec["type"]
	if t == DungeonDoorData.TYPE_ARCH or DungeonDoorData.is_curtain(rec["material"]):
		return true
	if t == DungeonDoorData.TYPE_UNLOCKED:
		return true
	if t == DungeonDoorData.TYPE_LOCKED or t == DungeonDoorData.TYPE_TRAPPED:
		return DungeonDoorData.is_bashable(rec["material"])
	return false


## Door record requires a placed key: locked/trapped AND (secret OR stone/metal).
static func _rec_needs_key(rec: Dictionary) -> bool:
	var t: String = rec["type"]
	if t != DungeonDoorData.TYPE_LOCKED and t != DungeonDoorData.TYPE_TRAPPED:
		return false
	if rec["is_secret"]:
		return true
	return rec["material"] == DungeonDoorData.MATERIAL_STONE or rec["material"] == DungeonDoorData.MATERIAL_METAL


## Candidate zones for key/lever placement: fully-discovered zones excluding the
## entrance zone and every circulation-room zone. Discovery order (deterministic).
static func _candidate_zones(st: Dictionary, entrance_zone_key: String, kind_by_room: Dictionary) -> Array:
	var out: Array = []
	for zk: String in st["full_zones"]:
		if zk == entrance_zone_key:
			continue
		var meta: Dictionary = st["zone_meta"][zk]
		if kind_by_room.get(meta["room_id"], DungeonRoomData.KIND_CHAMBER) == DungeonRoomData.KIND_CIRCULATION:
			continue
		if int(meta["total"]) == 0:
			continue
		out.append(zk)
	return out


## Weighted pick among candidate zones by band proximity to the door
## (same band 5 / adjacent 2 / distant 1).
static func _pick_zone(candidates: Array, zone_meta: Dictionary, door_band: int, rng: RandomNumberGenerator) -> String:
	var weights: Array[int] = []
	var total: int = 0
	for zk: String in candidates:
		var delta: int = absi(int(zone_meta[zk]["band"]) - door_band)
		var w: int = 5 if delta == 0 else (2 if delta == 1 else 1)
		weights.append(w)
		total += w
	var roll: int = rng.randi_range(0, total - 1)
	var acc: int = 0
	for i: int in range(candidates.size()):
		acc += weights[i]
		if roll < acc:
			return candidates[i]
	return candidates[candidates.size() - 1]


## Build a composed key record for a gated door, choosing a candidate zone
## weighted by band proximity to the door.
static func _make_key_composed(door_cell: Vector3i, rec: Dictionary, candidates: Array, st: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var zone_meta: Dictionary = st["zone_meta"]
	var zk: String = _pick_zone(candidates, zone_meta, int(rec.get("band", 0)), rng)
	var meta: Dictionary = zone_meta[zk]
	return {
		"opens_door_cell": door_cell,
		"room_id": int(meta["room_id"]),
		"zone_index": int(meta["zone_index"]),
		"band": int(meta["band"]),
		"zone_cells": (meta["cells"] as Array).duplicate(),
	}


## Wire a portcullis to a lever cell in a discovered zone; mutate the lever cell.
static func _wire_lever_composed(volume: VoxelMapData, door_cell: Vector3i, candidates: Array, st: Dictionary, rng: RandomNumberGenerator, wired_levers: Dictionary) -> void:
	var zone_meta: Dictionary = st["zone_meta"]
	# Weight candidate zones by band proximity to the portcullis (§10.3 step 3),
	# reading the door's real band from its record — not a hardcoded 0.
	var door_band: int = int((st["doors_by_cell"] as Dictionary)[door_cell].get("band", 0))
	var zk: String = _pick_zone(candidates, zone_meta, door_band, rng)
	var cells: Array = zone_meta[zk]["cells"]
	if cells.is_empty():
		return  # unwired: forceable per §9.2
	var lever_cell: Vector3i = cells[0]
	wired_levers[door_cell] = lever_cell
	volume.set_lever_link(lever_cell, door_cell)
	var cell: VoxelCell = volume.get_cell(lever_cell)
	# Runtime contract: every lever consumer (context menu "Pull Lever",
	# renderer mesh, combat lever actions) matches feature == "lever" exactly;
	# the lever→door pairing travels on volume.lever_links, not the feature
	# string. (The band LAYOUT cell keeps the legacy "lever_portcullis_x_y"
	# terrain stamp — that is a different layer, applied in the sync-back.)
	cell.feature = "lever"
	volume.set_cell(lever_cell, cell)


## §10.4 downgrade a gated composed door to plain unlocked (clear lock + secret).
static func _downgrade_composed_door(volume: VoxelMapData, rec: Dictionary) -> void:
	push_warning("DungeonKeyLeverPlacer.place_composed: no candidate zone for %s door at %s — downgrading to unlocked." % [rec["type"], str(rec["cell"])])
	rec["type"] = DungeonDoorData.TYPE_UNLOCKED
	rec["material"] = DungeonDoorData.MATERIAL_WOOD_STANDARD
	rec["is_secret"] = false
	restamp_composed_door(volume, rec)


## Clear ONE secret+unlocked frontier door whose far side is still unreached.
static func _clear_one_blocking_secret_composed(volume: VoxelMapData, st: Dictionary) -> bool:
	var reachable: Dictionary = st["reachable"]
	for door_cell: Vector3i in st["secret_blockers"]:
		var rec: Dictionary = st["doors_by_cell"][door_cell]
		if not rec["is_secret"]:
			continue
		var blocks_unreached: bool = false
		for nb: Vector3i in VoxelGrid.get_neighbors_3d(door_cell):
			if reachable.has(nb):
				continue
			if MovementRules.is_ground_step_open(volume, door_cell, nb):
				blocks_unreached = true
				break
		if not blocks_unreached:
			continue
		push_warning("DungeonKeyLeverPlacer.place_composed: secret door at %s gates mandatory content with no key path — clearing is_secret (§10.3 repair)." % str(door_cell))
		rec["is_secret"] = false
		restamp_composed_door(volume, rec)
		_mark_reached_3d(volume, door_cell, st)
		return true
	return false


## Re-stamp a door cell from its (possibly mutated) record.
static func restamp_composed_door(volume: VoxelMapData, rec: Dictionary) -> void:
	var cell: VoxelCell = volume.get_cell(rec["cell"])
	if rec["is_secret"]:
		cell.door_type = "secret"
		cell.door_state = "closed"
		cell.door_detected = false
	else:
		match rec["type"]:
			DungeonDoorData.TYPE_ARCH:
				cell.door_type = "arch"
				cell.door_state = "open"
			DungeonDoorData.TYPE_UNLOCKED:
				cell.door_type = "unlocked"
				cell.door_state = "closed"
			DungeonDoorData.TYPE_LOCKED, DungeonDoorData.TYPE_TRAPPED:
				cell.door_type = rec["type"]
				cell.door_state = "locked"
			DungeonDoorData.TYPE_PORTCULLIS:
				cell.door_type = "portcullis"
				cell.door_state = "closed"
	volume.set_cell(rec["cell"], cell)


## Sync the placer's door-RECORD mutations (§10.4 downgrades, secret-clears)
## and wired levers back onto the band layouts' DungeonDoorData, so the
## acceptance tests (T4/T6) and the relational persistence see the same door
## hardware the composed volume carries. Legacy-§10.4 parity: a full downgrade
## (gated door → plain unlocked wood) that removes a trap room's only
## qualifying gate demotes that room to "empty"; a bare secret-clear does not
## demote (matching the pre-flip place() behavior). Wired levers stamp the
## lever's own band layout cell and record the 2D position on the door.
static func sync_composed_doors_to_layouts(
		doors: Array,
		wired_levers: Dictionary,
		floors: Array[DungeonLayout],
		band_walk: Dictionary) -> void:
	var layout_by_floor: Dictionary = {}
	for fl in floors:
		layout_by_floor[(fl as DungeonLayout).level_number] = fl
	# Inverse of band_walk: every composed door/lever cell sits at its band's
	# WALK level, so z resolves the band directly.
	var walk_to_floor: Dictionary = {}
	for floor_index in band_walk:
		walk_to_floor[int(band_walk[floor_index])] = int(floor_index)

	for rec in doors:
		var band: int = int(rec.get("band", -1))
		if not layout_by_floor.has(band):
			# Every record originates from a band layout door (_stamp_band); a
			# miss is a composed-vs-layout desync worth surfacing, not skipping.
			push_warning("DungeonKeyLeverPlacer.sync_composed_doors_to_layouts: door record at %s has unknown band %d — mutation not synced." % [str(rec.get("cell", "?")), band])
			continue
		var layout: DungeonLayout = layout_by_floor[band]
		var cell: Vector3i = rec["cell"]
		var door: DungeonDoorData = layout.find_door_at(Vector2i(cell.x, cell.y))
		if door == null:
			push_warning("DungeonKeyLeverPlacer.sync_composed_doors_to_layouts: no layout door at band %d %s for a composed door record — mutation not synced." % [band, str(Vector2i(cell.x, cell.y))])
			continue
		var changed: bool = door.type != rec["type"] \
			or door.is_secret != rec["is_secret"] \
			or door.door_material != rec["material"]
		if not changed:
			continue
		var was_qualifying: bool = door.is_secret and (
			door.type == DungeonDoorData.TYPE_LOCKED
			or door.type == DungeonDoorData.TYPE_TRAPPED)
		var is_full_downgrade: bool = rec["type"] == DungeonDoorData.TYPE_UNLOCKED \
			and not rec["is_secret"] \
			and rec["material"] == DungeonDoorData.MATERIAL_WOOD_STANDARD
		door.type = rec["type"]
		door.is_secret = rec["is_secret"]
		door.door_material = rec["material"]
		if is_full_downgrade:
			door.wired_lever_position = Vector2i(-1, -1)
			if was_qualifying:
				_demote_ungated_trap_rooms(layout, door)

	# Wired levers: record the 2D lever position on the door and stamp the
	# lever terrain feature on the LEVER's band layout (mirrors the legacy
	# _wire_lever, which stamped the chosen room's own floor).
	for door_cell: Vector3i in wired_levers:
		var lever_cell: Vector3i = wired_levers[door_cell]
		var door_band: int = int(walk_to_floor.get(door_cell.z, -1))
		if layout_by_floor.has(door_band):
			var door_layout: DungeonLayout = layout_by_floor[door_band]
			var pdoor: DungeonDoorData = door_layout.find_door_at(Vector2i(door_cell.x, door_cell.y))
			if pdoor != null:
				pdoor.wired_lever_position = Vector2i(lever_cell.x, lever_cell.y)
		var lever_floor: int = int(walk_to_floor.get(lever_cell.z, -1))
		if layout_by_floor.has(lever_floor):
			var lever_layout: DungeonLayout = layout_by_floor[lever_floor]
			var lc: DungeonCellData = lever_layout.get_cell_at(Vector2i(lever_cell.x, lever_cell.y))
			if lc != null:
				lc.terrain_feature = "lever_portcullis_%d_%d" % [door_cell.x, door_cell.y]


## Convert place_composed's key records into KeyItemData for the result
## contract / persistence. The record's room_id is the composed GLOBAL id
## (band_slot * ROOM_ID_STRIDE + local); the relational store keys rooms by
## per-band-LOCAL id + floor, so the key's placed room resolves to its HOME
## band (slot + 1) with the local id — a balcony zone's key still records the
## owning room's home floor, and placed_in_zone_index carries the zone.
static func composed_keys_to_items(keys: Array, doors: Array) -> Array[KeyItemData]:
	var band_by_cell: Dictionary = {}
	for rec in doors:
		band_by_cell[rec["cell"]] = int(rec.get("band", -1))
	var out: Array[KeyItemData] = []
	for kd in keys:
		var record: Dictionary = kd
		var door_cell: Vector3i = record["opens_door_cell"]
		var door_band: int = int(band_by_cell.get(door_cell, -1))
		if door_band < 1:
			push_warning("DungeonKeyLeverPlacer.composed_keys_to_items: key for door at %s has no band record — skipping." % str(door_cell))
			continue
		var global_room: int = int(record["room_id"])
		var k := KeyItemData.new()
		k.id = CampaignRepository.generate_id()
		k.opens_door_floor_index = door_band
		k.opens_door_position = Vector2i(door_cell.x, door_cell.y)
		@warning_ignore("integer_division")
		k.placed_on_floor_index = global_room / DungeonVolumeComposer.ROOM_ID_STRIDE + 1
		k.placed_in_room_id = global_room % DungeonVolumeComposer.ROOM_ID_STRIDE
		k.placed_in_zone_index = int(record["zone_index"])
		k.placed_in = KeyItemData.PLACED_LOOSE  # finalized later
		out.append(k)
	return out


## Coverage: every zone and every stairwell reached (matches the solvability pass).
static func _coverage_complete_composed(volume: VoxelMapData, st: Dictionary, zones: Array[RoomZone], stairwells: Array[StairwellData], band_walk: Dictionary) -> bool:
	var reachable: Dictionary = st["reachable"]
	for z: RoomZone in zones:
		if int((st["zone_meta"][("%d:%d" % [z.room_id, z.zone_index])] as Dictionary)["total"]) == 0:
			continue
		var any: bool = false
		var walk: int = int(band_walk.get(z.band, 0))
		for c: Vector2i in z.cells:
			if reachable.has(Vector3i(c.x, c.y, walk)):
				any = true
				break
		if not any:
			return false
	for sw: StairwellData in stairwells:
		if not reachable.has(sw.bottom_cell) or not reachable.has(sw.top_cell):
			return false
	return true
