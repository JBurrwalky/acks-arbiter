class_name FormArmyHandler
extends RefCounted

## Singular activity handler — wraps ArmyComposer.compose() so the activity
## executor can launch army formation as a 1-game-hour activity per
## gdd-army-warfare.md §3.1 (form army flow) + §3.5 step "Confirm and commit."
##
## Activity params (from activity_state.params_json):
##   plan: Dictionary  — the full ArmyComposer.compose plan
##
## On_complete returns:
##   { summary, success, army_id, errors, warnings }
##
## EventBus.army_formed fires on success per gdd-army-warfare.md §6 EventBus
## block.


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var character_id: String = String(state.get("character_id", ""))
	var params: Dictionary = _parse_params(state)
	var plan: Dictionary = params.get("plan", {})
	if plan.is_empty():
		return {"summary": "form_army: no plan provided", "success": false, "errors": ["no_plan"]}

	# Stamp the form_army request with the launching character if missing.
	if not plan.has("political_owner_id"):
		plan["political_owner_id"] = character_id
	if not plan.has("command_character_id"):
		plan["command_character_id"] = character_id

	var result: Dictionary = ArmyComposer.compose(plan)
	if not bool(result.get("success", false)):
		return {
			"summary": "Army formation failed: %s" % [result.get("errors", [])],
			"success": false,
			"errors": result.get("errors", []),
			"warnings": result.get("warnings", []),
		}

	var army_id: String = String(result.get("army_id", ""))
	if EventBus.has_signal("army_formed"):
		var leader: Dictionary = ArmyRepository.get_army_leader(army_id)
		EventBus.emit_signal(
			"army_formed",
			army_id,
			String(plan.get("political_owner_id", "")),
			String(leader.get("id", ""))
		)
	return {
		"summary": "Army formed (%d warnings)" % result.get("warnings", []).size(),
		"success": true,
		"army_id": army_id,
		"errors": [],
		"warnings": result.get("warnings", []),
	}


static func _parse_params(state: Dictionary) -> Dictionary:
	var raw: String = String(state.get("params_json", "{}"))
	var parsed: Variant = JSON.parse_string(raw)
	if parsed is Dictionary:
		return parsed
	return {}
