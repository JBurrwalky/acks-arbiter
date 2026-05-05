extends "res://tests/test_suite_base.gd"

## Unit tests for WeatherGenerator (Wilderness closure Phase 2).
##
## Covers:
##   * Determinism — identical inputs always yield identical output
##   * DaW table parsing — "Mild; 75% Rainy" splits into temp + atmo with
##     percentage gating, "Hot; Calm" reads as unconditional, etc.
##   * Biome → terrain row mapping (mountains override, hills+clear → woods_hills,
##     desert → barren_desert, etc.)
##   * Snow conversion — Cold + Rainy normalizes to Snowy + snow precip
##   * Mud — clear/scrub + Rainy + Mild produces mud; water hexes never do


# ---------------------------------------------------------------------------
# Test entry
# ---------------------------------------------------------------------------

func run_all_tests() -> void:
	test_determinism_same_inputs_same_output()
	test_determinism_differs_by_hex_coord()
	test_determinism_differs_by_julian_day()
	test_determinism_differs_by_campaign()
	test_terrain_row_mapping_mountains_override()
	test_terrain_row_mapping_hills_plus_clear()
	test_terrain_row_mapping_desert()
	test_terrain_row_mapping_jungle()
	test_terrain_row_mapping_water_treated_as_clear()
	test_winter_mountains_always_cold_snowy()
	test_summer_jungle_always_hot_rainy()
	test_summer_scrub_always_hot_calm()
	test_cold_atmosphere_normalises_to_snowy()
	test_clear_grass_rainy_produces_mud()
	test_swamp_winter_cold_rainy()
	if not has_failures():
		print("WeatherGenerator: all tests passed.")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _terrain(elevation: String, biome: String, water: String = "") -> HexTerrainData:
	var t := HexTerrainData.new()
	t.elevation = elevation
	t.biome = biome
	t.water = water
	t.civilization = HexTerrainData.TERRITORY_WILDERNESS
	return t


# Calendar-season day_of_year landmarks per Timekeeping._SEASON_STARTS:
# spring=day 1, summer=day 92, autumn=day 183, winter=day 274.
const SPRING_DAY := 30
const SUMMER_DAY := 100
const AUTUMN_DAY := 200
const WINTER_DAY := 300


# ---------------------------------------------------------------------------
# Determinism
# ---------------------------------------------------------------------------

func test_determinism_same_inputs_same_output() -> void:
	var t := _terrain("flat", "clear")
	var w1 := WeatherGenerator.generate("camp_a", 5, 7, t, SUMMER_DAY, 1, "north")
	var w2 := WeatherGenerator.generate("camp_a", 5, 7, t, SUMMER_DAY, 1, "north")
	check(w1.temperature_band == w2.temperature_band,
		"determinism: temperature_band stable across calls")
	check(w1.atmosphere == w2.atmosphere,
		"determinism: atmosphere stable across calls")
	check(w1.visibility_multiplier == w2.visibility_multiplier,
		"determinism: visibility_multiplier stable")


func test_determinism_differs_by_hex_coord() -> void:
	# Run a small grid and confirm at least two adjacent hexes diverge.
	# DaW summer/clear_grass is "Hot; 25% Rainy" so there's stochastic diversity.
	var t := _terrain("flat", "clear")
	var seen_combos := {}
	for q in range(0, 12):
		for r in range(0, 6):
			var w := WeatherGenerator.generate("camp_a", q, r, t, SUMMER_DAY, 1, "north")
			seen_combos["%s|%s" % [w.temperature_band, w.atmosphere]] = true
	check(seen_combos.size() >= 2,
		"hex coords must produce variety across a grid; saw %d combos" %
		seen_combos.size())


func test_determinism_differs_by_julian_day() -> void:
	# Same hex, two seasons apart — must produce different weather most of the
	# time (winter mountains is "Cold; Snowy" vs summer mountains is
	# "Mild; 25% Windy"). Test the deterministic case (always-different cell).
	var t := _terrain("mountains", "clear")
	var summer := WeatherGenerator.generate("camp_a", 1, 1, t, SUMMER_DAY)
	var winter := WeatherGenerator.generate("camp_a", 1, 1, t, WINTER_DAY)
	check(summer.short_label() != winter.short_label(),
		"summer vs winter mountain weather differs: '%s' vs '%s'" %
		[summer.short_label(), winter.short_label()])


func test_determinism_differs_by_campaign() -> void:
	# Same hex, day, year — different campaign_id should typically diverge.
	# Spring/clear_grass = "Mild; 75% Rainy" → P(divergence) per pair ≈ 0.375.
	# Across 50 pairs, expected ≈ 19; we accept ≥8 to keep the test
	# robust against any reasonable hash distribution while still catching
	# a regression where campaign_id is silently dropped from the seed.
	var t := _terrain("flat", "clear")
	var divergences := 0
	for i in range(50):
		var w_a := WeatherGenerator.generate("camp_alpha_%d" % i, 0, 0, t, SPRING_DAY)
		var w_b := WeatherGenerator.generate("camp_beta_%d" % i, 0, 0, t, SPRING_DAY)
		if w_a.atmosphere != w_b.atmosphere or w_a.temperature_band != w_b.temperature_band:
			divergences += 1
	check(divergences >= 8,
		"campaign_id seeds must affect output; saw %d/50 divergences" % divergences)


# ---------------------------------------------------------------------------
# Terrain row mapping
# ---------------------------------------------------------------------------

func test_terrain_row_mapping_mountains_override() -> void:
	# Mountains elevation overrides the biome. Clear-biome mountains use the
	# DaW "mountains" row, which in winter is "Cold; Snowy" — fully
	# unconditional, so the test is deterministic regardless of seed.
	var mountains_clear := _terrain("mountains", "clear")
	var w := WeatherGenerator.generate("c", 0, 0, mountains_clear, WINTER_DAY)
	check(w.temperature_band == WeatherStateData.TEMP_COLD,
		"mountains/winter temp is Cold, got %d" % w.temperature_band)
	check(w.atmosphere == WeatherStateData.ATMO_SNOWY,
		"mountains/winter atmosphere is Snowy, got '%s'" % w.atmosphere)


func test_terrain_row_mapping_hills_plus_clear() -> void:
	# Hills + clear should map to the woods_hills DaW row (DaW pairs them).
	# In winter, woods_hills is "Cold; 25% Snowy" — temp is unconditional Cold.
	var hills_clear := _terrain("hills", "clear")
	var w := WeatherGenerator.generate("c", 1, 1, hills_clear, WINTER_DAY)
	check(w.temperature_band == WeatherStateData.TEMP_COLD,
		"hills+clear/winter is Cold")


func test_terrain_row_mapping_desert() -> void:
	# Desert biome → barren_desert DaW row. Summer barren_desert is
	# "Hot; 5% Rainy" — temp is unconditional Hot.
	var desert := _terrain("flat", "desert")
	var w := WeatherGenerator.generate("c", 2, 2, desert, SUMMER_DAY)
	check(w.temperature_band == WeatherStateData.TEMP_HOT,
		"desert/summer is Hot, got %d" % w.temperature_band)


func test_terrain_row_mapping_jungle() -> void:
	# Jungle biome → jungle DaW row. Summer jungle is "Hot; Rainy" — fully
	# unconditional; tests both temperature and atmosphere.
	var jungle := _terrain("flat", "jungle")
	var w := WeatherGenerator.generate("c", 3, 3, jungle, SUMMER_DAY)
	check(w.temperature_band == WeatherStateData.TEMP_HOT, "jungle/summer Hot")
	check(w.atmosphere == WeatherStateData.ATMO_RAINY, "jungle/summer Rainy")


func test_terrain_row_mapping_water_treated_as_clear() -> void:
	# Ocean hex inherits a clear-grass row for atmosphere derivation but mud
	# is suppressed — assertion on produces_mud regardless of weather rolled.
	var ocean := _terrain("flat", "clear", HexTerrainData.WATER_OCEAN)
	# Run a batch and confirm none ever produce mud, even when atmosphere
	# resolves to Rainy and biome is "clear".
	var any_mud := false
	for i in range(40):
		var w := WeatherGenerator.generate("camp_o_%d" % i, 0, 0, ocean, SPRING_DAY)
		if w.produces_mud:
			any_mud = true
			break
	check(not any_mud, "water hexes must never produce mud")


# ---------------------------------------------------------------------------
# Sacred unconditional cells (no percentage gating — always the listed value)
# ---------------------------------------------------------------------------

func test_winter_mountains_always_cold_snowy() -> void:
	var t := _terrain("mountains", "clear")
	for i in range(20):
		var w := WeatherGenerator.generate("camp_w%d" % i, i, 0, t, WINTER_DAY)
		check(w.temperature_band == WeatherStateData.TEMP_COLD,
			"winter/mountains always Cold (sample %d)" % i)
		check(w.atmosphere == WeatherStateData.ATMO_SNOWY,
			"winter/mountains always Snowy (sample %d)" % i)


func test_summer_jungle_always_hot_rainy() -> void:
	var t := _terrain("flat", "jungle")
	for i in range(20):
		var w := WeatherGenerator.generate("camp_j%d" % i, i, 0, t, SUMMER_DAY)
		check(w.temperature_band == WeatherStateData.TEMP_HOT,
			"summer/jungle always Hot (sample %d)" % i)
		check(w.atmosphere == WeatherStateData.ATMO_RAINY,
			"summer/jungle always Rainy (sample %d)" % i)


func test_summer_scrub_always_hot_calm() -> void:
	# scrub is not currently a HexTerrainData biome, but the WeatherGenerator
	# table includes it. Test by passing a hex that maps to scrub — actually
	# no biome currently maps to scrub in v1; skip via a synthetic terrain
	# row override is not exposed. Confirm the mapping for clear/scrub-class
	# behaviour via clear+flat instead, summer "Hot; 25% Rainy". Sanity:
	# temperature is always Hot (unconditional).
	var t := _terrain("flat", "clear")
	for i in range(20):
		var w := WeatherGenerator.generate("camp_s%d" % i, i, 0, t, SUMMER_DAY)
		check(w.temperature_band == WeatherStateData.TEMP_HOT,
			"summer/clear_grass always Hot")


# ---------------------------------------------------------------------------
# Snow normalisation
# ---------------------------------------------------------------------------

func test_cold_atmosphere_normalises_to_snowy() -> void:
	# Winter swamp is "Cold; Rainy" per DaW. The normalisation rule converts
	# Cold + Rainy → Snowy in WeatherStateData._derive_channels.
	var t := _terrain("flat", "swamp")
	var w := WeatherGenerator.generate("c", 0, 0, t, WINTER_DAY)
	check(w.temperature_band == WeatherStateData.TEMP_COLD,
		"swamp/winter is Cold")
	check(w.atmosphere == WeatherStateData.ATMO_SNOWY,
		"Cold + Rainy normalises to Snowy, got '%s'" % w.atmosphere)
	check(w.precipitation_type == WeatherStateData.PRECIP_SNOW,
		"snow precip type, got '%s'" % w.precipitation_type)


func test_swamp_winter_cold_rainy() -> void:
	# Same as above but exercise the daw_travel_multiplier composition:
	# Cold (×0.5) + Snowy (×0.5) = ×0.25. No mud (swamp is not clear/scrub).
	var t := _terrain("flat", "swamp")
	var w := WeatherGenerator.generate("c", 0, 0, t, WINTER_DAY)
	check(absf(w.travel_multiplier() - 0.25) < 0.001,
		"Cold + Snowy yields ×0.25 multiplier, got %.3f" % w.travel_multiplier())
	check(not w.produces_mud, "swamp does not mud up")


# ---------------------------------------------------------------------------
# Mud
# ---------------------------------------------------------------------------

func test_clear_grass_rainy_produces_mud() -> void:
	# Spring clear_grass is "Mild; 75% Rainy" per DaW. Run enough seeds to
	# guarantee at least one Rainy outcome, then confirm mud forms.
	var t := _terrain("flat", "clear")
	var saw_mud := false
	for i in range(40):
		var w := WeatherGenerator.generate("camp_m%d" % i, 0, 0, t, SPRING_DAY)
		if w.atmosphere == WeatherStateData.ATMO_RAINY and w.produces_mud:
			saw_mud = true
			break
	check(saw_mud, "Rainy + clear must yield produces_mud=true at least once")
