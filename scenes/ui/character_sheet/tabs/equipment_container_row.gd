class_name EquipmentContainerRow
extends PanelContainer

## A container header row that acts as a drop target for inventory items.
## Displays the container name, used/total capacity, and its contents as child
## EquipmentItemRows. Drag-and-drop moves an item into this container.


var _container: Dictionary = {}
var _capacity_units: int = 0
var _used_units: int = 0
var _character_id: String
var _drop_callback: Callable
var _remove_callback: Callable

var _capacity_label: Label
var _contents_box: VBoxContainer
var _header_style: StyleBoxFlat

const _COLOR_NORMAL   := Color(0.15, 0.15, 0.15, 1.0)
const _COLOR_DROP_OK  := Color(0.10, 0.35, 0.10, 1.0)
const _COLOR_DROP_FULL := Color(0.35, 0.10, 0.10, 1.0)


func setup(
	container: Dictionary,
	contents: Array,
	capacity_units: int,
	used_units: int,
	character_id: String,
	drop_callback: Callable,
	remove_callback: Callable,
) -> void:
	_container = container
	_capacity_units = capacity_units
	_used_units = used_units
	_character_id = character_id
	_drop_callback = drop_callback
	_remove_callback = remove_callback

	_header_style = StyleBoxFlat.new()
	_header_style.bg_color = _COLOR_NORMAL
	_header_style.set_border_width_all(1)
	_header_style.border_color = Color(0.4, 0.4, 0.4, 1.0)
	add_theme_stylebox_override("panel", _header_style)

	_build(contents)


func _build(contents: Array) -> void:
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(vbox)

	# Header row
	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(header)

	var name_label := Label.new()
	name_label.text = "[%s]" % _container.get("name", "Container")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)

	_capacity_label = Label.new()
	_capacity_label.custom_minimum_size.x = 100
	header.add_child(_capacity_label)
	_update_capacity_label()

	var drop_btn := Button.new()
	drop_btn.text = "Drop"
	drop_btn.pressed.connect(func(): _drop_callback.call(_container))
	header.add_child(drop_btn)

	# Contents
	_contents_box = VBoxContainer.new()
	_contents_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_contents_box)

	if contents.is_empty():
		var empty_label := Label.new()
		empty_label.text = "    (empty — drag items here)"
		empty_label.modulate = Color(0.6, 0.6, 0.6, 1.0)
		_contents_box.add_child(empty_label)
	else:
		for item in contents:
			var row := EquipmentItemRow.new()
			row.setup(item, _remove_callback, _character_id)
			_contents_box.add_child(row)


func _update_capacity_label() -> void:
	if _capacity_label == null:
		return
	var used_stone: float = _used_units / 1000.0
	var cap_stone: float = _capacity_units / 1000.0
	_capacity_label.text = "%.2f / %.2f st" % [used_stone, cap_stone]

	if _capacity_units > 0 and _used_units >= _capacity_units:
		_capacity_label.modulate = Color(1.0, 0.3, 0.3, 1.0)
	elif _capacity_units > 0 and _used_units > _capacity_units * 0.75:
		_capacity_label.modulate = Color(1.0, 0.85, 0.2, 1.0)
	else:
		_capacity_label.modulate = Color(1.0, 1.0, 1.0, 1.0)


# ---------------------------------------------------------------------------
# Drag and drop
# ---------------------------------------------------------------------------

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary:
		return false
	if data.get("type", "") != "inventory_item":
		return false
	var item: Dictionary = data.get("item", {})
	if item.get("container_id", "") == _container.get("id", ""):
		return false  # already in this container
	var item_units: int = int(item.get("encumbrance_units", 0)) * int(item.get("quantity", 1))
	var fits: bool = (_used_units + item_units) <= _capacity_units

	_header_style.bg_color = _COLOR_DROP_OK if fits else _COLOR_DROP_FULL
	add_theme_stylebox_override("panel", _header_style)
	return fits


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	_reset_style()
	var item: Dictionary = data.get("item", {})
	var item_id: String = data.get("item_id", "")
	var container_id: String = _container.get("id", "")
	CampaignRepository.update_inventory_item_equip_state(item_id, false, "pack", container_id)
	EventBus.inventory_updated.emit(_character_id)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_reset_style()


func _reset_style() -> void:
	_header_style.bg_color = _COLOR_NORMAL
	add_theme_stylebox_override("panel", _header_style)
