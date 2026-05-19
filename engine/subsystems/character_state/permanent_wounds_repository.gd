class_name PermanentWoundsRepository
extends RefCounted

## CRUD for the character_permanent_wounds table (migration 120).
##
## Wound rows are append-only — multiple convictions or wound events insert
## separate rows so the WoundEffectAggregator can sum across them with a
## per-category cap (per Phase 10B.3 #6 design: reaction cap -10).
##
## Source provenance is stored as a free-form string ("corporal_punishment:<kind>"
## or "mortal_wounds:<damage_type>") so audit + UI can render the cause.


## Insert a new wound row. Returns the new row's id on success, or "" on failure.
static func add_wound(
		character_id: String,
		wound_kind: String,
		source: String,
		applied_calendar_day: int,
		notes: String = ""
) -> String:
	if character_id.is_empty() or wound_kind.is_empty():
		return ""
	var wound_id := CampaignRepository.generate_id()
	if not CampaignRepository.db.query_with_bindings("""
		INSERT INTO character_permanent_wounds
			(id, character_id, wound_kind, source, applied_calendar_day, notes)
		VALUES (?, ?, ?, ?, ?, ?)
	""", [wound_id, character_id, wound_kind, source, applied_calendar_day, notes]):
		push_error("PermanentWoundsRepository.add_wound: insert failed character=%s kind=%s" % [
			character_id, wound_kind])
		return ""
	if EventBus.has_signal("permanent_wound_applied"):
		EventBus.emit_signal("permanent_wound_applied",
			character_id, wound_kind, source)
	return wound_id


## Returns all wound rows for a character (in insertion order).
static func list_for_character(character_id: String) -> Array:
	if character_id.is_empty():
		return []
	if not CampaignRepository.db.query_with_bindings("""
		SELECT * FROM character_permanent_wounds
		WHERE character_id = ?
		ORDER BY applied_calendar_day ASC, created_at ASC
	""", [character_id]):
		return []
	return CampaignRepository.db.query_result.duplicate()


## Test-only: clear all wound rows. NEVER used in production code paths.
static func _clear_all_for_test() -> void:
	CampaignRepository.db.query("DELETE FROM character_permanent_wounds")
