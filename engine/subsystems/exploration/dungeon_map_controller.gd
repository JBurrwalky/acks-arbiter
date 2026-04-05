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
	for eid in _party_entity_ids:
		_map.set_entity_pos(eid, entry)

	_reveal_entry_room()
	map_loaded.emit(_dungeon_id)


## Attempts to move all party members to [param target].
## Returns true on success, false if the move is invalid.
func move_party(target: Vector2i) -> bool:
	if _map == null:
		push_error("DungeonMapController.move_party: no map loaded")
		return false

	var party_pos := get_party_position()

	if not IsometricGrid.is_adjacent(party_pos, target):
		return false

	if not _map.is_passable(target):
		return false

	var old_pos := party_pos

	# Move all party entities to target
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

	var party_pos := get_party_position()
	if not IsometricGrid.is_adjacent(party_pos, pos):
		push_error("DungeonMapController.interact_door: pos %s not adjacent to party at %s" % [
			str(pos), str(party_pos)
		])
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

	# Move party to target cell
	for eid in _party_entity_ids:
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
