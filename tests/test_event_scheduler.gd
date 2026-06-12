extends "res://tests/test_suite_base.gd"

## Unit tests for EventScheduler and ScheduledEvent.
##
## Tests cover:
##   1. ScheduledEvent creation and serialization
##   2. Priority ordering (fire_time, priority tier, owner_id)
##   3. Schedule / peek / pop cycle
##   4. Cancel single event
##   5. Cancel all events for owner (with and without event_type filter)
##   6. Empty queue behavior
##   7. Persistence round-trip (to_dicts / load_from_dicts)
##   8. schedule_at and schedule_after convenience methods


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

var _scheduler: EventScheduler


func _setup() -> void:
	_scheduler = EventScheduler.new()


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func run_all_tests() -> void:
	test_scheduled_event_creation()
	test_scheduled_event_serialization()
	test_scheduled_event_ordering()
	test_basic_schedule_peek_pop()
	test_fifo_same_time_same_priority()
	test_priority_tiebreaker()
	test_owner_id_tiebreaker()
	test_cancel_single()
	test_cancel_nonexistent()
	test_cancel_all_for_owner()
	test_cancel_all_for_owner_with_type()
	test_empty_queue()
	test_peek_skips_cancelled()
	test_pop_skips_cancelled()
	test_size_excludes_cancelled()
	test_get_events_for_owner()
	test_get_all_events()
	test_schedule_at()
	test_schedule_after()
	test_persistence_round_trip()
	test_tie_order_survives_round_trip()
	test_park_and_release()
	test_cancel_reaches_parked()
	test_bulk_ordering()

	print("  EventScheduler: %d checks, %d failures" % [test_count(), fail_count()])


func test_scheduled_event_creation() -> void:
	var e := ScheduledEvent.create(100, "travel_leg", "party_a", {"hex": "0305"})
	check(e.fire_time == 100, "fire_time should be 100")
	check(e.event_type == "travel_leg", "event_type should be travel_leg")
	check(e.owner_id == "party_a", "owner_id should be party_a")
	check(e.data.has("hex"), "data should contain hex key")
	check(e.priority == ScheduledEvent.PRIORITY_ARRIVAL, "default priority should be ARRIVAL (20)")
	check(not e.cancelled, "should not be cancelled")
	check(not e.event_id.is_empty(), "event_id should be auto-generated")


func test_scheduled_event_serialization() -> void:
	var e := ScheduledEvent.create(200, "encounter_check", "party_b", {"terrain": "forest"}, ScheduledEvent.PRIORITY_SCHEDULED_CHECK)
	var d := e.to_dict()
	var restored := ScheduledEvent.from_dict(d)
	check(restored.event_id == e.event_id, "event_id round-trip")
	check(restored.fire_time == 200, "fire_time round-trip")
	check(restored.event_type == "encounter_check", "event_type round-trip")
	check(restored.owner_id == "party_b", "owner_id round-trip")
	check(restored.data.get("terrain") == "forest", "data round-trip")
	check(restored.priority == ScheduledEvent.PRIORITY_SCHEDULED_CHECK, "priority round-trip")
	check(not restored.cancelled, "cancelled round-trip")


func test_scheduled_event_ordering() -> void:
	var early := ScheduledEvent.create(10, "a", "x")
	var late := ScheduledEvent.create(20, "b", "x")
	check(early.is_before(late), "earlier fire_time should sort first")
	check(not late.is_before(early), "later fire_time should sort second")

	# Same fire_time, different priority
	var low_pri := ScheduledEvent.create(10, "a", "x", {}, 0)
	var high_pri := ScheduledEvent.create(10, "b", "x", {}, 30)
	check(low_pri.is_before(high_pri), "lower priority value should sort first")

	# Same fire_time, same priority, different owner
	var alpha := ScheduledEvent.create(10, "a", "aaa", {}, 10)
	var beta := ScheduledEvent.create(10, "b", "bbb", {}, 10)
	check(alpha.is_before(beta), "alphabetically earlier owner should sort first")


func test_basic_schedule_peek_pop() -> void:
	_setup()
	var id := _scheduler.schedule_at(50, "test_event", "owner_1", {"val": 42})
	check(not id.is_empty(), "schedule_at should return non-empty id")
	check(not _scheduler.is_empty(), "queue should not be empty after schedule")

	var peeked := _scheduler.peek()
	check(peeked != null, "peek should return event")
	check(peeked.fire_time == 50, "peeked event should have correct fire_time")
	check(_scheduler.size() == 1, "peek should not remove event")

	var popped := _scheduler.pop()
	check(popped != null, "pop should return event")
	check(popped.event_id == id, "popped event should match scheduled id")
	check(_scheduler.is_empty(), "queue should be empty after pop")


func test_fifo_same_time_same_priority() -> void:
	_setup()
	# Events at the same time with the same priority and owner should maintain order
	var id1 := _scheduler.schedule_at(100, "type_a", "owner_z", {}, 20)
	var id2 := _scheduler.schedule_at(100, "type_b", "owner_z", {}, 20)
	var first := _scheduler.pop()
	var second := _scheduler.pop()
	# Same fire_time, same priority, same owner — insertion order preserved by
	# binary search insert (stable for equal elements at the end).
	check(first.event_id == id1, "first inserted should come first when all keys equal")
	check(second.event_id == id2, "second inserted should come second")


func test_priority_tiebreaker() -> void:
	_setup()
	# Schedule in reverse priority order
	_scheduler.schedule_at(100, "consequence", "p", {}, ScheduledEvent.PRIORITY_CONSEQUENCE)
	_scheduler.schedule_at(100, "arrival", "p", {}, ScheduledEvent.PRIORITY_ARRIVAL)
	_scheduler.schedule_at(100, "environmental", "p", {}, ScheduledEvent.PRIORITY_ENVIRONMENTAL)
	_scheduler.schedule_at(100, "check", "p", {}, ScheduledEvent.PRIORITY_SCHEDULED_CHECK)

	check(_scheduler.pop().event_type == "environmental", "environmental (0) should be first")
	check(_scheduler.pop().event_type == "check", "check (10) should be second")
	check(_scheduler.pop().event_type == "arrival", "arrival (20) should be third")
	check(_scheduler.pop().event_type == "consequence", "consequence (30) should be fourth")


func test_owner_id_tiebreaker() -> void:
	_setup()
	_scheduler.schedule_at(100, "move", "charlie", {}, 20)
	_scheduler.schedule_at(100, "move", "alpha", {}, 20)
	_scheduler.schedule_at(100, "move", "bravo", {}, 20)

	check(_scheduler.pop().owner_id == "alpha", "alpha should be first")
	check(_scheduler.pop().owner_id == "bravo", "bravo should be second")
	check(_scheduler.pop().owner_id == "charlie", "charlie should be third")


func test_cancel_single() -> void:
	_setup()
	var id := _scheduler.schedule_at(100, "test", "o")
	check(_scheduler.cancel(id), "cancel should return true for existing event")
	check(_scheduler.is_empty(), "queue should be empty after cancelling only event")


func test_cancel_nonexistent() -> void:
	_setup()
	check(not _scheduler.cancel("nonexistent_id"), "cancel should return false for missing id")


func test_cancel_all_for_owner() -> void:
	_setup()
	_scheduler.schedule_at(100, "a", "owner_1")
	_scheduler.schedule_at(200, "b", "owner_1")
	_scheduler.schedule_at(300, "c", "owner_2")

	var count := _scheduler.cancel_all_for_owner("owner_1")
	check(count == 2, "should cancel 2 events for owner_1")
	check(_scheduler.size() == 1, "one event should remain")
	check(_scheduler.peek().owner_id == "owner_2", "remaining event should be owner_2")


func test_cancel_all_for_owner_with_type() -> void:
	_setup()
	_scheduler.schedule_at(100, "travel_leg", "party")
	_scheduler.schedule_at(200, "travel_leg", "party")
	_scheduler.schedule_at(300, "encounter_check", "party")

	var count := _scheduler.cancel_all_for_owner("party", "travel_leg")
	check(count == 2, "should cancel 2 travel_leg events")
	check(_scheduler.size() == 1, "one event should remain")
	check(_scheduler.peek().event_type == "encounter_check", "encounter_check should remain")


func test_empty_queue() -> void:
	_setup()
	check(_scheduler.is_empty(), "new scheduler should be empty")
	check(_scheduler.peek() == null, "peek on empty should return null")
	check(_scheduler.pop() == null, "pop on empty should return null")
	check(_scheduler.size() == 0, "size of empty should be 0")


func test_peek_skips_cancelled() -> void:
	_setup()
	var id1 := _scheduler.schedule_at(100, "a", "o")
	_scheduler.schedule_at(200, "b", "o")
	_scheduler.cancel(id1)
	var peeked := _scheduler.peek()
	check(peeked != null, "peek should skip cancelled and find second event")
	check(peeked.fire_time == 200, "peeked event should be the non-cancelled one")


func test_pop_skips_cancelled() -> void:
	_setup()
	var id1 := _scheduler.schedule_at(100, "a", "o")
	_scheduler.schedule_at(200, "b", "o")
	_scheduler.cancel(id1)
	var popped := _scheduler.pop()
	check(popped.fire_time == 200, "pop should skip cancelled event")
	check(_scheduler.is_empty(), "queue should be empty after popping remaining event")


func test_size_excludes_cancelled() -> void:
	_setup()
	var id1 := _scheduler.schedule_at(100, "a", "o")
	_scheduler.schedule_at(200, "b", "o")
	_scheduler.cancel(id1)
	check(_scheduler.size() == 1, "size should exclude cancelled events")


func test_get_events_for_owner() -> void:
	_setup()
	_scheduler.schedule_at(100, "a", "owner_1")
	_scheduler.schedule_at(200, "b", "owner_2")
	_scheduler.schedule_at(300, "c", "owner_1")
	var events := _scheduler.get_events_for_owner("owner_1")
	check(events.size() == 2, "should return 2 events for owner_1")
	check(events[0].fire_time == 100, "first event should be earliest")
	check(events[1].fire_time == 300, "second event should be latest")


func test_get_all_events() -> void:
	_setup()
	_scheduler.schedule_at(100, "a", "o")
	var id2 := _scheduler.schedule_at(200, "b", "o")
	_scheduler.schedule_at(300, "c", "o")
	_scheduler.cancel(id2)
	var events := _scheduler.get_all_events()
	check(events.size() == 2, "get_all_events should exclude cancelled")


func test_schedule_at() -> void:
	_setup()
	var id := _scheduler.schedule_at(500, "domain_tick", "domain_1", {"month": 3}, ScheduledEvent.PRIORITY_ENVIRONMENTAL)
	var event := _scheduler.peek()
	check(event.fire_time == 500, "fire_time from schedule_at")
	check(event.event_type == "domain_tick", "event_type from schedule_at")
	check(event.priority == ScheduledEvent.PRIORITY_ENVIRONMENTAL, "priority from schedule_at")


func test_schedule_after() -> void:
	_setup()
	var current_time := 1000
	var id := _scheduler.schedule_after(current_time, 120, "encounter_check", "party_a")
	var event := _scheduler.peek()
	check(event.fire_time == 1120, "fire_time should be current_time + delay")


func test_persistence_round_trip() -> void:
	_setup()
	_scheduler.schedule_at(100, "travel_leg", "party_a", {"hex": "0305"}, ScheduledEvent.PRIORITY_ARRIVAL)
	_scheduler.schedule_at(200, "encounter_check", "party_a", {}, ScheduledEvent.PRIORITY_SCHEDULED_CHECK)
	_scheduler.schedule_at(300, "domain_tick", "domain_1", {"month": 3}, ScheduledEvent.PRIORITY_ENVIRONMENTAL)

	var dicts := _scheduler.to_dicts()
	check(dicts.size() == 3, "to_dicts should return 3 events")

	var restored := EventScheduler.new()
	restored.load_from_dicts(dicts)
	check(restored.size() == 3, "restored scheduler should have 3 events")

	var first := restored.pop()
	check(first.fire_time == 100, "restored first event fire_time")
	check(first.event_type == "travel_leg", "restored first event type")
	check(first.data.get("hex") == "0305", "restored first event data")


func test_tie_order_survives_round_trip() -> void:
	_setup()
	# Two events fully tied on (fire_time, priority, owner_id) — FIFO order must
	# survive serialization. Before the sequence stamp, each round-trip REVERSED
	# tie order (lower-bound insert placed re-loaded equals in front).
	var id1 := _scheduler.schedule_at(100, "type_a", "owner_z", {}, 20)
	var id2 := _scheduler.schedule_at(100, "type_b", "owner_z", {}, 20)

	var restored := EventScheduler.new()
	restored.load_from_dicts(_scheduler.to_dicts())
	check(restored.pop().event_id == id1, "first-scheduled tie should still pop first after a round-trip")
	check(restored.pop().event_id == id2, "second-scheduled tie should still pop second after a round-trip")

	# DB rows carry no sequence column — sequence-less dicts must be re-stamped
	# in load order (get_scheduled_events returns saved queue order).
	var stripped: Array = []
	for d in _scheduler.to_dicts():
		var c: Dictionary = d.duplicate()
		c.erase("sequence")
		stripped.append(c)
	var restamped := EventScheduler.new()
	restamped.load_from_dicts(stripped)
	check(restamped.pop().event_id == id1, "sequence-less dicts (DB rows) should keep saved order")
	check(restamped.pop().event_id == id2, "sequence-less dicts (DB rows) keep saved order for the second event")


func test_park_and_release() -> void:
	_setup()
	# Park-don't-consume (Batch E): an event popped with no handler is parked —
	# out of the fireable queue but still a pending obligation — and released
	# back into the queue when its handler type registers.
	var id := _scheduler.schedule_at(100, "orphan_type", "owner_p")
	var ev := _scheduler.pop()
	check(ev != null and ev.event_id == id, "popped the event")
	_scheduler.park(ev)
	check(_scheduler.is_empty(), "parked event is not in the fireable queue")
	check(_scheduler.size() == 1, "parked event still counts as pending")
	check(_scheduler.get_events_for_owner("owner_p").size() == 1,
		"parked event visible to owner queries (idempotency checks)")
	check(_scheduler.to_dicts().size() == 1, "parked event persists via to_dicts")
	var released := _scheduler.release_parked("orphan_type")
	check(released == 1, "release re-queues the parked event")
	check(not _scheduler.is_empty(), "released event is fireable again")
	var popped := _scheduler.pop()
	check(popped != null and popped.event_id == id, "released event pops with its original id")


func test_cancel_reaches_parked() -> void:
	_setup()
	_scheduler.schedule_at(100, "orphan_type", "owner_q")
	_scheduler.park(_scheduler.pop())
	var n := _scheduler.cancel_all_for_owner("owner_q")
	check(n == 1, "cancel_all_for_owner reaches parked events")
	check(_scheduler.release_parked("orphan_type") == 0,
		"cancelled parked events are not released")
	check(_scheduler.size() == 0, "cancelled parked events do not count as pending")


func test_bulk_ordering() -> void:
	_setup()
	# Insert 20 events in random fire_time order and verify they come out sorted
	var times := [50, 10, 90, 30, 70, 20, 80, 40, 60, 100, 15, 85, 35, 65, 5, 95, 25, 75, 45, 55]
	for t in times:
		_scheduler.schedule_at(t, "test", "o")

	var prev_time := -1
	while not _scheduler.is_empty():
		var event := _scheduler.pop()
		check(event.fire_time >= prev_time, "events should come out in ascending fire_time order (got %d after %d)" % [event.fire_time, prev_time])
		prev_time = event.fire_time
