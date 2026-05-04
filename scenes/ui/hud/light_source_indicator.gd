extends CanvasLayer

## LightSourceIndicator — top-right HUD widget showing the party's current
## light source and remaining duration. Per gdd-ui-architecture.md §7.1.
##
## Subscribes to three EventBus signals (H.3 item 1):
##   light_source_activated(state)   — show + render
##   light_source_ticked(state)      — re-render remaining turns
##   light_source_deactivated        — hide
##
## Layer 24 — between InitiativeOverlay (25) and the SessionStatusBar
## widget zone, anchored top-right and floating below any other top-right
## widgets (LevelStripWidget anchors to the same edge).
##
## Visibility is purely signal-driven: hidden by default, shown when a
## tracker activates, hidden when deactivated or expired. No polling.
##
## Per LightSourceTracker.WARNING_THRESHOLDS [5, 2, 0], the visual state
## escalates: green/normal → yellow/flickering at ≤5 → red/danger at ≤2.


const OVERLAY_LAYER := 24
const PANEL_WIDTH := 200.0
const TOP_OFFSET := 240.0      # below LevelStripWidget which sits ~10px from top
const RIGHT_OFFSET := 10.0
const BOTTOM_PADDING := 6

const COLOR_NORMAL := Color(0.95, 0.90, 0.55, 1.0)    # warm yellow
const COLOR_FLICKERING := Color(0.95, 0.65, 0.30, 1.0) # orange
const COLOR_DANGER := Color(0.85, 0.30, 0.25, 1.0)     # red
const HEADING_COLOR := Color(0.95, 0.90, 0.78, 1.0)
const DIM_COLOR := Color(0.55, 0.50, 0.42, 1.0)

const FLICKERING_THRESHOLD := 5
const DANGER_THRESHOLD := 2


var _root: PanelContainer = null
var _heading_label: Label = null
var _remaining_label: Label = null
var _radius_label: Label = null


func _ready() -> void:
	layer = OVERLAY_LAYER
	visible = false
	add_to_group("light_source_indicator")
	_build_ui()
	_connect_signals()


func _build_ui() -> void:
	_root = PanelContainer.new()
	_root.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_root.offset_left = -(PANEL_WIDTH + RIGHT_OFFSET)
	_root.offset_right = -RIGHT_OFFSET
	_root.offset_top = TOP_OFFSET
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.10, 0.08, 0.85)
	style.border_color = Color(0.46, 0.33, 0.19, 0.55)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	_root.add_theme_stylebox_override("panel", style)
	add_child(_root)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	_root.add_child(v)

	_heading_label = Label.new()
	_heading_label.add_theme_font_size_override("font_size", 12)
	_heading_label.add_theme_color_override("font_color", HEADING_COLOR)
	v.add_child(_heading_label)

	_remaining_label = Label.new()
	_remaining_label.add_theme_font_size_override("font_size", 11)
	_remaining_label.add_theme_color_override("font_color", COLOR_NORMAL)
	v.add_child(_remaining_label)

	_radius_label = Label.new()
	_radius_label.add_theme_font_size_override("font_size", 10)
	_radius_label.add_theme_color_override("font_color", DIM_COLOR)
	v.add_child(_radius_label)


func _connect_signals() -> void:
	EventBus.light_source_activated.connect(_on_light_state)
	EventBus.light_source_ticked.connect(_on_light_state)
	EventBus.light_source_deactivated.connect(_on_light_deactivated)


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_light_state(state: Dictionary) -> void:
	visible = true
	var source_type: String = str(state.get("source_type", ""))
	var remaining: int = int(state.get("remaining_turns", 0))
	var radius: int = int(state.get("radius_feet", 0))
	_heading_label.text = _display_name(source_type)
	if remaining < 0:
		_remaining_label.text = "Permanent"
		_remaining_label.add_theme_color_override("font_color", COLOR_NORMAL)
	else:
		_remaining_label.text = "%d turn%s remaining" % [
			remaining, ("" if remaining == 1 else "s")]
		_remaining_label.add_theme_color_override("font_color",
			_color_for_remaining(remaining))
	_radius_label.text = "%d ft radius" % radius if radius > 0 else ""


func _on_light_deactivated() -> void:
	visible = false


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _color_for_remaining(remaining: int) -> Color:
	if remaining <= DANGER_THRESHOLD:
		return COLOR_DANGER
	if remaining <= FLICKERING_THRESHOLD:
		return COLOR_FLICKERING
	return COLOR_NORMAL


func _display_name(source_type: String) -> String:
	if source_type.is_empty():
		return "(no light)"
	return source_type.capitalize().replace("_", " ")
