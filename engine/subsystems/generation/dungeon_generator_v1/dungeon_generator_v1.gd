class_name DungeonGeneratorV1
extends RefCounted

## DG-V1.D multi-floor dungeon generation orchestrator.
##
## Drives the full gdd-dungeon-generator-v1.md §5 pipeline from a
## DungeonGeneratorRequestV1 to a DungeonGeneratorResultV1, stitching together:
##   DungeonTierDerivation    — per-floor tier computation (§6)
##   DungeonDataLoader        — JSON data tables (§7.2)
##   MonsterRegistry          — ACKS monster catalog
##   DungeonLayoutGenerator   — single-floor layout generation (§4.1)
##   DungeonStocker           — room contents (§11)
##   DungeonKeyLeverPlacer    — key/lever placements (§10)
##   DungeonNavigabilityValidator — §9.1 layout + §9.2 solvability checks
##   DungeonAcceptanceTests   — §14 hard/soft gate
##   DungeonGeneratorRepository — persistence (§12, optional)
##
## NOTE ON KEY/LEVER vs STOCKING ORDER (GDD §5 deviation):
##   The GDD §5 lists key/lever placement BEFORE stocking, but trap rooms (§11.4)
##   CREATE new locked+secret doors DURING stocking. Running key/lever placement
##   AFTER stocking lets it key those trap-room doors uniformly alongside the
##   pre-existing locked doors. The final placement outcomes (keys embedded in
##   monster inventories / treasure hoards) are preserved because
##   finalize_key_placements runs after both stocking and initial placement.
##   This is an intentional deviation from the GDD step ordering — document it
##   and keep it.


static func generate(request: DungeonGeneratorRequestV1) -> DungeonGeneratorResultV1:
	# ---------------------------------------------------------------------------
	# Step 1 — validate request (these hard errors are NEVER retried)
	# ---------------------------------------------------------------------------
	var result := DungeonGeneratorResultV1.new()

	if request.floor_count < 1:
		result.errors.append("floor_count must be >= 1 (got %d)" % request.floor_count)
		return result
	if request.entrance_tier < 1 or request.entrance_tier > 6:
		result.errors.append("entrance_tier must be in 1..6 (got %d)" % request.entrance_tier)
		return result
	if request.entrance_floor_index < 1 or request.entrance_floor_index > request.floor_count:
		result.errors.append(
			"entrance_floor_index must be in 1..floor_count (got %d, floor_count=%d)"
			% [request.entrance_floor_index, request.floor_count])
		return result

	# ---------------------------------------------------------------------------
	# Step 2 — base seed (each top-level attempt derives master_seed from this)
	# ---------------------------------------------------------------------------
	var base_seed: int
	if request.seed != 0:
		base_seed = request.seed
	else:
		base_seed = int(Time.get_unix_time_from_system() * 1000.0) & 0x7FFFFFFFFFFFFFFF

	# ---------------------------------------------------------------------------
	# Step 3 — data loader + monster registry (built once, reused across attempts)
	# ---------------------------------------------------------------------------
	var loader := DungeonDataLoader.new()
	if not loader.load_all():
		result.errors.append("DungeonGeneratorV1: data load failed")
		return result
	var registry := MonsterRegistry.new()

	# ---------------------------------------------------------------------------
	# Step 4 — dungeon id (stable across attempts)
	# ---------------------------------------------------------------------------
	var dungeon_id: String
	if not request.dungeon_id.is_empty():
		dungeon_id = request.dungeon_id
	else:
		dungeon_id = CampaignRepository.generate_id()

	# ---------------------------------------------------------------------------
	# Top-level retry — regenerate the WHOLE dungeon with a fresh seed when it is
	# not solvable/acceptable. The stocking-seed retries inside _generate_attempt
	# only re-roll room contents; they CANNOT fix a LAYOUT-generated locked /
	# secret / portcullis door that isolates a floor's entry antechamber. A fresh
	# master seed yields an independent layout, so this converges quickly.
	# Attempt 0 uses base_seed verbatim, so a fixed request reproduces the prior
	# single-shot result whenever that result was already solvable.
	# ---------------------------------------------------------------------------
	const MAX_DUNGEON_ATTEMPTS := 4
	var _gen_t0: int = Time.get_ticks_msec()
	for dungeon_attempt in range(MAX_DUNGEON_ATTEMPTS):
		var master_seed: int = base_seed + dungeon_attempt * 1000000007
		result = _generate_attempt(request, master_seed, dungeon_id, loader, registry)
		if result.success:
			break
		if dungeon_attempt < MAX_DUNGEON_ATTEMPTS - 1:
			push_warning("DungeonGeneratorV1: dungeon attempt %d not solvable/acceptable — regenerating with a fresh seed. (%s)"
				% [dungeon_attempt + 1, str(result.errors).substr(0, 100)])
	var _gen_elapsed: int = Time.get_ticks_msec() - _gen_t0
	if _gen_elapsed > 15000:
		push_warning("DungeonGeneratorV1: generate took %d ms (seed %d, %s %s, %d floors) — slow-generation telemetry, investigate if recurring."
			% [_gen_elapsed, base_seed, request.dungeon_type, request.dungeon_size, request.floor_count])

	# ---------------------------------------------------------------------------
	# Step 13 — persist (optional; once, on the accepted result)
	# ---------------------------------------------------------------------------
	if request.persist and result.success:
		if not DungeonGeneratorRepository.insert_dungeon_layout(
				dungeon_id, result.floors, result.key_items):
			result.errors.append("DungeonGeneratorV1: persist failed for dungeon '%s'" % dungeon_id)
			result.success = false
			push_error("DungeonGeneratorV1.generate: DB insert failed for dungeon '%s'" % dungeon_id)

	return result


## One generation attempt for a fixed master_seed (Steps 5-12). Returns a result
## whose `success` is false if a floor is ungenerable or the dungeon is not
## solvable/acceptable; generate() then retries with a fresh seed.
static func _generate_attempt(
		request: DungeonGeneratorRequestV1,
		master_seed: int,
		dungeon_id: String,
		loader: DungeonDataLoader,
		registry: MonsterRegistry) -> DungeonGeneratorResultV1:
	var result := DungeonGeneratorResultV1.new()
	result.dungeon_id = dungeon_id

	# ---------------------------------------------------------------------------
	# Step 5 — tier derivation
	# ---------------------------------------------------------------------------
	var tiers: Array[int] = DungeonTierDerivation.tiers_for_dungeon(
		request.entrance_tier, request.floor_count, request.entrance_floor_index)

	if DungeonTierDerivation.clamp_fired(
			request.entrance_tier, request.floor_count, request.entrance_floor_index):
		result.warnings.append(
			"tier clamp fired (entrance_tier=%d floor_count=%d efi=%d) — deep floors capped at tier 6"
			% [request.entrance_tier, request.floor_count, request.entrance_floor_index])

	# ---------------------------------------------------------------------------
	# Step 6 — generate floors top-down, threading stair anchors
	# ---------------------------------------------------------------------------
	var prev_down_positions: Array[Vector2i] = []

	for floor_index in range(1, request.floor_count + 1):
		var req := DungeonLayoutRequest.new()
		req.dungeon_type = request.dungeon_type
		req.dungeon_size = request.dungeon_size
		req.level_number = floor_index
		req.floor_tier = tiers[floor_index - 1]
		req.is_entrance_floor = (floor_index == request.entrance_floor_index)
		req.seed = master_seed + floor_index * 1000003

		# Down-stairs: this floor connects down to floor_index+1 if it exists.
		req.stairs_down = 1 if floor_index < request.floor_count else 0

		# Up-stairs: the prior floor's down-stair positions are supplied as
		# required_stair_positions with direction "up", so each anchor takes up
		# exactly one up-stair slot. Set stairs_up = number of anchors so the
		# composer subtracts them and places zero additional free up-stairs.
		req.required_stair_positions = []
		for p in prev_down_positions:
			req.required_stair_positions.append({"position": p, "direction": "up"})

		# The entrance floor on floor 1 gets stairs_up = 1 (the overworld entrance);
		# it has no required_stair_positions (no floor above), so free-placement fills it.
		# Non-first floors that have anchors set stairs_up to the anchor count.
		if floor_index == 1:
			req.stairs_up = 1   # entrance / overworld connection
		else:
			req.stairs_up = prev_down_positions.size()

		# Generate with up-to-3 retries on failure.
		var layout: DungeonLayout = null
		var try_seed: int = req.seed
		for _attempt in 4:
			req.seed = try_seed
			layout = DungeonLayoutGenerator.generate(req)
			if layout != null:
				break
			try_seed += 1
		if layout == null:
			result.errors.append(
				"DungeonGeneratorV1: floor %d ungenerable after retries (seed %d)" % [floor_index, req.seed])
			return result

		layout.dungeon_id = dungeon_id

		# Per-floor navigability check (doors-as-passable); retry up to 3x if failed.
		var nav: Dictionary = DungeonNavigabilityValidator.validate_layout(layout)
		if not nav["ok"]:
			var fixed := false
			var retry_seed: int = try_seed + 100
			for _retry in 3:
				retry_seed += 1
				req.seed = retry_seed
				var retry_layout: DungeonLayout = DungeonLayoutGenerator.generate(req)
				if retry_layout == null:
					continue
				retry_layout.dungeon_id = dungeon_id
				var retry_nav: Dictionary = DungeonNavigabilityValidator.validate_layout(retry_layout)
				if retry_nav["ok"]:
					layout = retry_layout
					fixed = true
					break
			if not fixed:
				# GDD §9.1 post-hoc carving: connect the unreachable rooms to
				# the reachable component directly rather than shipping a
				# structurally disconnected floor (which no stocking retry or
				# key placement can ever repair).
				if _carve_unreachable_rooms(layout):
					result.warnings.append(
						"DungeonGeneratorV1: floor %d connectivity repaired by §9.1 post-hoc carving."
						% floor_index)
				else:
					result.warnings.append(
						"DungeonGeneratorV1: floor %d layout connectivity issue after retries (carving failed): %s"
						% [floor_index, nav["message"]])

		# Stair-to-stair reachability check WITHOUT secret doors (pre-stocking guard).
		# If all stairs cannot reach each other ignoring secret doors, solvability will
		# always fail for this floor — retry layout generation to find a better seed.
		var _helper_result: bool = _stairs_all_mutually_reachable_no_secrets(layout)
		if not _helper_result:
			var fixed2 := false
			var retry_seed2: int = try_seed + 200
			for _retry2 in 5:
				retry_seed2 += 1
				req.seed = retry_seed2
				var retry_layout2: DungeonLayout = DungeonLayoutGenerator.generate(req)
				if retry_layout2 == null:
					continue
				retry_layout2.dungeon_id = dungeon_id
				var retry_nav2: Dictionary = DungeonNavigabilityValidator.validate_layout(retry_layout2)
				if retry_nav2["ok"] and _stairs_all_mutually_reachable_no_secrets(retry_layout2):
					layout = retry_layout2
					fixed2 = true
					break
			if not fixed2:
				push_warning("DungeonGeneratorV1: floor %d stairs not mutually reachable without secrets after retries." % floor_index)

		result.floors.append(layout)

		# Collect this floor's down-stair positions to anchor the next floor.
		prev_down_positions = []
		for s in layout.stairs:
			var stair: DungeonStairData = s
			if stair.direction == DungeonStairData.DIRECTION_DOWN:
				prev_down_positions.append(stair.position)

	# Wire connects_to_level on each stair now that the full floor list is known.
	for fi in range(result.floors.size()):
		var floor_layout: DungeonLayout = result.floors[fi]
		var floor_num: int = fi + 1  # 1-based
		for s in floor_layout.stairs:
			var stair: DungeonStairData = s
			if stair.direction == DungeonStairData.DIRECTION_DOWN:
				stair.connects_to_level = floor_num + 1
			elif stair.direction == DungeonStairData.DIRECTION_UP and floor_num > 1:
				stair.connects_to_level = floor_num - 1
			# Entrance-floor up-stair connects to overworld (level 0 convention).
			elif stair.direction == DungeonStairData.DIRECTION_UP and stair.is_entrance_stair:
				stair.connects_to_level = 0

	# ---------------------------------------------------------------------------
	# Steps 7-10 — stock, key/lever, lever-stamp, solvability (with retry).
	#
	# The stocker randomly converts doors to secret+locked for trap rooms. If a
	# trap room's door is on the only path between the entrance and a stair,
	# solvability fails. We retry stocking with a different seed up to 3 times
	# before accepting the result (solvability failures are then logged as errors
	# but do not prevent returning a best-effort result for the test harness).
	# ---------------------------------------------------------------------------

	# Snapshot the FULL mutable door state from the layout generator (before any
	# stocking / key-placement mutations) so each retry starts from a pristine
	# door state. Restoring ALL of type / is_secret / door_material /
	# wired_lever_position prevents a failed attempt's mutations (door.type forced
	# to LOCKED, a §10.4 material downgrade, a wired lever) from bleeding into the
	# next attempt — the bug that previously let a door stay LOCKED across retries
	# and produced spurious extra "qualifying" trap-room doors.
	var _door_original_state: Dictionary = {}  # "floor_idx:x:y" -> {type, is_secret, door_material, wlp}
	for _fi in range(result.floors.size()):
		var _fl: DungeonLayout = result.floors[_fi]
		for _d in _fl.doors:
			var _dobj: DungeonDoorData = _d
			var _dk: String = "%d:%d:%d" % [_fi, _dobj.position.x, _dobj.position.y]
			_door_original_state[_dk] = {
				"type": _dobj.type,
				"is_secret": _dobj.is_secret,
				"door_material": _dobj.door_material,
				"wlp": _dobj.wired_lever_position,
			}

	var solv: Dictionary = {}
	var report: Dictionary = {}
	var stocking_attempt := 0
	const MAX_STOCKING_ATTEMPTS := 4

	while stocking_attempt < MAX_STOCKING_ATTEMPTS:
		stocking_attempt += 1
		var stocking_seed_bump: int = (stocking_attempt - 1) * 999983

		# Step 7 — stock each floor (clear previous stocking state on retry).
		for fi in range(result.floors.size()):
			var floor_layout: DungeonLayout = result.floors[fi]
			# Clear stocker-generated state so the retry is fresh.
			for room in floor_layout.rooms:
				room.contents_kind = ""
				room.current_purpose = ""
				room.monster_group_id = ""
				room.treasure_hoard_id = ""
			floor_layout.monster_groups = []
			floor_layout.treasure_hoards = []
			# Restore doors to their pristine pre-stocking state on retry: ALL of
			# type / is_secret / door_material / wired_lever_position, so no
			# mutation from the failed attempt survives. Also clear stale lever
			# terrain stamps left on cells by the prior attempt's key/lever pass
			# (each door's wired_lever_position has just been reset).
			if stocking_attempt > 1:
				for d in floor_layout.doors:
					var dobj: DungeonDoorData = d
					var dk: String = "%d:%d:%d" % [fi, dobj.position.x, dobj.position.y]
					if _door_original_state.has(dk):
						var orig: Dictionary = _door_original_state[dk]
						dobj.type = orig["type"]
						dobj.is_secret = orig["is_secret"]
						dobj.door_material = orig["door_material"]
						dobj.wired_lever_position = orig["wlp"]
				_clear_lever_stamps(floor_layout)
			var floor_rng := RandomNumberGenerator.new()
			floor_rng.seed = master_seed + (fi + 1) * 7919 + stocking_seed_bump
			DungeonStocker.stock_floor(floor_layout, loader, registry, floor_rng)

		# Step 8 — key/lever placement (AFTER stocking so trap-room doors are present).
		# NOTE: the GDD §5 lists key/lever before stocking, but trap rooms (§11.4) create
		# new locked+secret doors during stocking. Running this after stocking ensures
		# trap-room doors get uniformly keyed alongside pre-existing locked doors.
		# finalize_key_placements runs here after both, preserving the intended outcomes.
		var kl_rng := RandomNumberGenerator.new()
		kl_rng.seed = master_seed + 104729 + stocking_seed_bump
		var keys: Array[KeyItemData] = DungeonKeyLeverPlacer.place(
			result.floors, request.entrance_floor_index, kl_rng)
		DungeonKeyLeverPlacer.finalize_key_placements(keys, result.floors, loader, kl_rng)
		result.key_items = keys

		# Step 9 — stamp lever terrain features.
		# key_lever_placer.place() already stamps lever terrain_features on portcullis
		# doors, so this step is idempotent — re-stamp for consistency.
		for fl in result.floors:
			var floor_layout: DungeonLayout = fl
			for d in floor_layout.doors:
				var door: DungeonDoorData = d
				if door.wired_lever_position == Vector2i(-1, -1):
					continue
				var lever_cell: DungeonCellData = floor_layout.get_cell_at(door.wired_lever_position)
				if lever_cell != null:
					lever_cell.terrain_feature = (
						"lever_portcullis_%d_%d" % [door.position.x, door.position.y])

		# Step 10 — solvability + acceptance gate. BOTH must pass to accept this
		# attempt. Re-rolling the stocking seed changes trap placement, so it can
		# clear a solvability failure (a trap's secret+locked door landing on the
		# sole entrance path) or a transient hard acceptance failure (e.g. a trap
		# room left ungated). T6 over-gating (>1) is only a soft warning and never
		# forces a retry.
		solv = DungeonNavigabilityValidator.validate_solvability(
			result.floors, result.key_items, request.entrance_floor_index)
		report = DungeonAcceptanceTests.run(result)
		var attempt_hard_pass: bool = report.get("hard_pass", false)
		if solv["ok"] and attempt_hard_pass:
			break  # solvable AND acceptance-clean — done retrying

		if stocking_attempt < MAX_STOCKING_ATTEMPTS:
			push_warning("DungeonGeneratorV1: stocking attempt %d not accepted (solvable=%s, hard_pass=%s) — retrying with a different stocking seed."
				% [stocking_attempt, str(solv.get("ok", false)), str(attempt_hard_pass)])

	if not solv["ok"]:
		for failure in solv["failures"]:
			result.errors.append(str(failure))

	# ---------------------------------------------------------------------------
	# Step 11 — record the final acceptance report (from the accepted/last attempt).
	# ---------------------------------------------------------------------------
	result.acceptance_report = report
	result.placeholder_counts = report.get("placeholder_counts", {})
	for w in report.get("soft_warnings", []):
		result.warnings.append(str(w))

	# ---------------------------------------------------------------------------
	# Step 12 — set success flag
	# ---------------------------------------------------------------------------
	var hard_pass: bool = report.get("hard_pass", false)
	# Surface any residual hard failures (e.g. an unresolvable topological case
	# after all retries) in result.errors, not just the acceptance report.
	if not hard_pass:
		for hf in report.get("hard_failures", []):
			result.errors.append(str(hf))
	result.success = hard_pass and solv["ok"] and result.errors.is_empty()
	return result


# ---------------------------------------------------------------------------
# Helper — entrance-and-stair reachability WITHOUT secret doors
# ---------------------------------------------------------------------------
## BFS from the entrance (or all stairs for non-entrance floors) treating
## secret doors as impassable. Returns true if all rooms AND all stairs are
## reachable without opening any secret doors.
##
## Called before stocking to catch layouts where the layout generator's §8.1
## weighted roll placed a secret door on the only path between the entrance
## and a stair cell (or between any two rooms). Stocking retries cannot fix
## this because the secret door is embedded in the layout, so we retry
## layout generation instead.
static func _stairs_all_mutually_reachable_no_secrets(layout: DungeonLayout) -> bool:
	# Seed BFS from a SINGLE point so the "every stair / every room reachable"
	# checks below verify the floor is ONE connected component (entrance floors:
	# the entrance; other floors: the first stair). Seeding from ALL stairs would
	# mask a disconnected component — e.g. an anchor antechamber holding the
	# up-stair that the rest of the floor cannot reach — because each stair
	# trivially reaches itself; that masked case is the cross-floor "entire floor
	# unreachable" solvability failure. A failure here triggers the caller's
	# layout-regeneration retry.
	var visited: Dictionary = {}
	var queue: Array[Vector2i] = []

	if layout.is_entrance_floor and layout.entrance != Vector2i(-1, -1):
		visited[layout.entrance] = true
		queue.append(layout.entrance)
	elif layout.stairs.size() > 0:
		var seed_stair: DungeonStairData = layout.stairs[0]
		visited[seed_stair.position] = true
		queue.append(seed_stair.position)

	while queue.size() > 0:
		var pos: Vector2i = queue.pop_front()
		for nb in [Vector2i(pos.x - 1, pos.y), Vector2i(pos.x + 1, pos.y),
				Vector2i(pos.x, pos.y - 1), Vector2i(pos.x, pos.y + 1)]:
			if visited.has(nb):
				continue
			if nb.x < 0 or nb.y < 0 or nb.x >= layout.grid_width or nb.y >= layout.grid_height:
				continue
			var cell: DungeonCellData = layout.get_cell_at(nb)
			if cell == null:
				continue
			if cell.is_door():
				var door: DungeonDoorData = layout.find_door_at(nb)
				if door != null and door.is_secret:
					continue  # treat secret door as impassable wall
				# Non-secret door: passable
			elif not cell.passable and not cell.is_stair():
				continue  # solid wall
			visited[nb] = true
			queue.append(nb)

	# Every stair must be reachable.
	for stair_data in layout.stairs:
		var s: DungeonStairData = stair_data
		if not visited.has(s.position):
			return false

	# Every room must have at least one cell reachable.
	for room: DungeonRoomData in layout.rooms:
		var any_reached := false
		for rc: Vector2i in room.cells:
			if visited.has(rc):
				any_reached = true
				break
		if not any_reached:
			return false

	return true


# ---------------------------------------------------------------------------
# Helper — §9.1 post-hoc carving for structurally disconnected floors
# ---------------------------------------------------------------------------
## GDD §9.1: when a floor still has unreachable rooms after the layout retry
## budget, carve a 2-cell-wide L-shaped corridor from each disconnected room to
## the nearest reachable cell (doors-as-passable model) instead of shipping a
## floor that no downstream retry can fix. Mutates layout.cells in place; rooms,
## doors, and stairs are untouched. Returns true when every room is reachable
## after carving.
static func _carve_unreachable_rooms(layout: DungeonLayout) -> bool:
	# Each pass connects at least one room, so passes are bounded by room count.
	for _pass in range(layout.rooms.size() + 1):
		# Doors-as-passable BFS from the same seed validate_layout uses.
		var seed_pos := Vector2i(-1, -1)
		if layout.is_entrance_floor and layout.entrance != Vector2i(-1, -1):
			seed_pos = layout.entrance
		elif layout.stairs.size() > 0:
			seed_pos = (layout.stairs[0] as DungeonStairData).position
		elif not layout.rooms.is_empty() and not (layout.rooms[0] as DungeonRoomData).cells.is_empty():
			seed_pos = (layout.rooms[0] as DungeonRoomData).cells[0]
		if seed_pos == Vector2i(-1, -1):
			return false

		var visited: Dictionary = {}
		var visited_list: Array[Vector2i] = []
		var queue: Array[Vector2i] = [seed_pos]
		visited[seed_pos] = true
		visited_list.append(seed_pos)
		while not queue.is_empty():
			var cur: Vector2i = queue.pop_front()
			for nb in [Vector2i(cur.x - 1, cur.y), Vector2i(cur.x + 1, cur.y),
					Vector2i(cur.x, cur.y - 1), Vector2i(cur.x, cur.y + 1)]:
				if visited.has(nb):
					continue
				if nb.x < 0 or nb.y < 0 or nb.x >= layout.grid_width or nb.y >= layout.grid_height:
					continue
				var cell: DungeonCellData = layout.get_cell_at(nb)
				if cell == null:
					continue
				if not cell.passable and not cell.is_door():
					continue
				visited[nb] = true
				visited_list.append(nb)
				queue.append(nb)

		# First room with no reached cell; none -> floor fully connected.
		var target_room: DungeonRoomData = null
		for r in layout.rooms:
			var room: DungeonRoomData = r
			if room.cells.is_empty():
				continue
			var reached := false
			for rc: Vector2i in room.cells:
				if visited.has(rc):
					reached = true
					break
			if not reached:
				target_room = room
				break
		if target_room == null:
			return true

		# Carve toward the nearest reachable cell (Manhattan distance).
		var from: Vector2i = target_room.cells[0]
		var best: Vector2i = visited_list[0]
		var best_d: int = absi(from.x - best.x) + absi(from.y - best.y)
		for v in visited_list:
			var d: int = absi(from.x - v.x) + absi(from.y - v.y)
			if d < best_d:
				best_d = d
				best = v
		_carve_l_path(layout, from, best)
	return false


## Carve an L-shaped 2-cell-wide corridor: horizontal leg from `from` to
## (to.x, from.y), then vertical leg to `to`. Only wall/rock cells are
## converted to open corridor; existing passable cells, doors, and stairs are
## left untouched.
static func _carve_l_path(layout: DungeonLayout, from: Vector2i, to: Vector2i) -> void:
	var x_step: int = 1 if to.x >= from.x else -1
	for x in range(from.x, to.x + x_step, x_step):
		_carve_cell(layout, Vector2i(x, from.y))
		_carve_cell(layout, Vector2i(x, from.y + (1 if from.y + 1 < layout.grid_height else -1)))
	var y_step: int = 1 if to.y >= from.y else -1
	for y in range(from.y, to.y + y_step, y_step):
		_carve_cell(layout, Vector2i(to.x, y))
		_carve_cell(layout, Vector2i(to.x + (1 if to.x + 1 < layout.grid_width else -1), y))


## Convert one wall/rock cell to open corridor. No-op for cells that are
## already passable or hold a door / stair (their data objects stay valid).
static func _carve_cell(layout: DungeonLayout, pos: Vector2i) -> void:
	var cell: DungeonCellData = layout.get_cell_at(pos)
	if cell == null:
		return
	if cell.passable or cell.is_door() or cell.is_stair():
		return
	cell.terrain_feature = DungeonCellData.FEATURE_OPEN
	cell.passable = true
	cell.blocks_los = false
	cell.is_corridor = true


# ---------------------------------------------------------------------------
# Helper — clear stale lever terrain stamps before a stocking retry
# ---------------------------------------------------------------------------
## Reset any "lever_portcullis_*" terrain feature stamped on a cell by a prior
## stocking attempt's key/lever placement back to the open-floor baseline. Lever
## cells are always room-interior floor cells (FEATURE_OPEN), chosen by
## DungeonKeyLeverPlacer, so FEATURE_OPEN is the correct restore value. Called on
## retry alongside the door-state restore so a lever that moves or disappears
## between attempts leaves no phantom stamp behind.
static func _clear_lever_stamps(layout: DungeonLayout) -> void:
	for x in range(layout.grid_width):
		for y in range(layout.grid_height):
			var cell: DungeonCellData = layout.get_cell(x, y)
			if cell != null and cell.terrain_feature.begins_with("lever_portcullis_"):
				cell.terrain_feature = DungeonCellData.FEATURE_OPEN
