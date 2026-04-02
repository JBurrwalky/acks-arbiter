class_name IsometricGrid
extends RefCounted

## Pure static utility for diamond (isometric) grid coordinate math.
##
## The coordinate system uses (col, row) integer pairs.
## Isometric screen projection:
##   screen_x = (col - row) * HALF_W
##   screen_y = (col + row) * HALF_H
##
## Used by: DungeonMapController, dungeon_map_renderer, future pathfinding & LOS.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const CELL_W := 64    ## Diamond width in pixels (tip to tip horizontally)
const CELL_H := 32    ## Diamond height in pixels (tip to tip vertically)
const HALF_W := 32
const HALF_H := 16


# ---------------------------------------------------------------------------
# Coordinate conversion
# ---------------------------------------------------------------------------

## Converts grid (col, row) to isometric screen position (centre of diamond).
static func cell_to_screen(col: int, row: int) -> Vector2:
	return Vector2(
		float((col - row) * HALF_W),
		float((col + row) * HALF_H)
	)


## Converts an isometric screen position back to the nearest grid (col, row).
## Uses round() for snapping to nearest integer cell.
static func screen_to_cell(screen_pos: Vector2) -> Vector2i:
	var col := roundf((screen_pos.x / float(HALF_W) + screen_pos.y / float(HALF_H)) / 2.0)
	var row := roundf((screen_pos.y / float(HALF_H) - screen_pos.x / float(HALF_W)) / 2.0)
	return Vector2i(int(col), int(row))


# ---------------------------------------------------------------------------
# Adjacency (4-directional: N/E/S/W in grid space)
# ---------------------------------------------------------------------------

## Returns the 4 orthogonal neighbors of [param pos] in grid space.
## Order: North (0,-1), East (1,0), South (0,1), West (-1,0).
static func get_neighbors(pos: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = [
		Vector2i(pos.x,     pos.y - 1),  # North
		Vector2i(pos.x + 1, pos.y),      # East
		Vector2i(pos.x,     pos.y + 1),  # South
		Vector2i(pos.x - 1, pos.y),      # West
	]
	return result


## Returns true if [param a] and [param b] are orthogonally adjacent (distance == 1).
static func is_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return manhattan_distance(a, b) == 1


## Returns the Manhattan distance between two grid cells.
static func manhattan_distance(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)


# ---------------------------------------------------------------------------
# Range queries
# ---------------------------------------------------------------------------

## Returns all grid cells within [param radius] Manhattan distance of [param center].
## Radius 0 returns only the center cell.
static func get_cells_in_radius(center: Vector2i, radius: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			if abs(dx) + abs(dy) <= radius:
				result.append(Vector2i(center.x + dx, center.y + dy))
	return result
