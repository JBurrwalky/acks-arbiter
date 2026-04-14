class_name DungeonHandlers
extends RefCounted

## Event handlers for dungeon exploration (real-time-with-pause at round granularity).
##
## Registered by DungeonExploreState.enter() with the EventHandlerRegistry.
## The dungeon operates on the party clock independently from the overworld.
##
## Movement model: units move continuously as the clock ticks. Each round,
## a movement tick advances all moving entities along their queued paths by
## their cells-per-round rate (based on movement mode and speed). Passive
## detection checks fire for each cell traversed.
##
## Event types handled:
##   "dungeon_movement_tick"    — advance all moving entities (fires every round)
##   "dungeon_encounter_check"  — wandering monster check (every 2 turns)
##   "dungeon_light_tick"       — tick light source tracker (every turn)
##   "dungeon_action_complete"  — a timed activity (search, listen, etc.) resolves


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## 5 feet per cell on the diamond grid.
const FEET_PER_CELL := 5

## Wandering monster check interval: every 2 turns = 120 rounds.
const ENCOUNTER_CHECK_INTERVAL := 120

## One dungeon turn = 60 rounds (10 minutes).
const TURN_ROUNDS := 60

## Movement mode multipliers relative to base combat movement.
## Exploration = 1/3 combat, combat = full, running = 2x combat.
const MODE_EXPLORATION := 1.0 / 3.0
const MODE_COMBAT := 1.0
const MODE_RUNNING := 2.0


# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------

var _runner = null  # SessionRunner
var _light_manager: DungeonLightManager = null

## Active movement orders: { entity_id: { path: Array[Vector2i], progress: float, mode: float } }
var _movement_orders: Dictionary = {}

## Whether a movement tick is currently scheduled (prevents double-scheduling).
var _tick_scheduled: bool = false


func _init(runner) -> void:
	_runner = runner
	_light_manager = DungeonLightManager.new()


# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------

func register(registry: EventHandlerRegistry) -> void:
	registry.register("dungeon_movement_tick", _handle_movement_tick)
	registry.register("dungeon_encounter_check", _handle_encounter_check)
	registry.register("dungeon_light_tick", _handle_light_tick)
	registry.register("dungeon_action_complete", _handle_action_complete)
	registry.register("dungeon_light_action", _handle_light_action)


func unregister(registry: EventHandlerRegistry) -> void:
	registry.unregister("dungeon_movement_tick")
	registry.unregister("dungeon_encounter_check")
	registry.unregister("dungeon_light_tick")
	registry.unregister("dungeon_action_complete")
	registry.unregister("dungeon_light_action")
	_movement_orders.clear()
	_tick_scheduled = false


# ---------------------------------------------------------------------------
# Light source management
# ---------------------------------------------------------------------------

func get_light_manager() -> DungeonLightManager:
	return _light_manager


## Attempt to light a torch for a character. Returns result dict.
func light_torch(character_id: String) -> Dictionary:
	return _light_manager.light_torch(character_id)


## Attempt to light a lantern for a character. Returns result dict.
func light_lantern(character_id: String) -> Dictionary:
	return _light_manager.light_lantern(character_id)


## Douse (extinguish) a character's light source.
func douse_light(character_id: String) -> void:
	_light_manager.douse(character_id)


# ---------------------------------------------------------------------------
# Movement mode
# ---------------------------------------------------------------------------

## Current movement mode multiplier (applied to all entities).
## Individual entity modes can override this in the future.
var _global_movement_mode: float = MODE_EXPLORATION


func set_movement_mode(mode: float) -> void:
	_global_movement_mode = mode


func get_movement_mode() -> float:
	return _global_movement_mode


## Calculate cells-per-round for an entity based on its base movement and mode.
## [param base_movement]: combat movement rate in feet/round (e.g. 120).
## [param mode]: movement mode multiplier (MODE_EXPLORATION, etc.).
func cells_per_round(base_movement: int, mode: float = -1.0) -> float:
	if mode < 0.0:
		mode = _global_movement_mode
	var feet_per_round: float = float(base_movement) * mode
	return feet_per_round / float(FEET_PER_CELL)


# ---------------------------------------------------------------------------
# Scheduling helpers (called by DungeonExploreState)
# ---------------------------------------------------------------------------

## Schedule the initial recurring events when entering a dungeon.
func seed_dungeon_events(scheduler: EventScheduler, party_id: String) -> void:
	var current_time: int = Timekeeping.get_party_time(party_id)

	# Wandering monster check every 2 turns
	scheduler.schedule_at(
		current_time + ENCOUNTER_CHECK_INTERVAL,
		"dungeon_encounter_check",
		party_id,
		{},
		ScheduledEvent.PRIORITY_SCHEDULED_CHECK,
	)

	# Light source tick every turn (if any entity has active light)
	if _light_manager.has_any_light():
		scheduler.schedule_at(
			current_time + TURN_ROUNDS,
			"dungeon_light_tick",
			party_id,
			{},
			ScheduledEvent.PRIORITY_ENVIRONMENTAL,
		)


## Issue a movement order for an entity. Computes BFS path via the controller.
## Cancels any existing movement for this entity. If no entities were moving,
## schedules the first movement tick.
func order_move(
	entity_id: String,
	target: Vector2i,
	base_movement: int,
	controller: DungeonMapController,
	scheduler: EventScheduler,
	party_id: String,
) -> bool:
	# Cancel existing movement for this entity.
	_movement_orders.erase(entity_id)

	# Compute path via the controller's BFS.
	if not controller.queue_move_order(entity_id, target):
		return false

	# Extract the path from the order manager.
	var om: RefCounted = controller.get_order_manager()
	var order: Dictionary = om.get_order(entity_id)
	var path: Array = order.get("path", [])
	om.remove_order(entity_id)  # We manage movement ourselves now.

	if path.is_empty():
		return false

	_movement_orders[entity_id] = {
		"path": path,
		"progress": 0.0,  # fractional cell index along path
		"base_movement": base_movement,
	}

	# Schedule a movement tick if one isn't already pending.
	_ensure_movement_tick(scheduler, party_id)
	EventBus.order_queued.emit(party_id, "dungeon_move", 0)
	return true


## Cancel movement for an entity. Returns true if it had a movement order.
func cancel_move(entity_id: String) -> bool:
	return _movement_orders.erase(entity_id)


## Cancel all movement orders.
func cancel_all_moves() -> void:
	_movement_orders.clear()


## Returns true if any entity currently has a movement order.
## If [param entity_id] is provided, checks only that entity.
func has_active_movement(entity_id: String = "") -> bool:
	if entity_id.is_empty():
		return not _movement_orders.is_empty()
	return _movement_orders.has(entity_id)


## Schedule a timed dungeon action (search, listen, door interact, etc.).
## [param duration_rounds]: how long the action takes (search=60, listen=1).
func schedule_action(
	action_type: String,
	entity_id: String,
	cell: Vector2i,
	duration_rounds: int,
	scheduler: EventScheduler,
	party_id: String,
) -> String:
	var current_time: int = Timekeeping.get_party_time(party_id)
	return scheduler.schedule_at(
		current_time + duration_rounds,
		"dungeon_action_complete",
		party_id,
		{
			"action_type": action_type,
			"entity_id": entity_id,
			"cell_x": cell.x,
			"cell_y": cell.y,
		},
		ScheduledEvent.PRIORITY_ARRIVAL,
	)


# ---------------------------------------------------------------------------
# Event handlers
# ---------------------------------------------------------------------------

## Advance all moving entities along their paths. Fires every round while
## any entity is moving. Checks for passive detection at each cell traversed.
func _handle_movement_tick(event: ScheduledEvent) -> Dictionary:
	_tick_scheduled = false
	var controller: DungeonMapController = _find_dungeon_controller()
	if controller == null:
		_movement_orders.clear()
		return {}

	var tactical_map: TacticalMapData = controller.get_map()
	if tactical_map == null:
		_movement_orders.clear()
		return {}

	var completed_entities: Array = []
	var encounter_triggered: bool = false
	var encounter_data: Dictionary = {}

	for entity_id in _movement_orders.keys():
		var order: Dictionary = _movement_orders[entity_id]
		var path: Array = order["path"]
		var progress: float = order["progress"]
		var base_mv: int = order["base_movement"]
		var cpr: float = cells_per_round(base_mv)

		# Advance progress by cells_per_round.
		progress += cpr
		var old_cell_index: int = int(order["progress"])
		var new_cell_index: int = mini(int(progress), path.size() - 1)

		# Move through each cell between old and new position.
		for ci in range(old_cell_index, new_cell_index + 1):
			if ci >= path.size():
				break
			var cell: Vector2i = path[ci]
			# Move entity to this cell on the tactical map.
			if tactical_map.is_passable(cell):
				var old_pos := tactical_map.get_entity_pos(entity_id)
				tactical_map.set_entity_pos(entity_id, cell)
				controller.entity_moved.emit(entity_id, old_pos, cell)
			else:
				# Path blocked — cancel this entity's movement.
				completed_entities.append(entity_id)
				break

			# TODO: passive detection checks (dwarf/elf) for secret features
			# at this cell would fire here in the future.

		order["progress"] = progress

		# Check if entity reached end of path.
		if progress >= path.size() - 1:
			completed_entities.append(entity_id)

	# Remove completed entities.
	for eid in completed_entities:
		_movement_orders.erase(eid)

	# Update fog of war after all movements.
	if not completed_entities.is_empty() or _movement_orders.size() > 0:
		controller._update_fog_for_all_members()

	# Build result.
	var result := {}

	# Schedule next movement tick if entities are still moving.
	if not _movement_orders.is_empty():
		result["next_events"] = [{
			"fire_time": event.fire_time + 1,
			"event_type": "dungeon_movement_tick",
			"owner_id": event.owner_id,
			"data": {},
			"priority": ScheduledEvent.PRIORITY_ARRIVAL,
		}]
		_tick_scheduled = true
	else:
		# All movement complete — auto-pause so player can issue new orders.
		result["auto_pause"] = true
		result["pause_reason"] = "Movement complete"

	if not completed_entities.is_empty():
		result["presentation"] = {
			"type": "dungeon_movement_complete",
			"completed_entities": completed_entities,
		}

	return result


## Wandering monster check — fires every 2 turns per ACKS rules.
func _handle_encounter_check(event: ScheduledEvent) -> Dictionary:
	var encounter: Dictionary = _runner.do_encounter_check(null)

	# Always reschedule the next check.
	var next_events := [{
		"fire_time": event.fire_time + ENCOUNTER_CHECK_INTERVAL,
		"event_type": "dungeon_encounter_check",
		"owner_id": event.owner_id,
		"data": {},
		"priority": ScheduledEvent.PRIORITY_SCHEDULED_CHECK,
	}]

	if encounter.get("triggered", false):
		var enc: Dictionary = encounter["encounter_data"]
		# Cancel all movement — combat interrupts.
		_movement_orders.clear()
		return {
			"auto_pause": true,
			"pause_reason": "Wandering monster: %d x %s" % [
				enc.get("number", 0), enc.get("monster_group", "unknown")],
			"next_events": next_events,
			"presentation": {
				"type": "dungeon_encounter",
				"encounter_data": enc,
			},
		}

	return {"next_events": next_events}


## Tick all active light sources via the DungeonLightManager.
## Handles warnings, expiry, auto-refuel, auto-relight, and darkness.
func _handle_light_tick(event: ScheduledEvent) -> Dictionary:
	var tick_events: Array[Dictionary] = _light_manager.tick_all()

	var result := {}
	var should_pause := false
	var pause_reason := ""
	var has_darkness := false

	# Process tick events into notifications and pause triggers.
	for te in tick_events:
		var te_type: String = te.get("type", "")
		var message: String = te.get("message", "")
		match te_type:
			"warning":
				EventBus.notification_requested.emit({
					"type": "warning",
					"category": "light",
					"title": message,
					"duration": 5.0,
				})
			"expired":
				should_pause = true
				pause_reason = message
				EventBus.notification_requested.emit({
					"type": "danger",
					"category": "light",
					"title": message,
					"duration": 0.0,
				})
			"refueled":
				EventBus.notification_requested.emit({
					"type": "info",
					"category": "light",
					"title": message,
					"duration": 4.0,
				})
			"auto_lit":
				EventBus.notification_requested.emit({
					"type": "info",
					"category": "light",
					"title": message,
					"duration": 4.0,
				})
			"darkness":
				has_darkness = true

	# If total darkness (no light sources remaining), cancel movement and pause.
	if has_darkness and not _light_manager.has_any_light():
		_movement_orders.clear()
		should_pause = true
		if pause_reason.is_empty():
			pause_reason = "Total darkness — no light sources!"

	if should_pause:
		result["auto_pause"] = true
		result["pause_reason"] = pause_reason

	# Reschedule next tick if any light sources are still active.
	if _light_manager.has_any_light():
		result["next_events"] = [{
			"fire_time": event.fire_time + TURN_ROUNDS,
			"event_type": "dungeon_light_tick",
			"owner_id": event.owner_id,
			"data": {},
			"priority": ScheduledEvent.PRIORITY_ENVIRONMENTAL,
		}]

	# Evil door auto-close: every turn tick, all open evil doors that are not
	# wedged or spiked swing shut automatically (per GDD §3.2.1).
	var controller: DungeonMapController = _find_dungeon_controller()
	if controller != null:
		var tmap: TacticalMapData = controller.get_map()
		if tmap != null:
			for pos in tmap._cells.keys():
				if tmap.is_evil_door(pos) and tmap.get_door_state(pos) == "open":
					# TODO: check wedged/spiked state when spike system is built.
					tmap.set_door_state(pos, "closed")
					EventBus.notification_requested.emit({
						"type": "warning",
						"category": "environment",
						"title": "An evil door swings shut!",
						"duration": 4.0,
					})

	# Update fog (light radius may have changed).
	if controller != null:
		controller._update_fog_for_all_members()

	return result


## A timed dungeon action completes (search, listen, door force, etc.).
func _handle_action_complete(event: ScheduledEvent) -> Dictionary:
	var action_type: String = event.data.get("action_type", "")
	var entity_id: String = event.data.get("entity_id", "")
	var cell := Vector2i(
		int(event.data.get("cell_x", 0)),
		int(event.data.get("cell_y", 0)))

	match action_type:
		"search":
			return _resolve_search(entity_id, cell)
		"listen":
			return _resolve_listen(entity_id, cell)
		"force_door":
			return _resolve_force_door(entity_id, cell)
		_:
			return {
				"auto_pause": true,
				"pause_reason": "%s complete" % action_type,
			}


# ---------------------------------------------------------------------------
# Action resolution
# ---------------------------------------------------------------------------

func _resolve_search(entity_id: String, cell: Vector2i) -> Dictionary:
	var roll: RollResult = DiceSystem.roll_digital(6, 1, 0, "search")
	var found: bool = roll.modified_total <= 1
	return {
		"auto_pause": true,
		"pause_reason": "Search complete" + (" — found something!" if found else " — nothing found"),
		"presentation": {
			"type": "dungeon_search_complete",
			"entity_id": entity_id,
			"cell": str(cell),
			"roll": roll.modified_total,
			"found": found,
		},
	}


func _resolve_listen(entity_id: String, cell: Vector2i) -> Dictionary:
	var roll: RollResult = DiceSystem.roll_digital(6, 1, 0, "listen")
	var heard: bool = roll.modified_total <= 1
	return {
		"auto_pause": true,
		"pause_reason": "Listen complete" + (" — heard something!" if heard else " — silence"),
		"presentation": {
			"type": "dungeon_listen_complete",
			"entity_id": entity_id,
			"cell": str(cell),
			"roll": roll.modified_total,
			"heard": heard,
		},
	}


func _resolve_force_door(entity_id: String, cell: Vector2i) -> Dictionary:
	# Force stuck door: d20 vs modified target (usually 18+).
	var roll: RollResult = DiceSystem.roll_digital(20, 1, 0, "force_door")
	var forced: bool = roll.modified_total >= 18
	return {
		"auto_pause": true,
		"pause_reason": "Door " + ("forced open!" if forced else "held fast"),
		"presentation": {
			"type": "dungeon_force_door",
			"entity_id": entity_id,
			"cell": str(cell),
			"roll": roll.modified_total,
			"forced": forced,
		},
	}


## Player-initiated light/douse action (takes 1 round to light with tinderbox).
func _handle_light_action(event: ScheduledEvent) -> Dictionary:
	var action: String = event.data.get("action", "")  # "light_torch", "light_lantern", "douse"
	var character_id: String = event.data.get("character_id", "")

	var result_dict: Dictionary
	match action:
		"light_torch":
			result_dict = _light_manager.light_torch(character_id)
		"light_lantern":
			result_dict = _light_manager.light_lantern(character_id)
		"douse":
			_light_manager.douse(character_id)
			result_dict = {"success": true, "message": "Light source doused."}
		_:
			result_dict = {"success": false, "message": "Unknown light action."}

	var succeeded: bool = result_dict.get("success", false)

	# If we just lit something and no light tick is scheduled, start one.
	if succeeded and action != "douse":
		var scheduler: EventScheduler = _runner.get_scheduler()
		var party_id: String = _runner.get_party_id()
		# Check if a light tick is already scheduled.
		var has_tick := false
		for ev in scheduler.get_events_for_owner(party_id):
			if ev.event_type == "dungeon_light_tick":
				has_tick = true
				break
		if not has_tick:
			var current_time: int = Timekeeping.get_party_time(party_id)
			scheduler.schedule_at(
				current_time + TURN_ROUNDS,
				"dungeon_light_tick",
				party_id,
				{},
				ScheduledEvent.PRIORITY_ENVIRONMENTAL,
			)

	# Update fog after light change.
	var controller: DungeonMapController = _find_dungeon_controller()
	if controller != null:
		controller._update_fog_for_all_members()

	if not succeeded:
		EventBus.notification_requested.emit({
			"type": "warning",
			"category": "light",
			"title": result_dict.get("message", "Cannot light."),
			"duration": 4.0,
		})

	return {
		"auto_pause": true,
		"pause_reason": result_dict.get("message", ""),
	}


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

## Ensure a movement tick is scheduled for the next round.
func _ensure_movement_tick(scheduler: EventScheduler, party_id: String) -> void:
	if _tick_scheduled:
		return
	var current_time: int = Timekeeping.get_party_time(party_id)
	scheduler.schedule_at(
		current_time + 1,
		"dungeon_movement_tick",
		party_id,
		{},
		ScheduledEvent.PRIORITY_ARRIVAL,
	)
	_tick_scheduled = true


func _find_dungeon_controller() -> DungeonMapController:
	if _runner == null:
		return null
	for child in _runner.get_children():
		if child is DungeonMapController:
			return child
	return null
