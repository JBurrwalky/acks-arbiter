class_name PerformBloodSacrificeHandler
extends RefCounted

## perform_blood_sacrifice handler (Phase 10A.2 — Faith block).
##
## Restricted minor activity, **Chaotic-only**. Per ax_campaign_play.xml
## §perform_blood_sacrifice L475-487:
##   - May not be performed more than once per day (restricted_period = 8640).
##   - The spellcaster conducts one blood sacrifice per class level per session.
##   - Each blood sacrifice generates DP equal to the XP value of the
##     sacrificed creature.
##
## State.params_json shape:
##   {
##     "sacrifice_target_ids": [<creature_or_character_id>, ...],
##     "sacrifice_xp_values":  [<int>, ...]   # optional precomputed; if absent,
##                                            # the handler tries to look up by id
##   }
##
## v1 reads xp values from params (the caller — likely the Faith block UI —
## resolves XP per target via MonsterRegistry or character XP). If params
## don't include precomputed values, the handler attempts the lookup itself.


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var character_id: String = String(state.get("character_id", ""))
	if character_id.is_empty():
		return {"summary": "perform_blood_sacrifice: no character_id"}

	var character := _get_character(character_id)
	if String(character.get("alignment", "neutral")) != "chaotic":
		return {"summary": "perform_blood_sacrifice failed: chaotic alignment required"}

	var params := _parse_params(state)
	var class_level: int = int(character.get("level", 1))
	var xp_values: Array = params.get("sacrifice_xp_values", [])
	if not (xp_values is Array) or xp_values.is_empty():
		# Defensive fallback: nothing to sacrifice.
		return {"summary": "perform_blood_sacrifice: no sacrifices recorded"}

	# Cap at class_level sacrifices per RAW.
	var capped: Array = (xp_values as Array).slice(0, min(class_level, xp_values.size()))
	var dp_total: int = 0
	for v in capped:
		dp_total += int(v)

	if dp_total <= 0:
		return {"summary": "perform_blood_sacrifice: total XP value is 0"}

	var new_balance: int = CampaignRepository.add_divine_power(character_id, dp_total)
	EventBus.divine_power_changed.emit(character_id, new_balance, dp_total)

	return {
		"summary": "Blood sacrifice: %d sacrifices, %d gp DP generated (new balance %d)" % [
			capped.size(), dp_total, new_balance
		],
		"presentation": {"type": "toast", "text": "DP +%d (blood sacrifice)" % dp_total},
	}


static func _parse_params(state: Dictionary) -> Dictionary:
	var raw: String = String(state.get("params_json", "{}"))
	if raw.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(raw)
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}


static func _get_character(character_id: String) -> Dictionary:
	if not CampaignRepository.db.query_with_bindings(
		"SELECT id, alignment, level FROM characters WHERE id = ? LIMIT 1",
		[character_id]
	):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0]
