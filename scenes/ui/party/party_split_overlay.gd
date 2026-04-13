class_name PartySplitOverlay
extends CanvasLayer

## Overlay for splitting a party into two groups.
##
## Two columns: "Stay" and "New Party". Characters can be dragged between
## columns. Henchmen auto-follow their employer. Confirm creates a new party.

signal split_confirmed(stay_ids: Array, new_party_ids: Array)
signal split_cancelled

const HEADING_COLOR := Color(0.95, 0.90, 0.78, 1.0)
const BODY_COLOR := Color(0.85, 0.80, 0.70, 1.0)
const DIM_COLOR := Color(0.55, 0.50, 0.42, 1.0)
const CHIP_BG := Color(0.22, 0.18, 0.14, 0.9)
const CHIP_SELECTED := Color(0.30, 0.45, 0.25, 0.9)

var _backdrop: ColorRect = null
var _panel: PanelContainer = null
var _stay_list: VBoxContainer = null
var _new_list: VBoxContainer = null
var _confirm_btn: Button = null
var _members: Array[Dictionary] = []
var _new_party_ids: Array[String] = []


func _ready() -> void:
	layer = 110
	_build_ui()
	_hide_all()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func open(party_members: Array[Dictionary]) -> void:
	_members = party_members
	_new_party_ids.clear()
	_rebuild_lists()
	_show_all()


func close() -> void:
	_hide_all()


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	_backdrop = ColorRect.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = Color(0.0, 0.0, 0.0, 0.55)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_backdrop)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(650, 400)
	_panel.offset_left = -325
	_panel.offset_right = 325
	_panel.offset_top = -200
	_panel.offset_bottom = 200
	UiSurfaceStyles.apply_framed_window_chrome(_panel)
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 16)
	_panel.add_child(margin)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	margin.add_child(outer)

	var title := Label.new()
	title.text = "Split Party"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", HEADING_COLOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(title)

	outer.add_child(_dim_label(
		"Click characters to move them between groups. "
		+ "Henchmen automatically follow their employer."))

	# Two columns.
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(columns)

	# Stay column.
	var stay_col := _build_column("Stay", columns)
	_stay_list = stay_col

	# New party column.
	var new_col := _build_column("New Party", columns)
	_new_list = new_col

	# Buttons.
	var btn_bar := HBoxContainer.new()
	btn_bar.add_theme_constant_override("separation", 16)
	btn_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_child(btn_bar)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.add_theme_font_size_override("font_size", 14)
	cancel_btn.custom_minimum_size = Vector2(100, 36)
	cancel_btn.pressed.connect(func():
		_hide_all()
		split_cancelled.emit()
	)
	btn_bar.add_child(cancel_btn)

	_confirm_btn = Button.new()
	_confirm_btn.text = "Confirm Split"
	_confirm_btn.add_theme_font_size_override("font_size", 14)
	_confirm_btn.custom_minimum_size = Vector2(120, 36)
	_confirm_btn.pressed.connect(_on_confirm)
	btn_bar.add_child(_confirm_btn)


func _build_column(header_text: String, parent: Control) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	parent.add_child(col)

	var header := Label.new()
	header.text = header_text
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", HEADING_COLOR)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(header)

	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", UiSurfaceStyles.FRAME_BORDER_COLOR)
	col.add_child(sep)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)

	return list


# ---------------------------------------------------------------------------
# List management
# ---------------------------------------------------------------------------

func _rebuild_lists() -> void:
	for child in _stay_list.get_children():
		child.queue_free()
	for child in _new_list.get_children():
		child.queue_free()

	for member in _members:
		var char_id: String = member.get("id", "")
		var is_new := char_id in _new_party_ids
		var chip := _create_chip(member, is_new)

		if is_new:
			_new_list.add_child(chip)
		else:
			_stay_list.add_child(chip)

	# Validate: need at least 1 in each group.
	var stay_count := _members.size() - _new_party_ids.size()
	_confirm_btn.disabled = _new_party_ids.is_empty() or stay_count <= 0


func _create_chip(member: Dictionary, in_new_party: bool) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.custom_minimum_size = Vector2(0, 32)

	var style := StyleBoxFlat.new()
	style.bg_color = CHIP_SELECTED if in_new_party else CHIP_BG
	style.border_color = Color(0.35, 0.30, 0.22, 0.6)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	chip.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	chip.add_child(hbox)

	var name_label := Label.new()
	name_label.text = member.get("name", "Unknown")
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", BODY_COLOR)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(name_label)

	var class_label := Label.new()
	class_label.text = member.get("character_class", "").capitalize()
	class_label.add_theme_font_size_override("font_size", 11)
	class_label.add_theme_color_override("font_color", DIM_COLOR)
	hbox.add_child(class_label)

	var hp_label := Label.new()
	hp_label.text = "HP %d/%d" % [member.get("hp_current", 0), member.get("hp_max", 0)]
	hp_label.add_theme_font_size_override("font_size", 11)
	hp_label.add_theme_color_override("font_color", DIM_COLOR)
	hbox.add_child(hp_label)

	# Click to toggle.
	var char_id: String = member.get("id", "")
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	chip.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_toggle_member(char_id)
	)

	return chip


func _toggle_member(char_id: String) -> void:
	if char_id in _new_party_ids:
		_new_party_ids.erase(char_id)
	else:
		_new_party_ids.append(char_id)

	# Auto-follow: move henchmen with their employer.
	for member in _members:
		var mid: String = member.get("id", "")
		var employer: String = member.get("employer_id", "")
		if not employer.is_empty():
			if employer in _new_party_ids and mid not in _new_party_ids:
				_new_party_ids.append(mid)
			elif employer not in _new_party_ids and mid in _new_party_ids:
				_new_party_ids.erase(mid)

	_rebuild_lists()


# ---------------------------------------------------------------------------
# Confirm / Cancel
# ---------------------------------------------------------------------------

func _on_confirm() -> void:
	var stay_ids: Array = []
	for member in _members:
		var mid: String = member.get("id", "")
		if mid not in _new_party_ids:
			stay_ids.append(mid)

	_hide_all()
	split_confirmed.emit(stay_ids, _new_party_ids.duplicate())


func _show_all() -> void:
	_backdrop.visible = true
	_panel.visible = true


func _hide_all() -> void:
	_backdrop.visible = false
	_panel.visible = false


func _dim_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", DIM_COLOR)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label
