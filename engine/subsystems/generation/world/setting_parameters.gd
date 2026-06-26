class_name SettingParameters
extends RefCounted

## The full user-parameter vector for setting generation
## (gdd-setting-generation.md §11.2; history-sim §13; region-painting §7;
## campaign-creation UI §4). One instance = one generation request.
##
## Determinism contract: campaign seed + canonical_json() of this object
## reproduce the world bit-identically (campaign-creation UI §9 share token).
## Every field therefore round-trips through to_dict()/from_dict(), and
## canonical_json() emits sorted keys at full float precision.

# --- Physical (Layers 1-2) --------------------------------------------------

## "small" 15x12 | "medium" 25x20 | "large" 40x30 | "huge" 60x45 (§4.6).
var map_size: String = "medium"
## "continental" | "archipelago" | "pangaea" (§4.2).
var land_mass_style: String = "continental"
## "low" | "medium" | "high" → elevation-curve exponent 2.0 / 1.5 / 1.0 (§4.3).
var mountain_frequency: String = "medium"
## "cordillera" (many distinct linear spines) | "alpine" (fewer, bolder ranges with
## broad lowlands). Drives the ridged-multifractal base frequency + octave count
## (geo_field_generator._RANGE_STYLE) — a world-character dial, not relief amount.
var mountain_range_style: String = "cordillera"
## "low" | "medium" | "high" — river-source elevation threshold (§4.4).
var river_density: String = "medium"
## Ocean threshold on the shaped 0-1 heightmap (§4.5).
var sea_level: float = 0.3
## "tropical" | "subtropical" | "temperate" | "continental" | "polar" (§5.1).
var latitude_range: String = "temperate"
## "north" | "south" (§5.1; consumed by gdd-calendar-seasons.md §4).
var hemisphere: String = "north"

# --- Cultures (Layer 3) -----------------------------------------------------

## Human culture seed points (~10 default, scaled to map size — catalog §6.1).
var human_seed_points: int = 10
## Whether demihuman (elf/dwarf) seeds are placed at all (§7.5).
var demihuman_presence: bool = true
## Baseline wilderness beastman clanhold scaling, 0.0-2.0 (§6.3).
## [CALIBRATION 2026-06-13] default 1.0→0.5: with the Lawful/Neutral-destroys-
## beastman war ruling, civilizations now clear beastmen by conquest, so the
## interior can stay beastman-rich (the chaotic frontier) without pinning the
## §17 wilderness fraction — 0.5 keeps a plentiful beastman interior that
## advancing civilizations push back.
var wilderness_beastman_density: float = 0.5

# --- History (Layer 4) ------------------------------------------------------

## "stable" 0.6 | "moderate" 1.0 | "turbulent" 1.6 (history-sim §13).
var collapse_temperament: String = "moderate"
## "short" 80 | "standard" 160 | "deep" 240 ticks (history-sim §13).
var history_length: String = "standard"
## "off" 0.0 | "low" 0.5 | "moderate" 1.0 | "high" 2.0 (history-sim §13).
var migration_rate: String = "moderate"
## Cultural assimilation speed — multiplier on the conquest culture-flip rate
## (history-sim §6 / §7.4e). 1.0 = default; lower = tenacious cultures and a lasting
## mosaic of peoples; higher = a fast melting-pot where dominant cultures homogenize
## the map. Scales the (entrenchment+rigidity-resisted) assimilation rate per tick.
var cultural_assimilation: float = 1.0
## Vassal-realm consolidation — multiplier on the target families per synthesized
## vassal in the Phase-5 finalization decomposition (gdd-realms-titles-refactor.md §7).
## 1.0 = the granular default (each Count/Marquis ≈ its tier's family floor → more,
## thinner vassals). Higher = fewer, fuller mid-tier realms (a Duke with 3-4 big
## Counties, not 6 thin ones), leaving more vacant seats for a player to claim. A
## finalization-only knob: it changes how the history-sim result is PARTITIONED for
## the handoff, never the simulated history itself.
var vassal_consolidation: float = 1.0
## Overall non-human demographic share target (~1:5 — setting-gen §7.5).
var non_human_ratio: float = 0.2
## Minimum demographic presence anywhere (setting-gen §7.3/§7.5).
var minority_weight_floor: float = 0.001

# --- Content (Layer 6) ------------------------------------------------------

var dungeon_density: float = 1.0
var road_density: float = 1.0
var fortification_density: float = 1.0
var poi_density: float = 1.0
## "low" | "medium" | "high".
var poi_danger: String = "medium"
## "dense" | "sparse" (region-painting §7 — Sparse doubles detection floors).
var naming_density: String = "dense"


const _MAP_DIMENSIONS := {
	"small": Vector2i(15, 12),
	"medium": Vector2i(25, 20),
	"large": Vector2i(40, 30),
	"huge": Vector2i(60, 45),
}

const _ELEVATION_EXPONENT := {"low": 2.0, "medium": 1.5, "high": 1.0}

const _TEMPERAMENT_MULT := {"stable": 0.6, "moderate": 1.0, "turbulent": 1.6}

const _HISTORY_TICKS := {"short": 80, "standard": 160, "deep": 240}

const _MIGRATION_MULT := {"off": 0.0, "low": 0.5, "moderate": 1.0, "high": 2.0}

# latitude_range → [south edge °N, north edge °N] (setting-gen §5.1 table).
const _LATITUDE_PRESETS := {
	"tropical": [5.0, 20.0],
	"subtropical": [20.0, 38.0],
	"temperate": [35.0, 55.0],
	"continental": [45.0, 65.0],
	"polar": [60.0, 75.0],
}


# --- Derived accessors ------------------------------------------------------

func map_dimensions() -> Vector2i:
	return _MAP_DIMENSIONS.get(map_size, _MAP_DIMENSIONS["medium"])


func elevation_exponent() -> float:
	return _ELEVATION_EXPONENT.get(mountain_frequency, 1.5)


func temperament_multiplier() -> float:
	return _TEMPERAMENT_MULT.get(collapse_temperament, 1.0)


func history_ticks() -> int:
	return _HISTORY_TICKS.get(history_length, 160)


func migration_multiplier() -> float:
	return _MIGRATION_MULT.get(migration_rate, 1.0)


func latitude_south() -> float:
	return _LATITUDE_PRESETS.get(latitude_range, _LATITUDE_PRESETS["temperate"])[0]


func latitude_north() -> float:
	return _LATITUDE_PRESETS.get(latitude_range, _LATITUDE_PRESETS["temperate"])[1]


# --- Serialization ----------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"map_size": map_size,
		"land_mass_style": land_mass_style,
		"mountain_frequency": mountain_frequency,
		"mountain_range_style": mountain_range_style,
		"river_density": river_density,
		"sea_level": sea_level,
		"latitude_range": latitude_range,
		"hemisphere": hemisphere,
		"human_seed_points": human_seed_points,
		"demihuman_presence": demihuman_presence,
		"wilderness_beastman_density": wilderness_beastman_density,
		"collapse_temperament": collapse_temperament,
		"history_length": history_length,
		"migration_rate": migration_rate,
		"cultural_assimilation": cultural_assimilation,
		"vassal_consolidation": vassal_consolidation,
		"non_human_ratio": non_human_ratio,
		"minority_weight_floor": minority_weight_floor,
		"dungeon_density": dungeon_density,
		"road_density": road_density,
		"fortification_density": fortification_density,
		"poi_density": poi_density,
		"poi_danger": poi_danger,
		"naming_density": naming_density,
	}


static func from_dict(data: Dictionary) -> SettingParameters:
	# Accept a raw `setting_parameters` DB row directly: its real parameter vector
	# lives in the `params_json` string column (campaign_seed is a separate column
	# the callers read on their own). Without this, from_dict(get_parameters(...))
	# silently DEFAULTED every field — most damagingly map_size -> "medium", so a
	# huge/large/small world regenerated its field at the wrong size and the 6-mile
	# materialization window clamped off the field edge into open ocean.
	if data.has("params_json"):
		var parsed: Variant = JSON.parse_string(str(data["params_json"]))
		if parsed is Dictionary:
			data = parsed
	var p := SettingParameters.new()
	p.map_size = str(data.get("map_size", p.map_size))
	p.land_mass_style = str(data.get("land_mass_style", p.land_mass_style))
	p.mountain_frequency = str(data.get("mountain_frequency", p.mountain_frequency))
	p.mountain_range_style = str(data.get("mountain_range_style", p.mountain_range_style))
	p.river_density = str(data.get("river_density", p.river_density))
	p.sea_level = float(data.get("sea_level", p.sea_level))
	p.latitude_range = str(data.get("latitude_range", p.latitude_range))
	p.hemisphere = str(data.get("hemisphere", p.hemisphere))
	p.human_seed_points = int(data.get("human_seed_points", p.human_seed_points))
	p.demihuman_presence = bool(data.get("demihuman_presence", p.demihuman_presence))
	p.wilderness_beastman_density = float(data.get("wilderness_beastman_density",
			p.wilderness_beastman_density))
	p.collapse_temperament = str(data.get("collapse_temperament", p.collapse_temperament))
	p.history_length = str(data.get("history_length", p.history_length))
	p.migration_rate = str(data.get("migration_rate", p.migration_rate))
	p.cultural_assimilation = float(data.get("cultural_assimilation", p.cultural_assimilation))
	p.vassal_consolidation = float(data.get("vassal_consolidation", p.vassal_consolidation))
	p.non_human_ratio = float(data.get("non_human_ratio", p.non_human_ratio))
	p.minority_weight_floor = float(data.get("minority_weight_floor", p.minority_weight_floor))
	p.dungeon_density = float(data.get("dungeon_density", p.dungeon_density))
	p.road_density = float(data.get("road_density", p.road_density))
	p.fortification_density = float(data.get("fortification_density", p.fortification_density))
	p.poi_density = float(data.get("poi_density", p.poi_density))
	p.poi_danger = str(data.get("poi_danger", p.poi_danger))
	p.naming_density = str(data.get("naming_density", p.naming_density))
	return p


## Canonical serialized form: sorted keys, full float precision. This string
## participates in the determinism hash and the share token — two parameter
## sets are "the same" iff their canonical_json() match.
func canonical_json() -> String:
	return JSON.stringify(to_dict(), "", true, true)
