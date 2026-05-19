class_name OrderHijinkHandler
extends RefCounted

## order_hijink handler (Phase 10B.3 UI polish wave).
##
## Singular major (or minor if assigning to ≤ 1/6 of syndicate per RAW L1212;
## the activity_level downgrade is applied by the launcher, not here). Per
## ax_campaign_play.xml §order_hijink L1202-1215, the boss assigns hijinks
## to syndicate members at his base.
##
## This handler is the on_complete that runs once the boss spends the
## activity tick. It inserts a `hijink_assignments` row with planning_state
## 'unplanned' and status 'queued'. The actual planning + perform steps
## are launched separately as their own activities (plan_hijink /
## perform_hijink).
##
## Params (read from state.params_json):
##   syndicate_id          — String, REQUIRED. The syndicate this order targets.
##   syndicate_member_id   — String, REQUIRED. The member being assigned.
##   hijink_kind           — String, REQUIRED. One of the 6 kinds.
##   target_id             — String, OPTIONAL. For assassinating: victim char id.
##   hideout_id            — String, OPTIONAL. The stronghold (if any).


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var params: Dictionary = _read_params(state)
	var boss_id: String = String(state.get("character_id", ""))
	var syndicate_id: String = String(params.get("syndicate_id", ""))
	var member_id: String = String(params.get("syndicate_member_id", ""))
	var kind: String = String(params.get("hijink_kind", ""))
	var target_id: String = String(params.get("target_id", ""))
	var hideout_id: String = String(params.get("hideout_id", ""))

	if syndicate_id.is_empty() or member_id.is_empty() or kind.is_empty():
		return {"summary": "order_hijink failed: syndicate_id / syndicate_member_id / hijink_kind required"}

	# Verify the boss matches the syndicate.
	var syndicate := SyndicateRepository.get_syndicate(syndicate_id)
	if syndicate.is_empty():
		return {"summary": "order_hijink failed: syndicate not found"}
	if String(syndicate.get("boss_character_id", "")) != boss_id:
		return {"summary": "order_hijink failed: only the syndicate boss may order hijinks"}

	# Verify the member belongs to this syndicate and is active.
	var member := SyndicateRepository.get_member(member_id)
	if member.is_empty() or String(member.get("syndicate_id", "")) != syndicate_id:
		return {"summary": "order_hijink failed: member not in this syndicate"}
	if String(member.get("status", "")) != "active":
		return {"summary": "order_hijink failed: member status is not 'active'"}

	# Hideout fallback: if not specified, use the syndicate's hideout.
	# hideout_stronghold_id is nullable; defensive coercion required.
	if hideout_id.is_empty():
		hideout_id = _str_or_empty(syndicate.get("hideout_stronghold_id"))

	var hijink_id: String = SyndicateRepository.create_hijink({
		"syndicate_id": syndicate_id,
		"syndicate_member_id": member_id,
		"boss_character_id": boss_id,
		"hideout_id": hideout_id,
		"hijink_kind": kind,
		"planning_state": "unplanned",
		"status": "queued",
		"target_id": target_id,
		"started_day": int(state.get("started_calendar_day", 0)),
	})
	if hijink_id.is_empty():
		return {"summary": "order_hijink failed: hijink_assignments INSERT failed"}

	return {
		"summary": "Ordered %s hijink for member %s" % [kind, member_id.substr(0, 8)],
		"hijink_id": hijink_id,
		"presentation": {"type": "toast", "text": "Hijink ordered: %s" % kind},
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


## SQLite NULLs surface as null in Dictionary; String(null) errors in Godot 4.
static func _str_or_empty(v: Variant) -> String:
	if v == null:
		return ""
	return str(v)
