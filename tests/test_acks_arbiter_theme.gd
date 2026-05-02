extends "res://tests/test_suite_base.gd"

## Smoke tests for the project Theme.tres (Phase α.4).
##
## Confirms the file loads, defaults are present, and the type variations
## that β/γ surfaces will consume are wired correctly. The actual visual
## styling per surface is verified by playtest, not by these tests; here we
## just guard against accidental syntax breakage that would silently strip
## variants on save.


const THEME_PATH := "res://assets/ui/theme/acks_arbiter_theme.tres"


func run_all_tests() -> void:
	test_theme_loads()
	test_default_font_size()
	test_framed_window_variant()
	test_notebook_variants()
	if not has_failures():
		print("AcksArbiterTheme: all tests passed.")


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_theme_loads() -> void:
	var theme: Theme = load(THEME_PATH) as Theme
	check(theme != null, "Theme.tres should load as a Theme resource")


func test_default_font_size() -> void:
	var theme: Theme = load(THEME_PATH) as Theme
	if theme == null:
		return
	check(theme.default_font_size == 14,
		"default_font_size should be 14 (got %d)" % theme.default_font_size)


func test_framed_window_variant() -> void:
	var theme: Theme = load(THEME_PATH) as Theme
	if theme == null:
		return
	var base := theme.get_type_variation_base(&"FramedWindow")
	check(base == &"PanelContainer",
		"FramedWindow should base on PanelContainer (got '%s')" % base)
	var sbf := theme.get_stylebox("panel", &"FramedWindow")
	check(sbf is StyleBoxFlat,
		"FramedWindow panel stylebox should be a StyleBoxFlat")
	if sbf is StyleBoxFlat:
		var flat := sbf as StyleBoxFlat
		check(not flat.draw_center,
			"FramedWindow should not draw center (chrome only)")
		check(flat.border_width_left == 2,
			"FramedWindow border_width_left should be 2")


func test_notebook_variants() -> void:
	var theme: Theme = load(THEME_PATH) as Theme
	if theme == null:
		return
	for variant in ["NotebookContainer", "NotebookPage", "NotebookActiveTab",
			"NotebookInactiveTab"]:
		var base := theme.get_type_variation_base(StringName(variant))
		check(base == &"PanelContainer",
			"%s should base on PanelContainer (got '%s')" % [variant, base])
		var sb := theme.get_stylebox("panel", StringName(variant))
		check(sb is StyleBoxFlat,
			"%s panel stylebox should be a StyleBoxFlat" % variant)
