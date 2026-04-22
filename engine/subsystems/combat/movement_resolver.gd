class_name MovementResolver
extends RefCounted

## Grid-based movement, pathfinding, engagement, and charge/retreat validation.
##
## When _map is null (no grid), all spatial queries return graceful defaults
## so pre-grid combat works identically to Sessions 1-3.

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const FEET_PER_CELL := 5
const MIN_CHARGE_CELLS := 4  ## 20 feet minimum for a charge

# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _map: TacticalMapData = null
var _roster: CombatRoster = null
var _voxel_map: VoxelMapData = null


# ---------------------------------------------------------------------------
# Constructor
# ---------------------------------------------------------------------------

## [param map] may be null when operating in voxel-only mode (set_voxel_map called after).
func _init(map: TacticalMapData = null, roster: CombatRoster = null) -> void:
	_map = map
	_roster = roster


# ---------------------------------------------------------------------------
# Grid presence
# ---------------------------------------------------------------------------

func has_grid() -> bool:
	return _map != null or _voxel_map != null


# ---------------------------------------------------------------------------
# Position accessors
# ---------------------------------------------------------------------------

func get_grid_position(combatant: Combatant) -> Vector2i:
	## Returns the combatant's grid position, or Vector2i(-1,-1) if not placed.
	## In voxel mode, projects the 3D position to 2D (x, y).
	if _voxel_map != null:
		var pos3d: Vector3i = _voxel_map.get_entity_pos(combatant.id)
		if pos3d == Vector3i(-1, -1, -1):
			return Vector2i(-1, -1)
		return Vector2i(pos3d.x, pos3d.y)
	if _map == null:
		return Vector2i(-1, -1)
	return _map.get_entity_pos(combatant.id)


func set_grid_position(combatant: Combatant, pos: Vector2i) -> void:
	## Updates both the combatant field and map entity tracking.
	## In voxel mode, also updates VoxelMapData and grid_position_3d (preserving z).
	combatant.grid_position = pos
	if _voxel_map != null:
		var z: int = combatant.grid_position_3d.z
		var pos3d := Vector3i(pos.x, pos.y, z)
		combatant.grid_position_3d = pos3d
		_voxel_map.set_entity_pos(combatant.id, pos3d)
	elif _map != null:
		_map.set_entity_pos(combatant.id, pos)


## Returns the combatant's 3D grid position, or Vector3i(-1,-1,-1) if not placed.
func get_grid_position_3d(combatant: Combatant) -> Vector3i:
	if _voxel_map == null:
		return Vector3i(-1, -1, -1)
	return _voxel_map.get_entity_pos(combatant.id)


## Updates the combatant's position in 3D and syncs the 2D projection.
func set_grid_position_3d(combatant: Combatant, pos: Vector3i) -> void:
	combatant.grid_position_3d = pos
	combatant.grid_position = Vector2i(pos.x, pos.y)
	if _voxel_map != null:
		_voxel_map.set_entity_pos(combatant.id, pos)


# ---------------------------------------------------------------------------
# Distance queries
# ---------------------------------------------------------------------------

func get_distance_cells(a: Combatant, b: Combatant) -> int:
	## Chebyshev distance between two combatants. Returns -1 if no grid.
	## In voxel mode, uses 3D Chebyshev distance.
	if _voxel_map != null:
		var pos_a: Vector3i = get_grid_position_3d(a)
		var pos_b: Vector3i = get_grid_position_3d(b)
		if pos_a == Vector3i(-1, -1, -1) or pos_b == Vector3i(-1, -1, -1):
			return -1
		return VoxelGrid.chebyshev_distance(pos_a, pos_b)
	if _map == null:
		return -1
	var pos_a: Vector2i = get_grid_position(a)
	var pos_b: Vector2i = get_grid_position(b)
	if pos_a == Vector2i(-1, -1) or pos_b == Vector2i(-1, -1):
		return -1
	return IsometricGrid.chebyshev_distance(pos_a, pos_b)


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
	## True if a and b are in adjacent cells (Chebyshev distance == 1).
	return get_distance_cells(a, b) == 1


func get_adjacent_enemies(combatant: Combatant) -> Array[Combatant]:
	## Returns all alive enemies adjacent to this combatant.
	## In voxel mode, uses 3D adjacency via VoxelGrid.
	var result: Array[Combatant] = []
	if _voxel_map != null:
		var pos: Vector3i = get_grid_position_3d(combatant)
		if pos == Vector3i(-1, -1, -1):
			return result
		var target_side: int
		if combatant.is_pc_side():
			target_side = Combatant.Side.ENEMY
		else:
			target_side = Combatant.Side.PARTY
		for c: Combatant in _roster.get_alive_on_side(target_side):
			var c_pos: Vector3i = get_grid_position_3d(c)
			if c_pos != Vector3i(-1, -1, -1) and VoxelGrid.is_adjacent(pos, c_pos):
				result.append(c)
		return result
	if _map == null:
		return result
	var pos: Vector2i = get_grid_position(combatant)
	if pos == Vector2i(-1, -1):
		return result
	var target_side: int
	if combatant.is_pc_side():
		target_side = Combatant.Side.ENEMY
	else:
		target_side = Combatant.Side.PARTY
	for c: Combatant in _roster.get_alive_on_side(target_side):
		var c_pos: Vector2i = get_grid_position(c)
		if c_pos != Vector2i(-1, -1) and IsometricGrid.chebyshev_distance(pos, c_pos) == 1:
			result.append(c)
	return result


func is_engaged(combatant: Combatant) -> bool:
	## True if the combatant has at least one adjacent enemy.
	return not get_adjacent_enemies(combatant).is_empty()


# ---------------------------------------------------------------------------
# Pathfinding (BFS)
# ---------------------------------------------------------------------------

func find_path(
		start: Vector2i,
		goal: Vector2i,
		exclude_occupied: bool = true,
		max_range: int = 50,
		mover_side: int = -1,
		level_z: int = 0) -> Array[Vector2i]:
	## BFS shortest path from start to goal on passable cells.
	## Returns the path INCLUDING start and goal, or empty if unreachable.
	## [param max_range] caps the BFS depth to avoid expensive searches.
	## [param mover_side] when >= 0, enemy ZoC cells block routing (except as goal).
	## [param level_z] z-level for voxel mode pathfinding.
	# --- Voxel path: delegate to 3D BFS and project result to 2D ---
	if _voxel_map != null:
		var start_3d := Vector3i(start.x, start.y, level_z)
		var goal_3d := Vector3i(goal.x, goal.y, level_z)
		var path_3d := path_bfs_3d(start_3d, goal_3d, "ground", max_range)
		var result: Array[Vector2i] = []
		for p in path_3d:
			result.append(Vector2i(p.x, p.y))
		return result
	if _map == null:
		return []
	if not _map.has_cell(start) or not _map.has_cell(goal):
		return []
	if start == goal:
		return [start]

	# Build occupied set (excluding start and goal positions)
	var occupied: Dictionary = {}
	if exclude_occupied:
		for eid: String in _map.entity_positions.keys():
			var epos: Vector2i = _map.entity_positions[eid]
			if epos != start and epos != goal:
				occupied[epos] = true

	# Build enemy ZoC set (cells adjacent to enemies of mover_side)
	var enemy_zoc: Dictionary = _build_enemy_zoc_set(mover_side) if mover_side >= 0 else {}

	var visited: Dictionary = {start: null}  # pos -> predecessor
	var queue: Array[Vector2i] = [start]
	var depth: Dictionary = {start: 0}

	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		var current_depth: int = depth[current]
		if current_depth >= max_range:
			continue

		for neighbor: Vector2i in IsometricGrid.get_neighbors(current):
			if visited.has(neighbor):
				continue
			if not _map.is_passable(neighbor):
				continue
			if occupied.has(neighbor) and neighbor != goal:
				continue
			# ZoC cells can be a destination but not a waypoint
			if not enemy_zoc.is_empty() and enemy_zoc.has(neighbor) and neighbor != goal:
				continue

			visited[neighbor] = current
			depth[neighbor] = current_depth + 1

			if neighbor == goal:
				# Reconstruct path
				return _reconstruct_path(visited, start, goal)
			queue.append(neighbor)

	return []  # Unreachable


func can_reach(combatant: Combatant, target_pos: Vector2i, max_cells: int,
		mover_side: int = -1) -> bool:
	## Returns true if combatant can reach target_pos within max_cells steps.
	## [param mover_side] when >= 0, enemy ZoC cells block routing (except as destination).
	if _voxel_map != null:
		var start_3d: Vector3i = get_grid_position_3d(combatant)
		if start_3d == Vector3i(-1, -1, -1):
			return true
		var goal_3d := Vector3i(target_pos.x, target_pos.y, start_3d.z)
		var path_3d := path_bfs_3d(start_3d, goal_3d, "ground", max_cells + 1)
		return not path_3d.is_empty() and (path_3d.size() - 1) <= max_cells
	if _map == null:
		return true  # No grid = everything reachable
	var start: Vector2i = get_grid_position(combatant)
	if start == Vector2i(-1, -1):
		return true
	var path: Array[Vector2i] = find_path(start, target_pos, true, max_cells + 1, mover_side)
	# Path includes start, so actual steps = path.size() - 1
	return not path.is_empty() and (path.size() - 1) <= max_cells


# ---------------------------------------------------------------------------
# Movement execution
# ---------------------------------------------------------------------------

func move_along_path(
		combatant: Combatant,
		path: Array[Vector2i],
		max_cells: int,
		mover_side: int = -1) -> int:
	## Move combatant along the given path up to max_cells steps.
	## Updates grid positions. Returns the number of cells actually moved.
	## [param mover_side] when >= 0, movement stops upon entering an enemy ZoC cell.
	if path.is_empty():
		return 0
	# In voxel mode, set_grid_position handles syncing 3D position
	if _voxel_map != null:
		var cells_moved := 0
		for i in range(1, path.size()):
			if cells_moved >= max_cells:
				break
			set_grid_position(combatant, path[i])
			cells_moved += 1
		return cells_moved
	if _map == null:
		return 0
	var enemy_zoc: Dictionary = _build_enemy_zoc_set(mover_side) if mover_side >= 0 else {}
	var cells_moved := 0
	# Path[0] is current position; move through path[1], path[2], ...
	for i in range(1, path.size()):
		if cells_moved >= max_cells:
			break
		set_grid_position(combatant, path[i])
		cells_moved += 1
		# Stop if we just entered an enemy ZoC cell (now engaged)
		if not enemy_zoc.is_empty() and enemy_zoc.has(path[i]):
			break
	return cells_moved


func get_cells_reachable(combatant: Combatant, max_cells: int,
		mover_side: int = -1) -> Array[Vector2i]:
	## Flood-fill to find all cells reachable within max_cells steps.
	## [param mover_side] when >= 0, enemy ZoC cells are reachable but act as
	## dead-ends (can enter but not leave — movement stops there).
	## In voxel mode, delegates to 3D flood-fill and projects results to 2D.
	if _voxel_map != null:
		var pos_3d: Vector3i = get_grid_position_3d(combatant)
		if pos_3d == Vector3i(-1, -1, -1):
			return []
		var cells_3d := get_cells_reachable_3d(pos_3d, "ground", max_cells)
		var result_2d: Array[Vector2i] = []
		for c3 in cells_3d:
			# Exclude start cell to match 2D get_cells_reachable behavior
			if c3 == pos_3d:
				continue
			result_2d.append(Vector2i(c3.x, c3.y))
		return result_2d
	var result: Array[Vector2i] = []
	if _map == null:
		return result
	var start: Vector2i = get_grid_position(combatant)
	if start == Vector2i(-1, -1):
		return result

	var occupied: Dictionary = {}
	for eid: String in _map.entity_positions.keys():
		var epos: Vector2i = _map.entity_positions[eid]
		if epos != start:
			occupied[epos] = true

	var enemy_zoc: Dictionary = _build_enemy_zoc_set(mover_side) if mover_side >= 0 else {}

	var visited: Dictionary = {start: 0}
	var queue: Array[Vector2i] = [start]

	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		var current_dist: int = visited[current]
		if current_dist >= max_cells:
			continue
		for neighbor: Vector2i in IsometricGrid.get_neighbors(current):
			if visited.has(neighbor):
				continue
			if not _map.is_passable(neighbor):
				continue
			if occupied.has(neighbor):
				continue
			visited[neighbor] = current_dist + 1
			result.append(neighbor)
			# ZoC cells are reachable but act as dead-ends — don't expand from them
			if not enemy_zoc.is_empty() and enemy_zoc.has(neighbor):
				continue
			queue.append(neighbor)

	return result


# ---------------------------------------------------------------------------
# Charge validation
# ---------------------------------------------------------------------------

func validate_charge(attacker: Combatant, target: Combatant) -> Dictionary:
	## Check if a charge from attacker to target is valid.
	## Returns {valid: bool, path: Array[Vector2i], reason: String}.

	# --- Voxel path ---
	if _voxel_map != null:
		var start: Vector2i = get_grid_position(attacker)
		var end: Vector2i = get_grid_position(target)
		if start == Vector2i(-1, -1) or end == Vector2i(-1, -1):
			return {"valid": false, "path": [], "reason": "combatants not placed on grid"}
		if not has_line_of_sight_combatants(attacker, target):
			return {"valid": false, "path": [], "reason": "no line of sight to target"}
		var z: int = attacker.grid_position_3d.z
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
			return {"valid": false, "path": line_path, "reason": "too close to charge (need %d+ cells, have %d)" % [MIN_CHARGE_CELLS, charge_distance]}
		var max_charge_cells := attacker.get_combat_movement_cells() * 3
		if charge_distance > max_charge_cells:
			return {"valid": false, "path": line_path, "reason": "target too far to charge (max %d cells)" % max_charge_cells}
		return {"valid": true, "path": line_path, "reason": ""}

	# --- Legacy TacticalMapData path ---
	if _map == null:
		# No grid = assume valid charge (pre-grid fallback)
		return {"valid": true, "path": [], "reason": ""}

	var start: Vector2i = get_grid_position(attacker)
	var end: Vector2i = get_grid_position(target)
	if start == Vector2i(-1, -1) or end == Vector2i(-1, -1):
		return {"valid": false, "path": [], "reason": "combatants not placed on grid"}

	# Check LOS at charge start
	if not has_line_of_sight(start, end):
		return {"valid": false, "path": [], "reason": "no line of sight to target"}

	# The charge destination is an adjacent cell to the target
	var best_adj: Vector2i = _find_best_adjacent_cell(start, end)
	if best_adj == Vector2i(-1, -1):
		return {"valid": false, "path": [], "reason": "no adjacent cell reachable near target"}

	# Check straight-line path (must be clear)
	var line_path: Array[Vector2i] = _get_line_cells(start, best_adj)
	for i in range(1, line_path.size()):  # Skip start cell
		var cell: Vector2i = line_path[i]
		if not _map.is_passable(cell):
			return {"valid": false, "path": [], "reason": "path blocked at %s" % str(cell)}
		# Check occupied by other entities (not attacker or target)
		var entities := _map.get_entities_at(cell)
		for eid: String in entities:
			if eid != attacker.id and eid != target.id:
				return {"valid": false, "path": [], "reason": "path blocked by entity at %s" % str(cell)}

	# Check minimum distance (4+ cells = 20+ feet)
	var charge_distance := line_path.size() - 1  # Exclude start
	if charge_distance < MIN_CHARGE_CELLS:
		return {"valid": false, "path": line_path, "reason": "too close to charge (need %d+ cells, have %d)" % [MIN_CHARGE_CELLS, charge_distance]}

	# Check max movement (3x combat movement for running/charging)
	var max_charge_cells := attacker.get_combat_movement_cells() * 3
	if charge_distance > max_charge_cells:
		return {"valid": false, "path": line_path, "reason": "target too far to charge (max %d cells)" % max_charge_cells}

	return {"valid": true, "path": line_path, "reason": ""}


# ---------------------------------------------------------------------------
# Line of sight
# ---------------------------------------------------------------------------

func has_line_of_sight(from_pos: Vector2i, to_pos: Vector2i) -> bool:
	## Bresenham line walk checking blocks_los on each intermediate cell.
	## In voxel mode, delegates to VoxelLOS with z=0 for both positions.
	## For full 3D LOS, use has_los_3d() directly.
	if _voxel_map != null:
		# Project 2D positions into 3D at z=0 for compatibility; callers that
		# need proper z should use has_los_3d() directly.
		return has_los_3d(Vector3i(from_pos.x, from_pos.y, 0),
						  Vector3i(to_pos.x, to_pos.y, 0))
	if _map == null:
		return true
	var line: Array[Vector2i] = _get_line_cells(from_pos, to_pos)
	# Check intermediate cells (exclude start and end)
	for i in range(1, line.size() - 1):
		if _map.blocks_los(line[i]):
			return false
	return true


## Overload that accepts combatants directly and uses correct z in voxel mode.
func has_line_of_sight_combatants(a: Combatant, b: Combatant) -> bool:
	if _voxel_map != null:
		return has_los_3d(get_grid_position_3d(a), get_grid_position_3d(b))
	return has_line_of_sight(get_grid_position(a), get_grid_position(b))


# ---------------------------------------------------------------------------
# Defensive movement
# ---------------------------------------------------------------------------

func resolve_fighting_withdrawal(
		combatant: Combatant,
		away_from: Vector2i) -> Vector2i:
	## Move up to half combat movement cells away from the specified position.
	## Returns new position.
	if _map == null and _voxel_map == null:
		return combatant.grid_position
	var start: Vector2i = get_grid_position(combatant)
	if start == Vector2i(-1, -1):
		return start
	var max_cells := combatant.get_combat_movement_cells() / 2
	if max_cells <= 0:
		return start
	var level_z: int = combatant.grid_position_3d.z
	var best_pos := _find_retreat_cell(start, away_from, max_cells, level_z)
	if best_pos != start:
		set_grid_position(combatant, best_pos)
	return best_pos


func resolve_full_retreat(
		combatant: Combatant,
		away_from: Vector2i) -> Vector2i:
	## Move at full combat movement away from the specified position.
	## Returns new position.
	if _map == null and _voxel_map == null:
		return combatant.grid_position
	var start: Vector2i = get_grid_position(combatant)
	if start == Vector2i(-1, -1):
		return start
	var max_cells := combatant.get_combat_movement_cells()
	if max_cells <= 0:
		return start
	var level_z: int = combatant.grid_position_3d.z
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
	if _voxel_map != null:
		var mover_pos: Vector2i = get_grid_position(mover)
		var target_pos: Vector2i = get_grid_position(target)
		return _find_best_adjacent_cell_voxel(mover_pos, target_pos, mover.grid_position_3d.z)
	if _map == null:
		return Vector2i(-1, -1)
	var mover_pos: Vector2i = get_grid_position(mover)
	var target_pos: Vector2i = get_grid_position(target)
	return _find_best_adjacent_cell(mover_pos, target_pos)


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

func _build_enemy_zoc_set(mover_side: int) -> Dictionary:
	## Returns a set (Dictionary of Vector2i -> true) of all cells adjacent to
	## alive enemies of the given side. These cells form the enemy zone of control.
	## In voxel mode, projects 3D ZoC to 2D keys for compatibility with 2D path code.
	var zoc: Dictionary = {}
	if _roster == null:
		return zoc
	if _map == null and _voxel_map == null:
		return zoc
	var enemy_side: int = Combatant.Side.ENEMY if mover_side == Combatant.Side.PARTY else Combatant.Side.PARTY
	for c: Combatant in _roster.get_alive_on_side(enemy_side):
		var c_pos: Vector2i = get_grid_position(c)
		if c_pos == Vector2i(-1, -1):
			continue
		for neighbor: Vector2i in IsometricGrid.get_neighbors(c_pos):
			zoc[neighbor] = true
	return zoc


func _reconstruct_path(
		visited: Dictionary,
		start: Vector2i,
		goal: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var current := goal
	while current != start:
		path.push_front(current)
		current = visited[current]
	path.push_front(start)
	return path


func _find_best_adjacent_cell(
		from_pos: Vector2i,
		target_pos: Vector2i) -> Vector2i:
	## Find the passable, unoccupied neighbor of target_pos closest to from_pos.
	var best := Vector2i(-1, -1)
	var best_dist := 999999
	for neighbor: Vector2i in IsometricGrid.get_neighbors(target_pos):
		if not _map.is_passable(neighbor):
			continue
		# Check not occupied by another entity
		var entities := _map.get_entities_at(neighbor)
		var blocked := false
		for eid: String in entities:
			# Allow the mover to occupy their own cell
			var epos := _map.get_entity_pos(eid)
			if epos == from_pos:
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


func _get_line_cells(from_pos: Vector2i, to_pos: Vector2i) -> Array[Vector2i]:
	## Bresenham-style line from from_pos to to_pos.
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
	## BFS to find the cell within max_cells that maximizes distance from away_from.
	## In voxel mode, uses VoxelMapData for passability and entity lookups.
	## [param level_z] is the z-level for voxel passability checks.
	var use_voxel: bool = _voxel_map != null
	var occupied: Dictionary = {}
	if use_voxel:
		for eid: String in _voxel_map.entity_positions.keys():
			var epos: Vector3i = _voxel_map.entity_positions[eid]
			var epos_2d := Vector2i(epos.x, epos.y)
			if epos_2d != start:
				occupied[epos_2d] = true
	else:
		for eid: String in _map.entity_positions.keys():
			var epos: Vector2i = _map.entity_positions[eid]
			if epos != start:
				occupied[epos] = true

	var visited: Dictionary = {start: 0}
	var queue: Array[Vector2i] = [start]
	var best_pos := start
	var best_dist := IsometricGrid.chebyshev_distance(start, away_from)

	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		var current_depth: int = visited[current]
		if current_depth >= max_cells:
			continue
		for neighbor: Vector2i in IsometricGrid.get_neighbors(current):
			if visited.has(neighbor):
				continue
			var passable: bool
			if use_voxel:
				passable = _voxel_map.is_passable(Vector3i(neighbor.x, neighbor.y, level_z))
			else:
				passable = _map.is_passable(neighbor)
			if not passable:
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
	## Voxel-mode equivalent of _find_best_adjacent_cell.
	## Uses VoxelMapData for passability checks, projects to 2D.
	## [param level_z] is the z-level for voxel lookups.
	var best := Vector2i(-1, -1)
	var best_dist := 999999
	# Iterate 2D neighbors (combat is still on a 2D plane within a level)
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
# 3D voxel methods (parallel to 2D methods above)
# ---------------------------------------------------------------------------

func set_voxel_map(voxel_map: VoxelMapData) -> void:
	_voxel_map = voxel_map


func has_voxel_grid() -> bool:
	return _voxel_map != null


## 3D BFS pathfinding on VoxelMapData.
## [param movement_type]: "ground", "flying", "tunnel_burrow", "earth_pass", "climbing".
## Returns path INCLUDING start and goal, or empty if unreachable.
func path_bfs_3d(from_pos: Vector3i, to_pos: Vector3i,
		movement_type: String = "ground",
		max_range: int = 50) -> Array[Vector3i]:
	if _voxel_map == null:
		return []
	if from_pos == to_pos:
		return [from_pos]

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
			if not _can_enter_3d(current, neighbor, movement_type):
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


## Flood-fill BFS returning all cells reachable from [param from_pos]
## within [param max_cells] steps using the given [param movement_type].
func get_cells_reachable_3d(from_pos: Vector3i,
		movement_type: String, max_cells: int) -> Array[Vector3i]:
	if _voxel_map == null:
		return []
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
			queue.append(neighbor)
			result.append(neighbor)

	return result


# ---------------------------------------------------------------------------
# 3D movement helpers (private)
# ---------------------------------------------------------------------------

## Returns true if [param movement_type] allows moving from [param from_pos]
## to [param to_pos].
func _can_enter_3d(from_pos: Vector3i, to_pos: Vector3i,
		movement_type: String) -> bool:
	var cell := _voxel_map.get_cell(to_pos)
	var level_diff: int = abs(to_pos.z - from_pos.z)

	match movement_type:
		"ground":
			if not cell.is_passable_by_walker():
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
