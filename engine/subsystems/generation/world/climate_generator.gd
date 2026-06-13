class_name ClimateGenerator
extends RefCounted

## Layer 2 — climate (gdd-setting-generation.md §5): latitude/elevation
## temperature, precipitation noise with rain shadow + coastal moisture,
## simplified Köppen classification, biome + default-subtype assignment per
## gdd-terrain-system.md §7.1, swamp placement, and the fixed per-terrain
## land_value table (history-sim §7.5.1 — set at map-gen).
##
## Reads/writes the orchestrator ctx.hex_grid built by HeightmapGenerator.
## All thresholds are tunable constants (§5.3 "exact thresholds are tunable").

# Temperature model (°C): T = sea-level latitude curve − lapse over elevation.
const TEMP_AT_EQUATOR := 30.0
const TEMP_LAPSE_PER_DEGREE_LAT := 0.6
# Land elevation (sea_level..1) maps to 0..MAX_ELEVATION_METERS.
const MAX_ELEVATION_METERS := 3500.0
const LAPSE_C_PER_1000M := 6.5

# Köppen thresholds (°C / normalized precipitation 0-1 / seasonality 0-1).
const COLD_THRESHOLD_C := -5.0     # below → E group (ET/EF)
const POLAR_DRY_THRESHOLD := 0.2   # E group: below → EF, else ET
const ARID_THRESHOLD := 0.18       # below → BW desert
const SEMIARID_THRESHOLD := 0.33   # below → BS steppe
const HOT_THRESHOLD_C := 22.0      # BWh/BSh vs BWk/BSk
const TROPICAL_THRESHOLD_C := 24.0 # above → A group
const TEMPERATE_THRESHOLD_C := 8.0 # above → C group, else D group
const WET_THRESHOLD := 0.65        # A group: above → Af rainforest
const MONSOON_SEASONALITY := 0.6   # A group: seasonal regime → Am
const SUMMER_DRY_SEASONALITY := 0.55  # C group: summer-dry → Csa/Csb
const CONTINENTAL_MILD_C := 2.0    # D group: above → Dfa/Dfb, else Dfc

# Rain shadow (§5.2): prevailing wind west→east; mountains shade up to
# RAIN_SHADOW_RANGE hexes downwind, strongest adjacent.
const RAIN_SHADOW_RANGE := 4
const RAIN_SHADOW_MAX_REDUCTION := 0.45

# Coastal moisture (§5.2): hexes within 3 of ocean get +20%.
const COASTAL_MOISTURE_RANGE := 3
const COASTAL_MOISTURE_BONUS := 1.2

# Deep interior (terrain-system §7.1: forest_dense "in deep interior").
const DEEP_INTERIOR_OCEAN_DISTANCE := 7

# Swamp placement (§5.4) — seeded per-hex rolls.
const SWAMP_CHANCE := 0.12
const SWAMP_CHANCE_TROPICAL := 0.20

const _OFF := [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0),
]


static func run(ctx: Dictionary) -> bool:
	var params: SettingParameters = ctx["params"]
	var campaign_seed: int = ctx["campaign_seed"]
	var grid: Dictionary = ctx["hex_grid"]
	var width: int = ctx["width"]
	var height: int = ctx["height"]
	var river_edges: Array = ctx["river_edges"]

	var precip_noise := FastNoiseLite.new()
	precip_noise.seed = WorldGenRng.derive_seed(campaign_seed, "precipitation")
	precip_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	precip_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	precip_noise.fractal_octaves = 4
	precip_noise.frequency = 0.004

	# Seasonality channel: broad regional belts deciding monsoon (Am) and
	# Mediterranean summer-dry (Csa/Csb) regimes — a deterministic stand-in
	# for the seasonal simulation Layer 2 doesn't run.
	var season_noise := FastNoiseLite.new()
	season_noise.seed = WorldGenRng.derive_seed(campaign_seed, "seasonality")
	season_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	season_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	season_noise.fractal_octaves = 2
	season_noise.frequency = 0.0012

	var ocean_distance := _ocean_distance_field(grid, width, height)
	var river_hexes := _river_adjacent_set(river_edges)
	var lat_south := params.latitude_south()
	var lat_span := params.latitude_north() - lat_south

	for r in range(height):
		for q in range(width):
			var key := Vector2i(q, r)
			var hex: Dictionary = grid[key]
			# North edge of the map is r = 0 (edge 0 = N points to r-1), so
			# latitude DEcreases as r grows.
			var lat: float = lat_south + lat_span * (float(height - 1 - r) / maxf(height - 1, 1))
			hex["effective_latitude"] = lat
			var temp := TEMP_AT_EQUATOR - TEMP_LAPSE_PER_DEGREE_LAT * lat
			if hex["water"] == "":
				var meters: float = (float(hex["elevation_raw"]) - params.sea_level) \
						/ maxf(1.0 - params.sea_level, 0.000001) * MAX_ELEVATION_METERS
				temp -= LAPSE_C_PER_1000M * maxf(meters, 0.0) / 1000.0
			hex["temperature"] = temp

			var pos := HeightmapGenerator._hex_center(q, r)
			var precip := (precip_noise.get_noise_2d(pos.x, pos.y) + 1.0) * 0.5
			precip *= 1.0 - _rain_shadow(key, grid)
			if int(ocean_distance.get(key, 9999)) <= COASTAL_MOISTURE_RANGE:
				precip *= COASTAL_MOISTURE_BONUS
			precip = clampf(precip, 0.0, 1.0)
			hex["precipitation"] = precip

			if hex["water"] != "":
				hex["koppen"] = ""
				hex["land_value"] = 0
				continue

			var seasonality := (season_noise.get_noise_2d(pos.x, pos.y) + 1.0) * 0.5
			var koppen := _classify_koppen(temp, precip, seasonality)
			hex["koppen"] = koppen
			_assign_biome(hex, koppen, int(ocean_distance.get(key, 9999)))

	_apply_swamp_pass(campaign_seed, grid, width, height, river_hexes)
	_assign_land_values(grid, width, height, river_hexes)
	return true


# ---------------------------------------------------------------------------
# Precipitation modifiers
# ---------------------------------------------------------------------------

## Fraction of precipitation removed by upwind mountains. Prevailing wind is
## west→east (§5.2 default): upwind = the -q axial direction.
static func _rain_shadow(key: Vector2i, grid: Dictionary) -> float:
	for k in range(1, RAIN_SHADOW_RANGE + 1):
		var upwind := Vector2i(key.x - k, key.y)
		if not grid.has(upwind):
			break
		var hex: Dictionary = grid[upwind]
		if hex["water"] == "" and hex["elevation"] == "mountains":
			# Decays with distance: full reduction adjacent, fading outward.
			return RAIN_SHADOW_MAX_REDUCTION * (1.0 - float(k - 1) / float(RAIN_SHADOW_RANGE))
	return 0.0


## BFS distance (in hexes) to the nearest ocean hex, capped where it stops
## mattering (deep-interior threshold + 1).
static func _ocean_distance_field(grid: Dictionary, width: int, height: int) -> Dictionary:
	var dist := {}
	var frontier: Array[Vector2i] = []
	for r in range(height):
		for q in range(width):
			var key := Vector2i(q, r)
			if grid[key]["water"] == "ocean":
				dist[key] = 0
				frontier.append(key)
	var d := 0
	var cap := DEEP_INTERIOR_OCEAN_DISTANCE + 1
	while not frontier.is_empty() and d < cap:
		d += 1
		var next: Array[Vector2i] = []
		for cell in frontier:
			for off in _OFF:
				var n: Vector2i = cell + off
				if grid.has(n) and not dist.has(n):
					dist[n] = d
					next.append(n)
		frontier = next
	return dist


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

static func _classify_koppen(temp: float, precip: float, seasonality: float) -> String:
	if temp < COLD_THRESHOLD_C:
		return "EF" if precip < POLAR_DRY_THRESHOLD else "ET"
	if precip < ARID_THRESHOLD:
		return "BWh" if temp > HOT_THRESHOLD_C else "BWk"
	if precip < SEMIARID_THRESHOLD:
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
	return "Dfa" if temp > CONTINENTAL_MILD_C else "Dfc"


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
			# §7.2: the driest steppe fringes shade into desert.
			if float(hex["precipitation"]) < ARID_THRESHOLD + 0.03:
				biome = "desert"
				subtype = ""
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
	# §7.2 montane forest: jungle at mountain elevation becomes woods.
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
	for r in range(height):
		for q in range(width):
			var key := Vector2i(q, r)
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
			var rng := WorldGenRng.stream(campaign_seed, "swamp", 0, "%d,%d" % [q, r])
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
	for r in range(height):
		for q in range(width):
			var key := Vector2i(q, r)
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
