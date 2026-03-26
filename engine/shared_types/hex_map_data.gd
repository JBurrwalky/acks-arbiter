class_name HexMapData
extends RefCounted

## Container for all data in one hex map layer.
## Hex coordinates are axial (q, r) stored as Vector2i(q, r).
## Fog state is per-hex; defaults to HIDDEN for any hex not in the fog dict.


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

enum MapScale {
	CAMPAIGN_24MI,  ## 24-mile hexes — strategic wilderness
	REGIONAL_6MI,   ## 6-mile hexes — tactical wilderness
	LOCAL_15MI,     ## 1.5-mile hexes — domain / local
}

enum FogState {
	HIDDEN,    ## Never seen — black overlay
	EXPLORED,  ## Previously seen — dimmed grey overlay
	VISIBLE,   ## Currently in party's sight range — no overlay
}


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var id: String = ""
var name: String = ""
var scale: MapScale = MapScale.REGIONAL_6MI
## Keyed by Vector2i(q, r) → HexTerrainData
var hexes: Dictionary = {}
## Keyed by Vector2i(q, r) → FogState; absent entries are treated as HIDDEN
var fog: Dictionary = {}
var party_hex: Vector2i = Vector2i.ZERO


# ---------------------------------------------------------------------------
# Public methods
# ---------------------------------------------------------------------------

func get_hex(coord: Vector2i) -> HexTerrainData:
	return hexes.get(coord, null)


func is_valid_coord(coord: Vector2i) -> bool:
	return hexes.has(coord)


func get_fog_state(coord: Vector2i) -> FogState:
	return fog.get(coord, FogState.HIDDEN)


func set_fog_state(coord: Vector2i, state: FogState) -> void:
	fog[coord] = state


## Builds a HexMapData from a dict matching the JSON structure.
## The "hexes" array becomes the hexes dict keyed by Vector2i(hex.q, hex.r).
## Fog starts empty (all HIDDEN) — controller sets fog on load.
static func from_dict(data: Dictionary) -> HexMapData:
	var m := HexMapData.new()
	m.id = data.get("id", "")
	m.name = data.get("name", "")
	m.scale = _scale_from_string(data.get("scale", "regional_6mi"))

	var party_hex_data: Dictionary = data.get("party_hex", {"q": 0, "r": 0})
	m.party_hex = Vector2i(party_hex_data.get("q", 0), party_hex_data.get("r", 0))

	var hexes_array: Array = data.get("hexes", [])
	for hex_data in hexes_array:
		var coord := Vector2i(hex_data.get("q", 0), hex_data.get("r", 0))
		m.hexes[coord] = HexTerrainData.from_dict(hex_data)

	# fog dict starts empty — all hexes are HIDDEN until controller reveals them
	return m


## Opens path via FileAccess, parses JSON, and returns a HexMapData.
## Logs errors and returns null on any failure.
static func load_from_file(path: String) -> HexMapData:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("HexMapData.load_from_file: could not open '%s' (error %d)" % [path, FileAccess.get_open_error()])
		return null

	var content := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(content)
	if parsed == null:
		push_error("HexMapData.load_from_file: JSON parse failed for '%s'" % path)
		return null

	return HexMapData.from_dict(parsed)


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

static func _scale_from_string(s: String) -> MapScale:
	match s:
		"campaign_24mi": return MapScale.CAMPAIGN_24MI
		"regional_6mi":  return MapScale.REGIONAL_6MI
		"local_15mi":    return MapScale.LOCAL_15MI
		_:               return MapScale.REGIONAL_6MI
