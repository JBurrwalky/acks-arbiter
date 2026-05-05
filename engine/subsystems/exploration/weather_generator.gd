class_name WeatherGenerator
extends RefCounted

## Deterministic weather generator for a single hex on a single day
## (Wilderness closure Phase 2).
##
## Reads the SACRED `daw_vagaries.xml` §severe_weather_conditions table
## (terrain_row × season → "{temperature}; {atmosphere_chance}%") and produces
## a WeatherStateData record. Determinism: seeded RNG keyed on
## (campaign_id, hex_q, hex_r, julian_day, year). The same (campaign, hex,
## day) tuple always yields the same weather; world-state never mutates the
## roll.
##
## v1 implements the DaW table directly. The Köppen-driven probability
## distributions described in `gdd-weather-generation.md` §5.2 are deferred
## to Phase 2.5 — DaW gives us a sharper, fully-RAW shape to ship.
##
## Coherence (yesterday's weather influences today's) is also Phase 2.5; v1
## is independent per-day. The cache (WeatherCache) keeps yesterday's record
## available so a future coherence pass has the input it needs.


# ---------------------------------------------------------------------------
# Biome → DaW terrain row mapping
# ---------------------------------------------------------------------------
#
# daw_vagaries.xml §severe_weather_conditions has 7 terrain rows:
#   clear_grass, scrub, woods_hills, barren_desert, mountains, swamp, jungle
#
# HexTerrainData has (elevation × biome × water × civilization). v1 maps:
#   biome=clear, elevation=flat   → clear_grass
#   biome=clear, elevation=hills  → woods_hills (rolling grasslands)
#   biome=woods, * (any)          → woods_hills
#   biome=desert                  → barren_desert
#   biome=jungle                  → jungle
#   biome=swamp                   → swamp
#   elevation=mountains            → mountains  (overrides biome)
#
# "scrub" is not currently a biome in HexTerrainData; mapping reserved for
# future biome expansion. v1 never returns it.

const TERRAIN_CLEAR_GRASS := "clear_grass"
const TERRAIN_SCRUB := "scrub"
const TERRAIN_WOODS_HILLS := "woods_hills"
const TERRAIN_BARREN_DESERT := "barren_desert"
const TERRAIN_MOUNTAINS := "mountains"
const TERRAIN_SWAMP := "swamp"
const TERRAIN_JUNGLE := "jungle"


# ---------------------------------------------------------------------------
# DaW severe_weather_conditions table (sacred — daw_vagaries.xml §442–492)
# ---------------------------------------------------------------------------
#
# Each cell is parsed into a struct:
#   { temp_default: int (band),
#     temp_alt: int (band),
#     temp_alt_chance: float (0.0–1.0; 0.0 means temp is unconditional),
#     atmo_default: String,
#     atmo_alt: String,
#     atmo_alt_chance: float (0.0–1.0; 0.0 means atmo is unconditional) }
#
# Per the rule text (line 428): "If an entry gives only a percentage chance
# for severe weather, apply that chance; if severe weather does not occur,
# use mild temperature or calm atmosphere instead." So when alt_chance > 0
# the default is Mild/Calm; the percentage gates the alt.
#
# Examples:
#   "Mild; 75% Rainy"        → temp=Mild always, 75% Rainy / 25% Calm
#   "75% Cold; 10% Windy"    → 75% Cold / 25% Mild; 10% Windy / 90% Calm
#   "Hot; Calm"              → temp=Hot always, atmo=Calm always
#   "Cold; Snowy"            → temp=Cold always, atmo=Snowy always
#   "25% Hot; Rainy"         → 25% Hot / 75% Mild; atmo=Rainy always

const _SEASON_SPRING := "spring"
const _SEASON_SUMMER := "summer"
const _SEASON_AUTUMN := "autumn"
const _SEASON_WINTER := "winter"

# Season alias: CalendarSeasons emits "autumn"; daw_vagaries.xml uses "fall".
# We use "autumn" internally per project convention.

const _DAW_TABLE: Dictionary = {
	_SEASON_SPRING: {
		TERRAIN_CLEAR_GRASS:  {"temp": "Mild",  "atmo": "75% Rainy"},
		TERRAIN_SCRUB:        {"temp": "Hot",   "atmo": "10% Windy"},
		TERRAIN_WOODS_HILLS:  {"temp": "Mild",  "atmo": "75% Rainy"},
		TERRAIN_BARREN_DESERT:{"temp": "Hot",   "atmo": "25% Windy"},
		TERRAIN_MOUNTAINS:    {"temp": "Mild",  "atmo": "25% Rainy"},
		TERRAIN_SWAMP:        {"temp": "Mild",  "atmo": "Rainy"},
		TERRAIN_JUNGLE:       {"temp": "Hot",   "atmo": "25% Rainy"},
	},
	_SEASON_SUMMER: {
		TERRAIN_CLEAR_GRASS:  {"temp": "Hot",   "atmo": "25% Rainy"},
		TERRAIN_SCRUB:        {"temp": "Hot",   "atmo": "Calm"},
		TERRAIN_WOODS_HILLS:  {"temp": "Hot",   "atmo": "25% Rainy"},
		TERRAIN_BARREN_DESERT:{"temp": "Hot",   "atmo": "5% Rainy"},
		TERRAIN_MOUNTAINS:    {"temp": "Mild",  "atmo": "25% Windy"},
		TERRAIN_SWAMP:        {"temp": "Hot",   "atmo": "Rainy"},
		TERRAIN_JUNGLE:       {"temp": "Hot",   "atmo": "Rainy"},
	},
	_SEASON_AUTUMN: {
		TERRAIN_CLEAR_GRASS:  {"temp": "75% Cold","atmo": "10% Windy"},
		TERRAIN_SCRUB:        {"temp": "Mild",  "atmo": "50% Windy"},
		TERRAIN_WOODS_HILLS:  {"temp": "75% Cold","atmo": "10% Snowy"},
		TERRAIN_BARREN_DESERT:{"temp": "Hot",   "atmo": "Calm"},
		TERRAIN_MOUNTAINS:    {"temp": "Cold",  "atmo": "50% Snowy"},
		TERRAIN_SWAMP:        {"temp": "Mild",  "atmo": "Rainy"},
		TERRAIN_JUNGLE:       {"temp": "Hot",   "atmo": "25% Rainy"},
	},
	_SEASON_WINTER: {
		TERRAIN_CLEAR_GRASS:  {"temp": "Cold",  "atmo": "10% Snowy"},
		TERRAIN_SCRUB:        {"temp": "Mild",  "atmo": "75% Rainy"},
		TERRAIN_WOODS_HILLS:  {"temp": "Cold",  "atmo": "25% Snowy"},
		TERRAIN_BARREN_DESERT:{"temp": "75% Hot","atmo": "Calm"},
		TERRAIN_MOUNTAINS:    {"temp": "Cold",  "atmo": "Snowy"},
		TERRAIN_SWAMP:        {"temp": "Cold",  "atmo": "Rainy"},
		TERRAIN_JUNGLE:       {"temp": "25% Hot","atmo": "Rainy"},
	},
}


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Generate a WeatherStateData for a hex on a specific day.
##
## [param campaign_id] — string seed namespace; same campaign_id + hex + day
##                        always yields identical weather.
## [param hex_q] / [param hex_r] — axial hex coordinates; part of the seed so
##                        adjacent hexes vary independently.
## [param terrain]      — HexTerrainData for the hex (biome + elevation drive
##                        the DaW row lookup).
## [param julian_day]   — 1–364 from Timekeeping.get_day_of_year().
## [param year]         — multi-year campaigns use this to vary year-over-year.
## [param hemisphere]   — "north" (default) or "south"; flips climate season.
##
## Returns a populated WeatherStateData with hex_q/hex_r/julian_day/year set.
static func generate(
	campaign_id: String,
	hex_q: int,
	hex_r: int,
	terrain: HexTerrainData,
	julian_day: int,
	year: int = 1,
	hemisphere: String = "north",
) -> WeatherStateData:
	var biome: String = _biome_for_weather(terrain)
	var dawn_terrain: String = _terrain_row_for_terrain(terrain)
	var season: String = CalendarSeasons.get_climate_season(julian_day, hemisphere)
	# CalendarSeasons emits "autumn"; the table key matches.
	var cell: Dictionary = _DAW_TABLE.get(season, {}).get(dawn_terrain, {})
	if cell.is_empty():
		# Defensive fallback: temperate calm spring day.
		cell = {"temp": "Mild", "atmo": "Calm"}

	var seed_value: int = _seed(campaign_id, hex_q, hex_r, julian_day, year)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var temp_band: int = _resolve_temperature(cell.get("temp", "Mild"), rng)
	var atmosphere: String = _resolve_atmosphere(cell.get("atmo", "Calm"), rng)

	var w := WeatherStateData.make(temp_band, atmosphere, biome)
	# Ocean / lake hexes inherit weather but never get mud (water bodies have
	# no soil to mud up). Idempotent safety guard.
	if not terrain.water.is_empty():
		w.produces_mud = false
	w.hex_q = hex_q
	w.hex_r = hex_r
	w.julian_day = julian_day
	w.year = year
	return w


# ---------------------------------------------------------------------------
# Internal — table parsing
# ---------------------------------------------------------------------------

## Parse a "Mild" / "75% Cold" / "Hot" temperature cell into a band int.
## When percentage-prefixed: roll the gate; on success return the alt band,
## on failure return Mild (band 3) per the rule fallback.
static func _resolve_temperature(cell: String, rng: RandomNumberGenerator) -> int:
	if cell.is_empty():
		return WeatherStateData.TEMP_MILD
	var spec: Dictionary = _parse_alt_spec(cell)
	if spec.get("alt_chance", 0.0) > 0.0:
		var roll: float = rng.randf()
		if roll < spec["alt_chance"]:
			return _temperature_band_from_label(spec["alt_label"])
		return WeatherStateData.TEMP_MILD
	return _temperature_band_from_label(spec.get("default_label", "Mild"))


## Parse a "Calm" / "75% Rainy" / "Rainy" atmosphere cell into the canonical
## atmosphere descriptor. Same percentage-fallback rule as temperature, but
## the fallback is Calm.
static func _resolve_atmosphere(cell: String, rng: RandomNumberGenerator) -> String:
	if cell.is_empty():
		return WeatherStateData.ATMO_CALM
	var spec: Dictionary = _parse_alt_spec(cell)
	if spec.get("alt_chance", 0.0) > 0.0:
		var roll: float = rng.randf()
		if roll < spec["alt_chance"]:
			return _atmosphere_from_label(spec["alt_label"])
		return WeatherStateData.ATMO_CALM
	return _atmosphere_from_label(spec.get("default_label", "Calm"))


## Convert a DaW cell string to:
##   { default_label: String, alt_label: String, alt_chance: float }
## "Mild"          → {default: "Mild", alt: "", alt_chance: 0.0}
## "75% Cold"      → {default: "Mild", alt: "Cold", alt_chance: 0.75}
## "10% Windy"     → {default: "Calm", alt: "Windy", alt_chance: 0.10}
## "25% Hot"       → {default: "Mild", alt: "Hot", alt_chance: 0.25}
##
## Detection: if the string starts with "<digits>% " it's percentage-gated;
## otherwise it's unconditional.
static func _parse_alt_spec(cell: String) -> Dictionary:
	var trimmed: String = cell.strip_edges()
	if trimmed.is_empty():
		return {"default_label": "", "alt_label": "", "alt_chance": 0.0}
	# Look for "NN%" prefix.
	var pct_pos: int = trimmed.find("%")
	if pct_pos > 0:
		var pct_part: String = trimmed.substr(0, pct_pos).strip_edges()
		if pct_part.is_valid_int():
			var chance: float = float(pct_part.to_int()) / 100.0
			var label: String = trimmed.substr(pct_pos + 1).strip_edges()
			return {
				"default_label": "",  # unset; resolver picks Mild/Calm fallback
				"alt_label": label,
				"alt_chance": chance,
			}
	return {
		"default_label": trimmed,
		"alt_label": "",
		"alt_chance": 0.0,
	}


static func _temperature_band_from_label(label: String) -> int:
	match label.to_lower():
		"frigid": return WeatherStateData.TEMP_FRIGID
		"cold":   return WeatherStateData.TEMP_COLD
		"cool":   return WeatherStateData.TEMP_COOL
		"mild":   return WeatherStateData.TEMP_MILD
		"warm":   return WeatherStateData.TEMP_WARM
		"hot":    return WeatherStateData.TEMP_HOT
		_:        return WeatherStateData.TEMP_MILD


static func _atmosphere_from_label(label: String) -> String:
	match label.to_lower():
		"calm":  return WeatherStateData.ATMO_CALM
		"rainy": return WeatherStateData.ATMO_RAINY
		"snowy": return WeatherStateData.ATMO_SNOWY
		"windy": return WeatherStateData.ATMO_WINDY
		_:       return WeatherStateData.ATMO_CALM


# ---------------------------------------------------------------------------
# Internal — biome / terrain row mapping
# ---------------------------------------------------------------------------

## Returns the biome string we feed into WeatherStateData.make() for mud
## evaluation. Mud only forms on clear/scrub. Water hexes pass through their
## underlying biome here (still no mud — guarded by the water check in
## generate()).
static func _biome_for_weather(terrain: HexTerrainData) -> String:
	return terrain.biome


## Maps a HexTerrainData → DaW severe_weather_conditions row name.
## Mountain elevation overrides biome (sacred — DaW uses elevation).
## Hills + clear/grass inherit "woods_hills" since DaW pairs them.
static func _terrain_row_for_terrain(terrain: HexTerrainData) -> String:
	if terrain.water == HexTerrainData.WATER_OCEAN \
			or terrain.water == HexTerrainData.WATER_LAKE:
		# Open water — treat as clear_grass for atmosphere; effects layer
		# guards mud. Sea-specific weather is Phase 7.
		return TERRAIN_CLEAR_GRASS
	if terrain.elevation == HexTerrainData.ELEVATION_MOUNTAINS:
		return TERRAIN_MOUNTAINS
	match terrain.biome:
		HexTerrainData.BIOME_DESERT: return TERRAIN_BARREN_DESERT
		HexTerrainData.BIOME_JUNGLE: return TERRAIN_JUNGLE
		HexTerrainData.BIOME_SWAMP:  return TERRAIN_SWAMP
		HexTerrainData.BIOME_WOODS:  return TERRAIN_WOODS_HILLS
		HexTerrainData.BIOME_CLEAR:
			# Hills + clear pairs with woods_hills per DaW; flat clear → clear_grass.
			if terrain.elevation == HexTerrainData.ELEVATION_HILLS:
				return TERRAIN_WOODS_HILLS
			return TERRAIN_CLEAR_GRASS
		_:
			return TERRAIN_CLEAR_GRASS


# ---------------------------------------------------------------------------
# Internal — deterministic seed
# ---------------------------------------------------------------------------

## Seed = hash of (campaign_id, hex_q, hex_r, julian_day, year). GDScript's
## hash() is 32-bit; collisions are statistically negligible for a single
## campaign's hex × day space. Terrain attributes are NOT part of the seed —
## a hex changing biome (e.g. deforestation) does not retroactively rewrite
## past days' rolls. The cache is keyed identically and supersedes the seed
## for already-generated days.
static func _seed(campaign_id: String, hex_q: int, hex_r: int, julian_day: int, year: int) -> int:
	var key: String = "%s|q=%d|r=%d|jd=%d|y=%d" % [
		campaign_id, hex_q, hex_r, julian_day, year,
	]
	return hash(key)
