class_name CampState
extends SessionState

## Camp/rest session state.
##
## Manages the 12-hour rest period with 3 watches of 4 hours each.
## Watch resolution is event-driven via the scheduler: after the player
## confirms assignments, 3 camp_watch events and 1 camp_rest_complete event
## are scheduled. The scheduler advances time and resolves each watch.
##
## Context keys (from transition):
##   "is_town": bool — if true, skip watches (town rest)
##   "return_state": String — state to return to after rest
##   "watch_number": int — if returning from camp combat, which watch to resume

var _camp_screen = null  # CampRestScreen — loaded lazily
var _is_town: bool = false
var _return_state: String = "wilderness"
var _resume_watch: int = -1  # -1 = start fresh, 0-2 = resume from combat
var _handlers: CampHandlers = null


func enter(runner, context: Dictionary) -> void:
	_is_town = context.get("is_town", false)
	_return_state = context.get("return_state", "wilderness")
	_resume_watch = context.get("watch_number", -1)

	# Register camp event handlers with the scheduler.
	_handlers = CampHandlers.new(runner)
	_handlers.register(runner.get_handler_registry())

	if _resume_watch >= 0:
		# Returning from a camp combat — remaining watches were cancelled.
		# Re-schedule from the next watch onward? No — the player should
		# see the combat result and decide. Auto-pause is already set.
		# Transition back after showing the result.
		_resume_watch += 1
		if _resume_watch >= CampManager.WATCH_COUNT:
			# All watches done (combat was on the last watch) — finalize.
			# The rest_complete handler won't fire since we cancelled it.
			# Fire it manually by transitioning back.
			runner.transition_to_state(_return_state)
			return

	GameState.transition_to(GameState.State.EXPLORATION)

	# Load camp screen.
	if runner.has_method("get_scene_container"):
		var container = runner.get_scene_container()
		if container:
			_camp_screen = preload("res://scenes/ui/camp/camp_rest_screen.tscn").instantiate()
			container.add_child(_camp_screen)
			_camp_screen.setup(_is_town)
			_camp_screen.watches_confirmed.connect(
				func(assignments: Array, armed: Array):
					_on_watches_confirmed(runner, assignments, armed))
			_camp_screen.rest_completed.connect(
				func(): runner.transition_to_state(_return_state))


func exit(runner) -> void:
	# Unregister camp handlers.
	if _handlers != null:
		_handlers.unregister(runner.get_handler_registry())
		_handlers = null

	if _camp_screen and is_instance_valid(_camp_screen):
		_camp_screen.queue_free()
		_camp_screen = null


func handle_action(runner, action: String, payload: Dictionary) -> String:
	match action:
		"cancel_camp":
			# Cancel any scheduled camp events and clear the camp state on
			# PartyData. Per gdd-realtime-scheduler.md §4.3.1, breaking camp
			# dissolves any pending wilderness_encounter scheduled by the
			# camp's encounter throw — clear_camp_state handles that
			# cancellation alongside the camp_* field reset.
			var party_id: String = runner.get_party_id()
			runner.get_scheduler().cancel_all_for_owner(party_id, "camp_watch")
			runner.get_scheduler().cancel_all_for_owner(party_id, "camp_rest_complete")
			if _handlers != null:
				_handlers.clear_camp_state(party_id)
			return _return_state
		"end_session":
			return "session_end"
	return ""


# ---------------------------------------------------------------------------
# Watch scheduling
# ---------------------------------------------------------------------------

func _on_watches_confirmed(runner, assignments: Array, armed_sleepers: Array) -> void:
	var party_id: String = runner.get_party_id()
	var scheduler: EventScheduler = runner.get_scheduler()

	if _is_town:
		# Town rest: no watches, no encounters — advance time directly.
		Timekeeping.advance_rounds(
			CampManager.TOTAL_REST_HOURS * Timekeeping.ROUNDS_PER_HOUR)
		# Schedule just the rest_complete for immediate resolution.
		var current_time: int = Timekeeping.get_total_rounds()
		scheduler.schedule_at(
			current_time,
			"camp_rest_complete",
			party_id,
			{"all_assignments": assignments, "armed_sleepers": armed_sleepers},
			ScheduledEvent.PRIORITY_ARRIVAL,
		)
	else:
		# Wilderness camp: schedule watch events via the handler. NOTE: the
		# resume-from-combat watch index (_resume_watch) is NOT threaded into
		# schedule_watches — the combat return path routes to wilderness, not
		# back here, so a mid-rest resume is currently unreachable. If that
		# path is ever wired, schedule_watches needs a start-watch parameter
		# (a fresh full-rest schedule would double-charge the night).
		_handlers.schedule_watches(assignments, armed_sleepers, scheduler, party_id)

	# Start the clock to resolve watches.
	var loop: SchedulerLoop = runner.get_scheduler_loop()
	if loop.is_paused():
		loop.resume(SchedulerLoop.SPEED_MAX)  # Resolve watches instantly (no real-time wait)
