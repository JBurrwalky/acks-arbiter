class_name ReplaceSpellHandler
extends RefCounted

## replace_spell handler (Phase 10B.1b).
##
## Major Ongoing, 7 days × spell_level. Cost 1,000 gp × spell_level.
## Per ax_campaign_play.xml §replace_spell L768-779.
##
## Swap one spell in the repertoire (character_spells) for another at the SAME
## level. New spell must already be in character_spell_formulas (the caster
## has access to the formula). The OLD spell's formula is preserved in
## character_spell_formulas — only its character_spells row is removed.
##
## Requirements per RAW L775:
##   - Arcane spellcaster.
##   - Full spell repertoire (RAW: the activity exists to manage repertoire
##     pressure when slots are full; we don't strictly enforce "full" since
##     it's only sometimes useful, but we DO require both spells to exist at
##     the same level).
##   - Copy of the new spell formula (character_spell_formulas row).
##
## No throw. Deterministic time + gp cost.


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var character_id: String = String(state.get("character_id", ""))
	if character_id.is_empty():
		return {"summary": "replace_spell: no character_id"}

	var character := _get_character(character_id)
	if character.is_empty():
		return {"summary": "replace_spell: character not found"}

	var params := _parse_params(state)
	var old_spell_key: String = String(params.get("old_spell_key", ""))
	var new_spell_key: String = String(params.get("new_spell_key", ""))
	var target_spell_level: int = int(params.get("target_spell_level", 0))
	var gp_committed: int = int(params.get("gp_committed", 0))
	var library_id: String = String(params.get("library_id", ""))
	if library_id.is_empty():
		var location_ref: String = String(state.get("location_ref", ""))
		if location_ref.begins_with("library:"):
			library_id = location_ref.substr(8)

	if old_spell_key.is_empty() or new_spell_key.is_empty():
		return {"summary": "replace_spell: old_spell_key and new_spell_key required"}
	if old_spell_key == new_spell_key:
		return {"summary": "replace_spell: old and new spells must differ"}
	if target_spell_level <= 0:
		return {"summary": "replace_spell: target_spell_level must be 1+"}
	if gp_committed < 1000 * target_spell_level:
		return {
			"summary": "replace_spell: insufficient gp_committed (need %d, have %d)" % [
				1000 * target_spell_level, gp_committed,
			],
		}
	if not ResearchMagicHandler._is_arcane_caster(character):
		return {"summary": "replace_spell failed: arcane caster required"}

	# Both spells must exist in the registry at the same level. RAW: "another
	# of equal level."
	var spell_registry := ResearchMagicHandler._get_spell_registry()
	if not spell_registry.has_spell(old_spell_key):
		return {"summary": "replace_spell failed: unknown old_spell_key '%s'" % old_spell_key}
	if not spell_registry.has_spell(new_spell_key):
		return {"summary": "replace_spell failed: unknown new_spell_key '%s'" % new_spell_key}
	var old_def: Dictionary = spell_registry.get_spell(old_spell_key)
	var new_def: Dictionary = spell_registry.get_spell(new_spell_key)
	var old_level: int = ResearchMagicHandler._get_arcane_spell_level(old_def)
	var new_level: int = ResearchMagicHandler._get_arcane_spell_level(new_def)
	if old_level == 0 or new_level == 0:
		return {
			"summary": "replace_spell failed: spells must be on the arcane spell list (old=%s, new=%s)" % [
				old_spell_key, new_spell_key,
			],
		}
	if old_level != new_level or new_level != target_spell_level:
		return {
			"summary": "replace_spell failed: spells must be at the same level (old=L%d, new=L%d, target=L%d)" % [
				old_level, new_level, target_spell_level,
			],
		}

	# Old spell must be in repertoire (the entry we're removing).
	if not CampaignRepository.db.query_with_bindings(
		"SELECT id FROM character_spells WHERE character_id = ? AND spell_key = ? LIMIT 1",
		[character_id, old_spell_key]
	):
		return {"summary": "replace_spell failed: SQL error reading old repertoire entry"}
	if CampaignRepository.db.query_result.is_empty():
		return {
			"summary": "replace_spell failed: old spell '%s' not in repertoire" % old_spell_key,
		}

	# New spell formula must be known (character_spell_formulas).
	if not CampaignRepository.db.query_with_bindings(
		"SELECT id FROM character_spell_formulas WHERE character_id = ? AND spell_key = ? LIMIT 1",
		[character_id, new_spell_key]
	):
		return {"summary": "replace_spell failed: SQL error reading formulas"}
	if CampaignRepository.db.query_result.is_empty():
		return {
			"summary": "replace_spell failed: caster does not have formula for '%s' (use scribe_spell first)" % new_spell_key,
		}

	# Library check.
	if not library_id.is_empty():
		var library := CampaignRepository.get_library(library_id)
		if library.is_empty():
			return {"summary": "replace_spell failed: library not found"}
		if String(library.get("owner_character_id", "")) != character_id:
			return {"summary": "replace_spell failed: library not owned by caster"}
		if String(library.get("status", "")) != "operational":
			return {"summary": "replace_spell failed: library not operational"}

	# Perform the swap.
	# Remove old from repertoire (formula preserved per RAW L777).
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM character_spells WHERE character_id = ? AND spell_key = ?",
		[character_id, old_spell_key]
	)
	# Add new to repertoire (formula already present per the check above).
	ResearchMagicHandler._add_spell_to_formulas_and_repertoire(
		character_id, new_spell_key, target_spell_level)

	var now_day: int = _calendar_day()
	var project_id := CampaignRepository.create_magic_research_project({
		"campaign_id": String(character.get("campaign_id", "")),
		"character_id": character_id,
		"project_kind": "spell",
		"target_spell_key": new_spell_key,
		"target_spell_level": target_spell_level,
		"cp_committed": gp_committed * 100,
		"days_total": 7 * target_spell_level,
		"days_completed": 7 * target_spell_level,
		"target_value": 0,
		"library_id": library_id,
		"status": "completed",
		"started_calendar_day": int(state.get("started_calendar_day", now_day)),
		"completed_calendar_day": now_day,
		"params_json": JSON.stringify({
			"activity": "replace_spell",
			"old_spell_key": old_spell_key,
		}),
	})
	EventBus.magic_research_project_completed.emit(project_id, character_id, true)

	return {
		"summary": "Replaced %s with %s in repertoire (L%d, %d gp, %d days). Old formula preserved." % [
			old_spell_key, new_spell_key, target_spell_level, gp_committed,
			7 * target_spell_level,
		],
		"presentation": {
			"type": "toast",
			"text": "Replaced %s with %s" % [old_spell_key, new_spell_key],
		},
	}


static func _get_character(character_id: String) -> Dictionary:
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM characters WHERE id = ? LIMIT 1", [character_id]
	):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func _parse_params(state: Dictionary) -> Dictionary:
	var raw: Variant = state.get("params_json", "{}")
	if raw is Dictionary:
		return raw
	if not (raw is String):
		return {}
	var parsed: Variant = JSON.parse_string(raw as String)
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}


static func _calendar_day() -> int:
	return Timekeeping.get_calendar_day()
