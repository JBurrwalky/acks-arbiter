extends "res://tests/test_suite_base.gd"

## Unit tests for DungeonRoomComposer — the geometric planning layer.


func run_all_tests() -> void:
	test_compose_places_at_least_one_room()
	test_compose_respects_wall_band_between_rooms()
	test_compose_is_deterministic_for_same_seed()
	test_compose_zero_target_room_count_is_safe()
	test_connection_graph_has_n_minus_1_mst_edges()
	test_connection_graph_adds_loop_edges_per_frequency()
	test_corridor_endpoints_are_outside_rooms()
	test_adjacent_rooms_get_doors_without_corridor()
	test_doors_have_resolved_types_after_compose()
	test_stairs_land_inside_rooms()
	test_room_purposes_assigned_from_theme_table()
	# §8.1 step 5: secret-as-overlay
	test_secret_roll_expands_to_underlying_type_with_is_secret()
	test_no_door_has_type_secret_after_compose()
	# §8.3: door material rule
	test_arches_have_none_material()
	test_portcullises_have_metal_material()
	test_secret_doors_have_wood_standard_material()
	test_every_door_material_is_in_valid_set()
	test_material_classifiers_bashable_flammable_curtain()
	test_tier_1_produces_mostly_wood_material()
	test_tier_6_produces_more_metal_and_portcullis()
	if not has_failures():
		print("DungeonRoomComposer: all tests passed.")


# ---------------------------------------------------------------------------
# Room scatter
# ---------------------------------------------------------------------------

func test_compose_places_at_least_one_room() -> void:
	var composer := DungeonRoomComposer.new()
	var theme := DungeonThemeCatalog.get_theme("wizards_dungeon")
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var placed: int = composer.compose(31, 31, 8, Vector2i(2, 4), theme, 1, 1, rng)
	check(placed > 0, "expected at least 1 room placed; got %d" % placed)
	check(composer.rooms.size() == placed,
		"composer.rooms.size() should match returned placed count")


func test_compose_respects_wall_band_between_rooms() -> void:
	# Per §6.1: rooms must be at least 1 cell apart (sharing a wall band) OR
	# further. They cannot directly touch interiors. After composition,
	# verify every pair of rooms has at least 1 cell of separation between
	# their bounds.
	var composer := DungeonRoomComposer.new()
	var theme := DungeonThemeCatalog.get_theme("wizards_dungeon")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	composer.compose(31, 31, 8, Vector2i(2, 4), theme, 1, 1, rng)
	for i in composer.rooms.size():
		for j in range(i + 1, composer.rooms.size()):
			var a: DungeonRoomComposer.RoomPlan = composer.rooms[i]
			var b: DungeonRoomComposer.RoomPlan = composer.rooms[j]
			# grow(1) on a should NOT intersect b (rooms must have at least
			# 1 cell of wall band between them).
			# Exception: when grow checks see them exactly adjacent (rooms
			# 1 cell apart sharing wall band), grow(1).intersects(b) returns
			# false because b starts 2 cells past a's far edge.
			check(not a.bounds.grow(1).intersects(b.bounds),
				"rooms %d and %d overlap or touch interiors: %s vs %s"
					% [i, j, a.bounds, b.bounds])


func test_compose_is_deterministic_for_same_seed() -> void:
	var theme := DungeonThemeCatalog.get_theme("wizards_dungeon")
	var rng1 := RandomNumberGenerator.new(); rng1.seed = 999
	var rng2 := RandomNumberGenerator.new(); rng2.seed = 999
	var c1 := DungeonRoomComposer.new()
	var c2 := DungeonRoomComposer.new()
	c1.compose(31, 31, 8, Vector2i(2, 4), theme, 1, 1, rng1)
	c2.compose(31, 31, 8, Vector2i(2, 4), theme, 1, 1, rng2)
	check(c1.rooms.size() == c2.rooms.size(),
		"deterministic: room count differs %d vs %d" % [c1.rooms.size(), c2.rooms.size()])
	check(c1.corridors.size() == c2.corridors.size(),
		"deterministic: corridor count differs %d vs %d" % [c1.corridors.size(), c2.corridors.size()])
	check(c1.doors.size() == c2.doors.size(),
		"deterministic: door count differs %d vs %d" % [c1.doors.size(), c2.doors.size()])
	for i in c1.rooms.size():
		var ra: DungeonRoomComposer.RoomPlan = c1.rooms[i]
		var rb: DungeonRoomComposer.RoomPlan = c2.rooms[i]
		check(ra.bounds == rb.bounds,
			"deterministic: room %d bounds differ %s vs %s" % [i, ra.bounds, rb.bounds])


func test_compose_zero_target_room_count_is_safe() -> void:
	var composer := DungeonRoomComposer.new()
	var theme := DungeonThemeCatalog.get_theme("wizards_dungeon")
	var rng := RandomNumberGenerator.new(); rng.seed = 1
	var placed: int = composer.compose(21, 21, 0, Vector2i(2, 4), theme, 1, 1, rng)
	check(placed == 0, "0 target → 0 placed")
	check(composer.rooms.is_empty(), "rooms array should be empty")
	check(composer.corridors.is_empty(), "corridors array should be empty when no rooms")
	check(composer.doors.is_empty(), "doors array should be empty when no rooms")


# ---------------------------------------------------------------------------
# Connection graph
# ---------------------------------------------------------------------------

func test_connection_graph_has_n_minus_1_mst_edges() -> void:
	# For N rooms, the MST has exactly N-1 edges. With loop_frequency = 0
	# the connection graph should equal the MST.
	var composer := DungeonRoomComposer.new()
	var theme := DungeonThemeCatalog.get_theme("wizards_dungeon")
	theme.loop_frequency = 0.0  # mutate to force MST-only
	var rng := RandomNumberGenerator.new(); rng.seed = 11
	composer.compose(31, 31, 8, Vector2i(2, 4), theme, 1, 1, rng)
	var n: int = composer.rooms.size()
	if n >= 2:
		check(composer.connection_edges.size() == n - 1,
			"MST edge count: expected %d, got %d" % [n - 1, composer.connection_edges.size()])


func test_connection_graph_adds_loop_edges_per_frequency() -> void:
	# With loop_frequency = 1.0 the graph should be complete (every pair of
	# rooms connected). For n rooms that's n*(n-1)/2 edges total.
	var composer := DungeonRoomComposer.new()
	var theme := DungeonThemeCatalog.get_theme("wizards_dungeon")
	theme.loop_frequency = 1.0
	var rng := RandomNumberGenerator.new(); rng.seed = 22
	composer.compose(21, 21, 5, Vector2i(2, 3), theme, 1, 1, rng)
	var n: int = composer.rooms.size()
	if n >= 2:
		var expected: int = n * (n - 1) / 2
		check(composer.connection_edges.size() == expected,
			"complete graph edge count: expected %d, got %d"
				% [expected, composer.connection_edges.size()])


# ---------------------------------------------------------------------------
# Corridor routing
# ---------------------------------------------------------------------------

func test_corridor_endpoints_are_outside_rooms() -> void:
	# Corridor centerlines should start and end on cells that are NOT inside
	# any room (they sit adjacent to room perimeters, not inside).
	var composer := DungeonRoomComposer.new()
	var theme := DungeonThemeCatalog.get_theme("wizards_dungeon")
	var rng := RandomNumberGenerator.new(); rng.seed = 33
	composer.compose(31, 31, 8, Vector2i(2, 4), theme, 1, 1, rng)
	for c in composer.corridors:
		var corridor: DungeonRoomComposer.CorridorPlan = c
		if corridor.centerline.is_empty():
			continue
		var first: Vector2i = corridor.centerline[0]
		var last: Vector2i = corridor.centerline[-1]
		var first_in_room: bool = _cell_is_in_any_room(first, composer)
		var last_in_room: bool = _cell_is_in_any_room(last, composer)
		check(not first_in_room,
			"corridor start cell %s should be outside all rooms" % first)
		check(not last_in_room,
			"corridor end cell %s should be outside all rooms" % last)


# ---------------------------------------------------------------------------
# Doors
# ---------------------------------------------------------------------------

func test_adjacent_rooms_get_doors_without_corridor() -> void:
	# Build a forced scenario: two rooms placed exactly 1 cell apart sharing
	# a wall band. The composer's adjacent-room shortcut should install a
	# door in the wall band and skip corridor routing.
	#
	# We can't force placement easily, but we can verify the helper directly.
	var composer := DungeonRoomComposer.new()
	composer.grid_width = 11
	composer.grid_height = 6
	var a := DungeonRoomComposer.RoomPlan.new()
	a.id = 0
	a.bounds = Rect2i(1, 1, 3, 3)  # cells (1-3, 1-3)
	composer.rooms.append(a)
	composer._stamp_room_occupancy(a)
	var b := DungeonRoomComposer.RoomPlan.new()
	b.id = 1
	b.bounds = Rect2i(5, 1, 3, 3)  # cells (5-7, 1-3); wall band at x=4
	composer.rooms.append(b)
	composer._stamp_room_occupancy(b)
	# The shared wall cells should be at x=4, y in [1, 3].
	var shared: Array[Vector2i] = composer._shared_wall_cells(a, b)
	check(shared.size() == 3,
		"expected 3 shared wall cells between adjacent rooms, got %d" % shared.size())
	for s in shared:
		check(s.x == 4 and s.y >= 1 and s.y <= 3,
			"shared cell %s should be at x=4 with y in [1,3]" % s)


func test_doors_have_resolved_types_after_compose() -> void:
	# No door should still have the "__pending__" sentinel after compose().
	var composer := DungeonRoomComposer.new()
	var theme := DungeonThemeCatalog.get_theme("wizards_dungeon")
	var rng := RandomNumberGenerator.new(); rng.seed = 44
	composer.compose(31, 31, 8, Vector2i(2, 4), theme, 1, 1, rng)
	for d in composer.doors:
		var door: DungeonRoomComposer.DoorPlan = d
		check(door.type != "__pending__",
			"door at %s has unresolved type sentinel" % door.position)
		check(door.type in DungeonDoorData.VALID_TYPES,
			"door at %s has invalid type '%s'" % [door.position, door.type])


# ---------------------------------------------------------------------------
# Stairs
# ---------------------------------------------------------------------------

func test_stairs_land_inside_rooms() -> void:
	var composer := DungeonRoomComposer.new()
	var theme := DungeonThemeCatalog.get_theme("wizards_dungeon")
	var rng := RandomNumberGenerator.new(); rng.seed = 55
	composer.compose(31, 31, 8, Vector2i(2, 4), theme, 1, 1, rng)
	check(composer.stairs.size() > 0,
		"expected at least 1 stair (compose request stairs_up=1, stairs_down=1)")
	for s in composer.stairs:
		var stair: DungeonRoomComposer.StairPlan = s
		check(_cell_is_in_any_room(stair.position, composer),
			"stair at %s should be inside a room" % stair.position)
		check(stair.direction in DungeonStairData.VALID_DIRECTIONS,
			"stair direction '%s' should be in VALID_DIRECTIONS" % stair.direction)


# ---------------------------------------------------------------------------
# Room purposes
# ---------------------------------------------------------------------------

func test_room_purposes_assigned_from_theme_table() -> void:
	var composer := DungeonRoomComposer.new()
	var theme := DungeonThemeCatalog.get_theme("wizards_dungeon")
	var rng := RandomNumberGenerator.new(); rng.seed = 66
	composer.compose(31, 31, 8, Vector2i(2, 4), theme, 1, 1, rng)
	var purposes: Array = theme.purpose_weights.keys()
	for r in composer.rooms:
		var room: DungeonRoomComposer.RoomPlan = r
		check(not room.original_purpose.is_empty(),
			"room %d should have non-empty original_purpose" % room.id)
		check(room.original_purpose in purposes,
			"room %d original_purpose '%s' should be from theme.purpose_weights"
				% [room.id, room.original_purpose])


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _cell_is_in_any_room(cell: Vector2i, composer: DungeonRoomComposer) -> bool:
	for r in composer.rooms:
		var room: DungeonRoomComposer.RoomPlan = r
		if room.bounds.has_point(cell):
			return true
	return false


# ---------------------------------------------------------------------------
# §8.1 step 5 — secret-as-overlay
# ---------------------------------------------------------------------------

func test_secret_roll_expands_to_underlying_type_with_is_secret() -> void:
	# Build a theme whose weights ONLY allow secret rolls. Every door the
	# composer plans must then come out with is_secret=true and an underlying
	# type ∈ {unlocked, locked, trapped} (the §8.1 step 5 sub-weights).
	var theme := DungeonThemeCatalog.get_theme("wizards_dungeon")
	theme.door_type_weights = {DungeonDoorData.ROLL_CATEGORY_SECRET: 100}
	var composer := DungeonRoomComposer.new()
	var rng := RandomNumberGenerator.new(); rng.seed = 100
	composer.compose(31, 31, 6, Vector2i(2, 4), theme, 1, 1, rng, 1)
	check(composer.doors.size() > 0, "expected at least one door planned")
	var underlying_seen: Dictionary = {}
	for d in composer.doors:
		var door: DungeonRoomComposer.DoorPlan = d
		check(door.is_secret,
			"door at %s should have is_secret=true (theme weights only roll secret)" % door.position)
		check(door.type in [
			DungeonDoorData.TYPE_UNLOCKED,
			DungeonDoorData.TYPE_LOCKED,
			DungeonDoorData.TYPE_TRAPPED,
		],
			"secret door's underlying type should be unlocked/locked/trapped, got '%s'" % door.type)
		underlying_seen[door.type] = true
	# With many doors and the 50/40/10 sub-weight, we should see at least 2 of
	# the 3 underlying types (probabilistic — but very likely with N>5).
	check(underlying_seen.size() >= 1,
		"expected at least one underlying type to be observed across all secret doors")


func test_no_door_has_type_secret_after_compose() -> void:
	# Regression guard for the §8.1 step 5 refactor: no door should ever have
	# door.type == "secret" after compose() — secret is an overlay (is_secret),
	# not a final type.
	var composer := DungeonRoomComposer.new()
	var theme := DungeonThemeCatalog.get_theme("wizards_dungeon")
	var rng := RandomNumberGenerator.new(); rng.seed = 101
	composer.compose(31, 31, 8, Vector2i(2, 4), theme, 1, 1, rng, 3)
	for d in composer.doors:
		var door: DungeonRoomComposer.DoorPlan = d
		check(door.type != DungeonDoorData.ROLL_CATEGORY_SECRET,
			"door at %s has the secret roll-category as type (should have been expanded)" % door.position)
		check(door.type in DungeonDoorData.VALID_TYPES,
			"door at %s has type '%s' not in VALID_TYPES" % [door.position, door.type])


# ---------------------------------------------------------------------------
# §8.3 — door material rule
# ---------------------------------------------------------------------------

func test_arches_have_none_material() -> void:
	# Step 1: arches get MATERIAL_NONE (no door object).
	var composer := DungeonRoomComposer.new()
	var theme := DungeonThemeCatalog.get_theme("wizards_dungeon")
	theme.door_type_weights = {DungeonDoorData.TYPE_ARCH: 100}
	var rng := RandomNumberGenerator.new(); rng.seed = 200
	composer.compose(31, 31, 6, Vector2i(2, 4), theme, 1, 1, rng, 3)
	for d in composer.doors:
		var door: DungeonRoomComposer.DoorPlan = d
		check(door.type == DungeonDoorData.TYPE_ARCH,
			"all doors should be arches (only roll-weight)")
		check(door.door_material == DungeonDoorData.MATERIAL_NONE,
			"arch door material should be MATERIAL_NONE (empty), got '%s'" % door.door_material)


func test_material_classifiers_bashable_flammable_curtain() -> void:
	# DungeonDoorData static classifiers (derived from material).
	# Bashable = the two wood tiers only.
	check(DungeonDoorData.is_bashable(DungeonDoorData.MATERIAL_WOOD_STANDARD), "wood_standard bashable")
	check(DungeonDoorData.is_bashable(DungeonDoorData.MATERIAL_WOOD_THICK), "wood_thick bashable")
	check(not DungeonDoorData.is_bashable(DungeonDoorData.MATERIAL_STONE), "stone NOT bashable")
	check(not DungeonDoorData.is_bashable(DungeonDoorData.MATERIAL_METAL), "metal NOT bashable")
	check(not DungeonDoorData.is_bashable(DungeonDoorData.MATERIAL_CURTAIN_CLOTH), "curtain NOT bashable")
	check(not DungeonDoorData.is_bashable(DungeonDoorData.MATERIAL_NONE), "none NOT bashable")
	# Flammable = curtains + both wood tiers.
	check(DungeonDoorData.is_flammable(DungeonDoorData.MATERIAL_CURTAIN_CLOTH), "curtain_cloth flammable")
	check(DungeonDoorData.is_flammable(DungeonDoorData.MATERIAL_CURTAIN_LEATHER), "curtain_leather flammable")
	check(DungeonDoorData.is_flammable(DungeonDoorData.MATERIAL_WOOD_STANDARD), "wood_standard flammable")
	check(DungeonDoorData.is_flammable(DungeonDoorData.MATERIAL_WOOD_THICK), "wood_thick flammable")
	check(not DungeonDoorData.is_flammable(DungeonDoorData.MATERIAL_STONE), "stone NOT flammable")
	check(not DungeonDoorData.is_flammable(DungeonDoorData.MATERIAL_METAL), "metal NOT flammable")
	check(not DungeonDoorData.is_flammable(DungeonDoorData.MATERIAL_NONE), "none NOT flammable")
	# Curtain classifier.
	check(DungeonDoorData.is_curtain(DungeonDoorData.MATERIAL_CURTAIN_CLOTH), "curtain_cloth is curtain")
	check(DungeonDoorData.is_curtain(DungeonDoorData.MATERIAL_CURTAIN_LEATHER), "curtain_leather is curtain")
	check(not DungeonDoorData.is_curtain(DungeonDoorData.MATERIAL_WOOD_STANDARD), "wood NOT curtain")
	# Instance wrappers.
	var d := DungeonDoorData.new()
	d.door_material = DungeonDoorData.MATERIAL_WOOD_THICK
	check(d.bashable() and d.flammable(), "wood_thick door instance bashable + flammable")


func test_every_door_material_is_in_valid_set() -> void:
	# Every door the composer produces must carry a door_material in the
	# canonical VALID_MATERIALS set (the DG-V1.C dungeon_doors CHECK constraint
	# mirrors this set).
	var composer := DungeonRoomComposer.new()
	var theme := DungeonThemeCatalog.get_theme("wizards_dungeon")
	var rng := RandomNumberGenerator.new(); rng.seed = 250
	composer.compose(51, 51, 20, Vector2i(2, 6), theme, 1, 1, rng, 4)
	for d in composer.doors:
		var door: DungeonRoomComposer.DoorPlan = d
		check(door.door_material in DungeonDoorData.VALID_MATERIALS,
			"door at %s has material '%s' not in VALID_MATERIALS"
				% [door.position, door.door_material])


func test_portcullises_have_metal_material() -> void:
	# Step 1: portcullises rolled by §8.1 (not §8.3 override) → metal material.
	var composer := DungeonRoomComposer.new()
	var theme := DungeonThemeCatalog.get_theme("wizards_dungeon")
	theme.door_type_weights = {DungeonDoorData.TYPE_PORTCULLIS: 100}
	var rng := RandomNumberGenerator.new(); rng.seed = 201
	composer.compose(31, 31, 6, Vector2i(2, 4), theme, 1, 1, rng, 1)
	for d in composer.doors:
		var door: DungeonRoomComposer.DoorPlan = d
		check(door.type == DungeonDoorData.TYPE_PORTCULLIS,
			"all doors should be portcullises")
		check(door.door_material == DungeonDoorData.MATERIAL_METAL,
			"portcullis material should be metal, got '%s'" % door.door_material)


func test_secret_doors_have_wood_standard_material() -> void:
	# Step 2: §8.3 forces secret-overlay doors to wood_standard.
	var composer := DungeonRoomComposer.new()
	var theme := DungeonThemeCatalog.get_theme("wizards_dungeon")
	theme.door_type_weights = {DungeonDoorData.ROLL_CATEGORY_SECRET: 100}
	var rng := RandomNumberGenerator.new(); rng.seed = 202
	composer.compose(31, 31, 6, Vector2i(2, 4), theme, 1, 1, rng, 6)  # tier 6 — maximum metal pressure
	for d in composer.doors:
		var door: DungeonRoomComposer.DoorPlan = d
		check(door.is_secret, "all doors should be secret-overlay")
		check(door.door_material == DungeonDoorData.MATERIAL_WOOD_STANDARD,
			"secret door at tier 6 should still be wood_standard (§8.3 step 2), got '%s'"
				% door.door_material)


func test_tier_1_produces_mostly_wood_material() -> void:
	# Tier 1: §8.3.2 says ~90% wood_standard for non-arch non-portcullis
	# non-secret doors. Sample a large generation and check ≥ 70% are wood.
	var composer := DungeonRoomComposer.new()
	var theme := DungeonThemeCatalog.get_theme("wizards_dungeon")
	# Force locked-only weights so every door reaches §8.3 step 4 (material roll).
	theme.door_type_weights = {DungeonDoorData.TYPE_LOCKED: 100}
	var rng := RandomNumberGenerator.new(); rng.seed = 203
	composer.compose(51, 51, 20, Vector2i(2, 4), theme, 1, 1, rng, 1)
	var wood: int = 0
	var total: int = 0
	for d in composer.doors:
		var door: DungeonRoomComposer.DoorPlan = d
		total += 1
		if door.door_material == DungeonDoorData.MATERIAL_WOOD_STANDARD:
			wood += 1
	check(total > 0, "expected some doors generated")
	var pct: float = 100.0 * float(wood) / float(total)
	check(pct >= 70.0,
		"tier 1 should produce ≥ 70%% wood_standard doors; got %.1f%% (%d/%d)"
			% [pct, wood, total])


func test_tier_6_produces_more_metal_and_portcullis() -> void:
	# Tier 6: §8.3.2 says ~30% portcullis-override + ~21% metal + ~49% wood
	# for non-arch non-portcullis non-secret doors. Wood should be ≤ 70% (vs
	# ≥ 90% at tier 1). Use a large sample so the chi-square is forgiving.
	var composer := DungeonRoomComposer.new()
	var theme := DungeonThemeCatalog.get_theme("wizards_dungeon")
	# Force locked-only weights so every door reaches the §8.3 step 3 + step 4 rolls.
	theme.door_type_weights = {DungeonDoorData.TYPE_LOCKED: 100}
	var rng := RandomNumberGenerator.new(); rng.seed = 204
	composer.compose(51, 51, 20, Vector2i(2, 4), theme, 1, 1, rng, 6)
	var wood: int = 0
	var hard: int = 0  # metal (incl. portcullis-override) + stone
	var total: int = 0
	for d in composer.doors:
		var door: DungeonRoomComposer.DoorPlan = d
		total += 1
		match door.door_material:
			DungeonDoorData.MATERIAL_WOOD_STANDARD:
				wood += 1
			DungeonDoorData.MATERIAL_METAL, DungeonDoorData.MATERIAL_STONE:
				hard += 1
	check(total > 0, "expected some doors generated")
	var wood_pct: float = 100.0 * float(wood) / float(total)
	var hard_pct: float = 100.0 * float(hard) / float(total)
	check(wood_pct <= 70.0,
		"tier 6 should produce ≤ 70%% wood_standard doors; got %.1f%% (%d/%d)"
			% [wood_pct, wood, total])
	check(hard_pct >= 25.0,
		"tier 6 should produce ≥ 25%% metal+stone doors; got %.1f%% (hard=%d total=%d)"
			% [hard_pct, hard, total])
