class_name DayDeclarationState
extends SessionState

## Day declaration session state.
##
## Players assign activities to the 8-slot day budget, then the engine
## resolves each slot in sequence (advancing time, triggering encounters,
## executing foraging checks, etc.).
##
## After all 8 slots resolve, transitions to camp_state for overnight rest.

var _day_screen = null
var _budget: DayBudgetManager = null
var _return_state: String = "wilderness"


func enter(runner, context: Dictionary) -> void:
	_return_state = context.get("return_state", "wilderness")
	_budget = DayBudgetManager.new()

	GameState.transition_to(GameState.State.EXPLORATION)

	# Load day declaration screen.
	if runner.has_method("get_scene_container"):
		var container = runner.get_scene_container()
		if container:
			_day_screen = preload("res://scenes/ui/day_planner/day_declaration_screen.tscn").instantiate()
			container.add_child(_day_screen)
			_day_screen.setup(_budget)
			_day_screen.day_confirmed.connect(
				func(budget: DayBudgetManager):
					_on_day_confirmed(runner, budget))
			_day_screen.day_cancelled.connect(
				func(): runner.transition_to_state(_return_state))


func exit(runner) -> void:
	if _day_screen and is_instance_valid(_day_screen):
		_day_screen.queue_free()
		_day_screen = null


func handle_action(runner, action: String, payload: Dictionary) -> String:
	match action:
		"cancel_day":
			return _return_state
		"end_session":
			return "session_end"
	return ""


# ---------------------------------------------------------------------------
# Day resolution
# ---------------------------------------------------------------------------

func _on_day_confirmed(runner, budget: DayBudgetManager) -> void:
	_budget = budget
	_resolve_day(runner)


func _resolve_day(runner) -> void:
	## Process each slot in sequence.
	for slot_index in range(DayBudgetManager.SLOT_COUNT):
		var slot_type: int = _budget.get_slot(slot_index)

		# Advance time by 1 hour per slot.
		Timekeeping.advance_hours(1)

		match slot_type:
			DayBudgetManager.SlotType.MARCH:
				_resolve_march_slot(runner, slot_index)
			DayBudgetManager.SlotType.EXPLORE:
				_resolve_explore_slot(runner, slot_index)
			DayBudgetManager.SlotType.REST:
				pass  # Partial recovery — no action needed per slot.
			DayBudgetManager.SlotType.FORAGE:
				_resolve_forage_slot(runner, slot_index)
			DayBudgetManager.SlotType.HUNT:
				_resolve_hunt_slot(runner, slot_index)
			DayBudgetManager.SlotType.GUARD:
				pass  # Reduces surprise — handled in encounter resolution.
			DayBudgetManager.SlotType.CRAFT:
				pass  # Craft checks — future implementation.
			DayBudgetManager.SlotType.FREE:
				pass  # No specific action.

	# Day is complete — transition to camp for overnight rest.
	runner.transition_to_state("camp", {
		"return_state": _return_state,
		"is_town": false,
	})


func _resolve_march_slot(runner, _slot_index: int) -> void:
	# In full implementation: move party along planned route,
	# trigger encounter check per hex entered.
	# For now: emit notification.
	if runner.has_method("do_encounter_check"):
		var encounter = runner.do_encounter_check({})
		if encounter != null:
			runner.transition_to_state("combat", {
				"return_state": "day_declaration",
				"encounter_data": encounter,
			})


func _resolve_explore_slot(runner, _slot_index: int) -> void:
	# Detailed hex investigation — reveal features, find POIs.
	# For now: encounter check.
	if runner.has_method("do_encounter_check"):
		var encounter = runner.do_encounter_check({})
		if encounter != null:
			runner.transition_to_state("combat", {
				"return_state": "day_declaration",
				"encounter_data": encounter,
			})


func _resolve_forage_slot(_runner, _slot_index: int) -> void:
	# Foraging proficiency check.
	# Survival or Foraging proficiency: d20 >= 14 (target 11+ for Survival).
	var roll := DiceSystem.roll_digital(20, 1, 0, "proficiency_throw")
	if roll.modified_total >= 14:
		EventBus.notification_requested.emit({
			"type": "success",
			"category": "supply",
			"title": "Foraging Successful",
			"body": "Found enough food for 1d6 people.",
			"duration": 4.0,
		})
	else:
		EventBus.notification_requested.emit({
			"type": "info",
			"category": "supply",
			"title": "Foraging Failed",
			"body": "No food found this hour.",
			"duration": 3.0,
		})


func _resolve_hunt_slot(_runner, _slot_index: int) -> void:
	# Hunting — similar to foraging but requires weapon and can trigger encounters.
	var roll := DiceSystem.roll_digital(20, 1, 0, "proficiency_throw")
	if roll.modified_total >= 14:
		EventBus.notification_requested.emit({
			"type": "success",
			"category": "supply",
			"title": "Hunt Successful",
			"body": "Killed game — enough food for 2d6 people.",
			"duration": 4.0,
		})
	else:
		EventBus.notification_requested.emit({
			"type": "info",
			"category": "supply",
			"title": "Hunt Failed",
			"body": "No game found.",
			"duration": 3.0,
		})
