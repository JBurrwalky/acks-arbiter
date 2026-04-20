class_name DungeonOrderManager
extends RefCounted

## Manages queued exploration orders for individual party members.
##
## Each entity can have at most one pending order. Orders are collected
## between turns, then executed simultaneously via DungeonMapController.execute_orders().
##
## Order types:
##   "move" — walk to target_pos along path
##   "interact_door" — interact with a door at target_pos
##   "search" — search the current or adjacent cell
##   "listen" — listen at a door or corridor
##   "wait" — hold position (explicit no-op)


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

## { entity_id: String → { order_type: String, target_pos: Vector2i, path: Array[Vector2i] } }
var _orders: Dictionary = {}


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Queue an order for [param entity_id].
## Replaces any existing order for the same entity.
func add_order(entity_id: String, order_type: String,
		target_pos = Vector2i(-1, -1),  # Vector2i or Vector3i
		path: Array = []) -> void:
	_orders[entity_id] = {
		"order_type": order_type,
		"target_pos": target_pos,
		"path": path,
	}


## Remove the pending order for [param entity_id].
func remove_order(entity_id: String) -> void:
	_orders.erase(entity_id)


## Returns the pending order for [param entity_id], or empty dict if none.
func get_order(entity_id: String) -> Dictionary:
	return _orders.get(entity_id, {})


## Returns all pending orders: { entity_id → order_dict }.
func get_all_orders() -> Dictionary:
	return _orders.duplicate()


## Returns true if [param entity_id] has a pending order.
func has_order(entity_id: String) -> bool:
	return _orders.has(entity_id)


## Clear all pending orders.
func clear() -> void:
	_orders.clear()


## Returns entity IDs that do NOT have a pending order.
## [param all_entity_ids]: the full list of entity IDs to check against.
func get_entities_without_orders(all_entity_ids: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for eid in all_entity_ids:
		if not _orders.has(eid):
			result.append(eid)
	return result


## Returns entity IDs that DO have a pending order.
func get_entities_with_orders() -> Array[String]:
	var result: Array[String] = []
	for eid in _orders.keys():
		result.append(eid)
	return result


## Returns the count of pending orders.
func order_count() -> int:
	return _orders.size()
