class_name SchedulerLoop
extends RefCounted

## Tick-driven loop that advances the game clock and resolves scheduled events.
##
## Called from SessionRunner._process(delta). Reads real-world delta time,
## converts it to game-time rounds based on the current speed multiplier,
## advances Timekeeping, and pops/resolves events from the EventScheduler.
##
## Speed settings (band ordinals, mapped through a per-context multiplier table):
##   PAUSED (0)     — no advancement
##   NORMAL (1)     — base band (×1 in every context)
##   FAST (2)       — fast band (dungeon ×6; wilderness/settlement ×2)
##   VERY_FAST (5)  — fastest band (dungeon ×30; wilderness/settlement ×5)
##   MAX (-1)       — instant advance to next event (no real-time delay)
##
## Real-time → game-time conversion:
##   rounds/sec = band multiplier × timescale / SECONDS_PER_ROUND
## e.g. dungeon NORMAL = 1 × 1.0 / 2.0 = 0.5 rounds/sec (one round per 2s).
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

## Upper bound on a single frame's real delta. A frame hitch (window drag on
## Windows, IO stall) can deliver a multi-second delta; unclamped, that converts
## into hours of game time, a boundary-signal storm, and dozens of eager DB
## saves in one frame. Excess real time beyond the clamp is simply dropped.
const MAX_TICK_DELTA := 0.25

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

## Diagnostic flags set when auto-pause fires. NOT consumed by SessionRunner —
## the reason reaches the UI inside the scheduler_paused signal (pause(reason));
## these fields exist for tests and debugging. resume() clears them.
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

## [param party_id] identifies the session's primary party. The loop advances
## the single shared world clock (Jedidiah ruling 2026-06-11) — the party_id is
## retained only as a "session is loaded" guard for tick().
func setup(scheduler: EventScheduler, registry: EventHandlerRegistry, party_id: String) -> void:
	_scheduler = scheduler
	_registry = registry
	_party_id = party_id
	_speed = SPEED_PAUSED
	_paused = true
	_accumulated_rounds = 0.0


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

## Single entry point for UI speed requests. Delegates to pause()/resume() at
## the pause boundary so scheduler_paused/scheduler_resumed always fire and
## stale auto-pause state is always cleared; a running→running change only
## retunes the speed band.
func set_speed(speed: int) -> void:
	if speed == SPEED_PAUSED:
		pause()
		return
	if _paused:
		resume(speed)
		return
	var old_speed := _speed
	_speed = speed
	_accumulated_rounds = 0.0
	if old_speed != speed:
		EventBus.scheduler_speed_changed.emit(speed)


func get_speed() -> int:
	return _speed


## Pause the loop. [param reason] is stored in auto_pause_reason and broadcast
## via scheduler_paused — producers pass the reason HERE instead of pre-setting
## the field, so the signal can never carry a stale reason from an earlier
## pause. A plain pause() clears any previous reason. No-op if already paused.
func pause(reason: String = "") -> void:
	if _paused:
		return
	_paused = true
	_speed = SPEED_PAUSED
	auto_pause_reason = reason
	EventBus.scheduler_speed_changed.emit(SPEED_PAUSED)
	EventBus.scheduler_paused.emit(reason if not reason.is_empty() else "paused")


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
	_accumulated_rounds += minf(real_delta, MAX_TICK_DELTA) * rounds_per_second

	var events_resolved := 0
	var max_events_per_tick := 20  # Safety cap to prevent infinite loops

	# Due events (fire_time <= now) cost zero accumulated rounds to resolve, so
	# they must not be stranded behind the >= 1.0 accumulator gate — e.g. right
	# after resume() zeroed the accumulator with an overdue event at the head.
	while (_accumulated_rounds >= 1.0 or _is_head_due()) and events_resolved < max_events_per_tick:
		var next_event := _scheduler.peek()
		# Rounds needed to reach the queue head; 0 when overdue (resolve now).
		var rounds_to_event := 0
		if next_event != null:
			rounds_to_event = maxi(0, next_event.fire_time - Timekeeping.get_total_rounds())

		if next_event == null or float(rounds_to_event) > _accumulated_rounds:
			# No events, or the next one is beyond this tick's reach — drain
			# the accumulated whole rounds and stop. (Single shared drain;
			# this block was previously duplicated in both arms.)
			var whole_rounds := int(_accumulated_rounds)
			if whole_rounds > 0:
				Timekeeping.advance_rounds(whole_rounds)
			_accumulated_rounds -= float(whole_rounds)
			break

		# Advance to the event's fire_time.
		if rounds_to_event > 0:
			Timekeeping.advance_rounds(rounds_to_event)
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


## True when the queue head is already due at the current clock time.
func _is_head_due() -> bool:
	var head := _scheduler.peek()
	return head != null and head.fire_time <= Timekeeping.get_total_rounds()


## Max speed: instantly advance to and resolve the next event.
## Resolves one event per call to avoid blocking the main thread for too long.
func _tick_max_speed() -> int:
	var next_event := _scheduler.peek()
	if next_event == null:
		auto_pause_triggered = true
		pause("No events scheduled")
		return 0

	var current_time := Timekeeping.get_total_rounds()
	var rounds_to_advance := next_event.fire_time - current_time

	if rounds_to_advance > 0:
		Timekeeping.advance_rounds(rounds_to_advance)

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

	# Park-don't-consume (2026-06-12): an event due while its handler is
	# unregistered (context-scoped handler, player in another context) must
	# not be destroyed. Park it; EventHandlerRegistry.register() re-injects it
	# when the handler comes back — e.g. commission_ready fired mid-wilderness
	# is delivered on the next settlement entry.
	if not _registry.has_handler(event.event_type):
		_scheduler.park(event)
		push_warning("SchedulerLoop: no handler for '%s' (owner %s) — event parked until one registers"
			% [event.event_type, event.owner_id])
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
		pause(result.get("pause_reason", event.event_type))

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
