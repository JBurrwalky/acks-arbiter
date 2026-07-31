class_name CreatureFootprint
extends RefCounted

## Rotating multi-cell footprint geometry for creatures larger than 1x1.
##
## A creature stores ONE anchor cell (`Combatant.grid_position` /
## `VoxelMapData.entity_positions[id]`). Its full set of occupied cells is DERIVED
## from that anchor, its facing, and its local-frame footprint
## `Vector2i(length, width)` (see CreatureSize). This keeps the single-anchor
## contract every other subsystem reads intact while letting big creatures span
## several cells.
##
## Frame convention (grid space, x=col, y=row):
##   - The anchor is the REAR-CENTER cell — always occupied (so `grid_position`
##     is a real body cell). The body extends `length` cells FORWARD along the
##     facing axis and `width` cells ACROSS it.
##   - Facing is SNAPPED to its dominant cardinal grid axis, so the occupied
##     region is always an axis-aligned rectangle. A quarter-turn therefore flips
##     a 2x1 into a 1x2 — the "footprint rotates with facing" rule.
##   - Even widths bias one cell to the right of the facing (documented, so the
##     geometry is deterministic).
##
## All methods static.


## Snaps an arbitrary facing to a unit forward step along the dominant cardinal
## grid axis. Zero facing defaults to east (1, 0). Diagonal facings resolve to
## their larger component (ties → the column axis).
static func snap_forward(facing: Vector2i) -> Vector2i:
	if facing == Vector2i.ZERO:
		return Vector2i(1, 0)
	if abs(facing.x) >= abs(facing.y):
		return Vector2i(signi(facing.x) if facing.x != 0 else 1, 0)
	return Vector2i(0, signi(facing.y))


## The (dcol, drow) offsets from the anchor for every occupied cell, in the
## snapped frame. Length 1 x width 1 returns exactly [(0, 0)].
static func occupied_offsets(facing: Vector2i, local: Vector2i) -> Array[Vector2i]:
	var length: int = maxi(1, local.x)
	var width: int = maxi(1, local.y)
	var forward := snap_forward(facing)
	var right := Vector2i(-forward.y, forward.x)  # 90° rotation in the col/row plane
	var across_shift: int = width / 2  # integer floor — even widths bias to +right
	var out: Array[Vector2i] = []
	for i in range(length):
		for j in range(width):
			out.append(forward * i + right * (j - across_shift))
	return out


## The full set of occupied cells for a creature anchored at [param anchor],
## facing [param facing], with local footprint [param local] (length, width).
## Cells share the anchor's level (footprints do not span levels in v1).
static func cells(anchor: Vector3i, facing: Vector2i, local: Vector2i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for off in occupied_offsets(facing, local):
		out.append(Vector3i(anchor.x + off.x, anchor.y + off.y, anchor.z))
	return out


## True when [param local] describes a single-cell (1x1) footprint. Callers use
## this to keep the fast single-cell path for the overwhelming majority of
## creatures (all PCs/henchmen and man-sized-or-smaller monsters).
static func is_single_cell(local: Vector2i) -> bool:
	return maxi(1, local.x) == 1 and maxi(1, local.y) == 1


## The cells a swarm's DIFFUSE area covers (RAW 10'x30', HD-scaled — see
## Combatant.get_swarm_area_local + coding_conventions §126). A swarm is NOT a
## solid body: it still stores ONE anchor cell and moves as a 1x1 mover (it is
## never routed through `footprint_can_occupy`), but it ENVELOPS every creature
## standing in the rectangle its area covers. Geometrically the area is the same
## rear-center-anchored, facing-oriented rectangle a footprint uses, so this is a
## thin, self-documenting alias over [method cells] — the SEPARATE name keeps the
## "solid footprint" vs "enveloping area" distinction explicit at every call
## site (the swarm subsystem never confuses the two).
static func area_cells(anchor: Vector3i, facing: Vector2i, area_local: Vector2i) -> Array[Vector3i]:
	return cells(anchor, facing, area_local)


## The world-space centroid of the footprint, for placing/scaling the render
## token so it straddles all its cells rather than sitting on the anchor corner.
## Averages the world positions of the occupied cells.
static func world_center(anchor: Vector3i, facing: Vector2i, local: Vector2i) -> Vector3:
	var sum := Vector3.ZERO
	var body := cells(anchor, facing, local)
	for c in body:
		sum += VoxelGrid.cell_to_world(c.x, c.y, c.z)
	return sum / float(body.size())


## The world-space span (x, z extents in world units) the footprint covers, for
## scaling the token mesh. Returns Vector2(x_extent, z_extent); a 1x1 footprint
## returns roughly (1, 1) cell-widths worth of span.
static func world_span(anchor: Vector3i, facing: Vector2i, local: Vector2i) -> Vector2:
	var body := cells(anchor, facing, local)
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for c in body:
		var w := VoxelGrid.cell_to_world(c.x, c.y, c.z)
		min_x = minf(min_x, w.x)
		max_x = maxf(max_x, w.x)
		min_z = minf(min_z, w.z)
		max_z = maxf(max_z, w.z)
	# Each cell centre is HALF_CELL from its edges; add one cell width so a single
	# cell reads as a full cell span, not zero.
	return Vector2((max_x - min_x) + VoxelGrid.CELL_SIZE, (max_z - min_z) + VoxelGrid.CELL_SIZE)
