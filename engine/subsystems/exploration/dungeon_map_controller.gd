class_name DungeonMapController
extends Node

## Manages dungeon exploration game logic: party movement, fog of war,
## door interaction, and multi-level stair transitions.
##
## D-4 simplified model: all party members move as a group to the same cell.
## Per-character tactical positioning is supported by TacticalMapData but
## deferred to E-2 (session runner) and F-1 (combat).
##
## This is NOT an autoload. Instantiate dynamically when entering a dungeon.


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal map_loaded(dungeon_id: String)
signal party_moved(from_pos: Vector2i, to_pos: Vector2i)
signal entity_moved(entity_id: String, from_pos: Vector2i, to_pos: Vector2i)
signal room_revealed(room_id: int)
signal fog_updated()
signal door_state_changed(pos: Vector2i, old_state: String, new_state: String)
signal level_changed(from_level: int, to_level: int)
signal orders_executed(result: Dictionary)

## Relay signals for renderer-driven movement animation.
## DungeonExploreState emits these; the renderer connects in setup().
signal movement_animation_requested(entity_id: String, path: Array, cells_per_round: float)
signal movement_animation_cancelled(entity_id: String)


# ---------------------------------------------------------------------------
# Private state
# ---------------------------------------------------------------------------

## Feature flag: when true, uses VoxelMapData; when false, legacy TacticalMapData.
static var use_voxel_renderer: bool = true

var _dungeon_id: String = ""
var _dungeon_name: String = ""
var _all_levels: Dictionary = {}   # int (level number) → TacticalMapData (legacy)
var _stairs: Array = []            # Array of stair connection Dictionaries (legacy)
var _current_level: int = 1
var _map: TacticalMapData          # Alias for _all_levels[_current_level] (legacy)

## Voxel map storage — single VoxelMapData containing all levels.
var _voxel_map: VoxelMapData = null

## Entity IDs of all party members (moved as a group in D-4).
var _party_entity_ids: Array[String] = []

## Per-entity light radius provider. If set, fog update queries this for
## each entity's radius. If null, falls back to _fallback_light_radius.
var _light_manager: DungeonLightManager = null

## Fallback light radius (used when no DungeonLightManager is set).
var _fallback_light_radius: int = 10  # 50 feet / 5 feet per cell

## Per-dungeon-visit session state (for spike/wedge checks).
var _session_state: RefCounted = null

## Per-entity darkvision bonuses: { entity_id: int (cells) }.
var _darkvision_bonuses: Dictionary = {}

## Order manager for individual movement queue (DungeonOrderManager).
var _order_manager: RefCounted = null

## Formation manager for party layout (FormationManager).
var _formation_manager: RefCounted = null

## Class references loaded at runtime to avoid parse-time dependency.
var _OrderManagerClass = null
var _FormationManagerClass = null

## Reference to the active PartyData for formation and individual movement.
## Set via set_party_data() before load_dungeon().
var _party_data_ref: PartyData = null


# ---------------------------------------------------------------------------
# Lazy init helpers
# ---------------------------------------------------------------------------

func _ensure_managers() -> void:
	if _order_manager == null:
		if _OrderManagerClass == null:
			_OrderManagerClass = load("res://engine/subsystems/exploration/dungeon_order_manager.gd")
		_order_manager = _OrderManagerClass.new()
	if _formation_manager == null:
		if _FormationManagerClass == null:
			_FormationManagerClass = load("res://engine/subsystems/exploration/formation_manager.gd")
		_formation_manager = _FormationManagerClass.new()


# ---------------------------------------------------------------------------
# Core API
# ---------------------------------------------------------------------------

## Loads all levels and stairs from a dungeon data dictionary.
## The dictionary should match the test_dungeon.json format:
##   { id, name, levels: [{level, grid_width, grid_height, entry_col, entry_row, cells}],
##     stairs: [{from_level, from_col, from_row, to_level, to_col, to_row}] }
## [param spawn_pos] overrides the default entry_pos when entering via a specific
## transition cell. Pass Vector2i(-1, -1) (the default) to use entry_pos.
func load_dungeon(dungeon_dict: Dictionary, spawn_pos: Vector2i = Vector2i(-1, -1)) -> void:
	_ensure_managers()
	_dungeon_id = dungeon_dict.get("id", "")
	_dungeon_name = dungeon_dict.get("name", "")

	if use_voxel_renderer:
		_load_dungeon_voxel(dungeon_dict, spawn_pos)
		return

	_all_levels.clear()
	_stairs.clear()

	var levels_array: Array = dungeon_dict.get("levels", [])
	for level_data in levels_array:
		var level_num: int = level_data.get("level", 1)
		var map_data := TacticalMapData.from_dict(level_data)
		_all_levels[level_num] = map_data

	_stairs = dungeon_dict.get("stairs", [])

	if _all_levels.is_empty():
		push_error("DungeonMapController.load_dungeon: no levels found in dungeon '%s'" % _dungeon_id)
		return

	_current_level = 1
	if not _all_levels.has(1):
		var keys: Array = _all_levels.keys()
		keys.sort()
		_current_level = keys[0]

	_map = _all_levels[_current_level]

	# Position party at spawn_pos or entry_pos
	var entry: Vector2i
	if spawn_pos != Vector2i(-1, -1):
		entry = spawn_pos
	else:
		entry = _map.entry_pos

	# Try formation placement; fall back to stacking at entry
	var formation_positions: Dictionary = _formation_manager.compute_dungeon_positions(
		entry, _party_data_ref, _map) if _party_data_ref != null else {}

	for eid in _party_entity_ids:
		if formation_positions.has(eid):
			_map.set_entity_pos(eid, formation_positions[eid])
		else:
			_map.set_entity_pos(eid, entry)

	_reveal_entry_room()
	map_loaded.emit(_dungeon_id)


## Voxel path for load_dungeon. Loads a single VoxelMapData from the dict.
## Handles both voxel format (has "cells" key) and legacy format (has "levels" key).
func _load_dungeon_voxel(dungeon_dict: Dictionary, spawn_pos: Vector2i) -> void:
	if dungeon_dict.has("cells"):
		# Native voxel format — unified cells array
		_voxel_map = VoxelMapData.from_dict(dungeon_dict)
	elif dungeon_dict.has("levels"):
		# Legacy format — convert levels[] + stairs[] to VoxelMapData
		_voxel_map = _convert_legacy_to_voxel(dungeon_dict)
	else:
		push_error("DungeonMapController._load_dungeon_voxel: unrecognized format for '%s'" % _dungeon_id)
		return

	if _voxel_map.cell_count() == 0:
		push_error("DungeonMapController._load_dungeon_voxel: no cells in dungeon '%s'" % _dungeon_id)
		return

	# Determine entry position
	var entry_3d: Vector3i
	if spawn_pos != Vector2i(-1, -1):
		entry_3d = Vector3i(spawn_pos.x, spawn_pos.y, _voxel_map.entry_pos.z)
	else:
		entry_3d = _voxel_map.entry_pos

	_current_level = entry_3d.z

	# Position party at entry
	for eid in _party_entity_ids:
		_voxel_map.set_entity_pos(eid, entry_3d)

	# Reveal entry room
	_reveal_entry_room_voxel()
	map_loaded.emit(_dungeon_id)


## Attempts to move all party members to [param target].
## Returns true on success, false if the move is invalid.
## Backward-compat wrapper: queues a group move and executes immediately.
func move_party(target: Vector2i) -> bool:
	_ensure_managers()
	if _map == null:
		push_error("DungeonMapController.move_party: no map loaded")
		return false

	var party_pos := get_party_position()

	if not IsometricGrid.is_adjacent(party_pos, target):
		return false

	if not _map.is_passable(target):
		return false

	var old_pos := party_pos

	# Use formation-aware group move if party data is available
	if _party_data_ref != null and _party_entity_ids.size() > 1:
		queue_group_move(target)
		execute_orders()
		return true

	# Fallback: move all entities to same cell (legacy behavior)
	for eid in _party_entity_ids:
		var from := _map.get_entity_pos(eid)
		_map.set_entity_pos(eid, target)
		entity_moved.emit(eid, from, target)

	_update_visibility_on_move(old_pos, target)
	party_moved.emit(old_pos, target)
	return true


## Returns true if the party can legally move to [param target].
func can_move_to(target: Vector2i) -> bool:
	if _map == null:
		return false
	var party_pos := get_party_position()
	return IsometricGrid.is_adjacent(party_pos, target) and _map.is_passable(target)


## Attempts to interact with a door at [param pos].
## pos must be adjacent to the party's current position.
## Returns true if the door state changed, false otherwise.
##
## D-4 door interactions:
##   arch → always open, no interaction
##   unlocked (closed) → opens
##   unlocked (open) → closes
##   locked → blocked (returns false — needs pick lock or force)
##   stuck → blocked (returns false — needs force door check)
##   secret (undetected) → no effect (returns false — needs search check)
##   secret (detected, closed) → opens
##   portcullis (closed) → blocked in D-4 (needs lever mechanism)
func interact_door(pos: Vector2i) -> bool:
	if _map == null:
		return false

	# Any party member adjacent to the door can interact with it
	var any_adjacent := false
	for eid in _party_entity_ids:
		var member_pos := _map.get_entity_pos(eid)
		if member_pos != Vector2i(-1, -1) and IsometricGrid.is_adjacent(member_pos, pos):
			any_adjacent = true
			break
	if not any_adjacent:
		return false

	if not _map.is_door(pos):
		push_error("DungeonMapController.interact_door: no door at %s" % str(pos))
		return false

	var door_type := _map.get_door_type(pos)
	var door_state := _map.get_door_state(pos)

	# Arch is always open — cannot be interacted with
	if door_type == "arch":
		return false

	# Destroyed door — permanently open, no interaction
	if door_state == "destroyed":
		return false

	# Secret door that hasn't been detected yet — search check needed first
	var cell := _map.get_cell(pos)
	if not cell.get("door_detected", true):
		return false

	# Portcullis — needs a lever/mechanism in D-4
	if door_type == "portcullis":
		return false

	# Locked door — needs pick lock or force
	if door_state == "locked":
		return false

	# Stuck door — needs force door check
	if door_state == "stuck":
		return false

	# Spiked shut — cannot open until spike is removed
	if _session_state != null and _session_state.has_method("is_spiked") \
			and _session_state.is_spiked(pos):
		return false

	# Wedged open — cannot close until wedge is removed
	if _session_state != null and _session_state.has_method("is_wedged") \
			and _session_state.is_wedged(pos):
		return false

	# Toggle open/closed for unlocked/detected-secret doors
	var old_state := door_state
	var new_state := "open" if door_state == "closed" else "closed"
	_map.set_door_state(pos, new_state)
	door_state_changed.emit(pos, old_state, new_state)
	return true


## Queue a compound "move to door + interact" order for an entity.
## If the entity is already adjacent to the door, interacts immediately and
## returns "immediate". Otherwise pathfinds to the nearest passable cell adjacent
## to the door and queues a move_and_interact_door order, returning "queued".
## Returns "" if no path or door is invalid.
func queue_door_interaction_order(entity_id: String, door_pos: Vector2i) -> String:
	if _map == null:
		return ""

	var entity_pos := _map.get_entity_pos(entity_id)
	if entity_pos == Vector2i(-1, -1):
		return ""

	# Already adjacent → interact immediately
	if IsometricGrid.is_adjacent(entity_pos, door_pos):
		if interact_door(door_pos):
			return "immediate"
		return ""

	# Find nearest passable neighbor of the door to pathfind to
	var door_neighbors := IsometricGrid.get_neighbors(door_pos)
	var best_path: Array[Vector2i] = []
	var best_path_len := 999999

	for neighbor in door_neighbors:
		if not _map.has_cell(neighbor) or not _map.is_passable(neighbor):
			continue
		var path := _bfs_path(entity_pos, neighbor, entity_id)
		if not path.is_empty() and path.size() < best_path_len:
			best_path = path
			best_path_len = path.size()

	if best_path.is_empty():
		return ""

	# Queue a compound order: move to adjacent cell, then interact with door
	_ensure_managers()
	_order_manager.add_order(entity_id, "move_and_interact_door", door_pos, best_path)
	return "queued"


## Attempts to use stairs at [param pos], transitioning the party to the connected level.
## Returns true on success, false if pos has no stairs or stair connection not found.
func use_stairs(pos: Vector2i) -> bool:
	if _map == null:
		return false

	var cell := _map.get_cell(pos)
	if cell.is_empty():
		return false

	var tf: String = cell.get("terrain_feature", "")
	if tf != "stairs_up" and tf != "stairs_down":
		push_error("DungeonMapController.use_stairs: no stairs at %s" % str(pos))
		return false

	# Find matching stair connection
	var target_stair: Dictionary = {}
	for stair in _stairs:
		if stair.get("from_level", 0) == _current_level and \
		   stair.get("from_col", -1) == pos.x and \
		   stair.get("from_row", -1) == pos.y:
			target_stair = stair
			break

	if target_stair.is_empty():
		push_error("DungeonMapController.use_stairs: no stair connection at level=%d pos=%s" % [
			_current_level, str(pos)
		])
		return false

	var target_level: int = target_stair.get("to_level", 1)
	if not _all_levels.has(target_level):
		push_error("DungeonMapController.use_stairs: level %d not loaded" % target_level)
		return false

	var old_level := _current_level
	_current_level = target_level
	_map = _all_levels[_current_level]

	var target_pos := Vector2i(
		target_stair.get("to_col", 0),
		target_stair.get("to_row", 0)
	)

	# Move party to target cell — use formation if available
	var formation_positions: Dictionary = _formation_manager.compute_dungeon_positions(
		target_pos, _party_data_ref, _map) if _party_data_ref != null else {}

	for eid in _party_entity_ids:
		if formation_positions.has(eid):
			_map.set_entity_pos(eid, formation_positions[eid])
		else:
			_map.set_entity_pos(eid, target_pos)

	_reveal_entry_room()
	level_changed.emit(old_level, target_level)
	return true


# ---------------------------------------------------------------------------
# Entity management
# ---------------------------------------------------------------------------

## Adds [param entity_id] to the party. Places them at the current party position.
func add_party_member(entity_id: String) -> void:
	if entity_id in _party_entity_ids:
		return
	_party_entity_ids.append(entity_id)
	if _map != null:
		_map.set_entity_pos(entity_id, get_party_position())


## Removes [param entity_id] from the party.
func remove_party_member(entity_id: String) -> void:
	_party_entity_ids.erase(entity_id)
	if _map != null:
		_map.remove_entity(entity_id)


## Returns a copy of the party entity IDs array.
func get_entity_ids() -> Array[String]:
	return _party_entity_ids.duplicate()


## Returns the grid position of the first party member, or entry_pos if no members.
func get_party_position() -> Vector2i:
	if _map == null:
		return Vector2i.ZERO
	if _party_entity_ids.is_empty():
		return _map.entry_pos
	var first_id := _party_entity_ids[0]
	var pos := _map.get_entity_pos(first_id)
	if pos == Vector2i(-1, -1):
		return _map.entry_pos
	return pos


# ---------------------------------------------------------------------------
# Party data + formation
# ---------------------------------------------------------------------------

## Set the PartyData reference. Call before load_dungeon() for formation placement.
func set_party_data(party_data: PartyData) -> void:
	_party_data_ref = party_data


## Set the per-visit session state (for spike/wedge checks on door toggle).
func set_session_state(state: RefCounted) -> void:
	_session_state = state


## Returns the FormationManager for preset application.
func get_formation_manager() -> RefCounted:
	_ensure_managers()
	return _formation_manager


## Returns the DungeonOrderManager for order inspection.
func get_order_manager() -> RefCounted:
	_ensure_managers()
	return _order_manager


## Snap all members to formation around [param center_pos].
## Uses the current formation preset stored in PartyData.
func reform_formation(center_pos: Vector2i = Vector2i(-1, -1)) -> void:
	_ensure_managers()
	if _map == null or _party_data_ref == null:
		return
	var center := center_pos if center_pos != Vector2i(-1, -1) else get_party_position()
	var positions: Dictionary = _formation_manager.compute_dungeon_positions(center, _party_data_ref, _map)
	for eid in positions:
		var old_pos := _map.get_entity_pos(eid)
		var new_pos: Vector2i = positions[eid]
		if old_pos != new_pos:
			_map.set_entity_pos(eid, new_pos)
			entity_moved.emit(eid, old_pos, new_pos)
	_update_fog_for_all_members()
	party_moved.emit(center, center)


# ---------------------------------------------------------------------------
# Individual movement + order queue
# ---------------------------------------------------------------------------

## Queue a move order for a single entity via BFS pathfinding.
## Returns true if a valid path was found and queued.
func queue_move_order(entity_id: String, target_pos) -> bool:
	_ensure_managers()

	if use_voxel_renderer:
		return _queue_move_order_voxel(entity_id, target_pos)

	if _map == null:
		return false
	if not _map.has_cell(target_pos) or not _map.is_passable(target_pos):
		return false
	if _map.is_occupied_by_other(target_pos, entity_id):
		return false

	var start := _map.get_entity_pos(entity_id)
	if start == Vector2i(-1, -1):
		return false

	var path := _bfs_path(start, target_pos, entity_id)
	if path.is_empty():
		return false

	_order_manager.add_order(entity_id, "move", target_pos, path)
	return true


## Voxel path for queue_move_order.
func _queue_move_order_voxel(entity_id: String, target_pos) -> bool:
	if _voxel_map == null:
		return false
	var pos_3d: Vector3i = target_pos if target_pos is Vector3i else Vector3i(target_pos.x, target_pos.y, _current_level)
	if not _voxel_map.has_cell(pos_3d) or not _voxel_map.is_passable(pos_3d):
		return false
	if _voxel_map.is_occupied_by_other(pos_3d, entity_id):
		return false

	var start: Vector3i = _voxel_map.get_entity_pos(entity_id)
	if start == Vector3i(-1, -1, -1):
		return false

	# BFS on same level using 2D neighbors
	var path: Array = _bfs_path_voxel(start, pos_3d, entity_id)
	if path.is_empty():
		return false

	_order_manager.add_order(entity_id, "move", pos_3d, path)
	return true


## BFS pathfinding on VoxelMapData (same-level, 2D neighbors).
func _bfs_path_voxel(start: Vector3i, goal: Vector3i, mover_id: String = "") -> Array:
	if start == goal:
		return [goal]
	if _voxel_map == null:
		return []

	var frontier: Array = [start]
	var came_from: Dictionary = {start: null}
	var found := false

	var best_cell: Vector3i = start
	var best_dist: int = VoxelGrid.chebyshev_distance(start, goal)

	while not frontier.is_empty():
		var current: Vector3i = frontier.pop_front()
		if current == goal:
			found = true
			break

		var dist: int = VoxelGrid.chebyshev_distance(current, goal)
		if dist < best_dist and not _voxel_map.is_occupied_by_other(current, mover_id):
			best_dist = dist
			best_cell = current

		for neighbor: Vector3i in VoxelGrid.get_neighbors_2d(current):
			if came_from.has(neighbor):
				continue
			if not _voxel_map.has_cell(neighbor):
				continue
			if not _voxel_map.is_passable(neighbor) and neighbor != goal:
				continue
			came_from[neighbor] = current
			frontier.append(neighbor)

	if found and _voxel_map.is_occupied_by_other(goal, mover_id):
		found = false

	var path_target: Vector3i
	if found:
		path_target = goal
	elif best_cell != start:
		path_target = best_cell
	else:
		return []

	var path: Array = []
	var current: Vector3i = path_target
	while current != start:
		path.push_front(current)
		current = came_from[current]

	return path


## Queue a group move for all party members, maintaining formation.
## Returns true if the leader can reach the target.
func queue_group_move(target_pos: Vector2i) -> bool:
	_ensure_managers()
	if _map == null or _party_data_ref == null:
		return false

	# Leader = first entity in the party list
	if _party_entity_ids.is_empty():
		return false

	var leader_id := _party_entity_ids[0]
	var leader_pos := _map.get_entity_pos(leader_id)
	if leader_pos == Vector2i(-1, -1):
		return false

	# BFS path for the leader
	var leader_path := _bfs_path(leader_pos, target_pos, leader_id)
	if leader_path.is_empty():
		return false

	# Queue leader move
	_order_manager.add_order(leader_id, "move", target_pos, leader_path)

	# Compute formation positions at the target for other members
	var formation: Dictionary = _formation_manager.compute_dungeon_positions(
		target_pos, _party_data_ref, _map)

	for eid in _party_entity_ids:
		if eid == leader_id:
			continue
		var member_target: Vector2i = formation.get(eid, target_pos)
		var member_pos := _map.get_entity_pos(eid)
		if member_pos == Vector2i(-1, -1):
			continue
		var member_path := _bfs_path(member_pos, member_target, eid)
		if member_path.is_empty():
			# Fallback: path to leader target
			member_path = _bfs_path(member_pos, target_pos, eid)
		if not member_path.is_empty():
			_order_manager.add_order(eid, "move", member_target, member_path)
		else:
			# Can't reach — queue wait
			_order_manager.add_order(eid, "wait")

	return true


## Execute all queued orders simultaneously.
## Updates positions, fog, and returns result dict.
## Returns {moved_entities: Array[String], events: Array[Dictionary]}.
func execute_orders() -> Dictionary:
	_ensure_managers()
	var moved_entities: Array[String] = []
	var events: Array = []

	var orders: Dictionary = _order_manager.get_all_orders()
	_order_manager.clear()

	# --- Collision resolution: prevent two entities targeting the same cell ---
	# Build a map of move destinations to detect conflicts.
	var claimed_cells: Dictionary = {}  # Vector2i -> String (first claimant)

	# First pass: collect stationary entities (not moving) as occupied.
	var moving_eids: Dictionary = {}
	for eid in orders:
		if orders[eid].get("order_type", "") == "move":
			moving_eids[eid] = true

	for eid in _map.entity_positions:
		if not moving_eids.has(eid):
			claimed_cells[_map.entity_positions[eid]] = eid

	# Second pass: for each mover, claim the target or downgrade to wait.
	for eid in orders:
		var order: Dictionary = orders[eid]
		if order.get("order_type", "") != "move":
			continue
		var target: Vector2i = order.get("target_pos", Vector2i(-1, -1))
		if target == Vector2i(-1, -1):
			continue
		if claimed_cells.has(target):
			# Target already claimed — downgrade to wait.
			order["order_type"] = "wait"
		else:
			claimed_cells[target] = eid

	for eid in orders:
		var order: Dictionary = orders[eid]
		var order_type: String = order.get("order_type", "")

		match order_type:
			"move":
				var target: Vector2i = order.get("target_pos", Vector2i(-1, -1))
				var path: Array = order.get("path", [])
				if target == Vector2i(-1, -1) or path.is_empty():
					continue
				var old_pos := _map.get_entity_pos(eid)
				if _map.is_passable(target):
					_map.set_entity_pos(eid, target)
					entity_moved.emit(eid, old_pos, target)
					moved_entities.append(eid)

			"interact_door":
				var door_pos: Vector2i = order.get("target_pos", Vector2i(-1, -1))
				if door_pos != Vector2i(-1, -1):
					interact_door(door_pos)
					events.append({"type": "door_interaction", "entity_id": eid, "pos": door_pos})

			"search":
				events.append({"type": "search", "entity_id": eid})

			"listen":
				events.append({"type": "listen", "entity_id": eid})

			"wait":
				pass  # Explicit no-op

	# Update fog based on all member positions
	if not moved_entities.is_empty():
		_update_fog_for_all_members()
		var leader_pos := get_party_position()
		party_moved.emit(leader_pos, leader_pos)

	var result := {"moved_entities": moved_entities, "events": events}
	orders_executed.emit(result)
	return result


# ---------------------------------------------------------------------------
# BFS pathfinding
# ---------------------------------------------------------------------------

## BFS pathfinding from [param start] to [param goal] on the current map.
## Returns array of cells from start (exclusive) to goal (inclusive).
##
## Allies can route THROUGH occupied cells but will not select an occupied
## cell as the final destination. If [param mover_id] is provided, that
## entity's own position is excluded from occupancy checks.
##
## If the goal is unreachable or occupied, falls back to the closest
## reachable unoccupied cell (by Chebyshev distance to goal). Returns
## empty only if the entity cannot move at all (completely boxed in).
func _bfs_path(start: Vector2i, goal: Vector2i, mover_id: String = "") -> Array[Vector2i]:
	if start == goal:
		return [goal]
	if _map == null:
		return []

	var frontier: Array[Vector2i] = [start]
	var came_from: Dictionary = {start: null}
	var found := false

	# Track closest reachable UNOCCUPIED cell to the goal for fallback.
	var best_cell := start
	var best_dist: int = IsometricGrid.chebyshev_distance(start, goal)

	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		if current == goal:
			found = true
			break

		# Update best fallback cell (only unoccupied cells qualify).
		var dist: int = IsometricGrid.chebyshev_distance(current, goal)
		if dist < best_dist and not _map.is_occupied_by_other(current, mover_id):
			best_dist = dist
			best_cell = current

		# Allies can route through occupied cells — no occupancy check here.
		for neighbor in IsometricGrid.get_neighbors(current):
			if came_from.has(neighbor):
				continue
			if not _map.has_cell(neighbor):
				continue
			if not _map.is_passable(neighbor) and neighbor != goal:
				continue
			came_from[neighbor] = current
			frontier.append(neighbor)

	# If the goal was reached but is occupied by another entity, treat as
	# unreachable and fall through to the closest unoccupied fallback.
	if found and _map.is_occupied_by_other(goal, mover_id):
		found = false

	# Determine which cell to reconstruct path to
	var path_target: Vector2i
	if found:
		path_target = goal
	elif best_cell != start:
		# Fallback: closest reachable unoccupied cell to the goal
		path_target = best_cell
	else:
		# Can't move at all
		return []

	# Reconstruct path (excluding start)
	var path: Array[Vector2i] = []
	var current: Vector2i = path_target
	while current != start:
		path.push_front(current)
		current = came_from[current]

	return path


# ---------------------------------------------------------------------------
# Fog update for individual positions
# ---------------------------------------------------------------------------

## Update fog-of-war based on the union of all party members' positions.
func _update_fog_for_all_members() -> void:
	if _map == null:
		return

	# Mark all currently VISIBLE cells as EXPLORED first
	for pos in _map._cells.keys():
		if _map.get_fog(pos) == TacticalMapData.FogState.VISIBLE:
			_map.set_fog(pos, TacticalMapData.FogState.EXPLORED)

	# Then reveal around each member's position using per-entity light radius.
	# Cells illuminated by ANY party member are visible to ALL (shared vision).
	var any_light := false
	for eid in _party_entity_ids:
		var member_pos := _map.get_entity_pos(eid)
		if member_pos == Vector2i(-1, -1):
			continue

		var radius := _get_entity_visible_radius(eid)
		if radius <= 0:
			continue  # This entity has no light — skip (they see via allies)
		any_light = true

		# Reveal room if in one
		var room_id := _map.get_room_at(member_pos)
		if room_id >= 0:
			_reveal_room(room_id)
		else:
			# Corridor: reveal cells within this entity's light radius
			var visible_cells := IsometricGrid.get_cells_in_radius(member_pos, radius)
			for vc in visible_cells:
				if _map.has_cell(vc):
					_map.set_fog(vc, TacticalMapData.FogState.VISIBLE)

	fog_updated.emit()


# ---------------------------------------------------------------------------
# Lighting
# ---------------------------------------------------------------------------

## Set the DungeonLightManager for inventory-driven per-entity lighting.
func set_light_manager(manager: DungeonLightManager) -> void:
	_light_manager = manager


## Set the fallback radius used when no DungeonLightManager is available.
func set_fallback_light_radius(cells: int) -> void:
	_fallback_light_radius = cells


## Set darkvision bonus for a specific entity (e.g., dwarves, elves).
func set_entity_darkvision(entity_id: String, cells: int) -> void:
	_darkvision_bonuses[entity_id] = cells


## Returns the visible radius for a specific entity, accounting for their
## light source and darkvision. Used by _update_fog_for_all_members.
func _get_entity_visible_radius(entity_id: String) -> int:
	var light: int = 0
	if _light_manager != null:
		light = _light_manager.get_light_radius(entity_id)
	else:
		light = _fallback_light_radius
	var darkvision: int = _darkvision_bonuses.get(entity_id, 0)
	return light + darkvision


## Returns the maximum visible radius across all party members (legacy compat).
func get_visible_radius() -> int:
	var max_radius := 0
	for eid in _party_entity_ids:
		var r := _get_entity_visible_radius(eid)
		if r > max_radius:
			max_radius = r
	return max_radius


# ---------------------------------------------------------------------------
# State accessors
# ---------------------------------------------------------------------------

func get_map() -> TacticalMapData:
	return _map


## Returns the VoxelMapData (only valid when use_voxel_renderer is true).
func get_voxel_map() -> VoxelMapData:
	return _voxel_map


func get_current_level() -> int:
	return _current_level


func get_dungeon_id() -> String:
	return _dungeon_id


func get_dungeon_name() -> String:
	return _dungeon_name


## Returns true if the party is standing on a designated transition cell.
func is_on_transition_cell() -> bool:
	if use_voxel_renderer:
		if _voxel_map == null:
			return false
		return _voxel_map.is_transition_cell(get_party_position_3d())
	if _map == null:
		return false
	return _map.is_transition_cell(get_party_position())


## Returns the 3D position of the party leader (voxel mode).
func get_party_position_3d() -> Vector3i:
	if _voxel_map == null:
		return Vector3i.ZERO
	if _party_entity_ids.is_empty():
		return _voxel_map.entry_pos
	var first_id := _party_entity_ids[0]
	var pos := _voxel_map.get_entity_pos(first_id)
	if pos == Vector3i(-1, -1, -1):
		return _voxel_map.entry_pos
	return pos


## Returns the entity position in voxel mode.
func get_entity_pos_3d(entity_id: String) -> Vector3i:
	if _voxel_map == null:
		return Vector3i(-1, -1, -1)
	return _voxel_map.get_entity_pos(entity_id)


# ---------------------------------------------------------------------------
# Room reveal (fog of war)
# ---------------------------------------------------------------------------

func _reveal_entry_room() -> void:
	var party_pos := get_party_position()
	var room_id := _map.get_room_at(party_pos)
	if room_id >= 0:
		_reveal_room(room_id)
	else:
		# Even if not in a named room, mark the entry cell as visible
		_map.set_fog(party_pos, TacticalMapData.FogState.VISIBLE)
		fog_updated.emit()


func _reveal_room(room_id: int) -> void:
	var cells := _map.get_room_cells(room_id)
	var boundary := _map.get_room_boundary_cells(room_id)

	for c in cells:
		_map.set_fog(c, TacticalMapData.FogState.VISIBLE)

	for c in boundary:
		if _map.get_fog(c) == TacticalMapData.FogState.HIDDEN:
			_map.set_fog(c, TacticalMapData.FogState.VISIBLE)

	room_revealed.emit(room_id)
	fog_updated.emit()


func _update_visibility_on_move(old_pos: Vector2i, new_pos: Vector2i) -> void:
	var old_room := _map.get_room_at(old_pos)
	var new_room := _map.get_room_at(new_pos)

	# If party moved out of a room, mark its cells as EXPLORED
	if old_room != new_room and old_room >= 0:
		for c in _map.get_room_cells(old_room):
			if _map.get_fog(c) == TacticalMapData.FogState.VISIBLE:
				_map.set_fog(c, TacticalMapData.FogState.EXPLORED)

	# Reveal new room if entered
	if new_room >= 0 and new_room != old_room:
		_reveal_room(new_room)
	else:
		fog_updated.emit()


# ---------------------------------------------------------------------------
# Voxel fog reveal helpers
# ---------------------------------------------------------------------------

func _reveal_entry_room_voxel() -> void:
	var party_pos := get_party_position_3d()
	var room_id := _voxel_map.get_room_at(party_pos)
	if room_id >= 0:
		_reveal_room_voxel(room_id)
	else:
		_voxel_map.set_fog(party_pos, "visible")
		# Also reveal immediate neighbors
		for neighbor: Vector3i in VoxelGrid.get_neighbors_2d(party_pos):
			if _voxel_map.has_cell(neighbor):
				_voxel_map.set_fog(neighbor, "visible")
		fog_updated.emit()


func _reveal_room_voxel(room_id: int) -> void:
	var cells := _voxel_map.get_room_cells(room_id)
	var boundary := _voxel_map.get_room_boundary_cells(room_id)

	for c: Vector3i in cells:
		_voxel_map.set_fog(c, "visible")

	for c: Vector3i in boundary:
		if _voxel_map.get_fog(c) == "hidden":
			_voxel_map.set_fog(c, "visible")

	room_revealed.emit(room_id)
	fog_updated.emit()


## Voxel fog update for all party members.
func _update_fog_for_all_members_voxel() -> void:
	if _voxel_map == null:
		return

	# Mark all currently "visible" cells as "explored" first
	for cell: VoxelCell in _voxel_map.get_all_cells():
		if cell.fog_state == "visible":
			cell.fog_state = "explored"

	# Reveal around each member's position
	for eid in _party_entity_ids:
		var member_pos := _voxel_map.get_entity_pos(eid)
		if member_pos == Vector3i(-1, -1, -1):
			continue

		var radius := _get_entity_visible_radius(eid)
		if radius <= 0:
			continue

		var room_id := _voxel_map.get_room_at(member_pos)
		if room_id >= 0:
			_reveal_room_voxel(room_id)
		else:
			# Corridor: reveal cells within radius on same level
			for neighbor: Vector3i in VoxelGrid.get_neighbors_2d(member_pos):
				if _voxel_map.has_cell(neighbor):
					_voxel_map.set_fog(neighbor, "visible")
			_voxel_map.set_fog(member_pos, "visible")

	fog_updated.emit()


# ---------------------------------------------------------------------------
# Legacy-to-voxel format converter
# ---------------------------------------------------------------------------

## Converts a legacy dungeon dict (levels[] + stairs[]) to a single VoxelMapData.
## Each old level N maps to voxel levels N*2 (floor) and N*2+1 (ceiling headroom).
## Walls are stamped as solid at both floor and ceiling levels.
static func _convert_legacy_to_voxel(dungeon_dict: Dictionary) -> VoxelMapData:
	var vmap := VoxelMapData.new()
	vmap.id = str(dungeon_dict.get("id", ""))
	vmap.name = str(dungeon_dict.get("name", ""))

	var levels_array: Array = dungeon_dict.get("levels", [])
	var first_level := true

	for level_data: Dictionary in levels_array:
		var level_num: int = level_data.get("level", 1)
		var voxel_floor: int = level_num * 2
		var voxel_ceiling: int = voxel_floor + 1

		var entry_col: int = level_data.get("entry_col", 0)
		var entry_row: int = level_data.get("entry_row", 0)
		if first_level:
			vmap.entry_pos = Vector3i(entry_col, entry_row, voxel_floor)
			first_level = false

		var cells_array: Array = level_data.get("cells", [])
		for cell_data: Dictionary in cells_array:
			var col: int = cell_data.get("col", 0)
			var row: int = cell_data.get("row", 0)
			var tf: String = cell_data.get("terrain_feature", "open")

			var vcell := VoxelCell.new()
			vcell.col = col
			vcell.row = row
			vcell.level = voxel_floor
			vcell.cover_value = cell_data.get("cover_value", 0)
			vcell.door_state = cell_data.get("door_state", "")
			vcell.door_type = cell_data.get("door_type", "")
			vcell.door_detected = cell_data.get("door_detected", true)

			match tf:
				"wall_stone", "rock":
					vcell.solidity = "solid"
					vcell.feature = tf
					vcell.floor_type = "none"
					# Also stamp ceiling level as solid
					var ceil_cell := VoxelCell.new()
					ceil_cell.col = col
					ceil_cell.row = row
					ceil_cell.level = voxel_ceiling
					ceil_cell.solidity = "solid"
					ceil_cell.feature = tf
					ceil_cell.floor_type = "none"
					vmap.set_cell(Vector3i(col, row, voxel_ceiling), ceil_cell)
				"wall_wood":
					vcell.solidity = "solid"
					vcell.feature = "wall_wood"
					vcell.floor_type = "none"
					var ceil_cell := VoxelCell.new()
					ceil_cell.col = col
					ceil_cell.row = row
					ceil_cell.level = voxel_ceiling
					ceil_cell.solidity = "solid"
					ceil_cell.feature = "wall_wood"
					ceil_cell.floor_type = "none"
					vmap.set_cell(Vector3i(col, row, voxel_ceiling), ceil_cell)
				"door", "door_locked", "door_secret", "portcullis":
					vcell.solidity = "air"
					vcell.feature = "open"
					vcell.floor_type = "stone"
					if vcell.door_state.is_empty():
						vcell.door_state = "closed"
				"stairs_up":
					vcell.solidity = "air"
					vcell.feature = "stairs_up_N"
					vcell.floor_type = "stone"
				"stairs_down":
					vcell.solidity = "air"
					vcell.feature = "stairs_down_S"
					vcell.floor_type = "stone"
				"lever":
					vcell.solidity = "air"
					vcell.feature = "lever"
					vcell.floor_type = "stone"
				_:  # "open" and anything else
					vcell.solidity = "air"
					vcell.feature = tf if tf != "" else "open"
					vcell.floor_type = "stone"

			vmap.set_cell(Vector3i(col, row, voxel_floor), vcell)

		# Set transition cells from entry position
		var tc_pos := Vector3i(entry_col, entry_row, voxel_floor)
		if tc_pos not in vmap.transition_cells:
			vmap.transition_cells.append(tc_pos)

	vmap.detect_rooms()
	return vmap
