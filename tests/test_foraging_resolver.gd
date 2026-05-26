extends "res://tests/test_suite_base.gd"

## Unit tests for ForagingResolver (Wilderness closure Phase 3).
##
## SACRED tests against `acore_adventures_and_encounters.xml`
## §rations_and_foraging.foraging:
##   * Throw 18+ on 1d20 per character per day (project-designed per-char
##     elaboration of "per day of travel"; documented in gdd-hunting-foraging).
##   * Survival proficiency: +4 to throws, plus auto-self-feed.
##   * Each success: 1d6 person-feeds added to ration_units.
##
## PROJECT-DESIGNED water foraging tests:
##   * Auto-pass on river / lake / rainy hex → water_units topped up to party_size.
##   * Otherwise: 14+ on 1d20 per character, +4 with Survival, 1d6 per success.
##
## Weather modifier tests cover the gdd-weather-generation.md §7.3 mapping.


# ---------------------------------------------------------------------------
# Fake DiceSystem — programmable per roll_type
# ---------------------------------------------------------------------------

class _ScriptedDice:
	extends RefCounted
	## Map of roll_type → Array of values to return in order. Falls back to
	## `default_value` when no script for the type or the queue is exhausted.
	var scripts: Dictionary = {}
	var default_value: int = 1

	func roll_digital(sides: int, count: int = 1, modifier: int = 0,
			roll_type: String = "") -> RollResult:
		var r := RollResult.new()
		r.sides = sides
		r.count = count
		r.modifier = modifier
		var base: int = default_value
		if scripts.has(roll_type) and not scripts[roll_type].is_empty():
			base = int(scripts[roll_type].pop_front())
		var total := 0
		r.individual_results = []
		for _i in range(count):
			r.individual_results.append(base)
			total += base
		r.raw_total = total
		r.modified_total = total + modifier
		r.natural_one = (base == 1 and sides == 20 and count == 1)
		r.natural_max = (base == sides and count == 1)
		return r


func run_all_tests() -> void:
	test_food_no_successes_no_units_added()
	test_food_one_success_adds_1d6()
	test_food_all_successes_stack()
	test_food_survival_bonus_helps_member()
	test_food_survival_auto_self_feed()
	test_food_storm_blocks()
	test_food_rainy_minus_one_modifier()
	test_water_river_auto_pass()
	test_water_lake_auto_pass()
	test_water_rainy_atmosphere_auto_pass()
	test_water_dry_hex_per_character_roll()
	test_water_dry_with_survival_easier()
	test_party_size_one_food_water_isolated()
	if not has_failures():
		print("ForagingResolver: all tests passed.")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _make_member(idx: int, has_survival: bool = false) -> CharacterData:
	var cd := CharacterData.new()
	cd.id = "pc_%d" % idx
	cd.name = "PC %d" % idx
	cd.hp_max = 10
	cd.hp_current = 10
	if has_survival:
		cd.proficiencies = [{"proficiency_key": "survival", "rank": 1}]
	return cd


func _make_party(member_count: int, survival_indices: Array = []) -> PartyData:
	var pd := PartyData.new()
	pd.id = "test_phase3_forage_party"
	pd.character_data = []
	for i in range(member_count):
		pd.character_data.append(_make_member(i, i in survival_indices))
	return pd


func _terrain_clear() -> HexTerrainData:
	var t := HexTerrainData.new()
	t.elevation = HexTerrainData.ELEVATION_FLAT
	t.biome = HexTerrainData.BIOME_CLEAR
	t.water = HexTerrainData.WATER_NONE
	return t


func _terrain_with_river() -> HexTerrainData:
	var t := _terrain_clear()
	# Migration 130: rivers are first-class edge entities, not overlays.
	# Foraging only cares whether the hex touches a river; flip the cached
	# flag directly rather than persisting a real edge for this unit test.
	t.has_river_cached = true
	return t


func _terrain_lake() -> HexTerrainData:
	var t := _terrain_clear()
	t.water = HexTerrainData.WATER_LAKE
	return t


func _calm_weather() -> WeatherStateData:
	return WeatherStateData.make(
		WeatherStateData.TEMP_MILD, WeatherStateData.ATMO_CALM, "clear")


func _rainy_weather() -> WeatherStateData:
	return WeatherStateData.make(
		WeatherStateData.TEMP_MILD, WeatherStateData.ATMO_RAINY, "woods")


func _storm_weather() -> WeatherStateData:
	# Storm = precipitation_level 4. v1 doesn't generate level 4 yet, so we
	# build manually for the test.
	var w := WeatherStateData.make(
		WeatherStateData.TEMP_MILD, WeatherStateData.ATMO_RAINY, "woods")
	w.precipitation_level = 4
	return w


# ---------------------------------------------------------------------------
# Food forage tests
# ---------------------------------------------------------------------------

func test_food_no_successes_no_units_added() -> void:
	# Untrained chars rolling 17 each (1 below 18) — 0 successes.
	var party := _make_party(3)
	party.ration_units = 0
	var dice := _ScriptedDice.new()
	dice.scripts = {"forage_food": [17, 17, 17], "forage_water": [1, 1, 1]}
	dice.default_value = 1
	var t := _terrain_clear()
	var w := _calm_weather()
	var r := ForagingResolver.attempt_daily(party, t, w, dice)
	var food: Dictionary = r["food"]
	check(food.get("successes", -1) == 0, "0 successes")
	check(food.get("units_added", -1) == 0, "0 units_added")
	check(party.ration_units == 0, "ration_units unchanged")


func test_food_one_success_adds_1d6() -> void:
	# One char rolls 18 (success); others roll 17 (fail). Yield die forced to 4.
	var party := _make_party(3)
	party.ration_units = 0
	var dice := _ScriptedDice.new()
	dice.scripts = {
		"forage_food": [18, 17, 17],
		"forage_food_yield": [4],
		"forage_water": [1, 1, 1],
	}
	dice.default_value = 1
	var r := ForagingResolver.attempt_daily(party, _terrain_clear(), _calm_weather(), dice)
	var food: Dictionary = r["food"]
	check(food.get("successes", -1) == 1, "1 success")
	check(food.get("units_added", -1) == 4, "1d6=4 units_added")
	check(party.ration_units == 4, "ration_units += 4")


func test_food_all_successes_stack() -> void:
	# 4 untrained chars all roll 18+. Yield 1d6 per success: 3, 5, 2, 6 → 16 total.
	var party := _make_party(4)
	party.ration_units = 0
	var dice := _ScriptedDice.new()
	dice.scripts = {
		"forage_food": [18, 19, 20, 18],
		"forage_food_yield": [3, 5, 2, 6],
		"forage_water": [1, 1, 1, 1],
	}
	dice.default_value = 1
	var r := ForagingResolver.attempt_daily(party, _terrain_clear(), _calm_weather(), dice)
	var food: Dictionary = r["food"]
	check(food.get("successes", -1) == 4, "4/4 successes")
	check(food.get("units_added", -1) == 16,
		"stacked yield: 3+5+2+6 = 16; got %d" % food.get("units_added", -1))
	check(party.ration_units == 16, "ration_units += 16")


func test_food_survival_bonus_helps_member() -> void:
	# Char w/ Survival rolls 14 → +4 = 18 → success. Untrained char rolls 14 → fail.
	var party := _make_party(2, [0])  # idx 0 has Survival
	party.ration_units = 0
	var dice := _ScriptedDice.new()
	dice.scripts = {
		"forage_food": [14, 14],
		"forage_food_yield": [3],
		"forage_water": [1, 1],
	}
	dice.default_value = 1
	var r := ForagingResolver.attempt_daily(party, _terrain_clear(), _calm_weather(), dice)
	var food: Dictionary = r["food"]
	check(food.get("successes", -1) == 1, "Survival +4 turned a 14 into a success; untrained 14 fails")
	# Survival auto-self-feed adds +1 too. Total: 3 yield + 1 self = 4.
	check(food.get("units_added", -1) == 4,
		"3 from yield + 1 from auto-self-feed = 4; got %d" % food.get("units_added", -1))


func test_food_survival_auto_self_feed() -> void:
	# Survival char rolls a clear failure (1+4=5) — but auto-self-feed still
	# contributes +1 unit per the proficiency catalog flag.
	var party := _make_party(1, [0])
	party.ration_units = 0
	var dice := _ScriptedDice.new()
	dice.scripts = {"forage_food": [1], "forage_water": [1]}
	dice.default_value = 1
	var r := ForagingResolver.attempt_daily(party, _terrain_clear(), _calm_weather(), dice)
	var food: Dictionary = r["food"]
	check(food.get("successes", -1) == 0, "the throw failed")
	check(food.get("units_added", -1) == 1,
		"auto-self-feed still adds 1 even on failed throw; got %d" %
		food.get("units_added", -1))


func test_food_storm_blocks() -> void:
	# Storm (precip level 4) blocks foraging entirely — 0 rolls.
	var party := _make_party(3)
	var dice := _ScriptedDice.new()
	dice.scripts = {"forage_water": [1, 1, 1]}
	var r := ForagingResolver.attempt_daily(
		party, _terrain_clear(), _storm_weather(), dice)
	var food: Dictionary = r["food"]
	check(food.get("weather_blocked", false), "storm marks weather_blocked")
	check(food.get("rolls", -1) == 0, "no rolls attempted")
	check(food.get("units_added", -1) == 0, "no units")


func test_food_rainy_minus_one_modifier() -> void:
	# Rainy = precip level 2 → −1 modifier. A 19 (no Survival) becomes 18 → just success.
	# An 18 becomes 17 → fail.
	var party := _make_party(2)
	party.ration_units = 0
	var dice := _ScriptedDice.new()
	dice.scripts = {
		"forage_food": [19, 18],
		"forage_food_yield": [2],
		# Rainy auto-passes water → no water rolls.
	}
	dice.default_value = 1
	var r := ForagingResolver.attempt_daily(
		party, _terrain_clear(), _rainy_weather(), dice)
	var food: Dictionary = r["food"]
	check(food.get("successes", -1) == 1,
		"under rain (-1), 19 still passes 18; 18 fails. got %d successes" %
		food.get("successes", -1))


# ---------------------------------------------------------------------------
# Water forage tests
# ---------------------------------------------------------------------------

func test_water_river_auto_pass() -> void:
	var party := _make_party(4)
	party.water_units = 0
	var dice := _ScriptedDice.new()
	dice.scripts = {"forage_food": [1, 1, 1, 1]}
	dice.default_value = 1
	var r := ForagingResolver.attempt_daily(
		party, _terrain_with_river(), _calm_weather(), dice)
	var water: Dictionary = r["water"]
	check(water.get("auto_pass", false), "river hex → auto_pass")
	check(water.get("rolls", -1) == 0, "no rolls when auto_pass")
	check(party.water_units == 4,
		"water_units topped to party_size=4; got %d" % party.water_units)


func test_water_lake_auto_pass() -> void:
	var party := _make_party(3)
	party.water_units = 0
	var dice := _ScriptedDice.new()
	dice.default_value = 1
	dice.scripts = {"forage_food": [1, 1, 1]}
	var r := ForagingResolver.attempt_daily(
		party, _terrain_lake(), _calm_weather(), dice)
	check(r["water"].get("auto_pass", false), "lake hex → auto_pass")
	check(party.water_units == 3, "water_units topped to party_size=3")


func test_water_rainy_atmosphere_auto_pass() -> void:
	var party := _make_party(2)
	party.water_units = 0
	var dice := _ScriptedDice.new()
	dice.default_value = 1
	dice.scripts = {"forage_food": [1, 1]}
	var r := ForagingResolver.attempt_daily(
		party, _terrain_clear(), _rainy_weather(), dice)
	check(r["water"].get("auto_pass", false), "rainy atmosphere → auto_pass")
	check(party.water_units == 2, "water_units topped to party_size=2")


func test_water_dry_hex_per_character_roll() -> void:
	# Dry desert hex, calm weather. Each char rolls; target 14 untrained.
	# Char 0: 14 → success; char 1: 13 → fail.
	var party := _make_party(2)
	party.water_units = 0
	var dice := _ScriptedDice.new()
	dice.scripts = {
		"forage_food": [1, 1],
		"forage_water": [14, 13],
		"forage_water_yield": [3],
	}
	var t := _terrain_clear()
	t.biome = HexTerrainData.BIOME_DESERT
	var r := ForagingResolver.attempt_daily(party, t, _calm_weather(), dice)
	var water: Dictionary = r["water"]
	check(not water.get("auto_pass", true), "dry desert → no auto_pass")
	check(water.get("rolls", -1) == 2, "rolled per character")
	check(water.get("successes", -1) == 1, "1 success")
	check(water.get("units_added", -1) == 3, "+1d6=3 water units")


func test_water_dry_with_survival_easier() -> void:
	# Survival + 14 = 18, survival + 10 = 14 (just success).
	var party := _make_party(2, [0])
	party.water_units = 0
	var dice := _ScriptedDice.new()
	dice.scripts = {
		"forage_food": [1, 1],
		"forage_water": [10, 13],  # Survival char makes 10+4=14 success; untrained char fails
		"forage_water_yield": [2],
	}
	var t := _terrain_clear()
	t.biome = HexTerrainData.BIOME_DESERT
	var r := ForagingResolver.attempt_daily(party, t, _calm_weather(), dice)
	var water: Dictionary = r["water"]
	check(water.get("successes", -1) == 1, "Survival's +4 turned a 10 into a success")
	check(water.get("units_added", -1) == 2, "+1d6=2 water units")


# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

func test_party_size_one_food_water_isolated() -> void:
	# Sanity: a 1-character party still rolls food and water independently.
	var party := _make_party(1)
	party.ration_units = 0
	party.water_units = 0
	var dice := _ScriptedDice.new()
	dice.scripts = {
		"forage_food": [18],
		"forage_food_yield": [4],
		"forage_water": [14],
		"forage_water_yield": [3],
	}
	var t := _terrain_clear()
	t.biome = HexTerrainData.BIOME_DESERT  # no auto-pass
	var r := ForagingResolver.attempt_daily(party, t, _calm_weather(), dice)
	check(r["food"].get("successes", -1) == 1, "food success")
	check(r["water"].get("successes", -1) == 1, "water success")
	check(party.ration_units == 4, "ration_units = +4")
	check(party.water_units == 3, "water_units = +3")
