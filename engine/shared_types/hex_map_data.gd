class_name HexMapData
extends RefCounted

## Container for all data in one hex map layer.
## Hex coordinates are axial (q, r) stored as Vector2i(q, r).
## Fog state is per-hex; defaults to HIDDEN for any hex not in the fog dict.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Sentinel for `parent_anchor` when the map has no parent. Used in lieu of
## a separate Variant-typed field so callers can rely on the type being
## Vector2i everywhere. Real anchor coordinates are non-negative-only in
## practice but the schema permits negatives, so the sentinel is chosen
## outside the plausible coordinate range.
const NO_PARENT_ANCHOR := Vector2i(-2147483648, -2147483648)


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

## Migration 119: parent linkage. Empty string = top-level map.
var parent_map_id: String = ""
## Parent-map hex this child's (0,0) corresponds to. NO_PARENT_ANCHOR when
## there is no parent.
var parent_anchor: Vector2i = NO_PARENT_ANCHOR
## Parent-map hex coords this inset covers. Array of Vector2i. Hand-authored;
## a 6-mile inset typically covers a 4x4-ish patch of a 24-mile parent hex but
## the shape is content, not derived.
var parent_hex_footprint: Array = []


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


func has_parent() -> bool:
	return not parent_map_id.is_empty()


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

	m.parent_map_id = data.get("parent_map_id", "")
	if data.has("parent_anchor"):
		var anchor_data: Dictionary = data["parent_anchor"]
		m.parent_anchor = Vector2i(anchor_data.get("q", 0), anchor_data.get("r", 0))
	else:
		m.parent_anchor = NO_PARENT_ANCHOR
	var footprint_data: Array = data.get("parent_hex_footprint", [])
	for entry in footprint_data:
		if entry is Dictionary:
			m.parent_hex_footprint.append(Vector2i(int(entry.get("q", 0)), int(entry.get("r", 0))))
		elif entry is Array and entry.size() >= 2:
			m.parent_hex_footprint.append(Vector2i(int(entry[0]), int(entry[1])))

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


## Serialize the parent-linkage footprint to JSON-friendly form.
## Returns an Array of [q, r] pairs (lists, not Vector2i) so JSON.stringify
## can round-trip it.
func footprint_to_json_array() -> Array:
	var out: Array = []
	for coord in parent_hex_footprint:
		out.append([coord.x, coord.y])
	return out


## Parse a footprint JSON string back into an Array[Vector2i]. Returns an
## empty array on malformed input.
static func footprint_from_json_string(s: String) -> Array:
	if s.is_empty():
		return []
	var parsed = JSON.parse_string(s)
	if not (parsed is Array):
		return []
	var out: Array = []
	for entry in parsed:
		if entry is Array and entry.size() >= 2:
			out.append(Vector2i(int(entry[0]), int(entry[1])))
		elif entry is Dictionary:
			out.append(Vector2i(int(entry.get("q", 0)), int(entry.get("r", 0))))
	return out


## Compares two MapScale values. Returns >0 if a is coarser than b, <0 if
## finer, 0 if equal. CAMPAIGN_24MI (0) is coarsest, LOCAL_15MI (2) finest;
## enum ordinal increases toward finer, so coarseness == -(a - b).
static func scale_compare_coarseness(a: MapScale, b: MapScale) -> int:
	return int(b) - int(a)


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

static func _scale_from_string(s: String) -> MapScale:
	match s:
		"campaign_24mi": return MapScale.CAMPAIGN_24MI
		"regional_6mi":  return MapScale.REGIONAL_6MI
		"local_15mi":    return MapScale.LOCAL_15MI
		_:               return MapScale.REGIONAL_6MI


static func _scale_to_string(s: MapScale) -> String:
	match s:
		MapScale.CAMPAIGN_24MI: return "campaign_24mi"
		MapScale.REGIONAL_6MI:  return "regional_6mi"
		MapScale.LOCAL_15MI:    return "local_15mi"
		_:                       return "regional_6mi"
