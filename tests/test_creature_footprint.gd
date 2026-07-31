extends "res://tests/test_suite_base.gd"

## Creature-size / multi-cell footprint architecture (creature-size build session).
##
## Covers the pure geometry (CreatureSize scale + CreatureFootprint rotation),
## VoxelMapData footprint-aware occupancy, and the MovementResolver gates:
## passage-gating (an oversized body can't squeeze a narrow corridor), ZoC
## bordering the whole footprint, and footprint-aware adjacency. The single-cell
## fast path is asserted to behave exactly as before.


func run_all_tests() -> void:
	# Pure geometry
	test_creature_size_footprint_table()
	test_creature_size_height_scale_monotonic()
	test_footprint_single_cell()
	test_footprint_2x1_east()
	test_footprint_rotates_with_facing()
	test_footprint_2x2_block()
	test_footprint_1x2_across()
	# VoxelMapData occupancy
	test_map_default_is_single_cell()
	test_map_multicell_occupies_all_cells()
	test_map_is_occupied_by_other_excludes_self()
	test_map_clear_footprint_collapses()
	test_map_remove_entity_clears_footprint()
	# MovementResolver gates
	test_footprint_can_occupy_open_vs_wall()
	test_huge_blocked_by_narrow_corridor_mansized_passes()
	test_zoc_borders_whole_footprint()
	test_adjacency_is_footprint_aware()
	if not has_failures():
		print("CreatureFootprint: all tests passed.")


# ---------------------------------------------------------------------------
# Pure geometry — CreatureSize
# ---------------------------------------------------------------------------

func test_creature_size_footprint_table() -> void:
	check(CreatureSize.footprint_local("man_sized") == Vector2i(1, 1), "man_sized 1x1")
	check(CreatureSize.footprint_local("small") == Vector2i(1, 1), "small 1x1")
	check(CreatureSize.footprint_local("large", "long") == Vector2i(2, 1), "large long 2x1")
	check(CreatureSize.footprint_local("large", "wide") == Vector2i(1, 2), "large wide 1x2")
	check(CreatureSize.footprint_local("huge") == Vector2i(2, 2), "huge 2x2")
	check(CreatureSize.footprint_local("gigantic") == Vector2i(3, 4), "gigantic 3x4")
	check(CreatureSize.footprint_local("colossal") == Vector2i(6, 9), "colossal 6x9")
	# Unknown category degrades to single cell.
	check(CreatureSize.footprint_local("gargantuan") == Vector2i(1, 1), "unknown -> 1x1")
	# parse helper matches the table.
	check(CreatureSize.parse_footprint_string("3x4") == Vector2i(3, 4), "parse 3x4")
	check(CreatureSize.parse_footprint_string("nonsense") == Vector2i(1, 1), "parse junk -> 1x1")


func test_creature_size_height_scale_monotonic() -> void:
	var prev := 0.0
	for cat in CreatureSize.CATEGORIES:
		var h := CreatureSize.height_scale(cat)
		check(h >= prev, "height scale non-decreasing at %s (%f < %f)" % [cat, h, prev])
		prev = h


func test_footprint_single_cell() -> void:
	var cells := CreatureFootprint.cells(Vector3i(5, 5, 0), Vector2i(1, 0), Vector2i(1, 1))
	check(cells.size() == 1, "1x1 occupies exactly one cell")
	check(cells[0] == Vector3i(5, 5, 0), "1x1 sits on its anchor")
	check(CreatureFootprint.is_single_cell(Vector2i(1, 1)), "is_single_cell true for 1x1")
	check(not CreatureFootprint.is_single_cell(Vector2i(2, 1)), "is_single_cell false for 2x1")


func test_footprint_2x1_east() -> void:
	# length 2 along facing east (1,0) -> anchor + one cell forward on the col axis.
	var cells := CreatureFootprint.cells(Vector3i(5, 5, 0), Vector2i(1, 0), Vector2i(2, 1))
	check(cells.size() == 2, "2x1 occupies two cells")
	check(Vector3i(5, 5, 0) in cells, "anchor occupied")
	check(Vector3i(6, 5, 0) in cells, "one cell east occupied")


func test_footprint_rotates_with_facing() -> void:
	# The SAME 2x1 body flips its occupied axis when it turns 90 degrees.
	var east := CreatureFootprint.cells(Vector3i(5, 5, 0), Vector2i(1, 0), Vector2i(2, 1))
	var south := CreatureFootprint.cells(Vector3i(5, 5, 0), Vector2i(0, 1), Vector2i(2, 1))
	check(Vector3i(6, 5, 0) in east, "east body extends along col axis")
	check(Vector3i(5, 6, 0) in south, "south body extends along row axis")
	check(not (Vector3i(6, 5, 0) in south), "turned body no longer occupies the old cell")


func test_footprint_2x2_block() -> void:
	var cells := CreatureFootprint.cells(Vector3i(4, 4, 0), Vector2i(1, 0), Vector2i(2, 2))
	check(cells.size() == 4, "2x2 occupies four cells")
	# distinct cells, all on the anchor's level
	var uniq: Dictionary = {}
	for c in cells:
		uniq[c] = true
		check(c.z == 0, "footprint stays on one level")
	check(uniq.size() == 4, "2x2 cells are distinct")


func test_footprint_1x2_across() -> void:
	var cells := CreatureFootprint.cells(Vector3i(5, 5, 0), Vector2i(1, 0), Vector2i(1, 2))
	check(cells.size() == 2, "1x2 occupies two cells across the facing")
	check(Vector3i(5, 5, 0) in cells, "anchor occupied")


# ---------------------------------------------------------------------------
# VoxelMapData occupancy
# ---------------------------------------------------------------------------

func test_map_default_is_single_cell() -> void:
	var m := VoxelMapData.new()
	m.set_entity_pos("gob", Vector3i(3, 3, 0))
	check(m.get_entity_footprint_cells("gob").size() == 1, "unregistered entity is single-cell")
	check(m.get_entities_at(Vector3i(3, 3, 0)) == ["gob"], "found at its anchor")
	check(m.get_entities_at(Vector3i(4, 3, 0)).is_empty(), "not found at a neighbour")


func test_map_multicell_occupies_all_cells() -> void:
	var m := VoxelMapData.new()
	m.set_entity_pos("ogre", Vector3i(5, 5, 0))
	var body: Array[Vector3i] = [Vector3i(5, 5, 0), Vector3i(6, 5, 0)]
	m.set_entity_footprint("ogre", body)
	check("ogre" in m.get_entities_at(Vector3i(5, 5, 0)), "found at anchor cell")
	check("ogre" in m.get_entities_at(Vector3i(6, 5, 0)), "found at second body cell")
	check(m.is_occupied(Vector3i(6, 5, 0)), "second cell reads occupied")
	check(m.get_entity_footprint_cells("ogre").size() == 2, "footprint reports two cells")


func test_map_is_occupied_by_other_excludes_self() -> void:
	var m := VoxelMapData.new()
	m.set_entity_pos("ogre", Vector3i(5, 5, 0))
	m.set_entity_footprint("ogre", [Vector3i(5, 5, 0), Vector3i(6, 5, 0)])
	check(not m.is_occupied_by_other(Vector3i(6, 5, 0), "ogre"), "own body cell is not 'other'")
	check(m.is_occupied_by_other(Vector3i(6, 5, 0), "someone_else"), "other sees the body cell")


func test_map_clear_footprint_collapses() -> void:
	var m := VoxelMapData.new()
	m.set_entity_pos("ogre", Vector3i(5, 5, 0))
	m.set_entity_footprint("ogre", [Vector3i(5, 5, 0), Vector3i(6, 5, 0)])
	m.clear_entity_footprint("ogre")
	check(m.get_entities_at(Vector3i(6, 5, 0)).is_empty(), "second cell freed after clear")
	check(m.get_entities_at(Vector3i(5, 5, 0)) == ["ogre"], "still occupies its anchor")
	# A one-cell array also collapses.
	m.set_entity_footprint("ogre", [Vector3i(5, 5, 0)])
	check(m.get_entities_at(Vector3i(6, 5, 0)).is_empty(), "single-cell array collapses to anchor")


func test_map_remove_entity_clears_footprint() -> void:
	var m := VoxelMapData.new()
	m.set_entity_pos("ogre", Vector3i(5, 5, 0))
	m.set_entity_footprint("ogre", [Vector3i(5, 5, 0), Vector3i(6, 5, 0)])
	m.remove_entity("ogre")
	check(m.get_entities_at(Vector3i(5, 5, 0)).is_empty(), "anchor freed")
	check(m.get_entities_at(Vector3i(6, 5, 0)).is_empty(), "body cell freed")
	check(m.get_entity_footprint_cells("ogre").is_empty(), "footprint gone")


# ---------------------------------------------------------------------------
# MovementResolver gates
# ---------------------------------------------------------------------------

func _open(map: VoxelMapData, positions: Array) -> void:
	for p in positions:
		var cell := VoxelCell.new()
		cell.solidity = "air"
		cell.feature = "open"
		cell.floor_type = "stone"
		map.set_cell(p, cell)


func _spawn(env: Dictionary, monster_id: String, cid: String, anchor: Vector3i,
		side: int = Combatant.Side.ENEMY) -> Combatant:
	var registry: MonsterRegistry = env.registry
	if not registry.has_monster(monster_id):
		return null
	var c := Combatant.from_monster(registry.get_monster(monster_id), 12, cid, monster_id)
	c.side = side
	env.roster.add_combatant(c)
	env.mr.set_grid_position_3d(c, anchor)
	return c


func _env(map: VoxelMapData) -> Dictionary:
	var roster := CombatRoster.new()
	var mr := MovementResolver.new(roster)
	mr.set_voxel_map(map)
	return {"roster": roster, "mr": mr, "registry": MonsterRegistry.new()}


func test_footprint_can_occupy_open_vs_wall() -> void:
	var map := VoxelMapData.new()
	# 3x3 open block at cols 0..2 rows 0..2.
	var open_cells: Array = []
	for c in range(3):
		for r in range(3):
			open_cells.append(Vector3i(c, r, 0))
	_open(map, open_cells)
	var mr := MovementResolver.new()
	mr.set_voxel_map(map)
	# A 2x2 (facing east: cells anchor, anchor-row, anchor+col, anchor+col-row) fits
	# when anchored at (1,1) -> cells (1,0),(1,1),(2,0),(2,1) all open.
	check(mr.footprint_can_occupy(Vector3i(1, 1, 0), Vector2i(1, 0), Vector2i(2, 2)),
		"2x2 fits inside the open 3x3 block")
	# Anchored so a body cell lands outside the block (a wall) -> refused.
	check(not mr.footprint_can_occupy(Vector3i(0, 0, 0), Vector2i(1, 0), Vector2i(2, 2)),
		"2x2 refused when a body cell falls on an unsupported/absent cell")


func _build_corridor_map() -> VoxelMapData:
	# Two 3x3 rooms joined by a ONE-row (1-wide) corridor on row 1.
	var map := VoxelMapData.new()
	var cells: Array = []
	for c in range(3):            # Room A cols 0..2
		for r in range(3):
			cells.append(Vector3i(c, r, 0))
	for c in range(3, 6):         # 1-wide corridor on row 1
		cells.append(Vector3i(c, 1, 0))
	for c in range(6, 9):         # Room B cols 6..8
		for r in range(3):
			cells.append(Vector3i(c, r, 0))
	_open(map, cells)
	return map


func test_huge_blocked_by_narrow_corridor_mansized_passes() -> void:
	# Separate maps so the two bodies never block each other's start cell.
	var gob_env := _env(_build_corridor_map())
	var mino_env := _env(_build_corridor_map())
	if not gob_env.registry.has_monster("goblin") or not mino_env.registry.has_monster("minotaur"):
		check(false, "fixture monsters missing from catalog")
		return
	var gob := _spawn(gob_env, "goblin", "gob1", Vector3i(1, 1, 0))    # man_sized 1x1
	var mino := _spawn(mino_env, "minotaur", "min1", Vector3i(1, 1, 0)) # huge 2x2

	check(not gob.is_multi_cell(), "goblin is single-cell")
	check(mino.is_multi_cell(), "minotaur is multi-cell (2x2)")

	# Man-sized reaches room B through the corridor.
	var gob_path: Array = gob_env.mr.path_bfs_3d(Vector3i(1, 1, 0), Vector3i(7, 1, 0),
		"ground", 50, -1, "strict", "gob1")
	check(not gob_path.is_empty(), "man-sized creature routes through the 1-wide corridor")

	# Huge cannot fit the corridor -> no path to room B.
	var mino_path: Array = mino_env.mr.path_bfs_3d(Vector3i(1, 1, 0), Vector3i(7, 1, 0),
		"ground", 50, -1, "strict", "min1")
	check(mino_path.is_empty(), "huge creature cannot squeeze the 1-wide corridor")


func test_zoc_borders_whole_footprint() -> void:
	var map := VoxelMapData.generate_open_field(14, 14)
	var env := _env(map)
	if not env.registry.has_monster("minotaur"):
		check(false, "minotaur missing"); return
	var mino := _spawn(env, "minotaur", "min1", Vector3i(6, 6, 0))  # 2x2, facing east
	# Body cells for east-facing 2x2 at (6,6): (6,5),(6,6),(7,5),(7,6).
	var body: Array = env.mr._footprint_cells_for(mino)
	check(body.size() == 4, "minotaur occupies 4 cells")
	var zoc: Dictionary = env.mr._build_enemy_zoc_set_3d(Combatant.Side.PARTY)
	# A cell bordering the far corner of the body is threatened...
	check(zoc.has(Vector3i(8, 6, 0)), "cell east of the body is in ZoC")
	check(zoc.has(Vector3i(5, 5, 0)), "cell northwest of the body is in ZoC")
	# ...but the occupied cells themselves are not part of the ZoC ring.
	for bc in body:
		check(not zoc.has(bc), "occupied cell %s excluded from ZoC" % str(bc))


func test_adjacency_is_footprint_aware() -> void:
	var map := VoxelMapData.generate_open_field(14, 14)
	var env := _env(map)
	if not env.registry.has_monster("minotaur") or not env.registry.has_monster("goblin"):
		check(false, "fixture monsters missing"); return
	var mino := _spawn(env, "minotaur", "min1", Vector3i(6, 6, 0), Combatant.Side.ENEMY)
	# Body cells: (6,5),(6,6),(7,5),(7,6). A PC touching (7,6) is engaged.
	var near := _spawn(env, "goblin", "near", Vector3i(8, 6, 0), Combatant.Side.PARTY)
	var far := _spawn(env, "goblin", "far", Vector3i(9, 6, 0), Combatant.Side.PARTY)
	check(env.mr.is_adjacent(near, mino), "cell bordering the body engages the big creature")
	check(not env.mr.is_adjacent(far, mino), "two cells away does not engage")
	# get_adjacent_enemies from the big creature's perspective finds the near PC only.
	var adj: Array = env.mr.get_adjacent_enemies(mino)
	var ids: Array = []
	for a in adj:
		ids.append(a.id)
	check("near" in ids, "big creature sees the adjacent PC")
	check(not ("far" in ids), "big creature does not see the far PC")
