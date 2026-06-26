class_name HexCliffEdgeData
extends RefCounted

## One cliff / canyon edge between two adjacent hexes (gdd-cliffs-canyons.md §3).
##
## Same per-edge model as [HexRiverEdgeData]: rows are stored canonically (the
## lex-lower (q, r) of the two adjacent hexes owns the entry; no mirror entry),
## and `edge` 0..5 names which of its six edges holds the cliff (flat-top,
## clockwise from N: 0=N, 1=NE, 2=SE, 3=S, 4=SW, 5=NW). It is an impassable
## elevation gradient — blocks party travel across the edge unless the
## SHEER_SURFACE_CLIMB gate (Mountaineering + per-climber gear) is met (§5).
##
## A canyon is not its own object — it is a run of `canyon`-typed cliff edges
## flanking a river-incised valley; both types block identically.

const CLIFF := "cliff"
const CANYON := "canyon"
const VALID_TYPES := [CLIFF, CANYON]


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var hex_q: int = 0
var hex_r: int = 0
var edge: int = 0
var cliff_type: String = CLIFF
## Climb height in feet (rim − floor). Drives the Climb-Walls throw count
## (ceil(height_ft / 100)) and the per-climber iron-stake count (ceil(height_ft / 50)).
var height_ft: int = 0
## Which side is the TOP of the wall: 0 = the owner hex, 1 = the neighbour across `edge`.
## Flips when the row is flipped to its canonical owner.
var high_side: int = 0


# ---------------------------------------------------------------------------
# Static helpers (edge geometry is shared with rivers — same convention)
# ---------------------------------------------------------------------------

static func neighbor_offset(e: int) -> Vector2i:
	return HexRiverEdgeData.neighbor_offset(e)


static func opposite_edge(e: int) -> int:
	return HexRiverEdgeData.opposite_edge(e)


## Canonical descriptor {hex_q, hex_r, edge, adjacent} for the boundary between two
## adjacent hexes (owner = lex-lower). Mirrors HexRiverEdgeData.canonicalize_edge.
static func canonicalize_edge(q1: int, r1: int, q2: int, r2: int) -> Dictionary:
	return HexRiverEdgeData.canonicalize_edge(q1, r1, q2, r2)


## Build a canonical cliff edge between [param high]/[param low] hexes (the higher
## one is the wall top). Returns null if the two hexes are not adjacent.
static func make(high: Vector2i, low: Vector2i, height_ft: int, cliff_type: String = CLIFF) -> HexCliffEdgeData:
	var info := canonicalize_edge(high.x, high.y, low.x, low.y)
	if not info.get("adjacent", false):
		return null
	var e := HexCliffEdgeData.new()
	e.hex_q = int(info["hex_q"])
	e.hex_r = int(info["hex_r"])
	e.edge = int(info["edge"])
	e.cliff_type = cliff_type
	e.height_ft = height_ft
	# high_side: 0 if the owner IS the high hex, else 1 (owner is the low hex).
	e.high_side = 0 if (e.hex_q == high.x and e.hex_r == high.y) else 1
	return e


func is_canonical() -> bool:
	var off: Vector2i = neighbor_offset(edge)
	var nq: int = hex_q + off.x
	var nr: int = hex_r + off.y
	return hex_q < nq or (hex_q == nq and hex_r < nr)


## Flip to point the other way along the same physical edge: owner becomes the
## neighbour, edge rotates 180°, and high_side flips (the top is the other hex now).
func flip_to_canonical() -> void:
	var off: Vector2i = neighbor_offset(edge)
	hex_q += off.x
	hex_r += off.y
	edge = opposite_edge(edge)
	high_side = 1 - high_side


# ---------------------------------------------------------------------------
# Validation + serialization
# ---------------------------------------------------------------------------

func is_valid() -> bool:
	if edge < 0 or edge >= HexRiverEdgeData.EDGE_COUNT:
		return false
	if not (cliff_type in VALID_TYPES):
		return false
	if not (high_side == 0 or high_side == 1):
		return false
	return true


static func from_dict(data: Dictionary) -> HexCliffEdgeData:
	var e := HexCliffEdgeData.new()
	if data.has("hex") and data["hex"] is Array and (data["hex"] as Array).size() >= 2:
		var arr: Array = data["hex"]
		e.hex_q = int(arr[0])
		e.hex_r = int(arr[1])
	else:
		e.hex_q = int(data.get("hex_q", 0))
		e.hex_r = int(data.get("hex_r", 0))
	e.edge = int(data.get("edge", 0))
	e.cliff_type = str(data.get("cliff_type", CLIFF))
	e.height_ft = int(data.get("height_ft", 0))
	e.high_side = int(data.get("high_side", 0))
	return e


func to_dict() -> Dictionary:
	return {
		"hex": [hex_q, hex_r],
		"edge": edge,
		"cliff_type": cliff_type,
		"height_ft": height_ft,
		"high_side": high_side,
	}
