class_name TravelSpeedCalculator
extends RefCounted

## Calculates party travel speed in the wilderness, accounting for:
##   - Individual member encumbrance → movement tier (via EncumbranceCalculator)
##   - Party moves at slowest member's rate
##   - Terrain movement cost multiplier
##   - Mounted travel (horse or mule)
##   - Forced march (+50% distance)
##   - Running proficiency (+30' base, chainmail or lighter only)
##
## ACKS wilderness movement table (exploration feet/turn → miles/day):
##   30' → 6 mi, 60' → 12 mi, 90' → 18 mi, 120' → 24 mi, 150' → 30 mi,
##   180' → 36 mi, 210' → 42 mi, 240' → 48 mi
##
## Terrain multipliers (ACKS):
##   Clear:                  ×1
##   Desert, hills, woods:   ×2/3
##   Jungle, swamp, mountains: ×1/2
##   Road:                   ×3/2

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Exploration feet/turn → wilderness miles/day conversion factor.
## 120 feet/turn = 24 miles/day → ratio is 24/120 = 1/5.
const FEET_TO_MILES_PER_DAY := 0.2

## Terrain movement cost multipliers keyed by movement_cost_category().
const TERRAIN_MULTIPLIERS := {
	"clear": 1.0,
	"desert": 2.0 / 3.0,
	"hills": 2.0 / 3.0,
	"woods": 2.0 / 3.0,
	"jungle": 0.5,
	"swamp": 0.5,
	"mountains": 0.5,
	"ocean": 1.0,   # sea travel uses different rules; placeholder
	"lake": 1.0,    # same
}

## Forced march multiplier (12-hour day instead of 8).
const FORCED_MARCH_MULTIPLIER := 1.5

## Road travel multiplier.
const ROAD_MULTIPLIER := 1.5

## ACKS standard hex size in miles.
const MILES_PER_HEX := 6.0

## Normal travel day length in hours (forced march extends to 12).
const TRAVEL_HOURS_PER_DAY := 8


# ---------------------------------------------------------------------------
# Main API
# ---------------------------------------------------------------------------

## Calculates the full travel speed for a party in a given terrain.
##
## [param party] — PartyData with character_data populated.
## [param terrain_category] — result of HexTerrainData.movement_cost_category().
## [param on_road] — true if party is following a road or clear trail.
##
## Returns Dictionary:
##   base_exploration_speed: int  — slowest member's exploration speed (ft/turn)
##   terrain_multiplier: float    — from terrain category
##   miles_per_day: float         — final miles/day after all modifiers
##   is_forced_march: bool        — from party state
##   slowest_member_id: String    — character_id of the bottleneck
##   details: Array[Dictionary]   — per-member breakdown
static func calculate_party_speed(party: PartyData, terrain_category: String, on_road: bool = false) -> Dictionary:
	var details: Array = []
	var slowest_speed: int = 999
	var slowest_id: String = ""

	for cd: CharacterData in party.character_data:
		var member_speed: int = cd.get_effective_movement()
		details.append({
			"character_id": cd.id,
			"name": cd.name,
			"effective_movement": member_speed,
		})
		if member_speed < slowest_speed:
			slowest_speed = member_speed
			slowest_id = cd.id

	# If no members, use default human speed
	if party.character_data.is_empty():
		slowest_speed = 120
		slowest_id = ""

	# Consider trained creature speeds.
	for creature: TrainedCreatureData in party.creature_data:
		var spd: int = creature.get_effective_movement()
		if spd < slowest_speed:
			slowest_speed = spd
			slowest_id = creature.id

	# Vehicles cap party speed at 60'/turn (ACKS: carts/wagons all move 60'/30').
	if not party.vehicle_data.is_empty():
		if PartyData.VEHICLE_SPEED < slowest_speed:
			slowest_speed = PartyData.VEHICLE_SPEED
			slowest_id = "vehicle"

	# Party moves at slowest member's speed. If a character has a mount
	# equipped, their get_effective_movement() already reflects the mount's
	# speed via the modifier system.
	var base_speed: int = slowest_speed

	# Terrain multiplier
	var terrain_mult: float = TERRAIN_MULTIPLIERS.get(terrain_category, 1.0)

	# Road overrides terrain: ×3/2 of base, ignoring terrain penalty
	if on_road:
		terrain_mult = ROAD_MULTIPLIER

	# Base miles per day (8-hour travel day)
	var miles_per_day: float = base_speed * FEET_TO_MILES_PER_DAY * terrain_mult

	# Forced march: +50% distance
	if party.is_force_marching:
		miles_per_day *= FORCED_MARCH_MULTIPLIER

	# Banker's rounding to nearest mile
	miles_per_day = _bankers_round(miles_per_day)

	return {
		"base_exploration_speed": base_speed,
		"terrain_multiplier": terrain_mult,
		"miles_per_day": miles_per_day,
		"is_forced_march": party.is_force_marching,
		"on_road": on_road,
		"slowest_member_id": slowest_id,
		"details": details,
	}


## Convenience: returns just the miles-per-day value for quick checks.
static func get_miles_per_day(party: PartyData, terrain_category: String, on_road: bool = false) -> float:
	var result: Dictionary = calculate_party_speed(party, terrain_category, on_road)
	return result["miles_per_day"]


## Returns the number of game rounds to cross one 6-mile hex at the party's
## speed in the given terrain. Used by the event scheduler to set travel_leg
## fire times.
##
## Derivation: 8-hour travel day = 2880 rounds. At X miles/day the party
## covers X/6 hexes per day. So rounds_per_hex = 2880 / (miles_per_day / 6).
## Minimum 1 round (degenerate case protection).
static func hex_crossing_rounds(party: PartyData, terrain_category: String, on_road: bool = false) -> int:
	var mpd: float = get_miles_per_day(party, terrain_category, on_road)
	if mpd <= 0.0:
		return Timekeeping.ROUNDS_PER_HOUR * 8  # fallback: full travel day per hex
	var hexes_per_day: float = mpd / MILES_PER_HEX
	if hexes_per_day <= 0.0:
		return Timekeeping.ROUNDS_PER_HOUR * 8
	var travel_rounds_per_day: int = Timekeeping.ROUNDS_PER_HOUR * TRAVEL_HOURS_PER_DAY
	var rounds: float = float(travel_rounds_per_day) / hexes_per_day
	return maxi(1, int(_bankers_round(rounds)))


## Returns the terrain multiplier for a given movement_cost_category.
static func get_terrain_multiplier(terrain_category: String) -> float:
	return TERRAIN_MULTIPLIERS.get(terrain_category, 1.0)


# ---------------------------------------------------------------------------
# Getting Lost Check
# ---------------------------------------------------------------------------

## Wilderness navigation target numbers by terrain.
## Party rolls 1d20, must meet or exceed target to stay on course.
## Navigation proficiency grants +4 to the roll.
const NAVIGATION_TARGETS := {
	"clear": 4,
	"hills": 7,
	"mountains": 7,
	"woods": 7,
	"desert": 11,
	"jungle": 11,
	"swamp": 11,
	"ocean": 11,   # open sea
	"lake": 4,     # coastal/lake travel
}

## Rolls a getting-lost check for the party.
## Returns a result Dictionary matching the EventBus.getting_lost_checked signal shape.
##
## [param party] — PartyData with character_data populated.
## [param terrain_category] — result of HexTerrainData.movement_cost_category().
## [param roll_result] — the d20 roll value (caller obtains from DiceSystem).
## [param on_road] — if true, party cannot get lost (auto-succeed).
static func check_getting_lost(party: PartyData, terrain_category: String, roll_result: int, on_road: bool = false) -> Dictionary:
	var target: int = NAVIGATION_TARGETS.get(terrain_category, 4)
	var modifier: int = 0

	# Navigation proficiency grants +4
	if party.any_member_has_proficiency("navigation"):
		modifier = 4

	# Roads and clear trails prevent getting lost entirely
	var succeeded: bool
	if on_road:
		succeeded = true
	else:
		succeeded = (roll_result + modifier) >= target

	return {
		"party_id": party.id,
		"target": target,
		"roll": roll_result,
		"modifier": modifier,
		"succeeded": succeeded,
	}


# ---------------------------------------------------------------------------
# Forced March
# ---------------------------------------------------------------------------

## Checks whether a character can endure a forced march day.
## Without Endurance: 1 day allowed, then mandatory 24h rest.
## With Endurance: 1 + CON bonus days allowed without penalty.
##
## This method does NOT roll dice — it checks eligibility.
## The caller should update party.force_march_days_used after each forced march day.
##
## Returns Dictionary:
##   can_continue: bool    — true if the party can force march today
##   max_days: int         — maximum consecutive forced march days
##   days_used: int        — how many forced march days already used
##   must_rest_after: bool — true if this is the last allowed day
static func check_force_march_eligibility(party: PartyData) -> Dictionary:
	var max_days: int = party.max_force_march_days()
	var can_continue: bool = party.force_march_days_used < max_days
	return {
		"can_continue": can_continue,
		"max_days": max_days,
		"days_used": party.force_march_days_used,
		"must_rest_after": party.force_march_days_used + 1 >= max_days,
	}


# ---------------------------------------------------------------------------
# Rest requirement
# ---------------------------------------------------------------------------

## Returns true if the party must rest (6+ consecutive travel days without rest,
## unless Endurance proficiency is present).
## Characters who skip rest suffer cumulative -1 attack/damage per day.
static func needs_rest(party: PartyData) -> bool:
	return party.needs_rest()


## Returns the cumulative rest penalty for attack throws and damage rolls.
## 0 if days_since_rest < 6 or party has Endurance. Otherwise days_since_rest - 5.
static func rest_penalty(party: PartyData) -> int:
	if party.any_member_has_proficiency("endurance"):
		return 0
	if party.days_since_rest < 6:
		return 0
	return party.days_since_rest - 5


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

## Banker's rounding (round half to even) per project convention.
static func _bankers_round(value: float) -> float:
	var floor_val: float = floorf(value)
	var frac: float = value - floor_val
	if absf(frac - 0.5) < 0.0001:
		# Exactly half — round to even
		if int(floor_val) % 2 == 0:
			return floor_val
		else:
			return floor_val + 1.0
	return roundf(value)
