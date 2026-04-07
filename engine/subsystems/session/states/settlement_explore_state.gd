class_name SettlementExploreState
extends SessionState

## Settlement exploration: graph-based movement, building entry, time advance.
##
## On enter: creates SettlementMapController, loads settlement, pushes scene.
## On node click: move → time advance → building interaction.
## On exit: pops scene, destroys controller.

var _runner = null
var _controller: SettlementMapController = null
var _scene: Node = null


func enter(runner, context: Dictionary) -> void:
	_runner = runner
	var entrance: Dictionary = context.get("entrance", {})
	var gate_node_id: int = context.get("gate_node_id", -1)

	var settlement_json: String = entrance.get("settlement_data", "")
	if settlement_json.is_empty():
		push_error("SettlementExploreState: entrance has empty settlement_data")
		runner.transition_to_state("wilderness")
		return

	var settlement_dict = JSON.parse_string(settlement_json)
	if settlement_dict == null:
		push_error("SettlementExploreState: JSON parse failed")
		runner.transition_to_state("wilderness")
		return

	# Create controller
	_controller = SettlementMapController.new()
	_controller.name = "SettlementMapController"
	runner.add_child(_controller)
	_controller.load_settlement(settlement_dict)
	if gate_node_id >= 0:
		_controller.set_party_node(gate_node_id)

	# Instantiate and wire settlement scene
	var packed: PackedScene = preload("res://scenes/maps/settlement_map.tscn")
	_scene = packed.instantiate()
	_scene.setup(_controller)

	_scene.exit_requested.connect(_on_exit_requested)
	_scene.node_clicked.connect(_on_node_clicked)

	runner.get_nav_stack().push_node(
		_scene, "settlement_%s" % entrance.get("id", "unknown")
	)


func exit(runner) -> void:
	runner.get_nav_stack().pop()

	if is_instance_valid(_controller):
		_controller.queue_free()
	_controller = null
	_scene = null
	_runner = null


func handle_action(runner, action: String, payload: Dictionary) -> String:
	match action:
		"exit_settlement":
			return "wilderness"
		"end_session":
			return "session_end"
	return ""


func _on_node_clicked(node_id: int) -> void:
	if _runner == null or _controller == null or not _controller.can_move_to(node_id):
		return

	_controller.move_party(node_id)

	# Advance 1 exploration turn (10 minutes) per movement in settlement
	_runner.advance_exploration_time(1)


func _on_exit_requested() -> void:
	if _runner != null:
		_runner.transition_to_state("wilderness")
