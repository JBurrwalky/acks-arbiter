class_name ActivityHandlerRegistry
extends RefCounted

## Lookup table mapping activity_def_id → handler Callables.
##
## Each activity in data/activities/*.json has a corresponding handler in
## engine/subsystems/activities/handlers/<id>.gd that mutates domain or
## campaign state when the activity completes (or, for Ongoing activities,
## on each daily tick).
##
## Handler signatures:
##   on_complete(state: Dictionary, runner) -> Dictionary
##     Returns side-effect summary: { ledger_entries, presentation, signals,
##                                    deferred_side_effects }
##   on_tick(state: Dictionary, runner) -> Dictionary
##     Optional; called once per Ongoing daily session before the executor
##     emits activity_tick_earned. Most handlers do nothing per-tick and only
##     act on completion.
##
## See gdd-realtime-scheduler.md §4.8 and the per-handler files for details.


# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------

## { activity_def_id (String) : Dictionary { on_complete: Callable,
##                                            on_tick: Callable (optional) } }
var _entries: Dictionary = {}


# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------

## Register a handler. [param on_complete] is required; [param on_tick] is
## optional and defaults to a no-op for activities that have no per-tick effect.
func register(
	activity_def_id: String,
	on_complete: Callable,
	on_tick: Callable = Callable()
) -> void:
	_entries[activity_def_id] = {
		"on_complete": on_complete,
		"on_tick": on_tick,
	}


## Returns true if [param activity_def_id] has a registered handler.
func has(activity_def_id: String) -> bool:
	return _entries.has(activity_def_id)


# ---------------------------------------------------------------------------
# Resolution
# ---------------------------------------------------------------------------

## Invoke the on_complete handler for [param activity_def_id]. Returns the
## handler's result Dictionary or empty if no handler is registered.
func invoke_on_complete(
	activity_def_id: String,
	state: Dictionary,
	runner
) -> Dictionary:
	if not _entries.has(activity_def_id):
		push_warning("ActivityHandlerRegistry: no handler for '%s'" % activity_def_id)
		return {}
	var on_complete: Callable = _entries[activity_def_id].get("on_complete", Callable())
	if not on_complete.is_valid():
		return {}
	var result: Variant = on_complete.call(state, runner)
	if result is Dictionary:
		return result
	return {}


## Invoke the optional on_tick handler. Returns empty if not registered or
## not provided.
func invoke_on_tick(
	activity_def_id: String,
	state: Dictionary,
	runner
) -> Dictionary:
	if not _entries.has(activity_def_id):
		return {}
	var on_tick: Variant = _entries[activity_def_id].get("on_tick", null)
	if on_tick == null:
		return {}
	var cb: Callable = on_tick as Callable
	if not cb.is_valid():
		return {}
	var result: Variant = cb.call(state, runner)
	if result is Dictionary:
		return result
	return {}


## Drop all registered handlers.
func clear() -> void:
	_entries.clear()
