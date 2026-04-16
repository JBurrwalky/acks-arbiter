extends "res://tests/test_suite_base.gd"

## Unit tests for DungeonContextMenuBuilder — verifies correct menu options
## appear for various cell states, door types, entity configurations, and fog.

const Builder := preload("res://engine/subsystems/exploration/dungeon_context_menu_builder.gd")


func run_all_tests() -> void:
	test_empty_selection_returns_empty()
	test_universal_options_always_present()
	test_cancel_always_last_universal()
	test_open_door_on_closed_unlocked()
	test_force_door_on_stuck()
	test_pick_lock_on_locked()
	test_bash_door_on_wooden()
	test_bash_door_disabled_on_iron()
	test_close_door_on_open()
	test_stairs_up_produces_ascend()
	test_stairs_down_produces_descend()
	test_transition_cell_produces_exit()
	test_hidden_fog_only_universal()
	test_self_click_produces_self_options()
	test_door_material_defaults()
	test_is_evil_door_accessor()
	if not has_failures():
		print("ContextMenuBuilder: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Build a minimal TacticalMapData with specific cells for testing.
func _make_map(cells: Array) -> TacticalMapData:
	var data := {
		"grid_width": 20,
		"grid_height": 16,
		"entry_col": 2,
		"entry_row": 2,
		"cells": cells,
		"transition_cells": [],
	}
	return TacticalMapData.from_dict(data)


func _make_map_with_transitions(cells: Array, transitions: Array) -> TacticalMapData:
	var data := {
		"grid_width": 20,
		"grid_height": 16,
		"entry_col": 2,
		"entry_row": 2,
		"cells": cells,
		"transition_cells": transitions,
	}
	return TacticalMapData.from_dict(data)


func _find_option(options: Array, id: String) -> Dictionary:
	for opt in options:
		if opt.get("id") == id:
			return opt
	return {}


func _has_option(options: Array, id: String) -> bool:
	return not _find_option(options, id).is_empty()


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_empty_selection_returns_empty() -> void:
	var map := _make_map([{"col": 5, "row": 5, "terrain_feature": "open"}])
	map.set_fog(Vector2i(5, 5), TacticalMapData.FogState.VISIBLE)
	var result := Builder.build_menu([], Vector2i(5, 5), map, null, null)
	check(result.is_empty(), "empty selection should return no options")
	print("  empty_selection_returns_empty: OK")


func test_universal_options_always_present() -> void:
	var map := _make_map([{"col": 5, "row": 5, "terrain_feature": "open"}])
	map.set_fog(Vector2i(5, 5), TacticalMapData.FogState.VISIBLE)
	var result := Builder.build_menu(["hero"], Vector2i(5, 5), map, null, null)
	check(_has_option(result, "move_here"), "Move Here should be present")
	check(_has_option(result, "search_here"), "Search Here should be present")
	check(_has_option(result, "listen_here"), "Listen Here should be present")
	check(_has_option(result, "cancel"), "Cancel should be present")
	print("  universal_options_always_present: OK")


func test_cancel_always_last_universal() -> void:
	var map := _make_map([{"col": 5, "row": 5, "terrain_feature": "open"}])
	map.set_fog(Vector2i(5, 5), TacticalMapData.FogState.VISIBLE)
	var result := Builder.build_menu(["hero"], Vector2i(5, 5), map, null, null)
	# Cancel should be the last universal option (index 3).
	var universals: Array = []
	for opt in result:
		if opt.get("category") == "universal":
			universals.append(opt)
	check(universals.size() >= 4, "at least 4 universal options")
	check(universals[-1].get("id") == "cancel", "cancel should be last universal")
	print("  cancel_always_last_universal: OK")


func test_open_door_on_closed_unlocked() -> void:
	var map := _make_map([{
		"col": 5, "row": 5,
		"terrain_feature": "door",
		"door_type": "unlocked",
		"door_state": "closed",
	}])
	map.set_fog(Vector2i(5, 5), TacticalMapData.FogState.VISIBLE)
	var result := Builder.build_menu(["hero"], Vector2i(5, 5), map, null, null)
	check(_has_option(result, "open_door"), "Open Door should be present for closed unlocked door")
	check(not _has_option(result, "force_door"), "Force Door should not be present")
	check(not _has_option(result, "pick_lock"), "Pick Lock should not be present")
	print("  open_door_on_closed_unlocked: OK")


func test_force_door_on_stuck() -> void:
	var map := _make_map([{
		"col": 5, "row": 5,
		"terrain_feature": "door",
		"door_type": "unlocked",
		"door_state": "stuck",
	}])
	map.set_fog(Vector2i(5, 5), TacticalMapData.FogState.VISIBLE)
	var result := Builder.build_menu(["hero"], Vector2i(5, 5), map, null, null)
	check(_has_option(result, "force_door"), "Force Door should be present for stuck door")
	check(not _has_option(result, "open_door"), "Open Door should not be present on stuck")
	print("  force_door_on_stuck: OK")


func test_pick_lock_on_locked() -> void:
	var map := _make_map([{
		"col": 5, "row": 5,
		"terrain_feature": "door_locked",
		"door_type": "locked",
		"door_state": "locked",
	}])
	map.set_fog(Vector2i(5, 5), TacticalMapData.FogState.VISIBLE)
	# Without party_data, pick lock should be disabled.
	var result := Builder.build_menu(["hero"], Vector2i(5, 5), map, null, null)
	var pick := _find_option(result, "pick_lock")
	check(not pick.is_empty(), "Pick Lock option should appear on locked door")
	check(not pick.get("enabled", true), "Pick Lock should be disabled without thief")
	check(_has_option(result, "unlock_door"), "Unlock option should appear")
	print("  pick_lock_on_locked: OK")


func test_bash_door_on_wooden() -> void:
	var map := _make_map([{
		"col": 5, "row": 5,
		"terrain_feature": "door",
		"door_type": "unlocked",
		"door_state": "closed",
		"door_material": "wood_simple",
	}])
	map.set_fog(Vector2i(5, 5), TacticalMapData.FogState.VISIBLE)
	var result := Builder.build_menu(["hero"], Vector2i(5, 5), map, null, null)
	var bash := _find_option(result, "bash_door")
	check(not bash.is_empty(), "Bash Door should appear on wooden door")
	check(bash.get("enabled", false), "Bash Door should be enabled on wooden")
	# Verify turns in action_data.
	check(bash.get("action_data", {}).get("turns", 0) == 1, "simple wood bash should take 1 turn")
	print("  bash_door_on_wooden: OK")


func test_bash_door_disabled_on_iron() -> void:
	var map := _make_map([{
		"col": 5, "row": 5,
		"terrain_feature": "door",
		"door_type": "unlocked",
		"door_state": "closed",
		"door_material": "iron",
	}])
	map.set_fog(Vector2i(5, 5), TacticalMapData.FogState.VISIBLE)
	var result := Builder.build_menu(["hero"], Vector2i(5, 5), map, null, null)
	var bash := _find_option(result, "bash_door")
	check(not bash.is_empty(), "Bash Door option should still appear (greyed)")
	check(not bash.get("enabled", true), "Bash Door should be disabled on iron door")
	print("  bash_door_disabled_on_iron: OK")


func test_close_door_on_open() -> void:
	var map := _make_map([{
		"col": 5, "row": 5,
		"terrain_feature": "door",
		"door_type": "unlocked",
		"door_state": "open",
	}])
	map.set_fog(Vector2i(5, 5), TacticalMapData.FogState.VISIBLE)
	var result := Builder.build_menu(["hero"], Vector2i(5, 5), map, null, null)
	check(_has_option(result, "close_door"), "Close Door should appear on open door")
	check(_has_option(result, "wedge_open"), "Wedge Open should appear on open door")
	check(not _has_option(result, "open_door"), "Open Door should not appear on open door")
	print("  close_door_on_open: OK")


func test_stairs_up_produces_ascend() -> void:
	var map := _make_map([{
		"col": 5, "row": 5,
		"terrain_feature": "stairs_up",
	}])
	map.set_fog(Vector2i(5, 5), TacticalMapData.FogState.VISIBLE)
	var result := Builder.build_menu(["hero"], Vector2i(5, 5), map, null, null)
	check(_has_option(result, "ascend"), "Ascend should appear on stairs_up")
	check(not _has_option(result, "descend"), "Descend should not appear on stairs_up")
	print("  stairs_up_produces_ascend: OK")


func test_stairs_down_produces_descend() -> void:
	var map := _make_map([{
		"col": 5, "row": 5,
		"terrain_feature": "stairs_down",
	}])
	map.set_fog(Vector2i(5, 5), TacticalMapData.FogState.VISIBLE)
	var result := Builder.build_menu(["hero"], Vector2i(5, 5), map, null, null)
	check(_has_option(result, "descend"), "Descend should appear on stairs_down")
	print("  stairs_down_produces_descend: OK")


func test_transition_cell_produces_exit() -> void:
	var map := _make_map_with_transitions(
		[{"col": 2, "row": 2, "terrain_feature": "stairs_up"}],
		[{"col": 2, "row": 2, "label": "Main Entrance"}],
	)
	map.set_fog(Vector2i(2, 2), TacticalMapData.FogState.VISIBLE)
	# Entity must be ON the transition cell for Exit Dungeon to appear.
	map.set_entity_pos("hero", Vector2i(2, 2))
	var result := Builder.build_menu(["hero"], Vector2i(2, 2), map, null, null)
	check(_has_option(result, "exit_dungeon"), "Exit Dungeon should appear on transition cell")
	# Should NOT also show Ascend (exit takes priority on transition cells).
	check(not _has_option(result, "ascend"), "Ascend should not appear when exit is available")
	print("  transition_cell_produces_exit: OK")


func test_hidden_fog_only_universal() -> void:
	var map := _make_map([{
		"col": 5, "row": 5,
		"terrain_feature": "door",
		"door_type": "unlocked",
		"door_state": "closed",
	}])
	# Default fog is HIDDEN.
	var result := Builder.build_menu(["hero"], Vector2i(5, 5), map, null, null)
	# Should have universal options only (no door options).
	check(_has_option(result, "move_here"), "Move Here should be present even in hidden fog")
	check(not _has_option(result, "open_door"), "Open Door should not appear in hidden fog")
	print("  hidden_fog_only_universal: OK")


func test_self_click_produces_self_options() -> void:
	var map := _make_map([{"col": 5, "row": 5, "terrain_feature": "open"}])
	map.set_fog(Vector2i(5, 5), TacticalMapData.FogState.VISIBLE)
	map.set_entity_pos("hero", Vector2i(5, 5))
	var result := Builder.build_menu(["hero"], Vector2i(5, 5), map, null, null)
	check(_has_option(result, "light_torch"), "Light Torch should appear on self-click")
	check(_has_option(result, "light_lantern"), "Light Lantern should appear on self-click")
	check(_has_option(result, "set_idle_behavior"), "Set Idle Behavior should appear on self-click")
	check(_has_option(result, "drop_item"), "Drop Item should appear on self-click")
	print("  self_click_produces_self_options: OK")


func test_door_material_defaults() -> void:
	var map := _make_map([{
		"col": 5, "row": 5,
		"terrain_feature": "door",
		"door_type": "unlocked",
		"door_state": "closed",
		# No door_material specified — should default to wood_standard.
	}])
	var material := map.get_door_material(Vector2i(5, 5))
	check(material == "wood_standard", "default door_material should be wood_standard, got '%s'" % material)
	print("  door_material_defaults: OK")


func test_is_evil_door_accessor() -> void:
	var map := _make_map([
		{"col": 5, "row": 5, "terrain_feature": "door", "is_evil": true},
		{"col": 6, "row": 5, "terrain_feature": "door"},
	])
	check(map.is_evil_door(Vector2i(5, 5)), "cell (5,5) should be evil door")
	check(not map.is_evil_door(Vector2i(6, 5)), "cell (6,5) should not be evil door (default false)")
	check(not map.is_evil_door(Vector2i(99, 99)), "non-existent cell should return false")
	print("  is_evil_door_accessor: OK")
