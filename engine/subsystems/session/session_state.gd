class_name SessionState
extends RefCounted

## Base class for all session runner states.
##
## Each concrete state extends this and overrides the lifecycle methods.
## The [param runner] argument is the SessionRunner node (untyped to avoid
## circular class_name references).
##
## State lifecycle:
##   enter(runner, context)   — state becomes active; wire signals, show UI
##   exit(runner)             — state is leaving; disconnect signals, clean up
##   handle_action(runner, action, payload) — process a validated action
##                              returns next state key ("" to stay)


## Called when this state becomes active.
## [param context] carries transition-specific data (e.g., dungeon entrance dict).
func enter(runner, context: Dictionary) -> void:
	pass


## Called when this state is being left. Clean up controllers, scenes, signals.
func exit(runner) -> void:
	pass


## Called by SessionRunner to process a validated game action.
## Returns the next state key (String) if a transition is warranted, or "" to stay.
## Actions come from either UI interactions or LLM interpretation — the state
## doesn't know or care which input channel produced the action.
func handle_action(runner, action: String, payload: Dictionary) -> String:
	return ""
