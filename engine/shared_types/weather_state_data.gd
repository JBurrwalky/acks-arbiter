class_name WeatherStateData
extends RefCounted

## Per-hex per-day weather state (Wilderness closure Phase 2).
##
## v1 implements three concrete channels (temperature_band, atmosphere with
## derived precipitation_level/precipitation_type, visibility_multiplier) plus
## a wind_level field that v1 sets coarsely from atmosphere — wind_direction
## is deferred to Phase 2.5. The 6-channel record in
## `gdd-weather-generation.md` §4.6 remains the long-term shape; later phases
## fill in fog_flag, wind_direction, and per-day Köppen-driven distributions.
##
## Authority:
##   * Atmosphere descriptors (Calm / Rainy / Snowy / Windy) are SACRED from
##     `daw_vagaries.xml` §severe_weather_conditions.
##   * Temperature bands Cold / Mild / Hot are SACRED from
##     `daw_vagaries.xml`. Bands Frigid / Cool / Warm are project-designed
##     intermediates retained for forward compatibility (v1 never emits them).
##   * Speed multipliers Cold/Hot/Rainy/Snowy/Windy ×0.5 + mud ×0.5 again on
##     clear/scrub are SACRED from `daw_vagaries.xml` §severe_weather_effects.
##   * Visibility multipliers and project-designed intermediate speed scales
##     are sourced from `gdd-weather-generation.md` §7.1 / §7.2.


# ---------------------------------------------------------------------------
# Temperature bands — sacred Cold/Mild/Hot per daw_vagaries.xml; intermediate
# Frigid / Cool / Warm bands declared for Phase 2.5 forward compatibility.
# ---------------------------------------------------------------------------

const TEMP_FRIGID := 0
const TEMP_COLD := 1
const TEMP_COOL := 2
const TEMP_MILD := 3
const TEMP_WARM := 4
const TEMP_HOT := 5

const TEMP_LABELS := {
	TEMP_FRIGID: "Frigid",
	TEMP_COLD: "Cold",
	TEMP_COOL: "Cool",
	TEMP_MILD: "Mild",
	TEMP_WARM: "Warm",
	TEMP_HOT: "Hot",
}


# ---------------------------------------------------------------------------
# Atmosphere descriptors — SACRED from daw_vagaries.xml.
# ---------------------------------------------------------------------------

const ATMO_CALM := "calm"
const ATMO_RAINY := "rainy"
const ATMO_SNOWY := "snowy"
const ATMO_WINDY := "windy"

const ATMO_LABELS := {
	ATMO_CALM: "Calm",
	ATMO_RAINY: "Rainy",
	ATMO_SNOWY: "Snowy",
	ATMO_WINDY: "Windy",
}


# ---------------------------------------------------------------------------
# Precipitation type — derived from atmosphere + temperature.
# ---------------------------------------------------------------------------

const PRECIP_NONE := "none"
const PRECIP_RAIN := "rain"
const PRECIP_SNOW := "snow"


# ---------------------------------------------------------------------------
# Feature flag — Phase 2 ships visibility-on-encounter-distance behind a
# compile-time gate so a single-line flip can disable it if regressions
# surface during the milestone after Phase 2 lands.
# ---------------------------------------------------------------------------

const FEATURE_VISIBILITY_ENABLED := true


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var hex_q: int = 0
var hex_r: int = 0
## Day of year, 1–364. Matches Timekeeping.get_day_of_year().
var julian_day: int = 1
var year: int = 1

var temperature_band: int = TEMP_MILD
var atmosphere: String = ATMO_CALM
## 0 = none, 1 = drizzle/flurries, 2 = rain/snow steady, 3 = heavy, 4 = storm.
## v1 only emits 0 (calm) and 2 (steady rain/snow). Phase 2.5 fills the rest.
var precipitation_level: int = 0
var precipitation_type: String = PRECIP_NONE
## Wind level 0–6 (Beaufort-ish). v1 sets coarsely: Windy → 5, otherwise 2.
var wind_level: int = 2
## Visibility multiplier applied to encounter distances. 1.0 = full visibility.
var visibility_multiplier: float = 1.0
## Mud forms when rain falls on clear/scrub biome (daw_vagaries.xml).
var produces_mud: bool = false


# ---------------------------------------------------------------------------
# Factory helpers
# ---------------------------------------------------------------------------

## Build the canonical WeatherStateData for an atmosphere descriptor and
## temperature band. Derives precipitation_level/type, wind_level, and
## visibility_multiplier per daw_vagaries.xml + gdd-weather-generation.md.
## [param biome] is the consumer's biome string (e.g. "clear", "scrub",
## "woods"); used to set produces_mud per the DaW mud rule.
static func make(
	temperature_band: int,
	atmosphere: String,
	biome: String,
) -> WeatherStateData:
	var w := WeatherStateData.new()
	w.temperature_band = temperature_band
	w.atmosphere = atmosphere
	w._derive_channels(biome)
	return w


## Internal: derive precipitation, wind, visibility, mud from the atmosphere
## descriptor + temperature band. Idempotent. Cold-band "Rainy" is normalized
## to "Snowy" first (precipitation falls as snow when freezing) per the
## implicit reading of daw_vagaries.xml — the table only ever pairs Snowy
## with Cold rows but the rule itself is temperature-driven.
func _derive_channels(biome: String) -> void:
	precipitation_level = 0
	precipitation_type = PRECIP_NONE
	wind_level = 2
	visibility_multiplier = 1.0
	produces_mud = false

	if atmosphere == ATMO_RAINY and temperature_band <= TEMP_COLD:
		atmosphere = ATMO_SNOWY

	match atmosphere:
		ATMO_RAINY:
			precipitation_type = PRECIP_RAIN
			precipitation_level = 2  # v1 baseline: steady rain
			visibility_multiplier = 0.5  # gdd-weather-generation.md §4.5
			# Mud forms on clear/scrub when rain falls per daw_vagaries.xml.
			if biome == "clear" or biome == "scrub":
				produces_mud = true
		ATMO_SNOWY:
			precipitation_type = PRECIP_SNOW
			precipitation_level = 2
			visibility_multiplier = 0.5
		ATMO_WINDY:
			# v1: wind 5 = Very Strong (DaW "Windy" trigger threshold).
			wind_level = 5
			# Slight visibility hit (sand/dust). gdd §4.5 has no direct entry
			# for "windy + clear sky"; project-designed conservative 0.9.
			visibility_multiplier = 0.9
		ATMO_CALM:
			pass


# ---------------------------------------------------------------------------
# Mechanical effects (sacred multipliers from daw_vagaries.xml)
# ---------------------------------------------------------------------------

## Returns the DaW "halved movement" multiplier composing temperature, atmos,
## and mud per daw_vagaries.xml §severe_weather_effects:
##   * Cold OR Hot temperature → ×0.5
##   * Rainy / Snowy / Windy atmosphere → ×0.5
##   * Mud (when produces_mud is true and biome is clear/scrub) → ×0.5
## Multipliers stack cumulatively.
##
## Project-designed extras (gdd-weather-generation.md §7.1) — Frigid ×0.33,
## Storm ×0.33, Dense fog ×0.75, Light precipitation ×0.9 — are NOT applied
## in v1 because the corresponding states (precip levels 1, 3, 4 and the fog
## flag) are not yet generated. They become live in Phase 2.5.
##
## Floor at 0.1 so weather alone never reduces travel to zero — players can
## always crawl forward at 10% speed.
func travel_multiplier() -> float:
	var mult: float = 1.0
	if temperature_band <= TEMP_COLD or temperature_band >= TEMP_HOT:
		mult *= 0.5
	if atmosphere == ATMO_RAINY or atmosphere == ATMO_SNOWY or atmosphere == ATMO_WINDY:
		mult *= 0.5
	if produces_mud:
		mult *= 0.5
	return maxf(mult, 0.1)


## Returns the visibility multiplier applied to ACKS encounter distances.
## Gated behind FEATURE_VISIBILITY_ENABLED — when false, returns 1.0 so the
## flag flip restores baseline behavior without removing the integration.
func encounter_visibility_multiplier() -> float:
	if not FEATURE_VISIBILITY_ENABLED:
		return 1.0
	return visibility_multiplier


# ---------------------------------------------------------------------------
# Tooltip / toast helpers
# ---------------------------------------------------------------------------

## Short label for hover popups: e.g. "Cold, Snowy" / "Hot, Calm".
func short_label() -> String:
	var temp_str: String = TEMP_LABELS.get(temperature_band, "Mild")
	var atmo_str: String = ATMO_LABELS.get(atmosphere, "Calm")
	return "%s, %s" % [temp_str, atmo_str]


## True iff this state would visibly differ from "Mild + Calm" in the UI.
## Day-tick toasts only fire when severe.
func is_severe() -> bool:
	if atmosphere != ATMO_CALM:
		return true
	if temperature_band <= TEMP_COLD or temperature_band >= TEMP_HOT:
		return true
	return false


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"hex_q": hex_q,
		"hex_r": hex_r,
		"julian_day": julian_day,
		"year": year,
		"temperature_band": temperature_band,
		"atmosphere": atmosphere,
		"precipitation_level": precipitation_level,
		"precipitation_type": precipitation_type,
		"wind_level": wind_level,
		"visibility_multiplier": visibility_multiplier,
		"produces_mud": int(produces_mud),
	}


static func from_dict(d: Dictionary) -> WeatherStateData:
	var w := WeatherStateData.new()
	w.hex_q = int(d.get("hex_q", 0))
	w.hex_r = int(d.get("hex_r", 0))
	w.julian_day = int(d.get("julian_day", 1))
	w.year = int(d.get("year", 1))
	w.temperature_band = int(d.get("temperature_band", TEMP_MILD))
	w.atmosphere = String(d.get("atmosphere", ATMO_CALM))
	w.precipitation_level = int(d.get("precipitation_level", 0))
	w.precipitation_type = String(d.get("precipitation_type", PRECIP_NONE))
	w.wind_level = int(d.get("wind_level", 2))
	w.visibility_multiplier = float(d.get("visibility_multiplier", 1.0))
	w.produces_mud = bool(int(d.get("produces_mud", 0)))
	return w
