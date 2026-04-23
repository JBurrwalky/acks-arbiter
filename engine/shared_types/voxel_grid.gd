class_name VoxelGrid
extends RefCounted

## Static utility for 3D voxel grid coordinate math.
##
## All methods are static. Provides coordinate conversion between the voxel grid
## (col, row, level) and 3D world space, 3D adjacency queries, and distance
## calculations.
##
## COORDINATE CONVENTION:
##   Vector3i(col, row, level) — x=col, y=row, z=level.
##   This extends the existing Vector2i(col, row) pattern with level appended.
##   NOTE: This differs from world-space Vector3 where y=up.
##   Use cell_to_world() / world_to_cell() to convert between the two.
##
## See gdd-voxel-tactical-architecture.md sections 6, 16.9, 17.2.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Each voxel cell is 5 feet on all three axes.
const CELL_SIZE_FEET: int = 5

## World units per cell edge (Godot coordinate space).
const CELL_SIZE: float = 1.0

## Half cell for diamond offset in XZ plane.
const HALF_CELL: float = 0.5


# ---------------------------------------------------------------------------
# Direction enum (horizontal compass, for stairs/ramps)
# ---------------------------------------------------------------------------

## 8-direction compass rose. Offsets match IsometricGrid.get_neighbors() order.
enum Direction { N, NE, E, SE, S, SW, W, NW }

## Direction offsets in (col, row) grid space. Level is unchanged.
const DIRECTION_OFFSETS: Array[Vector2i] = [
	Vector2i(0, -1),   # N
	Vector2i(1, -1),   # NE
	Vector2i(1, 0),    # E
	Vector2i(1, 1),    # SE
	Vector2i(0, 1),    # S
	Vector2i(-1, 1),   # SW
	Vector2i(-1, 0),   # W
	Vector2i(-1, -1),  # NW
]


# ---------------------------------------------------------------------------
# Coordinate conversion
# ---------------------------------------------------------------------------

## Converts voxel grid (col, row, level) to a 3D world position.
## Diamond layout on the XZ plane; Y = level * 1.0.
## Key difference from TacticalGrid3D: level maps 1:1 to world Y (not 0.5).
static func cell_to_world(col: int, row: int, level: int) -> Vector3:
	return Vector3(
		float(col - row) * HALF_CELL,
		float(level) * CELL_SIZE,
		float(col + row) * HALF_CELL
	)


## Converts a 3D world position back to the nearest voxel grid cell.
## Includes the Y component mapped to level.
static func world_to_cell(world_pos: Vector3) -> Vector3i:
	var col := roundf((world_pos.x / HALF_CELL + world_pos.z / HALF_CELL) / 2.0)
	var row := roundf((world_pos.z / HALF_CELL - world_pos.x / HALF_CELL) / 2.0)
	var lvl := roundf(world_pos.y / CELL_SIZE)
	return Vector3i(int(col), int(row), int(lvl))


# ---------------------------------------------------------------------------
# 3D adjacency and distance
# ---------------------------------------------------------------------------

## Returns the 26 neighbors of [param pos] (3x3x3 cube minus center).
## Includes all diagonal, edge, and face neighbors across levels.
static func get_neighbors_3d(pos: Vector3i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for dc in [-1, 0, 1]:
		for dr in [-1, 0, 1]:
			for dl in [-1, 0, 1]:
				if dc == 0 and dr == 0 and dl == 0:
					continue
				out.append(Vector3i(pos.x + dc, pos.y + dr, pos.z + dl))
	return out


## Returns the 8 same-level neighbors of [param pos] (horizontal only).
## Matches IsometricGrid.get_neighbors() order: N, NE, E, SE, S, SW, W, NW.
static func get_neighbors_2d(pos: Vector3i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for offset in DIRECTION_OFFSETS:
		out.append(Vector3i(pos.x + offset.x, pos.y + offset.y, pos.z))
	return out


## Returns true if [param a] and [param b] are adjacent (3D Chebyshev distance
## exactly 1). Same cell returns false.
## This is the single adjacency predicate for melee engagement, inventory
## transfers, and area effects (GDD section 16.9).
static func is_adjacent(a: Vector3i, b: Vector3i) -> bool:
	var d := b - a
	return d != Vector3i.ZERO and abs(d.x) <= 1 and abs(d.y) <= 1 and abs(d.z) <= 1


## Returns the 3D Chebyshev distance between two grid cells.
## Chebyshev = max(|dx|, |dy|, |dz|) — the number of "king moves" in 3D.
static func chebyshev_distance(a: Vector3i, b: Vector3i) -> int:
	var d := b - a
	return maxi(abs(d.x), maxi(abs(d.y), abs(d.z)))


## Returns all cells within [param radius] Chebyshev distance of [param center]
## on the same level, including the center. Used for area placement queries
## (combatant spawning, group scatter, AoE previews).
static func get_cells_in_radius_3d(center: Vector3i, radius: int) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	if radius < 0:
		return out
	for dc in range(-radius, radius + 1):
		for dr in range(-radius, radius + 1):
			out.append(Vector3i(center.x + dc, center.y + dr, center.z))
	return out


# ---------------------------------------------------------------------------
# Direction helpers
# ---------------------------------------------------------------------------

## Returns the (col, row) offset for a compass direction. Level is unchanged.
static func direction_offset(dir: Direction) -> Vector2i:
	return DIRECTION_OFFSETS[dir]


## Steps [param pos] one cell in [param dir] horizontally (level unchanged).
static func step_horizontal(pos: Vector3i, dir: Direction) -> Vector3i:
	var offset := DIRECTION_OFFSETS[dir]
	return Vector3i(pos.x + offset.x, pos.y + offset.y, pos.z)
