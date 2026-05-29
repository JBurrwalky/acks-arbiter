class_name PlanHijinkHandler
extends RefCounted

## plan_hijink handler (Phase 10B.3 UI polish wave).
##
## Ongoing minor activity per RAW §plan_hijink L1217-1233. The launcher
## (SyndicateLauncher.prepare_and_launch_plan_hijink) calls
## HijinkPlanningResolver.start_planning at launch — this initializes
## planning_state='planning', rolls planning_days_required, and stuffs the
## rolled value into params so ActivityTimeCostExecutor._compute_ticks_required
## returns the correct duration.
##
## on_tick: advance planning_days_completed by 1 per day. When the day count
## hits the requirement, HijinkPlanningResolver.advance_planning flips
## planning_state to 'planned' and emits EventBus.hijink_planned.
##
## on_complete: defensive final flip (in case the tick boundary races); emits
## a summary.
##
## Params:
##   hijink_assignment_id    — String, REQUIRED.
##   planning_days_required  — int, set by start_planning at launch.


static func on_tick(state: Dictionary, _runner) -> Dictionary:
	var params: Dictionary = _read_params(state)
	var hijink_id: String = String(params.get("hijink_assignment_id", ""))
	if hijink_id.is_empty():
		return {"summary": "plan_hijink tick: hijink_assignment_id missing"}
	var finished: bool = HijinkPlanningResolver.advance_planning(hijink_id)
	if finished:
		return {"summary": "plan_hijink complete"}
	return {"summary": "plan_hijink tick advanced"}


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var params: Dictionary = _read_params(state)
	var hijink_id: String = String(params.get("hijink_assignment_id", ""))
	if hijink_id.is_empty():
		return {"summary": "plan_hijink: hijink_assignment_id missing"}
	# Defensive: if the on_tick boundary didn't flip the state, force-flip here.
	var row := SyndicateRepository.get_hijink(hijink_id)
	if str(row.get("planning_state", "")) == "planning":
		SyndicateRepository.update_hijink(hijink_id, {
			"planning_state": "planned",
			"status": "queued",
			"planning_days_completed": int(row.get("planning_days_required", 0)),
		})
		EventBus.hijink_planned.emit(
			hijink_id,
			str(row.get("hijink_kind", "")),
			str(row.get("target_id", "")),
		)
	return {
		"summary": "plan_hijink complete (%s ready to perform)" % str(row.get("hijink_kind", "")),
		"presentation": {"type": "toast", "text": "Hijink planned: %s" % str(row.get("hijink_kind", ""))},
	}


static func _read_params(state: Dictionary) -> Dictionary:
	var raw: Variant = state.get("params_json", "")
	if raw == null:
		return {}
	var json_str: String = str(raw)
	if json_str.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(json_str)
	if parsed is Dictionary:
		return parsed
	return {}
