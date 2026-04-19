extends "res://tests/test_suite_base.gd"

## Unit tests for VisibilityManager state machine.


func run_all_tests() -> void:
	test_initial_focus_level_zero()
	test_set_focus_level_updates()
	test_set_focus_level_clamps_to_explored()
	test_set_focus_level_clamps_up()
	test_set_focus_level_no_explored_stays()
	test_set_focus_level_no_direction_match_stays()
	test_get_level_visibility_focus()
	test_get_level_visibility_below()
	test_get_level_visibility_dither()
	test_get_level_visibility_hidden()
	test_should_dither()
	test_jump_to_party_leader()
	test_jump_to_party_leader_empty()
	test_update_explored_levels()
	if not has_failures():
		print("VisibilityManager: all tests passed.")


func _make_manager(explored: Array[int] = [0]) -> VisibilityManager:
	var mgr := VisibilityManager.new()
	mgr.explored_levels = explored
	return mgr


func test_initial_focus_level_zero() -> void:
	var mgr := VisibilityManager.new()
	check(mgr.focus_level == 0, "initial focus_level should be 0")


func test_set_focus_level_updates() -> void:
	var mgr := _make_manager([0, 2, 4])
	mgr.set_focus_level(2)
	check(mgr.focus_level == 2, "focus_level should be 2 after set")


func test_set_focus_level_clamps_to_explored() -> void:
	var mgr := _make_manager([0, 2, 4])
	mgr.focus_level = 2
	# Request level 3 (not explored) while going up — should clamp to 4
	mgr.set_focus_level(3)
	check(mgr.focus_level == 4,
		"requesting 3 going up with explored [0,2,4] should clamp to 4, got %d" % mgr.focus_level)


func test_set_focus_level_clamps_up() -> void:
	var mgr := _make_manager([0, 2, 4])
	mgr.focus_level = 2
	# Request level 5 (above all explored) — should stay at 2
	mgr.set_focus_level(5)
	check(mgr.focus_level == 2,
		"requesting 5 with no explored >= 5 should stay at 2, got %d" % mgr.focus_level)


func test_set_focus_level_no_explored_stays() -> void:
	var mgr := VisibilityManager.new()
	mgr.explored_levels = []
	mgr.focus_level = 0
	mgr.set_focus_level(2)
	check(mgr.focus_level == 0,
		"with empty explored_levels, focus should stay at 0")


func test_set_focus_level_no_direction_match_stays() -> void:
	var mgr := _make_manager([0])
	mgr.focus_level = 0
	# Request -1 (below explored) — should stay at 0
	mgr.set_focus_level(-1)
	check(mgr.focus_level == 0,
		"requesting -1 with explored [0] should stay at 0, got %d" % mgr.focus_level)


func test_get_level_visibility_focus() -> void:
	var mgr := _make_manager([0, 2, 4])
	mgr.focus_level = 2
	check(is_equal_approx(mgr.get_level_visibility(2), 1.0),
		"focus level should have visibility 1.0")


func test_get_level_visibility_below() -> void:
	var mgr := _make_manager([0, 2, 4])
	mgr.focus_level = 2
	check(is_equal_approx(mgr.get_level_visibility(0), 0.6),
		"level below focus should have visibility 0.6")


func test_get_level_visibility_dither() -> void:
	var mgr := _make_manager([0, 2, 4])
	mgr.focus_level = 2
	check(is_equal_approx(mgr.get_level_visibility(3), 0.3),
		"focus + 1 should have visibility 0.3")


func test_get_level_visibility_hidden() -> void:
	var mgr := _make_manager([0, 2, 4])
	mgr.focus_level = 2
	check(is_equal_approx(mgr.get_level_visibility(5), 0.0),
		"level > focus+1 should have visibility 0.0")
	check(is_equal_approx(mgr.get_level_visibility(10), 0.0),
		"far level should have visibility 0.0")


func test_should_dither() -> void:
	var mgr := _make_manager([0, 2, 4])
	mgr.focus_level = 2
	check(mgr.should_dither(3) == true, "focus+1 should dither")
	check(mgr.should_dither(2) == false, "focus level should not dither")
	check(mgr.should_dither(0) == false, "below focus should not dither")
	check(mgr.should_dither(4) == false, "focus+2 should not dither")


func test_jump_to_party_leader() -> void:
	var mgr := _make_manager([0, 2, 4])
	mgr.party_positions = [Vector3i(5, 5, 4), Vector3i(3, 3, 0)]
	mgr.jump_to_party_leader()
	check(mgr.focus_level == 4,
		"should jump to leader's level (4), got %d" % mgr.focus_level)


func test_jump_to_party_leader_empty() -> void:
	var mgr := _make_manager([0, 2])
	mgr.focus_level = 0
	mgr.party_positions = []
	mgr.jump_to_party_leader()
	check(mgr.focus_level == 0, "should stay at 0 with empty positions")


func test_update_explored_levels() -> void:
	var map := VoxelMapData.new()
	# Level 0: explored cell
	var c0 := VoxelCell.new()
	c0.fog_state = "explored"
	map.set_cell(Vector3i(0, 0, 0), c0)
	# Level 1: hidden cell (should not count)
	var c1 := VoxelCell.new()
	c1.fog_state = "hidden"
	map.set_cell(Vector3i(0, 0, 1), c1)
	# Level 2: visible cell
	var c2 := VoxelCell.new()
	c2.fog_state = "visible"
	map.set_cell(Vector3i(0, 0, 2), c2)

	var mgr := VisibilityManager.new()
	mgr.update_explored_levels(map)

	check(mgr.explored_levels.size() == 2,
		"should have 2 explored levels, got %d" % mgr.explored_levels.size())
	check(0 in mgr.explored_levels, "level 0 should be explored")
	check(2 in mgr.explored_levels, "level 2 should be explored")
	check(1 not in mgr.explored_levels, "level 1 (hidden only) should not be explored")
