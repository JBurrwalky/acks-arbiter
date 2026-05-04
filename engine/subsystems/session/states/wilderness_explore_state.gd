class_name WildernessExploreState
extends SessionState

## Wilderness exploration: hex map movement, encounter checks, time advance.
##
## On enter: shows hex map, registers wilderness event handlers with the
## scheduler, connects renderer signals.
## On hex click: schedules travel_leg events via WildernessHandlers.
## On dungeon/settlement entry: transition to dungeon/settlement state.

const ContextMenuScene := preload("res://scenes/maps/dungeon_context_menu.gd")

var _runner = null  # stored reference to avoid closure issues
var _handlers: WildernessHandlers = null
var _context_menu = null  # instance of ContextMenuScene (shared with dungeon UI)


func enter(runner, context: Dictionary) -> void:
	_runner = runner
	var renderer: Node = runner.get_hex_map_renderer()

	# Show hex map
	renderer.visible = true
	renderer.process_mode = Node.PROCESS_MODE_INHERIT
	_show_hex_hud(renderer, true)

	# Connect renderer signals (safe: _connect checks for existing connections).
	# Left-clicks on party tokens select that party; right-clicks open the
	# context menu. Empty-hex left-clicks emit `hex_clicked` but we ignore them.
	_connect(renderer, "party_token_clicked", _on_party_token_clicked)
	_connect(renderer, "hex_context_menu_requested", _on_hex_context_menu_requested)
	_connect(renderer, "dungeon_entry_requested", _on_dungeon_entry)
	_connect(renderer, "settlement_entry_requested", _on_settlement_entry)

	# Connect status bar action buttons
	if not EventBus.camp_requested.is_connected(_on_camp_requested):
		EventBus.camp_requested.connect(_on_camp_requested)

	# Listen for active party switches
	if not EventBus.active_party_changed.is_connected(_on_active_party_changed):
		EventBus.active_party_changed.connect(_on_active_party_changed)

	# Cache-visit dispatch: handler emits, we open the inventory overlay.
	if not EventBus.wilderness_cache_visit_requested.is_connected(_on_wilderness_cache_visit_requested):
		EventBus.wilderness_cache_visit_requested.connect(_on_wilderness_cache_visit_requested)

	# Ensure all parties in the campaign are registered with Timekeeping
	var all_parties := CampaignRepository.list_parties_for_campaign(GameState.campaign_id)
	for p in all_parties:
		Timekeeping.register_party(p.id)

	# Register wilderness event handlers with the scheduler
	_handlers = WildernessHandlers.new(runner)
	_handlers.register(runner.get_handler_registry())

	# Set wilderness time scale — 1x feels like watching the day advance.
	runner.get_scheduler_loop().set_timescale(SchedulerLoop.TIMESCALE_WILDERNESS)

	# Check if the party is time-locked (returning from combat/dungeon
	# with time ahead of the global clock).
	runner.check_party_time_lock()

	# Start the scheduler paused — player issues orders, then unpauses.
	# (If the scheduler was already running and we returned from combat,
	# it was paused by CombatState. Leave it paused for the player.)


func exit(runner) -> void:
	var renderer: Node = runner.get_hex_map_renderer()

	# Disconnect renderer signals
	_disconnect(renderer, "party_token_clicked", _on_party_token_clicked)
	_disconnect(renderer, "hex_context_menu_requested", _on_hex_context_menu_requested)
	_disconnect(renderer, "dungeon_entry_requested", _on_dungeon_entry)
	_disconnect(renderer, "settlement_entry_requested", _on_settlement_entry)

	# Disconnect status bar action buttons
	if EventBus.camp_requested.is_connected(_on_camp_requested):
		EventBus.camp_requested.disconnect(_on_camp_requested)
	if EventBus.active_party_changed.is_connected(_on_active_party_changed):
		EventBus.active_party_changed.disconnect(_on_active_party_changed)
	if EventBus.wilderness_cache_visit_requested.is_connected(_on_wilderness_cache_visit_requested):
		EventBus.wilderness_cache_visit_requested.disconnect(_on_wilderness_cache_visit_requested)

	_close_context_menu()

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

## Left-click on a party's token selects it as the active party. Issuing
## orders happens through the right-click context menu.
func _on_party_token_clicked(party_id: String, _coord: Vector2i) -> void:
	if party_id.is_empty() or party_id == GameState.active_party_id:
		return
	GameState.set_active_party(party_id)


## Right-click on a hex opens a context menu for the active party.
func _on_hex_context_menu_requested(coord: Vector2i, screen_pos: Vector2) -> void:
	if _runner == null:
		return

	var party_id: String = _resolve_active_party_id()
	if party_id.is_empty():
		return
	if _runner.is_party_locked(party_id):
		EventBus.notification_requested.emit({
			"type": "warning",
			"category": "system",
			"title": "Party Locked",
			"body": "This party is committed to an activity. Wait for the world clock to catch up.",
		})
		return

	var controller: HexMapController = _runner.get_hex_map_controller()
	var map_data: HexMapData = controller.get_map() if controller != null else null
	var current_hex: Vector2i = _resolve_party_hex(party_id, map_data)
	var options: Array[Dictionary] = WildernessContextMenuBuilder.build_menu(
		coord, party_id, map_data, controller, current_hex)
	if options.is_empty():
		return

	_close_context_menu()
	_context_menu = ContextMenuScene.new()
	# Show above the HexHUD CanvasLayer (layer 10) but below dice prompts (64).
	var layer := CanvasLayer.new()
	layer.layer = 24
	layer.add_child(_context_menu)
	_runner.get_hex_map_renderer().add_child(layer)
	_context_menu.option_selected.connect(_on_context_action)
	_context_menu.cancelled.connect(_close_context_menu)
	_context_menu.show_at(screen_pos, options, _runner.get_scheduler_loop())


## Dispatch a context-menu selection.
## Move Here pathfinds via HexMapController.find_path and chains one
## travel_leg per intermediate hex. Activity options append a
## wilderness_activity event after the final leg; if the target equals the
## party's current hex the activity fires in place with no travel.
func _on_context_action(action_data: Dictionary) -> void:
	_close_context_menu()
	if _runner == null:
		return

	var action_type: String = str(action_data.get("action_type", ""))
	if action_type == "" or action_type == "cancel":
		return

	var target_hex := Vector2i(
		int(action_data.get("hex_q", 0)),
		int(action_data.get("hex_r", 0)))
	var controller: HexMapController = _runner.get_hex_map_controller()
	if controller == null:
		return
	var map_data: HexMapData = controller.get_map()
	if map_data == null:
		return
	if not controller.is_hex_passable(target_hex):
		return

	var scheduler: EventScheduler = _runner.get_scheduler()
	var party_id: String = _resolve_active_party_id()
	if party_id.is_empty():
		return
	var party_data: PartyData = _resolve_party_data(party_id)
	if party_data == null:
		return

	# Cancel prior travel and any queued follow-up activity for this party.
	# Right-clicking a new Move Here while traveling supersedes the journey.
	var cancelled: int = scheduler.cancel_all_for_owner(party_id, "travel_leg")
	cancelled += scheduler.cancel_all_for_owner(party_id, WildernessHandlers.ACTIVITY_EVENT)
	cancelled += scheduler.cancel_all_for_owner(party_id, WildernessHandlers.ACTIVITY_COMPLETE_EVENT)
	if cancelled > 0:
		EventBus.order_cancelled.emit(party_id, "travel_leg")

	var current_hex: Vector2i = _resolve_party_hex(party_id, map_data)
	var activity_type := _activity_type_for_action(action_type)

	# Build the path. Same-hex targets get an empty path (the activity fires in
	# place); pure Move Here on the same hex was already filtered out by the
	# context menu (Move Here is omitted when target == current hex).
	var path: Array[Vector2i] = []
	if target_hex != current_hex:
		path = controller.find_path(current_hex, target_hex)
		if path.is_empty():
			EventBus.notification_requested.emit({
				"type": "warning",
				"category": "exploration",
				"title": "No Route",
				"body": "There is no passable path to that hex.",
				"duration": 3.0,
			})
			return
		# Strip the start hex — schedule_travel_path expects a list of hexes
		# the party will *enter*, not the hex it's already on.
		if path.size() > 0 and path[0] == current_hex:
			var legs: Array[Vector2i] = []
			for i in range(1, path.size()):
				legs.append(path[i])
			path = legs

	var travel: Dictionary = _handlers.schedule_travel_path(
		path, scheduler, party_data, map_data)

	# For anything other than plain Move Here, queue the activity. Priority
	# slightly below PRIORITY_ARRIVAL so the arrival leg resolves first in
	# the same round (when there is one).
	if not activity_type.is_empty():
		var arrival_time: int = int(travel.get("arrival_time", 0))
		scheduler.schedule_at(
			arrival_time,
			WildernessHandlers.ACTIVITY_EVENT,
			party_id,
			{
				"activity_type": activity_type,
				"hex_q": target_hex.x,
				"hex_r": target_hex.y,
			},
			ScheduledEvent.PRIORITY_ARRIVAL + 1,
		)
		EventBus.order_queued.emit(party_id, WildernessHandlers.ACTIVITY_EVENT, arrival_time)

	var loop: SchedulerLoop = _runner.get_scheduler_loop()
	if loop != null and loop.is_paused():
		loop.resume(SchedulerLoop.SPEED_NORMAL)


func _close_context_menu() -> void:
	if _context_menu == null:
		return
	var parent: Node = _context_menu.get_parent()
	if is_instance_valid(parent):
		parent.queue_free()
	_context_menu = null


func _activity_type_for_action(action_type: String) -> String:
	match action_type:
		"wilderness_move_here":        return ""
		"wilderness_explore_hex":      return "explore"
		"wilderness_build_stronghold": return "build_stronghold"
		"wilderness_place_cache":      return "place_loot_cache"
		"wilderness_visit_cache":      return "visit_loot_cache"
		"wilderness_survey":           return "survey"
		_:                              return ""


## Returns the id of the party that should receive context-menu orders.
## Prefers GameState.active_party_id; falls back to the runner's tracked id.
func _resolve_active_party_id() -> String:
	var pid: String = GameState.active_party_id
	if pid.is_empty():
		pid = _runner.get_party_id() if _runner != null else ""
	return pid


## Returns PartyData for [param party_id]. Reuses the runner's cached object
## when the id matches, otherwise loads from the repository. Multi-party
## sessions need this because the runner only caches one party at a time.
func _resolve_party_data(party_id: String) -> PartyData:
	if _runner != null and _runner.get_party_id() == party_id:
		return _runner.get_party_data()
	return CampaignRepository.load_party_data(party_id)


## Returns the active party's current hex. For the runner-tracked primary
## party we trust the live HexMapData (which is what the renderer paints from);
## for non-primary parties we read the persisted current_hex_q/r from the DB.
func _resolve_party_hex(party_id: String, map_data: HexMapData) -> Vector2i:
	if _runner != null and _runner.get_party_id() == party_id and map_data != null:
		return map_data.party_hex
	var party := CampaignRepository.get_party(party_id)
	if party.is_empty():
		return Vector2i.ZERO
	var q: int = party.get("current_hex_q", 0) if party.get("current_hex_q") != null else 0
	var r: int = party.get("current_hex_r", 0) if party.get("current_hex_r") != null else 0
	return Vector2i(q, r)


## Opens the notebook to the Inventory tab so the player can trade with a
## wilderness loot cache. The Inventory tab auto-detects caches at the party's
## current hex via GameState.current_location_key.
func _on_wilderness_cache_visit_requested(_cache_id: String, _hex: Vector2i) -> void:
	EventBus.notebook_open_requested.emit("inventory")


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


func _on_settlement_entry(entrance: Dictionary, entry_poi_id: String) -> void:
	if _runner == null:
		return
	var loop: SchedulerLoop = _runner.get_scheduler_loop()
	if loop != null:
		loop.pause()
	_runner.transition_to_state("settlement", {
		"entrance": entrance,
		"entry_poi_id": entry_poi_id,
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


func get_location_key_for_character(character_id: String) -> String:
	# For multi-party: look up which party this character belongs to
	var char_party_id := CampaignRepository.get_party_for_character(character_id)
	if char_party_id.is_empty():
		return "unknown"
	var party := CampaignRepository.get_party(char_party_id)
	if party.is_empty():
		return "unknown"
	var q: int = party.get("current_hex_q", 0) if party.get("current_hex_q") != null else 0
	var r: int = party.get("current_hex_r", 0) if party.get("current_hex_r") != null else 0
	return "hex:%d,%d" % [q, r]


func _on_active_party_changed(_prev_id: String, _new_id: String) -> void:
	if _runner == null:
		return
	# Re-center the camera on the newly active party's hex
	var renderer: Node = _runner.get_hex_map_renderer()
	var party := CampaignRepository.get_party(_new_id)
	if not party.is_empty() and renderer != null:
		var q: int = party.get("current_hex_q", 0) if party.get("current_hex_q") != null else 0
		var r: int = party.get("current_hex_r", 0) if party.get("current_hex_r") != null else 0
		renderer.center_on_hex(Vector2i(q, r))
