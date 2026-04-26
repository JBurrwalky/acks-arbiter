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
var _session_state: RefCounted = null  # DungeonSessionState (set by DungeonExploreState)

## Active movement orders: { entity_id: { path: Array[Vector2i], progress: float, mode: float } }
var _movement_orders: Dictionary = {}

## Entities whose movement is driven by the renderer's continuous animation
## rather than the scheduler tick. The tick skips position advancement for these.
var _renderer_animated: Dictionary = {}  # { entity_id: true }

## Whether a movement tick is currently scheduled (prevents double-scheduling).
var _tick_scheduled: bool = false


func _init(runner) -> void:
	_runner = runner
	_light_manager = DungeonLightManager.new()


## Set the per-visit session state (for pick lock tracking).
func set_session_state(state: RefCounted) -> void:
	_session_state = state


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
	_renderer_animated.clear()
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
	target,  # Vector2i or Vector3i
	base_movement: int,
	controller: DungeonMapController,
	scheduler: EventScheduler,
	party_id: String,
) -> bool:
	# A character moving releases any held portcullis.
	_release_held_portcullises(entity_id)

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


## Issue a group move: all entities head toward [param target]. Followers
## scatter to unclaimed cells around the target (ring-search up to 4 cells)
## to prevent final-cell stacking. Returns the list of entity_ids that were
## successfully ordered. Voxel mode only — legacy path falls back to per-entity
## [method order_move] via the caller.
func order_group_move(
	entity_ids: Array,
	target,
	base_movements: Dictionary,  # entity_id -> base_movement
	controller: DungeonMapController,
	scheduler: EventScheduler,
	party_id: String,
) -> Array:
	if entity_ids.is_empty():
		return []

	for eid in entity_ids:
		_release_held_portcullises(eid)
		_movement_orders.erase(eid)

	# Seed the controller's party list so queue_group_move's leader/follower
	# split matches the intended ordering (first selected = leader).
	var prev_party_ids: Array = controller._party_entity_ids.duplicate()
	var typed_ids: Array[String] = []
	for eid in entity_ids:
		typed_ids.append(str(eid))
	controller._party_entity_ids = typed_ids

	var ok: bool = controller.queue_group_move(target)
	# Restore the real party list so downstream systems see the full roster.
	controller._party_entity_ids = prev_party_ids

	if not ok:
		return []

	var om: RefCounted = controller.get_order_manager()
	var ordered: Array = []
	for eid in entity_ids:
		var sid: String = str(eid)
		var order: Dictionary = om.get_order(sid)
		if order.is_empty():
			continue
		var order_type: String = order.get("order_type", "")
		var path: Array = order.get("path", [])
		om.remove_order(sid)

		if order_type != "move" or path.is_empty():
			continue

		_movement_orders[sid] = {
			"path": path,
			"progress": 0.0,
			"base_movement": base_movements.get(sid, 120),
		}
		ordered.append(sid)

	if not ordered.is_empty():
		_ensure_movement_tick(scheduler, party_id)
		EventBus.order_queued.emit(party_id, "dungeon_move", 0)

	return ordered


## Order a compound "move to adjacent cell + interact with door" action.
## The entity moves along the precomputed path; on arrival, auto-interacts with the door.
func order_move_and_interact_door(
	entity_id: String,
	door_pos,  # Vector2i or Vector3i
	base_movement: int,
	controller: DungeonMapController,
	scheduler: EventScheduler,
	party_id: String,
) -> bool:
	_movement_orders.erase(entity_id)

	# Use the controller's compound order which already computed the path.
	var result := controller.queue_door_interaction_order(entity_id, door_pos)
	if result == "immediate":
		return true  # Door was already interacted with
	if result != "queued":
		return false

	# Extract the path from the order manager.
	var om: RefCounted = controller.get_order_manager()
	var order: Dictionary = om.get_order(entity_id)
	var path: Array = order.get("path", [])
	om.remove_order(entity_id)

	if path.is_empty():
		return false

	_movement_orders[entity_id] = {
		"path": path,
		"progress": 0.0,
		"base_movement": base_movement,
		"on_arrival": {"action": "interact_door", "target": door_pos},
	}

	_ensure_movement_tick(scheduler, party_id)
	EventBus.order_queued.emit(party_id, "dungeon_move", 0)
	return true


## Order a compound "move to target site + on arrival, schedule a timed action."
## When [param adjacent_only] is true (the default for door/lever-side actions),
## the actor walks to a passable cell adjacent to [param target_cell] and the
## action fires from there. When false (search/listen/etc.), the actor walks
## INTO the target cell first.
##
## If the actor is already at the action site, the action is scheduled
## immediately and no movement is queued.
func order_move_and_schedule_action(
		entity_id: String,
		target_cell,  # Vector2i or Vector3i
		action_type: String,
		duration_rounds: int,
		base_movement: int,
		controller: DungeonMapController,
		scheduler: EventScheduler,
		party_id: String,
		adjacent_only: bool = true) -> bool:
	_movement_orders.erase(entity_id)

	var result: String
	if adjacent_only:
		result = controller.queue_move_adjacent_to(entity_id, target_cell)
	else:
		# On-cell flavor: pathfind into the target cell itself.
		var ok: bool = controller.queue_move_order(entity_id, target_cell)
		if ok:
			result = "queued"
		else:
			var vmap = controller.get_voxel_map()
			var here = vmap.get_entity_pos(entity_id) if vmap != null else null
			var target_3d: Vector3i = target_cell if target_cell is Vector3i else \
				Vector3i(target_cell.x, target_cell.y, controller.get_current_level())
			result = "immediate" if here == target_3d else ""

	if result == "immediate":
		schedule_action(action_type, entity_id, target_cell, duration_rounds,
			scheduler, party_id)
		return true
	if result != "queued":
		return false

	var om: RefCounted = controller.get_order_manager()
	var order: Dictionary = om.get_order(entity_id)
	var path: Array = order.get("path", [])
	om.remove_order(entity_id)
	if path.is_empty():
		return false

	_movement_orders[entity_id] = {
		"path": path,
		"progress": 0.0,
		"base_movement": base_movement,
		"on_arrival": {
			"action": "schedule_action",
			"action_type": action_type,
			"target": target_cell,
			"duration_rounds": duration_rounds,
			"party_id": party_id,
		},
	}
	_ensure_movement_tick(scheduler, party_id)
	EventBus.order_queued.emit(party_id, "dungeon_move", 0)
	return true


## Cancel movement for an entity. Returns true if it had a movement order.
func cancel_move(entity_id: String) -> bool:
	return _movement_orders.erase(entity_id)


## Cancel all movement orders.
func cancel_all_moves() -> void:
	_movement_orders.clear()
	_renderer_animated.clear()


## Returns true if any entity currently has a movement order.
## If [param entity_id] is provided, checks only that entity.
func has_active_movement(entity_id: String = "") -> bool:
	if entity_id.is_empty():
		return not _movement_orders.is_empty()
	return _movement_orders.has(entity_id)


# ---------------------------------------------------------------------------
# Renderer-driven animation support
# ---------------------------------------------------------------------------

## Mark an entity as renderer-animated (tick handler skips position updates).
func mark_renderer_animated(entity_id: String) -> void:
	_renderer_animated[entity_id] = true


## Clear renderer-animated flag for one entity.
func clear_renderer_animated(entity_id: String) -> void:
	_renderer_animated.erase(entity_id)


## Clear all renderer-animated flags.
func clear_all_renderer_animated() -> void:
	_renderer_animated.clear()


## Called by DungeonExploreState when the renderer's tween reaches a new cell.
## Updates the mechanical position, fog, and checks for passability/completion.
## Returns a result dict: { blocked: bool, path_complete: bool, all_complete: bool }
func on_cell_reached(entity_id: String, cell) -> Dictionary:  # cell: Vector2i or Vector3i
	if not _movement_orders.has(entity_id):
		return {"error": true}

	var controller: DungeonMapController = _find_dungeon_controller()
	if controller == null:
		return {"error": true}
	var tactical_map = controller.get_voxel_map()
	if tactical_map == null:
		return {"error": true}

	var order: Dictionary = _movement_orders[entity_id]

	# Auto-open closed unlocked doors as the entity walks through. Locked,
	# stuck, secret-undetected, and portcullis doors are not auto-handled —
	# is_walkable_with_open_door() rejects them at path-planning time, so they
	# never appear in the path.
	_auto_open_door_if_walking_through(controller, tactical_map, cell)

	# Check passability before committing the move.
	if not tactical_map.is_passable(cell):
		cancel_move(entity_id)
		clear_renderer_animated(entity_id)
		return {"blocked": true}

	# No-stacking: block if this is the FINAL cell and another entity is there.
	# Intermediate cells allow pass-through (allies move through each other).
	var path: Array = order["path"]
	var next_mech_idx: int = order.get("mechanical_index", -1) + 1
	if next_mech_idx >= path.size() - 1:
		if tactical_map.is_occupied_by_other(cell, entity_id):
			cancel_move(entity_id)
			clear_renderer_animated(entity_id)
			return {"blocked": true}

	# Commit the mechanical position update.
	# old_pos is Vector2i (legacy TacticalMapData) or Vector3i (VoxelMapData).
	var old_pos = tactical_map.get_entity_pos(entity_id)
	tactical_map.set_entity_pos(entity_id, cell)
	# Emit entity_moved (renderer ignores via _active_movements guard).
	controller.entity_moved.emit(entity_id, old_pos, cell)

	# If the party leader crossed to a new level (e.g. stair traversal in voxel
	# mode), notify the controller so VisibilityManager's focus can follow.
	if old_pos is Vector3i and cell is Vector3i:
		var party_ids: Array = controller.get_entity_ids()
		if not party_ids.is_empty() and party_ids[0] == entity_id and old_pos.z != cell.z:
			controller._current_level = cell.z
			controller.level_changed.emit(old_pos.z, cell.z)

	# Update fog of war.
	controller._update_fog_for_all_members()

	# Track mechanical progress along the path.
	var mech_idx: int = order.get("mechanical_index", -1) + 1
	order["mechanical_index"] = mech_idx

	# Check if entity reached end of path.
	if mech_idx >= path.size() - 1:
		# Path complete — handle on_arrival callbacks and remove order.
		var on_arrival: Dictionary = order.get("on_arrival", {})
		_movement_orders.erase(entity_id)
		_renderer_animated.erase(entity_id)

		if not on_arrival.is_empty() and controller != null:
			var action: String = on_arrival.get("action", "")
			var target = on_arrival.get("target", Vector2i(-1, -1))  # Vector2i or Vector3i
			match action:
				"interact_door":
					controller.interact_door(target)
				"schedule_action":
					var sa_type: String = on_arrival.get("action_type", "")
					var sa_dur: int = int(on_arrival.get("duration_rounds", 1))
					var sa_pid: String = on_arrival.get("party_id", "")
					var sa_scheduler: EventScheduler = _runner.get_scheduler() if _runner != null else null
					if not sa_type.is_empty() and sa_scheduler != null and not sa_pid.is_empty():
						schedule_action(sa_type, entity_id, target, sa_dur, sa_scheduler, sa_pid)

		return {
			"path_complete": true,
			"all_complete": _movement_orders.is_empty(),
		}

	return {}


## Auto-open a closed unlocked door at [param cell] when an entity walks into
## it during exploration. Locked / stuck / portcullis / secret-undetected doors
## are filtered out at path-planning time (is_walkable_with_open_door rejects
## them) so they never reach this helper. The 1-round opening cost is only
## enforced in combat — see CombatController._resolve_door_interaction.
func _auto_open_door_if_walking_through(
		controller: DungeonMapController,
		tactical_map,
		cell) -> void:
	if controller == null or tactical_map == null:
		return
	if not tactical_map.is_door(cell):
		return
	if tactical_map.get_door_state(cell) != "closed":
		return
	# Spike-shut and wedged doors are tracked outside the cell state; bail if
	# the session marks this door immobile so we don't silently override.
	if _session_state != null and _session_state.has_method("is_spiked") \
			and _session_state.is_spiked(cell):
		return
	tactical_map.set_door_state(cell, "open")
	controller.door_state_changed.emit(cell, "closed", "open")


## Schedule a timed dungeon action (search, listen, door interact, etc.).
## [param duration_rounds]: how long the action takes (search=60, listen=1).
func schedule_action(
	action_type: String,
	entity_id: String,
	cell,  # Vector2i or Vector3i
	duration_rounds: int,
	scheduler: EventScheduler,
	party_id: String,
) -> String:
	# A character performing any action releases any held portcullis.
	_release_held_portcullises(entity_id)

	# Serialize the cell coordinate — include level (z) when present so voxel
	# mode round-trips correctly. Vector2i has no z, so we mark it absent.
	var data: Dictionary = {
		"action_type": action_type,
		"entity_id": entity_id,
		"cell_x": cell.x,
		"cell_y": cell.y,
	}
	if cell is Vector3i:
		data["cell_z"] = cell.z
		data["cell_is_3d"] = true

	var current_time: int = Timekeeping.get_party_time(party_id)
	return scheduler.schedule_at(
		current_time + duration_rounds,
		"dungeon_action_complete",
		party_id,
		data,
		ScheduledEvent.PRIORITY_ARRIVAL,
	)


# ---------------------------------------------------------------------------
# Event handlers
# ---------------------------------------------------------------------------

## Advance all moving entities along their paths. Fires every round while
## any entity is moving.
##
## At normal/fast/very-fast speeds, renderer-animated entities are skipped
## (the renderer drives their position updates via on_cell_reached callbacks).
## At MAX speed the renderer is disabled, so this handler runs the original
## burst-advance logic for all entities.
func _handle_movement_tick(event: ScheduledEvent) -> Dictionary:
	_tick_scheduled = false
	var controller: DungeonMapController = _find_dungeon_controller()
	if controller == null:
		_movement_orders.clear()
		return {}

	var tactical_map = controller.get_voxel_map()
	if tactical_map == null:
		_movement_orders.clear()
		return {}

	# Determine if we're in MAX speed (renderer is disabled).
	var is_max_speed: bool = false
	var loop: SchedulerLoop = _runner.get_scheduler_loop() if _runner != null else null
	if loop != null and loop.get_speed() == SchedulerLoop.SPEED_MAX:
		is_max_speed = true

	var completed_entities: Array = []

	for entity_id in _movement_orders.keys():
		# At non-MAX speeds, skip entities whose animation is renderer-driven.
		if not is_max_speed and _renderer_animated.has(entity_id):
			continue

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
		var stopped_early := false
		for ci in range(old_cell_index, new_cell_index + 1):
			if ci >= path.size():
				break
			var cell = path[ci]  # Vector2i or Vector3i
			# Auto-open closed unlocked doors mid-traversal.
			_auto_open_door_if_walking_through(controller, tactical_map, cell)
			if not tactical_map.is_passable(cell):
				completed_entities.append(entity_id)
				stopped_early = true
				break
			# No-stacking: block on the final cell if occupied by another.
			# Intermediate cells allow pass-through.
			if ci >= path.size() - 1 and tactical_map.is_occupied_by_other(cell, entity_id):
				completed_entities.append(entity_id)
				stopped_early = true
				break
			var old_pos := tactical_map.get_entity_pos(entity_id)
			tactical_map.set_entity_pos(entity_id, cell)
			controller.entity_moved.emit(entity_id, old_pos, cell)

			# TODO: passive detection checks (dwarf/elf) for secret features
			# at this cell would fire here in the future.
		if stopped_early:
			continue

		order["progress"] = progress

		if progress >= path.size() - 1:
			completed_entities.append(entity_id)

	# Remove completed entities and execute any on_arrival callbacks.
	for eid in completed_entities:
		var order: Dictionary = _movement_orders.get(eid, {})
		var on_arrival: Dictionary = order.get("on_arrival", {})
		_movement_orders.erase(eid)
		_renderer_animated.erase(eid)

		if not on_arrival.is_empty() and controller != null:
			var action: String = on_arrival.get("action", "")
			var target = on_arrival.get("target", Vector2i(-1, -1))  # Vector2i or Vector3i
			match action:
				"interact_door":
					controller.interact_door(target)
				"schedule_action":
					var sa_type: String = on_arrival.get("action_type", "")
					var sa_dur: int = int(on_arrival.get("duration_rounds", 1))
					var sa_pid: String = on_arrival.get("party_id", "")
					var sa_scheduler: EventScheduler = _runner.get_scheduler() if _runner != null else null
					if not sa_type.is_empty() and sa_scheduler != null and not sa_pid.is_empty():
						schedule_action(sa_type, eid, target, sa_dur, sa_scheduler, sa_pid)

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
	# Fetch the dungeon's local wandering monster table if one is defined —
	# scopes the roll to a curated per-dungeon catalog instead of every monster
	# in the registry.
	var local_table: Array = []
	var enc_ctrl: DungeonMapController = _find_dungeon_controller()
	if enc_ctrl != null and enc_ctrl.has_map():
		var vmap = enc_ctrl.get_voxel_map()
		if vmap != null and "wandering_monster_table" in vmap:
			local_table = vmap.wandering_monster_table

	var encounter: Dictionary = _runner.do_encounter_check(null, local_table)

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
		# Cancel all movement — surprise pauses real-time exploration.
		_movement_orders.clear()
		# Auto-focus the camera on the party leader's level if the encounter
		# happens on a non-focus level. Reuses the controller already fetched
		# above when resolving the wandering-monster table.
		if enc_ctrl != null:
			var leader_pos: Vector3i = enc_ctrl.get_party_position_3d()
			EventBus.dungeon_auto_focus_requested.emit(leader_pos.z, "encounter")
		# Spawn-only presentation — DungeonExploreState places the monsters as
		# roaming entities and runs proximity ticks until they reach attack
		# range, at which point combat starts.
		return {
			"auto_pause": true,
			"pause_reason": "Wandering monster: %d x %s" % [
				enc.get("number", 0), enc.get("monster_group", "unknown")],
			"next_events": next_events,
			"presentation": {
				"type": "dungeon_encounter_spawned",
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
		var tmap = controller.get_voxel_map()
		if tmap != null:
			for pos in tmap._cells.keys():
				if tmap.is_evil_door(pos) and tmap.get_door_state(pos) == "open":
					# Wedged doors resist evil auto-close.
					if _session_state != null and _session_state.has_method("is_wedged") \
							and _session_state.is_wedged(pos):
						continue
					tmap.set_door_state(pos, "closed")
					controller.door_state_changed.emit(pos, "open", "closed")
					EventBus.notification_requested.emit({
						"type": "warning",
						"category": "environment",
						"title": "An evil door swings shut!",
						"duration": 4.0,
					})
					EventBus.dungeon_auto_focus_requested.emit(pos.z, "evil_door_close")

	# Update fog (light radius may have changed).
	if controller != null:
		controller._update_fog_for_all_members()

	return result


## A timed dungeon action completes (search, listen, door force, etc.).
func _handle_action_complete(event: ScheduledEvent) -> Dictionary:
	var action_type: String = event.data.get("action_type", "")
	var entity_id: String = event.data.get("entity_id", "")
	# Reconstruct as Vector3i when the scheduled event carries a level (voxel
	# mode); otherwise fall back to Vector2i (legacy TacticalMapData).
	var cell
	if event.data.get("cell_is_3d", false):
		cell = Vector3i(
			int(event.data.get("cell_x", 0)),
			int(event.data.get("cell_y", 0)),
			int(event.data.get("cell_z", 0)))
	else:
		cell = Vector2i(
			int(event.data.get("cell_x", 0)),
			int(event.data.get("cell_y", 0)))

	match action_type:
		"search":
			return _resolve_search(entity_id, cell)
		"listen", "listen_at_door":
			return _resolve_listen(entity_id, cell)
		"force_door":
			return _resolve_force_door(entity_id, cell)
		"bash_door":
			return _resolve_bash_door(entity_id, cell)
		"pick_lock":
			return _resolve_pick_lock(entity_id, cell)
		"use_lever":
			return _resolve_use_lever(entity_id, cell)
		"force_portcullis":
			return _resolve_force_portcullis(entity_id, cell)
		"drop_portcullis":
			return _resolve_drop_portcullis(entity_id, cell)
		"spike_shut":
			return _resolve_spike_shut(entity_id, cell)
		"wedge_open":
			return _resolve_wedge_open(entity_id, cell)
		"remove_spike":
			return _resolve_remove_spike(entity_id, cell)
		"remove_wedge":
			return _resolve_remove_wedge(entity_id, cell)
		"exit_dungeon":
			return _resolve_exit_dungeon(entity_id, cell)
		"loot":
			var dungeon_id: String = event.data.get("dungeon_id", "")
			return _resolve_loot(entity_id, cell, dungeon_id)
		"pick_up_all":
			var dungeon_id: String = event.data.get("dungeon_id", "")
			return _resolve_pick_up_all(entity_id, cell, dungeon_id)
		# TODO (dungeon stocking session): "open_container" — after Pick Lock / Bash
		# resolves on a container cell, create a cache via
		# LocationCacheManager.create_dungeon_container_cache() and emit
		# EventBus.container_opened(container_id, contents). The LootDistributionModal
		# can then open via its existing open() or open_from_cache() API.
		_:
			return {
				"auto_pause": true,
				"pause_reason": "%s complete" % action_type,
			}


# ---------------------------------------------------------------------------
# Action resolution
# ---------------------------------------------------------------------------

## Search — 1d20 ≥ target succeeds (ACKS Adventures, Active Search).
## Default is 18+. Elves throw 8+ when actively searching for secret doors
## (their primary search-bonus category). Dwarves throw 14+ for non-magical
## traps. The action is generic — actual feature found is determined by the
## current cell — so we apply the better of the two racial thresholds for
## each race. Thieves use the Find Traps skill via a separate flow (TODO);
## here they get the default unless they're also elf/dwarf.
func _resolve_search(entity_id: String, cell) -> Dictionary:  # cell: Vector2i or Vector3i
	var roll: RollResult = DiceSystem.roll_digital(20, 1, 0, "search")
	var target: int = _search_target_for(entity_id)
	var found: bool = roll.modified_total >= target
	return {
		"auto_pause": true,
		"pause_reason": "Search complete" + (" — found something!" if found else " — nothing found"),
		"presentation": {
			"type": "dungeon_search_complete",
			"entity_id": entity_id,
			"cell": str(cell),
			"roll": roll.modified_total,
			"target": target,
			"found": found,
		},
	}


## Listen / Listen at Door — 1d20 ≥ target succeeds (ACKS Adventures,
## Listening at Doors). Default 18+. Dwarves and elves throw 14+ ("keen
## hearing"). Thieves should use the Hear Noises thief skill via
## ThiefSkillResolver — TODO; for now non-elf/dwarf thieves get the default
## throw and Hear Noises remains a follow-up.
func _resolve_listen(entity_id: String, cell) -> Dictionary:  # cell: Vector2i or Vector3i
	var roll: RollResult = DiceSystem.roll_digital(20, 1, 0, "listen")
	var target: int = _listen_target_for(entity_id)
	var heard: bool = roll.modified_total >= target
	return {
		"auto_pause": true,
		"pause_reason": "Listen complete" + (" — heard something!" if heard else " — silence"),
		"presentation": {
			"type": "dungeon_listen_complete",
			"entity_id": entity_id,
			"cell": str(cell),
			"roll": roll.modified_total,
			"target": target,
			"heard": heard,
		},
	}


## Returns the search target number for [param entity_id] (≥ this on 1d20
## succeeds). 18 baseline, 8 for elves (secret doors), 14 for dwarves (traps).
func _search_target_for(entity_id: String) -> int:
	var cd: CharacterData = _get_character(entity_id)
	if cd == null:
		return 18
	if cd.race == "elf":
		return 8
	if cd.race == "dwarf":
		return 14
	return 18


## Returns the listen target number for [param entity_id] (≥ this on 1d20
## succeeds). 18 baseline; elves and dwarves both throw 14+.
func _listen_target_for(entity_id: String) -> int:
	var cd: CharacterData = _get_character(entity_id)
	if cd != null and (cd.race == "elf" or cd.race == "dwarf"):
		return 14
	return 18


## Convenience accessor — returns the CharacterData for [param entity_id]
## from the active party, or null if unavailable.
func _get_character(entity_id: String) -> CharacterData:
	if _runner == null:
		return null
	var party_data: PartyData = _runner.get_party_data()
	if party_data == null:
		return null
	return party_data.get_member(entity_id)


func _resolve_force_door(entity_id: String, cell) -> Dictionary:  # cell: Vector2i or Vector3i
	# Force stuck door: d20 vs target (base 18, modified by STR×4 and Dungeon Bashing).
	# Use ThiefSkillResolver for proper modifier calculation.
	var party_data: PartyData = _runner.get_party_data() if _runner != null else null
	var char_data: CharacterData = party_data.get_member(entity_id) if party_data != null else null

	var roll: RollResult
	var effective_target: int = 18
	if char_data != null:
		var bundle := CharacterBundle.new()
		bundle.character = char_data
		bundle.proficiencies = CampaignRepository.get_character_proficiencies(entity_id)
		bundle.character.proficiencies = bundle.proficiencies
		bundle.powers = CampaignRepository.get_character_powers(entity_id)
		bundle.inventory = []

		var class_reg: ClassRegistry = _runner.get_class_registry()
		var prof_reg := ProficiencyRegistry.new()
		var power_reg := PowerRegistry.new()
		var resolver := ThiefSkillResolver.new(class_reg, prof_reg, power_reg)

		var skill_check: Dictionary = resolver.get_skill_check(bundle, "force_door")
		if skill_check.get("effective_target", null) != null:
			effective_target = int(skill_check.get("effective_target"))
		roll = resolver.roll_skill_digital(bundle, "force_door")
	else:
		roll = DiceSystem.roll_digital(20, 1, 0, "force_door")

	var forced: bool = roll.modified_total >= effective_target

	if forced:
		var controller: DungeonMapController = _find_dungeon_controller()
		if controller != null and controller.has_map():
			var tmap = controller.get_voxel_map()
			tmap.set_door_state(cell, "closed")  # stuck → closed (now openable)
			controller.door_state_changed.emit(cell, "stuck", "closed")

	EventBus.notification_requested.emit({
		"type": "success" if forced else "warning",
		"category": "environment",
		"title": ("Door forced open! (rolled %d vs %d)" if forced else "Door held fast (rolled %d vs %d)") \
			% [roll.modified_total, effective_target],
		"duration": 4.0,
	})

	return {
		"auto_pause": true,
		"pause_reason": "Door " + ("forced open!" if forced else "held fast"),
		"presentation": {
			"type": "dungeon_force_door",
			"entity_id": entity_id,
			"cell": str(cell),
			"roll": roll.modified_total,
			"target": effective_target,
			"forced": forced,
		},
	}


func _resolve_bash_door(entity_id: String, cell) -> Dictionary:  # cell: Vector2i or Vector3i
	# Verify the basher has an axe.
	var axe_keys := ["hand_axe", "battle_axe", "great_axe"]
	var has_axe := false
	var items: Array = CampaignRepository.get_inventory_items(entity_id)
	for item in items:
		if item.get("item_key", "") in axe_keys:
			has_axe = true
			break
	if not has_axe:
		return {"auto_pause": true, "pause_reason": "Cannot bash — no axe!"}

	# Bash is deterministic — time spent = success per ACKS.
	var controller: DungeonMapController = _find_dungeon_controller()
	if controller != null and controller.has_map():
		var tmap = controller.get_voxel_map()
		var old_state: String = tmap.get_door_state(cell)
		tmap.set_door_state(cell, "destroyed")
		controller.door_state_changed.emit(cell, old_state, "destroyed")

	EventBus.notification_requested.emit({
		"type": "info",
		"category": "environment",
		"title": "The door splinters apart!",
		"duration": 4.0,
	})
	return {
		"auto_pause": true,
		"pause_reason": "Door destroyed!",
		"presentation": {
			"type": "dungeon_bash_door",
			"cell": str(cell),
		},
	}


func _resolve_pick_lock(entity_id: String, cell) -> Dictionary:  # cell: Vector2i or Vector3i
	# Build a CharacterBundle for the thief skill check.
	var party_data: PartyData = _runner.get_party_data() if _runner != null else null
	if party_data == null:
		return {"auto_pause": true, "pause_reason": "Pick lock failed — no party data"}

	var char_data: CharacterData = party_data.get_member(entity_id)
	if char_data == null:
		return {"auto_pause": true, "pause_reason": "Pick lock failed — character not found"}

	var bundle := CharacterBundle.new()
	bundle.character = char_data
	bundle.proficiencies = CampaignRepository.get_character_proficiencies(entity_id)
	bundle.character.proficiencies = bundle.proficiencies
	bundle.powers = CampaignRepository.get_character_powers(entity_id)
	bundle.inventory = []

	# Build ThiefSkillResolver with registries.
	var class_reg: ClassRegistry = _runner.get_class_registry()
	var prof_reg := ProficiencyRegistry.new()
	var power_reg := PowerRegistry.new()
	var resolver := ThiefSkillResolver.new(class_reg, prof_reg, power_reg)

	# Check if the skill is available before rolling.
	var skill_check: Dictionary = resolver.get_skill_check(bundle, "open_locks")
	if not bool(skill_check.get("is_available", false)):
		return {
			"auto_pause": true,
			"pause_reason": "Cannot pick locks — no applicable skill",
		}

	# Roll the skill check.
	var roll: RollResult = resolver.roll_skill_digital(bundle, "open_locks")
	var effective_target = skill_check.get("effective_target", 20)
	var success: bool = roll.modified_total >= int(effective_target)

	if success:
		var controller: DungeonMapController = _find_dungeon_controller()
		if controller != null and controller.has_map():
			var tmap = controller.get_voxel_map()
			var old_state: String = tmap.get_door_state(cell)
			tmap.set_door_state(cell, "closed")
			tmap.set_cell_field(cell, "door_type", "unlocked")
			controller.door_state_changed.emit(cell, old_state, "closed")

		# Record in session state for revert on dungeon exit.
		_record_picked_lock(cell)

		EventBus.notification_requested.emit({
			"type": "success",
			"category": "environment",
			"title": "Lock picked! (rolled %d vs %d)" % [roll.modified_total, int(effective_target)],
			"duration": 4.0,
		})
	else:
		# Record failure — character cannot retry until gaining a level.
		_record_pick_lock_failure(entity_id, char_data.level)

		EventBus.notification_requested.emit({
			"type": "warning",
			"category": "environment",
			"title": "Lock pick failed! (rolled %d vs %d)" % [roll.modified_total, int(effective_target)],
			"duration": 4.0,
		})

	return {
		"auto_pause": true,
		"pause_reason": "Lock " + ("picked!" if success else "resists!"),
		"presentation": {
			"type": "dungeon_pick_lock",
			"entity_id": entity_id,
			"cell": str(cell),
			"roll": roll.modified_total,
			"target": int(effective_target),
			"success": success,
		},
	}


func _resolve_use_lever(entity_id: String, cell) -> Dictionary:  # cell: Vector2i or Vector3i
	var controller: DungeonMapController = _find_dungeon_controller()
	if controller == null or not controller.has_map():
		return {"auto_pause": true, "pause_reason": "Lever — no map"}

	# Adjacency check: the acting entity must be one cell away (Chebyshev == 1).
	# Guards against stale right-click targets when the party has moved since
	# the menu opened.
	if not entity_id.is_empty() and cell is Vector3i:
		var actor_pos: Vector3i = controller.get_entity_pos_3d(entity_id)
		if actor_pos != Vector3i(-1, -1, -1) and not VoxelGrid.is_adjacent(actor_pos, cell):
			EventBus.notification_requested.emit({
				"type": "warning",
				"category": "environment",
				"title": "Too far to reach the lever.",
				"duration": 3.0,
			})
			return {"auto_pause": true, "pause_reason": "Lever — out of reach"}

	var tmap = controller.get_voxel_map()
	var target_pos
	if tmap.has_method("get_lever_target"):
		target_pos = tmap.get_lever_target(cell)
	else:
		target_pos = null
	if target_pos == null or target_pos == Vector2i(-1, -1) or target_pos == Vector3i(-1, -1, -1):
		EventBus.notification_requested.emit({
			"type": "info",
			"category": "environment",
			"title": "The lever doesn't seem to be connected to anything.",
			"duration": 4.0,
		})
		return {"auto_pause": true, "pause_reason": "Lever — no target"}

	# Spiked or wedged portcullises resist lever operation.
	if _session_state != null:
		if _session_state.has_method("is_spiked") and _session_state.is_spiked(target_pos):
			EventBus.notification_requested.emit({
				"type": "warning", "category": "environment",
				"title": "The portcullis is spiked and won't move!", "duration": 3.0,
			})
			return {"auto_pause": true, "pause_reason": "Portcullis is spiked!"}
		if _session_state.has_method("is_wedged") and _session_state.is_wedged(target_pos):
			EventBus.notification_requested.emit({
				"type": "warning", "category": "environment",
				"title": "The portcullis is wedged and won't move!", "duration": 3.0,
			})
			return {"auto_pause": true, "pause_reason": "Portcullis is wedged!"}

	var old_state: String = tmap.get_door_state(target_pos)
	var new_state: String = "open" if old_state != "open" else "closed"
	tmap.set_door_state(target_pos, new_state)
	controller.door_state_changed.emit(target_pos, old_state, new_state)

	var msg: String = "The portcullis rises with a grinding sound!" if new_state == "open" \
		else "The portcullis drops with a heavy clang!"
	EventBus.notification_requested.emit({
		"type": "info",
		"category": "environment",
		"title": msg,
		"duration": 4.0,
	})
	return {
		"auto_pause": true,
		"pause_reason": msg,
		"presentation": {
			"type": "dungeon_lever",
			"cell": str(cell),
			"target": str(target_pos),
			"new_state": new_state,
		},
	}


func _resolve_force_portcullis(entity_id: String, cell) -> Dictionary:  # cell: Vector2i or Vector3i
	# Same throw as force_door (base 18, STR×4, Dungeon Bashing), but on success
	# the portcullis is held open only while the character does nothing else.
	var party_data: PartyData = _runner.get_party_data() if _runner != null else null
	var char_data: CharacterData = party_data.get_member(entity_id) if party_data != null else null

	var roll: RollResult
	var effective_target: int = 18
	if char_data != null:
		var bundle := CharacterBundle.new()
		bundle.character = char_data
		bundle.proficiencies = CampaignRepository.get_character_proficiencies(entity_id)
		bundle.character.proficiencies = bundle.proficiencies
		bundle.powers = CampaignRepository.get_character_powers(entity_id)
		bundle.inventory = []

		var class_reg: ClassRegistry = _runner.get_class_registry()
		var prof_reg := ProficiencyRegistry.new()
		var power_reg := PowerRegistry.new()
		var resolver := ThiefSkillResolver.new(class_reg, prof_reg, power_reg)

		var skill_check: Dictionary = resolver.get_skill_check(bundle, "force_door")
		if skill_check.get("effective_target", null) != null:
			effective_target = int(skill_check.get("effective_target"))
		roll = resolver.roll_skill_digital(bundle, "force_door")
	else:
		roll = DiceSystem.roll_digital(20, 1, 0, "force_door")

	var forced: bool = roll.modified_total >= effective_target

	if forced:
		var controller: DungeonMapController = _find_dungeon_controller()
		if controller != null and controller.has_map():
			var tmap = controller.get_voxel_map()
			tmap.set_door_state(cell, "open")
			controller.door_state_changed.emit(cell, "closed", "open")

		# Record that this character is holding the portcullis.
		if _session_state != null and _session_state.has_method("hold_portcullis"):
			_session_state.hold_portcullis(cell, entity_id)

	var msg: String
	if forced:
		msg = "Portcullis forced open! (rolled %d vs %d) — drops if you act" \
			% [roll.modified_total, effective_target]
	else:
		msg = "Portcullis won't budge (rolled %d vs %d)" \
			% [roll.modified_total, effective_target]

	EventBus.notification_requested.emit({
		"type": "success" if forced else "warning",
		"category": "environment",
		"title": msg, "duration": 4.0,
	})
	return {
		"auto_pause": true,
		"pause_reason": msg,
		"presentation": {
			"type": "dungeon_force_portcullis",
			"entity_id": entity_id,
			"cell": str(cell),
			"roll": roll.modified_total,
			"target": effective_target,
			"forced": forced,
		},
	}


func _resolve_drop_portcullis(_entity_id: String, cell) -> Dictionary:  # cell: Vector2i or Vector3i
	var controller: DungeonMapController = _find_dungeon_controller()
	if controller == null or not controller.has_map():
		return {"auto_pause": true, "pause_reason": "No map"}

	var tmap = controller.get_voxel_map()

	# Spiked or wedged portcullises resist.
	if _session_state != null:
		if _session_state.has_method("is_spiked") and _session_state.is_spiked(cell):
			EventBus.notification_requested.emit({
				"type": "warning", "category": "environment",
				"title": "The portcullis is spiked and won't move!", "duration": 3.0,
			})
			return {"auto_pause": true, "pause_reason": "Portcullis is spiked!"}
		if _session_state.has_method("is_wedged") and _session_state.is_wedged(cell):
			EventBus.notification_requested.emit({
				"type": "warning", "category": "environment",
				"title": "The portcullis is wedged and won't move!", "duration": 3.0,
			})
			return {"auto_pause": true, "pause_reason": "Portcullis is wedged!"}

	tmap.set_door_state(cell, "closed")
	controller.door_state_changed.emit(cell, "open", "closed")

	EventBus.notification_requested.emit({
		"type": "info", "category": "environment",
		"title": "The portcullis drops with a heavy clang!", "duration": 3.0,
	})
	return {
		"auto_pause": true,
		"pause_reason": "Portcullis dropped.",
		"presentation": {"type": "dungeon_drop_portcullis", "cell": str(cell)},
	}


func _resolve_spike_shut(entity_id: String, cell) -> Dictionary:  # cell: Vector2i or Vector3i
	# Find and consume one iron spike from the character's inventory.
	var spike_item: Dictionary = _find_iron_spike(entity_id)
	if spike_item.is_empty():
		EventBus.notification_requested.emit({
			"type": "warning", "category": "environment",
			"title": "No iron spikes available!", "duration": 3.0,
		})
		return {"auto_pause": true, "pause_reason": "No iron spikes!"}

	# Consume one spike.
	var item_id: String = spike_item.get("id", "")
	var qty: int = spike_item.get("quantity", 1)
	CampaignRepository.update_inventory_item_quantity(item_id, qty - 1)

	# Record spiked state in session.
	if _session_state != null and _session_state.has_method("spike_door"):
		_session_state.spike_door(cell)

	EventBus.notification_requested.emit({
		"type": "info", "category": "environment",
		"title": "Door spiked shut!", "duration": 3.0,
	})
	return {
		"auto_pause": true,
		"pause_reason": "Door spiked shut!",
		"presentation": {"type": "dungeon_spike_door", "cell": str(cell)},
	}


func _resolve_wedge_open(entity_id: String, cell) -> Dictionary:  # cell: Vector2i or Vector3i
	# Find and consume one iron spike from the character's inventory.
	var spike_item: Dictionary = _find_iron_spike(entity_id)
	if spike_item.is_empty():
		EventBus.notification_requested.emit({
			"type": "warning", "category": "environment",
			"title": "No iron spikes available!", "duration": 3.0,
		})
		return {"auto_pause": true, "pause_reason": "No iron spikes!"}

	# Consume one spike.
	var item_id: String = spike_item.get("id", "")
	var qty: int = spike_item.get("quantity", 1)
	CampaignRepository.update_inventory_item_quantity(item_id, qty - 1)

	# Record wedged state in session.
	if _session_state != null and _session_state.has_method("wedge_door"):
		_session_state.wedge_door(cell)

	EventBus.notification_requested.emit({
		"type": "info", "category": "environment",
		"title": "Door wedged open!", "duration": 3.0,
	})
	return {
		"auto_pause": true,
		"pause_reason": "Door wedged open!",
		"presentation": {"type": "dungeon_wedge_door", "cell": str(cell)},
	}


## Find an iron spike item in a character's inventory. Returns the item dict or {}.
func _find_iron_spike(entity_id: String) -> Dictionary:
	var items: Array = CampaignRepository.get_inventory_items(entity_id)
	for item in items:
		if item.get("item_key", "") == "iron_spikes_12" and item.get("quantity", 0) > 0:
			return item
	return {}


func _resolve_remove_spike(entity_id: String, cell) -> Dictionary:  # cell: Vector2i or Vector3i
	if _session_state == null or not _session_state.has_method("is_spiked") \
			or not _session_state.is_spiked(cell):
		return {"auto_pause": true, "pause_reason": "No spike to remove"}

	_session_state.unspike_door(cell)

	# Return the spike to the character's inventory.
	_return_iron_spike(entity_id)

	EventBus.notification_requested.emit({
		"type": "info", "category": "environment",
		"title": "Spike removed.", "duration": 3.0,
	})
	return {
		"auto_pause": true,
		"pause_reason": "Spike removed.",
		"presentation": {"type": "dungeon_remove_spike", "cell": str(cell)},
	}


func _resolve_remove_wedge(entity_id: String, cell) -> Dictionary:  # cell: Vector2i or Vector3i
	if _session_state == null or not _session_state.has_method("is_wedged") \
			or not _session_state.is_wedged(cell):
		return {"auto_pause": true, "pause_reason": "No wedge to remove"}

	_session_state.unwedge_door(cell)

	# Return the spike to the character's inventory.
	_return_iron_spike(entity_id)

	EventBus.notification_requested.emit({
		"type": "info", "category": "environment",
		"title": "Wedge removed.", "duration": 3.0,
	})
	return {
		"auto_pause": true,
		"pause_reason": "Wedge removed.",
		"presentation": {"type": "dungeon_remove_wedge", "cell": str(cell)},
	}


func _resolve_exit_dungeon(entity_id: String, _cell) -> Dictionary:  # _cell: Vector2i or Vector3i
	var controller: DungeonMapController = _find_dungeon_controller()
	if controller == null:
		return {"auto_pause": true, "pause_reason": "Exit failed — no controller"}

	# Cancel any active movement for this entity.
	cancel_move(entity_id)
	clear_renderer_animated(entity_id)

	# Remove character from the dungeon map.
	controller.remove_party_member(entity_id)

	# Mark as exited in session state and remove from exit queue.
	if _session_state != null:
		_session_state.mark_exited(entity_id)
		_session_state.dequeue_exit(entity_id)

	# Get character name for notification.
	var char_name := entity_id
	var party_data: PartyData = _runner.get_party_data() if _runner != null else null
	if party_data != null:
		var cd: CharacterData = party_data.get_member(entity_id)
		if cd != null:
			char_name = cd.name

	EventBus.notification_requested.emit({
		"type": "info", "category": "exploration",
		"title": "%s exits the dungeon." % char_name,
		"duration": 4.0,
	})

	# Check if all party members have now exited or are incapacitated/dead.
	# Use all active characters from party_data — all_party_resolved checks
	# each character's exited/dead/incapacitated status.
	var all_resolved := false
	if _session_state != null and party_data != null:
		var all_ids: Array[String] = []
		for cd: CharacterData in party_data.character_data:
			if cd.is_active:
				all_ids.append(cd.id)
		all_resolved = _session_state.all_party_resolved(all_ids, party_data)

	return {
		"auto_pause": true,
		"pause_reason": "%s exited the dungeon" % char_name,
		"presentation": {
			"type": "dungeon_character_exited",
			"entity_id": entity_id,
			"all_resolved": all_resolved,
		},
	}


## Return one iron spike to a character's inventory (after removing spike/wedge).
func _return_iron_spike(entity_id: String) -> void:
	# Try to stack onto existing spike item.
	var existing: Dictionary = _find_iron_spike(entity_id)
	if not existing.is_empty():
		var item_id: String = existing.get("id", "")
		var qty: int = existing.get("quantity", 0)
		CampaignRepository.update_inventory_item_quantity(item_id, qty + 1)
	else:
		# Create a new stack of 1 spike.
		CampaignRepository.add_inventory_item({
			"character_id": entity_id,
			"item_key": "iron_spikes_12",
			"name": "Iron Spikes (12)",
			"quantity": 1,
			"encumbrance_units": 1000,
			"item_category": "gear",
			"slot": "pack",
		})


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


## Release any portcullises held open by this entity (they slam shut).
func _release_held_portcullises(entity_id: String) -> void:
	if _session_state == null or not _session_state.has_method("release_all_held_by"):
		return
	var released: Array = _session_state.release_all_held_by(entity_id)
	if released.is_empty():
		return
	var controller: DungeonMapController = _find_dungeon_controller()
	if controller == null or not controller.has_map():
		return
	var tmap = controller.get_voxel_map()
	for pos in released:
		if tmap.get_door_state(pos) == "open":
			tmap.set_door_state(pos, "closed")
			controller.door_state_changed.emit(pos, "open", "closed")
			EventBus.notification_requested.emit({
				"type": "warning",
				"category": "environment",
				"title": "The portcullis slams shut!",
				"duration": 3.0,
			})


## Record a successfully picked lock in session state (reverted on dungeon exit).
func _record_picked_lock(pos) -> void:
	if _session_state != null and _session_state.has_method("record_picked_lock"):
		_session_state.record_picked_lock(pos)


## Record a pick lock failure in session state.
func _record_pick_lock_failure(entity_id: String, level: int) -> void:
	if _session_state != null and _session_state.has_method("record_pick_lock_failure"):
		_session_state.record_pick_lock_failure(entity_id, level)


func _find_dungeon_controller() -> DungeonMapController:
	if _runner == null:
		return null
	for child in _runner.get_children():
		if child is DungeonMapController:
			return child
	return null


# ---------------------------------------------------------------------------
# Loot action resolvers
# ---------------------------------------------------------------------------

## Resolves the "loot" action: opens the loot distribution modal over the cache.
## The dungeon explore state listens for the "open_loot_modal" presentation type.
func _resolve_loot(_entity_id: String, cell, dungeon_id: String) -> Dictionary:  # cell: Vector2i or Vector3i
	# TODO (voxel migration): extend location_key to include level coordinate
	# per gdd-voxel-tactical-architecture-v1.1.md §6.3 — currently 2D (col,row);
	# becomes 3D (col,row,level) when the voxel schema lands.
	var location_key := "dungeon:%s:cell:%d,%d" % [dungeon_id, cell.x, cell.y]
	var cache: Dictionary = CampaignRepository.get_cache_at_location_key(
		GameState.campaign_id, location_key)
	if cache.is_empty():
		return {
			"auto_pause": true,
			"pause_reason": "Nothing to loot here.",
		}

	return {
		"auto_pause": true,
		"pause_reason": "Looting",
		"presentation": {
			"type": "open_loot_modal",
			"cache_id": cache.get("id", ""),
			"cell_x": cell.x,
			"cell_y": cell.y,
		},
	}


## Resolves the "pick_up_all" action: transfers all cache items to the acting
## character, respecting encumbrance. Coins are deposited directly; non-coin
## items are transferred via LocationCacheManager. Awards treasure XP.
func _resolve_pick_up_all(entity_id: String, cell, dungeon_id: String) -> Dictionary:  # cell: Vector2i or Vector3i
	# TODO (voxel migration): extend location_key to include level coordinate
	# per gdd-voxel-tactical-architecture-v1.1.md §6.3 — currently 2D (col,row);
	# becomes 3D (col,row,level) when the voxel schema lands.
	var location_key := "dungeon:%s:cell:%d,%d" % [dungeon_id, cell.x, cell.y]
	var cache: Dictionary = CampaignRepository.get_cache_at_location_key(
		GameState.campaign_id, location_key)
	if cache.is_empty():
		return {
			"auto_pause": true,
			"pause_reason": "Nothing to pick up.",
		}

	var cache_id: String = cache.get("id", "")
	var items: Array = CampaignRepository.list_items_in_cache(cache_id)
	if items.is_empty():
		return {
			"auto_pause": true,
			"pause_reason": "Cache is empty.",
		}

	# Separate coins from non-coins, then process.
	var total_coin_cp := 0
	var coin_item_ids: Array = []
	var non_coin_items: Array = []
	for item in items:
		var item_key: String = item.get("item_key", "")
		if Currency.is_coin(item_key):
			var qty: int = item.get("quantity", 0)
			total_coin_cp += qty * Currency.coin_key_to_cp_value(item_key)
			coin_item_ids.append(item.get("id", ""))
		else:
			non_coin_items.append(item)

	# Deposit coins to the acting character.
	if total_coin_cp > 0:
		CampaignRepository.add_coins_cp(entity_id, total_coin_cp)
		# Remove coin items from cache.
		for cid in coin_item_ids:
			CampaignRepository.remove_inventory_item(cid)

	# Transfer non-coin items (future: check encumbrance before each transfer).
	var items_picked := 0
	for item in non_coin_items:
		var item_id: String = item.get("id", "")
		if LocationCacheManager.pick_up_item(item_id, entity_id, "character"):
			items_picked += 1

	# Award treasure XP for recovered coins.
	var treasure_gp := total_coin_cp / 100  # Integer division; 100 cp = 1 gp
	if treasure_gp > 0:
		_award_treasure_xp(treasure_gp)

	# Clean up empty cache and clear cell flag.
	var remaining := CampaignRepository.list_items_in_cache(cache_id)
	if remaining.is_empty():
		CampaignRepository.delete_location_cache(cache_id)
		var controller: DungeonMapController = _find_dungeon_controller()
		if controller != null:
			var tmap = controller.get_voxel_map()
			if tmap != null:
				tmap.set_cell_field(cell, "has_ground_items", false)

	# Build summary notification.
	var char_name := entity_id
	var party_data: PartyData = _runner.get_party_data() if _runner != null else null
	if party_data != null:
		var cd: CharacterData = party_data.get_member(entity_id)
		if cd != null:
			char_name = cd.name
	var summary := "%s picked up" % char_name
	if total_coin_cp > 0:
		summary += " %s" % Currency.format_cost(total_coin_cp)
	if items_picked > 0:
		summary += " and %d item(s)" % items_picked
	summary += "."

	EventBus.notification_requested.emit({
		"type": "info", "category": "exploration",
		"title": summary,
		"duration": 5.0,
	})

	return {
		"auto_pause": true,
		"pause_reason": summary,
	}


## Awards treasure XP to all eligible party members.
## ACKS RAW: 1 XP per 1 GP of recovered treasure.
func _award_treasure_xp(treasure_gp: int) -> void:
	if treasure_gp <= 0 or _runner == null:
		return

	var party_id: String = GameState.active_party_id
	if party_id.is_empty():
		party_id = GameState.party_id

	var eligible := CampaignRepository.list_xp_eligible_entities(party_id)
	if eligible.is_empty():
		return

	# Build members array matching XPAwardCalculator format.
	var members: Array = []
	for row in eligible:
		var cid: String = row.get("id", "")
		var char_dict: Dictionary = CampaignRepository.get_character(cid)
		if char_dict.is_empty():
			continue
		var cd: CharacterData = CharacterData.from_dict(char_dict)
		members.append({
			"character_id": cid,
			"is_henchman": cd.character_type == "henchman",
			"xp_adjustment_percent": cd.xp_adjustment_percent,
			"character_data": cd,
		})

	if members.is_empty():
		return

	var class_registry: ClassRegistry = _runner.get_class_registry()
	var calculator := XPAwardCalculator.new(class_registry)
	var xp_results: Array = calculator.award_adventure_xp(0, treasure_gp, members)

	for xp_entry in xp_results:
		var cid: String = xp_entry["character_id"]
		var clamped: int = xp_entry["clamped_share"]
		# Persist XP to database.
		var cd: CharacterData = null
		for m in members:
			if m["character_id"] == cid:
				cd = m["character_data"]
				break
		if cd != null:
			cd.xp = xp_entry["xp_after"]
			CampaignRepository.save_character(cd.to_dict())
		EventBus.xp_awarded.emit(cid, clamped)
		if xp_entry.get("leveled_up", false):
			EventBus.character_leveled_up.emit(cid, (cd.level + 1) if cd != null else 0)
