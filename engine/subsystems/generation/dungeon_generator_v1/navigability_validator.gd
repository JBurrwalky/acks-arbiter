class_name DungeonNavigabilityValidator
extends RefCounted

## Validates spatial reachability for a generated dungeon.
##
## §9.1 validate_layout — per-band single-floor BFS: every room cell must be
## reachable within one band (doors treated as traversable regardless of
## type/state). Runs on each composed band during generation as a pre-compose
## structural guard.
##
## Composed-volume validation (DG-C3D.E) runs reachability on the real 3D
## movement graph of the contiguous VoxelMapData via MovementRules:
##   validate_composed_structural  — all doors passable; every zone + stairwell
##                                    reachable from the entrance; §10.2 geometry.
##   validate_composed_solvability — doors in their INITIAL state, fixpoint
##                                    key/lever unlock; gate blast-radius telemetry.
## (The legacy per-floor 2D validate_solvability + stair-teleport BFS was removed
## at DG-C3D.F.3; the composed volume is the only reachability surface.)
##
## Reference: gdd-dungeon-generator-v1.md §9; gdd-dungeon-contiguous-3d.md §10.


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
		# is floor-local (cross-band reachability is validate_composed_solvability).
		for stair: DungeonStairData in layout.stairs:
			_enqueue(layout, stair.position, visited, queue)
		# Composed-pipeline band (DG-C3D.F): no stairs at all — vertical
		# connectivity is the composer's stairwells. Seed from the first room
		# so the single-connected-component check still runs.
		if queue.is_empty():
			var seed_cell: Vector2i = fallback_seed_cell(layout)
			if seed_cell != Vector2i(-1, -1):
				_enqueue(layout, seed_cell, visited, queue)

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


## Composed-pipeline seeding fallback (DG-C3D.F): a band with no entrance and
## no stairs seeds its floor-local reachability checks from the first room's
## first cell (deterministic). Shared by validate_layout and the generator's
## pre-stocking no-secrets guard so the two checks can never diverge. Returns
## (-1, -1) when the layout has no seedable room.
static func fallback_seed_cell(layout: DungeonLayout) -> Vector2i:
	if not layout.rooms.is_empty() and not (layout.rooms[0] as DungeonRoomData).cells.is_empty():
		return (layout.rooms[0] as DungeonRoomData).cells[0]
	return Vector2i(-1, -1)


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


# =========================================================================
# DG-C3D.E — composed-volume validation on the real 3D movement graph
# =========================================================================
#
# The composed dungeon is ONE VoxelMapData. Reachability runs on the real
# ground-movement graph via MovementRules (support + ±1-level stair/ramp/spiral
# feature) — no per-floor BFS, no stair-teleport edges. Every pass seeds from
# the dungeon ENTRANCE only (the DG-V1 lesson that multi-point seeding masks
# disconnected pockets). Falls are NEVER edges: every legal walk edge is
# reversible (both stair cells are supported), and `assert_edge_symmetry`
# checks it. (The legacy per-floor validate_solvability was removed at
# DG-C3D.F.3; the per-band validate_layout above stays as a pre-compose guard.)


## Ground-movement reachable set (Dictionary[Vector3i -> true]) from
## [param entrance_pos] over the composed [param volume].
##
## Edge = MovementRules.is_ground_step_open (destination air + supported + legal
## level transition). Door policy by [param mode]:
##   "structural"  — every door passable. Door cells are open air, so they pass
##                   the geometry predicate directly; nothing extra is applied.
##   "solvability" — a door blocks in its INITIAL state unless its key/lever
##                   condition is already satisfied by the reachable set; the
##                   fixpoint re-runs while the set keeps growing (a newly
##                   reached key/lever can unlock a previously blocked door).
## [param doors_by_cell] maps a door Vector3i -> its ComposeResult door record
## (+ optional "wired_lever": Vector3i). [param keys] are composed key records
## {opens_door_cell: Vector3i, zone_cells: Array[Vector3i]}.
static func reach_composed(
		volume: VoxelMapData,
		entrance_pos: Vector3i,
		mode: String,
		doors_by_cell: Dictionary,
		keys: Array) -> Dictionary:
	var reachable: Dictionary = {}
	reachable[entrance_pos] = true
	var queue: Array[Vector3i] = [entrance_pos]
	# Solvability fixpoint, door-frontier form: doors found blocked are parked
	# in [blocked_doors]; whenever the frontier exhausts, every parked door is
	# re-checked against the GROWN reachable set (reachable growth is the only
	# thing that can open one — the geometry predicate is state-independent),
	# and each door that opens is enqueued as the new frontier. Each outer
	# iteration either opens ≥1 door or terminates, so iterations are bounded
	# by the door count and every cell is BFS-expanded exactly once. (The
	# previous form re-seeded the queue with the ENTIRE reachable set per pass
	# — O(doors × volume) re-expansion that made deep multi-band dungeons
	# effectively ungenerable.)
	var blocked_doors: Dictionary = {}  # Vector3i -> true
	var guard: int = 0
	while true:
		guard += 1
		if guard > doors_by_cell.size() + 2:
			push_error("DungeonNavigabilityValidator.reach_composed: fixpoint exceeded %d passes — bailing with partial reachability." % (doors_by_cell.size() + 2))
			break
		while not queue.is_empty():
			var cur: Vector3i = queue.pop_front()
			for nb: Vector3i in VoxelGrid.get_neighbors_3d(cur):
				if reachable.has(nb):
					continue
				if not MovementRules.is_ground_step_open(volume, cur, nb):
					continue
				if mode == "solvability" and doors_by_cell.has(nb):
					if not _composed_door_passable(doors_by_cell[nb], reachable, keys):
						blocked_doors[nb] = true
						continue
				reachable[nb] = true
				queue.append(nb)
		if mode != "solvability" or blocked_doors.is_empty():
			break
		var opened: Array[Vector3i] = []
		for door_cell: Vector3i in blocked_doors:
			if _composed_door_passable(doors_by_cell[door_cell], reachable, keys):
				opened.append(door_cell)
		if opened.is_empty():
			break  # true fixpoint — remaining doors stay locked
		for door_cell in opened:
			blocked_doors.erase(door_cell)
			reachable[door_cell] = true
			queue.append(door_cell)
	return reachable


## Whether a composed door record is passable in the dungeon's INITIAL state
## (the §9.2 door-passability model, applied to composed door records).
## Secret+unlocked doors are model-impassable (no key); secret
## locked/trapped need a reachable key; portcullises need a reachable wired
## lever or are forceable when unwired; non-bashable locked/trapped need a key.
static func _composed_door_passable(rec: Dictionary, reachable: Dictionary, keys: Array) -> bool:
	var dtype: String = rec.get("type", "")
	var is_secret: bool = rec.get("is_secret", false)
	var material: String = rec.get("material", "")
	var cell: Vector3i = rec.get("cell", Vector3i.ZERO)
	if is_secret:
		if dtype == DungeonDoorData.TYPE_LOCKED or dtype == DungeonDoorData.TYPE_TRAPPED:
			return _composed_key_reachable(cell, reachable, keys)
		return false  # secret+unlocked: Search-only, no key — impassable in the model
	if dtype == DungeonDoorData.TYPE_ARCH or DungeonDoorData.is_curtain(material):
		return true
	if dtype == DungeonDoorData.TYPE_UNLOCKED:
		return true
	if dtype == DungeonDoorData.TYPE_PORTCULLIS:
		var lever: Vector3i = rec.get("wired_lever", StairwellData.UNSET_CELL)
		if lever == StairwellData.UNSET_CELL:
			return true  # unwired portcullis: Force Portcullis always available
		return reachable.has(lever)
	if dtype == DungeonDoorData.TYPE_LOCKED or dtype == DungeonDoorData.TYPE_TRAPPED:
		if DungeonDoorData.is_bashable(material):
			return true  # wood door: bash available, no key needed
		return _composed_key_reachable(cell, reachable, keys)
	return true


## True if any key opening [param door_cell] has one of its zone cells reached.
static func _composed_key_reachable(door_cell: Vector3i, reachable: Dictionary, keys: Array) -> bool:
	for k in keys:
		if k.get("opens_door_cell", StairwellData.UNSET_CELL) != door_cell:
			continue
		for zc in k.get("zone_cells", []):
			if reachable.has(zc):
				return true
	return false


## Structural pass (pre-keys): all doors passable; every zone of every room
## reachable from the entrance; every stairwell traversable BOTH directions;
## the §10.2 geometry checks. Returns
## {ok, unreached_zones, unreached_stairwells, checks, message}.
static func validate_composed_structural(
		volume: VoxelMapData,
		zones: Array[RoomZone],
		stairwells: Array[StairwellData],
		band_walk: Dictionary,
		entrance_pos: Vector3i) -> Dictionary:
	var reachable: Dictionary = reach_composed(volume, entrance_pos, "structural", {}, [])

	var unreached_zones: Array = []
	for z: RoomZone in zones:
		if not _zone_reached(z, band_walk, reachable):
			unreached_zones.append({"room_id": z.room_id, "zone_index": z.zone_index, "band": z.band, "type": z.zone_type})

	var unreached_stairwells: Array = []
	for sw: StairwellData in stairwells:
		if not reachable.has(sw.bottom_cell) or not reachable.has(sw.top_cell):
			unreached_stairwells.append(sw.stairwell_id)

	var checks: Dictionary = {
		"stair_geometry": _check_stair_geometry(volume, stairwells),
		"no_door_in_run": _check_no_door_in_runs(volume, stairwells),
		"band_honesty": _check_band_honesty(volume, zones, band_walk),
		"edge_symmetry": assert_edge_symmetry(volume, reachable),
		"fall_audit": fall_audit(volume, zones, band_walk),
	}

	var ok: bool = unreached_zones.is_empty() and unreached_stairwells.is_empty() \
		and checks["stair_geometry"]["ok"] and checks["no_door_in_run"]["ok"] \
		and checks["band_honesty"]["ok"] and checks["edge_symmetry"]
	var message: String = "Composed structural: all zones + stairwells reachable, geometry clean." if ok \
		else "Composed structural FAILED: %d unreached zone(s), %d unreached stairwell(s); checks=%s" \
			% [unreached_zones.size(), unreached_stairwells.size(), str(checks)]

	return {
		"ok": ok,
		"unreached_zones": unreached_zones,
		"unreached_stairwells": unreached_stairwells,
		"checks": checks,
		"reachable": reachable,
		"message": message,
	}


# ---------------------------------------------------------------------------
# Composed-volume helpers
# ---------------------------------------------------------------------------

## True if any of the zone's cells (at its band's walk level) is in [reachable].
static func _zone_reached(z: RoomZone, band_walk: Dictionary, reachable: Dictionary) -> bool:
	var walk: int = int(band_walk.get(z.band, 0))
	for c: Vector2i in z.cells:
		if reachable.has(Vector3i(c.x, c.y, walk)):
			return true
	return false


## §10.2 check 2 — each stairwell's run walks cleanly bottom→top AND top→bottom
## under the movement rules. The reach is RESTRICTED to the stairwell's own
## locale (its run + landings + their 3D neighbours) so a broken run cannot pass
## by way of a bypass elsewhere in the volume — it isolates the stair geometry.
static func _check_stair_geometry(volume: VoxelMapData, stairwells: Array[StairwellData]) -> Dictionary:
	var failures: Array = []
	for sw: StairwellData in stairwells:
		var allowed: Dictionary = {}
		var anchors: Array[Vector3i] = sw.run_cells.duplicate()
		anchors.append(sw.bottom_cell)
		anchors.append(sw.top_cell)
		for a: Vector3i in anchors:
			allowed[a] = true
			for nb: Vector3i in VoxelGrid.get_neighbors_3d(a):
				allowed[nb] = true
		var up: Dictionary = _reach_restricted(volume, sw.bottom_cell, allowed)
		var down: Dictionary = _reach_restricted(volume, sw.top_cell, allowed)
		if not up.has(sw.top_cell) or not down.has(sw.bottom_cell):
			failures.append(sw.stairwell_id)
	return {"ok": failures.is_empty(), "failures": failures}


## Ground-movement reach from [start] restricted to cells in [allowed] (the
## stairwell tube). Used only by _check_stair_geometry.
static func _reach_restricted(volume: VoxelMapData, start: Vector3i, allowed: Dictionary) -> Dictionary:
	var reachable: Dictionary = {}
	if not allowed.has(start):
		return reachable
	reachable[start] = true
	var queue: Array[Vector3i] = [start]
	while not queue.is_empty():
		var cur: Vector3i = queue.pop_front()
		for nb: Vector3i in VoxelGrid.get_neighbors_3d(cur):
			if reachable.has(nb) or not allowed.has(nb):
				continue
			if not MovementRules.is_ground_step_open(volume, cur, nb):
				continue
			reachable[nb] = true
			queue.append(nb)
	return reachable


## §10.3 invariant — no door cell inside any StairwellData.run_cells (composer
## emits, validator asserts).
static func _check_no_door_in_runs(volume: VoxelMapData, stairwells: Array[StairwellData]) -> Dictionary:
	var violations: Array = []
	for sw: StairwellData in stairwells:
		for rc: Vector3i in sw.run_cells:
			if volume.get_cell(rc).door_state != "":
				violations.append({"stairwell": sw.stairwell_id, "cell": rc})
	return {"ok": violations.is_empty(), "violations": violations}


## §10.2 check 4 — band honesty: every zoned cell sits at walk_level(its band)
## (level_offset stays 0). Verifies the stamped zone_index matches the RoomZone.
static func _check_band_honesty(volume: VoxelMapData, zones: Array[RoomZone], band_walk: Dictionary) -> Dictionary:
	var violations: int = 0
	for z: RoomZone in zones:
		var walk: int = int(band_walk.get(z.band, 0))
		for c: Vector2i in z.cells:
			if volume.get_cell(Vector3i(c.x, c.y, walk)).zone_index != z.zone_index:
				violations += 1
	return {"ok": violations == 0, "violations": violations}


## §10.3 — reachability counts reversible edges only. For every reached cell,
## every legal outward ground step must be legal in reverse (falls are never
## edges). Returns true when symmetry holds.
static func assert_edge_symmetry(volume: VoxelMapData, reachable: Dictionary) -> bool:
	for pos: Vector3i in reachable.keys():
		for nb: Vector3i in VoxelGrid.get_neighbors_3d(pos):
			if not reachable.has(nb):
				continue
			if MovementRules.is_ground_step_open(volume, pos, nb) \
					and not MovementRules.is_ground_step_open(volume, nb, pos):
				return false
	return true


## §10.2 check 5 — soft fall audit: count walkable cells adjacent to a ≥10' drop
## (a balcony/shaft edge: a same-level neighbour that is open airspace with no
## floor, i.e. a void). Playtest telemetry, never a gate.
static func fall_audit(volume: VoxelMapData, zones: Array[RoomZone], band_walk: Dictionary) -> Dictionary:
	var per_band: Dictionary = {}
	for z: RoomZone in zones:
		var walk: int = int(band_walk.get(z.band, 0))
		for c: Vector2i in z.cells:
			var pos := Vector3i(c.x, c.y, walk)
			for nb: Vector3i in VoxelGrid.get_neighbors_2d(pos):
				var ncell := volume.get_cell(nb)
				if ncell.solidity == "air" and ncell.floor_type == "none":
					per_band[z.band] = int(per_band.get(z.band, 0)) + 1
					break
	return {"per_band": per_band}


## Build the Vector3i -> door-record lookup the solvability BFS consumes, folding
## any placer-supplied wired-lever cells (keyed by door cell) into the records.
static func composed_doors_by_cell(doors: Array, wired_levers: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {}
	for rec in doors:
		var cell: Vector3i = rec["cell"]
		var merged: Dictionary = rec.duplicate()
		if wired_levers.has(cell):
			merged["wired_lever"] = wired_levers[cell]
		out[cell] = merged
	return out


## Solvability pass (post-keys/stocking): doors in their INITIAL states, fixpoint
## key/lever unlock. Every zone reachable, every stairwell reachable. Adds gate
## blast-radius [GATE] telemetry (§10.3): a key gating more than [param
## gate_fraction] of stockable zones logs a warning. The telemetry re-runs the
## reach once PER KEY, so [param with_gate_telemetry] lets hot callers (the
## generator's stocking-retry loop) skip it and run it once on the accepted
## attempt only. Returns {ok, failures, unreached_zones, gate_warnings}.
static func validate_composed_solvability(
		volume: VoxelMapData,
		zones: Array[RoomZone],
		stairwells: Array[StairwellData],
		doors: Array,
		keys: Array,
		band_walk: Dictionary,
		entrance_pos: Vector3i,
		wired_levers: Dictionary = {},
		gate_fraction: float = 0.40,
		with_gate_telemetry: bool = true) -> Dictionary:
	var doors_by_cell: Dictionary = composed_doors_by_cell(doors, wired_levers)
	var reachable: Dictionary = reach_composed(volume, entrance_pos, "solvability", doors_by_cell, keys)

	var unreached_zones: Array = []
	for z: RoomZone in zones:
		if not _zone_reached(z, band_walk, reachable):
			unreached_zones.append({"room_id": z.room_id, "zone_index": z.zone_index, "band": z.band})

	var failures: Array[String] = []
	for entry in unreached_zones:
		failures.append("Zone (room %d, zone %d, band %d) unreachable in initial state." % [entry["room_id"], entry["zone_index"], entry["band"]])
	for sw: StairwellData in stairwells:
		if not reachable.has(sw.bottom_cell) or not reachable.has(sw.top_cell):
			failures.append("Stairwell %s not solvable-reachable." % sw.stairwell_id)

	# Gate blast-radius telemetry: how many stockable zones each key exclusively
	# gates (re-run solvability with that key's door forced shut).
	var stockable: Array[RoomZone] = []
	for z: RoomZone in zones:
		if z.zone_type != RoomZone.ZONE_TYPE_LANDING:
			stockable.append(z)
	var gate_warnings: Array = []
	if with_gate_telemetry and not stockable.is_empty():
		for k in keys:
			var door_cell: Vector3i = k.get("opens_door_cell", StairwellData.UNSET_CELL)
			if door_cell == StairwellData.UNSET_CELL:
				continue
			# MARGINAL blast radius: remove ONLY this key (every other key stays
			# usable, so their doors stay open); this door then reverts to
			# needing-a-key = shut. Count the stockable zones that become
			# unreachable — the zones THIS key exclusively gates. (Passing an
			# empty key list would shut every keyed door and over-count.)
			var keys_minus: Array = []
			for other in keys:
				if other.get("opens_door_cell", StairwellData.UNSET_CELL) != door_cell:
					keys_minus.append(other)
			var without: Dictionary = reach_composed(volume, entrance_pos, "solvability", doors_by_cell, keys_minus)
			var gated: int = 0
			for z: RoomZone in stockable:
				if _zone_reached(z, band_walk, reachable) and not _zone_reached(z, band_walk, without):
					gated += 1
			var frac: float = float(gated) / float(stockable.size())
			if frac > gate_fraction:
				var msg: String = "[GATE] key for door %s gates %d/%d stockable zones (%.0f%% > %.0f%%)." % [str(door_cell), gated, stockable.size(), frac * 100.0, gate_fraction * 100.0]
				push_warning(msg)
				gate_warnings.append(msg)

	return {
		"ok": failures.is_empty(),
		"failures": failures,
		"unreached_zones": unreached_zones,
		"gate_warnings": gate_warnings,
	}
