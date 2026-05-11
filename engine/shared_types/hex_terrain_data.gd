class_name HexTerrainData
extends RefCounted

## Terrain tag data for a single hex cell.
##
## Each hex carries independent tags from five layers:
##   Elevation:     flat | hills | mountains
##   Biome:         clear | woods | jungle | swamp | desert
##   Biome subtype: "" (parent default) | forest_dense | forest_taiga |
##                  mountains_volcanic | mountains_glacial | clear_tundra |
##                  clear_savanna | clear_grassland | desert_badlands
##   Water:         "" (none) | ocean | lake
##                  (rivers are overlay data, not a water tag)
##   Territory:     civilized | borderlands | wilderness
##
## See gdd-terrain-system.md §3 for full specification. Subtypes refine the
## parent biome's encounter column, movement bucket, navigation TN,
## encounter distance, lair density column, and creature-type tilt; they
## never invent new RAW columns.


# ---------------------------------------------------------------------------
# Constants — valid tag values per layer
# ---------------------------------------------------------------------------

const ELEVATION_FLAT := "flat"
const ELEVATION_HILLS := "hills"
const ELEVATION_MOUNTAINS := "mountains"

const BIOME_CLEAR := "clear"
const BIOME_WOODS := "woods"
const BIOME_JUNGLE := "jungle"
const BIOME_SWAMP := "swamp"
const BIOME_DESERT := "desert"

const SUBTYPE_NONE := ""
const SUBTYPE_FOREST_DENSE := "forest_dense"
const SUBTYPE_FOREST_TAIGA := "forest_taiga"
const SUBTYPE_MOUNTAINS_VOLCANIC := "mountains_volcanic"
const SUBTYPE_MOUNTAINS_GLACIAL := "mountains_glacial"
const SUBTYPE_CLEAR_TUNDRA := "clear_tundra"
const SUBTYPE_CLEAR_SAVANNA := "clear_savanna"
const SUBTYPE_CLEAR_GRASSLAND := "clear_grassland"
const SUBTYPE_DESERT_BADLANDS := "desert_badlands"

const WATER_NONE := ""
const WATER_OCEAN := "ocean"
const WATER_LAKE := "lake"

const TERRITORY_CIVILIZED := "civilized"
const TERRITORY_BORDERLANDS := "borderlands"
const TERRITORY_WILDERNESS := "wilderness"


## Subtype compatibility matrix.
## Each entry: parent biome it refines, allowed elevations, allowed co-biomes
## (for elevation-rooted subtypes that constrain biome), and the encounter
## column it resolves to. See gdd-terrain-system.md §3.4 Table 3.4.1.
const SUBTYPE_PROFILES := {
	SUBTYPE_FOREST_DENSE: {
		"parent_biome": BIOME_WOODS,
		"allowed_elevations": [ELEVATION_FLAT, ELEVATION_HILLS, ELEVATION_MOUNTAINS],
		"allowed_biomes": [BIOME_WOODS],
	},
	SUBTYPE_FOREST_TAIGA: {
		"parent_biome": BIOME_WOODS,
		"allowed_elevations": [ELEVATION_FLAT, ELEVATION_HILLS, ELEVATION_MOUNTAINS],
		"allowed_biomes": [BIOME_WOODS],
	},
	SUBTYPE_MOUNTAINS_VOLCANIC: {
		"parent_biome": "",  # elevation-rooted; constrains biome via allowed_biomes
		"allowed_elevations": [ELEVATION_MOUNTAINS],
		# Any biome except swamp. Jungle is explicitly allowed (tropical volcanic).
		"allowed_biomes": [BIOME_CLEAR, BIOME_WOODS, BIOME_JUNGLE, BIOME_DESERT],
	},
	SUBTYPE_MOUNTAINS_GLACIAL: {
		"parent_biome": "",
		"allowed_elevations": [ELEVATION_MOUNTAINS],
		"allowed_biomes": [BIOME_CLEAR, BIOME_DESERT],
	},
	SUBTYPE_CLEAR_TUNDRA: {
		"parent_biome": BIOME_CLEAR,
		"allowed_elevations": [ELEVATION_FLAT, ELEVATION_HILLS],
		"allowed_biomes": [BIOME_CLEAR],
	},
	SUBTYPE_CLEAR_SAVANNA: {
		"parent_biome": BIOME_CLEAR,
		"allowed_elevations": [ELEVATION_FLAT, ELEVATION_HILLS],
		"allowed_biomes": [BIOME_CLEAR],
	},
	SUBTYPE_CLEAR_GRASSLAND: {
		"parent_biome": BIOME_CLEAR,
		"allowed_elevations": [ELEVATION_FLAT, ELEVATION_HILLS, ELEVATION_MOUNTAINS],
		"allowed_biomes": [BIOME_CLEAR],
	},
	SUBTYPE_DESERT_BADLANDS: {
		"parent_biome": BIOME_DESERT,
		"allowed_elevations": [ELEVATION_FLAT, ELEVATION_HILLS],
		"allowed_biomes": [BIOME_DESERT],
	},
}


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var elevation: String = ELEVATION_FLAT
var biome: String = BIOME_CLEAR
var biome_subtype: String = SUBTYPE_NONE
var water: String = WATER_NONE
var civilization: String = TERRITORY_WILDERNESS
var has_city: bool = false
## Preserved so deforestation/forestation can be reversed later.
var original_biome: String = ""
var settlement_ids: Array[String] = []
## Overlay data for rivers/roads. null = no overlays on this hex.
var overlay: HexOverlayData = null


# ---------------------------------------------------------------------------
# Public methods
# ---------------------------------------------------------------------------

## Returns encounter table weights as {String: int} summing to 100.
## Implements the priority cascade from gdd-terrain-system.md §4.1 and §4.2,
## with §3.4 subtype overrides applied before the natural-terrain cascade.
##
## Special sentinel "_natural" means the caller should apply natural terrain
## logic for that portion of the roll (used only in borderlands).
func encounter_table_weights() -> Dictionary:
	# Ocean and lake are full-hex water tiles that override everything else.
	if water == WATER_OCEAN:
		return {"ocean": 100}
	if water == WATER_LAKE:
		return {"lake": 100}

	# City presence overrides all territory classifications.
	if has_city:
		return {"city": 100}

	if civilization == TERRITORY_CIVILIZED:
		return {"inhabited": 100}

	if civilization == TERRITORY_BORDERLANDS:
		return {"inhabited": 50, "_natural": 50}

	# Wilderness — derive from natural terrain tags, honoring subtype overrides.
	return _natural_terrain_weights()


## Returns the costliest movement terrain category for this hex.
## Subtype overrides apply first (e.g. forest_dense forces jungle-tier x1/2;
## desert_badlands forces hills-tier x2/3 even on flat).
## Priority (highest cost first): mountains > swamp > jungle > dense_forest >
##   woods > hills > badlands > desert > taiga(=woods) > clear
func movement_cost_category() -> String:
	if water == WATER_OCEAN:
		return "ocean"
	if water == WATER_LAKE:
		return "lake"

	# Subtype overrides for movement.
	match biome_subtype:
		SUBTYPE_FOREST_DENSE:
			# Dense forest = jungle-tier impedance per RAW (Forest Heavy
			# pairs with Jungle in encounter-distance table).
			if elevation == ELEVATION_MOUNTAINS:
				return "mountains"  # mountains x1/2 ties; keep mountains key
			return "dense_forest"
		SUBTYPE_DESERT_BADLANDS:
			# Eroded terrain impedes even when nominally flat.
			if elevation == ELEVATION_MOUNTAINS:
				return "mountains"
			return "badlands"

	# Default cascade (unchanged from pre-subtype behavior).
	if elevation == ELEVATION_MOUNTAINS:
		return "mountains"
	if biome == BIOME_SWAMP:
		return "swamp"
	if biome == BIOME_JUNGLE:
		return "jungle"
	if biome == BIOME_WOODS:
		return "woods"
	if elevation == ELEVATION_HILLS:
		return "hills"
	if biome == BIOME_DESERT:
		return "desert"
	return "clear"


## Returns the navigation throw target for this hex (per ACore Wilderness
## Navigation table). Higher = harder to navigate.
func navigation_target() -> int:
	if water == WATER_OCEAN:
		return 11  # Open Sea
	if water == WATER_LAKE:
		return 4   # Lake (per Sea Navigation table)

	# Subtype overrides — most match parent, but listed for clarity.
	match biome_subtype:
		SUBTYPE_FOREST_DENSE, SUBTYPE_FOREST_TAIGA:
			return 7   # Forest
		SUBTYPE_MOUNTAINS_VOLCANIC, SUBTYPE_MOUNTAINS_GLACIAL:
			return 7   # Mountains
		SUBTYPE_CLEAR_TUNDRA, SUBTYPE_CLEAR_SAVANNA, SUBTYPE_CLEAR_GRASSLAND:
			return 4   # Plains
		SUBTYPE_DESERT_BADLANDS:
			return 7   # Hills/Mountains (broken sight lines)

	# Default — derive from biome + elevation.
	if elevation == ELEVATION_MOUNTAINS or elevation == ELEVATION_HILLS:
		return 7
	if biome == BIOME_WOODS:
		return 7
	if biome == BIOME_JUNGLE or biome == BIOME_SWAMP:
		return 11
	if biome == BIOME_DESERT:
		return 11
	return 4  # Plains


## Returns the encounter distance dice expression (per ACore Wilderness
## Encounter Distance table). Returned as a string for downstream parsing.
func encounter_distance_dice() -> String:
	if water == WATER_OCEAN or water == WATER_LAKE:
		return "5d20x10"  # Open water = Plains-equivalent visibility

	match biome_subtype:
		SUBTYPE_FOREST_DENSE:
			return "5d4"             # Forest, Heavy
		SUBTYPE_FOREST_TAIGA:
			return "5d8"             # Forest, Light
		SUBTYPE_DESERT_BADLANDS:
			return "2d6x10"          # Badlands
		SUBTYPE_CLEAR_TUNDRA, SUBTYPE_CLEAR_SAVANNA, SUBTYPE_CLEAR_GRASSLAND:
			return "5d20x10"         # Plains
		SUBTYPE_MOUNTAINS_VOLCANIC, SUBTYPE_MOUNTAINS_GLACIAL:
			return "4d6x10"          # Mountains

	# Default — derive from biome/elevation.
	if elevation == ELEVATION_MOUNTAINS:
		return "4d6x10"
	if biome == BIOME_SWAMP:
		return "8d10"
	if biome == BIOME_JUNGLE:
		return "5d4"
	if biome == BIOME_WOODS:
		return "5d8"
	if biome == BIOME_DESERT:
		return "4d6x10"
	# Hills with clear biome use Mountains/Hills distance; flat clear uses Plains.
	if elevation == ELEVATION_HILLS:
		return "4d6x10"
	return "5d20x10"


## Returns the lair-density table column (per LE Wilderness Lair Rules
## lairs_per_hex table). One of: clear_grass, scrub_hills, barren_desert,
## mountains_woods, swamp, jungle.
func lair_density_column() -> String:
	if water == WATER_OCEAN or water == WATER_LAKE:
		return ""  # No land lairs on water hexes.

	match biome_subtype:
		SUBTYPE_FOREST_DENSE, SUBTYPE_FOREST_TAIGA:
			return "mountains_woods"
		SUBTYPE_MOUNTAINS_VOLCANIC, SUBTYPE_MOUNTAINS_GLACIAL:
			return "mountains_woods"
		SUBTYPE_CLEAR_TUNDRA, SUBTYPE_CLEAR_SAVANNA, SUBTYPE_CLEAR_GRASSLAND:
			return "clear_grass"
		SUBTYPE_DESERT_BADLANDS:
			return "barren_desert"

	if elevation == ELEVATION_MOUNTAINS or biome == BIOME_WOODS:
		return "mountains_woods"
	if biome == BIOME_JUNGLE:
		return "jungle"
	if biome == BIOME_SWAMP:
		return "swamp"
	if biome == BIOME_DESERT:
		return "barren_desert"
	if elevation == ELEVATION_HILLS:
		return "scrub_hills"
	return "clear_grass"


## Returns the creature-type tilt dictionary for this hex's subtype.
## Returned dict maps creature type ("Men", "Flyer", "Humanoid", "Animal",
## "Unusual", "Dragon", "Insect", "Swimmer", "Undead") to a weight
## multiplier. Multipliers <1.0 reduce the chance of that type; >1.0
## increase it. Unmentioned types use 1.0. An empty dict (default) means
## no tilt — use the RAW d8 column straight.
##
## See gdd-terrain-system.md §3.4 Table 3.4.2.
func creature_type_tilt() -> Dictionary:
	match biome_subtype:
		SUBTYPE_FOREST_TAIGA:
			# Cold-clime forest — boreal animals dominant, fewer humanoids.
			return {"Animal": 1.5, "Humanoid": 0.75}
		SUBTYPE_MOUNTAINS_VOLCANIC:
			# Fire-resistant tilt — Dragons (red), Unusual (salamander, hellhound).
			return {"Dragon": 1.5, "Unusual": 1.5, "Animal": 0.75}
		SUBTYPE_MOUNTAINS_GLACIAL:
			# Cold-clime mountains — frost giants, white dragons, yetis.
			return {"Humanoid": 1.25, "Dragon": 1.25, "Unusual": 1.25, "Insect": 0.25}
		SUBTYPE_CLEAR_TUNDRA:
			# Tundra — animal-heavy, sparse humanoids (per GDD §12).
			return {"Animal": 1.5, "Humanoid": 0.5, "Insect": 0.5}
		SUBTYPE_CLEAR_SAVANNA:
			# Hot grassland — heavy animals (lions, elephants), gnolls/nomads.
			return {"Animal": 1.5, "Humanoid": 1.25}
		SUBTYPE_DESERT_BADLANDS:
			# Use Barrens column directly; no additional tilt over that column.
			return {}
		_:
			return {}


## Creates a HexTerrainData from a dictionary. Missing keys fall back to field defaults.
static func from_dict(data: Dictionary) -> HexTerrainData:
	var t := HexTerrainData.new()
	t.elevation = data.get("elevation", ELEVATION_FLAT)
	t.biome = data.get("biome", BIOME_CLEAR)
	t.biome_subtype = data.get("biome_subtype", SUBTYPE_NONE)
	t.water = data.get("water", WATER_NONE)
	t.civilization = data.get("civilization", TERRITORY_WILDERNESS)
	t.has_city = data.get("has_city", false)
	t.original_biome = data.get("original_biome", "")
	t.settlement_ids.assign(data.get("settlement_ids", []))
	if data.has("overlay"):
		t.overlay = HexOverlayData.from_dict(data["overlay"])
	return t


## Returns true if all tags are legal values AND the subtype is compatible
## with the elevation/biome it sits on.
func is_valid() -> bool:
	var valid_elevations := [ELEVATION_FLAT, ELEVATION_HILLS, ELEVATION_MOUNTAINS]
	var valid_biomes := [BIOME_CLEAR, BIOME_WOODS, BIOME_JUNGLE, BIOME_SWAMP, BIOME_DESERT]
	var valid_waters := [WATER_NONE, WATER_OCEAN, WATER_LAKE]
	var valid_civilizations := [TERRITORY_CIVILIZED, TERRITORY_BORDERLANDS, TERRITORY_WILDERNESS]
	if not (elevation in valid_elevations and biome in valid_biomes
			and water in valid_waters and civilization in valid_civilizations):
		return false

	# Ocean and lake hexes cannot also be subtyped (subtype refines land terrain).
	if water != WATER_NONE and biome_subtype != SUBTYPE_NONE:
		return false

	# Subtype compatibility — empty subtype is always legal.
	if biome_subtype != SUBTYPE_NONE:
		if not SUBTYPE_PROFILES.has(biome_subtype):
			return false
		var profile: Dictionary = SUBTYPE_PROFILES[biome_subtype]
		if not (elevation in profile["allowed_elevations"]):
			return false
		if not (biome in profile["allowed_biomes"]):
			return false

	if overlay != null and not overlay.is_valid():
		return false
	return true


## Returns true if this hex has a river overlay.
func has_river() -> bool:
	return overlay != null and overlay.has_river()


## Returns true if this hex has a road overlay.
func has_road() -> bool:
	return overlay != null and overlay.has_road()


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Computes encounter table weights for wilderness hexes from natural terrain tags.
func _natural_terrain_weights() -> Dictionary:
	# Subtype overrides — explicit column choices for refined terrain.
	# These bypass the biome/elevation cascade entirely.
	match biome_subtype:
		SUBTYPE_FOREST_DENSE, SUBTYPE_FOREST_TAIGA:
			# Both resolve to Woods column regardless of elevation —
			# the subtype is what makes the forest dominant.
			if elevation == ELEVATION_MOUNTAINS or elevation == ELEVATION_HILLS:
				# Keep the parent biome/elevation split for parity with woods
				# on hills/mountains, since the subtype refines woods (not the
				# elevation modifier).
				return {"woods": 60, "mountains_hills": 40}
			return {"woods": 100}
		SUBTYPE_MOUNTAINS_VOLCANIC, SUBTYPE_MOUNTAINS_GLACIAL:
			# Mountains/Hills column directly; sub-table tilt picks creatures.
			return {"mountains_hills": 100}
		SUBTYPE_CLEAR_TUNDRA, SUBTYPE_CLEAR_SAVANNA, SUBTYPE_CLEAR_GRASSLAND:
			# Clear column; tundra/savanna tilt the creature sub-roll.
			if elevation == ELEVATION_HILLS or elevation == ELEVATION_MOUNTAINS:
				# Open-hills rule still applies.
				return {"clear_grass_scrub": 40, "mountains_hills": 60}
			return {"clear_grass_scrub": 100}
		SUBTYPE_DESERT_BADLANDS:
			# Badlands = Barrens column per RAW lair-density / encounter tables.
			return {"barren_desert": 100}

	# Default cascade (unchanged from pre-subtype behavior) ---------------

	# Desert special cases — desert biome interacts with elevation.
	if biome == BIOME_DESERT:
		match elevation:
			ELEVATION_FLAT:
				return {"barren_desert": 100}
			ELEVATION_HILLS, ELEVATION_MOUNTAINS:
				return {"barren_desert": 60, "mountains_hills": 40}

	# Flat hexes map directly to the biome's encounter column.
	if elevation == ELEVATION_FLAT:
		var biome_column := _biome_to_encounter_column(biome)
		return {biome_column: 100}

	# Non-flat, clear biome — "open hills" territory: reversed weights.
	if biome == BIOME_CLEAR:
		return {"clear_grass_scrub": 40, "mountains_hills": 60}

	# Non-flat, non-clear biome — biome dominates, hills/mountains add weight.
	var biome_col := _biome_to_encounter_column(biome)
	return {biome_col: 60, "mountains_hills": 40}


## Maps a biome tag to the canonical encounter table column key.
func _biome_to_encounter_column(b: String) -> String:
	match b:
		BIOME_CLEAR:   return "clear_grass_scrub"
		BIOME_WOODS:   return "woods"
		BIOME_JUNGLE:  return "jungle"
		BIOME_SWAMP:   return "swamp"
		BIOME_DESERT:  return "barren_desert"
		_:             return "clear_grass_scrub"
