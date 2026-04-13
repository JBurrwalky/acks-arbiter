class_name CampState
extends SessionState

## Camp/rest session state.
##
## Manages the 12-hour rest period with 3 watches of 4 hours each.
## Handles encounter checks per watch and rest recovery on completion.
##
## Context keys (from transition):
##   "is_town": bool — if true, skip watches (town rest)
##   "return_state": String — state to return to after rest
##   "watch_number": int — if returning from camp combat, which watch to resume

var _camp_screen = null  # CampRestScreen — loaded lazily
var _is_town: bool = false
var _return_state: String = "wilderness"
var _resume_watch: int = -1  # -1 = start fresh, 0-2 = resume from combat
var _watch_assignments: Array = []  # [Array[String]] per watch
var _watch_results: Array = []  # accumulated results
var _armed_sleepers: Array = []  # character ids sleeping in armor


func enter(runner, context: Dictionary) -> void:
	_is_town = context.get("is_town", false)
	_return_state = context.get("return_state", "wilderness")
	_resume_watch = context.get("watch_number", -1)

	if _resume_watch >= 0:
		# Returning from a camp combat — continue resolving remaining watches.
		_watch_results.append({
			"watch_index": _resume_watch,
			"encounter": true,
			"combat_occurred": true,
		})
		_resume_watch += 1
		if _resume_watch >= CampManager.WATCH_COUNT:
			_finalize_rest(runner)
			return
		# Continue processing next watch from the screen.

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
	if _camp_screen and is_instance_valid(_camp_screen):
		_camp_screen.queue_free()
		_camp_screen = null


func handle_action(runner, action: String, payload: Dictionary) -> String:
	match action:
		"cancel_camp":
			return _return_state
		"end_session":
			return "session_end"
	return ""


# ---------------------------------------------------------------------------
# Watch resolution
# ---------------------------------------------------------------------------

func _on_watches_confirmed(runner, assignments: Array, armed_sleepers: Array) -> void:
	_watch_assignments = assignments
	_armed_sleepers = armed_sleepers
	_watch_results.clear()
	if _is_town:
		# Town rest: no watches, no encounters — skip straight to rest recovery.
		Timekeeping.advance_hours(CampManager.TOTAL_REST_HOURS)
		_finalize_rest(runner)
	else:
		_resolve_watches(runner, _resume_watch if _resume_watch >= 0 else 0)


func _resolve_watches(runner, start_watch: int) -> void:
	for watch_index in range(start_watch, CampManager.WATCH_COUNT):
		# Advance time by 4 hours per watch.
		Timekeeping.advance_hours(CampManager.WATCH_HOURS)

		# Check for encounter.
		var terrain_chance := 1.0 / 6.0  # Default 1-in-6.
		var encounter: Variant = CampManager.check_watch_encounter(terrain_chance)

		if encounter != null:
			# Encounter triggered — transition to combat.
			_watch_results.append({
				"watch_index": watch_index,
				"encounter": true,
				"combat_occurred": false,  # Will be set true on return.
			})

			# Build combat context with sleeping character data.
			var sleeping_ids := _get_sleeping_ids(watch_index)
			var armed_sleeping := _get_armed_sleeping_ids(watch_index)
			runner.transition_to_state("combat", {
				"return_state": "camp",
				"watch_number": watch_index,
				"sleeping_characters": sleeping_ids,
				"armed_sleeping_characters": armed_sleeping,
				"encounter_data": encounter,
			})
			return  # Combat takes over; we'll resume on return.

		_watch_results.append({
			"watch_index": watch_index,
			"encounter": false,
			"combat_occurred": false,
		})

	# All watches passed without encounter — finalize rest.
	_finalize_rest(runner)


func _get_sleeping_ids(watch_index: int) -> Array:
	## Characters NOT on this watch are sleeping.
	var awake_ids: Array = _watch_assignments[watch_index] if watch_index < _watch_assignments.size() else []
	var all_ids: Array = []
	for watch in _watch_assignments:
		for cid in watch:
			if cid not in all_ids:
				all_ids.append(cid)
	var sleeping: Array = []
	for cid in all_ids:
		if cid not in awake_ids:
			sleeping.append(cid)
	return sleeping


func _get_armed_sleeping_ids(watch_index: int) -> Array:
	var sleeping := _get_sleeping_ids(watch_index)
	var armed_sleeping: Array = []
	for cid in sleeping:
		if cid in _armed_sleepers:
			armed_sleeping.append(cid)
	return armed_sleeping


# ---------------------------------------------------------------------------
# Rest finalization
# ---------------------------------------------------------------------------

func _finalize_rest(runner) -> void:
	# Armed sleeper checks.
	var failed_rest_ids: Array = []
	for char_id in _armed_sleepers:
		# Get character data for encumbrance and CON mod.
		var char_data = CampaignRepository.load_character(char_id)
		if char_data == null or not char_data is Dictionary:
			continue
		var enc: int = char_data.get("encumbrance_stones", 5)
		var con_mod: int = char_data.get("con_modifier", 0)
		var result := CampManager.armed_sleeper_check(enc, con_mod)
		if not result["success"]:
			failed_rest_ids.append(char_id)

	# Compute recovery.
	var party_members: Array = []
	if runner.has_method("get_party_members"):
		party_members = runner.get_party_members()

	var recovery := CampManager.compute_rest_recovery(party_members, failed_rest_ids)
	var rations := CampManager.compute_ration_consumption(party_members.size())

	# Apply recovery to characters.
	for char_id in recovery:
		var rec: Dictionary = recovery[char_id]
		var hp_gain: int = rec.get("hp_recovered", 0)
		if hp_gain > 0:
			var char_data = CampaignRepository.load_character(char_id)
			if char_data is Dictionary:
				var new_hp: int = mini(
					char_data.get("hp_current", 0) + hp_gain,
					char_data.get("hp_max", 0))
				CampaignRepository.update_character_fields(char_id, {"hp_current": new_hp})
		if rec.get("spells_recovered", false):
			CampaignRepository.reset_spell_slots(char_id)

	EventBus.rest_taken.emit(CampManager.TOTAL_REST_HOURS)

	# Show summary on camp screen.
	if _camp_screen and is_instance_valid(_camp_screen):
		_camp_screen.show_rest_summary({
			"watches": _watch_results,
			"rest_recovery": recovery,
			"rations_consumed": rations,
			"total_hours": CampManager.TOTAL_REST_HOURS,
			"failed_rest_ids": failed_rest_ids,
		})
	else:
		# No screen — just transition back.
		runner.transition_to_state(_return_state)
