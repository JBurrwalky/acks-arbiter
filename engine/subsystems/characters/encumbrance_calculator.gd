class_name EncumbranceCalculator
extends RefCounted

## Calculates encumbrance and movement rates from inventory.
## ACKS encumbrance rules (from acore_equipment.xml):
##   Armor: 1 stone per AC bonus (magical reduces by 1 stone per magic bonus)
##   Items: weight tracked in encumbrance_sixths (1/6 stone per unit)
##   Heavy items: flagged with is_heavy, each weighs 1 stone (6 sixths)
##   Treasure: 1 stone per 1000 coins (tracked via encumbrance_sixths)
##
## Movement table (ACKS):
##   <= 5 stone (<=30 sixths): 120'/turn, 40'/round, 120'/round running
##   <= 7 stone (<=42 sixths): 90'/turn, 30'/round, 90'/round running
##   <= 10 stone (<=60 sixths): 60'/turn, 20'/round, 60'/round running
##   <= 20 stone (<=120 sixths): 30'/turn, 10'/round, 30'/round running


static func calculate_encumbrance(inventory: Array) -> Dictionary:
	## Takes an Array of InventoryItem (or Dictionaries with same fields).
	## Returns encumbrance summary with movement rates.
	var total_sixths: int = 0
	for item in inventory:
		total_sixths += calculate_item_encumbrance(item)
	var movement := get_movement_tier(total_sixths)
	return {
		"total_sixths": total_sixths,
		"total_stone": total_sixths / 6.0,
		"exploration_speed": movement.exploration,
		"combat_speed": movement.combat,
		"running_speed": movement.running,
		"is_overloaded": total_sixths > 120,
	}


static func calculate_item_encumbrance(item) -> int:
	## Returns effective encumbrance in sixths for one inventory item.
	## Accounts for magical armor/shield weight reduction.
	var sixths: int
	if item is InventoryItem:
		sixths = item.encumbrance_sixths
		# Magical armor/shields weigh less: reduce by magical_bonus stones (x6 sixths)
		if item.is_magical and item.item_category in ["armor", "shield"]:
			sixths = maxi(sixths - item.magical_bonus * 6, 0)
	else:
		# Dictionary path (from DB rows)
		sixths = int(item.get("encumbrance_sixths", 0))
		var is_magical: bool = item.get("is_magical", 0) == 1 if item.get("is_magical", 0) is int else bool(item.get("is_magical", false))
		var category: String = item.get("item_category", "gear")
		if is_magical and category in ["armor", "shield"]:
			var bonus: int = int(item.get("magical_bonus", 0))
			sixths = maxi(sixths - bonus * 6, 0)
	return sixths


static func get_movement_tier(total_sixths: int) -> Dictionary:
	## Returns movement rates based on total encumbrance in sixths.
	if total_sixths <= 30:    # <= 5 stone
		return {"exploration": 120, "combat": 40, "running": 120}
	if total_sixths <= 42:    # <= 7 stone
		return {"exploration": 90, "combat": 30, "running": 90}
	if total_sixths <= 60:    # <= 10 stone
		return {"exploration": 60, "combat": 20, "running": 60}
	# Up to max capacity (20 stone = 120 sixths)
	return {"exploration": 30, "combat": 10, "running": 30}
