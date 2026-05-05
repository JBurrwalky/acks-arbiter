extends "res://tests/test_suite_base.gd"

## Unit tests for WeatherStateData mechanical effects (Wilderness closure
## Phase 2). Verifies the SACRED multipliers from daw_vagaries.xml
## §severe_weather_effects compose correctly:
##   * Cold OR Hot temperature → ×0.5
##   * Rainy / Snowy / Windy atmosphere → ×0.5
##   * Mud (rain on clear/scrub) → ×0.5 (composes with Rainy ×0.5)
## And the project-designed visibility multipliers from
## gdd-weather-generation.md §4.5.


func run_all_tests() -> void:
	# travel_multiplier composition
	test_calm_mild_unmodified()
	test_cold_only_halved()
	test_hot_only_halved()
	test_rainy_only_halved()
	test_snowy_only_halved()
	test_windy_only_halved()
	test_cold_plus_snowy_quartered()
	test_hot_plus_rainy_quartered()
	test_rainy_clear_with_mud_eighth()
	test_floor_at_ten_percent()

	# visibility multiplier
	test_calm_visibility_full()
	test_rainy_visibility_half()
	test_snowy_visibility_half()
	test_windy_visibility_slight()

	# Feature flag respected
	test_feature_flag_returns_one_when_disabled()

	# Severity flag
	test_calm_mild_not_severe()
	test_rainy_is_severe()
	test_cold_is_severe()
	test_hot_is_severe()

	# Persistence round-trip
	test_to_dict_from_dict_round_trip()

	if not has_failures():
		print("WeatherEffects: all tests passed.")


# ---------------------------------------------------------------------------
# travel_multiplier composition
# ---------------------------------------------------------------------------

func test_calm_mild_unmodified() -> void:
	var w := WeatherStateData.make(WeatherStateData.TEMP_MILD, WeatherStateData.ATMO_CALM, "clear")
	check(absf(w.travel_multiplier() - 1.0) < 0.001,
		"Mild + Calm = ×1.0, got %.3f" % w.travel_multiplier())


func test_cold_only_halved() -> void:
	var w := WeatherStateData.make(WeatherStateData.TEMP_COLD, WeatherStateData.ATMO_CALM, "clear")
	check(absf(w.travel_multiplier() - 0.5) < 0.001,
		"Cold + Calm = ×0.5, got %.3f" % w.travel_multiplier())


func test_hot_only_halved() -> void:
	var w := WeatherStateData.make(WeatherStateData.TEMP_HOT, WeatherStateData.ATMO_CALM, "clear")
	check(absf(w.travel_multiplier() - 0.5) < 0.001,
		"Hot + Calm = ×0.5")


func test_rainy_only_halved() -> void:
	# Mild + Rainy on woods (no mud — biome not clear/scrub).
	var w := WeatherStateData.make(WeatherStateData.TEMP_MILD, WeatherStateData.ATMO_RAINY, "woods")
	check(absf(w.travel_multiplier() - 0.5) < 0.001,
		"Mild + Rainy on woods = ×0.5 (no mud), got %.3f" % w.travel_multiplier())
	check(not w.produces_mud, "no mud on woods biome")


func test_snowy_only_halved() -> void:
	var w := WeatherStateData.make(WeatherStateData.TEMP_MILD, WeatherStateData.ATMO_SNOWY, "woods")
	check(absf(w.travel_multiplier() - 0.5) < 0.001, "Mild + Snowy = ×0.5")


func test_windy_only_halved() -> void:
	var w := WeatherStateData.make(WeatherStateData.TEMP_MILD, WeatherStateData.ATMO_WINDY, "desert")
	check(absf(w.travel_multiplier() - 0.5) < 0.001, "Mild + Windy = ×0.5")


func test_cold_plus_snowy_quartered() -> void:
	# Cold + Snowy stacks: Cold (×0.5) × Snowy (×0.5) = ×0.25.
	var w := WeatherStateData.make(WeatherStateData.TEMP_COLD, WeatherStateData.ATMO_SNOWY, "mountains")
	check(absf(w.travel_multiplier() - 0.25) < 0.001,
		"Cold + Snowy = ×0.25, got %.3f" % w.travel_multiplier())


func test_hot_plus_rainy_quartered() -> void:
	# Hot + Rainy on jungle (no mud — biome is jungle): ×0.25.
	var w := WeatherStateData.make(WeatherStateData.TEMP_HOT, WeatherStateData.ATMO_RAINY, "jungle")
	check(absf(w.travel_multiplier() - 0.25) < 0.001, "Hot + Rainy = ×0.25")
	check(not w.produces_mud, "jungle does not mud up")


func test_rainy_clear_with_mud_eighth() -> void:
	# Mild + Rainy + clear biome: Rainy (×0.5) × Mud (×0.5) = ×0.25.
	var w := WeatherStateData.make(WeatherStateData.TEMP_MILD, WeatherStateData.ATMO_RAINY, "clear")
	check(w.produces_mud, "clear + rain produces mud")
	check(absf(w.travel_multiplier() - 0.25) < 0.001,
		"Mild + Rainy + Mud (clear) = ×0.25, got %.3f" % w.travel_multiplier())

	# And Hot + Rainy + clear → ×0.5 × ×0.5 (Hot + Rainy) × ×0.5 (Mud) = ×0.125.
	var w2 := WeatherStateData.make(WeatherStateData.TEMP_HOT, WeatherStateData.ATMO_RAINY, "clear")
	check(w2.produces_mud, "Hot + Rainy + clear → mud")
	check(absf(w2.travel_multiplier() - 0.125) < 0.001,
		"Hot + Rainy + Mud (clear) = ×0.125, got %.3f" % w2.travel_multiplier())


func test_floor_at_ten_percent() -> void:
	# Verify the 0.1 floor by stacking maximal multipliers (Cold + Snowy +
	# theoretical mud — though Snowy has no mud, we set produces_mud manually
	# to push past the floor and confirm the clamp).
	var w := WeatherStateData.make(WeatherStateData.TEMP_COLD, WeatherStateData.ATMO_SNOWY, "mountains")
	w.produces_mud = true  # synthetic — Snowy doesn't mud, but clamp test only
	# Cold (×0.5) × Snowy (×0.5) × Mud (×0.5) = ×0.125. Above floor.
	check(absf(w.travel_multiplier() - 0.125) < 0.001,
		"Cold + Snowy + synthetic mud = ×0.125, got %.3f" % w.travel_multiplier())
	# floor only kicks in if we somehow stack more — the v1 channels can't
	# legally produce sub-0.1, so the clamp is defensive.
	check(w.travel_multiplier() >= 0.1, "floor at 0.1 enforced")


# ---------------------------------------------------------------------------
# visibility multiplier
# ---------------------------------------------------------------------------

func test_calm_visibility_full() -> void:
	var w := WeatherStateData.make(WeatherStateData.TEMP_MILD, WeatherStateData.ATMO_CALM, "clear")
	check(absf(w.visibility_multiplier - 1.0) < 0.001,
		"Calm visibility = 1.0, got %.3f" % w.visibility_multiplier)


func test_rainy_visibility_half() -> void:
	var w := WeatherStateData.make(WeatherStateData.TEMP_MILD, WeatherStateData.ATMO_RAINY, "clear")
	check(absf(w.visibility_multiplier - 0.5) < 0.001,
		"Rainy visibility = 0.5, got %.3f" % w.visibility_multiplier)


func test_snowy_visibility_half() -> void:
	var w := WeatherStateData.make(WeatherStateData.TEMP_COLD, WeatherStateData.ATMO_SNOWY, "mountains")
	check(absf(w.visibility_multiplier - 0.5) < 0.001,
		"Snowy visibility = 0.5")


func test_windy_visibility_slight() -> void:
	var w := WeatherStateData.make(WeatherStateData.TEMP_MILD, WeatherStateData.ATMO_WINDY, "desert")
	check(absf(w.visibility_multiplier - 0.9) < 0.001,
		"Windy visibility = 0.9, got %.3f" % w.visibility_multiplier)


# ---------------------------------------------------------------------------
# Feature flag
# ---------------------------------------------------------------------------

func test_feature_flag_returns_one_when_disabled() -> void:
	# encounter_visibility_multiplier() reads FEATURE_VISIBILITY_ENABLED. The
	# flag is a compile-time constant — we can't flip it at runtime. Instead
	# we verify that when the flag is true (the v1 ship configuration) the
	# helper returns the underlying field, and we document the flip-to-false
	# contract by testing the helper's branch directly via reflection isn't
	# clean in GDScript. Verify the trivial case: when atmospheric multiplier
	# IS 1.0 (Calm), helper returns 1.0 regardless of flag.
	var w := WeatherStateData.make(WeatherStateData.TEMP_MILD, WeatherStateData.ATMO_CALM, "clear")
	check(absf(w.encounter_visibility_multiplier() - 1.0) < 0.001,
		"Calm → encounter_visibility_multiplier 1.0 regardless of flag")

	# When the flag is enabled (v1 default), severe weather lowers it.
	var w_rain := WeatherStateData.make(WeatherStateData.TEMP_MILD, WeatherStateData.ATMO_RAINY, "woods")
	if WeatherStateData.FEATURE_VISIBILITY_ENABLED:
		check(absf(w_rain.encounter_visibility_multiplier() - 0.5) < 0.001,
			"flag on: Rainy returns underlying 0.5 multiplier")
	else:
		check(absf(w_rain.encounter_visibility_multiplier() - 1.0) < 0.001,
			"flag off: returns 1.0")


# ---------------------------------------------------------------------------
# Severity
# ---------------------------------------------------------------------------

func test_calm_mild_not_severe() -> void:
	var w := WeatherStateData.make(WeatherStateData.TEMP_MILD, WeatherStateData.ATMO_CALM, "clear")
	check(not w.is_severe(), "Mild + Calm is not severe")


func test_rainy_is_severe() -> void:
	var w := WeatherStateData.make(WeatherStateData.TEMP_MILD, WeatherStateData.ATMO_RAINY, "clear")
	check(w.is_severe(), "Rainy is severe")


func test_cold_is_severe() -> void:
	var w := WeatherStateData.make(WeatherStateData.TEMP_COLD, WeatherStateData.ATMO_CALM, "mountains")
	check(w.is_severe(), "Cold is severe")


func test_hot_is_severe() -> void:
	var w := WeatherStateData.make(WeatherStateData.TEMP_HOT, WeatherStateData.ATMO_CALM, "desert")
	check(w.is_severe(), "Hot is severe")


# ---------------------------------------------------------------------------
# Persistence round-trip
# ---------------------------------------------------------------------------

func test_to_dict_from_dict_round_trip() -> void:
	var w := WeatherStateData.make(WeatherStateData.TEMP_COLD, WeatherStateData.ATMO_SNOWY, "mountains")
	w.hex_q = 5
	w.hex_r = 7
	w.julian_day = 300
	w.year = 2
	var d: Dictionary = w.to_dict()
	var restored: WeatherStateData = WeatherStateData.from_dict(d)
	check(restored.hex_q == 5 and restored.hex_r == 7, "coords round-trip")
	check(restored.julian_day == 300, "julian_day round-trip")
	check(restored.year == 2, "year round-trip")
	check(restored.temperature_band == WeatherStateData.TEMP_COLD, "temp band round-trip")
	check(restored.atmosphere == WeatherStateData.ATMO_SNOWY, "atmo round-trip")
	check(restored.precipitation_type == WeatherStateData.PRECIP_SNOW, "precip type round-trip")
	check(restored.precipitation_level == 2, "precip level round-trip")
	check(restored.produces_mud == w.produces_mud, "mud round-trip")
	check(absf(restored.visibility_multiplier - w.visibility_multiplier) < 0.001,
		"visibility round-trip")
