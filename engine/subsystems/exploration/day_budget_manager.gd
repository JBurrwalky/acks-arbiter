class_name DayBudgetManager
extends RefCounted

## Manages the 8-slot day budget for wilderness exploration.
##
## Each slot represents ~1 hour of primary activity. Players assign activities
## to slots during the Day Declaration phase. The budget constrains what the
## party can accomplish in a single day.
##
## Slot types:
##   MARCH   — Travel. Each slot = party's hourly movement rate.
##   EXPLORE — Detailed hex investigation. Reveals features, finds POIs.
##   REST    — Partial recovery. No encounter check.
##   FORAGE  — Food procurement via proficiency check.
##   HUNT    — Game hunting via proficiency check.
##   GUARD   — Increased vigilance. Reduces surprise chance.
##   CRAFT   — Crafting or repair. Requires proficiency.
##   FREE    — Unstructured time. General activities.

enum SlotType {
	MARCH,
	EXPLORE,
	REST,
	FORAGE,
	HUNT,
	GUARD,
	CRAFT,
	FREE,
}

const SLOT_COUNT := 8

const SLOT_NAMES := {
	SlotType.MARCH: "March",
	SlotType.EXPLORE: "Explore",
	SlotType.REST: "Rest",
	SlotType.FORAGE: "Forage",
	SlotType.HUNT: "Hunt",
	SlotType.GUARD: "Guard",
	SlotType.CRAFT: "Craft",
	SlotType.FREE: "Free",
}

const SLOT_COLORS := {
	SlotType.MARCH: Color(0.50, 0.35, 0.20, 1.0),    # Brown
	SlotType.EXPLORE: Color(0.20, 0.50, 0.25, 1.0),   # Green
	SlotType.REST: Color(0.25, 0.40, 0.60, 1.0),      # Blue
	SlotType.FORAGE: Color(0.45, 0.50, 0.20, 1.0),    # Olive
	SlotType.HUNT: Color(0.60, 0.25, 0.20, 1.0),      # Red
	SlotType.GUARD: Color(0.40, 0.40, 0.40, 1.0),     # Gray
	SlotType.CRAFT: Color(0.45, 0.25, 0.55, 1.0),     # Purple
	SlotType.FREE: Color(0.60, 0.58, 0.52, 1.0),      # White-ish
}

## Minimum REST slots required for a valid day plan.
const MIN_REST_SLOTS := 2

## Minimum REST slots after forced march (need extra recovery).
const MIN_REST_AFTER_FORCED_MARCH := 3

var slots: Array[int] = []  # Array of SlotType values


func _init() -> void:
	# Default day plan: 4 march, 2 explore, 2 rest.
	slots = [
		SlotType.MARCH, SlotType.MARCH, SlotType.MARCH, SlotType.MARCH,
		SlotType.EXPLORE, SlotType.EXPLORE,
		SlotType.REST, SlotType.REST,
	]


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func set_slot(index: int, slot_type: int) -> void:
	if index < 0 or index >= SLOT_COUNT:
		return
	slots[index] = slot_type


func get_slot(index: int) -> int:
	if index < 0 or index >= SLOT_COUNT:
		return SlotType.FREE
	return slots[index]


func get_slot_name(slot_type: int) -> String:
	return SLOT_NAMES.get(slot_type, "Unknown")


func get_slot_color(slot_type: int) -> Color:
	return SLOT_COLORS.get(slot_type, Color.WHITE)


## Validate the current plan. Returns "" on success, error message on failure.
func validate() -> String:
	var rest_count := count_slots(SlotType.REST)
	if rest_count < MIN_REST_SLOTS:
		return "Day plan requires at least %d rest slots (found %d)." % [MIN_REST_SLOTS, rest_count]
	return ""


func count_slots(slot_type: int) -> int:
	var count := 0
	for s in slots:
		if s == slot_type:
			count += 1
	return count


## Estimate travel distance for the day based on march slots and party speed.
## party_miles_per_day: the party's base daily movement rate (e.g., 24 miles).
## Returns estimated miles traveled.
func estimate_travel_distance(party_miles_per_day: float) -> float:
	# ACKS assumes ~8 hours of marching per day for full movement.
	# Each march slot = 1 hour = 1/8 of daily rate.
	var march_count := count_slots(SlotType.MARCH)
	return party_miles_per_day * (float(march_count) / 8.0)


## Count how many encounter checks will occur today.
## Each MARCH and EXPLORE slot triggers one check.
func estimate_encounter_checks() -> int:
	return count_slots(SlotType.MARCH) + count_slots(SlotType.EXPLORE)


# ---------------------------------------------------------------------------
# Serialization
# ---------------------------------------------------------------------------

func to_array() -> Array:
	return slots.duplicate()


func from_array(data: Array) -> void:
	slots.clear()
	for i in range(mini(data.size(), SLOT_COUNT)):
		slots.append(int(data[i]))
	while slots.size() < SLOT_COUNT:
		slots.append(SlotType.FREE)
