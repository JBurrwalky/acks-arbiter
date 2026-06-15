class_name WallEdgeResolver
extends RefCounted

## Edge-resolved wall placement (Strategy A — see
## generation/gdd-dungeon-asset-integration-plan.md §3.1).
##
## The voxel data model stores cells as solid or air; walls ARE the solid cells.
## The code-generated renderer draws a cube at each solid cell. Quaternius walls,
## however, are thin slabs designed to sit ON cell edges. So for asset rendering
## we keep the data model untouched and, at render time, walk each FLOORED AIR
## cell's perimeter, emitting one wall record per cardinal edge whose neighbor is
## a solid cell. The solid cell stays a pure passability/LOS blocker; it is no
## longer a render target (fully-interior rock emits nothing — a win, the player
## never sees it).
##
## This class is pure topology (no Godot scene nodes), so it is unit-tested in
## the headless suite. Geometry (world position, rotation) lives in
## DungeonAssetBuilder, which consumes these records.


## Cardinal edge directions. A wall record's `edge_dir` is one of these.
enum EdgeDir { N, S, E, W }

## (col, row) grid offset to the neighbor across each cardinal edge.
## Level is unchanged. Keyed by EdgeDir.
const OFFSETS: Dictionary = {
	EdgeDir.N: Vector2i(0, -1),
	EdgeDir.S: Vector2i(0, 1),
	EdgeDir.E: Vector2i(1, 0),
	EdgeDir.W: Vector2i(-1, 0),
}

## Iteration order for deterministic output.
const _DIRS: Array = [EdgeDir.N, EdgeDir.S, EdgeDir.E, EdgeDir.W]


## Returns wall-edge records for [param level]: one per floored air cell edge
## whose neighbor (same level) is solid. Each record is a Dictionary:
##   {
##     "air_cell":       Vector3i,  # the floored air cell the wall borders
##     "edge_dir":       int,       # EdgeDir (N/S/E/W) — direction to the solid
##     "neighbor_solid": Vector3i,  # the solid cell the wall replaces as render
##   }
## Deterministic: cells in map storage order, edges in N,S,E,W order.
static func resolve_level(map: VoxelMapData, level: int) -> Array:
	var out: Array = []
	if map == null:
		return out
	for cell: VoxelCell in map.get_cells_at_level(level):
		if not _is_floored_air(cell):
			continue
		var p := Vector3i(cell.col, cell.row, level)
		for dir: int in _DIRS:
			var off: Vector2i = OFFSETS[dir]
			var npos := Vector3i(p.x + off.x, p.y + off.y, level)
			if _is_solid(map, npos):
				out.append({
					"air_cell": p,
					"edge_dir": dir,
					"neighbor_solid": npos,
				})
	return out


## A cell that should render a floor (and therefore can border walls): explicitly
## stored air with a real floor. Empty airspace (floor_type == "none") and solid
## rock are excluded.
static func _is_floored_air(cell: VoxelCell) -> bool:
	return cell.solidity == "air" and cell.floor_type != "none"


## True if [param pos] holds an explicitly-stored solid cell. Absent cells are
## treated as open (no wall) — the map author/generator places solids where
## walls belong, matching the code-generated renderer's "walls = solid cells".
static func _is_solid(map: VoxelMapData, pos: Vector3i) -> bool:
	return map.has_cell(pos) and map.get_cell(pos).solidity == "solid"
