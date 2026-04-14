class_name WildernessExploreState
extends SessionState

## Wilderness exploration: hex map movement, encounter checks, time advance.
##
## On enter: shows hex map, registers wilderness event handlers with the
## scheduler, connects renderer signals.
## On hex click: schedules travel_leg events via WildernessHandlers.
## On dungeon/settlement entry: transition to dungeon/settlement state.

var _runner = null  # stored reference to avoid closure issues
var _handlers: WildernessHandlers = null


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

	# Connect status bar action buttons
	if not EventBus.camp_requested.is_connected(_on_camp_requested):
		EventBus.camp_requested.connect(_on_camp_requested)
	if not EventBus.day_declaration_requested.is_connected(_on_day_declaration_requested):
		EventBus.day_declaration_requested.connect(_on_day_declaration_requested)

	# Register wilderness event handlers with the scheduler
	_handlers = WildernessHandlers.new(runner)
	_handlers.register(runner.get_handler_registry())

	# Check if the party is time-locked (returning from combat/dungeon
	# with time ahead of the global clock).
	runner.check_party_time_lock()

	# Start the scheduler paused — player issues orders, then unpauses.
	# (If the scheduler was already running and we returned from combat,
	# it was paused by CombatState. Leave it paused for the player.)


func exit(runner) -> void:
	var renderer: Node = runner.get_hex_map_renderer()

	# Disconnect renderer signals
	_disconnect(renderer, "hex_clicked", _on_hex_clicked)
	_disconnect(renderer, "dungeon_entry_requested", _on_dungeon_entry)
	_disconnect(renderer, "settlement_entry_requested", _on_settlement_entry)

	# Disconnect status bar action buttons
	if EventBus.camp_requested.is_connected(_on_camp_requested):
		EventBus.camp_requested.disconnect(_on_camp_requested)
	if EventBus.day_declaration_requested.is_connected(_on_day_declaration_requested):
		EventBus.day_declaration_requested.disconnect(_on_day_declaration_requested)

	# Unregister wilderness event handlers
	if _handlers != null:
		_handlers.unregister(runner.get_handler_registry())
		_handlers = null

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
		"cancel_travel":
			_cancel_current_orders(runner)
		"end_session":
			return "session_end"
	return ""


## Cancel all travel orders for the active party. Party stops at current hex.
func _cancel_current_orders(runner) -> void:
	var party_id: String = runner.get_party_id()
	var scheduler: EventScheduler = runner.get_scheduler()
	var cancelled: int = scheduler.cancel_all_for_owner(party_id, "travel_leg")
	cancelled += scheduler.cancel_all_for_owner(party_id, "getting_lost_check")
	cancelled += scheduler.cancel_all_for_owner(party_id, "forced_march_check")
	if cancelled > 0:
		EventBus.order_cancelled.emit(party_id, "travel_leg")
	var loop: SchedulerLoop = runner.get_scheduler_loop()
	if loop != null and not loop.is_paused():
		loop.pause()


# ---------------------------------------------------------------------------
# Event handlers
# ---------------------------------------------------------------------------

func _on_hex_clicked(coord: Vector2i) -> void:
	if _runner == null:
		return

	# Block orders if the party is time-locked
	if _runner.is_party_locked(_runner.get_party_id()):
		EventBus.notification_requested.emit({
			"type": "warning",
			"category": "system",
			"title": "Party Locked",
			"body": "This party is committed to an activity. Wait for the world clock to catch up.",
		})
		return

	var controller: HexMapController = _runner.get_hex_map_controller()
	if not controller.can_move_to(coord):
		return

	var scheduler: EventScheduler = _runner.get_scheduler()
	var party_data: PartyData = _runner.get_party_data()
	var map_data: HexMapData = controller.get_map()

	# Cancel any existing travel orders for this party
	var party_id: String = _runner.get_party_id()
	var cancelled: int = scheduler.cancel_all_for_owner(party_id, "travel_leg")
	if cancelled > 0:
		EventBus.order_cancelled.emit(party_id, "travel_leg")

	# Schedule the travel path (single hex for now — future: full pathfinding)
	var path: Array = [coord]
	_handlers.schedule_travel_path(path, scheduler, party_data, map_data)

	# Start the clock if paused
	var loop: SchedulerLoop = _runner.get_scheduler_loop()
	if loop.is_paused():
		loop.resume(SchedulerLoop.SPEED_NORMAL)


func _on_camp_requested() -> void:
	if _runner == null:
		return
	# Pause the scheduler before transitioning
	var loop: SchedulerLoop = _runner.get_scheduler_loop()
	if loop != null:
		loop.pause()
	_runner.transition_to_state("camp", {
		"return_state": "wilderness",
		"is_town": false,
	})


func _on_day_declaration_requested() -> void:
	if _runner == null:
		return
	var loop: SchedulerLoop = _runner.get_scheduler_loop()
	if loop != null:
		loop.pause()
	_runner.transition_to_state("day_declaration", {
		"return_state": "wilderness",
	})


func _on_dungeon_entry(entrance: Dictionary, spawn_cell: Vector2i) -> void:
	if _runner == null:
		return
	# Pause scheduler — dungeon runs its own time independently
	var loop: SchedulerLoop = _runner.get_scheduler_loop()
	if loop != null:
		loop.pause()
	_runner.transition_to_state("dungeon", {
		"entrance": entrance,
		"spawn_cell": spawn_cell,
	})


func _on_settlement_entry(entrance: Dictionary, gate_node_id: int) -> void:
	if _runner == null:
		return
	var loop: SchedulerLoop = _runner.get_scheduler_loop()
	if loop != null:
		loop.pause()
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
