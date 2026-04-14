class_name SettlementHandlers
extends RefCounted

## Event handlers for settlement (city node-graph) exploration.
##
## Registered by SettlementExploreState.enter() with the EventHandlerRegistry.
## Settlement movement and activities are scheduled as events, with the clock
## advancing to resolve them.
##
## Event types handled:
##   "settlement_move"      — party moves to an adjacent node in the settlement
##   "settlement_activity"  — a timed activity at a PoI (shopping, hiring, etc.)
##   "settlement_encounter" — random urban encounter check


# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------

var _runner = null  # SessionRunner


func _init(runner) -> void:
	_runner = runner


# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------

func register(registry: EventHandlerRegistry) -> void:
	registry.register("settlement_move", _handle_settlement_move)
	registry.register("settlement_activity", _handle_settlement_activity)
	registry.register("settlement_encounter", _handle_settlement_encounter)


func unregister(registry: EventHandlerRegistry) -> void:
	registry.unregister("settlement_move")
	registry.unregister("settlement_activity")
	registry.unregister("settlement_encounter")


# ---------------------------------------------------------------------------
# Scheduling helpers (called by SettlementExploreState)
# ---------------------------------------------------------------------------

## Schedule a single node-to-node move. Duration: 1 exploration turn (10 min).
## Future: weight by edge distance and party speed in blocks.
func schedule_move(
	target_node_id: int,
	scheduler: EventScheduler,
	party_id: String,
) -> String:
	var current_time: int = Timekeeping.get_party_time(party_id)
	var move_rounds: int = Timekeeping.ROUNDS_PER_TURN  # 1 turn per settlement move

	var event_id := scheduler.schedule_at(
		current_time + move_rounds,
		"settlement_move",
		party_id,
		{"target_node_id": target_node_id},
		ScheduledEvent.PRIORITY_ARRIVAL,
	)
	EventBus.order_queued.emit(party_id, "settlement_move", current_time + move_rounds)
	return event_id


## Schedule a timed activity at a PoI. Duration depends on activity type.
func schedule_activity(
	activity_type: String,
	poi_data: Dictionary,
	duration_turns: int,
	scheduler: EventScheduler,
	party_id: String,
) -> String:
	var current_time: int = Timekeeping.get_party_time(party_id)
	var duration_rounds: int = duration_turns * Timekeeping.ROUNDS_PER_TURN

	var event_id := scheduler.schedule_at(
		current_time + duration_rounds,
		"settlement_activity",
		party_id,
		{
			"activity_type": activity_type,
			"poi_data": poi_data,
			"duration_turns": duration_turns,
		},
		ScheduledEvent.PRIORITY_ARRIVAL,
	)
	EventBus.order_queued.emit(party_id, "settlement_activity", current_time + duration_rounds)
	return event_id


# ---------------------------------------------------------------------------
# Event handlers
# ---------------------------------------------------------------------------

## Party moves to a settlement node. Execute the move on the controller.
func _handle_settlement_move(event: ScheduledEvent) -> Dictionary:
	var target_node_id: int = event.data.get("target_node_id", -1)
	if target_node_id < 0:
		return {}

	# Find the settlement controller in the scene tree.
	# The SettlementExploreState adds it as a child of the runner's parent.
	var controller: SettlementMapController = _find_settlement_controller()
	if controller == null:
		push_warning("SettlementHandlers: no SettlementMapController found")
		return {}

	if controller.can_move_to(target_node_id):
		controller.move_party(target_node_id)
	else:
		return {
			"auto_pause": true,
			"pause_reason": "Cannot move to node %d" % target_node_id,
		}

	EventBus.settlement_entered.emit(
		event.data.get("settlement_id", ""),
		str(target_node_id))

	return {}


## A timed activity at a PoI completes.
func _handle_settlement_activity(event: ScheduledEvent) -> Dictionary:
	var activity_type: String = event.data.get("activity_type", "")
	return {
		"auto_pause": true,
		"pause_reason": "Activity complete: %s" % activity_type,
		"presentation": {
			"type": "settlement_activity_complete",
			"activity_type": activity_type,
			"poi_data": event.data.get("poi_data", {}),
		},
	}


## Urban encounter check.
func _handle_settlement_encounter(event: ScheduledEvent) -> Dictionary:
	# Urban encounters per ACKS: 1-in-6 check per certain amount of time
	# spent in the settlement. For now, use standard encounter check logic.
	var roll: RollResult = DiceSystem.roll_digital(6, 1, 0, "urban_encounter_check")
	if roll.modified_total <= 1:
		return {
			"auto_pause": true,
			"pause_reason": "Urban encounter!",
			"presentation": {
				"type": "settlement_encounter",
				"roll": roll.modified_total,
			},
		}
	return {}


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _find_settlement_controller() -> SettlementMapController:
	# The controller is added as a child of the runner node.
	if _runner == null:
		return null
	for child in _runner.get_children():
		if child is SettlementMapController:
			return child
	return null
