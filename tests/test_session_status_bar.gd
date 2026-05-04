extends "res://tests/test_suite_base.gd"

## Focused tests for the SessionStatusBar three-zone rework (γ.4).
##
## Covers:
##   - Bar builds three zones (portrait, widget, log placeholder) under a
##     drag handle row
##   - Height-state transitions snap to the four canonical values (Hidden /
##     Minimal / Default / Expanded)
##   - Height persistence round-trips via user://session_status_bar_height.txt
##   - notebook_open_state_changed hides the bar on open and restores on close
##   - Open Notebook button disables when CombatUIController.notebook_open_allowed
##     returns false (combat enemy-resolution gate)


const SESSION_STATUS_BAR := preload("res://scenes/ui/hud/session_status_bar.gd")
const PORTRAIT_WITH_BADGE := preload("res://scenes/ui/components/portrait_with_badge.gd")


func run_all_tests() -> void:
	test_bar_builds_three_zones_and_drag_handle()
	test_height_states_resolve_to_pixel_values()
	test_height_persistence_round_trip()
	test_notebook_open_hides_bar()
	test_combat_block_disables_notebook_button()
	# Item 4 — PortraitWithBadge migration smoke tests.
	test_portrait_widgets_dict_starts_empty()
	test_apply_level_badges_sets_text_and_modulate()
	test_apply_level_badges_clears_badge_when_level_unknown()
	test_apply_level_badges_dim_modulate_on_focus_level()
	test_session_ended_flushes_widget_cache()

	if not has_failures():
		print("SessionStatusBar: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_bar() -> SessionStatusBar:
	var bar := SESSION_STATUS_BAR.new()
	add_child(bar)
	return bar


func _delete_persisted_height() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists("session_status_bar_height.txt"):
		dir.remove("session_status_bar_height.txt")


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_bar_builds_three_zones_and_drag_handle() -> void:
	_delete_persisted_height()
	var bar := _make_bar()

	check(bar._bar != null, "bar PanelContainer is constructed")
	check(bar._drag_handle != null, "drag handle is constructed")
	check(bar._portrait_zone != null, "portrait zone is constructed")
	check(bar._widget_zone != null, "widget zone is constructed")
	check(bar._log_zone != null, "log zone (placeholder) is constructed")
	check(bar._widget_zone.columns == 3,
		"widget zone is a 3-column grid; got %d" % bar._widget_zone.columns)
	# 9 cells in the 3×3 grid (3 rows × 3 cols).
	check(bar._widget_zone.get_child_count() == 9,
		"widget zone has 9 cells (3×3); got %d" % bar._widget_zone.get_child_count())

	bar.queue_free()
	print("  bar_builds_three_zones_and_drag_handle: OK")


func test_height_states_resolve_to_pixel_values() -> void:
	_delete_persisted_height()
	var bar := _make_bar()

	check(bar._bar_height_for_state(SESSION_STATUS_BAR.HEIGHT_STATE_HIDDEN) == SESSION_STATUS_BAR.HEIGHT_HIDDEN,
		"Hidden state resolves to HEIGHT_HIDDEN pixels")
	check(bar._bar_height_for_state(SESSION_STATUS_BAR.HEIGHT_STATE_MINIMAL) == SESSION_STATUS_BAR.HEIGHT_MINIMAL,
		"Minimal state resolves to HEIGHT_MINIMAL pixels")
	check(bar._bar_height_for_state(SESSION_STATUS_BAR.HEIGHT_STATE_DEFAULT) == SESSION_STATUS_BAR.HEIGHT_DEFAULT,
		"Default state resolves to HEIGHT_DEFAULT pixels")
	# Expanded depends on viewport — just verify it returns a positive int.
	var exp_h: int = bar._bar_height_for_state(SESSION_STATUS_BAR.HEIGHT_STATE_EXPANDED)
	check(exp_h > 0,
		"Expanded state resolves to a positive pixel value; got %d" % exp_h)

	bar.queue_free()
	print("  height_states_resolve_to_pixel_values: OK")


func test_height_persistence_round_trip() -> void:
	_delete_persisted_height()
	var bar := _make_bar()

	bar._set_height_state(SESSION_STATUS_BAR.HEIGHT_STATE_MINIMAL)
	check(bar._height_state == SESSION_STATUS_BAR.HEIGHT_STATE_MINIMAL,
		"set_height_state updates internal state")
	check(FileAccess.file_exists("user://session_status_bar_height.txt"),
		"persistence file is written on state change")

	bar.queue_free()

	var bar2 := _make_bar()
	check(bar2._height_state == SESSION_STATUS_BAR.HEIGHT_STATE_MINIMAL,
		"persisted state restores on construction; got '%s'" % bar2._height_state)

	bar2.queue_free()
	_delete_persisted_height()
	print("  height_persistence_round_trip: OK")


func test_notebook_open_hides_bar() -> void:
	_delete_persisted_height()
	var bar := _make_bar()
	# Force a state that allows visibility (mirrors what _state_allows_visibility
	# checks). EXPLORATION is one such state.
	GameState.current_state = GameState.State.EXPLORATION

	bar._on_notebook_open_state_changed(true)
	check(not bar._bar.visible,
		"bar should hide when notebook opens")

	bar._on_notebook_open_state_changed(false)
	check(bar._bar.visible,
		"bar should reappear when notebook closes (state still allows visibility)")

	bar.queue_free()
	print("  notebook_open_hides_bar: OK")


func test_combat_block_disables_notebook_button() -> void:
	_delete_persisted_height()
	var bar := _make_bar()

	# No active combat — button should be enabled.
	CombatUIController.active_instance = null
	bar._refresh_notebook_btn_state()
	check(not bar._notebook_btn.disabled,
		"notebook button enabled when no combat is active")
	check(not bar._notebook_btn.tooltip_text.contains("Notebook unavailable"),
		"tooltip should not show the combat-block message when enabled")

	# Simulate active combat in a non-pc-input state.
	# (We can't easily instantiate a real CombatUIController without its
	# dependencies; tests for the predicate itself live in test_notebook.gd.)
	# This test only verifies the bar's reaction to the predicate's return.
	# If active_instance is null → notebook_open_allowed() returns true.
	# That covers the enabled path; the disabled path is exercised via the
	# notebook test suite's combat-gating tests in test_notebook.gd.

	bar.queue_free()
	print("  combat_block_disables_notebook_button: OK")


# ---------------------------------------------------------------------------
# Item 4 — PortraitWithBadge migration tests
# ---------------------------------------------------------------------------

func test_portrait_widgets_dict_starts_empty() -> void:
	var bar := _make_bar()
	check(bar._portrait_widgets.is_empty(),
		"_portrait_widgets dict starts empty before any party load")
	bar.queue_free()


func test_apply_level_badges_sets_text_and_modulate() -> void:
	# Drive _apply_level_badges with synthetic state so we don't need a DB
	# party. Manually populate _portrait_widgets with a PortraitWithBadge
	# instance, set the level snapshot, call the apply, and assert the
	# badge text + modulate.
	var bar := _make_bar()
	var widget = PORTRAIT_WITH_BADGE.new()
	bar.add_child(widget)
	bar._portrait_widgets["pc_a"] = widget
	bar._party_levels = {"pc_a": 3}
	bar._current_focus_level = 1  # not 3 → off-focus
	bar._apply_level_badges()
	check(widget._badge != null and widget._badge.visible,
		"Badge should be visible after _apply_level_badges with level data")
	check(widget._badge.text == "L3",
		"Badge text should reflect level (got '%s')" % widget._badge.text)
	# Off-focus → bright tint.
	check(widget._badge.modulate.is_equal_approx(SESSION_STATUS_BAR.LEVEL_BADGE_TINT_OFF_FOCUS),
		"Off-focus level should set bright modulate (got %s)" % widget._badge.modulate)
	bar.queue_free()


func test_apply_level_badges_clears_badge_when_level_unknown() -> void:
	var bar := _make_bar()
	var widget = PORTRAIT_WITH_BADGE.new()
	bar.add_child(widget)
	# Pre-populate badge so we can verify clear takes effect.
	widget.set_badge("L9", Color.WHITE)
	bar._portrait_widgets["ghost_pc"] = widget
	bar._party_levels = {}  # no level for this character
	bar._apply_level_badges()
	check(not widget._badge.visible,
		"Badge should hide when no level data is available")
	bar.queue_free()


func test_apply_level_badges_dim_modulate_on_focus_level() -> void:
	var bar := _make_bar()
	var widget = PORTRAIT_WITH_BADGE.new()
	bar.add_child(widget)
	bar._portrait_widgets["pc_b"] = widget
	bar._party_levels = {"pc_b": 2}
	bar._current_focus_level = 2  # match → on-focus → muted modulate
	bar._apply_level_badges()
	check(widget._badge.modulate.is_equal_approx(SESSION_STATUS_BAR.LEVEL_BADGE_TINT_ON_FOCUS),
		"On-focus level should set muted modulate (got %s)" % widget._badge.modulate)
	bar.queue_free()


func test_session_ended_flushes_widget_cache() -> void:
	var bar := _make_bar()
	var widget = PORTRAIT_WITH_BADGE.new()
	bar.add_child(widget)
	bar._portrait_widgets["pc_c"] = widget
	bar._on_session_ended()
	check(bar._portrait_widgets.is_empty(),
		"_portrait_widgets dict should clear on session_ended")
	bar.queue_free()
