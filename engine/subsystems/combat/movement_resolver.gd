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


## The active voxel map (null before a grid is set). Exposed so combat-scoped
## helpers (e.g. SwarmDriver's water / LOS checks) can query terrain without
## re-plumbing the map reference.
func get_voxel_map() -> VoxelMapData:
	return _voxel_map


## True when [param pos] is a body of water (fleeing into water swats a swarm's
## remaining creatures off in 1 round — RAW le_monster_catalog_2_summary.xml).
## Recognizes the several ways a water cell is spelled in the voxel schema:
## liquid solidity, a non-zero water_depth, a "water" floor_type, or a
## water_shallow/water_deep feature. Returns false when there is no grid.
func is_water_cell(pos: Vector3i) -> bool:
	if _voxel_map == null:
		return false
	var cell: VoxelCell = _voxel_map.get_cell(pos)
	if cell == null:
		return false
	if cell.solidity == "liquid" or cell.water_depth > 0 or cell.floor_type == "water":
		return true
	return cell.feature.begins_with("water")


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
##
## Emits EventBus.combatant_moved with a single-cell path (the destination)
## when the position actually changes — covers teleports, forced movement,
## and any other non-path-walking placement. No emission on no-op (pos
## already equals current grid_position).
func set_grid_position_3d(combatant: Combatant, pos: Vector3i) -> void:
	var from_pos: Vector3i = combatant.grid_position
	combatant.grid_position = pos
	if _voxel_map != null:
		_voxel_map.set_entity_pos(combatant.id, pos)
		sync_entity_footprint(combatant)
	if from_pos != pos:
		EventBus.combatant_moved.emit(combatant.id, from_pos, pos, [pos])


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
	## Footprint-aware: a multi-cell creature is adjacent when ANY of its body
	## cells is one step from any of the other's. Two single-cell creatures use
	## the untouched anchor-distance fast path.
	if _voxel_map == null or (not a.is_multi_cell() and not b.is_multi_cell()):
		return get_distance_cells(a, b) == 1
	return _footprint_min_distance(a, b) == 1


func get_adjacent_enemies(combatant: Combatant) -> Array[Combatant]:
	## Returns all alive enemies within 3D Chebyshev distance 1 (footprint-aware).
	var result: Array[Combatant] = []
	if _voxel_map == null or _roster == null:
		return result
	var pos: Vector3i = get_grid_position_3d(combatant)
	if pos == Vector3i(-1, -1, -1):
		return result
	var self_multicell: bool = combatant.is_multi_cell()
	var target_side: int = Combatant.Side.ENEMY if combatant.is_pc_side() else Combatant.Side.PARTY
	for c: Combatant in _roster.get_alive_on_side(target_side):
		var c_pos: Vector3i = get_grid_position_3d(c)
		if c_pos == Vector3i(-1, -1, -1):
			continue
		if self_multicell or c.is_multi_cell():
			if _footprint_min_distance(combatant, c) == 1:
				result.append(c)
		elif VoxelGrid.is_adjacent(pos, c_pos):
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
	## incapacitated pass-through). On natural-slope terrain maps, start and
	## goal are resolved onto the terrain surface so cross-level slope paths
	## work through the 2D signature.
	if _voxel_map == null:
		return []
	var start_3d := Vector3i(start.x, start.y, _surface_z(start.x, start.y, level_z))
	var goal_3d := Vector3i(goal.x, goal.y, _surface_z(goal.x, goal.y, level_z))
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
	var goal_3d := Vector3i(
		target_pos.x, target_pos.y, _surface_z(target_pos.x, target_pos.y, start_3d.z))
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
	##
	## Appends each entered cell to combatant.cells_traversed_this_round (P1)
	## and emits EventBus.combatant_moved at end of move with the walked
	## path_cells. No signal on a 0-cell move.
	if path.is_empty() or _voxel_map == null:
		return 0
	var from_cell: Vector3i = combatant.grid_position
	var z: int = from_cell.z if from_cell.z >= 0 else 0
	var walked_cells: Array[Vector3i] = [from_cell]
	var enemy_zoc: Dictionary = _build_enemy_zoc_set_3d(mover_side) if mover_side >= 0 else {}
	# Swarms ignore ZoC stops — they march through enemy threatened cells freely.
	var mover_flags := combatant.get_flags()
	var ignore_zoc_stops: bool = mover_flags != null and mover_flags.has_flag("no_zoc_obedience")
	# Multi-cell movers re-validate each step's footprint on execution (safe even
	# if the path was produced without the footprint gate) and turn to face travel.
	var mover_local: Vector2i = combatant.get_footprint_local()
	var multicell: bool = not CreatureFootprint.is_single_cell(mover_local)
	var cells_moved := 0
	for i in range(1, path.size()):
		if cells_moved >= max_cells:
			break
		# On natural-slope terrain maps each step tracks the terrain surface
		# (walking up/down 5' grades); on dungeon maps _surface_z falls back to
		# the combatant's current z, preserving the legacy same-level behavior.
		var step_z: int = _surface_z(path[i].x, path[i].y, combatant.grid_position.z)
		var entered := Vector3i(path[i].x, path[i].y, step_z)
		var step_facing := Vector2i(entered.x - combatant.grid_position.x,
			entered.y - combatant.grid_position.y)
		if multicell:
			var face := step_facing if step_facing != Vector2i.ZERO else combatant.facing
			# An oversized body that no longer fits (e.g. path not footprint-
			# validated, or a body cell now occupied) stops before entering.
			if not footprint_can_occupy(entered, face, mover_local, combatant.id):
				break
			combatant.facing = face
		combatant.grid_position = entered
		_voxel_map.set_entity_pos(combatant.id, entered)
		if multicell:
			sync_entity_footprint(combatant)
		cells_moved += 1
		combatant.cells_traversed_this_round.append(entered)
		walked_cells.append(entered)
		if not enemy_zoc.is_empty() and not ignore_zoc_stops:
			if enemy_zoc.has(entered):
				break
	if cells_moved > 0:
		EventBus.combatant_moved.emit(
			combatant.id, from_cell, combatant.grid_position, walked_cells)
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
	var cells_3d := get_cells_reachable_3d(
		pos_3d, "ground", max_cells, mover_side,
		combatant.id if combatant != null else "")
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
	# On natural-slope terrain maps the charge lane follows the surface; a step
	# of 2+ levels (a bluff or drop-off) breaks the straight charge.
	var prev_z: int = _surface_z(start.x, start.y, z)
	for i in range(1, line_path.size()):
		var cell: Vector2i = line_path[i]
		var cell_3d := Vector3i(cell.x, cell.y, _surface_z(cell.x, cell.y, prev_z))
		if abs(cell_3d.z - prev_z) > 1:
			return {"valid": false, "path": [],
				"reason": "terrain break in charge lane at %s" % str(cell)}
		prev_z = cell_3d.z
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
	## 2D-signature LOS. Projects into 3D for VoxelLOS — on natural-slope
	## terrain maps the endpoints resolve to the terrain surface, otherwise
	## z=0 (legacy). Callers that need proper z should use has_los_3d().
	if _voxel_map == null:
		return true
	return has_los_3d(
		Vector3i(from_pos.x, from_pos.y, _surface_z(from_pos.x, from_pos.y, 0)),
		Vector3i(to_pos.x, to_pos.y, _surface_z(to_pos.x, to_pos.y, 0)))


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
		set_grid_position_3d(combatant, Vector3i(
			best_pos.x, best_pos.y, _surface_z(best_pos.x, best_pos.y, level_z)))
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
		set_grid_position_3d(combatant, Vector3i(
			best_pos.x, best_pos.y, _surface_z(best_pos.x, best_pos.y, level_z)))
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
	## BFS that picks the cell within max_cells maximizing Chebyshev distance
	## from away_from. Voxel-only. Same-level on dungeon maps; on natural-slope
	## terrain maps each step follows the terrain surface (±1 level grades).
	if _voxel_map == null:
		return start

	var occupied: Dictionary = {}
	for eid: String in _voxel_map.entity_positions.keys():
		var epos: Vector3i = _voxel_map.entity_positions[eid]
		var epos_2d := Vector2i(epos.x, epos.y)
		if epos_2d != start:
			occupied[epos_2d] = true

	var visited: Dictionary = {start: 0}
	var cell_z: Dictionary = {start: _surface_z(start.x, start.y, level_z)}
	var queue: Array[Vector2i] = [start]
	var best_pos := start
	var best_dist: int = IsometricGrid.chebyshev_distance(start, away_from)

	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		var current_depth: int = visited[current]
		var current_z: int = cell_z[current]
		if current_depth >= max_cells:
			continue
		for neighbor: Vector2i in IsometricGrid.get_neighbors(current):
			if visited.has(neighbor):
				continue
			var nz: int = _surface_z(neighbor.x, neighbor.y, current_z)
			if abs(nz - current_z) > 1:
				continue  # cliff step — not a legal retreat move
			if not _voxel_map.is_passable(Vector3i(neighbor.x, neighbor.y, nz)):
				continue
			if occupied.has(neighbor):
				continue
			visited[neighbor] = current_depth + 1
			cell_z[neighbor] = nz
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
	## Returns the passable, unoccupied neighbor of target_pos closest to
	## from_pos. Vector2i(-1, -1) if none. On dungeon maps neighbors are taken
	## on level_z; on natural-slope terrain maps each neighbor resolves to its
	## own surface level and must sit within ±1 level of the target's surface
	## (3D adjacency — melee across a cliff edge is not "adjacent").
	if _voxel_map == null:
		return Vector2i(-1, -1)
	var target_z: int = _surface_z(target_pos.x, target_pos.y, level_z)
	var best := Vector2i(-1, -1)
	var best_dist := 999999
	for neighbor: Vector2i in IsometricGrid.get_neighbors(target_pos):
		var neighbor_3d := Vector3i(
			neighbor.x, neighbor.y, _surface_z(neighbor.x, neighbor.y, level_z))
		if abs(neighbor_3d.z - target_z) > 1:
			continue
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

	# Multi-cell movers additionally require their WHOLE footprint to fit at each
	# candidate anchor (with the facing implied by the step). Single-cell movers
	# skip this entirely and run the original single-cell BFS unchanged.
	var mover_local: Vector2i = _footprint_local_for(mover_id)
	var mover_multicell: bool = not CreatureFootprint.is_single_cell(mover_local)
	var mover_facing: Vector2i = _facing_for(mover_id)

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
			# Oversized body must clear its full footprint at the destination
			# anchor, facing the direction of travel — this is what stops a Huge
			# creature routing through a 1-wide door/corridor.
			if mover_multicell:
				var step := Vector2i(neighbor.x - current.x, neighbor.y - current.y)
				var step_facing := step if step != Vector2i.ZERO else mover_facing
				if not footprint_can_occupy(neighbor, step_facing, mover_local, mover_id):
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
##   - blocked_cell: Vector3i — the impassable cell that stopped the walk
##       ((-1,-1,-1) when no wall collision). On natural-slope terrain the
##       blocker is reported at its surface level so hazard checks (lava,
##       future deep-water/cliff rules) see the real obstacle.
##   - blocked_feature: String — that cell's feature ("" when none)
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
	var blocked_cell := Vector3i(-1, -1, -1)
	var blocked_feature := ""
	if _voxel_map == null or max_cells <= 0:
		return {
			"cells_traveled": 0,
			"final_pos": current,
			"wall_collision": false,
			"entity_collision": false,
			"blocked_cell": blocked_cell,
			"blocked_feature": blocked_feature,
		}
	for _i in range(max_cells):
		var next := current + direction
		# On natural-slope terrain the walk follows the surface (a push can go
		# up/down a 5' grade); on dungeon maps _surface_z falls back to the
		# same-level cell, preserving legacy behavior. A liquid surface (deep
		# water, lava) resolves to the liquid cell, which ground movement
		# rejects — so it reports as the blocking cell for hazard rules.
		next.z = _surface_z(next.x, next.y, next.z)
		# Reachability via the same BFS primitive used by normal movement.
		# path_bfs_3d returns a 1-step path when next is adjacent and passable.
		var path := path_bfs_3d(current, next, "ground", 1)
		if path.is_empty():
			wall = true
			blocked_cell = next
			blocked_feature = _voxel_map.get_cell(next).feature
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
		"blocked_cell": blocked_cell,
		"blocked_feature": blocked_feature,
	}


## Flood-fill BFS returning all cells reachable from [param from_pos]
## within [param max_cells] steps using the given [param movement_type].
## [param mover_side] (optional, default -1 = ignore ZoC): when >= 0, ZoC
##   cells are reachable but act as dead-ends — the flood includes them but
##   does not expand from them (entering costs movement and consumes the turn).
func get_cells_reachable_3d(from_pos: Vector3i,
		movement_type: String, max_cells: int,
		mover_side: int = -1, mover_id: String = "") -> Array[Vector3i]:
	if _voxel_map == null:
		return []
	var enemy_zoc: Dictionary = _build_enemy_zoc_set_3d(mover_side) if mover_side >= 0 else {}
	# Multi-cell mover: the whole footprint must fit at every reachable anchor.
	var mover_local: Vector2i = _footprint_local_for(mover_id)
	var mover_multicell: bool = not CreatureFootprint.is_single_cell(mover_local)
	var mover_facing: Vector2i = _facing_for(mover_id)
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
			if mover_multicell:
				var step := Vector2i(neighbor.x - current.x, neighbor.y - current.y)
				var step_facing := step if step != Vector2i.ZERO else mover_facing
				if not footprint_can_occupy(neighbor, step_facing, mover_local, mover_id):
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
		# Swarms and other entities flagged no_zoc_emission don't threaten
		# adjacent cells. Their cell-occupancy block is also waived (above).
		var flags := c.get_flags()
		if flags != null and flags.has_flag("no_zoc_emission"):
			continue
		# ZoC borders EVERY cell the creature occupies. For a single-cell
		# creature this is the same 8 neighbors as before; a multi-cell creature
		# threatens the whole ring around its footprint. Occupied cells are
		# themselves excluded (you can't stand where the body is).
		var body: Array[Vector3i] = _footprint_cells_for(c)
		var body_set: Dictionary = {}
		for bc: Vector3i in body:
			body_set[bc] = true
		for bc: Vector3i in body:
			for neighbor: Vector3i in VoxelGrid.get_neighbors_2d(bc):
				if not body_set.has(neighbor):
					zoc[neighbor] = true
	return zoc


# ---------------------------------------------------------------------------
# Multi-cell footprints (creature-size build session)
# ---------------------------------------------------------------------------

## Every cell [param combatant] currently occupies. Reads the map's registered
## footprint (kept current by sync_entity_footprint); falls back to the single
## anchor cell for the single-cell majority. Empty when not placed.
func _footprint_cells_for(combatant: Combatant) -> Array[Vector3i]:
	if _voxel_map == null or combatant == null:
		return []
	return _voxel_map.get_entity_footprint_cells(combatant.id)


## The local-frame footprint (length, width) of the mover behind [param mover_id],
## or (1, 1) when there's no such combatant or it is single-cell. This is the
## gate that keeps ALL single-cell movement on the untouched fast path.
func _footprint_local_for(mover_id: String) -> Vector2i:
	if mover_id.is_empty():
		return Vector2i(1, 1)
	var c := _lookup_combatant(mover_id)
	if c == null:
		return Vector2i(1, 1)
	return c.get_footprint_local()


## The mover's current facing (grid Vector2i), defaulting to east.
func _facing_for(mover_id: String) -> Vector2i:
	var c := _lookup_combatant(mover_id)
	if c == null:
		return Vector2i(1, 0)
	return c.facing


## True when a creature with local footprint [param local], facing [param facing],
## can legally anchor at [param anchor]: EVERY footprint cell must be passable by
## a ground walker, supported, and free of any OTHER blocking entity (the mover's
## own cells are exempt via mover_id). This is the "no squeezing an oversized body
## through a small door/corridor" gate — one wall cell anywhere in the footprint
## refuses the placement.
##
## v1 checks ground passability + support for the whole body; flyers/burrowers
## with multi-cell footprints validate only their anchor via _can_enter_3d (a
## documented v1 limitation — no multi-cell flyers are wired yet).
func footprint_can_occupy(anchor: Vector3i, facing: Vector2i,
		local: Vector2i, mover_id: String = "") -> bool:
	if _voxel_map == null:
		return true
	for cell: Vector3i in CreatureFootprint.cells(anchor, facing, local):
		var vc: VoxelCell = _voxel_map.get_cell(cell)
		if not vc.is_passable_by_walker():
			return false
		if not FallingResolver.has_support(_voxel_map, cell):
			return false
		if _is_blocking_occupant(cell, mover_id):
			return false
	return true


## Recomputes [param combatant]'s occupied cells from its anchor + facing + size
## and pushes them to the voxel map. Collapses to single-anchor occupancy for
## single-cell creatures (clears any stale footprint). The one writer of
## VoxelMapData.entity_footprints — call after every placement / move / turn of a
## multi-cell creature so occupancy queries stay correct.
func sync_entity_footprint(combatant: Combatant) -> void:
	if _voxel_map == null or combatant == null:
		return
	var local: Vector2i = combatant.get_footprint_local()
	if CreatureFootprint.is_single_cell(local):
		_voxel_map.clear_entity_footprint(combatant.id)
		return
	var cells: Array[Vector3i] = CreatureFootprint.cells(
		combatant.grid_position, combatant.facing, local)
	_voxel_map.set_entity_footprint(combatant.id, cells)


## Turn a combatant in place to [param new_facing], validating that its footprint
## still fits (a long creature may not be able to swing broadside in a tight
## corridor). Single-cell creatures always succeed. Returns true on success and
## updates facing + footprint; false leaves the combatant unchanged (the caller
## flags the illegal turn). Multi-cell v1 behavior: refuse rather than shove.
func set_facing_and_revalidate(combatant: Combatant, new_facing: Vector2i) -> bool:
	if combatant == null:
		return false
	var local: Vector2i = combatant.get_footprint_local()
	if CreatureFootprint.is_single_cell(local):
		combatant.facing = new_facing
		return true
	if not footprint_can_occupy(combatant.grid_position, new_facing, local, combatant.id):
		return false
	combatant.facing = new_facing
	sync_entity_footprint(combatant)
	return true


## Footprint-aware minimum 3D Chebyshev distance between two combatants (the
## smallest distance between any cell of A's body and any cell of B's body). For
## two single-cell creatures this equals the plain anchor distance.
func _footprint_min_distance(a: Combatant, b: Combatant) -> int:
	var ca: Array[Vector3i] = _footprint_cells_for(a)
	var cb: Array[Vector3i] = _footprint_cells_for(b)
	if ca.is_empty() or cb.is_empty():
		return -1
	var best: int = 0x7fffffff
	for pa: Vector3i in ca:
		for pb: Vector3i in cb:
			best = mini(best, VoxelGrid.chebyshev_distance(pa, pb))
	return best


# ---------------------------------------------------------------------------
# Occupancy checks (B2 — block actives, allow incapacitated pass-through)
# ---------------------------------------------------------------------------

## True when [param pos] is occupied by an entity that should block the
## mover's path step. The mover's own cell never blocks itself; incapacitated
## occupants (dead, unconscious, paralyzed, sleeping) are treated as
## obstacle-free because PCs and monsters can step over downed bodies.
## Scrolls of Warding entry-block check (2026-06-03 RAW-aligned). Scans
## the roster for any combatant carrying the `warded_against_creature_type`
## flag. For each bearer, if [param mover_id]'s combatant matches one of
## the ward's `creature_types`, and [param to_pos] is within `radius_feet`
## of the bearer's current cell, the move is refused. The bearer itself
## is exempt (the bearer can move freely). Returns true if any active
## ward blocks the move.
func _ward_blocks_entry(to_pos: Vector3i, mover_id: String) -> bool:
	var mover := _lookup_combatant(mover_id)
	if mover == null:
		return false
	for bearer in _roster.get_alive():
		if bearer == null:
			continue
		if String(bearer.id) == mover_id:
			continue  # bearer exempt from their own ward
		var b_flags: EntityFlags = bearer.get_flags() if bearer.has_method("get_flags") else null
		if b_flags == null or not b_flags.has_flag("warded_against_creature_type"):
			continue
		var b_pos: Vector3i = bearer.grid_position
		var ward_entries: Array = b_flags.get_flag_source_entries(
			"warded_against_creature_type")
		for entry in ward_entries:
			var meta: Dictionary = entry.get("metadata", {})
			var warded_types: Array = meta.get("creature_types", [])
			if warded_types.is_empty():
				continue
			if not _mover_matches_warded_types(mover, warded_types):
				continue
			# Distance: ward radius is in FEET; one cell = 5 feet by ACKS
			# convention. radius_feet / 5 = cell radius. Chebyshev distance
			# (3D max-axis) matches the existing combat-grid distance model.
			var radius_feet: int = int(meta.get("radius_feet", 10))
			var radius_cells: int = int(radius_feet / 5)
			var dx: int = abs(to_pos.x - b_pos.x)
			var dy: int = abs(to_pos.y - b_pos.y)
			var dz: int = abs(to_pos.z - b_pos.z)
			var dist_cells: int = max(dx, max(dy, dz))
			if dist_cells <= radius_cells:
				return true
	return false


## Returns true if [param mover]'s creature_type matches any of
## [param warded_types]. Mirrors SpellCombatHooks._target_matches_warded_types
## but lives here for movement-resolver use.
func _mover_matches_warded_types(mover: Variant, warded_types: Array) -> bool:
	if mover == null:
		return false
	for t in warded_types:
		var t_str: String = String(t).to_lower()
		if mover.has_method("is_creature_type"):
			if mover.is_creature_type(t_str):
				return true
		if "creature_type" in mover:
			if String(mover.creature_type).to_lower() == t_str:
				return true
		if "tags" in mover:
			var tags = mover.tags
			if tags is Array and t_str in tags:
				return true
	return false


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
		if _is_incapacitated(combatant):
			continue
		# Swarms (insect / rat / bat) flag ignores_cell_occupancy so other
		# creatures may walk through the cells they occupy.
		var flags := combatant.get_flags()
		if flags != null and flags.has_flag("ignores_cell_occupancy"):
			continue
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

## Resolves a (col, row) reference to a level for the 2D-signature wrappers.
## On natural-slope terrain maps (generated wilderness battle maps) this is the
## terrain surface at that column; on dungeon maps — and when the column has no
## surface — it falls back to [param fallback_z], preserving legacy same-level
## behavior. See gdd-combat-map-generation.md §9.2.
func _surface_z(col: int, row: int, fallback_z: int) -> int:
	if _voxel_map == null or not _voxel_map.natural_slopes:
		return fallback_z
	var s: int = _voxel_map.surface_level_at(col, row)
	return s if s >= 0 else fallback_z


## Wade-depth allowance for a mover, in full 5' voxels of water
## (gdd-combat-map-generation.md §9.3). v1: every creature wades shallow water
## only (allowance 0). The creature-size build session will derive this from
## size category — this helper is the single place it plugs in.
func _wade_allowance_for(_mover_id: String) -> int:
	return 0

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
	# Scrolls of Warding entry-block (2026-06-03 RAW-aligned). Any
	# bearer carrying the `warded_against_creature_type` flag projects
	# a 10' barrier centered on themselves. A creature whose
	# creature_type matches one of the bearer's warded_types CANNOT
	# enter cells within radius_feet of the bearer. Per RAW
	# acore_treasure_and_magic_items_rules.xml:268-272 — no save. The
	# barrier moves with the bearer (re-evaluated each move).
	if mover_id != "" and _roster != null:
		if _ward_blocks_entry(to_pos, mover_id):
			return false
	# Out-of-volume cells are impassable for EVERY movement type (matches
	# is_passable(), which returns false for absent cells). get_cell() hands back
	# a fresh AIR sentinel for an undefined cell, which the flying/gaseous
	# branches below would otherwise treat as open air — letting a flyer path
	# through the void around a solid. The ground/swim/burrow/climb branches
	# already reject absent cells (via support / solidity checks), so this only
	# adds the missing gate for flyers. Maps store every in-bounds cell explicitly
	# (open as air, rock/walls as solid — burrowers require the solid to be real),
	# so this never fires for a legal in-bounds step.
	if not _voxel_map.has_cell(to_pos):
		return false
	var cell := _voxel_map.get_cell(to_pos)
	var level_diff: int = abs(to_pos.z - from_pos.z)

	# Gaseous Form auto-detect (Tier 4 follow-up, 2026-06-01). A
	# combatant carrying the is_gaseous EntityFlag (set by the
	# Gaseous Form spell or Potion of Gaseous Form) moves in gas
	# semantics — passes any air cell regardless of door_state +
	# ignores support. Per RAW pc_spell_catalog_f-u.xml:90-126
	# "can flow below doors and through small unsealed spaces."
	# Auto-promotion happens here so existing callers (charging,
	# pathfinding, AI movement) all get the bypass without each
	# needing to detect is_gaseous and pass "gaseous" explicitly.
	# NOTE: Combatants expose flags via get_flags() (which returns
	# the character's flags for PCs and _monster_flags for monsters);
	# we use that accessor — there's no public `flags` property.
	if movement_type == "ground" and mover_id != "" and _roster != null:
		var mover: Combatant = _roster.get_by_id(mover_id)
		if mover != null:
			var mover_flags: EntityFlags = mover.get_flags()
			if mover_flags != null and mover_flags.has_flag("is_gaseous"):
				movement_type = "gaseous"

	match movement_type:
		"ground":
			var ground_passable: bool
			if passability_mode == "explore":
				ground_passable = cell.is_walkable_with_open_door()
			else:
				ground_passable = cell.is_passable_by_walker()
			if not ground_passable:
				# Water-depth wading gate (gdd-combat-map-generation.md §9.3):
				# a deep-water cell (solidity "liquid") is enterable by a
				# ground walker whose wade allowance covers its water_depth.
				# v1 allowance is 0 for everyone, so this admits nothing yet —
				# it is the hook the creature-size session keys into. Lava is
				# liquid but never wadeable.
				var wadeable: bool = cell.solidity == "liquid" \
					and cell.feature != "lava" \
					and MovementRules.can_wade(cell, _wade_allowance_for(mover_id))
				if not wadeable:
					return false
			if not FallingResolver.has_support(_voxel_map, to_pos):
				return false
			if level_diff == 0:
				return true
			if level_diff == 1:
				return _has_stair_connection(from_pos, to_pos)
			return false  # level diff 2+ blocked for ground

		"swimming":
			# Hook for swim-capable creatures (no swimmers wired in v1).
			# Liquid water cells and shallow-water cells are swimmable; lava
			# is not. Level changes follow the same ±1 rule as ground so a
			# swimmer can haul out onto a bank via the natural-slope clause.
			var swimmable: bool = (cell.solidity == "liquid" and cell.feature != "lava") \
				or cell.feature == "water_shallow"
			if not swimmable:
				return false
			if level_diff == 0:
				return true
			if level_diff == 1:
				return _has_stair_connection(from_pos, to_pos)
			return false

		"flying":
			return not cell.blocks_flight()

		"gaseous":
			# Gas flows through any air cell — closed/locked/stuck doors
			# and closed portcullises don't block (RAW). Solid walls
			# still block (gas can't pass solid matter). No support
			# requirement (gas doesn't fall). Vertical movement: 1 level
			# diff requires the same stair-connection check as ground
			# walkers (gas needs a vertical opening); level diff 2+
			# blocked (matches ground semantics — V1 simplification).
			if not cell.is_passable_by_gaseous():
				return false
			if level_diff == 0:
				return true
			if level_diff == 1:
				return _has_stair_connection(from_pos, to_pos)
			return false

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


## Checks if a stair / ramp / spiral feature connects [param from_pos] to
## [param to_pos] (which must differ by exactly 1 level). Delegates to the
## single step-legality home `MovementRules.connects_via_feature` (DG-C3D.E) so
## combat/exploration movement, the navigability validator, and the key/lever
## placer share ONE stair predicate — and this is where combat picks up the
## spiral-stair clause (voxel GDD §10.5).
func _has_stair_connection(from_pos: Vector3i, to_pos: Vector3i) -> bool:
	return MovementRules.connects_via_feature(_voxel_map, from_pos, to_pos)


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
