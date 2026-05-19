class_name MercantileForfeitRouter
extends RefCounted

## Subscribes to EventBus.activity_forfeited and dispatches forfeit-time
## cleanup to per-activity handlers in the mercantile category. Per Phase
## 10B.2 Wave 3 — the ActivityHandlerRegistry only exposes on_complete +
## on_tick hooks, so this router compensates by listening for the executor's
## terminal-forfeit signal and invoking the relevant handler's
## handle_forfeit() static method.
##
## Currently routes:
##   * solicit_merchants → SolicitMerchantsHandler.handle_forfeit (rolls back
##     unfired reveals per §5.4)
##
## Other mercantile activities (buy_merchandise, sell_merchandise,
## persuade_merchants, locate_merchandise) are Singular; their state is
## fully committed by on_complete or rejected outright. They don't need
## forfeit cleanup.
##
## Registration is idempotent — SessionRunner.load_session calls
## register_signal_listeners once; if the connection already exists from a
## prior load_session call (campaign-switch path), the call is a no-op.


static func register_signal_listeners() -> void:
	if not EventBus.activity_forfeited.is_connected(_on_activity_forfeited):
		EventBus.activity_forfeited.connect(_on_activity_forfeited)


static func unregister_signal_listeners() -> void:
	if EventBus.activity_forfeited.is_connected(_on_activity_forfeited):
		EventBus.activity_forfeited.disconnect(_on_activity_forfeited)


## Fires when ActivityTimeCostExecutor.cancel(terminal=true) / abandon() / the
## absence-exceeded-ticks branch of _handle_ongoing_session_complete signals
## a terminal forfeit. Inspects the activity_state row by id; routes to the
## activity-specific cleanup if it matches a mercantile handler.
##
## Non-terminal ongoing cancellations (daily-session interruption — see
## ActivityTimeCostExecutor.cancel docstring) also emit activity_forfeited
## with the row's status still 'active'. We filter on status to skip those.
static func _on_activity_forfeited(state_id: String, _character_id: String, _reason: String) -> void:
	if state_id.is_empty():
		return
	var state: Dictionary = CampaignRepository.get_activity_state(state_id)
	if state.is_empty():
		return
	var status: String = String(state.get("status", ""))
	# Only handle terminal forfeits ('forfeited' or 'abandoned'); skip
	# daily-session interruptions where status is still 'active'.
	if not (status in ["forfeited", "abandoned"]):
		return
	var activity_def_id: String = String(state.get("activity_def_id", ""))
	match activity_def_id:
		"solicit_merchants":
			SolicitMerchantsHandler.handle_forfeit(state)
		_:
			pass
