extends "res://scenes/ui/notebook/tab_pages/notebook_tab_page.gd"

## Journal tab — H.2 first pass per gdd-journal-tab.md v1.1.
##
## Replaces the β empty-state stub with three sub-tabs: Narrative Log
## (default), Notes, Bookmarks. The Journal is the player's curated
## narrative archive — distinct from the Unified Log (which is the immediate
## mechanical event feed per gdd-unified-log-panel.md).
##
## In scope (H.2 first pass):
##   - Sub-tab strip (Narrative Log / Notes / Bookmarks)
##   - Narrative Log: list + "New entry" modal (title + body + significance)
##   - Notes: list + "New note" modal (title + body + entity attachment freeform id)
##   - Bookmarks: list + "Open source" routing for narrative_entry / note targets
##   - Empty-states per sub-tab
##   - Per-tab substate persistence: active sub-tab id only
##   - Live refresh on EventBus.notebook_journal_changed (new signal authored
##     here to drive cross-tab badge refresh on Henchmen tab Roster)
##
## Out of scope (deferred to follow-ups):
##   - Markdown-lite rendering / toolbar / @-autocomplete entity-link insertion
##   - LLM auto-generation (Journal v1.1+ when LLM narration system lands)
##   - Inline-edit affordances (v1 is create + delete only; edit defers to a
##     future detail-pane refactor)
##   - Filter / search dropdowns
##   - Export pipeline (per gdd-journal-tab.md §11.2 step 9)
##   - Cross-activation from Unified Log right-click "Bookmark in Journal"
##     (the LogEntryRow context menu does NOT yet expose this — H.0 added
##     Mark / Hide-source for narration only)
##   - Soft-delete (per resolved O-J2 v1 ships hard-delete)


const PortraitWithBadgeScript := preload("res://scenes/ui/components/portrait_with_badge.gd")

const SUBSTATE_TAB_ID := "journal"

const SUBTAB_NARRATIVE := "narrative_log"
const SUBTAB_NOTES := "notes"
const SUBTAB_BOOKMARKS := "bookmarks"
const SUBTAB_DEFAULT := SUBTAB_NARRATIVE

const SUBTAB_FONT_SIZE := 12
# Notebook page is light parchment — dark text required (these were cream/light,
# invisible on the light page). Dark primary = VELLUM_TEXT_COLOR; muted secondary
# = VELLUM_SECONDARY_TEXT_COLOR. See docs/coding_conventions.md §6.10.
const ACTIVE_SUBTAB_COLOR := Color(0.09, 0.06, 0.03, 1.0)
const INACTIVE_SUBTAB_COLOR := Color(0.34, 0.27, 0.19, 1.0)

const HEADING_COLOR := Color(0.09, 0.06, 0.03, 1.0)
const BODY_COLOR := Color(0.09, 0.06, 0.03, 1.0)
const DIM_COLOR := Color(0.34, 0.27, 0.19, 1.0)
const PIN_COLOR := Color(1.0, 0.78, 0.30, 1.0)

const SIGNIFICANCE_LABELS := {
	"minor":     "Minor",
	"major":     "Major",
	"milestone": "Milestone",
}

const SIGNIFICANCE_COLORS := {
	"minor":     Color(0.55, 0.50, 0.42, 1.0),
	"major":     Color(0.85, 0.78, 0.45, 1.0),
	"milestone": Color(1.0, 0.78, 0.30, 1.0),
}


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _subtab_strip: HBoxContainer = null
var _subtab_buttons: Dictionary = {}  # subtab id -> Button
var _content_holder: Control = null

var _narrative_view: Control = null
var _notes_view: Control = null
var _bookmarks_view: Control = null
var _empty_state: Control = null

var _active_subtab: String = SUBTAB_DEFAULT
var _journal_repo: JournalRepository = null

## Notes sub-tab filter — when non-empty, only notes with this entity in
## their attached_entity_ids array render. Set via cross-tab activation
## (EventBus.notebook_journal_notes_filter_requested) or via the Notes
## sub-tab's own filter dropdown (item 3d).
var _notes_filter_entity_id: String = ""

## H.2 polish item 3d — per-sub-tab search query (case-insensitive
## substring match against title + body / label). Empty disables the
## filter. Persisted in per-tab substate so re-open restores.
var _narrative_search: String = ""
var _notes_search: String = ""
var _bookmarks_search: String = ""


# ---------------------------------------------------------------------------
# Lifecycle (overrides notebook_tab_page._build_content)
# ---------------------------------------------------------------------------

func _build_content() -> void:
	_journal_repo = JournalRepository.new(CampaignRepository)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)

	_subtab_strip = _build_subtab_strip()
	vbox.add_child(_subtab_strip)

	_content_holder = Control.new()
	_content_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_content_holder)

	_connect_signals()
	_restore_substate()
	_refresh()


func _connect_signals() -> void:
	# Cross-tab badge refresh: when journal contents change, the Henchmen tab
	# Roster (and any other badge consumer) listens and re-renders.
	EventBus.journal_changed.connect(_on_journal_changed)
	EventBus.active_party_changed.connect(_on_active_party_changed)
	# H.2 polish — cross-tab Notes filter application.
	EventBus.notebook_journal_notes_filter_requested.connect(
		_on_journal_notes_filter_requested)


# ---------------------------------------------------------------------------
# Sub-tab strip
# ---------------------------------------------------------------------------

func _build_subtab_strip() -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)

	_subtab_buttons.clear()
	for sub in [SUBTAB_NARRATIVE, SUBTAB_NOTES, SUBTAB_BOOKMARKS]:
		var btn := Button.new()
		btn.text = _subtab_label(sub)
		btn.flat = true
		btn.toggle_mode = true
		btn.add_theme_font_size_override("font_size", SUBTAB_FONT_SIZE)
		btn.pressed.connect(_on_subtab_pressed.bind(sub))
		hbox.add_child(btn)
		_subtab_buttons[sub] = btn
	return hbox


func _subtab_label(subtab: String) -> String:
	match subtab:
		SUBTAB_NARRATIVE:  return "Narrative Log"
		SUBTAB_NOTES:      return "Notes"
		SUBTAB_BOOKMARKS:  return "Bookmarks"
	return subtab


func _on_subtab_pressed(subtab: String) -> void:
	if subtab == _active_subtab:
		(_subtab_buttons[subtab] as Button).button_pressed = true
		return
	_active_subtab = subtab
	_persist_substate()
	_refresh_subtab_highlight()
	_swap_content()


func _refresh_subtab_highlight() -> void:
	for sub in _subtab_buttons.keys():
		var btn: Button = _subtab_buttons[sub]
		var active: bool = (sub == _active_subtab)
		btn.button_pressed = active
		btn.add_theme_color_override("font_color",
			ACTIVE_SUBTAB_COLOR if active else INACTIVE_SUBTAB_COLOR)


# ---------------------------------------------------------------------------
# Refresh
# ---------------------------------------------------------------------------

func _refresh() -> void:
	if _content_holder == null:
		return
	var pid: String = GameState.active_party_id
	if pid.is_empty():
		_show_empty_state()
		return
	_clear_empty_state()
	_refresh_subtab_highlight()
	_rebuild_views(pid)
	_swap_content()


func _rebuild_views(party_id: String) -> void:
	for view in [_narrative_view, _notes_view, _bookmarks_view]:
		if view != null and is_instance_valid(view):
			view.queue_free()
	_narrative_view = _build_narrative_view(party_id)
	_notes_view = _build_notes_view(party_id)
	_bookmarks_view = _build_bookmarks_view(party_id)


func _swap_content() -> void:
	if _content_holder == null:
		return
	for child in _content_holder.get_children():
		_content_holder.remove_child(child)
	var view: Control = null
	match _active_subtab:
		SUBTAB_NARRATIVE:  view = _narrative_view
		SUBTAB_NOTES:      view = _notes_view
		SUBTAB_BOOKMARKS:  view = _bookmarks_view
	if view == null:
		return
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content_holder.add_child(view)


func _show_empty_state() -> void:
	if _subtab_strip != null:
		_subtab_strip.visible = false
	if _empty_state != null and is_instance_valid(_empty_state):
		return
	for child in _content_holder.get_children():
		_content_holder.remove_child(child)
	_empty_state = _add_empty_state(
		"Journal Unavailable",
		"The Journal is per-party. Activate a party to begin keeping a " +
		"narrative record. Once active, write narrative log entries, attach " +
		"notes to characters and locations, and bookmark moments worth " +
		"revisiting.",
		[])
	if _empty_state != null:
		_empty_state.reparent(_content_holder)


func _clear_empty_state() -> void:
	if _subtab_strip != null:
		_subtab_strip.visible = true
	if _empty_state != null and is_instance_valid(_empty_state):
		_empty_state.queue_free()
		_empty_state = null


# ---------------------------------------------------------------------------
# Narrative Log sub-tab
# ---------------------------------------------------------------------------

func _build_narrative_view(party_id: String) -> Control:
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)

	# Controls row.
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	var new_btn := Button.new()
	new_btn.text = "+ New entry"
	new_btn.add_theme_font_size_override("font_size", 12)
	new_btn.pressed.connect(_open_narrative_modal)
	controls.add_child(new_btn)
	# H.2 polish item 3d — search field. Refresh on text_changed; the list
	# below filters by substring match against title + body.
	var search := _make_search_field("Search entries…", _narrative_search,
		func(text: String):
			_narrative_search = text
			_persist_substate()
			_refresh())
	controls.add_child(search)
	vbox.add_child(controls)

	# Entry list (filtered by search).
	var raw_entries: Array = _journal_repo.list_narrative_entries(party_id)
	var entries: Array = _filter_by_search(raw_entries, _narrative_search,
		["title", "body"])
	if entries.is_empty():
		var empty_body: String = (
			"No entries match \"%s\"." % _narrative_search
			if not _narrative_search.is_empty()
			else "The Journal is your party's story. Click [+ New entry] to write the first chapter.")
		vbox.add_child(_make_empty_message("No narrative entries", empty_body))
		return vbox

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	for entry in entries:
		list.add_child(_build_narrative_row(entry))
	return vbox


func _build_narrative_row(entry: Dictionary) -> Control:
	var entry_id: String = str(entry.get("id", ""))
	var title: String = str(entry.get("title", "(untitled)"))
	var body: String = str(entry.get("body", ""))
	var sig_key: String = str(entry.get("significance", "minor"))

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = Color(0.46, 0.33, 0.19, 0.45)
	style.border_width_left = 3
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	panel.add_child(v)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	var title_label := Label.new()
	title_label.text = title if not title.is_empty() else "(untitled)"
	title_label.add_theme_font_size_override("font_size", 14)
	title_label.add_theme_color_override("font_color", HEADING_COLOR)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)

	var sig_label := Label.new()
	sig_label.text = SIGNIFICANCE_LABELS.get(sig_key, sig_key.capitalize())
	sig_label.add_theme_font_size_override("font_size", 10)
	sig_label.add_theme_color_override("font_color",
		SIGNIFICANCE_COLORS.get(sig_key, BODY_COLOR))
	header.add_child(sig_label)

	# H.2 polish item 3b — inline edit reuses the create modal pre-populated.
	var edit_btn := Button.new()
	edit_btn.text = "Edit"
	edit_btn.flat = true
	edit_btn.add_theme_font_size_override("font_size", 10)
	edit_btn.add_theme_color_override("font_color", DIM_COLOR)
	edit_btn.pressed.connect(_open_narrative_modal.bind(entry))
	header.add_child(edit_btn)

	var bookmark_btn := Button.new()
	bookmark_btn.text = "Bookmark"
	bookmark_btn.flat = true
	bookmark_btn.add_theme_font_size_override("font_size", 10)
	bookmark_btn.add_theme_color_override("font_color", DIM_COLOR)
	bookmark_btn.pressed.connect(_on_bookmark_narrative.bind(entry_id, title))
	header.add_child(bookmark_btn)

	var delete_btn := Button.new()
	delete_btn.text = "Delete"
	delete_btn.flat = true
	delete_btn.add_theme_font_size_override("font_size", 10)
	delete_btn.add_theme_color_override("font_color", DIM_COLOR)
	delete_btn.pressed.connect(_on_delete_narrative.bind(entry_id))
	header.add_child(delete_btn)
	v.add_child(header)

	if not body.is_empty():
		var body_label := RichTextLabel.new()
		# H.2 polish item 3a — render markdown-lite via the converter; the
		# RichTextLabel renders BBCode (bold / italic / lists / entity-link
		# color tokens). Accept malformed markdown by rendering verbatim.
		body_label.bbcode_enabled = true
		body_label.fit_content = true
		body_label.scroll_active = false
		body_label.text = MarkdownLite.to_bbcode(body)
		body_label.add_theme_font_size_override("normal_font_size", 12)
		body_label.add_theme_color_override("default_color", BODY_COLOR)
		v.add_child(body_label)

	return panel


func _open_narrative_modal(initial: Dictionary = {}) -> void:
	# Inline-edit reuses the create modal pre-populated; when initial is
	# non-empty, save updates the existing entry instead of inserting (item 3b).
	var entry_id: String = str(initial.get("id", ""))
	var heading: String = "Edit Narrative Entry" if not entry_id.is_empty() else "New Narrative Entry"
	_open_text_entry_modal(
		heading,
		"Title (optional):",
		"Body:",
		func(title: String, body: String):
			var pid: String = GameState.active_party_id
			if pid.is_empty():
				return
			if not entry_id.is_empty():
				_journal_repo.update_narrative_entry(entry_id, {
					"title": title,
					"body":  body,
				})
				EventBus.journal_changed.emit("narrative_entry_updated", pid)
			else:
				_journal_repo.create_narrative_entry(pid, {
					"title": title,
					"body":  body,
					"significance": "minor",
					"timestamp_ingame": _current_game_time(),
				})
				EventBus.journal_changed.emit("narrative_entry_added", pid),
		str(initial.get("title", "")),
		str(initial.get("body", "")))


func _on_delete_narrative(entry_id: String) -> void:
	_journal_repo.delete_narrative_entry(entry_id)
	EventBus.journal_changed.emit("narrative_entry_removed", GameState.active_party_id)


func _on_bookmark_narrative(entry_id: String, title: String) -> void:
	var pid: String = GameState.active_party_id
	if pid.is_empty():
		return
	_journal_repo.create_bookmark(pid, "narrative_entry", entry_id, title)
	EventBus.journal_changed.emit("bookmark_added", pid)
	EventBus.notification_requested.emit({
		"type":  "info",
		"title": "Bookmarked",
		"body":  "\"%s\" added to Journal Bookmarks." % title,
	})


# ---------------------------------------------------------------------------
# Notes sub-tab
# ---------------------------------------------------------------------------

func _build_notes_view(party_id: String) -> Control:
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	var new_btn := Button.new()
	new_btn.text = "+ New note"
	new_btn.add_theme_font_size_override("font_size", 12)
	new_btn.pressed.connect(_open_note_modal)
	controls.add_child(new_btn)

	# H.2 polish — entity-filter chip. When the Notes sub-tab was opened from
	# a Notes badge (e.g., Henchmen Roster row), the filter scopes the list
	# to notes attached to that entity only. Clear via the chip's × button.
	if not _notes_filter_entity_id.is_empty():
		var chip := PanelContainer.new()
		var chip_style := StyleBoxFlat.new()
		chip_style.bg_color = Color(0.18, 0.14, 0.10, 0.65)
		chip_style.border_color = Color(0.78, 0.65, 0.30, 1.0)
		chip_style.border_width_left = 1
		chip_style.border_width_right = 1
		chip_style.border_width_top = 1
		chip_style.border_width_bottom = 1
		chip_style.corner_radius_top_left = 3
		chip_style.corner_radius_top_right = 3
		chip_style.corner_radius_bottom_left = 3
		chip_style.corner_radius_bottom_right = 3
		chip_style.content_margin_left = 8
		chip_style.content_margin_right = 4
		chip_style.content_margin_top = 2
		chip_style.content_margin_bottom = 2
		chip.add_theme_stylebox_override("panel", chip_style)
		var chip_hbox := HBoxContainer.new()
		chip_hbox.add_theme_constant_override("separation", 4)
		chip.add_child(chip_hbox)
		var chip_label := Label.new()
		chip_label.text = "Filtered: %s" % _resolve_entity_display_name(_notes_filter_entity_id)
		chip_label.add_theme_font_size_override("font_size", 11)
		chip_label.add_theme_color_override("font_color", HEADING_COLOR)
		chip_hbox.add_child(chip_label)
		var clear_btn := Button.new()
		clear_btn.text = "×"
		clear_btn.flat = true
		clear_btn.add_theme_font_size_override("font_size", 14)
		clear_btn.add_theme_color_override("font_color", DIM_COLOR)
		clear_btn.tooltip_text = "Clear filter"
		clear_btn.pressed.connect(_on_clear_notes_filter)
		chip_hbox.add_child(clear_btn)
		controls.add_child(chip)

	vbox.add_child(controls)

	# H.2 polish item 3d — search field for notes.
	var notes_search := _make_search_field("Search notes…", _notes_search,
		func(text: String):
			_notes_search = text
			_persist_substate()
			_refresh())
	controls.add_child(notes_search)

	var raw_notes: Array = (
		_journal_repo.list_notes_for_entity(party_id, _notes_filter_entity_id)
		if not _notes_filter_entity_id.is_empty()
		else _journal_repo.list_notes(party_id))
	var notes: Array = _filter_by_search(raw_notes, _notes_search,
		["title", "body"])
	if notes.is_empty():
		var empty_body: String = ""
		if not _notes_search.is_empty():
			empty_body = "No notes match \"%s\"." % _notes_search
		elif not _notes_filter_entity_id.is_empty():
			empty_body = "No notes attached to this entity yet."
		else:
			empty_body = "Notes are your record of people, places, and theories. Click [+ New note] to write one."
		vbox.add_child(_make_empty_message("No notes", empty_body))
		return vbox

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	for note in notes:
		list.add_child(_build_note_row(note))
	return vbox


func _build_note_row(note: Dictionary) -> Control:
	var note_id: String = str(note.get("id", ""))
	var title: String = str(note.get("title", ""))
	var body: String = str(note.get("body", ""))
	var pinned: bool = int(note.get("pinned", 0)) == 1
	var attached_ids: Array = _parse_json_array(str(note.get("attached_entity_ids", "[]")))

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = (PIN_COLOR if pinned else Color(0.46, 0.33, 0.19, 0.45))
	style.border_width_left = 3
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	panel.add_child(v)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	var title_label := Label.new()
	if pinned:
		title_label.text = "★ %s" % (title if not title.is_empty() else "(untitled)")
	else:
		title_label.text = title if not title.is_empty() else "(untitled)"
	title_label.add_theme_font_size_override("font_size", 13)
	title_label.add_theme_color_override("font_color", HEADING_COLOR)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)

	# H.2 polish item 3b — inline edit reuses the create modal pre-populated.
	var edit_btn := Button.new()
	edit_btn.text = "Edit"
	edit_btn.flat = true
	edit_btn.add_theme_font_size_override("font_size", 10)
	edit_btn.add_theme_color_override("font_color", DIM_COLOR)
	edit_btn.pressed.connect(_open_note_modal.bind(note))
	header.add_child(edit_btn)

	var pin_btn := Button.new()
	pin_btn.text = "Unpin" if pinned else "Pin"
	pin_btn.flat = true
	pin_btn.add_theme_font_size_override("font_size", 10)
	pin_btn.add_theme_color_override("font_color", DIM_COLOR)
	pin_btn.pressed.connect(_on_toggle_pin.bind(note_id, not pinned))
	header.add_child(pin_btn)

	var bookmark_btn := Button.new()
	bookmark_btn.text = "Bookmark"
	bookmark_btn.flat = true
	bookmark_btn.add_theme_font_size_override("font_size", 10)
	bookmark_btn.add_theme_color_override("font_color", DIM_COLOR)
	bookmark_btn.pressed.connect(_on_bookmark_note.bind(note_id, title))
	header.add_child(bookmark_btn)

	var delete_btn := Button.new()
	delete_btn.text = "Delete"
	delete_btn.flat = true
	delete_btn.add_theme_font_size_override("font_size", 10)
	delete_btn.add_theme_color_override("font_color", DIM_COLOR)
	delete_btn.pressed.connect(_on_delete_note.bind(note_id))
	header.add_child(delete_btn)
	v.add_child(header)

	if not attached_ids.is_empty():
		var attach_label := Label.new()
		attach_label.text = "Attached: %d entit%s" % [
			attached_ids.size(), ("y" if attached_ids.size() == 1 else "ies"),
		]
		attach_label.add_theme_font_size_override("font_size", 10)
		attach_label.add_theme_color_override("font_color", DIM_COLOR)
		v.add_child(attach_label)

	if not body.is_empty():
		var body_label := RichTextLabel.new()
		body_label.bbcode_enabled = true
		body_label.fit_content = true
		body_label.scroll_active = false
		body_label.text = MarkdownLite.to_bbcode(body)
		body_label.add_theme_font_size_override("normal_font_size", 12)
		body_label.add_theme_color_override("default_color", BODY_COLOR)
		v.add_child(body_label)

	return panel


func _open_note_modal(initial: Dictionary = {}) -> void:
	var note_id: String = str(initial.get("id", ""))
	var heading: String = "Edit Note" if not note_id.is_empty() else "New Note"
	_open_text_entry_modal(
		heading,
		"Title (optional):",
		"Body:",
		func(title: String, body: String):
			var pid: String = GameState.active_party_id
			if pid.is_empty():
				return
			if not note_id.is_empty():
				_journal_repo.update_note(note_id, {
					"title": title,
					"body":  body,
				})
				EventBus.journal_changed.emit("note_updated", pid)
			else:
				_journal_repo.create_note(pid, {
					"title": title,
					"body":  body,
					"timestamp_ingame": _current_game_time(),
				})
				EventBus.journal_changed.emit("note_added", pid),
		str(initial.get("title", "")),
		str(initial.get("body", "")))


func _on_delete_note(note_id: String) -> void:
	_journal_repo.delete_note(note_id)
	EventBus.journal_changed.emit("note_removed", GameState.active_party_id)


func _on_toggle_pin(note_id: String, pinned: bool) -> void:
	_journal_repo.update_note(note_id, {"pinned": (1 if pinned else 0)})
	EventBus.journal_changed.emit("note_updated", GameState.active_party_id)


func _on_bookmark_note(note_id: String, title: String) -> void:
	var pid: String = GameState.active_party_id
	if pid.is_empty():
		return
	var label: String = title if not title.is_empty() else "Note"
	_journal_repo.create_bookmark(pid, "note", note_id, label)
	EventBus.journal_changed.emit("bookmark_added", pid)
	EventBus.notification_requested.emit({
		"type":  "info",
		"title": "Bookmarked",
		"body":  "Note \"%s\" added to Journal Bookmarks." % label,
	})


# ---------------------------------------------------------------------------
# Bookmarks sub-tab
# ---------------------------------------------------------------------------

func _build_bookmarks_view(party_id: String) -> Control:
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)

	# H.2 polish item 3d — search field for bookmarks.
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	var bookmarks_search := _make_search_field("Search bookmarks…",
		_bookmarks_search,
		func(text: String):
			_bookmarks_search = text
			_persist_substate()
			_refresh())
	controls.add_child(bookmarks_search)
	vbox.add_child(controls)

	var raw_bookmarks: Array = _journal_repo.list_bookmarks(party_id)
	var bookmarks: Array = _filter_by_search(raw_bookmarks, _bookmarks_search,
		["label", "category"])
	if bookmarks.is_empty():
		var empty_body: String = (
			"No bookmarks match \"%s\"." % _bookmarks_search
			if not _bookmarks_search.is_empty()
			else "Click \"Bookmark\" on any narrative entry or note to pin it here for quick recall.")
		vbox.add_child(_make_empty_message("No bookmarks", empty_body))
		return vbox

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	for bookmark in bookmarks:
		list.add_child(_build_bookmark_row(bookmark))
	return vbox


func _build_bookmark_row(bookmark: Dictionary) -> Control:
	var bookmark_id: String = str(bookmark.get("id", ""))
	var label: String = str(bookmark.get("label", "(unlabeled)"))
	var target_kind: String = str(bookmark.get("target_kind", ""))
	var target_id: String = str(bookmark.get("target_id", ""))
	var category: String = str(bookmark.get("category", ""))

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = Color(0.46, 0.33, 0.19, 0.45)
	style.border_width_left = 3
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	panel.add_child(v)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	var label_label := Label.new()
	label_label.text = label
	label_label.add_theme_font_size_override("font_size", 13)
	label_label.add_theme_color_override("font_color", HEADING_COLOR)
	label_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(label_label)

	var open_btn := Button.new()
	open_btn.text = "Open source"
	open_btn.flat = true
	open_btn.add_theme_font_size_override("font_size", 10)
	open_btn.add_theme_color_override("font_color", DIM_COLOR)
	open_btn.pressed.connect(_on_open_bookmark_source.bind(target_kind, target_id))
	header.add_child(open_btn)

	var delete_btn := Button.new()
	delete_btn.text = "Remove"
	delete_btn.flat = true
	delete_btn.add_theme_font_size_override("font_size", 10)
	delete_btn.add_theme_color_override("font_color", DIM_COLOR)
	delete_btn.pressed.connect(_on_delete_bookmark.bind(bookmark_id))
	header.add_child(delete_btn)
	v.add_child(header)

	var source_text: String = "Source: %s" % _bookmark_source_label(target_kind)
	if not category.is_empty():
		source_text = "%s · Category: %s" % [source_text, category]
	var source_label := Label.new()
	source_label.text = source_text
	source_label.add_theme_font_size_override("font_size", 10)
	source_label.add_theme_color_override("font_color", DIM_COLOR)
	v.add_child(source_label)

	return panel


func _emit_log_scroll(target_id: String) -> void:
	# H.2 polish item 1e helper — UnifiedLog accepts the entry id as int.
	if target_id.is_valid_int():
		EventBus.unified_log_scroll_to_id_requested.emit(target_id.to_int())


func _bookmark_source_label(target_kind: String) -> String:
	match target_kind:
		"narrative_entry":     return "Narrative entry"
		"note":                return "Note"
		"unified_log_entry":   return "Unified Log entry"
	return target_kind


func _on_delete_bookmark(bookmark_id: String) -> void:
	_journal_repo.delete_bookmark(bookmark_id)
	EventBus.journal_changed.emit("bookmark_removed", GameState.active_party_id)


func _on_open_bookmark_source(target_kind: String, target_id: String) -> void:
	# v1 routes narrative_entry and note bookmarks to their respective sub-tab.
	# Unified Log entry routing requires Unified Log scroll-to-id support
	# (gdd-unified-log-panel.md §3.3.2; not yet wired) — surface a notification
	# until that lands.
	match target_kind:
		"narrative_entry":
			_active_subtab = SUBTAB_NARRATIVE
			_persist_substate()
			_refresh_subtab_highlight()
			_swap_content()
		"note":
			_active_subtab = SUBTAB_NOTES
			_persist_substate()
			_refresh_subtab_highlight()
			_swap_content()
		"unified_log_entry":
			# H.2 polish item 1e — close the notebook so the world view +
			# UnifiedLog become visible, then ask the log to scroll. The
			# notebook close emits notebook_open_state_changed(false) which
			# unhides the SessionStatusBar (where UnifiedLog lives).
			EventBus.notebook_close_requested.emit()
			# Defer the scroll one frame so the close completes first.
			call_deferred("_emit_log_scroll", target_id)
		_:
			push_warning("Journal: unknown bookmark target_kind '%s'" % target_kind)


# ---------------------------------------------------------------------------
# Modal helpers
# ---------------------------------------------------------------------------

func _open_text_entry_modal(heading: String, title_label: String,
		body_label: String, on_save: Callable,
		initial_title: String = "", initial_body: String = "") -> void:
	# Lightweight inline modal — H.2 polish item 3a/c will add markdown-lite
	# rendering and @-autocomplete; this helper is the shared shell. Vellum
	# chrome via UiSurfaceStyles (item 1b) so the modal matches the
	# notebook's framed-window aesthetic.
	var modal := PopupPanel.new()
	modal.exclusive = true
	modal.size = Vector2i(560, 400)
	add_child(modal)
	UiSurfaceStyles.apply_framed_window_chrome(modal)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	modal.add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	margin.add_child(v)

	var heading_lbl := Label.new()
	heading_lbl.text = heading
	heading_lbl.add_theme_font_size_override("font_size", 16)
	heading_lbl.add_theme_color_override("font_color", HEADING_COLOR)
	v.add_child(heading_lbl)

	var title_lbl := Label.new()
	title_lbl.text = title_label
	title_lbl.add_theme_font_size_override("font_size", 11)
	title_lbl.add_theme_color_override("font_color", DIM_COLOR)
	v.add_child(title_lbl)

	var title_edit := LineEdit.new()
	title_edit.text = initial_title
	v.add_child(title_edit)

	var body_lbl := Label.new()
	body_lbl.text = body_label
	body_lbl.add_theme_font_size_override("font_size", 11)
	body_lbl.add_theme_color_override("font_color", DIM_COLOR)
	v.add_child(body_lbl)

	var body_edit := TextEdit.new()
	body_edit.text = initial_body
	body_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_edit.custom_minimum_size = Vector2(0, 180)
	v.add_child(body_edit)
	# H.2 polish item 3c — wire @-autocomplete on the body editor.
	_wire_entity_autocomplete(body_edit, modal)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(modal.queue_free)
	btn_row.add_child(cancel_btn)
	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.pressed.connect(func():
		on_save.call(title_edit.text, body_edit.text)
		modal.queue_free())
	btn_row.add_child(save_btn)
	v.add_child(btn_row)

	modal.popup_centered()


# H.2 polish item 3d — shared search field builder. on_change is called with
# the new text on every text_changed; callers refresh the affected sub-tab.
func _make_search_field(placeholder: String, initial: String,
		on_change: Callable) -> LineEdit:
	var field := LineEdit.new()
	field.placeholder_text = placeholder
	field.text = initial
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.custom_minimum_size = Vector2(160, 0)
	field.text_changed.connect(on_change)
	return field


# Case-insensitive substring filter over the named string fields. Returns
# the original list when the query is empty.
func _filter_by_search(rows: Array, query: String, fields: Array) -> Array:
	if query.strip_edges().is_empty():
		return rows
	var needle: String = query.strip_edges().to_lower()
	var out: Array = []
	for row in rows:
		for field in fields:
			var value: String = str(row.get(field, "")).to_lower()
			if needle in value:
				out.append(row)
				break
	return out


# H.2 polish item 3c — @-trigger entity autocomplete on the body editor.
# When the user types '@', a popup of party PCs + henchmen surfaces; click
# to insert `@<entity_id>` at the caret. Per resolved O-J4 v1 covers PCs
# and henchmen (the catalogs that exist today); NPCs / locations land when
# their generation systems do.
func _wire_entity_autocomplete(body_edit: TextEdit, modal_root: Window) -> void:
	body_edit.text_changed.connect(func():
		_maybe_show_entity_popup(body_edit, modal_root))


func _maybe_show_entity_popup(body_edit: TextEdit, modal_root: Window) -> void:
	var text: String = body_edit.text
	var caret_line: int = body_edit.get_caret_line()
	var caret_col: int = body_edit.get_caret_column()
	var abs_pos: int = _absolute_caret_offset(text, caret_line, caret_col)
	if abs_pos <= 0:
		return
	if text[abs_pos - 1] != "@":
		return
	# Don't fire on the trailing @ of a longer email-like token (preceded
	# by a word char) — the user wants `foo@bar` to render as plain text.
	if abs_pos >= 2:
		var prev: String = text[abs_pos - 2]
		if MarkdownLite._is_id_char(prev):
			return
	_show_entity_picker_popup(body_edit, modal_root)


func _absolute_caret_offset(text: String, line: int, col: int) -> int:
	var lines := text.split("\n")
	var off: int = 0
	for i in range(min(line, lines.size())):
		off += String(lines[i]).length() + 1  # +1 for the newline
	off += col
	return off


func _show_entity_picker_popup(body_edit: TextEdit, modal_root: Window) -> void:
	var pid: String = GameState.active_party_id
	if pid.is_empty():
		return
	var entries: Array = _gather_party_entities(pid)
	if entries.is_empty():
		return
	var menu := PopupMenu.new()
	for i in range(entries.size()):
		var entry: Dictionary = entries[i]
		menu.add_item("%s — %s" % [entry["kind_label"], entry["name"]], i)
	menu.id_pressed.connect(func(idx: int):
		var picked: Dictionary = entries[idx]
		_insert_entity_link_at_caret(body_edit, str(picked["id"])))
	menu.popup_hide.connect(menu.queue_free)
	modal_root.add_child(menu)
	# Position roughly at the caret; PopupMenu doesn't have a native caret-
	# anchor API, so we settle for "centered under the modal."
	menu.popup_centered()


func _gather_party_entities(party_id: String) -> Array:
	var rows: Array = CampaignRepository.list_party_characters(party_id)
	var out: Array = []
	for row in rows:
		var ctype: String = str(row.get("character_type", ""))
		var kind_label: String = "PC" if ctype == "pc" else "Henchman"
		out.append({
			"id": str(row.get("id", "")),
			"name": str(row.get("name", "(unnamed)")),
			"kind_label": kind_label,
		})
	return out


func _insert_entity_link_at_caret(body_edit: TextEdit, entity_id: String) -> void:
	# The '@' is already in the text at caret-1. Insert the id immediately
	# after so the final token is `@<entity_id>`.
	body_edit.insert_text_at_caret(entity_id)


func _make_empty_message(heading: String, body: String) -> Control:
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	center.add_child(v)
	var heading_lbl := Label.new()
	heading_lbl.text = heading
	heading_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading_lbl.add_theme_font_size_override("font_size", 16)
	heading_lbl.add_theme_color_override("font_color", HEADING_COLOR)
	v.add_child(heading_lbl)
	var body_lbl := Label.new()
	body_lbl.text = body
	body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_lbl.custom_minimum_size = Vector2(420, 0)
	body_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body_lbl.add_theme_font_size_override("font_size", 12)
	body_lbl.add_theme_color_override("font_color", DIM_COLOR)
	v.add_child(body_lbl)
	return center


# ---------------------------------------------------------------------------
# Per-tab substate persistence
# ---------------------------------------------------------------------------

func _restore_substate() -> void:
	var pid: String = GameState.active_party_id
	if pid.is_empty():
		return
	var sub: Dictionary = NotebookState.get_substate_for_tab(pid, SUBSTATE_TAB_ID)
	var stored: String = str(sub.get("active_subtab", SUBTAB_DEFAULT))
	if stored in [SUBTAB_NARRATIVE, SUBTAB_NOTES, SUBTAB_BOOKMARKS]:
		_active_subtab = stored
	# H.2 polish item 3d — restore search strings.
	_narrative_search = str(sub.get("narrative_search", ""))
	_notes_search = str(sub.get("notes_search", ""))
	_bookmarks_search = str(sub.get("bookmarks_search", ""))


func _persist_substate() -> void:
	var pid: String = GameState.active_party_id
	if pid.is_empty():
		return
	NotebookState.set_substate_for_tab(pid, SUBSTATE_TAB_ID, {
		"active_subtab":     _active_subtab,
		"narrative_search":  _narrative_search,
		"notes_search":      _notes_search,
		"bookmarks_search":  _bookmarks_search,
	})


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_journal_changed(_kind: String, _party_id: String) -> void:
	_refresh()


func _on_active_party_changed(_previous: String, _new: String) -> void:
	_restore_substate()
	# Clear cross-tab filter on party switch — filters are entity-specific
	# and the entity may not exist in the new party.
	_notes_filter_entity_id = ""
	_refresh()


func _on_journal_notes_filter_requested(entity_id: String) -> void:
	# Cross-tab Notes-badge click. Switch to the Notes sub-tab and apply the
	# entity filter; refresh rebuilds the Notes view with the chip + filtered
	# list. The Notebook root has already routed `notebook_open_requested`
	# to make this tab visible.
	_notes_filter_entity_id = entity_id
	_active_subtab = SUBTAB_NOTES
	_persist_substate()
	_refresh()


func _on_clear_notes_filter() -> void:
	_notes_filter_entity_id = ""
	_refresh()


# Resolve a display name for the cross-tab filter chip. Falls back to the id
# when the entity isn't a known character (e.g., NPC / location id whose
# rendering hooks land later).
func _resolve_entity_display_name(entity_id: String) -> String:
	if entity_id.is_empty():
		return ""
	if not CampaignRepository.db.query_with_bindings(
			"SELECT name FROM characters WHERE id = ?", [entity_id]):
		return entity_id
	if CampaignRepository.db.query_result.is_empty():
		return entity_id
	var name: String = str(CampaignRepository.db.query_result[0].get("name", ""))
	return name if not name.is_empty() else entity_id


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _current_game_time() -> int:
	# Timekeeping is an autoload that may not be active in tests; defer
	# defensively to avoid hard-failing test instantiation.
	var main_loop := Engine.get_main_loop()
	if main_loop == null or not (main_loop is SceneTree):
		return 0
	var root := (main_loop as SceneTree).root
	if root == null:
		return 0
	var tk := root.get_node_or_null("Timekeeping")
	if tk == null:
		return 0
	if "_elapsed_rounds" in tk:
		return int(tk._elapsed_rounds)
	return 0


func _parse_json_array(text: String) -> Array:
	if text.is_empty():
		return []
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Array:
		return parsed
	return []
