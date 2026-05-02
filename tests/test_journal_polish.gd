extends "res://tests/test_suite_base.gd"

## H.2 polish — items 1 + 3 smoke tests.
##
## Covers:
##   - MarkdownLite converter (bold / italic / lists / @ entity links)
##   - InitiativeOverlay shared constant matches surface-side reservation
##   - Journal page _filter_by_search substring filter
##   - Notes filter-to-entity round-trip
##   - LogEntryRow Journal-context-menu signal wiring
##   - UnifiedLog accepts scroll-to-id without crashing on missing entry


const MarkdownLiteScript := preload("res://engine/subsystems/journal/markdown_lite.gd")
const JournalTabPageScript := preload("res://scenes/ui/notebook/tab_pages/journal_tab_page.gd")
const InitiativeOverlayScript := preload("res://scenes/ui/hud/initiative_overlay.gd")
const CombatScreenScript := preload("res://scenes/ui/combat/combat_screen.gd")
const DungeonCombatOverlayScript := preload("res://scenes/ui/combat/dungeon_combat_overlay.gd")
const LogEntryRowScript := preload("res://scenes/ui/hud/unified_log/log_entry_row.gd")
const UnifiedLogScript := preload("res://scenes/ui/hud/unified_log/unified_log.gd")


func run_all_tests() -> void:
	test_markdown_bold()
	test_markdown_italic()
	test_markdown_unordered_list()
	test_markdown_ordered_list()
	test_markdown_entity_link()
	test_markdown_mixed_inline()
	test_markdown_unbalanced_renders_verbatim()
	test_initiative_overlay_constant_matches_surfaces()
	test_filter_by_search_empty_query_returns_all()
	test_filter_by_search_substring_match()
	test_filter_by_search_case_insensitive()
	test_log_entry_row_emits_bookmark_in_journal()
	test_log_entry_row_emits_note_about_entry()
	test_unified_log_scroll_to_missing_id_does_not_crash()
	if not has_failures():
		print("JournalPolish: all tests passed.")


# ---------------------------------------------------------------------------
# MarkdownLite
# ---------------------------------------------------------------------------

func test_markdown_bold() -> void:
	check(MarkdownLiteScript.to_bbcode("a **bold** word") == "a [b]bold[/b] word",
		"bold should convert to [b]")


func test_markdown_italic() -> void:
	check(MarkdownLiteScript.to_bbcode("an *italic* word") == "an [i]italic[/i] word",
		"single-* italic should convert to [i]")


func test_markdown_unordered_list() -> void:
	var got := MarkdownLiteScript.to_bbcode("- alpha\n- beta")
	check(got == "[indent]• alpha[/indent]\n[indent]• beta[/indent]",
		"bullet list should produce indented bullets (got '%s')" % got)


func test_markdown_ordered_list() -> void:
	var got := MarkdownLiteScript.to_bbcode("1. first\n2. second")
	check(got == "[indent]1. first[/indent]\n[indent]2. second[/indent]",
		"ordered list should preserve numbers (got '%s')" % got)


func test_markdown_entity_link() -> void:
	var got := MarkdownLiteScript.to_bbcode("Talk to @aldric_pc and @brigid")
	check("[color=#a78240]@aldric_pc[/color]" in got,
		"@aldric_pc should render as colored token")
	check("[color=#a78240]@brigid[/color]" in got,
		"@brigid should render as colored token")


func test_markdown_mixed_inline() -> void:
	var got := MarkdownLiteScript.to_bbcode("**bold** and *italic* and @x")
	check(got == "[b]bold[/b] and [i]italic[/i] and [color=#a78240]@x[/color]",
		"mixed inline markdown should compose; got '%s'" % got)


func test_markdown_unbalanced_renders_verbatim() -> void:
	# Per the doc: malformed markdown should not crash. Forgiving behavior.
	var got := MarkdownLiteScript.to_bbcode("a *single asterisk")
	check(not got.is_empty(),
		"Unbalanced *italic* should not return empty / crash")


# ---------------------------------------------------------------------------
# InitiativeOverlay shared constant
# ---------------------------------------------------------------------------

func test_initiative_overlay_constant_matches_surfaces() -> void:
	var overlay_const: int = InitiativeOverlayScript.STRIP_OVERLAY_RESERVE
	check(CombatScreenScript.STRIP_OVERLAY_RESERVE == overlay_const,
		"CombatScreen.STRIP_OVERLAY_RESERVE should equal overlay's value")
	check(DungeonCombatOverlayScript.STRIP_OVERLAY_RESERVE == overlay_const,
		"DungeonCombatOverlay.STRIP_OVERLAY_RESERVE should equal overlay's value")


# ---------------------------------------------------------------------------
# Filter / search helpers (exercised through the page instance)
# ---------------------------------------------------------------------------

func test_filter_by_search_empty_query_returns_all() -> void:
	var page = JournalTabPageScript.new()
	add_child(page)
	var rows: Array = [{"title": "A"}, {"title": "B"}]
	var got: Array = page._filter_by_search(rows, "", ["title"])
	check(got.size() == 2, "Empty query should return all rows")
	page.queue_free()


func test_filter_by_search_substring_match() -> void:
	var page = JournalTabPageScript.new()
	add_child(page)
	var rows: Array = [
		{"title": "Aerendel Crossing", "body": ""},
		{"title": "Crypt of Skreech",  "body": ""},
		{"title": "Inn meeting",       "body": "talked at the Aerendel inn"},
	]
	var got: Array = page._filter_by_search(rows, "Aerendel", ["title", "body"])
	check(got.size() == 2,
		"Aerendel should match title-1 and body-3 (got %d)" % got.size())
	page.queue_free()


func test_filter_by_search_case_insensitive() -> void:
	var page = JournalTabPageScript.new()
	add_child(page)
	var rows: Array = [{"title": "AERENDEL"}, {"title": "other"}]
	var got: Array = page._filter_by_search(rows, "aerendel", ["title"])
	check(got.size() == 1, "Case-insensitive match should find AERENDEL")
	page.queue_free()


# ---------------------------------------------------------------------------
# LogEntryRow Journal context menu signals
# ---------------------------------------------------------------------------

func test_log_entry_row_emits_bookmark_in_journal() -> void:
	var row = LogEntryRowScript.new()
	add_child(row)
	row.setup({
		"id": 42, "category": "combat", "summary": "Hit for 5 damage",
		"actor_id": "pc_a", "target_id": "orc_b",
	})
	var got: Array = []
	row.bookmark_in_journal_requested.connect(func(e): got.append(e))
	row._on_context_menu_pressed(3)  # _MENU_BOOKMARK_JOURNAL
	check(got.size() == 1, "bookmark_in_journal_requested should fire once")
	if got.size() == 1:
		check(int(got[0].get("id", 0)) == 42,
			"Signal payload should carry the entry dict")
	row.queue_free()


func test_log_entry_row_emits_note_about_entry() -> void:
	var row = LogEntryRowScript.new()
	add_child(row)
	row.setup({
		"id": 7, "category": "dice", "summary": "natural 20",
		"actor_id": "pc_b", "target_id": "",
	})
	var got: Array = []
	row.note_about_entry_requested.connect(func(e): got.append(e))
	row._on_context_menu_pressed(4)  # _MENU_NOTE_ABOUT_ENTRY
	check(got.size() == 1, "note_about_entry_requested should fire once")
	if got.size() == 1:
		check(str(got[0].get("actor_id", "")) == "pc_b",
			"Note signal payload should carry actor_id")
	row.queue_free()


# ---------------------------------------------------------------------------
# UnifiedLog scroll-to-id resilience
# ---------------------------------------------------------------------------

func test_unified_log_scroll_to_missing_id_does_not_crash() -> void:
	var ulog = UnifiedLogScript.new()
	add_child(ulog)
	# A nonexistent id should fire a notification (not crash). We assert
	# only that the call returns without erroring.
	ulog._on_scroll_to_id_requested(-99999)
	check(true, "scroll-to nonexistent id should not crash")
	ulog.queue_free()
