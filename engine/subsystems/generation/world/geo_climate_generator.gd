class_name GeoClimateGenerator
extends RefCounted

## Layer-2 of the field-first world generator (gdd-continuous-geography.md §6-7,
## approved 2026-06-24). Fills a [GeoField]'s climate + per-cell biome channels:
##
##   temperature (lat² curve + elevation lapse + continentality + anomaly noise) →
##   precipitation (orographic west→east moisture sweep + blur + normalize) →
##   per-cell Köppen classification → biome + subtype.
##
## REUSES the live pipeline's climate logic verbatim — `ClimateGenerator`'s
## temperature constants, `_classify_koppen`, and `_assign_biome`, plus
## `HeightmapGenerator._elevation_tag` — so the field-first biome assignment
## matches the hex-native one. The only model CHANGE is precipitation: the
## noise×rain-shadow heuristic is replaced by an orographic sweep, where rain
## shadow EMERGES from windward moisture depletion (GDD §6).
##
## ADDITIVE: not wired into the live pipeline. Deterministic (WorldGenRng; fixed
## sweep/iteration order). Operates on the square base raster.

## Max interior cooling (°C) folded in as a continentality term.
const CONTINENTALITY_C := 2.5
const CONTINENTALITY_CAP := 7  # ocean-distance (cells) at which cooling saturates

# --- Orographic precipitation sweep ---
const MOISTURE_START := 0.6      # parcel moisture arriving at the west edge
const MOISTURE_CEILING := 1.5
const EVAP_RATE := 0.18          # moisture gained per ocean/lake cell (×temp factor)
const BASE_RAIN := 0.06          # fraction of the parcel that rains on flat land
const OROGRAPHIC_COEF := 6.0     # extra rain fraction per unit of windward uplift
const BLUR_PASSES := 2
const PRECIP_NOISE_AMP := 0.08   # low-amplitude texture so iso-precip lines aren't smooth
## Dials the whole world wetter (<1) or drier (>1) by reshaping the rank-normalized
## precip. 1.0 = uniform [0,1] (~18% of land below the arid threshold). Lower values
## push the median wetter (less desert); higher values aridify. A global character
## knob that never touches the Köppen thresholds themselves.
const ARIDITY_GAMMA := 0.82


## Fill field.temperature / precipitation / biome / biome_subtype. Call after
## GeoFieldGenerator.generate() (needs surface + water + the filled hydrology).
static func apply(field: GeoField, campaign_seed: int, params) -> void:
	var ocean_dist := _ocean_distance(field)
	_temperature(field, campaign_seed, params, ocean_dist)
	_precipitation(field, campaign_seed)
	_classify(field, campaign_seed, ocean_dist)


# ---------------------------------------------------------------------------
# Ocean-distance (BFS over the raster, capped) — feeds continentality + biome
# ---------------------------------------------------------------------------

static func _ocean_distance(field: GeoField) -> PackedInt32Array:
	var w := field.width
	var h := field.height
	var n := w * h
	var dist := PackedInt32Array()
	dist.resize(n)
	dist.fill(9999)
	var frontier: Array[int] = []
	for i in range(n):
		if field.water[i] == GeoField.WATER_OCEAN:
			dist[i] = 0
			frontier.append(i)
	var d := 0
	var cap := CONTINENTALITY_CAP + 1
	while not frontier.is_empty() and d < cap:
		d += 1
		var nxt: Array[int] = []
		for i in frontier:
			var col := field.col_of(i)
			var row := field.row_of(i)
			for off: Vector2i in GeoField.D8:
				var nc := col + off.x
				var nr := row + off.y
				if nc < 0 or nc >= w or nr < 0 or nr >= h:
					continue
				var ni := nr * w + nc
				if dist[ni] > d:
					dist[ni] = d
					nxt.append(ni)
		frontier = nxt
	return dist


# ---------------------------------------------------------------------------
# Temperature: lat² curve + above-ceiling lapse + continentality + anomaly
# ---------------------------------------------------------------------------

static func _temperature(field: GeoField, campaign_seed: int, params, ocean_dist: PackedInt32Array) -> void:
	var w := field.width
	var h := field.height
	var temp_noise := FastNoiseLite.new()
	temp_noise.seed = WorldGenRng.derive_seed(campaign_seed, "geo_temperature")
	temp_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	temp_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	temp_noise.fractal_octaves = 3
	temp_noise.frequency = 0.006

	var lat_south: float = params.latitude_south()
	var lat_span: float = params.latitude_north() - lat_south
	var ceiling := HeightmapGenerator.HILLS_THRESHOLD
	var ceiling_span := maxf(1.0 - ceiling, 0.000001)

	for row in range(h):
		# row 0 = north edge (highest latitude); latitude falls southward.
		var lat := lat_south + lat_span * (float(h - 1 - row) / maxf(float(h - 1), 1.0))
		for col in range(w):
			var i := row * w + col
			var px := (float(col) + 0.5) * GeoField.CELL_MILES
			var py := (float(row) + 0.5) * GeoField.CELL_MILES
			var temp := ClimateGenerator.TEMP_AT_EQUATOR - ClimateGenerator.TEMP_LAT_QUADRATIC * lat * lat \
					+ temp_noise.get_noise_2d(px, py) * ClimateGenerator.TEMP_NOISE_AMPLITUDE_C
			if field.water[i] == GeoField.WATER_NONE:
				var land_above := maxf(field.surface[i] - ceiling, 0.0)
				var meters := land_above / ceiling_span * ClimateGenerator.MAX_ELEVATION_METERS
				temp -= ClimateGenerator.LAPSE_C_PER_1000M * meters / 1000.0
			# Continentality: interior runs cooler (annual-mean stand-in for swing).
			var od := mini(ocean_dist[i], CONTINENTALITY_CAP)
			temp -= CONTINENTALITY_C * float(od) / float(CONTINENTALITY_CAP)
			field.temperature[i] = temp


# ---------------------------------------------------------------------------
# Precipitation: orographic west→east moisture sweep + blur + normalize + noise
# ---------------------------------------------------------------------------

static func _precipitation(field: GeoField, campaign_seed: int) -> void:
	var w := field.width
	var h := field.height
	var n := w * h
	var raw := PackedFloat32Array()
	raw.resize(n)

	# West→east parcel sweep: evaporate over water, rain on windward uplift.
	for row in range(h):
		var moisture := MOISTURE_START
		for col in range(w):
			var i := row * w + col
			if field.water[i] != GeoField.WATER_NONE:
				var tfac := clampf((field.temperature[i] + 10.0) / 40.0, 0.1, 1.0)
				moisture = minf(moisture + EVAP_RATE * tfac, MOISTURE_CEILING)
				raw[i] = 0.0
			else:
				var prev_h := field.surface[i] if col == 0 else field.surface[i - 1]
				var uplift := maxf(field.surface[i] - prev_h, 0.0)
				var frac := clampf(BASE_RAIN + OROGRAPHIC_COEF * uplift, 0.0, 1.0)
				var rain := moisture * frac
				raw[i] = rain
				moisture = maxf(moisture - rain, 0.0)

	# Box-blur the land precip a couple of passes to kill 1-D streaking.
	for _pass in range(BLUR_PASSES):
		var blurred := raw.duplicate()
		for row in range(h):
			for col in range(w):
				var i := row * w + col
				if field.water[i] != GeoField.WATER_NONE:
					continue
				var sum := raw[i]
				var cnt := 1.0
				for off: Vector2i in GeoField.D8:
					var nc := col + off.x
					var nr := row + off.y
					if nc < 0 or nc >= w or nr < 0 or nr >= h:
						continue
					var ni := nr * w + nc
					if field.water[ni] != GeoField.WATER_NONE:
						continue
					sum += raw[ni]
					cnt += 1.0
				blurred[i] = sum / cnt
		raw = blurred

	# Rank-normalize the land precip to a uniform [0,1]. The orographic sweep is
	# pathologically right-skewed — a mass of low flat-land values plus rare high
	# windward-mountain spikes — so a plain min-max normalize crushes almost all
	# land below the arid Köppen threshold (the whole continent becomes desert).
	# Ranking preserves the sweep's wet→dry ORDERING (windward wet, leeward and
	# deep-interior dry, rain shadow intact) while guaranteeing a balanced split,
	# self-calibrating across seeds and latitudes. ARIDITY_GAMMA then dials the
	# world wetter/drier without disturbing the thresholds.
	var land_idx: Array[int] = []
	for i in range(n):
		if field.water[i] == GeoField.WATER_NONE:
			land_idx.append(i)
	# Ascending by rain; index tie-break keeps the order deterministic.
	land_idx.sort_custom(func(a: int, b: int) -> bool:
		if raw[a] == raw[b]:
			return a < b
		return raw[a] < raw[b])
	var denom := maxf(float(land_idx.size() - 1), 1.0)
	var rank_frac := PackedFloat32Array()
	rank_frac.resize(n)
	for r in range(land_idx.size()):
		rank_frac[land_idx[r]] = float(r) / denom

	var precip_noise := FastNoiseLite.new()
	precip_noise.seed = WorldGenRng.derive_seed(campaign_seed, "geo_precip_texture")
	precip_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	precip_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	precip_noise.fractal_octaves = 3
	precip_noise.frequency = 0.005

	for row in range(h):
		for col in range(w):
			var i := row * w + col
			if field.water[i] != GeoField.WATER_NONE:
				field.precipitation[i] = 0.0
				continue
			var norm := pow(rank_frac[i], ARIDITY_GAMMA)
			var px := (float(col) + 0.5) * GeoField.CELL_MILES
			var py := (float(row) + 0.5) * GeoField.CELL_MILES
			var jitter := precip_noise.get_noise_2d(px, py) * PRECIP_NOISE_AMP
			field.precipitation[i] = clampf(norm + jitter, 0.0, 1.0)


# ---------------------------------------------------------------------------
# Per-cell biome classification (reuses the live Köppen + biome logic)
# ---------------------------------------------------------------------------

static func _classify(field: GeoField, campaign_seed: int, ocean_dist: PackedInt32Array) -> void:
	var w := field.width
	var h := field.height
	var season_noise := FastNoiseLite.new()
	season_noise.seed = WorldGenRng.derive_seed(campaign_seed, "geo_seasonality")
	season_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	season_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	season_noise.fractal_octaves = 2
	season_noise.frequency = 0.0012

	for row in range(h):
		for col in range(w):
			var i := row * w + col
			if field.water[i] != GeoField.WATER_NONE:
				field.biome[i] = GeoField.BIOME_CLEAR
				field.biome_subtype[i] = GeoField.SUB_NONE
				continue
			var px := (float(col) + 0.5) * GeoField.CELL_MILES
			var py := (float(row) + 0.5) * GeoField.CELL_MILES
			var seasonality := (season_noise.get_noise_2d(px, py) + 1.0) * 0.5
			var koppen := ClimateGenerator._classify_koppen(field.temperature[i], field.precipitation[i], seasonality)
			var elev_tag := HeightmapGenerator.elevation_tag_for(field.surface[i], field.slope[i])
			var d := {"elevation": elev_tag, "precipitation": field.precipitation[i], "water": ""}
			ClimateGenerator._assign_biome(d, koppen, ocean_dist[i])
			field.biome[i] = maxi(0, GeoField.BIOME_NAMES.find(str(d["biome"])))
			field.biome_subtype[i] = maxi(0, GeoField.SUBTYPE_NAMES.find(str(d["biome_subtype"])))
