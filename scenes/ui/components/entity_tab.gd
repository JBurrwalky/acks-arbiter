class_name EntityTab
extends PanelContainer

## EntityTab — one entry in the Character tab's entity strip.
##
## Per gdd-ui-architecture.md §3.5 and §5.4. Shows a small portrait + name
## label; click sets the global active entity. The active entity gets a
## visual highlight; other entries render flat.
##
## The Character tab will host a horizontal scrollable HBox of these,
## populated from the type-dropdown selection (PCs / Henchmen / Mercenary
## Officers / Trained Animals / Vehicles).


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted when the entity tab is clicked. Consumers (Notebook root) consume
## this and emit `EventBus.notebook_active_entity_requested(entity_id)`.
signal entity_clicked(entity_id: String)


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const PORTRAIT_SIZE := Vector2(36, 36)
const PADDING := 4
const NAME_FONT_SIZE := 11

const ACTIVE_BG_COLOR := Color(0.42, 0.30, 0.16, 1.0)
const INACTIVE_BG_COLOR := Color(0, 0, 0, 0)
const BORDER_COLOR := Color(0.46, 0.33, 0.19, 0.55)
const ACTIVE_BORDER_COLOR := Color(0.85, 0.65, 0.30, 1.0)
# State-dependent name color (mirrors notebook_tab_strip): the active chip has a
# dark-brown background → light text; the inactive chip is transparent and shows
# the light parchment page → dark text. A single light NAME_COLOR was invisible
# on inactive tabs. See docs/coding_conventions.md §6.10 / build_log.md 2026-05-27.
const NAME_ACTIVE_COLOR := Color(0.92, 0.86, 0.74, 1.0)
const NAME_INACTIVE_COLOR := Color(0.09, 0.06, 0.03, 1.0)


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _btn: Button = null
var _portrait: TextureRect = null
var _name_label: Label = null
var _entity_id: String = ""
var _is_active: bool = false


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_ensure_built()


func _build() -> void:
	add_theme_stylebox_override("panel", _make_style(false))

	_btn = Button.new()
	_btn.flat = true
	_btn.focus_mode = Control.FOCUS_NONE
	_btn.pressed.connect(_on_pressed)
	add_child(_btn)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	_btn.add_child(vbox)

	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = PORTRAIT_SIZE
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(_portrait)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", NAME_FONT_SIZE)
	# Default to the inactive (dark, on light page) color; set_active() flips it.
	_name_label.add_theme_color_override("font_color", NAME_INACTIVE_COLOR)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.custom_minimum_size = Vector2(PORTRAIT_SIZE.x + PADDING * 2, 0)
	vbox.add_child(_name_label)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Configure the tab in one call. [param portrait] may be null to render an
## empty image (TextureRect just shows the panel background).
func setup(entity_id: String, portrait: Texture2D, display_name: String, is_active: bool = false) -> void:
	_ensure_built()
	_entity_id = entity_id
	_portrait.texture = portrait
	_name_label.text = display_name
	_btn.tooltip_text = display_name
	set_active(is_active)


## Update only the active-highlight state.
func set_active(is_active: bool) -> void:
	_ensure_built()
	if _is_active == is_active:
		return
	_is_active = is_active
	add_theme_stylebox_override("panel", _make_style(is_active))
	# Flip name text color to stay legible against the chip background.
	if _name_label != null:
		_name_label.add_theme_color_override(
			"font_color", NAME_ACTIVE_COLOR if is_active else NAME_INACTIVE_COLOR)


func entity_id() -> String:
	return _entity_id


func is_active() -> bool:
	return _is_active


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _on_pressed() -> void:
	entity_clicked.emit(_entity_id)


func _make_style(active: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = ACTIVE_BG_COLOR if active else INACTIVE_BG_COLOR
	style.border_color = ACTIVE_BORDER_COLOR if active else BORDER_COLOR
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 2 if active else 1
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	style.content_margin_left = PADDING
	style.content_margin_right = PADDING
	style.content_margin_top = PADDING
	style.content_margin_bottom = PADDING
	return style


func _ensure_built() -> void:
	if _btn == null:
		_build()
