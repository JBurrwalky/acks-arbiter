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


static func calculate_encumbrance(inventory: Array) -> Dictionary:
	## Takes an Array of InventoryItem (or Dictionaries with same fields).
	## Returns encumbrance summary with movement rates.
	var total_units: int = 0
	for item in inventory:
		total_units += calculate_item_encumbrance(item)
	var movement := get_movement_tier(total_units)
	return {
		"total_units": total_units,
		"total_stone": total_units / 1000.0,
		"exploration_speed": movement.exploration,
		"combat_speed": movement.combat,
		"running_speed": movement.running,
		"is_overloaded": total_units > 20000,
	}


static func calculate_item_encumbrance(item) -> int:
	## Returns effective encumbrance in units for one inventory item (quantity included).
	## Equipped clothing and equipped accessories (accessory_N slots) weigh 0 — they are
	## considered "worn" and do not encumber. Armor is always weighted even when worn.
	## Accounts for magical armor/shield weight reduction (1000 units = 1 stone per bonus).
	var units: int
	var qty: int
	if item is InventoryItem:
		# Worn clothing/accessories are weightless
		if item.is_equipped and (
			item.item_category == "clothing"
			or item.slot.begins_with("accessory")
		):
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
		# Worn clothing/accessories are weightless
		if is_equipped and (category == "clothing" or slot.begins_with("accessory")):
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
