class_name ActivityTimeCostExecutor
extends RefCounted

## Schedules and resolves RAW activity time costs against the EventScheduler.
##
## Per `gdd-realtime-scheduler.md` §4.8, activities are launched from their
## location of execution and fire as ScheduledEvents:
##
##   * Singular  — atomic; one `activity_complete` event scheduled at
##                 fire_time = now + time_cost_rounds. Cancel = total failure
##                 (no partial credit).
##   * Restricted — same as Singular plus a per-period cooldown set on
##                  completion via restricted_cooldowns.
##   * Ongoing   — daily-session model. Each day's session fires as
##                 `ongoing_session_complete`; on uninterrupted fire,
##                 ticks_accumulated += 1 and the next day's session is
##                 scheduled at fire_time + ROUNDS_PER_DAY. Tick-tolerance
##                 forfeit when absence_accumulated > ticks_accumulated.
##
## See gdd-domain-tab.md §15.1 for the tick-tolerance / absence semantics.
##
## Owned by SessionRunner; instantiated once per session.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const EVENT_ACTIVITY_COMPLETE := "activity_complete"
const EVENT_ONGOING_SESSION_COMPLETE := "ongoing_session_complete"

## Default session time costs per activity_level. Major = 6h, minor = 1h,
## trivial = 0. These are the gdd-realtime-scheduler.md §4.8.1 defaults; the
## per-activity JSON catalog may override.
const _SESSION_ROUNDS_BY_LEVEL: Dictionary = {
	"major":   6 * 360,    # 6 hours = 2,160 rounds
	"minor":   360,        # 1 hour
	"trivial": 0,
}

## Per RAW frequency_types; restricted_period_rounds is currently a per-
## activity field but defaults to one game-week if unspecified. For Phase 3
## no domain-category Restricted activities exist (consult_senate is Singular);
## kept as a hook for Phase 9 (carouse, lay_low, etc.).
const _DEFAULT_RESTRICTED_PERIOD_ROUNDS := 7 * 8640  # one week


# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------

var _runner = null  # SessionRunner
var _campaign_id: String = ""
var _catalog: ActivityCatalog
var _handler_registry: ActivityHandlerRegistry

## Optional external resolver: takes character_id, returns
## { "kind": String, "ref": String } describing the character's CURRENT
## location for the absence-vs-tick decision. If null, every session is
## treated as "at required location" (unit tests inject a mock).
var _location_resolver: Callable = Callable()


# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------

func _init(
	runner,
	catalog: ActivityCatalog,
	handler_registry: ActivityHandlerRegistry
) -> void:
	_runner = runner
	_catalog = catalog
	_handler_registry = handler_registry
	if runner != null and runner.has_method("get_campaign_id"):
		_campaign_id = runner.get_campaign_id()


## Wire a function (character_id) -> { "kind": String, "ref": String } that
## reports the character's current location. Used to decide tick-vs-absence
## when an `ongoing_session_complete` event fires. Tests can override this.
func set_location_resolver(resolver: Callable) -> void:
	_location_resolver = resolver


# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------

func register(registry: EventHandlerRegistry) -> void:
	registry.register(EVENT_ACTIVITY_COMPLETE, _handle_activity_complete)
	registry.register(EVENT_ONGOING_SESSION_COMPLETE, _handle_ongoing_session_complete)


func unregister(registry: EventHandlerRegistry) -> void:
	registry.unregister(EVENT_ACTIVITY_COMPLETE)
	registry.unregister(EVENT_ONGOING_SESSION_COMPLETE)


# ---------------------------------------------------------------------------
# Launch
# ---------------------------------------------------------------------------

## Launch an activity for [param character_id]. Persists the activity_state
## row, schedules the appropriate first event, and emits
## EventBus.activity_launched.
##
## Returns: { success: bool, activity_state_id: String, error: String }
## error codes: "unknown_activity" | "on_cooldown" | "no_scheduler"
func launch(
	character_id: String,
	activity_def_id: String,
	location_kind: String,
	location_ref: String,
	params: Dictionary,
	scheduler: EventScheduler,
	party_id: String = ""
) -> Dictionary:
	var def: Dictionary = _catalog.get_definition(activity_def_id)
	if def.is_empty():
		return {"success": false, "activity_state_id": "", "error": "unknown_activity"}
	if scheduler == null:
		return {"success": false, "activity_state_id": "", "error": "no_scheduler"}

	var freq: String = String(def.get("frequency", "singular"))
	var current_time: int = _get_time(party_id)

	if freq == "restricted":
		var cooldown_until: int = CampaignRepository.get_restricted_cooldown(
			character_id, activity_def_id)
		if current_time < cooldown_until:
			return {"success": false, "activity_state_id": "", "error": "on_cooldown"}

	var session_rounds: int = _session_rounds_for(def)
	var ticks_required: int = _compute_ticks_required(def, params)

	var state_record: Dictionary = {
		"campaign_id": _campaign_id,
		"character_id": character_id,
		"activity_def_id": activity_def_id,
		"frequency_type": freq,
		"status": "active",
		"location_kind": location_kind,
		"location_ref": location_ref,
		"time_cost_rounds": session_rounds,
		"ticks_required": ticks_required,
		"ticks_accumulated": 0,
		"absence_accumulated": 0,
		"started_calendar_day": _calendar_day(),
		"last_session_day": 0,
		"cp_committed": int(params.get("gp_committed", 0)) * 100,
		"params_json": JSON.stringify(params),
		"scheduled_event_id": "",
	}
	var state_id: String = CampaignRepository.create_activity_state(state_record)
	if state_id.is_empty():
		return {"success": false, "activity_state_id": "", "error": "persist_failed"}

	var event_type: String = EVENT_ONGOING_SESSION_COMPLETE if freq == "ongoing" \
		else EVENT_ACTIVITY_COMPLETE
	var event_id: String = scheduler.schedule_after(
		current_time,
		session_rounds,
		event_type,
		character_id,
		{
			"activity_state_id": state_id,
			"activity_def_id": activity_def_id,
			"party_id": party_id,
		},
		ScheduledEvent.PRIORITY_ARRIVAL,
	)
	CampaignRepository.update_activity_state(state_id, {"scheduled_event_id": event_id})

	EventBus.activity_launched.emit(state_id, character_id, activity_def_id)
	return {"success": true, "activity_state_id": state_id, "error": ""}


# ---------------------------------------------------------------------------
# Cancellation / abandonment
# ---------------------------------------------------------------------------

## Cancel the in-flight scheduled session for an activity. For Singular and
## Restricted, this is full forfeiture (status=forfeited, no partial credit).
## For Ongoing, this cancels the day's session and emits activity_forfeited
## with the given reason; prior ticks_accumulated is preserved and status
## stays 'active' unless [param terminal] is true.
func cancel(
	activity_state_id: String,
	reason: String,
	scheduler: EventScheduler,
	terminal: bool = false
) -> bool:
	var state: Dictionary = CampaignRepository.get_activity_state(activity_state_id)
	if state.is_empty():
		return false
	var status: String = String(state.get("status", "active"))
	if status != "active":
		return false

	var event_id: String = String(state.get("scheduled_event_id", ""))
	if scheduler != null and not event_id.is_empty():
		scheduler.cancel(event_id)

	var freq: String = String(state.get("frequency_type", "singular"))
	var character_id: String = String(state.get("character_id", ""))

	if freq == "ongoing" and not terminal:
		# Daily-session interruption: emit forfeiture for THIS session;
		# preserve prior accumulated ticks; status remains active.
		CampaignRepository.update_activity_state(activity_state_id, {
			"scheduled_event_id": "",
		})
		EventBus.activity_forfeited.emit(activity_state_id, character_id, reason)
		return true

	# Singular / Restricted / terminal Ongoing: full forfeit.
	var new_status: String = "abandoned" if terminal else "forfeited"
	CampaignRepository.update_activity_state(activity_state_id, {
		"status": new_status,
		"scheduled_event_id": "",
	})
	EventBus.activity_forfeited.emit(activity_state_id, character_id, reason)
	return true


## Mark an Ongoing activity terminally abandoned (no resumption). Used by the
## §15.1.5 pre-departure modal "Yes, forfeit progress" affordance.
func abandon(
	activity_state_id: String,
	reason: String,
	scheduler: EventScheduler
) -> bool:
	return cancel(activity_state_id, reason, scheduler, true)


# ---------------------------------------------------------------------------
# Day-advance hook
# ---------------------------------------------------------------------------

## Called by SessionRunner once per Timekeeping.day_changed. Iterates all
## active Ongoing activities for [param character_id] and increments
## absence_accumulated for any whose required location does not match the
## current location resolver result. Forfeits per §15.1 when absence exceeds
## ticks_accumulated.
##
## NOTE: this fires alongside session_complete, not instead of it. The session
## handler decides tick-vs-absence at session-fire time; this hook catches the
## case where a session was cancelled by an interrupt earlier in the day.
func on_day_advanced(character_id: String, scheduler: EventScheduler) -> void:
	var rows: Array = CampaignRepository.list_active_activity_states_for_character(character_id)
	for row: Dictionary in rows:
		if str(row.get("frequency_type", "")) != "ongoing":
			continue
		if str(row.get("status", "")) != "active":
			continue
		# If the day's session never fired (cancelled by interrupt) AND the
		# character isn't here, count an absence day.
		var event_id: String = str(row.get("scheduled_event_id", ""))
		if event_id.is_empty() and not _is_at_required_location(character_id, row):
			_record_absence(row, scheduler)


# ---------------------------------------------------------------------------
# Event handlers
# ---------------------------------------------------------------------------

## Singular / Restricted activity completes atomically.
func _handle_activity_complete(event: ScheduledEvent) -> Dictionary:
	var data: Dictionary = event.data
	var state_id: String = str(data.get("activity_state_id", ""))
	var state: Dictionary = CampaignRepository.get_activity_state(state_id)
	if state.is_empty() or String(state.get("status", "")) != "active":
		return {}

	var character_id: String = String(state.get("character_id", ""))
	var activity_def_id: String = String(state.get("activity_def_id", ""))

	# Restricted: stamp cooldown.
	var freq: String = String(state.get("frequency_type", "singular"))
	if freq == "restricted":
		var period: int = int(_catalog.get_definition(activity_def_id).get(
			"restricted_period_rounds", _DEFAULT_RESTRICTED_PERIOD_ROUNDS))
		CampaignRepository.set_restricted_cooldown(
			character_id, activity_def_id, event.fire_time + period)

	# Invoke real-effect handler.
	var handler_result: Dictionary = _handler_registry.invoke_on_complete(
		activity_def_id, state, _runner)

	CampaignRepository.update_activity_state(state_id, {
		"status": "completed",
		"scheduled_event_id": "",
		"ticks_accumulated": int(state.get("ticks_required", 1)),
	})
	EventBus.activity_completed.emit(state_id, character_id, {
		"activity_def_id": activity_def_id,
		"success": true,
		"summary": handler_result.get("summary", ""),
	})

	var presentation: Variant = handler_result.get("presentation", null)
	var result: Dictionary = {}
	if presentation != null:
		result["presentation"] = presentation
	return result


## One day's Ongoing-session fires. Decide tick-vs-absence, advance state, and
## either schedule the next day's session or finalize.
func _handle_ongoing_session_complete(event: ScheduledEvent) -> Dictionary:
	var data: Dictionary = event.data
	var state_id: String = str(data.get("activity_state_id", ""))
	var state: Dictionary = CampaignRepository.get_activity_state(state_id)
	if state.is_empty() or String(state.get("status", "")) != "active":
		return {}

	var character_id: String = String(state.get("character_id", ""))
	var activity_def_id: String = String(state.get("activity_def_id", ""))
	var ticks_required: int = int(state.get("ticks_required", 1))
	var ticks_accumulated: int = int(state.get("ticks_accumulated", 0))
	var absence_accumulated: int = int(state.get("absence_accumulated", 0))

	# Tick-vs-absence by location.
	var present: bool = _is_at_required_location(character_id, state)
	if present:
		ticks_accumulated += 1
		_handler_registry.invoke_on_tick(activity_def_id, state, _runner)
		EventBus.activity_tick_earned.emit(state_id, character_id, ticks_accumulated)
	else:
		absence_accumulated += 1

	# Forfeit check per §15.1.
	if absence_accumulated > ticks_accumulated:
		CampaignRepository.update_activity_state(state_id, {
			"status": "forfeited",
			"ticks_accumulated": ticks_accumulated,
			"absence_accumulated": absence_accumulated,
			"last_session_day": _calendar_day(),
			"scheduled_event_id": "",
		})
		EventBus.activity_forfeited.emit(state_id, character_id, "absence_exceeded_ticks")
		return {}

	# Final tick → completion.
	if ticks_accumulated >= ticks_required:
		CampaignRepository.update_activity_state(state_id, {
			"status": "completed",
			"ticks_accumulated": ticks_accumulated,
			"absence_accumulated": absence_accumulated,
			"last_session_day": _calendar_day(),
			"scheduled_event_id": "",
		})
		# Refresh and invoke completion handler.
		var refreshed_state: Dictionary = CampaignRepository.get_activity_state(state_id)
		var handler_result: Dictionary = _handler_registry.invoke_on_complete(
			activity_def_id, refreshed_state, _runner)
		EventBus.activity_completed.emit(state_id, character_id, {
			"activity_def_id": activity_def_id,
			"success": true,
			"summary": handler_result.get("summary", ""),
		})
		var result: Dictionary = {}
		var presentation: Variant = handler_result.get("presentation", null)
		if presentation != null:
			result["presentation"] = presentation
		return result

	# Schedule the next day's session.
	var next_event_id: String = ""
	var session_rounds: int = int(state.get("time_cost_rounds", 0))
	var next_events: Array = [{
		"fire_time": event.fire_time + Timekeeping.ROUNDS_PER_DAY,
		"event_type": EVENT_ONGOING_SESSION_COMPLETE,
		"owner_id": character_id,
		"data": {
			"activity_state_id": state_id,
			"activity_def_id": activity_def_id,
			"party_id": data.get("party_id", ""),
		},
		"priority": ScheduledEvent.PRIORITY_ARRIVAL,
	}]

	# Preflight reserve a scheduled_event_id by pre-generating; the SchedulerLoop
	# will assign one when it processes next_events. Persist what we know.
	CampaignRepository.update_activity_state(state_id, {
		"ticks_accumulated": ticks_accumulated,
		"absence_accumulated": absence_accumulated,
		"last_session_day": _calendar_day(),
		"scheduled_event_id": next_event_id,
	})

	return {"next_events": next_events}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _session_rounds_for(def: Dictionary) -> int:
	var explicit: Variant = def.get("session_time_cost_rounds", null)
	if explicit is int:
		return int(explicit)
	if explicit is String:
		match String(explicit):
			"major_activity":   return _SESSION_ROUNDS_BY_LEVEL["major"]
			"minor_activity":   return _SESSION_ROUNDS_BY_LEVEL["minor"]
			"trivial_activity": return _SESSION_ROUNDS_BY_LEVEL["trivial"]
	# Fall back to activity_level.
	var level: String = String(def.get("activity_level", "minor"))
	return _SESSION_ROUNDS_BY_LEVEL.get(level, _SESSION_ROUNDS_BY_LEVEL["minor"])


## Compute ticks_required from the activity's duration_formula plus runtime
## params. For Phase 3 we support: integer literals (e.g. "21" / "30") and a
## small set of known formulas. Unknown formulas fall back to default_ticks.
func _compute_ticks_required(def: Dictionary, params: Dictionary) -> int:
	var formula: String = String(def.get("duration_formula", ""))
	var default_ticks: int = int(def.get("default_ticks_required", 1))

	if formula.is_empty():
		return maxi(1, default_ticks)
	if formula.is_valid_int():
		return maxi(1, formula.to_int())

	# Known formulas.
	match formula:
		"ceil(0.5 * (hex_count + vassal_count + (6 - market_class)))":
			var hex_count: int = int(params.get("hex_count", 1))
			var vassal_count: int = int(params.get("vassal_count", 0))
			var market_class: int = int(params.get("market_class", 6))
			return maxi(1, int(ceil(0.5 * (hex_count + vassal_count + (6 - market_class)))))
		"ceil(gp_committed / 500)":
			var gp: int = int(params.get("gp_committed", 0))
			return maxi(1, int(ceil(float(gp) / 500.0)))
		# Phase 10B.1b: research_magic — 14 days (2 weeks) per spell level.
		# Per acore-campaign-general-and-magic-research.xml §research_existing_spell L75.
		"research_magic_duration":
			var spell_level: int = int(params.get("target_spell_level", 1))
			return maxi(14, 14 * spell_level)
		# Phase 10B.1b: rewrite_spell / replace_spell — 7 days per spell level.
		# Per ax_campaign_play.xml §rewrite_spell L760 + §replace_spell L772.
		"rewrite_replace_spell_duration":
			var spell_level2: int = int(params.get("target_spell_level", 1))
			return maxi(7, 7 * spell_level2)
		# Phase 10B.3 (Syndicate): each of the four syndicate-Ongoing
		# durations is pre-rolled by the launcher (per RAW the perpetrator
		# does not know the required time until completion) and stuffed
		# into the params dict before executor.launch is called. The
		# executor reads it back here. Convention: SyndicateLauncher's
		# prepare_* helpers roll via the relevant resolver and embed:
		#   * plan_hijink_duration     → params.planning_days_required
		#   * perform_hijink_duration  → params.perform_days_required
		#   * lay_low_duration         → params.lay_low_days
		#   * await_trial_duration     → params.time_languishing_days
		# Fallback default: 1 tick (per Phase 10B.3 schema defaults).
		"plan_hijink_duration":
			return maxi(1, int(params.get("planning_days_required", 1)))
		"perform_hijink_duration":
			return maxi(1, int(params.get("perform_days_required", 1)))
		"lay_low_duration":
			return maxi(1, int(params.get("lay_low_days", 1)))
		"await_trial_duration":
			return maxi(1, int(params.get("time_languishing_days", 1)))

	return maxi(1, default_ticks)


func _is_at_required_location(character_id: String, state: Dictionary) -> bool:
	var required_kind: String = String(state.get("location_kind", "anywhere"))
	if required_kind == "anywhere":
		return true
	if not _location_resolver.is_valid():
		return true  # No resolver wired = treat all sessions as present.
	var current: Variant = _location_resolver.call(character_id)
	if not (current is Dictionary):
		return true
	var current_kind: String = String((current as Dictionary).get("kind", ""))
	var current_ref: String = String((current as Dictionary).get("ref", ""))
	var required_ref: String = String(state.get("location_ref", ""))
	if current_kind != required_kind:
		return false
	if not required_ref.is_empty() and current_ref != required_ref:
		return false
	return true


func _record_absence(state: Dictionary, scheduler: EventScheduler) -> void:
	var state_id: String = String(state.get("id", ""))
	var character_id: String = String(state.get("character_id", ""))
	var ticks_accumulated: int = int(state.get("ticks_accumulated", 0))
	var absence_accumulated: int = int(state.get("absence_accumulated", 0)) + 1

	if absence_accumulated > ticks_accumulated:
		CampaignRepository.update_activity_state(state_id, {
			"status": "forfeited",
			"absence_accumulated": absence_accumulated,
			"scheduled_event_id": "",
		})
		EventBus.activity_forfeited.emit(state_id, character_id, "absence_exceeded_ticks")
		return

	CampaignRepository.update_activity_state(state_id, {
		"absence_accumulated": absence_accumulated,
	})


func _get_time(_party_id: String) -> int:
	return Timekeeping.get_total_rounds()


func _calendar_day() -> int:
	return Timekeeping.get_calendar_day()
