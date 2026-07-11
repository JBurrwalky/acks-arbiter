extends "res://tests/test_suite_base.gd"

## DG-C3D.D unit tests — DungeonVolumeComposer (vertical composition).
##
## Covers the build-plan D requirements:
##   1. Per-connector-pattern fixtures (straight / ramp / switchback / spiral):
##      hand-built two-band micro-dungeons; assert the exact §6 cell pattern
##      (step features + suffixes, under-fill, shaft openings, mid-landings,
##      spiral shafts) and that floor integrity holds (compose ok).
##   2. Atrium fixture: main + balcony zones; void cells floor_type none with the
##      atrium room_id; parapet cover on balcony edges; disconnected same-band
##      regions -> distinct zone_index; degradation when no balcony access.
##   3. Walk-level stamping: subterranean 3-floor at -2/-1 and -4/-3; above-ground
##      ascends.
##   4. Floor-integrity pass: a clean composed volume passes; a deliberately
##      corrupted slab is caught; the real C->D pipeline passes over a seed sweep.
##   5. Band honesty: every zoned cell sits at walk_level(band) (offset 0).
##
## All fixtures are deterministic; every assertion is run-to-run stable.


func run_all_tests() -> void:
	test_straight_run_pattern()
	test_ramp_run_pattern()
	test_switchback_pattern()
	test_spiral_pattern()
	test_walk_level_stamping_subterranean()
	test_above_ground_ascends()
	test_atrium_void_ring_parapet_zones()
	test_atrium_degrades_without_access()
	test_disconnected_regions_distinct_zones()
	test_band_honesty()
	test_floor_integrity_detects_corrupt_slab()
	test_floor_integrity_property_sweep()
	if not has_failures():
		print("DungeonVolumeComposer: all tests passed.")


# ---------------------------------------------------------------------------
# Fixture builders
# ---------------------------------------------------------------------------

func _band(floor_index: int, walk: int, tier: int = 1) -> VerticalPlan.BandPlan:
	var b := VerticalPlan.BandPlan.new()
	b.floor_index = floor_index
	b.walk_level = walk
	b.tier = tier
	return b


func _connector(type: String, lower: int, upper: int, footprint: Rect2i, width: int) -> VerticalPlan.ConnectorPlan:
	var c := VerticalPlan.ConnectorPlan.new()
	c.type = type
	c.lower_band = lower
	c.upper_band = upper
	c.footprint = footprint
	c.width = width
	c.is_sole_connector = true
	return c


func _plan(grid: Vector2i, dir: int, entrance: int, bands: Array, connectors: Array, atriums: Array = []) -> VerticalPlan:
	var p := VerticalPlan.new()
	p.grid_size = grid
	p.direction = dir
	p.entrance_floor_index = entrance
	for b in bands:
		p.bands.append(b)
	for c in connectors:
		p.connectors.append(c)
	for a in atriums:
		p.atriums.append(a)
	return p


## Build a DungeonLayout. [param specs] entries: {rect: Rect2i, kind: String,
## blocked: bool}. Blocked regions stay rock and emit no room (mirrors the
## DG-C3D.C rasterizer for atrium-upper footprints).
func _layout(grid_w: int, grid_h: int, level_number: int, specs: Array,
		entrance: Vector2i = Vector2i(-1, -1), is_entrance: bool = false) -> DungeonLayout:
	var layout := DungeonLayout.new()
	layout.level_number = level_number
	layout.grid_width = grid_w
	layout.grid_height = grid_h
	layout.is_entrance_floor = is_entrance
	layout.entrance = entrance
	var cells: Array[Array] = []
	for x in range(grid_w):
		var col: Array[DungeonCellData] = []
		for y in range(grid_h):
			var c := DungeonCellData.new()
			c.terrain_feature = DungeonCellData.FEATURE_ROCK
			c.passable = false
			c.room_id = -1
			col.append(c)
		cells.append(col)
	layout.cells = cells

	var rid: int = 0
	for spec in specs:
		var rect: Rect2i = spec["rect"]
		var kind: String = spec.get("kind", DungeonRoomData.KIND_CHAMBER)
		var blocked: bool = spec.get("blocked", false)
		if not blocked:
			var rd := DungeonRoomData.new()
			rd.id = rid
			rd.kind = kind
			rd.bounds = rect
			rd.band = level_number
			for x in range(rect.position.x, rect.end.x):
				for y in range(rect.position.y, rect.end.y):
					var c: DungeonCellData = cells[x][y]
					c.terrain_feature = DungeonCellData.FEATURE_OPEN
					c.passable = true
					c.room_id = rid
					rd.cells.append(Vector2i(x, y))
			layout.rooms.append(rd)
		rid += 1
	return layout


func _cell(vol: VoxelMapData, x: int, y: int, z: int) -> VoxelCell:
	return vol.get_cell(Vector3i(x, y, z))


# ---------------------------------------------------------------------------
# 1. Connector patterns
# ---------------------------------------------------------------------------

## Straight run: footprint (3,3,4,2), lower band 2 (walk -2) up to band 1 (walk 0).
func test_straight_run_pattern() -> void:
	var plan := _plan(Vector2i(12, 12), VerticalPlan.DIRECTION_DOWN, 1,
		[_band(1, 0), _band(2, -2)],
		[_connector(StairwellData.TYPE_STRAIGHT, 2, 1, Rect2i(3, 3, 4, 2), 2)])
	var lower := _layout(12, 12, 2, [{"rect": Rect2i(3, 3, 4, 2), "kind": DungeonRoomData.KIND_CIRCULATION}])
	var upper := _layout(12, 12, 1, [{"rect": Rect2i(3, 3, 4, 2), "kind": DungeonRoomData.KIND_CIRCULATION}],
		Vector2i(3, 3), true)
	var res := DungeonVolumeComposer.compose(plan, [upper, lower], 111, "straight")
	check(res.ok, "straight compose ok: %s" % res.error)
	var v := res.volume
	# idx0 L (3,3,-2) landing; idx1 A (4,3,-2) lower step E; idx2 B (5,3,-1) upper step.
	check(_cell(v, 3, 3, -2).floor_type == "stone" and _cell(v, 3, 3, -2).solidity == "air", "L floor")
	check(_cell(v, 4, 3, -2).feature == "stairs_up_E" and _cell(v, 4, 3, -2).floor_type == "stone", "A step stairs_up_E")
	check(_cell(v, 5, 3, -1).feature == "stairs_up_E" and _cell(v, 5, 3, -1).floor_type == "stone", "B step at WL+1")
	check(_cell(v, 5, 3, -2).solidity == "solid", "under-B solid")
	check(_cell(v, 6, 3, 0).floor_type == "stone" and _cell(v, 6, 3, 0).solidity == "air", "T top landing at WU")
	check(_cell(v, 6, 3, -2).solidity == "solid" and _cell(v, 6, 3, -1).solidity == "solid", "under-T solid both levels")
	check(_cell(v, 5, 3, 0).floor_type == "none" and _cell(v, 5, 3, 0).solidity == "air", "shaft above B is open void")
	check(_cell(v, 3, 3, 0).floor_type == "none", "shaft above L open")
	check(res.stairwells.size() == 1, "one stairwell emitted")
	if res.stairwells.size() == 1:
		var sw: StairwellData = res.stairwells[0]
		check(sw.type == StairwellData.TYPE_STRAIGHT, "stairwell type straight")
		check(sw.bottom_cell == Vector3i(3, 3, -2), "bottom cell = L")
		check(sw.top_cell == Vector3i(6, 3, 0), "top cell = T")
		# No door cell inside the run (§10.3 emission rule).
		var run_has_door := false
		for rc in sw.run_cells:
			if v.get_cell(rc).door_state != "":
				run_has_door = true
		check(not run_has_door, "no door cells inside run")


## Ramp: same geometry, ramp_ feature + dirt floor.
func test_ramp_run_pattern() -> void:
	var plan := _plan(Vector2i(12, 12), VerticalPlan.DIRECTION_DOWN, 1,
		[_band(1, 0), _band(2, -2)],
		[_connector(StairwellData.TYPE_RAMP, 2, 1, Rect2i(3, 3, 4, 2), 2)])
	var lower := _layout(12, 12, 2, [{"rect": Rect2i(3, 3, 4, 2), "kind": DungeonRoomData.KIND_CIRCULATION}])
	var upper := _layout(12, 12, 1, [{"rect": Rect2i(3, 3, 4, 2), "kind": DungeonRoomData.KIND_CIRCULATION}])
	var res := DungeonVolumeComposer.compose(plan, [upper, lower], 222, "ramp")
	check(res.ok, "ramp compose ok: %s" % res.error)
	var v := res.volume
	check(_cell(v, 4, 3, -2).feature == "ramp_E" and _cell(v, 4, 3, -2).floor_type == "dirt", "ramp cell feature + dirt floor")
	check(_cell(v, 5, 3, -1).feature == "ramp_E", "upper ramp step")
	check(_cell(v, 5, 3, 0).floor_type == "none", "ramp shaft open")


## Switchback: footprint (3,3,3,2), east step -> mid-landing -> west step.
func test_switchback_pattern() -> void:
	var plan := _plan(Vector2i(12, 12), VerticalPlan.DIRECTION_DOWN, 1,
		[_band(1, 0), _band(2, -2)],
		[_connector(StairwellData.TYPE_SWITCHBACK, 2, 1, Rect2i(3, 3, 3, 2), 1)])
	var lower := _layout(12, 12, 2, [{"rect": Rect2i(3, 3, 3, 2), "kind": DungeonRoomData.KIND_CIRCULATION}])
	var upper := _layout(12, 12, 1, [{"rect": Rect2i(3, 3, 3, 2), "kind": DungeonRoomData.KIND_CIRCULATION}])
	var res := DungeonVolumeComposer.compose(plan, [upper, lower], 333, "switchback")
	check(res.ok, "switchback compose ok: %s" % res.error)
	var v := res.volume
	check(_cell(v, 3, 3, -2).floor_type == "stone", "L landing")
	check(_cell(v, 4, 3, -2).feature == "stairs_up_E", "A rises east")
	check(_cell(v, 5, 3, -1).floor_type == "stone" and _cell(v, 5, 3, -1).feature == "open", "mid-landing at WL+1")
	check(_cell(v, 5, 4, -1).feature == "stairs_up_W", "B rises west at WL+1")
	check(_cell(v, 5, 4, 0).floor_type == "none", "shaft above B open")
	check(_cell(v, 4, 4, 0).floor_type == "stone", "upper landing floor")
	check(res.stairwells.size() == 1 and res.stairwells[0].type == StairwellData.TYPE_SWITCHBACK, "switchback stairwell")


## Spiral: 2x2 shaft — stone at each walk level, floor opening between.
func test_spiral_pattern() -> void:
	var plan := _plan(Vector2i(12, 12), VerticalPlan.DIRECTION_DOWN, 1,
		[_band(1, 0), _band(2, -2)],
		[_connector(StairwellData.TYPE_SPIRAL, 2, 1, Rect2i(4, 4, 2, 2), 1)])
	var lower := _layout(12, 12, 2, [{"rect": Rect2i(4, 4, 2, 2), "kind": DungeonRoomData.KIND_CIRCULATION}])
	var upper := _layout(12, 12, 1, [{"rect": Rect2i(4, 4, 2, 2), "kind": DungeonRoomData.KIND_CIRCULATION}])
	var res := DungeonVolumeComposer.compose(plan, [upper, lower], 444, "spiral")
	check(res.ok, "spiral compose ok: %s" % res.error)
	var v := res.volume
	check(_cell(v, 4, 4, -2).feature == "stairs_spiral" and _cell(v, 4, 4, -2).floor_type == "stone", "spiral bottom stone")
	check(_cell(v, 4, 4, -1).feature == "stairs_spiral" and _cell(v, 4, 4, -1).floor_type == "none", "spiral gap open")
	check(_cell(v, 4, 4, 0).feature == "stairs_spiral" and _cell(v, 4, 4, 0).floor_type == "stone", "spiral top stone")
	check(_cell(v, 5, 5, -2).feature == "stairs_spiral", "all four columns are spiral")


# ---------------------------------------------------------------------------
# 3. Walk-level stamping
# ---------------------------------------------------------------------------

func test_walk_level_stamping_subterranean() -> void:
	# 3 subterranean floors: walks 0 / -2 / -4; headroom +1 above each.
	var plan := _plan(Vector2i(14, 14), VerticalPlan.DIRECTION_DOWN, 1,
		[_band(1, 0), _band(2, -2), _band(3, -4)], [])
	var f1 := _layout(14, 14, 1, [{"rect": Rect2i(2, 2, 4, 4)}], Vector2i(2, 2), true)
	var f2 := _layout(14, 14, 2, [{"rect": Rect2i(2, 2, 4, 4)}])
	var f3 := _layout(14, 14, 3, [{"rect": Rect2i(2, 2, 4, 4)}])
	var res := DungeonVolumeComposer.compose(plan, [f1, f2, f3], 555, "stack")
	check(res.ok, "3-floor compose ok: %s" % res.error)
	var v := res.volume
	# Floor 2 open cell at walk -2, headroom -1.
	check(_cell(v, 3, 3, -2).floor_type == "stone" and _cell(v, 3, 3, -2).solidity == "air", "floor 2 walks at -2")
	check(_cell(v, 3, 3, -1).floor_type == "none" and _cell(v, 3, 3, -1).solidity == "air", "floor 2 headroom at -1")
	# Floor 3 open cell at walk -4, headroom -3.
	check(_cell(v, 3, 3, -4).floor_type == "stone", "floor 3 walks at -4")
	check(_cell(v, 3, 3, -3).solidity == "air", "floor 3 headroom at -3")
	# Entrance recorded at floor 1 walk level.
	check(v.entry_pos == Vector3i(2, 2, 0), "entrance at floor 1 walk 0, got %s" % str(v.entry_pos))


func test_above_ground_ascends() -> void:
	# Above ground: walks 0 / +2 / +4.
	var plan := _plan(Vector2i(12, 12), VerticalPlan.DIRECTION_UP, 1,
		[_band(1, 0), _band(2, 2), _band(3, 4)], [])
	var f1 := _layout(12, 12, 1, [{"rect": Rect2i(2, 2, 3, 3)}], Vector2i(2, 2), true)
	var f2 := _layout(12, 12, 2, [{"rect": Rect2i(2, 2, 3, 3)}])
	var f3 := _layout(12, 12, 3, [{"rect": Rect2i(2, 2, 3, 3)}])
	var res := DungeonVolumeComposer.compose(plan, [f1, f2, f3], 666, "tower")
	check(res.ok, "above-ground compose ok: %s" % res.error)
	var v := res.volume
	check(_cell(v, 3, 3, 2).floor_type == "stone", "floor 2 walks at +2")
	check(_cell(v, 3, 3, 4).floor_type == "stone", "floor 3 walks at +4")


# ---------------------------------------------------------------------------
# 2. Atrium
# ---------------------------------------------------------------------------

func _atrium_plan_obj(base_band: int, upper_band: int, footprint: Rect2i, internal_stair: bool) -> VerticalPlan.AtriumPlan:
	var a := VerticalPlan.AtriumPlan.new()
	a.base_band = base_band
	a.upper_band = upper_band
	a.footprint = footprint
	a.ring_depth = 1
	a.ring_is_ledge = false
	a.internal_stair = internal_stair
	return a


func test_atrium_void_ring_parapet_zones() -> void:
	var foot := Rect2i(2, 2, 5, 5)
	var atrium := _atrium_plan_obj(2, 1, foot, true)  # base = deeper floor 2
	var plan := _plan(Vector2i(14, 14), VerticalPlan.DIRECTION_DOWN, 1,
		[_band(1, 0), _band(2, -2)], [], [atrium])
	# Floor 2 hosts the atrium main floor; floor 1 has it as a blocked region.
	var f2 := _layout(14, 14, 2, [{"rect": foot, "kind": DungeonRoomData.KIND_CHAMBER}])
	var f1 := _layout(14, 14, 1, [{"rect": foot, "blocked": true}], Vector2i(0, 0), false)
	var res := DungeonVolumeComposer.compose(plan, [f1, f2], 777, "atrium")
	check(res.ok, "atrium compose ok: %s" % res.error)
	var v := res.volume
	# Interior void at the upper band (walk 0): air_open, no floor. Pick a void
	# cell clear of the internal grand stair (which recarves its flanks to plain
	# open-void as it rises).
	check(_cell(v, 5, 5, 0).feature == "air_open" and _cell(v, 5, 5, 0).floor_type == "none", "atrium void interior")
	# Ring balcony floor (corner) belongs to the atrium room.
	var corner := _cell(v, 2, 2, 0)
	check(corner.floor_type == "wood" and corner.solidity == "air", "balcony ring floor at corner")
	# Parapet cover on a balcony cell adjacent to the void.
	var edge := _cell(v, 4, 2, 0)  # top-middle ring cell, adjacent to void (4,3,0)
	check(edge.cover_value == DungeonVolumeComposer.PARAPET_COVER, "parapet cover on balcony edge, got %d" % edge.cover_value)
	# Zones: one main (band 2) + at least one balcony (band 1) on the atrium room.
	var main_zones := 0
	var balcony_zones := 0
	for z in res.zones:
		if z.zone_type == RoomZone.ZONE_TYPE_MAIN and z.band == 2:
			main_zones += 1
		if z.zone_type == RoomZone.ZONE_TYPE_BALCONY and z.band == 1:
			balcony_zones += 1
	check(main_zones >= 1, "atrium has a main zone on band 2")
	check(balcony_zones >= 1, "atrium has a balcony zone on band 1")


func test_atrium_degrades_without_access() -> void:
	var foot := Rect2i(2, 2, 5, 5)
	var atrium := _atrium_plan_obj(2, 1, foot, false)  # no internal stair
	var plan := _plan(Vector2i(14, 14), VerticalPlan.DIRECTION_DOWN, 1,
		[_band(1, 0), _band(2, -2)], [], [atrium])
	var f2 := _layout(14, 14, 2, [{"rect": foot, "kind": DungeonRoomData.KIND_CHAMBER}])
	var f1 := _layout(14, 14, 1, [{"rect": foot, "blocked": true}])  # no door reaching the ring
	var res := DungeonVolumeComposer.compose(plan, [f1, f2], 888, "atrium_degraded")
	check(res.ok, "degraded atrium compose ok: %s" % res.error)
	var degraded := false
	for w in res.warnings:
		if w.contains("degraded"):
			degraded = true
	check(degraded, "degradation logged")
	# The ring is void too (main zone only) — corner is now void, not balcony.
	check(_cell(res.volume, 2, 2, 0).floor_type == "none", "degraded ring corner is void")


# ---------------------------------------------------------------------------
# Zone flood-fill: disconnected same-band regions -> distinct zone_index
# ---------------------------------------------------------------------------

func test_disconnected_regions_distinct_zones() -> void:
	# One chamber split by a rock wall into left / right halves (same room_id).
	var plan := _plan(Vector2i(14, 8), VerticalPlan.DIRECTION_DOWN, 1, [_band(1, 0)], [])
	var layout := _layout(14, 8, 1, [{"rect": Rect2i(2, 2, 7, 3)}], Vector2i(2, 2), true)
	# Wall off the middle column (col 5) -> two disconnected open halves.
	for y in range(2, 5):
		var c: DungeonCellData = layout.cells[5][y]
		c.terrain_feature = DungeonCellData.FEATURE_ROCK
		c.passable = false
		c.room_id = -1
	var res := DungeonVolumeComposer.compose(plan, [layout], 999, "split")
	check(res.ok, "split compose ok: %s" % res.error)
	# The room should have produced exactly two zones with distinct indices.
	var room_zones: Array = []
	for z in res.zones:
		if z.room_id == 0:  # single band, slot 0 -> global id 0
			room_zones.append(z)
	check(room_zones.size() == 2, "split chamber -> 2 zones, got %d" % room_zones.size())
	if room_zones.size() == 2:
		check(room_zones[0].zone_index != room_zones[1].zone_index, "distinct zone_index")


# ---------------------------------------------------------------------------
# 5. Band honesty
# ---------------------------------------------------------------------------

func test_band_honesty() -> void:
	var plan := _plan(Vector2i(12, 12), VerticalPlan.DIRECTION_DOWN, 1,
		[_band(1, 0), _band(2, -2)],
		[_connector(StairwellData.TYPE_STRAIGHT, 2, 1, Rect2i(3, 3, 4, 2), 2)])
	var lower := _layout(12, 12, 2, [{"rect": Rect2i(3, 3, 4, 2), "kind": DungeonRoomData.KIND_CIRCULATION},
		{"rect": Rect2i(7, 7, 3, 3)}])
	var upper := _layout(12, 12, 1, [{"rect": Rect2i(3, 3, 4, 2), "kind": DungeonRoomData.KIND_CIRCULATION},
		{"rect": Rect2i(7, 7, 3, 3)}], Vector2i(7, 7), true)
	var res := DungeonVolumeComposer.compose(plan, [upper, lower], 1234, "honest")
	check(res.ok, "compose ok: %s" % res.error)
	var v := res.volume
	# Every zone's cells sit at walk_level(zone.band).
	var walk_by_band: Dictionary = {}
	for b in plan.bands:
		walk_by_band[b.floor_index] = b.walk_level
	var honest := true
	for z in res.zones:
		var walk: int = walk_by_band[z.band]
		for c in z.cells:
			if v.get_cell(Vector3i(c.x, c.y, walk)).zone_index != z.zone_index:
				honest = false
	check(honest, "every zone cell stamped at walk_level(band)")
	# No zoned voxel cell lives off a walk level.
	var walk_set: Dictionary = {}
	for b in plan.bands:
		walk_set[b.walk_level] = true
	var off_walk := 0
	for pos in v.get_all_positions():
		if v.get_cell(pos).zone_index >= 0 and not walk_set.has(pos.z):
			off_walk += 1
	check(off_walk == 0, "no zoned cell off a walk level, found %d" % off_walk)


# ---------------------------------------------------------------------------
# 4. Floor integrity
# ---------------------------------------------------------------------------

func test_floor_integrity_detects_corrupt_slab() -> void:
	# Hand-build a 1x1 two-band volume so absent-cell sentinels don't count as
	# holes: floor 2 (WL -2) open + headroom -1 air; floor 1 (WU 0) open floor.
	var plan := _plan(Vector2i(1, 1), VerticalPlan.DIRECTION_DOWN, 1, [_band(1, 0), _band(2, -2)], [])
	var vol := VoxelMapData.new()
	_open(vol, 0, 0, -2)
	_air_gap(vol, 0, 0, -1)
	_open(vol, 0, 0, 0)
	# Clean: no violation.
	check(DungeonVolumeComposer._check_floor_integrity(vol, plan, {}) == "", "clean slab passes")
	# Corrupt: punch an undeclared hole in the floor-1 slab.
	var slab: VoxelCell = vol.get_cell(Vector3i(0, 0, 0))
	slab.floor_type = "none"
	vol.set_cell(Vector3i(0, 0, 0), slab)
	var msg := DungeonVolumeComposer._check_floor_integrity(vol, plan, {})
	check(msg != "", "undeclared hole is caught")
	# Registered opening with the same hole: legal.
	check(DungeonVolumeComposer._check_floor_integrity(vol, plan, {Vector3i(0, 0, 0): true}) == "",
		"registered opening with no floor passes")


func test_floor_integrity_property_sweep() -> void:
	# Drive the real C->D pipeline (layout gen with reservations -> compose) and
	# assert floor integrity holds for every seed.
	var theme: DungeonTheme = DungeonThemeCatalog.get_theme("wizards_dungeon")
	for seed_value in [7, 42, 108, 2024]:
		var request := DungeonGeneratorRequestV1.new()
		request.dungeon_size = DungeonLayoutRequest.SIZE_SMALL
		request.floor_count = 3
		request.entrance_floor_index = 1
		request.dungeon_type = "wizards_dungeon"
		request.entrance_tier = 1
		request.seed = seed_value
		var plan := VerticalPlan.build(request, theme, VerticalPlan.derive_rng(seed_value))
		check(plan != null, "plan builds for seed %d" % seed_value)
		if plan == null:
			continue
		var layouts: Array[DungeonLayout] = []
		var ok_layouts := true
		for fi in range(1, request.floor_count + 1):
			var req := DungeonLayoutRequest.new()
			req.dungeon_type = request.dungeon_type
			req.dungeon_size = request.dungeon_size
			req.level_number = fi
			req.floor_tier = plan.band_for_floor(fi).tier
			req.is_entrance_floor = (fi == request.entrance_floor_index)
			req.seed = seed_value + fi * 1000003
			req.reserved_rooms = plan.reservations_for_band(fi)
			var layout := DungeonLayoutGenerator.generate(req)
			if layout == null:
				ok_layouts = false
				break
			layouts.append(layout)
		check(ok_layouts, "all bands generated for seed %d" % seed_value)
		if not ok_layouts:
			continue
		var res := DungeonVolumeComposer.compose(plan, layouts, seed_value, "sweep_%d" % seed_value)
		check(res.ok, "seed %d composes with clean floor integrity: %s" % [seed_value, res.error])


# ---------------------------------------------------------------------------
# Small volume helpers (for the direct floor-integrity test)
# ---------------------------------------------------------------------------

func _open(vol: VoxelMapData, x: int, y: int, z: int) -> void:
	var c := VoxelCell.new()
	c.col = x
	c.row = y
	c.level = z
	c.solidity = "air"
	c.feature = "open"
	c.floor_type = "stone"
	vol.set_cell(Vector3i(x, y, z), c)


func _air_gap(vol: VoxelMapData, x: int, y: int, z: int) -> void:
	var c := VoxelCell.new()
	c.col = x
	c.row = y
	c.level = z
	c.solidity = "air"
	c.feature = "open"
	c.floor_type = "none"
	vol.set_cell(Vector3i(x, y, z), c)
