class_name RewriteSpellHandler
extends RefCounted

## rewrite_spell handler (Phase 10B.1b).
##
## Major Ongoing, 7 days × spell_level. Cost 1,000 gp × spell_level.
## Per ax_campaign_play.xml §rewrite_spell L756-766.
##
## RAW requires the caster to be "an arcane spellcaster who has lost his spell
## book." v1 simplification: we don't track lost-spellbook state explicitly;
## the handler accepts the launch and re-adds the spell to character_spells +
## character_spell_formulas. Idempotent.
##
## No throw. Deterministic time + gp cost.


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var character_id: String = String(state.get("character_id", ""))
	if character_id.is_empty():
		return {"summary": "rewrite_spell: no character_id"}

	var character := _get_character(character_id)
	if character.is_empty():
		return {"summary": "rewrite_spell: character not found"}

	var params := _parse_params(state)
	var target_spell_key: String = String(params.get("target_spell_key", ""))
	var target_spell_level: int = int(params.get("target_spell_level", 0))
	var gp_committed: int = int(params.get("gp_committed", 0))
	var library_id: String = String(params.get("library_id", ""))
	if library_id.is_empty():
		var location_ref: String = String(state.get("location_ref", ""))
		if location_ref.begins_with("library:"):
			library_id = location_ref.substr(8)

	if target_spell_key.is_empty():
		return {"summary": "rewrite_spell: target_spell_key required"}
	if target_spell_level <= 0:
		return {"summary": "rewrite_spell: target_spell_level must be 1+"}
	if gp_committed < 1000 * target_spell_level:
		return {
			"summary": "rewrite_spell: insufficient gp_committed (need %d, have %d)" % [
				1000 * target_spell_level, gp_committed,
			],
		}
	if not ResearchMagicHandler._is_arcane_caster(character):
		return {"summary": "rewrite_spell failed: arcane caster required"}

	# Library check (lighter than research_magic — rewrite needs library access
	# but doesn't have a spell-level support requirement per RAW; we still
	# require an operational owned library for Q21 location-ref consistency).
	if not library_id.is_empty():
		var library := CampaignRepository.get_library(library_id)
		if library.is_empty():
			return {"summary": "rewrite_spell failed: library not found"}
		if String(library.get("owner_character_id", "")) != character_id:
			return {"summary": "rewrite_spell failed: library not owned by caster"}
		if String(library.get("status", "")) != "operational":
			return {"summary": "rewrite_spell failed: library not operational"}

	# Re-add the spell.
	ResearchMagicHandler._add_spell_to_formulas_and_repertoire(
		character_id, target_spell_key, target_spell_level)

	# Audit row in magic_research_projects (project_kind='spell',
	# completed). This makes the rewrite/replace/scribe activity show up in
	# the Magical Research block's research-history view.
	var now_day: int = _calendar_day()
	var project_id := CampaignRepository.create_magic_research_project({
		"campaign_id": String(character.get("campaign_id", "")),
		"character_id": character_id,
		"project_kind": "spell",
		"target_spell_key": target_spell_key,
		"target_spell_level": target_spell_level,
		"gp_committed": gp_committed,
		"days_total": 7 * target_spell_level,
		"days_completed": 7 * target_spell_level,
		"target_value": 0,  # no throw for rewrite
		"library_id": library_id,
		"status": "completed",
		"started_calendar_day": int(state.get("started_calendar_day", now_day)),
		"completed_calendar_day": now_day,
		"params_json": JSON.stringify({"activity": "rewrite_spell"}),
	})

	EventBus.magic_research_project_completed.emit(project_id, character_id, true)

	return {
		"summary": "Rewrote %s (L%d) into spellbook (%d gp, %d days)." % [
			target_spell_key, target_spell_level, gp_committed, 7 * target_spell_level,
		],
		"presentation": {
			"type": "toast",
			"text": "Rewrote %s" % target_spell_key,
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
	var date: Dictionary = Timekeeping.get_date()
	var year: int = int(date.get("year", 1))
	var month: int = int(date.get("month", 1))
	var day: int = int(date.get("day", 1))
	return ((year - 1) * 12 + (month - 1)) * Timekeeping.DAYS_PER_MONTH + day
