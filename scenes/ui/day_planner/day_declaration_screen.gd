class_name DayDeclarationScreen
extends Control

## Day declaration UI — 8-slot activity assignment for wilderness exploration.
##
## Players assign activities (March, Explore, Rest, Forage, Hunt, Guard,
## Craft, Free) to each of the 8 time slots. Shows estimated travel distance,
## encounter check count, and resource consumption.

signal day_confirmed(budget: DayBudgetManager)
signal day_cancelled

const HEADING_COLOR := Color(0.95, 0.90, 0.78, 1.0)
const BODY_COLOR := Color(0.85, 0.80, 0.70, 1.0)
const DIM_COLOR := Color(0.55, 0.50, 0.42, 1.0)
const SLOT_SIZE := Vector2(80, 80)

var _budget: DayBudgetManager = null
var _slot_buttons: Array[Button] = []
var _summary_label: Label = null
var _error_label: Label = null
var _confirm_btn: Button = null
var _content: VBoxContainer = null


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)


func setup(budget: DayBudgetManager) -> void:
	_budget = budget
	_build_ui()
	_update_summary()


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	_clear()

	var bg := PanelContainer.new()
	bg.set_anchors_preset(PRESET_FULL_RECT)
	UiSurfaceStyles.apply_framed_window_chrome(bg)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	bg.add_child(margin)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 14)
	_content.size_flags_horizontal = SIZE_EXPAND_FILL
	margin.add_child(_content)

	_content.add_child(_heading("Plan the Day"))
	_content.add_child(_body(
		"Assign activities to each hour of daylight. "
		+ "Click a slot to cycle through activity types."))

	# Slot grid.
	var slot_bar := HBoxContainer.new()
	slot_bar.add_theme_constant_override("separation", 8)
	slot_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.add_child(slot_bar)

	_slot_buttons.clear()
	for i in range(DayBudgetManager.SLOT_COUNT):
		var slot_btn := _create_slot_button(i)
		slot_bar.add_child(slot_btn)
		_slot_buttons.append(slot_btn)

	# Legend.
	var legend := _build_legend()
	_content.add_child(legend)

	# Summary.
	_summary_label = _body("")
	_content.add_child(_summary_label)

	# Error label.
	_error_label = Label.new()
	_error_label.add_theme_font_size_override("font_size", 13)
	_error_label.add_theme_color_override("font_color", Color(0.75, 0.22, 0.18, 1.0))
	_error_label.visible = false
	_content.add_child(_error_label)

	# Buttons.
	var btn_bar := HBoxContainer.new()
	btn_bar.add_theme_constant_override("separation", 16)
	btn_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.add_child(btn_bar)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.add_theme_font_size_override("font_size", 14)
	cancel_btn.custom_minimum_size = Vector2(100, 38)
	cancel_btn.pressed.connect(func(): day_cancelled.emit())
	btn_bar.add_child(cancel_btn)

	_confirm_btn = Button.new()
	_confirm_btn.text = "Begin Day"
	_confirm_btn.add_theme_font_size_override("font_size", 14)
	_confirm_btn.custom_minimum_size = Vector2(120, 38)
	_confirm_btn.pressed.connect(func():
		var error := _budget.validate()
		if not error.is_empty():
			_error_label.text = error
			_error_label.visible = true
			return
		day_confirmed.emit(_budget)
	)
	btn_bar.add_child(_confirm_btn)


func _create_slot_button(index: int) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = SLOT_SIZE
	_update_slot_button(btn, index)

	btn.pressed.connect(func():
		# Cycle to next slot type.
		var current: int = _budget.get_slot(index)
		var next: int = (current + 1) % DayBudgetManager.SlotType.size()
		_budget.set_slot(index, next)
		_update_slot_button(btn, index)
		_update_summary()
	)

	return btn


func _update_slot_button(btn: Button, index: int) -> void:
	var slot_type: int = _budget.get_slot(index)
	var color: Color = _budget.get_slot_color(slot_type)
	var name_str: String = _budget.get_slot_name(slot_type)

	btn.text = "%s\n%d" % [name_str, index + 1]
	btn.tooltip_text = "Hour %d: %s (click to change)" % [index + 1, name_str]

	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.35, 0.30, 0.22, 0.8)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	btn.add_theme_stylebox_override("normal", style)

	var hover := style.duplicate()
	hover.border_color = Color(0.75, 0.65, 0.45, 1.0)
	btn.add_theme_stylebox_override("hover", hover)

	btn.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85, 1.0))
	btn.add_theme_font_size_override("font_size", 11)


func _build_legend() -> HBoxContainer:
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 12)
	legend.alignment = BoxContainer.ALIGNMENT_CENTER

	for slot_type in DayBudgetManager.SlotType.values():
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 4)

		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(12, 12)
		swatch.color = _budget.get_slot_color(slot_type)
		item.add_child(swatch)

		var label := Label.new()
		label.text = _budget.get_slot_name(slot_type)
		label.add_theme_font_size_override("font_size", 10)
		label.add_theme_color_override("font_color", DIM_COLOR)
		item.add_child(label)

		legend.add_child(item)

	return legend


# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

func _update_summary() -> void:
	if _summary_label == null or _budget == null:
		return

	var march := _budget.count_slots(DayBudgetManager.SlotType.MARCH)
	var explore := _budget.count_slots(DayBudgetManager.SlotType.EXPLORE)
	var rest := _budget.count_slots(DayBudgetManager.SlotType.REST)
	var checks := _budget.estimate_encounter_checks()

	_summary_label.text = (
		"March: %d slots | Explore: %d | Rest: %d | Encounter checks: ~%d"
		% [march, explore, rest, checks])

	# Validate and show error.
	var error := _budget.validate()
	if not error.is_empty():
		_error_label.text = error
		_error_label.visible = true
	else:
		_error_label.visible = false


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _clear() -> void:
	for child in get_children():
		child.queue_free()
	_content = null
	_slot_buttons.clear()


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", HEADING_COLOR)
	return label


func _body(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", BODY_COLOR)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
