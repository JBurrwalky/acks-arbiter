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
