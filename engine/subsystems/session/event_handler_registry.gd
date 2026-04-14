class_name EventHandlerRegistry
extends RefCounted

## Maps event_type strings to handler Callables for the EventScheduler.
##
## Subsystems register themselves as handlers for specific event types
## (e.g., WildernessHandlers registers for "travel_leg"). When the scheduler
## pops an event, the SchedulerLoop dispatches it through this registry.
##
## Handler signature:
##   func handle_event(event: ScheduledEvent) -> Dictionary
##
## Return dict keys (all optional):
##   "next_events": Array[Dictionary] — events to schedule (each has fire_time,
##       event_type, owner_id, data, priority)
##   "auto_pause": bool — true to pause the scheduler after this event
##   "pause_reason": String — human-readable reason for auto-pause
##   "enter_combat": bool — true to suspend scheduler and enter combat
##   "encounter_data": Dictionary — passed to CombatState if enter_combat
##   "presentation": Dictionary — data for UI notification/display
##   "transition_to": String — state key if a session state change is needed


# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------

## { event_type (String) : handler (Callable) }
var _handlers: Dictionary = {}


# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------

## Register a handler for [param event_type]. Overwrites any existing handler.
func register(event_type: String, handler: Callable) -> void:
	_handlers[event_type] = handler


## Unregister the handler for [param event_type].
func unregister(event_type: String) -> void:
	_handlers.erase(event_type)


## Unregister all handlers. Called during context teardown.
func clear() -> void:
	_handlers.clear()


## Returns true if a handler is registered for [param event_type].
func has_handler(event_type: String) -> bool:
	return _handlers.has(event_type)


# ---------------------------------------------------------------------------
# Resolution
# ---------------------------------------------------------------------------

## Dispatch [param event] to its registered handler.
## Returns the handler's result Dictionary, or an empty dict if unhandled.
func resolve(event: ScheduledEvent) -> Dictionary:
	if not _handlers.has(event.event_type):
		push_warning("EventHandlerRegistry: no handler for event_type '%s'" % event.event_type)
		return {}
	var handler: Callable = _handlers[event.event_type]
	var result = handler.call(event)
	if result is Dictionary:
		return result
	push_warning("EventHandlerRegistry: handler for '%s' returned non-Dictionary" % event.event_type)
	return {}
