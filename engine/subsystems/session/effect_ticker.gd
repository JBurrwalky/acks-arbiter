class_name EffectTicker
extends RefCounted

## Bridges ActiveEffectTracker tick methods to Timekeeping boundary signals.
##
## Owned by SessionRunner. Created on session load, disconnected on session end.
## When Timekeeping advances time and crosses boundaries (round, turn, hour, day),
## this class forwards those events to the ActiveEffectTracker so spell/effect
## durations tick down automatically.

var _tracker: ActiveEffectTracker
var _connected: bool = false


func _init(tracker: ActiveEffectTracker) -> void:
	_tracker = tracker


## Connects to all Timekeeping boundary signals. Safe to call multiple times.
func connect_signals() -> void:
	if _connected:
		return
	Timekeeping.round_advanced.connect(_on_rounds)
	Timekeeping.turn_advanced.connect(_on_turns)
	Timekeeping.hour_advanced.connect(_on_hours)
	Timekeeping.day_changed.connect(_on_day)
	_connected = true


## Disconnects from all Timekeeping signals. Safe to call when not connected.
func disconnect_signals() -> void:
	if not _connected:
		return
	if Timekeeping.round_advanced.is_connected(_on_rounds):
		Timekeeping.round_advanced.disconnect(_on_rounds)
	if Timekeeping.turn_advanced.is_connected(_on_turns):
		Timekeeping.turn_advanced.disconnect(_on_turns)
	if Timekeeping.hour_advanced.is_connected(_on_hours):
		Timekeeping.hour_advanced.disconnect(_on_hours)
	if Timekeeping.day_changed.is_connected(_on_day):
		Timekeeping.day_changed.disconnect(_on_day)
	_connected = false


func is_connected_to_timekeeping() -> bool:
	return _connected


func _on_rounds(n: int) -> void:
	var expired: Array = _tracker.tick_rounds(n)
	_emit_expired(expired)


func _on_turns(n: int) -> void:
	var expired: Array = _tracker.tick_turns(n)
	_emit_expired(expired)


func _on_hours(n: int) -> void:
	var expired: Array = _tracker.tick_hours(n)
	_emit_expired(expired)


func _on_day(_new_day: int, _new_month: int, _new_year: int) -> void:
	var expired: Array = _tracker.tick_days(1)
	_emit_expired(expired)


func _emit_expired(expired_ids: Array) -> void:
	for eid: String in expired_ids:
		# Emit removal signal. Future: look up effect before removal for richer data.
		EventBus.spell_effect_removed.emit(eid, "")
