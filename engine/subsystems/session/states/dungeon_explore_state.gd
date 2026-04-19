class_name DungeonExploreState
extends SessionState

## Dungeon exploration: real-time-with-pause movement on the diamond grid.
##
## Units move continuously as the game clock ticks at round granularity.
## The player pauses to issue movement and action orders, then unpauses
## to watch them play out. The scheduler auto-pauses on interesting events
## (encounters, activity completion, light expiry, arrival at destination).
##
## Combat transitions to turn-based on the same map grid. All other
## dungeon activity (movement, searching, listening) is real-time.
##
## The dungeon operates on the party clock independently from the overworld.
## On dungeon exit, the party may be time-locked until the world catches up.

const DungeonSessionState := preload("res://engine/subsystems/exploration/dungeon_session_state.gd")
const ContextMenuBuilder := preload("res://engine/subsystems/exploration/dungeon_context_menu_builder.gd")
const ContextMenuScene := preload("res://scenes/maps/dungeon_context_menu.gd")
const UnitInfoPanelScene := preload("res://scenes/maps/dungeon_unit_info_panel.gd")
const ControlGroupBarScene := preload("res://scenes/maps/dungeon_control_group_bar.gd")
const NotificationLogScene := preload("res://scenes/maps/dungeon_notification_log.gd")
const MinimapScene := preload("res://scenes/maps/dungeon_minimap.gd")
const LootGenerator := preload("res://engine/subsystems/combat/loot_generator.gd")
const LootModalScript := preload("res://scenes/ui/party_inventory/loot_distribution_modal.gd")

var _runner = null
var _controller: DungeonMapController = null
var _scene: Node = null
var _combat_overlay: DungeonCombatOverlay = null
var _dungeon_combat_controller: CombatController = null
var _in_combat: bool = false
var _finalizer := CombatFinalizer.new()
var _spawner := DungeonEncounterSpawner.new()
var _handlers: DungeonHandlers = null

## Per-dungeon-visit in-memory state (control groups, idle behaviors, etc.).
var _session_state: RefCounted = null  # DungeonSessionState

## Active context menu popup (if any).
var _context_menu: PanelContainer = null

## Loot distribution modal for dungeon cache looting.
var _loot_modal = null  # LootDistributionModal (lazy-created)

## UI panels.
var _unit_info_panel: PanelContainer = null
var _control_group_bar: PanelContainer = null
var _notification_log: PanelContainer = null
var _minimap: PanelContainer = null


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

	# Create session state for this dungeon visit.
	_session_state = DungeonSessionState.new()

	# Create controller
	_controller = DungeonMapController.new()
	_controller.name = "DungeonMapController"
	runner.add_child(_controller)

	# Wire party data for formation placement
	var party_data: PartyData = runner.get_party_data()
	if party_data != null:
		_controller.set_party_data(party_data)

	# Wire session state for spike/wedge checks on door toggle.
	_controller.set_session_state(_session_state)

	# Add all active living party members
	var active_chars: Array = []
	if party_data != null:
		for cd: CharacterData in party_data.character_data:
			if not cd.is_dead and cd.is_active:
				_controller.add_party_member(cd.id)
				active_chars.append(cd)
	if _controller.get_entity_ids().is_empty():
		_controller.add_party_member("party_leader")

	# Apply a formation preset so members spread across cells at entry
	# instead of all stacking on the same cell.
	if party_data != null and active_chars.size() > 1:
		var fm: RefCounted = _controller.get_formation_manager()
		if fm != null:
			fm.apply_preset("column", party_data, active_chars)

	_controller.load_dungeon(dungeon_dict, spawn_cell)

	# Save party dungeon position
	CampaignRepository.update_party_dungeon_position(
		runner.get_party_id(),
		_controller.get_dungeon_id(),
		_controller.get_current_level(),
		spawn_cell.x, spawn_cell.y
	)

	# Instantiate and wire dungeon scene
	var packed: PackedScene = preload("res://scenes/maps/dungeon_map_3d.tscn")
	_scene = packed.instantiate()
	_scene.setup(_controller)

	# Wire scene signals (context menu replaces old selection panel + door interact).
	_scene.exit_requested.connect(_on_exit_requested)
	_scene.cell_clicked.connect(_on_cell_clicked)
	_scene.entity_selected.connect(_on_entity_selected)
	_scene.selection_cleared.connect(_on_selection_cleared)
	_scene.context_menu_requested.connect(_on_context_menu_requested)
	_scene.control_group_assign_requested.connect(_on_control_group_assign)
	_scene.control_group_recall_requested.connect(_on_control_group_recall)
	_scene.control_group_select_requested.connect(_on_control_group_select_entity)
	_scene.minimap_toggle_requested.connect(_on_minimap_toggle)
	# Renderer-driven movement animation callbacks.
	_scene.movement_cell_reached.connect(_on_movement_cell_reached)
	_scene.movement_path_complete.connect(_on_movement_path_complete)

	runner.get_nav_stack().push_node(
		_scene, "dungeon_%s" % entrance.get("id", "unknown")
	)

	# Create tokens
	if party_data != null:
		for cd: CharacterData in party_data.character_data:
			if not cd.is_dead and cd.is_active:
				var class_letter := _class_letter(cd.character_class)
				_scene.add_entity_token(cd.id, cd.name, 0, class_letter,
					cd.character_class, cd.token_variant)
	elif _controller.get_entity_ids().size() > 0:
		_scene.add_entity_token("party_leader", "Party", 0, "?")

	# Create UI panels and add them to the HUD.
	_create_ui_panels()

	# Register dungeon event handlers with the scheduler.
	_handlers = DungeonHandlers.new(runner)
	_handlers.set_session_state(_session_state)
	_handlers.register(runner.get_handler_registry())

	# Set dungeon time scale — round-level granularity.
	runner.get_scheduler_loop().set_timescale(SchedulerLoop.TIMESCALE_DUNGEON)

	# Set dungeon light manager on the controller for per-entity fog.
	_controller.set_light_manager(_handlers.get_light_manager())

	# Listen for scheduler events to detect dungeon encounters.
	if not EventBus.scheduler_event_resolved.is_connected(_on_scheduler_event_resolved):
		EventBus.scheduler_event_resolved.connect(_on_scheduler_event_resolved)

	# Auto-activate light sources from inventory.
	_auto_activate_lights(runner)

	# Seed recurring dungeon events (wandering monster checks, light ticks).
	_handlers.seed_dungeon_events(runner.get_scheduler(), runner.get_party_id())

	# Scheduler starts paused — player issues orders, then unpauses.


func exit(runner) -> void:
	runner.get_nav_stack().pop()

	# Revert picked locks before saving (locks reset on dungeon exit).
	if _session_state != null and _controller != null and _controller.get_map() != null:
		var tmap: TacticalMapData = _controller.get_map()
		for pos in _session_state.get_picked_locks():
			if tmap.get_door_state(pos) in ["closed", "open"]:
				tmap.set_door_state(pos, "locked")
				tmap.set_cell_field(pos, "door_type", "locked")

	# Save dungeon cell states (door + fog) for all loaded levels.
	_save_dungeon_cell_states()

	# Disconnect scheduler event listener.
	if EventBus.scheduler_event_resolved.is_connected(_on_scheduler_event_resolved):
		EventBus.scheduler_event_resolved.disconnect(_on_scheduler_event_resolved)

	# Cancel movement animations before tearing down.
	if _scene != null:
		_scene.cancel_all_movement_animations()

	# Unregister dungeon event handlers and cancel dungeon events.
	if _handlers != null:
		_handlers.cancel_all_moves()
		_handlers.unregister(runner.get_handler_registry())
		var party_id: String = runner.get_party_id()
		runner.get_scheduler().cancel_all_for_owner(party_id, "dungeon_movement_tick")
		runner.get_scheduler().cancel_all_for_owner(party_id, "dungeon_encounter_check")
		runner.get_scheduler().cancel_all_for_owner(party_id, "dungeon_light_tick")
		runner.get_scheduler().cancel_all_for_owner(party_id, "dungeon_action_complete")
		_handlers = null

	# Pause scheduler when leaving dungeon.
	var loop: SchedulerLoop = runner.get_scheduler_loop()
	if loop != null and not loop.is_paused():
		loop.pause()

	# Clean up context menu if open.
	if _context_menu != null and is_instance_valid(_context_menu):
		_context_menu.queue_free()
		_context_menu = null

	if is_instance_valid(_controller):
		_controller.queue_free()
	_controller = null
	_scene = null
	_runner = null
	_session_state = null

	CampaignRepository.clear_party_dungeon_position(runner.get_party_id())

	# Check party time lock (dungeon may have advanced party clock ahead).
	runner.check_party_time_lock()


func handle_action(runner, action: String, payload: Dictionary) -> String:
	match action:
		"exit_dungeon":
			pass  # Now handled as per-character scheduled action via context menu.
		"cancel_movement":
			_cancel_all_movement(runner)
		"cancel_action":
			_cancel_pending_actions(runner)
		"set_movement_mode":
			_change_movement_mode(runner, payload)
		"light_source":
			_light_source(runner, payload)
		"douse_source":
			_douse_source(runner, payload)
		"end_session":
			return "session_end"
	return ""


## Cancel all real-time movement orders. Entities stop at their current cells.
func _cancel_all_movement(runner) -> void:
	if _handlers != null:
		_handlers.cancel_all_moves()
	if _scene != null:
		_scene.cancel_all_movement_animations()
	var party_id: String = runner.get_party_id()
	runner.get_scheduler().cancel_all_for_owner(party_id, "dungeon_movement_tick")
	EventBus.order_cancelled.emit(party_id, "dungeon_move")
	var loop: SchedulerLoop = runner.get_scheduler_loop()
	if loop != null and not loop.is_paused():
		loop.pause()


## Persist dungeon cell states (door_state + fog) for all loaded levels.
func _save_dungeon_cell_states() -> void:
	if _controller == null:
		return
	var dungeon_id: String = _controller.get_dungeon_id()
	if dungeon_id.is_empty():
		return
	for level_num in _controller._all_levels:
		var tmap: TacticalMapData = _controller._all_levels[level_num]
		var cells_to_save: Array = []
		for pos in tmap._cells:
			var cell: Dictionary = tmap._cells[pos]
			var tf: String = cell.get("terrain_feature", "open")
			var ds: String = cell.get("door_state", "")
			var fog_int: int = tmap.fog.get(pos, TacticalMapData.FogState.HIDDEN)
			var fog_str: String = "hidden"
			match fog_int:
				TacticalMapData.FogState.EXPLORED:
					fog_str = "explored"
				TacticalMapData.FogState.VISIBLE:
					fog_str = "explored"  # visible reverts to explored on save
			# Only save cells that have meaningful state (doors or explored fog).
			if tf in ["door", "door_locked", "door_secret", "portcullis"] or fog_int != TacticalMapData.FogState.HIDDEN:
				cells_to_save.append({
					"col": pos.x,
					"row": pos.y,
					"door_state": ds,
					"fog_state": fog_str,
				})
		if not cells_to_save.is_empty():
			CampaignRepository.save_dungeon_cell_states(dungeon_id, level_num, cells_to_save)


## Cancel any pending timed actions (search, listen, etc.).
## Time already elapsed is consumed — no partial progress per ACKS.
func _cancel_pending_actions(runner) -> void:
	var party_id: String = runner.get_party_id()
	var cancelled: int = runner.get_scheduler().cancel_all_for_owner(party_id, "dungeon_action_complete")
	if cancelled > 0:
		EventBus.order_cancelled.emit(party_id, "dungeon_action_complete")


## Change the dungeon movement mode and recalculate any active movement.
## payload keys: "mode" — "exploration", "combat", or "running"
func _change_movement_mode(runner, payload: Dictionary) -> void:
	if _handlers == null:
		return
	var mode_name: String = payload.get("mode", "exploration")
	var mode_value: float = DungeonHandlers.MODE_EXPLORATION
	match mode_name:
		"combat":
			mode_value = DungeonHandlers.MODE_COMBAT
		"running":
			mode_value = DungeonHandlers.MODE_RUNNING
		_:
			mode_value = DungeonHandlers.MODE_EXPLORATION
	_handlers.set_movement_mode(mode_value)


## Light a torch or lantern for a character. Scheduled as a 1-round action
## (lighting with tinderbox takes a full round per ACKS).
## payload keys: "character_id", "source_type" ("torch" or "lantern")
func _light_source(runner, payload: Dictionary) -> void:
	if _handlers == null:
		return
	var character_id: String = payload.get("character_id", "")
	var source_type: String = payload.get("source_type", "torch")
	var scheduler: EventScheduler = runner.get_scheduler()
	var party_id: String = runner.get_party_id()
	scheduler.schedule_at(
		Timekeeping.get_party_time(party_id) + 1,
		"dungeon_light_action",
		party_id,
		{
			"action": "light_%s" % source_type,
			"character_id": character_id,
		},
		ScheduledEvent.PRIORITY_ARRIVAL,
	)
	_start_clock_if_paused()


## Douse a character's light source (instant — no round cost).
func _douse_source(runner, payload: Dictionary) -> void:
	if _handlers == null:
		return
	var character_id: String = payload.get("character_id", "")
	_handlers.douse_light(character_id)
	if _controller != null:
		_controller._update_fog_for_all_members()


## Scan party inventory on dungeon entry and auto-activate any light sources
## that are already equipped in hand slots with uses_remaining > 0.
func _auto_activate_lights(runner) -> void:
	if _handlers == null:
		return
	var party_data: PartyData = runner.get_party_data()
	if party_data == null:
		return

	var any_lit := false
	for cd: CharacterData in party_data.character_data:
		if cd.is_dead or not cd.is_active:
			continue
		var inventory: Array = CampaignRepository.get_inventory_items(cd.id)
		for item in inventory:
			if int(item.get("is_equipped", 0)) != 1:
				continue
			var slot: String = item.get("slot", "")
			if slot != "hands_main" and slot != "hands_off":
				continue
			var item_key: String = item.get("item_key", "")
			var uses: int = int(item.get("uses_remaining", -1))
			if item_key == DungeonLightManager.TORCH_KEY and uses > 0:
				_handlers.get_light_manager()._activate(cd.id, "torch", item.get("id", ""), uses)
				any_lit = true
			elif item_key == DungeonLightManager.LANTERN_KEY and uses > 0:
				_handlers.get_light_manager()._activate(cd.id, "lantern", item.get("id", ""), uses)
				any_lit = true

	# If nobody has an active light source, try to auto-light for the first character
	# that has a torch/lantern + tinderbox.
	if not any_lit:
		for cd: CharacterData in party_data.character_data:
			if cd.is_dead or not cd.is_active:
				continue
			var result: Dictionary = _handlers.light_torch(cd.id)
			if result.get("success", false):
				any_lit = true
				break
			result = _handlers.light_lantern(cd.id)
			if result.get("success", false):
				any_lit = true
				break

	if not any_lit:
		EventBus.notification_requested.emit({
			"type": "danger",
			"category": "light",
			"title": "No light source!",
			"body": "The party has no torch, lantern, or tinderbox. Equip a light source.",
			"duration": 0.0,
		})


## Returns darkvision cells for a character. ACKS 1e does NOT give dwarves,
## elves, or halflings darkvision by default (unlike D&D). Darkvision is
## reserved for monsters and certain spells. Returns 0 for all PCs unless
## a spell or magic item grants it (future: check active effects).
static func _get_darkvision_cells(_cd: CharacterData) -> int:
	# TODO: check active spell effects for darkvision/infravision grants.
	return 0


# ---------------------------------------------------------------------------
# Context menu system
# ---------------------------------------------------------------------------

func _on_context_menu_requested(cell_pos: Vector2i, screen_pos: Vector2) -> void:
	if _in_combat or _runner == null or _controller == null or _scene == null:
		return

	# Close any existing context menu.
	_close_context_menu()

	var selected: Array[String] = _scene.get_selected_entity_ids()
	if selected.is_empty():
		# No selection — select all party members for context actions.
		var all_ids: Array[String] = []
		for eid in _controller.get_entity_ids():
			all_ids.append(eid)
		selected = all_ids

	var map: TacticalMapData = _controller.get_map()
	var party_data: PartyData = _runner.get_party_data()
	var light_mgr = _handlers.get_light_manager() if _handlers != null else null

	var options: Array[Dictionary] = ContextMenuBuilder.build_menu(
		selected, cell_pos, map, party_data, _session_state, light_mgr
	)

	if options.is_empty():
		return

	# Create and show the context menu popup.
	_context_menu = ContextMenuScene.new()
	var ctx_layer = _scene.get_node_or_null("DungeonHUD/ContextMenuLayer")
	if ctx_layer != null:
		ctx_layer.add_child(_context_menu)
	else:
		_scene.add_child(_context_menu)

	_context_menu.option_selected.connect(_on_context_action)
	_context_menu.cancelled.connect(_on_context_cancelled)

	var loop: SchedulerLoop = _runner.get_scheduler_loop()
	_context_menu.show_at(screen_pos, options, loop)


func _on_context_action(action_data: Dictionary) -> void:
	if _runner == null or _controller == null:
		return

	var action_type: String = action_data.get("action_type", "")
	var cell: Vector2i = action_data.get("cell", Vector2i(-1, -1))
	var character_id: String = action_data.get("character_id", "")
	var target_id: String = action_data.get("target_id", "")

	var selected: Array[String] = _scene.get_selected_entity_ids() if _scene != null else []
	if selected.is_empty():
		for eid in _controller.get_entity_ids():
			selected.append(eid)

	var scheduler: EventScheduler = _runner.get_scheduler()
	var party_id: String = _runner.get_party_id()
	var party_data: PartyData = _runner.get_party_data()

	match action_type:
		# --- Universal ---
		"move_here":
			_issue_move_orders(selected, cell, party_data, scheduler, party_id)
		"search_here":
			# Move to cell, then search (1 turn = 60 rounds).
			for eid in selected:
				_handlers.schedule_action("search", eid, cell, DungeonHandlers.TURN_ROUNDS, scheduler, party_id)
			_start_clock_if_paused()
		"listen_here":
			# Move to cell, then listen (1 round).
			for eid in selected:
				_handlers.schedule_action("listen", eid, cell, 1, scheduler, party_id)
			_start_clock_if_paused()

		# --- Door interactions (compound: move to door + interact) ---
		"open_door", "close_door":
			var any_door_ordered := false
			for eid in selected:
				var base_mv: int = 120
				if party_data != null:
					var cd: CharacterData = party_data.get_member(eid)
					if cd != null:
						base_mv = cd.get_effective_movement()
				if _handlers.order_move_and_interact_door(eid, cell, base_mv, _controller, scheduler, party_id):
					any_door_ordered = true
					# Start continuous animation for the walk-to-door path.
					if _scene != null and _handlers != null:
						var cpr: float = _handlers.cells_per_round(base_mv)
						var order: Dictionary = _handlers._movement_orders.get(eid, {})
						var path: Array = order.get("path", [])
						if not path.is_empty():
							_scene.start_movement_animation(eid, path, cpr)
							_handlers.mark_renderer_animated(eid)
			if any_door_ordered:
				_start_clock_if_paused()
		"force_door":
			for eid in selected:
				_handlers.schedule_action("force_door", eid, cell, 1, scheduler, party_id)
			_start_clock_if_paused()
		"pick_lock":
			for eid in selected:
				_handlers.schedule_action("pick_lock", eid, cell, DungeonHandlers.TURN_ROUNDS, scheduler, party_id)
			_start_clock_if_paused()
		"bash_door":
			var bash_turns: int = action_data.get("turns", 3)
			for eid in selected:
				_handlers.schedule_action("bash_door", eid, cell, bash_turns * DungeonHandlers.TURN_ROUNDS, scheduler, party_id)
			_start_clock_if_paused()
		"spike_shut", "wedge_open", "listen_at_door", "remove_spike", "remove_wedge":
			var action_name: String = action_type
			for eid in selected:
				_handlers.schedule_action(action_name, eid, cell, 1, scheduler, party_id)
			_start_clock_if_paused()
		"force_portcullis":
			for eid in selected:
				_handlers.schedule_action("force_portcullis", eid, cell, 1, scheduler, party_id)
			_start_clock_if_paused()

		# --- Stairs ---
		"ascend", "descend":
			_controller.use_stairs(cell)
		"exit_dungeon":
			# Queue all selected characters to exit the dungeon.
			var map: TacticalMapData = _controller.get_map()
			var any_queued := false
			for eid in selected:
				if _session_state != null and (_session_state.is_exited(eid) or _session_state.is_queued_for_exit(eid)):
					continue
				if map != null and map.get_entity_pos(eid) == cell:
					# Already on the exit cell — schedule the 1-round action now.
					_handlers.schedule_action("exit_dungeon", eid, cell, 1, scheduler, party_id)
					any_queued = true
				else:
					# Not on the exit cell — add to exit queue; they'll advance
					# toward the exit automatically as space opens up.
					if _session_state != null:
						_session_state.queue_for_exit(eid, cell)
						any_queued = true
			if any_queued:
				_start_clock_if_paused()

		# --- Light source ---
		"light_torch":
			_light_source(_runner, {"character_id": character_id, "source_type": "torch"})
		"light_lantern":
			_light_source(_runner, {"character_id": character_id, "source_type": "lantern"})
		"extinguish_light":
			_douse_source(_runner, {"character_id": character_id})

		# --- Entity interactions ---
		"trade":
			EventBus.notification_requested.emit({
				"type": "info", "category": "ui",
				"title": "Trade", "body": "Trade system not yet implemented.",
				"duration": 3.0,
			})
		"attack":
			EventBus.notification_requested.emit({
				"type": "warning", "category": "combat",
				"title": "Attack", "body": "Combat initiation via context menu — handled in combat pass.",
				"duration": 3.0,
			})
		"add_to_group":
			if not selected.is_empty() and not target_id.is_empty():
				var group_num: int = _session_state.get_entity_group(selected[0]) if _session_state != null else 0
				if group_num == 0:
					# Find first available group number.
					for i in range(1, 10):
						if _session_state.get_group(i).is_empty():
							group_num = i
							break
				if group_num > 0 and _session_state != null:
					var members: Array[String] = _session_state.get_group(group_num)
					if target_id not in members:
						members.append(target_id)
					_session_state.assign_group(group_num, members)

		"use_lever":
			for eid in selected:
				_handlers.schedule_action("use_lever", eid, cell, 1, scheduler, party_id)
			_start_clock_if_paused()
		"drop_portcullis":
			for eid in selected:
				_handlers.schedule_action("drop_portcullis", eid, cell, 1, scheduler, party_id)
			_start_clock_if_paused()

		# --- Loot actions ---
		"loot":
			if not selected.is_empty():
				var eid: String = selected[0]
				# TODO (voxel migration): extend location_key to include level coordinate
				# per gdd-voxel-tactical-architecture-v1.1.md §6.3 — currently 2D (col,row);
				# becomes 3D (col,row,level) when the voxel schema lands.
				var current_time: int = Timekeeping.get_party_time(party_id)
				scheduler.schedule_at(
					current_time + DungeonHandlers.TURN_ROUNDS,
					"dungeon_action_complete", party_id,
					{"action_type": "loot", "entity_id": eid,
					 "cell_x": cell.x, "cell_y": cell.y,
					 "dungeon_id": _controller.get_dungeon_id()},
					ScheduledEvent.PRIORITY_ARRIVAL)
				_start_clock_if_paused()
		"pick_up_all":
			if not selected.is_empty():
				var eid: String = selected[0]
				# TODO (voxel migration): extend location_key to include level coordinate
				# per gdd-voxel-tactical-architecture-v1.1.md §6.3 — currently 2D (col,row);
				# becomes 3D (col,row,level) when the voxel schema lands.
				var current_time: int = Timekeeping.get_party_time(party_id)
				scheduler.schedule_at(
					current_time + DungeonHandlers.TURN_ROUNDS,
					"dungeon_action_complete", party_id,
					{"action_type": "pick_up_all", "entity_id": eid,
					 "cell_x": cell.x, "cell_y": cell.y,
					 "dungeon_id": _controller.get_dungeon_id()},
					ScheduledEvent.PRIORITY_ARRIVAL)
				_start_clock_if_paused()

		# --- Deferred / placeholder ---
		"talk", "heal", "heal_self", "cast_spell", "cast_spell_self", \
		"use_item", "drop_item", "hide", "check_status", "carry", \
		"disarm_trap", "trigger_trap", "examine", \
		"pick_pockets", "unlock_door":
			EventBus.notification_requested.emit({
				"type": "info", "category": "ui",
				"title": action_type.replace("_", " ").capitalize(),
				"body": "Not yet implemented.",
				"duration": 3.0,
			})
		"set_idle_behavior":
			# TODO: Open idle behavior submenu (Phase 8).
			EventBus.notification_requested.emit({
				"type": "info", "category": "ui",
				"title": "Idle Behavior",
				"body": "Idle behavior configuration coming soon.",
				"duration": 3.0,
			})

	# Update order overlay after any action.
	if _scene != null and _controller != null:
		_scene.update_order_overlay(_controller.get_order_manager().get_all_orders())

	_close_context_menu()


func _on_context_cancelled() -> void:
	_close_context_menu()


func _close_context_menu() -> void:
	if _context_menu != null and is_instance_valid(_context_menu):
		_context_menu.queue_free()
		_context_menu = null


# ---------------------------------------------------------------------------
# Cell interaction (left-click fallback — no context menu, direct move)
# ---------------------------------------------------------------------------

func _on_cell_clicked(pos: Vector2i) -> void:
	# Left-click on a cell with no entity: currently a no-op in the new model.
	# Movement is done via right-click context menu "Move Here".
	# This signal is kept for potential future use (cell inspection, etc.).
	pass


# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------

func _on_entity_selected(entity_id: String) -> void:
	if _unit_info_panel == null or _runner == null:
		return
	var selected: Array[String] = _scene.get_selected_entity_ids() if _scene != null else []
	var party_data: PartyData = _runner.get_party_data()
	if party_data == null:
		return

	if selected.size() == 1:
		var cd: CharacterData = party_data.get_member(selected[0])
		if cd != null:
			var light_info := {}
			if _handlers != null:
				var lm = _handlers.get_light_manager()
				if lm != null:
					var src_type: String = lm.get_source_type(selected[0])
					if not src_type.is_empty():
						light_info = {
							"source_type": src_type,
							"remaining": lm.get_remaining_turns(selected[0]),
						}
			_unit_info_panel.show_entity(cd, {}, light_info)
	elif selected.size() > 1:
		var chars: Array = []
		for eid in selected:
			var cd: CharacterData = party_data.get_member(eid)
			if cd != null:
				chars.append(cd)
		_unit_info_panel.show_multi_select(chars)


func _on_selection_cleared() -> void:
	if _unit_info_panel != null:
		_unit_info_panel.clear()


# ---------------------------------------------------------------------------
# Control groups
# ---------------------------------------------------------------------------

func _on_control_group_assign(group_number: int, entity_ids: Array) -> void:
	if _session_state == null or entity_ids.is_empty():
		return
	_session_state.assign_group(group_number, entity_ids)


func _on_control_group_recall(group_number: int) -> void:
	if _session_state == null or _scene == null:
		return
	var members: Array[String] = _session_state.get_group(group_number)
	if members.is_empty():
		return
	_scene.clear_selection()
	for eid in members:
		_scene.select_entity(eid, true)


func _on_control_group_select_entity(entity_id: String) -> void:
	# Double-click on entity: select all members of that entity's control group.
	if _session_state == null or _scene == null:
		return
	var group_num: int = _session_state.get_entity_group(entity_id)
	if group_num == 0:
		return
	_on_control_group_recall(group_num)


# ---------------------------------------------------------------------------
# UI panel creation
# ---------------------------------------------------------------------------

func _create_ui_panels() -> void:
	if _scene == null:
		return
	var hud = _scene.get_node_or_null("DungeonHUD")
	if hud == null:
		return

	# Unit info panel (left side).
	_unit_info_panel = UnitInfoPanelScene.new()
	_unit_info_panel.anchors_preset = Control.PRESET_LEFT_WIDE
	_unit_info_panel.anchor_right = 0.0
	_unit_info_panel.offset_left = 8.0
	_unit_info_panel.offset_top = 8.0
	_unit_info_panel.offset_right = 210.0
	_unit_info_panel.offset_bottom = -60.0
	_unit_info_panel.grow_horizontal = Control.GROW_DIRECTION_END
	hud.add_child(_unit_info_panel)

	# Control group bar (top left, below unit info panel).
	_control_group_bar = ControlGroupBarScene.new()
	_control_group_bar.anchors_preset = Control.PRESET_TOP_LEFT
	_control_group_bar.offset_left = 8.0
	_control_group_bar.offset_top = 270.0
	_control_group_bar.offset_right = 210.0
	_control_group_bar.offset_bottom = 310.0
	_control_group_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_control_group_bar.group_clicked.connect(_on_control_group_recall)
	_control_group_bar.group_double_clicked.connect(_on_control_group_recall)
	hud.add_child(_control_group_bar)

	# Notification log (bottom right).
	_notification_log = NotificationLogScene.new()
	_notification_log.anchors_preset = Control.PRESET_BOTTOM_RIGHT
	_notification_log.anchor_left = 1.0
	_notification_log.anchor_top = 1.0
	_notification_log.offset_left = -290.0
	_notification_log.offset_top = -240.0
	_notification_log.offset_right = -8.0
	_notification_log.offset_bottom = -36.0
	_notification_log.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_notification_log.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_notification_log.log_entry_clicked.connect(_on_log_entry_clicked)
	hud.add_child(_notification_log)

	# Minimap (top right).
	_minimap = MinimapScene.new()
	_minimap.anchors_preset = Control.PRESET_TOP_RIGHT
	_minimap.anchor_left = 1.0
	_minimap.offset_left = -192.0
	_minimap.offset_top = 8.0
	_minimap.offset_right = -8.0
	_minimap.offset_bottom = 192.0
	_minimap.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_minimap.visible = false  # Toggle with M key.
	_minimap.cell_clicked.connect(_on_minimap_cell_clicked)
	hud.add_child(_minimap)

	# Initial minimap update.
	_update_minimap()


func _update_minimap() -> void:
	if _minimap == null or _controller == null:
		return
	var map: TacticalMapData = _controller.get_map()
	if map == null:
		return
	# Check if party has a mapper.
	var has_mapper := false
	var party_data: PartyData = _runner.get_party_data() if _runner != null else null
	if party_data != null:
		for cd: CharacterData in party_data.character_data:
			if not cd.is_dead and cd.is_active and cd.has_proficiency("mapping"):
				has_mapper = true
				break
	_minimap.update(map, map.entity_positions, has_mapper)


func _on_log_entry_clicked(cell: Vector2i) -> void:
	if _scene == null:
		return
	var camera = _scene.get_node_or_null("Camera2D")
	if camera != null:
		camera.position = IsometricGrid.cell_to_screen(cell.x, cell.y)


func _on_minimap_cell_clicked(cell: Vector2i) -> void:
	_on_log_entry_clicked(cell)  # Same behavior — center camera.


func _on_minimap_toggle() -> void:
	if _minimap != null:
		_minimap.toggle()
		if _minimap.visible:
			_update_minimap()


# ---------------------------------------------------------------------------
# Movement orders
# ---------------------------------------------------------------------------

## Issue movement orders for a list of entities to a target cell.
func _issue_move_orders(
	entity_ids: Array,
	target: Vector2i,
	party_data: PartyData,
	scheduler: EventScheduler,
	party_id: String,
) -> void:
	var any_ordered := false
	for eid in entity_ids:
		var base_mv: int = 120  # default
		if party_data != null:
			var cd: CharacterData = party_data.get_member(eid)
			if cd != null:
				base_mv = cd.get_effective_movement()
		if _handlers.order_move(eid, target, base_mv, _controller, scheduler, party_id):
			any_ordered = true
			# Start continuous animation immediately (before clock unpauses).
			if _scene != null and _handlers != null:
				var cpr: float = _handlers.cells_per_round(base_mv)
				var order: Dictionary = _handlers._movement_orders.get(eid, {})
				var path: Array = order.get("path", [])
				if not path.is_empty():
					_scene.start_movement_animation(eid, path, cpr)
					_handlers.mark_renderer_animated(eid)

	if any_ordered:
		_start_clock_if_paused()


func _on_exit_requested() -> void:
	if _runner != null:
		_runner.transition_to_state("wilderness")


## Called when all party members have either exited or are incapacitated/dead.
func _on_all_party_resolved() -> void:
	if _runner == null:
		return
	_record_abandoned_characters()
	_runner.transition_to_state("wilderness")


## Record positions and timestamps of characters left behind in the dungeon
## (incapacitated or dead but body still present). They survive for 1 game day
## after the last member exits, after which they are considered dead.
func _record_abandoned_characters() -> void:
	if _session_state == null or _controller == null or _runner == null:
		return
	var party_data: PartyData = _runner.get_party_data()
	if party_data == null:
		return
	var party_id: String = _runner.get_party_id()
	var current_time: int = Timekeeping.get_party_time(party_id)
	var map: TacticalMapData = _controller.get_map()
	if map == null:
		return

	for cd: CharacterData in party_data.character_data:
		if not cd.is_active:
			continue
		if _session_state.is_exited(cd.id):
			continue  # Successfully exited — not abandoned.
		if not cd.is_dead and not cd.is_incapacitated:
			continue  # Still active — shouldn't happen if all_party_resolved is true.
		var pos: Vector2i = map.get_entity_pos(cd.id)
		if pos == Vector2i(-1, -1):
			continue
		CampaignRepository.record_abandoned_character(
			cd.id,
			_controller.get_dungeon_id(),
			_controller.get_current_level(),
			pos.x, pos.y,
			current_time,
		)


# ---------------------------------------------------------------------------
# Exit queue processing
# ---------------------------------------------------------------------------

## Advance queued exit characters toward the exit cell. Called after each
## scheduler tick. Characters queue up in adjacent cells and step forward
## as space opens.
func _check_exit_queue() -> void:
	if _session_state == null or _controller == null or _handlers == null or _runner == null:
		return
	var exit_queue: Dictionary = _session_state.get_exit_queue()
	if exit_queue.is_empty():
		return

	var map: TacticalMapData = _controller.get_map()
	if map == null:
		return

	var scheduler: EventScheduler = _runner.get_scheduler()
	var party_id: String = _runner.get_party_id()
	var party_data: PartyData = _runner.get_party_data()
	var any_ordered := false

	for eid in exit_queue:
		var exit_cell: Vector2i = exit_queue[eid]
		var entity_id: String = str(eid)

		# Skip if this entity already has an active movement.
		if _handlers.has_active_movement(entity_id):
			continue

		var current_pos: Vector2i = map.get_entity_pos(entity_id)
		if current_pos == Vector2i(-1, -1):
			# Entity no longer on the map — remove from queue.
			_session_state.dequeue_exit(entity_id)
			continue

		if current_pos == exit_cell:
			# On the exit cell — schedule the 1-round exit action and dequeue.
			_session_state.dequeue_exit(entity_id)
			_handlers.schedule_action("exit_dungeon", entity_id, exit_cell, 1, scheduler, party_id)
			any_ordered = true
		else:
			# Not on the exit cell yet — try to move closer.
			var base_mv: int = 120
			if party_data != null:
				var cd: CharacterData = party_data.get_member(entity_id)
				if cd != null:
					base_mv = cd.get_effective_movement()
			if _handlers.order_move(entity_id, exit_cell, base_mv, _controller, scheduler, party_id):
				# Start continuous animation for the movement.
				if _scene != null:
					var cpr: float = _handlers.cells_per_round(base_mv)
					var order: Dictionary = _handlers._movement_orders.get(entity_id, {})
					var path: Array = order.get("path", [])
					if not path.is_empty():
						_scene.start_movement_animation(entity_id, path, cpr)
						_handlers.mark_renderer_animated(entity_id)
				any_ordered = true

	if any_ordered:
		_start_clock_if_paused()


# ---------------------------------------------------------------------------
# Clock control
# ---------------------------------------------------------------------------

## Start the clock at normal speed if currently paused.
func _start_clock_if_paused() -> void:
	var loop: SchedulerLoop = _runner.get_scheduler_loop()
	if loop != null and loop.is_paused():
		loop.resume(SchedulerLoop.SPEED_NORMAL)


# ---------------------------------------------------------------------------
# Renderer-driven movement animation callbacks
# ---------------------------------------------------------------------------

## Called when the renderer's tween crosses a cell boundary during continuous
## movement animation. Updates the mechanical position and checks passability.
func _on_movement_cell_reached(entity_id: String, cell: Vector2i) -> void:
	if _handlers == null or _in_combat:
		return
	var result: Dictionary = _handlers.on_cell_reached(entity_id, cell)

	if result.get("blocked", false):
		# Path became impassable — cancel the visual animation.
		if _scene != null:
			_scene.cancel_movement_animation(entity_id)
		_check_all_movement_done()
		return

	if result.get("all_complete", false):
		_check_all_movement_done()


## Called when the renderer finishes the full path for an entity.
func _on_movement_path_complete(entity_id: String) -> void:
	if _handlers == null or _in_combat:
		return
	# The final cell was already committed by the last movement_cell_reached
	# callback. Clean up the movement order and handle on_arrival.
	if _handlers._movement_orders.has(entity_id):
		# The last on_cell_reached should have handled this, but as a safety
		# net: remove the order and clear renderer flag.
		_handlers._movement_orders.erase(entity_id)
		_handlers.clear_renderer_animated(entity_id)
	_check_all_movement_done()


## If all movement orders have been completed, auto-pause the scheduler.
func _check_all_movement_done() -> void:
	if _handlers == null:
		return
	if not _handlers.has_active_movement():
		var loop: SchedulerLoop = _runner.get_scheduler_loop()
		if loop != null and not loop.is_paused():
			loop.pause()


# ---------------------------------------------------------------------------
# Scheduler event listener — detect dungeon encounters for in-place combat
# ---------------------------------------------------------------------------

func _on_scheduler_event_resolved(event_type: String, _event_data: Dictionary) -> void:
	if _in_combat or _runner == null:
		return

	var loop: SchedulerLoop = _runner.get_scheduler_loop()
	if loop == null:
		return
	for result in loop.last_tick_results:
		var presentation: Dictionary = result.get("presentation", {})
		var ptype: String = presentation.get("type", "")

		if ptype == "dungeon_encounter":
			var enc: Dictionary = presentation.get("encounter_data", {})
			if not enc.is_empty():
				_start_dungeon_combat(enc)
				return

		if ptype == "dungeon_character_exited":
			var exited_id: String = presentation.get("entity_id", "")
			if not exited_id.is_empty() and _scene != null:
				_scene.remove_entity_token(exited_id)
			if presentation.get("all_resolved", false):
				_on_all_party_resolved()
				return

		if ptype == "open_loot_modal":
			var cache_id: String = presentation.get("cache_id", "")
			var cell_x: int = presentation.get("cell_x", 0)
			var cell_y: int = presentation.get("cell_y", 0)
			if not cache_id.is_empty():
				_open_loot_modal_from_cache(cache_id, Vector2i(cell_x, cell_y))
			return

	# After resolving events, check idle behaviors for entities without orders.
	_check_idle_behaviors()

	# Advance queued exit characters toward the exit cell.
	_check_exit_queue()

	# Refresh minimap after any state change.
	_update_minimap()


## Check idle behaviors for all entities that have no active orders.
func _check_idle_behaviors() -> void:
	if _session_state == null or _controller == null or _handlers == null or _runner == null:
		return
	var scheduler: EventScheduler = _runner.get_scheduler()
	var party_id: String = _runner.get_party_id()
	var party_data: PartyData = _runner.get_party_data()
	var map: TacticalMapData = _controller.get_map()
	if map == null or party_data == null:
		return

	for eid in _controller.get_entity_ids():
		if _handlers.has_active_movement(eid):
			continue
		if _session_state.has_active_action(eid):
			continue

		var behavior: String = _session_state.get_idle_behavior(eid)
		match behavior:
			"auto_listen_at_doors":
				# If adjacent to a closed door, auto-listen.
				var pos: Vector2i = map.get_entity_pos(eid)
				if pos == Vector2i(-1, -1):
					continue
				for neighbor in IsometricGrid.get_neighbors(pos):
					if map.is_door(neighbor) and map.get_door_state(neighbor) != "open":
						_handlers.schedule_action("listen", eid, neighbor, 1, scheduler, party_id)
						break
			"guard":
				# Check for hostiles in awareness radius — auto-pause if found.
				# For now, this is handled by the encounter check system.
				pass
			_:
				# hold_position, follow_group_lead, auto_search, hide — more complex,
				# deferred to when the systems they depend on are built.
				pass


# ---------------------------------------------------------------------------
# In-place dungeon combat
# ---------------------------------------------------------------------------

func _start_dungeon_combat(encounter_data: Dictionary) -> void:
	if _runner == null or _controller == null or _scene == null:
		return
	_in_combat = true

	# Pause scheduler — combat is turn-based.
	var loop: SchedulerLoop = _runner.get_scheduler_loop()
	if loop != null:
		loop.pause()

	# Cancel all real-time movement and visual animations.
	if _handlers != null:
		_handlers.cancel_all_moves()
	if _scene != null:
		_scene.cancel_all_movement_animations()

	var tactical_map: TacticalMapData = _controller.get_map()

	# Gather current party positions
	var party_positions: Array[Vector2i] = []
	for eid in _controller.get_entity_ids():
		if tactical_map.entity_positions.has(eid):
			party_positions.append(tactical_map.entity_positions[eid])
	if party_positions.is_empty():
		party_positions.append(_controller.get_party_position())

	# Spawn monsters
	var monster_registry = _runner.get_monster_registry()
	var placements: Array = _spawner.spawn_encounter(
		tactical_map, party_positions, encounter_data, monster_registry, DiceSystem)

	if placements.is_empty():
		push_warning("DungeonExploreState: encounter spawn failed, skipping combat")
		_in_combat = false
		return

	# Build CombatRoster
	var party_data: PartyData = _runner.get_party_data()
	var roster := CombatRoster.new()

	var equip_catalog = load("res://engine/subsystems/characters/equipment_catalog.gd")
	var catalog = equip_catalog.new() if equip_catalog != null else null
	if party_data != null:
		for cd: CharacterData in party_data.character_data:
			if not cd.is_dead and cd.is_active:
				var combatant := Combatant.from_character(cd)
				if tactical_map.entity_positions.has(cd.id):
					combatant.grid_position = tactical_map.entity_positions[cd.id]
				var inv_rows: Array = CampaignRepository.get_inventory_items(cd.id)
				combatant.wire_equipment(inv_rows, catalog)
				roster.add_combatant(combatant)

	# Add trained creatures with combat roles (war mounts, guards, hunters).
	if party_data != null:
		var mr: MonsterRegistry = _runner.get_monster_registry()
		roster.add_party_creatures(party_data, mr)
		# Place creature combatants on the grid near party members.
		for c: Combatant in roster.get_alive_on_side(Combatant.Side.PARTY):
			if c.is_character:
				continue
			if not tactical_map.entity_positions.has(c.id):
				var placement := _find_creature_placement(tactical_map, party_positions)
				if placement != Vector2i(-1, -1):
					c.grid_position = placement
					tactical_map.set_entity_pos(c.id, placement)
				# Add a token for the creature on the dungeon map.
				var cname: String = c.display_name
				_scene.add_entity_token(c.id, cname, 1, cname.substr(0, 1).to_upper())
				_scene.move_token(c.id, c.grid_position)

	for p in placements:
		var m_combatant := Combatant.from_monster(
			p["monster_data"], p["rolled_hp"], p["combatant_id"], p["group_id"])
		m_combatant.grid_position = p["grid_position"]
		roster.add_combatant(m_combatant)
		tactical_map.set_entity_pos(p["combatant_id"], p["grid_position"])
		var mname: String = p["monster_data"].get("name", "Monster")
		_scene.add_entity_token(p["combatant_id"], mname, 1, mname.substr(0, 1).to_upper())
		_scene.move_token(p["combatant_id"], p["grid_position"])

	roster.enemy_count_at_start = roster.get_alive_on_side(Combatant.Side.ENEMY).size()

	# Build combat subsystems
	var active_effects: ActiveEffectTracker = _runner.get_active_effects()
	var condition_catalog := ConditionCatalog.new()
	var condition_manager := CombatConditionManager.new(condition_catalog)
	var spell_hooks := SpellCombatHooks.new(active_effects)

	var init_resolver := InitiativeResolver.new(DiceSystem)
	var attack_resolver := AttackResolver.new(DiceSystem, spell_hooks)
	var ranged_resolver := RangedAttackResolver.new(DiceSystem, spell_hooks)

	var movement_resolver := MovementResolver.new(tactical_map, roster)
	var monster_ai := MonsterAI.new(roster, DiceSystem, movement_resolver)
	var morale_resolver := MoraleResolver.new(DiceSystem)
	var cleave_resolver := CleaveResolver.new()
	var mortal_wounds_resolver := MortalWoundsResolver.new(DiceSystem)

	_dungeon_combat_controller = CombatController.new(
		roster, init_resolver, attack_resolver,
		spell_hooks, condition_manager, ranged_resolver,
		monster_ai, morale_resolver, cleave_resolver,
		tactical_map, mortal_wounds_resolver)
	_dungeon_combat_controller.encounter_id = encounter_data.get("encounter_id", "")

	EventBus.combat_started.emit(_dungeon_combat_controller.encounter_id)

	_set_dungeon_hud_visible(false)

	_combat_overlay = DungeonCombatOverlay.new()
	_runner.add_child(_combat_overlay)
	_combat_overlay.combat_finished.connect(_on_dungeon_combat_finished)
	_combat_overlay.start_combat(_dungeon_combat_controller, _scene)


func _on_dungeon_combat_finished(result: Dictionary) -> void:
	_in_combat = false

	# Finalize: mortal wounds, XP, creature casualties, timekeeping.
	var party_data: PartyData = _runner.get_party_data()
	var roster: CombatRoster = _dungeon_combat_controller.roster if _dungeon_combat_controller != null else null
	_finalizer.finalize(_runner, result, party_data, roster)

	# Place loot at death cells on dungeon victory (before clearing the controller).
	if result.get("result", "") == "victory" and roster != null:
		_place_dungeon_loot(roster)

	_dungeon_combat_controller = null

	# Remove non-party tokens (monsters, dead creatures).
	# Keep alive PCs and alive creature tokens on the map.
	var tactical_map: TacticalMapData = _controller.get_map()
	if tactical_map != null:
		var keep_ids: Dictionary = {}
		if party_data != null:
			for cd: CharacterData in party_data.character_data:
				if not cd.is_dead:
					keep_ids[cd.id] = true
			for creature: TrainedCreatureData in party_data.creature_data:
				if creature.is_alive:
					keep_ids["creature_" + creature.id] = true
		var to_remove: Array = []
		for eid in tactical_map.entity_positions.keys():
			if not keep_ids.has(eid):
				to_remove.append(eid)
		for eid in to_remove:
			tactical_map.remove_entity(eid)
			_scene.remove_entity_token(eid)

	if _combat_overlay != null:
		_combat_overlay.end_combat()
		_combat_overlay = null

	_set_dungeon_hud_visible(true)
	# Scheduler stays paused after combat — player decides when to resume.


# ---------------------------------------------------------------------------
# Dungeon loot placement
# ---------------------------------------------------------------------------

## Creates a location cache at the first defeated enemy's death cell and deposits
## rolled treasure (coins) into it. Called after dungeon combat victory.
## The context menu's "Loot" option appears when has_ground_items is set on the cell.
func _place_dungeon_loot(roster: CombatRoster) -> void:
	if _controller == null:
		return

	# Collect treasure types and the first valid death cell from defeated enemies.
	# TODO (voxel migration): extend location_key to include level coordinate
	# per gdd-voxel-tactical-architecture-v1.1.md §6.3 — currently 2D (col,row);
	# becomes 3D (col,row,level) when the voxel schema lands.
	var treasure_types: Array = []
	var loot_cell := Vector2i(-1, -1)
	for c: Combatant in roster.get_all():
		if c.is_enemy_side() and not c.is_alive():
			var tt: String = c._monster_data.get("treasure_type", "None")
			if tt != "None" and not tt.is_empty():
				treasure_types.append(tt)
			if loot_cell == Vector2i(-1, -1) and c.grid_position != Vector2i(-1, -1):
				loot_cell = c.grid_position

	if treasure_types.is_empty():
		return
	if loot_cell == Vector2i(-1, -1):
		push_warning("DungeonExploreState._place_dungeon_loot: no valid death cell for loot placement")
		return

	# Roll coins from treasure types.
	var generator := LootGenerator.new()
	var loot: Dictionary = generator.generate_from_treasure_types(treasure_types)
	if loot.is_empty():
		return
	var total_cp := Currency.coins_to_cp(loot)
	if total_cp <= 0:
		return

	# Create a loose cache at the death cell.
	var dungeon_id: String = _controller.get_dungeon_id()
	var cache_id: String = LocationCacheManager.create_dungeon_loose_cache(dungeon_id, loot_cell)
	if cache_id.is_empty():
		push_error("DungeonExploreState._place_dungeon_loot: failed to create cache at %s" % str(loot_cell))
		return

	# Insert coin items into the cache.
	for denom in Currency.DENOMINATIONS:
		var coin_key: String = denom["key"]
		var qty: int = loot.get(coin_key, 0)
		if qty <= 0:
			continue
		var item_id: String = CampaignRepository.add_inventory_item({
			"item_key": coin_key,
			"name": denom["name"],
			"quantity": qty,
			"encumbrance_units": Currency.ENC_PER_COIN,
			"item_category": Currency.COIN_ITEM_CATEGORY,
		})
		if not item_id.is_empty():
			CampaignRepository.transfer_item_to_cache(item_id, cache_id)

	# Flag the cell so the context menu shows Loot / Pick Up All.
	var tactical_map: TacticalMapData = _controller.get_map()
	if tactical_map != null:
		tactical_map.set_cell_field(loot_cell, "has_ground_items", true)

	print("Placed dungeon loot cache at cell %s (cache_id=%s, total_cp=%d)" % [
		str(loot_cell), cache_id, total_cp])


# ---------------------------------------------------------------------------
# Loot modal management
# ---------------------------------------------------------------------------

func _ensure_loot_modal() -> void:
	if _loot_modal != null:
		return
	_loot_modal = LootModalScript.new()
	_loot_modal.distribution_completed.connect(_on_loot_modal_completed)
	if _runner != null:
		_runner.add_child(_loot_modal)


func _open_loot_modal_from_cache(cache_id: String, cell: Vector2i) -> void:
	_ensure_loot_modal()
	_loot_modal.open_from_cache(cache_id, cell)


func _on_loot_modal_completed(cache_id: String, cache_cell: Vector2i) -> void:
	if cache_id.is_empty():
		return
	# If the cache is now empty, delete it and clear the cell flag.
	var remaining := CampaignRepository.list_items_in_cache(cache_id)
	if remaining.is_empty():
		CampaignRepository.delete_location_cache(cache_id)
		var tactical_map: TacticalMapData = _controller.get_map() if _controller != null else null
		if tactical_map != null and cache_cell != Vector2i(-1, -1):
			tactical_map.set_cell_field(cache_cell, "has_ground_items", false)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _find_creature_placement(
		tactical_map: TacticalMapData,
		party_positions: Array[Vector2i]) -> Vector2i:
	## Find a passable, unoccupied cell adjacent to any party member.
	## Returns Vector2i(-1, -1) if none found.
	for pos in party_positions:
		for neighbor in IsometricGrid.get_neighbors(pos):
			if tactical_map.is_passable(neighbor) and tactical_map.get_entities_at(neighbor).is_empty():
				return neighbor
	# Fallback: if no free adjacent cell, stack on leader position.
	if not party_positions.is_empty():
		return party_positions[0]
	return Vector2i(-1, -1)


func _set_dungeon_hud_visible(vis: bool) -> void:
	if _scene == null:
		return
	var ctx_layer = _scene.get_node_or_null("DungeonHUD/ContextMenuLayer")
	if ctx_layer != null:
		ctx_layer.visible = vis
	if _unit_info_panel != null:
		_unit_info_panel.visible = vis and _unit_info_panel.visible
	if _control_group_bar != null:
		_control_group_bar.visible = vis
	if _notification_log != null:
		_notification_log.visible = vis
	if _minimap != null and vis:
		# Don't force minimap visible — respect its toggle state.
		pass
	elif _minimap != null and not vis:
		_minimap.visible = false


static func _class_letter(character_class: String) -> String:
	match character_class.to_lower():
		"fighter", "warrior":   return "F"
		"mage", "wizard":       return "M"
		"cleric", "priest":     return "C"
		"thief", "rogue":       return "T"
		"bard":                 return "B"
		"ranger":               return "R"
		"paladin":              return "P"
		"assassin":             return "A"
		_:                      return character_class.substr(0, 1).to_upper()


func get_location_key_for_character(_character_id: String) -> String:
	if _controller == null:
		return "unknown"
	return "dungeon:%s:level:%d" % [_controller.get_dungeon_id(), _controller.get_current_level()]
