class_name EquipmentLooseZone
extends PanelContainer

## Drop target for the "Loose Carry" area.
## Dropping an item here removes it from its container (sets container_id = "").
## Also contains EquipmentItemRows for loose items, which can be dragged
## to an EquipmentContainerRow.


var _character_id: String
var _items_box: VBoxContainer

var _bg_style: StyleBoxFlat

const _COLOR_NORMAL   := Color(0.08, 0.08, 0.12, 1.0)
const _COLOR_DROP_OK  := Color(0.10, 0.30, 0.10, 1.0)


func setup(loose_items: Array, character_id: String, remove_callback: Callable, equip_fn: Callable = Callable(), split_fn: Callable = Callable()) -> void:
	_character_id = character_id

	_bg_style = StyleBoxFlat.new()
	_bg_style.bg_color = _COLOR_NORMAL
	_bg_style.set_border_width_all(1)
	_bg_style.border_color = Color(0.3, 0.3, 0.4, 1.0)
	add_theme_stylebox_override("panel", _bg_style)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(vbox)

	var header := Label.new()
	header.text = "─── Loose Carry ───"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	_items_box = VBoxContainer.new()
	_items_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_items_box)

	if loose_items.is_empty():
		var empty_label := Label.new()
		empty_label.text = "    (drag containers here to unpack)"
		empty_label.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_TEXT_COLOR)
		_items_box.add_child(empty_label)
	else:
		for item in loose_items:
			var row := EquipmentItemRow.new()
			var equip_cb: Callable = equip_fn.call(item) if equip_fn.is_valid() else Callable()
			var split_cb: Callable = split_fn.call(item) if split_fn.is_valid() else Callable()
			row.setup(item, remove_callback, character_id, equip_cb, split_cb)
			_items_box.add_child(row)


# ---------------------------------------------------------------------------
# Drag and drop — accepts items that are currently inside a container
# ---------------------------------------------------------------------------

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary:
		return false
	if data.get("type", "") != "inventory_item":
		return false
	var item: Dictionary = data.get("item", {})
	var has_container: bool = not item.get("container_id", "").is_empty()

	_bg_style.bg_color = _COLOR_DROP_OK if has_container else _COLOR_NORMAL
	add_theme_stylebox_override("panel", _bg_style)
	return has_container


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	_reset_style()
	var item_id: String = data.get("item_id", "")
	CampaignRepository.update_inventory_item_equip_state(item_id, false, "pack", "")
	EventBus.inventory_updated.emit(_character_id)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_reset_style()


func _reset_style() -> void:
	_bg_style.bg_color = _COLOR_NORMAL
	add_theme_stylebox_override("panel", _bg_style)
