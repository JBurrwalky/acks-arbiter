# DropItemDialog — wilderness drop/hide chooser for the Party Inventory overlay.
#
# Dependencies:
#   - LocationCacheManager (autoload): cache creation methods
#   - Timekeeping (autoload): time display for hide-and-memorize cost
#
# No class_name — lazily instantiated by InventoryTabPage.

extends PanelContainer

signal drop_confirmed(item_id: String, source: Dictionary, mode: String)

var _item_id: String = ""
var _source: Dictionary = {}
var _item_name_label: Label
var _radio_loose: CheckBox
var _radio_hidden: CheckBox
var _is_built: bool = false


func _ready() -> void:
	visible = false
	_build_ui()


func open_for_item(item_id: String, source: Dictionary) -> void:
	_item_id = item_id
	_source = source
	if not _is_built:
		_build_ui()

	# Try to get item name from the source carrier
	_item_name_label.text = "Drop item?"

	_radio_loose.button_pressed = true
	_radio_hidden.button_pressed = false
	visible = true


func _build_ui() -> void:
	_is_built = true

	anchor_left = 0.3
	anchor_right = 0.7
	anchor_top = 0.25
	anchor_bottom = 0.75

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.12, 0.08, 0.95)
	style.border_color = Color(0.46, 0.33, 0.19, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(12)
	add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	add_child(vbox)

	# Title
	_item_name_label = Label.new()
	_item_name_label.text = "Drop item?"
	_item_name_label.add_theme_font_size_override("font_size", 15)
	_item_name_label.add_theme_color_override("font_color", Color(0.95, 0.88, 0.7))
	_item_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_item_name_label)

	vbox.add_child(HSeparator.new())

	# Radio group
	var radio_group := ButtonGroup.new()

	# Option 1: Drop on ground
	_radio_loose = CheckBox.new()
	_radio_loose.text = "Drop on ground"
	_radio_loose.button_group = radio_group
	_radio_loose.button_pressed = true
	_radio_loose.add_theme_font_size_override("font_size", 13)
	vbox.add_child(_radio_loose)

	var loose_desc := Label.new()
	loose_desc.text = "  Items decay over 1d4 weeks.\n  After that, lost forever."
	loose_desc.add_theme_font_size_override("font_size", 11)
	loose_desc.add_theme_color_override("font_color", Color(0.6, 0.55, 0.45))
	vbox.add_child(loose_desc)

	# Spacer
	vbox.add_child(Control.new())

	# Option 2: Hide and memorize
	_radio_hidden = CheckBox.new()
	_radio_hidden.text = "Hide and memorize location (1 hour)"
	_radio_hidden.button_group = radio_group
	_radio_hidden.add_theme_font_size_override("font_size", 13)
	vbox.add_child(_radio_hidden)

	var hidden_desc := Label.new()
	hidden_desc.text = "  Stash is permanent, but monthly\n  risk of raid.\n  Current raid risk: 0% (new)"
	hidden_desc.add_theme_font_size_override("font_size", 11)
	hidden_desc.add_theme_color_override("font_color", Color(0.6, 0.55, 0.45))
	vbox.add_child(hidden_desc)

	vbox.add_child(HSeparator.new())

	# Buttons
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(btn_row)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.add_theme_font_size_override("font_size", 12)
	cancel_btn.pressed.connect(func(): visible = false)
	btn_row.add_child(cancel_btn)

	var confirm_btn := Button.new()
	confirm_btn.text = "Confirm"
	confirm_btn.add_theme_font_size_override("font_size", 12)
	confirm_btn.pressed.connect(_on_confirm)
	btn_row.add_child(confirm_btn)


func _on_confirm() -> void:
	var mode := "hidden" if _radio_hidden.button_pressed else "loose"
	visible = false
	drop_confirmed.emit(_item_id, _source, mode)
