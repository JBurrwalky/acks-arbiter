class_name CommanderDepartureCheck
extends RefCounted

## v1 intercept-helper for the §3.6 commander-departure rule per
## gdd-army-warfare.md. UI layers that move characters between parties (or
## otherwise separate a PC from their army) call this helper FIRST and
## surface the commander_departure_modal if any of the departing characters
## are active army commanders.
##
## Public API:
##   blocking_armies(departing_character_ids: Array) -> Array[Dictionary]
##     Returns the list of armies that the modal must be raised for, with
##     each entry shaped {army_id, name, commander_character_id, state}.
##
## Note: the UI surface is responsible for ACTUALLY blocking the action
## while the modal is open. This helper only enumerates the affected armies.


static func blocking_armies(departing_character_ids: Array) -> Array:
	if departing_character_ids.is_empty():
		return []
	var blocking: Array = []
	for cid in departing_character_ids:
		var character_id: String = String(cid)
		if character_id.is_empty():
			continue
		var armies: Array = ArmyRepository.list_armies_under_command(character_id)
		for army in armies:
			var state_v: Variant = army.get("state")
			var state: String = String(state_v) if state_v != null else ""
			# Disbanded armies are not blocking; battling armies are blocked
			# from any departure regardless (per §3.6 edge case "Combat in
			# progress"); the modal disables Cancel option in that case.
			if state == "disbanded":
				continue
			var aid_v: Variant = army.get("id")
			var name_v: Variant = army.get("name")
			blocking.append({
				"army_id": String(aid_v) if aid_v != null else "",
				"name": String(name_v) if name_v != null else "",
				"commander_character_id": character_id,
				"state": state,
			})
	return blocking


static func has_blocking_armies(departing_character_ids: Array) -> bool:
	return not blocking_armies(departing_character_ids).is_empty()
