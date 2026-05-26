class_name HexRiverEdgeData
extends RefCounted

## One river edge between two adjacent hexes. Migration 130 / GDD §3.6.
##
## Rows are stored canonically: the lex-lower (q, r) of the two adjacent
## hexes owns the entry, and `edge` (0..5) names which of its six edges
## the river follows. The neighbor hex is implied — it never stores a
## mirror entry. Querying "what river edges touch hex H?" requires a
## two-sided lookup (H as owner plus H as neighbor-of-owner); see
## [method CampaignRepository.get_river_edges_for_hex].
##
## Edge numbering matches HexOverlayData (flat-top, clockwise from N):
##   0=N, 1=NE, 2=SE, 3=S, 4=SW, 5=NW.
##
## Flow direction is encoded by `flow_clockwise` relative to the owning
## hex: from the owner's center looking at edge `e`, the clockwise vertex
## is the corner shared with edge `(e + 1) mod 6`. When `flow_clockwise`
## is true that vertex is downstream; when false, upstream. Combined with
## `edge`, this uniquely identifies the downstream vertex (GDD §3.6.3).


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const EDGE_COUNT := 6

# Axial offsets per edge (flat-top): edge → Vector2i(dq, dr) from this hex
# to the neighbor across that edge.
const EDGE_NEIGHBOR_OFFSETS := [
	Vector2i(0, -1),    # 0 = N
	Vector2i(1, -1),    # 1 = NE
	Vector2i(1, 0),     # 2 = SE
	Vector2i(0, 1),     # 3 = S
	Vector2i(-1, 1),    # 4 = SW
	Vector2i(-1, 0),    # 5 = NW
]

const NAV_NONE := "none"
const NAV_SMALL_CRAFT := "small_craft"
const NAV_RIVER_CRAFT := "river_craft"
const NAV_LARGE_CRAFT := "large_craft"

const CROSSING_NONE := "none"
const CROSSING_BRIDGE := "bridge"
const CROSSING_FORD := "ford"
const CROSSING_FERRY := "ferry"

const VALID_NAVIGABILITY := [
	NAV_NONE, NAV_SMALL_CRAFT, NAV_RIVER_CRAFT, NAV_LARGE_CRAFT,
]
const VALID_CROSSINGS := [
	CROSSING_NONE, CROSSING_BRIDGE, CROSSING_FORD, CROSSING_FERRY,
]


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var hex_q: int = 0
var hex_r: int = 0
var edge: int = 0
var flow_clockwise: bool = true
var navigability: String = NAV_RIVER_CRAFT
var crossing: String = CROSSING_NONE


# ---------------------------------------------------------------------------
# Static helpers
# ---------------------------------------------------------------------------

## Returns Vector2i(dq, dr) from this hex to the neighbor across `edge`.
static func neighbor_offset(e: int) -> Vector2i:
	if e < 0 or e >= EDGE_COUNT:
		return Vector2i.ZERO
	return EDGE_NEIGHBOR_OFFSETS[e]


## Returns the opposite edge index per GDD §3.6: (edge + 3) mod 6.
static func opposite_edge(e: int) -> int:
	return (e + 3) % EDGE_COUNT


## Given two adjacent hex coordinates, returns a Dictionary describing the
## canonical river-edge row that would represent a river between them:
##   {
##     "hex_q":  owner q,
##     "hex_r":  owner r,
##     "edge":   edge index (0..5) on the owner pointing to the non-owner,
##     "adjacent": true if (q1,r1) and (q2,r2) are hex-adjacent, false otherwise
##   }
## Callers should check `adjacent` before using the result. Non-adjacent
## inputs return `{"adjacent": false}` with no other fields set.
static func canonicalize_edge(q1: int, r1: int, q2: int, r2: int) -> Dictionary:
	for i in range(EDGE_COUNT):
		var off: Vector2i = EDGE_NEIGHBOR_OFFSETS[i]
		if q1 + off.x == q2 and r1 + off.y == r2:
			# (q1,r1) → (q2,r2) via edge i. Decide owner by lex order.
			if q1 < q2 or (q1 == q2 and r1 < r2):
				return {
					"hex_q": q1, "hex_r": r1,
					"edge": i,
					"adjacent": true,
				}
			else:
				return {
					"hex_q": q2, "hex_r": r2,
					"edge": opposite_edge(i),
					"adjacent": true,
				}
	return {"adjacent": false}


## Returns true if the owner (hex_q, hex_r) is the lex-lower endpoint of
## the edge — i.e. this row is already canonical.
func is_canonical() -> bool:
	var off: Vector2i = neighbor_offset(edge)
	var neighbor_q: int = hex_q + off.x
	var neighbor_r: int = hex_r + off.y
	return hex_q < neighbor_q or (hex_q == neighbor_q and hex_r < neighbor_r)


## Flip this row so it points the other way along the same physical edge.
## Updates (hex_q, hex_r) to the neighbor and rotates `edge` 180°. Flow
## direction (`flow_clockwise`) is also flipped because the clockwise
## sense reverses when viewed from the opposite center. Navigability and
## crossing are unchanged.
func flip_to_canonical() -> void:
	var off: Vector2i = neighbor_offset(edge)
	hex_q += off.x
	hex_r += off.y
	edge = opposite_edge(edge)
	flow_clockwise = not flow_clockwise


# ---------------------------------------------------------------------------
# Validation + serialization
# ---------------------------------------------------------------------------

func is_valid() -> bool:
	if edge < 0 or edge >= EDGE_COUNT:
		return false
	if not (navigability in VALID_NAVIGABILITY):
		return false
	if not (crossing in VALID_CROSSINGS):
		return false
	return true


## Builds a HexRiverEdgeData from a Dictionary. Accepts either {"hex":[q,r]} or
## explicit "hex_q"/"hex_r" keys; either form is allowed in hand-authored JSON.
static func from_dict(data: Dictionary) -> HexRiverEdgeData:
	var e := HexRiverEdgeData.new()
	if data.has("hex") and data["hex"] is Array and (data["hex"] as Array).size() >= 2:
		var arr: Array = data["hex"]
		e.hex_q = int(arr[0])
		e.hex_r = int(arr[1])
	else:
		e.hex_q = int(data.get("hex_q", 0))
		e.hex_r = int(data.get("hex_r", 0))
	e.edge = int(data.get("edge", 0))
	e.flow_clockwise = bool(data.get("flow_clockwise", true))
	e.navigability = String(data.get("navigability", NAV_RIVER_CRAFT))
	e.crossing = String(data.get("crossing", CROSSING_NONE))
	return e


func to_dict() -> Dictionary:
	return {
		"hex": [hex_q, hex_r],
		"edge": edge,
		"flow_clockwise": flow_clockwise,
		"navigability": navigability,
		"crossing": crossing,
	}
