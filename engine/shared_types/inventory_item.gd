class_name InventoryItem
extends RefCounted

## One item in a character's positional inventory.
## Encumbrance tracked in 1/1000-stone units:
##   1 unit   = 1/1000 stone (coin or gem weight)
##   167 units = 1/6 stone   (standard "item weight" — dagger, potion, scroll)
##   1000 units = 1 stone    (sword, shield)
##   6000 units = 6 stone    (plate armour)

var id: String = ""
var character_id: String = ""
var creature_id: String = ""
var container_id: String = ""       # id of container item this is inside (empty = not in container)
var vehicle_id: String = ""         # id of draft_vehicle this is stored in (empty = not in vehicle)
var item_key: String = ""           # references data/equipment catalog
var name: String = ""
var quantity: int = 1
var encumbrance_units: int = 0      # weight in 1/1000-stone units
var slot: String = "pack"
	# "hands_main"|"hands_off"|"body"|"head"|"belt"|"feet"|"hands_worn"|"cloak"
	# |"accessory_1"–"accessory_5"|"pack"|"mount"
var is_equipped: bool = false
var notes: String = ""

## Combat-relevant fields (migration 005)
var item_category: String = "gear"  # "weapon"|"armor"|"shield"|"gear"|"treasure"|"ammunition"
var is_magical: bool = false
var magical_bonus: int = 0          # +1, +2, +3 etc.
var weapon_damage: String = ""      # e.g., "1d8" (empty for non-weapons)
var armor_ac_bonus: int = 0         # AC granted by this armor/shield
var is_heavy: bool = false          # true = 1 stone each (two-handed weapons, items >= 8 lbs)

## Spell hook fields — persistent (migration 006)
var damage_type: String = "physical"  # DamageTypes constant; damage dealt by this weapon
var material: String = ""             # "wood"|"metal"|"stone"|"leather"|"" (used by spell targeting)

## Consumable state — migration 012
## -1 = not a consumable. Positive = remaining uses/turns before depletion.
## Examples: torch = 6 turns, lantern oil = 24 turns, scroll = 1 charge.
var uses_remaining: int = -1

## Economic value — migration 134
## -1 = no intrinsic value; value this item by item_key -> EquipmentCatalog.cost_cp
## (mundane equipment). >= 0 = authoritative per-item value in copper pieces, for
## rolled valuables (gems, jewelry, special-treasure trade goods, identified magic
## items) whose value is not a fixed catalog price. See gdd-treasure-item-backing.md.
var value_cp: int = -1

## Cursed flag — migration 136
## true = `CampaignRepository.update_inventory_item_equip_state` refuses to
## UNEQUIP this item (RAW acore_treasure_and_magic_items_rules.xml:235: "Cursed
## items cannot be discarded except by dispel evil or remove curse"). The
## negative `magical_bonus` term itself flows through the existing +N paths;
## this field is the sticky-equip signal only. Equipping a cursed item is
## unrestricted (the owner doesn't know — RAW :236).
var is_cursed: bool = false

## Container runtime state — migration 138 (cell-based treasure containers arc,
## see gdd-treasure-item-backing.md §15). chest / barrel / sack hoards
## materialize into a backing inventory_items row that IS the container; the
## container's lock + trap state lives here so the per-cell interaction layer
## can gate opening without re-reading the source treasure_hoards row.
## For non-container items, both default to false (the schema default).
var is_locked: bool = false
var is_trapped: bool = false

## Spell hook fields — runtime only (not persisted; set by active spell effects)
var spell_bonus: int = 0              # temporary bonus from spells (e.g., Bless Weapon)
var spell_damage_bonus: String = ""   # extra damage dice from spells (e.g., "1d6" from Striking)


func get_effective_bonus() -> int:
	## Returns the total attack/damage bonus for this item (permanent + active spell bonus).
	return magical_bonus + spell_bonus


static func from_dict(data: Dictionary) -> InventoryItem:
	var i := InventoryItem.new()
	i.id = _str_or_empty(data.get("id"))
	i.character_id = _str_or_empty(data.get("character_id"))
	i.creature_id = _str_or_empty(data.get("creature_id"))
	i.container_id = _str_or_empty(data.get("container_id"))
	i.vehicle_id = _str_or_empty(data.get("vehicle_id"))
	i.item_key = data.get("item_key", "")
	i.name = data.get("name", "")
	i.quantity = data.get("quantity", 1)
	i.encumbrance_units = data.get("encumbrance_units", data.get("encumbrance_sixths", 0))
	i.slot = data.get("slot", "pack")
	i.notes = data.get("notes", "")
	i.item_category = data.get("item_category", "gear")
	i.magical_bonus = data.get("magical_bonus", 0)
	i.weapon_damage = data.get("weapon_damage", "")
	i.armor_ac_bonus = data.get("armor_ac_bonus", 0)
	# Boolean DB fields are stored as INTEGER (0/1) — convert on read
	i.is_equipped = data.get("is_equipped", 0) == 1
	i.is_magical = data.get("is_magical", 0) == 1
	i.is_heavy = data.get("is_heavy", 0) == 1
	i.damage_type = data.get("damage_type", "physical")
	i.material = data.get("material", "")
	i.uses_remaining = data.get("uses_remaining", -1)
	i.value_cp = data.get("value_cp", -1)
	i.is_cursed = data.get("is_cursed", 0) == 1
	i.is_locked = data.get("is_locked", 0) == 1
	i.is_trapped = data.get("is_trapped", 0) == 1
	return i


func to_dict() -> Dictionary:
	# Booleans become integers (0/1) for SQLite compatibility.
	return {
		"id": id,
		"character_id": character_id,
		"creature_id": creature_id,
		"container_id": container_id,
		"vehicle_id": vehicle_id,
		"item_key": item_key,
		"name": name,
		"quantity": quantity,
		"encumbrance_units": encumbrance_units,
		"slot": slot,
		"is_equipped": 1 if is_equipped else 0,
		"notes": notes,
		"item_category": item_category,
		"is_magical": 1 if is_magical else 0,
		"magical_bonus": magical_bonus,
		"weapon_damage": weapon_damage,
		"armor_ac_bonus": armor_ac_bonus,
		"is_heavy": 1 if is_heavy else 0,
		"damage_type": damage_type,
		"material": material,
		"uses_remaining": uses_remaining,
		"value_cp": value_cp,
		"is_cursed": 1 if is_cursed else 0,
		"is_locked": 1 if is_locked else 0,
		"is_trapped": 1 if is_trapped else 0,
	}


func encumbrance_stone() -> float:
	return encumbrance_units / 1000.0


func effective_value_cp(catalog) -> int:
	## Authoritative monetary value of one unit, in copper pieces.
	## value_cp >= 0 is intrinsic (rolled valuables: gems, jewelry, trade goods,
	## identified magic items). value_cp < 0 means "value by catalog cost_cp"
	## (mundane equipment). `catalog` is an EquipmentCatalog instance (or null).
	if value_cp >= 0:
		return value_cp
	if catalog == null:
		return 0
	return int(catalog.get_item(item_key).get("cost_cp", 0))


static func _str_or_empty(value) -> String:
	## SQLite returns null for nullable columns; coerce to "".
	if value == null:
		return ""
	return str(value)
