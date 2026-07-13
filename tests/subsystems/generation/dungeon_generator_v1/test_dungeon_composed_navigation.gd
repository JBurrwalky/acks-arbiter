extends "res://tests/test_suite_base.gd"

## DG-C3D.E unit tests — 3D-graph validation, spiral movement clause, and the
## composed-volume key/lever placer / solvability, all on the real movement
## graph (MovementRules).
##
## Covers the build-plan E requirements:
##   1. Spiral: ±1-level in-column movement at normal cost, support on the open
##      gap cell, engagement across adjacent spiral levels.
##   2. Traversal per connector type: bottom landing -> top landing through each
##      §6 pattern using only legal ground steps (D's geometry meets movement).
##   3. Structural validator on a composed fixture: every zone + stairwell
##      reachable; §10.2 checks (stair geometry, no-door-in-run, band honesty,
##      edge symmetry) pass.
##   4. Solvability + placer: locked stairwell-room door gating a whole band ->
##      key lands on an earlier band and the dungeon solves; secret+unlocked
##      blocker cleared; disconnected reservation -> rule-3 hard fail; [GATE]
##      blast-radius telemetry.


func run_all_tests() -> void:
	test_spiral_support_on_gap_cell()
	test_spiral_in_column_movement()
	test_spiral_engagement_adjacent_levels()
	test_straight_run_traversable_both_ways()
	test_switchback_traversable()
	test_spiral_connector_traversable()
	test_ramp_traversable()
	test_structural_validator_clean()
	test_no_door_in_run_assertion()
	test_solvability_locked_band_gate_key_crosses_band()
	test_solvability_secret_unlocked_cleared()
	test_placer_10_4_downgrade_sole_path()
	test_placer_rule3_disconnected_hard_fail()
	test_gate_blast_radius_warning()
	if not has_failures():
		print("DungeonComposedNavigation: all tests passed.")


# ---------------------------------------------------------------------------
# Fixture builders (shared with the composer-test style)
# ---------------------------------------------------------------------------

func _band(floor_index: int, walk: int) -> VerticalPlan.BandPlan:
	var b := VerticalPlan.BandPlan.new()
	b.floor_index = floor_index
	b.walk_level = walk
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


func _plan(grid: Vector2i, entrance: int, bands: Array, connectors: Array) -> VerticalPlan:
	var p := VerticalPlan.new()
	p.grid_size = grid
	p.direction = VerticalPlan.DIRECTION_DOWN
	p.entrance_floor_index = entrance
	for b in bands:
		p.bands.append(b)
	for c in connectors:
		p.connectors.append(c)
	return p


func _band_walk(plan: VerticalPlan) -> Dictionary:
	var out: Dictionary = {}
	for b in plan.bands:
		out[b.floor_index] = b.walk_level
	return out


## Build a DungeonLayout. specs: {rect, kind, blocked, doors:[{pos, type,
## is_secret, material}]}.
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
	# Doors.
	for spec in specs:
		for door_spec in spec.get("doors", []):
			var dd := DungeonDoorData.new()
			dd.position = door_spec["pos"]
			dd.type = door_spec.get("type", DungeonDoorData.TYPE_UNLOCKED)
			dd.is_secret = door_spec.get("is_secret", false)
			dd.door_material = door_spec.get("material", DungeonDoorData.MATERIAL_WOOD_STANDARD)
			var conn: Array[int] = []
			for cid in door_spec.get("connects", []):
				conn.append(int(cid))
			dd.connects = conn
			layout.doors.append(dd)
			var dc: DungeonCellData = layout.cells[dd.position.x][dd.position.y]
			dc.terrain_feature = DungeonCellData.FEATURE_DOOR
			dc.passable = true
	return layout


func _mover(map: VoxelMapData) -> MovementResolver:
	var m := MovementResolver.new(null)
	m.set_voxel_map(map)
	return m


# ---------------------------------------------------------------------------
# 1. Spiral movement + support
# ---------------------------------------------------------------------------

func _spiral_map() -> VoxelMapData:
	# A spiral column (2,2) rising from level 0 to level 2, floor cells at each
	# walk level so a walker can stand at the bottom and top.
	var m := VoxelMapData.new()
	_put(m, 2, 2, 0, "stairs_spiral", "stone")
	_put(m, 2, 2, 1, "stairs_spiral", "none")
	_put(m, 2, 2, 2, "stairs_spiral", "stone")
	# Adjacent floor cells at the two walk levels to step off onto.
	_put(m, 3, 2, 0, "open", "stone")
	_put(m, 3, 2, 2, "open", "stone")
	return m


func _put(m: VoxelMapData, x: int, y: int, z: int, feature: String, floor_type: String) -> void:
	var c := VoxelCell.new()
	c.col = x
	c.row = y
	c.level = z
	c.solidity = "air"
	c.feature = feature
	c.floor_type = floor_type
	m.set_cell(Vector3i(x, y, z), c)


func test_spiral_support_on_gap_cell() -> void:
	var m := _spiral_map()
	check(FallingResolver.has_support(m, Vector3i(2, 2, 1)),
		"spiral gap cell (floor none) is supported by the winding stair")
	check(not FallingResolver.has_support(m, Vector3i(5, 5, 1)),
		"a plain floor-none air cell is NOT supported (control)")


func test_spiral_in_column_movement() -> void:
	var m := _spiral_map()
	var mv := _mover(m)
	var up := mv.path_bfs_3d(Vector3i(2, 2, 0), Vector3i(2, 2, 2), "ground", 20, -1, "strict", "")
	check(up.size() == 3, "spiral up path is 3 cells (0->1->2), got %d" % up.size())
	var down := mv.path_bfs_3d(Vector3i(2, 2, 2), Vector3i(2, 2, 0), "ground", 20, -1, "strict", "")
	check(down.size() == 3, "spiral down path is 3 cells, got %d" % down.size())
	# Reaching the adjacent floor at the top proves you can step off the spiral.
	var off := mv.path_bfs_3d(Vector3i(3, 2, 0), Vector3i(3, 2, 2), "ground", 20, -1, "strict", "")
	check(off.size() > 0, "bottom floor reaches top floor via the spiral")


func test_spiral_engagement_adjacent_levels() -> void:
	# 3D Chebyshev adjacency handles cross-level engagement on a spiral (voxel §20.4).
	check(VoxelGrid.is_adjacent(Vector3i(2, 2, 0), Vector3i(2, 2, 1)), "adjacent across one spiral level")
	check(not VoxelGrid.is_adjacent(Vector3i(2, 2, 0), Vector3i(2, 2, 2)), "not adjacent across two levels")


# ---------------------------------------------------------------------------
# 2. Connector traversal (D geometry on the movement graph)
# ---------------------------------------------------------------------------

func _compose_two_band(conn_type: String, footprint: Rect2i, width: int) -> DungeonVolumeComposer.ComposeResult:
	var plan := _plan(Vector2i(12, 12), 1, [_band(1, 0), _band(2, -2)],
		[_connector(conn_type, 2, 1, footprint, width)])
	var lower := _layout(12, 12, 2, [{"rect": footprint, "kind": DungeonRoomData.KIND_CIRCULATION}])
	var upper := _layout(12, 12, 1, [{"rect": footprint, "kind": DungeonRoomData.KIND_CIRCULATION}],
		Vector2i(footprint.position.x, footprint.position.y), true)
	return DungeonVolumeComposer.compose(plan, [upper, lower], 100, "conn")


func _assert_traversable(res: DungeonVolumeComposer.ComposeResult, label: String) -> void:
	check(res.ok, "%s composes ok: %s" % [label, res.error])
	if not res.ok or res.stairwells.is_empty():
		check(false, "%s: no stairwell to traverse" % label)
		return
	var sw: StairwellData = res.stairwells[0]
	var mv := _mover(res.volume)
	var up := mv.path_bfs_3d(sw.bottom_cell, sw.top_cell, "ground", 60, -1, "strict", "")
	check(up.size() > 0, "%s: bottom landing reaches top landing" % label)
	var down := mv.path_bfs_3d(sw.top_cell, sw.bottom_cell, "ground", 60, -1, "strict", "")
	check(down.size() > 0, "%s: top landing reaches bottom landing (reversible)" % label)


func test_straight_run_traversable_both_ways() -> void:
	_assert_traversable(_compose_two_band(StairwellData.TYPE_STRAIGHT, Rect2i(3, 3, 4, 2), 2), "straight")


func test_switchback_traversable() -> void:
	_assert_traversable(_compose_two_band(StairwellData.TYPE_SWITCHBACK, Rect2i(3, 3, 3, 2), 1), "switchback")


func test_spiral_connector_traversable() -> void:
	_assert_traversable(_compose_two_band(StairwellData.TYPE_SPIRAL, Rect2i(4, 4, 2, 2), 1), "spiral")


func test_ramp_traversable() -> void:
	_assert_traversable(_compose_two_band(StairwellData.TYPE_RAMP, Rect2i(3, 3, 4, 2), 2), "ramp")


# ---------------------------------------------------------------------------
# 3. Structural validator
# ---------------------------------------------------------------------------

## Standard two-band dungeon on a straight run. The stairwell's bottom landing L
## is on band 2 at column 4; its top landing T is on band 1 at column 7. The
## ENTRANCE sits on T (the circulation top landing). Band 1 also has a candidate
## chamber (right of the stairwell, joined to T) so the placer has a
## non-circulation, non-entrance zone to home keys into. Band 2's chamber (left
## of the stairwell) joins the bottom landing L via a door with [param
## band2_door] — omit / set connect_band2 = false to leave it disconnected.
func _make_two_band(band2_door: Dictionary, connect_band2: bool = true, seed_value: int = 200) -> Dictionary:
	var foot := Rect2i(4, 2, 4, 2)  # straight-run footprint (run axis x): L=(4,2), T=(7,2)
	var plan := _plan(Vector2i(16, 12), 1, [_band(1, 0), _band(2, -2)],
		[_connector(StairwellData.TYPE_STRAIGHT, 2, 1, foot, 2)])
	# Band 1 (entrance, walk 0): the circulation footprint (entrance = top landing
	# T at 7,2) + a candidate chamber joined to T by a door at (8,2).
	var b1 := _layout(16, 12, 1, [
		{"rect": foot, "kind": DungeonRoomData.KIND_CIRCULATION},
		{"rect": Rect2i(8, 1, 3, 3), "kind": DungeonRoomData.KIND_CHAMBER,
			"doors": [{"pos": Vector2i(8, 2), "type": DungeonDoorData.TYPE_UNLOCKED}]},
	], Vector2i(7, 2), true)
	# Band 2 (walk -2): the circulation footprint + a chamber left of the bottom
	# landing L (4,2), joined by the caller-supplied door at (3,2).
	var b2_specs: Array = [{"rect": foot, "kind": DungeonRoomData.KIND_CIRCULATION}]
	var chamber: Dictionary = {"rect": Rect2i(0, 1, 3, 3), "kind": DungeonRoomData.KIND_CHAMBER}
	if connect_band2:
		var door: Dictionary = band2_door.duplicate()
		door["pos"] = Vector2i(3, 2)
		chamber["doors"] = [door]
	b2_specs.append(chamber)
	var b2 := _layout(16, 12, 2, b2_specs)
	var res := DungeonVolumeComposer.compose(plan, [b1, b2], seed_value, "twoband")
	return {"plan": plan, "res": res}


func test_structural_validator_clean() -> void:
	var d := _make_two_band({"type": DungeonDoorData.TYPE_UNLOCKED})
	var res: DungeonVolumeComposer.ComposeResult = d["res"]
	check(res.ok, "two-band composes ok: %s" % res.error)
	var report: Dictionary = DungeonNavigabilityValidator.validate_composed_structural(
		res.volume, res.zones, res.stairwells, _band_walk(d["plan"]), res.volume.entry_pos)
	check(report["ok"], "structural validation passes: %s" % report["message"])
	check(report["checks"]["stair_geometry"]["ok"], "stair geometry walks both ways")
	check(report["checks"]["band_honesty"]["ok"], "band honesty holds")
	check(report["checks"]["edge_symmetry"], "edges are symmetric (falls never edges)")


func test_no_door_in_run_assertion() -> void:
	var d := _make_two_band({"type": DungeonDoorData.TYPE_UNLOCKED})
	var res: DungeonVolumeComposer.ComposeResult = d["res"]
	# Inject a door onto a run cell and confirm the assertion trips.
	var sw: StairwellData = res.stairwells[0]
	check(res.stairwells.size() > 0 and sw.run_cells.size() > 0, "have a run to corrupt")
	var clean: Dictionary = DungeonNavigabilityValidator._check_no_door_in_runs(res.volume, res.stairwells)
	check(clean["ok"], "clean run has no doors")
	var rc: Vector3i = sw.run_cells[0]
	var cell: VoxelCell = res.volume.get_cell(rc)
	cell.door_state = "locked"
	res.volume.set_cell(rc, cell)
	var dirty: Dictionary = DungeonNavigabilityValidator._check_no_door_in_runs(res.volume, res.stairwells)
	check(not dirty["ok"], "door injected into a run is caught")


# ---------------------------------------------------------------------------
# 4. Solvability + placer
# ---------------------------------------------------------------------------

## Band 2's only connector-room door is LOCKED STONE (a key-needing gate on the
## sole path to band 2). The placer must land the key in a band-1 zone and the
## dungeon must then be solvable.
func test_solvability_locked_band_gate_key_crosses_band() -> void:
	var d := _make_two_band({"type": DungeonDoorData.TYPE_LOCKED, "material": DungeonDoorData.MATERIAL_STONE}, true, 300)
	var res: DungeonVolumeComposer.ComposeResult = d["res"]
	check(res.ok, "gated dungeon composes: %s" % res.error)
	var bw := _band_walk(d["plan"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var placement: Dictionary = DungeonKeyLeverPlacer.place_composed(
		res.volume, res.zones, res.stairwells, res.rooms, res.doors, bw, res.volume.entry_pos, rng)
	check(placement["solved"], "placer solves the gated dungeon")
	check((placement["keys"] as Array).size() >= 1, "a key was placed for the locked stone door")
	if not (placement["keys"] as Array).is_empty():
		var k: Dictionary = placement["keys"][0]
		check(int(k["band"]) == 1, "key landed on band 1 (earlier than the band-2 door), got band %d" % int(k["band"]))
	var solv: Dictionary = DungeonNavigabilityValidator.validate_composed_solvability(
		res.volume, res.zones, res.stairwells, res.doors, placement["keys"], bw, res.volume.entry_pos, placement["wired_levers"])
	check(solv["ok"], "solvable with the placed key: %s" % str(solv["failures"]))


## A secret+unlocked door on the sole path to content is model-impassable; the
## placer clears its is_secret to keep the content reachable.
func test_solvability_secret_unlocked_cleared() -> void:
	var d := _make_two_band({"type": DungeonDoorData.TYPE_UNLOCKED, "is_secret": true}, true, 400)
	var res: DungeonVolumeComposer.ComposeResult = d["res"]
	check(res.ok, "secret dungeon composes: %s" % res.error)
	var bw := _band_walk(d["plan"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var placement: Dictionary = DungeonKeyLeverPlacer.place_composed(
		res.volume, res.zones, res.stairwells, res.rooms, res.doors, bw, res.volume.entry_pos, rng)
	check(placement["solved"], "placer solves by clearing the blocking secret door")
	# The band-2 chamber's door record (at bottom-landing approach 3,2,-2) is no longer secret.
	var cleared := false
	for rec in res.doors:
		if rec["cell"] == Vector3i(3, 2, -2):
			cleared = not rec["is_secret"]
	check(cleared, "the secret+unlocked blocker was cleared")


## §10.4 sole-path downgrade (composed `_downgrade_composed_door`): a locked-stone
## gate on the sole entrance path with NO fully-discovered candidate zone must be
## downgraded to plain unlocked wood — not keyed and not stranded. Band 1 here has
## only the entrance/circulation zone (no candidate chamber), so when the frontier
## reaches the band-2 connector door no candidate exists and the downgrade fires.
func test_placer_10_4_downgrade_sole_path() -> void:
	var foot := Rect2i(4, 2, 4, 2)
	var plan := _plan(Vector2i(16, 12), 1, [_band(1, 0), _band(2, -2)],
		[_connector(StairwellData.TYPE_STRAIGHT, 2, 1, foot, 2)])
	# Band 1 (entrance, walk 0): ONLY the circulation footprint (entrance = top
	# landing T at 7,2) — no candidate chamber, so no non-entrance/non-circulation
	# zone is ever fully discovered.
	var b1 := _layout(16, 12, 1, [
		{"rect": foot, "kind": DungeonRoomData.KIND_CIRCULATION},
	], Vector2i(7, 2), true)
	# Band 2 (walk -2): circulation + a chamber behind a LOCKED STONE door at (3,2)
	# — the sole gate on the only forward path.
	var b2 := _layout(16, 12, 2, [
		{"rect": foot, "kind": DungeonRoomData.KIND_CIRCULATION},
		{"rect": Rect2i(0, 1, 3, 3), "kind": DungeonRoomData.KIND_CHAMBER,
			"doors": [{"pos": Vector2i(3, 2), "type": DungeonDoorData.TYPE_LOCKED,
				"material": DungeonDoorData.MATERIAL_STONE}]},
	])
	var res := DungeonVolumeComposer.compose(plan, [b1, b2], 700, "downgrade")
	check(res.ok, "downgrade fixture composes: %s" % res.error)
	var bw := _band_walk(plan)
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	var placement: Dictionary = DungeonKeyLeverPlacer.place_composed(
		res.volume, res.zones, res.stairwells, res.rooms, res.doors, bw, res.volume.entry_pos, rng)
	check(placement["solved"], "sole-path gate downgraded → dungeon solves")
	check((placement["keys"] as Array).is_empty(),
		"no key placed (the gate was downgraded, not keyed)")
	var downgraded := false
	for rec in res.doors:
		if rec["cell"] == Vector3i(3, 2, -2):
			downgraded = rec["type"] == DungeonDoorData.TYPE_UNLOCKED \
				and not rec["is_secret"] \
				and rec["material"] == DungeonDoorData.MATERIAL_WOOD_STANDARD
	check(downgraded, "the sole-path locked-stone gate was downgraded to unlocked wood")


## A reservation-free band-2 chamber with NO connecting door is structurally
## disconnected: the placer must NOT geometric-repair — it returns solved=false
## (rule 3), handing off to the whole-dungeon re-seed ladder.
func test_placer_rule3_disconnected_hard_fail() -> void:
	var d := _make_two_band({}, false, 500)  # band-2 chamber walled off (no door)
	var res: DungeonVolumeComposer.ComposeResult = d["res"]
	check(res.ok, "disconnected dungeon still composes (geometry is legal)")
	var bw := _band_walk(d["plan"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var placement: Dictionary = DungeonKeyLeverPlacer.place_composed(
		res.volume, res.zones, res.stairwells, res.rooms, res.doors, bw, res.volume.entry_pos, rng)
	check(not placement["solved"], "structural disconnection is a rule-3 hard fail (no key repair)")
	check((placement["keys"] as Array).is_empty(), "no keys placed for a structural defect")


## A single key that gates a large majority of the stockable zones triggers a
## [GATE] blast-radius warning. The stone door gates band-2's chamber (1 of 2
## stockable chambers = 50% > 40%).
func test_gate_blast_radius_warning() -> void:
	var d := _make_two_band({"type": DungeonDoorData.TYPE_LOCKED, "material": DungeonDoorData.MATERIAL_STONE}, true, 600)
	var res: DungeonVolumeComposer.ComposeResult = d["res"]
	var bw := _band_walk(d["plan"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var placement: Dictionary = DungeonKeyLeverPlacer.place_composed(
		res.volume, res.zones, res.stairwells, res.rooms, res.doors, bw, res.volume.entry_pos, rng)
	var solv: Dictionary = DungeonNavigabilityValidator.validate_composed_solvability(
		res.volume, res.zones, res.stairwells, res.doors, placement["keys"], bw, res.volume.entry_pos,
		placement["wired_levers"], 0.40)
	check((solv["gate_warnings"] as Array).size() >= 1, "a key gating >40%% of stockable zones emits [GATE]")
