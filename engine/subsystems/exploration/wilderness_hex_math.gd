class_name WildernessHexMath
extends RefCounted

## Shared world-XZ <-> axial(q,r) math for the 3D wilderness renderer
## (gdd-wilderness-hex-3d.md §3.2). One implementation serves three systems:
## the height mesh (vertex placement), the hex-grid overlay shader, and picking.
##
## Layout: FLAT-TOP hexes, axial coordinates, **1 hex neighbour spacing = 1.0
## world unit** (the §6 anchor that keeps a 60x45 map's ortho camera size far
## under the 16384 clamp). Applying the flat-top axial pixel formula to the
## project's axial keys reproduces the SAME even-q offset rectangle the 2D
## renderer draws (a stored offset-rectangle renders as a clean rectangle),
## because HexMapController.axial_to_godot_map IS the even-q offset transform —
## so world XZ, the field-cell grid, and the 2D map all stay consistent.
##
## Field-cell mapping (height sampling) is SEPARATE and routes through
## HexMapController.axial_to_godot_map (== WorldGrid.axial_to_offset), the exact
## mapping region_zoom_in.gd used to sample the 6-mile children.

const SQRT3 := 1.7320508075688772
## center->corner radius; neighbour spacing = SQRT3 * HEX_RADIUS = 1.0 world unit.
const HEX_RADIUS := 0.5773502691896258  # 1/sqrt(3)


## Axial (q,r) -> world XZ (Vector2 = (x, z)). Flat-top, 1-unit neighbour spacing.
static func axial_to_world(coord: Vector2i) -> Vector2:
	var x := HEX_RADIUS * 1.5 * float(coord.x)
	var z := HEX_RADIUS * SQRT3 * (float(coord.y) + float(coord.x) * 0.5)
	return Vector2(x, z)


## World XZ -> nearest axial (q,r). Inverse of axial_to_world + cube rounding.
static func world_to_axial(world_xz: Vector2) -> Vector2i:
	var qf := (2.0 / 3.0 * world_xz.x) / HEX_RADIUS
	var rf := (-1.0 / 3.0 * world_xz.x + SQRT3 / 3.0 * world_xz.y) / HEX_RADIUS
	return _cube_round(qf, rf)


## The 6 corner offsets (XZ, world units) of a flat-top hex relative to its
## center, in canonical order matching HexRiverEdgeData edge indexing is NOT
## assumed here — these are geometric corners for mesh building (angle 0,60,...).
static func corner_offsets() -> Array:
	var out: Array = []
	for i in range(6):
		# Flat-top: corner angles at 0, 60, 120, ... degrees from +X.
		var ang := deg_to_rad(60.0 * float(i))
		out.append(Vector2(HEX_RADIUS * cos(ang), HEX_RADIUS * sin(ang)))
	return out


## Axial cube rounding (redblobgames). qf/rf are fractional axial.
static func _cube_round(qf: float, rf: float) -> Vector2i:
	var xf := qf
	var zf := rf
	var yf := -xf - zf
	var rx := roundi(xf)
	var ry := roundi(yf)
	var rz := roundi(zf)
	var dx := absf(float(rx) - xf)
	var dy := absf(float(ry) - yf)
	var dz := absf(float(rz) - zf)
	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dy > dz:
		ry = -rx - rz
	else:
		rz = -rx - ry
	return Vector2i(rx, rz)
