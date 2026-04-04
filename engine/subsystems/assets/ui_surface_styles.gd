class_name UiSurfaceStyles
extends RefCounted

## Shared vellum panel and modal styling helpers for runtime-built UI.

const DEFAULT_TEXTURE_ID := "ui.bg.vellum_subtle"
const FRAME_BORDER_COLOR := Color(0.46, 0.33, 0.19, 1.0)
const FRAME_FILL_COLOR := Color(0.19, 0.13, 0.08, 0.94)
const FALLBACK_VELLUM_COLOR := Color(0.90, 0.84, 0.74, 1.0)
const VELLUM_TEXT_COLOR := Color(0.09, 0.06, 0.03, 1.0)
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
	theme.set_color("font_color", "Label", VELLUM_TEXT_COLOR)
	theme.set_color("default_color", "RichTextLabel", VELLUM_TEXT_COLOR)
	theme.set_color("font_color", "ItemList", VELLUM_TEXT_COLOR)
	theme.set_color("font_hovered_color", "ItemList", VELLUM_TEXT_COLOR)
	theme.set_color("font_disabled_color", "ItemList", VELLUM_TEXT_COLOR.darkened(0.25))
	theme.set_color("title_color", "Window", VELLUM_TEXT_COLOR)
	_vellum_text_theme = theme
	return _vellum_text_theme


static func _load_texture(texture_id: String) -> Texture2D:
	var texture_path := AssetRegistry.get_asset_path(texture_id)
	if texture_path.is_empty():
		return null
	if not ResourceLoader.exists(texture_path):
		return null
	return load(texture_path) as Texture2D
