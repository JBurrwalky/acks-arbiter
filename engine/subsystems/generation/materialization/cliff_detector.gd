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

# Cross-edge raw delta at/above which a boundary is a cliff. Calibrated against the play
# grid's land-edge delta distribution (gdd §4): 0.12 ≈ 3,000 ft ≈ the top ~1.7% of land
# edges — dramatic escarpments + canyon walls, not every steep slope. Tunable.
const CLIFF_DELTA := 0.12


## Detect cliff/canyon edges. [param grid]: Vector2i → {elevation_raw: float, water: String}
## (extra keys ignored, so child dicts pass straight through). [param river_hexes]: a set
## (Vector2i → true) of hexes a river touches. Returns Array[HexCliffEdgeData], canonical,
## one per steep boundary.
static func detect(grid: Dictionary, river_hexes: Dictionary) -> Array:
	var out: Array = []
	for a: Vector2i in grid.keys():
		var ha: Dictionary = grid[a]
		if str(ha.get("water", "")) == "ocean":
			continue
		var ea := float(ha.get("elevation_raw", 0.0))
		for e in range(6):
			var b: Vector2i = a + HexCliffEdgeData.neighbor_offset(e)
			if not grid.has(b):
				continue
			# Process each boundary once, from its lex-lower hex.
			if not (a.x < b.x or (a.x == b.x and a.y < b.y)):
				continue
			var hb: Dictionary = grid[b]
			if str(hb.get("water", "")) == "ocean":
				continue
			var eb := float(hb.get("elevation_raw", 0.0))
			var delta := absf(ea - eb)
			if delta < CLIFF_DELTA:
				continue
			var high: Vector2i = a if ea > eb else b
			var low: Vector2i = b if ea > eb else a
			var height_ft: int = roundi(delta * RAW_TO_FEET)
			var ctype: String = HexCliffEdgeData.CANYON if river_hexes.has(low) else HexCliffEdgeData.CLIFF
			var cliff := HexCliffEdgeData.make(high, low, height_ft, ctype)
			if cliff != null:
				out.append(cliff)
	return out
