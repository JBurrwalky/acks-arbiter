class_name HexOverlayData
extends RefCounted

## Overlay data for rivers and roads on a single hex cell.
##
## Edge numbering: 0–5 clockwise from North (flat top = North).
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

## Which edges the river touches (values 0–5). Empty = no river.
var river_edges: Array[int] = []

## The edge the river flows out of (downstream). -1 = terminus (e.g. flows into lake).
var river_flow_exit: int = -1

## Which edges the road touches (values 0–5). Empty = no road.
var road_edges: Array[int] = []


# ---------------------------------------------------------------------------
# Public methods
# ---------------------------------------------------------------------------

func has_river() -> bool:
	return not river_edges.is_empty()


func has_road() -> bool:
	return not road_edges.is_empty()


## Returns all river edges except the flow exit (i.e. the entry edges).
func river_entry_edges() -> Array[int]:
	var entries: Array[int] = []
	for edge in river_edges:
		if edge != river_flow_exit:
			entries.append(edge)
	return entries


## Returns the opposite edge index: (edge + 3) % 6.
static func opposite_edge(edge: int) -> int:
	return (edge + 3) % EDGE_COUNT


## Returns the compass name for an edge index.
static func edge_name(edge: int) -> String:
	if edge < 0 or edge >= EDGE_COUNT:
		return "?"
	return EDGE_NAMES[edge]


## Validates that all edge values are in range 0–5 and flow_exit is valid.
func is_valid() -> bool:
	for edge in river_edges:
		if edge < 0 or edge >= EDGE_COUNT:
			return false
	for edge in road_edges:
		if edge < 0 or edge >= EDGE_COUNT:
			return false
	if has_river() and river_flow_exit != -1:
		if river_flow_exit not in river_edges:
			return false
	return true


## Creates a HexOverlayData from a dictionary.
static func from_dict(data: Dictionary) -> HexOverlayData:
	var overlay := HexOverlayData.new()
	var raw_river: Array = data.get("river_edges", [])
	for e in raw_river:
		overlay.river_edges.append(int(e))
	overlay.river_flow_exit = int(data.get("river_flow_exit", -1))
	var raw_road: Array = data.get("road_edges", [])
	for e in raw_road:
		overlay.road_edges.append(int(e))
	return overlay


## Serializes to a dictionary for JSON/DB storage.
func to_dict() -> Dictionary:
	var d := {}
	if has_river():
		d["river_edges"] = river_edges.duplicate()
		d["river_flow_exit"] = river_flow_exit
	if has_road():
		d["road_edges"] = road_edges.duplicate()
	return d
