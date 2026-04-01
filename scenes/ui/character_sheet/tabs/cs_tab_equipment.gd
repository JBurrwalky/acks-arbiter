class_name CSTabEquipment
extends VBoxContainer

## Equipment tab — equipped items, containers with contents, loose carry.
## Supports equip/unequip for weapons/armor/shields, placing items into containers,
## and dropping containers (removes the container and all its contents from inventory).

const EQUIPPABLE_CATEGORIES := ["weapon", "armor", "shield"]

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

const SLOT_LABELS := {
	"hands_main": "Main Hand",
	"hands_off":  "Off Hand",
	"body":       "Body",
	"head":       "Head",
	"belt":       "Belt",
}

var _character_id: String = ""
var _bundle: CharacterBundle = null


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

	## Show primary body slots; each shows the equipped item or "—"
	var equipped_by_slot: Dictionary = {}
	for item in bundle.inventory:
		if bool(int(item.get("is_equipped", 0))):
			var s: String = item.get("slot", "pack")
			equipped_by_slot[s] = item

	for slot in ["hands_main", "hands_off", "body", "head", "belt"]:
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

	## Also show any unequipped equippable items with an Equip button
	var has_unequipped := false
	for item in bundle.inventory:
		var cat: String = item.get("item_category", "")
		if cat not in EQUIPPABLE_CATEGORIES:
			continue
		if bool(int(item.get("is_equipped", 0))):
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

		var equip_btn := Button.new()
		equip_btn.text = "Equip"
		equip_btn.custom_minimum_size = Vector2(60, 0)
		var item_id: String = item.get("id", "")
		var item_cat: String = item.get("item_category", "")
		equip_btn.pressed.connect(_on_equip.bind(item_id, item_cat))
		row.add_child(equip_btn)


func _render_containers(bundle: CharacterBundle) -> void:
	## Find container items in inventory
	var containers: Array = []
	for item in bundle.inventory:
		if _is_container(item):
			containers.append(item)

	if containers.is_empty():
		return

	_add_section_header("Containers")

	## Build a lookup of items by container_id
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

		## Compute contents weight
		var contents_sixths: float = 0.0
		for ci in contents:
			var sixths: int = int(ci.get("encumbrance_sixths", 0))
			var qty: int = int(ci.get("quantity", 1))
			contents_sixths += sixths * qty
		var contents_stone: float = contents_sixths / 6.0
		var capacity: float = _container_capacity(container)

		## Container header row
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

		## Contents
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

		## "Move item here" button for loose items
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
	## Items in pack slot with no container, that are not containers themselves
	var loose: Array = []
	for item in bundle.inventory:
		if _is_container(item):
			continue
		var cat: String = item.get("item_category", "")
		if cat in EQUIPPABLE_CATEGORIES:
			continue  ## equippables already shown in the Equipped section
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

func _on_equip(item_id: String, item_category: String) -> void:
	var slot := _determine_equip_slot(item_category)
	if slot.is_empty():
		push_warning("CSTabEquipment: no free slot available for %s" % item_category)
		return
	if CampaignRepository.update_inventory_item_equip_state(item_id, true, slot, ""):
		EventBus.inventory_updated.emit(_character_id)


func _on_unequip(item_id: String) -> void:
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
# Helpers
# ---------------------------------------------------------------------------

func _determine_equip_slot(category: String) -> String:
	match category:
		"armor":
			if not _is_slot_equipped("body"):
				return "body"
			return ""
		"shield":
			if not _is_slot_equipped("hands_off"):
				return "hands_off"
			return ""
		"weapon":
			if not _is_slot_equipped("hands_main"):
				return "hands_main"
			if not _is_slot_equipped("hands_off"):
				return "hands_off"
			return ""
	return ""


func _is_slot_equipped(slot: String) -> bool:
	if _bundle == null:
		return false
	for item in _bundle.inventory:
		if bool(int(item.get("is_equipped", 0))) and item.get("slot", "") == slot:
			return true
	return false


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


func _get_loose_movable_items(bundle: CharacterBundle, exclude_container_id: String) -> Array:
	## Returns non-equippable, non-container items not yet in any container.
	var result: Array = []
	for item in bundle.inventory:
		if _is_container(item):
			continue
		var cat: String = item.get("item_category", "")
		if cat in EQUIPPABLE_CATEGORIES:
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
