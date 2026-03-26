class_name ActionPayload
extends RefCounted

## Typed payload for a player or NPC action in the action vocabulary.
## Every UI click and every text-input interpretation resolves to an ActionPayload.
## The engine validates and executes; the LLM interprets and selects.

var action_id: String = ""           # e.g. "attack_melee", "move_to_hex", "cast_spell"
var actor_id: String = ""            # character id performing the action
var parameters: Dictionary = {}      # action-specific parameters (typed by action_id)
var context_tags: Array[String] = [] # e.g. ["combat", "melee"]
var game_round: int = 0              # combat round or exploration turn count


static func from_dict(data: Dictionary) -> ActionPayload:
	var a := ActionPayload.new()
	a.action_id = data.get("action_id", "")
	a.actor_id = data.get("actor_id", "")
	a.parameters = data.get("parameters", {})
	a.context_tags = data.get("context_tags", [])
	a.game_round = data.get("game_round", 0)
	return a


func is_valid() -> bool:
	# An action with no id or no actor cannot be resolved by the engine.
	return not action_id.is_empty() and not actor_id.is_empty()
