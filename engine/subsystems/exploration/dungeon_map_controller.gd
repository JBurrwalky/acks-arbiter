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
## Positions are Vector3i in voxel mode, Vector2i in legacy TacticalMapData mode.
## Params are untyped so both ride through until the legacy code path is deleted in D.2.
signal party_moved(from_pos, to_pos)
signal entity_moved(entity_id: String, from_pos, to_pos)
signal room_revealed(room_id: int)
signal fog_updated()
signal door_state_changed(pos, old_state: String, new_state: String)
signal level_changed(from_level: int, to_level: int)
signal orders_executed(result: Dictionary)

## Relay signals for renderer-driven movement animation.
## DungeonExploreState emits these; the renderer connects in setup().
signal movement_animation_requested(entity_id: String, path: Array, cells_per_round: float)
signal movement_animation_cancelled(entity_id: String)


# ---------------------------------------------------------------------------
# Private state
# ---------------------------------------------------------------------------

var _dungeon_id: String = ""
var _dungeon_name: String = ""
var _current_level: int = 0

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

## Movement resolver for 3D pathfinding (stair-aware, level-spanning).
## Only used in voxel mode.
var _movement_resolver: MovementResolver = null

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
	if _movement_resolver == null:
		_movement_resolver = MovementResolver.new()
	if _movement_resolver != null and _voxel_map != null:
		_movement_resolver.set_voxel_map(_voxel_map)
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
	_load_dungeon_voxel(dungeon_dict, spawn_pos)


## Places party members at and around [param entry], avoiding stacking when
## adjacent passable cells are available. Leader stays at entry; others try
## each of the 8 same-level neighbors in turn. All-blocked -> stack at entry.
func _scatter_party_at_entry(entry: Vector3i) -> void:
	if _party_entity_ids.is_empty():
		return
	# Leader at entry
	_voxel_map.set_entity_pos(_party_entity_ids[0], entry)
	var occupied: Dictionary = {entry: true}
	for i in range(1, _party_entity_ids.size()):
		var eid: String = _party_entity_ids[i]
		var placed := false
		for neighbor: Vector3i in VoxelGrid.get_neighbors_2d(entry):
			if occupied.has(neighbor):
				continue
			if not _voxel_map.has_cell(neighbor):
				continue
			if not _voxel_map.is_passable(neighbor):
				continue
			_voxel_map.set_entity_pos(eid, neighbor)
			occupied[neighbor] = true
			placed = true
			break
		if not placed:
			# All 8 neighbors blocked — fall back to entry (last resort)
			_voxel_map.set_entity_pos(eid, entry)


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

	# Position party at entry with 8-neighbor scatter (no stacking).
	_scatter_party_at_entry(entry_3d)

	# Reveal entry room
	_reveal_entry_room_voxel()
	map_loaded.emit(_dungeon_id)


## Attempts to move all party members to [param target].
## Returns true on success, false if the move is invalid.
## Backward-compat wrapper: queues a group move and executes immediately.
## [param target] is Vector3i; Vector2i callers get z inferred from _current_level.
func move_party(target) -> bool:
	_ensure_managers()
	return _move_party_voxel(target)


## Voxel-mode implementation of move_party.
## Validates adjacency + stair-aware passability via MovementResolver.path_bfs_3d.
func _move_party_voxel(target) -> bool:
	if _voxel_map == null:
		push_error("DungeonMapController._move_party_voxel: no voxel map loaded")
		return false

	var pos_3d: Vector3i = target if target is Vector3i else Vector3i(target.x, target.y, _current_level)
	var party_pos := get_party_position_3d()

	if not VoxelGrid.is_adjacent(party_pos, pos_3d):
		return false

	# Use MovementResolver to validate stair-aware entry (level-diff + feature check).
	# path_bfs_3d returns [start, target] for a 1-step reachable move, empty if blocked.
	var validation_path: Array = _movement_resolver.path_bfs_3d(party_pos, pos_3d)
	if validation_path.is_empty():
		return false

	var old_pos := party_pos

	# Use formation-aware group move if party data is available
	if _party_data_ref != null and _party_entity_ids.size() > 1:
		queue_group_move(pos_3d)
		execute_orders()
		return true

	# Fallback: move all entities to same cell
	for eid in _party_entity_ids:
		var from: Vector3i = _voxel_map.get_entity_pos(eid)
		_voxel_map.set_entity_pos(eid, pos_3d)
		entity_moved.emit(eid, from, pos_3d)

	_current_level = pos_3d.z
	_update_visibility_on_move(old_pos, pos_3d)
	party_moved.emit(old_pos, pos_3d)
	return true


## Returns true if the party can legally move to [param target].
## [param target] is Vector3i; Vector2i is coerced with z from _current_level.
func can_move_to(target) -> bool:
	if _voxel_map == null:
		return false
	var pos_3d: Vector3i = target if target is Vector3i else Vector3i(target.x, target.y, _current_level)
	var party_pos := get_party_position_3d()
	if not VoxelGrid.is_adjacent(party_pos, pos_3d):
		return false
	_ensure_managers()
	var validation_path: Array = _movement_resolver.path_bfs_3d(party_pos, pos_3d)
	return not validation_path.is_empty()


## Attempts to interact with a door at [param pos].
## pos must be adjacent to the party's current position.
## pos is Vector3i in voxel mode, Vector2i in legacy mode.
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
func interact_door(pos) -> bool:
	return _interact_door_voxel(pos)


## Voxel-mode implementation of interact_door. Same rule gates as legacy.
func _interact_door_voxel(pos) -> bool:
	if _voxel_map == null:
		return false

	var pos_3d: Vector3i = pos if pos is Vector3i else Vector3i(pos.x, pos.y, _current_level)

	# Any party member adjacent (3D Chebyshev ≤ 1) to the door can interact.
	var any_adjacent := false
	for eid in _party_entity_ids:
		var member_pos: Vector3i = _voxel_map.get_entity_pos(eid)
		if member_pos != Vector3i(-1, -1, -1) and VoxelGrid.is_adjacent(member_pos, pos_3d):
			any_adjacent = true
			break
	if not any_adjacent:
		return false

	if not _voxel_map.is_door(pos_3d):
		push_error("DungeonMapController.interact_door: no door at %s" % str(pos_3d))
		return false

	var cell := _voxel_map.get_cell(pos_3d)
	var door_type := cell.door_type
	var door_state := cell.door_state

	# Arch is always open — cannot be interacted with
	if door_type == "arch":
		return false

	# Destroyed door — permanently open, no interaction
	if door_state == "destroyed":
		return false

	# Secret door that hasn't been detected yet — search check needed first.
	# Only blocks secret doors; other types don't set door_detected.
	if door_type == "secret" and not cell.door_detected:
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
			and _session_state.is_spiked(pos_3d):
		return false

	# Wedged open — cannot close until wedge is removed
	if _session_state != null and _session_state.has_method("is_wedged") \
			and _session_state.is_wedged(pos_3d):
		return false

	# Toggle open/closed for unlocked/detected-secret doors
	var old_state := door_state
	var new_state := "open" if door_state == "closed" else "closed"
	_voxel_map.set_door_state(pos_3d, new_state)
	door_state_changed.emit(pos_3d, old_state, new_state)
	return true


## Queue a compound "move to door + interact" order for an entity.
## If the entity is already adjacent to the door, interacts immediately and
## returns "immediate". Otherwise pathfinds to the nearest passable cell adjacent
## to the door and queues a move_and_interact_door order, returning "queued".
## [param door_pos] is Vector3i in voxel mode, Vector2i in legacy mode.
## Returns "" if no path or door is invalid.
func queue_door_interaction_order(entity_id: String, door_pos) -> String:
	_ensure_managers()
	return _queue_door_interaction_order_voxel(entity_id, door_pos)


## Voxel-mode path for queue_door_interaction_order.
func _queue_door_interaction_order_voxel(entity_id: String, door_pos) -> String:
	if _voxel_map == null:
		return ""

	var door_3d: Vector3i = door_pos if door_pos is Vector3i else Vector3i(door_pos.x, door_pos.y, _current_level)
	var entity_pos: Vector3i = _voxel_map.get_entity_pos(entity_id)
	if entity_pos == Vector3i(-1, -1, -1):
		return ""

	# Already adjacent (3D Chebyshev ≤ 1) → interact immediately
	if VoxelGrid.is_adjacent(entity_pos, door_3d):
		if interact_door(door_3d):
			return "immediate"
		return ""

	# Find nearest passable neighbor on the same level to pathfind to.
	var door_neighbors := VoxelGrid.get_neighbors_2d(door_3d)
	var best_path: Array = []
	var best_path_len := 999999

	for neighbor: Vector3i in door_neighbors:
		if not _voxel_map.has_cell(neighbor) or not _voxel_map.is_passable(neighbor):
			continue
		var path: Array = _bfs_path_voxel(entity_pos, neighbor, entity_id)
		if not path.is_empty() and path.size() < best_path_len:
			best_path = path
			best_path_len = path.size()

	if best_path.is_empty():
		return ""

	_order_manager.add_order(entity_id, "move_and_interact_door", door_3d, best_path)
	return "queued"


## Given a stair cell [param pos], returns the coordinate on the connected
## level that the stair leads to. Returns Vector3i(-1, -1, -1) if pos is not
## a stair cell. Voxel mode only.
##
## Preference order:
##   1. Explicit stair_target_col/row/level on the cell (set by the authored
##      dungeon when geometric inference doesn't apply).
##   2. Direction-suffix inference: stairs_up_<DIR> / stairs_down_<DIR> — one
##      horizontal step in DIR and one level up or down.
func get_stair_target(pos: Vector3i) -> Vector3i:
	if _voxel_map == null:
		return Vector3i(-1, -1, -1)
	var cell := _voxel_map.get_cell(pos)
	if cell == null:
		return Vector3i(-1, -1, -1)

	# 1. Explicit pairing takes priority.
	if cell.stair_target_col != -1 \
			and cell.stair_target_row != -1 \
			and cell.stair_target_level != -1:
		return Vector3i(cell.stair_target_col, cell.stair_target_row, cell.stair_target_level)

	var feat: String = cell.feature
	var going_up: bool
	var suffix: String
	if feat.begins_with("stairs_up_"):
		going_up = true
		suffix = feat.substr("stairs_up_".length())
	elif feat.begins_with("stairs_down_"):
		going_up = false
		suffix = feat.substr("stairs_down_".length())
	else:
		return Vector3i(-1, -1, -1)

	var dir_keys: Array = VoxelGrid.Direction.keys()
	var dir_idx: int = dir_keys.find(suffix)
	if dir_idx < 0:
		return Vector3i(-1, -1, -1)
	var offset: Vector2i = VoxelGrid.DIRECTION_OFFSETS[dir_idx]
	var z_delta: int = 1 if going_up else -1
	return Vector3i(pos.x + offset.x, pos.y + offset.y, pos.z + z_delta)


## Teleports the party to [param target_pos] and its immediate neighbors.
## Used by stair traversal (Ascend/Descend) when the stair's destination is
## not spatially adjacent to the stair cell — bypasses adjacency/BFS checks
## and places each party member around the target with the same 8-neighbor
## scatter logic used on dungeon entry.
## Returns true on success, false if the voxel map is absent or target
## is not a valid cell.
func teleport_party_to(target_pos: Vector3i) -> bool:
	if _voxel_map == null:
		return false
	if not _voxel_map.has_cell(target_pos):
		push_error("DungeonMapController.teleport_party_to: no cell at %s" % str(target_pos))
		return false
	if not _voxel_map.is_passable(target_pos):
		push_error("DungeonMapController.teleport_party_to: target %s is not passable" % str(target_pos))
		return false

	var old_pos := get_party_position_3d()
	_scatter_party_at_entry(target_pos)
	_current_level = target_pos.z

	# Fire per-entity moved signals so renderer/handlers sync.
	for eid in _party_entity_ids:
		var new_pos: Vector3i = _voxel_map.get_entity_pos(eid)
		entity_moved.emit(eid, old_pos, new_pos)

	# Visibility + level follow + fog.
	if old_pos.z != target_pos.z:
		level_changed.emit(old_pos.z, target_pos.z)
	_update_visibility_on_move(old_pos, target_pos)
	_update_fog_for_all_members()
	party_moved.emit(old_pos, target_pos)
	return true


# ---------------------------------------------------------------------------
# Entity management
# ---------------------------------------------------------------------------

## Adds [param entity_id] to the party.
## Entity placement on the voxel map happens at load_dungeon / reveal time;
## this helper only manages the party-membership list.
func add_party_member(entity_id: String) -> void:
	if entity_id in _party_entity_ids:
		return
	_party_entity_ids.append(entity_id)


## Removes [param entity_id] from the party and from the voxel map.
func remove_party_member(entity_id: String) -> void:
	_party_entity_ids.erase(entity_id)
	if _voxel_map != null:
		_voxel_map.remove_entity(entity_id)


## Returns a copy of the party entity IDs array.
func get_entity_ids() -> Array[String]:
	return _party_entity_ids.duplicate()


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


# ---------------------------------------------------------------------------
# Individual movement + order queue
# ---------------------------------------------------------------------------

## Queue a move order for a single entity via BFS pathfinding.
## Returns true if a valid path was found and queued.
func queue_move_order(entity_id: String, target_pos) -> bool:
	_ensure_managers()
	return _queue_move_order_voxel(entity_id, target_pos)


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

	var path: Array
	if start.z != pos_3d.z:
		# Multi-level move — delegate to MovementResolver for stair-aware pathfinding.
		_ensure_managers()
		path = _movement_resolver.path_bfs_3d(start, pos_3d)
	else:
		# Same-level — local BFS with fallback-to-closest-unoccupied-cell semantics.
		path = _bfs_path_voxel(start, pos_3d, entity_id)

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
## [param target_pos] is Vector3i in voxel mode, Vector2i in legacy mode.
func queue_group_move(target_pos) -> bool:
	_ensure_managers()
	return _queue_group_move_voxel(target_pos)


## Voxel-mode group move: leader paths via MovementResolver (stair-aware);
## followers place relative to the leader using FormationManager's preset grid
## (collapse chain: full → double column → single column → stack on leader).
## When [member _party_data_ref] is null (headless tests, no PartyData wired),
## falls back to ring-scatter around the target.
func _queue_group_move_voxel(target_pos) -> bool:
	if _voxel_map == null:
		return false
	if _party_entity_ids.is_empty():
		return false

	var target_3d: Vector3i = target_pos if target_pos is Vector3i else Vector3i(target_pos.x, target_pos.y, _current_level)

	var leader_id := _party_entity_ids[0]
	var leader_pos: Vector3i = _voxel_map.get_entity_pos(leader_id)
	if leader_pos == Vector3i(-1, -1, -1):
		return false

	# Leader path via MovementResolver (stair/ramp-aware, multi-level-capable).
	var leader_path: Array = _movement_resolver.path_bfs_3d(leader_pos, target_3d)
	if leader_path.is_empty():
		return false
	_order_manager.add_order(leader_id, "move", target_3d, leader_path)

	# Follower placement strategy.
	# (1) If PartyData is wired, use FormationManager.compute_dungeon_positions_3d
	#     which respects the active preset and collapses when corridors narrow.
	# (2) Otherwise fall back to ring-scatter around target_3d.
	var formation_targets: Dictionary = {}
	if _party_data_ref != null and _formation_manager != null \
			and _formation_manager.has_method("compute_dungeon_positions_3d"):
		formation_targets = _formation_manager.compute_dungeon_positions_3d(
			target_3d, _party_data_ref, _voxel_map)

	var claimed: Dictionary = {target_3d: leader_id}
	const MAX_RING_RADIUS := 4  # cells — fallback only

	for i in range(1, _party_entity_ids.size()):
		var eid: String = _party_entity_ids[i]
		var member_pos: Vector3i = _voxel_map.get_entity_pos(eid)
		if member_pos == Vector3i(-1, -1, -1):
			continue

		var member_target := Vector3i(-1, -1, -1)

		# Preferred: formation-assigned cell.
		if formation_targets.has(eid):
			var formation_cell: Vector3i = formation_targets[eid]
			if formation_cell != leader_pos and not claimed.has(formation_cell) \
					and _voxel_map.has_cell(formation_cell) \
					and _voxel_map.is_passable(formation_cell) \
					and not _voxel_map.is_occupied_by_other(formation_cell, eid):
				member_target = formation_cell

		# Fallback: ring-scatter (keeps headless tests + unplaced members moving).
		if member_target == Vector3i(-1, -1, -1):
			member_target = _find_scatter_cell(target_3d, eid, claimed, MAX_RING_RADIUS)

		if member_target == Vector3i(-1, -1, -1):
			# Nothing worked — member waits this turn.
			_order_manager.add_order(eid, "wait")
			continue

		claimed[member_target] = eid
		var member_path: Array = _movement_resolver.path_bfs_3d(member_pos, member_target)
		if member_path.is_empty():
			# Unreachable — drop the claim and wait.
			claimed.erase(member_target)
			_order_manager.add_order(eid, "wait")
		else:
			_order_manager.add_order(eid, "move", member_target, member_path)

	return true


## Finds the nearest cell to [param center] (by Chebyshev distance) that is
## passable, not [claimed] by any other party member, and not occupied by a
## different entity. Searches outward in rings up to [max_radius] cells.
## Returns Vector3i(-1, -1, -1) if no valid cell is found.
func _find_scatter_cell(center: Vector3i, mover_id: String,
		claimed: Dictionary, max_radius: int) -> Vector3i:
	if _voxel_map == null:
		return Vector3i(-1, -1, -1)
	for r in range(1, max_radius + 1):
		# Generate the perimeter of the ring at distance r (same-level).
		for dc in range(-r, r + 1):
			for dr in range(-r, r + 1):
				# Only perimeter cells (Chebyshev == r).
				if maxi(abs(dc), abs(dr)) != r:
					continue
				var candidate := Vector3i(center.x + dc, center.y + dr, center.z)
				if claimed.has(candidate):
					continue
				if not _voxel_map.has_cell(candidate) or not _voxel_map.is_passable(candidate):
					continue
				if _voxel_map.is_occupied_by_other(candidate, mover_id):
					continue
				return candidate
	return Vector3i(-1, -1, -1)


## Execute all queued orders simultaneously.
## Updates positions, fog, and returns result dict.
## Returns {moved_entities: Array[String], events: Array[Dictionary]}.
func execute_orders() -> Dictionary:
	_ensure_managers()
	return _execute_orders_voxel()


## Voxel-mode implementation of execute_orders. Mirrors the legacy
## collision-resolution + move-commit logic using Vector3i positions.
func _execute_orders_voxel() -> Dictionary:
	var moved_entities: Array[String] = []
	var events: Array = []

	var orders: Dictionary = _order_manager.get_all_orders()
	_order_manager.clear()

	# Collision resolution: prevent two entities targeting the same cell.
	var claimed_cells: Dictionary = {}

	var moving_eids: Dictionary = {}
	for eid in orders:
		if orders[eid].get("order_type", "") == "move":
			moving_eids[eid] = true

	for eid in _voxel_map.entity_positions:
		if not moving_eids.has(eid):
			claimed_cells[_voxel_map.entity_positions[eid]] = eid

	for eid in orders:
		var order: Dictionary = orders[eid]
		if order.get("order_type", "") != "move":
			continue
		var target = order.get("target_pos", null)
		if target == null or not (target is Vector3i) or target == Vector3i(-1, -1, -1):
			continue
		if claimed_cells.has(target):
			order["order_type"] = "wait"
		else:
			claimed_cells[target] = eid

	for eid in orders:
		var order: Dictionary = orders[eid]
		var order_type: String = order.get("order_type", "")

		match order_type:
			"move":
				var target = order.get("target_pos", null)
				var path: Array = order.get("path", [])
				if target == null or not (target is Vector3i) or path.is_empty():
					continue
				var old_pos: Vector3i = _voxel_map.get_entity_pos(eid)
				if _voxel_map.is_passable(target):
					_voxel_map.set_entity_pos(eid, target)
					entity_moved.emit(eid, old_pos, target)
					moved_entities.append(eid)

			"interact_door":
				var door_pos = order.get("target_pos", null)
				if door_pos != null and door_pos is Vector3i and door_pos != Vector3i(-1, -1, -1):
					interact_door(door_pos)
					events.append({"type": "door_interaction", "entity_id": eid, "pos": door_pos})

			"search":
				events.append({"type": "search", "entity_id": eid})

			"listen":
				events.append({"type": "listen", "entity_id": eid})

			"wait":
				pass

	if not moved_entities.is_empty():
		# Update _current_level to the leader's level after movement.
		var leader_pos_after := get_party_position_3d()
		_current_level = leader_pos_after.z
		_update_fog_for_all_members()
		party_moved.emit(leader_pos_after, leader_pos_after)

	var result := {"moved_entities": moved_entities, "events": events}
	orders_executed.emit(result)
	return result


# ---------------------------------------------------------------------------
# Fog update for individual positions
# ---------------------------------------------------------------------------

## Update fog-of-war based on the union of all party members' positions.
func _update_fog_for_all_members() -> void:
	_update_fog_for_all_members_voxel()


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

## Returns the VoxelMapData loaded for the current dungeon (or null).
func get_voxel_map() -> VoxelMapData:
	return _voxel_map


## Returns true if a voxel map has been loaded. Retained for test suites and
## call sites that predate `get_voxel_map`; new code should prefer
## `get_voxel_map() != null` directly.
func has_map() -> bool:
	return _voxel_map != null


func get_current_level() -> int:
	return _current_level


func get_dungeon_id() -> String:
	return _dungeon_id


func get_dungeon_name() -> String:
	return _dungeon_name


## Returns true if the party is standing on a designated transition cell.
func is_on_transition_cell() -> bool:
	if _voxel_map == null:
		return false
	return _voxel_map.is_transition_cell(get_party_position_3d())


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
	_reveal_entry_room_voxel()


func _update_visibility_on_move(old_pos, new_pos) -> void:
	_update_visibility_on_move_voxel(old_pos, new_pos)


## Voxel-mode visibility update. Marks cells of the old room as explored when
## the party leaves it, and reveals the new room (if any) when entered.
func _update_visibility_on_move_voxel(old_pos, new_pos) -> void:
	if _voxel_map == null:
		return
	var old_3d: Vector3i = old_pos if old_pos is Vector3i else Vector3i(old_pos.x, old_pos.y, _current_level)
	var new_3d: Vector3i = new_pos if new_pos is Vector3i else Vector3i(new_pos.x, new_pos.y, _current_level)

	var old_room := _voxel_map.get_room_at(old_3d)
	var new_room := _voxel_map.get_room_at(new_3d)

	if old_room != new_room and old_room >= 0:
		for c: Vector3i in _voxel_map.get_room_cells(old_room):
			if _voxel_map.get_fog(c) == "visible":
				_voxel_map.set_fog(c, "explored")

	if new_room >= 0 and new_room != old_room:
		_reveal_room_voxel(new_room)
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
