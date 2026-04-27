extends "res://tests/test_suite_base.gd"

## Unit tests for MovementResolver 3D voxel methods.
##
## Tests BFS pathfinding across movement types (ground, flying, burrowing,
## climbing), stair connections, LOS delegation, and null-map fallbacks.
## All tests use hand-built VoxelMapData fixtures.


func run_all_tests() -> void:
	test_path_bfs_3d_flat_ground()
	test_path_bfs_3d_wall_blocked()
	test_path_bfs_3d_stairs_up()
	test_path_bfs_3d_no_stairs_blocked()
	test_path_bfs_3d_level_diff_2_blocked()
	test_path_bfs_3d_flying_free()
	test_path_bfs_3d_flying_blocked_by_solid()
	test_path_bfs_3d_burrow_through_solid()
	test_path_bfs_3d_climbing_wall()
	test_path_bfs_3d_ground_needs_support()
	test_has_los_3d_clear()
	test_has_los_3d_blocked()
	test_has_los_3d_null_map_returns_true()
	test_is_adjacent_3d()
	test_get_cells_reachable_3d_ground()
	test_closed_door_blocks_ground()
	test_closed_door_walkable_in_explore_mode()
	test_locked_door_blocks_explore_mode()
	test_stuck_door_blocks_explore_mode()
	test_open_door_walkable_strict()
	test_b2_pathfinding_walks_through_incapacitated()
	test_b2_pathfinding_blocked_by_active_combatant()
	test_b2_endpoint_blocked_by_incapacitated_body()
	test_b2_endpoint_allowed_when_only_self_present()
	test_b2_default_signature_ignores_occupancy()
	if not has_failures():
		print("MovementResolver3D: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_resolver() -> MovementResolver:
	return MovementResolver.new()


func _make_flat_room(width: int, height: int, level: int = 0) -> VoxelMapData:
	var map := VoxelMapData.new()
	for c in range(width):
		for r in range(height):
			var cell := VoxelCell.new()
			cell.solidity = "air"
			cell.feature = "open"
			cell.floor_type = "stone"
			map.set_cell(Vector3i(c, r, level), cell)
	return map


func _place_solid(map: VoxelMapData, pos: Vector3i) -> void:
	var cell := VoxelCell.new()
	cell.solidity = "solid"
	cell.feature = "rock"
	map.set_cell(pos, cell)


func _place_air_no_floor(map: VoxelMapData, pos: Vector3i) -> void:
	var cell := VoxelCell.new()
	cell.solidity = "air"
	cell.feature = "air_open"
	cell.floor_type = "none"
	map.set_cell(pos, cell)


# ---------------------------------------------------------------------------
# Ground movement tests
# ---------------------------------------------------------------------------

func test_path_bfs_3d_flat_ground() -> void:
	var map := _make_flat_room(5, 5)
	var mr := _make_resolver()
	mr.set_voxel_map(map)
	var path := mr.path_bfs_3d(Vector3i(0, 0, 0), Vector3i(4, 4, 0))
	check(not path.is_empty(), "ground path on flat room should be found")
	check(path[0] == Vector3i(0, 0, 0), "path should start at from_pos")
	check(path[path.size() - 1] == Vector3i(4, 4, 0), "path should end at to_pos")


func test_path_bfs_3d_wall_blocked() -> void:
	var map := _make_flat_room(5, 1)
	_place_solid(map, Vector3i(2, 0, 0))  # Wall in the middle
	var mr := _make_resolver()
	mr.set_voxel_map(map)
	var path := mr.path_bfs_3d(Vector3i(0, 0, 0), Vector3i(4, 0, 0))
	check(path.is_empty(), "path through solid wall should be blocked")


func test_path_bfs_3d_stairs_up() -> void:
	var map := _make_flat_room(3, 3, 0)
	# Add level 2 floor
	for c in range(3):
		for r in range(3):
			var cell := VoxelCell.new()
			cell.solidity = "air"
			cell.feature = "open"
			cell.floor_type = "stone"
			map.set_cell(Vector3i(c, r, 1), cell)
	# Place stairs: going up from (1,1,0) to (1,0,1) (north and up)
	var stair_from := VoxelCell.new()
	stair_from.solidity = "air"
	stair_from.feature = "stairs_up_N"
	stair_from.floor_type = "stone"
	map.set_cell(Vector3i(1, 1, 0), stair_from)

	var mr := _make_resolver()
	mr.set_voxel_map(map)
	var path := mr.path_bfs_3d(Vector3i(0, 0, 0), Vector3i(2, 2, 1))
	check(not path.is_empty(),
		"ground walker should find path via stairs across levels")


func test_path_bfs_3d_no_stairs_blocked() -> void:
	var map := _make_flat_room(3, 3, 0)
	# Add level 1 floor (no stairs connecting)
	for c in range(3):
		for r in range(3):
			var cell := VoxelCell.new()
			cell.solidity = "air"
			cell.feature = "open"
			cell.floor_type = "stone"
			map.set_cell(Vector3i(c, r, 1), cell)

	var mr := _make_resolver()
	mr.set_voxel_map(map)
	var path := mr.path_bfs_3d(Vector3i(0, 0, 0), Vector3i(0, 0, 1))
	check(path.is_empty(),
		"ground walker should not cross levels without stairs")


func test_path_bfs_3d_level_diff_2_blocked() -> void:
	var map := _make_flat_room(3, 3, 0)
	for c in range(3):
		for r in range(3):
			var cell := VoxelCell.new()
			cell.solidity = "air"
			cell.feature = "open"
			cell.floor_type = "stone"
			map.set_cell(Vector3i(c, r, 2), cell)

	var mr := _make_resolver()
	mr.set_voxel_map(map)
	var path := mr.path_bfs_3d(Vector3i(0, 0, 0), Vector3i(0, 0, 2))
	check(path.is_empty(),
		"ground walker should not cross 2 levels in one step")


# ---------------------------------------------------------------------------
# Flying movement tests
# ---------------------------------------------------------------------------

func test_path_bfs_3d_flying_free() -> void:
	var map := VoxelMapData.new()
	# Place air cells at two levels (no floor needed for flyers)
	for lvl in [0, 1, 2]:
		var cell := VoxelCell.new()
		cell.solidity = "air"
		cell.feature = "air_open"
		cell.floor_type = "none"
		map.set_cell(Vector3i(0, 0, lvl), cell)

	var mr := _make_resolver()
	mr.set_voxel_map(map)
	var path := mr.path_bfs_3d(Vector3i(0, 0, 0), Vector3i(0, 0, 2), "flying")
	check(not path.is_empty(), "flyer should move through air levels freely")


func test_path_bfs_3d_flying_blocked_by_solid() -> void:
	var map := VoxelMapData.new()
	_place_air_no_floor(map, Vector3i(0, 0, 0))
	_place_solid(map, Vector3i(0, 0, 1))  # Solid ceiling
	_place_air_no_floor(map, Vector3i(0, 0, 2))

	var mr := _make_resolver()
	mr.set_voxel_map(map)
	var path := mr.path_bfs_3d(Vector3i(0, 0, 0), Vector3i(0, 0, 2), "flying")
	check(path.is_empty(), "flyer should not pass through solid cell")


# ---------------------------------------------------------------------------
# Burrowing movement tests
# ---------------------------------------------------------------------------

func test_path_bfs_3d_burrow_through_solid() -> void:
	var map := VoxelMapData.new()
	for i in range(5):
		_place_solid(map, Vector3i(i, 0, 0))

	var mr := _make_resolver()
	mr.set_voxel_map(map)
	var path := mr.path_bfs_3d(Vector3i(0, 0, 0), Vector3i(4, 0, 0), "tunnel_burrow")
	check(not path.is_empty(), "burrower should path through solid cells")


# ---------------------------------------------------------------------------
# Climbing movement tests
# ---------------------------------------------------------------------------

func test_path_bfs_3d_climbing_wall() -> void:
	var map := VoxelMapData.new()
	# Wall at (0,0,0) and (0,0,1)
	_place_solid(map, Vector3i(0, 0, 0))
	_place_solid(map, Vector3i(0, 0, 1))
	# Air next to wall at (1,0,0) and (1,0,1) — climbable
	_place_air_no_floor(map, Vector3i(1, 0, 0))
	_place_air_no_floor(map, Vector3i(1, 0, 1))

	var mr := _make_resolver()
	mr.set_voxel_map(map)
	var path := mr.path_bfs_3d(Vector3i(1, 0, 0), Vector3i(1, 0, 1), "climbing")
	check(not path.is_empty(),
		"climber should path up air cells adjacent to solid wall")


# ---------------------------------------------------------------------------
# Support tests
# ---------------------------------------------------------------------------

func test_path_bfs_3d_ground_needs_support() -> void:
	var map := _make_flat_room(3, 1, 0)
	# Replace middle cell with unsupported air
	_place_air_no_floor(map, Vector3i(1, 0, 0))

	var mr := _make_resolver()
	mr.set_voxel_map(map)
	var path := mr.path_bfs_3d(Vector3i(0, 0, 0), Vector3i(2, 0, 0))
	check(path.is_empty(),
		"ground walker should not cross unsupported air cell")


# ---------------------------------------------------------------------------
# LOS tests
# ---------------------------------------------------------------------------

func test_has_los_3d_clear() -> void:
	var map := _make_flat_room(5, 1)
	var mr := _make_resolver()
	mr.set_voxel_map(map)
	check(mr.has_los_3d(Vector3i(0, 0, 0), Vector3i(4, 0, 0)),
		"LOS through open cells should be clear")


func test_has_los_3d_blocked() -> void:
	var map := _make_flat_room(5, 1)
	_place_solid(map, Vector3i(2, 0, 0))
	var mr := _make_resolver()
	mr.set_voxel_map(map)
	check(not mr.has_los_3d(Vector3i(0, 0, 0), Vector3i(4, 0, 0)),
		"LOS through solid wall should be blocked")


func test_has_los_3d_null_map_returns_true() -> void:
	var mr := _make_resolver()
	check(mr.has_los_3d(Vector3i(0, 0, 0), Vector3i(5, 5, 5)),
		"has_los_3d with null voxel map should return true (fallback)")


# ---------------------------------------------------------------------------
# Adjacency and distance
# ---------------------------------------------------------------------------

func test_is_adjacent_3d() -> void:
	var mr := _make_resolver()
	check(mr.is_adjacent_3d(Vector3i(0, 0, 0), Vector3i(1, 0, 0)),
		"same-level neighbor should be adjacent")
	check(mr.is_adjacent_3d(Vector3i(0, 0, 0), Vector3i(0, 0, 1)),
		"one level up should be adjacent")
	check(not mr.is_adjacent_3d(Vector3i(0, 0, 0), Vector3i(0, 0, 2)),
		"two levels apart should not be adjacent")


# ---------------------------------------------------------------------------
# Reachability
# ---------------------------------------------------------------------------

func test_get_cells_reachable_3d_ground() -> void:
	var map := _make_flat_room(3, 3)
	var mr := _make_resolver()
	mr.set_voxel_map(map)
	var reachable := mr.get_cells_reachable_3d(Vector3i(1, 1, 0), "ground", 1)
	# From center of 3x3, should reach all 9 cells (center + 8 neighbors)
	check(reachable.size() == 9,
		"should reach 9 cells (center + 8 neighbors) in 3x3 room, got %d" % reachable.size())


# ---------------------------------------------------------------------------
# Door blocking
# ---------------------------------------------------------------------------

func test_closed_door_blocks_ground() -> void:
	var map := _make_flat_room(3, 1)
	# Replace middle cell with closed door
	var door_cell := VoxelCell.new()
	door_cell.solidity = "air"
	door_cell.feature = "open"
	door_cell.floor_type = "stone"
	door_cell.door_state = "closed"
	door_cell.door_type = "unlocked"
	map.set_cell(Vector3i(1, 0, 0), door_cell)

	var mr := _make_resolver()
	mr.set_voxel_map(map)
	var path := mr.path_bfs_3d(Vector3i(0, 0, 0), Vector3i(2, 0, 0))
	check(path.is_empty(), "closed door should block ground walker (strict)")


func test_closed_door_walkable_in_explore_mode() -> void:
	# Same fixture as above but with explore-mode passability — the path must
	# now route through the closed unlocked door cell.
	var map := _make_flat_room(3, 1)
	var door_cell := VoxelCell.new()
	door_cell.solidity = "air"
	door_cell.feature = "open"
	door_cell.floor_type = "stone"
	door_cell.door_state = "closed"
	door_cell.door_type = "unlocked"
	map.set_cell(Vector3i(1, 0, 0), door_cell)

	var mr := _make_resolver()
	mr.set_voxel_map(map)
	var path := mr.path_bfs_3d(
		Vector3i(0, 0, 0), Vector3i(2, 0, 0), "ground", 50, -1, "explore")
	check(not path.is_empty(),
		"explore mode should route through closed unlocked door")
	check(Vector3i(1, 0, 0) in path,
		"explore-mode path must pass through the door cell")


func test_locked_door_blocks_explore_mode() -> void:
	var map := _make_flat_room(3, 1)
	var door_cell := VoxelCell.new()
	door_cell.solidity = "air"
	door_cell.feature = "open"
	door_cell.floor_type = "stone"
	door_cell.door_state = "locked"
	door_cell.door_type = "locked"
	map.set_cell(Vector3i(1, 0, 0), door_cell)

	var mr := _make_resolver()
	mr.set_voxel_map(map)
	var path := mr.path_bfs_3d(
		Vector3i(0, 0, 0), Vector3i(2, 0, 0), "ground", 50, -1, "explore")
	check(path.is_empty(),
		"locked door should block path even in explore mode")


func test_stuck_door_blocks_explore_mode() -> void:
	var map := _make_flat_room(3, 1)
	var door_cell := VoxelCell.new()
	door_cell.solidity = "air"
	door_cell.feature = "open"
	door_cell.floor_type = "stone"
	door_cell.door_state = "stuck"
	door_cell.door_type = "unlocked"
	map.set_cell(Vector3i(1, 0, 0), door_cell)

	var mr := _make_resolver()
	mr.set_voxel_map(map)
	var path := mr.path_bfs_3d(
		Vector3i(0, 0, 0), Vector3i(2, 0, 0), "ground", 50, -1, "explore")
	check(path.is_empty(),
		"stuck door should block path even in explore mode")


func test_open_door_walkable_strict() -> void:
	var map := _make_flat_room(3, 1)
	var door_cell := VoxelCell.new()
	door_cell.solidity = "air"
	door_cell.feature = "open"
	door_cell.floor_type = "stone"
	door_cell.door_state = "open"
	door_cell.door_type = "unlocked"
	map.set_cell(Vector3i(1, 0, 0), door_cell)

	var mr := _make_resolver()
	mr.set_voxel_map(map)
	var path := mr.path_bfs_3d(Vector3i(0, 0, 0), Vector3i(2, 0, 0))
	check(not path.is_empty(),
		"open door should be walkable in strict mode")


# ---------------------------------------------------------------------------
# B2 — Block actives, allow incapacitated pass-through
# ---------------------------------------------------------------------------

func _make_combatant(id: String, side: int, alive: bool = true) -> Combatant:
	var c := Combatant.new()
	c.id = id
	c.side = side
	c.is_character = false
	c._monster_hp_max = 10
	c._monster_hp_current = 10 if alive else 0
	if not alive:
		c.add_condition("dead")
	return c


func test_b2_pathfinding_walks_through_incapacitated() -> void:
	# Map: 5×1 corridor, with an incapacitated enemy at (2,0,0).
	# Mover at (0,0,0) wants to reach (4,0,0). The downed body at (2,0,0)
	# is a waypoint, not the goal — must be passable.
	var map := _make_flat_room(5, 1)
	var mover := _make_combatant("MOVER", Combatant.Side.PARTY)
	var corpse := _make_combatant("CORPSE", Combatant.Side.ENEMY, false)
	var roster := CombatRoster.new()
	roster.add_combatant(mover); roster.add_combatant(corpse)
	var mr := MovementResolver.new(roster)
	mr.set_voxel_map(map)
	map.set_entity_pos("MOVER", Vector3i(0, 0, 0))
	map.set_entity_pos("CORPSE", Vector3i(2, 0, 0))
	var path := mr.path_bfs_3d(
		Vector3i(0, 0, 0), Vector3i(4, 0, 0),
		"ground", 50, -1, "strict", "MOVER")
	check(not path.is_empty(),
		"path through an incapacitated body should succeed")
	# The path should actually traverse (2,0,0) — corridor leaves no detour.
	check(Vector3i(2, 0, 0) in path,
		"path must include the incapacitated occupant's cell")


func test_b2_pathfinding_blocked_by_active_combatant() -> void:
	# Same setup but the occupant is alive — pathfinding must reject the
	# corridor and return empty (no detour available in 5×1).
	var map := _make_flat_room(5, 1)
	var mover := _make_combatant("MOVER", Combatant.Side.PARTY)
	var blocker := _make_combatant("BLOCKER", Combatant.Side.ENEMY, true)
	var roster := CombatRoster.new()
	roster.add_combatant(mover); roster.add_combatant(blocker)
	var mr := MovementResolver.new(roster)
	mr.set_voxel_map(map)
	map.set_entity_pos("MOVER", Vector3i(0, 0, 0))
	map.set_entity_pos("BLOCKER", Vector3i(2, 0, 0))
	var path := mr.path_bfs_3d(
		Vector3i(0, 0, 0), Vector3i(4, 0, 0),
		"ground", 50, -1, "strict", "MOVER")
	check(path.is_empty(),
		"active combatant in the corridor must block the path")


func test_b2_endpoint_blocked_by_incapacitated_body() -> void:
	# Path step over a body is allowed; stopping ON the body is not.
	var map := _make_flat_room(3, 1)
	var mover := _make_combatant("MOVER", Combatant.Side.PARTY)
	var corpse := _make_combatant("CORPSE", Combatant.Side.ENEMY, false)
	var roster := CombatRoster.new()
	roster.add_combatant(mover); roster.add_combatant(corpse)
	var mr := MovementResolver.new(roster)
	mr.set_voxel_map(map)
	map.set_entity_pos("MOVER", Vector3i(0, 0, 0))
	map.set_entity_pos("CORPSE", Vector3i(2, 0, 0))
	var path := mr.path_bfs_3d(
		Vector3i(0, 0, 0), Vector3i(2, 0, 0),
		"ground", 50, -1, "strict", "MOVER")
	check(path.is_empty(),
		"cannot end movement on an incapacitated occupant's cell")


func test_b2_endpoint_allowed_when_only_self_present() -> void:
	# Mover ending on a cell containing only its own token is fine (self-loop
	# move; common after pathfinding to a destination next to where you start).
	var map := _make_flat_room(3, 1)
	var mover := _make_combatant("MOVER", Combatant.Side.PARTY)
	var roster := CombatRoster.new()
	roster.add_combatant(mover)
	var mr := MovementResolver.new(roster)
	mr.set_voxel_map(map)
	map.set_entity_pos("MOVER", Vector3i(0, 0, 0))
	var path := mr.path_bfs_3d(
		Vector3i(0, 0, 0), Vector3i(2, 0, 0),
		"ground", 50, -1, "strict", "MOVER")
	check(not path.is_empty(),
		"empty corridor with only self entity present should path freely")


func test_b2_default_signature_ignores_occupancy() -> void:
	# Backwards-compat: callers that don't pass mover_id (e.g. dungeon
	# explorer) still get the old "occupancy ignored" behavior.
	var map := _make_flat_room(3, 1)
	var blocker := _make_combatant("BLOCKER", Combatant.Side.ENEMY, true)
	var roster := CombatRoster.new()
	roster.add_combatant(blocker)
	var mr := MovementResolver.new(roster)
	mr.set_voxel_map(map)
	map.set_entity_pos("BLOCKER", Vector3i(1, 0, 0))
	var path := mr.path_bfs_3d(Vector3i(0, 0, 0), Vector3i(2, 0, 0))
	check(not path.is_empty(),
		"default signature must ignore occupancy (no regression for dungeon explorer)")
