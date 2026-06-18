class_name WorldGrid
extends RefCounted

## Canonical world-grid geometry for the setting generator (rectangle worlds).
##
## The generator lays its hexes on an OFFSET-rectangle (a clean col x row grid),
## stored as axial (q, r). The shared even-q render transform
## HexMapController.axial_to_godot_map(q, r) = (q, r + (q - (q & 1)) / 2) is the
## EXACT inverse of the offset->axial conversion used here, so a stored
## offset-rectangle renders as a clean RECTANGLE on every map (setting-review,
## the 24-mile world-map screen, and the 6-mile play map) while faithful axial
## adjacency (the _OFF neighbour deltas) is unchanged. (The old generator stored
## an axial-rectangle q in [0,W) x r in [0,H), which the same transform sheared
## into a parallelogram.)
##
## IMPORTANT: latitude / "visual row" / north-south semantics must be derived from
## the OFFSET row, NOT from axial r. Under this layout a constant axial r is no
## longer a constant visual row (the even-q transform staggers columns), so
## reading semantics off raw r would shear the map. Use enumerate()'s `row`.
##
## Coordinate transforms route through HexMapController so generation and the
## renderers share ONE even-q definition and can never drift.


## col/row (even-q offset) -> axial (q, r). q is 0..W-1; r is sheared and may be
## NEGATIVE for high columns (acceptable: storage is INTEGER, adjacency is
## label-agnostic, runtime bounds are dictionary membership, and the renderers
## measure their own pixel extent). Pre-launch we may shift all coords positive.
static func offset_to_axial(col: int, row: int) -> Vector2i:
	return HexMapController.godot_map_to_axial(Vector2i(col, row))


## axial (q, r) -> col/row (even-q offset). Inverse of offset_to_axial.
static func axial_to_offset(key: Vector2i) -> Vector2i:
	return HexMapController.axial_to_godot_map(key)


## Enumerate the width x height offset-rectangle. Returns an Array of
##   {"key": Vector2i (axial), "col": int, "row": int}
## sorted in canonical (r ASC, q ASC) order — the order shared by
## SettingRepository.list_hexes and the replay-frame RLE. Every generation layer
## should iterate THIS rather than `for r in range(H): for q in range(W)` so it
## covers exactly the stored key set (sheared in axial space, possibly negative r)
## and feeds any seeded sequential draw a deterministic order.
static func enumerate(width: int, height: int) -> Array:
	var cells: Array = []
	for row in range(height):
		for col in range(width):
			cells.append({"key": offset_to_axial(col, row), "col": col, "row": row})
	cells.sort_custom(_canonical_less_entry)
	return cells


## Canonical (r ASC, q ASC) comparator over axial keys — matches
## HistorySimulator._canonical_less and SettingRepository's list order.
static func canonical_less(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)


static func _canonical_less_entry(a: Dictionary, b: Dictionary) -> bool:
	return canonical_less(a["key"], b["key"])
