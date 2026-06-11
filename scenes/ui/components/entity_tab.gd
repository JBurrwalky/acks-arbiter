class_name EntityTab
extends PanelContainer

## EntityTab — one entry in the Character tab's entity strip (gdd-character-tab.md
## §2). The portrait IS the selector tile: it fills the tile edge-to-edge, with a
## translucent name banner across the bottom and a level badge in the top-right.
## The active entity gets a gold frame; others a subtle brown border. Clicking
## emits entity_clicked(entity_id).
##
## Redesign 2026-06-11 (approved): replaced the small portrait + caption-below
## layout (which overlapped in a cramped strip) with a full-bleed portrait tile.


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted when the entity tab is clicked.
signal entity_clicked(entity_id: String)


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const TILE_SIZE := Vector2(88, 104)
const NAME_FONT_SIZE := 12
const BADGE_SIZE := 20
const BADGE_INSET := 3

## Name-banner truncation thresholds (per Jedidiah 2026-06-11): show only the
## first whitespace-delimited word; if that word is LONG_NAME_CHARS+ characters
## (no spaces), show the first SHORT_NAME_KEEP characters + an ellipsis.
const LONG_NAME_CHARS := 15
const SHORT_NAME_KEEP := 8

const TILE_BG := Color(0.80, 0.75, 0.62, 1.0)        # neutral tan (shows if no portrait)
const BORDER_COLOR := Color(0.46, 0.33, 0.19, 0.70)
const ACTIVE_BORDER_COLOR := Color(0.85, 0.65, 0.30, 1.0)
const BANNER_BG := Color(0.15, 0.10, 0.04, 0.82)
const NAME_COLOR := Color(0.95, 0.90, 0.80, 1.0)
const BADGE_BG := Color(0.88, 0.66, 0.23, 1.0)
const BADGE_TEXT := Color(0.18, 0.12, 0.02, 1.0)
const BADGE_BORDER := Color(0.40, 0.28, 0.10, 1.0)


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _btn: Button = null
var _portrait: TextureRect = null
var _name_label: Label = null
var _badge: PanelContainer = null
var _level_label: Label = null
var _entity_id: String = ""
var _is_active: bool = false


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_ensure_built()


func _build() -> void:
	custom_minimum_size = TILE_SIZE
	add_theme_stylebox_override("panel", _make_style(false))

	_btn = Button.new()
	_btn.flat = true
	_btn.focus_mode = Control.FOCUS_NONE
	_btn.pressed.connect(_on_pressed)
	add_child(_btn)

	# Portrait fills the tile (cropped to cover).
	_portrait = TextureRect.new()
	_portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	# Use the portrait's mip chain (EntityStrip builds mipmapped tile textures) so
	# the large bust minifies to ~88px smoothly instead of aliasing hard.
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_btn.add_child(_portrait)

	# Name banner across the bottom.
	var banner := PanelContainer.new()
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_theme_stylebox_override("panel", _make_banner_style())
	banner.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_btn.add_child(banner)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", NAME_FONT_SIZE)
	_name_label.add_theme_color_override("font_color", NAME_COLOR)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(_name_label)

	# Level badge, top-right corner.
	_badge = PanelContainer.new()
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.add_theme_stylebox_override("panel", _make_badge_style())
	_badge.anchor_left = 1.0
	_badge.anchor_right = 1.0
	_badge.anchor_top = 0.0
	_badge.anchor_bottom = 0.0
	_badge.offset_left = -(BADGE_SIZE + BADGE_INSET)
	_badge.offset_right = -BADGE_INSET
	_badge.offset_top = BADGE_INSET
	_badge.offset_bottom = BADGE_INSET + BADGE_SIZE
	_btn.add_child(_badge)

	_level_label = Label.new()
	_level_label.add_theme_font_size_override("font_size", 11)
	_level_label.add_theme_color_override("font_color", BADGE_TEXT)
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.add_child(_level_label)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Configure the tab. [param portrait] may be null (tile shows the tan bg).
## [param level] <= 0 hides the level badge (e.g. trained animals / vehicles).
func setup(entity_id: String, portrait: Texture2D, display_name: String,
		level: int = 0, is_active: bool = false) -> void:
	_ensure_built()
	_entity_id = entity_id
	_portrait.texture = portrait
	_name_label.text = banner_name(display_name)
	_btn.tooltip_text = display_name  # full, untruncated name on hover
	if level > 0:
		_level_label.text = str(level)
		_badge.visible = true
	else:
		_badge.visible = false
	set_active(is_active)


## Update only the active-highlight state (gold frame).
func set_active(is_active: bool) -> void:
	_ensure_built()
	if _is_active == is_active:
		return
	_is_active = is_active
	add_theme_stylebox_override("panel", _make_style(is_active))


func entity_id() -> String:
	return _entity_id


func is_active() -> bool:
	return _is_active


## Name shown on the banner: first whitespace-delimited word; if that word is
## LONG_NAME_CHARS+ characters, the first SHORT_NAME_KEEP chars + "...".
## "Half Nuari" -> "Half"; "Lunalarielaurelie" -> "Lunalari...". Static + testable.
static func banner_name(full: String) -> String:
	var s := full.strip_edges()
	var space_idx := s.find(" ")
	if space_idx >= 0:
		s = s.substr(0, space_idx)
	if s.length() >= LONG_NAME_CHARS:
		s = s.substr(0, SHORT_NAME_KEEP) + "..."
	return s


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _on_pressed() -> void:
	entity_clicked.emit(_entity_id)


func _make_style(active: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = TILE_BG
	style.border_color = ACTIVE_BORDER_COLOR if active else BORDER_COLOR
	var w := 3 if active else 1
	style.border_width_left = w
	style.border_width_right = w
	style.border_width_top = w
	style.border_width_bottom = w
	style.set_corner_radius_all(5)
	style.set_content_margin_all(2)
	return style


func _make_banner_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = BANNER_BG
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	style.content_margin_left = 4
	style.content_margin_right = 4
	return style


func _make_badge_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = BADGE_BG
	style.border_color = BADGE_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(int(BADGE_SIZE / 2.0))
	style.content_margin_left = 1
	style.content_margin_right = 1
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	return style


func _ensure_built() -> void:
	if _btn == null:
		_build()
