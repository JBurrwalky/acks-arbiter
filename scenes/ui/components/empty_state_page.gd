class_name EmptyStatePage
extends MarginContainer

## EmptyStatePage — standardized layout for notebook tabs whose content is
## not yet available (no domain established, no henchmen hired, etc.).
##
## Per gdd-ui-architecture.md §3.6 and §5.4. Each notebook tab whose
## prerequisites are unmet renders an EmptyStatePage explaining:
##   - Why the tab is currently empty
##   - How the player acquires the missing thing (with ACKS-correct rule
##     citations supplied by the tab's owning GDD)
##   - Where in the game the relevant action lives (acquisition links)
##
## The component is a passive renderer — it takes content as data via
## configure() and emits link_activated(link_id) when a link is clicked.
## The notebook root maps link_id values to navigation actions (open
## Settlement Panel, focus Stronghold Construction system, etc.).


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted when one of the acquisition links is clicked. [param link_id] is
## whatever opaque token the caller put in the link's dict. Notebook root
## consumes this and routes to the appropriate surface.
signal link_activated(link_id: String)


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const HEADING_FONT_SIZE := 22
const BODY_FONT_SIZE := 14
const LINK_FONT_SIZE := 13

# Dark text for the light parchment notebook page (were cream → invisible).
# See docs/coding_conventions.md §6.10 / build_log.md 2026-05-27.
const HEADING_COLOR := Color(0.09, 0.06, 0.03, 1.0)
const BODY_COLOR := Color(0.34, 0.27, 0.19, 1.0)
const LINK_COLOR := Color(0.62, 0.40, 0.10, 1.0)        # gold accent, darkened for light-page contrast
const LINK_HOVER_COLOR := Color(0.78, 0.52, 0.16, 1.0)

const OUTER_MARGIN := 60
const VERTICAL_SEPARATION := 18
const ICON_SIZE := Vector2(96, 96)


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _icon_rect: TextureRect = null
var _heading_label: Label = null
var _body_label: RichTextLabel = null
var _links_vbox: VBoxContainer = null


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_ensure_built()


func _build() -> void:
	add_theme_constant_override("margin_left", OUTER_MARGIN)
	add_theme_constant_override("margin_right", OUTER_MARGIN)
	add_theme_constant_override("margin_top", OUTER_MARGIN)
	add_theme_constant_override("margin_bottom", OUTER_MARGIN)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", VERTICAL_SEPARATION)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vbox)

	_icon_rect = TextureRect.new()
	_icon_rect.custom_minimum_size = ICON_SIZE
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_icon_rect.modulate = Color(1, 1, 1, 0.7)
	_icon_rect.visible = false
	vbox.add_child(_icon_rect)

	_heading_label = Label.new()
	_heading_label.add_theme_font_size_override("font_size", HEADING_FONT_SIZE)
	_heading_label.add_theme_color_override("font_color", HEADING_COLOR)
	_heading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_heading_label)

	_body_label = RichTextLabel.new()
	_body_label.bbcode_enabled = true
	_body_label.fit_content = true
	_body_label.scroll_active = false
	_body_label.add_theme_font_size_override("normal_font_size", BODY_FONT_SIZE)
	_body_label.add_theme_color_override("default_color", BODY_COLOR)
	_body_label.custom_minimum_size = Vector2(480, 0)
	# Center text within its width.
	_body_label.add_theme_constant_override("text_alignment", HORIZONTAL_ALIGNMENT_CENTER)
	vbox.add_child(_body_label)

	_links_vbox = VBoxContainer.new()
	_links_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_links_vbox.add_theme_constant_override("separation", 6)
	vbox.add_child(_links_vbox)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Configure the page in one call. [param links] is an Array of dicts each
## with keys:
##   text: String — display label, e.g. "Open the Settlement Panel"
##   id:   String — opaque token emitted via link_activated when clicked
##
## [param icon] may be null to omit the icon (the icon TextureRect hides).
##
## [param body] may include BBCode (italics, bold, links). Plain text works
## fine — the RichTextLabel renders it correctly.
func configure(heading: String, body: String, links: Array = [], icon: Texture2D = null) -> void:
	_ensure_built()
	_heading_label.text = heading
	_body_label.text = body
	_set_icon(icon)
	_rebuild_links(links)


func _set_icon(icon: Texture2D) -> void:
	_icon_rect.texture = icon
	_icon_rect.visible = icon != null


func _rebuild_links(links: Array) -> void:
	for child in _links_vbox.get_children():
		child.queue_free()

	for link in links:
		if not (link is Dictionary):
			continue
		var text: String = link.get("text", "")
		var id: String = link.get("id", "")
		if text.is_empty() or id.is_empty():
			continue
		_links_vbox.add_child(_make_link_button(text, id))


func _make_link_button(text: String, id: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.flat = true
	btn.add_theme_font_size_override("font_size", LINK_FONT_SIZE)
	btn.add_theme_color_override("font_color", LINK_COLOR)
	btn.add_theme_color_override("font_hover_color", LINK_HOVER_COLOR)
	btn.add_theme_color_override("font_focus_color", LINK_HOVER_COLOR)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.pressed.connect(_on_link_pressed.bind(id))
	return btn


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _on_link_pressed(id: String) -> void:
	link_activated.emit(id)


func _ensure_built() -> void:
	if _heading_label == null:
		_build()
