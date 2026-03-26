class_name InventoryItem
extends RefCounted

## One item in a character's positional inventory.
## Encumbrance tracked in 1/6-stone units (ACKS base unit = "item weight"):
##   1/6 stone = 1 unit (coin/dagger weight)
##   1 stone = 6 units (sword, shield)
##   5 stone = 30 units (plate armour)

var id: String = ""
var character_id: String = ""
var item_key: String = ""           # references data/items catalog
var name: String = ""
var quantity: int = 1
var encumbrance_sixths: int = 0     # weight in 1/6-stone units
var slot: String = "pack"
	# "hands_main"|"hands_off"|"body"|"head"|"belt"|"pack"|"mount"
var is_equipped: bool = false
var notes: String = ""


static func from_dict(data: Dictionary) -> InventoryItem:
	var i := InventoryItem.new()
	i.id = data.get("id", "")
	i.character_id = data.get("character_id", "")
	i.item_key = data.get("item_key", "")
	i.name = data.get("name", "")
	i.quantity = data.get("quantity", 1)
	i.encumbrance_sixths = data.get("encumbrance_sixths", 0)
	i.slot = data.get("slot", "pack")
	# Boolean DB fields are stored as INTEGER (0/1) — convert on read
	i.is_equipped = data.get("is_equipped", 0) == 1
	i.notes = data.get("notes", "")
	return i


func to_dict() -> Dictionary:
	# Booleans become integers (0/1) for SQLite compatibility.
	return {
		"id": id,
		"character_id": character_id,
		"item_key": item_key,
		"name": name,
		"quantity": quantity,
		"encumbrance_sixths": encumbrance_sixths,
		"slot": slot,
		"is_equipped": 1 if is_equipped else 0,
		"notes": notes,
	}


func encumbrance_stone() -> float:
	return encumbrance_sixths / 6.0
