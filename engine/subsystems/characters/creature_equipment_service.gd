class_name CreatureEquipmentService
extends RefCounted

## Validation and slot determination for equipping items on trained creatures.
##
## Slot mapping (reuses existing slot values; creature_id distinguishes ownership):
##   Barding     -> slot "body",  is_equipped = true
##   Saddle      -> slot "mount", is_equipped = true
##   Saddlebags  -> slot "pack",  is_equipped = true
##   Caparison   -> slot "pack",  is_equipped = true
##   Rope/cargo  -> slot "pack",  is_equipped = false


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

## Returns "" if the item can be equipped on the creature, or an error message.
static func validate_equip_on_creature(
		creature: TrainedCreatureData,
		item: Dictionary,
		catalog: EquipmentCatalog) -> String:
	var cat: String = item.get("item_category", "")
	var key: String = item.get("item_key", "")

	# Barding
	if cat == "barding":
		if not creature.can_equip_barding():
			return "Creature must be size large or greater to equip barding."
		if has_barding_equipped(creature):
			return "Creature already has barding equipped."
		return ""

	# Saddle (any type)
	if key.begins_with("saddle_"):
		if not creature.can_equip_saddle():
			return "Only mounts, war mounts, and workbeasts can equip saddles."
		if has_saddle_equipped(creature):
			return "Creature already has a saddle equipped."
		return ""

	# Saddlebags or Panniers
	# TODO: Session 5 — replace with §2.3a authoritative validation
	# (panniers should require saddle_pack specifically; saddlebags should be
	# rejected on pack saddles; currently any saddle permits either container)
	if key == "saddlebags" or key == "panniers":
		if not has_saddle_equipped(creature):
			return "A saddle must be equipped before %s." % item.get("name", key)
		if has_pack_container_equipped(creature):
			return "Creature already has a pack container equipped."
		return ""

	# Caparison
	if key == "caparison":
		if not has_saddle_equipped(creature):
			return "A saddle must be equipped before a caparison."
		if _has_caparison_equipped(creature):
			return "Creature already has a caparison equipped."
		return ""

	return "This item cannot be equipped on a creature."


## Returns "" if the item can be placed as loose cargo on the creature, or error.
static func validate_cargo_on_creature(
		creature: TrainedCreatureData,
		item: Dictionary) -> String:
	if creature.get_load_multiplier() <= 0.0:
		return "Creature needs a draft saddle or rope to carry cargo."
	var item_units: int = int(item.get("encumbrance_units", 0)) * int(item.get("quantity", 1))
	var current_units: int = creature.get_current_load_units()
	var max_units: int = creature.get_effective_capacity_max() * 1000
	if current_units + item_units > max_units:
		return "Cargo would exceed creature's maximum carrying capacity (%d stone)." % creature.get_effective_capacity_max()
	return ""


## Returns "" if the item can be placed into the creature's pack container, or error.
## Works with saddlebags, panniers, or any future pack-slot container.
static func validate_into_saddlebags(
		creature: TrainedCreatureData,
		item: Dictionary,
		saddlebag_item_id: String,
		catalog: EquipmentCatalog) -> String:
	if saddlebag_item_id.is_empty():
		return "No pack container specified."
	# Verify the container exists and is equipped on this creature.
	var found_key := ""
	for inv_item in creature.inventory:
		var iid := _get_field(inv_item, "id")
		var ikey := _get_field(inv_item, "item_key")
		var equipped := _get_bool(inv_item, "is_equipped")
		if iid == saddlebag_item_id and (ikey == "saddlebags" or ikey == "panniers") and equipped:
			found_key = ikey
			break
	if found_key.is_empty():
		return "Pack container not found or not equipped on this creature."
	# Check capacity using the actual item_key for catalog lookup.
	var capacity: int = catalog.get_container_capacity_units(found_key)
	if capacity <= 0:
		return "Container has no defined capacity."
	var used: int = _calculate_container_used_units(creature, saddlebag_item_id)
	var item_units: int = int(item.get("encumbrance_units", 0)) * int(item.get("quantity", 1))
	if used + item_units > capacity:
		return "Container is full (%d/%d units used)." % [used, capacity]
	return ""


# ---------------------------------------------------------------------------
# Slot determination
# ---------------------------------------------------------------------------

## Returns the slot for equipping this item on a creature, or "" if not equippable.
static func determine_creature_slot(item: Dictionary) -> String:
	var cat: String = item.get("item_category", "")
	var key: String = item.get("item_key", "")
	if cat == "barding":
		return "body"
	if key.begins_with("saddle_"):
		return "mount"
	if key == "saddlebags" or key == "panniers" or key == "caparison":
		return "pack"
	return ""


# ---------------------------------------------------------------------------
# Equipment queries
# ---------------------------------------------------------------------------

static func has_saddle_equipped(creature: TrainedCreatureData) -> bool:
	for item in creature.inventory:
		var key := _get_field(item, "item_key")
		var equipped := _get_bool(item, "is_equipped")
		if equipped and key.begins_with("saddle_"):
			return true
	return false


static func has_barding_equipped(creature: TrainedCreatureData) -> bool:
	for item in creature.inventory:
		var cat := _get_field(item, "item_category")
		var equipped := _get_bool(item, "is_equipped")
		if equipped and cat == "barding":
			return true
	return false


static func has_saddlebags_equipped(creature: TrainedCreatureData) -> bool:
	return has_pack_container_equipped(creature)


## Returns true if any pack container (saddlebags or panniers) is equipped.
static func has_pack_container_equipped(creature: TrainedCreatureData) -> bool:
	for item in creature.inventory:
		var key := _get_field(item, "item_key")
		var equipped := _get_bool(item, "is_equipped")
		if equipped and (key == "saddlebags" or key == "panniers"):
			return true
	return false


## Returns the inventory item ID of the equipped saddlebags, or "".
static func get_saddlebag_item_id(creature: TrainedCreatureData) -> String:
	return get_pack_container_item_id(creature)


## Returns the inventory item ID of the equipped pack container (saddlebags or panniers), or "".
static func get_pack_container_item_id(creature: TrainedCreatureData) -> String:
	for item in creature.inventory:
		var key := _get_field(item, "item_key")
		var equipped := _get_bool(item, "is_equipped")
		if equipped and (key == "saddlebags" or key == "panniers"):
			return _get_field(item, "id")
	return ""


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

static func _has_caparison_equipped(creature: TrainedCreatureData) -> bool:
	for item in creature.inventory:
		var key := _get_field(item, "item_key")
		var equipped := _get_bool(item, "is_equipped")
		if equipped and key == "caparison":
			return true
	return false


static func _calculate_container_used_units(
		creature: TrainedCreatureData, container_item_id: String) -> int:
	var total := 0
	for item in creature.inventory:
		var cid := _get_field(item, "container_id")
		if cid == container_item_id:
			var enc: int = _get_int(item, "encumbrance_units")
			var qty: int = _get_int(item, "quantity", 1)
			total += enc * qty
	return total


## Reads a string field from either InventoryItem or Dictionary.
static func _get_field(item, field: String, default: String = "") -> String:
	if item is InventoryItem:
		match field:
			"id": return item.id
			"item_key": return item.item_key
			"item_category": return item.item_category
			"slot": return item.slot
			"container_id": return item.container_id
			"name": return item.name
			_: return default
	elif item is Dictionary:
		return str(item.get(field, default))
	return default


## Reads a bool field, handling 0/1 integer DB values.
static func _get_bool(item, field: String) -> bool:
	if item is InventoryItem:
		match field:
			"is_equipped": return item.is_equipped
			"is_magical": return item.is_magical
			"is_heavy": return item.is_heavy
			_: return false
	elif item is Dictionary:
		var val = item.get(field, 0)
		return val == 1 or val == true
	return false


## Reads an int field.
static func _get_int(item, field: String, default: int = 0) -> int:
	if item is InventoryItem:
		match field:
			"encumbrance_units": return item.encumbrance_units
			"quantity": return item.quantity
			"armor_ac_bonus": return item.armor_ac_bonus
			"magical_bonus": return item.magical_bonus
			_: return default
	elif item is Dictionary:
		return int(item.get(field, default))
	return default
