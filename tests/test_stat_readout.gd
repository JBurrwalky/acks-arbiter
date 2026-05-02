extends "res://tests/test_suite_base.gd"

## Focused tests for the StatReadout component (Phase α.3).
##
## Covers static helpers (hp_color_for, format_hp) and instance API
## (show_hp / show_ac / show_movement / show_save).


func run_all_tests() -> void:
	test_hp_color_thresholds()
	test_hp_color_max_zero_is_safe()
	test_hp_color_negative_current_is_downed()
	test_format_hp_basic()
	test_format_hp_with_temp()
	test_show_hp_sets_label_and_color()
	test_show_ac_clears_color_override()
	test_show_movement_with_and_without_total()
	test_show_save_format()
	if not has_failures():
		print("StatReadout: all tests passed.")


# ---------------------------------------------------------------------------
# Static color helper
# ---------------------------------------------------------------------------

func test_hp_color_thresholds() -> void:
	# Healthy: ratio >= 0.5
	check(StatReadout.hp_color_for(10, 10) == UiPalette.HP_COLOR_HEALTHY,
		"full HP should be HEALTHY")
	check(StatReadout.hp_color_for(5, 10) == UiPalette.HP_COLOR_HEALTHY,
		"50%% HP exact should be HEALTHY")
	check(StatReadout.hp_color_for(6, 10) == UiPalette.HP_COLOR_HEALTHY,
		"60%% HP should be HEALTHY")
	# Hurt: 0.25 <= ratio < 0.5
	check(StatReadout.hp_color_for(4, 10) == UiPalette.HP_COLOR_HURT,
		"40%% HP should be HURT")
	check(StatReadout.hp_color_for(3, 10) == UiPalette.HP_COLOR_HURT,
		"30%% HP should be HURT")
	# Critical: 0 < ratio < 0.25
	check(StatReadout.hp_color_for(2, 10) == UiPalette.HP_COLOR_CRITICAL,
		"20%% HP should be CRITICAL")
	check(StatReadout.hp_color_for(1, 10) == UiPalette.HP_COLOR_CRITICAL,
		"10%% HP should be CRITICAL")
	# Downed
	check(StatReadout.hp_color_for(0, 10) == UiPalette.HP_COLOR_DOWNED,
		"0 HP should be DOWNED")


func test_hp_color_max_zero_is_safe() -> void:
	# Defensive: max_value <= 0 returns HEALTHY (no division by zero).
	check(StatReadout.hp_color_for(0, 0) == UiPalette.HP_COLOR_HEALTHY,
		"max=0 should not crash; returns HEALTHY")
	check(StatReadout.hp_color_for(5, -1) == UiPalette.HP_COLOR_HEALTHY,
		"negative max should not crash; returns HEALTHY")


func test_hp_color_negative_current_is_downed() -> void:
	# Combatants with negative HP (mortal-wounded) read as DOWNED.
	check(StatReadout.hp_color_for(-3, 10) == UiPalette.HP_COLOR_DOWNED,
		"negative current should be DOWNED")


# ---------------------------------------------------------------------------
# Static format helper
# ---------------------------------------------------------------------------

func test_format_hp_basic() -> void:
	check(StatReadout.format_hp(7, 12) == "7 / 12",
		"format_hp without temp: '7 / 12'")
	check(StatReadout.format_hp(0, 8) == "0 / 8",
		"format_hp at zero: '0 / 8'")


func test_format_hp_with_temp() -> void:
	check(StatReadout.format_hp(5, 10, 3) == "5 / 10 (+3)",
		"format_hp with temp: '5 / 10 (+3)'")
	check(StatReadout.format_hp(5, 10, 0) == "5 / 10",
		"zero temp should be omitted")


# ---------------------------------------------------------------------------
# Instance API
# ---------------------------------------------------------------------------

func test_show_hp_sets_label_and_color() -> void:
	var sr := StatReadout.new()
	sr.show_hp(3, 10)
	# Internals checked via the value Label.
	var value_label: Label = sr.get_child(1) as Label
	check(value_label != null, "value Label should exist")
	check(value_label.text == "3 / 10", "value Label text should be '3 / 10'")
	check(value_label.has_theme_color_override("font_color"),
		"low HP should have a font_color override")
	check(sr.current_kind() == StatReadout.KIND_HP,
		"current_kind() should report 'hp'")
	sr.queue_free()


func test_show_ac_clears_color_override() -> void:
	var sr := StatReadout.new()
	sr.show_hp(1, 10)  # apply color override first
	var value_label: Label = sr.get_child(1) as Label
	check(value_label.has_theme_color_override("font_color"),
		"sanity: HP override is set")

	sr.show_ac(15, " (effective)")
	check(value_label.text == "15 (effective)",
		"AC text should include the suffix")
	check(not value_label.has_theme_color_override("font_color"),
		"showing AC should clear the HP color override")
	check(sr.current_kind() == StatReadout.KIND_AC,
		"current_kind() should switch to 'ac'")
	sr.queue_free()


func test_show_movement_with_and_without_total() -> void:
	var sr := StatReadout.new()
	sr.show_movement(40, 90)
	var value_label: Label = sr.get_child(1) as Label
	check(value_label.text == "40 / 90 ft",
		"movement with total: '40 / 90 ft'")

	sr.show_movement(40)
	check(value_label.text == "40 ft",
		"movement without total: '40 ft'")
	check(sr.current_kind() == StatReadout.KIND_MOVEMENT,
		"current_kind() should be 'movement'")
	sr.queue_free()


func test_show_save_format() -> void:
	var sr := StatReadout.new()
	sr.show_save("Death", 14)
	var title: Label = sr.get_child(0) as Label
	var value: Label = sr.get_child(1) as Label
	check(title.text == "Death:", "save title should be 'Death:'")
	check(value.text == "14+", "save value should use ACKS descending '14+'")
	check(sr.current_kind() == StatReadout.KIND_SAVE,
		"current_kind() should be 'save'")
	sr.queue_free()
