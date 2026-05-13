class_name CharacterLegalStatusRepository
extends RefCounted

## Character legal-status persistence — tracks the three permanent flags
## (Branded / Maimed / Proscribed) that contribute to RAW's Crime & Punishment
## prior-crimes modifier per acore-campaign-hijinks.xml:300-304.
##
## Per generation/gdd-settlement-economy.md §10. RefCounted static-function
## library; no autoload. Phase 10B.3's C&P resolver calls
## `get_prior_crimes_modifier(character_id)` once per throw.
##
## Modifier formula (negative — penalties to the perpetrator):
##   prior_crimes_modifier_cache = (-1 × is_branded) + (-2 × is_maimed) + (-3 × is_proscribed)
##
## v1 does NOT mutate combat-affecting character state for any flag —
## per Phase 10 Q6 [RESOLVED 2026-05-10], permanent-wound effects are logged
## but not yet wired to HP / attack-roll / inventory mutations.
## [NEEDS-PERMANENT-WOUND-COMBAT-PASS] flag for future work.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const FLAG_BRANDED := "branded"
const FLAG_MAIMED := "maimed"
const FLAG_PROSCRIBED := "proscribed"

const _ALLOWED_FLAGS := [FLAG_BRANDED, FLAG_MAIMED, FLAG_PROSCRIBED]


# ---------------------------------------------------------------------------
# Reads
# ---------------------------------------------------------------------------

## Returns the legal-status row as a dict, or a zeroed default if no row exists.
## Default dict keys: character_id, is_branded, is_maimed, is_proscribed,
## prior_crimes_modifier_cache, branded_at_calendar_day (null if unset), etc.
static func get_status(character_id: String) -> Dictionary:
	if character_id.is_empty():
		return _default_dict("")
	if not CampaignRepository.db.query_with_bindings(
			"SELECT * FROM character_legal_status WHERE character_id = ?",
			[character_id]):
		return _default_dict(character_id)
	if CampaignRepository.db.query_result.is_empty():
		return _default_dict(character_id)
	return CampaignRepository.db.query_result[0]


## Convenience: returns prior_crimes_modifier_cache, or 0 if no row.
## Phase 10B.3's Crime & Punishment resolver invokes this once per throw.
static func get_prior_crimes_modifier(character_id: String) -> int:
	if character_id.is_empty():
		return 0
	if not CampaignRepository.db.query_with_bindings(
			"SELECT prior_crimes_modifier_cache FROM character_legal_status WHERE character_id = ?",
			[character_id]):
		return 0
	if CampaignRepository.db.query_result.is_empty():
		return 0
	return int(CampaignRepository.db.query_result[0].get("prior_crimes_modifier_cache", 0))


# ---------------------------------------------------------------------------
# Flag setters
# ---------------------------------------------------------------------------

## Sets is_branded=1, records the calendar_day, updates the notes field
## (if notes is non-empty, appends with a newline separator), recomputes
## the modifier cache, emits character_legal_status_changed.
## Returns true on success.
static func apply_branded(character_id: String, calendar_day: int, notes: String = "") -> bool:
	return _apply_flag(character_id, FLAG_BRANDED, calendar_day, notes)


static func apply_maimed(character_id: String, calendar_day: int, notes: String = "") -> bool:
	return _apply_flag(character_id, FLAG_MAIMED, calendar_day, notes)


static func apply_proscribed(character_id: String, calendar_day: int, notes: String = "") -> bool:
	return _apply_flag(character_id, FLAG_PROSCRIBED, calendar_day, notes)


## Sets the named flag back to 0. Recomputes the modifier cache.
## Used for future amnesty / expungement mechanics; not consumed by v1 C&P resolver.
## Returns true if the flag was set and is now cleared; false if the flag was
## already 0 or the character has no row.
static func clear_flag(character_id: String, flag: String) -> bool:
	if character_id.is_empty() or not (flag in _ALLOWED_FLAGS):
		return false
	if not _ensure_row(character_id):
		return false
	var column: String = _flag_to_column(flag)
	if column.is_empty():
		return false
	# Only update if currently set.
	var current: Dictionary = get_status(character_id)
	if int(current.get(column, 0)) == 0:
		return false
	CampaignRepository.db.query_with_bindings("""
		UPDATE character_legal_status
		SET %s = 0, updated_at = datetime('now')
		WHERE character_id = ?
	""" % column, [character_id])
	var new_total: int = recompute_modifier_cache(character_id)
	EventBus.character_legal_status_changed.emit(character_id, flag, 0, new_total)
	return true


# ---------------------------------------------------------------------------
# Maintenance
# ---------------------------------------------------------------------------

## Recomputes prior_crimes_modifier_cache from the current boolean flags.
## Returns the recomputed value. Defensive helper for external code that
## might mutate the booleans via raw SQL.
static func recompute_modifier_cache(character_id: String) -> int:
	if character_id.is_empty():
		return 0
	var status: Dictionary = get_status(character_id)
	var total: int = (
		int(status.get("is_branded", 0)) * -1
		+ int(status.get("is_maimed", 0)) * -2
		+ int(status.get("is_proscribed", 0)) * -3
	)
	CampaignRepository.db.query_with_bindings("""
		UPDATE character_legal_status
		SET prior_crimes_modifier_cache = ?, updated_at = datetime('now')
		WHERE character_id = ?
	""", [total, character_id])
	return total


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

## INSERT OR IGNORE the row with all-zero defaults. Returns true if a row
## now exists (whether or not we created it this call).
static func _ensure_row(character_id: String) -> bool:
	if character_id.is_empty():
		return false
	if not CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO character_legal_status (character_id) VALUES (?)
	""", [character_id]):
		return false
	return true


## Shared body for apply_branded / _maimed / _proscribed.
static func _apply_flag(
		character_id: String,
		flag: String,
		calendar_day: int,
		notes: String,
) -> bool:
	if character_id.is_empty() or not (flag in _ALLOWED_FLAGS):
		return false
	if not _ensure_row(character_id):
		return false
	var bool_col: String = _flag_to_column(flag)
	var day_col: String = "%s_at_calendar_day" % flag
	# Set boolean + timestamp.
	CampaignRepository.db.query_with_bindings("""
		UPDATE character_legal_status
		SET %s = 1, %s = ?, updated_at = datetime('now')
		WHERE character_id = ?
	""" % [bool_col, day_col], [calendar_day, character_id])
	# Append notes if provided.
	if not notes.is_empty():
		_append_notes(character_id, notes)
	# Recompute + emit.
	var new_total: int = recompute_modifier_cache(character_id)
	EventBus.character_legal_status_changed.emit(character_id, flag, 1, new_total)
	return true


static func _flag_to_column(flag: String) -> String:
	match flag:
		FLAG_BRANDED:
			return "is_branded"
		FLAG_MAIMED:
			return "is_maimed"
		FLAG_PROSCRIBED:
			return "is_proscribed"
	return ""


## Appends [param new_note] to the row's notes column with a newline
## separator (skipped if existing notes is empty).
static func _append_notes(character_id: String, new_note: String) -> void:
	if not CampaignRepository.db.query_with_bindings(
			"SELECT notes FROM character_legal_status WHERE character_id = ?",
			[character_id]):
		return
	if CampaignRepository.db.query_result.is_empty():
		return
	var existing: String = str(CampaignRepository.db.query_result[0].get("notes", ""))
	var combined: String = new_note if existing.is_empty() else "%s\n%s" % [existing, new_note]
	CampaignRepository.db.query_with_bindings(
		"UPDATE character_legal_status SET notes = ? WHERE character_id = ?",
		[combined, character_id])


static func _default_dict(character_id: String) -> Dictionary:
	return {
		"character_id": character_id,
		"is_branded": 0,
		"is_maimed": 0,
		"is_proscribed": 0,
		"prior_crimes_modifier_cache": 0,
		"branded_at_calendar_day": null,
		"maimed_at_calendar_day": null,
		"proscribed_at_calendar_day": null,
		"notes": "",
	}
