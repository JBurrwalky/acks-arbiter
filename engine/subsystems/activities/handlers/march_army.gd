class_name MarchArmyHandler
extends RefCounted

## Ongoing activity handler — wraps ArmyMarcher.march_army to surface army
## marching as an Ongoing-frequency activity in the Active Projects panel
## per gdd-army-warfare.md §7.5.
##
## Per gdd-domain-tab.md §11 + gdd-army-warfare.md §6 EventBus block, the
## "march" activity is scheduled by the activity executor; on_complete fires
## when the destination is reached (= when army_arrived_at_hex emits with the
## destination hex). For Phase 6A part 2 v1, this handler just records the
## march intent. The actual leg-by-leg movement is driven by ArmyMarcher
## directly via the EventScheduler; the activity_state row is for UI display
## (Active Projects).
##
## Activity params:
##   army_id: String          — the army being marched
##   destination_hex_q: int
##   destination_hex_r: int
##   march_mode: String       — 'normal' | 'forced' | 'cautious'
##   extraction_mode: String  — 'none' | 'requisition' | 'loot'


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	## When the activity_state's session completes (Ongoing frequency: per RAW
	## ax_campaign_play.xml §frequency_types.ongoing, completion is when the
	## destination is reached — ticks_required = number of legs).
	## For v1: this handler is invoked when the Activity executor counts the
	## final tick. We just verify the army has arrived and report the summary.
	var character_id: String = String(state.get("character_id", ""))
	var params: Dictionary = _parse_params(state)
	var army_id: String = String(params.get("army_id", ""))
	if army_id.is_empty():
		return {"summary": "march_army: no army_id", "success": false}

	var army: Dictionary = ArmyRepository.get_army(army_id)
	if army.is_empty():
		return {"summary": "march_army: army not found", "success": false}
	var current_state: String = String(army.get("state", ""))
	# The activity completes when the army is encamped at the destination.
	var arrived: bool = (current_state == "encamped" or current_state == "battling")
	var summary: String
	if arrived:
		summary = "Army %s arrived at destination" % String(army.get("name", army_id))
	else:
		summary = "March completed but army state is %s" % current_state
	var _ignored := character_id
	return {
		"summary": summary,
		"success": arrived,
		"army_id": army_id,
		"final_state": current_state,
	}


## Helper for the UI surface — schedules the actual march via ArmyMarcher.
## Call this from the form_army-style entry point right after launching the
## activity, OR from an explicit "March" button on the army detail panel.
static func schedule_march(
	army_id: String,
	destination_q: int,
	destination_r: int,
	current_time: int,
	scheduler: EventScheduler,
	march_mode: String = "normal",
	extraction_mode: String = "none"
) -> Dictionary:
	var marcher := ArmyMarcher.new()
	return marcher.march_army(
		army_id, destination_q, destination_r,
		current_time, scheduler, march_mode, extraction_mode
	)


static func _parse_params(state: Dictionary) -> Dictionary:
	var raw: String = String(state.get("params_json", "{}"))
	var parsed: Variant = JSON.parse_string(raw)
	if parsed is Dictionary:
		return parsed
	return {}
