class_name PerformHijinkHandler
extends RefCounted

## perform_hijink handler (Phase 10B.3 UI polish wave).
##
## Singular major (1 day for plannable kinds) OR Ongoing major (3d6+10 /
## 3d4+8 / 2d6+5 days for non-plannable kinds — carousing / spying /
## treasure_hunting) per RAW §perform_hijink L1235-1251.
##
## This handler is the FINAL on_complete that fires when the activity's day
## counter reaches zero (singular: 1 tick; ongoing: pre-rolled day count).
## It dispatches to the kind-specific handler module (the 6 per-hijink
## handlers shipped in the Phase 10B.3 main wave), which performs the actual
## throw + yield + catch resolution.
##
## Params (read from state.params_json):
##   hijink_assignment_id   — String, REQUIRED.
##   perform_days_required  — int, OPTIONAL (used by duration formula).
##   merchandise_type       — String, OPTIONAL (smuggling/stealing override).
##   settlement_id          — String, OPTIONAL.
##   victim_level           — int, OPTIONAL (assassinating).
##   target_id              — String, OPTIONAL.
##   for_hire               — bool, OPTIONAL (assassinating).


const KIND_DISPATCH := {
	"assassinating":    "AssassinatingHijinkHandler",
	"carousing":        "CarousingHijinkHandler",
	"smuggling":        "SmugglingHijinkHandler",
	"spying":           "SpyingHijinkHandler",
	"stealing":         "StealingHijinkHandler",
	"treasure_hunting": "TreasureHuntingHijinkHandler",
}


static func on_complete(state: Dictionary, runner) -> Dictionary:
	var params: Dictionary = _read_params(state)
	var hijink_id: String = String(params.get("hijink_assignment_id", ""))
	if hijink_id.is_empty():
		return {"summary": "perform_hijink: hijink_assignment_id missing"}
	var row := SyndicateRepository.get_hijink(hijink_id)
	if row.is_empty():
		return {"summary": "perform_hijink: hijink_assignments row not found"}
	var kind: String = String(row.get("hijink_kind", ""))
	var class_name_str: String = String(KIND_DISPATCH.get(kind, ""))
	if class_name_str.is_empty():
		return {"summary": "perform_hijink: unknown hijink_kind '%s'" % kind}

	# Merge hijink_assignment_id into params and route to the per-kind handler.
	# Each kind handler's on_complete reads params from `state` (the dict it
	# receives), so we hand it a state-shaped dict carrying the merged params.
	var inner_params: Dictionary = params.duplicate(true)
	inner_params["hijink_assignment_id"] = hijink_id
	# Carry forward the settlement context if not specified — handlers
	# resolve it from the syndicate's base if needed.
	var inner_state: Dictionary = {
		"hijink_assignment_id": hijink_id,
		"merchandise_type": inner_params.get("merchandise_type", ""),
		"settlement_id": inner_params.get("settlement_id", ""),
		"victim_level": inner_params.get("victim_level", 1),
		"target_id": inner_params.get("target_id", ""),
		"for_hire": inner_params.get("for_hire", true),
		"calendar_day": int(state.get("started_calendar_day", Timekeeping.get_total_days())),
	}

	# Dispatch via match — the handler class_names are resolved at compile
	# time, so we can't fully data-drive this without ClassDB. Each branch
	# is a one-line call.
	match kind:
		"assassinating":
			return AssassinatingHijinkHandler.on_complete(inner_state, runner)
		"carousing":
			return CarousingHijinkHandler.on_complete(inner_state, runner)
		"smuggling":
			return SmugglingHijinkHandler.on_complete(inner_state, runner)
		"spying":
			return SpyingHijinkHandler.on_complete(inner_state, runner)
		"stealing":
			return StealingHijinkHandler.on_complete(inner_state, runner)
		"treasure_hunting":
			return TreasureHuntingHijinkHandler.on_complete(inner_state, runner)
	return {"summary": "perform_hijink: unreachable dispatch for kind '%s'" % kind}


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
