# ItemContextMenu — right-click context menu for items in the Party Inventory overlay.
#
# Dependencies:
#   - Currency (preloaded): coin detection
#
# No class_name — lazily instantiated by PartyInventoryOverlay.

extends PopupMenu

const Currency := preload("res://engine/subsystems/commerce/currency.gd")
const CSTabEquipment := preload("res://scenes/ui/character_sheet/tabs/cs_tab_equipment.gd")
const ClassEquipRestrictionValidator := preload("res://engine/subsystems/inventory/class_equipment_restriction_validator.gd")

signal send_to_requested(item_data: Dictionary, source_carrier_type: String,
		source_carrier_id: String, target_carrier: Dictionary)
signal drop_requested(item_data: Dictionary, source_carrier_type: String,
		source_carrier_id: String)
signal transfer_gold_requested(item_data: Dictionary)
signal equip_rejected(reason: String)

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
	var item_key: String = str(_item_data.get("item_key", ""))
	var catalog := EquipmentCatalog.new()
	var catalog_entry: Dictionary = catalog.get_item(item_key)
	var weapon_tags: Array = catalog_entry.get("weapon_tags", [])

	var slot := "pack"
	match cat:
		"weapon":
			slot = "hands_main"
		"armor":
			slot = "body"
		"shield":
			slot = "hands_off"
		"ammunition":
			# Only thrown self-ammo (darts) is equippable; routes to a hand slot.
			if "thrown" in weapon_tags and not String(catalog_entry.get("weapon_damage", "")).is_empty():
				slot = "hands_main"
			else:
				return  # Non-throwable ammo (arrows/bolts) isn't equippable here.

	if slot == "pack":
		return  # Unsupported category.

	# Class restriction check (mage can't equip plate, cleric can't equip swords, etc.)
	if _source_carrier_type == "character" and not _source_carrier_id.is_empty():
		var check: Dictionary = ClassEquipRestrictionValidator.can_equip_for_character(
				_source_carrier_id, _item_data)
		if not check.get("ok", true):
			equip_rejected.emit(String(check.get("reason", "Cannot equip this item.")))
			return

	var qty: int = int(_item_data.get("quantity", 1))
	if CSTabEquipment.is_thrown_stackable(_item_data, catalog):
		# Thrown weapons / dart bundles equip the whole stack.
		if CampaignRepository.update_inventory_item_equip_state(item_id, true, slot):
			# Seed uses_remaining for fresh dart-style bundles.
			var uses_per_unit: int = int(catalog_entry.get("uses_per_unit", -1))
			var current_uses: int = int(_item_data.get("uses_remaining", -1))
			if uses_per_unit > 0 and current_uses < 0:
				CampaignRepository.update_inventory_item_uses(item_id, uses_per_unit)
			EventBus.inventory_updated.emit(_source_carrier_id)
		return

	# Non-thrown stack: split off one unit so only a single item gets equipped.
	if qty > 1:
		var uses_per_unit: int = int(catalog_entry.get("uses_per_unit", -1))
		if not CampaignRepository.split_item_for_equip(item_id, slot, uses_per_unit).is_empty():
			EventBus.inventory_updated.emit(_source_carrier_id)
	else:
		if CampaignRepository.update_inventory_item_equip_state(item_id, true, slot):
			EventBus.inventory_updated.emit(_source_carrier_id)


func _unequip_item() -> void:
	var item_id: String = str(_item_data.get("id", ""))
	CampaignRepository.update_inventory_item_equip_state(item_id, false, "pack")
	EventBus.inventory_updated.emit(_source_carrier_id)
