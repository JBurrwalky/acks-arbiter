extends "res://tests/test_suite_base.gd"

## Integration tests for the converted voxel test dungeon (Goblin Warrens).
##
## Verifies structural correctness of the voxel format: wall stacks, stair
## direction suffixes, door states, LOS through rooms, and entry cell walkability.


var _map: VoxelMapData


func run_all_tests() -> void:
	_map = VoxelMapData.load_from_file("res://data/test_dungeon.json")
	if _map == null:
		push_error("test_voxel_dungeon_integration: failed to load test_dungeon.json")
		check(false, "test_dungeon.json must be loadable")
		return

	test_load_goblin_warrens()
	test_entry_cell_is_walkable()
	test_level_0_has_open_cells()
	test_level_2_has_open_cells()
	test_wall_stacks_at_floor_and_ceiling()
	test_stair_cells_exist()
	test_stair_direction_suffix_valid()
	test_door_cells_have_state()
	test_los_through_open_cells()
	test_los_blocked_by_wall()
	if not has_failures():
		print("VoxelDungeonIntegration: all tests passed.")


func test_load_goblin_warrens() -> void:
	check(_map.id == "test_dungeon_goblin_warrens",
		"id should be test_dungeon_goblin_warrens")
	check(_map.cell_count() > 0, "map should have cells")
	check(_map.theme == "humanoid_warren", "theme should be humanoid_warren")


func test_entry_cell_is_walkable() -> void:
	var entry := _map.get_cell(_map.entry_pos)
	check(entry.solidity == "air", "entry cell should be air")
	check(entry.floor_type != "none", "entry cell should have a floor")
	check(entry.is_passable_by_walker(), "entry cell should be passable")


func test_level_0_has_open_cells() -> void:
	var cells := _map.get_cells_at_level(0)
	var open_count := 0
	for cell: VoxelCell in cells:
		if cell.solidity == "air" and cell.feature == "open":
			open_count += 1
	check(open_count > 10, "level 0 should have > 10 open cells, got %d" % open_count)


func test_level_2_has_open_cells() -> void:
	var cells := _map.get_cells_at_level(2)
	var open_count := 0
	for cell: VoxelCell in cells:
		if cell.solidity == "air" and cell.feature == "open":
			open_count += 1
	check(open_count > 5, "level 2 should have > 5 open cells, got %d" % open_count)


func test_wall_stacks_at_floor_and_ceiling() -> void:
	# Find a wall at level 0 and verify it has a matching wall at level 1
	var found_stack := false
	for cell: VoxelCell in _map.get_cells_at_level(0):
		if cell.solidity == "solid" and cell.feature == "wall_stone":
			var above := _map.get_cell(Vector3i(cell.col, cell.row, 1))
			if above.solidity == "solid":
				found_stack = true
				break
	check(found_stack, "should find at least one wall stack (level 0 + level 1)")


func test_stair_cells_exist() -> void:
	var stair_count := 0
	for cell: VoxelCell in _map.get_all_cells():
		if cell.feature.begins_with("stairs_"):
			stair_count += 1
	check(stair_count >= 2, "should have at least 2 stair cells, got %d" % stair_count)


func test_stair_direction_suffix_valid() -> void:
	var valid_suffixes := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	for cell: VoxelCell in _map.get_all_cells():
		if not cell.feature.begins_with("stairs_"):
			continue
		# Feature format: stairs_(up|down)_<DIR>
		var parts := cell.feature.split("_")
		check(parts.size() == 3,
			"stair feature should have 3 parts (stairs_dir_suffix), got '%s'" % cell.feature)
		if parts.size() == 3:
			check(parts[1] in ["up", "down"],
				"stair direction should be 'up' or 'down', got '%s'" % parts[1])
			check(parts[2] in valid_suffixes,
				"stair suffix should be a compass direction, got '%s'" % parts[2])


func test_door_cells_have_state() -> void:
	var valid_states := ["open", "closed", "locked", "stuck", "destroyed"]
	for cell: VoxelCell in _map.get_all_cells():
		if cell.door_state == "":
			continue
		check(cell.door_state in valid_states,
			"door_state '%s' at (%d,%d,%d) should be valid" % [
				cell.door_state, cell.col, cell.row, cell.level])
		check(cell.door_type != "",
			"cell with door_state should have door_type at (%d,%d,%d)" % [
				cell.col, cell.row, cell.level])


func test_los_through_open_cells() -> void:
	# Find two adjacent open cells at level 0 and verify LOS
	var open_cells: Array[Vector3i] = []
	for cell: VoxelCell in _map.get_cells_at_level(0):
		if cell.solidity == "air" and cell.feature == "open":
			open_cells.append(cell.pos)
		if open_cells.size() >= 2:
			break
	if open_cells.size() < 2:
		check(false, "need at least 2 open cells at level 0 for LOS test")
		return
	check(VoxelLOS.has_los(_map, open_cells[0], open_cells[1]),
		"LOS between two open cells should be clear")


func test_los_blocked_by_wall() -> void:
	# Find an open cell and a wall cell on the same level, then check LOS
	# through the wall to a cell on the other side
	var entry := _map.entry_pos
	# Scan in one direction from entry to find a wall, then a cell beyond it
	var wall_pos := Vector3i(-1, -1, -1)
	var beyond_pos := Vector3i(-1, -1, -1)
	for offset in range(1, 20):
		var test_pos := Vector3i(entry.x + offset, entry.y, entry.z)
		var cell := _map.get_cell(test_pos)
		if cell.solidity == "solid" and wall_pos == Vector3i(-1, -1, -1):
			wall_pos = test_pos
		elif wall_pos != Vector3i(-1, -1, -1) and cell.solidity == "air":
			beyond_pos = test_pos
			break

	if wall_pos == Vector3i(-1, -1, -1) or beyond_pos == Vector3i(-1, -1, -1):
		# Could not find wall + beyond pattern; skip gracefully
		return

	check(not VoxelLOS.has_los(_map, entry, beyond_pos),
		"LOS through a wall should be blocked")
