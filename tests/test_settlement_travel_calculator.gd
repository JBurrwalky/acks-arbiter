extends "res://tests/test_suite_base.gd"

## Unit tests for SettlementTravelCalculator.
##
## Tests pathfinding, block counting, edge type breakdown, commute/meander
## travel time calculation, straggling group penalties, and alley filtering.


var _map: SettlementMapData
var _map_with_alleys: SettlementMapData


func run_all_tests() -> void:
	_load_test_data()
	_build_alley_test_data()

	test_same_node_returns_zero_travel()
	test_adjacent_node_one_block()
	test_multi_block_path()
	test_block_count_equals_edge_count()
	test_commute_rounds_15_per_block()
	test_meander_rounds_60_per_block()
	test_straggling_medium_doubles_commute()
	test_straggling_large_quadruples_commute()
	test_straggling_no_effect_on_meander()
	test_edge_types_counted()
	test_alley_filtering_streets_only()
	test_alley_included_when_allowed()
	test_no_path_returns_empty()
	test_null_map_returns_empty()
	test_calculate_all_poi_distances()
	test_straggling_multiplier_boundaries()

	if not has_failures():
		print("SettlementTravelCalculator: all tests passed.")


func _load_test_data() -> void:
	_map = SettlementMapData.load_from_file("res://data/test_settlement.json")
	check(_map != null, "should load test_settlement.json")


## Build a small test map with alley edges for alley-filtering tests.
## Graph:
##   0 ---main_road--- 1 ---minor--- 2
##                      |             |
##                    alley         minor
##                      |             |
##                      3 ---minor--- 4 (poi: "test_poi")
func _build_alley_test_data() -> void:
	var data := {
		"id": "alley_test",
		"name": "Alley Test Town",
		"market_class": 6,
		"population_families": 50,
		"entry_node_id": 0,
		"blocks": [],
		"street_graph": {
			"nodes": [
				{"id": 0, "position": [0, 0],   "type": "gate",         "poi_id": ""},
				{"id": 1, "position": [100, 0],  "type": "intersection", "poi_id": ""},
				{"id": 2, "position": [200, 0],  "type": "intersection", "poi_id": ""},
				{"id": 3, "position": [100, 100],"type": "intersection", "poi_id": ""},
				{"id": 4, "position": [200, 100],"type": "poi",          "poi_id": "test_poi"},
			],
			"edges": [
				{"id": 0, "node_a": 0, "node_b": 1, "type": "main_road", "length": 100.0, "left_block_id": -1, "right_block_id": -1},
				{"id": 1, "node_a": 1, "node_b": 2, "type": "minor",     "length": 100.0, "left_block_id": -1, "right_block_id": -1},
				{"id": 2, "node_a": 1, "node_b": 3, "type": "alley",     "length": 100.0, "left_block_id": -1, "right_block_id": -1},
				{"id": 3, "node_a": 2, "node_b": 4, "type": "minor",     "length": 100.0, "left_block_id": -1, "right_block_id": -1},
				{"id": 4, "node_a": 3, "node_b": 4, "type": "minor",     "length": 100.0, "left_block_id": -1, "right_block_id": -1},
			],
		},
		"districts": [{"id": "d1", "name": "Center", "type": "market", "block_ids": [], "encounter_modifier": "normal"}],
		"walls": null,
		"water_features": null,
		"pois": [
			{"id": "test_poi", "name": "Test Shop", "type": "shop", "subtype": "general",
			 "block_id": -1, "street_node_ids": [4], "district_id": "d1",
			 "importance": "minor", "label": "Shop"},
		],
	}
	_map_with_alleys = SettlementMapData.from_dict(data)
	check(_map_with_alleys != null, "should build alley test map")


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_same_node_returns_zero_travel() -> void:
	var result := SettlementTravelCalculator.calculate_route(_map, 13, 13)
	check(not result.is_empty(), "same-node route should return result")
	check(result["block_count"] == 0, "same-node should have 0 blocks, got %d" % result.get("block_count", -1))
	check(result["commute_rounds"] == 0, "same-node commute should be 0")
	check(result["meander_rounds"] == 0, "same-node meander should be 0")


func test_adjacent_node_one_block() -> void:
	# Node 13 (south gate) → Node 11, connected by edge 23 (main_road, length 100)
	var result := SettlementTravelCalculator.calculate_route(_map, 13, 11)
	check(not result.is_empty(), "adjacent route should return result")
	check(result["block_count"] == 1, "adjacent nodes should be 1 block, got %d" % result.get("block_count", -1))


func test_multi_block_path() -> void:
	# Node 13 (south gate) → Node 0 (north gate): should traverse multiple edges
	var result := SettlementTravelCalculator.calculate_route(_map, 13, 0)
	check(not result.is_empty(), "multi-block route should return result")
	check(result["block_count"] > 1, "gate-to-gate should be >1 block, got %d" % result.get("block_count", -1))
	check(result["path"].size() == result["block_count"] + 1,
		"path size should be block_count + 1")


func test_block_count_equals_edge_count() -> void:
	var result := SettlementTravelCalculator.calculate_route(_map, 13, 14)
	check(not result.is_empty(), "should find path to tavern node")
	var path: PackedInt64Array = result["path"]
	check(result["block_count"] == path.size() - 1,
		"block_count (%d) should equal path edges (%d)" % [result["block_count"], path.size() - 1])


func test_commute_rounds_15_per_block() -> void:
	var result := SettlementTravelCalculator.calculate_route(_map, 13, 11, true, 1)
	check(result["commute_rounds"] == result["block_count"] * 15,
		"commute should be 15 rounds/block: expected %d, got %d" % [
			result["block_count"] * 15, result["commute_rounds"]])


func test_meander_rounds_60_per_block() -> void:
	var result := SettlementTravelCalculator.calculate_route(_map, 13, 11, true, 1)
	check(result["meander_rounds"] == result["block_count"] * 60,
		"meander should be 60 rounds/block: expected %d, got %d" % [
			result["block_count"] * 60, result["meander_rounds"]])


func test_straggling_medium_doubles_commute() -> void:
	var result_solo := SettlementTravelCalculator.calculate_route(_map, 13, 0, true, 3)
	var result_medium := SettlementTravelCalculator.calculate_route(_map, 13, 0, true, 8)
	check(result_medium["commute_rounds"] == result_solo["commute_rounds"] * 2,
		"6-11 chars should double commute: solo=%d, medium=%d" % [
			result_solo["commute_rounds"], result_medium["commute_rounds"]])
	check(result_medium["straggling_multiplier"] == 2, "straggling mult should be 2 for 8 chars")


func test_straggling_large_quadruples_commute() -> void:
	var result_solo := SettlementTravelCalculator.calculate_route(_map, 13, 0, true, 3)
	var result_large := SettlementTravelCalculator.calculate_route(_map, 13, 0, true, 14)
	check(result_large["commute_rounds"] == result_solo["commute_rounds"] * 4,
		"12+ chars should quadruple commute: solo=%d, large=%d" % [
			result_solo["commute_rounds"], result_large["commute_rounds"]])
	check(result_large["straggling_multiplier"] == 4, "straggling mult should be 4 for 14 chars")


func test_straggling_no_effect_on_meander() -> void:
	var result_solo := SettlementTravelCalculator.calculate_route(_map, 13, 0, true, 1)
	var result_large := SettlementTravelCalculator.calculate_route(_map, 13, 0, true, 14)
	check(result_solo["meander_rounds"] == result_large["meander_rounds"],
		"straggling should not affect meander: solo=%d, large=%d" % [
			result_solo["meander_rounds"], result_large["meander_rounds"]])


func test_edge_types_counted() -> void:
	var result := SettlementTravelCalculator.calculate_route(_map, 13, 0)
	check(not result.is_empty(), "should find path")
	var types: Dictionary = result["edge_types"]
	var total: int = types.get("main_road", 0) + types.get("secondary", 0) + types.get("minor", 0) + types.get("alley", 0)
	check(total == result["block_count"],
		"edge type counts (%d) should sum to block_count (%d)" % [total, result["block_count"]])


func test_alley_filtering_streets_only() -> void:
	# With streets_only=true, path from 0→4 must go 0→1→2→4 (3 blocks, no alley).
	# The alley edge 1→3 is excluded.
	var result := SettlementTravelCalculator.calculate_route(_map_with_alleys, 0, 4, true, 1)
	check(not result.is_empty(), "streets-only should find path via non-alley route")
	check(result["block_count"] == 3,
		"streets-only path should be 3 blocks (0→1→2→4), got %d" % result.get("block_count", -1))
	check(result["edge_types"].get("alley", 0) == 0,
		"streets-only path should have 0 alley edges")
	check(result["has_alleys"] == false, "has_alleys should be false")


func test_alley_included_when_allowed() -> void:
	# With streets_only=false, path from 0→4 can go 0→1→3→4 (3 blocks, via alley).
	# Or 0→1→2→4 (also 3 blocks). Both are 3 edges. AStar2D may pick either,
	# but the alley route should be possible.
	var result := SettlementTravelCalculator.calculate_route(_map_with_alleys, 0, 4, false, 1)
	check(not result.is_empty(), "alleys-allowed should find path")
	check(result["block_count"] <= 3,
		"alleys-allowed path should be ≤3 blocks, got %d" % result.get("block_count", -1))


func test_no_path_returns_empty() -> void:
	# Node IDs that don't exist in the graph.
	var result := SettlementTravelCalculator.calculate_route(_map, 13, 9999)
	check(result.is_empty(), "non-existent dest should return empty dict")


func test_null_map_returns_empty() -> void:
	var result := SettlementTravelCalculator.calculate_route(null, 0, 1)
	check(result.is_empty(), "null map should return empty dict")


func test_calculate_all_poi_distances() -> void:
	# From the south gate (node 13), calculate distances to all POIs.
	var distances := SettlementTravelCalculator.calculate_all_poi_distances(_map, 13)
	check(distances.size() > 0, "should have at least one POI distance")
	# The test settlement has 5 POIs.
	check(distances.size() == 5, "should have 5 POI distances, got %d" % distances.size())
	# Each result should have valid block counts.
	for poi_id in distances:
		var r: Dictionary = distances[poi_id]
		check(r["block_count"] > 0,
			"POI '%s' should have >0 blocks from gate, got %d" % [poi_id, r["block_count"]])


func test_straggling_multiplier_boundaries() -> void:
	# Test boundary values: 5 (no penalty), 6 (double), 11 (double), 12 (quadruple)
	var r5 := SettlementTravelCalculator.calculate_route(_map, 13, 11, true, 5)
	var r6 := SettlementTravelCalculator.calculate_route(_map, 13, 11, true, 6)
	var r11 := SettlementTravelCalculator.calculate_route(_map, 13, 11, true, 11)
	var r12 := SettlementTravelCalculator.calculate_route(_map, 13, 11, true, 12)
	check(r5["straggling_multiplier"] == 1, "5 chars should be 1x")
	check(r6["straggling_multiplier"] == 2, "6 chars should be 2x")
	check(r11["straggling_multiplier"] == 2, "11 chars should be 2x")
	check(r12["straggling_multiplier"] == 4, "12 chars should be 4x")
