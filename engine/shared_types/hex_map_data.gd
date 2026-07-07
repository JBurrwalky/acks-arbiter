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

## All river edges on this map (migration 130 / GDD §3.6). Each entry is a
## HexRiverEdgeData in canonical form (lex-lower owner). Populated by
## CampaignRepository.load_hex_map and by HexMapData.from_dict.
var river_edges: Array = []

## All cliff/canyon edges on this map (migration 176 / gdd-cliffs-canyons.md §3).
## Each entry is a HexCliffEdgeData in canonical form. Impassable elevation
## gradients; populated by CampaignRepository.load_hex_map.
var cliff_edges: Array = []


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
##
## Worldographer compatibility: if the dict declares
## `_coordinate_format` OR any hex entry uses `col`/`row` keys instead of
## `q`/`r`, the entire payload is converted from odd-q offset to axial
## (q, r) before parsing. The original `data` argument is never mutated.
static func from_dict(data: Dictionary) -> HexMapData:
	data = _convert_offset_dict_to_axial(data)
	var m := HexMapData.new()
	m.id = data.get("id", "")
	m.name = data.get("name", "")
	m.scale = _scale_from_string(data.get("scale", "regional_6mi"))

	var party_hex_data: Dictionary = data.get("party_hex", {"q": 0, "r": 0})
	m.party_hex = Vector2i(party_hex_data.get("q", 0), party_hex_data.get("r", 0))

	var parent_id_v = data.get("parent_map_id", "")
	m.parent_map_id = String(parent_id_v) if parent_id_v != null else ""
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

	# Migration 130 / GDD §3.6: top-level `river_edges` array. Each entry is
	# canonicalized on read — entries authored against the non-owning hex
	# get flipped (with a warning) so hand-editing either side of an edge
	# produces the same row. Non-adjacent entries are dropped with an error.
	var river_edges_data: Array = data.get("river_edges", [])
	for entry in river_edges_data:
		if not (entry is Dictionary):
			continue
		var edge_data := HexRiverEdgeData.from_dict(entry)
		if not edge_data.is_valid():
			push_error("HexMapData.from_dict: invalid river edge entry: %s" % str(entry))
			continue
		# Compute the neighbor across the declared edge and check
		# canonicality. Non-canonical entries auto-flip with a warning so
		# authors can write either side.
		if not edge_data.is_canonical():
			push_warning("HexMapData.from_dict: river edge at hex=(%d,%d) edge=%d is non-canonical; flipping to lex-lower owner"
				% [edge_data.hex_q, edge_data.hex_r, edge_data.edge])
			edge_data.flip_to_canonical()
		m.river_edges.append(edge_data)
		# Stamp has_river_cached on both endpoint terrains so callers using
		# from_dict (test maps, fixtures) get the same has_river() behavior
		# as repository-loaded maps without an extra walk.
		var owner_coord := Vector2i(edge_data.hex_q, edge_data.hex_r)
		var owner_terrain: HexTerrainData = m.hexes.get(owner_coord)
		if owner_terrain != null:
			owner_terrain.has_river_cached = true
		var off: Vector2i = HexRiverEdgeData.neighbor_offset(edge_data.edge)
		var neighbor_coord: Vector2i = owner_coord + off
		var neighbor_terrain: HexTerrainData = m.hexes.get(neighbor_coord)
		if neighbor_terrain != null:
			neighbor_terrain.has_river_cached = true

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


## Worldographer odd-q offset → axial conversion.
##
## Worldographer exports use odd-column-down offset (q, r are named "col"
## and "row"). Detection is opportunistic: a top-level `_coordinate_format`
## marker OR any `hexes` entry that has `col`/`row` instead of `q`/`r`
## triggers conversion of the entire payload. Dicts already in axial
## form pass through unchanged.
##
## The original argument is never mutated — a deep copy is rewritten.
## Conversion formula (odd cols shifted DOWN by half):
##   q = col
##   r = row - (col - (col & 1)) / 2
##
## Conversion rewrites:
##   * top-level `party_hex`     {"col","row"} → {"q","r"}
##   * each `hexes[]` entry      adds q/r derived from col/row
##   * each `river_edges[]` entry's nested `hex` {"col","row"} →
##                               top-level `hex_q`/`hex_r`
##   * each `road_overlays[]` entry's nested `hex` → same treatment
static func _convert_offset_dict_to_axial(data: Dictionary) -> Dictionary:
	if not _needs_offset_conversion(data):
		return data
	var out: Dictionary = data.duplicate(true)

	# party_hex
	if out.has("party_hex"):
		var ph: Dictionary = out["party_hex"]
		if ph.has("col") and ph.has("row"):
			out["party_hex"] = _offset_to_axial_dict(int(ph["col"]), int(ph["row"]))

	# hexes
	if out.has("hexes") and out["hexes"] is Array:
		for entry in out["hexes"]:
			if entry is Dictionary and entry.has("col") and entry.has("row"):
				var qr: Dictionary = _offset_to_axial_dict(int(entry["col"]), int(entry["row"]))
				entry["q"] = qr["q"]
				entry["r"] = qr["r"]

	# river_edges — nested hex {col,row} → top-level hex_q/hex_r
	if out.has("river_edges") and out["river_edges"] is Array:
		for entry in out["river_edges"]:
			if entry is Dictionary:
				var hex_field = entry.get("hex", null)
				if hex_field is Dictionary and hex_field.has("col") and hex_field.has("row"):
					var qr: Dictionary = _offset_to_axial_dict(int(hex_field["col"]), int(hex_field["row"]))
					entry["hex_q"] = qr["q"]
					entry["hex_r"] = qr["r"]
					entry.erase("hex")

	# road_overlays — same nested treatment. Stored back as `road_overlays`;
	# the consuming code reads through HexTerrainData.from_dict's `overlay`,
	# so we also push road_edges onto the matching `hexes[]` entry below.
	if out.has("road_overlays") and out["road_overlays"] is Array:
		for entry in out["road_overlays"]:
			if entry is Dictionary:
				var hex_field = entry.get("hex", null)
				if hex_field is Dictionary and hex_field.has("col") and hex_field.has("row"):
					var qr: Dictionary = _offset_to_axial_dict(int(hex_field["col"]), int(hex_field["row"]))
					entry["hex_q"] = qr["q"]
					entry["hex_r"] = qr["r"]
					entry.erase("hex")

	return out


static func _needs_offset_conversion(data: Dictionary) -> bool:
	if data.has("_coordinate_format"):
		return true
	var hexes_v = data.get("hexes", null)
	if hexes_v is Array:
		for entry in hexes_v:
			if entry is Dictionary and entry.has("col") and not entry.has("q"):
				return true
			break  # check only the first entry — payloads are uniform
	# Also detect via river_edges or road_overlays nested col/row.
	for key in ["river_edges", "road_overlays"]:
		var arr = data.get(key, null)
		if arr is Array:
			for entry in arr:
				if entry is Dictionary:
					var hex_field = entry.get("hex", null)
					if hex_field is Dictionary and hex_field.has("col"):
						return true
				break
	return false


## Offset (col, row) → axial (q, r). Worldographer odd-q "odd cols shifted
## DOWN by half" convention. (col & 1) is 1 for odd cols, 0 for even cols.
static func _offset_to_axial_dict(col: int, row: int) -> Dictionary:
	var q := col
	var r := row - (col - (col & 1)) / 2
	return {"q": q, "r": r}
