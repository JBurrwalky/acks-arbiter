class_name PortraitWithBadge
extends PanelContainer

## PortraitWithBadge — portrait slot with overlay level/status badge.
##
## Per gdd-ui-architecture.md §5.4. Extracted (forward-design) from
## SessionStatusBar's per-portrait slot logic so the SessionStatusBar
## three-zone rework (Phase γ.4) and the Character-tab entity strip (Phase γ.1)
## share one implementation.
##
## Visual structure: PanelContainer (slot frame) → Button (click target) →
## TextureRect (portrait image, anchored to fill) + Label (badge, top-right).
##
## Texture loading is the caller's concern — this component takes a Texture2D
## directly. SessionStatusBar's `_portrait_cache` (per-id cache for shipped /
## user portraits) stays where it is; the component does not re-implement that
## responsibility. This separation matches how the existing CharacterSheetPanel
## consumes textures.


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted when the portrait is clicked. The arg is whatever entity_id was
## passed to set_entity_id() (empty string if the caller didn't set one).
signal portrait_clicked(entity_id: String)


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const DEFAULT_PORTRAIT_SIZE := Vector2(48, 48)
const DEFAULT_SLOT_PADDING := 4

const DEFAULT_BADGE_COLOR := Color(1.0, 0.92, 0.45, 1.0)
const DEFAULT_BADGE_OUTLINE_COLOR := Color(0, 0, 0, 1)
const DEFAULT_BADGE_FONT_SIZE := 11

const DEFAULT_SLOT_BORDER_COLOR := Color(0.46, 0.33, 0.19, 0.55)


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _btn: Button = null
var _texture_rect: TextureRect = null
var _badge: Label = null
var _entity_id: String = ""

var _portrait_size: Vector2 = DEFAULT_PORTRAIT_SIZE
var _slot_padding: int = DEFAULT_SLOT_PADDING


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_ensure_built()


func _build() -> void:
	clip_contents = true
	add_theme_stylebox_override("panel", _make_slot_style())

	var slot_size := Vector2(
		_portrait_size.x + _slot_padding * 2,
		_portrait_size.y + _slot_padding * 2)
	custom_minimum_size = slot_size
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER

	_btn = Button.new()
	_btn.flat = true
	_btn.focus_mode = Control.FOCUS_NONE
	_btn.custom_minimum_size = _portrait_size
	_btn.pressed.connect(_on_pressed)
	add_child(_btn)

	_texture_rect = TextureRect.new()
	_texture_rect.custom_minimum_size = _portrait_size
	_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Add to parent first so PRESET_FULL_RECT resolves offsets against a live parent rect.
	_btn.add_child(_texture_rect)
	_texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)

	_badge = Label.new()
	_badge.name = "Badge"
	_badge.visible = false
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.add_theme_color_override("font_color", DEFAULT_BADGE_COLOR)
	_badge.add_theme_color_override("font_outline_color", DEFAULT_BADGE_OUTLINE_COLOR)
	_badge.add_theme_constant_override("outline_size", 3)
	_badge.add_theme_font_size_override("font_size", DEFAULT_BADGE_FONT_SIZE)
	_badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_badge.offset_left = -24
	_badge.offset_right = -2
	_badge.offset_top = 1
	_badge.offset_bottom = 14
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_btn.add_child(_badge)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Set the portrait image. Pass null to clear.
func set_texture(texture: Texture2D) -> void:
	_ensure_built()
	_texture_rect.texture = texture


## Tooltip on hover. Convention: pass the character's display name.
func set_tooltip(text: String) -> void:
	_ensure_built()
	_btn.tooltip_text = text


## Identifier emitted with portrait_clicked when the user clicks. Convention:
## the character_id; can be any token the consumer cares to round-trip.
func set_entity_id(entity_id: String) -> void:
	_entity_id = entity_id


## Show the badge with [param text] (typically a level number). Empty text
## hides the badge.
func set_badge(text: String, color: Color = DEFAULT_BADGE_COLOR) -> void:
	_ensure_built()
	if text.is_empty():
		_badge.visible = false
		_badge.text = ""
		return
	_badge.text = text
	_badge.add_theme_color_override("font_color", color)
	_badge.visible = true


## Hide the badge without changing its text.
func clear_badge() -> void:
	_ensure_built()
	_badge.visible = false


## Update only the badge color without retyping the text. Useful for callers
## (e.g., SessionStatusBar's level badges) that want to recolor in response to
## state changes without rebuilding the badge contents.
func set_badge_color(color: Color) -> void:
	_ensure_built()
	_badge.add_theme_color_override("font_color", color)


## Apply a multiplicative tint to the badge node only (not the portrait).
## Used by SessionStatusBar's dungeon-focus dimming, where badges of party
## members at the current camera focus level render muted so they don't draw
## the eye away from the active level. Pass Color.WHITE to reset.
func set_badge_modulate(color: Color) -> void:
	_ensure_built()
	_badge.modulate = color


## Resize the inner portrait area. Call before adding the component to a
## tree so the slot wrapper sizes correctly.
func set_portrait_size(size: Vector2) -> void:
	_portrait_size = size
	if _texture_rect != null:
		_texture_rect.custom_minimum_size = size
		_texture_rect.size = size
		var slot_size := Vector2(size.x + _slot_padding * 2, size.y + _slot_padding * 2)
		custom_minimum_size = slot_size


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _on_pressed() -> void:
	portrait_clicked.emit(_entity_id)


func _make_slot_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = DEFAULT_SLOT_BORDER_COLOR
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	style.content_margin_left = _slot_padding
	style.content_margin_right = _slot_padding
	style.content_margin_top = _slot_padding
	style.content_margin_bottom = _slot_padding
	return style


func _ensure_built() -> void:
	if _btn == null:
		_build()
