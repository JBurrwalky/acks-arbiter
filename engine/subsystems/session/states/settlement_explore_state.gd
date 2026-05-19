class_name SettlementExploreState
extends SessionState

## Settlement exploration: pure menu-overlay PoI navigation with auto-pause.
##
## V2 (2026-05-02 — gdd-settlement-exploration-ui.md v2). The hex map remains
## visible behind the menu overlay. The scheduler auto-pauses while the menu
## is open. PoI selection schedules travel and resumes the scheduler; arrival
## auto-pauses again and surfaces the activity panel for the destination PoI.
##
## On enter: instantiate SettlementContext (the slim controller), mount the
##   settlement menu + activity panel as peer CanvasLayers, register handlers,
##   pause the scheduler, listen for party-token-click reopens.
## On menu PoI click: schedule travel via SettlementHandlers, close menu,
##   resume scheduler.
## On arrival: SettlementContext updates current PoI; activity panel surfaces.
## On menu close (Esc / X button): hide menu, scheduler stays paused.
## On exit: tear down everything.

var _runner = null
var _controller: SettlementMapController = null  # SettlementContext (preserved class name)
var _handlers: SettlementHandlers = null
var _settlement_hud: CanvasLayer = null
var _menu: SettlementMenu = null
var _activity_panel: SettlementActivityPanel = null
var _settlement_id: String = ""
var _campaign_id: String = ""


func enter(runner, context: Dictionary) -> void:
	_runner = runner
	_campaign_id = GameState.campaign_id
	var entrance: Dictionary = context.get("entrance", {})
	var entry_poi_id: String = context.get("entry_poi_id", "")

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

	# Create the SettlementContext (still typed as SettlementMapController for
	# class-name stability — see settlement_map_controller.gd header).
	_controller = SettlementMapController.new()
	_controller.name = "SettlementMapController"
	runner.add_child(_controller)
	_controller.load_settlement(settlement_dict, entry_poi_id)
	_settlement_id = _controller.get_settlement_id()

	# Register settlement event handlers with the scheduler.
	_handlers = SettlementHandlers.new(runner)
	_handlers.register(runner.get_handler_registry())

	# Mount the menu + activity panel.
	_create_settlement_hud()

	# Auto-pause the scheduler while in the settlement.
	var loop: SchedulerLoop = runner.get_scheduler_loop()
	if loop != null and not loop.is_paused():
		loop.pause()

	# Set settlement time scale for when activities/travel resume the clock.
	if loop != null:
		loop.set_timescale(SchedulerLoop.TIMESCALE_SETTLEMENT)

	# Listen for left-clicks on our party token (reopens the menu after a
	# travel commit closes it). The hex map remains visible and clickable.
	var renderer: Node = runner.get_hex_map_renderer()
	if renderer != null:
		_connect(renderer, "party_token_clicked", _on_party_token_clicked)

	# Refresh the menu on active-party switches (per gdd-ui-architecture.md §3.5).
	if not EventBus.active_party_changed.is_connected(_on_active_party_changed):
		EventBus.active_party_changed.connect(_on_active_party_changed)

	# Listen for scheduler events to update the UI (arrival, encounter checks).
	if not EventBus.scheduler_event_resolved.is_connected(_on_scheduler_event_resolved):
		EventBus.scheduler_event_resolved.connect(_on_scheduler_event_resolved)

	# Check party time lock (returning from combat/dungeon in settlement).
	runner.check_party_time_lock()

	# Phase 10B.2 Wave 2: signal entry to VisitStateManager for the trade
	# block's per-visit state (entry toll first-fire bookkeeping + Wave 4
	# shipping-offer roll). Picks the first active PC as the active character;
	# the mercantile_panel exposes a selector to swap mid-visit if desired.
	_notify_visit_state_entered()


func exit(runner) -> void:
	# Phase 10B.2 Wave 2: signal departure to VisitStateManager — debits
	# stabling + moorage, clears Wave 4's per-visit shipping offers, DELETEs
	# the visit row. Fires party_departed_settlement.
	_notify_visit_state_departed()

	if EventBus.scheduler_event_resolved.is_connected(_on_scheduler_event_resolved):
		EventBus.scheduler_event_resolved.disconnect(_on_scheduler_event_resolved)
	if EventBus.active_party_changed.is_connected(_on_active_party_changed):
		EventBus.active_party_changed.disconnect(_on_active_party_changed)

	var renderer: Node = runner.get_hex_map_renderer()
	if renderer != null:
		_disconnect(renderer, "party_token_clicked", _on_party_token_clicked)

	if _handlers != null:
		var party_id: String = runner.get_party_id()
		_handlers.cancel_travel(runner.get_scheduler(), party_id)
		runner.get_scheduler().cancel_all_for_owner(party_id, "settlement_activity")
		_handlers.unregister(runner.get_handler_registry())
		_handlers = null

	var loop: SchedulerLoop = runner.get_scheduler_loop()
	if loop != null and not loop.is_paused():
		loop.pause()

	if _settlement_hud != null and is_instance_valid(_settlement_hud):
		_settlement_hud.queue_free()
	_settlement_hud = null
	_menu = null
	_activity_panel = null

	if is_instance_valid(_controller):
		_controller.queue_free()
	_controller = null
	_runner = null


func handle_action(runner, action: String, payload: Dictionary) -> String:
	match action:
		"exit_settlement":
			return "wilderness"
		"end_session":
			return "session_end"
	return ""


# ---------------------------------------------------------------------------
# HUD construction
# ---------------------------------------------------------------------------

func _create_settlement_hud() -> void:
	_settlement_hud = CanvasLayer.new()
	_settlement_hud.name = "SettlementHUD"
	_settlement_hud.layer = 10
	_runner.add_child(_settlement_hud)

	# Menu (right-side overlay).
	_menu = preload("res://scenes/ui/settlement/settlement_menu.tscn").instantiate()
	_settlement_hud.add_child(_menu)
	_menu.setup(_controller.get_map(), _controller.get_current_poi_id())
	_menu.poi_clicked.connect(_on_poi_clicked)
	_menu.close_requested.connect(_on_menu_close_requested)

	# Activity panel (sibling overlay; surfaces independently on PoI selection
	# at current location, or on travel arrival auto-pause).
	_activity_panel = SettlementActivityPanel.new()
	_activity_panel.visible = false
	_activity_panel.anchor_left = 0.6
	_activity_panel.anchor_right = 1.0
	_activity_panel.anchor_top = 0.0
	_activity_panel.anchor_bottom = 1.0
	_settlement_hud.add_child(_activity_panel)
	_activity_panel.exit_settlement_requested.connect(_on_exit_requested)
	_activity_panel.shop_requested.connect(_on_shop_requested)
	_activity_panel.hiring_requested.connect(_on_hiring_requested)
	_activity_panel.activity_requested.connect(_on_activity_requested)
	# Phase 10B.2 Wave 2: route mercantile activity launchers to mercantile_panel.
	_activity_panel.mercantile_requested.connect(_on_mercantile_requested)


# ---------------------------------------------------------------------------
# Menu signal handlers
# ---------------------------------------------------------------------------

func _on_poi_clicked(poi: Dictionary) -> void:
	if _runner == null or _controller == null or _handlers == null:
		return

	var party_id: String = _runner.get_party_id()

	if _runner.is_party_locked(party_id):
		EventBus.notification_requested.emit({
			"type": "warning",
			"category": "system",
			"title": "Party Locked",
			"body": "This party is committed to an activity.",
		})
		return

	var poi_id: String = poi.get("id", "")
	if poi_id.is_empty():
		return

	# Already at this PoI — show its activity panel; menu stays open so the
	# player can pick another destination.
	if poi_id == _controller.get_current_poi_id():
		if _activity_panel != null:
			_activity_panel.show_for_poi(poi)
		return

	# Cancel any pending travel.
	_handlers.cancel_travel(_runner.get_scheduler(), party_id)

	# Schedule travel.
	var result := _handlers.schedule_travel(
		_controller.get_map(),
		_controller.get_current_poi_id(),
		poi_id,
		_runner.get_scheduler(),
		party_id,
		_campaign_id,
		_settlement_id,
		_is_nighttime(),
	)

	if result.is_empty():
		EventBus.notification_requested.emit({
			"type": "warning",
			"category": "system",
			"title": "Cannot Travel",
			"body": "Unable to schedule travel to that location.",
		})
		return

	# Hide menu and activity panel; resume the scheduler so travel ticks down.
	if _menu != null:
		_menu.visible = false
	if _activity_panel != null:
		_activity_panel.visible = false
	var loop: SchedulerLoop = _runner.get_scheduler_loop()
	if loop != null and loop.is_paused():
		loop.resume(SchedulerLoop.SPEED_NORMAL)


func _on_menu_close_requested() -> void:
	if _menu != null:
		_menu.visible = false
	# Scheduler stays paused — player resumes via speed controls.


func _on_party_token_clicked(party_id: String, _coord: Vector2i) -> void:
	# Only react if the click matches our party.
	if _runner == null or party_id != _runner.get_party_id():
		return
	if _menu == null:
		return

	# Refresh menu state to current PoI in case travel completed since last
	# open, then show.
	_menu.update_current_poi(_controller.get_current_poi_id())
	_menu.visible = true

	var loop: SchedulerLoop = _runner.get_scheduler_loop()
	if loop != null and not loop.is_paused():
		loop.pause()


func _on_active_party_changed(_previous_party_id: String, _new_party_id: String) -> void:
	# If the new active party is not in this settlement, hide the menu.
	# Multi-party-in-settlement is rare; future work: rebind to that party's
	# SettlementContext. For now, just hide.
	if _runner == null:
		return
	if _menu != null:
		_menu.visible = false
	if _activity_panel != null:
		_activity_panel.visible = false


# ---------------------------------------------------------------------------
# Activity panel signal handlers
# ---------------------------------------------------------------------------

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

	if _activity_panel != null:
		_activity_panel.visible = false
	_settlement_hud.add_child(panel)
	panel.closed.connect(func():
		panel.queue_free()
		if _activity_panel != null and not _controller.get_current_poi().is_empty():
			_activity_panel.show_for_poi(_controller.get_current_poi())
	)


func _on_hiring_requested(poi: Dictionary) -> void:
	if _runner == null or _controller == null:
		return

	var party_data = _runner.get_party_data()
	if party_data == null:
		return

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

	var rep_system := ReputationSystem.new(CampaignRepository, _campaign_id, party_id)
	var char_gen := CharacterGenerator.new(
		_runner.get_class_registry(), PowerRegistry.new(), ProficiencyRegistry.new())
	var lifecycle := HenchmanLifecycleManager.new(CampaignRepository, rep_system, char_gen)

	var date: Dictionary = Timekeeping.get_date()
	var month: int = date.get("month", 1)
	var year: int = date.get("year", 1)
	var day: int = date.get("day", 1)
	var current_week: int = clampi((day - 1) / 7 + 1, 1, 4)

	var pool_id: String = lifecycle.ensure_pool(
		_settlement_id, market_class, _campaign_id, month, year)
	var search_cost: int = lifecycle.get_search_cost(pool_id)

	var panel := HiringPanel.new()
	panel.setup(lifecycle, pool_id, _settlement_id, market_class,
		search_cost, current_week, employer_id, cha_mod, party_id)

	if _activity_panel != null:
		_activity_panel.visible = false
	_settlement_hud.add_child(panel)
	panel.closed.connect(func():
		panel.queue_free()
		if _activity_panel != null and not _controller.get_current_poi().is_empty():
			_activity_panel.show_for_poi(_controller.get_current_poi())
	)
	panel.hire_completed.connect(func(_character_id: String):
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
	# Schedule major activities; minor activities resolve immediately.
	var duration_turns: int
	match activity_type:
		"gather_info":
			duration_turns = 24  # ~4 hours
		"carouse":
			duration_turns = 144  # ~1 day
		"rest_long":
			duration_turns = 48  # ~8 hours
		_:
			duration_turns = 1

	if duration_turns > 1:
		_handlers.schedule_activity(
			activity_type, poi, duration_turns,
			_runner.get_scheduler(), _runner.get_party_id())
		# Hide panels and resume the scheduler for the activity to tick.
		if _menu != null:
			_menu.visible = false
		if _activity_panel != null:
			_activity_panel.visible = false
		var loop: SchedulerLoop = _runner.get_scheduler_loop()
		if loop != null and loop.is_paused():
			loop.resume(SchedulerLoop.SPEED_NORMAL)
	else:
		EventBus.notification_requested.emit({
			"type": "info",
			"category": "settlement",
			"title": activity_type.capitalize(),
			"body": "Activity completed at %s." % poi.get("name", "location"),
		})


func _on_exit_requested() -> void:
	if _runner == null:
		return
	# Only allow exit when at an entry/exit PoI.
	if _controller != null and _controller.is_at_entry_exit():
		var loop: SchedulerLoop = _runner.get_scheduler_loop()
		if loop != null and not loop.is_paused():
			loop.pause()
		_runner.transition_to_state("wilderness")
	else:
		EventBus.notification_requested.emit({
			"type": "warning",
			"category": "system",
			"title": "Not at Exit Point",
			"body": "Travel to an entry/exit PoI to leave the settlement.",
		})


# ---------------------------------------------------------------------------
# Scheduler event listener
# ---------------------------------------------------------------------------

func _on_scheduler_event_resolved(_event_type: String, _event_data: Dictionary) -> void:
	if _runner == null:
		return
	var loop: SchedulerLoop = _runner.get_scheduler_loop()
	if loop == null:
		return
	for result in loop.last_tick_results:
		var presentation: Dictionary = result.get("presentation", {})
		var ptype: String = presentation.get("type", "")
		match ptype:
			"city_travel_arrival":
				_on_arrival(presentation)


func _on_arrival(data: Dictionary) -> void:
	if _controller == null:
		return
	var dest_poi: Dictionary = data.get("poi", {})
	var poi_id: String = dest_poi.get("id", "")
	if not poi_id.is_empty():
		_controller.set_current_poi(poi_id)

	# Surface the activity panel for the arrived-at PoI. Menu does NOT auto-
	# reopen — player explicitly reopens via party-token click.
	if _activity_panel != null and not dest_poi.is_empty():
		_activity_panel.show_for_poi(dest_poi)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _is_nighttime() -> bool:
	if _runner == null:
		return false
	var party_id: String = _runner.get_party_id()
	var elapsed: int = Timekeeping.get_party_time(party_id)
	var time_of_day: int = elapsed % Timekeeping.ROUNDS_PER_DAY
	# Approximation: night = 18:00 to 06:00 (3/4 to 1/4 of the day).
	var dusk_rounds: int = Timekeeping.ROUNDS_PER_DAY * 3 / 4
	var dawn_rounds: int = Timekeeping.ROUNDS_PER_DAY / 4
	return time_of_day >= dusk_rounds or time_of_day < dawn_rounds


func _connect(obj: Node, sig_name: String, method: Callable) -> void:
	if obj == null:
		return
	if not obj.is_connected(sig_name, method):
		obj.connect(sig_name, method)


func _disconnect(obj: Node, sig_name: String, method: Callable) -> void:
	if obj == null:
		return
	if obj.is_connected(sig_name, method):
		obj.disconnect(sig_name, method)


func get_location_key_for_character(_character_id: String) -> String:
	if _settlement_id.is_empty():
		return "unknown"
	return "settlement:%s" % _settlement_id


# ---------------------------------------------------------------------------
# Phase 10B.2 Wave 2 — mercantile routing + visit-state hooks
# ---------------------------------------------------------------------------

func _on_mercantile_requested(activity_id: String, _poi: Dictionary) -> void:
	if _runner == null or _settlement_id.is_empty():
		return
	var party_id: String = _runner.get_party_id()
	var character_id: String = _first_active_character_id()
	if character_id.is_empty():
		EventBus.notification_requested.emit({
			"type": "warning",
			"category": "settlement",
			"title": "No Active Character",
			"body": "The party has no active character to transact for.",
		})
		return

	var picker = preload("res://scenes/ui/settlement/mercantile_panel.gd").new()
	_settlement_hud.add_child(picker)
	picker.setup(activity_id, _settlement_id, party_id, character_id)
	picker.launch_requested.connect(_on_mercantile_launch_requested)
	picker.cancelled.connect(func() -> void:
		# Restore the activity panel on cancel — same UX as shop/hiring close.
		if _activity_panel != null and _controller != null \
				and not _controller.get_current_poi().is_empty():
			_activity_panel.show_for_poi(_controller.get_current_poi()))

	# Hide the activity panel while the picker is in front (mirrors shop/hire).
	if _activity_panel != null:
		_activity_panel.visible = false


func _on_mercantile_launch_requested(
		activity_def_id: String, params: Dictionary,
		location_kind: String, location_ref: String) -> void:
	if _runner == null:
		return
	var executor: ActivityTimeCostExecutor = _runner.get_activity_executor()
	if executor == null:
		EventBus.notification_requested.emit({
			"type": "warning",
			"category": "settlement",
			"title": "Activity Executor Unavailable",
			"body": "Cannot launch %s — executor not initialized." % activity_def_id,
		})
		return
	var scheduler: EventScheduler = _runner.get_scheduler()
	var party_id: String = _runner.get_party_id()
	var character_id: String = _first_active_character_id()

	# Phase 10B.2 Wave 3: solicit_merchants uses a launch-side prepare hook
	# (the ActivityHandlerRegistry has no on_started). prepare_launch runs
	# MerchantPoolRepository.process_solicitation immediately + stamps
	# started_at_calendar_day into params for forfeit-rollback attribution.
	if activity_def_id == "solicit_merchants":
		var prep: Dictionary = SolicitMerchantsHandler.prepare_launch(
			party_id, location_ref, character_id)
		if not bool(prep.get("success", false)):
			EventBus.notification_requested.emit({
				"type": "warning",
				"category": "settlement",
				"title": "Cannot Solicit",
				"body": "Solicit failed: %s" % String(prep.get("error", "?")),
			})
			if _activity_panel != null and _controller != null \
					and not _controller.get_current_poi().is_empty():
				_activity_panel.show_for_poi(_controller.get_current_poi())
			return
		# Merge prepare_launch's params into the picker's params (picker passes
		# {} since solicit's picker has no fields).
		var prep_params: Dictionary = prep.get("params", {})
		for key in prep_params:
			params[key] = prep_params[key]

	var result: Dictionary = executor.launch(
		character_id, activity_def_id, location_kind, location_ref,
		params, scheduler, party_id)
	if not bool(result.get("success", false)):
		EventBus.notification_requested.emit({
			"type": "warning",
			"category": "settlement",
			"title": "Activity Launch Failed",
			"body": "Could not launch %s: %s" % [activity_def_id, String(result.get("error", "?"))],
		})
	# Restore the activity panel after the launch.
	if _activity_panel != null and _controller != null \
			and not _controller.get_current_poi().is_empty():
		_activity_panel.show_for_poi(_controller.get_current_poi())


func _notify_visit_state_entered() -> void:
	if _runner == null or _settlement_id.is_empty():
		return
	var party_id: String = _runner.get_party_id()
	var character_id: String = _first_active_character_id()
	if party_id.is_empty():
		return
	VisitStateManager.on_party_entered_settlement(
		party_id, _settlement_id, character_id, Timekeeping.get_total_days())


func _notify_visit_state_departed() -> void:
	if _runner == null or _settlement_id.is_empty():
		return
	var party_id: String = _runner.get_party_id()
	if party_id.is_empty():
		return
	VisitStateManager.on_party_departed_settlement(
		party_id, _settlement_id, Timekeeping.get_total_days())


func _first_active_character_id() -> String:
	if _runner == null:
		return ""
	var party_data = _runner.get_party_data()
	if party_data == null:
		return ""
	for cd in party_data.character_data:
		if cd != null and not cd.is_dead and cd.is_active:
			return cd.id
	return ""
