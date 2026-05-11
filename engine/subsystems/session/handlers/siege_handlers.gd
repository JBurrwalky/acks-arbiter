class_name SiegeHandlers
extends RefCounted

## Event handlers for the Phase 9B siege subsystem and Phase 9C disease loop.
##
## Handles event types fed by SiegeResolver / SiegeResolverSimplified /
## DiseaseResolver:
##   "siege_daily_tick"            — daily; owner=siege_id; full sieges only
##   "siege_weekly_tick"           — weekly; owner=siege_id; full sieges only
##   "siege_simplified_concluded"  — one-shot at started_day + duration_days;
##                                    owner=siege_id; simplified sieges only
##   "disease_recovery_check"      — Phase 9C; one-shot at the diseased unit's
##                                    recovery_calendar_day; owner=troop_unit_id
##
## Registered by SessionRunner at session load. Survives state transitions
## (sieges and disease state may persist across travel/dungeon/settlement
## contexts).

var _runner = null  # SessionRunner


func _init(runner) -> void:
	_runner = runner


func register(registry: EventHandlerRegistry) -> void:
	registry.register("siege_daily_tick", _handle_daily_tick)
	registry.register("siege_weekly_tick", _handle_weekly_tick)
	registry.register("siege_simplified_concluded", _handle_simplified_concluded)
	registry.register("disease_recovery_check", _handle_disease_recovery_check)
	registry.register("disease_cure_weekly_tick", _handle_disease_cure_weekly_tick)
	registry.register("call_to_arms_tranche_arrival", _handle_call_to_arms_tranche)


func unregister(registry: EventHandlerRegistry) -> void:
	registry.unregister("siege_daily_tick")
	registry.unregister("siege_weekly_tick")
	registry.unregister("siege_simplified_concluded")
	registry.unregister("disease_recovery_check")
	registry.unregister("disease_cure_weekly_tick")
	registry.unregister("call_to_arms_tranche_arrival")


# ---------------------------------------------------------------------------
# Handlers
# ---------------------------------------------------------------------------

func _handle_daily_tick(event: ScheduledEvent) -> Dictionary:
	var siege_id: String = String(event.owner_id)
	var calendar_day: int = _calendar_day()
	var scheduler = _runner.get_scheduler() if _runner != null and _runner.has_method("get_scheduler") else null
	var summary: Dictionary = SiegeResolver.tick_daily(siege_id, calendar_day, Callable(), scheduler)
	# tick_daily already reschedules the next daily tick; we just return the summary.
	# next_events left empty — tick_daily owns its own re-scheduling for clarity.
	return {
		"presentation": {
			"type": "siege_daily_tick",
			"siege_id": siege_id,
			"summary": summary,
		},
	}


func _handle_weekly_tick(event: ScheduledEvent) -> Dictionary:
	var siege_id: String = String(event.owner_id)
	var calendar_day: int = _calendar_day()
	var scheduler = _runner.get_scheduler() if _runner != null and _runner.has_method("get_scheduler") else null
	var summary: Dictionary = SiegeResolver.tick_weekly(siege_id, calendar_day, Callable(), scheduler)
	return {
		"presentation": {
			"type": "siege_weekly_tick",
			"siege_id": siege_id,
			"summary": summary,
		},
	}


func _handle_simplified_concluded(event: ScheduledEvent) -> Dictionary:
	var siege_id: String = String(event.owner_id)
	var calendar_day: int = _calendar_day()
	var result: Dictionary = SiegeResolverSimplified.resolve_simplified_conclusion(siege_id, calendar_day, Callable())
	return {
		"auto_pause": false,
		"presentation": {
			"type": "siege_concluded",
			"siege_id": siege_id,
			"result": result,
		},
	}


## Phase 9C — disease recovery / death check at end-of-duration.
## Called when a previously-scheduled disease_recovery_check event fires.
## Per RAW daw_vagaries.xml §disease L301-302.
func _handle_disease_recovery_check(event: ScheduledEvent) -> Dictionary:
	var unit_id: String = String(event.owner_id)
	var calendar_day: int = _calendar_day()
	var result: Dictionary = DiseaseResolver.resolve_disease_recovery(unit_id, calendar_day)
	return {
		"auto_pause": false,
		"presentation": {
			"type": "disease_recovery_check",
			"unit_id": unit_id,
			"result": result,
		},
	}


## Phase 9C polish — weekly cure tick driver. Calls DiseaseResolver.tick_weekly_cures
## and reschedules itself if diseased units remain in the army.
func _handle_disease_cure_weekly_tick(event: ScheduledEvent) -> Dictionary:
	var army_id: String = String(event.owner_id)
	var calendar_day: int = _calendar_day()
	var result: Dictionary = DiseaseResolver.tick_weekly_cures(army_id, calendar_day)
	# Reschedule self if any diseased units remain.
	var next_events: Array = []
	if bool(result.get("should_reschedule", false)):
		next_events.append({
			"fire_time": event.fire_time + 7 * Timekeeping.ROUNDS_PER_DAY,
			"event_type": "disease_cure_weekly_tick",
			"owner_id": army_id,
			"data": {"army_id": army_id},
			"priority": ScheduledEvent.PRIORITY_CONSEQUENCE,
		})
	return {
		"auto_pause": false,
		"next_events": next_events,
		"presentation": {
			"type": "disease_cure_weekly_tick",
			"army_id": army_id,
			"result": result,
		},
	}


## Phase 9C — Call to Arms tranche arrival.
## Per RAW daw_armies_recruitment.xml §vassal_troops.time_required L674-680.
## owner_id = call_to_arms_state_id; data["tranche"] ∈ {1, 2, 3}.
func _handle_call_to_arms_tranche(event: ScheduledEvent) -> Dictionary:
	var state_id: String = String(event.owner_id)
	var tranche: int = int(event.data.get("tranche", 0))
	var calendar_day: int = _calendar_day()
	var result: Dictionary = CallToArmsMuster.resolve_tranche_arrival(state_id, tranche, calendar_day)
	return {
		"auto_pause": false,
		"presentation": {
			"type": "call_to_arms_tranche_arrival",
			"call_to_arms_state_id": state_id,
			"tranche": tranche,
			"result": result,
		},
	}


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _calendar_day() -> int:
	var date: Dictionary = Timekeeping.get_date()
	return int(date.get("year", 0)) * Timekeeping.DAYS_PER_YEAR \
		+ int(date.get("month", 0)) * Timekeeping.DAYS_PER_MONTH \
		+ int(date.get("day", 0))
