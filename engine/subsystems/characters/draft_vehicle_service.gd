class_name DraftVehicleService
extends RefCounted

## Capacity calculation and hitch validation for carts and wagons.
##
## Vehicle capacity depends on the draft team composition per ACKS rules
## (acore_equipment.xml:623-628). Capacity is looked up from a table, not
## computed from a formula.


# ---------------------------------------------------------------------------
# ACKS Vehicle Capacity Table (SACRED — from acore_equipment.xml)
# ---------------------------------------------------------------------------

## Each entry: {min_equiv, load_normal, load_max, speed_normal, speed_loaded}
## Tiers are ordered highest-first so we match the best applicable tier.
const VEHICLE_CAPACITY := {
	"cart_small": [
		{"min_equiv": 1.0, "load_normal": 80, "load_max": 160, "speed_normal": 60, "speed_loaded": 30},
		{"min_equiv": 0.5, "load_normal": 35, "load_max": 70, "speed_normal": 60, "speed_loaded": 30},
	],
	"cart_large": [
		{"min_equiv": 2.0, "load_normal": 120, "load_max": 240, "speed_normal": 60, "speed_loaded": 30},
		{"min_equiv": 1.0, "load_normal": 80, "load_max": 160, "speed_normal": 60, "speed_loaded": 30},
	],
	"wagon": [
		{"min_equiv": 4.0, "load_normal": 320, "load_max": 640, "speed_normal": 60, "speed_loaded": 30},
		{"min_equiv": 2.0, "load_normal": 160, "load_max": 320, "speed_normal": 60, "speed_loaded": 30},
	],
}

## Draft pulling power per species (1.0 = one heavy horse equivalent).
const DRAFT_EQUIVALENTS := {
	"horse_heavy": 1.0,
	"ox": 1.0,
	"camel": 1.0,
	"horse_medium": 0.5,
	"mule": 0.5,
	"donkey": 0.5,
}

## Maximum team equivalents per vehicle type.
const MAX_TEAM_EQUIV := {
	"cart_small": 1.0,
	"cart_large": 2.0,
	"wagon": 4.0,
}


# ---------------------------------------------------------------------------
# Team Calculation
# ---------------------------------------------------------------------------

## Returns the total draft equivalents for an array of TrainedCreatureData.
static func calculate_team_equivalents(creatures: Array) -> float:
	var total := 0.0
	for creature in creatures:
		var species: String = ""
		if creature is TrainedCreatureData:
			species = creature.species_id
		elif creature is Dictionary:
			species = str(creature.get("species_id", ""))
		total += DRAFT_EQUIVALENTS.get(species, 0.0)
	return total


## Returns the capacity dict for a vehicle given its team equivalents.
## Returns: {load_normal, load_max, speed_normal, speed_loaded} or empty dict
## if the team is insufficient (vehicle is immobile).
static func get_vehicle_capacity(item_key: String, team_equiv: float) -> Dictionary:
	var tiers: Array = VEHICLE_CAPACITY.get(item_key, [])
	for tier in tiers:
		if team_equiv >= tier["min_equiv"]:
			return {
				"load_normal": tier["load_normal"],
				"load_max": tier["load_max"],
				"speed_normal": tier["speed_normal"],
				"speed_loaded": tier["speed_loaded"],
			}
	return {}


## Returns true if the vehicle has enough draft power to move.
static func is_vehicle_mobile(item_key: String, team_equiv: float) -> bool:
	return not get_vehicle_capacity(item_key, team_equiv).is_empty()


# ---------------------------------------------------------------------------
# Hitch Validation
# ---------------------------------------------------------------------------

## Returns "" if the creature can be hitched to the vehicle, or an error message.
static func validate_hitch(
		vehicle: Dictionary,
		creature: TrainedCreatureData,
		all_vehicles: Array) -> String:
	if not creature.is_alive:
		return "Creature is not alive."

	# Must have draft saddle equipped.
	if creature.get_equipped_saddle_type() != "draft":
		return "Creature must have a draft saddle equipped to pull a vehicle."

	# Check creature is not already hitched to another vehicle.
	for v in all_vehicles:
		var vid: String = str(v.get("id", ""))
		if vid == str(vehicle.get("id", "")):
			continue
		var hitched_json: String = str(v.get("hitched_creatures", "[]"))
		var hitched = JSON.parse_string(hitched_json)
		if hitched is Array and creature.id in hitched:
			return "Creature is already hitched to another vehicle."

	# Check not already hitched to this vehicle.
	var this_hitched_json: String = str(vehicle.get("hitched_creatures", "[]"))
	var this_hitched = JSON.parse_string(this_hitched_json)
	if this_hitched is Array and creature.id in this_hitched:
		return "Creature is already hitched to this vehicle."

	# Check team size limit.
	var item_key: String = str(vehicle.get("item_key", ""))
	var max_equiv: float = MAX_TEAM_EQUIV.get(item_key, 2.0)
	var species_equiv: float = DRAFT_EQUIVALENTS.get(creature.species_id, 0.0)
	if species_equiv <= 0.0:
		return "This creature species cannot pull vehicles."

	# Calculate current team equivalents.
	var current_equiv := 0.0
	if this_hitched is Array:
		# We don't have full creature data here, just IDs.
		# The caller should pass creature data if precise checking is needed.
		# For now, count existing hitched entries by their known equivalents.
		current_equiv = float(this_hitched.size()) * 0.5  # Conservative estimate

	if current_equiv + species_equiv > max_equiv:
		return "Vehicle is at maximum draft team capacity."

	return ""


## Returns "" if unhitching is safe, or a warning message.
## Unhitching is always allowed, but may leave the vehicle immobile or overloaded.
static func validate_unhitch(
		vehicle: Dictionary,
		creature_id: String,
		current_load_units: int,
		remaining_team_equiv: float) -> String:
	var item_key: String = str(vehicle.get("item_key", ""))

	if not is_vehicle_mobile(item_key, remaining_team_equiv):
		return "Warning: unhitching will leave the vehicle immobile."

	var capacity := get_vehicle_capacity(item_key, remaining_team_equiv)
	if not capacity.is_empty():
		var max_load_units: int = int(capacity["load_max"]) * 1000
		if current_load_units > max_load_units:
			return "Warning: unhitching will leave the vehicle overloaded."

	return ""


# ---------------------------------------------------------------------------
# Load Calculation
# ---------------------------------------------------------------------------

## Calculates total load in a vehicle from an array of inventory item dicts/objects.
static func calculate_vehicle_load_units(items: Array) -> int:
	var total := 0
	for item in items:
		var enc := 0
		var qty := 1
		if item is InventoryItem:
			enc = item.encumbrance_units
			qty = item.quantity
		elif item is Dictionary:
			enc = int(item.get("encumbrance_units", 0))
			qty = int(item.get("quantity", 1))
		total += enc * qty
	return total


## Returns true if the vehicle's current load exceeds its max capacity.
static func is_overloaded(item_key: String, team_equiv: float, load_units: int) -> bool:
	var capacity := get_vehicle_capacity(item_key, team_equiv)
	if capacity.is_empty():
		return load_units > 0  # No capacity at all = overloaded if anything is inside
	return load_units > int(capacity["load_max"]) * 1000
