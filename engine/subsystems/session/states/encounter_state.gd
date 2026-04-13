class_name EncounterState
extends SessionState

## NPC encounter/social interaction session state.
##
## Wraps the InteractionResolver for reaction rolls and influence checks.
## Provides a UI for NPC encounter, tone selection, and action resolution.
##
## Context keys:
##   "encounter_data": Dictionary — encounter info (monster_group, number, etc.)
##   "return_state": String — state to return to after encounter resolves
##   "npc_data": Dictionary — NPC details (optional, for named NPC encounters)

var _encounter_screen = null
var _return_state: String = "wilderness"
var _encounter_data: Dictionary = {}


func enter(runner, context: Dictionary) -> void:
	_return_state = context.get("return_state", "wilderness")
	_encounter_data = context.get("encounter_data", {})

	GameState.transition_to(GameState.State.EXPLORATION)

	if runner.has_method("get_scene_container"):
		var container = runner.get_scene_container()
		if container:
			_encounter_screen = preload("res://scenes/ui/encounter/encounter_screen.tscn").instantiate()
			container.add_child(_encounter_screen)
			_encounter_screen.setup(_encounter_data)
			_encounter_screen.encounter_resolved.connect(
				func(result: Dictionary):
					_on_encounter_resolved(runner, result))
			_encounter_screen.combat_requested.connect(
				func():
					runner.transition_to_state("combat", {
						"return_state": _return_state,
						"encounter_data": _encounter_data,
					}))
			_encounter_screen.flee_requested.connect(
				func():
					runner.transition_to_state(_return_state))


func exit(runner) -> void:
	if _encounter_screen and is_instance_valid(_encounter_screen):
		_encounter_screen.queue_free()
		_encounter_screen = null


func handle_action(runner, action: String, payload: Dictionary) -> String:
	match action:
		"attack":
			return "combat"
		"flee":
			return _return_state
		"end_session":
			return "session_end"
	return ""


func _on_encounter_resolved(runner, result: Dictionary) -> void:
	EventBus.interaction_resolved.emit(
		result.get("target_id", ""),
		result
	)
	runner.transition_to_state(_return_state)
