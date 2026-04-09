class_name DungeonExploreState
extends SessionState

## Dungeon exploration: cell-to-cell movement, encounter checks, time advance.
##
## On enter: creates DungeonMapController, loads dungeon, pushes dungeon scene.
## On cell click: move → auto-stairs → encounter check → time advance.
## On exit: pops scene, destroys controller.

var _runner = null
var _controller: DungeonMapController = null
var _scene: Node = null


func enter(runner, context: Dictionary) -> void:
	_runner = runner
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

	_scene.exit_requested.connect(_on_exit_requested)
	_scene.cell_clicked.connect(_on_cell_clicked)
	_scene.door_interact_requested.connect(_on_door_interact)

	runner.get_nav_stack().push_node(
		_scene, "dungeon_%s" % entrance.get("id", "unknown")
	)


func exit(runner) -> void:
	runner.get_nav_stack().pop()

	if is_instance_valid(_controller):
		_controller.queue_free()
	_controller = null
	_scene = null
	_runner = null

	# Clear dungeon position
	CampaignRepository.clear_party_dungeon_position(runner.get_party_id())


func handle_action(runner, action: String, payload: Dictionary) -> String:
	match action:
		"exit_dungeon":
			return "wilderness"
		"end_session":
			return "session_end"
	return ""


func _on_cell_clicked(pos: Vector2i) -> void:
	if _runner == null or _controller == null or not _controller.can_move_to(pos):
		return

	_controller.move_party(pos)

	# Auto-use stairs
	var m: TacticalMapData = _controller.get_map()
	if m != null:
		var tf: String = m.get_cell(pos).get("terrain_feature", "")
		if tf == "stairs_up" or tf == "stairs_down":
			_controller.use_stairs(pos)

	# Encounter check (1 in 6 per dungeon turn)
	var encounter: Dictionary = _runner.do_encounter_check(null)
	if encounter.get("triggered", false):
		var enc: Dictionary = encounter["encounter_data"]
		print("ENCOUNTER (dungeon): %d x %s (%s, reaction %d)" % [
			enc.get("number", 0), enc.get("monster_group", "unknown"),
			enc.get("behavioral_disposition", "neutral"),
			enc.get("reaction_roll", 0)])
		var tactical_map: TacticalMapData = null
		if _controller != null:
			tactical_map = _controller.get_map()
		var combat_context := {
			"encounter_data": enc,
			"return_state":   "dungeon",
			"tactical_map":   tactical_map,
		}
		_runner.transition_to_state("combat", combat_context)
		return  # CombatState handles time advance on exit

	# Advance 1 dungeon turn (10 minutes)
	_runner.advance_exploration_time(1)


func _on_door_interact(pos: Vector2i) -> void:
	if _controller != null:
		_controller.interact_door(pos)


func _on_exit_requested() -> void:
	if _runner != null:
		_runner.transition_to_state("wilderness")
