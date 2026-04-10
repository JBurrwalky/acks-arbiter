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


# ---------------------------------------------------------------------------
# Private state
# ---------------------------------------------------------------------------

var _dungeon_id: String = ""
var _dungeon_name: String = ""
var _all_levels: Dictionary = {}   # int (level number) → TacticalMapData
var _stairs: Array = []            # Array of stair connection Dictionaries from JSON
var _current_level: int = 1
var _map: TacticalMapData          # Alias for _all_levels[_current_level]

## Entity IDs of all party members (moved as a group in D-4).
var _party_entity_ids: Array[String] = []

## Torch/light radius in cells (30 ft = 6 cells in ACKS).
var _light_radius: int = 6

## Additional visibility from darkvision (60 ft darkvision = +6).
var _darkvision_bonus: int = 0

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

	# Toggle open/closed for unlocked/detected-secret doors
	var old_state := door_state
	var new_state := "open" if door_state == "closed" else "closed"
	_map.set_door_state(pos, new_state)
	door_state_changed.emit(pos, old_state, new_state)
	return true


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
func queue_move_order(entity_id: String, target_pos: Vector2i) -> bool:
	_ensure_managers()
	if _map == null:
		return false
	if not _map.has_cell(target_pos) or not _map.is_passable(target_pos):
		return false

	var start := _map.get_entity_pos(entity_id)
	if start == Vector2i(-1, -1):
		return false

	var path := _bfs_path(start, target_pos)
	if path.is_empty():
		return false

	_order_manager.add_order(entity_id, "move", target_pos, path)
	return true


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
	var leader_path := _bfs_path(leader_pos, target_pos)
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
		var member_path := _bfs_path(member_pos, member_target)
		if member_path.is_empty():
			# Fallback: path to leader target
			member_path = _bfs_path(member_pos, target_pos)
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

	for eid in orders:
		var order: Dictionary = orders[eid]
		var order_type: String = order.get("order_type", "")

		match order_type:
			"move":
				var target: Vector2i = order.get("target_pos", Vector2i(-1, -1))
				var path: Array = order.get("path", [])
				if target == Vector2i(-1, -1) or path.is_empty():
					continue
				# Move entity step by step (for now, teleport to destination)
				var old_pos := _map.get_entity_pos(eid)
				# Walk the path: move one step at a time (adjacent steps)
				# For simplicity in exploration, move to final target directly
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

## Simple BFS pathfinding from [param start] to [param goal] on the current map.
## Returns array of cells from start (exclusive) to goal (inclusive), or empty if no path.
func _bfs_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	if start == goal:
		return [goal]
	if _map == null:
		return []

	var frontier: Array[Vector2i] = [start]
	var came_from: Dictionary = {start: null}
	var found := false

	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		if current == goal:
			found = true
			break
		for neighbor in IsometricGrid.get_neighbors(current):
			if came_from.has(neighbor):
				continue
			if not _map.has_cell(neighbor):
				continue
			if not _map.is_passable(neighbor) and neighbor != goal:
				continue
			came_from[neighbor] = current
			frontier.append(neighbor)

	if not found:
		return []

	# Reconstruct path (excluding start)
	var path: Array[Vector2i] = []
	var current: Vector2i = goal
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

	# Then reveal around each member's position
	var radius := get_visible_radius()
	for eid in _party_entity_ids:
		var member_pos := _map.get_entity_pos(eid)
		if member_pos == Vector2i(-1, -1):
			continue

		# Reveal room if in one
		var room_id := _map.get_room_at(member_pos)
		if room_id >= 0:
			_reveal_room(room_id)
		else:
			# Corridor: reveal cells within light radius
			var visible_cells := IsometricGrid.get_cells_in_radius(member_pos, radius)
			for vc in visible_cells:
				if _map.has_cell(vc):
					_map.set_fog(vc, TacticalMapData.FogState.VISIBLE)

	fog_updated.emit()


# ---------------------------------------------------------------------------
# Lighting
# ---------------------------------------------------------------------------

func set_light_radius(cells: int) -> void:
	_light_radius = cells


func set_darkvision_bonus(cells: int) -> void:
	_darkvision_bonus = cells


func get_visible_radius() -> int:
	return _light_radius + _darkvision_bonus


# ---------------------------------------------------------------------------
# State accessors
# ---------------------------------------------------------------------------

func get_map() -> TacticalMapData:
	return _map


func get_current_level() -> int:
	return _current_level


func get_dungeon_id() -> String:
	return _dungeon_id


func get_dungeon_name() -> String:
	return _dungeon_name


## Returns true if the party is standing on a designated transition cell.
func is_on_transition_cell() -> bool:
	if _map == null:
		return false
	return _map.is_transition_cell(get_party_position())


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
