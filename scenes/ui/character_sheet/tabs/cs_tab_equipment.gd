class_name CSTabEquipment
extends VBoxContainer

## Equipment tab — equipped items, containers with contents, loose carry.
## Supports equip/unequip for weapons/armor/shields/clothing/gear, placing items
## into containers, and dropping containers.

## Item categories that show Equip buttons in the "Available to equip" list.
const EQUIPPABLE_CATEGORIES := ["weapon", "armor", "shield", "clothing"]

## Keys that identify container items. Matched as substring of item_key.
const CONTAINER_KEYS := ["backpack", "sack_large", "sack_small", "pouch", "belt_pouch"]

## Carry capacity per container (in stone). Used for display only.
const CONTAINER_CAPACITY_STONE := {
	"backpack":   4.0,
	"sack_large": 6.0,
	"sack_small": 2.0,
	"pouch":      0.5,
	"belt_pouch": 0.5,
}

## Gear item_keys that can be equipped to a hand slot.
const HAND_HOLDABLE_KEYS := [
	"torch", "lantern",
	"oil_flask_common", "oil_flask_military",
	"holy_water",
	"rope_50ft", "iron_spikes_12", "pole_wooden_10ft",
	"grappling_hook", "hammer_small", "mirror_small", "crowbar",
]

## Gear item_keys that equip to an accessory slot (worn, not held).
const ACCESSORY_KEYS := ["holy_symbol"]

## All five accessory slot names, in order.
const ACCESSORY_SLOTS := [
	"accessory_1", "accessory_2", "accessory_3", "accessory_4", "accessory_5"
]

const SLOT_LABELS := {
	"hands_main":  "Main Hand",
	"hands_off":   "Off Hand",
	"body":        "Body",
	"head":        "Head",
	"belt":        "Belt",
	"feet":        "Feet",
	"hands_worn":  "Gloves",
	"cloak":       "Cloak",
	"accessory_1": "Accessory 1",
	"accessory_2": "Accessory 2",
	"accessory_3": "Accessory 3",
	"accessory_4": "Accessory 4",
	"accessory_5": "Accessory 5",
}

var _character_id: String = ""
var _bundle: CharacterBundle = null
var _catalog: EquipmentCatalog = null   ## lazy-loaded


func display(bundle: CharacterBundle, _registries: Dictionary) -> void:
	_bundle = bundle
	_character_id = ""

	for child in get_children():
		child.queue_free()

	var character: CharacterData = bundle.character
	if character == null:
		_add_text("No character data.")
		return
	_character_id = character.id

	_render_encumbrance(bundle)
	add_child(HSeparator.new())
	_render_equipped(bundle)
	add_child(HSeparator.new())
	_render_containers(bundle)
	_render_loose(bundle)


# ---------------------------------------------------------------------------
# Section renderers
# ---------------------------------------------------------------------------

func _render_encumbrance(bundle: CharacterBundle) -> void:
	_add_section_header("Encumbrance")
	var enc := EncumbranceCalculator.calculate_encumbrance(bundle.inventory)
	var total_stone: float = enc.get("total_stone", 0.0)
	var explore: int = enc.get("exploration_speed", 120)
	var is_overloaded: bool = enc.get("is_overloaded", false)

	var enc_row := HBoxContainer.new()
	enc_row.add_theme_constant_override("separation", 8)
	add_child(enc_row)
	var enc_lbl := Label.new()
	enc_lbl.text = "%.2f stone  |  %d' / turn" % [total_stone, explore]
	if is_overloaded:
		enc_lbl.add_theme_color_override("font_color", Color(0.85, 0.15, 0.15))
	enc_row.add_child(enc_lbl)
	if is_overloaded:
		var ov := Label.new()
		ov.text = " OVERLOADED"
		ov.add_theme_color_override("font_color", Color(0.85, 0.15, 0.15))
		ov.add_theme_font_size_override("font_size", 11)
		enc_row.add_child(ov)


func _render_equipped(bundle: CharacterBundle) -> void:
	_add_section_header("Equipped")

	var equipped_by_slot: Dictionary = {}
	for item in bundle.inventory:
		if bool(int(item.get("is_equipped", 0))):
			var s: String = item.get("slot", "pack")
			equipped_by_slot[s] = item

	## Main slots
	var main_slots := ["hands_main", "hands_off", "body", "head", "belt", "feet", "hands_worn", "cloak"]
	for slot in main_slots:
		_add_slot_row(slot, equipped_by_slot)

	## Accessory slots — all five always visible
	for slot in ACCESSORY_SLOTS:
		_add_slot_row(slot, equipped_by_slot)

	## Available to equip
	var has_unequipped := false
	for item in bundle.inventory:
		if bool(int(item.get("is_equipped", 0))):
			continue
		if not _can_equip(item):
			continue
		if _is_container(item):
			continue
		if not has_unequipped:
			var lbl := Label.new()
			lbl.text = "Available to equip:"
			lbl.add_theme_font_size_override("font_size", 11)
			lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			add_child(lbl)
			has_unequipped = true

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		add_child(row)

		var name_lbl := Label.new()
		name_lbl.text = "  " + _item_display_name(item)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)

		var target_slot := _determine_equip_slot(item)
		var equip_btn := Button.new()
		equip_btn.text = "Equip"
		equip_btn.custom_minimum_size = Vector2(60, 0)
		if target_slot.is_empty():
			equip_btn.disabled = true
			equip_btn.tooltip_text = "No free slot available."
		else:
			var item_id: String = item.get("id", "")
			equip_btn.pressed.connect(_on_equip.bind(item_id))
		row.add_child(equip_btn)


func _add_slot_row(slot: String, equipped_by_slot: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	add_child(row)

	var slot_lbl := Label.new()
	slot_lbl.text = SLOT_LABELS.get(slot, slot) + ":"
	slot_lbl.custom_minimum_size = Vector2(90, 0)
	row.add_child(slot_lbl)

	if equipped_by_slot.has(slot):
		var item: Dictionary = equipped_by_slot[slot]
		var name_lbl := Label.new()
		name_lbl.text = _item_display_name(item)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)

		var unequip_btn := Button.new()
		unequip_btn.text = "Unequip"
		unequip_btn.custom_minimum_size = Vector2(70, 0)
		var item_id: String = item.get("id", "")
		unequip_btn.pressed.connect(_on_unequip.bind(item_id))
		row.add_child(unequip_btn)
	else:
		var empty_lbl := Label.new()
		empty_lbl.text = "—"
		empty_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		empty_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(empty_lbl)


func _render_containers(bundle: CharacterBundle) -> void:
	var containers: Array = []
	for item in bundle.inventory:
		if _is_container(item):
			containers.append(item)

	if containers.is_empty():
		return

	_add_section_header("Containers")

	var by_container: Dictionary = {}
	for item in bundle.inventory:
		var cid: String = item.get("container_id", "")
		if cid.is_empty():
			continue
		if not by_container.has(cid):
			by_container[cid] = []
		by_container[cid].append(item)

	for container in containers:
		var cid: String = container.get("id", "")
		var contents: Array = by_container.get(cid, [])

		var contents_sixths: float = 0.0
		for ci in contents:
			var sixths: int = int(ci.get("encumbrance_sixths", 0))
			var qty: int = int(ci.get("quantity", 1))
			contents_sixths += sixths * qty
		var contents_stone: float = contents_sixths / 6.0
		var capacity: float = _container_capacity(container)

		var hdr := HBoxContainer.new()
		hdr.add_theme_constant_override("separation", 6)
		add_child(hdr)

		var hdr_lbl := Label.new()
		hdr_lbl.text = container.get("name", container.get("item_key", "?"))
		hdr_lbl.add_theme_font_size_override("font_size", 12)
		hdr_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hdr.add_child(hdr_lbl)

		if capacity > 0:
			var cap_lbl := Label.new()
			cap_lbl.text = "%.2f / %.2f stone" % [contents_stone, capacity]
			cap_lbl.add_theme_font_size_override("font_size", 11)
			cap_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			hdr.add_child(cap_lbl)

		var drop_btn := Button.new()
		drop_btn.text = "Drop"
		drop_btn.custom_minimum_size = Vector2(50, 0)
		drop_btn.add_theme_color_override("font_color", Color(0.9, 0.4, 0.2))
		drop_btn.pressed.connect(_on_drop_container.bind(cid))
		hdr.add_child(drop_btn)

		if contents.is_empty():
			var empty_lbl := Label.new()
			empty_lbl.text = "    (empty)"
			empty_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
			add_child(empty_lbl)
		else:
			for ci in contents:
				var ci_row := HBoxContainer.new()
				ci_row.add_theme_constant_override("separation", 6)
				add_child(ci_row)

				var ci_name := Label.new()
				var ci_sixths: int = int(ci.get("encumbrance_sixths", 0))
				var ci_qty: int = int(ci.get("quantity", 1))
				var ci_stone_str := " (%.2f st)" % (ci_sixths * ci_qty / 6.0) if ci_sixths > 0 else ""
				ci_name.text = "    \u2022 " + _item_display_name(ci) + ci_stone_str
				ci_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				ci_row.add_child(ci_name)

				var rm_btn := Button.new()
				rm_btn.text = "Remove"
				rm_btn.custom_minimum_size = Vector2(65, 0)
				rm_btn.flat = true
				var ci_id: String = ci.get("id", "")
				rm_btn.pressed.connect(_on_remove_from_container.bind(ci_id))
				ci_row.add_child(rm_btn)

		var movable: Array = _get_loose_movable_items(bundle, cid)
		if not movable.is_empty():
			var move_hdr := Label.new()
			move_hdr.text = "    Move to %s:" % container.get("name", "container")
			move_hdr.add_theme_font_size_override("font_size", 10)
			move_hdr.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
			add_child(move_hdr)

			for mi in movable:
				var mi_row := HBoxContainer.new()
				mi_row.add_theme_constant_override("separation", 6)
				add_child(mi_row)

				var mi_name := Label.new()
				mi_name.text = "      " + _item_display_name(mi)
				mi_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				mi_row.add_child(mi_name)

				var mv_btn := Button.new()
				mv_btn.text = "Move in"
				mv_btn.custom_minimum_size = Vector2(65, 0)
				mv_btn.flat = true
				var mi_id: String = mi.get("id", "")
				mv_btn.pressed.connect(_on_move_into_container.bind(mi_id, cid))
				mi_row.add_child(mv_btn)


func _render_loose(bundle: CharacterBundle) -> void:
	## Items carried but not equipped and not in a container.
	## Excludes equippable items (those are shown in the Equipped section).
	var loose: Array = []
	for item in bundle.inventory:
		if _is_container(item):
			continue
		if _can_equip(item):
			continue  ## shown in Equipped / Available to equip
		if bool(int(item.get("is_equipped", 0))):
			continue
		var cid: String = item.get("container_id", "")
		if not cid.is_empty():
			continue
		loose.append(item)

	if loose.is_empty():
		return

	add_child(HSeparator.new())
	_add_section_header("Loose Carry (no container)")

	for item in loose:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		add_child(row)

		var sixths: int = int(item.get("encumbrance_sixths", 0))
		var qty: int = int(item.get("quantity", 1))
		var stone_str := " (%.2f st)" % (sixths * qty / 6.0) if sixths > 0 else ""

		var name_lbl := Label.new()
		name_lbl.text = "  \u2022 " + _item_display_name(item) + stone_str
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(name_lbl)


# ---------------------------------------------------------------------------
# Button callbacks
# ---------------------------------------------------------------------------

func _on_equip(item_id: String) -> void:
	if _bundle == null:
		return
	var item: Dictionary = {}
	for i in _bundle.inventory:
		if i.get("id", "") == item_id:
			item = i
			break
	if item.is_empty():
		return
	var slot := _determine_equip_slot(item)
	if slot.is_empty():
		push_warning("CSTabEquipment: no free slot for %s" % item.get("item_key", "?"))
		return
	var item_key: String = item.get("item_key", "")
	var qty: int = int(item.get("quantity", 1))
	# Bundle items in hand slots: split one unit off the stack
	if item_key in HAND_HOLDABLE_KEYS and qty > 1:
		var catalog_entry: Dictionary = _get_catalog().get_item(item_key)
		var uses_per_unit: int = int(catalog_entry.get("uses_per_unit", -1))
		if not CampaignRepository.split_item_for_equip(item_id, slot, uses_per_unit).is_empty():
			EventBus.inventory_updated.emit(_character_id)
	else:
		if CampaignRepository.update_inventory_item_equip_state(item_id, true, slot, ""):
			EventBus.inventory_updated.emit(_character_id)


func _on_unequip(item_id: String) -> void:
	# Look up the item to check if it's a hand-held bundle item needing merge logic
	var item: Dictionary = {}
	if _bundle != null:
		for i in _bundle.inventory:
			if i.get("id", "") == item_id:
				item = i
				break
	var item_key: String = item.get("item_key", "")
	if item_key in HAND_HOLDABLE_KEYS:
		var catalog_entry: Dictionary = _get_catalog().get_item(item_key)
		var uses_per_unit: int = int(catalog_entry.get("uses_per_unit", -1))
		if CampaignRepository.merge_item_on_unequip(item_id, uses_per_unit):
			EventBus.inventory_updated.emit(_character_id)
	else:
		if CampaignRepository.update_inventory_item_equip_state(item_id, false, "pack", ""):
			EventBus.inventory_updated.emit(_character_id)


func _on_move_into_container(item_id: String, container_id: String) -> void:
	if CampaignRepository.update_inventory_item_equip_state(item_id, false, "pack", container_id):
		EventBus.inventory_updated.emit(_character_id)


func _on_remove_from_container(item_id: String) -> void:
	if CampaignRepository.update_inventory_item_equip_state(item_id, false, "pack", ""):
		EventBus.inventory_updated.emit(_character_id)


func _on_drop_container(container_item_id: String) -> void:
	if CampaignRepository.drop_container(container_item_id):
		EventBus.inventory_updated.emit(_character_id)


# ---------------------------------------------------------------------------
# Equip routing
# ---------------------------------------------------------------------------

func _can_equip(item: Dictionary) -> bool:
	var category: String = item.get("item_category", "")
	var item_key: String = item.get("item_key", "")
	if category in EQUIPPABLE_CATEGORIES:
		return true
	if category == "gear":
		if item_key in HAND_HOLDABLE_KEYS:
			return true
		if item_key in ACCESSORY_KEYS:
			return true
	## Boots and gloves by item_key substring (for when clothing has these sub-types)
	if "boots" in item_key or "sandals" in item_key:
		return true
	if "gloves" in item_key or "gauntlets" in item_key:
		return true
	return false


func _determine_equip_slot(item: Dictionary) -> String:
	var category: String = item.get("item_category", "")
	var item_key: String = item.get("item_key", "")

	match category:
		"armor":
			if not _is_slot_equipped("body"):
				return "body"
			return ""

		"clothing":
			if "belt" in item_key:
				if not _is_slot_equipped("belt"):
					return "belt"
				return ""
			if "boots" in item_key or "sandals" in item_key:
				if not _is_slot_equipped("feet"):
					return "feet"
				return ""
			if "gloves" in item_key or "gauntlets" in item_key:
				if not _is_slot_equipped("hands_worn"):
					return "hands_worn"
				return ""
			if "hat" in item_key or "skullcap" in item_key or "veil" in item_key:
				if not _is_slot_equipped("head"):
					return "head"
				return ""
			if "cloak" in item_key:
				if not _is_slot_equipped("cloak"):
					return "cloak"
				return ""
			## All other clothing (tunics, robes, dresses, gowns, cassocks, etc.) → body
			if not _is_slot_equipped("body"):
				return "body"
			return ""

		"shield":
			if _is_main_hand_two_handed():
				return ""  ## two-handed weapon blocks off hand
			if not _is_slot_equipped("hands_off"):
				return "hands_off"
			return ""

		"weapon":
			if _is_two_handed_weapon(item):
				## Two-handed needs both hands free
				if not _is_slot_equipped("hands_main") and not _is_slot_equipped("hands_off"):
					return "hands_main"
				return ""
			## One-handed: blocked if a two-handed weapon occupies main hand
			if _is_main_hand_two_handed():
				return ""
			if not _is_slot_equipped("hands_main"):
				return "hands_main"
			if not _is_slot_equipped("hands_off"):
				return "hands_off"
			return ""

		"gear":
			if item_key in HAND_HOLDABLE_KEYS:
				if not _is_slot_equipped("hands_main"):
					return "hands_main"
				if not _is_main_hand_two_handed() and not _is_slot_equipped("hands_off"):
					return "hands_off"
				return ""
			if item_key in ACCESSORY_KEYS:
				for slot in ACCESSORY_SLOTS:
					if not _is_slot_equipped(slot):
						return slot
				return ""

	return ""


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _is_slot_equipped(slot: String) -> bool:
	if _bundle == null:
		return false
	for item in _bundle.inventory:
		if bool(int(item.get("is_equipped", 0))) and item.get("slot", "") == slot:
			return true
	return false


func _is_main_hand_two_handed() -> bool:
	if _bundle == null:
		return false
	for item in _bundle.inventory:
		if bool(int(item.get("is_equipped", 0))) and item.get("slot", "") == "hands_main":
			return _is_two_handed_weapon(item)
	return false


func _is_two_handed_weapon(item: Dictionary) -> bool:
	var tags: Array = _get_catalog().get_item(item.get("item_key", "")).get("weapon_tags", [])
	return "two_handed" in tags


func _get_catalog() -> EquipmentCatalog:
	if _catalog == null:
		_catalog = EquipmentCatalog.new()
	return _catalog


func _is_container(item: Dictionary) -> bool:
	var key: String = item.get("item_key", "").to_lower()
	for ck in CONTAINER_KEYS:
		if ck in key:
			return true
	return false


func _container_capacity(container: Dictionary) -> float:
	var key: String = container.get("item_key", "").to_lower()
	for ck in CONTAINER_CAPACITY_STONE:
		if ck in key:
			return CONTAINER_CAPACITY_STONE[ck]
	return 0.0


func _get_loose_movable_items(bundle: CharacterBundle, _exclude_container_id: String) -> Array:
	## Returns non-equippable, non-container items not yet in any container.
	var result: Array = []
	for item in bundle.inventory:
		if _is_container(item):
			continue
		if _can_equip(item):
			continue
		if bool(int(item.get("is_equipped", 0))):
			continue
		var cid: String = item.get("container_id", "")
		if not cid.is_empty():
			continue
		result.append(item)
	return result


func _item_display_name(item: Dictionary) -> String:
	var name_str: String = item.get("name", item.get("item_key", "?"))
	var qty: int = int(item.get("quantity", 1))
	var mag: int = int(item.get("magical_bonus", 0))
	var dmg: String = item.get("weapon_damage", "")
	var result := name_str
	if qty > 1:
		result += " \u00d7%d" % qty
	if mag > 0:
		result += " +%d" % mag
	if not dmg.is_empty():
		result += " (%s)" % dmg
	return result


# ---------------------------------------------------------------------------
# Layout helpers
# ---------------------------------------------------------------------------

func _add_section_header(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	add_child(lbl)
	add_child(HSeparator.new())


func _add_text(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(lbl)
