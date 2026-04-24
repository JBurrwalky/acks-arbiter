extends PanelContainer

## Horizontal bar showing control group slots [1]-[9] for dungeon exploration.
##
## Each slot shows group number, compact member count, and movement mode pip.
## Left-click selects group, right-click opens group options (future).

signal group_clicked(group_number: int)
signal group_double_clicked(group_number: int)
signal group_right_clicked(group_number: int)


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const SLOT_COUNT := 9
const SLOT_SIZE := Vector2(36, 36)

const MODE_COLORS := {
	"exploration": Color(0.3, 0.8, 0.3),
	"combat": Color(0.9, 0.8, 0.2),
	"running": Color(0.9, 0.3, 0.2),
}


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _hbox: HBoxContainer = null
var _slots: Array = []  # Array of PanelContainer


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Dark bar style.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.10, 0.85)
	style.border_color = Color(0.3, 0.3, 0.4, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(4)
	add_theme_stylebox_override("panel", style)

	_hbox = HBoxContainer.new()
	_hbox.add_theme_constant_override("separation", 4)
	_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_hbox)

	for i in range(1, SLOT_COUNT + 1):
		var slot := _create_slot(i)
		_hbox.add_child(slot)
		_slots.append(slot)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Update all slots from session state.
## [param session_state]: DungeonSessionState (or null to clear).
## [param party_data]: PartyData for member info (or null).
func update_groups(session_state, party_data = null) -> void:
	for i in range(SLOT_COUNT):
		var group_num: int = i + 1
		var slot: PanelContainer = _slots[i]
		var count_label: Label = slot.get_node("CountLabel")
		var num_label: Label = slot.get_node("NumLabel")
		var check_label: Label = slot.get_node_or_null("CheckLabel")

		if session_state == null:
			count_label.text = ""
			slot.modulate = Color(0.4, 0.4, 0.4, 0.5)
			if check_label != null:
				check_label.visible = false
			continue

		var members = session_state.get_group(group_num)
		if members.is_empty():
			count_label.text = ""
			slot.modulate = Color(0.4, 0.4, 0.4, 0.5)
			if check_label != null:
				check_label.visible = false
		else:
			count_label.text = str(members.size())
			slot.modulate = Color(1.0, 1.0, 1.0, 1.0)
			if check_label != null:
				check_label.visible = true


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _create_slot(group_number: int) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = SLOT_SIZE

	var slot_style := StyleBoxFlat.new()
	slot_style.bg_color = Color(0.12, 0.12, 0.16, 0.9)
	slot_style.border_color = Color(0.35, 0.35, 0.45, 0.7)
	slot_style.set_border_width_all(1)
	slot_style.set_corner_radius_all(3)
	slot.add_theme_stylebox_override("panel", slot_style)

	# Group number label (top-left, small).
	var num_label := Label.new()
	num_label.name = "NumLabel"
	num_label.text = str(group_number)
	num_label.add_theme_font_size_override("font_size", 10)
	num_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	num_label.position = Vector2(2, 0)
	slot.add_child(num_label)

	# Member count (center).
	var count_label := Label.new()
	count_label.name = "CountLabel"
	count_label.text = ""
	count_label.add_theme_font_size_override("font_size", 14)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count_label.anchors_preset = Control.PRESET_FULL_RECT
	slot.add_child(count_label)

	# Filled-group checkmark indicator (top-right, hidden until update_groups
	# reveals it for groups with at least one member). Placeholder until an
	# icon asset replaces the glyph.
	var check_label := Label.new()
	check_label.name = "CheckLabel"
	check_label.text = "✓"
	check_label.add_theme_font_size_override("font_size", 10)
	check_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
	check_label.position = Vector2(SLOT_SIZE.x - 11, 0)
	check_label.visible = false
	slot.add_child(check_label)

	# Make clickable.
	slot.gui_input.connect(_on_slot_input.bind(group_number))
	slot.mouse_filter = Control.MOUSE_FILTER_STOP

	return slot


func _on_slot_input(event: InputEvent, group_number: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if event.double_click:
					group_double_clicked.emit(group_number)
				else:
					group_clicked.emit(group_number)
			MOUSE_BUTTON_RIGHT:
				group_right_clicked.emit(group_number)
