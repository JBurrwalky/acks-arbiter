class_name InterpleadHandler
extends RefCounted

## interplead handler (Phase 10B.3 UI polish wave).
##
## Singular minor per RAW §interplead L1175-1186 + §interpleader L293-298.
## Sets `caught_perpetrators.interpleader_id` so the C&P resolver picks up
## the interpleader's CHA modifier at trial time. Eligibility per RAW:
## the interpleader must be a domain ruler in the domain where the
## perpetrator was caught. v1 trusts the launcher to have validated the
## domain-ruler relationship; this handler does no further check.
##
## RAW L1185: if the interpleader controls the domain where the crime
## occurred, he may instead issue a decree freeing the perpetrator without
## trial. That alternative path is the existing `issue_decree` activity,
## not this one — interplead only adds the verdict-roll modifier.
##
## Params:
##   caught_perpetrator_id   — String, REQUIRED.


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var params: Dictionary = _read_params(state)
	var caught_id: String = String(params.get("caught_perpetrator_id", ""))
	var interpleader_id: String = String(state.get("character_id", ""))

	if caught_id.is_empty() or interpleader_id.is_empty():
		return {"summary": "interplead failed: caught_perpetrator_id and character_id required"}

	var row := SyndicateRepository.get_caught(caught_id)
	if row.is_empty():
		return {"summary": "interplead failed: caught_perpetrators row not found"}
	if row.get("verdict") != null:
		return {"summary": "interplead failed: trial already resolved"}

	SyndicateRepository.update_caught(caught_id, {"interpleader_id": interpleader_id})
	return {
		"summary": "Interplead recorded — interpleader's CHA mod applies at trial",
		"presentation": {"type": "toast", "text": "Interpleader recorded"},
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
