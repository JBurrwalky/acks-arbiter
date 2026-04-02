extends "res://tests/test_suite_base.gd"

## Unit tests for DungeonMapController.
##
## Each test creates a fresh DungeonMapController Node, adds it to the scene
## tree (required for signals to work), loads a minimal dungeon dict, and
## exercises the controller's public API.


# ---------------------------------------------------------------------------
# Minimal dungeon data
# ---------------------------------------------------------------------------

## Builds a minimal two-room dungeon dict for testing.
## Layout:
##   Room A: open cells (0,0),(1,0),(2,0)
##   Door (unlocked, closed): (3,0)
##   Corridor: (4,0)
##   Room B: open cells (5,0),(6,0),(7,0)
##   Wall boundary: row=-1 is void (not listed)
##   Stairs down at (7,0) → level 2
##   Level 2: stairs_up at (0,0), open (1,0),(2,0)
func _dungeon_dict() -> Dictionary:
	var cells_l1 := [
		{"col": 0, "row": 0, "terrain_feature": "open"},
		{"col": 1, "row": 0, "terrain_feature": "open"},
		{"col": 2, "row": 0, "terrain_feature": "open"},
		{"col": 3, "row": 0, "terrain_feature": "door",
			"door_type": "unlocked", "door_state": "closed"},
		{"col": 4, "row": 0, "terrain_feature": "open"},
		{"col": 5, "row": 0, "terrain_feature": "open"},
		{"col": 6, "row": 0, "terrain_feature": "open"},
		{"col": 7, "row": 0, "terrain_feature": "stairs_down"},
		{"col": 0, "row": 1, "terrain_feature": "wall_stone"},
		{"col": 1, "row": 1, "terrain_feature": "wall_stone"},
		{"col": 2, "row": 1, "terrain_feature": "wall_stone"},
		{"col": 3, "row": 1, "terrain_feature": "wall_stone"},
		{"col": 4, "row": 1, "terrain_feature": "wall_stone"},
		{"col": 5, "row": 1, "terrain_feature": "wall_stone"},
		{"col": 6, "row": 1, "terrain_feature": "wall_stone"},
		{"col": 7, "row": 1, "terrain_feature": "wall_stone"},
		{"col": 0, "row": -1, "terrain_feature": "wall_stone"},
		{"col": 1, "row": -1, "terrain_feature": "wall_stone"},
		{"col": 2, "row": -1, "terrain_feature": "wall_stone"},
		{"col": 3, "row": -1, "terrain_feature": "wall_stone"},
		{"col": 4, "row": -1, "terrain_feature": "wall_stone"},
		{"col": 5, "row": -1, "terrain_feature": "wall_stone"},
		{"col": 6, "row": -1, "terrain_feature": "wall_stone"},
		{"col": 7, "row": -1, "terrain_feature": "wall_stone"},
	]

	var cells_l2 := [
		{"col": 0, "row": 0, "terrain_feature": "stairs_up"},
		{"col": 1, "row": 0, "terrain_feature": "open"},
		{"col": 2, "row": 0, "terrain_feature": "open"},
	]

	return {
		"id": "test_dungeon_ctrl",
		"name": "Controller Test Dungeon",
		"levels": [
			{
				"level": 1,
				"grid_width": 8,
				"grid_height": 3,
				"entry_col": 0,
				"entry_row": 0,
				"cells": cells_l1,
			},
			{
				"level": 2,
				"grid_width": 3,
				"grid_height": 1,
				"entry_col": 0,
				"entry_row": 0,
				"cells": cells_l2,
			},
		],
		"stairs": [
			{"from_level": 1, "from_col": 7, "from_row": 0,
				"to_level": 2, "to_col": 0, "to_row": 0},
			{"from_level": 2, "from_col": 0, "from_row": 0,
				"to_level": 1, "to_col": 7, "to_row": 0},
		],
	}


## Creates a fresh controller, loads the dungeon, adds a party member.
## Returns the controller (caller must queue_free when done).
func _make_controller() -> DungeonMapController:
	var ctrl := DungeonMapController.new()
	add_child(ctrl)
	ctrl.add_party_member("hero")
	ctrl.load_dungeon(_dungeon_dict())
	return ctrl


# ---------------------------------------------------------------------------
# Test runner
# ---------------------------------------------------------------------------

func run_all_tests() -> void:
	test_load_positions_party_at_entry()
	test_load_reveals_entry_room()
	test_move_to_adjacent_floor()
	test_move_non_adjacent_fails()
	test_move_to_wall_fails()
	test_move_through_closed_door_fails()
	test_move_through_open_door_succeeds()
	test_interact_door_open_close()
	test_interact_locked_door_blocked()
	test_room_reveal_on_entry()
	test_fog_explored_on_leave()
	test_signals_emitted_on_move()
	test_use_stairs_transitions_level()
	test_use_stairs_positions_party_at_target()
	test_level_changed_signal()
	test_fog_preserved_across_levels()
	if not has_failures():
		print("DungeonMapController: all tests passed.")


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_load_positions_party_at_entry() -> void:
	var ctrl := _make_controller()
	var pos := ctrl.get_party_position()
	check(pos == Vector2i(0, 0),
		"party should be at entry (0,0) after load, got %s" % str(pos))
	ctrl.queue_free()


func test_load_reveals_entry_room() -> void:
	var ctrl := _make_controller()
	var map := ctrl.get_map()
	# Entry is (0,0) which is in room A (open cells 0-2, row 0)
	# All cells in that room should be VISIBLE
	check(map.get_fog(Vector2i(0, 0)) == TacticalMapData.FogState.VISIBLE,
		"entry cell (0,0) should be VISIBLE after load")
	check(map.get_fog(Vector2i(1, 0)) == TacticalMapData.FogState.VISIBLE,
		"cell (1,0) in entry room should be VISIBLE after load")
	ctrl.queue_free()


func test_move_to_adjacent_floor() -> void:
	var ctrl := _make_controller()
	var result := ctrl.move_party(Vector2i(1, 0))
	check(result, "move to adjacent open cell (1,0) should succeed")
	check(ctrl.get_party_position() == Vector2i(1, 0),
		"party position should be (1,0) after successful move")
	ctrl.queue_free()


func test_move_non_adjacent_fails() -> void:
	var ctrl := _make_controller()
	var result := ctrl.move_party(Vector2i(5, 0))
	check(not result, "move to non-adjacent cell (5,0) should fail")
	check(ctrl.get_party_position() == Vector2i(0, 0),
		"party position should remain at (0,0) after failed move")
	ctrl.queue_free()


func test_move_to_wall_fails() -> void:
	var ctrl := _make_controller()
	var result := ctrl.move_party(Vector2i(0, 1))
	check(not result, "move to wall_stone at (0,1) should fail")
	ctrl.queue_free()


func test_move_through_closed_door_fails() -> void:
	var ctrl := _make_controller()
	# Move from (0,0) to (1,0) to (2,0) to try door at (3,0)
	ctrl.move_party(Vector2i(1, 0))
	ctrl.move_party(Vector2i(2, 0))
	var result := ctrl.move_party(Vector2i(3, 0))
	check(not result, "move through closed door at (3,0) should fail")
	ctrl.queue_free()


func test_move_through_open_door_succeeds() -> void:
	var ctrl := _make_controller()
	# Open the door first
	var map := ctrl.get_map()
	map.set_door_state(Vector2i(3, 0), "open")
	# Move up to the door
	ctrl.move_party(Vector2i(1, 0))
	ctrl.move_party(Vector2i(2, 0))
	var result := ctrl.move_party(Vector2i(3, 0))
	check(result, "move through open door should succeed")
	ctrl.queue_free()


func test_interact_door_open_close() -> void:
	var ctrl := _make_controller()
	# Move adjacent to door at (3,0): need to be at (2,0)
	ctrl.move_party(Vector2i(1, 0))
	ctrl.move_party(Vector2i(2, 0))

	# Open the door
	var result_open := ctrl.interact_door(Vector2i(3, 0))
	check(result_open, "interact_door on closed unlocked door should return true")
	check(ctrl.get_map().get_door_state(Vector2i(3, 0)) == "open",
		"door should be open after interact")

	# Close the door again
	var result_close := ctrl.interact_door(Vector2i(3, 0))
	check(result_close, "interact_door on open door should return true (close it)")
	check(ctrl.get_map().get_door_state(Vector2i(3, 0)) == "closed",
		"door should be closed after second interact")
	ctrl.queue_free()


func test_interact_locked_door_blocked() -> void:
	# Build a map with a locked door
	var cells := [
		{"col": 0, "row": 0, "terrain_feature": "open"},
		{"col": 1, "row": 0, "terrain_feature": "door_locked",
			"door_type": "locked", "door_state": "locked"},
	]
	var d := {
		"id": "locked_test", "name": "Locked Test",
		"levels": [{"level": 1, "grid_width": 2, "grid_height": 1,
			"entry_col": 0, "entry_row": 0, "cells": cells}],
		"stairs": []
	}
	var ctrl := DungeonMapController.new()
	add_child(ctrl)
	ctrl.add_party_member("hero")
	ctrl.load_dungeon(d)

	var result := ctrl.interact_door(Vector2i(1, 0))
	check(not result, "interact_door on locked door should return false")
	ctrl.queue_free()


func test_room_reveal_on_entry() -> void:
	var ctrl := _make_controller()
	var map := ctrl.get_map()

	# Entry room (room A: cells 0-2 row 0) should be revealed on load
	check(map.get_fog(Vector2i(0, 0)) == TacticalMapData.FogState.VISIBLE,
		"(0,0) in room A should be VISIBLE after entering")

	# Room B (cells 4-7 row 0) should still be hidden
	check(map.get_fog(Vector2i(6, 0)) == TacticalMapData.FogState.HIDDEN,
		"(6,0) in room B should still be HIDDEN before party enters")

	# Open the door and move to room B
	map.set_door_state(Vector2i(3, 0), "open")
	ctrl.move_party(Vector2i(1, 0))
	ctrl.move_party(Vector2i(2, 0))
	ctrl.move_party(Vector2i(3, 0))
	ctrl.move_party(Vector2i(4, 0))
	ctrl.move_party(Vector2i(5, 0))

	# Room B cells should now be visible
	check(map.get_fog(Vector2i(5, 0)) == TacticalMapData.FogState.VISIBLE,
		"(5,0) in room B should be VISIBLE after party enters")
	check(map.get_fog(Vector2i(6, 0)) == TacticalMapData.FogState.VISIBLE,
		"(6,0) in room B should be VISIBLE after party enters")
	ctrl.queue_free()


func test_fog_explored_on_leave() -> void:
	var ctrl := _make_controller()
	var map := ctrl.get_map()

	# Room A is visible (entry room revealed)
	check(map.get_fog(Vector2i(0, 0)) == TacticalMapData.FogState.VISIBLE,
		"room A should start VISIBLE")

	# Open door and cross into room B
	map.set_door_state(Vector2i(3, 0), "open")
	ctrl.move_party(Vector2i(1, 0))
	ctrl.move_party(Vector2i(2, 0))
	ctrl.move_party(Vector2i(3, 0))
	ctrl.move_party(Vector2i(4, 0))
	ctrl.move_party(Vector2i(5, 0))

	# Room A cells should now be EXPLORED (party left)
	check(map.get_fog(Vector2i(0, 0)) == TacticalMapData.FogState.EXPLORED,
		"room A cell (0,0) should be EXPLORED after party leaves")
	check(map.get_fog(Vector2i(1, 0)) == TacticalMapData.FogState.EXPLORED,
		"room A cell (1,0) should be EXPLORED after party leaves")
	ctrl.queue_free()


func test_signals_emitted_on_move() -> void:
	var ctrl := _make_controller()

	var moved_from := Vector2i(-1, -1)
	var moved_to := Vector2i(-1, -1)
	ctrl.party_moved.connect(func(from: Vector2i, to: Vector2i) -> void:
		moved_from = from
		moved_to = to
	)

	ctrl.move_party(Vector2i(1, 0))
	check(moved_from == Vector2i(0, 0), "party_moved from should be (0,0)")
	check(moved_to == Vector2i(1, 0), "party_moved to should be (1,0)")
	ctrl.queue_free()


func test_use_stairs_transitions_level() -> void:
	var ctrl := _make_controller()
	# Move party to stairs at (7,0)
	var map := ctrl.get_map()
	map.set_door_state(Vector2i(3, 0), "open")
	ctrl.move_party(Vector2i(1, 0))
	ctrl.move_party(Vector2i(2, 0))
	ctrl.move_party(Vector2i(3, 0))
	ctrl.move_party(Vector2i(4, 0))
	ctrl.move_party(Vector2i(5, 0))
	ctrl.move_party(Vector2i(6, 0))
	ctrl.move_party(Vector2i(7, 0))

	check(ctrl.get_current_level() == 1, "should still be on level 1 before using stairs")

	var result := ctrl.use_stairs(Vector2i(7, 0))
	check(result, "use_stairs on valid stairs_down should return true")
	check(ctrl.get_current_level() == 2, "level should be 2 after using stairs down")
	ctrl.queue_free()


func test_use_stairs_positions_party_at_target() -> void:
	var ctrl := _make_controller()
	var map := ctrl.get_map()
	map.set_door_state(Vector2i(3, 0), "open")
	ctrl.move_party(Vector2i(1, 0))
	ctrl.move_party(Vector2i(2, 0))
	ctrl.move_party(Vector2i(3, 0))
	ctrl.move_party(Vector2i(4, 0))
	ctrl.move_party(Vector2i(5, 0))
	ctrl.move_party(Vector2i(6, 0))
	ctrl.move_party(Vector2i(7, 0))
	ctrl.use_stairs(Vector2i(7, 0))

	var pos := ctrl.get_party_position()
	check(pos == Vector2i(0, 0),
		"after stairs down, party should be at (0,0) on level 2, got %s" % str(pos))
	ctrl.queue_free()


func test_level_changed_signal() -> void:
	var ctrl := _make_controller()
	var map := ctrl.get_map()
	map.set_door_state(Vector2i(3, 0), "open")
	ctrl.move_party(Vector2i(1, 0))
	ctrl.move_party(Vector2i(2, 0))
	ctrl.move_party(Vector2i(3, 0))
	ctrl.move_party(Vector2i(4, 0))
	ctrl.move_party(Vector2i(5, 0))
	ctrl.move_party(Vector2i(6, 0))
	ctrl.move_party(Vector2i(7, 0))

	var from_l := -1
	var to_l := -1
	ctrl.level_changed.connect(func(from: int, to: int) -> void:
		from_l = from
		to_l = to
	)

	ctrl.use_stairs(Vector2i(7, 0))
	check(from_l == 1, "level_changed from should be 1, got %d" % from_l)
	check(to_l == 2, "level_changed to should be 2, got %d" % to_l)
	ctrl.queue_free()


func test_fog_preserved_across_levels() -> void:
	var ctrl := _make_controller()
	var map_l1 := ctrl.get_map()

	# Room A on level 1 is revealed on load
	check(map_l1.get_fog(Vector2i(1, 0)) == TacticalMapData.FogState.VISIBLE,
		"room A cell should be VISIBLE before going to level 2")

	# Go to level 2
	var map := ctrl.get_map()
	map.set_door_state(Vector2i(3, 0), "open")
	ctrl.move_party(Vector2i(1, 0))
	ctrl.move_party(Vector2i(2, 0))
	ctrl.move_party(Vector2i(3, 0))
	ctrl.move_party(Vector2i(4, 0))
	ctrl.move_party(Vector2i(5, 0))
	ctrl.move_party(Vector2i(6, 0))
	ctrl.move_party(Vector2i(7, 0))
	ctrl.use_stairs(Vector2i(7, 0))

	# Come back to level 1
	ctrl.use_stairs(Vector2i(0, 0))

	# Level 1 fog should be preserved (room A was VISIBLE/EXPLORED, not reset to HIDDEN)
	var map_l1_again := ctrl.get_map()
	var fog_val := map_l1_again.get_fog(Vector2i(1, 0))
	check(fog_val != TacticalMapData.FogState.HIDDEN,
		"room A fog should be preserved after returning from level 2, got %d" % fog_val)
	ctrl.queue_free()
