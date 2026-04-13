class_name DowntimeState
extends SessionState

## Downtime session state — between-adventure activities in settlements.
##
## Activity hub with sub-wizards for: Hiring, Carousing, Hijinks,
## Reserve XP, Rest & Recuperate. Spell Research and Mercantile Ventures
## are placeholders for Phase J+.

var _downtime_screen = null
var _return_state: String = "settlement"


func enter(runner, context: Dictionary) -> void:
	_return_state = context.get("return_state", "settlement")

	GameState.transition_to(GameState.State.DOWNTIME)

	if runner.has_method("get_scene_container"):
		var container = runner.get_scene_container()
		if container:
			_downtime_screen = preload("res://scenes/ui/downtime/downtime_screen.tscn").instantiate()
			container.add_child(_downtime_screen)
			_downtime_screen.setup()
			_downtime_screen.downtime_ended.connect(
				func(): runner.transition_to_state(_return_state))


func exit(runner) -> void:
	if _downtime_screen and is_instance_valid(_downtime_screen):
		_downtime_screen.queue_free()
		_downtime_screen = null


func handle_action(runner, action: String, payload: Dictionary) -> String:
	match action:
		"end_downtime":
			return _return_state
		"end_session":
			return "session_end"
	return ""
