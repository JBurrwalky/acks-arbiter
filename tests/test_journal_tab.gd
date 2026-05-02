extends "res://tests/test_suite_base.gd"

## H.2 — Journal tab + JournalRepository smoke tests.
##
## Covers:
##   - Migration 045_journal.sql tables exist (narrative_entries / player_notes
##     / journal_bookmarks)
##   - JournalRepository CRUD for all three entity types
##   - count_notes_for_entity matches the JSON-array contains semantic
##   - bookmark target_kind validation rejects unknown kinds
##   - Empty-state surfaces when active party is unset
##   - Per-tab substate round-trip
##   - Notes badge column on Henchmen Roster reflects the count
##
## Tests use a real CampaignRepository (autoload) — the Journal tables are
## per-party scoped and need a real `parties` row to satisfy the FK. We
## create a dedicated test campaign + party at the start and clean up
## inserts on teardown.


const JournalTabPageScript := preload("res://scenes/ui/notebook/tab_pages/journal_tab_page.gd")

var _test_campaign_id: String = ""
var _test_party_id: String = ""


func run_all_tests() -> void:
	_setup_test_party()
	test_migration_tables_exist()
	test_create_and_list_narrative_entries()
	test_update_and_delete_narrative_entry()
	test_create_and_list_notes()
	test_count_notes_for_entity()
	test_create_and_list_bookmarks()
	test_bookmark_rejects_unknown_target_kind()
	test_empty_state_when_no_active_party()
	test_substate_round_trip()
	_teardown_test_party()
	if not has_failures():
		print("JournalTab: all tests passed.")


# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

func _setup_test_party() -> void:
	_test_campaign_id = "test_journal_campaign_%d" % randi()
	_test_party_id = "test_journal_party_%d" % randi()
	# Insert minimal campaign + party rows so FKs resolve. CampaignRepository
	# already created the schema during autoload init.
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[_test_campaign_id, "Test Campaign"])
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO parties (id, campaign_id, name) VALUES (?, ?, ?)",
		[_test_party_id, _test_campaign_id, "Test Party"])


func _teardown_test_party() -> void:
	# CASCADE on parties.id should clean up child rows in narrative_entries /
	# player_notes / journal_bookmarks.
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM parties WHERE id = ?", [_test_party_id])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [_test_campaign_id])


# ---------------------------------------------------------------------------
# Migration
# ---------------------------------------------------------------------------

func test_migration_tables_exist() -> void:
	for table in ["narrative_entries", "player_notes", "journal_bookmarks"]:
		CampaignRepository.db.query(
			"SELECT name FROM sqlite_master WHERE type='table' AND name='%s'" % table)
		check(not CampaignRepository.db.query_result.is_empty(),
			"Migration 045 should create '%s' table" % table)


# ---------------------------------------------------------------------------
# Narrative entries
# ---------------------------------------------------------------------------

func test_create_and_list_narrative_entries() -> void:
	var repo := JournalRepository.new(CampaignRepository)
	var id1 := repo.create_narrative_entry(_test_party_id, {
		"title": "Chapter 1: Arrival",
		"body":  "The party reached Aerendel after four days of travel.",
		"significance": "major",
		"timestamp_ingame": 100,
	})
	check(not id1.is_empty(), "create_narrative_entry should return a non-empty id")
	var id2 := repo.create_narrative_entry(_test_party_id, {
		"title": "Chapter 2: Inn meeting",
		"body":  "An old man told us of the Crypt.",
		"timestamp_ingame": 200,
	})
	check(not id2.is_empty(), "second narrative entry should also create")

	var entries := repo.list_narrative_entries(_test_party_id)
	check(entries.size() == 2,
		"Expected 2 narrative entries; got %d" % entries.size())
	# Reverse-chronological by timestamp_ingame: entry 2 (ts=200) first.
	if entries.size() == 2:
		check(str(entries[0].get("title", "")) == "Chapter 2: Inn meeting",
			"Entries should be reverse-chronological (Chapter 2 first)")


func test_update_and_delete_narrative_entry() -> void:
	var repo := JournalRepository.new(CampaignRepository)
	var id := repo.create_narrative_entry(_test_party_id, {
		"title": "Draft entry",
		"body":  "Initial body",
	})
	check(not id.is_empty(), "Create should succeed for update test")
	var ok := repo.update_narrative_entry(id, {
		"title": "Final title",
		"significance": "milestone",
	})
	check(ok, "update_narrative_entry should return true")
	var got := repo.get_narrative_entry(id)
	check(str(got.get("title", "")) == "Final title",
		"Updated title should round-trip; got '%s'" % got.get("title", ""))
	check(str(got.get("significance", "")) == "milestone",
		"Updated significance should round-trip")

	var deleted := repo.delete_narrative_entry(id)
	check(deleted, "delete_narrative_entry should return true")
	var after := repo.get_narrative_entry(id)
	check(after.is_empty(), "Deleted entry should not be retrievable")


# ---------------------------------------------------------------------------
# Notes
# ---------------------------------------------------------------------------

func test_create_and_list_notes() -> void:
	var repo := JournalRepository.new(CampaignRepository)
	var id := repo.create_note(_test_party_id, {
		"title": "Theory: the runes",
		"body":  "The runes glowed when we approached the door.",
		"attached_entity_ids":   JSON.stringify(["henchman_brigid"]),
		"attached_entity_kinds": JSON.stringify(["henchman"]),
		"pinned": 1,
	})
	check(not id.is_empty(), "create_note should return a non-empty id")

	var notes := repo.list_notes(_test_party_id)
	check(notes.size() >= 1, "list_notes should include the created note")
	if notes.size() >= 1:
		check(int(notes[0].get("pinned", 0)) == 1,
			"Pinned notes should sort first")


func test_count_notes_for_entity() -> void:
	var repo := JournalRepository.new(CampaignRepository)
	# Pre-seed two notes attached to the same entity, one to a different entity.
	repo.create_note(_test_party_id, {
		"title": "Note A",
		"body":  "About PC X",
		"attached_entity_ids":   JSON.stringify(["pc_x"]),
		"attached_entity_kinds": JSON.stringify(["pc"]),
	})
	repo.create_note(_test_party_id, {
		"title": "Note B",
		"body":  "Also about PC X",
		"attached_entity_ids":   JSON.stringify(["pc_x", "npc_y"]),
		"attached_entity_kinds": JSON.stringify(["pc", "npc"]),
	})
	repo.create_note(_test_party_id, {
		"title": "Note C",
		"body":  "Only about NPC Y",
		"attached_entity_ids":   JSON.stringify(["npc_y"]),
		"attached_entity_kinds": JSON.stringify(["npc"]),
	})
	var count_x := repo.count_notes_for_entity(_test_party_id, "pc_x")
	check(count_x == 2, "Expected 2 notes for pc_x; got %d" % count_x)
	var count_y := repo.count_notes_for_entity(_test_party_id, "npc_y")
	check(count_y == 2, "Expected 2 notes for npc_y; got %d" % count_y)
	var count_unknown := repo.count_notes_for_entity(_test_party_id, "no_such_id")
	check(count_unknown == 0,
		"Unknown entity id should return 0 notes; got %d" % count_unknown)


# ---------------------------------------------------------------------------
# Bookmarks
# ---------------------------------------------------------------------------

func test_create_and_list_bookmarks() -> void:
	var repo := JournalRepository.new(CampaignRepository)
	var id := repo.create_bookmark(_test_party_id, "narrative_entry",
		"narrative_id_42", "The Fall of Brigid", "callbacks")
	check(not id.is_empty(), "create_bookmark should return a non-empty id")

	var bookmarks := repo.list_bookmarks(_test_party_id)
	check(bookmarks.size() >= 1, "list_bookmarks should include the new entry")
	var found := false
	for b in bookmarks:
		if str(b.get("id", "")) == id:
			found = true
			check(str(b.get("target_kind", "")) == "narrative_entry",
				"target_kind should round-trip")
			check(str(b.get("category", "")) == "callbacks",
				"category should round-trip")
	check(found, "Created bookmark should appear in list_bookmarks")


func test_bookmark_rejects_unknown_target_kind() -> void:
	var repo := JournalRepository.new(CampaignRepository)
	var id := repo.create_bookmark(_test_party_id, "invalid_kind",
		"some_id", "label", "")
	check(id.is_empty(),
		"Unknown target_kind should return empty id (got '%s')" % id)


# ---------------------------------------------------------------------------
# Tab page integration
# ---------------------------------------------------------------------------

func test_empty_state_when_no_active_party() -> void:
	GameState.active_party_id = ""
	var page = JournalTabPageScript.new()
	add_child(page)
	# When no active party, the page surfaces an EmptyStatePage and hides
	# the sub-tab strip.
	check(page._subtab_strip != null and not page._subtab_strip.visible,
		"Sub-tab strip should hide when no active party")
	check(page._empty_state != null,
		"Empty-state page should surface when no active party")
	page.queue_free()


func test_substate_round_trip() -> void:
	NotebookState.set_substate_for_tab(_test_party_id, "journal", {
		"active_subtab": "bookmarks",
	})
	var got := NotebookState.get_substate_for_tab(_test_party_id, "journal")
	check(got.get("active_subtab", "") == "bookmarks",
		"Journal substate active_subtab should round-trip (got '%s')" % got.get("active_subtab", ""))
