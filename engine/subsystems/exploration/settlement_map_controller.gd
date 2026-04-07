class_name SettlementMapController
extends Node

## Manages settlement exploration: party movement on the street graph,
## building entrance detection, and settlement exit.
##
## Movement is node-to-node on the street graph (not cell-to-cell).
## Party position is tracked as a street node ID.
##
## This is NOT an autoload. Instantiate dynamically when entering a settlement.


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal map_loaded(settlement_id: String)
signal party_moved(from_node_id: int, to_node_id: int)
signal building_entered(poi: Dictionary)
signal settlement_exited(gate_node_id: int)


# ---------------------------------------------------------------------------
# Private state
# ---------------------------------------------------------------------------

var _settlement_id: String = ""
var _map: SettlementMapData
var _party_node_id: int = -1
var _astar: AStar2D


# ---------------------------------------------------------------------------
# Core API
# ---------------------------------------------------------------------------

## Loads a settlement from a parsed dictionary. Builds the AStar2D graph
## and positions the party at the entry node.
func load_settlement(settlement_dict: Dictionary) -> void:
	_map = SettlementMapData.from_dict(settlement_dict)
	_settlement_id = _map.id
	_build_astar()

	_party_node_id = _map.entry_node_id
	map_loaded.emit(_settlement_id)

	# Notify EventBus
	var district_id: String = ""
	if not _map.districts.is_empty():
		district_id = _map.districts[0].get("id", "")
	EventBus.settlement_entered.emit(_settlement_id, district_id)


## Attempts to move the party to [param target_node_id].
## Returns true if the move succeeds. Emits party_moved on success.
## Also emits building_entered if the target is a POI node.
func move_party(target_node_id: int) -> bool:
	if _map == null:
		return false

	if not can_move_to(target_node_id):
		return false

	var from := _party_node_id
	_party_node_id = target_node_id
	party_moved.emit(from, target_node_id)

	# Check for POI at destination
	var poi: Dictionary = _map.get_poi_at_node(target_node_id)
	if not poi.is_empty():
		building_entered.emit(poi)

	return true


## Returns true if [param target_node_id] is a valid move target
## (i.e., directly connected to the party's current node via an edge).
func can_move_to(target_node_id: int) -> bool:
	if _map == null:
		return false
	if _party_node_id < 0:
		return false
	var node: Dictionary = _map.get_node_by_id(target_node_id)
	if node.is_empty():
		return false
	var adj: Array[int] = _map.get_adjacent_node_ids(_party_node_id)
	return target_node_id in adj


## Returns AStar2D pathfinding result from the party's current position
## to [param target_node_id]. Returns an empty array if no path exists.
func find_path_to(target_node_id: int) -> PackedInt64Array:
	if _astar == null or _party_node_id < 0:
		return PackedInt64Array()
	if not _astar.has_point(_party_node_id) or not _astar.has_point(target_node_id):
		return PackedInt64Array()
	return _astar.get_id_path(_party_node_id, target_node_id)


## Returns all node IDs reachable from the party's current position in one step.
func get_adjacent_nodes() -> Array[int]:
	if _map == null or _party_node_id < 0:
		return []
	return _map.get_adjacent_node_ids(_party_node_id)


## Returns the party's current street node ID.
func get_party_node_id() -> int:
	return _party_node_id


## Returns the world-space position of the party's current node.
func get_party_position() -> Vector2:
	if _map == null or _party_node_id < 0:
		return Vector2.ZERO
	var node: Dictionary = _map.get_node_by_id(_party_node_id)
	return node.get("position", Vector2.ZERO)


## Returns the current SettlementMapData, or null if not loaded.
func get_map() -> SettlementMapData:
	return _map


## Returns the current settlement ID.
func get_settlement_id() -> String:
	return _settlement_id


## Returns true if the party is currently standing on a gate node.
func is_on_gate() -> bool:
	if _map == null or _party_node_id < 0:
		return false
	var node: Dictionary = _map.get_node_by_id(_party_node_id)
	return node.get("type", "") == "gate"


## Sets the party position to a specific node (e.g. a non-default gate on entry).
func set_party_node(node_id: int) -> void:
	if _map == null:
		return
	var node: Dictionary = _map.get_node_by_id(node_id)
	if node.is_empty():
		push_error("SettlementMapController.set_party_node: invalid node_id %d" % node_id)
		return
	_party_node_id = node_id


# ---------------------------------------------------------------------------
# Private
# ---------------------------------------------------------------------------

## Builds the AStar2D graph from the settlement's street graph.
func _build_astar() -> void:
	_astar = AStar2D.new()

	for node in _map.street_graph.get("nodes", []):
		var nid: int = node.get("id", 0)
		var pos: Vector2 = node.get("position", Vector2.ZERO)
		_astar.add_point(nid, pos)

	for edge in _map.street_graph.get("edges", []):
		var a: int = edge.get("node_a", 0)
		var b: int = edge.get("node_b", 0)
		if _astar.has_point(a) and _astar.has_point(b):
			_astar.connect_points(a, b)
