class_name CSTabEquipment
extends VBoxContainer

## Equipment tab — equipped items, containers with contents, loose carry.
## Supports equip/unequip for weapons/armor/shields/clothing/gear, placing items
## into containers via drag-and-drop, and dropping containers.

## Item categories that receive an Equip button in the inventory loose carry zone.
const EQUIPPABLE_CATEGORIES := ["weapon", "armor", "shield", "clothing"]

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
	_render_inventory(bundle)


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

	## Unequipped equippable items now appear in the Inventory section (loose carry)
	## so they can be dragged into containers and equipped from one unified list.


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


func _render_inventory(bundle: CharacterBundle) -> void:
	## Flat inventory list: each container as a drop target (EquipmentContainerRow)
	## followed by the loose carry zone (EquipmentLooseZone).
	_add_section_header("Inventory")

	# Build lookup: container_id -> [items inside it]
	var by_container: Dictionary = {}
	for item in bundle.inventory:
		var cid: String = item.get("container_id", "")
		if cid.is_empty():
			continue
		if not by_container.has(cid):
			by_container[cid] = []
		by_container[cid].append(item)

	# Render each container
	for item in bundle.inventory:
		if not _is_container_item(item):
			continue
		var cid: String = item.get("id", "")
		var contents: Array = by_container.get(cid, [])
		var capacity_units: int = _get_catalog().get_container_capacity_units(item.get("item_key", ""))
		var used_units: int = _calculate_container_used_units(cid)

		var container_row := EquipmentContainerRow.new()
		container_row.setup(
			item,
			contents,
			capacity_units,
			used_units,
			_character_id,
			func(c: Dictionary): _on_drop_container(c.get("id", "")),
			func(ci: Dictionary): _on_remove_from_container(ci.get("id", "")),
		)
		add_child(container_row)

	# Collect loose items: not equipped, not in a container, not a container itself,
	# and not a living creature (those display on the Retainers tab).
	var loose: Array = []
	for item in bundle.inventory:
		if _is_container_item(item):
			continue
		if bool(int(item.get("is_equipped", 0))):
			continue
		if not item.get("container_id", "").is_empty():
			continue
		if item.get("item_category", "") in CSTabRetainers.ANIMAL_CATEGORIES:
			continue
		loose.append(item)

	var loose_zone := EquipmentLooseZone.new()
	loose_zone.setup(
		loose,
		_character_id,
		func(ci: Dictionary): _on_remove_from_container(ci.get("id", "")),
		func(item: Dictionary) -> Callable:
			if _can_equip(item):
				return func(): _on_equip(item.get("id", ""))
			return Callable(),
	)
	add_child(loose_zone)


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

func _is_container_item(item: Dictionary) -> bool:
	return _get_catalog().is_container(item.get("item_key", ""))


func _calculate_container_used_units(container_id: String) -> int:
	var total: int = 0
	if _bundle == null:
		return total
	for item in _bundle.inventory:
		if item.get("container_id", "") == container_id:
			total += int(item.get("encumbrance_units", 0)) * int(item.get("quantity", 1))
	return total


func can_fit_in_container(item: Dictionary, container_id: String) -> bool:
	var container: Dictionary = {}
	if _bundle != null:
		for inv_item in _bundle.inventory:
			if inv_item.get("id", "") == container_id:
				container = inv_item
				break
	if container.is_empty():
		return false
	var capacity: int = _get_catalog().get_container_capacity_units(container.get("item_key", ""))
	if capacity <= 0:
		return false
	var used: int = _calculate_container_used_units(container_id)
	var item_units: int = int(item.get("encumbrance_units", 0)) * int(item.get("quantity", 1))
	return (used + item_units) <= capacity


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
