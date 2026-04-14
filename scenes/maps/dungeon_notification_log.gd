extends PanelContainer

## Scrolling notification log for dungeon exploration events.
##
## Shows colored entries for movement, action results, encounters, resource
## depletion, and other mechanical events. Click an entry to center camera
## on the referenced cell.

signal log_entry_clicked(cell: Vector2i)


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Color mapping per GDD §7.2.
const CATEGORY_COLORS := {
	"movement": Color(0.85, 0.85, 0.85),     # Default/white
	"success": Color(0.3, 0.85, 0.3),         # Green
	"failure": Color(0.9, 0.85, 0.2),         # Yellow
	"detection": Color(0.3, 0.85, 0.9),       # Cyan
	"trap": Color(0.9, 0.25, 0.2),            # Red
	"encounter": Color(0.95, 0.2, 0.2),       # Red bold
	"resource": Color(0.9, 0.6, 0.15),        # Orange
	"combat_transition": Color(0.95, 0.2, 0.2), # Red bold
	"unreachable": Color(0.55, 0.55, 0.55),   # Grey
	"item": Color(0.85, 0.85, 0.85),          # White
	"info": Color(0.7, 0.7, 0.8),             # Light grey
}

const MAX_ENTRIES := 200
const LOG_WIDTH := 280.0
const LOG_HEIGHT := 200.0


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _scroll: ScrollContainer = null
var _vbox: VBoxContainer = null
var _entry_count: int = 0
var _auto_scroll: bool = true


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	custom_minimum_size = Vector2(LOG_WIDTH, LOG_HEIGHT)

	# Dark panel style.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.04, 0.08, 0.85)
	style.border_color = Color(0.3, 0.3, 0.4, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(4)
	add_theme_stylebox_override("panel", style)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.follow_focus = true
	add_child(_scroll)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 2)
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_vbox)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Add a log entry.
## [param category]: determines color (see CATEGORY_COLORS).
## [param text]: the message text.
## [param cell]: grid position for click-to-center (Vector2i(-1,-1) = no location).
func add_entry(category: String, text: String, cell: Vector2i = Vector2i(-1, -1)) -> void:
	var color: Color = CATEGORY_COLORS.get(category, CATEGORY_COLORS["info"])

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Bold for encounters and combat transitions.
	if category in ["encounter", "combat_transition"]:
		label.add_theme_font_size_override("font_size", 12)

	# Make clickable if cell is valid.
	if cell != Vector2i(-1, -1):
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		label.gui_input.connect(_on_entry_clicked.bind(cell))
		label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	_vbox.add_child(label)
	_entry_count += 1

	# Cap entries.
	if _entry_count > MAX_ENTRIES:
		var first := _vbox.get_child(0)
		if first != null:
			first.queue_free()
			_entry_count -= 1

	# Auto-scroll to bottom.
	if _auto_scroll:
		await get_tree().process_frame
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


## Clear all entries.
func clear_log() -> void:
	for child in _vbox.get_children():
		child.queue_free()
	_entry_count = 0


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _on_entry_clicked(event: InputEvent, cell: Vector2i) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		log_entry_clicked.emit(cell)
