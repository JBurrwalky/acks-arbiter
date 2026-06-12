class_name EventScheduler
extends RefCounted

## Priority queue of ScheduledEvents ordered by fire_time, priority, owner_id.
##
## The EventScheduler is the backbone of the real-time-with-pause game loop.
## It stores future events and serves them in chronological order. It does NOT
## advance the clock or call handlers — that is SchedulerLoop's job.
##
## Owned by SessionRunner, NOT an autoload.
##
## Implementation: sorted Array with binary-search insertion. GDScript lacks
## a native heap, and the expected queue size (tens to low hundreds of events)
## makes sorted-array insertion O(n) perfectly acceptable.


# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------

## Sorted array of ScheduledEvent. Index 0 = earliest (next to fire).
var _queue: Array[ScheduledEvent] = []

## Fast lookup: event_id → ScheduledEvent for O(1) cancel.
var _id_index: Dictionary = {}  # { String: ScheduledEvent }

## Monotonic counter stamped onto events at schedule() time as the final FIFO
## tiebreaker. Events loaded without a sequence (DB rows carry none) are stamped
## in load order, which equals saved queue order — campaign_repository orders by
## (fire_time, rowid) — so tie order survives save/load round-trips.
var _next_sequence: int = 0

## Events that came due with no registered handler (park-don't-consume,
## 2026-06-12). Previously such events were popped and silently destroyed —
## killing e.g. commission_ready notifications fired outside a settlement.
## Parked events are OUT of the fireable queue but still pending obligations:
## they appear in to_dicts()/size()/owner queries, are reachable by
## cancel_all_for_owner, and release_parked() re-injects them when a handler
## for their type registers (wired via EventHandlerRegistry.register).
var _parked: Array[ScheduledEvent] = []


# ---------------------------------------------------------------------------
# Scheduling
# ---------------------------------------------------------------------------

## Insert an event into the queue. Returns the event's id.
func schedule(event: ScheduledEvent) -> String:
	# Tripwire for the day-axis bug class: fire_time is ROUNDS (8,640 per day).
	# A fire_time far in the past usually means a caller scheduled a calendar-day
	# serial (~hundreds) onto the rounds axis — convert via
	# Timekeeping.calendar_day_to_rounds(). Legitimate catch-up chains can trip
	# this after large GM time skips, so it warns rather than asserts.
	if event.fire_time < Timekeeping.get_total_rounds() - 2 * Timekeeping.ROUNDS_PER_DAY:
		push_warning(
			"EventScheduler.schedule: '%s' fire_time %d is >2 days in the past (now %d) — day-axis value scheduled as rounds?"
			% [event.event_type, event.fire_time, Timekeeping.get_total_rounds()])
	if event.event_id.is_empty():
		event.event_id = CampaignRepository.generate_id()
	if event.sequence < 0:
		event.sequence = _next_sequence
	_next_sequence = maxi(_next_sequence, event.sequence) + 1
	_id_index[event.event_id] = event
	_insert_sorted(event)
	return event.event_id


## Convenience: create and schedule an event, returning its id.
func schedule_at(
	fire_time: int,
	event_type: String,
	owner_id: String,
	data: Dictionary = {},
	priority: int = ScheduledEvent.PRIORITY_ARRIVAL
) -> String:
	var event := ScheduledEvent.create(fire_time, event_type, owner_id, data, priority)
	return schedule(event)


## Convenience: schedule an event relative to [param current_time].
func schedule_after(
	current_time: int,
	delay_rounds: int,
	event_type: String,
	owner_id: String,
	data: Dictionary = {},
	priority: int = ScheduledEvent.PRIORITY_ARRIVAL
) -> String:
	return schedule_at(current_time + delay_rounds, event_type, owner_id, data, priority)


# ---------------------------------------------------------------------------
# Cancellation
# ---------------------------------------------------------------------------

## Cancel a single event by id. Returns true if found and cancelled.
func cancel(event_id: String) -> bool:
	var event: ScheduledEvent = _id_index.get(event_id)
	if event == null or event.cancelled:
		return false
	event.cancelled = true
	return true


## Cancel all events owned by [param owner_id] — queued AND parked.
## If [param event_type] is non-empty, only cancel events of that type.
func cancel_all_for_owner(owner_id: String, event_type: String = "") -> int:
	var count := 0
	for event in _queue:
		if event.cancelled:
			continue
		if event.owner_id != owner_id:
			continue
		if not event_type.is_empty() and event.event_type != event_type:
			continue
		event.cancelled = true
		count += 1
	for event in _parked:
		if event.cancelled:
			continue
		if event.owner_id != owner_id:
			continue
		if not event_type.is_empty() and event.event_type != event_type:
			continue
		event.cancelled = true
		count += 1
	return count


# ---------------------------------------------------------------------------
# Parking (unhandled-event deferral)
# ---------------------------------------------------------------------------

## Park an event that came due with no registered handler (called by
## SchedulerLoop after popping it). The event stays a pending obligation;
## release_parked() re-queues it when its handler registers.
func park(event: ScheduledEvent) -> void:
	if event == null or event.cancelled:
		return
	_parked.append(event)
	_id_index[event.event_id] = event


## Re-inject all parked events of [param event_type] into the queue. Their
## fire_times are typically in the past, so they resolve on the next tick.
## Returns the number of events released. Called by
## EventHandlerRegistry.register() when a handler for the type appears.
func release_parked(event_type: String) -> int:
	var released := 0
	var remaining: Array[ScheduledEvent] = []
	for event in _parked:
		if event.cancelled:
			_id_index.erase(event.event_id)
			continue
		if event.event_type == event_type:
			schedule(event)
			released += 1
		else:
			remaining.append(event)
	_parked = remaining
	return released


# ---------------------------------------------------------------------------
# Queue access
# ---------------------------------------------------------------------------

## Return the next non-cancelled event without removing it, or null if empty.
func peek() -> ScheduledEvent:
	_skip_cancelled()
	if _queue.is_empty():
		return null
	return _queue[0]


## Remove and return the next non-cancelled event, or null if empty.
func pop() -> ScheduledEvent:
	_skip_cancelled()
	if _queue.is_empty():
		return null
	var event: ScheduledEvent = _queue[0]
	_queue.remove_at(0)
	_id_index.erase(event.event_id)
	return event


## True if no non-cancelled FIREABLE events remain. Parked events do not
## count — they cannot fire until a handler registers, so e.g. MAX speed
## correctly auto-pauses on a queue that holds only parked events.
func is_empty() -> bool:
	_skip_cancelled()
	return _queue.is_empty()


## Number of non-cancelled pending events (queued + parked).
func size() -> int:
	var count := 0
	for event in _queue:
		if not event.cancelled:
			count += 1
	for event in _parked:
		if not event.cancelled:
			count += 1
	return count


## True if a non-cancelled event of [param event_type] (queued or parked) is
## pending for [param owner_id]. THE idempotency check for "schedule X unless
## one is already pending" — use this instead of hand-rolled
## get_events_for_owner scans.
func has_event_for_owner(owner_id: String, event_type: String) -> bool:
	for event in _queue:
		if not event.cancelled and event.owner_id == owner_id and event.event_type == event_type:
			return true
	for event in _parked:
		if not event.cancelled and event.owner_id == owner_id and event.event_type == event_type:
			return true
	return false


## Return all non-cancelled events for [param owner_id] (queued + parked),
## queue order first. Parked events count as pending for idempotency checks.
func get_events_for_owner(owner_id: String) -> Array[ScheduledEvent]:
	var result: Array[ScheduledEvent] = []
	for event in _queue:
		if not event.cancelled and event.owner_id == owner_id:
			result.append(event)
	for event in _parked:
		if not event.cancelled and event.owner_id == owner_id:
			result.append(event)
	return result


## Return all non-cancelled events (queued + parked), queue order first.
func get_all_events() -> Array[ScheduledEvent]:
	var result: Array[ScheduledEvent] = []
	for event in _queue:
		if not event.cancelled:
			result.append(event)
	for event in _parked:
		if not event.cancelled:
			result.append(event)
	return result


## Remove all events from the queue (parked included).
func clear() -> void:
	_queue.clear()
	_parked.clear()
	_id_index.clear()
	_next_sequence = 0


# ---------------------------------------------------------------------------
# Persistence helpers
# ---------------------------------------------------------------------------

## Serialize all non-cancelled events for DB storage (parked included —
## they are pending obligations; on load they re-enter the queue and re-park
## if their handler is still absent).
func to_dicts() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event in _queue:
		if not event.cancelled:
			result.append(event.to_dict())
	for event in _parked:
		if not event.cancelled:
			result.append(event.to_dict())
	return result


## Bulk-load events from persistence. Clears existing queue first.
func load_from_dicts(dicts: Array) -> void:
	clear()
	for d in dicts:
		var event := ScheduledEvent.from_dict(d)
		if not event.cancelled:
			schedule(event)


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

## Binary-search insert to maintain sorted order.
func _insert_sorted(event: ScheduledEvent) -> void:
	var lo := 0
	var hi := _queue.size()
	while lo < hi:
		@warning_ignore("integer_division")
		var mid := (lo + hi) / 2
		if _queue[mid].is_before(event):
			lo = mid + 1
		else:
			hi = mid
	_queue.insert(lo, event)


## Remove cancelled events from the front of the queue (lazy deletion).
func _skip_cancelled() -> void:
	while not _queue.is_empty() and _queue[0].cancelled:
		var removed: ScheduledEvent = _queue[0]
		_queue.remove_at(0)
		_id_index.erase(removed.event_id)
