class_name HexOverlayData
extends RefCounted

## Cell-attached overlay data for a single hex cell. As of migration 130
## this holds road edges ONLY — rivers are first-class edge entities in
## HexRiverEdgeData / hex_river_edges (see GDD §3.6).
##
## Edge numbering: 0–5 clockwise from North (flat-top = North).
##   0 = N, 1 = NE, 2 = SE, 3 = S, 4 = SW, 5 = NW
## Opposite edge: (n + 3) % 6


# ---------------------------------------------------------------------------
# Edge constants (flat-top hex, clockwise from North)
# ---------------------------------------------------------------------------

const EDGE_N  := 0
const EDGE_NE := 1
const EDGE_SE := 2
const EDGE_S  := 3
const EDGE_SW := 4
const EDGE_NW := 5

const EDGE_NAMES := ["N", "NE", "SE", "S", "SW", "NW"]

const EDGE_COUNT := 6


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

## Which edges the road touches (values 0–5). Empty = no road.
var road_edges: Array[int] = []


# ---------------------------------------------------------------------------
# Public methods
# ---------------------------------------------------------------------------

func has_road() -> bool:
	return not road_edges.is_empty()


## Returns the opposite edge index: (edge + 3) % 6.
static func opposite_edge(edge: int) -> int:
	return (edge + 3) % EDGE_COUNT


## Returns the compass name for an edge index.
static func edge_name(edge: int) -> String:
	if edge < 0 or edge >= EDGE_COUNT:
		return "?"
	return EDGE_NAMES[edge]


## Validates that all edge values are in range 0–5.
func is_valid() -> bool:
	for edge in road_edges:
		if edge < 0 or edge >= EDGE_COUNT:
			return false
	return true


## Creates a HexOverlayData from a dictionary. Tolerates legacy keys
## (`river_edges`, `river_flow_exit`) by ignoring them — the migration-130
## conversion is responsible for translating those into hex_river_edges
## rows; a stale JSON file that still names them will simply lose its
## rivers, which is the same behavior as the schema-side conversion.
static func from_dict(data: Dictionary) -> HexOverlayData:
	var overlay := HexOverlayData.new()
	var raw_road: Array = data.get("road_edges", [])
	for e in raw_road:
		overlay.road_edges.append(int(e))
	return overlay


## Serializes to a dictionary for JSON/DB storage.
func to_dict() -> Dictionary:
	var d := {}
	if has_road():
		d["road_edges"] = road_edges.duplicate()
	return d
