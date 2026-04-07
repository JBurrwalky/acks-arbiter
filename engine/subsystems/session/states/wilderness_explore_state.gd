class_name WildernessExploreState
extends SessionState

## Wilderness exploration: hex map movement, encounter checks, time advance.
##
## On enter: shows hex map, connects renderer signals.
## On hex click: move party → encounter check → time advance → autosave.
## On dungeon/settlement entry: transition to dungeon/settlement state.


# ---------------------------------------------------------------------------
# Signal connections (stored for clean disconnection)
# ---------------------------------------------------------------------------

var _hex_clicked_cb: Callable
var _dungeon_entry_cb: Callable
var _settlement_entry_cb: Callable


func enter(runner, context: Dictionary) -> void:
	var renderer: Node = runner.get_hex_map_renderer()

	# Show hex map
	renderer.visible = true
	renderer.process_mode = Node.PROCESS_MODE_INHERIT
	_show_hex_hud(renderer, true)

	# Connect renderer signals
	_hex_clicked_cb = func(coord: Vector2i): _on_hex_clicked(runner, coord)
	_dungeon_entry_cb = func(entrance: Dictionary, spawn_cell: Vector2i):
		_on_dungeon_entry(runner, entrance, spawn_cell)
	_settlement_entry_cb = func(entrance: Dictionary, gate_node_id: int):
		_on_settlement_entry(runner, entrance, gate_node_id)

	if not renderer.hex_clicked.is_connected(_hex_clicked_cb):
		renderer.hex_clicked.connect(_hex_clicked_cb)
	if not renderer.dungeon_entry_requested.is_connected(_dungeon_entry_cb):
		renderer.dungeon_entry_requested.connect(_dungeon_entry_cb)
	if not renderer.settlement_entry_requested.is_connected(_settlement_entry_cb):
		renderer.settlement_entry_requested.connect(_settlement_entry_cb)


func exit(runner) -> void:
	var renderer: Node = runner.get_hex_map_renderer()

	# Disconnect renderer signals
	if renderer.hex_clicked.is_connected(_hex_clicked_cb):
		renderer.hex_clicked.disconnect(_hex_clicked_cb)
	if renderer.dungeon_entry_requested.is_connected(_dungeon_entry_cb):
		renderer.dungeon_entry_requested.disconnect(_dungeon_entry_cb)
	if renderer.settlement_entry_requested.is_connected(_settlement_entry_cb):
		renderer.settlement_entry_requested.disconnect(_settlement_entry_cb)

	# Hide hex map
	renderer.visible = false
	renderer.process_mode = Node.PROCESS_MODE_DISABLED
	_show_hex_hud(renderer, false)


func handle_action(runner, action: String, payload: Dictionary) -> String:
	match action:
		"move_to_hex":
			var coord: Vector2i = payload.get("coord", Vector2i.ZERO)
			_on_hex_clicked(runner, coord)
		"enter_dungeon":
			return "dungeon"
		"enter_settlement":
			return "settlement"
		"end_session":
			return "session_end"
	return ""


# ---------------------------------------------------------------------------
# Event handlers
# ---------------------------------------------------------------------------

func _on_hex_clicked(runner, coord: Vector2i) -> void:
	var controller: HexMapController = runner.get_hex_map_controller()
	if not controller.can_move_to(coord):
		return

	controller.move_party(coord)

	# Save map state
	var map_data: HexMapData = controller.get_map()
	if map_data != null:
		CampaignRepository.save_hex_map(map_data, runner.get_campaign_id())

	# Encounter check
	var terrain: HexTerrainData = map_data.get_hex(coord) if map_data != null else null
	if terrain != null:
		var encounter: Dictionary = runner.do_encounter_check(terrain)
		if encounter.get("triggered", false):
			runner.transition_to_state("combat", {
				"encounter_data": encounter.get("encounter_data", {}),
				"return_state": "wilderness",
			})
			return

	# Time advance (1 turn per hex for now — future: terrain-based turn cost)
	runner.advance_exploration_time(1)

	# Autosave
	runner.save_session()


func _on_dungeon_entry(runner, entrance: Dictionary, spawn_cell: Vector2i) -> void:
	runner.transition_to_state("dungeon", {
		"entrance": entrance,
		"spawn_cell": spawn_cell,
	})


func _on_settlement_entry(runner, entrance: Dictionary, gate_node_id: int) -> void:
	runner.transition_to_state("settlement", {
		"entrance": entrance,
		"gate_node_id": gate_node_id,
	})


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _show_hex_hud(renderer: Node, show: bool) -> void:
	var hex_hud: Node = renderer.get_node_or_null("HexHUD")
	if hex_hud != null:
		hex_hud.visible = show
