class_name EquipmentShopPanel
extends VBoxContainer

## Step 7 — Starting Equipment Shop.
##
## Player rolls 3d6 × 10 gp (converted to copper) as starting gold, then
## buys from the equipment catalog. All purchases default to slot "pack".
## An "Auto-Equip" button assigns best armor → body, shield → hands_off,
## top weapon → hands_main.
##
## Class restrictions are warnings only — they do NOT block purchase (ACKS rule).
## Gold tracking is in copper pieces. Encumbrance updates live after each change.


const TAB_CATEGORY_MAP: Array = [
	["Weapons",              ["weapon"]],
	["Armor & Shields",      ["armor", "shield"]],
	["Ammunition",           ["ammunition"]],
	["Gear",                 ["gear"]],
	["Clothing",             ["clothing"]],
	["Transport",            ["mount", "pack_animal", "draft_animal", "vehicle", "tack", "barding", "livestock"]],
	["Food & Drink",         ["foodstuff"]],
]

var _state: Dictionary = {}
var _catalog: EquipmentCatalog
var _class_registry: ClassRegistry

# Gold state
var _starting_gold_cp: int = 0
var _gold_remaining_cp: int = 0
var _gold_rolled: bool = false
var _rolling: bool = false

# UI refs
var _roll_btn: Button
var _gold_label: Label
var _enc_label: Label
var _tab_bar: TabBar
var _item_list_container: VBoxContainer
var _cart_container: VBoxContainer
var _status_label: Label


func setup(state: Dictionary, catalog: EquipmentCatalog,
		class_registry: ClassRegistry) -> void:
	_state = state
	_catalog = catalog
	_class_registry = class_registry
	if get_child_count() == 0:
		_build_ui()
	_restore_from_state()
	_refresh_gold_display()
	_refresh_cart()
	if _gold_rolled:
		_refresh_item_list()


func is_complete() -> bool:
	return int(_state.get("starting_gold_cp", 0)) > 0


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

func _restore_from_state() -> void:
	if int(_state.get("starting_gold_cp", 0)) > 0:
		_starting_gold_cp = int(_state["starting_gold_cp"])
		_gold_remaining_cp = int(_state.get("gold_remaining_cp", 0))
		_gold_rolled = true
		if _roll_btn != null:
			_roll_btn.visible = false
	else:
		_gold_rolled = false


func _commit_gold() -> void:
	_state["starting_gold_cp"] = _starting_gold_cp
	_state["gold_remaining_cp"] = _gold_remaining_cp


func _commit_inventory() -> void:
	_state["inventory"] = _cart_items().duplicate()


func _cart_items() -> Array:
	return _state.get("inventory", [])


# ---------------------------------------------------------------------------
# UI Construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	add_theme_constant_override("separation", 6)

	# Top bar: gold + encumbrance + roll button
	var top_bar := HBoxContainer.new()
	add_child(top_bar)

	_roll_btn = Button.new()
	_roll_btn.text = "Roll Starting Gold (3d6 × 10gp)"
	_roll_btn.pressed.connect(_on_roll_gold)
	top_bar.add_child(_roll_btn)

	_gold_label = Label.new()
	_gold_label.text = "Gold: —"
	_gold_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(_gold_label)

	_enc_label = Label.new()
	_enc_label.text = "Enc: — stone"
	top_bar.add_child(_enc_label)

	var autoequip_btn := Button.new()
	autoequip_btn.text = "Auto-Equip"
	autoequip_btn.tooltip_text = "Assigns best armor, shield, and weapon to equipped slots."
	autoequip_btn.pressed.connect(_on_auto_equip)
	top_bar.add_child(autoequip_btn)

	# Main split: catalog left, cart right
	var hbox := HBoxContainer.new()
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 8)
	add_child(hbox)

	# Left: tab bar + item list
	var left_vbox := VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_vbox.size_flags_stretch_ratio = 0.6
	left_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(left_vbox)

	_tab_bar = TabBar.new()
	for tab_data in TAB_CATEGORY_MAP:
		_tab_bar.add_tab(tab_data[0])
	_tab_bar.tab_changed.connect(_on_tab_changed)
	left_vbox.add_child(_tab_bar)

	var left_scroll := ScrollContainer.new()
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_vbox.add_child(left_scroll)

	_item_list_container = VBoxContainer.new()
	_item_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.add_child(_item_list_container)

	# Right: cart
	var right_vbox := VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.size_flags_stretch_ratio = 0.4
	right_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(right_vbox)

	var cart_header := Label.new()
	cart_header.text = "Purchased Items:"
	right_vbox.add_child(cart_header)

	var cart_scroll := ScrollContainer.new()
	cart_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(cart_scroll)

	_cart_container = VBoxContainer.new()
	_cart_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cart_scroll.add_child(_cart_container)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status_label)


# ---------------------------------------------------------------------------
# Gold roll
# ---------------------------------------------------------------------------

func _on_roll_gold() -> void:
	if _rolling:
		return
	_rolling = true
	_roll_btn.disabled = true

	var result: RollResult = await DiceSystem.player_roll(6, 3, 0,
		"starting_gold", "Roll Starting Gold (3d6 × 10gp)")
	# 3d6 × 10gp × 100cp/gp
	_starting_gold_cp = result.modified_total * 10 * 100
	_gold_remaining_cp = _starting_gold_cp
	_gold_rolled = true
	_commit_gold()

	_rolling = false
	_roll_btn.visible = false
	_refresh_gold_display()
	_refresh_item_list()


# ---------------------------------------------------------------------------
# Item list
# ---------------------------------------------------------------------------

func _on_tab_changed(_tab: int) -> void:
	_refresh_item_list()


func _refresh_item_list() -> void:
	for child in _item_list_container.get_children():
		child.queue_free()

	if not _gold_rolled:
		var lbl := Label.new()
		lbl.text = "Roll your starting gold to begin shopping."
		_item_list_container.add_child(lbl)
		return

	var tab_idx := _tab_bar.current_tab
	var categories: Array = TAB_CATEGORY_MAP[tab_idx][1]

	var items: Array[Dictionary] = []
	for cat in categories:
		for item in _catalog.get_items_by_category(cat):
			items.append(item)

	if items.is_empty():
		var lbl := Label.new()
		lbl.text = "No items in this category."
		_item_list_container.add_child(lbl)
		return

	# Sort by cost ascending
	items.sort_custom(func(a, b): return int(a.get("cost_cp", 0)) < int(b.get("cost_cp", 0)))

	var class_id: String = _state.get("class_id", "")
	var cls := _class_registry.get_class_def(class_id)

	for item in items:
		_add_item_row(item, cls)
		_item_list_container.add_child(HSeparator.new())


func _add_item_row(item: Dictionary, cls: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_item_list_container.add_child(row)

	var item_key: String = item.get("item_key", "")
	var cost_cp: int = int(item.get("cost_cp", 0))
	var enc: int = int(item.get("encumbrance_sixths", 0))
	var name_str: String = item.get("name", item_key)
	var category: String = item.get("item_category", "gear")

	# Name + info block
	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info_vbox)

	# Build display line
	var line1_parts: Array = [name_str]
	if category == "weapon":
		var dmg: String = item.get("weapon_damage", "")
		if not dmg.is_empty():
			line1_parts.append("(%s)" % dmg)
	elif category in ["armor", "shield"]:
		var ac_bonus: int = int(item.get("armor_ac_bonus", 0))
		if ac_bonus > 0:
			line1_parts.append("(+%d AC)" % ac_bonus)

	# Class restriction check
	var restriction_warning := _get_restriction_warning(item, cls)
	if not restriction_warning.is_empty():
		line1_parts.append("⚠")

	var name_lbl := Label.new()
	name_lbl.text = " ".join(line1_parts)
	info_vbox.add_child(name_lbl)

	var detail_lbl := Label.new()
	var enc_str := "%.1f stone" % (enc / 6.0) if enc > 0 else "negligible"
	detail_lbl.text = "%s  |  %s" % [EquipmentCatalog.format_cost(cost_cp), enc_str]
	detail_lbl.add_theme_font_size_override("font_size", 11)
	detail_lbl.modulate = Color(0.75, 0.75, 0.75, 1.0)
	info_vbox.add_child(detail_lbl)

	if not restriction_warning.is_empty():
		var warn_lbl := Label.new()
		warn_lbl.text = restriction_warning
		warn_lbl.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2, 1.0))
		warn_lbl.add_theme_font_size_override("font_size", 11)
		warn_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info_vbox.add_child(warn_lbl)

	# Buy button
	var buy_btn := Button.new()
	buy_btn.text = "Buy"
	buy_btn.custom_minimum_size = Vector2(50, 0)
	if cost_cp > _gold_remaining_cp:
		buy_btn.disabled = true
		buy_btn.tooltip_text = "Insufficient gold."
	buy_btn.pressed.connect(_on_buy_item.bind(item_key))
	row.add_child(buy_btn)


func _get_restriction_warning(item: Dictionary, cls: Dictionary) -> String:
	if cls.is_empty():
		return ""
	var category: String = item.get("item_category", "gear")
	var item_key: String = item.get("item_key", "")

	if category == "weapon":
		var wpn_perms: Array = cls.get("weapon_permissions", [])
		if wpn_perms.size() > 0 and wpn_perms[0] != "all":
			if item_key not in wpn_perms:
				return "Your class cannot use this weapon proficiently."
	elif category == "armor":
		var arm_perms: Array = cls.get("armor_permissions", [])
		if arm_perms.size() > 0 and arm_perms[0] != "all":
			if item_key not in arm_perms:
				return "Your class cannot wear this armor without penalty."
		elif arm_perms.is_empty():
			return "Your class cannot wear armor."
	elif category == "shield":
		if not cls.get("shield_permitted", true):
			return "Your class cannot use shields."

	return ""


# ---------------------------------------------------------------------------
# Buy / Sell
# ---------------------------------------------------------------------------

func _on_buy_item(item_key: String) -> void:
	var item := _catalog.get_item(item_key)
	if item.is_empty():
		return
	var cost_cp: int = int(item.get("cost_cp", 0))
	if cost_cp > _gold_remaining_cp:
		_status_label.text = "Not enough gold."
		return

	_gold_remaining_cp -= cost_cp
	_commit_gold()

	# Add to cart (stack if already present)
	var inventory: Array = _state.get("inventory", [])
	var found := false
	for cart_item in inventory:
		if cart_item.get("item_key", "") == item_key:
			cart_item["quantity"] = int(cart_item.get("quantity", 1)) + 1
			found = true
			break
	if not found:
		inventory.append(_catalog_item_to_cart(item))
	_state["inventory"] = inventory
	_commit_inventory()
	_status_label.text = ""
	_refresh_gold_display()
	_refresh_cart()
	_refresh_item_list()


func _on_sell_item(item_key: String) -> void:
	var item := _catalog.get_item(item_key)
	var cost_cp: int = int(item.get("cost_cp", 0)) if not item.is_empty() else 0

	var inventory: Array = _state.get("inventory", [])
	for i in range(inventory.size() - 1, -1, -1):
		if inventory[i].get("item_key", "") == item_key:
			var qty: int = int(inventory[i].get("quantity", 1))
			if qty > 1:
				inventory[i]["quantity"] = qty - 1
			else:
				inventory.remove_at(i)
			_gold_remaining_cp += cost_cp
			_commit_gold()
			break
	_state["inventory"] = inventory
	_commit_inventory()
	_refresh_gold_display()
	_refresh_cart()
	_refresh_item_list()


func _catalog_item_to_cart(catalog_item: Dictionary) -> Dictionary:
	## Convert a catalog item dict to a cart item (InventoryItem.to_dict()-compatible shape).
	return {
		"item_key": catalog_item.get("item_key", ""),
		"name": catalog_item.get("name", ""),
		"quantity": 1,
		"encumbrance_sixths": int(catalog_item.get("encumbrance_sixths", 0)),
		"slot": "pack",
		"is_equipped": 0,
		"item_category": catalog_item.get("item_category", "gear"),
		"is_magical": 0,
		"magical_bonus": 0,
		"weapon_damage": catalog_item.get("weapon_damage", ""),
		"armor_ac_bonus": int(catalog_item.get("armor_ac_bonus", 0)),
		"is_heavy": 1 if catalog_item.get("is_heavy", false) else 0,
		"damage_type": catalog_item.get("damage_type", "physical"),
		"material": catalog_item.get("material", ""),
		"notes": catalog_item.get("notes", ""),
	}


# ---------------------------------------------------------------------------
# Auto-equip
# ---------------------------------------------------------------------------

func _on_auto_equip() -> void:
	var inventory: Array = _state.get("inventory", [])
	if inventory.is_empty():
		return

	# Reset all slots to pack first
	for item in inventory:
		item["slot"] = "pack"
		item["is_equipped"] = 0

	# Find best armor (highest ac_bonus)
	var best_armor_idx := -1
	var best_ac := -1
	for i in inventory.size():
		if inventory[i].get("item_category", "") == "armor":
			var ac: int = int(inventory[i].get("armor_ac_bonus", 0))
			if ac > best_ac:
				best_ac = ac
				best_armor_idx = i
	if best_armor_idx >= 0:
		inventory[best_armor_idx]["slot"] = "body"
		inventory[best_armor_idx]["is_equipped"] = 1

	# Shield
	for i in inventory.size():
		if inventory[i].get("item_category", "") == "shield":
			inventory[i]["slot"] = "hands_off"
			inventory[i]["is_equipped"] = 1
			break

	# Best weapon (highest avg damage, naive: sort by weapon_damage string length as proxy)
	var best_weapon_idx := -1
	var best_dmg := -1
	for i in inventory.size():
		if inventory[i].get("item_category", "") == "weapon":
			var dmg: String = inventory[i].get("weapon_damage", "")
			# Approximate damage value: parse die sides
			var sides := _parse_die_sides(dmg)
			if sides > best_dmg:
				best_dmg = sides
				best_weapon_idx = i
	if best_weapon_idx >= 0:
		inventory[best_weapon_idx]["slot"] = "hands_main"
		inventory[best_weapon_idx]["is_equipped"] = 1

	_state["inventory"] = inventory
	_commit_inventory()
	_refresh_cart()
	_status_label.text = "Auto-equip applied."


func _parse_die_sides(weapon_damage: String) -> int:
	## Parse "1d8" or "1d6/1d8" → return max sides.
	var max_sides := 0
	for part in weapon_damage.split("/"):
		if "d" in part:
			var sub := part.split("d")
			if sub.size() >= 2 and sub[1].is_valid_int():
				var s := int(sub[1])
				if s > max_sides:
					max_sides = s
	return max_sides


# ---------------------------------------------------------------------------
# Display refresh
# ---------------------------------------------------------------------------

func _refresh_gold_display() -> void:
	if not _gold_rolled:
		_gold_label.text = "Gold: —"
		_enc_label.text = "Enc: — stone"
		return
	_gold_label.text = "Gold: %s remaining of %s" % [
		EquipmentCatalog.format_cost(_gold_remaining_cp),
		EquipmentCatalog.format_cost(_starting_gold_cp)]

	var inventory: Array = _state.get("inventory", [])
	var enc := EncumbranceCalculator.calculate_encumbrance(inventory)
	_enc_label.text = "Enc: %.1f stone  (%d'/turn)" % [
		enc.get("total_stone", 0.0), enc.get("exploration_speed", 120)]


func _refresh_cart() -> void:
	for child in _cart_container.get_children():
		child.queue_free()

	var inventory: Array = _state.get("inventory", [])
	if inventory.is_empty():
		var lbl := Label.new()
		lbl.text = "(nothing purchased yet)"
		lbl.modulate = Color(0.6, 0.6, 0.6, 1.0)
		_cart_container.add_child(lbl)
		return

	for item in inventory:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		_cart_container.add_child(row)

		var item_key: String = item.get("item_key", "")
		var name_str: String = item.get("name", item_key)
		var qty: int = int(item.get("quantity", 1))
		var slot: String = item.get("slot", "pack")

		var name_lbl := Label.new()
		var slot_tag := ""
		match slot:
			"body":    slot_tag = "[body] "
			"hands_main": slot_tag = "[main] "
			"hands_off":  slot_tag = "[off]  "
			"belt":    slot_tag = "[belt] "
			_:         slot_tag = "[pack] "
		name_lbl.text = slot_tag + name_str + (" ×%d" % qty if qty > 1 else "")
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)

		var cost_cp: int = 0
		var catalog_item := _catalog.get_item(item_key)
		if not catalog_item.is_empty():
			cost_cp = int(catalog_item.get("cost_cp", 0))

		var sell_btn := Button.new()
		sell_btn.text = "Sell"
		sell_btn.custom_minimum_size = Vector2(40, 0)
		sell_btn.tooltip_text = "Refund: %s" % EquipmentCatalog.format_cost(cost_cp)
		sell_btn.pressed.connect(_on_sell_item.bind(item_key))
		row.add_child(sell_btn)
