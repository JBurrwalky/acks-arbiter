extends "res://tests/test_suite_base.gd"

## Unit tests for SettlementMapData.
##
## Tests data loading, street graph queries, POI lookups, block/district queries,
## and bounds computation.


var _data: SettlementMapData


func run_all_tests() -> void:
	_load_test_data()
	test_from_dict_loads_basic_fields()
	test_from_dict_loads_blocks()
	test_from_dict_loads_street_graph_nodes()
	test_from_dict_loads_street_graph_edges()
	test_from_dict_loads_districts()
	test_from_dict_loads_pois()
	test_node_lookup()
	test_adjacency()
	test_edges_from_node()
	test_poi_at_node()
	test_poi_at_non_poi_node()
	test_pois_in_district()
	test_block_lookup()
	test_district_for_block()
	test_compute_bounds()
	test_entry_node_id()
	if not has_failures():
		print("SettlementMapData: all tests passed.")


func _load_test_data() -> void:
	_data = SettlementMapData.load_from_file("res://data/test_settlement.json")
	check(_data != null, "load_from_file should return non-null")


func test_from_dict_loads_basic_fields() -> void:
	check(_data.id == "test_settlement_ashford",
		"id should be 'test_settlement_ashford', got '%s'" % _data.id)
	check(_data.name == "Ashford Village",
		"name should be 'Ashford Village', got '%s'" % _data.name)
	check(_data.market_class == 6,
		"market_class should be 6, got %d" % _data.market_class)
	check(_data.population_families == 120,
		"population_families should be 120, got %d" % _data.population_families)
	check(_data.terrain_context == "crossroads",
		"terrain_context should be 'crossroads', got '%s'" % _data.terrain_context)


func test_from_dict_loads_blocks() -> void:
	check(_data.blocks.size() == 6,
		"should have 6 blocks, got %d" % _data.blocks.size())
	var b0: Dictionary = _data.blocks[0]
	check(b0.get("id") == 0, "first block id should be 0")
	var poly: Array = b0.get("polygon", [])
	check(poly.size() == 5, "first block polygon should have 5 vertices, got %d" % poly.size())
	check(poly[0] is Vector2, "polygon vertices should be Vector2")
	check(b0.get("district_id") == "village_center",
		"first block district_id should be 'village_center'")
	check(b0.get("alley_traversable") == true,
		"first block should be alley_traversable")


func test_from_dict_loads_street_graph_nodes() -> void:
	var nodes: Array = _data.street_graph.get("nodes", [])
	check(nodes.size() == 19,
		"should have 19 street nodes, got %d" % nodes.size())
	var n0: Dictionary = nodes[0]
	check(n0.get("id") == 0, "first node id should be 0")
	check(n0.get("type") == "gate", "first node type should be 'gate'")
	check(n0.get("position") is Vector2, "node position should be Vector2")


func test_from_dict_loads_street_graph_edges() -> void:
	var edges: Array = _data.street_graph.get("edges", [])
	check(edges.size() == 24,
		"should have 24 street edges, got %d" % edges.size())
	var e0: Dictionary = edges[0]
	check(e0.get("node_a") == 0, "first edge node_a should be 0")
	check(e0.get("node_b") == 1, "first edge node_b should be 1")
	check(e0.get("type") == "main_road", "first edge type should be 'main_road'")


func test_from_dict_loads_districts() -> void:
	check(_data.districts.size() == 1,
		"should have 1 district, got %d" % _data.districts.size())
	var d: Dictionary = _data.districts[0]
	check(d.get("id") == "village_center",
		"district id should be 'village_center'")
	check(d.get("type") == "market",
		"district type should be 'market'")
	var bids: Array = d.get("block_ids", [])
	check(bids.size() == 6, "district should contain 6 blocks, got %d" % bids.size())


func test_from_dict_loads_pois() -> void:
	check(_data.pois.size() == 5,
		"should have 5 POIs, got %d" % _data.pois.size())
	var tavern: Dictionary = _data.pois[0]
	check(tavern.get("id") == "poi_tavern",
		"first POI id should be 'poi_tavern'")
	check(tavern.get("type") == "tavern",
		"first POI type should be 'tavern'")
	check(tavern.get("label") == "Tavern",
		"first POI label should be 'Tavern'")
	var node_ids: Array = tavern.get("street_node_ids", [])
	check(node_ids.size() == 1, "tavern should have 1 entrance node")
	check(node_ids[0] == 14, "tavern entrance node should be 14")


func test_node_lookup() -> void:
	var node: Dictionary = _data.get_node_by_id(14)
	check(not node.is_empty(), "get_node_by_id(14) should return non-empty")
	check(node.get("type") == "poi", "node 14 type should be 'poi'")
	check(node.get("poi_id") == "poi_tavern",
		"node 14 poi_id should be 'poi_tavern'")
	var missing: Dictionary = _data.get_node_by_id(999)
	check(missing.is_empty(), "get_node_by_id(999) should return {}")


func test_adjacency() -> void:
	# Node 0 (north gate) connects to node 2 (v1)
	var adj: Array[int] = _data.get_adjacent_node_ids(0)
	check(2 in adj, "node 0 should be adjacent to node 2")

	# Node 5 (v4, central intersection) has many connections
	var adj5: Array[int] = _data.get_adjacent_node_ids(5)
	check(adj5.size() >= 4,
		"node 5 should have at least 4 adjacent nodes, got %d" % adj5.size())
	check(2 in adj5, "node 5 should be adjacent to node 2 (v1)")
	check(17 in adj5, "node 5 should be adjacent to node 17 (store)")


func test_edges_from_node() -> void:
	var edges: Array[Dictionary] = _data.get_edges_from_node(0)
	check(edges.size() == 1, "node 0 (gate) should have 1 edge, got %d" % edges.size())
	check(edges[0].get("type") == "main_road",
		"edge from gate should be main_road")


func test_poi_at_node() -> void:
	var poi: Dictionary = _data.get_poi_at_node(14)
	check(not poi.is_empty(), "node 14 should have a POI")
	check(poi.get("id") == "poi_tavern",
		"POI at node 14 should be poi_tavern, got '%s'" % poi.get("id", ""))
	check(poi.get("name") == "The Rusty Lantern",
		"POI name should be 'The Rusty Lantern'")


func test_poi_at_non_poi_node() -> void:
	var poi: Dictionary = _data.get_poi_at_node(5)
	check(poi.is_empty(), "node 5 (intersection) should have no POI")


func test_pois_in_district() -> void:
	var district_pois: Array[Dictionary] = _data.get_pois_in_district("village_center")
	check(district_pois.size() == 5,
		"village_center should have 5 POIs, got %d" % district_pois.size())

	var empty_pois: Array[Dictionary] = _data.get_pois_in_district("nonexistent")
	check(empty_pois.is_empty(), "nonexistent district should return empty array")


func test_block_lookup() -> void:
	var block: Dictionary = _data.get_block_by_id(0)
	check(not block.is_empty(), "get_block_by_id(0) should return non-empty")
	check(block.get("block_type") == "residential",
		"block 0 type should be 'residential'")

	var missing: Dictionary = _data.get_block_by_id(999)
	check(missing.is_empty(), "get_block_by_id(999) should return {}")


func test_district_for_block() -> void:
	var dist: Dictionary = _data.get_district_for_block(0)
	check(not dist.is_empty(), "block 0 should have a district")
	check(dist.get("id") == "village_center",
		"block 0 district should be 'village_center'")

	var missing: Dictionary = _data.get_district_for_block(999)
	check(missing.is_empty(), "nonexistent block should return {}")


func test_compute_bounds() -> void:
	var b: Rect2 = _data.bounds
	check(b.size.x > 0.0, "bounds width should be > 0")
	check(b.size.y > 0.0, "bounds height should be > 0")
	# All polygon vertices should be within bounds (with some tolerance)
	for block in _data.blocks:
		for pt in block.get("polygon", []):
			check(b.has_point(pt),
				"point %s should be within bounds %s" % [str(pt), str(b)])


func test_entry_node_id() -> void:
	check(_data.entry_node_id == 13,
		"entry_node_id should be 13 (south gate), got %d" % _data.entry_node_id)
	var entry_node: Dictionary = _data.get_node_by_id(_data.entry_node_id)
	check(entry_node.get("type") == "gate",
		"entry node should be type 'gate'")
