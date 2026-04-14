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


# ---------------------------------------------------------------------------
# Scheduling
# ---------------------------------------------------------------------------

## Insert an event into the queue. Returns the event's id.
func schedule(event: ScheduledEvent) -> String:
	if event.event_id.is_empty():
		event.event_id = CampaignRepository.generate_id()
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


## Cancel all events owned by [param owner_id].
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
	return count


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


## True if no non-cancelled events remain.
func is_empty() -> bool:
	_skip_cancelled()
	return _queue.is_empty()


## Number of non-cancelled events in the queue.
func size() -> int:
	var count := 0
	for event in _queue:
		if not event.cancelled:
			count += 1
	return count


## Return all non-cancelled events for [param owner_id], sorted by fire_time.
func get_events_for_owner(owner_id: String) -> Array[ScheduledEvent]:
	var result: Array[ScheduledEvent] = []
	for event in _queue:
		if not event.cancelled and event.owner_id == owner_id:
			result.append(event)
	return result


## Return all non-cancelled events, sorted by fire_time.
func get_all_events() -> Array[ScheduledEvent]:
	var result: Array[ScheduledEvent] = []
	for event in _queue:
		if not event.cancelled:
			result.append(event)
	return result


## Remove all events from the queue.
func clear() -> void:
	_queue.clear()
	_id_index.clear()


# ---------------------------------------------------------------------------
# Persistence helpers
# ---------------------------------------------------------------------------

## Serialize all non-cancelled events for DB storage.
func to_dicts() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event in _queue:
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
