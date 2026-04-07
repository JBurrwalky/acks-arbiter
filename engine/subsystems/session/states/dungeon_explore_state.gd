class_name DungeonExploreState
extends SessionState

## Dungeon exploration: cell-to-cell movement, encounter checks, time advance.
##
## On enter: creates DungeonMapController, loads dungeon, pushes dungeon scene.
## On cell click: move → auto-stairs → encounter check → time advance.
## On exit: pops scene, destroys controller.

var _controller: DungeonMapController = null
var _scene: Node = null
var _cell_clicked_cb: Callable
var _door_interact_cb: Callable
var _exit_cb: Callable


func enter(runner, context: Dictionary) -> void:
	var entrance: Dictionary = context.get("entrance", {})
	var spawn_cell: Vector2i = context.get("spawn_cell", Vector2i(-1, -1))

	var dungeon_json: String = entrance.get("dungeon_data", "")
	if dungeon_json.is_empty():
		push_error("DungeonExploreState: entrance has empty dungeon_data")
		runner.transition_to_state("wilderness")
		return

	var dungeon_dict = JSON.parse_string(dungeon_json)
	if dungeon_dict == null:
		push_error("DungeonExploreState: JSON parse failed")
		runner.transition_to_state("wilderness")
		return

	# Create controller
	_controller = DungeonMapController.new()
	_controller.name = "DungeonMapController"
	runner.add_child(_controller)
	_controller.add_party_member("party_leader")
	_controller.load_dungeon(dungeon_dict, spawn_cell)

	# Save party dungeon position
	CampaignRepository.update_party_dungeon_position(
		runner.get_party_id(),
		_controller.get_dungeon_id(),
		_controller.get_current_level(),
		spawn_cell.x, spawn_cell.y
	)

	# Instantiate and wire dungeon scene
	var packed: PackedScene = preload("res://scenes/maps/dungeon_map.tscn")
	_scene = packed.instantiate()
	_scene.setup(_controller)

	_exit_cb = func(): _on_exit_requested(runner)
	_scene.exit_requested.connect(_exit_cb)

	_cell_clicked_cb = func(pos: Vector2i): _on_cell_clicked(runner, pos)
	_scene.cell_clicked.connect(_cell_clicked_cb)

	_door_interact_cb = func(pos: Vector2i): _controller.interact_door(pos)
	_scene.door_interact_requested.connect(_door_interact_cb)

	runner.get_nav_stack().push_node(
		_scene, "dungeon_%s" % entrance.get("id", "unknown")
	)


func exit(runner) -> void:
	runner.get_nav_stack().pop()

	if is_instance_valid(_controller):
		_controller.queue_free()
	_controller = null
	_scene = null

	# Clear dungeon position
	CampaignRepository.clear_party_dungeon_position(runner.get_party_id())


func handle_action(runner, action: String, payload: Dictionary) -> String:
	match action:
		"exit_dungeon":
			return "wilderness"
		"end_session":
			return "session_end"
	return ""


func _on_cell_clicked(runner, pos: Vector2i) -> void:
	if _controller == null or not _controller.can_move_to(pos):
		return

	_controller.move_party(pos)

	# Auto-use stairs
	var m: TacticalMapData = _controller.get_map()
	if m != null:
		var tf: String = m.get_cell(pos).get("terrain_feature", "")
		if tf == "stairs_up" or tf == "stairs_down":
			_controller.use_stairs(pos)

	# Encounter check (1 in 6 per dungeon turn)
	var encounter: Dictionary = runner.do_encounter_check(null)
	if encounter.get("triggered", false):
		runner.transition_to_state("combat", {
			"encounter_data": encounter.get("encounter_data", {}),
			"return_state": "dungeon",
		})
		return

	# Advance 1 dungeon turn (10 minutes)
	runner.advance_exploration_time(1)


func _on_exit_requested(runner) -> void:
	runner.transition_to_state("wilderness")
