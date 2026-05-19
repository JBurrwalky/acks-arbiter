class_name AwaitTrialHandler
extends RefCounted

## await_trial handler (Phase 10B.3 UI polish wave).
##
## Ongoing major activity for caught_perpetrators awaiting trial per RAW
## §await_trial L1128-1149. Duration is pre-rolled at arrest time and stored
## on the caught_perpetrators row as `time_languishing_days`. The launcher
## (SyndicateLauncher.prepare_and_launch_await_trial) reads that value and
## passes it as params.time_languishing_days for the duration formula.
##
## on_complete: invoke CrimeAndPunishmentResolver.resolve, which writes the
## verdict / fine / punishment_kind back to the caught_perpetrators row,
## applies permanent flags via CharacterLegalStatusRepository, and emits
## EventBus.verdict_rendered.
##
## Params:
##   caught_perpetrator_id   — String, REQUIRED.
##   time_languishing_days   — int, set by launcher (mirrors row value).


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var params: Dictionary = _read_params(state)
	var caught_id: String = String(params.get("caught_perpetrator_id", ""))
	if caught_id.is_empty():
		return {"summary": "await_trial: caught_perpetrator_id missing"}
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var current_day: int = Timekeeping.get_total_days()
	var result: Dictionary = CrimeAndPunishmentResolver.resolve(caught_id, current_day, rng)
	return {
		"summary": String(result.get("summary", "await_trial: verdict rendered")),
		"verdict": result.get("verdict", ""),
		"presentation": {
			"type": "modal",
			"title": "Verdict Rendered",
			"text": String(result.get("summary", "")),
		},
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
