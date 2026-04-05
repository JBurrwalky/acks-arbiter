extends "res://tests/test_suite_base.gd"

## Unit tests for SettlementMapController.
##
## Tests party positioning, movement on the street graph, signal emission,
## building entrance detection, settlement exit, and AStar2D pathfinding.


var _controller: SettlementMapController
var _settlement_dict: Dictionary

# Signal tracking
var _last_party_moved_from: int = -1
var _last_party_moved_to: int = -1
var _last_building_entered_poi: Dictionary = {}
var _last_settlement_exited_gate: int = -1
var _map_loaded_id: String = ""


func run_all_tests() -> void:
	_load_test_data()
	_setup_controller()
	test_load_positions_party_at_entry()
	test_get_party_position_returns_vector2()
	test_get_adjacent_nodes()
	test_move_to_adjacent_node()
	test_move_non_adjacent_fails()
	test_party_moved_signal()
	test_building_entered_on_poi_node()
	test_building_entered_carries_poi_data()
	test_settlement_exited_on_gate()
	test_find_path_to_distant_node()
	test_map_loaded_signal()
	if not has_failures():
		print("SettlementMapController: all tests passed.")


func _load_test_data() -> void:
	var file := FileAccess.open("res://data/test_settlement.json", FileAccess.READ)
	check(file != null, "should open test_settlement.json")
	if file == null:
		return
	var json_text := file.get_as_text()
	file.close()
	_settlement_dict = JSON.parse_string(json_text)
	check(_settlement_dict != null and not _settlement_dict.is_empty(),
		"should parse test_settlement.json")


func _setup_controller() -> void:
	# Create a fresh controller for each test run
	if _controller != null:
		_controller.queue_free()
	_controller = SettlementMapController.new()
	_controller.name = "TestSettlementController"
	add_child(_controller)

	# Connect signals
	_controller.map_loaded.connect(_on_map_loaded)
	_controller.party_moved.connect(_on_party_moved)
	_controller.building_entered.connect(_on_building_entered)
	_controller.settlement_exited.connect(_on_settlement_exited)

	# Reset signal tracking
	_reset_signals()

	# Load settlement
	_controller.load_settlement(_settlement_dict)


func _reset_signals() -> void:
	_last_party_moved_from = -1
	_last_party_moved_to = -1
	_last_building_entered_poi = {}
	_last_settlement_exited_gate = -1
	_map_loaded_id = ""


func _on_map_loaded(settlement_id: String) -> void:
	_map_loaded_id = settlement_id

func _on_party_moved(from_id: int, to_id: int) -> void:
	_last_party_moved_from = from_id
	_last_party_moved_to = to_id

func _on_building_entered(poi: Dictionary) -> void:
	_last_building_entered_poi = poi

func _on_settlement_exited(gate_id: int) -> void:
	_last_settlement_exited_gate = gate_id


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_load_positions_party_at_entry() -> void:
	check(_controller.get_party_node_id() == 13,
		"party should be at entry node 13 (south gate), got %d" % _controller.get_party_node_id())


func test_get_party_position_returns_vector2() -> void:
	var pos: Vector2 = _controller.get_party_position()
	# Node 13 (south gate) is at [510, 990]
	check(abs(pos.x - 510.0) < 1.0 and abs(pos.y - 990.0) < 1.0,
		"party should be near (510, 990), got %s" % str(pos))


func test_get_adjacent_nodes() -> void:
	# Node 13 (south gate) connects to node 11 via edge 23
	var adj: Array[int] = _controller.get_adjacent_nodes()
	check(adj.size() == 1, "node 13 should have 1 adjacent node, got %d" % adj.size())
	check(11 in adj, "node 13 should be adjacent to node 11")


func test_move_to_adjacent_node() -> void:
	# Start at node 13, move to node 11 (adjacent)
	_reset_signals()
	var success := _controller.move_party(11)
	check(success, "move from node 13 to node 11 should succeed")
	check(_controller.get_party_node_id() == 11,
		"party should now be at node 11, got %d" % _controller.get_party_node_id())


func test_move_non_adjacent_fails() -> void:
	# Party at node 11. Node 0 (north gate) is not adjacent.
	var success := _controller.move_party(0)
	check(not success, "move from node 11 to non-adjacent node 0 should fail")
	check(_controller.get_party_node_id() == 11,
		"party should still be at node 11 after failed move")


func test_party_moved_signal() -> void:
	_reset_signals()
	# Move from 11 to 8 (v7, adjacent via edge 22)
	_controller.move_party(8)
	check(_last_party_moved_from == 11,
		"party_moved from should be 11, got %d" % _last_party_moved_from)
	check(_last_party_moved_to == 8,
		"party_moved to should be 8, got %d" % _last_party_moved_to)


func test_building_entered_on_poi_node() -> void:
	# Party at node 8 (v7). Move to node 17 (store POI, adjacent via edge 19).
	_reset_signals()
	_controller.move_party(17)
	check(not _last_building_entered_poi.is_empty(),
		"node 17 (store POI) should trigger building_entered")


func test_building_entered_carries_poi_data() -> void:
	check(_last_building_entered_poi.get("id", "") == "poi_store",
		"building_entered poi id should be 'poi_store', got '%s'" % _last_building_entered_poi.get("id", ""))
	check(_last_building_entered_poi.get("type", "") == "shop",
		"building_entered poi type should be 'shop'")
	check(_last_building_entered_poi.get("name", "") == "Ashford General Goods",
		"building_entered poi name should be 'Ashford General Goods'")


func test_settlement_exited_on_gate() -> void:
	# Navigate from store(17) to v4(5) to v1(2) to north gate(0)
	_controller.move_party(5)
	_controller.move_party(2)

	_reset_signals()
	_controller.move_party(0)
	check(_last_settlement_exited_gate == 0,
		"moving to north gate (node 0) should emit settlement_exited, got %d" % _last_settlement_exited_gate)


func test_find_path_to_distant_node() -> void:
	# Party is at node 0 (north gate). Get path to node 13 (south gate).
	var path: PackedInt64Array = _controller.find_path_to(13)
	check(path.size() >= 3,
		"path from node 0 to node 13 should have at least 3 nodes, got %d" % path.size())
	check(path[0] == 0, "path should start at node 0")
	check(path[path.size() - 1] == 13, "path should end at node 13")


func test_map_loaded_signal() -> void:
	check(_map_loaded_id == "test_settlement_ashford",
		"map_loaded should have emitted with 'test_settlement_ashford', got '%s'" % _map_loaded_id)
