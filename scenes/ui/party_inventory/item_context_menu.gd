# ItemContextMenu — right-click context menu for items in the Party Inventory overlay.
#
# Dependencies:
#   - Currency (preloaded): coin detection
#
# No class_name — lazily instantiated by PartyInventoryOverlay.

extends PopupMenu

const Currency := preload("res://engine/subsystems/commerce/currency.gd")

signal send_to_requested(item_data: Dictionary, source_carrier_type: String,
		source_carrier_id: String, target_carrier: Dictionary)
signal drop_requested(item_data: Dictionary, source_carrier_type: String,
		source_carrier_id: String)
signal transfer_gold_requested(item_data: Dictionary)

var _item_data: Dictionary = {}
var _source_carrier_type: String = ""
var _source_carrier_id: String = ""
var _valid_targets: Array = []
var _send_to_submenu: PopupMenu = null

# Menu item IDs
const ID_TRANSFER_GOLD := 100
const ID_DROP := 200
const ID_SPLIT := 300
const ID_VIEW_DETAILS := 400
const ID_EQUIP := 500
const ID_UNEQUIP := 501


func _ready() -> void:
	id_pressed.connect(_on_id_pressed)


func show_for_item(item_data: Dictionary, carrier_type: String,
		carrier_id: String, valid_targets: Array, global_pos: Vector2) -> void:
	_item_data = item_data
	_source_carrier_type = carrier_type
	_source_carrier_id = carrier_id
	_valid_targets = valid_targets

	clear()
	# Remove old submenu if any
	if _send_to_submenu != null:
		if _send_to_submenu.get_parent() == self:
			remove_child(_send_to_submenu)
		_send_to_submenu.queue_free()
		_send_to_submenu = null

	var key: String = str(item_data.get("item_key", ""))

	if Currency.is_coin(key):
		add_item("Transfer Gold...", ID_TRANSFER_GOLD)
	else:
		# "Send to" submenu
		if not valid_targets.is_empty():
			_send_to_submenu = PopupMenu.new()
			_send_to_submenu.name = "SendToSubmenu"
			_send_to_submenu.id_pressed.connect(_on_send_to_pressed)
			for i in range(valid_targets.size()):
				var t: Dictionary = valid_targets[i]
				var label_text: String = str(t.get("label", "Unknown"))
				_send_to_submenu.add_item(label_text, i)
				if not t.get("ok", true):
					_send_to_submenu.set_item_disabled(
						_send_to_submenu.get_item_index(i), true)
					_send_to_submenu.set_item_tooltip(
						_send_to_submenu.get_item_index(i),
						str(t.get("reason", "")))
			add_child(_send_to_submenu)
			add_submenu_item("Send to...", "SendToSubmenu")

		add_item("Drop on ground", ID_DROP)
		add_separator()

		var qty: int = int(item_data.get("quantity", 1))
		if qty > 1:
			add_item("Split stack", ID_SPLIT)

		add_item("View details", ID_VIEW_DETAILS)

		# Equip/Unequip
		var cat: String = str(item_data.get("item_category", ""))
		var equipped: bool = false
		var eq_val = item_data.get("is_equipped", false)
		if eq_val is bool:
			equipped = eq_val
		else:
			equipped = int(eq_val) == 1
		if cat in ["weapon", "armor", "shield"] and carrier_type == "character":
			if equipped:
				add_item("Unequip", ID_UNEQUIP)
			else:
				add_item("Equip", ID_EQUIP)

	position = Vector2i(int(global_pos.x), int(global_pos.y))
	popup()


func _on_id_pressed(id: int) -> void:
	match id:
		ID_TRANSFER_GOLD:
			transfer_gold_requested.emit(_item_data)
		ID_DROP:
			drop_requested.emit(_item_data, _source_carrier_type, _source_carrier_id)
		ID_SPLIT:
			# Stub — would open a split dialog
			EventBus.notification_requested.emit({
				"message": "Split stack will be available in a future update.",
				"type": "info",
			})
		ID_VIEW_DETAILS:
			EventBus.notification_requested.emit({
				"message": "Item details view coming soon.",
				"type": "info",
			})
		ID_EQUIP:
			_equip_item()
		ID_UNEQUIP:
			_unequip_item()


func _on_send_to_pressed(target_index: int) -> void:
	if target_index < 0 or target_index >= _valid_targets.size():
		return
	var target: Dictionary = _valid_targets[target_index]
	if not target.get("ok", false):
		return
	send_to_requested.emit(_item_data, _source_carrier_type,
			_source_carrier_id, {
		"carrier_type": target.get("carrier_type", ""),
		"carrier_id": target.get("carrier_id", ""),
		"slot": "",
		"data": target.get("data"),
	})


func _equip_item() -> void:
	var item_id: String = str(_item_data.get("id", ""))
	var cat: String = str(_item_data.get("item_category", ""))
	var slot := "pack"
	match cat:
		"weapon":
			slot = "hands_main"
		"armor":
			slot = "body"
		"shield":
			slot = "hands_off"
	CampaignRepository.update_inventory_item_equip_state(item_id, true, slot)
	EventBus.inventory_updated.emit(_source_carrier_id)


func _unequip_item() -> void:
	var item_id: String = str(_item_data.get("id", ""))
	CampaignRepository.update_inventory_item_equip_state(item_id, false, "pack")
	EventBus.inventory_updated.emit(_source_carrier_id)
