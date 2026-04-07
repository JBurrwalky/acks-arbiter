class_name WildernessExploreState
extends SessionState

## Wilderness exploration: hex map movement, encounter checks, time advance.
##
## On enter: shows hex map, connects renderer signals.
## On hex click: move party → encounter check → time advance → autosave.
## On dungeon/settlement entry: transition to dungeon/settlement state.

var _runner = null  # stored reference to avoid closure issues


func enter(runner, context: Dictionary) -> void:
	_runner = runner
	var renderer: Node = runner.get_hex_map_renderer()

	# Show hex map
	renderer.visible = true
	renderer.process_mode = Node.PROCESS_MODE_INHERIT
	_show_hex_hud(renderer, true)

	# Connect renderer signals (safe: _connect checks for existing connections)
	_connect(renderer, "hex_clicked", _on_hex_clicked)
	_connect(renderer, "dungeon_entry_requested", _on_dungeon_entry)
	_connect(renderer, "settlement_entry_requested", _on_settlement_entry)


func exit(runner) -> void:
	var renderer: Node = runner.get_hex_map_renderer()

	# Disconnect renderer signals
	_disconnect(renderer, "hex_clicked", _on_hex_clicked)
	_disconnect(renderer, "dungeon_entry_requested", _on_dungeon_entry)
	_disconnect(renderer, "settlement_entry_requested", _on_settlement_entry)

	# Hide hex map (only needed when transitioning to dungeon/settlement,
	# but safe to always do — re-shown on enter)
	renderer.visible = false
	renderer.process_mode = Node.PROCESS_MODE_DISABLED
	_show_hex_hud(renderer, false)

	_runner = null


func handle_action(runner, action: String, payload: Dictionary) -> String:
	match action:
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

func _on_hex_clicked(coord: Vector2i) -> void:
	if _runner == null:
		return
	var controller: HexMapController = _runner.get_hex_map_controller()
	if not controller.can_move_to(coord):
		return

	controller.move_party(coord)

	# Save map state
	var map_data: HexMapData = controller.get_map()
	if map_data != null:
		CampaignRepository.save_hex_map(map_data, _runner.get_campaign_id())

	# Encounter check
	var terrain: HexTerrainData = map_data.get_hex(coord) if map_data != null else null
	if terrain != null:
		var encounter: Dictionary = _runner.do_encounter_check(terrain)
		if encounter.get("triggered", false):
			# Log encounter but do NOT transition to combat — combat system (F-1)
			# not yet built. Future: runner.transition_to_state("combat", {...})
			print("SessionRunner: encounter triggered at %s (combat not yet implemented)" % str(coord))

	# Time advance (1 turn per hex for now — future: terrain-based turn cost)
	_runner.advance_exploration_time(1)

	# Autosave
	_runner.save_session()


func _on_dungeon_entry(entrance: Dictionary, spawn_cell: Vector2i) -> void:
	if _runner == null:
		return
	_runner.transition_to_state("dungeon", {
		"entrance": entrance,
		"spawn_cell": spawn_cell,
	})


func _on_settlement_entry(entrance: Dictionary, gate_node_id: int) -> void:
	if _runner == null:
		return
	_runner.transition_to_state("settlement", {
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


func _connect(obj: Node, sig_name: String, method: Callable) -> void:
	if not obj.is_connected(sig_name, method):
		obj.connect(sig_name, method)


func _disconnect(obj: Node, sig_name: String, method: Callable) -> void:
	if obj.is_connected(sig_name, method):
		obj.disconnect(sig_name, method)
