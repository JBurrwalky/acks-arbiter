class_name VoxelLOS
extends RefCounted

## 3D line-of-sight raycast on the voxel grid.
##
## Uses a 3D DDA (Digital Differential Analyzer) algorithm to walk a ray from
## the center of one cell to the center of another, checking each intermediate
## cell for LOS obstruction via VoxelCell.blocks_los().
##
## Start and end cells are NOT checked — only intermediate cells along the ray.
## Absent cells (not in the map) use the sentinel default (air/open) which does
## not block LOS.
##
## See gdd-voxel-tactical-architecture.md section 15.


## Returns true if there is a clear line of sight from [param from_pos] to
## [param to_pos] on [param map].
static func has_los(map: VoxelMapData, from_pos: Vector3i, to_pos: Vector3i) -> bool:
	if from_pos == to_pos:
		return true

	var cells := _walk_ray(from_pos, to_pos)
	for cell_pos: Vector3i in cells:
		if map.get_cell(cell_pos).blocks_los():
			return false
	return true


## Returns the maximum cover value of any intermediate cell along the ray from
## [param from_pos] to [param to_pos]. Returns 0 if no intermediate cells
## provide cover.
static func get_cover_value(map: VoxelMapData, from_pos: Vector3i, to_pos: Vector3i) -> int:
	if from_pos == to_pos:
		return 0

	var max_cover: int = 0
	var cells := _walk_ray(from_pos, to_pos)
	for cell_pos: Vector3i in cells:
		var cv: int = map.get_cell(cell_pos).cover_value
		if cv > max_cover:
			max_cover = cv
	return max_cover


## Walks a 3D DDA ray from [param from_pos] to [param to_pos] and returns
## the list of intermediate cell positions (excluding start and end).
##
## Uses the Amanatides-Woo algorithm: for each axis, track how far along the
## ray we must travel to cross the next cell boundary. Step in the axis with
## the smallest t value.
static func _walk_ray(from_pos: Vector3i, to_pos: Vector3i) -> Array[Vector3i]:
	var result: Array[Vector3i] = []

	var dx: int = to_pos.x - from_pos.x
	var dy: int = to_pos.y - from_pos.y
	var dz: int = to_pos.z - from_pos.z

	var step_x: int = 1 if dx > 0 else (-1 if dx < 0 else 0)
	var step_y: int = 1 if dy > 0 else (-1 if dy < 0 else 0)
	var step_z: int = 1 if dz > 0 else (-1 if dz < 0 else 0)

	# Length of ray direction vector for normalization
	var length := sqrt(float(dx * dx + dy * dy + dz * dz))
	if length < 0.0001:
		return result

	# t_delta: how much t increases to cross one full cell on each axis
	# t_max: the t value at which we cross the NEXT cell boundary on each axis
	# INF for axes with no movement (ray is parallel to that axis)
	var t_max_x: float = INF
	var t_max_y: float = INF
	var t_max_z: float = INF
	var t_delta_x: float = INF
	var t_delta_y: float = INF
	var t_delta_z: float = INF

	if dx != 0:
		t_delta_x = length / absf(float(dx))
		# Distance from cell center to first boundary crossing
		t_max_x = t_delta_x * 0.5
	if dy != 0:
		t_delta_y = length / absf(float(dy))
		t_max_y = t_delta_y * 0.5
	if dz != 0:
		t_delta_z = length / absf(float(dz))
		t_max_z = t_delta_z * 0.5

	var cx: int = from_pos.x
	var cy: int = from_pos.y
	var cz: int = from_pos.z

	# Walk until we reach the target cell.
	# Safety limit to avoid infinite loops.
	var max_steps: int = abs(dx) + abs(dy) + abs(dz) + 1

	for _i in range(max_steps):
		# Step in the axis with the smallest t_max
		if t_max_x <= t_max_y and t_max_x <= t_max_z:
			cx += step_x
			t_max_x += t_delta_x
		elif t_max_y <= t_max_z:
			cy += step_y
			t_max_y += t_delta_y
		else:
			cz += step_z
			t_max_z += t_delta_z

		# Check if we've reached the target
		if cx == to_pos.x and cy == to_pos.y and cz == to_pos.z:
			break

		result.append(Vector3i(cx, cy, cz))

	return result
