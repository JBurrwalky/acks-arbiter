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
##
## [NEEDS-SPELL-COST-LOOKUP-PASS] (Prereq.7 audit per gdd-settlement-economy.md §11.1)
## The Spell Availability by Market table is not yet encoded as data; this handler
## relies entirely on the caller's gp_value computation. When a future session
## ships the lookup, expected scope:
##   1. Encode the table from RAW (acore-campaign-hijinks.xml) as
##      `data/spells/spell_availability_by_market.json`.
##   2. Add `SpellRegistry.get_spell_cost_gp(spell_key: String) -> int` reading the JSON.
##   3. Rewire this handler to compute `gp_value_total` from `spell_keys` rather
##      than taking it as a caller param.
## The gap is not blocking — Phase 10B.2 (Trade) and 10B.3 (Syndicate) do not
## depend on the spell-cost lookup.


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var character_id: String = String(state.get("character_id", ""))
	if character_id.is_empty():
		return {"summary": "cast_charitable_spells: no character_id"}

	var params := _parse_params(state)
	# RAW spell value is captured in gp by the launcher; convert at the
	# boundary so storage stays in cp.
	var gp_value: int = int(params.get("gp_value_total", 0))
	if gp_value <= 0:
		return {"summary": "cast_charitable_spells completed (no gp value tracked)"}
	var cp_value: int = gp_value * 100

	CampaignRepository.add_congregant_pending_cp(character_id, cp_value)

	var spell_keys: Array = params.get("spell_keys", [])
	var spell_summary: String = ""
	if spell_keys is Array and not spell_keys.is_empty():
		spell_summary = " — " + ", ".join((spell_keys as Array).map(func(k): return String(k)))

	var pretty := Currency.format_cost(cp_value)
	return {
		"summary": "Charitable spells cast: %s value tracked%s" % [pretty, spell_summary],
		"presentation": {"type": "toast", "text": "Charitable spells cast (%s value)" % pretty},
	}


static func _parse_params(state: Dictionary) -> Dictionary:
	var raw: String = String(state.get("params_json", "{}"))
	if raw.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(raw)
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}
