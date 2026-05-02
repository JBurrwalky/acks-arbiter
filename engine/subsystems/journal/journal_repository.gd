class_name JournalRepository
extends RefCounted

## Phase H.2 — Journal tab data access. Wraps CampaignRepository's db handle
## for the three Journal-owned tables: narrative_entries, player_notes,
## journal_bookmarks.
##
## Per gdd-journal-tab.md v1.1. All three tables are per-party scoped
## (matching the Unified Log per-party model per
## gdd-unified-log-panel.md §13).
##
## CRUD pattern matches HenchmanLifecycleManager — RefCounted, takes the
## CampaignRepository at construction so tests can inject a FakeRepo.
##
## Public API:
##   Narrative entries:
##     create_narrative_entry(party_id, fields) -> id
##     update_narrative_entry(id, fields)
##     delete_narrative_entry(id)
##     list_narrative_entries(party_id) -> Array[Dictionary]
##     get_narrative_entry(id) -> Dictionary
##
##   Notes:
##     create_note(party_id, fields) -> id
##     update_note(id, fields)
##     delete_note(id)
##     list_notes(party_id) -> Array[Dictionary]
##     list_notes_for_entity(party_id, entity_id) -> Array[Dictionary]
##     count_notes_for_entity(party_id, entity_id) -> int
##     get_note(id) -> Dictionary
##
##   Bookmarks:
##     create_bookmark(party_id, target_kind, target_id, label, category) -> id
##     delete_bookmark(id)
##     list_bookmarks(party_id) -> Array[Dictionary]
##     get_bookmark(id) -> Dictionary
##
## All `fields` dicts use the table column names verbatim. Missing fields
## fall back to schema defaults; extra fields are silently ignored.


# Allowed-fields whitelists for partial updates / inserts. Keep in sync with
# migration 045_journal.sql column lists.
const _NARRATIVE_FIELDS := [
	"title", "body",
	"timestamp_ingame", "timestamp_realworld",
	"source", "significance",
	"related_unified_log_entry_ids", "related_entity_ids",
]
const _NOTE_FIELDS := [
	"title", "body",
	"attached_entity_ids", "attached_entity_kinds",
	"category", "pinned",
	"timestamp_ingame", "timestamp_realworld",
]
const _BOOKMARK_FIELDS := [
	"label", "category",
	"timestamp_realworld",
]


var _repo  # CampaignRepository (or test fake exposing `db.query_with_bindings`)


func _init(repo) -> void:
	_repo = repo


# ---------------------------------------------------------------------------
# Narrative entries
# ---------------------------------------------------------------------------

## Insert a new narrative entry for [param party_id]. Returns the new id, or
## "" on insert failure. [param fields] dict accepts any of _NARRATIVE_FIELDS;
## omitted fields use schema defaults.
func create_narrative_entry(party_id: String, fields: Dictionary) -> String:
	if party_id.is_empty():
		return ""
	var id := _generate_id()
	var now := int(Time.get_unix_time_from_system())
	# Default timestamp_realworld to now if caller didn't supply one.
	if not fields.has("timestamp_realworld"):
		fields = fields.duplicate()
		fields["timestamp_realworld"] = now
	if not _insert_row("narrative_entries", id, party_id, fields, _NARRATIVE_FIELDS):
		return ""
	return id


## Patch an existing narrative entry. Only whitelisted fields apply; touches
## updated_at automatically. Returns true on success.
func update_narrative_entry(id: String, fields: Dictionary) -> bool:
	if id.is_empty():
		return false
	return _update_row("narrative_entries", id, fields, _NARRATIVE_FIELDS, true)


func delete_narrative_entry(id: String) -> bool:
	return _delete_row("narrative_entries", id)


## Returns all narrative entries for [param party_id], reverse-chronological
## by in-game timestamp.
func list_narrative_entries(party_id: String) -> Array:
	if party_id.is_empty():
		return []
	if not _repo.db.query_with_bindings("""
			SELECT * FROM narrative_entries
			WHERE party_id = ?
			ORDER BY timestamp_ingame DESC, created_at DESC
		""", [party_id]):
		return []
	return _repo.db.query_result.duplicate()


func get_narrative_entry(id: String) -> Dictionary:
	if id.is_empty():
		return {}
	if not _repo.db.query_with_bindings(
			"SELECT * FROM narrative_entries WHERE id = ?", [id]
		) or _repo.db.query_result.is_empty():
		return {}
	return _repo.db.query_result[0]


# ---------------------------------------------------------------------------
# Player notes
# ---------------------------------------------------------------------------

func create_note(party_id: String, fields: Dictionary) -> String:
	if party_id.is_empty():
		return ""
	var id := _generate_id()
	if not fields.has("timestamp_realworld"):
		fields = fields.duplicate()
		fields["timestamp_realworld"] = int(Time.get_unix_time_from_system())
	if not _insert_row("player_notes", id, party_id, fields, _NOTE_FIELDS):
		return ""
	return id


func update_note(id: String, fields: Dictionary) -> bool:
	if id.is_empty():
		return false
	return _update_row("player_notes", id, fields, _NOTE_FIELDS, true)


func delete_note(id: String) -> bool:
	return _delete_row("player_notes", id)


## Pinned notes appear first, then most-recently-updated.
func list_notes(party_id: String) -> Array:
	if party_id.is_empty():
		return []
	if not _repo.db.query_with_bindings("""
			SELECT * FROM player_notes
			WHERE party_id = ?
			ORDER BY pinned DESC, updated_at DESC
		""", [party_id]):
		return []
	return _repo.db.query_result.duplicate()


## Returns notes whose attached_entity_ids JSON array contains [param entity_id].
## SQLite has no JSON contains operator across versions, so this filters
## client-side after fetching the party's notes.
func list_notes_for_entity(party_id: String, entity_id: String) -> Array:
	if party_id.is_empty() or entity_id.is_empty():
		return []
	var all_notes := list_notes(party_id)
	var matches: Array = []
	for note in all_notes:
		var attached: Array = _parse_json_array(str(note.get("attached_entity_ids", "[]")))
		if attached.has(entity_id):
			matches.append(note)
	return matches


## Convenience for cross-tab "Notes" badge counts (Henchmen tab Roster /
## Character tab Status sub-tab) — does the same JSON-array filter as
## list_notes_for_entity but only returns the count.
func count_notes_for_entity(party_id: String, entity_id: String) -> int:
	return list_notes_for_entity(party_id, entity_id).size()


func get_note(id: String) -> Dictionary:
	if id.is_empty():
		return {}
	if not _repo.db.query_with_bindings(
			"SELECT * FROM player_notes WHERE id = ?", [id]
		) or _repo.db.query_result.is_empty():
		return {}
	return _repo.db.query_result[0]


# ---------------------------------------------------------------------------
# Journal bookmarks
# ---------------------------------------------------------------------------

func create_bookmark(party_id: String, target_kind: String, target_id: String,
		label: String = "", category: String = "") -> String:
	if party_id.is_empty() or target_kind.is_empty() or target_id.is_empty():
		return ""
	if not target_kind in ["unified_log_entry", "narrative_entry", "note"]:
		push_warning("JournalRepository.create_bookmark: invalid target_kind '%s'" % target_kind)
		return ""
	var id := _generate_id()
	var now := int(Time.get_unix_time_from_system())
	if not _repo.db.query_with_bindings("""
			INSERT INTO journal_bookmarks
				(id, party_id, target_kind, target_id, label, category, timestamp_realworld)
			VALUES (?, ?, ?, ?, ?, ?, ?)
		""", [id, party_id, target_kind, target_id, label, category, now]):
		return ""
	return id


func delete_bookmark(id: String) -> bool:
	return _delete_row("journal_bookmarks", id)


func list_bookmarks(party_id: String) -> Array:
	if party_id.is_empty():
		return []
	if not _repo.db.query_with_bindings("""
			SELECT * FROM journal_bookmarks
			WHERE party_id = ?
			ORDER BY created_at DESC
		""", [party_id]):
		return []
	return _repo.db.query_result.duplicate()


func get_bookmark(id: String) -> Dictionary:
	if id.is_empty():
		return {}
	if not _repo.db.query_with_bindings(
			"SELECT * FROM journal_bookmarks WHERE id = ?", [id]
		) or _repo.db.query_result.is_empty():
		return {}
	return _repo.db.query_result[0]


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _generate_id() -> String:
	# Mirrors CampaignRepository.generate_id static (which lives on the
	# autoload class). Using a local copy keeps JournalRepository pure
	# RefCounted without importing the autoload's static directly.
	return "%08x%04x%04x%04x%08x%04x" % [
		randi(), randi() & 0xFFFF, randi() & 0xFFFF,
		randi() & 0xFFFF, randi(), randi() & 0xFFFF
	]


## INSERT with id + party_id + whitelisted fields. Builds the SQL dynamically
## from the present columns to keep schema-default behavior for omitted ones.
func _insert_row(table: String, id: String, party_id: String,
		fields: Dictionary, whitelist: Array) -> bool:
	var cols: Array[String] = ["id", "party_id"]
	var placeholders: Array[String] = ["?", "?"]
	var values: Array = [id, party_id]
	for col in whitelist:
		if not fields.has(col):
			continue
		cols.append(col)
		placeholders.append("?")
		values.append(fields[col])
	var sql := "INSERT INTO %s (%s) VALUES (%s)" % [
		table, ", ".join(cols), ", ".join(placeholders),
	]
	return _repo.db.query_with_bindings(sql, values)


## UPDATE with whitelisted fields. Skips columns absent from [param fields].
## When [param touch_updated_at] is true, also sets updated_at = now.
func _update_row(table: String, id: String, fields: Dictionary,
		whitelist: Array, touch_updated_at: bool) -> bool:
	var assignments: Array[String] = []
	var values: Array = []
	for col in whitelist:
		if not fields.has(col):
			continue
		assignments.append("%s = ?" % col)
		values.append(fields[col])
	if assignments.is_empty() and not touch_updated_at:
		return true  # no-op
	if touch_updated_at:
		assignments.append("updated_at = datetime('now')")
	values.append(id)
	var sql := "UPDATE %s SET %s WHERE id = ?" % [table, ", ".join(assignments)]
	return _repo.db.query_with_bindings(sql, values)


func _delete_row(table: String, id: String) -> bool:
	if id.is_empty():
		return false
	return _repo.db.query_with_bindings(
		"DELETE FROM %s WHERE id = ?" % table, [id])


func _parse_json_array(text: String) -> Array:
	if text.is_empty():
		return []
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Array:
		return parsed
	return []
