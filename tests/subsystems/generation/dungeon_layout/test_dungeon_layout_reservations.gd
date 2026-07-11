extends "res://tests/test_suite_base.gd"

## DG-C3D.C unit tests — per-band layout with vertical-plan reservations.
##
## Covers the build-plan C requirements:
##   1. ZERO-DIFF GATE: no-reservation requests produce byte-identical output
##      to the pre-C generator (golden fingerprints captured at commit 62691f0
##      before any C edit) — the RNG stream-identity guarantee.
##   2. Reserved rooms survive scatter untouched (exact bounds, no overlap).
##   3. Reserved circulation / atrium-base rooms are BFS-connected to the
##      network in every seed of a sweep (MST-by-construction + safety net).
##   4. Atrium-upper blocked regions receive no room floor and no corridors;
##      they are absent from the DungeonRoomData output; doors into the ring
##      stub are permitted (>= 0).
##   5. Sole-connector secret exclusion (contiguous GDD §10.3 proactive half):
##      doors on sole-connector circulation rooms never carry the secret
##      overlay, with the rng draw sequence unchanged.
##   6. Theme vertical fields (DG-C3D.C): wizards row parity with the
##      VerticalPlan defaults; dungeon_type_id guards the universal fallback.
##
## Legacy anchor coverage is unchanged and stays in
## test_dungeon_room_composer.gd / test_dungeon_layout_generator.gd.


func run_all_tests() -> void:
	test_zero_diff_golden_fingerprints()
	test_reserved_rooms_survive_scatter_exact()
	test_reserved_rooms_connected_sweep()
	test_blocked_region_untouched()
	test_sole_connector_secret_exclusion()
	test_theme_vertical_fields()
	test_corridor_never_clips_blocked_interior()
	test_force_carve_skips_blocked_region_target()
	test_free_stair_never_in_blocked_region_fallback()
	if not has_failures():
		print("DungeonLayoutReservations: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_request(size: String, seed_value: int, reserved: Array = []) -> DungeonLayoutRequest:
	var request := DungeonLayoutRequest.new()
	request.dungeon_size = size
	request.dungeon_type = "wizards_dungeon"
	request.level_number = 1
	request.seed = seed_value
	request.floor_tier = 3
	request.stairs_up = 1
	request.stairs_down = 1
	request.is_entrance_floor = true
	request.reserved_rooms = reserved
	return request


func _entry(rect: Rect2i, kind: String, sole: bool = false) -> Dictionary:
	return {"rect": rect, "kind": kind, "ref": null, "is_sole_connector": sole}


## Standard reservation set for a 51x51 medium band: one sole circulation
## room, one atrium base, one atrium-upper blocked region (disjoint rects,
## 1-cell wall band honored).
func _standard_reservations() -> Array:
	return [
		_entry(Rect2i(6, 6, 3, 3), "circulation", true),
		_entry(Rect2i(30, 30, 7, 7), "atrium_base"),
		_entry(Rect2i(14, 34, 7, 7), "atrium_upper"),
	]


func _fingerprint(layout: DungeonLayout) -> String:
	var parts: Array[String] = []
	for x in layout.grid_width:
		for y in layout.grid_height:
			var c: DungeonCellData = layout.cells[x][y]
			parts.append("%s%d%d%s%d" % [
				c.terrain_feature, int(c.passable), c.room_id, c.door_state,
				int(c.is_corridor)])
	for r in layout.rooms:
		parts.append("R%d:%s:%s" % [r.id, str(r.bounds), r.original_purpose])
	for d in layout.doors:
		parts.append("D%s:%s:%d:%s:%s" % [
			str(d.position), d.type, int(d.is_secret), d.door_material, str(d.connects)])
	for s in layout.stairs:
		parts.append("S%s:%s:%d" % [str(s.position), s.direction, int(s.is_entrance_stair)])
	return "|".join(parts).md5_text()


## BFS over passable-or-door cells from the first stair; returns the visited set.
func _bfs_visited(layout: DungeonLayout) -> Dictionary:
	var visited: Dictionary = {}
	if layout.stairs.is_empty():
		return visited
	var start: Vector2i = (layout.stairs[0] as DungeonStairData).position
	visited[start] = true
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		for dir in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
			var n: Vector2i = cur + dir
			if visited.has(n):
				continue
			if n.x < 0 or n.y < 0 or n.x >= layout.grid_width or n.y >= layout.grid_height:
				continue
			var cd: DungeonCellData = layout.cells[n.x][n.y]
			if cd == null or (not cd.passable and not cd.is_door()):
				continue
			visited[n] = true
			queue.append(n)
	return visited


func _room_with_bounds(layout: DungeonLayout, rect: Rect2i) -> DungeonRoomData:
	for r in layout.rooms:
		if r.bounds == rect:
			return r
	return null


# ---------------------------------------------------------------------------
# 1. Zero-diff gate (RNG stream identity for no-reservation requests)
# ---------------------------------------------------------------------------

const _GOLDEN_FINGERPRINTS := {
	# Captured from the pre-C generator (commit 62691f0) via
	# tools/tmp_layout_golden.gd — wizards_dungeon, tier 3, stairs 1/1,
	# entrance floor. ANY mismatch means the C rework changed the output or
	# rng draw sequence of the reservation-free path — a hard regression
	# against the DG-C3D.F single-band byte-identity gate.
	"lair:11": "eb3a6ae3fe56017329a521c9692ba7e9",
	"small:22": "6f49aafba6d27b6b7f2a2fe05b02bc07",
	"medium:33": "6e8d7963bb2fa52be3544207ebb132a3",
	"large:44": "7da15b70d499801940767f45dc224814",
	"medium:55": "7f1ea7e173df7128fa95bdcd3c805b7d",
	"large:66": "2c1d4ad7d7af3fb038ab8d5e832b083d",
}


func test_zero_diff_golden_fingerprints() -> void:
	for key in _GOLDEN_FINGERPRINTS:
		var parts: PackedStringArray = str(key).split(":")
		var layout: DungeonLayout = DungeonLayoutGenerator.generate(
			_make_request(parts[0], int(parts[1])))
		check(layout != null, "golden %s: layout generates" % key)
		if layout == null:
			continue
		check(_fingerprint(layout) == str(_GOLDEN_FINGERPRINTS[key]),
			"golden %s: no-reservation output byte-identical to pre-C generator" % key)


# ---------------------------------------------------------------------------
# 2. Reserved rooms survive scatter
# ---------------------------------------------------------------------------

func test_reserved_rooms_survive_scatter_exact() -> void:
	var reserved := _standard_reservations()
	var layout: DungeonLayout = DungeonLayoutGenerator.generate(
		_make_request("medium", 777, reserved))
	check(layout != null, "reserved layout generates")
	if layout == null:
		return
	# Circulation + atrium base present at EXACT bounds; kind carried.
	var circ := _room_with_bounds(layout, Rect2i(6, 6, 3, 3))
	check(circ != null, "circulation room present at exact reserved bounds")
	if circ != null:
		check(circ.kind == DungeonRoomData.KIND_CIRCULATION, "circulation room carries kind")
	var base := _room_with_bounds(layout, Rect2i(30, 30, 7, 7))
	check(base != null, "atrium base room present at exact reserved bounds")
	if base != null:
		check(base.kind == DungeonRoomData.KIND_CHAMBER, "atrium base room is an ordinary chamber")
	# No scattered room overlaps any reservation (1-cell wall band enforced).
	for rect in [Rect2i(6, 6, 3, 3), Rect2i(30, 30, 7, 7), Rect2i(14, 34, 7, 7)]:
		for r in layout.rooms:
			if r.bounds == rect:
				continue
			check(not (rect as Rect2i).grow(1).intersects(r.bounds),
				"room %s keeps a wall band from reservation %s" % [str(r.bounds), str(rect)])


# ---------------------------------------------------------------------------
# 3. Connectivity sweep
# ---------------------------------------------------------------------------

func test_reserved_rooms_connected_sweep() -> void:
	for s in 12:
		var layout: DungeonLayout = DungeonLayoutGenerator.generate(
			_make_request("medium", 5000 + s, _standard_reservations()))
		check(layout != null, "sweep seed %d: layout generates" % s)
		if layout == null:
			continue
		var visited := _bfs_visited(layout)
		for rect in [Rect2i(6, 6, 3, 3), Rect2i(30, 30, 7, 7)]:
			var room := _room_with_bounds(layout, rect)
			check(room != null, "sweep seed %d: reserved room %s present" % [s, str(rect)])
			if room == null:
				continue
			var reached := false
			for c in room.cells:
				if visited.has(c):
					reached = true
					break
			check(reached, "sweep seed %d: reserved room %s BFS-reachable" % [s, str(rect)])


# ---------------------------------------------------------------------------
# 4. Blocked region
# ---------------------------------------------------------------------------

func test_blocked_region_untouched() -> void:
	var blocked := Rect2i(14, 34, 7, 7)
	for s in 6:
		var layout: DungeonLayout = DungeonLayoutGenerator.generate(
			_make_request("medium", 6000 + s, _standard_reservations()))
		check(layout != null, "blocked seed %d: layout generates" % s)
		if layout == null:
			continue
		# Not a room in the output.
		check(_room_with_bounds(layout, blocked) == null,
			"blocked seed %d: atrium-upper region is not a DungeonRoomData" % s)
		# Interior cells carry no room floor and no corridor.
		for x in range(blocked.position.x, blocked.end.x):
			for y in range(blocked.position.y, blocked.end.y):
				var cd: DungeonCellData = layout.cells[x][y]
				check(cd.room_id < 0 and not cd.is_corridor,
					"blocked seed %d: cell (%d,%d) has no room/corridor" % [s, x, y])


# ---------------------------------------------------------------------------
# 5. Sole-connector secret exclusion (§10.3)
# ---------------------------------------------------------------------------

func test_sole_connector_secret_exclusion() -> void:
	# Direct unit on _assign_door_type with a forced all-secret weight table:
	# a door touching a sole-connector circulation room must resolve WITHOUT
	# the secret overlay; an identical door elsewhere keeps it. Draw parity:
	# both paths consume exactly two draws (category + underlying sub-roll).
	var composer := DungeonRoomComposer.new()
	composer.grid_width = 21
	composer.grid_height = 21
	composer.rooms = []
	var ok: bool = composer._pre_place_reserved_rooms([
		_entry(Rect2i(2, 2, 3, 3), "circulation", true),   # id 0 — sole
		_entry(Rect2i(8, 8, 3, 3), "circulation", false),  # id 1 — not sole
	])
	check(ok, "pre-place for exclusion test succeeds")
	var forced := {DungeonDoorData.ROLL_CATEGORY_SECRET: 100}

	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var door_sole := DungeonRoomComposer.DoorPlan.new()
	door_sole.room_id_a = 0
	door_sole.room_id_b = -1
	var state_before: int = rng.state
	composer._assign_door_type(door_sole, forced, rng)
	var draws_state_sole: int = rng.state
	check(door_sole.is_secret == false,
		"door on sole-connector circulation room skips the secret overlay")
	check(door_sole.type in [DungeonDoorData.TYPE_UNLOCKED, DungeonDoorData.TYPE_LOCKED, DungeonDoorData.TYPE_TRAPPED],
		"suppressed door resolves to its plain underlying type (locked permitted)")

	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 42
	var door_plain := DungeonRoomComposer.DoorPlan.new()
	door_plain.room_id_a = 1
	door_plain.room_id_b = -1
	composer._assign_door_type(door_plain, forced, rng2)
	check(door_plain.is_secret == true,
		"door on a NON-sole circulation room keeps the secret overlay")
	check(door_plain.type == door_sole.type,
		"same seed resolves the same underlying type either way (draw parity)")
	check(rng2.state == draws_state_sole and rng2.state != state_before,
		"suppression consumes the identical rng draw sequence")


# ---------------------------------------------------------------------------
# 6. Theme vertical fields
# ---------------------------------------------------------------------------

func test_theme_vertical_fields() -> void:
	# Wizards row parity: theme fields equal the VerticalPlan defaults, so
	# the C rewire is behavior-neutral for wizard dungeons.
	var wizards: DungeonTheme = DungeonThemeCatalog.get_theme("wizards_dungeon")
	check(wizards.dungeon_type_id == "wizards_dungeon", "wizards theme carries its type id")
	check(wizards.connector_weights == VerticalPlan._DEFAULT_CONNECTOR_WEIGHTS,
		"wizards connector_weights match the VerticalPlan default row")
	check(wizards.multi_story_room_chance == int(VerticalPlan._ATRIUM_CHANCE_BY_TYPE["wizards_dungeon"]),
		"wizards multi_story_room_chance matches the VerticalPlan table")

	# Theme fields WIN when the id matches: an all-ramp wizards row forces
	# every connector to ramp.
	var custom := DungeonTheme.new()
	custom.dungeon_type_id = "wizards_dungeon"
	custom.connector_weights = {"straight": 0, "switchback": 0, "spiral": 0, "ramp": 100}
	custom.multi_story_room_chance = 0
	var request := DungeonGeneratorRequestV1.new()
	request.dungeon_size = "medium"
	request.floor_count = 3
	request.entrance_floor_index = 1
	request.dungeon_type = "wizards_dungeon"
	request.seed = 8080
	var plan := VerticalPlan.build(request, custom, VerticalPlan.derive_rng(8080))
	check(plan != null, "custom-theme plan builds")
	if plan != null:
		for c in plan.connectors:
			check(c.type == StairwellData.TYPE_RAMP, "theme connector_weights override the table when ids match")
		check(plan.atriums.is_empty(), "multi_story_room_chance 0 suppresses atriums")

	# The universal fallback CANNOT override another type's row: a tomb
	# request handed the wizards fallback theme still uses the tomb table
	# (no ramps — tomb row is 55/25/20/0).
	var tomb_request := DungeonGeneratorRequestV1.new()
	tomb_request.dungeon_size = "large"
	tomb_request.floor_count = 2
	tomb_request.entrance_floor_index = 1
	tomb_request.dungeon_type = "tomb"
	tomb_request.seed = 8181
	var tomb_plan := VerticalPlan.build(
		tomb_request, DungeonThemeCatalog.get_theme("tomb"), VerticalPlan.derive_rng(8181))
	check(tomb_plan != null, "tomb plan builds under the wizards fallback theme")
	if tomb_plan != null:
		for c in tomb_plan.connectors:
			check(c.type != StairwellData.TYPE_RAMP,
				"tomb keeps its own §8.3 row despite the wizards fallback theme")


# ---------------------------------------------------------------------------
# 7. Blocked-region impassability regressions (DG-C3D.C /code-review fixes)
# ---------------------------------------------------------------------------

## A fresh composer with only grid dims + scratch state set, for poking the
## private geometry helpers directly (mirrors the secret-exclusion unit).
func _bare_composer() -> DungeonRoomComposer:
	var composer := DungeonRoomComposer.new()
	composer.grid_width = 21
	composer.grid_height = 21
	composer.rooms = []
	composer.corridors = []
	composer.doors = []
	composer.stairs = []
	composer._occupancy = {}
	composer._corridor_cells = {}
	return composer


func test_corridor_never_clips_blocked_interior() -> void:
	# Regression: _path_crosses_blocked_region must flag a path through a
	# blocked region's INTERIOR even when the region is the corridor's own
	# endpoint (the pre-fix except-exemption let such a path clip the void and
	# get rasterized as corridor floor).
	var composer := _bare_composer()
	check(composer._pre_place_reserved_rooms([_entry(Rect2i(8, 8, 5, 5), "atrium_upper")]),
		"blocked region pre-placed")
	# Straight run through the interior (region spans cols 8..12 at row 10).
	var through: Array[Vector2i] = [
		Vector2i(6, 10), Vector2i(7, 10), Vector2i(8, 10), Vector2i(10, 10), Vector2i(11, 10)]
	check(composer._path_crosses_blocked_region(through) == true,
		"a centerline through the blocked interior is rejected (no endpoint exemption)")
	# A path that stops one cell short of the region (perimeter approach) is OK.
	var adjacent: Array[Vector2i] = [Vector2i(4, 10), Vector2i(5, 10), Vector2i(6, 10), Vector2i(7, 10)]
	check(composer._path_crosses_blocked_region(adjacent) == false,
		"a centerline adjacent to (not inside) the blocked region is allowed")


func test_force_carve_skips_blocked_region_target() -> void:
	# Regression: the §9.3.3 safety-net force-carve must not accept a blocked
	# region as a connection target — that produced a dead-end corridor+door
	# to the void, leaving the reserved room disconnected. When the ONLY
	# reachable neighbor is a blocked region, nothing is carved.
	var composer := _bare_composer()
	check(composer._pre_place_reserved_rooms([
		_entry(Rect2i(3, 9, 3, 3), "circulation", true),  # id 0 — the doorless room
		_entry(Rect2i(8, 9, 5, 5), "atrium_upper"),       # id 1 — blocked, due east
	]), "circulation + blocked region pre-placed")
	composer._force_carve_from_anchor(composer.rooms[0])
	check(composer.doors.is_empty() and composer.corridors.is_empty(),
		"force-carve creates nothing when the only reachable neighbor is the atrium void (no dead-end to the void)")


func test_free_stair_never_in_blocked_region_fallback() -> void:
	# Regression: when every room is anchor/reserved the stair fallback used to
	# add ALL rooms — including the blocked region — so a free stair could land
	# in the atrium void. It must never select a blocked region.
	var blocked := Rect2i(10, 10, 5, 5)
	for seed_v in 20:
		var composer := _bare_composer()
		check(composer._pre_place_reserved_rooms([
			_entry(Rect2i(3, 3, 3, 3), "circulation", true),  # id 0
			_entry(blocked, "atrium_upper"),                   # id 1 — blocked
		]), "reserved-only rooms pre-placed (seed %d)" % seed_v)
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_v
		composer._plan_stairs(1, 0, rng)
		for s in composer.stairs:
			check(not blocked.has_point((s as DungeonRoomComposer.StairPlan).position),
				"seed %d: free stair never lands inside the atrium void" % seed_v)
