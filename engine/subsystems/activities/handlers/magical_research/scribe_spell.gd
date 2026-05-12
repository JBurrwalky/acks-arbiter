class_name ScribeSpellHandler
extends RefCounted

## scribe_spell handler (Phase 10B.1b).
##
## Major Ongoing, 7 days regardless of spell level. Per ax_campaign_play.xml
## §scribe_spell L781-792. No gp cost in RAW; the scroll itself (or formula
## access) is the cost.
##
## Adds a spell to character_spell_formulas. If source_kind='scroll', the
## scroll is consumed (deleted from inventory_items). Scribing from another
## spellbook does NOT erase the original.
##
## Eligibility:
##   - Arcane spellcaster.
##   - source_kind in {scroll, spellbook}.
##   - Can learn spells at target_spell_level.
##   - If source_kind='scroll': inventory_items.id = source_ref must exist
##     and belong to the character.
##   - If source_kind='spellbook': the source spellbook owner is recorded but
##     we don't strictly enforce permission in v1 (Judge call). Validation:
##     the source character_id must exist.
##
## No throw. Deterministic time. v1 simplification: doesn't track formula
## DRM (RAW says formulas in another's spellbook are encoded; deciphering may
## require additional cost/time). The handler treats spellbook source as
## already-deciphered; future v1.1 can add a decipher_spellbook activity.


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var character_id: String = String(state.get("character_id", ""))
	if character_id.is_empty():
		return {"summary": "scribe_spell: no character_id"}

	var character := _get_character(character_id)
	if character.is_empty():
		return {"summary": "scribe_spell: character not found"}

	var params := _parse_params(state)
	var target_spell_key: String = String(params.get("target_spell_key", ""))
	var target_spell_level: int = int(params.get("target_spell_level", 0))
	var source_kind: String = String(params.get("source_kind", ""))
	var source_ref: String = String(params.get("source_ref", ""))
	var library_id: String = String(params.get("library_id", ""))
	if library_id.is_empty():
		var location_ref: String = String(state.get("location_ref", ""))
		if location_ref.begins_with("library:"):
			library_id = location_ref.substr(8)

	if target_spell_key.is_empty():
		return {"summary": "scribe_spell: target_spell_key required"}
	if target_spell_level <= 0:
		return {"summary": "scribe_spell: target_spell_level must be 1+"}
	if not (source_kind in ["scroll", "spellbook"]):
		return {
			"summary": "scribe_spell: source_kind must be 'scroll' or 'spellbook' (got '%s')" % source_kind,
		}

	if not ResearchMagicHandler._is_arcane_caster(character):
		return {"summary": "scribe_spell failed: arcane caster required"}
	if not ResearchMagicHandler._can_learn_spell_level(character, target_spell_level):
		var caster_level: int = int(character.get("level", 1))
		return {
			"summary": "scribe_spell failed: caster cannot learn spells of level %d at level %d" % [
				target_spell_level, caster_level,
			],
		}

	var spell_registry := ResearchMagicHandler._get_spell_registry()
	if not spell_registry.has_spell(target_spell_key):
		return {"summary": "scribe_spell failed: spell '%s' not in registry" % target_spell_key}

	# Library check.
	if not library_id.is_empty():
		var library := CampaignRepository.get_library(library_id)
		if library.is_empty():
			return {"summary": "scribe_spell failed: library not found"}
		if String(library.get("owner_character_id", "")) != character_id:
			return {"summary": "scribe_spell failed: library not owned by caster"}
		if String(library.get("status", "")) != "operational":
			return {"summary": "scribe_spell failed: library not operational"}

	# Source validation.
	if source_kind == "scroll":
		if source_ref.is_empty():
			return {"summary": "scribe_spell failed: source_ref (scroll inventory id) required"}
		if not CampaignRepository.db.query_with_bindings(
			"SELECT id, character_id FROM inventory_items WHERE id = ? LIMIT 1", [source_ref]
		):
			return {"summary": "scribe_spell failed: SQL error reading scroll"}
		if CampaignRepository.db.query_result.is_empty():
			return {"summary": "scribe_spell failed: scroll inventory item not found"}
		var scroll_row: Dictionary = CampaignRepository.db.query_result[0]
		if String(scroll_row.get("character_id", "")) != character_id:
			return {"summary": "scribe_spell failed: scroll not in caster's inventory"}

	# Add to formulas (idempotent via UNIQUE constraint on character_id +
	# spell_key). Per RAW the scroll grants the formula; the scribed spell is
	# NOT auto-added to active repertoire — that's a separate replace_spell
	# operation if the caster wants to actually cast it.
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO character_spell_formulas
			(character_id, spell_key, spell_level)
		VALUES (?, ?, ?)
	""", [character_id, target_spell_key, target_spell_level])

	# Consume scroll if applicable.
	if source_kind == "scroll":
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM inventory_items WHERE id = ?", [source_ref]
		)

	# Audit row.
	var now_day: int = _calendar_day()
	var project_id := CampaignRepository.create_magic_research_project({
		"campaign_id": String(character.get("campaign_id", "")),
		"character_id": character_id,
		"project_kind": "spell",
		"target_spell_key": target_spell_key,
		"target_spell_level": target_spell_level,
		"gp_committed": 0,
		"days_total": 7,
		"days_completed": 7,
		"target_value": 0,
		"library_id": library_id,
		"status": "completed",
		"started_calendar_day": int(state.get("started_calendar_day", now_day)),
		"completed_calendar_day": now_day,
		"params_json": JSON.stringify({
			"activity": "scribe_spell",
			"source_kind": source_kind,
			"source_ref": source_ref,
		}),
	})
	EventBus.magic_research_project_completed.emit(project_id, character_id, true)

	var consume_note: String = " (scroll consumed)" if source_kind == "scroll" else " (source spellbook preserved)"
	return {
		"summary": "Scribed %s (L%d) into formulas%s. 7 days." % [
			target_spell_key, target_spell_level, consume_note,
		],
		"presentation": {
			"type": "toast",
			"text": "Scribed %s" % target_spell_key,
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
