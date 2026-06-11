class_name EncumbranceCalculator
extends RefCounted

## Calculates encumbrance and movement rates from inventory.
## ACKS encumbrance rules (from acore_equipment.xml):
##   Armor: 1 stone per AC bonus (magical reduces by 1 stone per magic bonus)
##   Items: weight tracked in encumbrance_units (1/1000 stone per unit)
##   Heavy items: flagged with is_heavy, each weighs 1 stone (1000 units)
##   Treasure: 1 stone per 1000 coins/gems (1 unit per coin/gem)
##
## Movement table (ACKS):
##   <= 5 stone (<=5000 units): 120'/turn, 40'/round, 120'/round running
##   <= 7 stone (<=7000 units): 90'/turn, 30'/round, 90'/round running
##   <= 10 stone (<=10000 units): 60'/turn, 20'/round, 60'/round running
##   <= 20 stone (<=20000 units): 30'/turn, 10'/round, 30'/round running
##
## ## Container-as-sub-carrier (2026-05-31)
##
## Containers (items with at least one other item pointing to them via
## `container_id`) act as SUB-CARRIERS, not flat groupings:
##   - Items inside a container do NOT contribute their individual weight
##     to the bearer's total.
##   - Instead, each container contributes its AGGREGATE weight, computed
##     per its own rules.
##   - Mundane container aggregate = own weight + sum(contents weights).
##   - Extradimensional container aggregate = own weight ONLY (contents
##     are weightless to the bearer regardless of how much is inside;
##     migration-139 `is_extradimensional` flag).
##   - Nesting is supported recursively (pouch in backpack in chest etc.).
##
## Previously, every inventory_items row owned by the character was summed
## flat — containers were a UI grouping only. The new model matches RAW
## (Bag of Holding fixed-weight regardless of contents, locked-chest carry
## semantics, saddlebags as a mount's sub-carrier, etc.). Backward-compat
## for inventories with NO containers (the common pre-refactor case):
## identical totals to the old flat-sum behavior.


static func calculate_encumbrance(inventory: Array) -> Dictionary:
	## Takes an Array of InventoryItem (or Dictionaries with same fields).
	## Returns encumbrance summary with movement rates.
	##
	## Container-aware: items with a non-empty `container_id` are deferred
	## from the top-level sum; their weight contributes only through the
	## containing item's aggregate. See `_calculate_container_aggregate_weight`.
	var total_units: int = _sum_with_containers(inventory)
	var movement := get_movement_tier(total_units)
	return {
		"total_units": total_units,
		"total_stone": total_units / 1000.0,
		"exploration_speed": movement.exploration,
		"combat_speed": movement.combat,
		"running_speed": movement.running,
		"is_overloaded": total_units > 20000,
	}


## Sum the bearer's effective encumbrance from a flat inventory list,
## treating containers as sub-carriers. Two passes:
##   1. Group items by `container_id`: loose items (no parent container) +
##      a map of `parent_container_id -> Array[item]` for contents.
##   2. For each loose item, compute its weight (or its container-aggregate
##      weight if it has contents pointing at it). Container-aggregate
##      recurses into nested containers via the same map.
static func _sum_with_containers(inventory: Array) -> int:
	var loose_items: Array = []
	var contents_by_parent: Dictionary = {}  # parent_id -> Array of items
	for item in inventory:
		var parent_id: String = _container_id_of(item)
		if parent_id.is_empty():
			loose_items.append(item)
		else:
			if not contents_by_parent.has(parent_id):
				contents_by_parent[parent_id] = []
			contents_by_parent[parent_id].append(item)

	var total: int = 0
	for item in loose_items:
		total += _weight_of_loose_or_container(item, contents_by_parent)
	return total


## Returns the encumbrance contribution of a top-level (loose) item to the
## bearer. If the item has contents (anything in `contents_by_parent`
## pointing at it), it's a container — compute its aggregate. Otherwise,
## standard per-item weight.
static func _weight_of_loose_or_container(item, contents_by_parent: Dictionary) -> int:
	var id: String = _id_of(item)
	if not id.is_empty() and contents_by_parent.has(id):
		return _calculate_container_aggregate_weight(
			item, contents_by_parent[id], contents_by_parent)
	return calculate_item_encumbrance(item)


## Compute the aggregate weight of a container (own weight + contents per
## its rules):
##   - Extradimensional container: own weight only (Bag of Holding etc.).
##   - Mundane container: own weight + recursive aggregate of every content
##     (each content may itself be a nested container).
##
## `contents` is the direct children of this container; deeper nesting is
## resolved by passing `contents_by_parent` through to the recursive calls.
static func _calculate_container_aggregate_weight(
		container, contents: Array, contents_by_parent: Dictionary) -> int:
	var own_weight: int = calculate_item_encumbrance(container)
	if _is_extradimensional(container):
		# Contents are weightless to the bearer regardless of total inside.
		# UI may still display container-internal "X / Y stones used" via
		# its own calculation (separate from bearer encumbrance).
		return own_weight
	var total: int = own_weight
	for content in contents:
		var content_id: String = _id_of(content)
		if not content_id.is_empty() and contents_by_parent.has(content_id):
			# Nested container — recurse.
			total += _calculate_container_aggregate_weight(
				content, contents_by_parent[content_id], contents_by_parent)
		else:
			# Leaf item — standard per-item weight.
			total += calculate_item_encumbrance(content)
	return total


## Slots whose occupant is weightless when WORN regardless of item_category —
## the ornamentation + ring slots from gdd-character-tab.md §3.4.6. Clothing-
## category items (tunics, robes, hats, shoes, belts, cloaks) are handled by
## the category test in `_is_worn_weightless`; these slots additionally cover
## non-clothing ornamentation (holy symbol / amulet on `neck`, a magic cloak,
## and rings, which RAW treats as negligible weight).
const WORN_WEIGHTLESS_SLOTS := ["neck", "cloak", "ring_l", "ring_r"]


## gdd-character-tab.md §3.4.6 clothing-vs-armor stacking rule. An EQUIPPED item
## contributes zero stone when it is non-armor clothing/ornamentation:
##   - any `item_category == "clothing"` item (worn tunic/robe/hat/shoes/belt —
##     full weight only when carried in the pack), OR
##   - any item in an ornamentation/ring slot (neck, cloak, ring_l, ring_r), OR
##   - any legacy `accessory_N` slot occupant (pre-migration-151 saves).
## Armor (slot `armor`), weapons, gauntlets (`hands_worn`), bracers (`arms`),
## helmets (`head`, armor category), and quivered ammo keep their full stone
## whether worn or carried — they fall through to the standard weight path.
static func _is_worn_weightless(is_equipped: bool, category: String, slot: String) -> bool:
	if not is_equipped:
		return false
	if category == "clothing":
		return true
	if slot in WORN_WEIGHTLESS_SLOTS:
		return true
	if slot.begins_with("accessory"):
		return true
	return false


static func calculate_item_encumbrance(item) -> int:
	## Returns effective encumbrance in units for one inventory item (quantity included).
	## Worn clothing/ornamentation/rings weigh 0 per §3.4.6 (see `_is_worn_weightless`);
	## armor is always weighted even when worn (it now lives in its own `armor` slot,
	## coexisting with `torso_clothing`). Accounts for magical armor/shield weight
	## reduction (1000 units = 1 stone per bonus).
	##
	## Container-aware? NO — this function gives the SINGLE item's own weight.
	## Container aggregate (own + contents) lives in
	## `_calculate_container_aggregate_weight`. `calculate_encumbrance` orchestrates
	## the two for a bearer-level total.
	var units: int
	var qty: int
	if item is InventoryItem:
		if _is_worn_weightless(item.is_equipped, item.item_category, item.slot):
			return 0
		units = item.encumbrance_units
		qty = item.quantity
		# Magical armor/shields weigh less: reduce by magical_bonus stones (x1000 units)
		if item.is_magical and item.item_category in ["armor", "shield"]:
			units = maxi(units - item.magical_bonus * 1000, 0)
	else:
		# Dictionary path (from DB rows)
		var is_equipped: bool = int(item.get("is_equipped", 0)) == 1
		var category: String = item.get("item_category", "gear")
		var slot: String = item.get("slot", "pack")
		if _is_worn_weightless(is_equipped, category, slot):
			return 0
		units = int(item.get("encumbrance_units", 0))
		qty = int(item.get("quantity", 1))
		var is_magical: bool = item.get("is_magical", 0) == 1 if item.get("is_magical", 0) is int else bool(item.get("is_magical", false))
		if is_magical and category in ["armor", "shield"]:
			var bonus: int = int(item.get("magical_bonus", 0))
			units = maxi(units - bonus * 1000, 0)
	return units * qty


static func get_movement_tier(total_units: int) -> Dictionary:
	## Returns movement rates based on total encumbrance in units (1 unit = 1/1000 stone).
	if total_units <= 5000:    # <= 5 stone
		return {"exploration": 120, "combat": 40, "running": 120}
	if total_units <= 7000:    # <= 7 stone
		return {"exploration": 90, "combat": 30, "running": 90}
	if total_units <= 10000:   # <= 10 stone
		return {"exploration": 60, "combat": 20, "running": 60}
	# Up to max capacity (20 stone = 20000 units)
	return {"exploration": 30, "combat": 10, "running": 30}


# ---------------------------------------------------------------------------
# Dual-shape helpers — item may be InventoryItem OR Dictionary (DB row).
# Mirrors the pattern used in calculate_item_encumbrance above.
# ---------------------------------------------------------------------------

static func _id_of(item) -> String:
	if item is InventoryItem:
		return item.id
	if item is Dictionary:
		return str(item.get("id", ""))
	return ""


static func _container_id_of(item) -> String:
	## The id of the container this item is INSIDE (i.e., the parent
	## container in the sub-carrier model). Empty string = loose / top-level.
	if item is InventoryItem:
		return item.container_id
	if item is Dictionary:
		return str(item.get("container_id", ""))
	return ""


static func _is_extradimensional(item) -> bool:
	if item is InventoryItem:
		return item.is_extradimensional
	if item is Dictionary:
		var raw = item.get("is_extradimensional", 0)
		if raw is bool:
			return raw
		return int(raw) == 1
	return false
