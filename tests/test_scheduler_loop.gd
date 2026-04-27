extends "res://tests/test_suite_base.gd"

## Unit tests for SchedulerLoop.
##
## Tests cover:
##   1. Tick does nothing when paused
##   2. Normal speed advances clock and resolves events
##   3. Fast speed resolves events faster
##   4. MAX speed resolves next event instantly
##   5. Auto-pause stops the loop
##   6. Combat request stops the loop
##   7. Fractional round accumulation
##   8. Event handler follow-up scheduling
##   9. Speed control methods
##  10. Empty queue at MAX speed pauses


const TEST_PARTY := "test_party_loop"

var _scheduler: EventScheduler
var _registry: EventHandlerRegistry
var _loop: SchedulerLoop

var _resolved_events: Array = []
var _speed_changes: Array = []


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _setup() -> void:
	_resolved_events.clear()
	_speed_changes.clear()

	# Reset Timekeeping
	Timekeeping._elapsed_rounds = 0
	Timekeeping._party_clocks.clear()
	Timekeeping.register_party(TEST_PARTY)

	_scheduler = EventScheduler.new()
	_registry = EventHandlerRegistry.new()
	_loop = SchedulerLoop.new()
	_loop.setup(_scheduler, _registry, TEST_PARTY)

	# Connect signals for verification
	if not EventBus.scheduler_speed_changed.is_connected(_on_speed_changed):
		EventBus.scheduler_speed_changed.connect(_on_speed_changed)


func _cleanup() -> void:
	Timekeeping.unregister_party(TEST_PARTY)
	Timekeeping._elapsed_rounds = 0
	if EventBus.scheduler_speed_changed.is_connected(_on_speed_changed):
		EventBus.scheduler_speed_changed.disconnect(_on_speed_changed)


func _on_speed_changed(speed: int) -> void:
	_speed_changes.append(speed)


## A simple handler that records the event and returns no follow-ups.
func _simple_handler(event: ScheduledEvent) -> Dictionary:
	_resolved_events.append(event.event_type)
	return {}


## A handler that triggers auto-pause.
func _pause_handler(event: ScheduledEvent) -> Dictionary:
	_resolved_events.append(event.event_type)
	return {"auto_pause": true, "pause_reason": "encounter detected"}


## A handler that requests combat.
func _combat_handler(event: ScheduledEvent) -> Dictionary:
	_resolved_events.append(event.event_type)
	return {"enter_combat": true, "encounter_data": {"monster": "goblin"}}


## A handler that schedules a follow-up event.
func _chain_handler(event: ScheduledEvent) -> Dictionary:
	_resolved_events.append(event.event_type)
	var current_time: int = event.fire_time
	return {
		"next_events": [
			{
				"fire_time": current_time + 10,
				"event_type": "chained_event",
				"owner_id": event.owner_id,
				"data": {},
				"priority": ScheduledEvent.PRIORITY_ARRIVAL,
			}
		]
	}


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func run_all_tests() -> void:
	test_tick_when_paused()
	test_tick_normal_speed()
	test_tick_fast_speed()
	test_tick_max_speed()
	test_auto_pause_stops_loop()
	test_combat_request_stops_loop()
	test_fractional_accumulation()
	test_follow_up_events()
	test_speed_control_methods()
	test_max_speed_empty_queue_pauses()
	test_toggle_pause()
	test_c1_dungeon_normal_multiplier()
	test_c1_dungeon_fast_multiplier()
	test_c1_dungeon_very_fast_multiplier()
	test_c1_wilderness_speeds_unchanged()
	test_c1_settlement_speeds_unchanged()

	_cleanup()
	print("  SchedulerLoop: %d checks, %d failures" % [test_count(), fail_count()])


func test_tick_when_paused() -> void:
	_setup()
	_registry.register("test", _simple_handler)
	_scheduler.schedule_at(1, "test", TEST_PARTY)

	# Loop starts paused — tick should do nothing.
	var resolved := _loop.tick(1.0)
	check(resolved == 0, "paused loop should resolve 0 events")
	check(_resolved_events.is_empty(), "no events should fire while paused")
	check(Timekeeping.get_party_time(TEST_PARTY) == 0, "clock should not advance while paused")


func test_tick_normal_speed() -> void:
	_setup()
	_registry.register("test", _simple_handler)
	# At NORMAL speed, 1 real second = 1 round / SECONDS_PER_ROUND.
	# SECONDS_PER_ROUND = 2.0, so 1 real second = 0.5 rounds.
	# Schedule event at round 1. Need 2 real seconds to reach it.
	_scheduler.schedule_at(1, "test", TEST_PARTY)
	_loop.set_speed(SchedulerLoop.SPEED_NORMAL)

	# First tick: 2 seconds of real time = 1 round
	var resolved := _loop.tick(2.0)
	check(resolved == 1, "should resolve 1 event after 2 seconds at NORMAL speed")
	check(_resolved_events.size() == 1, "one handler should have fired")
	check(_resolved_events[0] == "test", "correct event type should resolve")


func test_tick_fast_speed() -> void:
	_setup()
	_registry.register("test", _simple_handler)
	_scheduler.schedule_at(2, "test", TEST_PARTY)
	_loop.set_speed(SchedulerLoop.SPEED_FAST)

	# FAST = 2, so 1 real second = 2 rounds / SECONDS_PER_ROUND = 1 round.
	# Need 2 seconds for round 2.
	# Actually: rounds_per_second = speed / SECONDS_PER_ROUND = 2 / 2.0 = 1.0
	# So after 2 real seconds we have 2 accumulated rounds.
	var resolved := _loop.tick(2.0)
	check(resolved == 1, "should resolve event at round 2 with 2s at FAST speed")


func test_tick_max_speed() -> void:
	_setup()
	_registry.register("test", _simple_handler)
	_scheduler.schedule_at(1000, "test", TEST_PARTY)
	_loop.set_speed(SchedulerLoop.SPEED_MAX)

	# MAX instantly jumps to next event regardless of real delta.
	var resolved := _loop.tick(0.016)  # ~1 frame
	check(resolved == 1, "MAX speed should resolve event instantly")
	check(Timekeeping.get_party_time(TEST_PARTY) == 1000, "clock should jump to fire_time at MAX speed")


func test_auto_pause_stops_loop() -> void:
	_setup()
	_registry.register("pause_event", _pause_handler)
	_registry.register("after_event", _simple_handler)
	_scheduler.schedule_at(1, "pause_event", TEST_PARTY)
	_scheduler.schedule_at(2, "after_event", TEST_PARTY)
	_loop.set_speed(SchedulerLoop.SPEED_MAX)

	_loop.tick(0.016)
	check(_loop.is_paused(), "loop should be paused after auto-pause event")
	check(_loop.auto_pause_triggered, "auto_pause_triggered flag should be set")
	check(_loop.auto_pause_reason == "encounter detected", "pause reason should be set")
	check(_resolved_events.size() == 1, "only the pause event should have resolved")
	check(_resolved_events[0] == "pause_event", "correct event should have resolved")


func test_combat_request_stops_loop() -> void:
	_setup()
	_registry.register("combat_event", _combat_handler)
	_scheduler.schedule_at(1, "combat_event", TEST_PARTY)
	_loop.set_speed(SchedulerLoop.SPEED_MAX)

	_loop.tick(0.016)
	check(_loop.combat_requested, "combat_requested should be true")
	check(_loop.combat_data.get("monster") == "goblin", "combat_data should be populated")
	check(_loop.is_paused(), "loop should pause for combat")


func test_fractional_accumulation() -> void:
	_setup()
	_registry.register("test", _simple_handler)
	_scheduler.schedule_at(1, "test", TEST_PARTY)
	_loop.set_speed(SchedulerLoop.SPEED_NORMAL)

	# NORMAL: rounds_per_second = 1/2.0 = 0.5
	# Tick 1: 0.5 real seconds -> 0.25 rounds (not enough for round 1)
	var r1 := _loop.tick(0.5)
	check(r1 == 0, "0.5s at normal should not reach round 1 yet")

	# Tick 2: another 0.5s -> accumulated = 0.5 (still not enough)
	var r2 := _loop.tick(0.5)
	check(r2 == 0, "1.0s total at normal should accumulate 0.5 rounds, not enough")

	# Tick 3: another 2.0s -> accumulated = 0.5 + 1.0 = 1.5 (enough for round 1)
	var r3 := _loop.tick(2.0)
	check(r3 == 1, "should resolve event once enough rounds accumulated")


func test_follow_up_events() -> void:
	_setup()
	_registry.register("chain_start", _chain_handler)
	_registry.register("chained_event", _simple_handler)
	_scheduler.schedule_at(10, "chain_start", TEST_PARTY)
	_loop.set_speed(SchedulerLoop.SPEED_MAX)

	# First tick: resolves chain_start, which schedules chained_event at round 20.
	_loop.tick(0.016)
	check(_resolved_events.size() == 1, "first tick resolves chain_start")
	check(_resolved_events[0] == "chain_start", "chain_start fires first")
	check(not _scheduler.is_empty(), "chained_event should be in queue")

	# Second tick at MAX: resolves chained_event.
	_loop.tick(0.016)
	check(_resolved_events.size() == 2, "second tick resolves chained_event")
	check(_resolved_events[1] == "chained_event", "chained_event fires second")
	check(Timekeeping.get_party_time(TEST_PARTY) == 20, "clock should be at round 20")


func test_speed_control_methods() -> void:
	_setup()
	check(_loop.is_paused(), "should start paused")
	check(_loop.get_speed() == SchedulerLoop.SPEED_PAUSED, "initial speed should be PAUSED")

	_loop.set_speed(SchedulerLoop.SPEED_FAST)
	check(not _loop.is_paused(), "should not be paused after set_speed(FAST)")
	check(_loop.get_speed() == SchedulerLoop.SPEED_FAST, "speed should be FAST")

	_loop.pause()
	check(_loop.is_paused(), "pause() should pause")

	_loop.resume(SchedulerLoop.SPEED_VERY_FAST)
	check(not _loop.is_paused(), "resume should unpause")
	check(_loop.get_speed() == SchedulerLoop.SPEED_VERY_FAST, "speed should be VERY_FAST after resume")


func test_max_speed_empty_queue_pauses() -> void:
	_setup()
	_loop.set_speed(SchedulerLoop.SPEED_MAX)

	var resolved := _loop.tick(0.016)
	check(resolved == 0, "empty queue should resolve nothing")
	check(_loop.is_paused(), "MAX speed with empty queue should auto-pause")
	check(_loop.auto_pause_triggered, "auto_pause_triggered should be set for empty queue")


func test_toggle_pause() -> void:
	_setup()
	_loop.toggle_pause(SchedulerLoop.SPEED_NORMAL)
	check(not _loop.is_paused(), "toggle from paused should resume")
	check(_loop.get_speed() == SchedulerLoop.SPEED_NORMAL, "toggle should resume at requested speed")

	_loop.toggle_pause()
	check(_loop.is_paused(), "toggle from running should pause")


# ---------------------------------------------------------------------------
# C1 — Per-context speed bands
# ---------------------------------------------------------------------------

func test_c1_dungeon_normal_multiplier() -> void:
	_setup()
	_loop.set_timescale(SchedulerLoop.TIMESCALE_DUNGEON)
	_loop.set_speed(SchedulerLoop.SPEED_NORMAL)
	check(_loop.get_effective_multiplier() == 1.0,
		"dungeon Normal should resolve to 1×, got %.1f" % _loop.get_effective_multiplier())


func test_c1_dungeon_fast_multiplier() -> void:
	# Per the smoke-test prompt: dungeon Fast = 6 rounds (1 minute) per 2
	# real seconds. With SECONDS_PER_ROUND=2 and timescale=1, that's
	# multiplier = 6 → rounds/sec = 3.
	_setup()
	_loop.set_timescale(SchedulerLoop.TIMESCALE_DUNGEON)
	_loop.set_speed(SchedulerLoop.SPEED_FAST)
	check(_loop.get_effective_multiplier() == 6.0,
		"dungeon Fast should resolve to 6×, got %.1f" % _loop.get_effective_multiplier())


func test_c1_dungeon_very_fast_multiplier() -> void:
	# Dungeon Very Fast = 30 rounds (5 minutes) per 2 real seconds.
	_setup()
	_loop.set_timescale(SchedulerLoop.TIMESCALE_DUNGEON)
	_loop.set_speed(SchedulerLoop.SPEED_VERY_FAST)
	check(_loop.get_effective_multiplier() == 30.0,
		"dungeon Very Fast should resolve to 30×, got %.1f" % _loop.get_effective_multiplier())


func test_c1_wilderness_speeds_unchanged() -> void:
	# Wilderness keeps the prior 1×/2×/5× because TIMESCALE_WILDERNESS=60
	# already amplifies the band — bumping wilderness Very Fast to 30 would
	# push it to 9000× real time.
	_setup()
	_loop.set_timescale(SchedulerLoop.TIMESCALE_WILDERNESS)
	_loop.set_speed(SchedulerLoop.SPEED_NORMAL)
	check(_loop.get_effective_multiplier() == 1.0, "wilderness Normal = 1×")
	_loop.set_speed(SchedulerLoop.SPEED_FAST)
	check(_loop.get_effective_multiplier() == 2.0, "wilderness Fast = 2×")
	_loop.set_speed(SchedulerLoop.SPEED_VERY_FAST)
	check(_loop.get_effective_multiplier() == 5.0, "wilderness Very Fast = 5×")


func test_c1_settlement_speeds_unchanged() -> void:
	_setup()
	_loop.set_timescale(SchedulerLoop.TIMESCALE_SETTLEMENT)
	_loop.set_speed(SchedulerLoop.SPEED_FAST)
	check(_loop.get_effective_multiplier() == 2.0,
		"settlement Fast keeps prior 2×, got %.1f" % _loop.get_effective_multiplier())
