extends PanelContainer

## Right-side exploration panel for dungeon individual movement.
##
## Shows:
## - Character list with name, class, HP, current order status
## - Click to select character on map; Shift+click for multi-select
## - Per-character order buttons: Move, Search, Listen, Wait
## - End Turn button
## - Reform Formation button
## - Formation preset dropdown
##
## All actions emit signals — wired by DungeonExploreState.


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal character_selected(character_id: String)
signal character_deselected(character_id: String)
signal select_all_pressed()
signal end_turn_pressed()
signal reform_formation_pressed()
signal order_type_selected(order_type: String)
signal formation_preset_selected(preset_name: String)


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const ORDER_STATUS_ICONS := {
	"move": ">",
	"search": "?",
	"listen": "~",
	"wait": ".",
	"interact_door": "D",
	"": "-",
}


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

## Array of {character_id, display_name, class_letter, hp_current, hp_max, order_status}
var _character_list: Array = []
var _selected_ids: Array[String] = []
var _current_order_type: String = "move"

## UI references
var _char_list_container: VBoxContainer = null
var _char_rows: Dictionary = {}  # character_id -> HBoxContainer
var _order_buttons: Dictionary = {}  # order_type -> Button
var _end_turn_btn: Button = null
var _reform_btn: Button = null
var _preset_dropdown: OptionButton = null
var _select_all_btn: Button = null


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	custom_minimum_size = Vector2(210, 0)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.85)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	add_theme_stylebox_override("panel", style)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	add_child(outer)

	# Title
	var title := Label.new()
	title.text = "Party"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	outer.add_child(title)

	var sep1 := HSeparator.new()
	outer.add_child(sep1)

	# Character list (scrollable)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	_char_list_container = VBoxContainer.new()
	_char_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_char_list_container.add_theme_constant_override("separation", 2)
	scroll.add_child(_char_list_container)

	# Select All button
	_select_all_btn = Button.new()
	_select_all_btn.text = "Select All"
	_select_all_btn.custom_minimum_size.y = 24.0
	_select_all_btn.pressed.connect(func(): select_all_pressed.emit())
	outer.add_child(_select_all_btn)

	var sep2 := HSeparator.new()
	outer.add_child(sep2)

	# Order type buttons
	var order_label := Label.new()
	order_label.text = "Order"
	order_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	order_label.add_theme_font_size_override("font_size", 11)
	order_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	outer.add_child(order_label)

	var order_row := HBoxContainer.new()
	order_row.add_theme_constant_override("separation", 3)
	order_row.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_child(order_row)

	var order_defs := [
		{"id": "move", "label": "Move", "shortcut": "M"},
		{"id": "search", "label": "Search", "shortcut": "S"},
		{"id": "listen", "label": "Listen", "shortcut": "L"},
		{"id": "wait", "label": "Wait", "shortcut": "W"},
	]
	for odef in order_defs:
		var btn := Button.new()
		btn.text = odef["shortcut"]
		btn.tooltip_text = odef["label"]
		btn.custom_minimum_size = Vector2(36, 28)
		var oid: String = odef["id"]
		btn.pressed.connect(_on_order_type_pressed.bind(oid))
		order_row.add_child(btn)
		_order_buttons[oid] = btn

	# Highlight current order type
	_highlight_order_button("move")

	var sep3 := HSeparator.new()
	outer.add_child(sep3)

	# Formation preset dropdown
	var form_label := Label.new()
	form_label.text = "Formation"
	form_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	form_label.add_theme_font_size_override("font_size", 11)
	form_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	outer.add_child(form_label)

	_preset_dropdown = OptionButton.new()
	_preset_dropdown.add_item("Column")
	_preset_dropdown.add_item("Double Column")
	_preset_dropdown.add_item("Line")
	_preset_dropdown.add_item("Double Line")
	_preset_dropdown.add_item("Wedge")
	_preset_dropdown.selected = 0
	_preset_dropdown.item_selected.connect(_on_preset_selected)
	outer.add_child(_preset_dropdown)

	_reform_btn = Button.new()
	_reform_btn.text = "Reform Formation"
	_reform_btn.custom_minimum_size.y = 28.0
	_reform_btn.pressed.connect(func(): reform_formation_pressed.emit())
	outer.add_child(_reform_btn)

	var sep4 := HSeparator.new()
	outer.add_child(sep4)

	# End Turn button
	_end_turn_btn = Button.new()
	_end_turn_btn.text = "End Turn"
	_end_turn_btn.custom_minimum_size.y = 36.0
	_end_turn_btn.pressed.connect(func(): end_turn_pressed.emit())
	outer.add_child(_end_turn_btn)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Set the character list. Each entry:
## {character_id, display_name, class_letter, hp_current, hp_max, order_status}
func set_characters(characters: Array) -> void:
	_character_list = characters
	_rebuild_character_list()


## Update the order status icon for a single character.
func update_order_status(character_id: String, order_type: String) -> void:
	var row: HBoxContainer = _char_rows.get(character_id)
	if row == null:
		return
	var status_label: Label = row.get_node_or_null("OrderStatus")
	if status_label != null:
		status_label.text = ORDER_STATUS_ICONS.get(order_type, "-")


## Update HP display for a single character.
func update_hp(character_id: String, hp_current: int, hp_max: int) -> void:
	var row: HBoxContainer = _char_rows.get(character_id)
	if row == null:
		return
	var hp_label: Label = row.get_node_or_null("HPLabel")
	if hp_label != null:
		hp_label.text = "%d/%d" % [hp_current, hp_max]
		var ratio := 0.0 if hp_max <= 0 else float(hp_current) / float(hp_max)
		if ratio > 0.5:
			hp_label.add_theme_color_override("font_color", Color(0.3, 0.8, 0.3))
		elif ratio > 0.25:
			hp_label.add_theme_color_override("font_color", Color(0.8, 0.7, 0.2))
		else:
			hp_label.add_theme_color_override("font_color", Color(0.8, 0.2, 0.2))


## Mark a character as selected (highlight row).
func set_selected(character_id: String, is_selected: bool) -> void:
	if is_selected and character_id not in _selected_ids:
		_selected_ids.append(character_id)
	elif not is_selected:
		_selected_ids.erase(character_id)
	_update_row_highlights()


## Clear all selections.
func clear_selection() -> void:
	_selected_ids.clear()
	_update_row_highlights()


## Returns the currently active order type.
func get_current_order_type() -> String:
	return _current_order_type


## Returns currently selected character IDs.
func get_selected_ids() -> Array[String]:
	return _selected_ids.duplicate()


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _rebuild_character_list() -> void:
	_char_rows.clear()
	for child in _char_list_container.get_children():
		child.queue_free()

	for entry in _character_list:
		var cid: String = entry.get("character_id", "")
		var row := _create_character_row(entry)
		_char_list_container.add_child(row)
		_char_rows[cid] = row

	_update_row_highlights()


func _create_character_row(entry: Dictionary) -> HBoxContainer:
	var cid: String = entry.get("character_id", "")
	var dname: String = entry.get("display_name", "???")
	var class_letter: String = entry.get("class_letter", "?")
	var hp_cur: int = entry.get("hp_current", 0)
	var hp_max: int = entry.get("hp_max", 1)
	var order_status: String = entry.get("order_status", "")

	var row := HBoxContainer.new()
	row.name = cid
	row.custom_minimum_size.y = 24.0
	row.add_theme_constant_override("separation", 3)

	# Make the row clickable via an invisible button overlay
	var click_btn := Button.new()
	click_btn.name = "ClickBtn"
	click_btn.flat = true
	click_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	click_btn.custom_minimum_size.y = 24.0
	click_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	click_btn.pressed.connect(_on_character_row_clicked.bind(cid))

	# Class letter
	var cls_label := Label.new()
	cls_label.text = class_letter
	cls_label.custom_minimum_size.x = 14.0
	cls_label.add_theme_font_size_override("font_size", 11)
	cls_label.add_theme_color_override("font_color", Color(0.5, 0.7, 1.0))
	row.add_child(cls_label)

	# Name
	var name_label := Label.new()
	name_label.name = "NameLabel"
	name_label.text = dname
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.add_theme_font_size_override("font_size", 11)
	row.add_child(name_label)

	# HP
	var hp_label := Label.new()
	hp_label.name = "HPLabel"
	hp_label.text = "%d/%d" % [hp_cur, hp_max]
	hp_label.custom_minimum_size.x = 38.0
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hp_label.add_theme_font_size_override("font_size", 10)
	row.add_child(hp_label)

	# Order status icon
	var status_label := Label.new()
	status_label.name = "OrderStatus"
	status_label.text = ORDER_STATUS_ICONS.get(order_status, "-")
	status_label.custom_minimum_size.x = 14.0
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 11)
	status_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.3))
	row.add_child(status_label)

	# Overlay the click button on the row
	row.add_child(click_btn)
	click_btn.set_anchors_preset(Control.PRESET_FULL_RECT)

	return row


func _on_character_row_clicked(character_id: String) -> void:
	if character_id in _selected_ids:
		_selected_ids.erase(character_id)
		character_deselected.emit(character_id)
	else:
		# Single select by default (shift-click multi-select handled by renderer)
		_selected_ids.clear()
		_selected_ids.append(character_id)
		character_selected.emit(character_id)
	_update_row_highlights()


func _update_row_highlights() -> void:
	for cid in _char_rows:
		var row: HBoxContainer = _char_rows[cid]
		if cid in _selected_ids:
			row.modulate = Color(1.3, 1.3, 1.0)
		else:
			row.modulate = Color.WHITE


func _on_order_type_pressed(order_type: String) -> void:
	_current_order_type = order_type
	_highlight_order_button(order_type)
	order_type_selected.emit(order_type)


func _highlight_order_button(active_type: String) -> void:
	for oid in _order_buttons:
		var btn: Button = _order_buttons[oid]
		if oid == active_type:
			btn.modulate = Color(1.0, 1.0, 0.5)
		else:
			btn.modulate = Color.WHITE


const _PRESET_NAMES := ["column", "double_column", "line", "double_line", "wedge"]

func _on_preset_selected(index: int) -> void:
	if index >= 0 and index < _PRESET_NAMES.size():
		formation_preset_selected.emit(_PRESET_NAMES[index])
