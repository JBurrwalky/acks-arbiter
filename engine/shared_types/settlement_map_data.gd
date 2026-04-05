class_name SettlementMapData
extends RefCounted

## Settlement spatial data: irregular polygon blocks, street graph, districts, POIs.
##
## Movement is node-to-node on the street graph (not cell-to-cell).
## Party position is a street node ID, not grid coordinates.
##
## This type is NOT an autoload. Instantiate via from_dict() or load_from_file().
## Data format matches gdd-settlement-layout.md §13 (SettlementLayout).


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var id: String = ""
var name: String = ""
var market_class: int = 6
var population_families: int = 0
var terrain_context: String = "crossroads"
var bounds: Rect2 = Rect2()
var generation_seed: int = 0
var culture_id: String = ""

## Block polygons. Each entry: {id: int, polygon: Array[Vector2], district_id: String,
##   block_type: String, alley_traversable: bool, poi_ids: Array[String], waterfront: bool}
var blocks: Array = []

## Street graph. {nodes: Array[StreetNode dict], edges: Array[StreetEdge dict]}
## StreetNode: {id: int, position: Vector2, type: String, poi_id: String}
## StreetEdge: {id: int, node_a: int, node_b: int, type: String, length: float,
##   left_block_id: int, right_block_id: int}
var street_graph: Dictionary = {"nodes": [], "edges": []}

## Districts. Each: {id: String, name: String, type: String, block_ids: Array[int],
##   encounter_modifier: String}
var districts: Array = []

## Walls. Empty dict if unwalled. {path: Array[Vector2], towers: Array[Vector2],
##   gates: Array[GateData dict]}
## GateData: {position: Vector2, street_node_id: int, name: String}
var walls: Dictionary = {}

## Water features. Empty dict if none. {river_path: Array[Vector2],
##   coastline: Array[Vector2], bridges: Array[{position: Vector2, street_node_id: int}]}
var water_features: Dictionary = {}

## Points of interest. Each: {id: String, name: String, type: String, subtype: String,
##   block_id: int, street_node_ids: Array[int], district_id: String,
##   importance: String, label: String}
var pois: Array = []

## Default entry node ID (gate where party enters from hex map).
var entry_node_id: int = -1


# ---------------------------------------------------------------------------
# Internal lookup tables (built by from_dict)
# ---------------------------------------------------------------------------

var _node_lookup: Dictionary = {}      ## node_id (int) → node dict
var _edge_lookup: Dictionary = {}      ## edge_id (int) → edge dict
var _adjacency: Dictionary = {}        ## node_id (int) → Array[{node_id: int, edge_id: int}]
var _poi_at_node: Dictionary = {}      ## node_id (int) → POI dict
var _block_lookup: Dictionary = {}     ## block_id (int) → block dict
var _district_lookup: Dictionary = {}  ## district_id (String) → district dict
var _block_to_district: Dictionary = {} ## block_id (int) → district dict


# ---------------------------------------------------------------------------
# Factory
# ---------------------------------------------------------------------------

## Builds a SettlementMapData from a parsed JSON dictionary.
static func from_dict(data: Dictionary) -> SettlementMapData:
	var m := SettlementMapData.new()
	m.id = data.get("id", "")
	m.name = data.get("name", "")
	m.market_class = data.get("market_class", 6)
	m.population_families = data.get("population_families", 0)
	m.terrain_context = data.get("terrain_context", "crossroads")
	m.generation_seed = data.get("generation_seed", 0)
	m.culture_id = data.get("culture_id", "")
	m.entry_node_id = int(data.get("entry_node_id", -1))

	# --- Blocks ---
	for b in data.get("blocks", []):
		var block: Dictionary = {}
		block["id"] = int(b.get("id", 0))
		block["district_id"] = b.get("district_id", "")
		block["block_type"] = b.get("block_type", "residential")
		block["alley_traversable"] = b.get("alley_traversable", true)
		block["poi_ids"] = b.get("poi_ids", [])
		block["waterfront"] = b.get("waterfront", false)

		var poly: Array[Vector2] = []
		for pt in b.get("polygon", []):
			if pt is Array and pt.size() >= 2:
				poly.append(Vector2(pt[0], pt[1]))
			elif pt is Dictionary:
				poly.append(Vector2(pt.get("x", 0.0), pt.get("y", 0.0)))
		block["polygon"] = poly

		m.blocks.append(block)
		m._block_lookup[int(block["id"])] = block

	# --- Street graph ---
	var sg: Dictionary = data.get("street_graph", {})

	var nodes: Array = []
	for n in sg.get("nodes", []):
		var node: Dictionary = {}
		node["id"] = int(n.get("id", 0))
		node["type"] = n.get("type", "intersection")
		node["poi_id"] = n.get("poi_id", "")

		var pos = n.get("position", [0.0, 0.0])
		if pos is Array and pos.size() >= 2:
			node["position"] = Vector2(pos[0], pos[1])
		elif pos is Dictionary:
			node["position"] = Vector2(pos.get("x", 0.0), pos.get("y", 0.0))
		else:
			node["position"] = Vector2.ZERO

		nodes.append(node)
		m._node_lookup[int(node["id"])] = node
		m._adjacency[int(node["id"])] = []

	var edges: Array = []
	for e in sg.get("edges", []):
		var edge: Dictionary = {}
		edge["id"] = int(e.get("id", 0))
		edge["node_a"] = int(e.get("node_a", 0))
		edge["node_b"] = int(e.get("node_b", 0))
		edge["type"] = e.get("type", "minor")
		edge["length"] = e.get("length", 1.0)
		edge["left_block_id"] = int(e.get("left_block_id", -1))
		edge["right_block_id"] = int(e.get("right_block_id", -1))
		edges.append(edge)
		m._edge_lookup[int(edge["id"])] = edge

		# Build adjacency
		var a_id: int = edge["node_a"]
		var b_id: int = edge["node_b"]
		if m._adjacency.has(a_id):
			m._adjacency[a_id].append({"node_id": b_id, "edge_id": edge["id"]})
		if m._adjacency.has(b_id):
			m._adjacency[b_id].append({"node_id": a_id, "edge_id": edge["id"]})

	m.street_graph = {"nodes": nodes, "edges": edges}

	# --- Districts ---
	for d in data.get("districts", []):
		var dist: Dictionary = {}
		dist["id"] = d.get("id", "")
		dist["name"] = d.get("name", "")
		dist["type"] = d.get("type", "residential")
		# Ensure block_ids are int for consistent dictionary lookups
		var raw_bids: Array = d.get("block_ids", [])
		var int_bids: Array = []
		for raw_bid in raw_bids:
			int_bids.append(int(raw_bid))
		dist["block_ids"] = int_bids
		dist["encounter_modifier"] = d.get("encounter_modifier", "normal")
		m.districts.append(dist)
		m._district_lookup[dist["id"]] = dist

		for bid in dist["block_ids"]:
			if m._block_lookup.has(bid):
				m._block_to_district[bid] = dist

	# --- Walls ---
	var raw_walls = data.get("walls", null)
	if raw_walls != null and raw_walls is Dictionary and not raw_walls.is_empty():
		m.walls = _parse_walls(raw_walls)

	# --- Water features ---
	var raw_water = data.get("water_features", null)
	if raw_water != null and raw_water is Dictionary and not raw_water.is_empty():
		m.water_features = _parse_water_features(raw_water)

	# --- POIs ---
	for p in data.get("pois", []):
		var poi: Dictionary = {}
		poi["id"] = p.get("id", "")
		poi["name"] = p.get("name", "")
		poi["type"] = p.get("type", "")
		poi["subtype"] = p.get("subtype", "")
		poi["block_id"] = int(p.get("block_id", -1))
		# Ensure street_node_ids are int for consistent dictionary lookups
		var raw_snids: Array = p.get("street_node_ids", [])
		var int_snids: Array = []
		for raw_snid in raw_snids:
			int_snids.append(int(raw_snid))
		poi["street_node_ids"] = int_snids
		poi["district_id"] = p.get("district_id", "")
		poi["importance"] = p.get("importance", "minor")
		poi["label"] = p.get("label", poi["name"])
		m.pois.append(poi)

		# Build POI-at-node lookup
		for nid in poi["street_node_ids"]:
			m._poi_at_node[nid] = poi

	# --- Bounds ---
	m.bounds = m.compute_bounds()

	return m


## Loads from a JSON file at the given path.
static func load_from_file(path: String) -> SettlementMapData:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("SettlementMapData.load_from_file: cannot open '%s'" % path)
		return null
	var json_text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(json_text)
	if parsed == null:
		push_error("SettlementMapData.load_from_file: JSON parse failed for '%s'" % path)
		return null
	return from_dict(parsed)


# ---------------------------------------------------------------------------
# Queries — Street Graph
# ---------------------------------------------------------------------------

## Returns the street node dict for [param node_id], or {} if not found.
func get_node_by_id(node_id: int) -> Dictionary:
	return _node_lookup.get(node_id, {})


## Returns the street edge dict for [param edge_id], or {} if not found.
func get_edge_by_id(edge_id: int) -> Dictionary:
	return _edge_lookup.get(edge_id, {})


## Returns all node IDs directly connected to [param node_id] via edges.
func get_adjacent_node_ids(node_id: int) -> Array[int]:
	var result: Array[int] = []
	for entry in _adjacency.get(node_id, []):
		result.append(entry["node_id"])
	return result


## Returns all edge dicts touching [param node_id].
func get_edges_from_node(node_id: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in _adjacency.get(node_id, []):
		var edge: Dictionary = _edge_lookup.get(entry["edge_id"], {})
		if not edge.is_empty():
			result.append(edge)
	return result


# ---------------------------------------------------------------------------
# Queries — POIs
# ---------------------------------------------------------------------------

## Returns the POI dict at [param node_id], or {} if no POI there.
func get_poi_at_node(node_id: int) -> Dictionary:
	return _poi_at_node.get(node_id, {})


## Returns all POIs in the given district.
func get_pois_in_district(district_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for poi in pois:
		if poi.get("district_id", "") == district_id:
			result.append(poi)
	return result


## Returns the POI dict with the given id, or {} if not found.
func get_poi_by_id(poi_id: String) -> Dictionary:
	for poi in pois:
		if poi.get("id", "") == poi_id:
			return poi
	return {}


# ---------------------------------------------------------------------------
# Queries — Blocks & Districts
# ---------------------------------------------------------------------------

## Returns the block dict for [param block_id], or {} if not found.
func get_block_by_id(block_id: int) -> Dictionary:
	return _block_lookup.get(block_id, {})


## Returns the district dict for [param district_id], or {} if not found.
func get_district_by_id(district_id: String) -> Dictionary:
	return _district_lookup.get(district_id, {})


## Returns the district dict that contains [param block_id], or {} if not found.
func get_district_for_block(block_id: int) -> Dictionary:
	return _block_to_district.get(block_id, {})


# ---------------------------------------------------------------------------
# Geometry
# ---------------------------------------------------------------------------

## Computes the bounding rectangle enclosing all block polygons.
func compute_bounds() -> Rect2:
	var min_x := INF
	var min_y := INF
	var max_x := -INF
	var max_y := -INF
	for block in blocks:
		for pt in block.get("polygon", []):
			if pt.x < min_x:
				min_x = pt.x
			if pt.y < min_y:
				min_y = pt.y
			if pt.x > max_x:
				max_x = pt.x
			if pt.y > max_y:
				max_y = pt.y
	if min_x == INF:
		return Rect2()
	return Rect2(min_x, min_y, max_x - min_x, max_y - min_y)


# ---------------------------------------------------------------------------
# Internal parse helpers
# ---------------------------------------------------------------------------

static func _parse_vector2_array(arr: Array) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for pt in arr:
		if pt is Array and pt.size() >= 2:
			result.append(Vector2(pt[0], pt[1]))
		elif pt is Dictionary:
			result.append(Vector2(pt.get("x", 0.0), pt.get("y", 0.0)))
	return result


static func _parse_walls(data: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	result["path"] = _parse_vector2_array(data.get("path", []))
	result["towers"] = _parse_vector2_array(data.get("towers", []))

	var gates: Array = []
	for g in data.get("gates", []):
		var gate: Dictionary = {}
		var pos = g.get("position", [0.0, 0.0])
		if pos is Array and pos.size() >= 2:
			gate["position"] = Vector2(pos[0], pos[1])
		elif pos is Dictionary:
			gate["position"] = Vector2(pos.get("x", 0.0), pos.get("y", 0.0))
		else:
			gate["position"] = Vector2.ZERO
		gate["street_node_id"] = g.get("street_node_id", -1)
		gate["name"] = g.get("name", "")
		gates.append(gate)
	result["gates"] = gates
	return result


static func _parse_water_features(data: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	result["river_path"] = _parse_vector2_array(data.get("river_path", []))
	result["coastline"] = _parse_vector2_array(data.get("coastline", []))

	var bridges: Array = []
	for b in data.get("bridges", []):
		var bridge: Dictionary = {}
		var pos = b.get("position", [0.0, 0.0])
		if pos is Array and pos.size() >= 2:
			bridge["position"] = Vector2(pos[0], pos[1])
		elif pos is Dictionary:
			bridge["position"] = Vector2(pos.get("x", 0.0), pos.get("y", 0.0))
		else:
			bridge["position"] = Vector2.ZERO
		bridge["street_node_id"] = b.get("street_node_id", -1)
		bridges.append(bridge)
	result["bridges"] = bridges
	return result
