class_name CastCharitableSpellsHandler
extends RefCounted

## cast_charitable_spells handler (Phase 10A.2 — Faith block).
##
## Singular minor activity. Per ax_campaign_play.xml §cast_charitable_spells
## L396-406: cast one or more daily spells for charitable purposes. Track the
## gp value of all charitably cast spells using spell costs from the Spell
## Availability by Market table and apply it to next month's congregant
## growth.
##
## State.params_json shape:
##   {
##     "spell_keys": [<String>, ...],     # informational; logged but not used for math
##     "gp_value_total": <int>,            # caller computes from spell-cost table
##   }
##
## v1 takes `gp_value_total` from params. The spell-cost lookup (mapping each
## spell_key to its gp value per the Spell Availability by Market table) is
## deferred to the caller — typically the UI Faith block builds the gp_value
## from the launched spells before launching the activity. Future iterations
## may move that lookup here.


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var character_id: String = String(state.get("character_id", ""))
	if character_id.is_empty():
		return {"summary": "cast_charitable_spells: no character_id"}

	var params := _parse_params(state)
	var gp_value: int = int(params.get("gp_value_total", 0))
	if gp_value <= 0:
		return {"summary": "cast_charitable_spells completed (no gp value tracked)"}

	CampaignRepository.add_congregant_pending_gp(character_id, gp_value)

	var spell_keys: Array = params.get("spell_keys", [])
	var spell_summary: String = ""
	if spell_keys is Array and not spell_keys.is_empty():
		spell_summary = " — " + ", ".join((spell_keys as Array).map(func(k): return String(k)))

	return {
		"summary": "Charitable spells cast: %d gp value tracked%s" % [gp_value, spell_summary],
		"presentation": {"type": "toast", "text": "Charitable spells cast (%d gp value)" % gp_value},
	}


static func _parse_params(state: Dictionary) -> Dictionary:
	var raw: String = String(state.get("params_json", "{}"))
	if raw.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(raw)
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}
