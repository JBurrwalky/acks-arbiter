class_name SchedulerLoop
extends RefCounted

## Tick-driven loop that advances the game clock and resolves scheduled events.
##
## Called from SessionRunner._process(delta). Reads real-world delta time,
## converts it to game-time rounds based on the current speed multiplier,
## advances Timekeeping, and pops/resolves events from the EventScheduler.
##
## Speed settings:
##   PAUSED (0)     — no advancement
##   NORMAL (1)     — 1 real second = 1 game round (10 game-seconds)
##   FAST (2)       — 1 real second = 2 rounds
##   VERY_FAST (5)  — 1 real second = 5 rounds
##   MAX (-1)       — instant advance to next event (no real-time delay)
##
## The loop does NOT own the scheduler or registry — they are injected.


# ---------------------------------------------------------------------------
# Speed constants
# ---------------------------------------------------------------------------

const SPEED_PAUSED := 0
const SPEED_NORMAL := 1
const SPEED_FAST := 2
const SPEED_VERY_FAST := 5
const SPEED_MAX := -1

## Real seconds per game round at SPEED_NORMAL in dungeon context. Tunable.
## Dungeon: 1 round = 10 game-seconds, so 1x shows rounds ticking by.
const SECONDS_PER_ROUND := 2.0

## Context-dependent time scale. Multiplies the base tick rate so that
## wilderness 1x feels like watching the day advance, not individual rounds.
## Set by the exploration state on enter.
##   Dungeon:    1.0 (round-level granularity — 1 round per 2s at 1x)
##   Settlement: 6.0 (turn-level — 1 turn per ~10s at 1x)
##   Wilderness: 60.0 (hour-level — 1 hour per ~12s at 1x)
##   Camp:       use MAX speed (resolved instantly)
const TIMESCALE_DUNGEON := 1.0
const TIMESCALE_SETTLEMENT := 6.0
const TIMESCALE_WILDERNESS := 60.0

## Per-context speed multipliers. Keyed by SPEED_NORMAL/FAST/VERY_FAST.
## C1 decoupling: dungeon Fast = 6 rounds (1 minute) per 2 real seconds, Very
## Fast = 30 rounds (5 minutes) per 2 real seconds. Wilderness/settlement keep
## the prior 1×/2×/5× because their TIMESCALE_* multipliers (60, 6) already
## advance large stretches of game time at the same band — bumping the band
## multipliers there would push wilderness Very Fast to 9000× real-time.
const DUNGEON_SPEEDS := {
	SPEED_NORMAL: 1,
	SPEED_FAST: 6,
	SPEED_VERY_FAST: 30,
}
const WILDERNESS_SPEEDS := {
	SPEED_NORMAL: 1,
	SPEED_FAST: 2,
	SPEED_VERY_FAST: 5,
}
const SETTLEMENT_SPEEDS := {
	SPEED_NORMAL: 1,
	SPEED_FAST: 2,
	SPEED_VERY_FAST: 5,
}


# ---------------------------------------------------------------------------
# Dependencies (injected)
# ---------------------------------------------------------------------------

var _scheduler: EventScheduler
var _registry: EventHandlerRegistry
var _party_id: String = ""


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _speed: int = SPEED_PAUSED
var _paused: bool = true

## Context-dependent time scale (see TIMESCALE_* constants).
var _timescale: float = TIMESCALE_WILDERNESS

## Fractional rounds accumulated between frames (avoids drift at low speeds).
var _accumulated_rounds: float = 0.0

## Set to true by event resolution when combat should be entered.
## SessionRunner reads and clears this after each tick.
var combat_requested: bool = false
var combat_data: Dictionary = {}

## Set to true when auto-pause fires. SessionRunner reads and clears.
var auto_pause_triggered: bool = false
var auto_pause_reason: String = ""

## Set when a state transition is requested by an event handler.
var transition_requested: String = ""
var transition_data: Dictionary = {}

## Events resolved during the most recent tick, for UI notification.
var last_tick_results: Array[Dictionary] = []


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func setup(scheduler: EventScheduler, registry: EventHandlerRegistry, party_id: String) -> void:
	_scheduler = scheduler
	_registry = registry
	_party_id = party_id
	_speed = SPEED_PAUSED
	_paused = true
	_accumulated_rounds = 0.0


func set_party_id(party_id: String) -> void:
	_party_id = party_id


## Set the time scale for the current exploration context.
## Higher values make the clock tick faster at the same speed setting.
func set_timescale(scale: float) -> void:
	_timescale = maxf(1.0, scale)
	_accumulated_rounds = 0.0


func get_timescale() -> float:
	return _timescale


## Returns the per-context multiplier for the currently-set speed band.
## Internal tick math and external consumers (e.g. the dungeon renderer's
## tween-speed computation) both go through this so the two stay in sync.
func get_effective_multiplier() -> float:
	if _speed == SPEED_PAUSED or _speed == SPEED_MAX:
		return float(_speed)
	var table: Dictionary = _speed_table_for_timescale()
	return float(table.get(_speed, _speed))


## Picks the per-context speed table by inspecting the current `_timescale`
## (set on state enter). Falls back to wilderness for unknown values.
func _speed_table_for_timescale() -> Dictionary:
	if is_equal_approx(_timescale, TIMESCALE_DUNGEON):
		return DUNGEON_SPEEDS
	if is_equal_approx(_timescale, TIMESCALE_SETTLEMENT):
		return SETTLEMENT_SPEEDS
	return WILDERNESS_SPEEDS


# ---------------------------------------------------------------------------
# Speed control
# ---------------------------------------------------------------------------

func set_speed(speed: int) -> void:
	var old_speed := _speed
	_speed = speed
	if speed == SPEED_PAUSED:
		_paused = true
	else:
		_paused = false
	_accumulated_rounds = 0.0
	if old_speed != speed:
		EventBus.scheduler_speed_changed.emit(speed)


func get_speed() -> int:
	return _speed


func pause() -> void:
	if not _paused:
		_paused = true
		_speed = SPEED_PAUSED
		EventBus.scheduler_speed_changed.emit(SPEED_PAUSED)
		EventBus.scheduler_paused.emit(auto_pause_reason if not auto_pause_reason.is_empty() else "paused")


func resume(speed: int = SPEED_NORMAL) -> void:
	_paused = false
	_speed = speed
	_accumulated_rounds = 0.0
	auto_pause_triggered = false
	auto_pause_reason = ""
	combat_requested = false
	combat_data = {}
	transition_requested = ""
	transition_data = {}
	EventBus.scheduler_speed_changed.emit(speed)
	EventBus.scheduler_resumed.emit()


func is_paused() -> bool:
	return _paused


func toggle_pause(resume_speed: int = SPEED_NORMAL) -> void:
	if _paused:
		resume(resume_speed)
	else:
		pause()


# ---------------------------------------------------------------------------
# Tick (called from SessionRunner._process)
# ---------------------------------------------------------------------------

## Advance the clock and resolve events for one frame.
## Returns the number of events resolved this tick.
func tick(real_delta: float) -> int:
	last_tick_results.clear()

	if _paused or _scheduler == null or _registry == null:
		return 0

	if _party_id.is_empty():
		return 0

	var events_resolved := 0

	if _speed == SPEED_MAX:
		events_resolved = _tick_max_speed()
	else:
		events_resolved = _tick_normal(real_delta)

	return events_resolved


# ---------------------------------------------------------------------------
# Tick implementations
# ---------------------------------------------------------------------------

## Normal/fast tick: convert real delta to game rounds, advance toward events.
func _tick_normal(real_delta: float) -> int:
	var rounds_per_second := get_effective_multiplier() * _timescale / SECONDS_PER_ROUND
	_accumulated_rounds += real_delta * rounds_per_second

	var events_resolved := 0
	var max_events_per_tick := 20  # Safety cap to prevent infinite loops

	while _accumulated_rounds >= 1.0 and events_resolved < max_events_per_tick:
		var next_event := _scheduler.peek()
		if next_event == null:
			# No events — advance remaining accumulated time and stop.
			var whole_rounds := int(_accumulated_rounds)
			if whole_rounds > 0:
				Timekeeping.advance_party_rounds(_party_id, whole_rounds)
			_accumulated_rounds -= float(whole_rounds)
			break

		var current_time := Timekeeping.get_party_time(_party_id)
		var rounds_to_event := next_event.fire_time - current_time

		if rounds_to_event < 0:
			# Event is in the past — resolve immediately.
			rounds_to_event = 0

		if float(rounds_to_event) > _accumulated_rounds:
			# Next event is beyond what we can reach this tick.
			var whole_rounds := int(_accumulated_rounds)
			if whole_rounds > 0:
				Timekeeping.advance_party_rounds(_party_id, whole_rounds)
			_accumulated_rounds -= float(whole_rounds)
			break

		# Advance to the event's fire_time.
		if rounds_to_event > 0:
			Timekeeping.advance_party_rounds(_party_id, rounds_to_event)
			_accumulated_rounds -= float(rounds_to_event)

		# Pop and resolve.
		var resolved := _resolve_next_event()
		if resolved:
			events_resolved += 1

		# Check if resolution caused a pause/combat request.
		if _paused or combat_requested or not transition_requested.is_empty():
			_accumulated_rounds = 0.0
			break

	return events_resolved


## Max speed: instantly advance to and resolve the next event.
## Resolves one event per call to avoid blocking the main thread for too long.
func _tick_max_speed() -> int:
	var next_event := _scheduler.peek()
	if next_event == null:
		pause()
		auto_pause_reason = "No events scheduled"
		auto_pause_triggered = true
		return 0

	var current_time := Timekeeping.get_party_time(_party_id)
	var rounds_to_advance := next_event.fire_time - current_time

	if rounds_to_advance > 0:
		Timekeeping.advance_party_rounds(_party_id, rounds_to_advance)

	if _resolve_next_event():
		return 1
	return 0


# ---------------------------------------------------------------------------
# Event resolution
# ---------------------------------------------------------------------------

## Pop the next event from the scheduler and resolve it via the handler registry.
## Returns true if an event was resolved.
func _resolve_next_event() -> bool:
	var event := _scheduler.pop()
	if event == null:
		return false

	var result := _registry.resolve(event)

	# Store for UI notification.
	result["_event_type"] = event.event_type
	result["_owner_id"] = event.owner_id
	result["_fire_time"] = event.fire_time
	last_tick_results.append(result)

	# Emit resolved signal.
	EventBus.scheduler_event_resolved.emit(event.event_type, event.data)

	# Schedule follow-up events.
	var next_events: Array = result.get("next_events", [])
	for ev_dict in next_events:
		var new_event := ScheduledEvent.create(
			int(ev_dict.get("fire_time", 0)),
			str(ev_dict.get("event_type", "")),
			str(ev_dict.get("owner_id", event.owner_id)),
			ev_dict.get("data", {}),
			int(ev_dict.get("priority", ScheduledEvent.PRIORITY_ARRIVAL)),
		)
		_scheduler.schedule(new_event)

	# Check for auto-pause.
	if result.get("auto_pause", false):
		auto_pause_triggered = true
		auto_pause_reason = result.get("pause_reason", event.event_type)
		pause()

	# Check for combat entry.
	if result.get("enter_combat", false):
		combat_requested = true
		combat_data = result.get("encounter_data", {})
		pause()

	# Check for state transition.
	if result.has("transition_to"):
		transition_requested = result["transition_to"]
		transition_data = result.get("transition_data", {})
		pause()

	return true
