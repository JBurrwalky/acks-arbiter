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

## Roaming monsters spawned by an encounter check but not yet in combat.
## Combat starts when any of them has a clear path within attack range to a PC.
## Shape: { encounter_id: { encounter_data: Dictionary, placements: Array } }
## Placements use the same dict shape returned by DungeonEncounterSpawner —
## each entry is reused verbatim when combat is finally triggered.
var _roaming_monsters: Dictionary = {}

## Per-dungeon-visit in-memory state (control groups, idle behaviors, etc.).
var _session_state: RefCounted = null  # DungeonSessionState

## Active context menu popup (if any).
var _context_menu: PanelContainer = null

## Last-requested context menu screen position — used to re-show the menu
## at the same spot for the Session 8 two-click confirm submenu.
var _last_menu_screen_pos: Vector2 = Vector2.ZERO

## Loot distribution modal for dungeon cache looting.
var _loot_modal = null  # LootDistributionModal (lazy-created)

## UI panels.
var _unit_info_panel: PanelContainer = null
var _control_group_bar: PanelContainer = null
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
					cd.character_class, cd.token_variant, cd.sex)
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

	# Refresh the minimap when the renderer's focus level changes (PgUp/PgDn,
	# party-portrait clicks, wandering-encounter auto-focus).
	if not EventBus.dungeon_focus_level_changed.is_connected(_on_dungeon_focus_level_changed):
		EventBus.dungeon_focus_level_changed.connect(_on_dungeon_focus_level_changed)

	# Auto-activate light sources from inventory.
	_auto_activate_lights(runner)

	# Seed recurring dungeon events (wandering monster checks, light ticks).
	_handlers.seed_dungeon_events(runner.get_scheduler(), runner.get_party_id())

	# Scheduler starts paused — player issues orders, then unpauses.


func exit(runner) -> void:
	runner.get_nav_stack().pop()

	# Revert picked locks before saving (locks reset on dungeon exit).
	if _session_state != null and _controller != null and _controller.get_voxel_map() != null:
		var vmap: VoxelMapData = _controller.get_voxel_map()
		for pos in _session_state.get_picked_locks():
			if vmap.get_door_state(pos) in ["closed", "open"]:
				vmap.set_door_state(pos, "locked")
				vmap.set_cell_field(pos, "door_type", "locked")

	# Save dungeon cell states (door + fog) for all loaded levels.
	_save_dungeon_cell_states()

	# Disconnect scheduler event listener.
	if EventBus.scheduler_event_resolved.is_connected(_on_scheduler_event_resolved):
		EventBus.scheduler_event_resolved.disconnect(_on_scheduler_event_resolved)
	if EventBus.dungeon_focus_level_changed.is_connected(_on_dungeon_focus_level_changed):
		EventBus.dungeon_focus_level_changed.disconnect(_on_dungeon_focus_level_changed)

	# Cancel movement animations before tearing down.
	if _scene != null:
		_scene.cancel_all_movement_animations()

	# Drop any roaming monsters that never reached attack range — leaving the
	# dungeon level unloads them. Their tokens go away with the scene.
	_roaming_monsters.clear()

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
	var vmap: VoxelMapData = _controller.get_voxel_map()
	if vmap == null:
		return
	var cells_to_save: Array = []
	for vcell: VoxelCell in vmap.get_all_cells():
		# Visible reverts to explored on save.
		var save_fog: String = "explored" if vcell.fog_state == "visible" else vcell.fog_state
		# Only save cells with meaningful state (doors or non-hidden fog).
		if not vcell.door_state.is_empty() or vcell.fog_state != "hidden":
			var save_cell := VoxelCell.new()
			save_cell.col = vcell.col
			save_cell.row = vcell.row
			save_cell.level = vcell.level
			save_cell.solidity = vcell.solidity
			save_cell.feature = vcell.feature
			save_cell.floor_type = vcell.floor_type
			save_cell.door_state = vcell.door_state
			save_cell.door_type = vcell.door_type
			save_cell.door_detected = vcell.door_detected
			save_cell.fog_state = save_fog
			save_cell.room_id = vcell.room_id
			save_cell.is_corridor = vcell.is_corridor
			save_cell.cover_value = vcell.cover_value
			cells_to_save.append(save_cell)
	if not cells_to_save.is_empty():
		CampaignRepository.save_voxel_cells_batch(dungeon_id, cells_to_save)


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

func _on_context_menu_requested(cell_pos, screen_pos: Vector2) -> void:
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

	var map = _controller.get_voxel_map()
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
	_last_menu_screen_pos = screen_pos
	_context_menu.show_at(screen_pos, options, loop)


func _on_context_action(action_data: Dictionary) -> void:
	if _runner == null or _controller == null:
		return

	var action_type: String = action_data.get("action_type", "")
	var cell = action_data.get("cell", Vector2i(-1, -1))  # Vector2i or Vector3i
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
			if _should_confirm_cross_level_move(cell):
				_show_move_confirm_menu(cell, selected)
				return
			_issue_move_orders(selected, cell, party_data, scheduler, party_id)
		"move_here_confirm":
			_issue_move_orders(selected, cell, party_data, scheduler, party_id)
		"search_here":
			# Move to cell, then search (1 turn = 60 rounds). Picker queries
			# ThiefSkillResolver for each candidate's `detect_secrets` target,
			# so the lowest target wins — high-level thief beats an elf when
			# their thief progression is better, otherwise racial 8+ wins.
			var search_actor: String = DungeonActionActorPicker.pick_for_search(
				selected, party_data,
				_thief_skill_resolver(), _build_bundle_callable())
			_issue_single_actor_action(
				search_actor, selected, "search", cell, DungeonHandlers.TURN_ROUNDS,
				party_data, scheduler, party_id, false,
				"No one to search.", "Search")
		"listen_here":
			var listen_actor: String = DungeonActionActorPicker.pick_for_listen(
				selected, party_data,
				_thief_skill_resolver(), _build_bundle_callable())
			_issue_single_actor_action(
				listen_actor, selected, "listen", cell, 1,
				party_data, scheduler, party_id, false,
				"No one to listen.", "Listen")

		# --- Door interactions (instant on-arrival door toggle) ---
		"open_door", "close_door":
			var actor: String = DungeonActionActorPicker.pick_first_available(
				selected, party_data)
			_issue_door_toggle(actor, selected, cell, party_data, scheduler, party_id,
				"Open Door" if action_type == "open_door" else "Close Door")
		"force_door":
			var force_actor: String = DungeonActionActorPicker.pick_for_force(
				selected, party_data)
			_issue_single_actor_action(
				force_actor, selected, "force_door", cell, 1,
				party_data, scheduler, party_id, true,
				"No one strong enough to force this door.",
				"Force Door (1 round)")
		"pick_lock":
			var lock_actor: String = DungeonActionActorPicker.pick_for_pick_lock(
				selected, party_data, _session_state)
			_issue_single_actor_action(
				lock_actor, selected, "pick_lock", cell, DungeonHandlers.TURN_ROUNDS,
				party_data, scheduler, party_id, true,
				"No qualified thief in the group.",
				"Pick Lock (1 turn)")
		"bash_door":
			var bash_turns: int = action_data.get("turns", 1)
			var bash_actor: String = DungeonActionActorPicker.pick_for_bash_door(
				selected, party_data)
			_issue_single_actor_action(
				bash_actor, selected, "bash_door", cell,
				bash_turns * DungeonHandlers.TURN_ROUNDS,
				party_data, scheduler, party_id, true,
				"No one is wielding an axe.",
				"Bash Door (%d turn%s)" % [bash_turns, "s" if bash_turns > 1 else ""])
		"spike_shut", "wedge_open":
			var spike_actor: String = DungeonActionActorPicker.pick_for_spike_action(
				selected, party_data, true)
			_issue_single_actor_action(
				spike_actor, selected, action_type, cell, 1,
				party_data, scheduler, party_id, true,
				"No one is carrying iron spikes.",
				"Spike Shut" if action_type == "spike_shut" else "Wedge Open")
		"remove_spike", "remove_wedge":
			var remove_actor: String = DungeonActionActorPicker.pick_for_spike_action(
				selected, party_data, false)
			_issue_single_actor_action(
				remove_actor, selected, action_type, cell, 1,
				party_data, scheduler, party_id, true,
				"No one available.",
				"Remove Spike" if action_type == "remove_spike" else "Remove Wedge")
		"listen_at_door":
			var listen_door_actor: String = DungeonActionActorPicker.pick_for_listen(
				selected, party_data,
				_thief_skill_resolver(), _build_bundle_callable())
			_issue_single_actor_action(
				listen_door_actor, selected, "listen_at_door", cell, 1,
				party_data, scheduler, party_id, true,
				"No one to listen.", "Listen at Door")
		"force_portcullis":
			var portcullis_actor: String = DungeonActionActorPicker.pick_for_force(
				selected, party_data)
			_issue_single_actor_action(
				portcullis_actor, selected, "force_portcullis", cell, 1,
				party_data, scheduler, party_id, true,
				"No one strong enough.",
				"Force Portcullis (1 round)")

		# --- Stairs ---
		"ascend", "descend":
			# Stair cells carry either an explicit stair_target_* coordinate
			# or a direction-suffix (stairs_up_<DIR>). get_stair_target resolves
			# the destination. When the destination is spatially adjacent the
			# party could pathfind to it, but hand-authored dungeons with paired
			# staircases often have non-adjacent destinations — we teleport the
			# party directly onto the landing cell, which also sidesteps the BFS
			# cost and avoids edge cases with intermediate unreachable cells.
			var cell_3d: Vector3i = cell if cell is Vector3i else Vector3i(cell.x, cell.y, _controller.get_current_level())
			var stair_target: Vector3i = _controller.get_stair_target(cell_3d)
			if stair_target == Vector3i(-1, -1, -1):
				EventBus.notification_requested.emit({
					"type": "warning", "category": "environment",
					"title": "Stair %s is not connected to anywhere." % str(cell_3d),
					"duration": 4.0,
				})
			else:
				var ok: bool = _controller.teleport_party_to(stair_target)
				if ok:
					var msg: String = "Ascend" if action_type == "ascend" else "Descend"
					EventBus.notification_requested.emit({
						"type": "info", "category": "environment",
						"title": "%s: %s → %s" % [msg, str(cell_3d), str(stair_target)],
						"duration": 3.0,
					})
				else:
					var vmap := _controller.get_voxel_map()
					var detail: String = "unknown"
					if vmap != null:
						if not vmap.has_cell(stair_target):
							detail = "no cell"
						elif not vmap.is_passable(stair_target):
							detail = "not passable (solidity=%s, floor=%s)" % [
								vmap.get_cell(stair_target).solidity,
								vmap.get_cell(stair_target).floor_type,
							]
					EventBus.notification_requested.emit({
						"type": "warning", "category": "environment",
						"title": "Stair %s → %s failed: %s" % [str(cell_3d), str(stair_target), detail],
						"duration": 6.0,
					})
		"exit_dungeon":
			# Queue all selected characters to exit the dungeon.
			var map = _controller.get_voxel_map()
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
					_refresh_control_group_bar()

		"use_lever":
			# Only one PC actually pulls the lever — schedule the first selected
			# character who is currently 3D-adjacent to it. Scheduling for every
			# selected PC produced a flurry of "Too far to reach the lever"
			# toasts when only one was adjacent.
			var lever_actor: String = ""
			var lever_cell_3d: Vector3i = cell if cell is Vector3i else \
				Vector3i(cell.x, cell.y, _controller.get_current_level())
			for eid in selected:
				var ep: Vector3i = _controller.get_entity_pos_3d(eid)
				if ep != Vector3i(-1, -1, -1) and VoxelGrid.is_adjacent(ep, lever_cell_3d):
					lever_actor = eid
					break
			if lever_actor.is_empty():
				EventBus.notification_requested.emit({
					"type": "warning", "category": "environment",
					"title": "No one is close enough to pull the lever.",
					"duration": 3.0,
				})
			else:
				_handlers.schedule_action("use_lever", lever_actor, cell, 1, scheduler, party_id)
				_start_clock_if_paused()
		"drop_portcullis":
			var drop_actor: String = DungeonActionActorPicker.pick_first_available(
				selected, party_data)
			_issue_single_actor_action(
				drop_actor, selected, "drop_portcullis", cell, 1,
				party_data, scheduler, party_id, true,
				"No one is at the controls.",
				"Drop Portcullis")

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


## Returns true if [param cell] is a Vector3i targeting a level other than the
## renderer's current VisibilityManager focus_level. Session 8 requires
## two-click confirmation for cross-level moves to prevent misclicks on dimmed
## / dithered levels.
func _should_confirm_cross_level_move(cell) -> bool:
	if not (cell is Vector3i):
		return false
	if _scene == null or not _scene.has_method("get_visibility_manager"):
		return false
	var vis = _scene.get_visibility_manager()
	if vis == null:
		return false
	return int(cell.z) != int(vis.focus_level)


## Builds a two-option confirmation submenu (Confirm / Cancel) at the last
## context-menu screen position. Choosing Confirm dispatches a
## "move_here_confirm" action through the normal _on_context_action path.
func _show_move_confirm_menu(cell, selected: Array[String]) -> void:
	_close_context_menu()
	if _scene == null or not (cell is Vector3i):
		return
	var target_z: int = int(cell.z)
	var options: Array[Dictionary] = [
		{
			"id": "move_here_confirm",
			"label": "Confirm move to Level %d" % target_z,
			"category": "confirm",
			"enabled": true,
			"action_data": {
				"action_type": "move_here_confirm",
				"cell": cell,
				"selected": selected,
			},
		},
		{
			"id": "cancel",
			"label": "Cancel",
			"category": "confirm",
			"enabled": true,
			"action_data": {"action_type": "cancel"},
		},
	]
	_context_menu = ContextMenuScene.new()
	var ctx_layer = _scene.get_node_or_null("DungeonHUD/ContextMenuLayer")
	if ctx_layer != null:
		ctx_layer.add_child(_context_menu)
	else:
		_scene.add_child(_context_menu)
	_context_menu.option_selected.connect(_on_context_action)
	_context_menu.cancelled.connect(_on_context_cancelled)
	var loop: SchedulerLoop = _runner.get_scheduler_loop()
	_context_menu.show_at(_last_menu_screen_pos, options, loop)


func _close_context_menu() -> void:
	if _context_menu != null and is_instance_valid(_context_menu):
		_context_menu.queue_free()
		_context_menu = null


# ---------------------------------------------------------------------------
# Cell interaction (left-click fallback — no context menu, direct move)
# ---------------------------------------------------------------------------

func _on_cell_clicked(pos) -> void:
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
	_refresh_control_group_bar()


func _refresh_control_group_bar() -> void:
	if _control_group_bar != null and _session_state != null:
		_control_group_bar.update_groups(_session_state, null)


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
	_refresh_control_group_bar()

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
	var vmap: VoxelMapData = _controller.get_voxel_map()
	if vmap == null:
		return
	# Gather party Vector3i positions from the voxel map.
	var party_positions: Dictionary = {}
	for eid in _controller.get_entity_ids():
		if vmap.entity_positions.has(eid):
			party_positions[eid] = vmap.entity_positions[eid]
	# Focus level comes from the renderer's VisibilityManager when available;
	# fall back to the controller's current_level.
	var focus_level: int = _controller.get_current_level()
	if _scene != null and _scene.has_method("get_visibility_manager"):
		var vm = _scene.get_visibility_manager()
		if vm != null:
			focus_level = vm.focus_level
	_minimap.update(vmap, party_positions, focus_level)


func _on_minimap_cell_clicked(cell: Vector3i) -> void:
	## Switch focus level to the clicked cell's level so the player sees
	## the corresponding dungeon layer. Camera recenter on (cell.x, cell.y)
	## within that level is a renderer follow-up — requires a scene method
	## we don't expose yet.
	if _scene == null:
		return
	if _scene.has_method("get_visibility_manager"):
		var vm = _scene.get_visibility_manager()
		if vm != null and cell.z != vm.focus_level:
			vm.set_focus_level(cell.z)
			_update_minimap()


func _on_dungeon_focus_level_changed(_level: int) -> void:
	_update_minimap()


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
	target,  # Vector2i or Vector3i
	party_data: PartyData,
	scheduler: EventScheduler,
	party_id: String,
) -> void:
	# Pre-compute base movement per entity so group and single paths share inputs.
	var base_movements: Dictionary = {}
	for eid in entity_ids:
		var bm: int = 120
		if party_data != null:
			var cd: CharacterData = party_data.get_member(eid)
			if cd != null:
				bm = cd.get_effective_movement()
		base_movements[eid] = bm

	var any_ordered := false

	# Multi-entity move: route through order_group_move so followers ring-scatter
	# around the target instead of stacking on it. Single-entity falls through to
	# the per-entity path.
	if entity_ids.size() > 1:
		var ordered: Array = _handlers.order_group_move(
			entity_ids, target, base_movements, _controller, scheduler, party_id
		)
		if not ordered.is_empty() and _scene != null and _handlers != null:
			for eid in ordered:
				var base_mv: int = base_movements.get(eid, 120)
				var cpr: float = _handlers.cells_per_round(base_mv)
				var order: Dictionary = _handlers._movement_orders.get(eid, {})
				var path: Array = order.get("path", [])
				if path.is_empty():
					continue
				_scene.start_movement_animation(eid, path, cpr)
				_handlers.mark_renderer_animated(eid)
				any_ordered = true
	else:
		for eid in entity_ids:
			var base_mv: int = base_movements.get(eid, 120)
			if _handlers.order_move(eid, target, base_mv, _controller, scheduler, party_id):
				any_ordered = true
				if _scene != null and _handlers != null:
					var cpr: float = _handlers.cells_per_round(base_mv)
					var order: Dictionary = _handlers._movement_orders.get(eid, {})
					var path: Array = order.get("path", [])
					if not path.is_empty():
						_scene.start_movement_animation(eid, path, cpr)
						_handlers.mark_renderer_animated(eid)

	if any_ordered:
		_start_clock_if_paused()


## Returns a fresh ThiefSkillResolver wired to the runner's class registry.
## Used by the actor picker to compute true effective targets for thief and
## adventuring skills (with class progression and proficiency equivalents).
## Returns null when the runner / class registry is unavailable.
func _thief_skill_resolver() -> ThiefSkillResolver:
	if _runner == null:
		return null
	var class_reg: ClassRegistry = _runner.get_class_registry()
	if class_reg == null:
		return null
	return ThiefSkillResolver.new(class_reg, ProficiencyRegistry.new(), PowerRegistry.new())


## Returns a Callable(character_id) -> CharacterBundle that the picker can
## invoke per candidate. Centralises the bundle-build pattern used by
## skill-roll resolvers in DungeonHandlers.
func _build_bundle_callable() -> Callable:
	return Callable(self, "_build_bundle_for_picker")


func _build_bundle_for_picker(character_id: String) -> CharacterBundle:
	if _runner == null:
		return null
	var party_data: PartyData = _runner.get_party_data()
	if party_data == null:
		return null
	var cd: CharacterData = party_data.get_member(character_id)
	if cd == null:
		return null
	var bundle := CharacterBundle.new()
	bundle.character = cd
	bundle.proficiencies = CampaignRepository.get_character_proficiencies(character_id)
	bundle.character.proficiencies = bundle.proficiencies
	bundle.powers = CampaignRepository.get_character_powers(character_id)
	bundle.inventory = CampaignRepository.get_inventory_items(character_id)
	return bundle


## Returns the effective base movement (ft/round) for [param entity_id].
## Falls back to 120 ft when CharacterData is unavailable.
func _get_base_movement(entity_id: String, party_data: PartyData) -> int:
	if party_data == null:
		return 120
	var cd: CharacterData = party_data.get_member(entity_id)
	if cd == null:
		return 120
	return cd.get_effective_movement()


## Kick off the renderer's continuous-movement tween for [param entity_id]
## using the path that handlers just queued. No-op when no path is queued.
func _start_renderer_animation_for(entity_id: String, base_movement: int) -> void:
	if _scene == null or _handlers == null:
		return
	var order: Dictionary = _handlers._movement_orders.get(entity_id, {})
	var path: Array = order.get("path", [])
	if path.is_empty():
		return
	var cpr: float = _handlers.cells_per_round(base_movement)
	_scene.start_movement_animation(entity_id, path, cpr)
	_handlers.mark_renderer_animated(entity_id)


## Issue a single-actor compound action with the rest of the selection
## following in formation toward the action site. Used for skill-roll and
## item-required dungeon actions (pick_lock, force_door, bash_door, search,
## listen, spike-shut, ...). When [param best_actor] is empty (nobody
## qualifies), emits [param empty_warning] and does nothing.
func _issue_single_actor_action(
		best_actor: String,
		selected: Array,
		action_type: String,
		cell,
		duration_rounds: int,
		party_data: PartyData,
		scheduler: EventScheduler,
		party_id: String,
		adjacent_only: bool,
		empty_warning: String,
		action_label: String) -> void:
	if best_actor.is_empty():
		EventBus.notification_requested.emit({
			"type": "warning", "category": "environment",
			"title": empty_warning, "duration": 3.0,
		})
		return

	var actor_mv: int = _get_base_movement(best_actor, party_data)
	var ok: bool = _handlers.order_move_and_schedule_action(
		best_actor, cell, action_type, duration_rounds,
		actor_mv, _controller, scheduler, party_id, adjacent_only)
	if not ok:
		EventBus.notification_requested.emit({
			"type": "warning", "category": "environment",
			"title": "%s: cannot reach the target." % action_label,
			"duration": 3.0,
		})
		return

	# If a walk-to phase was queued, drive its tween animation.
	_start_renderer_animation_for(best_actor, actor_mv)

	# Followers — everyone else in the selection — group-move toward the
	# action site so they bunch up near the actor while waiting.
	var followers: Array = []
	var follower_movements: Dictionary = {}
	for eid in selected:
		var sid: String = str(eid)
		if sid == best_actor:
			continue
		followers.append(sid)
		follower_movements[sid] = _get_base_movement(sid, party_data)
	if not followers.is_empty():
		var ordered: Array = _handlers.order_group_move(
			followers, cell, follower_movements,
			_controller, scheduler, party_id)
		for eid in ordered:
			_start_renderer_animation_for(eid, follower_movements.get(eid, 120))

	var actor_name: String = best_actor
	if party_data != null:
		var cd: CharacterData = party_data.get_member(best_actor)
		if cd != null:
			actor_name = cd.name
	EventBus.notification_requested.emit({
		"type": "info", "category": "environment",
		"title": "%s: %s" % [action_label, actor_name],
		"duration": 2.5,
	})
	_start_clock_if_paused()


## Issue an instant door open/close: best actor walks to the door cell and
## toggles it on arrival; followers group-move to the door's vicinity in
## formation. Mirrors _issue_single_actor_action but uses interact_door
## (instant) instead of schedule_action (timed).
func _issue_door_toggle(
		best_actor: String,
		selected: Array,
		cell,
		party_data: PartyData,
		scheduler: EventScheduler,
		party_id: String,
		action_label: String) -> void:
	if best_actor.is_empty():
		EventBus.notification_requested.emit({
			"type": "warning", "category": "environment",
			"title": "No one available to operate the door.",
			"duration": 3.0,
		})
		return
	var actor_mv: int = _get_base_movement(best_actor, party_data)
	var ok: bool = _handlers.order_move_and_interact_door(
		best_actor, cell, actor_mv, _controller, scheduler, party_id)
	if not ok:
		EventBus.notification_requested.emit({
			"type": "warning", "category": "environment",
			"title": "%s: cannot reach the door." % action_label,
			"duration": 3.0,
		})
		return
	_start_renderer_animation_for(best_actor, actor_mv)
	# Followers march toward the door.
	var followers: Array = []
	var follower_movements: Dictionary = {}
	for eid in selected:
		var sid: String = str(eid)
		if sid == best_actor:
			continue
		followers.append(sid)
		follower_movements[sid] = _get_base_movement(sid, party_data)
	if not followers.is_empty():
		var ordered: Array = _handlers.order_group_move(
			followers, cell, follower_movements,
			_controller, scheduler, party_id)
		for eid in ordered:
			_start_renderer_animation_for(eid, follower_movements.get(eid, 120))
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
	var map = _controller.get_voxel_map()
	if map == null:
		return

	for cd: CharacterData in party_data.character_data:
		if not cd.is_active:
			continue
		if _session_state.is_exited(cd.id):
			continue  # Successfully exited — not abandoned.
		if not cd.is_dead and not cd.is_incapacitated:
			continue  # Still active — shouldn't happen if all_party_resolved is true.
		var pos = map.get_entity_pos(cd.id)
		if pos == Vector2i(-1, -1) or pos == Vector3i(-1, -1, -1):
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

	var map = _controller.get_voxel_map()
	if map == null:
		return

	var scheduler: EventScheduler = _runner.get_scheduler()
	var party_id: String = _runner.get_party_id()
	var party_data: PartyData = _runner.get_party_data()
	var any_ordered := false

	for eid in exit_queue:
		var exit_cell = exit_queue[eid]
		var entity_id: String = str(eid)

		# Skip if this entity already has an active movement.
		if _handlers.has_active_movement(entity_id):
			continue

		var current_pos = map.get_entity_pos(entity_id)
		if current_pos == Vector2i(-1, -1) or current_pos == Vector3i(-1, -1, -1):
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
func _on_movement_cell_reached(entity_id: String, cell) -> void:
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

		if ptype == "dungeon_encounter_spawned":
			var enc: Dictionary = presentation.get("encounter_data", {})
			if not enc.is_empty():
				_spawn_roaming_encounter(enc)
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

	# Re-evaluate roaming-monster proximity. Combat triggers when any roaming
	# monster has a clear path within attack range to a PC.
	_check_roaming_proximity()

	# Refresh minimap after any state change.
	_update_minimap()


## Check idle behaviors for all entities that have no active orders.
func _check_idle_behaviors() -> void:
	if _session_state == null or _controller == null or _handlers == null or _runner == null:
		return
	var scheduler: EventScheduler = _runner.get_scheduler()
	var party_id: String = _runner.get_party_id()
	var party_data: PartyData = _runner.get_party_data()
	var map = _controller.get_voxel_map()
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
				# Auto-listen at adjacent closed doors. Deferred — the neighbor
				# scan was 2D-only (IsometricGrid.get_neighbors); the voxel port
				# needs a level-aware scan. Tracked as a follow-up behavior port.
				pass
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

## Spawn the encounter's monsters into the dungeon as roaming entities, but
## do NOT enter combat. Combat starts later via _check_roaming_proximity()
## when at least one monster has a clear path within attack range to a PC.
func _spawn_roaming_encounter(encounter_data: Dictionary) -> void:
	if _runner == null or _controller == null or _scene == null:
		return
	var tactical_map: VoxelMapData = _controller.get_voxel_map()
	if tactical_map == null:
		return

	var party_positions: Array[Vector3i] = []
	for eid in _controller.get_entity_ids():
		if tactical_map.entity_positions.has(eid):
			party_positions.append(tactical_map.entity_positions[eid])
	if party_positions.is_empty():
		party_positions.append(_controller.get_party_position_3d())

	var monster_registry = _runner.get_monster_registry()
	var current_level: int = _controller.get_current_level()
	var placements: Array = _spawner.spawn_encounter(
		tactical_map, party_positions, encounter_data, monster_registry, DiceSystem, current_level)
	if placements.is_empty():
		push_warning("DungeonExploreState: roaming spawn failed, skipping encounter")
		return

	# Place tokens + map entities so the renderer shows the monsters.
	for p in placements:
		var combatant_id: String = p["combatant_id"]
		var gp_3d: Vector3i = p["grid_position"]
		tactical_map.set_entity_pos(combatant_id, gp_3d)
		var mname: String = p["monster_data"].get("name", "Monster")
		_scene.add_entity_token(combatant_id, mname, 1, mname.substr(0, 1).to_upper())
		_scene.move_token(combatant_id, gp_3d)

	var enc_id: String = encounter_data.get("encounter_id", "")
	if enc_id.is_empty():
		enc_id = "enc_%d" % Time.get_ticks_msec()
	_roaming_monsters[enc_id] = {
		"encounter_data": encounter_data,
		"placements": placements,
	}

	EventBus.notification_requested.emit({
		"type": "warning", "category": "encounter",
		"title": "Encounter: %d %s nearby!" % [
			encounter_data.get("number", 0),
			encounter_data.get("monster_group", "monsters")],
		"duration": 5.0,
	})

	# Run an immediate check in case the spawn rolled close enough to trigger
	# combat right away. Also covers the case where party is adjacent.
	_check_roaming_proximity()


## Returns true when any roaming monster has a path of length ≤ trigger range
## to a PC, using explore-mode passability (closed unlocked doors permitted,
## locked / stuck / portcullis / undetected secret blocked).
func _check_roaming_proximity() -> void:
	if _in_combat or _roaming_monsters.is_empty():
		return
	if _controller == null or _runner == null:
		return
	var tactical_map: VoxelMapData = _controller.get_voxel_map()
	if tactical_map == null:
		return
	var party_data: PartyData = _runner.get_party_data()
	if party_data == null:
		return

	var party_positions: Array[Vector3i] = []
	for eid in _controller.get_entity_ids():
		if tactical_map.entity_positions.has(eid):
			party_positions.append(tactical_map.entity_positions[eid])
	if party_positions.is_empty():
		return

	var resolver := MovementResolver.new()
	resolver.set_voxel_map(tactical_map)

	for enc_id in _roaming_monsters.keys():
		var entry: Dictionary = _roaming_monsters[enc_id]
		var placements: Array = entry.get("placements", [])
		for p in placements:
			var monster_id: String = p["combatant_id"]
			if not tactical_map.entity_positions.has(monster_id):
				continue
			var monster_pos: Vector3i = tactical_map.entity_positions[monster_id]
			var monster_data: Dictionary = p.get("monster_data", {})
			var move_feet: int = int(monster_data.get("movement", 90))
			var move_cells: int = maxi(1, move_feet / 5)
			var trigger_range: int = move_cells + 1  # one round of approach + one cell to attack
			for pc_pos: Vector3i in party_positions:
				var path: Array = resolver.path_bfs_3d(
					monster_pos, pc_pos, "ground", trigger_range, -1, "explore")
				if not path.is_empty() and path.size() - 1 <= trigger_range:
					_start_dungeon_combat(entry["encounter_data"], placements)
					_roaming_monsters.erase(enc_id)
					return


func _start_dungeon_combat(encounter_data: Dictionary,
		existing_placements: Array = []) -> void:
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

	var tactical_map: VoxelMapData = _controller.get_voxel_map()

	# Gather current party positions (Vector3i; voxel-native)
	var party_positions: Array[Vector3i] = []
	for eid in _controller.get_entity_ids():
		if tactical_map.entity_positions.has(eid):
			party_positions.append(tactical_map.entity_positions[eid])
	if party_positions.is_empty():
		party_positions.append(_controller.get_party_position_3d())

	# Use pre-spawned roaming placements when supplied (deferred combat trigger);
	# otherwise spawn fresh from the encounter data.
	var monster_registry = _runner.get_monster_registry()
	var current_level: int = _controller.get_current_level()
	var placements: Array = existing_placements
	if placements.is_empty():
		placements = _spawner.spawn_encounter(
			tactical_map, party_positions, encounter_data, monster_registry, DiceSystem, current_level)

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
					var placement_3d := Vector3i(placement.x, placement.y, current_level)
					c.grid_position = placement_3d
					tactical_map.set_entity_pos(c.id, placement_3d)
				# Add a token for the creature on the dungeon map.
				var cname: String = c.display_name
				_scene.add_entity_token(c.id, cname, 1, cname.substr(0, 1).to_upper())
				_scene.move_token(c.id, c.grid_position)

	for p in placements:
		var m_combatant := Combatant.from_monster(
			p["monster_data"], p["rolled_hp"], p["combatant_id"], p["group_id"])
		var gp_3d: Vector3i = p["grid_position"]
		m_combatant.grid_position = gp_3d
		roster.add_combatant(m_combatant)
		tactical_map.set_entity_pos(p["combatant_id"], gp_3d)
		var mname: String = p["monster_data"].get("name", "Monster")
		_scene.add_entity_token(p["combatant_id"], mname, 1, mname.substr(0, 1).to_upper())
		_scene.move_token(p["combatant_id"], gp_3d)

	roster.enemy_count_at_start = roster.get_alive_on_side(Combatant.Side.ENEMY).size()

	# Build combat subsystems
	var active_effects: ActiveEffectTracker = _runner.get_active_effects()
	var condition_catalog := ConditionCatalog.new()
	var condition_manager := CombatConditionManager.new(condition_catalog)
	var spell_hooks := SpellCombatHooks.new(active_effects)

	var init_resolver := InitiativeResolver.new(DiceSystem)
	var attack_resolver := AttackResolver.new(DiceSystem, spell_hooks)
	var ranged_resolver := RangedAttackResolver.new(DiceSystem, spell_hooks)

	var movement_resolver := MovementResolver.new(roster)
	movement_resolver.set_voxel_map(tactical_map)
	var monster_ai := MonsterAI.new(roster, DiceSystem, movement_resolver)
	var morale_resolver := MoraleResolver.new(DiceSystem)
	var cleave_resolver := CleaveResolver.new()
	var mortal_wounds_resolver := MortalWoundsResolver.new(DiceSystem)

	_dungeon_combat_controller = CombatController.new(
		roster, init_resolver, attack_resolver,
		spell_hooks, condition_manager, ranged_resolver,
		monster_ai, morale_resolver, cleave_resolver,
		mortal_wounds_resolver, tactical_map)
	_dungeon_combat_controller.encounter_id = encounter_data.get("encounter_id", "")
	# Forward combat-side door changes to the dungeon controller so the renderer
	# refreshes. Combat doesn't own the controller — this state owns both.
	if _controller != null:
		_dungeon_combat_controller.door_state_changed.connect(_controller.door_state_changed.emit)

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
	var tactical_map = _controller.get_voxel_map()
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
	var treasure_types: Array = []
	var loot_cell := Vector3i(-1, -1, -1)
	for c: Combatant in roster.get_all():
		if c.is_enemy_side() and not c.is_alive():
			var tt: String = c._monster_data.get("treasure_type", "None")
			if tt != "None" and not tt.is_empty():
				treasure_types.append(tt)
			if loot_cell == Vector3i(-1, -1, -1):
				if c.grid_position != Vector3i(-1, -1, 0):
					loot_cell = c.grid_position

	if treasure_types.is_empty():
		return
	if loot_cell == Vector3i(-1, -1, -1):
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
	var tactical_map = _controller.get_voxel_map()
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
		var tactical_map = _controller.get_voxel_map() if _controller != null else null
		if tactical_map != null and cache_cell != Vector2i(-1, -1):
			var cache_cell_3d := Vector3i(cache_cell.x, cache_cell.y, _controller.get_current_level())
			tactical_map.set_cell_field(cache_cell_3d, "has_ground_items", false)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _find_creature_placement(
		tactical_map,  # VoxelMapData
		party_positions) -> Vector2i:
	## Find a passable, unoccupied cell adjacent to any party member.
	## Returns Vector2i(-1, -1) if none found. Return type is Vector2i for
	## legacy-caller compatibility; level is dropped.
	for pos in party_positions:
		for neighbor: Vector3i in VoxelGrid.get_neighbors_2d(pos):
			if tactical_map.is_passable(neighbor) and tactical_map.get_entities_at(neighbor).is_empty():
				return Vector2i(neighbor.x, neighbor.y)
	# Fallback: if no free adjacent cell, stack on leader position.
	if not party_positions.is_empty():
		var first = party_positions[0]
		if first is Vector3i:
			return Vector2i(first.x, first.y)
		return first
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
