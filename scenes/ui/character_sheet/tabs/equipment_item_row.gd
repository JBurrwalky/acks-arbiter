class_name EquipmentItemRow
extends PanelContainer

## A single draggable inventory item row.
## Used both inside containers and in the loose carry zone.
## Drag payload: { "type": "inventory_item", "item_id": String, "item": Dictionary }


var _item: Dictionary = {}
var _remove_callback: Callable
var _equip_callback: Callable
var _split_callback: Callable
var _character_id: String


func setup(item: Dictionary, remove_callback: Callable, character_id: String, equip_callback: Callable = Callable(), split_callback: Callable = Callable()) -> void:
	_item = item
	_remove_callback = remove_callback
	_equip_callback = equip_callback
	_split_callback = split_callback
	_character_id = character_id

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	add_theme_stylebox_override("panel", style)

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	_build()


func _build() -> void:
	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(hbox)

	var name_label := Label.new()
	var qty: int = int(_item.get("quantity", 1))
	var display_name: String = _item.get("name", "Unknown")
	if qty > 1:
		display_name += " x%d" % qty
	name_label.text = display_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(name_label)

	var enc_units: int = int(_item.get("encumbrance_units", 0)) * qty
	var stone: float = enc_units / 1000.0
	var weight_label := Label.new()
	weight_label.text = "%.2f st" % stone
	weight_label.custom_minimum_size.x = 60
	hbox.add_child(weight_label)

	# Show Equip button when the item is equippable and not in a container
	if _equip_callback.is_valid() and _item.get("container_id", "").is_empty():
		var equip_btn := Button.new()
		equip_btn.text = "Equip"
		equip_btn.pressed.connect(func(): _equip_callback.call())
		hbox.add_child(equip_btn)

	# Show Split button for stacks with qty > 1
	if qty > 1 and _split_callback.is_valid():
		var split_btn := Button.new()
		split_btn.text = "Split"
		split_btn.pressed.connect(_on_split_pressed.bind(qty))
		hbox.add_child(split_btn)

	# Show Remove button only for items inside a container
	if not _item.get("container_id", "").is_empty():
		var remove_btn := Button.new()
		remove_btn.text = "Remove"
		remove_btn.pressed.connect(func(): _remove_callback.call(_item))
		hbox.add_child(remove_btn)


func _on_split_pressed(max_qty: int) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Split Stack"
	UiSurfaceStyles.apply_framed_window_chrome(dialog)

	var vbox := VBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "Split off how many?"
	vbox.add_child(lbl)

	var spin := SpinBox.new()
	spin.min_value = 1
	spin.max_value = max_qty - 1
	spin.value = 1
	vbox.add_child(spin)

	dialog.add_child(vbox)
	add_child(dialog)

	dialog.confirmed.connect(func():
		_split_callback.call(int(spin.value))
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered()


# ---------------------------------------------------------------------------
# Drag and drop
# ---------------------------------------------------------------------------

func _get_drag_data(_at_position: Vector2) -> Variant:
	var preview := Label.new()
	preview.text = _item.get("name", "Item")
	set_drag_preview(preview)
	return {
		"type": "inventory_item",
		"item_id": _item.get("id", ""),
		"item": _item,
	}


# ---------------------------------------------------------------------------
# Hover styling
# ---------------------------------------------------------------------------

func _on_mouse_entered() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.06)
	add_theme_stylebox_override("panel", style)


func _on_mouse_exited() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	add_theme_stylebox_override("panel", style)
