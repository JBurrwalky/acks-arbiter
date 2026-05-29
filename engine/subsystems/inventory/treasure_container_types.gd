class_name TreasureContainerTypes
extends RefCounted

## Catalog of treasure container types for the cell-based loot model
## (see generation/gdd-treasure-item-backing.md §15).
##
## Each container type is a label persisted on `treasure_hoards.container_type`
## and materialized at first visit as an `inventory_items` row referenced via
## `location_caches.container_item_id`. The properties below drive what the
## placement service is allowed to do with each type.

const CHEST: String = "chest"
const BARREL: String = "barrel"
const SACK: String = "sack"
const COIN_PILE: String = "coin_pile"
const GEAR_PILE: String = "gear_pile"

const VALID: Array[String] = [CHEST, BARREL, SACK, COIN_PILE, GEAR_PILE]

## Per-type capability flags + display data. V1 keeps these as a static dict
## for readability; if the catalog grows we can promote to a JSON data file.
const PROPERTIES: Dictionary = {
	CHEST: {
		"display_name": "Treasure Chest",
		"can_lock":  true,   # carry a lock (Pick Lock or key to open)
		"can_trap":  true,   # carry a trap (fires on open)
		"can_hide":  true,   # can be hidden (Search to reveal)
		"opaque":    true,   # contents not visible without opening
		"weight_units": 6000,  # 6 stone — heavy, immobile container
	},
	BARREL: {
		"display_name": "Barrel",
		"can_lock":  true,
		"can_trap":  true,
		"can_hide":  true,
		"opaque":    true,
		"weight_units": 8000,  # 8 stone
	},
	SACK: {
		"display_name": "Sack",
		"can_lock":  true,   # tied / locked-pouch; rarer than chest locks
		"can_trap":  false,  # too small / cloth — no trap mechanism
		"can_hide":  true,
		"opaque":    true,
		"weight_units": 100,  # 0.1 stone — light, portable
	},
	COIN_PILE: {
		"display_name": "Pile of Coins",
		"can_lock":  false,  # loose pile — nothing to lock
		"can_trap":  false,
		"can_hide":  true,   # under dust / sand / rubble
		"opaque":    false,  # coins are visible on the floor
		"weight_units": 0,    # the pile itself is weightless — the coins ARE the weight
	},
	GEAR_PILE: {
		"display_name": "Pile of Gear",
		"can_lock":  false,
		"can_trap":  false,
		"can_hide":  true,
		"opaque":    false,
		"weight_units": 0,
	},
}


static func is_valid(container_type: String) -> bool:
	return container_type in VALID


static func display_name(container_type: String) -> String:
	return str(PROPERTIES.get(container_type, {}).get("display_name", container_type))


static func can_lock(container_type: String) -> bool:
	return bool(PROPERTIES.get(container_type, {}).get("can_lock", false))


static func can_trap(container_type: String) -> bool:
	return bool(PROPERTIES.get(container_type, {}).get("can_trap", false))


static func can_hide(container_type: String) -> bool:
	return bool(PROPERTIES.get(container_type, {}).get("can_hide", false))


static func is_opaque(container_type: String) -> bool:
	return bool(PROPERTIES.get(container_type, {}).get("opaque", false))


static func weight_units(container_type: String) -> int:
	return int(PROPERTIES.get(container_type, {}).get("weight_units", 0))
