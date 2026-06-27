class_name CliffDetector
extends RefCounted

## Derives cliff / canyon EDGES from a materialized 6-mile play grid (gdd-cliffs-canyons.md
## §4). At 6-mile resolution 1 hex = 1 GeoField cell (CELL_MILES = 6), so a hex's
## `elevation_raw` IS its field-cell surface — the same height the 3D renderer draws — and a
## cliff edge is simply a cross-edge height delta ≥ CLIFF_DELTA. A cliff whose LOW side
## carries a river is a `canyon` (the floor of a river-incised gorge). Ocean coasts are
## skipped (beaches, not cliffs); lake rims and steep mountain/escarpment edges qualify.
##
## NOTE: at 6-mile scale every cliff is a major escarpment (thousands of feet) — there are no
## small wilderness cliffs, so party climbing (§5) is effectively route-around here. The
## SHEER_SURFACE_CLIMB reuse for smaller DUNGEON walls is where the climb mechanic shines.

# Raw elevation (0-1) → feet: ~7,778 m per raw unit (climate lapse) × 3.281 ft/m.
const RAW_TO_FEET := 25524.0

# ADAPTIVE cliff threshold (gdd §4). A fixed absolute cutoff is map-size dependent — larger
# maps build steeper relief, so 0.12 gave a Large map ~51 cliffs while a Medium map's STEEPEST
# edge was only 0.11 (=> zero cliffs). Instead take the steepest CLIFF_PERCENTILE of a map's
# own land edges, so cliff DENSITY is consistent at any size — but never below CLIFF_DELTA_FLOOR
# so a genuinely flat map stays cliff-free.
const CLIFF_PERCENTILE := 0.97    # top ~3% of land edges by cross-edge delta
const CLIFF_DELTA_FLOOR := 0.07   # ~1,800 ft; no edge below this is ever a cliff


## Detect cliff/canyon edges. [param grid]: Vector2i → {elevation_raw: float, water: String}
## (extra keys ignored, so child dicts pass straight through). [param river_hexes]: a set
## (Vector2i → true) of hexes a river touches. [param threshold_override]: pin the cutoff for
## tests (< 0 = use the adaptive threshold). Returns Array[HexCliffEdgeData], canonical.
static func detect(grid: Dictionary, river_hexes: Dictionary, threshold_override: float = -1.0) -> Array:
	# Pass 1: every land-land boundary (once, from the lex-lower hex) + its delta.
	var edges: Array = []
	var deltas: Array = []
	for a: Vector2i in grid.keys():
		var ha: Dictionary = grid[a]
		if str(ha.get("water", "")) == "ocean":
			continue
		var ea := float(ha.get("elevation_raw", 0.0))
		for e in range(6):
			var b: Vector2i = a + HexCliffEdgeData.neighbor_offset(e)
			if not grid.has(b):
				continue
			if not (a.x < b.x or (a.x == b.x and a.y < b.y)):
				continue
			var hb: Dictionary = grid[b]
			if str(hb.get("water", "")) == "ocean":
				continue
			var eb := float(hb.get("elevation_raw", 0.0))
			var d := absf(ea - eb)
			edges.append({"a": a, "b": b, "ea": ea, "eb": eb, "delta": d})
			deltas.append(d)
	if edges.is_empty():
		return []
	# Adaptive cutoff (or the test override).
	var threshold: float
	if threshold_override >= 0.0:
		threshold = threshold_override
	else:
		deltas.sort()
		var idx: int = clampi(int(CLIFF_PERCENTILE * float(deltas.size())), 0, deltas.size() - 1)
		threshold = maxf(CLIFF_DELTA_FLOOR, float(deltas[idx]))
	# Pass 2: build cliff edges at/above the cutoff.
	var out: Array = []
	for rec: Dictionary in edges:
		if float(rec["delta"]) < threshold:
			continue
		var a: Vector2i = rec["a"]
		var b: Vector2i = rec["b"]
		var ea2 := float(rec["ea"])
		var eb2 := float(rec["eb"])
		var high: Vector2i = a if ea2 > eb2 else b
		var low: Vector2i = b if ea2 > eb2 else a
		var height_ft: int = roundi(float(rec["delta"]) * RAW_TO_FEET)
		var ctype: String = HexCliffEdgeData.CANYON if river_hexes.has(low) else HexCliffEdgeData.CLIFF
		var cliff := HexCliffEdgeData.make(high, low, height_ft, ctype)
		if cliff != null:
			out.append(cliff)
	return out
