class_name SessionEndState
extends SessionState

## Handles session teardown: saves all state, ends the GameState session,
## and transitions back to campaign select.


func enter(runner, context: Dictionary) -> void:
	runner.end_session()
	runner.transition_to_state("campaign_select")
