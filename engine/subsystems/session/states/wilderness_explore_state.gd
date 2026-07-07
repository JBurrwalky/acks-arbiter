class_name WildernessExploreState
extends SessionState

## Wilderness exploration: hex map movement, encounter checks, time advance.
##
## On enter: shows hex map, registers wilderness event handlers with the
## scheduler, connects renderer signals.
## On hex click: schedules travel_leg events via WildernessHandlers.
## On dungeon/settlement entry: transition to dungeon/settlement state.

const ContextMenuScene := preload("res://scenes/maps/dungeon_context_menu.gd")
const EncounterDecisionScene := preload("res://scenes/ui/dialogs/encounter_decision_prompt.gd")
const AbandonVehicleScene := preload("res://scenes/ui/dialogs/abandon_vehicle_prompt.gd")
const HexInfoModalScene := preload("res://scenes/ui/dev/hex_info_modal.gd")
const ArmyMenuBuilder := preload("res://scenes/ui/troops/army_marching_context_menu.gd")
const ArmyDetailPanelScene := preload("res://scenes/ui/notebook/troops/army_detail_panel.gd")
const ArmySupplyGaugeScene := preload("res://scenes/ui/components/army_supply_gauge.gd")

var _runner = null  # stored reference to avoid closure issues
var _handlers: WildernessHandlers = null
var _context_menu = null  # instance of ContextMenuScene (shared with dungeon UI)
var _encounter_prompt: EncounterDecisionPrompt = null
var _pending_encounter: Dictionary = {}
var _pending_encounter_party: String = ""
# Bug 3: when travel is requested with an unhitched (immobile) vehicle, the
# AbandonVehiclePrompt asks leave-behind vs cancel. The travel params are stashed
# here until the player decides.
var _abandon_prompt = null
var _pending_travel: Dictionary = {}

# Army selection on the wilderness map (gdd-army-warfare.md §7.3). Left-click a
# player army token to select it (highlight + path overlay + supply gauge); then
# right-click a destination hex for its order menu. NPC armies open a read-only
# inspect panel and are never orderable.
var _selected_army_id: String = ""
var _army_gauge = null
var _army_inspect = null


func enter(runner, context: Dictionary) -> void:
	_runner = runner
	var renderer: Node = runner.get_hex_map_renderer()

	# Show hex map. The map lives inside the WorldViewport SubViewport frame —
	# show the whole frame, not just the renderer, so the wilderness surface is
	# visible above the status bar.
	renderer.visible = true
	renderer.process_mode = Node.PROCESS_MODE_INHERIT
	var world_viewport: Node = runner.get_world_viewport()
	if world_viewport != null:
		world_viewport.visible = true
	_show_hex_hud(renderer, true)

	# Connect renderer signals (safe: _connect checks for existing connections).
	# Left-clicks on party tokens select that party; right-clicks open the
	# context menu. Empty-hex left-clicks emit `hex_clicked` but we ignore them.
	_connect(renderer, "party_token_clicked", _on_party_token_clicked)
	_connect(renderer, "hex_context_menu_requested", _on_hex_context_menu_requested)
	_connect(renderer, "dungeon_entry_requested", _on_dungeon_entry)
	_connect(renderer, "settlement_entry_requested", _on_settlement_entry)
	# Army map layer (gdd-army-warfare.md §7.3): select on token click, deselect on
	# empty-hex click.
	if renderer.has_signal("army_token_clicked"):
		_connect(renderer, "army_token_clicked", _on_army_token_clicked)
	_connect(renderer, "hex_clicked", _on_hex_clicked)

	# Connect status bar action buttons
	if not EventBus.camp_requested.is_connected(_on_camp_requested):
		EventBus.camp_requested.connect(_on_camp_requested)

	# Listen for active party switches
	if not EventBus.active_party_changed.is_connected(_on_active_party_changed):
		EventBus.active_party_changed.connect(_on_active_party_changed)

	# Cache-visit dispatch: handler emits, we open the inventory overlay.
	if not EventBus.wilderness_cache_visit_requested.is_connected(_on_wilderness_cache_visit_requested):
		EventBus.wilderness_cache_visit_requested.connect(_on_wilderness_cache_visit_requested)

	# Encounter-decision modal — handler emits, we show the prompt.
	if not EventBus.encounter_decision_required.is_connected(_on_encounter_decision_required):
		EventBus.encounter_decision_required.connect(_on_encounter_decision_required)

	# Migration 119 cross-scale view-mode toggle. Swap the controller's
	# loaded map when the player toggles Strategic / Regional view, and
	# refresh the camera when the party crosses between maps.
	if not EventBus.map_view_mode_changed.is_connected(_on_map_view_mode_changed):
		EventBus.map_view_mode_changed.connect(_on_map_view_mode_changed)
	if not EventBus.party_map_changed.is_connected(_on_party_map_changed):
		EventBus.party_map_changed.connect(_on_party_map_changed)

	var all_parties := CampaignRepository.list_parties_for_campaign(GameState.campaign_id)

	# All wilderness handlers are globally registered by
	# SessionRunner.load_session (Option 2 — background-party resolution,
	# 2026-06-12): travel/activity chains keep resolving while the player is
	# in another context. The state borrows the runner's shared instance for
	# its scheduling helpers (schedule_travel_path, day/noon ticks, evasion).
	_handlers = runner.get_wilderness_handlers()

	# Ensure each registered party has a pending wilderness_day_tick. Idempotent
	# against the scheduler queue — schedule_day_tick no-ops when one is already
	# pending, so re-entering wilderness from combat/dungeon does not double-fire.
	# Phase 5 polish (2026-05-05): also schedule the noon tick (foraging).
	var scheduler: EventScheduler = runner.get_scheduler()
	for p in all_parties:
		_handlers.schedule_day_tick(scheduler, p.id)
		_handlers.schedule_noon_tick(scheduler, p.id)

	# Declare the wilderness context — 1x feels like watching the day advance.
	runner.get_scheduler_loop().set_context(SchedulerLoop.TimeContext.WILDERNESS)

	# Switch-first encounter flow (Option 1, 2026-06-12): if the focused party
	# acquired a deferred encounter while backgrounded, present it now that
	# the decision listener is connected. Fire-and-clear — once presented, the
	# stored copy is spent (the prompt forces a choice; if the player somehow
	# dismisses it, the encounter is gone, matching the pre-deferral fiction
	# of a broken-off contact).
	var focus_pid: String = runner.get_party_id()
	if not focus_pid.is_empty():
		var pending: String = CampaignRepository.get_party_pending_encounter(focus_pid)
		if not pending.is_empty():
			CampaignRepository.set_party_pending_encounter(focus_pid, "")
			var enc = str_to_var(pending)
			if enc is Dictionary and not (enc as Dictionary).is_empty():
				# call_deferred so enter() finishes first — the prompt parents
				# onto the renderer this frame is still wiring up.
				EventBus.encounter_decision_required.emit.call_deferred(focus_pid, enc)

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
	if renderer.has_signal("army_token_clicked"):
		_disconnect(renderer, "army_token_clicked", _on_army_token_clicked)
	_disconnect(renderer, "hex_clicked", _on_hex_clicked)

	# Disconnect status bar action buttons
	if EventBus.camp_requested.is_connected(_on_camp_requested):
		EventBus.camp_requested.disconnect(_on_camp_requested)
	if EventBus.active_party_changed.is_connected(_on_active_party_changed):
		EventBus.active_party_changed.disconnect(_on_active_party_changed)
	if EventBus.wilderness_cache_visit_requested.is_connected(_on_wilderness_cache_visit_requested):
		EventBus.wilderness_cache_visit_requested.disconnect(_on_wilderness_cache_visit_requested)
	if EventBus.encounter_decision_required.is_connected(_on_encounter_decision_required):
		EventBus.encounter_decision_required.disconnect(_on_encounter_decision_required)
	if EventBus.map_view_mode_changed.is_connected(_on_map_view_mode_changed):
		EventBus.map_view_mode_changed.disconnect(_on_map_view_mode_changed)
	if EventBus.party_map_changed.is_connected(_on_party_map_changed):
		EventBus.party_map_changed.disconnect(_on_party_map_changed)

	_close_context_menu()
	_close_encounter_prompt()
	_close_abandon_prompt()
	_clear_army_selection()

	# Handlers stay globally registered (SessionRunner owns the lifetime) —
	# background parties' travel/activity chains keep resolving after the
	# player leaves the wilderness context. Just drop our borrowed reference.
	_handlers = null

	# Hide hex map (only needed when transitioning to dungeon/settlement,
	# but safe to always do — re-shown on enter). Hide the WorldViewport frame
	# too: hiding only the renderer leaves the SubViewportContainer drawing an
	# opaque (cleared) rectangle that would cover 3D world content rendered
	# behind it — e.g. the dungeon map in SceneContainer.
	renderer.visible = false
	renderer.process_mode = Node.PROCESS_MODE_DISABLED
	var world_viewport: Node = runner.get_world_viewport()
	if world_viewport != null:
		world_viewport.visible = false
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

	# Army orders take precedence when a player army is selected — the right-clicked
	# hex is the march destination / current-hex action target (gdd §7.3).
	if not _selected_army_id.is_empty() and ArmyMapPresence.is_player_owned_id(_selected_army_id):
		_open_army_context_menu(_selected_army_id, coord, screen_pos)
		return

	var party_id: String = _resolve_active_party_id()
	if party_id.is_empty():
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

	# Army orders (gdd §7.3) dispatch through ArmyMarchingContextMenu.
	if action_type == "army_order":
		_dispatch_army_order(action_data)
		return

	# Get Hex Info (dev tool, Jedidiah 2026-06-23): a self-contained UI action — open a modal
	# dump of all stored data for the hex. No travel, works on any hex (impassable included),
	# so it returns BEFORE the passable-target / active-party resolution below.
	if action_type == "wilderness_get_hex_info":
		_show_hex_info(Vector2i(int(action_data.get("hex_q", 0)), int(action_data.get("hex_r", 0))))
		return

	# Enter Lair (gdd-lair-discovery.md §6.2). The dungeon-entry flow needs
	# the Lair Generator's tactical layout, which is a stubbed future
	# subsystem — surface the placeholder rather than a broken transition.
	if action_type == "wilderness_enter_lair":
		_on_enter_lair_requested(str(action_data.get("lair_id", "")))
		return

	# Climb Here (gdd-cliffs-canyons.md §5/§6). A deliberate cliff crossing — runs the
	# SHEER_SURFACE_CLIMB gate + per-climber throws and schedules the gate-bypassing
	# arrival itself, so it returns BEFORE the normal passable-target / pathfind flow
	# (find_path can't route across a cliff and would just report "No Route").
	if action_type == "wilderness_climb_cliff":
		_on_climb_cliff_requested(Vector2i(
			int(action_data.get("hex_q", 0)), int(action_data.get("hex_r", 0))))
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

	# Bug 3: a party can't drag an unhitched (immobile) vehicle along. If we're
	# actually moving (non-empty path) and any vehicle can't move, prompt the
	# player to leave it behind or cancel — don't silently travel without it.
	var unhitched: Array = VehicleAbandonmentService.unhitched_vehicles_for_party(party_id)
	if not path.is_empty() and not unhitched.is_empty():
		_pending_travel = {
			"path": path,
			"scheduler": scheduler,
			"party_data": party_data,
			"map_data": map_data,
			"activity_type": activity_type,
			"target_hex": target_hex,
			"party_id": party_id,
			"current_hex": current_hex,
			"unhitched": unhitched,
		}
		_show_abandon_prompt(unhitched)
		return

	_proceed_with_travel(path, scheduler, party_data, map_data, activity_type, target_hex, party_id)


## Schedules the travel legs + any trailing activity and resumes the clock.
## Split out of _on_context_action so the unhitched-vehicle prompt can defer it
## until the player decides (see _on_abandon_decided).
func _proceed_with_travel(path: Array, scheduler: EventScheduler, party_data: PartyData,
		map_data: HexMapData, activity_type: String, target_hex: Vector2i, party_id: String) -> void:
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

	# Focus-coupled clock (Option 1 ruling 2026-06-12): orders queue fine, but
	# the clock may not run on the hexmap while a party is in a dungeon — the
	# queued orders execute when the player returns to the dungeon layer.
	var loop: SchedulerLoop = _runner.get_scheduler_loop()
	if loop != null and loop.is_paused() \
			and _runner.get_clock_lock_reason().is_empty():
		loop.resume(SchedulerLoop.SPEED_NORMAL)


# ---------------------------------------------------------------------------
# Unhitched-vehicle prompt (Bug 3)
# ---------------------------------------------------------------------------

func _show_abandon_prompt(unhitched: Array) -> void:
	if _abandon_prompt != null and is_instance_valid(_abandon_prompt):
		_abandon_prompt.queue_free()
	_abandon_prompt = AbandonVehicleScene.new()
	_runner.get_hex_map_renderer().add_child(_abandon_prompt)
	_abandon_prompt.decided.connect(_on_abandon_decided, CONNECT_ONE_SHOT)
	var names: Array = []
	for v in unhitched:
		names.append(str(v.get("name", "Vehicle")))
	_abandon_prompt.open(names)


func _on_abandon_decided(choice: String) -> void:
	var pending: Dictionary = _pending_travel
	_pending_travel = {}
	if is_instance_valid(_abandon_prompt):
		_abandon_prompt.queue_free()
	_abandon_prompt = null
	if pending.is_empty():
		return
	# Cancel: abort the journey; vehicles stay with the party so the player can
	# hitch a team. The clock is left paused (same as never issuing the command).
	if choice == AbandonVehiclePrompt.CHOICE_CANCEL:
		return
	# Leave behind: park each immobile vehicle at the party's *current* hex
	# (where it is now, before the party departs), then commit the journey.
	var current_hex: Vector2i = pending.get("current_hex", Vector2i.ZERO)
	for v in pending.get("unhitched", []):
		VehicleAbandonmentService.abandon_to_hex(str(v.get("id", "")), current_hex)
	_proceed_with_travel(
		pending.get("path", []),
		pending.get("scheduler"),
		pending.get("party_data"),
		pending.get("map_data"),
		str(pending.get("activity_type", "")),
		pending.get("target_hex", Vector2i.ZERO),
		str(pending.get("party_id", "")))


func _close_abandon_prompt() -> void:
	if _abandon_prompt != null and is_instance_valid(_abandon_prompt):
		_abandon_prompt.queue_free()
	_abandon_prompt = null
	_pending_travel = {}


func _close_context_menu() -> void:
	if _context_menu == null:
		return
	var parent: Node = _context_menu.get_parent()
	if is_instance_valid(parent):
		parent.queue_free()
	_context_menu = null


# ---------------------------------------------------------------------------
# Army map layer (gdd-army-warfare.md §7.3)
# ---------------------------------------------------------------------------

## Left-click on an army token. Player-orderable armies are selected (highlight +
## path overlay + supply gauge); NPC armies open a read-only inspect panel.
func _on_army_token_clicked(army_id: String, _coord: Vector2i) -> void:
	if _runner == null or army_id.is_empty():
		return
	if ArmyMapPresence.is_player_owned_id(army_id):
		_select_army(army_id)
	else:
		_clear_army_selection()
		_open_army_inspect(army_id)


## Left-click on empty terrain clears any army selection.
func _on_hex_clicked(_coord: Vector2i) -> void:
	_clear_army_selection()


func _select_army(army_id: String) -> void:
	# Tear down any open NPC inspect panel when switching to an orderable army.
	_close_army_inspect()
	_selected_army_id = army_id
	var renderer: Node = _runner.get_hex_map_renderer()
	if renderer != null and renderer.has_method("set_selected_army"):
		renderer.set_selected_army(army_id)
	_refresh_army_path(army_id)
	_show_army_gauge(army_id)


func _clear_army_selection() -> void:
	_selected_army_id = ""
	if _runner != null:
		var renderer: Node = _runner.get_hex_map_renderer()
		if renderer != null:
			if renderer.has_method("set_selected_army"):
				renderer.set_selected_army("")
			if renderer.has_method("clear_army_path_overlay"):
				renderer.clear_army_path_overlay()
	_hide_army_gauge()
	_close_army_inspect()


## Draw the army's single pending travel leg as the dashed path overlay (armies
## pre-schedule one leg at a time — the overlay is a single segment).
func _refresh_army_path(army_id: String) -> void:
	var renderer: Node = _runner.get_hex_map_renderer()
	if renderer == null or not renderer.has_method("set_army_path_overlay"):
		return
	var scheduler: EventScheduler = _runner.get_scheduler()
	if scheduler != null:
		for ev in scheduler.get_events_for_owner(army_id):
			if ev.event_type == ArmyMarcher.EVENT_ARMY_TRAVEL_LEG:
				var from_hex := Vector2i(
					int(ev.data.get("from_hex_q", 0)), int(ev.data.get("from_hex_r", 0)))
				var to_hex := Vector2i(
					int(ev.data.get("to_hex_q", 0)), int(ev.data.get("to_hex_r", 0)))
				renderer.set_army_path_overlay(from_hex, to_hex)
				return
	if renderer.has_method("clear_army_path_overlay"):
		renderer.clear_army_path_overlay()


## Right-click order menu for the selected player army, targeting [param coord].
func _open_army_context_menu(army_id: String, coord: Vector2i, screen_pos: Vector2) -> void:
	var options: Array = ArmyMenuBuilder.build_menu_options(army_id, coord.x, coord.y)
	if options.is_empty():
		return
	_close_context_menu()
	_context_menu = ContextMenuScene.new()
	var layer := CanvasLayer.new()
	layer.layer = 24
	layer.add_child(_context_menu)
	_runner.get_hex_map_renderer().add_child(layer)
	_context_menu.option_selected.connect(_on_context_action)
	_context_menu.cancelled.connect(_close_context_menu)
	_context_menu.show_at(screen_pos, options, _runner.get_scheduler_loop())


## Dispatch an army context-menu order via ArmyMarchingContextMenu.
func _dispatch_army_order(action_data: Dictionary) -> void:
	if _runner == null:
		return
	var army_id := str(action_data.get("army_id", ""))
	var army_action := str(action_data.get("army_action", ""))
	if army_id.is_empty() or army_action.is_empty():
		return
	var scheduler: EventScheduler = _runner.get_scheduler()
	# Phase B: encamped requisition/loot orders launch via the session's ExtractionScheduler.
	var extraction_scheduler = _runner.get_extraction_scheduler() \
		if _runner.has_method("get_extraction_scheduler") else null
	var result: Dictionary = ArmyMenuBuilder.execute_action(
		army_action, army_id,
		int(action_data.get("hex_q", 0)), int(action_data.get("hex_r", 0)),
		Timekeeping.get_total_rounds(), scheduler, extraction_scheduler)
	if not bool(result.get("success", false)):
		var err := str(result.get("error", ""))
		if err != "" and err != "phase_b_pending" and err != "unknown_action":
			EventBus.notification_requested.emit({
				"type": "warning", "category": "armies",
				"title": "Order Failed",
				"body": "Could not issue that order (%s)." % err,
				"duration": 3.0,
			})
		return
	# Reflect the new state at once + resume so the leg (or disband) resolves.
	var renderer: Node = _runner.get_hex_map_renderer()
	if army_action == ArmyMenuBuilder.ACTION_DISBAND:
		_clear_army_selection()
	else:
		if renderer != null and renderer.has_method("refresh_armies"):
			renderer.refresh_armies()
		_refresh_army_path(army_id)
		_show_army_gauge(army_id)
	var loop: SchedulerLoop = _runner.get_scheduler_loop()
	if loop != null and loop.is_paused() and _runner.get_clock_lock_reason().is_empty():
		loop.resume(SchedulerLoop.SPEED_NORMAL)


func _show_army_gauge(army_id: String) -> void:
	_hide_army_gauge()
	_army_gauge = ArmySupplyGaugeScene.new()
	var layer := CanvasLayer.new()
	layer.layer = 12   # above HexHUD (10), below the context menu (24)
	layer.add_child(_army_gauge)
	_runner.get_hex_map_renderer().add_child(layer)
	if _army_gauge.has_method("set_army"):
		_army_gauge.set_army(army_id)


func _hide_army_gauge() -> void:
	if _army_gauge == null:
		return
	var parent: Node = _army_gauge.get_parent()
	if is_instance_valid(parent):
		parent.queue_free()
	_army_gauge = null


## Open the army detail panel in read-only (inspect) mode for an NPC army, centered
## over the map. Parented to the renderer; queue_free()s on close.
func _open_army_inspect(army_id: String) -> void:
	_close_army_inspect()
	if _runner == null:
		return
	var army: Dictionary = ArmyRepository.get_army(army_id)
	var layer := CanvasLayer.new()
	layer.layer = 26
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var panel := PanelContainer.new()
	UiSurfaceStyles.apply_textured_panel(panel)
	panel.custom_minimum_size = Vector2(360, 0)
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	panel.add_child(vbox)
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = String(army.get("name", "Army"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "✕"
	close.pressed.connect(_close_army_inspect)
	header.add_child(close)
	vbox.add_child(header)
	var detail := ArmyDetailPanelScene.new()
	vbox.add_child(detail)
	_runner.get_hex_map_renderer().add_child(layer)   # tree entry -> panels' _ready runs
	detail.display(army_id, true)
	_army_inspect = layer


func _close_army_inspect() -> void:
	if _army_inspect == null:
		return
	if is_instance_valid(_army_inspect):
		_army_inspect.queue_free()
	_army_inspect = null


## Dev tool (Jedidiah 2026-06-23): open the Get Hex Info modal for [param hex] — a scrollable
## dump of every stored datum (terrain/ownership/realm/population/culture/settlement/dungeon/
## POI/stronghold/lairs/setting/history/occupants). News up a fresh modal parented to the
## viewport root (above the play map, survives state/HUD teardown); it queue_free()s on close.
func _show_hex_info(hex: Vector2i) -> void:
	if _runner == null:
		return
	var controller: HexMapController = _runner.get_hex_map_controller()
	var map_data: HexMapData = controller.get_map() if controller != null else null
	var map_id: String = map_data.id if map_data != null else ""
	var campaign_id: String = GameState.campaign_id if typeof(GameState) != TYPE_NIL else ""
	if map_id.is_empty() or campaign_id.is_empty():
		return
	var sections: Array = HexInfoAssembler.assemble(campaign_id, map_id, hex.x, hex.y)
	var modal := HexInfoModalScene.new()
	modal.setup("Hex Info — (%d, %d)" % [hex.x, hex.y], sections)
	(Engine.get_main_loop() as SceneTree).root.add_child(modal)


func _activity_type_for_action(action_type: String) -> String:
	match action_type:
		"wilderness_move_here":        return ""
		"wilderness_explore_hex":      return "explore"
		"wilderness_build_stronghold": return "build_stronghold"
		"wilderness_place_cache":      return "place_loot_cache"
		"wilderness_visit_cache":      return "visit_loot_cache"
		"wilderness_survey":           return "survey"
		"wilderness_hunt":             return "hunt"
		"wilderness_search_lair":      return "search_lair"
		_:                              return ""


## Enter {Type} Lair (gdd-lair-discovery.md §6.2). TODO(lair-generator-gdd):
## once the Lair Generator subsystem produces a tactical layout from
## lairs.lair_layout_seed, route through the existing dungeon-entry flow
## (transition_to_state("dungeon", {entrance, spawn_cell}) — see
## _on_dungeon_entry). Until then the button surfaces and explains itself.
func _on_enter_lair_requested(lair_id: String) -> void:
	var row: Dictionary = CampaignRepository.get_lair(lair_id)
	if row.is_empty():
		return
	var type_label: String = String(row.get("monster_group", "")).capitalize()
	EventBus.notification_requested.emit({
		"type": "info",
		"category": "exploration",
		"title": "%s Lair" % type_label,
		"body": "Lair interiors arrive with the Lair Generator — entering is not yet implemented.",
		"duration": 4.0,
	})


# ---------------------------------------------------------------------------
# Cliff climbing (SHEER_SURFACE_CLIMB — gdd-cliffs-canyons.md §5/§6)
# ---------------------------------------------------------------------------

## Handle a deliberate "Climb Here" order onto an across-a-cliff neighbour. Runs the
## ClimbResolver gate (Mountaineering + per-climber gear; refuse if mercenaries present),
## blocks with a shortfall toast when short, otherwise resolves each climber's throws,
## applies + persists any fall damage, and schedules the gate-bypassing crossing at ¼
## movement speed. The climb math/gate is the pure ClimbResolver; this is the wiring.
func _on_climb_cliff_requested(target_hex: Vector2i) -> void:
	var controller: HexMapController = _runner.get_hex_map_controller()
	if controller == null:
		return
	var map_data: HexMapData = controller.get_map()
	if map_data == null:
		return
	var party_id: String = _resolve_active_party_id()
	if party_id.is_empty():
		return
	var party_data: PartyData = _resolve_party_data(party_id)
	if party_data == null:
		return
	var current_hex: Vector2i = _resolve_party_hex(party_id, map_data)
	var cliff: HexCliffEdgeData = controller.cliff_edge_between(current_hex, target_hex)
	if cliff == null or not controller.is_hex_passable(target_hex):
		return

	var climbers: Array = _load_climbers(party_id)
	var pooled_gear: Dictionary = _pooled_climb_gear(party_id, climbers)
	var gate: Dictionary = ClimbResolver.evaluate_gate(
		climbers, pooled_gear, cliff.height_ft, _party_has_mercenaries(party_id))
	if not bool(gate.get("allowed", false)):
		_notify_climb_blocked(gate)
		return

	# Gate satisfied → resolve each climber's ascent and apply + persist any falls.
	var falls: Array = _resolve_and_apply_falls(climbers, cliff.height_ft)

	# The climb supersedes any in-flight travel/activity (mirrors Move Here).
	var scheduler: EventScheduler = _runner.get_scheduler()
	var cancelled: int = scheduler.cancel_all_for_owner(party_id, "travel_leg")
	cancelled += scheduler.cancel_all_for_owner(party_id, WildernessHandlers.ACTIVITY_EVENT)
	cancelled += scheduler.cancel_all_for_owner(party_id, WildernessHandlers.ACTIVITY_COMPLETE_EVENT)
	if cancelled > 0:
		EventBus.order_cancelled.emit(party_id, "travel_leg")

	# Climb time = ¼ normal movement (acore_core_classes.xml:1450) → 4× a normal hex
	# crossing. Schedule a single is_climb travel_leg; _handle_travel_leg crosses it with
	# the gate-bypassing climb_party_across, and path_index 0 of 1 auto-pauses on arrival.
	var terrain: HexTerrainData = map_data.get_hex(target_hex)
	var terrain_cat: String = terrain.movement_cost_category() if terrain != null else "clear"
	var base_rounds: int = TravelSpeedCalculator.hex_crossing_rounds(party_data, terrain_cat, false, null)
	var arrival_time: int = Timekeeping.get_total_rounds() + maxi(1, base_rounds * 4)
	scheduler.schedule_at(
		arrival_time, "travel_leg", party_id,
		{
			"hex_q": target_hex.x, "hex_r": target_hex.y, "is_climb": true,
			"path_index": 0, "path_total": 1, "terrain_category": terrain_cat,
		},
		ScheduledEvent.PRIORITY_ARRIVAL)
	EventBus.order_queued.emit(party_id, "travel_leg", arrival_time)
	_notify_climb_started(cliff, falls)

	# Resume the clock so the climb leg fires (mirrors _proceed_with_travel).
	var loop: SchedulerLoop = _runner.get_scheduler_loop()
	if loop != null and loop.is_paused() and _runner.get_clock_lock_reason().is_empty():
		loop.resume(SchedulerLoop.SPEED_NORMAL)


## Every climber = each PC + henchman in the travelling party (list_party_characters spans
## both), loaded as a damageable CharacterData with proficiencies hydrated — has_proficiency
## reads c.proficiencies, which the bare character-row load does NOT populate.
func _load_climbers(party_id: String) -> Array:
	var out: Array = []
	for row in CampaignRepository.list_party_characters(party_id):
		var c := CharacterData.from_dict(row)
		c.proficiencies = CampaignRepository.get_character_proficiencies(c.id)
		out.append(c)
	return out


## Pooled climbing gear (individual units) across every climber's inventory + the shared
## party pool, bucketed to ClimbResolver's GEAR_* keys. iron_spikes_12 is a bundle of 12, so
## its quantity is multiplied; a mallet drives wooden stakes only and does NOT count as a
## spike-driving hammer (base_equipment.json:100).
func _pooled_climb_gear(party_id: String, climbers: Array) -> Dictionary:
	var rope := 0
	var spikes := 0
	var hammer := 0
	var grapple := 0
	var rows: Array = []
	for c in climbers:
		rows.append_array(CampaignRepository.get_inventory_items(c.id))
	rows.append_array(CampaignRepository.get_party_inventory(party_id))
	for it in rows:
		var key := str(it.get("item_key", ""))
		var qty := int(it.get("quantity", 1))
		match key:
			"rope_50ft": rope += qty
			"iron_spikes_12": spikes += qty * 12
			"hammer_small", "warhammer": hammer += qty
			"grappling_hook": grapple += qty
	return {
		ClimbResolver.GEAR_ROPE: rope,
		ClimbResolver.GEAR_SPIKES: spikes,
		ClimbResolver.GEAR_HAMMER: hammer,
		ClimbResolver.GEAR_GRAPPLE: grapple,
	}


## Mercenaries are troop units with no party-travel association yet (gdd-cliffs-canyons.md
## §2a; recon 2026-06-26), so they can't travel as individual climbers — always false for
## now. When war-band travel lands, detect mercenary troop units on the party here.
func _party_has_mercenaries(_party_id: String) -> bool:
	return false


## Resolve each climber's ascent; for any who fall, apply + persist the fall damage and emit
## the same damage/hp signals the sustenance system uses. Returns per-faller summaries.
func _resolve_and_apply_falls(climbers: Array, height_ft: int) -> Array:
	var summaries: Array = []
	for c in climbers:
		var res: Dictionary = ClimbResolver.resolve_climb(c, height_ft)
		if not bool(res.get("fell", false)):
			continue
		var dmg: int = int(res.get("damage", 0))
		var before: int = c.hp_current
		var outcome: Dictionary = c.apply_damage(dmg, "physical")
		CampaignRepository.update_character_hp(c.id, c.hp_current)
		EventBus.damage_dealt.emit(c.id, dmg, "fall", "")
		EventBus.hp_changed.emit(c.id, before, c.hp_current)
		summaries.append({
			"name": c.name, "damage": dmg, "fall_ft": int(res.get("fall_ft", 0)),
			"downed": bool(outcome.get("is_downed", c.hp_current <= 0)),
		})
	return summaries


func _notify_climb_blocked(gate: Dictionary) -> void:
	var body := ""
	match str(gate.get("reason", "")):
		ClimbResolver.REASON_MERCENARIES:
			body = "The party's mercenaries can't make this climb. Send them around, or travel without them."
		ClimbResolver.REASON_NO_MOUNTAINEERING:
			body = "No one has the Mountaineering proficiency — this cliff can't be climbed. Route around it."
		ClimbResolver.REASON_INSUFFICIENT_GEAR:
			body = ClimbResolver.shortfall_message(gate.get("shortfall", {}))
		_:
			body = "The cliff can't be climbed right now."
	EventBus.notification_requested.emit({
		"type": "warning", "category": "exploration",
		"title": "Cannot Climb", "body": body, "duration": 5.0,
	})


func _notify_climb_started(cliff: HexCliffEdgeData, falls: Array) -> void:
	var kind := "canyon wall" if cliff.cliff_type == HexCliffEdgeData.CANYON else "cliff"
	var body := "The party scales the %d-ft %s." % [cliff.height_ft, kind]
	if not falls.is_empty():
		var parts: Array[String] = []
		for f in falls:
			var tag := " (down!)" if bool(f.get("downed", false)) else ""
			parts.append("%s fell %d ft for %d damage%s" % [
				str(f.get("name", "A climber")), int(f.get("fall_ft", 0)),
				int(f.get("damage", 0)), tag])
		body += " " + "; ".join(parts) + "."
	EventBus.notification_requested.emit({
		"type": "warning" if not falls.is_empty() else "info",
		"category": "exploration", "title": "Climbing",
		"body": body, "duration": 6.0,
	})


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
	# Focus-coupled clock (Option 1 ruling 2026-06-12): camping needs the
	# clock to run (watches resolve at MAX speed), which is forbidden while a
	# party is in a dungeon. Block camp entry rather than hanging at pause.
	var lock_reason: String = _runner.get_clock_lock_reason()
	if not lock_reason.is_empty():
		EventBus.notification_requested.emit({
			"type": "warning",
			"category": "system",
			"title": "Cannot Camp Now",
			"body": lock_reason,
		})
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


# ---------------------------------------------------------------------------
# Migration 119 — cross-scale view-mode + party-map-change handlers
# ---------------------------------------------------------------------------

## Swap the loaded map when the view mode changes. Camera-only — the party's
## logical map (parties.current_map_id) is unchanged. STRATEGIC walks up the
## parent_map_id chain to the topmost ancestor and renders that; REGIONAL
## renders the party's actual current map.
func _on_map_view_mode_changed(_from_mode: int, to_mode: int) -> void:
	if _runner == null:
		return
	var controller: HexMapController = _runner.get_hex_map_controller()
	if controller == null:
		return
	var target_map_id := _resolve_target_map_id_for_view(to_mode)
	if target_map_id.is_empty():
		return
	var current_map: HexMapData = controller.get_map()
	if current_map != null and current_map.id == target_map_id:
		return  # already showing the right map
	var loaded: HexMapData = CampaignRepository.load_hex_map(target_map_id)
	if loaded == null:
		push_warning("WildernessExploreState: load_hex_map returned null for %s" % target_map_id)
		return
	# Set party_hex on the loaded map to the active party's position projected
	# onto this map (live DB read), so camera-centering + enter-button logic
	# resolves correctly. The renderer's _resolve_party_render_position
	# handles per-token placement on top of this.
	_apply_party_hex_to_loaded_map(loaded)
	controller.load_map(loaded)


## Persists the hex map's mutable state (fog-of-war, survey progress) on save.
## gdd-savegame-system.md §5.3 — this replaces the old wilderness-only block in
## SessionRunner.save_session(). Party hex position is written incrementally by
## WildernessHandlers on each travel leg, so it is not re-saved here.
func flush_to_db(runner) -> void:
	var controller: HexMapController = runner.get_hex_map_controller()
	if controller == null:
		return
	var map_data: HexMapData = controller.get_map()
	if map_data != null:
		CampaignRepository.save_hex_map(map_data, GameState.campaign_id)


## Set [param loaded].party_hex to the active party's actual coordinate on
## that map (if directly on it), or to the parent_anchor of the party's
## child map (if [param loaded] is the parent / ancestor of the party's
## actual map). Falls through to the map's existing party_hex on no match.
func _apply_party_hex_to_loaded_map(loaded: HexMapData) -> void:
	var party_id := GameState.active_party_id
	if party_id.is_empty():
		party_id = GameState.party_id
	if party_id.is_empty():
		return
	var party := CampaignRepository.get_party(party_id)
	if party.is_empty():
		return
	var party_map_id := String(party.get("current_map_id", ""))
	if party_map_id == loaded.id:
		var q: int = int(party.get("current_hex_q", 0)) if party.get("current_hex_q") != null else 0
		var r: int = int(party.get("current_hex_r", 0)) if party.get("current_hex_r") != null else 0
		loaded.party_hex = Vector2i(q, r)
		return
	# Party is on a child map of `loaded` — walk up looking for an ancestor
	# match and use that child's parent_anchor (or first footprint hex).
	var safety := 8
	var current_child := party_map_id
	while safety > 0 and not current_child.is_empty():
		var parent_id := CampaignRepository.get_hex_map_parent_id(current_child)
		if parent_id.is_empty():
			break
		if parent_id == loaded.id:
			var footprint: Array = CampaignRepository.get_hex_map_parent_footprint(current_child)
			if footprint.size() > 0:
				loaded.party_hex = footprint[0]
			return
		current_child = parent_id
		safety -= 1


## Refresh the loaded map when the party crosses between hex maps. Honors
## the current view mode: if the player is in STRATEGIC view, we may not
## need to swap (still showing the ancestor); if REGIONAL, we always swap
## to the party's new map.
func _on_party_map_changed(party_id: String, _from_map: String, to_map: String) -> void:
	if _runner == null or to_map.is_empty():
		return
	# Only react when the active/primary party changes maps. Background-party
	# transitions don't move the player's camera.
	if party_id != GameState.party_id and party_id != GameState.active_party_id:
		return
	var controller: HexMapController = _runner.get_hex_map_controller()
	if controller == null:
		return
	var target_map_id := _resolve_target_map_id_for_view(int(GameState.map_view_mode))
	if target_map_id.is_empty():
		target_map_id = to_map
	var current_map: HexMapData = controller.get_map()
	if current_map != null and current_map.id == target_map_id:
		# Still the right map; the renderer's party-token rebuild will
		# reposition the token without a full reload.
		return
	var loaded: HexMapData = CampaignRepository.load_hex_map(target_map_id)
	if loaded != null:
		_apply_party_hex_to_loaded_map(loaded)
		controller.load_map(loaded)


## Returns the map_id that should be displayed for the given view mode,
## based on the active party's current_map_id and its parent chain.
func _resolve_target_map_id_for_view(view_mode: int) -> String:
	var party_id := GameState.active_party_id
	if party_id.is_empty():
		party_id = GameState.party_id
	if party_id.is_empty():
		return ""
	var party := CampaignRepository.get_party(party_id)
	if party.is_empty():
		return ""
	var party_map_id := String(party.get("current_map_id", ""))
	if party_map_id.is_empty():
		return ""
	if view_mode == GameState.MapViewMode.REGIONAL:
		return party_map_id
	# STRATEGIC: walk up the parent chain.
	var current := party_map_id
	var safety := 8
	while safety > 0:
		var parent := CampaignRepository.get_hex_map_parent_id(current)
		if parent.is_empty():
			break
		current = parent
		safety -= 1
	return current


# ---------------------------------------------------------------------------
# Encounter decision modal (Phase 5 polish, 2026-05-05)
# ---------------------------------------------------------------------------

## Wilderness handler emits `encounter_decision_required` after rolling an
## encounter; we show the modal and route the player's choice. The handler
## already paused the scheduler with `auto_pause`, so the world clock is
## halted while the player decides.
func _on_encounter_decision_required(party_id: String, encounter_data: Dictionary) -> void:
	if _runner == null:
		return
	# Only the active party's encounters surface a modal — background-party
	# encounters in multi-party play default to "continue" so they don't
	# interrupt the player's UI. (Future polish: queue decisions per party.)
	if party_id != GameState.active_party_id:
		EventBus.encounter_avoided.emit(party_id, encounter_data)
		_resume_scheduler()
		return

	_pending_encounter = encounter_data
	_pending_encounter_party = party_id

	_close_encounter_prompt()
	_encounter_prompt = EncounterDecisionScene.new()
	# The prompt's CanvasLayer (180) sits above the hex map; add it under the
	# renderer so its lifetime is tied to the wilderness scene tree.
	_runner.get_hex_map_renderer().add_child(_encounter_prompt)
	_encounter_prompt.decided.connect(_on_encounter_decided, CONNECT_ONE_SHOT)
	_encounter_prompt.open(encounter_data)


func _on_encounter_decided(choice: String) -> void:
	var party_id: String = _pending_encounter_party
	var enc: Dictionary = _pending_encounter.duplicate()
	_pending_encounter = {}
	_pending_encounter_party = ""

	EventBus.encounter_decision_made.emit(party_id, enc, choice)
	_close_encounter_prompt()

	if _runner == null:
		return

	match choice:
		EncounterDecisionPrompt.CHOICE_FIGHT, EncounterDecisionPrompt.CHOICE_ENGAGE:
			_runner.transition_to_state("combat", {
				"encounter_data": enc,
				"return_state": "wilderness",
			})
		EncounterDecisionPrompt.CHOICE_PARLEY:
			_runner.transition_to_state("encounter", {
				"encounter_data": enc,
				"return_state": "wilderness",
			})
		EncounterDecisionPrompt.CHOICE_EVADE:
			if _handlers != null:
				_handlers.attempt_evasion(party_id, enc)
			# Resume the scheduler so travel can continue (or so the daily
			# pursuit catch-up event can fire on schedule).
			_resume_scheduler()
		EncounterDecisionPrompt.CHOICE_CONTINUE:
			EventBus.encounter_avoided.emit(party_id, enc)
			EventBus.notification_requested.emit({
				"type": "info",
				"category": "exploration",
				"title": "Travel Resumed",
				"body": "You let them pass.",
				"duration": 2.5,
			})
			_resume_scheduler()
		_:
			# Unknown choice — fail safe to "continue" so the player isn't
			# stuck with the scheduler paused.
			_resume_scheduler()


func _close_encounter_prompt() -> void:
	if _encounter_prompt != null:
		_encounter_prompt.queue_free()
		_encounter_prompt = null


func _resume_scheduler() -> void:
	if _runner == null:
		return
	# Focus-coupled clock: no hexmap-side resume while a party is below.
	if not _runner.get_clock_lock_reason().is_empty():
		return
	var loop: SchedulerLoop = _runner.get_scheduler_loop()
	if loop != null and loop.is_paused():
		loop.resume()
