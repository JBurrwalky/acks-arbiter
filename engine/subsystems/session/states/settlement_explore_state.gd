class_name SettlementExploreState
extends SessionState

## Settlement exploration: graph-based movement, building entry, time advance.
##
## On enter: creates SettlementMapController, loads settlement, pushes scene,
## registers settlement event handlers with the scheduler.
## On node click: schedules settlement_move event via SettlementHandlers.
## On exit: pops scene, destroys controller, unregisters handlers.

var _runner = null
var _controller: SettlementMapController = null
var _scene: Node = null
var _handlers: SettlementHandlers = null


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
	_controller.building_entered.connect(_on_building_entered)

	runner.get_nav_stack().push_node(
		_scene, "settlement_%s" % entrance.get("id", "unknown")
	)

	# Register settlement event handlers with the scheduler.
	_handlers = SettlementHandlers.new(runner)
	_handlers.register(runner.get_handler_registry())

	# Set settlement time scale — turn-level granularity.
	runner.get_scheduler_loop().set_timescale(SchedulerLoop.TIMESCALE_SETTLEMENT)

	# Check party time lock (returning from combat in settlement).
	runner.check_party_time_lock()


func exit(runner) -> void:
	runner.get_nav_stack().pop()

	# Unregister settlement handlers.
	if _handlers != null:
		_handlers.unregister(runner.get_handler_registry())
		_handlers = null

	# Pause scheduler when leaving settlement context.
	var loop: SchedulerLoop = runner.get_scheduler_loop()
	if loop != null and not loop.is_paused():
		loop.pause()

	if is_instance_valid(_controller):
		_controller.queue_free()
	_controller = null
	_scene = null
	_runner = null


func handle_action(runner, action: String, payload: Dictionary) -> String:
	match action:
		"exit_settlement":
			return "wilderness"
		"cancel_movement":
			_cancel_settlement_orders(runner)
		"cancel_activity":
			_cancel_settlement_activity(runner)
		"end_session":
			return "session_end"
	return ""


## Cancel pending settlement movement. Party stays at current node.
func _cancel_settlement_orders(runner) -> void:
	var party_id: String = runner.get_party_id()
	var cancelled: int = runner.get_scheduler().cancel_all_for_owner(party_id, "settlement_move")
	if cancelled > 0:
		EventBus.order_cancelled.emit(party_id, "settlement_move")
	var loop: SchedulerLoop = runner.get_scheduler_loop()
	if loop != null and not loop.is_paused():
		loop.pause()


## Cancel a pending settlement activity (shopping, hiring, etc.).
## Time already elapsed is consumed.
func _cancel_settlement_activity(runner) -> void:
	var party_id: String = runner.get_party_id()
	var cancelled: int = runner.get_scheduler().cancel_all_for_owner(party_id, "settlement_activity")
	if cancelled > 0:
		EventBus.order_cancelled.emit(party_id, "settlement_activity")


func _on_node_clicked(node_id: int) -> void:
	if _runner == null or _controller == null or not _controller.can_move_to(node_id):
		return

	# Block orders if party is time-locked.
	if _runner.is_party_locked(_runner.get_party_id()):
		EventBus.notification_requested.emit({
			"type": "warning",
			"category": "system",
			"title": "Party Locked",
			"body": "This party is committed to an activity.",
		})
		return

	var scheduler: EventScheduler = _runner.get_scheduler()
	var party_id: String = _runner.get_party_id()

	# Cancel any existing settlement move for this party.
	scheduler.cancel_all_for_owner(party_id, "settlement_move")

	# Schedule the move.
	_handlers.schedule_move(node_id, scheduler, party_id)

	# Start the clock.
	var loop: SchedulerLoop = _runner.get_scheduler_loop()
	if loop.is_paused():
		loop.resume(SchedulerLoop.SPEED_MAX)  # Settlement moves resolve instantly


func _on_building_entered(poi: Dictionary) -> void:
	var poi_type: String = poi.get("type", "")
	match poi_type:
		"tavern", "inn":
			_open_hiring_panel(poi)
		"shop", "shophouse", "emporium":
			_open_shop_panel(poi)


func _open_hiring_panel(_poi: Dictionary) -> void:
	# Phase G-2 stub: the hiring panel will be pushed as a modal.
	pass


func _open_shop_panel(poi: Dictionary) -> void:
	if _runner == null or _controller == null:
		return
	var settlement_data: SettlementMapData = _controller.get_settlement_data()
	var market_class: int = settlement_data.market_class if settlement_data != null else 6
	var settlement_id: String = settlement_data.settlement_id if settlement_data != null else ""
	var campaign_id: String = GameState.current_campaign_id

	var service := ShopService.new()
	var current_round: int = Timekeeping.get_party_time(_runner.get_party_id())
	var shop_data := service.open_shop(poi, market_class, settlement_id, campaign_id, current_round)

	var panel := preload("res://scenes/ui/settlement/shop_panel.tscn").instantiate()
	panel.setup(shop_data, _runner, service)
	_runner.get_nav_stack().push_node(panel)
	panel.closed.connect(func():
		_runner.get_nav_stack().pop_node()
	)


func _on_exit_requested() -> void:
	if _runner != null:
		# Pause scheduler before leaving.
		var loop: SchedulerLoop = _runner.get_scheduler_loop()
		if loop != null and not loop.is_paused():
			loop.pause()
		_runner.transition_to_state("wilderness")
