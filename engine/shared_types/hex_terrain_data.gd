class_name HexTerrainData
extends RefCounted

## Terrain tag data for a single hex cell.
##
## Each hex carries independent tags from four layers:
##   Elevation: flat | hills | mountains
##   Biome:     clear | woods | jungle | swamp | desert
##   Water:     "" (none) | ocean | lake
##   Territory: civilized | borderlands | wilderness
##
## See gdd-terrain-system.md for full specification.


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

const WATER_NONE := ""
const WATER_OCEAN := "ocean"
const WATER_LAKE := "lake"

const TERRITORY_CIVILIZED := "civilized"
const TERRITORY_BORDERLANDS := "borderlands"
const TERRITORY_WILDERNESS := "wilderness"


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var elevation: String = ELEVATION_FLAT
var biome: String = BIOME_CLEAR
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
## Implements the priority cascade from gdd-terrain-system.md §4.1 and §4.2.
##
## Special sentinel "_natural" means the caller should apply natural terrain
## logic for that portion of the roll (used only in borderlands).
func encounter_table_weights() -> Dictionary:
	# Ocean overrides biome entirely.
	if water == WATER_OCEAN:
		return {"ocean": 100}

	# Lake uses its own encounter table (placeholder — populated in a later build).
	if water == WATER_LAKE:
		return {"lake": 100}

	# City presence overrides all territory classifications.
	if has_city:
		return {"city": 100}

	if civilization == TERRITORY_CIVILIZED:
		return {"inhabited": 100}

	if civilization == TERRITORY_BORDERLANDS:
		return {"inhabited": 50, "_natural": 50}

	# Wilderness — derive from natural terrain tags.
	return _natural_terrain_weights()


## Returns the costliest movement terrain category for this hex.
## Priority (highest cost first): mountains > swamp > jungle > woods > hills > desert > clear > ocean
func movement_cost_category() -> String:
	# Ocean and lake override everything as special/impassable categories.
	if water == WATER_OCEAN:
		return "ocean"
	if water == WATER_LAKE:
		return "lake"

	if elevation == ELEVATION_MOUNTAINS:
		return "mountains"

	if biome == BIOME_SWAMP:
		return "swamp"

	if biome == BIOME_JUNGLE:
		return "jungle"

	# Both woods and hills present — woods is costlier.
	if biome == BIOME_WOODS and elevation == ELEVATION_HILLS:
		return "woods"

	if biome == BIOME_WOODS:
		return "woods"

	if elevation == ELEVATION_HILLS:
		return "hills"

	if biome == BIOME_DESERT:
		return "desert"

	return "clear"


## Creates a HexTerrainData from a dictionary. Missing keys fall back to field defaults.
static func from_dict(data: Dictionary) -> HexTerrainData:
	var t := HexTerrainData.new()
	t.elevation = data.get("elevation", ELEVATION_FLAT)
	t.biome = data.get("biome", BIOME_CLEAR)
	t.water = data.get("water", WATER_NONE)
	t.civilization = data.get("civilization", TERRITORY_WILDERNESS)
	t.has_city = data.get("has_city", false)
	t.original_biome = data.get("original_biome", "")
	t.settlement_ids.assign(data.get("settlement_ids", []))
	if data.has("overlay"):
		t.overlay = HexOverlayData.from_dict(data["overlay"])
	return t


## Returns true if all tags are legal values.
func is_valid() -> bool:
	var valid_elevations := [ELEVATION_FLAT, ELEVATION_HILLS, ELEVATION_MOUNTAINS]
	var valid_biomes := [BIOME_CLEAR, BIOME_WOODS, BIOME_JUNGLE, BIOME_SWAMP, BIOME_DESERT]
	var valid_waters := [WATER_NONE, WATER_OCEAN, WATER_LAKE]
	var valid_civilizations := [TERRITORY_CIVILIZED, TERRITORY_BORDERLANDS, TERRITORY_WILDERNESS]
	if not (elevation in valid_elevations and biome in valid_biomes
			and water in valid_waters and civilization in valid_civilizations):
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
