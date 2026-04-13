class_name DayDeclarationScreen
extends CanvasLayer

## Day declaration UI — 8-slot activity assignment for wilderness exploration.
##
## Players assign activities via dropdown selectors for each of the 8 time
## slots. Shows estimated travel distance, encounter check count, and
## resource consumption.

signal day_confirmed(budget: DayBudgetManager)
signal day_cancelled

const HEADING_COLOR := Color(0.95, 0.90, 0.78, 1.0)
const BODY_COLOR := Color(0.85, 0.80, 0.70, 1.0)
const DIM_COLOR := Color(0.55, 0.50, 0.42, 1.0)

var _budget: DayBudgetManager = null
var _slot_dropdowns: Array[OptionButton] = []
var _slot_swatches: Array[ColorRect] = []
var _summary_label: Label = null
var _error_label: Label = null
var _confirm_btn: Button = null


func _ready() -> void:
	layer = 50


func setup(budget: DayBudgetManager) -> void:
	_budget = budget
	_build_ui()
	_update_summary()


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var bg := PanelContainer.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	UiSurfaceStyles.apply_framed_window_chrome(bg)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 60)
	bg.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(content)

	content.add_child(_heading("Plan the Day"))
	content.add_child(_body(
		"Assign an activity to each hour of daylight using the dropdowns below."))

	# Slot grid — each slot is a row with hour label, color swatch, dropdown.
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	content.add_child(grid)

	_slot_dropdowns.clear()
	_slot_swatches.clear()
	for i in range(DayBudgetManager.SLOT_COUNT):
		# Hour label.
		var hour_label := Label.new()
		hour_label.text = "Hour %d:" % (i + 1)
		hour_label.add_theme_font_size_override("font_size", 13)
		hour_label.add_theme_color_override("font_color", BODY_COLOR)
		hour_label.custom_minimum_size = Vector2(60, 0)
		grid.add_child(hour_label)

		# Color swatch.
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(20, 20)
		swatch.color = _budget.get_slot_color(_budget.get_slot(i))
		grid.add_child(swatch)
		_slot_swatches.append(swatch)

		# Dropdown.
		var dropdown := OptionButton.new()
		dropdown.custom_minimum_size = Vector2(140, 28)
		dropdown.add_theme_font_size_override("font_size", 12)
		for slot_type in DayBudgetManager.SlotType.values():
			dropdown.add_item(_budget.get_slot_name(slot_type), slot_type)
		dropdown.selected = _budget.get_slot(i)
		var slot_index: int = i
		dropdown.item_selected.connect(func(idx: int):
			_on_slot_changed(slot_index, idx))
		grid.add_child(dropdown)
		_slot_dropdowns.append(dropdown)

	# Summary.
	_summary_label = _body("")
	content.add_child(_summary_label)

	# Error label.
	_error_label = Label.new()
	_error_label.add_theme_font_size_override("font_size", 13)
	_error_label.add_theme_color_override("font_color", Color(0.75, 0.22, 0.18, 1.0))
	_error_label.visible = false
	content.add_child(_error_label)

	# Buttons.
	var btn_bar := HBoxContainer.new()
	btn_bar.add_theme_constant_override("separation", 16)
	btn_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(btn_bar)

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


# ---------------------------------------------------------------------------
# Slot changes
# ---------------------------------------------------------------------------

func _on_slot_changed(slot_index: int, dropdown_index: int) -> void:
	_budget.set_slot(slot_index, dropdown_index)
	# Update swatch color.
	if slot_index < _slot_swatches.size():
		_slot_swatches[slot_index].color = _budget.get_slot_color(dropdown_index)
	_update_summary()


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

	var error := _budget.validate()
	if not error.is_empty():
		_error_label.text = error
		_error_label.visible = true
	else:
		_error_label.visible = false


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

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
