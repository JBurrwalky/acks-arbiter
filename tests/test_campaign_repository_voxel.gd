extends "res://tests/test_suite_base.gd"

## Unit tests for CampaignRepository voxel cell persistence (migration 036).
##
## Tests CRUD operations for voxel_map_cells via the CampaignRepository autoload.
## Uses a unique map_id prefix to avoid collisions with live data.

const TEST_MAP_ID := "test_voxel_repo_"
var _repo: Node  # CampaignRepository autoload


func run_all_tests() -> void:
	_repo = Engine.get_singleton("CampaignRepository") if Engine.has_singleton("CampaignRepository") else null
	if _repo == null:
		# Fallback: try the autoload node via tree
		_repo = _get_autoload("CampaignRepository")
	if _repo == null:
		push_error("CampaignRepository autoload not found — skipping voxel repo tests")
		return

	_cleanup()
	test_save_and_load_single_cell()
	_cleanup()
	test_save_batch_and_load()
	_cleanup()
	test_load_empty_map()
	_cleanup()
	test_update_cell_state()
	_cleanup()
	test_save_overwrites_existing()
	_cleanup()
	test_bool_fields_roundtrip()
	_cleanup()
	test_load_voxel_map_returns_voxel_map_data()
	_cleanup()
	test_load_voxel_map_empty()
	_cleanup()
	test_different_map_ids_dont_cross()
	_cleanup()
	test_batch_save_100_cells()
	_cleanup()
	test_room_id_and_cover_persist()
	_cleanup()
	test_all_fields_roundtrip()
	_cleanup()

	if not has_failures():
		print("CampaignRepositoryVoxel: all tests passed.")


func _get_autoload(aname: String) -> Node:
	var root := get_tree().root
	for child in root.get_children():
		if child.name == aname:
			return child
	return null


func _cleanup() -> void:
	# Delete test rows to avoid contamination between tests.
	if _repo and _repo.db:
		_repo.db.query_with_bindings(
			"DELETE FROM voxel_map_cells WHERE map_id LIKE ?",
			[TEST_MAP_ID + "%"]
		)


func _make_cell(c: int, r: int, l: int) -> VoxelCell:
	var cell := VoxelCell.new()
	cell.col = c
	cell.row = r
	cell.level = l
	cell.solidity = "air"
	cell.feature = "open"
	cell.floor_type = "stone"
	cell.fog_state = "hidden"
	return cell


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_save_and_load_single_cell() -> void:
	var mid := TEST_MAP_ID + "single"
	var cell := _make_cell(3, 5, 2)
	cell.solidity = "solid"
	cell.feature = "wall_stone"
	cell.floor_type = "none"
	cell.fog_state = "visible"

	var ok: bool = _repo.save_voxel_cell(mid, cell)
	check(ok, "save_voxel_cell should return true")

	var cells: Array = _repo.load_voxel_cells_for_map(mid)
	check(cells.size() == 1, "should load 1 cell, got %d" % cells.size())
	if cells.size() == 0:
		return
	var loaded: VoxelCell = cells[0]
	check(loaded.col == 3, "col should be 3")
	check(loaded.row == 5, "row should be 5")
	check(loaded.level == 2, "level should be 2")
	check(loaded.solidity == "solid", "solidity should be solid")
	check(loaded.feature == "wall_stone", "feature should be wall_stone")
	check(loaded.floor_type == "none", "floor_type should be none")
	check(loaded.fog_state == "visible", "fog_state should be visible")


func test_save_batch_and_load() -> void:
	var mid := TEST_MAP_ID + "batch"
	var cells: Array = []
	for i in range(5):
		cells.append(_make_cell(i, 0, 0))

	var ok: bool = _repo.save_voxel_cells_batch(mid, cells)
	check(ok, "save_voxel_cells_batch should return true")

	var loaded: Array = _repo.load_voxel_cells_for_map(mid)
	check(loaded.size() == 5, "should load 5 cells, got %d" % loaded.size())


func test_load_empty_map() -> void:
	var cells: Array = _repo.load_voxel_cells_for_map(TEST_MAP_ID + "nonexistent")
	check(cells.size() == 0, "loading nonexistent map should return empty array")


func test_update_cell_state() -> void:
	var mid := TEST_MAP_ID + "update"
	var cell := _make_cell(1, 1, 0)
	cell.door_state = "closed"
	cell.fog_state = "hidden"
	_repo.save_voxel_cell(mid, cell)

	_repo.update_voxel_cell_state(mid, 1, 1, 0, "open", "visible")

	var loaded: Array = _repo.load_voxel_cells_for_map(mid)
	check(loaded.size() == 1, "should have 1 cell")
	if loaded.size() == 0:
		return
	var lc: VoxelCell = loaded[0]
	check(lc.door_state == "open", "door_state should be updated to 'open', got '%s'" % lc.door_state)
	check(lc.fog_state == "visible", "fog_state should be updated to 'visible', got '%s'" % lc.fog_state)


func test_save_overwrites_existing() -> void:
	var mid := TEST_MAP_ID + "overwrite"
	var cell1 := _make_cell(2, 2, 0)
	cell1.feature = "rock"
	_repo.save_voxel_cell(mid, cell1)

	var cell2 := _make_cell(2, 2, 0)
	cell2.feature = "wall_stone"
	_repo.save_voxel_cell(mid, cell2)

	var loaded: Array = _repo.load_voxel_cells_for_map(mid)
	check(loaded.size() == 1, "should have 1 cell after overwrite")
	if loaded.size() == 0:
		return
	check(loaded[0].feature == "wall_stone",
		"overwritten feature should be wall_stone, got '%s'" % loaded[0].feature)


func test_bool_fields_roundtrip() -> void:
	var mid := TEST_MAP_ID + "bools"
	var cell := _make_cell(0, 0, 0)
	cell.door_detected = true
	cell.is_corridor = true
	_repo.save_voxel_cell(mid, cell)

	var loaded: Array = _repo.load_voxel_cells_for_map(mid)
	check(loaded.size() == 1, "should have 1 cell")
	if loaded.size() == 0:
		return
	check(loaded[0].door_detected == true, "door_detected should round-trip as true")
	check(loaded[0].is_corridor == true, "is_corridor should round-trip as true")

	# Also test false
	var cell2 := _make_cell(1, 0, 0)
	cell2.door_detected = false
	cell2.is_corridor = false
	_repo.save_voxel_cell(mid, cell2)

	var all: Array = _repo.load_voxel_cells_for_map(mid)
	var found := false
	for c: VoxelCell in all:
		if c.col == 1:
			found = true
			check(c.door_detected == false, "door_detected false should round-trip")
			check(c.is_corridor == false, "is_corridor false should round-trip")
	check(found, "should find the cell with col=1")


func test_load_voxel_map_returns_voxel_map_data() -> void:
	var mid := TEST_MAP_ID + "mapload"
	var cells: Array = []
	for i in range(3):
		cells.append(_make_cell(i, 0, 0))
	_repo.save_voxel_cells_batch(mid, cells)

	var map: VoxelMapData = _repo.load_voxel_map(mid)
	check(map != null, "load_voxel_map should return non-null")
	check(map.id == mid, "map.id should match")
	check(map.cell_count() == 3, "map should have 3 cells, got %d" % map.cell_count())


func test_load_voxel_map_empty() -> void:
	var map: VoxelMapData = _repo.load_voxel_map(TEST_MAP_ID + "empty")
	check(map != null, "should return non-null VoxelMapData for empty map")
	check(map.cell_count() == 0, "empty map should have 0 cells")


func test_different_map_ids_dont_cross() -> void:
	var mid_a := TEST_MAP_ID + "cross_a"
	var mid_b := TEST_MAP_ID + "cross_b"
	_repo.save_voxel_cell(mid_a, _make_cell(0, 0, 0))
	_repo.save_voxel_cell(mid_b, _make_cell(1, 1, 1))

	var cells_a: Array = _repo.load_voxel_cells_for_map(mid_a)
	var cells_b: Array = _repo.load_voxel_cells_for_map(mid_b)
	check(cells_a.size() == 1, "map_a should have 1 cell")
	check(cells_b.size() == 1, "map_b should have 1 cell")
	if cells_a.size() > 0:
		check(cells_a[0].col == 0, "map_a cell should be at col 0")
	if cells_b.size() > 0:
		check(cells_b[0].col == 1, "map_b cell should be at col 1")


func test_batch_save_100_cells() -> void:
	var mid := TEST_MAP_ID + "batch100"
	var cells: Array = []
	for i in range(100):
		cells.append(_make_cell(i, 0, 0))
	var ok: bool = _repo.save_voxel_cells_batch(mid, cells)
	check(ok, "batch save of 100 cells should succeed")

	var loaded: Array = _repo.load_voxel_cells_for_map(mid)
	check(loaded.size() == 100, "should load 100 cells, got %d" % loaded.size())


func test_room_id_and_cover_persist() -> void:
	var mid := TEST_MAP_ID + "roomcover"
	var cell := _make_cell(0, 0, 0)
	cell.room_id = 42
	cell.cover_value = 3
	_repo.save_voxel_cell(mid, cell)

	var loaded: Array = _repo.load_voxel_cells_for_map(mid)
	check(loaded.size() == 1, "should have 1 cell")
	if loaded.size() == 0:
		return
	check(loaded[0].room_id == 42, "room_id should persist as 42, got %d" % loaded[0].room_id)
	check(loaded[0].cover_value == 3, "cover_value should persist as 3, got %d" % loaded[0].cover_value)


func test_all_fields_roundtrip() -> void:
	var mid := TEST_MAP_ID + "allfields"
	var cell := VoxelCell.new()
	cell.col = 7
	cell.row = 11
	cell.level = 4
	cell.solidity = "liquid"
	cell.feature = "water_deep"
	cell.floor_type = "stone"
	cell.door_state = "locked"
	cell.door_type = "trapped"
	cell.door_detected = true
	cell.fog_state = "explored"
	cell.room_id = 99
	cell.is_corridor = true
	cell.cover_value = 2
	_repo.save_voxel_cell(mid, cell)

	var loaded: Array = _repo.load_voxel_cells_for_map(mid)
	check(loaded.size() == 1, "should have 1 cell")
	if loaded.size() == 0:
		return
	var lc: VoxelCell = loaded[0]
	check(lc.col == 7, "col round-trip")
	check(lc.row == 11, "row round-trip")
	check(lc.level == 4, "level round-trip")
	check(lc.solidity == "liquid", "solidity round-trip")
	check(lc.feature == "water_deep", "feature round-trip")
	check(lc.floor_type == "stone", "floor_type round-trip")
	check(lc.door_state == "locked", "door_state round-trip")
	check(lc.door_type == "trapped", "door_type round-trip")
	check(lc.door_detected == true, "door_detected round-trip")
	check(lc.fog_state == "explored", "fog_state round-trip")
	check(lc.room_id == 99, "room_id round-trip")
	check(lc.is_corridor == true, "is_corridor round-trip")
	check(lc.cover_value == 2, "cover_value round-trip")
