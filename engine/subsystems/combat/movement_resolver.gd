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


# ---------------------------------------------------------------------------
# Constructor
# ---------------------------------------------------------------------------

func _init(map: TacticalMapData, roster: CombatRoster) -> void:
	_map = map
	_roster = roster


# ---------------------------------------------------------------------------
# Grid presence
# ---------------------------------------------------------------------------

func has_grid() -> bool:
	return _map != null


# ---------------------------------------------------------------------------
# Position accessors
# ---------------------------------------------------------------------------

func get_grid_position(combatant: Combatant) -> Vector2i:
	## Returns the combatant's grid position, or Vector2i(-1,-1) if not placed.
	if _map == null:
		return Vector2i(-1, -1)
	return _map.get_entity_pos(combatant.id)


func set_grid_position(combatant: Combatant, pos: Vector2i) -> void:
	## Updates both the combatant field and TacticalMapData entity tracking.
	combatant.grid_position = pos
	if _map != null:
		_map.set_entity_pos(combatant.id, pos)


# ---------------------------------------------------------------------------
# Distance queries
# ---------------------------------------------------------------------------

func get_distance_cells(a: Combatant, b: Combatant) -> int:
	## Chebyshev distance between two combatants. Returns -1 if no grid.
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
	var result: Array[Combatant] = []
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
		max_range: int = 50) -> Array[Vector2i]:
	## BFS shortest path from start to goal on passable cells.
	## Returns the path INCLUDING start and goal, or empty if unreachable.
	## [param max_range] caps the BFS depth to avoid expensive searches.
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

			visited[neighbor] = current
			depth[neighbor] = current_depth + 1

			if neighbor == goal:
				# Reconstruct path
				return _reconstruct_path(visited, start, goal)
			queue.append(neighbor)

	return []  # Unreachable


func can_reach(combatant: Combatant, target_pos: Vector2i, max_cells: int) -> bool:
	## Returns true if combatant can reach target_pos within max_cells steps.
	if _map == null:
		return true  # No grid = everything reachable
	var start: Vector2i = get_grid_position(combatant)
	if start == Vector2i(-1, -1):
		return true
	var path: Array[Vector2i] = find_path(start, target_pos, true, max_cells + 1)
	# Path includes start, so actual steps = path.size() - 1
	return not path.is_empty() and (path.size() - 1) <= max_cells


# ---------------------------------------------------------------------------
# Movement execution
# ---------------------------------------------------------------------------

func move_along_path(
		combatant: Combatant,
		path: Array[Vector2i],
		max_cells: int) -> int:
	## Move combatant along the given path up to max_cells steps.
	## Updates grid positions. Returns the number of cells actually moved.
	if _map == null or path.is_empty():
		return 0
	var cells_moved := 0
	# Path[0] is current position; move through path[1], path[2], ...
	for i in range(1, path.size()):
		if cells_moved >= max_cells:
			break
		set_grid_position(combatant, path[i])
		cells_moved += 1
	return cells_moved


func get_cells_reachable(combatant: Combatant, max_cells: int) -> Array[Vector2i]:
	## Flood-fill to find all cells reachable within max_cells steps.
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
			queue.append(neighbor)
			result.append(neighbor)

	return result


# ---------------------------------------------------------------------------
# Charge validation
# ---------------------------------------------------------------------------

func validate_charge(attacker: Combatant, target: Combatant) -> Dictionary:
	## Check if a charge from attacker to target is valid.
	## Returns {valid: bool, path: Array[Vector2i], reason: String}.
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
	if _map == null:
		return true
	var line: Array[Vector2i] = _get_line_cells(from_pos, to_pos)
	# Check intermediate cells (exclude start and end)
	for i in range(1, line.size() - 1):
		if _map.blocks_los(line[i]):
			return false
	return true


# ---------------------------------------------------------------------------
# Defensive movement
# ---------------------------------------------------------------------------

func resolve_fighting_withdrawal(
		combatant: Combatant,
		away_from: Vector2i) -> Vector2i:
	## Move up to half combat movement cells away from the specified position.
	## Returns new position.
	if _map == null:
		return combatant.grid_position
	var start: Vector2i = get_grid_position(combatant)
	if start == Vector2i(-1, -1):
		return start
	var max_cells := combatant.get_combat_movement_cells() / 2
	if max_cells <= 0:
		return start
	var best_pos := _find_retreat_cell(start, away_from, max_cells)
	if best_pos != start:
		set_grid_position(combatant, best_pos)
	return best_pos


func resolve_full_retreat(
		combatant: Combatant,
		away_from: Vector2i) -> Vector2i:
	## Move at full combat movement away from the specified position.
	## Returns new position.
	if _map == null:
		return combatant.grid_position
	var start: Vector2i = get_grid_position(combatant)
	if start == Vector2i(-1, -1):
		return start
	var max_cells := combatant.get_combat_movement_cells()
	if max_cells <= 0:
		return start
	var best_pos := _find_retreat_cell(start, away_from, max_cells)
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
	if _map == null:
		return Vector2i(-1, -1)
	var mover_pos: Vector2i = get_grid_position(mover)
	var target_pos: Vector2i = get_grid_position(target)
	return _find_best_adjacent_cell(mover_pos, target_pos)


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

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
		max_cells: int) -> Vector2i:
	## BFS to find the cell within max_cells that maximizes distance from away_from.
	var occupied: Dictionary = {}
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
			if not _map.is_passable(neighbor):
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
