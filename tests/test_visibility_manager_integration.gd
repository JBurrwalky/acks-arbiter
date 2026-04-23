extends "res://tests/test_suite_base.gd"

## Session 8 integration tests for VisibilityManager additions:
## free_camera bypass, cycle_next_party_member, request_auto_focus, and the
## level-visibility matrix parameterized over every relative level.


func run_all_tests() -> void:
	test_set_focus_level_clamps_up_to_nearest_explored()
	test_set_focus_level_clamps_down_to_nearest_explored()
	test_set_focus_level_exact_match_no_clamp()
	test_set_focus_level_empty_explored_is_noop()
	test_free_camera_bypasses_clamp()
	test_jump_to_party_leader_sets_focus_to_leader_z()
	test_jump_to_party_leader_empty_party_noop()
	test_cycle_next_party_member_advances_index()
	test_cycle_next_party_member_wraps()
	test_request_auto_focus_emits_signal_and_updates_focus()
	test_should_dither_only_focus_plus_one()
	test_get_level_visibility_matrix()
	if not has_failures():
		print("VisibilityManagerIntegration: all tests passed.")


func _make_manager(explored: Array[int] = [0]) -> VisibilityManager:
	var mgr := VisibilityManager.new()
	mgr.explored_levels = explored
	return mgr


# ---------------------------------------------------------------------------
# set_focus_level clamping
# ---------------------------------------------------------------------------

func test_set_focus_level_clamps_up_to_nearest_explored() -> void:
	var mgr := _make_manager([0, 2, 6])
	mgr.focus_level = 0
	mgr.set_focus_level(3)
	check(mgr.focus_level == 6,
		"requesting 3 going up with [0,2,6] should clamp to 6, got %d" % mgr.focus_level)


func test_set_focus_level_clamps_down_to_nearest_explored() -> void:
	var mgr := _make_manager([0, 2, 6])
	mgr.focus_level = 6
	mgr.set_focus_level(3)
	check(mgr.focus_level == 2,
		"requesting 3 going down from 6 with [0,2,6] should clamp to 2, got %d" % mgr.focus_level)


func test_set_focus_level_exact_match_no_clamp() -> void:
	var mgr := _make_manager([0, 2, 4])
	mgr.focus_level = 0
	mgr.set_focus_level(4)
	check(mgr.focus_level == 4,
		"requesting exact-match level should bypass clamp, got %d" % mgr.focus_level)


func test_set_focus_level_empty_explored_is_noop() -> void:
	var mgr := VisibilityManager.new()
	mgr.explored_levels = []
	mgr.focus_level = 0
	mgr.set_focus_level(5)
	check(mgr.focus_level == 0,
		"empty explored_levels should leave focus unchanged")


# ---------------------------------------------------------------------------
# free_camera bypass
# ---------------------------------------------------------------------------

func test_free_camera_bypasses_clamp() -> void:
	var mgr := _make_manager([0, 2])
	mgr.focus_level = 0
	mgr.set_free_camera(true)
	mgr.set_focus_level(99)
	check(mgr.focus_level == 99,
		"free_camera=true should allow unclamped focus, got %d" % mgr.focus_level)
	mgr.set_free_camera(false)
	# Re-enable clamp. Requesting 150 while at 99 goes up, no explored >= 150,
	# so focus stays at 99.
	mgr.set_focus_level(150)
	check(mgr.focus_level == 99,
		"with clamp re-enabled and no explored >= 150, focus stays at 99, got %d" % mgr.focus_level)


# ---------------------------------------------------------------------------
# jump_to_party_leader
# ---------------------------------------------------------------------------

func test_jump_to_party_leader_sets_focus_to_leader_z() -> void:
	var mgr := _make_manager([0, 2, 4])
	mgr.party_positions = [Vector3i(1, 1, 4), Vector3i(0, 0, 0)]
	mgr.focus_level = 0
	mgr.jump_to_party_leader()
	check(mgr.focus_level == 4,
		"leader at z=4 should focus level 4, got %d" % mgr.focus_level)


func test_jump_to_party_leader_empty_party_noop() -> void:
	var mgr := _make_manager([0, 2])
	mgr.focus_level = 2
	mgr.party_positions = []
	mgr.jump_to_party_leader()
	check(mgr.focus_level == 2,
		"empty party should leave focus at 2, got %d" % mgr.focus_level)


# ---------------------------------------------------------------------------
# cycle_next_party_member
# ---------------------------------------------------------------------------

func test_cycle_next_party_member_advances_index() -> void:
	var mgr := _make_manager([0, 2, 4])
	mgr.party_positions = [
		Vector3i(0, 0, 0),
		Vector3i(1, 1, 2),
		Vector3i(2, 2, 4),
	]
	mgr.focus_level = 0
	var idx1 := mgr.cycle_next_party_member()
	check(idx1 == 1, "first cycle should advance to index 1, got %d" % idx1)
	check(mgr.focus_level == 2,
		"focus should follow member at index 1 (z=2), got %d" % mgr.focus_level)
	var idx2 := mgr.cycle_next_party_member()
	check(idx2 == 2, "second cycle should advance to index 2, got %d" % idx2)
	check(mgr.focus_level == 4,
		"focus should follow member at index 2 (z=4), got %d" % mgr.focus_level)


func test_cycle_next_party_member_wraps() -> void:
	var mgr := _make_manager([0, 2])
	mgr.party_positions = [Vector3i(0, 0, 0), Vector3i(1, 1, 2)]
	mgr.focus_level = 0
	var _a := mgr.cycle_next_party_member()  # -> idx 1, z=2
	var idx := mgr.cycle_next_party_member()  # wraps -> idx 0, z=0
	check(idx == 0, "cycle should wrap to 0, got %d" % idx)
	check(mgr.focus_level == 0,
		"focus should follow wrap to z=0, got %d" % mgr.focus_level)


# ---------------------------------------------------------------------------
# request_auto_focus
# ---------------------------------------------------------------------------

func test_request_auto_focus_emits_signal_and_updates_focus() -> void:
	var mgr := _make_manager([0])
	mgr.focus_level = 0
	var captured := {"level": -1, "reason": ""}
	mgr.auto_focus_requested.connect(func(lvl: int, reason: String) -> void:
		captured["level"] = lvl
		captured["reason"] = reason
	)
	mgr.request_auto_focus(4, "encounter")
	check(captured["level"] == 4,
		"auto_focus_requested signal should carry level=4, got %d" % captured["level"])
	check(captured["reason"] == "encounter",
		"auto_focus_requested signal should carry reason, got %s" % str(captured["reason"]))
	check(mgr.focus_level == 4,
		"focus should update to requested level even when unexplored, got %d" % mgr.focus_level)


# ---------------------------------------------------------------------------
# Visibility matrix — should_dither + get_level_visibility
# ---------------------------------------------------------------------------

func test_should_dither_only_focus_plus_one() -> void:
	var mgr := _make_manager([0, 2, 4])
	mgr.focus_level = 2
	check(mgr.should_dither(3) == true, "focus+1 (3) dithers")
	check(mgr.should_dither(2) == false, "focus level does not dither")
	check(mgr.should_dither(0) == false, "below focus does not dither")
	check(mgr.should_dither(4) == false, "focus+2 does not dither")
	check(mgr.should_dither(-1) == false, "far below does not dither")


func test_get_level_visibility_matrix() -> void:
	# explored = [0, 2, 4], focus = 2
	# Expected: 0 → VIS_BELOW(0.6), 2 → VIS_FOCUS(1.0), 3 → VIS_DITHER(0.3),
	#           4 → VIS_HIDDEN(0.0) (above focus+1), -1 → hidden (not explored).
	var mgr := _make_manager([0, 2, 4])
	mgr.focus_level = 2

	check(is_equal_approx(mgr.get_level_visibility(0), VisibilityManager.VIS_BELOW),
		"level 0 (below, explored) = VIS_BELOW")
	check(is_equal_approx(mgr.get_level_visibility(2), VisibilityManager.VIS_FOCUS),
		"level 2 (focus) = VIS_FOCUS")
	check(is_equal_approx(mgr.get_level_visibility(3), VisibilityManager.VIS_DITHER),
		"level 3 (focus+1) = VIS_DITHER")
	check(is_equal_approx(mgr.get_level_visibility(4), VisibilityManager.VIS_HIDDEN),
		"level 4 (above focus+1) = VIS_HIDDEN")
	check(is_equal_approx(mgr.get_level_visibility(-1), VisibilityManager.VIS_HIDDEN),
		"level -1 (not explored) = VIS_HIDDEN")
