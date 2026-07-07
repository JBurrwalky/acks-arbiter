class_name ClimateGenerator
extends RefCounted

## Shared Layer-2 climate CLASSIFICATION (gdd-setting-generation.md §5). The
## hex-native climate generation (the latitude/lapse temperature + noise-precip
## + rain-shadow + coastal-moisture run() pass) was RETIRED 2026-06-25 —
## continuous-geography (GeoClimateGenerator) is the only climate producer. What
## survives are the pure classifiers the field-first engine + materializer reuse:
## the simplified Köppen cascade, biome + default-subtype assignment
## (gdd-terrain-system.md §7.1), swamp placement, the fixed per-terrain land_value
## table (history-sim §7.5.1), and the river-adjacency set — plus the temperature
## + Köppen-threshold constants GeoClimateGenerator samples. (Class name kept to
## avoid churn; it is now a classifier util, not a generator.)
##
## All thresholds are tunable constants (§5.3 "exact thresholds are tunable").

# Temperature model (°C): T = sea-level latitude curve − lapse over elevation.
# The latitude curve is QUADRATIC, not linear: real annual-mean temperature is
# nearly flat through the tropics and steepens toward the poles. A linear
# 0.6 °C/° curve put lat 20 (still tropical) at 18 °C and ran every climate band
# ~2 zones too cold (a "Tropical" map produced temperate forest, a "Temperate"
# map produced taiga). T(lat) = TEMP_AT_EQUATOR − TEMP_LAT_QUADRATIC·lat².
# Calibrated so the latitude presets land on their namesake biomes:
# lat 20 → ~24 °C (A group), lat 45 → ~13 °C (C group), lat 67 → ~−3 °C (D/E).
const TEMP_AT_EQUATOR := 27.0
const TEMP_LAT_QUADRATIC := 0.0068
# A low-frequency regional temperature anomaly (°C, ±) so the pure-temperature
# biome boundaries (the A/C/D/E Köppen group splits) don't fall on dead-straight
# horizontal isotherm lines across large flat lowlands — and so band edges read
# as natural transition zones rather than a hard latitude cut.
const TEMP_NOISE_AMPLITUDE_C := 2.0
# Elevation lapse bites only ABOVE the flat ceiling: flat land is lowland and
# follows the latitude curve directly; hills/mountains get progressively colder.
# (Mapping the whole sea-level..1 band to 0..3500 m over-cooled flat lowlands.)
const MAX_ELEVATION_METERS := 3500.0
const LAPSE_C_PER_1000M := 6.5

# Köppen thresholds (°C / normalized precipitation 0-1 / seasonality 0-1).
const COLD_THRESHOLD_C := -5.0     # below → E group (ET/EF)
const POLAR_DRY_THRESHOLD := 0.2   # E group: below → EF, else ET
const HOT_THRESHOLD_C := 22.0      # BWh/BSh vs BWk/BSk

# Temperature-dependent aridity (real Köppen B: the dry threshold rises with mean
# temperature — hot regions need far more rain to escape desert, so the great deserts
# sit in the hot subtropics/tropics and cold zones stay non-arid). Replaces the flat
# ARID/SEMIARID cutoffs (2026-06-25). `precip` is the normalized [0,1] field value;
# arid_t = clamp(ARID_BASE + ARID_PER_DEG·(temp − ARID_REF_TEMP_C), ARID_MIN, ARID_MAX),
# steppe band = [arid_t, arid_t + STEPPE_BAND).
const ARID_REF_TEMP_C := 10.0
const ARID_BASE := 0.15
const ARID_PER_DEG := 0.011
const ARID_MIN := 0.03
const ARID_MAX := 0.40
const STEPPE_BAND := 0.15
const TROPICAL_THRESHOLD_C := 24.0 # above → A group
const TEMPERATE_THRESHOLD_C := 8.0 # above → C group, else D group
const WET_THRESHOLD := 0.65        # A group: above → Af rainforest
const MONSOON_SEASONALITY := 0.6   # A group: seasonal regime → Am
const SUMMER_DRY_SEASONALITY := 0.55  # C group: summer-dry → Csa/Csb
# D group (continental) summer/winter severity bands, split on the annual-mean
# temperature (the field carries no monthly temps to do real warmest/coldest-month
# Köppen). CONTINENTAL_MILD_C stays the woods/taiga edge — Dfa/Dfb map to woods,
# Dfc/Dfd to taiga in _assign_biome — so emitting all four codes refines the Köppen
# label without moving any biome boundary.
const CONTINENTAL_WARM_C := 4.0    # D group: above → Dfa (hot summer), else Dfb (warm summer)
const CONTINENTAL_MILD_C := 2.0    # D group: woods/taiga edge (Dfa/Dfb above, Dfc/Dfd below)
const CONTINENTAL_COLD_C := -2.0   # D group: above → Dfc (subarctic), else Dfd (very cold winter)

# Deep interior (terrain-system §7.1: forest_dense "in deep interior").
const DEEP_INTERIOR_OCEAN_DISTANCE := 7

# Swamp placement (§5.4) — seeded per-hex rolls.
const SWAMP_CHANCE := 0.12
const SWAMP_CHANCE_TROPICAL := 0.20

const _OFF := [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0),
]


## Hexes touched by any river edge (owner side + the neighbor across it).
static func _river_adjacent_set(river_edges: Array) -> Dictionary:
	var touched := {}
	for row in river_edges:
		var owner := Vector2i(int(row["hex_q"]), int(row["hex_r"]))
		touched[owner] = true
		touched[owner + _OFF[int(row["edge"])]] = true
	return touched


# ---------------------------------------------------------------------------
# Köppen classification (§5.3 cascade, simplified major groups)
# ---------------------------------------------------------------------------

## Temperature-dependent Köppen B cutoff: warmer → higher dry threshold → arid.
static func _arid_threshold(temp: float) -> float:
	return clampf(ARID_BASE + ARID_PER_DEG * (temp - ARID_REF_TEMP_C), ARID_MIN, ARID_MAX)


static func _classify_koppen(temp: float, precip: float, seasonality: float) -> String:
	if temp < COLD_THRESHOLD_C:
		return "EF" if precip < POLAR_DRY_THRESHOLD else "ET"
	var arid_t := _arid_threshold(temp)
	if precip < arid_t:
		return "BWh" if temp > HOT_THRESHOLD_C else "BWk"
	if precip < arid_t + STEPPE_BAND:
		return "BSh" if temp > HOT_THRESHOLD_C else "BSk"
	if temp > TROPICAL_THRESHOLD_C:
		if precip > WET_THRESHOLD:
			return "Af"
		if seasonality > MONSOON_SEASONALITY:
			return "Am"
		return "Aw"
	if temp > TEMPERATE_THRESHOLD_C:
		if seasonality > SUMMER_DRY_SEASONALITY:
			return "Csa" if temp > 15.0 else "Csb"
		return "Cfa" if temp > 15.0 else "Cfb"
	# D group: four summer/winter severity bands. CONTINENTAL_MILD_C remains the
	# woods/taiga boundary, so biome output is unchanged (Dfa/Dfb → woods, Dfc/Dfd
	# → taiga); the finer codes light up the previously-dead Dfb/Dfd biome arms.
	if temp > CONTINENTAL_WARM_C:
		return "Dfa"
	if temp > CONTINENTAL_MILD_C:
		return "Dfb"
	if temp > CONTINENTAL_COLD_C:
		return "Dfc"
	return "Dfd"


## Biome + default subtype per gdd-terrain-system.md §7.1, plus its §7.2
## deterministic variation rules (montane jungle→woods; driest steppe→desert).
static func _assign_biome(hex: Dictionary, koppen: String, ocean_dist: int) -> void:
	var biome := "clear"
	var subtype := ""
	match koppen:
		"Af", "Am":
			biome = "jungle"
		"Aw":
			biome = "clear"
			subtype = "clear_savanna"
		"BWh", "BWk":
			biome = "desert"
		"BSh", "BSk":
			biome = "clear"
			subtype = "clear_grassland"
			# (The temperature-dependent BW cutoff in _classify_koppen now draws the
			# desert/steppe line; the old flat-threshold fringe rule is retired.)
		"Csa", "Csb":
			biome = "clear"
			subtype = "clear_grassland"
		"Cfa", "Cfb":
			biome = "woods"
			if ocean_dist >= DEEP_INTERIOR_OCEAN_DISTANCE:
				subtype = "forest_dense"
		"Dfa", "Dfb":
			biome = "woods"
			if ocean_dist >= DEEP_INTERIOR_OCEAN_DISTANCE:
				subtype = "forest_dense"
		"Dfc", "Dfd":
			biome = "woods"
			subtype = "forest_taiga"
		"ET":
			biome = "clear"
			subtype = "clear_tundra"
		"EF":
			biome = "desert"
			if hex["elevation"] == "mountains":
				subtype = "mountains_glacial"
	# §7.2 montane forest: jungle at mountain elevation becomes woods. Defensive:
	# with the current elevation lapse a mountain hex is always cooled below the
	# 24 °C tropical threshold, so the Köppen cascade already classifies tropical
	# peaks as montane woods directly and this guard normally does not fire.
	if biome == "jungle" and hex["elevation"] == "mountains":
		biome = "woods"
		subtype = ""
	hex["biome"] = biome
	hex["biome_subtype"] = subtype


# ---------------------------------------------------------------------------
# Swamp placement (§5.4)
# ---------------------------------------------------------------------------

static func _apply_swamp_pass(campaign_seed: int, grid: Dictionary, width: int,
		height: int, river_hexes: Dictionary) -> void:
	for row in range(height):
		for col in range(width):
			var key := WorldGrid.offset_to_axial(col, row)
			var hex: Dictionary = grid[key]
			if hex["water"] != "" or hex["elevation"] != "flat":
				continue
			if not river_hexes.has(key):
				continue
			var chance := 0.0
			match hex["biome"]:
				"woods", "clear":
					chance = SWAMP_CHANCE
				"jungle":
					chance = SWAMP_CHANCE_TROPICAL
			if chance <= 0.0:
				continue
			# Per-hex stream: deterministic regardless of iteration order.
			var rng := WorldGenRng.stream(campaign_seed, "swamp", 0, "%d,%d" % [key.x, key.y])
			if rng.randf() < chance:
				hex["biome"] = "swamp"
				hex["biome_subtype"] = ""


# ---------------------------------------------------------------------------
# Land value (history-sim §7.5.1: fixed per-terrain table, set at map-gen,
# within the RAW 3-9 range — plains/river-valley 6, hills 5, forest 4,
# mountain/desert/tundra 3; +1 if river-adjacent, capped at 9)
# ---------------------------------------------------------------------------

static func _assign_land_values(grid: Dictionary, width: int, height: int,
		river_hexes: Dictionary) -> void:
	for row in range(height):
		for col in range(width):
			var key := WorldGrid.offset_to_axial(col, row)
			var hex: Dictionary = grid[key]
			if hex["water"] != "":
				hex["land_value"] = 0
				continue
			var value: int
			if hex["biome"] == "desert" or hex["biome"] == "swamp" \
					or hex["biome_subtype"] == "clear_tundra":
				value = 3
			elif hex["elevation"] == "mountains":
				value = 3
			elif hex["biome"] == "woods" or hex["biome"] == "jungle":
				value = 4
			elif hex["elevation"] == "hills":
				value = 5
			else:
				value = 6
			if river_hexes.has(key):
				value = mini(value + 1, 9)
			hex["land_value"] = value
