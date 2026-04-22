extends RefCounted

## Per-dungeon-visit in-memory state for control groups, idle behaviors,
## marching orders, and action queues.
##
## No class_name — instantiated by DungeonExploreState, not registered as autoload.
## All data is transient (per dungeon visit, not persisted to DB).


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Valid idle behavior values.
const IDLE_HOLD_POSITION := "hold_position"
const IDLE_FOLLOW_GROUP_LEAD := "follow_group_lead"
const IDLE_AUTO_LISTEN := "auto_listen_at_doors"
const IDLE_AUTO_SEARCH := "auto_search"
const IDLE_GUARD := "guard"
const IDLE_HIDE := "hide"

const VALID_IDLE_BEHAVIORS := [
	IDLE_HOLD_POSITION,
	IDLE_FOLLOW_GROUP_LEAD,
	IDLE_AUTO_LISTEN,
	IDLE_AUTO_SEARCH,
	IDLE_GUARD,
	IDLE_HIDE,
]


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

## Control groups: int (1-9) -> Array[String] entity_ids.
var _control_groups: Dictionary = {}

## Idle behaviors: String entity_id -> String behavior.
var _idle_behaviors: Dictionary = {}

## Marching orders per control group: int group_number -> Array[String] ordered entity_ids.
var _marching_orders: Dictionary = {}

## Action queue per entity: String entity_id -> Dictionary { current_action, pending_action }.
## Each action dict: { type: String, target_cell: Vector2i, data: Dictionary } or empty {}.
var _action_queues: Dictionary = {}


# ---------------------------------------------------------------------------
# Control Groups
# ---------------------------------------------------------------------------

## Assign entities to a control group (1-9). Replaces any existing assignment.
func assign_group(group_number: int, entity_ids: Array) -> void:
	if group_number < 1 or group_number > 9:
		return
	var ids: Array[String] = []
	for eid in entity_ids:
		ids.append(str(eid))
	_control_groups[group_number] = ids
	# Set marching order to assignment order by default.
	_marching_orders[group_number] = ids.duplicate()


## Get entity IDs in a control group. Returns empty array if group is unassigned.
func get_group(group_number: int) -> Array[String]:
	if not _control_groups.has(group_number):
		return []
	return _control_groups[group_number]


## Find which group an entity belongs to. Returns 0 if not in any group.
func get_entity_group(entity_id: String) -> int:
	for gn in _control_groups:
		var members: Array = _control_groups[gn]
		if entity_id in members:
			return gn
	return 0


## Disband a control group. Members become ungrouped.
func disband_group(group_number: int) -> void:
	_control_groups.erase(group_number)
	_marching_orders.erase(group_number)


## Remove an entity from whatever group it belongs to.
func remove_from_group(entity_id: String) -> void:
	for gn in _control_groups.keys():
		var members: Array = _control_groups[gn]
		var idx := members.find(entity_id)
		if idx >= 0:
			members.remove_at(idx)
			if _marching_orders.has(gn):
				var mo: Array = _marching_orders[gn]
				var mo_idx := mo.find(entity_id)
				if mo_idx >= 0:
					mo.remove_at(mo_idx)
			# Auto-disband if only 0 or 1 member left.
			if members.size() <= 1:
				disband_group(gn)
			return


## Get all assigned group numbers (1-9).
func get_assigned_group_numbers() -> Array[int]:
	var result: Array[int] = []
	for gn in _control_groups:
		result.append(gn)
	result.sort()
	return result


# ---------------------------------------------------------------------------
# Marching Order
# ---------------------------------------------------------------------------

## Set the marching order for a control group.
func set_marching_order(group_number: int, ordered_ids: Array) -> void:
	if not _control_groups.has(group_number):
		return
	var ids: Array[String] = []
	for eid in ordered_ids:
		ids.append(str(eid))
	_marching_orders[group_number] = ids


## Get marching order for a group. Returns assignment order if not set.
func get_marching_order(group_number: int) -> Array[String]:
	if _marching_orders.has(group_number):
		return _marching_orders[group_number]
	return get_group(group_number)


## Get the front entity (position 1) in a group's marching order.
func get_front_entity(group_number: int) -> String:
	var order := get_marching_order(group_number)
	if order.is_empty():
		return ""
	return order[0]


# ---------------------------------------------------------------------------
# Idle Behaviors
# ---------------------------------------------------------------------------

## Set idle behavior for an entity.
func set_idle_behavior(entity_id: String, behavior: String) -> void:
	if behavior not in VALID_IDLE_BEHAVIORS:
		push_warning("DungeonSessionState: invalid idle behavior '%s'" % behavior)
		return
	_idle_behaviors[entity_id] = behavior


## Get idle behavior for an entity. Default: hold_position.
func get_idle_behavior(entity_id: String) -> String:
	return _idle_behaviors.get(entity_id, IDLE_HOLD_POSITION)


## Set idle behavior for all members of a control group.
func set_group_idle_behavior(group_number: int, behavior: String) -> void:
	for eid in get_group(group_number):
		set_idle_behavior(eid, behavior)


# ---------------------------------------------------------------------------
# Action Queue (single-slot per entity)
# ---------------------------------------------------------------------------

## Queue an action for an entity. If the entity already has a current action,
## the new action becomes the pending action (replacing any existing pending).
## If no current action, the new action becomes current immediately.
func queue_action(entity_id: String, action: Dictionary) -> void:
	if not _action_queues.has(entity_id):
		_action_queues[entity_id] = {"current_action": action, "pending_action": {}}
		return
	var q: Dictionary = _action_queues[entity_id]
	if q.get("current_action", {}).is_empty():
		q["current_action"] = action
	else:
		q["pending_action"] = action


## Get the current action for an entity. Returns empty dict if none.
func get_current_action(entity_id: String) -> Dictionary:
	if not _action_queues.has(entity_id):
		return {}
	return _action_queues[entity_id].get("current_action", {})


## Get the pending action for an entity. Returns empty dict if none.
func get_pending_action(entity_id: String) -> Dictionary:
	if not _action_queues.has(entity_id):
		return {}
	return _action_queues[entity_id].get("pending_action", {})


## Complete the current action for an entity. Promotes pending to current.
func complete_current_action(entity_id: String) -> void:
	if not _action_queues.has(entity_id):
		return
	var q: Dictionary = _action_queues[entity_id]
	q["current_action"] = q.get("pending_action", {})
	q["pending_action"] = {}


## Clear all actions for an entity (interrupt).
func clear_action_queue(entity_id: String) -> void:
	_action_queues[entity_id] = {"current_action": {}, "pending_action": {}}


## Clear all actions for all entities.
func clear_all_action_queues() -> void:
	for eid in _action_queues:
		_action_queues[eid] = {"current_action": {}, "pending_action": {}}


## Check if an entity has any active action.
func has_active_action(entity_id: String) -> bool:
	if not _action_queues.has(entity_id):
		return false
	return not _action_queues[entity_id].get("current_action", {}).is_empty()


## Replace the current action immediately (for move order interrupts).
func replace_current_action(entity_id: String, action: Dictionary) -> void:
	_action_queues[entity_id] = {"current_action": action, "pending_action": {}}


# ---------------------------------------------------------------------------
# Pick Lock Tracking
# ---------------------------------------------------------------------------

## Locks successfully picked this visit. Reverted on dungeon exit.
## Key: Vector2i door position -> true.
var _picked_locks: Dictionary = {}

## Characters who failed a pick lock this visit.
## Key: String entity_id -> int character_level at time of failure.
var _pick_lock_failures: Dictionary = {}


## Record that a lock was successfully picked (for reverting on exit).
## [param pos] accepts Vector2i (legacy) or Vector3i (voxel).
func record_picked_lock(pos) -> void:
	_picked_locks[pos] = true


## Get all positions of locks picked this visit.
func get_picked_locks() -> Array:
	return _picked_locks.keys()


## Record a pick lock failure for a character at their current level.
func record_pick_lock_failure(entity_id: String, level: int) -> void:
	_pick_lock_failures[entity_id] = level


## Returns true if the character has failed a pick lock and hasn't leveled up since.
func has_failed_pick_lock(entity_id: String, current_level: int) -> bool:
	if not _pick_lock_failures.has(entity_id):
		return false
	return _pick_lock_failures[entity_id] >= current_level


# ---------------------------------------------------------------------------
# Spike / Wedge Tracking
# ---------------------------------------------------------------------------

## Doors spiked shut this visit. Key: Vector2i (legacy) or Vector3i (voxel) -> true.
var _spiked_doors: Dictionary = {}

## Doors wedged open this visit. Key: Vector2i (legacy) or Vector3i (voxel) -> true.
var _wedged_doors: Dictionary = {}


## Door-position params accept Vector2i (legacy TacticalMapData) or Vector3i
## (VoxelMapData). Dictionaries hash the value directly.
func spike_door(pos) -> void:
	_spiked_doors[pos] = true
	_wedged_doors.erase(pos)  # Can't be both.


func unspike_door(pos) -> void:
	_spiked_doors.erase(pos)


func wedge_door(pos) -> void:
	_wedged_doors[pos] = true
	_spiked_doors.erase(pos)  # Can't be both.


func unwedge_door(pos) -> void:
	_wedged_doors.erase(pos)


func is_spiked(pos) -> bool:
	return _spiked_doors.has(pos)


func is_wedged(pos) -> bool:
	return _wedged_doors.has(pos)


# ---------------------------------------------------------------------------
# Held Portcullis Tracking
# ---------------------------------------------------------------------------

## Portcullises held open by brute force. Key: Vector2i (legacy) or Vector3i (voxel) -> String entity_id.
## Drops as soon as the holding entity performs any other action.
var _held_portcullises: Dictionary = {}


func hold_portcullis(pos, entity_id: String) -> void:
	_held_portcullises[pos] = entity_id


func release_portcullis(pos) -> void:
	_held_portcullises.erase(pos)


func is_held_open(pos) -> bool:
	return _held_portcullises.has(pos)


func get_portcullis_holder(pos) -> String:
	return _held_portcullises.get(pos, "")


## Release all portcullises held by [param entity_id]. Returns the positions released.
func release_all_held_by(entity_id: String) -> Array:
	var released: Array = []
	for pos in _held_portcullises.keys():
		if _held_portcullises[pos] == entity_id:
			released.append(pos)
	for pos in released:
		_held_portcullises.erase(pos)
	return released


# ---------------------------------------------------------------------------
# Exited Entity Tracking
# ---------------------------------------------------------------------------

## Entities that have successfully exited the dungeon this visit.
## Key: String entity_id -> true.
var _exited_entities: Dictionary = {}


## Mark an entity as having exited the dungeon.
func mark_exited(entity_id: String) -> void:
	_exited_entities[entity_id] = true


## Returns true if [param entity_id] has already exited.
func is_exited(entity_id: String) -> bool:
	return _exited_entities.has(entity_id)


## Returns all entity IDs that have exited.
func get_exited_entities() -> Array:
	return _exited_entities.keys()


## Returns true when every entity in [param party_ids] has either exited,
## is incapacitated, or is dead.
func all_party_resolved(party_ids: Array, party_data) -> bool:
	if party_data == null:
		return false
	for eid in party_ids:
		if is_exited(str(eid)):
			continue
		var cd = party_data.get_member(str(eid))
		if cd == null:
			continue
		if cd.is_dead or cd.is_incapacitated:
			continue
		return false
	return true


# ---------------------------------------------------------------------------
# Exit Queue
# ---------------------------------------------------------------------------

## Entities queued to exit the dungeon. They will automatically advance
## toward the exit cell as space becomes available.
## Key: String entity_id -> Vector2i exit cell position.
var _exit_queue: Dictionary = {}


## Add an entity to the exit queue targeting [param exit_cell].
## [param exit_cell] accepts Vector2i (legacy) or Vector3i (voxel).
func queue_for_exit(entity_id: String, exit_cell) -> void:
	_exit_queue[entity_id] = exit_cell


## Remove an entity from the exit queue.
func dequeue_exit(entity_id: String) -> void:
	_exit_queue.erase(entity_id)


## Returns true if [param entity_id] is in the exit queue.
func is_queued_for_exit(entity_id: String) -> bool:
	return _exit_queue.has(entity_id)


## Returns a copy of the exit queue dictionary.
func get_exit_queue() -> Dictionary:
	return _exit_queue.duplicate()


## Clears the entire exit queue.
func clear_exit_queue() -> void:
	_exit_queue.clear()
