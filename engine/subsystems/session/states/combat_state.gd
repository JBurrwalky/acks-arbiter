class_name CombatState
extends SessionState

## Stub combat state for F-1 integration.
##
## Records the return state key so that when combat ends, the session runner
## transitions back to the correct exploration state (wilderness, dungeon, etc.).
## F-1 will flesh this out with CombatController instantiation, combat scene
## push, initiative, rounds, etc.

var _encounter_data: Dictionary = {}
var _return_state_key: String = "wilderness"


func enter(runner, context: Dictionary) -> void:
	_encounter_data = context.get("encounter_data", {})
	_return_state_key = context.get("return_state", "wilderness")
	runner.cancel_pending_roll()
	EventBus.combat_started.emit(_encounter_data.get("encounter_id", ""))


func exit(runner) -> void:
	pass


func handle_action(runner, action: String, payload: Dictionary) -> String:
	if action == "combat_ended":
		# Advance time by rounds fought
		var rounds_fought: int = payload.get("rounds", 0)
		if rounds_fought > 0:
			runner.advance_exploration_time(0)  # don't advance turns
			Timekeeping.advance_rounds(rounds_fought)
		EventBus.combat_ended.emit(
			_encounter_data.get("encounter_id", ""),
			payload
		)
		return _return_state_key
	return ""
