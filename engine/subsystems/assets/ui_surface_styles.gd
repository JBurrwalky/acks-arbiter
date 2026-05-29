class_name UiSurfaceStyles
extends RefCounted

## Shared vellum panel and modal styling helpers for runtime-built UI.

const DEFAULT_TEXTURE_ID := "ui.bg.vellum_subtle"
const FRAME_BORDER_COLOR := Color(0.46, 0.33, 0.19, 1.0)
const FRAME_FILL_COLOR := Color(0.19, 0.13, 0.08, 0.94)
const FALLBACK_VELLUM_COLOR := Color(0.90, 0.84, 0.74, 1.0)
const VELLUM_TEXT_COLOR := Color(0.09, 0.06, 0.03, 1.0)
## Secondary/dim text on the light vellum page. Readable mid-dark brown — use
## for de-emphasized labels (hints, timestamps, "dim" rows) that should read as
## secondary WITHOUT washing out on the parchment background. Replaces the
## old light cream/gray "DIM" tones that were invisible on the light page.
## See docs/coding_conventions.md §6.10 / build_log.md 2026-05-27.
const VELLUM_SECONDARY_TEXT_COLOR := Color(0.34, 0.27, 0.19, 1.0)
const VELLUM_WARNING_TEXT_COLOR := Color(0.46, 0.12, 0.08, 1.0)
const BACKGROUND_NODE_NAME := "__ui_vellum_background"

static var _vellum_text_theme: Theme = null


static func apply_textured_panel(panel: PanelContainer,
		texture_id: String = DEFAULT_TEXTURE_ID) -> void:
	if panel == null:
		return
	panel.add_theme_stylebox_override("panel", make_vellum_style(texture_id))
	apply_vellum_text_theme(panel)


static func apply_framed_window_chrome(target: Node,
		texture_id: String = DEFAULT_TEXTURE_ID) -> void:
	if target == null:
		return
	if target is Control:
		(target as Control).add_theme_stylebox_override("panel", make_window_frame_style())
	elif target is Window:
		(target as Window).add_theme_stylebox_override("panel", make_window_frame_style())
	else:
		push_warning("UiSurfaceStyles.apply_framed_window_chrome: target must be a Control or Window")
		return

	var background := target.get_node_or_null(BACKGROUND_NODE_NAME) as TextureRect
	if background == null:
		background = make_background_rect(texture_id)
		background.name = BACKGROUND_NODE_NAME
		target.add_child(background)
		target.move_child(background, 0)
	else:
		background.texture = _load_texture(texture_id)

	apply_vellum_text_theme(target)


static func apply_vellum_text_theme(target: Node) -> void:
	if target == null:
		return

	var theme := _get_vellum_text_theme()
	if target is Control:
		(target as Control).theme = theme
	elif target is Window:
		(target as Window).theme = theme


static func make_vellum_style(texture_id: String = DEFAULT_TEXTURE_ID) -> StyleBox:
	var texture := _load_texture(texture_id)
	if texture != null:
		var style := StyleBoxTexture.new()
		style.texture = texture
		style.content_margin_left = 0.0
		style.content_margin_right = 0.0
		style.content_margin_top = 0.0
		style.content_margin_bottom = 0.0
		return style

	var fallback := StyleBoxFlat.new()
	fallback.bg_color = FALLBACK_VELLUM_COLOR
	return fallback


static func make_filled_frame_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = FRAME_FILL_COLOR
	style.border_color = FRAME_BORDER_COLOR
	style.set_border_width_all(2)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_right = 12
	style.corner_radius_bottom_left = 12
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.28)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 4)
	return style


static func make_window_frame_style() -> StyleBoxFlat:
	var style := make_filled_frame_style()
	style.draw_center = false
	return style


static func make_background_rect(texture_id: String = DEFAULT_TEXTURE_ID) -> TextureRect:
	var background := TextureRect.new()
	background.texture = _load_texture(texture_id)
	background.anchor_right = 1.0
	background.anchor_bottom = 1.0
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.show_behind_parent = true
	background.z_index = -1
	if background.texture == null:
		background.self_modulate = FALLBACK_VELLUM_COLOR
	return background


static func _get_vellum_text_theme() -> Theme:
	if _vellum_text_theme != null:
		return _vellum_text_theme

	var theme := Theme.new()
	var disabled_color := VELLUM_TEXT_COLOR.lightened(0.45)

	# Passive text surfaces.
	theme.set_color("font_color", "Label", VELLUM_TEXT_COLOR)
	theme.set_color("default_color", "RichTextLabel", VELLUM_TEXT_COLOR)
	theme.set_color("title_color", "Window", VELLUM_TEXT_COLOR)

	# ItemList rows.
	theme.set_color("font_color", "ItemList", VELLUM_TEXT_COLOR)
	theme.set_color("font_hovered_color", "ItemList", VELLUM_TEXT_COLOR)
	theme.set_color("font_selected_color", "ItemList", VELLUM_TEXT_COLOR)
	theme.set_color("font_disabled_color", "ItemList", disabled_color)

	# Button family. Engine defaults are near-white and unreadable on parchment;
	# keep all interactive states at VELLUM_TEXT_COLOR and let the stylebox
	# (panel/button background) provide affordance feedback.
	for cls in ["Button", "OptionButton", "MenuButton", "CheckBox", "CheckButton", "LinkButton"]:
		theme.set_color("font_color", cls, VELLUM_TEXT_COLOR)
		theme.set_color("font_pressed_color", cls, VELLUM_TEXT_COLOR)
		theme.set_color("font_hover_color", cls, VELLUM_TEXT_COLOR)
		theme.set_color("font_hover_pressed_color", cls, VELLUM_TEXT_COLOR)
		theme.set_color("font_focus_color", cls, VELLUM_TEXT_COLOR)
		theme.set_color("font_disabled_color", cls, disabled_color)

	# Text input.
	theme.set_color("font_color", "LineEdit", VELLUM_TEXT_COLOR)
	theme.set_color("font_uneditable_color", "LineEdit", disabled_color)
	theme.set_color("font_placeholder_color", "LineEdit", disabled_color)
	theme.set_color("caret_color", "LineEdit", VELLUM_TEXT_COLOR)
	theme.set_color("font_color", "TextEdit", VELLUM_TEXT_COLOR)
	theme.set_color("font_readonly_color", "TextEdit", disabled_color)
	theme.set_color("font_placeholder_color", "TextEdit", disabled_color)
	theme.set_color("caret_color", "TextEdit", VELLUM_TEXT_COLOR)

	# Tree widget.
	theme.set_color("font_color", "Tree", VELLUM_TEXT_COLOR)
	theme.set_color("font_selected_color", "Tree", VELLUM_TEXT_COLOR)
	theme.set_color("font_hovered_color", "Tree", VELLUM_TEXT_COLOR)
	theme.set_color("font_disabled_color", "Tree", disabled_color)
	theme.set_color("title_button_color", "Tree", VELLUM_TEXT_COLOR)

	# Tabs (TabBar drives both TabContainer headers and standalone TabBar).
	theme.set_color("font_selected_color", "TabBar", VELLUM_TEXT_COLOR)
	theme.set_color("font_unselected_color", "TabBar", disabled_color)
	theme.set_color("font_hovered_color", "TabBar", VELLUM_TEXT_COLOR)
	theme.set_color("font_disabled_color", "TabBar", disabled_color)
	theme.set_color("font_selected_color", "TabContainer", VELLUM_TEXT_COLOR)
	theme.set_color("font_unselected_color", "TabContainer", disabled_color)
	theme.set_color("font_hovered_color", "TabContainer", VELLUM_TEXT_COLOR)
	theme.set_color("font_disabled_color", "TabContainer", disabled_color)

	# Popup menus (right-click context menus, dropdown lists).
	theme.set_color("font_color", "PopupMenu", VELLUM_TEXT_COLOR)
	theme.set_color("font_hover_color", "PopupMenu", VELLUM_TEXT_COLOR)
	theme.set_color("font_disabled_color", "PopupMenu", disabled_color)
	theme.set_color("font_separator_color", "PopupMenu", disabled_color)
	theme.set_color("font_accelerator_color", "PopupMenu", disabled_color)

	# SpinBox (uses LineEdit internally but exposes its own color too).
	theme.set_color("font_color", "SpinBox", VELLUM_TEXT_COLOR)

	_vellum_text_theme = theme
	return _vellum_text_theme


static func _load_texture(texture_id: String) -> Texture2D:
	var texture_path := AssetRegistry.get_asset_path(texture_id)
	if texture_path.is_empty():
		return null
	if not ResourceLoader.exists(texture_path):
		return null
	return load(texture_path) as Texture2D
