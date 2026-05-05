extends "res://tests/test_suite_base.gd"

## Integration tests for TravelSpeedCalculator with WeatherStateData
## (Wilderness closure Phase 2). Verifies the full multiplier chain
## (terrain × encumbrance × forced-march × weather × mud) per
## gdd-weather-generation.md §7.1 and confirms that callers passing null
## weather get unchanged legacy behaviour.


func run_all_tests() -> void:
	test_no_weather_matches_legacy_speed()
	test_calm_weather_matches_no_weather()
	test_rainy_halves_miles_per_day()
	test_cold_plus_snowy_quarters()
	test_rainy_clear_with_mud_quarters()
	test_hex_crossing_rounds_doubles_under_rainy()
	test_weather_then_forced_march_compose()
	test_storm_floor_never_zero()
	if not has_failures():
		print("TravelWithWeather: all tests passed.")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

const TEST_PARTY_ID := "test_phase2_tspeed_party"


## Builds a single-character party at 120'/turn (no encumbrance hit, no
## mounts, no vehicles). 120'/turn = 24 mi/day in clear terrain.
func _make_party() -> PartyData:
	var pd := PartyData.new()
	pd.id = TEST_PARTY_ID
	pd.name = "Test Travel Party"
	pd.is_force_marching = false

	var cd := CharacterData.new()
	cd.id = "test_phase2_tspeed_pc"
	cd.name = "Speedy McTester"
	cd.base_movement = 120
	pd.character_data = [cd]
	pd.creature_data = []
	pd.vehicle_data = []
	return pd


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_no_weather_matches_legacy_speed() -> void:
	# Null weather should leave miles_per_day unchanged from the pre-Phase-2
	# behavior. Clear terrain at 120'/turn = 24 mi/day.
	var party := _make_party()
	var result_no_weather: Dictionary = TravelSpeedCalculator.calculate_party_speed(
		party, "clear", false, null)
	var result_legacy: Dictionary = TravelSpeedCalculator.calculate_party_speed(
		party, "clear", false)
	check(result_no_weather["miles_per_day"] == result_legacy["miles_per_day"],
		"null weather matches legacy 3-arg call")
	check(absf(result_no_weather.get("weather_multiplier", -1.0) - 1.0) < 0.001,
		"null weather → multiplier 1.0, got %.3f" %
		result_no_weather.get("weather_multiplier", -1.0))


func test_calm_weather_matches_no_weather() -> void:
	# Calm + Mild weather is a no-op multiplier.
	var party := _make_party()
	var calm := WeatherStateData.make(WeatherStateData.TEMP_MILD, WeatherStateData.ATMO_CALM, "clear")
	var with_calm: Dictionary = TravelSpeedCalculator.calculate_party_speed(
		party, "clear", false, calm)
	var no_weather: Dictionary = TravelSpeedCalculator.calculate_party_speed(
		party, "clear", false, null)
	check(with_calm["miles_per_day"] == no_weather["miles_per_day"],
		"Calm + Mild = no speed change, got %s vs %s" %
		[with_calm["miles_per_day"], no_weather["miles_per_day"]])


func test_rainy_halves_miles_per_day() -> void:
	# Mild + Rainy on woods (no mud) = ×0.5 weather. 24 mi/day → 12 mi/day.
	var party := _make_party()
	var rainy := WeatherStateData.make(WeatherStateData.TEMP_MILD, WeatherStateData.ATMO_RAINY, "woods")
	var with_rainy: Dictionary = TravelSpeedCalculator.calculate_party_speed(
		party, "clear", false, rainy)
	var no_weather: Dictionary = TravelSpeedCalculator.calculate_party_speed(
		party, "clear", false, null)
	check(with_rainy["miles_per_day"] == no_weather["miles_per_day"] * 0.5
			or absf(with_rainy["miles_per_day"] - no_weather["miles_per_day"] * 0.5) <= 1.0,
		"Rainy halves miles_per_day: %s -> %s" %
		[no_weather["miles_per_day"], with_rainy["miles_per_day"]])


func test_cold_plus_snowy_quarters() -> void:
	# Cold + Snowy on mountains: ×0.5 × ×0.5 = ×0.25.
	var party := _make_party()
	var w := WeatherStateData.make(WeatherStateData.TEMP_COLD, WeatherStateData.ATMO_SNOWY, "mountains")
	# Use clear terrain so we isolate the weather contribution.
	var with_w: Dictionary = TravelSpeedCalculator.calculate_party_speed(
		party, "clear", false, w)
	var no_w: Dictionary = TravelSpeedCalculator.calculate_party_speed(
		party, "clear", false, null)
	# Banker's rounding to nearest mile means 24 × 0.25 = 6 exactly.
	check(absf(with_w["miles_per_day"] - no_w["miles_per_day"] * 0.25) <= 1.0,
		"Cold + Snowy quarters speed: %s -> %s" %
		[no_w["miles_per_day"], with_w["miles_per_day"]])


func test_rainy_clear_with_mud_quarters() -> void:
	# Rainy + Mild on clear biome → produces_mud → Rainy ×0.5 + Mud ×0.5 = ×0.25.
	var party := _make_party()
	var rainy_clear := WeatherStateData.make(
		WeatherStateData.TEMP_MILD, WeatherStateData.ATMO_RAINY, "clear")
	check(rainy_clear.produces_mud, "fixture: rainy_clear has mud")
	var with_w: Dictionary = TravelSpeedCalculator.calculate_party_speed(
		party, "clear", false, rainy_clear)
	var no_w: Dictionary = TravelSpeedCalculator.calculate_party_speed(
		party, "clear", false, null)
	check(absf(with_w["miles_per_day"] - no_w["miles_per_day"] * 0.25) <= 1.0,
		"Rainy + Mud on clear: %s -> %s (expected ×0.25)" %
		[no_w["miles_per_day"], with_w["miles_per_day"]])


func test_hex_crossing_rounds_doubles_under_rainy() -> void:
	# Rainy ×0.5 means it takes ~2× the rounds to cross a hex.
	var party := _make_party()
	var rainy := WeatherStateData.make(WeatherStateData.TEMP_MILD, WeatherStateData.ATMO_RAINY, "woods")
	var rounds_calm: int = TravelSpeedCalculator.hex_crossing_rounds(
		party, "clear", false, null)
	var rounds_rainy: int = TravelSpeedCalculator.hex_crossing_rounds(
		party, "clear", false, rainy)
	# Allow some slack for banker's rounding fence-posts.
	check(rounds_rainy >= rounds_calm * 2 - 2,
		"Rainy roughly doubles rounds_per_hex: %d → %d" % [rounds_calm, rounds_rainy])
	check(rounds_rainy <= rounds_calm * 2 + 2,
		"Rainy doesn't more than double: %d → %d" % [rounds_calm, rounds_rainy])


func test_weather_then_forced_march_compose() -> void:
	# Forced march ×1.5, Rainy ×0.5: 24 × 1.5 × 0.5 = 18 mi/day.
	var party := _make_party()
	party.is_force_marching = true
	var rainy := WeatherStateData.make(WeatherStateData.TEMP_MILD, WeatherStateData.ATMO_RAINY, "woods")
	var result: Dictionary = TravelSpeedCalculator.calculate_party_speed(
		party, "clear", false, rainy)
	# 24 * 1.5 = 36, then * 0.5 = 18.
	check(absf(result["miles_per_day"] - 18.0) <= 1.0,
		"forced march + Rainy = 18 mi/day, got %s" % result["miles_per_day"])


func test_storm_floor_never_zero() -> void:
	# Even with all multipliers stacked the floor should keep miles_per_day > 0.
	# v1 cannot legally produce <0.1 weather multiplier; this is a defensive
	# regression guard.
	var party := _make_party()
	var w := WeatherStateData.make(WeatherStateData.TEMP_COLD, WeatherStateData.ATMO_SNOWY, "mountains")
	w.produces_mud = true
	var result: Dictionary = TravelSpeedCalculator.calculate_party_speed(
		party, "swamp", false, w)
	check(result["miles_per_day"] > 0.0,
		"floor never zeroes miles_per_day, got %s" % result["miles_per_day"])
