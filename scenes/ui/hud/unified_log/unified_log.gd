extends Control

## UnifiedLog — embedded log surface in the SessionStatusBar's right zone
## (γ.5). Per gdd-unified-log-panel.md v2 the log replaces the deleted
## GameLogPanel / CombatLogPanel / RollLogOverlay surfaces.
##
## Tabs (gdd-unified-log-panel.md §4):
##   All        — every entry
##   Combat     — category == "combat"
##   Rolls      — category == "dice"
##   Narration  — category == "narration"
##
## Live updates: subscribes to EventBus.log_entry_added (α.1).
## History fill: GameLog.get_entries(category, limit) on construction and
## on EventBus.active_party_changed.
##
## L-key cycle: subscribes to EventBus.unified_log_cycle_requested (α.2).
##
## Click-to-link: rows emit `entity_link_requested(id)` which is forwarded
## to EventBus.notebook_active_entity_requested.
##
## Export: markdown / JSON / TXT submenu, defaulting to markdown clipboard.


const LogEntryRowScript := preload("res://scenes/ui/hud/unified_log/log_entry_row.gd")


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const TAB_ALL := "all"
const TAB_COMBAT := "combat"
const TAB_ROLLS := "rolls"
const TAB_NARRATION := "narration"

const TAB_ORDER := [TAB_ALL, TAB_COMBAT, TAB_ROLLS, TAB_NARRATION]

const TAB_LABELS := {
	TAB_ALL:       "All",
	TAB_COMBAT:    "Combat",
	TAB_ROLLS:     "Rolls",
	TAB_NARRATION: "Narration",
}

## Map of tab id → category id used by GameLog.get_entries. TAB_ALL maps to
## "all" (which the autoload treats as no filter).
const TAB_CATEGORY := {
	TAB_ALL:       "all",
	TAB_COMBAT:    "combat",
	TAB_ROLLS:     "dice",
	TAB_NARRATION: "narration",
}

## Display cap for the entries scroll. Older entries remain in GameLog and
## can be exported; only the most-recent N render to keep the bar responsive.
const VISIBLE_ENTRY_LIMIT := 100

const TAB_FONT_SIZE := 11
const ACTIVE_TAB_COLOR := Color(0.92, 0.86, 0.74, 1.0)
const INACTIVE_TAB_COLOR := Color(0.55, 0.50, 0.42, 1.0)


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _active_tab: String = TAB_ALL
var _tab_buttons: Dictionary = {}  # tab_id -> Button
var _entries_vbox: VBoxContainer = null
var _scroll: ScrollContainer = null


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_ui()
	_connect_signals()
	_refresh_entries()


# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 2)
	add_child(vbox)

	# Tab strip + export button.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	vbox.add_child(header)

	for tab_id in TAB_ORDER:
		var btn := Button.new()
		btn.text = TAB_LABELS[tab_id]
		btn.toggle_mode = true
		btn.flat = true
		btn.add_theme_font_size_override("font_size", TAB_FONT_SIZE)
		btn.add_theme_color_override("font_color", INACTIVE_TAB_COLOR)
		btn.pressed.connect(_on_tab_pressed.bind(tab_id))
		header.add_child(btn)
		_tab_buttons[tab_id] = btn

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	var export_btn := MenuButton.new()
	export_btn.text = "Export"
	export_btn.add_theme_font_size_override("font_size", TAB_FONT_SIZE)
	var popup := export_btn.get_popup()
	popup.add_item("Markdown → Clipboard", 0)
	popup.add_item("Plain Text → Clipboard", 1)
	popup.add_item("JSON → Clipboard", 2)
	popup.add_separator()
	popup.add_item("Save to File…", 3)
	popup.id_pressed.connect(_on_export_pressed)
	header.add_child(export_btn)

	# Scrollable entries.
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_scroll)

	_entries_vbox = VBoxContainer.new()
	_entries_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entries_vbox.add_theme_constant_override("separation", 2)
	_scroll.add_child(_entries_vbox)

	_apply_tab_highlight()


func _connect_signals() -> void:
	EventBus.log_entry_added.connect(_on_log_entry_added)
	EventBus.unified_log_cycle_requested.connect(_on_cycle_requested)
	EventBus.active_party_changed.connect(_on_active_party_changed)
	GameState.session_ended.connect(_on_session_ended)
	# H.2 polish item 1e — bookmarks "Open source" → scroll to that entry.
	EventBus.unified_log_scroll_to_id_requested.connect(_on_scroll_to_id_requested)


# ---------------------------------------------------------------------------
# Tab strip
# ---------------------------------------------------------------------------

func _on_tab_pressed(tab_id: String) -> void:
	if tab_id == _active_tab:
		(_tab_buttons[tab_id] as Button).button_pressed = true
		return
	_active_tab = tab_id
	_apply_tab_highlight()
	_refresh_entries()


func _on_cycle_requested() -> void:
	var idx: int = TAB_ORDER.find(_active_tab)
	if idx < 0:
		idx = 0
	var next_idx: int = (idx + 1) % TAB_ORDER.size()
	_active_tab = TAB_ORDER[next_idx]
	_apply_tab_highlight()
	_refresh_entries()


func _apply_tab_highlight() -> void:
	for tab_id in _tab_buttons.keys():
		var btn: Button = _tab_buttons[tab_id]
		var is_active: bool = (tab_id == _active_tab)
		btn.button_pressed = is_active
		btn.add_theme_color_override("font_color",
			ACTIVE_TAB_COLOR if is_active else INACTIVE_TAB_COLOR)


## Public API for tests: returns the currently active tab id.
func active_tab() -> String:
	return _active_tab


# ---------------------------------------------------------------------------
# Entry rendering
# ---------------------------------------------------------------------------

func _refresh_entries() -> void:
	if _entries_vbox == null:
		return
	for child in _entries_vbox.get_children():
		_entries_vbox.remove_child(child)
		child.queue_free()
	var category: String = TAB_CATEGORY.get(_active_tab, "all")
	var entries: Array = GameLog.get_entries(category, VISIBLE_ENTRY_LIMIT)
	for entry in entries:
		_append_row(entry)
	_scroll_to_bottom()


func _append_row(entry: Dictionary) -> void:
	var row = LogEntryRowScript.new()
	row.setup(entry)
	row.entity_link_requested.connect(_on_entity_link)
	# H.0 — narration right-click signals. Mark routes to a notification stub
	# until Journal bookmarks land (H.2). Hide-this-source also stubs until
	# the per-source filter system lands.
	row.narration_mark_requested.connect(_on_narration_mark)
	row.narration_hide_source_requested.connect(_on_narration_hide_source)
	# H.2 polish item 1f — Journal context menu items.
	row.bookmark_in_journal_requested.connect(_on_bookmark_in_journal)
	row.note_about_entry_requested.connect(_on_note_about_entry)
	_entries_vbox.add_child(row)


func _scroll_to_bottom() -> void:
	if _scroll == null:
		return
	# Defer one frame so the new rows have laid out before we scroll.
	call_deferred("_do_scroll_to_bottom")


func _do_scroll_to_bottom() -> void:
	if _scroll == null or not is_instance_valid(_scroll):
		return
	var bar := _scroll.get_v_scroll_bar()
	if bar != null:
		_scroll.scroll_vertical = int(bar.max_value)


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_log_entry_added(entry: Dictionary) -> void:
	var category: String = str(entry.get("category", ""))
	var active_category: String = TAB_CATEGORY.get(_active_tab, "all")
	if active_category != "all" and category != active_category:
		return
	# Trim old rows when at the visible cap.
	while _entries_vbox.get_child_count() >= VISIBLE_ENTRY_LIMIT:
		var oldest: Node = _entries_vbox.get_child(0)
		_entries_vbox.remove_child(oldest)
		oldest.queue_free()
	_append_row(entry)
	_scroll_to_bottom()


func _on_entity_link(entity_id: String) -> void:
	if entity_id.is_empty():
		return
	EventBus.notebook_active_entity_requested.emit(entity_id)


func _on_active_party_changed(_prev: String, _new: String) -> void:
	_refresh_entries()


func _on_session_ended() -> void:
	if _entries_vbox == null:
		return
	for child in _entries_vbox.get_children():
		_entries_vbox.remove_child(child)
		child.queue_free()


func _on_scroll_to_id_requested(entry_id: int) -> void:
	# H.2 polish item 1e — Journal Bookmarks → "Open source" for a
	# unified_log_entry target jumps the active log view to that entry. If
	# the active tab filters out the entry's category, switch to All first.
	if _entries_vbox == null or _scroll == null:
		return
	# Resolve the entry from GameLog so we can switch tabs to one that will
	# render it.
	var all_entries: Array = GameLog.get_entries("all", 0)
	var target: Dictionary = {}
	for entry in all_entries:
		if int(entry.get("id", -1)) == entry_id:
			target = entry
			break
	if target.is_empty():
		EventBus.notification_requested.emit({
			"type":  "warning",
			"title": "Open Source",
			"body":  "Log entry %d no longer exists." % entry_id,
		})
		return
	# If the current tab can't render this entry's category, switch to All.
	var entry_category: String = str(target.get("category", ""))
	var active_category: String = TAB_CATEGORY.get(_active_tab, "all")
	if active_category != "all" and entry_category != active_category:
		_active_tab = TAB_ALL
		_apply_tab_highlight()
		_refresh_entries()
	# Find the row whose entry id matches and scroll to it.
	call_deferred("_scroll_to_entry_id", entry_id)


func _scroll_to_entry_id(entry_id: int) -> void:
	if _entries_vbox == null or _scroll == null:
		return
	for row in _entries_vbox.get_children():
		if not (row is PanelContainer):
			continue
		var row_entry: Dictionary = row.get_meta("entry", {}) if row.has_meta("entry") else {}
		if int(row_entry.get("id", -1)) == entry_id:
			_scroll.ensure_control_visible(row)
			# Brief modulate flash so the player's eye catches it.
			row.modulate = Color(1.4, 1.3, 1.0)
			var tween := create_tween()
			tween.tween_property(row, "modulate", Color.WHITE, 0.6)
			return


# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------

func _on_export_pressed(item_id: int) -> void:
	var category: String = TAB_CATEGORY.get(_active_tab, "all")
	var entries: Array = GameLog.get_entries(category, 0)  # 0 = no cap
	if item_id == 3:
		# Save-to-file (H.0). Opens a save dialog; format inferred from file
		# extension (.md / .json default to JSON; anything else writes plain
		# text). Default name embeds the active tab + day-time stamp.
		_open_save_dialog(entries)
		return
	var payload: String = ""
	match item_id:
		0:
			payload = _format_markdown(entries)
		1:
			payload = _format_text(entries)
		2:
			payload = JSON.stringify(entries, "\t")
	if payload.is_empty():
		return
	DisplayServer.clipboard_set(payload)
	EventBus.notification_requested.emit({
		"type":  "info",
		"title": "Log Exported",
		"body":  "%d %s entries copied to clipboard." % [entries.size(), _active_tab],
	})


func _open_save_dialog(entries: Array) -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.access = FileDialog.ACCESS_USERDATA
	dialog.add_filter("*.md ; Markdown")
	dialog.add_filter("*.txt ; Plain text")
	dialog.add_filter("*.json ; JSON")
	dialog.current_file = "game-log-%s.md" % _active_tab
	dialog.size = Vector2i(640, 420)
	dialog.file_selected.connect(_on_save_file_selected.bind(entries))
	dialog.close_requested.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()


func _on_save_file_selected(path: String, entries: Array) -> void:
	var ext: String = path.get_extension().to_lower()
	var payload: String = ""
	match ext:
		"json":
			payload = JSON.stringify(entries, "\t")
		"txt":
			payload = _format_text(entries)
		_:
			payload = _format_markdown(entries)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		EventBus.notification_requested.emit({
			"type":  "warning",
			"title": "Save Failed",
			"body":  "Could not open %s for writing." % path,
		})
		return
	f.store_string(payload)
	f.close()
	EventBus.notification_requested.emit({
		"type":  "info",
		"title": "Log Saved",
		"body":  "%d %s entries written to %s." % [entries.size(), _active_tab, path],
	})


func _on_narration_mark(entry: Dictionary) -> void:
	# Stub until Journal bookmarks land (H.2). For now, a notification
	# acknowledges the click so the affordance is discoverable.
	var summary: String = str(entry.get("summary", "")).substr(0, 60)
	EventBus.notification_requested.emit({
		"type":  "info",
		"title": "Marked",
		"body":  "Marked: \"%s…\" (Journal bookmarks land in Phase H.2)" % summary,
	})


func _on_narration_hide_source(source_id: String, _entry: Dictionary) -> void:
	# Stub until the per-source log filter lands. Notification confirms.
	EventBus.notification_requested.emit({
		"type":  "info",
		"title": "Hide Source",
		"body":  "Source '%s' will be hidden once the source-filter system lands." % source_id,
	})


# ---------------------------------------------------------------------------
# Journal context menu handlers (H.2 polish item 1f)
# ---------------------------------------------------------------------------

func _on_bookmark_in_journal(entry: Dictionary) -> void:
	var pid: String = GameState.active_party_id
	if pid.is_empty():
		EventBus.notification_requested.emit({
			"type":  "warning",
			"title": "Bookmark Failed",
			"body":  "No active party — bookmarks are per-party scoped.",
		})
		return
	var journal_repo := JournalRepository.new(CampaignRepository)
	var summary: String = str(entry.get("summary", ""))
	# Truncate the auto-label so the Bookmarks list stays compact; player can
	# rename later via Edit (when inline-edit lands per item 3b).
	var label: String = summary.substr(0, 80) if summary.length() > 80 else summary
	if label.is_empty():
		label = "Log entry %d" % int(entry.get("id", 0))
	var bookmark_id: String = journal_repo.create_bookmark(
		pid, "unified_log_entry", str(int(entry.get("id", 0))), label, "")
	if bookmark_id.is_empty():
		EventBus.notification_requested.emit({
			"type":  "warning",
			"title": "Bookmark Failed",
			"body":  "Could not write bookmark — see logs.",
		})
		return
	EventBus.journal_changed.emit("bookmark_added", pid)
	EventBus.notification_requested.emit({
		"type":  "info",
		"title": "Bookmarked",
		"body":  "Log entry added to Journal Bookmarks.",
	})


func _on_note_about_entry(entry: Dictionary) -> void:
	var pid: String = GameState.active_party_id
	if pid.is_empty():
		EventBus.notification_requested.emit({
			"type":  "warning",
			"title": "Note Failed",
			"body":  "No active party — notes are per-party scoped.",
		})
		return
	# Pre-create a stub note seeded with the entry's actor / target ids and a
	# body excerpting the entry summary; the player edits the note via the
	# Journal Notes sub-tab inline-edit (when item 3b lands). Until then,
	# the notification gives the player the affordance entry point.
	var journal_repo := JournalRepository.new(CampaignRepository)
	var attached_ids: Array = []
	var attached_kinds: Array = []
	var actor_id: String = str(entry.get("actor_id", ""))
	var target_id: String = str(entry.get("target_id", ""))
	if not actor_id.is_empty():
		attached_ids.append(actor_id)
		attached_kinds.append("character")
	if not target_id.is_empty() and target_id != actor_id:
		attached_ids.append(target_id)
		attached_kinds.append("character")
	var note_id: String = journal_repo.create_note(pid, {
		"title": "About log entry %d" % int(entry.get("id", 0)),
		"body":  "Source event: %s" % str(entry.get("summary", "")),
		"attached_entity_ids":   JSON.stringify(attached_ids),
		"attached_entity_kinds": JSON.stringify(attached_kinds),
	})
	if note_id.is_empty():
		EventBus.notification_requested.emit({
			"type":  "warning",
			"title": "Note Failed",
			"body":  "Could not write note — see logs.",
		})
		return
	EventBus.journal_changed.emit("note_added", pid)
	# Open the Journal Notes sub-tab so the player can edit the new note.
	EventBus.notebook_open_requested.emit("journal")
	EventBus.notification_requested.emit({
		"type":  "info",
		"title": "Note Created",
		"body":  "Stub note added to Journal Notes — open and edit to refine.",
	})


func _format_markdown(entries: Array) -> String:
	var lines: Array[String] = ["# Game Log — %s tab" % TAB_LABELS.get(_active_tab, "All"), ""]
	for entry in entries:
		var ts: String = _format_export_timestamp(entry)
		var summary: String = str(entry.get("summary", ""))
		var category: String = str(entry.get("category", ""))
		lines.append("- **[%s]** _%s_ — %s" % [ts, category, summary])
	return "\n".join(lines)


func _format_text(entries: Array) -> String:
	var lines: Array[String] = []
	for entry in entries:
		var ts: String = _format_export_timestamp(entry)
		lines.append("[%s] %s" % [ts, str(entry.get("summary", ""))])
	return "\n".join(lines)


func _format_export_timestamp(entry: Dictionary) -> String:
	var gt: int = int(entry.get("game_time", 0))
	if gt > 0:
		var day: int = gt / 8640
		var rounds_today: int = gt % 8640
		var hour: int = rounds_today / 360
		var minute: int = (rounds_today % 360) / 6
		return "D%d %02d:%02d" % [day + 1, hour, minute]
	return ""
