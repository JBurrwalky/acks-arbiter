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

	# Reset Timekeeping (single shared timeline — the loop advances the
	# world clock; TEST_PARTY is only the loop's session-loaded guard)
	Timekeeping._elapsed_rounds = 0

	_scheduler = EventScheduler.new()
	_registry = EventHandlerRegistry.new()
	# Production wiring (SessionRunner._ready does the same): registering a
	# handler releases any events of that type parked while it was absent.
	_registry.set_scheduler(_scheduler)
	_loop = SchedulerLoop.new()
	_loop.setup(_scheduler, _registry, TEST_PARTY)

	# The legacy tests below compute rounds/sec assuming timescale 1.0. The
	# loop's default is TIMESCALE_WILDERNESS (60), which silently ran them 60×
	# fast — pin the dungeon timescale; C1 tests override per-test as needed.
	_loop.set_timescale(SchedulerLoop.TIMESCALE_DUNGEON)

	# Connect signals for verification
	if not EventBus.scheduler_speed_changed.is_connected(_on_speed_changed):
		EventBus.scheduler_speed_changed.connect(_on_speed_changed)


func _cleanup() -> void:
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
	test_due_event_resolves_without_full_accumulation()
	test_same_time_events_resolve_in_one_pass()
	test_unhandled_event_parks_and_resolves_on_register()
	test_delta_clamp_bounds_time_jump()
	test_set_speed_emits_pause_resume_signals()
	test_stale_pause_reason_not_replayed()
	test_max_speed_empty_queue_signal_reason()
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
	check(Timekeeping.get_total_rounds() == 0, "clock should not advance while paused")


func test_tick_normal_speed() -> void:
	_setup()
	_registry.register("test", _simple_handler)
	# At dungeon NORMAL, rounds/sec = 1 × 1.0 / SECONDS_PER_ROUND (2.0) = 0.5.
	# Schedule event at round 1: 2 real seconds reach it. Deltas above
	# MAX_TICK_DELTA are clamped, so feed 8 × 0.25s frames.
	_scheduler.schedule_at(1, "test", TEST_PARTY)
	_loop.set_speed(SchedulerLoop.SPEED_NORMAL)

	var resolved := 0
	for i in 8:
		resolved += _loop.tick(0.25)
	check(resolved == 1, "should resolve 1 event after 2 seconds at NORMAL speed")
	check(_resolved_events.size() == 1, "one handler should have fired")
	check(_resolved_events[0] == "test", "correct event type should resolve")


func test_tick_fast_speed() -> void:
	_setup()
	_registry.register("test", _simple_handler)
	_scheduler.schedule_at(2, "test", TEST_PARTY)
	_loop.set_speed(SchedulerLoop.SPEED_FAST)

	# Dungeon FAST band = ×6 → rounds/sec = 6 × 1.0 / 2.0 = 3. The event at
	# round 2 needs 2/3s of real time; 3 × 0.25s frames give 2.25 rounds.
	var resolved := 0
	for i in 3:
		resolved += _loop.tick(0.25)
	check(resolved == 1, "should resolve event at round 2 within 0.75s at dungeon FAST speed")


func test_tick_max_speed() -> void:
	_setup()
	_registry.register("test", _simple_handler)
	_scheduler.schedule_at(1000, "test", TEST_PARTY)
	_loop.set_speed(SchedulerLoop.SPEED_MAX)

	# MAX instantly jumps to next event regardless of real delta.
	var resolved := _loop.tick(0.016)  # ~1 frame
	check(resolved == 1, "MAX speed should resolve event instantly")
	check(Timekeeping.get_total_rounds() == 1000, "clock should jump to fire_time at MAX speed")


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

	# Dungeon NORMAL: rounds/sec = 0.5, so each 0.25s frame adds 0.125 rounds.
	var r1 := _loop.tick(0.25)
	check(r1 == 0, "0.25s at normal should not reach round 1 yet")

	var r2 := _loop.tick(0.25)
	check(r2 == 0, "0.5s total at normal accumulates 0.25 rounds, not enough")

	# Six more 0.25s frames -> 8 × 0.125 = exactly 1.0 round accumulated.
	var resolved_later := 0
	for i in 6:
		resolved_later += _loop.tick(0.25)
	check(resolved_later == 1, "should resolve event once enough rounds accumulated")


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
	check(Timekeeping.get_total_rounds() == 20, "clock should be at round 20")


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


func test_due_event_resolves_without_full_accumulation() -> void:
	_setup()
	_registry.register("test", _simple_handler)
	_scheduler.schedule_at(0, "test", TEST_PARTY)  # due immediately (clock = 0)
	_loop.set_speed(SchedulerLoop.SPEED_NORMAL)

	# One ~frame-sized tick accumulates far less than a full round, but a due
	# event costs zero rounds — it must not wait for the >= 1.0 gate.
	var resolved := _loop.tick(0.016)
	check(resolved == 1, "already-due event should resolve without a full round of real time")
	check(Timekeeping.get_total_rounds() == 0, "resolving a due event should not advance the clock")


func test_same_time_events_resolve_in_one_pass() -> void:
	_setup()
	_registry.register("test_a", _simple_handler)
	_registry.register("test_b", _simple_handler)
	_scheduler.schedule_at(1, "test_a", TEST_PARTY)
	_scheduler.schedule_at(1, "test_b", TEST_PARTY)
	_loop.set_speed(SchedulerLoop.SPEED_NORMAL)

	var resolved := 0
	for i in 8:
		resolved += _loop.tick(0.25)
	check(resolved == 2, "both events at the same fire_time should resolve in the same pass")
	check(_resolved_events == ["test_a", "test_b"],
		"same-time same-priority events resolve in scheduling order (got %s)" % str(_resolved_events))


func test_unhandled_event_parks_and_resolves_on_register() -> void:
	_setup()
	# Park-don't-consume (Batch E): no handler exists for "late_bound" when the
	# event comes due — previously it was popped and silently destroyed.
	_scheduler.schedule_at(1, "late_bound", TEST_PARTY)
	_loop.set_speed(SchedulerLoop.SPEED_MAX)
	var r1 := _loop.tick(0.016)
	check(r1 == 0, "unhandled event must not count as resolved")
	check(_resolved_events.is_empty(), "no handler fired for the parked event")
	check(_scheduler.size() == 1, "event should be parked, not destroyed")
	# Registering the handler releases the parked event; it resolves next tick.
	_registry.register("late_bound", _simple_handler)
	var r2 := _loop.tick(0.016)
	check(r2 == 1, "released event resolves once a handler exists")
	check(_resolved_events == ["late_bound"], "the parked event was delivered")


func test_delta_clamp_bounds_time_jump() -> void:
	_setup()
	_loop.set_timescale(SchedulerLoop.TIMESCALE_WILDERNESS)
	_loop.set_speed(SchedulerLoop.SPEED_VERY_FAST)

	# Wilderness VERY_FAST = 5 × 60 / 2.0 = 150 rounds/sec. A 10s frame hitch
	# would jump 1500 rounds unclamped; the clamp caps it at 0.25s of real time.
	_loop.tick(10.0)
	var bound := int(SchedulerLoop.MAX_TICK_DELTA * 150.0)
	check(Timekeeping.get_total_rounds() <= bound,
		"a frame hitch must not fast-forward past the clamp bound (got %d, bound %d)"
		% [Timekeeping.get_total_rounds(), bound])


func test_set_speed_emits_pause_resume_signals() -> void:
	_setup()
	var pause_reasons: Array = []
	var resume_count: Array = [0]
	var on_paused := func(reason: String) -> void: pause_reasons.append(reason)
	var on_resumed := func() -> void: resume_count[0] += 1
	EventBus.scheduler_paused.connect(on_paused)
	EventBus.scheduler_resumed.connect(on_resumed)

	_loop.set_speed(SchedulerLoop.SPEED_NORMAL)
	check(resume_count[0] == 1, "set_speed from paused should emit scheduler_resumed")
	_loop.set_speed(SchedulerLoop.SPEED_PAUSED)
	check(pause_reasons == ["paused"], "set_speed(PAUSED) should emit scheduler_paused")
	_loop.set_speed(SchedulerLoop.SPEED_FAST)
	check(resume_count[0] == 2, "unpausing via set_speed should emit scheduler_resumed again")

	EventBus.scheduler_paused.disconnect(on_paused)
	EventBus.scheduler_resumed.disconnect(on_resumed)


func test_stale_pause_reason_not_replayed() -> void:
	_setup()
	_registry.register("pause_event", _pause_handler)
	_scheduler.schedule_at(1, "pause_event", TEST_PARTY)
	_loop.set_speed(SchedulerLoop.SPEED_MAX)
	_loop.tick(0.016)  # auto-pauses with reason "encounter detected"
	check(_loop.auto_pause_reason == "encounter detected", "auto-pause reason recorded")

	var pause_reasons: Array = []
	var on_paused := func(reason: String) -> void: pause_reasons.append(reason)
	EventBus.scheduler_paused.connect(on_paused)

	_loop.set_speed(SchedulerLoop.SPEED_NORMAL)  # player unpauses via the toolbar
	_loop.pause()  # later, an unrelated plain pause
	check(pause_reasons == ["paused"],
		"a plain pause after unpausing must not replay the old auto-pause reason (got %s)"
		% str(pause_reasons))

	EventBus.scheduler_paused.disconnect(on_paused)


func test_max_speed_empty_queue_signal_reason() -> void:
	_setup()
	var pause_reasons: Array = []
	var on_paused := func(reason: String) -> void: pause_reasons.append(reason)
	EventBus.scheduler_paused.connect(on_paused)

	_loop.set_speed(SchedulerLoop.SPEED_MAX)
	_loop.tick(0.016)
	check(pause_reasons == ["No events scheduled"],
		"empty-queue MAX pause should broadcast its reason via scheduler_paused (got %s)"
		% str(pause_reasons))
	check(_loop.auto_pause_reason == "No events scheduled",
		"auto_pause_reason should match the broadcast reason")

	EventBus.scheduler_paused.disconnect(on_paused)


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
