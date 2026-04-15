class_name SettlementExploreState
extends SessionState

## Settlement exploration: menu-driven PoI navigation with scheduled travel.
##
## The player selects destinations from a PoI list in the SettlementPanel.
## Travel is a scheduled event that consumes time, with navigation throws
## (commuting speed) and encounter checks at time-based intervals.
##
## The hex map remains visible (left ~60%). The settlement panel overlays
## the right ~40% as a HUD CanvasLayer — it does NOT replace the hex map
## via nav_stack.
##
## On enter: creates controller, loads settlement, creates HUD panel,
##   registers settlement event handlers, auto-discovers obvious POIs.
## On PoI click: schedules travel via SettlementHandlers.
## On exit: removes HUD, destroys controller, unregisters handlers.

var _runner = null
var _controller: SettlementMapController = null
var _handlers: SettlementHandlers = null
var _settlement_hud: CanvasLayer = null
var _panel: SettlementPanel = null
var _activity_panel: SettlementActivityPanel = null
var _overview_widget: Control = null  # city_overview_widget.gd
var _settlement_id: String = ""
var _campaign_id: String = ""


func enter(runner, context: Dictionary) -> void:
	_runner = runner
	_campaign_id = GameState.campaign_id
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

	# Create controller.
	_controller = SettlementMapController.new()
	_controller.name = "SettlementMapController"
	runner.add_child(_controller)
	_controller.load_settlement(settlement_dict)
	_settlement_id = _controller.get_settlement_id()
	if gate_node_id >= 0:
		_controller.set_party_node(gate_node_id)

	# Register settlement event handlers with the scheduler.
	_handlers = SettlementHandlers.new(runner)
	_handlers.register(runner.get_handler_registry())

	# Auto-discover obvious POIs on entry.
	_auto_discover_obvious_pois()

	# Create the settlement HUD overlay.
	_create_settlement_hud()

	# Set settlement time scale — turn-level granularity.
	runner.get_scheduler_loop().set_timescale(SchedulerLoop.TIMESCALE_SETTLEMENT)

	# Listen for scheduler events to update the UI.
	if not EventBus.scheduler_event_resolved.is_connected(_on_scheduler_event_resolved):
		EventBus.scheduler_event_resolved.connect(_on_scheduler_event_resolved)

	# Check party time lock (returning from combat/dungeon in settlement).
	runner.check_party_time_lock()


func exit(runner) -> void:
	# Disconnect scheduler event listener.
	if EventBus.scheduler_event_resolved.is_connected(_on_scheduler_event_resolved):
		EventBus.scheduler_event_resolved.disconnect(_on_scheduler_event_resolved)

	# Unregister settlement handlers and cancel pending events.
	if _handlers != null:
		var party_id: String = runner.get_party_id()
		_handlers.cancel_travel(runner.get_scheduler(), party_id)
		runner.get_scheduler().cancel_all_for_owner(party_id, "settlement_activity")
		_handlers.unregister(runner.get_handler_registry())
		_handlers = null

	# Pause scheduler when leaving settlement context.
	var loop: SchedulerLoop = runner.get_scheduler_loop()
	if loop != null and not loop.is_paused():
		loop.pause()

	# Clean up HUD.
	if _settlement_hud != null and is_instance_valid(_settlement_hud):
		_settlement_hud.queue_free()
	_settlement_hud = null
	_panel = null

	if is_instance_valid(_controller):
		_controller.queue_free()
	_controller = null
	_runner = null


func handle_action(runner, action: String, payload: Dictionary) -> String:
	match action:
		"exit_settlement":
			return "wilderness"
		"cancel_travel":
			if _handlers != null:
				_handlers.cancel_travel(runner.get_scheduler(), runner.get_party_id())
				if _panel != null:
					_panel.hide_travel_progress()
			var loop: SchedulerLoop = runner.get_scheduler_loop()
			if loop != null and not loop.is_paused():
				loop.pause()
		"end_session":
			return "session_end"
	return ""


# ---------------------------------------------------------------------------
# HUD creation
# ---------------------------------------------------------------------------

func _create_settlement_hud() -> void:
	_settlement_hud = CanvasLayer.new()
	_settlement_hud.name = "SettlementHUD"
	_settlement_hud.layer = 10
	_runner.add_child(_settlement_hud)

	# Create and setup the settlement panel.
	_panel = preload("res://scenes/ui/settlement/settlement_panel.tscn").instantiate()
	_settlement_hud.add_child(_panel)

	var party_size: int = _get_party_size()
	var discovered := CampaignRepository.get_discovered_poi_ids(_campaign_id, _settlement_id)

	_panel.setup(
		_controller.get_map(),
		_controller.get_party_node_id(),
		party_size,
		discovered,
	)

	# Create city overview widget (top-left corner).
	var WidgetScript := preload("res://scenes/ui/settlement/city_overview_widget.gd")
	_overview_widget = WidgetScript.new()
	_overview_widget.position = Vector2(8, 8)
	_settlement_hud.add_child(_overview_widget)
	_overview_widget.setup(
		_controller.get_map(),
		_controller.get_party_node_id(),
		discovered,
	)

	# Create activity panel inside the settlement panel's activity area.
	_activity_panel = SettlementActivityPanel.new()
	_activity_panel.visible = false
	_panel.get_activity_area().add_child(_activity_panel)
	_activity_panel.exit_settlement_requested.connect(_on_exit_requested)
	_activity_panel.shop_requested.connect(_on_shop_requested)
	_activity_panel.hiring_requested.connect(_on_hiring_requested)
	_activity_panel.activity_requested.connect(_on_activity_requested)

	# Wire panel signals.
	_panel.poi_clicked.connect(_on_poi_clicked)
	_panel.travel_cancelled.connect(_on_travel_cancelled)
	_panel.speed_toggled.connect(_on_speed_toggled)
	_panel.exit_requested.connect(_on_exit_requested)

	# If party starts at a POI, show activity panel immediately.
	var start_poi: Dictionary = _controller.get_current_poi()
	if not start_poi.is_empty():
		_activity_panel.show_for_poi(start_poi)


# ---------------------------------------------------------------------------
# POI discovery
# ---------------------------------------------------------------------------

func _auto_discover_obvious_pois() -> void:
	if _controller == null:
		return
	var map_data: SettlementMapData = _controller.get_map()
	if map_data == null:
		return
	var current_round: int = Timekeeping.get_party_time(_runner.get_party_id())

	for poi in map_data.pois:
		var importance: String = poi.get("importance", "minor")
		var poi_type: String = poi.get("type", "")
		# Obvious: gates, major temples, markets, large taverns.
		if importance == "major" or poi_type == "gate":
			CampaignRepository.record_visited_poi(
				_campaign_id, _settlement_id,
				poi.get("id", ""), current_round, "obvious")


# ---------------------------------------------------------------------------
# Signal handlers from panel
# ---------------------------------------------------------------------------

func _on_poi_clicked(poi: Dictionary) -> void:
	if _runner == null or _controller == null or _handlers == null:
		return

	var party_id: String = _runner.get_party_id()

	# Block orders if party is time-locked.
	if _runner.is_party_locked(party_id):
		EventBus.notification_requested.emit({
			"type": "warning",
			"category": "system",
			"title": "Party Locked",
			"body": "This party is committed to an activity.",
		})
		return

	# Check if we're already at this POI.
	var poi_node_ids: Array = poi.get("street_node_ids", [])
	if not poi_node_ids.is_empty() and _controller.get_party_node_id() == poi_node_ids[0]:
		# Already here — show the activity panel.
		if _activity_panel != null:
			_activity_panel.show_for_poi(poi)
		return

	# Cancel any existing travel.
	_handlers.cancel_travel(_runner.get_scheduler(), party_id)

	# Get current POI for route memory.
	var current_poi: Dictionary = _controller.get_map().get_poi_at_node(
		_controller.get_party_node_id())

	# Determine night status from Timekeeping.
	var is_night: bool = _is_nighttime()

	# Schedule travel.
	var result := _handlers.schedule_travel(
		_controller.get_map(),
		_controller.get_party_node_id(),
		poi,
		_panel.get_speed_mode(),
		not _panel.get_use_alleys(),  # streets_only = NOT use_alleys
		_get_party_size(),
		_runner.get_scheduler(),
		party_id,
		_campaign_id,
		_settlement_id,
		is_night,
		_panel.get_looking_for_trouble(),
		current_poi,
	)

	if result.is_empty():
		EventBus.notification_requested.emit({
			"type": "warning",
			"category": "system",
			"title": "No Route",
			"body": "Cannot find a route to that location.",
		})
		return

	# Show travel indicator.
	if _panel != null:
		_panel.show_travel_progress(
			result["block_count"], result["total_rounds"],
			result["block_count"], result["total_rounds"])

	# Start the clock.
	var loop: SchedulerLoop = _runner.get_scheduler_loop()
	if loop.is_paused():
		loop.resume(SchedulerLoop.SPEED_NORMAL)


func _on_travel_cancelled() -> void:
	if _runner != null:
		handle_action(_runner, "cancel_travel", {})


func _on_speed_toggled(_mode: String) -> void:
	# If currently traveling, cancel and reschedule at new speed.
	if _handlers != null and _handlers.is_traveling(_runner.get_party_id()):
		# For now, cancel travel. Player can re-click the destination.
		_on_travel_cancelled()


func _on_shop_requested(poi: Dictionary) -> void:
	if _runner == null or _controller == null:
		return
	var map_data: SettlementMapData = _controller.get_map()
	var market_class: int = map_data.market_class if map_data != null else 6
	var settlement_id: String = _controller.get_settlement_id()
	var campaign_id: String = GameState.campaign_id

	var service := ShopService.new()
	var current_round: int = Timekeeping.get_party_time(_runner.get_party_id())
	var shop_data := service.open_shop(poi, market_class, settlement_id, campaign_id, current_round)

	var panel := preload("res://scenes/ui/settlement/shop_panel.tscn").instantiate()
	panel.setup(shop_data, _runner, service)

	# Push shop panel as modal overlay in the activity area.
	if _activity_panel != null:
		_activity_panel.visible = false
	_panel.get_activity_area().add_child(panel)
	panel.closed.connect(func():
		panel.queue_free()
		if _activity_panel != null:
			_activity_panel.visible = true
	)


func _on_hiring_requested(poi: Dictionary) -> void:
	if _runner == null or _controller == null:
		return

	var party_data = _runner.get_party_data()
	if party_data == null:
		return

	# Get employer (party leader) CHA modifier.
	var employer: CharacterData = null
	for cd in party_data.character_data:
		if not cd.is_dead and cd.is_active:
			employer = cd
			break
	if employer == null:
		return

	var cha_mod: int = CharacterData.ability_modifier(employer.charisma)
	var employer_id: String = employer.id
	var party_id: String = _runner.get_party_id()
	var map_data: SettlementMapData = _controller.get_map()
	var market_class: int = map_data.market_class if map_data != null else 6

	# Create lifecycle manager on demand.
	var rep_system := ReputationSystem.new(CampaignRepository, _campaign_id, party_id)
	var lifecycle := HenchmanLifecycleManager.new(CampaignRepository, rep_system)

	# Get current month/year and week for pool generation.
	var date: Dictionary = Timekeeping.get_date()
	var month: int = date.get("month", 1)
	var year: int = date.get("year", 1)
	var day: int = date.get("day", 1)
	var current_week: int = clampi((day - 1) / 7 + 1, 1, 4)

	# Ensure a pool exists for this settlement+month.
	var pool_id: String = lifecycle.ensure_pool(
		_settlement_id, market_class, _campaign_id, month, year)
	var search_cost: int = lifecycle.get_search_cost(pool_id)

	# Instantiate and setup the hiring panel.
	var panel := HiringPanel.new()
	panel.setup(lifecycle, pool_id, _settlement_id, market_class,
		search_cost, current_week, employer_id, cha_mod, party_id)

	# Show it in the activity area (hide activity panel while hiring).
	if _activity_panel != null:
		_activity_panel.visible = false
	_panel.get_activity_area().add_child(panel)
	panel.closed.connect(func():
		panel.queue_free()
		if _activity_panel != null:
			_activity_panel.visible = true
	)
	panel.hire_completed.connect(func(character_id: String):
		EventBus.notification_requested.emit({
			"type": "info",
			"category": "settlement",
			"title": "Henchman Hired",
			"body": "A new henchman has joined the party.",
		})
	)


func _on_activity_requested(activity_type: String, poi: Dictionary) -> void:
	if _runner == null or _handlers == null:
		return
	# Schedule major activities as settlement_activity events.
	var duration_turns: int
	match activity_type:
		"gather_info":
			duration_turns = 24  # ~4 hours
		"carouse":
			duration_turns = 144  # ~1 day
		"rest_long":
			duration_turns = 48  # ~8 hours
		_:
			duration_turns = 1  # Minor activity placeholder

	if duration_turns > 1:
		_handlers.schedule_activity(
			activity_type, poi, duration_turns,
			_runner.get_scheduler(), _runner.get_party_id())
		var loop: SchedulerLoop = _runner.get_scheduler_loop()
		if loop.is_paused():
			loop.resume(SchedulerLoop.SPEED_NORMAL)
	else:
		# Minor activity — resolve immediately.
		EventBus.notification_requested.emit({
			"type": "info",
			"category": "settlement",
			"title": activity_type.capitalize(),
			"body": "Activity completed at %s." % poi.get("name", "location"),
		})


func _on_exit_requested() -> void:
	if _runner == null:
		return
	# Only allow exit when at a gate.
	if _controller != null and _controller.is_on_gate():
		var loop: SchedulerLoop = _runner.get_scheduler_loop()
		if loop != null and not loop.is_paused():
			loop.pause()
		_runner.transition_to_state("wilderness")
	else:
		EventBus.notification_requested.emit({
			"type": "warning",
			"category": "system",
			"title": "Not at Gate",
			"body": "Travel to a city gate to exit the settlement.",
		})


# ---------------------------------------------------------------------------
# Scheduler event listener
# ---------------------------------------------------------------------------

func _on_scheduler_event_resolved(event_type: String, data: Dictionary) -> void:
	match event_type:
		"city_travel_arrival":
			_on_arrival(data)
		"navigation_check":
			_on_nav_check(data)
		"city_encounter_check":
			_on_encounter_check(data)


func _on_arrival(data: Dictionary) -> void:
	if _controller == null or _panel == null:
		return
	# Update party position in the panel.
	var dest_poi: Dictionary = data.get("poi", {})
	var node_ids: Array = dest_poi.get("street_node_ids", [])
	if not node_ids.is_empty():
		_panel.update_party_position(node_ids[0])
	_panel.hide_travel_progress()

	# Refresh discovered POIs.
	var discovered := CampaignRepository.get_discovered_poi_ids(_campaign_id, _settlement_id)
	_panel.update_discovered_pois(discovered)

	# Update overview widget.
	if _overview_widget != null:
		_overview_widget.update_party_position(_controller.get_party_node_id())
		_overview_widget.update_discovered_pois(discovered)

	# Show activity panel for the arrived-at POI.
	if _activity_panel != null and not dest_poi.is_empty():
		_activity_panel.show_for_poi(dest_poi)


func _on_nav_check(data: Dictionary) -> void:
	if _panel == null:
		return
	var result: Dictionary = data.get("result", {})
	_panel.show_nav_result(result)


func _on_encounter_check(_data: Dictionary) -> void:
	# Encounter handling is done by the handler result dict (auto_pause, etc.)
	# The state just needs to be aware it happened for UI updates.
	pass


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _get_party_size() -> int:
	if _runner == null:
		return 1
	var party_data = _runner.get_party_data()
	if party_data == null:
		return 1
	var count := 0
	for cd in party_data.character_data:
		if not cd.is_dead and cd.is_active:
			count += 1
	return maxi(count, 1)


func _is_nighttime() -> bool:
	# Check if current time is between dusk and dawn.
	var party_id: String = _runner.get_party_id()
	var elapsed: int = Timekeeping.get_party_time(party_id)
	var time_of_day: int = elapsed % Timekeeping.ROUNDS_PER_DAY
	# Rough approximation: night = 18:00 to 06:00 (3/4 of day to 1/4 of day).
	var dusk_rounds: int = Timekeeping.ROUNDS_PER_DAY * 3 / 4  # ~18:00
	var dawn_rounds: int = Timekeeping.ROUNDS_PER_DAY / 4       # ~06:00
	return time_of_day >= dusk_rounds or time_of_day < dawn_rounds
