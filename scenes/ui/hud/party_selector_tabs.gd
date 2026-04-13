class_name PartySelectorTabs
extends HBoxContainer

## Tab bar for switching between multiple active parties.
##
## Shows one tab per party. Each tab displays party name, member count,
## location summary, and activity icon. Click to switch active party.
## Only visible when more than one party exists.

signal party_selected(party_id: String)
signal split_requested

const TAB_MIN_WIDTH := 140
const TAB_HEIGHT := 32
const ACTIVE_COLOR := Color(0.30, 0.45, 0.25, 1.0)
const INACTIVE_COLOR := Color(0.18, 0.15, 0.12, 0.8)
const BORDER_COLOR := Color(0.46, 0.33, 0.19, 0.8)
const LABEL_COLOR := Color(0.85, 0.80, 0.70, 1.0)
const DIM_COLOR := Color(0.55, 0.50, 0.42, 1.0)

var _parties: Array[Dictionary] = []
var _active_party_id: String = ""
var _split_btn: Button = null


func _ready() -> void:
	add_theme_constant_override("separation", 4)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func update_parties(parties: Array[Dictionary], active_id: String) -> void:
	## Update the tab display.
	## parties: [{id, name, member_count, location, activity}]
	_parties = parties
	_active_party_id = active_id
	_rebuild()


func set_active(party_id: String) -> void:
	_active_party_id = party_id
	_rebuild()


# ---------------------------------------------------------------------------
# UI rebuild
# ---------------------------------------------------------------------------

func _rebuild() -> void:
	for child in get_children():
		child.queue_free()

	# Hide if only one party.
	visible = _parties.size() > 1

	for party in _parties:
		var tab := _create_tab(party)
		add_child(tab)

	# Split party button.
	_split_btn = Button.new()
	_split_btn.text = "+"
	_split_btn.flat = true
	_split_btn.tooltip_text = "Split Party"
	_split_btn.add_theme_font_size_override("font_size", 14)
	_split_btn.add_theme_color_override("font_color", DIM_COLOR)
	_split_btn.custom_minimum_size = Vector2(28, TAB_HEIGHT)
	_split_btn.pressed.connect(func(): split_requested.emit())
	add_child(_split_btn)


func _create_tab(party: Dictionary) -> PanelContainer:
	var pid: String = party.get("id", "")
	var is_active := pid == _active_party_id

	var tab := PanelContainer.new()
	tab.custom_minimum_size = Vector2(TAB_MIN_WIDTH, TAB_HEIGHT)

	var style := StyleBoxFlat.new()
	style.bg_color = ACTIVE_COLOR if is_active else INACTIVE_COLOR
	style.border_color = BORDER_COLOR
	style.border_width_bottom = 2 if is_active else 1
	style.border_width_top = 1
	style.border_width_left = 1
	style.border_width_right = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	tab.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	tab.add_child(hbox)

	# Party name.
	var name_label := Label.new()
	name_label.text = party.get("name", "Party")
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", LABEL_COLOR)
	name_label.size_flags_horizontal = SIZE_EXPAND_FILL
	hbox.add_child(name_label)

	# Member count.
	var count_label := Label.new()
	count_label.text = str(party.get("member_count", 0))
	count_label.add_theme_font_size_override("font_size", 10)
	count_label.add_theme_color_override("font_color", DIM_COLOR)
	hbox.add_child(count_label)

	# Activity icon.
	var activity: String = party.get("activity", "exploring")
	var icon_map := {
		"exploring": ">",
		"camping": "z",
		"in_combat": "!",
		"in_settlement": "^",
	}
	var icon_label := Label.new()
	icon_label.text = icon_map.get(activity, ">")
	icon_label.add_theme_font_size_override("font_size", 10)
	icon_label.add_theme_color_override("font_color", DIM_COLOR)
	hbox.add_child(icon_label)

	# Click to select.
	if not is_active:
		tab.mouse_filter = MOUSE_FILTER_STOP
		tab.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				party_selected.emit(pid)
		)

	return tab
