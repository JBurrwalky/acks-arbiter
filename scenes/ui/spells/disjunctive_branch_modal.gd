extends CanvasLayer

## Modal that asks the player to pick one of a disjunctive spell's branches
## (Sleep: single creature OR group; Charm Monster: same; etc.). Sits at
## CanvasLayer 58 (just above SpellPickerPanel at 56) so it stacks correctly
## when the picker re-opens after a cancel.
##
## Usage:
##   var modal = preload("res://scenes/ui/spells/disjunctive_branch_modal.tscn").instantiate()
##   add_child(modal)
##   modal.setup(spell_name, options)
##     spell_name: String — display label
##     options: Array — each item is {"label": String} from target_spec.options
##   modal.branch_chosen.connect(func(idx): ...)
##   modal.cancelled.connect(...)

signal branch_chosen(index: int)
signal cancelled


var _root_panel: PanelContainer = null
var _option_container: VBoxContainer = null
var _options: Array = []


func _ready() -> void:
	layer = 58
	visible = false
	_build_ui()


func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.55)
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(_on_backdrop_input)
	add_child(backdrop)

	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	add_child(center)

	_root_panel = PanelContainer.new()
	_root_panel.custom_minimum_size = Vector2(420, 200)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.10, 0.13, 0.97)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.45, 0.40, 0.20)
	_root_panel.add_theme_stylebox_override("panel", style)
	center.add_child(_root_panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	_root_panel.add_child(outer)

	var header := Label.new()
	header.name = "Header"
	header.text = "Choose Target Mode"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", Color(0.92, 0.86, 0.62))
	outer.add_child(header)

	outer.add_child(HSeparator.new())

	_option_container = VBoxContainer.new()
	_option_container.add_theme_constant_override("separation", 6)
	outer.add_child(_option_container)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	outer.add_child(btn_row)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(_on_cancel_pressed)
	btn_row.add_child(cancel_btn)


func setup(spell_name: String, options: Array) -> void:
	_options = options
	var header_lbl: Label = _root_panel.get_node("VBoxContainer/Header") as Label if _root_panel.has_node("VBoxContainer/Header") else null
	if header_lbl == null:
		for child in _root_panel.get_children():
			if child is VBoxContainer:
				header_lbl = child.get_node_or_null("Header") as Label
				break
	if header_lbl != null:
		header_lbl.text = "%s — Choose Target Mode" % spell_name

	for child in _option_container.get_children():
		child.queue_free()

	for i in range(options.size()):
		var label: String = String(options[i].get("label", "Option %d" % (i + 1)))
		var btn := Button.new()
		btn.text = label
		btn.custom_minimum_size = Vector2(380, 40)
		btn.pressed.connect(_on_option_pressed.bind(i))
		_option_container.add_child(btn)

	visible = true


func close() -> void:
	visible = false
	queue_free()


func _on_option_pressed(index: int) -> void:
	emit_signal("branch_chosen", index)
	close()


func _on_cancel_pressed() -> void:
	emit_signal("cancelled")
	close()


func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_cancel_pressed()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_cancel_pressed()
		get_viewport().set_input_as_handled()
