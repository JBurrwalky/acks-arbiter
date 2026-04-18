class_name CSTabCreatureInventory
extends VBoxContainer

## Creature inventory tab — shows equipped gear (barding, saddle, saddlebags,
## caparison), saddlebag contents, loose cargo, and encumbrance summary.
## Supports interactive equip/unequip via CreatureEquipmentService.


var _creature: TrainedCreatureData = null
var _catalog: EquipmentCatalog = null


func display(creature: TrainedCreatureData, registries: Dictionary) -> void:
	for child in get_children():
		child.queue_free()

	_creature = creature
	_catalog = registries.get("equipment_catalog", null)
	if _catalog == null:
		_catalog = EquipmentCatalog.new()

	if creature == null:
		_add_text("No creature data.")
		return

	# --- Equipment Slots ---
	_add_section_header("Equipment")

	_render_equip_slot("Barding", "barding", creature)
	_render_equip_slot("Saddle", "saddle", creature)
	_render_equip_slot("Pack Container", "pack_container", creature)
	_render_equip_slot("Caparison", "caparison", creature)

	# Equip from handler button
	if not creature.handler_id.is_empty():
		add_child(HSeparator.new())
		var equip_row := HBoxContainer.new()
		equip_row.add_theme_constant_override("separation", 4)
		add_child(equip_row)

		var equip_label := Label.new()
		equip_label.text = "Equip from handler:"
		equip_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		equip_row.add_child(equip_label)

		var equip_option := OptionButton.new()
		equip_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		equip_option.add_item("-- select item --", 0)
		var equippable_items := _get_equippable_handler_items(creature)
		for i in range(equippable_items.size()):
			var item: Dictionary = equippable_items[i]
			equip_option.add_item(str(item.get("name", "?")), i + 1)
		equip_option.item_selected.connect(_on_equip_selected.bind(equippable_items))
		equip_row.add_child(equip_option)

	add_child(HSeparator.new())

	# --- Pack Container Contents (saddlebags or panniers) ---
	var pack_container_id := CreatureEquipmentService.get_pack_container_item_id(creature)
	if not pack_container_id.is_empty():
		# Find the actual item key for capacity lookup
		var container_key := ""
		var container_name := "Container"
		for item in creature.inventory:
			var iid := _item_field(item, "id")
			if iid == pack_container_id:
				container_key = _item_field(item, "item_key")
				container_name = _item_field(item, "name")
				break
		_add_section_header("%s Contents" % container_name)
		var used_units := 0
		var sb_items: Array = []
		for item in creature.inventory:
			var cid := _item_field(item, "container_id")
			if cid == pack_container_id:
				sb_items.append(item)
				used_units += _item_int(item, "encumbrance_units") * _item_int(item, "quantity", 1)
		var capacity_units: int = _catalog.get_container_capacity_units(container_key)
		var cap_stone := "%.1f / %.1f stone" % [used_units / 1000.0, capacity_units / 1000.0]
		_add_row("Capacity", cap_stone)

		if sb_items.is_empty():
			_add_text("  (empty)")
		else:
			for item in sb_items:
				_render_cargo_row(item)
		add_child(HSeparator.new())

	# --- Loose Cargo ---
	_add_section_header("Loose Cargo")
	var cargo_items: Array = []
	for item in creature.inventory:
		var equipped := _item_bool(item, "is_equipped")
		var container := _item_field(item, "container_id")
		if not equipped and container.is_empty():
			cargo_items.append(item)

	if cargo_items.is_empty():
		_add_text("  (none)")
	else:
		for item in cargo_items:
			_render_cargo_row(item)

	add_child(HSeparator.new())

	# --- Encumbrance Summary ---
	_add_section_header("Encumbrance")
	var load_stone := creature.get_current_load_stone()
	var cap_normal := creature.get_effective_capacity_normal()
	var cap_max := creature.get_effective_capacity_max()
	var enc_text := "%d / %d stone" % [load_stone, cap_normal]
	if cap_max > 0 and cap_max != cap_normal:
		enc_text += " (max %d)" % cap_max
	var enc_color := Color.WHITE
	if creature.is_overloaded():
		enc_color = Color.ORANGE_RED
		enc_text += "  [OVERLOADED]"
	_add_row_colored("Load", enc_text, enc_color)

	var multiplier := creature.get_load_multiplier()
	if multiplier <= 0.0:
		_add_text("  No rigging — cannot carry cargo.")
	elif multiplier < 1.0:
		_add_text("  Rope lashing — half capacity.")


# ---------------------------------------------------------------------------
# Equipment slot rendering
# ---------------------------------------------------------------------------

func _render_equip_slot(label: String, slot_type: String, creature: TrainedCreatureData) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)

	var slot_label := Label.new()
	slot_label.text = label + ":"
	slot_label.custom_minimum_size = Vector2(100, 0)
	slot_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	row.add_child(slot_label)

	var equipped_item = _find_equipped_by_type(creature, slot_type)
	if equipped_item != null:
		var item_name: String = _item_field(equipped_item, "name")
		var detail := ""
		if slot_type == "barding":
			var ac_bonus: int = _item_int(equipped_item, "armor_ac_bonus")
			if ac_bonus > 0:
				detail = " (AC +%d)" % ac_bonus

		var val := Label.new()
		val.text = item_name + detail
		val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(val)

		var unequip_btn := Button.new()
		unequip_btn.text = "Unequip"
		unequip_btn.flat = true
		unequip_btn.add_theme_font_size_override("font_size", 10)
		var item_id: String = _item_field(equipped_item, "id")
		unequip_btn.pressed.connect(_on_unequip.bind(item_id))
		row.add_child(unequip_btn)
	else:
		var val := Label.new()
		val.text = "-- none --"
		val.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(val)


func _render_cargo_row(item) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)

	var name_str: String = _item_field(item, "name")
	var qty: int = _item_int(item, "quantity", 1)
	if qty > 1:
		name_str = "%s (x%d)" % [name_str, qty]

	var lbl := Label.new()
	lbl.text = "  " + name_str
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	var enc: int = _item_int(item, "encumbrance_units") * qty
	var enc_lbl := Label.new()
	enc_lbl.text = "%.1f st" % (enc / 1000.0)
	enc_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	row.add_child(enc_lbl)


# ---------------------------------------------------------------------------
# Callbacks
# ---------------------------------------------------------------------------

func _on_unequip(item_id: String) -> void:
	if _creature == null:
		return
	CampaignRepository.unequip_creature_item(item_id)
	# Transfer back to handler's inventory.
	if not _creature.handler_id.is_empty():
		CampaignRepository.transfer_item_from_creature_to_character(item_id, _creature.handler_id)
	EventBus.creature_inventory_updated.emit(_creature.id)


func _on_equip_selected(index: int, items: Array) -> void:
	if index <= 0 or _creature == null:
		return  # "-- select item --" chosen
	var item_index := index - 1
	if item_index >= items.size():
		return
	var item: Dictionary = items[item_index]
	var item_id: String = str(item.get("id", ""))
	if item_id.is_empty():
		return

	var error := CreatureEquipmentService.validate_equip_on_creature(_creature, item, _catalog)
	if not error.is_empty():
		push_warning("Cannot equip: %s" % error)
		return

	var slot := CreatureEquipmentService.determine_creature_slot(item)
	if slot.is_empty():
		return

	CampaignRepository.equip_creature_item(item_id, _creature.id, slot)
	EventBus.creature_inventory_updated.emit(_creature.id)


# ---------------------------------------------------------------------------
# Data helpers
# ---------------------------------------------------------------------------

func _find_equipped_by_type(creature: TrainedCreatureData, slot_type: String):
	for item in creature.inventory:
		var equipped := _item_bool(item, "is_equipped")
		if not equipped:
			continue
		var key: String = _item_field(item, "item_key")
		var cat: String = _item_field(item, "item_category")
		match slot_type:
			"barding":
				if cat == "barding":
					return item
			"saddle":
				if key.begins_with("saddle_"):
					return item
			"pack_container":
				if key == "saddlebags" or key == "panniers":
					return item
			"caparison":
				if key == "caparison":
					return item
	return null


func _get_equippable_handler_items(creature: TrainedCreatureData) -> Array:
	if creature.handler_id.is_empty():
		return []
	var handler_inv := CampaignRepository.get_inventory_items(creature.handler_id)
	var result: Array = []
	for item in handler_inv:
		var cat: String = str(item.get("item_category", ""))
		var key: String = str(item.get("item_key", ""))
		# Only show items that could be equipped on this creature.
		if cat == "barding" or key.begins_with("saddle_") or key == "saddlebags" or key == "panniers" or key == "caparison":
			var error := CreatureEquipmentService.validate_equip_on_creature(creature, item, _catalog)
			if error.is_empty():
				result.append(item)
	return result


func _item_field(item, field: String, default: String = "") -> String:
	if item is InventoryItem:
		match field:
			"id": return item.id
			"name": return item.name
			"item_key": return item.item_key
			"item_category": return item.item_category
			"container_id": return item.container_id
			_: return default
	elif item is Dictionary:
		return str(item.get(field, default))
	return default


func _item_int(item, field: String, default: int = 0) -> int:
	if item is InventoryItem:
		match field:
			"encumbrance_units": return item.encumbrance_units
			"quantity": return item.quantity
			"armor_ac_bonus": return item.armor_ac_bonus
			_: return default
	elif item is Dictionary:
		return int(item.get(field, default))
	return default


func _item_bool(item, field: String) -> bool:
	if item is InventoryItem:
		match field:
			"is_equipped": return item.is_equipped
			_: return false
	elif item is Dictionary:
		var val = item.get(field, 0)
		return val == 1 or val == true
	return false


# ---------------------------------------------------------------------------
# Layout helpers
# ---------------------------------------------------------------------------

func _add_section_header(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.75, 0.55))
	add_child(lbl)


func _add_row(label_text: String, value_text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	var lbl := Label.new()
	lbl.text = label_text + ":"
	lbl.custom_minimum_size = Vector2(100, 0)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	row.add_child(lbl)
	var val := Label.new()
	val.text = value_text
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(val)


func _add_row_colored(label_text: String, value_text: String, color: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	var lbl := Label.new()
	lbl.text = label_text + ":"
	lbl.custom_minimum_size = Vector2(100, 0)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	row.add_child(lbl)
	var val := Label.new()
	val.text = value_text
	val.add_theme_color_override("font_color", color)
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(val)


func _add_text(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	add_child(lbl)
