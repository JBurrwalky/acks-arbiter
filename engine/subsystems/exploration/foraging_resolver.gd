class_name ForagingResolver
extends RefCounted

## Daily wilderness foraging — food and water (Wilderness closure Phase 3).
##
## Pure logic — no DB writes, no signal emission. The day-tick handler calls
## `attempt_daily(party, terrain, weather, dice)`, applies the resulting
## ration_units / water_units deltas, and routes the toast.
##
## Cadence: fires on `wilderness_day_tick`, NOT per travel-leg. Skipped when
## the party is not in the wilderness state (settlement / dungeon / camp).
##
## Authority — food forage:
##   SACRED: `acore_adventures_and_encounters.xml` §rations_and_foraging.foraging
##     "Proficiency throw 18+ on 1d20 per day of travel.
##      Success: Food for 1d6 man-sized creatures."
##   SACRED: `acore_adventures_and_encounters.xml` §rations_and_foraging
##           .survival_proficiency_bonus
##     "Characters with Survival proficiency gain +4 on hunt and forage throws."
##   SACRED: `acore_proficiencies_rules_and_catalog.xml` Survival entry
##     "Automatically forage enough food for self while moving in a fairly
##      fertile area. If foraging for more than one person, make the normal
##      proficiency throw with a +4 bonus."
##
##   PROJECT-DESIGNED ELABORATION: The RAW reads "Proficiency throw 18+ on
##   1d20 per day of travel" without explicit per-character qualifier. We
##   interpret it as one throw per character per day (consistent with
##   ACKS proficiency-throw conventions, where proficiencies are individual).
##   Successes stack additively: 4 successes → 4d6 person-feeds. Documented
##   in `gdd-hunting-foraging.md`. A future Opus review can second-guess.
##
## Authority — water forage:
##   PROJECT-DESIGNED. ACKS RAW does not specify a water foraging procedure.
##   We mirror the food cadence: per-character throw on day-tick, successes
##   stack. Auto-pass conditions:
##     * `terrain.has_river()` — flowing water source.
##     * `terrain.water == "lake"` — standing water source.
##     * `weather.atmosphere == ATMO_RAINY` — rainwater collection.
##   Auto-pass tops up `water_units` to `party_size` (one day's draw for
##   everyone). On dry hexes the per-character throw target is 14+, matching
##   the hunting target — finding hidden water is harder than gathering
##   plants. Survival's +4 bonus applies. Container fill (waterskins,
##   barrels) is deferred to Phase 3.5 polish; v1 abstracts containers as
##   the `water_units` cache.
##
## Weather modifiers — food (gdd-weather-generation.md §7.3):
##   * Storm or blizzard (precipitation_level 4) — foraging impossible.
##   * Heavy rain/snow (level 3) — −2.
##   * Steady rain/snow (level 2) — −1.
##   * Frigid (temp band 0) — −4 (nothing grows).
##
## v1 only emits precipitation levels 0 and 2; the level-3/4 hooks remain
## live for Phase 2.5 weather expansion.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const FOOD_TARGET_UNTRAINED := 18
const HUNT_AND_FORAGE_TRAINED_BONUS := 4
## Project-designed: water search target on a dry hex without auto-pass.
const WATER_TARGET_UNTRAINED := 14

const SURVIVAL_PROFICIENCY := "survival"

const FOOD_DIE_SIDES := 6
const FOOD_DIE_COUNT_PER_SUCCESS := 1
## Auto-pass on water tops up water_units to party_size (one day's draw).
## Phase 3.5 polish may grant party_size × N when explicit container-fill
## interaction lands.
const WATER_AUTO_FILL_DAYS := 1


# ---------------------------------------------------------------------------
# Public API — daily roll for both food and water
# ---------------------------------------------------------------------------

## Roll the daily food + water forage for [param party] in [param terrain]
## under [param weather] (may be null when weather isn't loaded).
##
## Returns Dictionary:
##   food: { rolls, successes, units_added, weather_blocked, throws }
##   water: { rolls, successes, units_added, auto_pass, throws }
##   notes: String — short summary, suitable as toast body.
##
## Mutates [param party]: ration_units += food.units_added; water_units is
## set to max(water_units, party_size) on auto-pass, else += water.units_added.
##
## [param dice] — DiceSystem-like; tests pass a deterministic fake.
static func attempt_daily(
	party: PartyData,
	terrain: HexTerrainData,
	weather: WeatherStateData,
	dice,
) -> Dictionary:
	if party == null or party.character_data.is_empty():
		return _empty_result()

	var food: Dictionary = _attempt_food(party, weather, dice)
	var water: Dictionary = _attempt_water(party, terrain, weather, dice)

	# Apply units to the cache.
	party.ration_units += int(food.get("units_added", 0))
	if water.get("auto_pass", false):
		# Auto-pass tops up to one full day for the party (no over-fill).
		var fill: int = party.character_data.size() * WATER_AUTO_FILL_DAYS
		party.water_units = maxi(party.water_units, fill)
	else:
		party.water_units += int(water.get("units_added", 0))

	var notes: String = _summarize(food, water)
	return {
		"food": food,
		"water": water,
		"notes": notes,
	}


# ---------------------------------------------------------------------------
# Food forage
# ---------------------------------------------------------------------------

static func _attempt_food(
	party: PartyData,
	weather: WeatherStateData,
	dice,
) -> Dictionary:
	var weather_mod: int = _food_weather_modifier(weather)
	var weather_blocked: bool = _food_weather_blocked(weather)
	if weather_blocked:
		return {
			"rolls": 0, "successes": 0, "units_added": 0,
			"weather_blocked": true, "throws": [],
		}

	var rolls: int = 0
	var successes: int = 0
	var units_added: int = 0
	var throws: Array = []

	for cd: CharacterData in party.character_data:
		var has_survival: bool = cd.has_proficiency(SURVIVAL_PROFICIENCY)
		var bonus: int = HUNT_AND_FORAGE_TRAINED_BONUS if has_survival else 0
		var roll: RollResult = dice.roll_digital(20, 1, 0, "forage_food")
		var total: int = roll.modified_total + bonus + weather_mod
		var succeeded: bool = total >= FOOD_TARGET_UNTRAINED
		rolls += 1
		if succeeded:
			successes += 1
			# Each success: +1d6 man-feeds. RAW phrasing.
			var feed_roll: RollResult = dice.roll_digital(
				FOOD_DIE_SIDES, FOOD_DIE_COUNT_PER_SUCCESS, 0, "forage_food_yield")
			units_added += feed_roll.modified_total
		throws.append({
			"character_id": cd.id,
			"roll": roll.modified_total,
			"survival_bonus": bonus,
			"weather_modifier": weather_mod,
			"total": total,
			"target": FOOD_TARGET_UNTRAINED,
			"succeeded": succeeded,
		})

		# Survival auto-self-feed flag per the proficiency catalog: "Automatically
		# forage enough food for self while moving in a fairly fertile area." We
		# add a free 1 unit for each Survival member regardless of throw outcome.
		# This is on top of any 1d6 they rolled for the group.
		if has_survival:
			units_added += 1

	return {
		"rolls": rolls,
		"successes": successes,
		"units_added": units_added,
		"weather_blocked": false,
		"throws": throws,
	}


# ---------------------------------------------------------------------------
# Water forage
# ---------------------------------------------------------------------------

static func _attempt_water(
	party: PartyData,
	terrain: HexTerrainData,
	weather: WeatherStateData,
	dice,
) -> Dictionary:
	if _is_auto_pass_water(terrain, weather):
		return {
			"rolls": 0, "successes": 0, "units_added": 0,
			"auto_pass": true, "throws": [],
		}

	var rolls: int = 0
	var successes: int = 0
	var units_added: int = 0
	var throws: Array = []

	for cd: CharacterData in party.character_data:
		var has_survival: bool = cd.has_proficiency(SURVIVAL_PROFICIENCY)
		var bonus: int = HUNT_AND_FORAGE_TRAINED_BONUS if has_survival else 0
		var roll: RollResult = dice.roll_digital(20, 1, 0, "forage_water")
		var total: int = roll.modified_total + bonus
		var succeeded: bool = total >= WATER_TARGET_UNTRAINED
		rolls += 1
		if succeeded:
			successes += 1
			var feed_roll: RollResult = dice.roll_digital(
				FOOD_DIE_SIDES, FOOD_DIE_COUNT_PER_SUCCESS, 0, "forage_water_yield")
			units_added += feed_roll.modified_total
		throws.append({
			"character_id": cd.id,
			"roll": roll.modified_total,
			"survival_bonus": bonus,
			"total": total,
			"target": WATER_TARGET_UNTRAINED,
			"succeeded": succeeded,
		})

	return {
		"rolls": rolls,
		"successes": successes,
		"units_added": units_added,
		"auto_pass": false,
		"throws": throws,
	}


# ---------------------------------------------------------------------------
# Auto-pass evaluation
# ---------------------------------------------------------------------------

## Water foraging auto-passes when there is a free-flowing or rain water
## source available. Project-designed conditions; document changes in
## gdd-hunting-foraging.md.
static func _is_auto_pass_water(
	terrain: HexTerrainData,
	weather: WeatherStateData,
) -> bool:
	if terrain != null:
		if terrain.has_river():
			return true
		if terrain.water == HexTerrainData.WATER_LAKE:
			return true
	if weather != null and weather.atmosphere == WeatherStateData.ATMO_RAINY:
		return true
	return false


# ---------------------------------------------------------------------------
# Weather modifiers (food)
# ---------------------------------------------------------------------------

## Returns the throw modifier from weather (negative penalties only). Per
## gdd-weather-generation.md §7.3, with the caveat that v1 only emits
## precipitation level 0 (calm) or 2 (steady). The level-1/3/4 mappings
## stay live for Phase 2.5.
static func _food_weather_modifier(weather: WeatherStateData) -> int:
	if weather == null:
		return 0
	# Frigid override — nothing grows in the cold.
	if weather.temperature_band == WeatherStateData.TEMP_FRIGID:
		return -4
	match weather.precipitation_level:
		1: return 0     # drizzle/flurries — no penalty per GDD §7.3
		2: return -1    # steady rain/snow
		3: return -2    # heavy
		4: return 0     # storm — handled by `_food_weather_blocked` instead
		_: return 0


## True when weather makes foraging impossible (storm / blizzard).
static func _food_weather_blocked(weather: WeatherStateData) -> bool:
	if weather == null:
		return false
	return weather.precipitation_level >= 4


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _summarize(food: Dictionary, water: Dictionary) -> String:
	var parts: Array[String] = []
	if food.get("weather_blocked", false):
		parts.append("Foraging impossible (storm)")
	else:
		parts.append("Food: %d/%d successes (+%d units)" % [
			food.get("successes", 0), food.get("rolls", 0),
			food.get("units_added", 0)])
	if water.get("auto_pass", false):
		parts.append("Water: replenished (river/lake/rain)")
	else:
		parts.append("Water: %d/%d successes (+%d units)" % [
			water.get("successes", 0), water.get("rolls", 0),
			water.get("units_added", 0)])
	return "; ".join(parts)


static func _empty_result() -> Dictionary:
	return {
		"food": {"rolls": 0, "successes": 0, "units_added": 0,
				 "weather_blocked": false, "throws": []},
		"water": {"rolls": 0, "successes": 0, "units_added": 0,
				  "auto_pass": false, "throws": []},
		"notes": "no characters present",
	}
