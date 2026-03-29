class_name DamageTypes
extends RefCounted

## Canonical damage type constants.
## Used by DamageResistance, InventoryItem.damage_type, and combat damage application.
## This class is never instantiated — reference constants directly: DamageTypes.FIRE

const PHYSICAL := "physical"    # slashing, piercing, bludgeoning (non-magical weapons)
const FIRE := "fire"
const COLD := "cold"
const LIGHTNING := "lightning"
const ACID := "acid"
const NECROTIC := "necrotic"    # unholy/death energy
const FORCE := "force"          # magic missile, wall of force
const UNTYPED := "untyped"      # damage that bypasses all resistances
const HOLY := "holy"            # alignment-based divine damage (Forbiddance)

const ALL_TYPES: Array[String] = [
	PHYSICAL, FIRE, COLD, LIGHTNING, ACID, NECROTIC, FORCE, UNTYPED, HOLY
]


static func is_valid(damage_type: String) -> bool:
	return damage_type in ALL_TYPES
