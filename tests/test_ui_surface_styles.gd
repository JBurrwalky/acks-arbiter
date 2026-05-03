extends "res://tests/test_suite_base.gd"

## Focused tests for shared vellum surface styling helpers.


func run_all_tests() -> void:
	test_make_vellum_style_uses_registered_texture()
	test_apply_vellum_text_theme_sets_readable_label_colors()
	test_vellum_text_theme_covers_button_family()
	test_vellum_text_theme_covers_text_input()
	test_vellum_text_theme_covers_tabs_and_popups()
	test_apply_framed_window_chrome_adds_background_node()
	test_apply_framed_window_chrome_accepts_confirmation_dialog()
	test_apply_framed_window_chrome_accepts_popup_panel()
	if not has_failures():
		print("UiSurfaceStyles: all tests passed.")


func test_make_vellum_style_uses_registered_texture() -> void:
	var style := UiSurfaceStyles.make_vellum_style()
	check(style is StyleBoxTexture,
		"vellum style should resolve to a texture-backed style box when the asset is registered")
	if style is StyleBoxTexture:
		check((style as StyleBoxTexture).texture != null,
			"vellum style texture should load from the asset registry")
	print("  make_vellum_style_uses_registered_texture: OK")


func test_apply_vellum_text_theme_sets_readable_label_colors() -> void:
	var root := Control.new()

	UiSurfaceStyles.apply_vellum_text_theme(root)

	check(root.theme != null,
		"vellum text theming should attach a shared theme to the target surface")
	check(root.theme.get_color("font_color", "Label") == UiSurfaceStyles.VELLUM_TEXT_COLOR,
		"vellum text theming should default labels to the readable dark parchment color")
	check(root.theme.get_color("title_color", "Window") == UiSurfaceStyles.VELLUM_TEXT_COLOR,
		"vellum text theming should also darken embedded window title text")
	print("  apply_vellum_text_theme_sets_readable_label_colors: OK")


func test_vellum_text_theme_covers_button_family() -> void:
	var root := Control.new()
	UiSurfaceStyles.apply_vellum_text_theme(root)
	var theme: Theme = root.theme

	# Engine defaults are near-white on Button etc., which are unreadable on
	# parchment. The vellum theme must darken the interactive states for
	# Button-family controls so all UI surfaces using apply_framed_window_chrome
	# render readable button labels.
	for cls in ["Button", "OptionButton", "MenuButton", "CheckBox", "CheckButton", "LinkButton"]:
		check(theme.get_color("font_color", cls) == UiSurfaceStyles.VELLUM_TEXT_COLOR,
			"%s.font_color should be darkened to vellum text color" % cls)
		check(theme.get_color("font_pressed_color", cls) == UiSurfaceStyles.VELLUM_TEXT_COLOR,
			"%s.font_pressed_color should be darkened" % cls)
		check(theme.get_color("font_hover_color", cls) == UiSurfaceStyles.VELLUM_TEXT_COLOR,
			"%s.font_hover_color should be darkened" % cls)
		check(theme.get_color("font_focus_color", cls) == UiSurfaceStyles.VELLUM_TEXT_COLOR,
			"%s.font_focus_color should be darkened" % cls)
		# Disabled state should be visibly distinct (lighter/grayed) but still on
		# the dark side of the parchment palette so it remains readable.
		var disabled := theme.get_color("font_disabled_color", cls)
		check(disabled != UiSurfaceStyles.VELLUM_TEXT_COLOR,
			"%s.font_disabled_color should differ from active text" % cls)
		check(disabled.r < 0.6 and disabled.g < 0.6 and disabled.b < 0.6,
			"%s.font_disabled_color should still be on the dark side of the parchment palette" % cls)
	print("  vellum_text_theme_covers_button_family: OK")


func test_vellum_text_theme_covers_text_input() -> void:
	var root := Control.new()
	UiSurfaceStyles.apply_vellum_text_theme(root)
	var theme: Theme = root.theme

	check(theme.get_color("font_color", "LineEdit") == UiSurfaceStyles.VELLUM_TEXT_COLOR,
		"LineEdit.font_color should be vellum text color")
	check(theme.get_color("caret_color", "LineEdit") == UiSurfaceStyles.VELLUM_TEXT_COLOR,
		"LineEdit.caret_color should be visible against parchment")
	check(theme.get_color("font_color", "TextEdit") == UiSurfaceStyles.VELLUM_TEXT_COLOR,
		"TextEdit.font_color should be vellum text color")
	check(theme.get_color("caret_color", "TextEdit") == UiSurfaceStyles.VELLUM_TEXT_COLOR,
		"TextEdit.caret_color should be visible against parchment")
	print("  vellum_text_theme_covers_text_input: OK")


func test_vellum_text_theme_covers_tabs_and_popups() -> void:
	var root := Control.new()
	UiSurfaceStyles.apply_vellum_text_theme(root)
	var theme: Theme = root.theme

	check(theme.get_color("font_selected_color", "TabBar") == UiSurfaceStyles.VELLUM_TEXT_COLOR,
		"TabBar.font_selected_color should be readable on parchment")
	check(theme.get_color("font_selected_color", "TabContainer") == UiSurfaceStyles.VELLUM_TEXT_COLOR,
		"TabContainer.font_selected_color should be readable on parchment")
	check(theme.get_color("font_color", "PopupMenu") == UiSurfaceStyles.VELLUM_TEXT_COLOR,
		"PopupMenu.font_color should be readable on parchment")
	check(theme.get_color("font_color", "Tree") == UiSurfaceStyles.VELLUM_TEXT_COLOR,
		"Tree.font_color should be readable on parchment")
	print("  vellum_text_theme_covers_tabs_and_popups: OK")


func test_apply_framed_window_chrome_adds_background_node() -> void:
	var panel := PanelContainer.new()
	var content := Label.new()
	content.text = "content"
	panel.add_child(content)

	UiSurfaceStyles.apply_framed_window_chrome(panel)

	_check_framed_surface(panel, "panel container")
	print("  apply_framed_window_chrome_adds_background_node: OK")


func test_apply_framed_window_chrome_accepts_confirmation_dialog() -> void:
	var dialog := ConfirmationDialog.new()

	UiSurfaceStyles.apply_framed_window_chrome(dialog)

	_check_framed_surface(dialog, "confirmation dialog")
	print("  apply_framed_window_chrome_accepts_confirmation_dialog: OK")


func test_apply_framed_window_chrome_accepts_popup_panel() -> void:
	var popup := PopupPanel.new()

	UiSurfaceStyles.apply_framed_window_chrome(popup)

	_check_framed_surface(popup, "popup panel")
	print("  apply_framed_window_chrome_accepts_popup_panel: OK")


func _check_framed_surface(surface: Node, surface_name: String) -> void:
	var background := surface.get_node_or_null("__ui_vellum_background")
	check(background is TextureRect,
		"%s should install a vellum background TextureRect" % surface_name)
	if background is TextureRect:
		check((background as TextureRect).show_behind_parent,
			"%s background should draw behind the dialog content rather than covering it" % surface_name)

	var panel_style: StyleBox = null
	if surface is Control:
		panel_style = (surface as Control).get_theme_stylebox("panel")
	elif surface is Window:
		panel_style = (surface as Window).get_theme_stylebox("panel")

	check(panel_style is StyleBoxFlat,
		"%s should override the panel style with a frame style" % surface_name)
	if panel_style is StyleBoxFlat:
		check(not (panel_style as StyleBoxFlat).draw_center,
			"%s should leave the center open so the vellum background shows through" % surface_name)

	var theme: Theme = null
	if surface is Control:
		theme = (surface as Control).theme
	elif surface is Window:
		theme = (surface as Window).theme
	check(theme != null,
		"%s should receive the shared vellum text theme" % surface_name)
	if theme != null:
		check(theme.get_color("font_color", "Label") == UiSurfaceStyles.VELLUM_TEXT_COLOR,
			"%s should use the readable dark vellum text color" % surface_name)
