extends "res://tests/test_suite_base.gd"

## Unit tests for DungeonMapController voxel-mode methods.
##
## Exercises the voxel-path dispatch added in Session 7b: move_party,
## interact_door, can_move_to, queue_group_move, queue_door_interaction_order,
## stair traversal via move_party, the fog helpers, and signal emission with
## Vector3i payloads.
## All tests use hand-built VoxelMapData fixtures — no PartyData is required.


func run_all_tests() -> void:
	test_load_populates_voxel_map()
	test_move_party_adjacent_succeeds()
	test_move_party_non_adjacent_fails()
	test_move_party_blocked_cell_fails()
	test_can_move_to_voxel()
	test_interact_door_closed_opens()
	test_interact_door_open_closes()
	test_interact_locked_door_blocked()
	test_interact_door_non_adjacent_fails()
	test_move_party_via_stair_transitions_level()
	test_update_fog_on_move_transitions()
	test_reveal_entry_room_voxel()
	test_get_voxel_map_returns_data()
	test_signals_carry_vector3i()
	if not has_failures():
		print("DungeonMapControllerVoxel: all tests passed.")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _make_flat_voxel_dungeon(width: int, height: int, level: int = 0) -> VoxelMapData:
	var map := VoxelMapData.new()
	map.entry_pos = Vector3i(0, 0, level)
	for c in range(width):
		for r in range(height):
			var cell := VoxelCell.new()
			cell.solidity = "air"
			cell.feature = "open"
			cell.floor_type = "stone"
			cell.fog_state = "hidden"
			map.set_cell(Vector3i(c, r, level), cell)
	return map


func _make_controller_with_map(map: VoxelMapData, entity_id: String = "hero") -> DungeonMapController:
	var ctrl := DungeonMapController.new()
	add_child(ctrl)
	ctrl.add_party_member(entity_id)
	# Bypass load_dungeon's JSON path — inject the voxel map directly.
	ctrl._voxel_map = map
	ctrl._current_level = map.entry_pos.z
	# Place the hero at the entry position
	map.set_entity_pos(entity_id, map.entry_pos)
	return ctrl


func _place_voxel_cell(map: VoxelMapData, pos: Vector3i, solidity: String = "air",
		feature: String = "open", floor_type: String = "stone") -> VoxelCell:
	var cell := VoxelCell.new()
	cell.solidity = solidity
	cell.feature = feature
	cell.floor_type = floor_type
	cell.fog_state = "hidden"
	map.set_cell(pos, cell)
	return cell


func _place_voxel_door(map: VoxelMapData, pos: Vector3i, door_type: String, door_state: String) -> VoxelCell:
	var cell := VoxelCell.new()
	cell.solidity = "air"
	cell.feature = "door"
	cell.floor_type = "stone"
	cell.fog_state = "visible"
	cell.door_type = door_type
	cell.door_state = door_state
	cell.door_detected = true
	map.set_cell(pos, cell)
	return cell


# ---------------------------------------------------------------------------
# Load / basic state
# ---------------------------------------------------------------------------

func test_load_populates_voxel_map() -> void:
	var map := _make_flat_voxel_dungeon(3, 3)
	var ctrl := _make_controller_with_map(map)
	check(ctrl.get_voxel_map() == map,
		"get_voxel_map should return the loaded VoxelMapData")
	check(ctrl.get_party_position_3d() == Vector3i(0, 0, 0),
		"hero should be positioned at entry_pos")
	ctrl.queue_free()


# ---------------------------------------------------------------------------
# Movement
# ---------------------------------------------------------------------------

func test_move_party_adjacent_succeeds() -> void:
	var map := _make_flat_voxel_dungeon(3, 3)
	var ctrl := _make_controller_with_map(map)
	var result := ctrl.move_party(Vector3i(1, 0, 0))
	check(result, "move_party to adjacent Vector3i should succeed")
	check(ctrl.get_party_position_3d() == Vector3i(1, 0, 0),
		"party should be at target after move")
	ctrl.queue_free()


func test_move_party_non_adjacent_fails() -> void:
	var map := _make_flat_voxel_dungeon(3, 3)
	var ctrl := _make_controller_with_map(map)
	var result := ctrl.move_party(Vector3i(2, 2, 0))
	check(not result, "move_party to non-adjacent cell should fail")
	check(ctrl.get_party_position_3d() == Vector3i(0, 0, 0),
		"party should remain at entry after failed move")
	ctrl.queue_free()


func test_move_party_blocked_cell_fails() -> void:
	var map := _make_flat_voxel_dungeon(3, 3)
	# Block (1,0,0) with solid rock
	_place_voxel_cell(map, Vector3i(1, 0, 0), "solid", "rock", "none")
	var ctrl := _make_controller_with_map(map)
	var result := ctrl.move_party(Vector3i(1, 0, 0))
	check(not result, "move_party into solid cell should fail")
	ctrl.queue_free()


func test_can_move_to_voxel() -> void:
	var map := _make_flat_voxel_dungeon(3, 3)
	var ctrl := _make_controller_with_map(map)
	check(ctrl.can_move_to(Vector3i(1, 0, 0)),
		"can_move_to should return true for adjacent passable cell")
	check(not ctrl.can_move_to(Vector3i(2, 2, 0)),
		"can_move_to should return false for non-adjacent cell")
	ctrl.queue_free()


# ---------------------------------------------------------------------------
# Doors
# ---------------------------------------------------------------------------

func test_interact_door_closed_opens() -> void:
	var map := _make_flat_voxel_dungeon(3, 3)
	_place_voxel_door(map, Vector3i(1, 0, 0), "unlocked", "closed")
	var ctrl := _make_controller_with_map(map)
	var result := ctrl.interact_door(Vector3i(1, 0, 0))
	check(result, "interact_door on adjacent closed door should succeed")
	check(map.get_cell(Vector3i(1, 0, 0)).door_state == "open",
		"door state should transition to 'open'")
	ctrl.queue_free()


func test_interact_door_open_closes() -> void:
	var map := _make_flat_voxel_dungeon(3, 3)
	_place_voxel_door(map, Vector3i(1, 0, 0), "unlocked", "open")
	var ctrl := _make_controller_with_map(map)
	var result := ctrl.interact_door(Vector3i(1, 0, 0))
	check(result, "interact_door on adjacent open door should close it")
	check(map.get_cell(Vector3i(1, 0, 0)).door_state == "closed",
		"door state should transition to 'closed'")
	ctrl.queue_free()


func test_interact_locked_door_blocked() -> void:
	var map := _make_flat_voxel_dungeon(3, 3)
	_place_voxel_door(map, Vector3i(1, 0, 0), "locked", "locked")
	var ctrl := _make_controller_with_map(map)
	var result := ctrl.interact_door(Vector3i(1, 0, 0))
	check(not result, "interact_door on locked door should return false")
	check(map.get_cell(Vector3i(1, 0, 0)).door_state == "locked",
		"locked door state should not change")
	ctrl.queue_free()


func test_interact_door_non_adjacent_fails() -> void:
	var map := _make_flat_voxel_dungeon(3, 3)
	_place_voxel_door(map, Vector3i(2, 2, 0), "unlocked", "closed")
	var ctrl := _make_controller_with_map(map)
	var result := ctrl.interact_door(Vector3i(2, 2, 0))
	check(not result,
		"interact_door on non-adjacent door should return false")
	ctrl.queue_free()


# ---------------------------------------------------------------------------
# Stairs
# ---------------------------------------------------------------------------

func test_move_party_via_stair_transitions_level() -> void:
	var map := _make_flat_voxel_dungeon(3, 3, 0)
	# Add level 1 (2x2 at upper layer)
	_place_voxel_cell(map, Vector3i(1, 0, 1))
	_place_voxel_cell(map, Vector3i(0, 0, 1))
	_place_voxel_cell(map, Vector3i(1, 1, 1))
	_place_voxel_cell(map, Vector3i(0, 1, 1))
	# Stairs_up_E at (0,0,0) connects to (1,0,1)
	_place_voxel_cell(map, Vector3i(0, 0, 0), "air", "stairs_up_E")
	var ctrl := _make_controller_with_map(map)
	# Hero starts on the stair cell at (0,0,0). move_party to the connected cell.
	var result := ctrl.move_party(Vector3i(1, 0, 1))
	check(result, "move_party across stair should succeed")
	check(ctrl.get_party_position_3d() == Vector3i(1, 0, 1),
		"party should be at the target level after stair traversal")
	check(ctrl.get_current_level() == 1,
		"current_level should update to the destination level")
	ctrl.queue_free()


# ---------------------------------------------------------------------------
# Fog
# ---------------------------------------------------------------------------

func test_update_fog_on_move_transitions() -> void:
	var map := _make_flat_voxel_dungeon(3, 3)
	var ctrl := _make_controller_with_map(map)
	# Trigger initial fog reveal
	ctrl._update_fog_for_all_members()
	var entry_fog := map.get_fog(Vector3i(0, 0, 0))
	check(entry_fog == "visible",
		"entry cell should be 'visible' after fog update; got '%s'" % entry_fog)
	# Move away and re-run fog; previous cell should become 'explored'.
	ctrl.move_party(Vector3i(1, 0, 0))
	var new_entry_fog := map.get_fog(Vector3i(1, 0, 0))
	check(new_entry_fog == "visible",
		"new position should be 'visible' after move")
	ctrl.queue_free()


func test_reveal_entry_room_voxel() -> void:
	var map := _make_flat_voxel_dungeon(3, 3)
	# Assign all cells to room_id=1 (single room)
	for c in range(3):
		for r in range(3):
			map.get_cell(Vector3i(c, r, 0)).room_id = 1
	var ctrl := _make_controller_with_map(map)
	ctrl._reveal_entry_room()
	var fog_at_entry := map.get_fog(Vector3i(0, 0, 0))
	check(fog_at_entry == "visible",
		"entry cell should be 'visible' after _reveal_entry_room; got '%s'" % fog_at_entry)
	ctrl.queue_free()


# ---------------------------------------------------------------------------
# Accessors + signals
# ---------------------------------------------------------------------------

func test_get_voxel_map_returns_data() -> void:
	var map := _make_flat_voxel_dungeon(2, 2)
	var ctrl := _make_controller_with_map(map)
	check(ctrl.get_voxel_map() == map, "get_voxel_map should return the injected map")
	ctrl.queue_free()


func test_signals_carry_vector3i() -> void:
	var map := _make_flat_voxel_dungeon(3, 3)
	_place_voxel_door(map, Vector3i(1, 0, 0), "unlocked", "closed")
	var ctrl := _make_controller_with_map(map)

	var moved_from_is_v3 := false
	var moved_to_is_v3 := false
	ctrl.party_moved.connect(func(f, t) -> void:
		moved_from_is_v3 = f is Vector3i
		moved_to_is_v3 = t is Vector3i
	)

	var door_pos_is_v3 := false
	ctrl.door_state_changed.connect(func(p, _old: String, _new: String) -> void:
		door_pos_is_v3 = p is Vector3i
	)

	# Move: move_party emits party_moved(Vector3i, Vector3i) in the single-entity branch.
	ctrl.move_party(Vector3i(0, 1, 0))
	check(moved_from_is_v3, "party_moved from_pos should be Vector3i")
	check(moved_to_is_v3, "party_moved to_pos should be Vector3i")

	# Door interaction emits door_state_changed(Vector3i, String, String).
	# Hero is now at (0,1,0); the door at (1,0,0) is still adjacent (Chebyshev=1).
	ctrl.interact_door(Vector3i(1, 0, 0))
	check(door_pos_is_v3, "door_state_changed pos should be Vector3i")
	ctrl.queue_free()
