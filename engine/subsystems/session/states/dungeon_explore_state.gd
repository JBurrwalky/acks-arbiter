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

var _runner = null
var _controller: DungeonMapController = null
var _scene: Node = null
var _combat_overlay: DungeonCombatOverlay = null
var _in_combat: bool = false
var _finalizer := CombatFinalizer.new()
var _spawner := DungeonEncounterSpawner.new()
var _handlers: DungeonHandlers = null

## Current order type from the selection panel.
var _current_order_type: String = "move"


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

	# Create controller
	_controller = DungeonMapController.new()
	_controller.name = "DungeonMapController"
	runner.add_child(_controller)

	# Wire party data for formation placement
	var party_data: PartyData = runner.get_party_data()
	if party_data != null:
		_controller.set_party_data(party_data)

	# Add all active living party members
	if party_data != null:
		for cd: CharacterData in party_data.character_data:
			if not cd.is_dead and cd.is_active:
				_controller.add_party_member(cd.id)
	if _controller.get_entity_ids().is_empty():
		_controller.add_party_member("party_leader")

	_controller.load_dungeon(dungeon_dict, spawn_cell)

	# Save party dungeon position
	CampaignRepository.update_party_dungeon_position(
		runner.get_party_id(),
		_controller.get_dungeon_id(),
		_controller.get_current_level(),
		spawn_cell.x, spawn_cell.y
	)

	# Instantiate and wire dungeon scene
	var packed: PackedScene = preload("res://scenes/maps/dungeon_map.tscn")
	_scene = packed.instantiate()
	_scene.setup(_controller)

	_scene.exit_requested.connect(_on_exit_requested)
	_scene.cell_clicked.connect(_on_cell_clicked)
	_scene.door_interact_requested.connect(_on_door_interact)
	_scene.entity_selected.connect(_on_entity_selected)

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

	# Wire selection panel
	var sel_panel = _scene.get_node_or_null("DungeonHUD/SelectionPanel")
	if sel_panel != null:
		sel_panel.end_turn_pressed.connect(_on_end_turn)
		sel_panel.reform_formation_pressed.connect(_on_reform_formation)
		sel_panel.formation_preset_selected.connect(_on_formation_preset_selected)
		sel_panel.character_selected.connect(_on_panel_character_selected)
		sel_panel.select_all_pressed.connect(_on_select_all)
		sel_panel.order_type_selected.connect(_on_order_type_selected)
		_refresh_selection_panel(sel_panel, party_data)

	# Register dungeon event handlers with the scheduler.
	_handlers = DungeonHandlers.new(runner)
	_handlers.register(runner.get_handler_registry())

	# Listen for scheduler events to detect dungeon encounters.
	if not EventBus.scheduler_event_resolved.is_connected(_on_scheduler_event_resolved):
		EventBus.scheduler_event_resolved.connect(_on_scheduler_event_resolved)

	# Activate a default light source (torch).
	# Future: check party inventory for actual light sources.
	_handlers.activate_light("torch")

	# Seed recurring dungeon events (wandering monster checks, light ticks).
	_handlers.seed_dungeon_events(runner.get_scheduler(), runner.get_party_id())

	# Scheduler starts paused — player issues orders, then unpauses.


func exit(runner) -> void:
	runner.get_nav_stack().pop()

	# Disconnect scheduler event listener.
	if EventBus.scheduler_event_resolved.is_connected(_on_scheduler_event_resolved):
		EventBus.scheduler_event_resolved.disconnect(_on_scheduler_event_resolved)

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

	if is_instance_valid(_controller):
		_controller.queue_free()
	_controller = null
	_scene = null
	_runner = null

	CampaignRepository.clear_party_dungeon_position(runner.get_party_id())

	# Check party time lock (dungeon may have advanced party clock ahead).
	runner.check_party_time_lock()


func handle_action(runner, action: String, payload: Dictionary) -> String:
	match action:
		"exit_dungeon":
			return "wilderness"
		"cancel_movement":
			_cancel_all_movement(runner)
		"cancel_action":
			_cancel_pending_actions(runner)
		"set_movement_mode":
			_change_movement_mode(runner, payload)
		"end_session":
			return "session_end"
	return ""


## Cancel all real-time movement orders. Entities stop at their current cells.
func _cancel_all_movement(runner) -> void:
	if _handlers != null:
		_handlers.cancel_all_moves()
	var party_id: String = runner.get_party_id()
	runner.get_scheduler().cancel_all_for_owner(party_id, "dungeon_movement_tick")
	EventBus.order_cancelled.emit(party_id, "dungeon_move")
	var loop: SchedulerLoop = runner.get_scheduler_loop()
	if loop != null and not loop.is_paused():
		loop.pause()


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
	# Movement speed change takes effect on the next movement tick —
	# no need to cancel and reschedule, since cells_per_round is read
	# dynamically each tick.


# ---------------------------------------------------------------------------
# Cell interaction (real-time movement orders)
# ---------------------------------------------------------------------------

func _on_cell_clicked(pos: Vector2i) -> void:
	if _in_combat or _runner == null or _controller == null:
		return

	var selected: Array[String] = []
	if _scene != null:
		selected = _scene.get_selected_entity_ids()

	var scheduler: EventScheduler = _runner.get_scheduler()
	var party_id: String = _runner.get_party_id()
	var party_data: PartyData = _runner.get_party_data()

	if not selected.is_empty():
		# Issue orders based on current order type.
		match _current_order_type:
			"move":
				_issue_move_orders(selected, pos, party_data, scheduler, party_id)
			"search":
				for eid in selected:
					_handlers.schedule_action("search", eid, pos, DungeonHandlers.TURN_ROUNDS, scheduler, party_id)
				_start_clock_if_paused()
			"listen":
				for eid in selected:
					_handlers.schedule_action("listen", eid, pos, 1, scheduler, party_id)
				_start_clock_if_paused()
			"wait":
				pass  # Explicit no-op, no scheduling needed.

		if _scene != null:
			_scene.update_order_overlay(_controller.get_order_manager().get_all_orders())
		_refresh_order_status()
		return

	# No selection: move all party members to the clicked cell (group move).
	if not _controller.can_move_to(pos):
		return

	var all_ids: Array[String] = []
	for eid in _controller.get_entity_ids():
		all_ids.append(eid)
	_issue_move_orders(all_ids, pos, party_data, scheduler, party_id)


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
		# Determine base movement for this entity.
		var base_mv: int = 120  # default
		if party_data != null:
			var cd: CharacterData = party_data.get_member(eid)
			if cd != null:
				base_mv = cd.get_effective_movement()
		if _handlers.order_move(eid, target, base_mv, _controller, scheduler, party_id):
			any_ordered = true

	if any_ordered:
		_start_clock_if_paused()


func _on_door_interact(pos: Vector2i) -> void:
	if _controller != null:
		_controller.interact_door(pos)


func _on_exit_requested() -> void:
	if _runner != null:
		_runner.transition_to_state("wilderness")


# ---------------------------------------------------------------------------
# Clock control
# ---------------------------------------------------------------------------

## Start the clock at normal speed if currently paused.
func _start_clock_if_paused() -> void:
	var loop: SchedulerLoop = _runner.get_scheduler_loop()
	if loop != null and loop.is_paused():
		loop.resume(SchedulerLoop.SPEED_NORMAL)


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
		if presentation.get("type") == "dungeon_encounter":
			var enc: Dictionary = presentation.get("encounter_data", {})
			if not enc.is_empty():
				_start_dungeon_combat(enc)
				return


# ---------------------------------------------------------------------------
# Selection panel + UI
# ---------------------------------------------------------------------------

func _on_entity_selected(entity_id: String) -> void:
	var sel_panel = _scene.get_node_or_null("DungeonHUD/SelectionPanel") if _scene != null else null
	if sel_panel != null:
		sel_panel.set_selected(entity_id, true)


func _on_panel_character_selected(character_id: String) -> void:
	if _scene != null:
		_scene.select_entity(character_id, false)


func _on_select_all() -> void:
	if _scene != null:
		_scene.select_all_on_side(0)
	var sel_panel = _scene.get_node_or_null("DungeonHUD/SelectionPanel") if _scene != null else null
	if sel_panel != null:
		for eid in _controller.get_entity_ids():
			sel_panel.set_selected(eid, true)


func _on_order_type_selected(order_type: String) -> void:
	_current_order_type = order_type


func _on_end_turn() -> void:
	## "End Turn" convenience: advance the clock by 1 turn (10 minutes).
	## Useful for waiting, resting, or letting time pass without movement.
	if _runner == null or _controller == null or _in_combat:
		return
	var loop: SchedulerLoop = _runner.get_scheduler_loop()
	if loop != null:
		if loop.is_paused():
			loop.resume(SchedulerLoop.SPEED_MAX)
		# The scheduler will advance to the next event (encounter check,
		# light tick, etc.) or sit idle. MAX speed means it happens instantly.


func _on_reform_formation() -> void:
	if _controller == null:
		return
	_controller.reform_formation()
	_controller.get_order_manager().clear()
	if _handlers != null:
		_handlers.cancel_all_moves()
	if _scene != null:
		_scene.clear_order_overlay()
	_refresh_order_status()


func _on_formation_preset_selected(preset_name: String) -> void:
	if _controller == null or _runner == null:
		return
	var party_data: PartyData = _runner.get_party_data()
	if party_data == null:
		return
	var fm: RefCounted = _controller.get_formation_manager()
	var active_chars: Array = []
	for cd: CharacterData in party_data.character_data:
		if not cd.is_dead and cd.is_active:
			active_chars.append(cd)
	fm.apply_preset(preset_name, party_data, active_chars)
	_controller.reform_formation()
	if _scene != null:
		_scene.clear_order_overlay()
	_refresh_order_status()


func _refresh_selection_panel(sel_panel, party_data: PartyData) -> void:
	if sel_panel == null or party_data == null:
		return
	var chars: Array = []
	for cd: CharacterData in party_data.character_data:
		if not cd.is_dead and cd.is_active:
			chars.append({
				"character_id": cd.id,
				"display_name": cd.name,
				"class_letter": _class_letter(cd.character_class),
				"hp_current": cd.hp_current,
				"hp_max": cd.hp_max,
				"order_status": "",
			})
	sel_panel.set_characters(chars)


func _refresh_order_status() -> void:
	var sel_panel = _scene.get_node_or_null("DungeonHUD/SelectionPanel") if _scene != null else null
	if sel_panel == null or _controller == null:
		return
	var om: RefCounted = _controller.get_order_manager()
	for eid in _controller.get_entity_ids():
		var order: Dictionary = om.get_order(eid)
		sel_panel.update_order_status(eid, order.get("order_type", ""))


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

	# Cancel all real-time movement.
	if _handlers != null:
		_handlers.cancel_all_moves()

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

	var combat_controller := CombatController.new(
		roster, init_resolver, attack_resolver,
		spell_hooks, condition_manager, ranged_resolver,
		monster_ai, morale_resolver, cleave_resolver,
		tactical_map, mortal_wounds_resolver)
	combat_controller.encounter_id = encounter_data.get("encounter_id", "")

	EventBus.combat_started.emit(combat_controller.encounter_id)

	_set_dungeon_hud_visible(false)

	_combat_overlay = DungeonCombatOverlay.new()
	_runner.add_child(_combat_overlay)
	_combat_overlay.combat_finished.connect(_on_dungeon_combat_finished)
	_combat_overlay.start_combat(combat_controller, _scene)


func _on_dungeon_combat_finished(result: Dictionary) -> void:
	_in_combat = false

	# Finalize: mortal wounds, XP, timekeeping (party clock + turn rounding).
	var party_data: PartyData = _runner.get_party_data()
	_finalizer.finalize(_runner, result, party_data)

	# Remove monster tokens
	var tactical_map: TacticalMapData = _controller.get_map()
	if tactical_map != null:
		var to_remove: Array = []
		for eid in tactical_map.entity_positions.keys():
			var is_party := false
			if party_data != null:
				for cd: CharacterData in party_data.character_data:
					if cd.id == eid:
						is_party = true
						break
			if not is_party:
				to_remove.append(eid)
		for eid in to_remove:
			tactical_map.remove_entity(eid)
			_scene.remove_entity_token(eid)

	if _combat_overlay != null:
		_combat_overlay.end_combat()
		_combat_overlay = null

	# Remove dead party member tokens
	if party_data != null:
		for cd: CharacterData in party_data.character_data:
			if cd.is_dead:
				if tactical_map != null:
					tactical_map.remove_entity(cd.id)
				_scene.remove_entity_token(cd.id)

	_set_dungeon_hud_visible(true)
	# Scheduler stays paused after combat — player decides when to resume.


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _set_dungeon_hud_visible(vis: bool) -> void:
	if _scene == null:
		return
	var sel_panel = _scene.get_node_or_null("DungeonHUD/SelectionPanel")
	var bottom_bar = _scene.get_node_or_null("DungeonHUD/BottomBar")
	var exit_btn = _scene.get_node_or_null("DungeonHUD/ExitButton")
	if sel_panel != null:
		sel_panel.visible = vis
	if bottom_bar != null:
		bottom_bar.visible = vis
	if exit_btn != null:
		exit_btn.visible = vis


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
