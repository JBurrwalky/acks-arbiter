class_name DungeonGeneratorV1
extends RefCounted

## Multi-band dungeon generation orchestrator — the COMPOSED contiguous-3D
## pipeline (DG-C3D.F cutover; gdd-dungeon-contiguous-3d.md §8).
##
## Drives one DungeonGeneratorRequestV1 to a DungeonGeneratorResultV1:
##   VerticalPlan             — whole-dungeon vertical plan (bands, connectors,
##                              atriums, reservations; contiguous GDD §8 A)
##   DungeonTierDerivation    — per-band tier computation (V1 §6, via the plan)
##   DungeonDataLoader        — JSON data tables (V1 §7.2)
##   MonsterRegistry          — ACKS monster catalog
##   DungeonLayoutGenerator   — per-band 2D layout (reservations pre-placed)
##   DungeonStocker           — room contents (V1 §11) + per-zone projection
##   DungeonVolumeComposer    — ONE contiguous VoxelMapData + stairwells +
##                              zones (contiguous GDD §8 C)
##   DungeonKeyLeverPlacer    — composed key/lever placement over the real 3D
##                              movement graph (contiguous GDD §10.3)
##   DungeonNavigabilityValidator — per-band §9.1 + composed solvability (§10)
##   DungeonAcceptanceTests   — V1 §14 hard/soft gate (per-band ledgers)
##   DungeonGeneratorRepository — persistence (V1 §12, optional)
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


## Generator version stamp (DG-C3D.A; gdd-dungeon-contiguous-3d.md §13).
## Persisted with every generated dungeon (dungeon_floors.generator_version +
## the "generator_version" key in the voxel JSON payload). The lazy-generation
## seam (DungeonFixtureService) discards and regenerates any stored dungeon
## whose stamp does not match this constant — "regenerate, no migration".
##
## 0 = the pre-contiguous floor-stitched generator (payloads persisted before
## the stamp existed read as 0 via the missing-key default). 1 = the composed
## contiguous-volume pipeline (DG-C3D.F.2c cutover, 2026-07-12). 2 = balcony/
## gallery zone stocking + zone-aware key finalize (DG-C3D.F.2d, 2026-07-13) —
## atrium dungeons regenerate with stocked upper zones; balcony-less dungeons
## regenerate byte-identically (the balcony stream draws zero values for
## them). Each bump invalidates every stored generated dungeon at once; each
## lazily regenerates on next access. Hand-authored payloads (test content —
## cells but no dungeon_floors provenance rows) are exempted at the
## DungeonFixtureService seam and never regenerate.
const GENERATOR_VERSION: int = 2


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
	# Step 13 — persist (optional; once, on the accepted result). Zones and
	# stairwells ride the same transaction as the floors (DG-C3D.F).
	# ---------------------------------------------------------------------------
	if request.persist and result.success:
		if not DungeonGeneratorRepository.insert_dungeon_layout(
				dungeon_id, result.floors, result.key_items,
				result.zones, result.stairwells):
			result.errors.append("DungeonGeneratorV1: persist failed for dungeon '%s'" % dungeon_id)
			result.success = false
			push_error("DungeonGeneratorV1.generate: DB insert failed for dungeon '%s'" % dungeon_id)

	return result


## One generation attempt for a fixed master_seed (Steps 5-12) through the
## COMPOSED pipeline (DG-C3D.F; contiguous GDD §8): vertical plan → per-band
## layouts (reservations pre-placed, NO legacy stairs) → per-band stocking →
## vertical composition into ONE VoxelMapData → composed key/lever placement →
## per-zone stocking projection → composed solvability + acceptance. Returns a
## result whose `success` is false if a band is ungenerable or the dungeon is
## not solvable/acceptable; generate() then retries with a fresh seed.
static func _generate_attempt(
		request: DungeonGeneratorRequestV1,
		master_seed: int,
		dungeon_id: String,
		loader: DungeonDataLoader,
		registry: MonsterRegistry) -> DungeonGeneratorResultV1:
	var result := DungeonGeneratorResultV1.new()
	result.dungeon_id = dungeon_id

	# ---------------------------------------------------------------------------
	# Step 5 — whole-dungeon vertical plan (DG-C3D.B): bands + walk levels +
	# per-band tiers, connectors, atrium promotions, reserved footprints. Draws
	# ONLY from its own namespaced stream (conventions §118); a single-band
	# dungeon draws zero values, so the per-floor layout/stocking streams below
	# are byte-identical to the pre-flip pipeline for single-floor dungeons.
	# ---------------------------------------------------------------------------
	var theme: DungeonTheme = DungeonThemeCatalog.get_theme(request.dungeon_type)
	var vplan: VerticalPlan = VerticalPlan.build(
		request, theme, VerticalPlan.derive_rng(master_seed))
	if vplan == null:
		result.errors.append(
			"DungeonGeneratorV1: vertical plan failed (master seed %d)" % master_seed)
		return result

	if DungeonTierDerivation.clamp_fired(
			request.entrance_tier, request.floor_count, request.entrance_floor_index):
		result.warnings.append(
			"tier clamp fired (entrance_tier=%d floor_count=%d efi=%d) — deep floors capped at tier 6"
			% [request.entrance_tier, request.floor_count, request.entrance_floor_index])

	# floor_index -> walk level, for the composed validators/placer.
	var band_walk: Dictionary = {}
	for band in vplan.bands:
		band_walk[band.floor_index] = band.walk_level

	# ---------------------------------------------------------------------------
	# Step 6 — generate one layout per band. The vertical plan's reservations
	# enter each band as pre-placed rooms (circulation footprints, atrium
	# base/upper); legacy stair anchoring is gone — vertical connectivity is
	# carved by the composer, so bands place NO stairs except the entrance
	# band's single up-stair (the overworld connection).
	# ---------------------------------------------------------------------------
	for floor_index in range(1, request.floor_count + 1):
		var req := DungeonLayoutRequest.new()
		req.dungeon_type = request.dungeon_type
		req.dungeon_size = request.dungeon_size
		req.level_number = floor_index
		req.floor_tier = vplan.band_for_floor(floor_index).tier
		req.is_entrance_floor = (floor_index == request.entrance_floor_index)
		req.seed = master_seed + floor_index * 1000003
		req.stairs_down = 0
		req.stairs_up = 1 if req.is_entrance_floor else 0
		req.reserved_rooms = vplan.reservations_for_band(floor_index)

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

	# The only stair any band carries is the entrance band's overworld up-stair;
	# wire its connects_to_level = 0 (overworld convention). Vertical band-to-band
	# connectivity is the composer's stairwells, not DungeonStairData.
	for fl in result.floors:
		var floor_layout: DungeonLayout = fl
		for s in floor_layout.stairs:
			var stair: DungeonStairData = s
			if stair.direction == DungeonStairData.DIRECTION_UP and stair.is_entrance_stair:
				stair.connects_to_level = 0

	# ---------------------------------------------------------------------------
	# Steps 7-10 — stock per band, compose, key/lever on the composed volume,
	# per-zone projection, composed solvability + acceptance (with retry).
	#
	# The stocker randomly converts doors to secret+locked for trap rooms. If a
	# trap room's door is on the only path between the entrance and content,
	# solvability fails. We retry stocking with a different seed up to 3 times
	# before accepting the result (solvability failures are then logged as errors
	# but do not prevent returning a best-effort result for the test harness).
	# The volume is re-composed per attempt because composition stamps the
	# CURRENT door states into its door records/cells.
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
	var compose_result: DungeonVolumeComposer.ComposeResult = null
	var placement: Dictionary = {}
	var placement_solved: bool = false
	# Warnings from the composer / placer / gate telemetry are collected per
	# attempt and only the ACCEPTED (or final) attempt's are surfaced — a
	# rejected attempt's warnings describe door/key states that were rolled
	# back, and the deterministic compose warnings would otherwise duplicate
	# once per retry.
	var attempt_warnings: Array[String] = []
	var stocking_attempt := 0
	const MAX_STOCKING_ATTEMPTS := 4

	while stocking_attempt < MAX_STOCKING_ATTEMPTS:
		stocking_attempt += 1
		var stocking_seed_bump: int = (stocking_attempt - 1) * 999983

		# Step 7 — stock each band (clear previous stocking state on retry).
		for fi in range(result.floors.size()):
			var floor_layout: DungeonLayout = result.floors[fi]
			# Clear stocker-generated state so the retry is fresh. Circulation
			# rooms are never stocked (§11.1) — leave their default "empty"
			# contents intact so they persist under the dungeon_rooms
			# contents_kind CHECK enum ("" is not a valid value).
			for room in floor_layout.rooms:
				if room.kind == DungeonRoomData.KIND_CIRCULATION:
					continue
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

		# Step 8 — vertical composition (DG-C3D.D): stamp the stocked bands into
		# ONE contiguous VoxelMapData, carve connectors + atriums, assign zones.
		# Runs after stocking so the door records carry the §11.4 trap gates.
		# Deterministic given the layouts (no RNG stream of its own), so a
		# compose failure is a geometry bug no stocking re-roll can fix — bail to
		# the whole-dungeon re-seed ladder.
		attempt_warnings = []
		compose_result = DungeonVolumeComposer.compose(
			vplan, result.floors, master_seed, dungeon_id)
		for cw in compose_result.warnings:
			attempt_warnings.append(str(cw))
		if not compose_result.ok:
			for aw in attempt_warnings:
				result.warnings.append(aw)
			result.errors.append("DungeonGeneratorV1: composition failed — %s" % compose_result.error)
			return result

		# Step 8b — project the per-band stocking results onto the composed
		# zones (F.2a; draws no RNG): zone 0 mirrors its room's stocking. Runs
		# BEFORE the balcony pass and the placer so zone records are complete
		# when keys finalize against them.
		DungeonStocker.map_band_stocking_to_zones(result.floors, compose_result)

		# Step 8c — balcony/gallery zone stocking (F.2d; contiguous GDD §11):
		# zone_index >= 1 zones roll their own d100 at their band's tier from a
		# dedicated namespaced stream (zero draws when no such zones exist).
		# Balcony trap gates mutate door RECORDS + volume cells here, BEFORE
		# the placer, so they are keyed like any other gated door.
		var balcony_rng := DungeonStocker.derive_balcony_rng(master_seed, stocking_seed_bump)
		DungeonStocker.stock_balcony_zones(
			result.floors, compose_result, band_walk, loader, registry, balcony_rng)

		# Step 9 — key/lever placement over the composed 3D movement graph
		# (DG-C3D.E). Same stream derivation as the pre-flip placer. NOTE: the
		# GDD §5 lists key/lever before stocking, but trap rooms (§11.4) create
		# new locked+secret doors during stocking, so this runs after. The
		# placer mutates door RECORDS + volume cells; sync those mutations back
		# onto the band layouts so acceptance (T4/T6) and persistence see them.
		var kl_rng := RandomNumberGenerator.new()
		kl_rng.seed = master_seed + 104729 + stocking_seed_bump
		placement = DungeonKeyLeverPlacer.place_composed(
			compose_result.volume, compose_result.zones, compose_result.stairwells,
			compose_result.rooms, compose_result.doors, band_walk,
			compose_result.volume.entry_pos, kl_rng)
		placement_solved = bool(placement.get("solved", false))
		for pw in placement.get("warnings", []):
			attempt_warnings.append(str(pw))
		DungeonKeyLeverPlacer.sync_composed_doors_to_layouts(
			compose_result.doors, placement["wired_levers"], result.floors, band_walk)
		var keys: Array[KeyItemData] = DungeonKeyLeverPlacer.composed_keys_to_items(
			placement["keys"], compose_result.doors)
		DungeonKeyLeverPlacer.finalize_key_placements_composed(
			keys, result.floors, compose_result.zones, loader, kl_rng)
		result.key_items = keys

		# Step 9b — zone-0 refresh (idempotent, no RNG): re-copy room fields
		# onto zone 0 so §10.4 trap-room demotions from the sync-back and
		# finalize's forced-hoard back-links stay mirrored; then compose each
		# atrium room's LLM-facing purpose from its zones.
		DungeonStocker.map_band_stocking_to_zones(result.floors, compose_result)
		DungeonStocker.compose_atrium_rollups(result.floors, compose_result)

		# Step 10 — composed solvability + acceptance gate. BOTH must pass (plus
		# the placer's own rule-3 verdict) to accept this attempt. Re-rolling the
		# stocking seed changes trap placement, so it can clear a solvability
		# failure or a transient hard acceptance failure. T6 over-gating (>1) is
		# only a soft warning and never forces a retry.
		# Gate blast-radius telemetry re-runs the reach once per key — far too
		# expensive per retry attempt; it runs ONCE on the final state below.
		solv = DungeonNavigabilityValidator.validate_composed_solvability(
			compose_result.volume, compose_result.zones, compose_result.stairwells,
			compose_result.doors, placement["keys"], band_walk,
			compose_result.volume.entry_pos, placement["wired_levers"], 0.40, false)
		report = DungeonAcceptanceTests.run(result)
		var attempt_hard_pass: bool = report.get("hard_pass", false)
		if solv["ok"] and placement_solved and attempt_hard_pass:
			break  # solvable AND acceptance-clean — done retrying

		if stocking_attempt < MAX_STOCKING_ATTEMPTS:
			push_warning("DungeonGeneratorV1: stocking attempt %d not accepted (solvable=%s, placer_solved=%s, hard_pass=%s) — retrying with a different stocking seed."
				% [stocking_attempt, str(solv.get("ok", false)), str(placement_solved), str(attempt_hard_pass)])

	# [GATE] blast-radius telemetry (§10.3) once, against the accepted state —
	# the per-key reach re-runs were skipped inside the retry loop.
	if solv.get("ok", false) and placement_solved and not placement.is_empty():
		var telemetry: Dictionary = DungeonNavigabilityValidator.validate_composed_solvability(
			compose_result.volume, compose_result.zones, compose_result.stairwells,
			compose_result.doors, placement["keys"], band_walk,
			compose_result.volume.entry_pos, placement["wired_levers"])
		for gw in telemetry.get("gate_warnings", []):
			attempt_warnings.append(str(gw))

	# Surface the accepted (or final) attempt's composer/placer/gate warnings.
	for aw in attempt_warnings:
		result.warnings.append(aw)

	if not solv["ok"]:
		for failure in solv["failures"]:
			result.errors.append(str(failure))
	if not placement_solved:
		result.errors.append("DungeonGeneratorV1: composed key/lever placement unsolved (rule-3 structural defect) — re-seed required.")

	# ---------------------------------------------------------------------------
	# Step 11 — composed output + hoard cell remap.
	# ---------------------------------------------------------------------------
	result.composed_volume = compose_result.volume
	result.stairwells = compose_result.stairwells
	result.zones = compose_result.zones

	# Treasure hoards were placed on the 2D band grids at the LEGACY voxel z
	# (level_number - 1, stamped by DungeonStocker._place_hoards). Remap each
	# placed hoard's cell_z to its band's composed walk level so the runtime
	# cell-based loot query (get_unlooted_treasure_hoard_at_cell) matches the
	# volume's coordinates. A no-op for a single-band dungeon (both are 0).
	# Guarded to hoards still carrying the legacy stamp, so a placement site
	# that already writes a real composed z (the F.2d balcony-zone pass) is
	# never clobbered. Unplaced hoards (cell_x == -1, e.g. finalize-forced key
	# hoards) keep their sentinel.
	for fl in result.floors:
		var floor_layout: DungeonLayout = fl
		var walk: int = int(band_walk.get(floor_layout.level_number, 0))
		for h in floor_layout.treasure_hoards:
			var hoard: TreasureHoardData = h
			if hoard.cell_x >= 0 and hoard.cell_z == floor_layout.level_number - 1:
				hoard.cell_z = walk

	# ---------------------------------------------------------------------------
	# Step 12 — record the final acceptance report + set success flag
	# ---------------------------------------------------------------------------
	result.acceptance_report = report
	result.placeholder_counts = report.get("placeholder_counts", {})
	for w in report.get("soft_warnings", []):
		result.warnings.append(str(w))

	var hard_pass: bool = report.get("hard_pass", false)
	# Surface any residual hard failures (e.g. an unresolvable topological case
	# after all retries) in result.errors, not just the acceptance report.
	if not hard_pass:
		for hf in report.get("hard_failures", []):
			result.errors.append(str(hf))
	result.success = hard_pass and solv["ok"] and placement_solved and result.errors.is_empty()
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
	else:
		# Composed-pipeline band with no stairs (vertical connectivity is the
		# composer's, not DungeonStairData): seed from the shared fallback so
		# this guard and validate_layout can never diverge.
		var seed_cell: Vector2i = DungeonNavigabilityValidator.fallback_seed_cell(layout)
		if seed_cell != Vector2i(-1, -1):
			visited[seed_cell] = true
			queue.append(seed_cell)

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
