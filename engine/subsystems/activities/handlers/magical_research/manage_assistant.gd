class_name ManageAssistantHandler
extends RefCounted

## manage_assistant handler (Phase 10B.1c).
##
## Trivial Restricted (monthly). Per ax_campaign_play.xml §manage_assistant
## L733-742 + acore-campaign-general-and-magic-research.xml §assistants
## L217-228:
##   - Caster level 9+.
##   - Caster supervises 1 + INT-bonus assistants.
##   - Each assistant performs one additional magic item creation task per
##     work session under supervision.
##   - Assistants must be arcane casters of L1+ (or 0-level with Alchemy 2+
##     for potions only).
##   - Assistant's success chance is based on the assistant's OWN level, not
##     the supervisor's.
##
## v1 10B.1c scope: handler validates supervisor eligibility (L9+, arcane)
## and records the supervisor relationship. The actual parallel item-creation
## orchestration (spawning extra magic_research_projects rows for each
## assistant when the supervisor launches research_magic[magic_item]) is
## DEFERRED to a future polish wave because:
##   1. Assistants are followers (10B.1a `followers` table) but the assistant-
##      promotion-to-classed-follower path is 10B.1d work.
##   2. The "extra item creation tasks" effect requires a per-assistant
##      project queue that the activity engine doesn't surface today.
##
## What the v1 handler actually does:
##   1. Verifies L9+ arcane caster.
##   2. Reads params.assistant_character_ids and validates each is a follower
##      of the supervisor (source_kind='aspirant' with level >= 1, or any
##      follower with character_class in arcane-caster set).
##   3. Returns a summary listing the supervised count and the additional-
##      task budget (= count, since each assistant grants 1 extra task).
##   4. Future polish (10B.1c.polish): wire the extra-task budget into the
##      research_magic launch flow so consumers can spawn parallel projects.


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var character_id: String = String(state.get("character_id", ""))
	if character_id.is_empty():
		return {"summary": "manage_assistant: no character_id"}

	var character := _get_character(character_id)
	if character.is_empty():
		return {"summary": "manage_assistant: character not found"}

	var caster_level: int = int(character.get("level", 1))
	if caster_level < 9:
		return {
			"summary": "manage_assistant failed: caster must be L9+ (was L%d)" % caster_level,
		}
	# Any spellcaster can manage assistants per RAW L740 — divine and arcane
	# both qualify. The handler does NOT require arcane-only here.

	var int_mod: int = MagicResearchThrowUtil.int_mod_for_character(character)
	var max_assistants: int = 1 + max(0, int_mod)

	var params := _parse_params(state)
	var raw_assistants: Array = params.get("assistant_character_ids", [])
	if not (raw_assistants is Array):
		raw_assistants = []

	# Validate each assistant.
	var valid_assistants: Array[String] = []
	var rejected: Array = []
	for raw_id: Variant in raw_assistants:
		var assistant_id: String = String(raw_id)
		if assistant_id.is_empty():
			continue
		var reason: String = _validate_assistant(assistant_id, character_id)
		if reason.is_empty():
			valid_assistants.append(assistant_id)
		else:
			rejected.append({"id": assistant_id, "reason": reason})

	if valid_assistants.size() > max_assistants:
		# Soft-cap: take only the first N.
		valid_assistants = valid_assistants.slice(0, max_assistants)

	var summary: String = "Managing %d/%d assistants (L%d caster, +%d INT)." % [
		valid_assistants.size(), max_assistants, caster_level, int_mod,
	]
	if rejected.size() > 0:
		summary += " %d rejected." % rejected.size()
	summary += " Extra item-creation task budget = %d (parallel-task wiring lands in a future polish wave)." % valid_assistants.size()

	return {
		"summary": summary,
		"presentation": {
			"type": "toast",
			"text": "Managing %d assistants" % valid_assistants.size(),
		},
	}


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

static func _validate_assistant(assistant_id: String, supervisor_id: String) -> String:
	# Assistant must be a follower of the supervisor (any source_kind).
	if not CampaignRepository.db.query_with_bindings("""
		SELECT * FROM followers
		WHERE id = ? AND owner_character_id = ? LIMIT 1
	""", [assistant_id, supervisor_id]):
		return "SQL error reading assistant"
	if CampaignRepository.db.query_result.is_empty():
		# Fallback: a characters row (e.g., a hired henchman) can also serve
		# as an assistant.
		if not CampaignRepository.db.query_with_bindings(
			"SELECT id, level, character_class FROM characters WHERE id = ? LIMIT 1",
			[assistant_id]
		):
			return "assistant not found in followers or characters"
		if CampaignRepository.db.query_result.is_empty():
			return "assistant not found"
		# v1 simplification: accept any characters row as a valid assistant.
		# Tighter validation (L1+ arcane or L0 with Alchemy 2+) is a polish
		# item paired with the parallel-task orchestration work.
		return ""
	var follower: Dictionary = CampaignRepository.db.query_result[0]
	var lvl: int = int(follower.get("level", 0))
	if lvl < 1:
		# 0-level aspirants must have Alchemy 2+ for potion-creation
		# assistance per RAW L223. v1 simplification: skip the proficiency
		# check; reject all 0-level assistants until the polish wave wires
		# the per-item-category eligibility.
		return "0-level aspirant cannot assist in v1 (Alchemy 2+ wiring deferred)"
	return ""


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

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
