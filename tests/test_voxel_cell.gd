extends "res://tests/test_suite_base.gd"

## Unit tests for VoxelCell data type.
##
## Tests field defaults, serialization round-trip, and derived property methods.


func run_all_tests() -> void:
	test_default_values()
	test_pos_property()
	test_from_dict_populates_fields()
	test_to_dict_round_trip()
	test_from_dict_defaults()
	test_passable_open_air()
	test_not_passable_solid()
	test_not_passable_liquid()
	test_not_passable_closed_door()
	test_passable_open_door()
	test_passable_destroyed_door()
	test_walkable_with_open_door_closed_unlocked()
	test_walkable_with_open_door_locked()
	test_walkable_with_open_door_stuck()
	test_walkable_with_open_door_open()
	test_walkable_with_open_door_no_door()
	test_walkable_with_open_door_undetected_secret()
	test_walkable_with_open_door_portcullis_closed()
	test_walkable_with_open_door_portcullis_open()
	test_blocks_los_solid()
	test_not_blocks_los_open()
	test_not_blocks_los_portcullis_feature()
	test_not_blocks_los_arrow_slit()
	test_not_blocks_los_window()
	test_blocks_los_closed_door()
	test_not_blocks_los_portcullis_door()
	test_blocks_flight_solid()
	test_blocks_flight_closed_door()
	test_not_blocks_flight_liquid()
	test_not_blocks_flight_open()
	test_blocks_burrow_air()
	test_not_blocks_burrow_solid()
	test_not_blocks_burrow_liquid()
	if not has_failures():
		print("VoxelCell: all tests passed.")


# ---------------------------------------------------------------------------
# Defaults and identity
# ---------------------------------------------------------------------------

func test_default_values() -> void:
	var cell := VoxelCell.new()
	check(cell.col == 0, "default col should be 0")
	check(cell.row == 0, "default row should be 0")
	check(cell.level == 0, "default level should be 0")
	check(cell.solidity == "air", "default solidity should be 'air'")
	check(cell.feature == "open", "default feature should be 'open'")
	check(cell.floor_type == "none", "default floor_type should be 'none'")
	check(cell.door_state == "", "default door_state should be empty")
	check(cell.door_type == "", "default door_type should be empty")
	check(cell.door_detected == false, "default door_detected should be false")
	check(cell.room_id == -1, "default room_id should be -1")
	check(cell.is_corridor == false, "default is_corridor should be false")
	check(cell.zone_index == -1, "default zone_index should be -1")
	check(cell.fog_state == "hidden", "default fog_state should be 'hidden'")
	check(cell.cover_value == 0, "default cover_value should be 0")


func test_pos_property() -> void:
	var cell := VoxelCell.new()
	cell.col = 3
	cell.row = 7
	cell.level = 2
	check(cell.pos == Vector3i(3, 7, 2),
		"pos should be Vector3i(col, row, level), got %s" % str(cell.pos))


# ---------------------------------------------------------------------------
# Serialization
# ---------------------------------------------------------------------------

func test_from_dict_populates_fields() -> void:
	var data := {
		"col": 5, "row": 10, "level": 3,
		"solidity": "solid", "feature": "wall_stone", "floor_type": "stone",
		"door_state": "locked", "door_type": "locked", "door_detected": true,
		"room_id": 4, "is_corridor": true, "zone_index": 2,
		"fog_state": "visible", "cover_value": 2,
	}
	var cell := VoxelCell.from_dict(data)
	check(cell.col == 5, "col from dict")
	check(cell.row == 10, "row from dict")
	check(cell.level == 3, "level from dict")
	check(cell.solidity == "solid", "solidity from dict")
	check(cell.feature == "wall_stone", "feature from dict")
	check(cell.floor_type == "stone", "floor_type from dict")
	check(cell.door_state == "locked", "door_state from dict")
	check(cell.door_type == "locked", "door_type from dict")
	check(cell.door_detected == true, "door_detected from dict")
	check(cell.room_id == 4, "room_id from dict")
	check(cell.is_corridor == true, "is_corridor from dict")
	check(cell.zone_index == 2, "zone_index from dict")
	check(cell.fog_state == "visible", "fog_state from dict")
	check(cell.cover_value == 2, "cover_value from dict")


func test_to_dict_round_trip() -> void:
	var data := {
		"col": 2, "row": 8, "level": 1,
		"solidity": "liquid", "feature": "water_deep", "floor_type": "stone",
		"door_state": "", "door_type": "", "door_detected": false,
		"room_id": 7, "is_corridor": false, "zone_index": 1,
		"fog_state": "explored", "cover_value": 1,
	}
	var cell := VoxelCell.from_dict(data)
	var out := cell.to_dict()
	var cell2 := VoxelCell.from_dict(out)
	check(cell2.col == cell.col, "round-trip col")
	check(cell2.row == cell.row, "round-trip row")
	check(cell2.level == cell.level, "round-trip level")
	check(cell2.solidity == cell.solidity, "round-trip solidity")
	check(cell2.feature == cell.feature, "round-trip feature")
	check(cell2.floor_type == cell.floor_type, "round-trip floor_type")
	check(cell2.door_state == cell.door_state, "round-trip door_state")
	check(cell2.door_type == cell.door_type, "round-trip door_type")
	check(cell2.door_detected == cell.door_detected, "round-trip door_detected")
	check(cell2.room_id == cell.room_id, "round-trip room_id")
	check(cell2.is_corridor == cell.is_corridor, "round-trip is_corridor")
	check(cell2.zone_index == cell.zone_index, "round-trip zone_index")
	check(cell2.fog_state == cell.fog_state, "round-trip fog_state")
	check(cell2.cover_value == cell.cover_value, "round-trip cover_value")


func test_from_dict_defaults() -> void:
	var cell := VoxelCell.from_dict({})
	check(cell.solidity == "air", "empty dict defaults solidity to air")
	check(cell.feature == "open", "empty dict defaults feature to open")
	check(cell.floor_type == "none", "empty dict defaults floor_type to none")
	check(cell.zone_index == -1, "empty dict defaults zone_index to -1")


# ---------------------------------------------------------------------------
# is_passable_by_walker
# ---------------------------------------------------------------------------

func test_passable_open_air() -> void:
	var cell := VoxelCell.new()
	cell.solidity = "air"
	cell.feature = "open"
	check(cell.is_passable_by_walker() == true, "air + open should be passable")


func test_not_passable_solid() -> void:
	var cell := VoxelCell.new()
	cell.solidity = "solid"
	check(cell.is_passable_by_walker() == false, "solid should not be passable")


func test_not_passable_liquid() -> void:
	var cell := VoxelCell.new()
	cell.solidity = "liquid"
	check(cell.is_passable_by_walker() == false, "liquid should not be passable")


func test_not_passable_closed_door() -> void:
	var cell := VoxelCell.new()
	cell.solidity = "air"
	cell.door_state = "closed"
	check(cell.is_passable_by_walker() == false, "closed door should not be passable")


func test_passable_open_door() -> void:
	var cell := VoxelCell.new()
	cell.solidity = "air"
	cell.door_state = "open"
	check(cell.is_passable_by_walker() == true, "open door should be passable")


func test_passable_destroyed_door() -> void:
	var cell := VoxelCell.new()
	cell.solidity = "air"
	cell.door_state = "destroyed"
	check(cell.is_passable_by_walker() == true, "destroyed door should be passable")


# ---------------------------------------------------------------------------
# is_walkable_with_open_door (explore-mode pathfinding)
# ---------------------------------------------------------------------------

func test_walkable_with_open_door_closed_unlocked() -> void:
	var cell := VoxelCell.new()
	cell.solidity = "air"
	cell.door_state = "closed"
	cell.door_type = "unlocked"
	check(cell.is_walkable_with_open_door() == true,
		"closed unlocked door should be walkable in explore mode")


func test_walkable_with_open_door_locked() -> void:
	var cell := VoxelCell.new()
	cell.solidity = "air"
	cell.door_state = "locked"
	cell.door_type = "locked"
	check(cell.is_walkable_with_open_door() == false,
		"locked door should not be walkable")


func test_walkable_with_open_door_stuck() -> void:
	var cell := VoxelCell.new()
	cell.solidity = "air"
	cell.door_state = "stuck"
	cell.door_type = "unlocked"
	check(cell.is_walkable_with_open_door() == false,
		"stuck door should not be walkable")


func test_walkable_with_open_door_open() -> void:
	var cell := VoxelCell.new()
	cell.solidity = "air"
	cell.door_state = "open"
	check(cell.is_walkable_with_open_door() == true,
		"open door should be walkable")


func test_walkable_with_open_door_no_door() -> void:
	var cell := VoxelCell.new()
	cell.solidity = "air"
	check(cell.is_walkable_with_open_door() == true,
		"plain air cell should be walkable")


func test_walkable_with_open_door_undetected_secret() -> void:
	var cell := VoxelCell.new()
	cell.solidity = "air"
	cell.door_state = "closed"
	cell.door_type = "secret"
	cell.door_detected = false
	check(cell.is_walkable_with_open_door() == false,
		"undetected secret door should not be walkable")


func test_walkable_with_open_door_portcullis_closed() -> void:
	var cell := VoxelCell.new()
	cell.solidity = "air"
	cell.door_state = "closed"
	cell.door_type = "portcullis"
	check(cell.is_walkable_with_open_door() == false,
		"closed portcullis should not be walkable (needs lever)")


func test_walkable_with_open_door_portcullis_open() -> void:
	var cell := VoxelCell.new()
	cell.solidity = "air"
	cell.door_state = "open"
	cell.door_type = "portcullis"
	check(cell.is_walkable_with_open_door() == true,
		"open portcullis should be walkable")


# ---------------------------------------------------------------------------
# blocks_los
# ---------------------------------------------------------------------------

func test_blocks_los_solid() -> void:
	var cell := VoxelCell.new()
	cell.solidity = "solid"
	cell.feature = "rock"
	check(cell.blocks_los() == true, "solid rock should block LOS")


func test_not_blocks_los_open() -> void:
	var cell := VoxelCell.new()
	check(cell.blocks_los() == false, "default air cell should not block LOS")


func test_not_blocks_los_portcullis_feature() -> void:
	var cell := VoxelCell.new()
	cell.solidity = "solid"
	cell.feature = "portcullis"
	check(cell.blocks_los() == false, "solid portcullis feature should not block LOS")


func test_not_blocks_los_arrow_slit() -> void:
	var cell := VoxelCell.new()
	cell.solidity = "solid"
	cell.feature = "arrow_slit"
	check(cell.blocks_los() == false, "arrow_slit should not block LOS")


func test_not_blocks_los_window() -> void:
	var cell := VoxelCell.new()
	cell.solidity = "solid"
	cell.feature = "window"
	check(cell.blocks_los() == false, "window should not block LOS")


func test_blocks_los_closed_door() -> void:
	var cell := VoxelCell.new()
	cell.door_state = "closed"
	cell.door_type = "unlocked"
	check(cell.blocks_los() == true, "closed non-portcullis door should block LOS")


func test_not_blocks_los_portcullis_door() -> void:
	var cell := VoxelCell.new()
	cell.door_state = "closed"
	cell.door_type = "portcullis"
	check(cell.blocks_los() == false, "closed portcullis should not block LOS")


# ---------------------------------------------------------------------------
# blocks_flight
# ---------------------------------------------------------------------------

func test_blocks_flight_solid() -> void:
	var cell := VoxelCell.new()
	cell.solidity = "solid"
	check(cell.blocks_flight() == true, "solid should block flight")


func test_blocks_flight_closed_door() -> void:
	var cell := VoxelCell.new()
	cell.door_state = "stuck"
	check(cell.blocks_flight() == true, "stuck door should block flight")


func test_not_blocks_flight_liquid() -> void:
	var cell := VoxelCell.new()
	cell.solidity = "liquid"
	check(cell.blocks_flight() == false, "liquid should not block flight")


func test_not_blocks_flight_open() -> void:
	var cell := VoxelCell.new()
	check(cell.blocks_flight() == false, "default air cell should not block flight")


# ---------------------------------------------------------------------------
# blocks_burrow
# ---------------------------------------------------------------------------

func test_blocks_burrow_air() -> void:
	var cell := VoxelCell.new()
	cell.solidity = "air"
	check(cell.blocks_burrow() == true, "air should block burrowing")


func test_not_blocks_burrow_solid() -> void:
	var cell := VoxelCell.new()
	cell.solidity = "solid"
	check(cell.blocks_burrow() == false, "solid should not block burrowing")


func test_not_blocks_burrow_liquid() -> void:
	var cell := VoxelCell.new()
	cell.solidity = "liquid"
	check(cell.blocks_burrow() == false, "liquid should not block burrowing")
