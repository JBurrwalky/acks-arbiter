class_name MovementResolver
extends RefCounted

## Voxel-based movement, pathfinding, engagement, and charge/retreat validation.
##
## Construction: `MovementResolver.new(roster)` then `set_voxel_map(voxel_map)`
## once the active battle map is known. When `_voxel_map` is null (pre-grid
## tests, cold init), all spatial queries return graceful defaults so callers
## without a map don't crash.
##
## The 2D-signature public API (`get_grid_position`, `find_path`, `can_reach`,
## `move_along_path`, `get_cells_reachable`, `has_line_of_sight`,
## `validate_charge`, `resolve_fighting_withdrawal`, `resolve_full_retreat`,
## `find_adjacent_cell_to`) survives as thin projection wrappers over the 3D
## voxel primitives. New code should prefer the `*_3d` methods directly.
##
## **Zone of Control.** When [param mover_side] >= 0 is passed to find_path /
## can_reach / move_along_path / get_cells_reachable (or to path_bfs_3d /
## get_cells_reachable_3d directly), cells within the 8-neighbor same-level
## threatened range of any alive enemy combatant act as:
##   - Routing barriers in find_path / can_reach / path_bfs_3d (a ZoC cell
##     may be the destination but NOT a waypoint).
##   - Dead-ends in get_cells_reachable / get_cells_reachable_3d (reachable
##     but not expandable).
##   - Move stoppers in move_along_path (entering a ZoC cell ends movement).
## Default `mover_side = -1` disables ZoC entirely.

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const FEET_PER_CELL := 5
const MIN_CHARGE_CELLS := 4  ## 20 feet minimum for a charge

# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _roster: CombatRoster = null
var _voxel_map: VoxelMapData = null


# ---------------------------------------------------------------------------
# Constructor
# ---------------------------------------------------------------------------

func _init(roster: CombatRoster = null) -> void:
	_roster = roster


# ---------------------------------------------------------------------------
# Grid presence
# ---------------------------------------------------------------------------

func has_grid() -> bool:
	return _voxel_map != null


func has_voxel_grid() -> bool:
	return _voxel_map != null


func set_voxel_map(voxel_map: VoxelMapData) -> void:
	_voxel_map = voxel_map


# ---------------------------------------------------------------------------
# Position accessors
# ---------------------------------------------------------------------------

func get_grid_position(combatant: Combatant) -> Vector2i:
	## Returns the combatant's 2D-projected grid position, or Vector2i(-1,-1)
	## if not placed. Drops the z coordinate — callers that care about level
	## should use get_grid_position_3d().
	if _voxel_map == null:
		return Vector2i(-1, -1)
	var pos3d: Vector3i = _voxel_map.get_entity_pos(combatant.id)
	if pos3d == Vector3i(-1, -1, -1):
		return Vector2i(-1, -1)
	return Vector2i(pos3d.x, pos3d.y)


func set_grid_position(combatant: Combatant, pos: Vector2i) -> void:
	## Updates the combatant's position using a Vector2i input.
	## Preserves the combatant's current z when projecting into Vector3i.
	var z: int = combatant.grid_position.z
	if z < 0:
		z = 0
	var pos3d := Vector3i(pos.x, pos.y, z)
	combatant.grid_position = pos3d
	if _voxel_map != null:
		_voxel_map.set_entity_pos(combatant.id, pos3d)


## Returns the combatant's 3D grid position, or Vector3i(-1,-1,-1) if not placed.
func get_grid_position_3d(combatant: Combatant) -> Vector3i:
	if _voxel_map == null:
		return Vector3i(-1, -1, -1)
	return _voxel_map.get_entity_pos(combatant.id)


## Updates the combatant's 3D grid position.
func set_grid_position_3d(combatant: Combatant, pos: Vector3i) -> void:
	combatant.grid_position = pos
	if _voxel_map != null:
		_voxel_map.set_entity_pos(combatant.id, pos)


# ---------------------------------------------------------------------------
# Distance queries
# ---------------------------------------------------------------------------

func get_distance_cells(a: Combatant, b: Combatant) -> int:
	## 3D Chebyshev distance between two combatants. Returns -1 if no grid.
	if _voxel_map == null:
		return -1
	var pos_a: Vector3i = get_grid_position_3d(a)
	var pos_b: Vector3i = get_grid_position_3d(b)
	if pos_a == Vector3i(-1, -1, -1) or pos_b == Vector3i(-1, -1, -1):
		return -1
	return VoxelGrid.chebyshev_distance(pos_a, pos_b)


func get_distance_ft(a: Combatant, b: Combatant) -> int:
	## Distance in feet between two combatants. Returns -1 if no grid.
	var cells: int = get_distance_cells(a, b)
	if cells < 0:
		return -1
	return cells * FEET_PER_CELL


# ---------------------------------------------------------------------------
# Adjacency and engagement
# ---------------------------------------------------------------------------

func is_adjacent(a: Combatant, b: Combatant) -> bool:
	## True if a and b are in adjacent cells (3D Chebyshev distance == 1).
	return get_distance_cells(a, b) == 1


func get_adjacent_enemies(combatant: Combatant) -> Array[Combatant]:
	## Returns all alive enemies within 3D Chebyshev distance 1.
	var result: Array[Combatant] = []
	if _voxel_map == null or _roster == null:
		return result
	var pos: Vector3i = get_grid_position_3d(combatant)
	if pos == Vector3i(-1, -1, -1):
		return result
	var target_side: int = Combatant.Side.ENEMY if combatant.is_pc_side() else Combatant.Side.PARTY
	for c: Combatant in _roster.get_alive_on_side(target_side):
		var c_pos: Vector3i = get_grid_position_3d(c)
		if c_pos != Vector3i(-1, -1, -1) and VoxelGrid.is_adjacent(pos, c_pos):
			result.append(c)
	return result


func is_engaged(combatant: Combatant) -> bool:
	## True if the combatant has at least one adjacent enemy.
	return not get_adjacent_enemies(combatant).is_empty()


# ---------------------------------------------------------------------------
# Pathfinding — 2D-signature wrappers delegate to path_bfs_3d
# ---------------------------------------------------------------------------

func find_path(
		start: Vector2i,
		goal: Vector2i,
		_exclude_occupied: bool = true,
		max_range: int = 50,
		mover_side: int = -1,
		level_z: int = 0,
		mover_id: String = "") -> Array[Vector2i]:
	## 2D projection of path_bfs_3d. Returns path INCLUDING start and goal,
	## or empty if unreachable. When [param mover_side] >= 0, enemy ZoC cells
	## act as routing barriers (destination allowed, not a waypoint). Pass
	## [param mover_id] to enable B2 occupancy checks (block actives, allow
	## incapacitated pass-through).
	if _voxel_map == null:
		return []
	var start_3d := Vector3i(start.x, start.y, level_z)
	var goal_3d := Vector3i(goal.x, goal.y, level_z)
	var path_3d := path_bfs_3d(
		start_3d, goal_3d, "ground", max_range, mover_side, "strict", mover_id)
	var result: Array[Vector2i] = []
	for p in path_3d:
		result.append(Vector2i(p.x, p.y))
	return result


func can_reach(combatant: Combatant, target_pos: Vector2i, max_cells: int,
		mover_side: int = -1) -> bool:
	## Returns true if combatant can reach target_pos within max_cells steps.
	## When [param mover_side] >= 0, enemy ZoC cells act as routing barriers
	## (destination allowed, not a waypoint). The combatant's own id is
	## passed to path_bfs_3d so B2 occupancy rules apply.
	if _voxel_map == null:
		return true  # No grid = everything reachable
	var start_3d: Vector3i = get_grid_position_3d(combatant)
	if start_3d == Vector3i(-1, -1, -1):
		return true
	var goal_3d := Vector3i(target_pos.x, target_pos.y, start_3d.z)
	var path_3d := path_bfs_3d(
		start_3d, goal_3d, "ground", max_cells + 1, mover_side, "strict",
		combatant.id if combatant != null else "")
	return not path_3d.is_empty() and (path_3d.size() - 1) <= max_cells


# ---------------------------------------------------------------------------
# Movement execution
# ---------------------------------------------------------------------------

func move_along_path(
		combatant: Combatant,
		path: Array[Vector2i],
		max_cells: int,
		mover_side: int = -1) -> int:
	## Move combatant along the given path up to max_cells steps.
	## Returns the number of cells actually moved. When [param mover_side] >= 0,
	## movement stops immediately after entering an enemy ZoC cell (engagement).
	if path.is_empty() or _voxel_map == null:
		return 0
	var enemy_zoc: Dictionary = _build_enemy_zoc_set_3d(mover_side) if mover_side >= 0 else {}
	var cells_moved := 0
	for i in range(1, path.size()):
		if cells_moved >= max_cells:
			break
		set_grid_position(combatant, path[i])
		cells_moved += 1
		if not enemy_zoc.is_empty():
			# ZoC set is keyed by Vector3i; project current cell using the
			# combatant's z (set_grid_position preserved it from the prior step).
			var z: int = combatant.grid_position.z
			if enemy_zoc.has(Vector3i(path[i].x, path[i].y, z)):
				break
	return cells_moved


func get_cells_reachable(combatant: Combatant, max_cells: int,
		mover_side: int = -1) -> Array[Vector2i]:
	## 2D projection of get_cells_reachable_3d. When [param mover_side] >= 0,
	## ZoC cells are reachable but act as dead-ends (no expansion past them).
	if _voxel_map == null:
		return []
	var pos_3d: Vector3i = get_grid_position_3d(combatant)
	if pos_3d == Vector3i(-1, -1, -1):
		return []
	var cells_3d := get_cells_reachable_3d(pos_3d, "ground", max_cells, mover_side)
	var result: Array[Vector2i] = []
	for c3 in cells_3d:
		# Exclude start cell to match the legacy 2D get_cells_reachable behavior
		if c3 == pos_3d:
			continue
		result.append(Vector2i(c3.x, c3.y))
	return result


# ---------------------------------------------------------------------------
# Charge validation
# ---------------------------------------------------------------------------

func validate_charge(attacker: Combatant, target: Combatant) -> Dictionary:
	## Check if a charge from attacker to target is valid.
	## Returns {valid: bool, path: Array[Vector2i], reason: String}.
	if _voxel_map == null:
		# No grid = assume valid charge (pre-grid fallback for tests).
		return {"valid": true, "path": [], "reason": ""}

	var start: Vector2i = get_grid_position(attacker)
	var end: Vector2i = get_grid_position(target)
	if start == Vector2i(-1, -1) or end == Vector2i(-1, -1):
		return {"valid": false, "path": [], "reason": "combatants not placed on grid"}
	if not has_line_of_sight_combatants(attacker, target):
		return {"valid": false, "path": [], "reason": "no line of sight to target"}
	var z: int = attacker.grid_position.z
	var best_adj: Vector2i = _find_best_adjacent_cell_voxel(start, end, z)
	if best_adj == Vector2i(-1, -1):
		return {"valid": false, "path": [], "reason": "no adjacent cell reachable near target"}
	var line_path: Array[Vector2i] = _get_line_cells(start, best_adj)
	for i in range(1, line_path.size()):
		var cell: Vector2i = line_path[i]
		var cell_3d := Vector3i(cell.x, cell.y, z)
		if not _voxel_map.is_passable(cell_3d):
			return {"valid": false, "path": [], "reason": "path blocked at %s" % str(cell)}
		var entities := _voxel_map.get_entities_at(cell_3d)
		for eid: String in entities:
			if eid != attacker.id and eid != target.id:
				return {"valid": false, "path": [], "reason": "path blocked by entity at %s" % str(cell)}
	var charge_distance := line_path.size() - 1
	if charge_distance < MIN_CHARGE_CELLS:
		return {"valid": false, "path": line_path,
			"reason": "too close to charge (need %d+ cells, have %d)" % [MIN_CHARGE_CELLS, charge_distance]}
	var max_charge_cells := attacker.get_combat_movement_cells() * 3
	if charge_distance > max_charge_cells:
		return {"valid": false, "path": line_path,
			"reason": "target too far to charge (max %d cells)" % max_charge_cells}
	return {"valid": true, "path": line_path, "reason": ""}


# ---------------------------------------------------------------------------
# Line of sight
# ---------------------------------------------------------------------------

func has_line_of_sight(from_pos: Vector2i, to_pos: Vector2i) -> bool:
	## 2D-signature LOS. Projects into 3D at z=0 for VoxelLOS; callers that
	## need proper z should use has_los_3d() directly.
	if _voxel_map == null:
		return true
	return has_los_3d(Vector3i(from_pos.x, from_pos.y, 0),
					  Vector3i(to_pos.x, to_pos.y, 0))


## Overload that accepts combatants directly and uses correct z in voxel mode.
func has_line_of_sight_combatants(a: Combatant, b: Combatant) -> bool:
	if _voxel_map == null:
		return true
	return has_los_3d(get_grid_position_3d(a), get_grid_position_3d(b))


# ---------------------------------------------------------------------------
# Defensive movement
# ---------------------------------------------------------------------------

func resolve_fighting_withdrawal(
		combatant: Combatant,
		away_from: Vector2i) -> Vector2i:
	## Move up to half combat movement cells away from the specified position.
	## Returns new 2D position.
	if _voxel_map == null:
		return Vector2i(combatant.grid_position.x, combatant.grid_position.y)
	var start: Vector2i = get_grid_position(combatant)
	if start == Vector2i(-1, -1):
		return start
	var max_cells := combatant.get_combat_movement_cells() / 2
	if max_cells <= 0:
		return start
	var level_z: int = combatant.grid_position.z
	var best_pos := _find_retreat_cell(start, away_from, max_cells, level_z)
	if best_pos != start:
		set_grid_position(combatant, best_pos)
	return best_pos


func resolve_full_retreat(
		combatant: Combatant,
		away_from: Vector2i) -> Vector2i:
	## Move at full combat movement away from the specified position.
	## Returns new 2D position.
	if _voxel_map == null:
		return Vector2i(combatant.grid_position.x, combatant.grid_position.y)
	var start: Vector2i = get_grid_position(combatant)
	if start == Vector2i(-1, -1):
		return start
	var max_cells := combatant.get_combat_movement_cells()
	if max_cells <= 0:
		return start
	var level_z: int = combatant.grid_position.z
	var best_pos := _find_retreat_cell(start, away_from, max_cells, level_z)
	if best_pos != start:
		set_grid_position(combatant, best_pos)
	return best_pos


# ---------------------------------------------------------------------------
# Adjacent cell finding
# ---------------------------------------------------------------------------

func find_adjacent_cell_to(
		mover: Combatant,
		target: Combatant) -> Vector2i:
	## Find the best passable, unoccupied cell adjacent to target that is
	## closest to mover. Returns Vector2i(-1,-1) if none.
	if _voxel_map == null:
		return Vector2i(-1, -1)
	var mover_pos: Vector2i = get_grid_position(mover)
	var target_pos: Vector2i = get_grid_position(target)
	return _find_best_adjacent_cell_voxel(mover_pos, target_pos, mover.grid_position.z)


# ---------------------------------------------------------------------------
# Private helpers (voxel-only)
# ---------------------------------------------------------------------------

func _get_line_cells(from_pos: Vector2i, to_pos: Vector2i) -> Array[Vector2i]:
	## Bresenham-style line from from_pos to to_pos (pure math, no map access).
	var result: Array[Vector2i] = []
	var x0 := from_pos.x
	var y0 := from_pos.y
	var x1 := to_pos.x
	var y1 := to_pos.y
	var dx := absi(x1 - x0)
	var dy := absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx - dy

	while true:
		result.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break
		var e2 := 2 * err
		if e2 > -dy:
			err -= dy
			x0 += sx
		if e2 < dx:
			err += dx
			y0 += sy

	return result


func _find_retreat_cell(
		start: Vector2i,
		away_from: Vector2i,
		max_cells: int,
		level_z: int = 0) -> Vector2i:
	## Same-level BFS that picks the cell within max_cells maximizing Chebyshev
	## distance from away_from. Voxel-only.
	if _voxel_map == null:
		return start

	var occupied: Dictionary = {}
	for eid: String in _voxel_map.entity_positions.keys():
		var epos: Vector3i = _voxel_map.entity_positions[eid]
		var epos_2d := Vector2i(epos.x, epos.y)
		if epos_2d != start:
			occupied[epos_2d] = true

	var visited: Dictionary = {start: 0}
	var queue: Array[Vector2i] = [start]
	var best_pos := start
	var best_dist: int = IsometricGrid.chebyshev_distance(start, away_from)

	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		var current_depth: int = visited[current]
		if current_depth >= max_cells:
			continue
		for neighbor: Vector2i in IsometricGrid.get_neighbors(current):
			if visited.has(neighbor):
				continue
			if not _voxel_map.is_passable(Vector3i(neighbor.x, neighbor.y, level_z)):
				continue
			if occupied.has(neighbor):
				continue
			visited[neighbor] = current_depth + 1
			queue.append(neighbor)
			var dist := IsometricGrid.chebyshev_distance(neighbor, away_from)
			if dist > best_dist:
				best_dist = dist
				best_pos = neighbor

	return best_pos


func _find_best_adjacent_cell_voxel(
		from_pos: Vector2i,
		target_pos: Vector2i,
		level_z: int = 0) -> Vector2i:
	## Returns the passable, unoccupied neighbor of target_pos (on level_z)
	## closest to from_pos. Vector2i(-1, -1) if none.
	if _voxel_map == null:
		return Vector2i(-1, -1)
	var best := Vector2i(-1, -1)
	var best_dist := 999999
	for neighbor: Vector2i in IsometricGrid.get_neighbors(target_pos):
		var neighbor_3d := Vector3i(neighbor.x, neighbor.y, level_z)
		if not _voxel_map.is_passable(neighbor_3d):
			continue
		var entities := _voxel_map.get_entities_at(neighbor_3d)
		var blocked := false
		for eid: String in entities:
			var epos := _voxel_map.get_entity_pos(eid)
			if Vector2i(epos.x, epos.y) == from_pos:
				continue
			blocked = true
			break
		if blocked:
			continue
		var dist := IsometricGrid.chebyshev_distance(from_pos, neighbor)
		if dist < best_dist:
			best_dist = dist
			best = neighbor
	return best


# ---------------------------------------------------------------------------
# 3D voxel primitives
# ---------------------------------------------------------------------------

## 3D BFS pathfinding on VoxelMapData.
## [param movement_type]: "ground", "flying", "tunnel_burrow", "earth_pass", "climbing".
## [param mover_side] (optional, default -1 = ignore ZoC): Combatant.Side value
##   for the mover. When >= 0, cells in enemy ZoC (8 same-level neighbors of
##   alive enemies of the opposite side) act as routing barriers — a ZoC cell
##   may be the destination but NOT a waypoint. Matches ACKS threatened-squares
##   engagement semantics.
## Returns path INCLUDING start and goal, or empty if unreachable.
func path_bfs_3d(from_pos: Vector3i, to_pos: Vector3i,
		movement_type: String = "ground",
		max_range: int = 50,
		mover_side: int = -1,
		passability_mode: String = "strict",
		mover_id: String = "") -> Array[Vector3i]:
	if _voxel_map == null:
		return []
	if from_pos == to_pos:
		return [from_pos]

	var enemy_zoc: Dictionary = _build_enemy_zoc_set_3d(mover_side) if mover_side >= 0 else {}
	var visited: Dictionary = {from_pos: null}  # pos -> predecessor
	var depth: Dictionary = {from_pos: 0}
	var queue: Array[Vector3i] = [from_pos]

	while not queue.is_empty():
		var current: Vector3i = queue.pop_front()
		var current_depth: int = depth[current]
		if current_depth >= max_range:
			continue

		for neighbor: Vector3i in VoxelGrid.get_neighbors_3d(current):
			if visited.has(neighbor):
				continue
			if not _can_enter_3d(current, neighbor, movement_type, passability_mode, mover_id):
				continue
			# ZoC cells can be a destination but not a waypoint.
			if not enemy_zoc.is_empty() and enemy_zoc.has(neighbor) and neighbor != to_pos:
				continue
			# Incapacitated occupants can be walked THROUGH, but you cannot
			# stop on a body — endpoint must be empty or contain only the
			# mover. _can_enter_3d above already permits the pass-through.
			if neighbor == to_pos and mover_id != "" \
					and not _is_legal_endpoint(neighbor, mover_id):
				continue

			visited[neighbor] = current
			depth[neighbor] = current_depth + 1

			if neighbor == to_pos:
				return _reconstruct_path_3d(visited, from_pos, to_pos)
			queue.append(neighbor)

	return []  # Unreachable


## 3D line of sight. Delegates to VoxelLOS.
## Returns true if no voxel map is set (graceful fallback).
func has_los_3d(from_pos: Vector3i, to_pos: Vector3i) -> bool:
	if _voxel_map == null:
		return true
	return VoxelLOS.has_los(_voxel_map, from_pos, to_pos)


## 3D adjacency check. Delegates to VoxelGrid.
func is_adjacent_3d(a: Vector3i, b: Vector3i) -> bool:
	return VoxelGrid.is_adjacent(a, b)


## 3D Chebyshev distance. Delegates to VoxelGrid.
func get_distance_3d(a: Vector3i, b: Vector3i) -> int:
	return VoxelGrid.chebyshev_distance(a, b)


## Walks a straight line of up to max_cells in [param direction] (unit vector
## in grid coords). Stops at the first cell that is not passable OR is occupied
## by an entity not in [param ignore_entity_ids].
##
## Returns a Dictionary with:
##   - cells_traveled: int   — number of cells actually entered
##   - final_pos: Vector3i   — the cell the walker ended on
##   - wall_collision: bool  — true if stopped because the next cell was impassable
##   - entity_collision: bool — true if stopped because the next cell was occupied
##
## Used by ManeuverResolver for force_back and overrun. Internally uses
## path_bfs_3d on each step so the same passability/reachability rules that
## govern normal movement apply.
func walk_direction_3d(
		start: Vector3i,
		direction: Vector3i,
		max_cells: int,
		ignore_entity_ids: Array = []) -> Dictionary:
	var current := start
	var traveled := 0
	var wall := false
	var entity := false
	if _voxel_map == null or max_cells <= 0:
		return {
			"cells_traveled": 0,
			"final_pos": current,
			"wall_collision": false,
			"entity_collision": false,
		}
	for _i in range(max_cells):
		var next := current + direction
		# Reachability via the same BFS primitive used by normal movement.
		# path_bfs_3d returns a 1-step path when next is adjacent and passable.
		var path := path_bfs_3d(current, next, "ground", 1)
		if path.is_empty():
			wall = true
			break
		var occupants := _voxel_map.get_entities_at(next)
		var blocked := false
		for eid: String in occupants:
			if eid in ignore_entity_ids:
				continue
			blocked = true
			break
		if blocked:
			entity = true
			break
		current = next
		traveled += 1
	return {
		"cells_traveled": traveled,
		"final_pos": current,
		"wall_collision": wall,
		"entity_collision": entity,
	}


## Flood-fill BFS returning all cells reachable from [param from_pos]
## within [param max_cells] steps using the given [param movement_type].
## [param mover_side] (optional, default -1 = ignore ZoC): when >= 0, ZoC
##   cells are reachable but act as dead-ends — the flood includes them but
##   does not expand from them (entering costs movement and consumes the turn).
func get_cells_reachable_3d(from_pos: Vector3i,
		movement_type: String, max_cells: int,
		mover_side: int = -1) -> Array[Vector3i]:
	if _voxel_map == null:
		return []
	var enemy_zoc: Dictionary = _build_enemy_zoc_set_3d(mover_side) if mover_side >= 0 else {}
	var visited: Dictionary = {from_pos: 0}
	var queue: Array[Vector3i] = [from_pos]
	var result: Array[Vector3i] = [from_pos]

	while not queue.is_empty():
		var current: Vector3i = queue.pop_front()
		var current_depth: int = visited[current]
		if current_depth >= max_cells:
			continue

		for neighbor: Vector3i in VoxelGrid.get_neighbors_3d(current):
			if visited.has(neighbor):
				continue
			if not _can_enter_3d(current, neighbor, movement_type):
				continue
			visited[neighbor] = current_depth + 1
			result.append(neighbor)
			# ZoC cells are reachable but act as dead-ends — don't expand from them
			if not enemy_zoc.is_empty() and enemy_zoc.has(neighbor):
				continue
			queue.append(neighbor)

	return result


## Returns a Dictionary[Vector3i -> true] of cells threatened by alive enemies
## of the opposite side of [param mover_side]. Uses 2D-flat neighbors (same
## level, 8 cells) per ACKS threatened-squares engagement — cross-level
## engagement via stairs is not modeled. Empty if _roster or _voxel_map is null,
## or if mover_side < 0.
func _build_enemy_zoc_set_3d(mover_side: int) -> Dictionary:
	var zoc: Dictionary = {}
	if mover_side < 0 or _roster == null or _voxel_map == null:
		return zoc
	var enemy_side: int
	if mover_side == Combatant.Side.PARTY:
		enemy_side = Combatant.Side.ENEMY
	else:
		enemy_side = Combatant.Side.PARTY
	for c: Combatant in _roster.get_alive_on_side(enemy_side):
		var c_pos: Vector3i = get_grid_position_3d(c)
		if c_pos == Vector3i(-1, -1, -1):
			continue
		for neighbor: Vector3i in VoxelGrid.get_neighbors_2d(c_pos):
			zoc[neighbor] = true
	return zoc


# ---------------------------------------------------------------------------
# Occupancy checks (B2 — block actives, allow incapacitated pass-through)
# ---------------------------------------------------------------------------

## True when [param pos] is occupied by an entity that should block the
## mover's path step. The mover's own cell never blocks itself; incapacitated
## occupants (dead, unconscious, paralyzed, sleeping) are treated as
## obstacle-free because PCs and monsters can step over downed bodies.
func _is_blocking_occupant(pos: Vector3i, mover_id: String) -> bool:
	if _voxel_map == null:
		return false
	var occupants: Array = _voxel_map.get_entities_at(pos)
	for eid: String in occupants:
		if eid == mover_id:
			continue
		var combatant := _lookup_combatant(eid)
		if combatant == null:
			# Unknown occupant (e.g. a creature token without a roster
			# entry). Treat as blocking — safer than stepping on something
			# we can't reason about.
			return true
		if not _is_incapacitated(combatant):
			return true
	return false


## True when [param pos] is a legal stopping cell for the mover. Empty or
## containing only the mover qualifies; any other occupant — incapacitated
## OR active — blocks. End-of-move occupancy is one combatant per cell
## per ACKS RAW.
func _is_legal_endpoint(pos: Vector3i, mover_id: String) -> bool:
	if _voxel_map == null:
		return true
	var occupants: Array = _voxel_map.get_entities_at(pos)
	for eid: String in occupants:
		if eid != mover_id:
			return false
	return true


## Looks up a combatant by id via the roster, or null if not present.
func _lookup_combatant(entity_id: String) -> Combatant:
	if _roster == null:
		return null
	return _roster.get_by_id(entity_id)


## Per ACKS, "incapacitated" units include the dead, unconscious, paralyzed,
## sleeping, and petrified — anything that would prevent the unit from
## actively defending its tile. Other states (prone, stunned-1-round) leave
## the unit able to react and therefore still block.
static func _is_incapacitated(combatant: Combatant) -> bool:
	if combatant == null:
		return false
	if not combatant.is_alive():
		return true
	for cond: String in ["unconscious", "paralyzed", "sleeping", "petrified"]:
		if combatant.has_condition(cond):
			return true
	return false


# ---------------------------------------------------------------------------
# 3D movement helpers (private)
# ---------------------------------------------------------------------------

## Returns true if [param movement_type] allows moving from [param from_pos]
## to [param to_pos]. [param passability_mode] = "strict" (default) blocks all
## closed doors; "explore" treats closed unlocked doors as walkable so a single
## click can route the party through them (executor pauses 1 round to open).
## When [param mover_id] is non-empty, cells occupied by another *active*
## entity are treated as impassable (incapacitated entities — dead, sleeping,
## paralyzed, unconscious — may be walked through; endpoint legality is a
## separate check in path_bfs_3d).
func _can_enter_3d(from_pos: Vector3i, to_pos: Vector3i,
		movement_type: String,
		passability_mode: String = "strict",
		mover_id: String = "") -> bool:
	if mover_id != "" and _is_blocking_occupant(to_pos, mover_id):
		return false
	var cell := _voxel_map.get_cell(to_pos)
	var level_diff: int = abs(to_pos.z - from_pos.z)

	match movement_type:
		"ground":
			var ground_passable: bool
			if passability_mode == "explore":
				ground_passable = cell.is_walkable_with_open_door()
			else:
				ground_passable = cell.is_passable_by_walker()
			if not ground_passable:
				return false
			if not FallingResolver.has_support(_voxel_map, to_pos):
				return false
			if level_diff == 0:
				return true
			if level_diff == 1:
				return _has_stair_connection(from_pos, to_pos)
			return false  # level diff 2+ blocked for ground

		"flying":
			return not cell.blocks_flight()

		"tunnel_burrow", "earth_pass":
			return not cell.blocks_burrow()

		"climbing":
			if cell.solidity != "air":
				return false
			# Must be adjacent to at least one solid cell (wall face)
			for adj: Vector3i in VoxelGrid.get_neighbors_3d(to_pos):
				if _voxel_map.get_cell(adj).solidity == "solid":
					return true
			return false

		_:
			return false


## Checks if a stair or ramp feature connects [param from_pos] to
## [param to_pos] (which must differ by exactly 1 level).
func _has_stair_connection(from_pos: Vector3i, to_pos: Vector3i) -> bool:
	var going_up: bool = to_pos.z > from_pos.z
	var h_delta := Vector2i(to_pos.x - from_pos.x, to_pos.y - from_pos.y)

	# Find the direction suffix for this horizontal movement
	var suffix := _direction_suffix_for_delta(h_delta)
	if suffix.is_empty():
		# Pure vertical movement (no horizontal delta) — check for ladder
		var from_cell := _voxel_map.get_cell(from_pos)
		var to_cell := _voxel_map.get_cell(to_pos)
		return from_cell.feature == "ladder" or to_cell.feature == "ladder"

	var from_cell := _voxel_map.get_cell(from_pos)
	var to_cell := _voxel_map.get_cell(to_pos)

	if going_up:
		# From cell has stairs_up_<suffix> or ramp_<suffix>
		if from_cell.feature == "stairs_up_" + suffix:
			return true
		if from_cell.feature == "ramp_" + suffix:
			return true
		# To cell has stairs_down_<reverse> (entering from above)
		var rev := _reverse_direction(suffix)
		if to_cell.feature == "stairs_down_" + rev:
			return true
		if to_cell.feature == "ramp_" + rev:
			return true
	else:
		# Going down: from cell has stairs_down_<suffix>
		if from_cell.feature == "stairs_down_" + suffix:
			return true
		if from_cell.feature == "ramp_" + suffix:
			return true
		var rev := _reverse_direction(suffix)
		if to_cell.feature == "stairs_up_" + rev:
			return true
		if to_cell.feature == "ramp_" + rev:
			return true

	return false


## Maps a horizontal delta to its compass direction suffix string.
func _direction_suffix_for_delta(delta: Vector2i) -> String:
	for i in VoxelGrid.DIRECTION_OFFSETS.size():
		if VoxelGrid.DIRECTION_OFFSETS[i] == delta:
			return VoxelGrid.Direction.keys()[i]
	return ""


## Returns the opposite compass direction.
func _reverse_direction(dir: String) -> String:
	const REVERSE := {
		"N": "S", "NE": "SW", "E": "W", "SE": "NW",
		"S": "N", "SW": "NE", "W": "E", "NW": "SE",
	}
	return REVERSE.get(dir, "")


## Reconstructs a path from BFS visited dictionary (3D version).
## visited[start] is null (start has no predecessor); terminate on start, not null,
## because assigning null to a Vector3i-typed variable is a runtime type error.
func _reconstruct_path_3d(visited: Dictionary, start: Vector3i,
		goal: Vector3i) -> Array[Vector3i]:
	var path: Array[Vector3i] = []
	if not visited.has(goal):
		return path
	var current: Vector3i = goal
	path.push_front(current)
	while current != start:
		var prev = visited.get(current)
		if prev == null:
			break
		current = prev
		path.push_front(current)
	return path
