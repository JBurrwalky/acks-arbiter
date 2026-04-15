class_name SettlementTravelCalculator
extends RefCounted

## Calculates travel routes and times between street graph nodes in a settlement.
##
## Uses AStar2D pathfinding on the SettlementMapData street graph. Supports
## filtering out alley edges (Streets Only mode) and adjusting commute speed
## for straggling groups (6+ party members).
##
## Travel time rules (ACKS sacred — gdd-settlement-exploration-ui.md §3.3):
##   Commuting: 15 rounds per block (90 seconds). Navigation throws required.
##   Meandering: 1 turn (60 rounds) per block. No navigation throws.
##   Straggling: 6-11 chars → commute doubled; 12+ chars → commute quadrupled.
##   Encumbrance/mounts: NO effect on city travel speed.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Rounds per block at commuting speed (15 rounds = 90 seconds).
const COMMUTE_ROUNDS_PER_BLOCK := 15

## Rounds per block at meandering speed (1 turn = 60 rounds = 10 minutes).
const MEANDER_ROUNDS_PER_BLOCK := 60

## Straggling group thresholds.
const STRAGGLING_MEDIUM_THRESHOLD := 6   ## 6-11 chars: commute speed halved
const STRAGGLING_LARGE_THRESHOLD := 12   ## 12+ chars: commute speed quartered


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Calculates the shortest travel route between two nodes on the street graph.
##
## Returns a result dictionary:
##   path: PackedInt64Array — ordered node IDs from origin to destination
##   block_count: int — number of edges traversed (= path.size() - 1)
##   edge_types: Dictionary — count of edges by type {"main_road": N, ...}
##   commute_rounds: int — total travel time at commuting speed
##   meander_rounds: int — total travel time at meandering speed
##   straggling_multiplier: int — 1, 2, or 4 based on party size
##   has_alleys: bool — true if any edge in the route is an alley
##
## Returns an empty dictionary if no path exists.
static func calculate_route(
	map_data: SettlementMapData,
	origin_node: int,
	dest_node: int,
	streets_only: bool = true,
	party_size: int = 1,
) -> Dictionary:
	if map_data == null:
		return {}
	if origin_node == dest_node:
		return {
			"path": PackedInt64Array([origin_node]),
			"block_count": 0,
			"edge_types": {"main_road": 0, "secondary": 0, "minor": 0, "alley": 0},
			"commute_rounds": 0,
			"meander_rounds": 0,
			"straggling_multiplier": _straggling_multiplier(party_size),
			"has_alleys": false,
		}

	# Build a filtered AStar2D graph.
	var astar := AStar2D.new()
	var edge_map := {}  # "node_a:node_b" → edge dict (lower id first)

	# Add all nodes.
	for node in map_data.street_graph.get("nodes", []):
		var nid: int = node.get("id", 0)
		var pos: Vector2 = node.get("position", Vector2.ZERO)
		astar.add_point(nid, pos)

	# Add edges, optionally filtering out alleys.
	for edge in map_data.street_graph.get("edges", []):
		var edge_type: String = edge.get("type", "minor")
		if streets_only and edge_type == "alley":
			continue

		var a: int = edge.get("node_a", 0)
		var b: int = edge.get("node_b", 0)
		if not astar.has_point(a) or not astar.has_point(b):
			continue

		# Use length as edge weight for shortest-path calculation.
		var weight: float = edge.get("length", 1.0)
		if weight <= 0.0:
			weight = 1.0
		astar.connect_points(a, b)

		# Store edge data for type counting after pathfinding.
		var key_ab := _edge_key(a, b)
		edge_map[key_ab] = edge

	# Find shortest path.
	if not astar.has_point(origin_node) or not astar.has_point(dest_node):
		return {}

	var path: PackedInt64Array = astar.get_id_path(origin_node, dest_node)
	if path.is_empty():
		return {}

	# Count edge types along the path.
	var edge_types := {"main_road": 0, "secondary": 0, "minor": 0, "alley": 0}
	var has_alleys := false
	for i in range(path.size() - 1):
		var key := _edge_key(path[i], path[i + 1])
		var edge: Dictionary = edge_map.get(key, {})
		var etype: String = edge.get("type", "minor")
		if edge_types.has(etype):
			edge_types[etype] += 1
		else:
			edge_types[etype] = 1
		if etype == "alley":
			has_alleys = true

	var block_count: int = path.size() - 1
	var strag_mult: int = _straggling_multiplier(party_size)
	var commute_rounds: int = block_count * COMMUTE_ROUNDS_PER_BLOCK * strag_mult
	var meander_rounds: int = block_count * MEANDER_ROUNDS_PER_BLOCK

	return {
		"path": path,
		"block_count": block_count,
		"edge_types": edge_types,
		"commute_rounds": commute_rounds,
		"meander_rounds": meander_rounds,
		"straggling_multiplier": strag_mult,
		"has_alleys": has_alleys,
	}


## Calculates travel time estimates from a party's current node to every POI
## in the settlement. Used to populate the PoI list with distance/time info.
##
## Returns: Dictionary[String, Dictionary] — poi_id → route result dict
static func calculate_all_poi_distances(
	map_data: SettlementMapData,
	origin_node: int,
	streets_only: bool = true,
	party_size: int = 1,
) -> Dictionary:
	var results := {}
	for poi in map_data.pois:
		var poi_id: String = poi.get("id", "")
		var node_ids: Array = poi.get("street_node_ids", [])
		if node_ids.is_empty():
			continue

		# Use the first street node for the POI as the destination.
		var dest_node: int = node_ids[0]
		var route := calculate_route(map_data, origin_node, dest_node, streets_only, party_size)
		if not route.is_empty():
			results[poi_id] = route

	return results


## Returns the straggling group multiplier for commuting speed.
## 1-5 chars: 1x, 6-11 chars: 2x, 12+ chars: 4x.
static func _straggling_multiplier(party_size: int) -> int:
	if party_size >= STRAGGLING_LARGE_THRESHOLD:
		return 4
	elif party_size >= STRAGGLING_MEDIUM_THRESHOLD:
		return 2
	return 1


## Returns a canonical key for an edge between two nodes (lower id first).
static func _edge_key(a: int, b: int) -> String:
	if a <= b:
		return "%d:%d" % [a, b]
	return "%d:%d" % [b, a]
