extends PanelContainer

## LogEntryRow — single entry rendering for the embedded Unified Log
## (gdd-unified-log-panel.md §6). Pure presentation: builds a label row and
## emits click-to-link signals for entries that carry actor / target ids.
##
## Click behavior per resolved O-L7:
##   - Combat / Rolls / Quest entries (any category with actor_id or
##     target_id): left-click on the row emits `entity_link_requested(id)`
##     for the actor (or the target if no actor). Consumers route this to
##     EventBus.notebook_active_entity_requested.
##   - Narration entries: left-click is a no-op; right-click opens a small
##     context menu (Copy / Mark / Hide-this-source) per H.0 v1.1 polish.
##     Copy writes the entry summary to the clipboard; Mark + Hide emit
##     signals that downstream systems (Journal bookmarks H.2; per-source
##     log filter — future) consume.


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal entity_link_requested(entity_id: String)

## H.0 — narration row right-click "Mark" emits this. Journal bookmarks
## (Phase H.2) consume; for now the parent UnifiedLog logs a notification.
signal narration_mark_requested(entry: Dictionary)

## H.0 — narration row right-click "Hide source" emits this. The per-source
## log filter (future) consumes. Empty string source falls back to category.
signal narration_hide_source_requested(source_id: String, entry: Dictionary)

## H.2 polish item 1f — right-click "Bookmark in Journal" emits this; the
## UnifiedLog parent forwards to JournalRepository.create_bookmark.
signal bookmark_in_journal_requested(entry: Dictionary)

## H.2 polish item 1f — right-click "Add note about this" emits this; the
## UnifiedLog parent opens a Notes-modal flow with the entry pre-attached.
signal note_about_entry_requested(entry: Dictionary)


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const TIMESTAMP_FONT_SIZE := 9
const SUMMARY_FONT_SIZE := 11
const TIMESTAMP_COLOR := Color(0.55, 0.50, 0.42, 1.0)
const SUMMARY_COLOR := Color(0.85, 0.80, 0.70, 1.0)
const NARRATION_COLOR := Color(0.78, 0.72, 0.92, 1.0)

const CATEGORY_BORDER_COLORS := {
	"combat":      Color(0.85, 0.45, 0.35, 1.0),
	"dice":        Color(0.50, 0.70, 0.85, 1.0),
	"narration":   Color(0.65, 0.55, 0.85, 1.0),
	"exploration": Color(0.55, 0.80, 0.55, 1.0),
	"character":   Color(0.85, 0.75, 0.45, 1.0),
	"inventory":   Color(0.75, 0.65, 0.45, 1.0),
	"party":       Color(0.70, 0.55, 0.40, 1.0),
	"henchman":    Color(0.65, 0.60, 0.50, 1.0),
	"magic":       Color(0.55, 0.50, 0.85, 1.0),
	"domain":      Color(0.85, 0.65, 0.30, 1.0),
}
const DEFAULT_BORDER_COLOR := Color(0.46, 0.33, 0.19, 1.0)


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _entry: Dictionary = {}
var _summary_label: Label = null


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func setup(entry: Dictionary) -> void:
	_entry = entry
	# Stored as metadata so UnifiedLog's scroll-to-id helper (H.2 item 1e)
	# can match the row to the bookmark target without reparsing children.
	set_meta("entry", entry)
	_build_ui()
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)


# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var category: String = str(_entry.get("category", ""))
	add_theme_stylebox_override("panel", _row_style(category))

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hbox)

	var ts_label := Label.new()
	ts_label.text = _format_timestamp()
	ts_label.add_theme_font_size_override("font_size", TIMESTAMP_FONT_SIZE)
	ts_label.add_theme_color_override("font_color", TIMESTAMP_COLOR)
	ts_label.custom_minimum_size = Vector2(60, 0)
	ts_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(ts_label)

	_summary_label = Label.new()
	_summary_label.text = str(_entry.get("summary", ""))
	_summary_label.add_theme_font_size_override("font_size", SUMMARY_FONT_SIZE)
	var summary_color: Color = NARRATION_COLOR if category == "narration" else SUMMARY_COLOR
	_summary_label.add_theme_color_override("font_color", summary_color)
	_summary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(_summary_label)


func _row_style(category: String) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = CATEGORY_BORDER_COLORS.get(category, DEFAULT_BORDER_COLOR)
	style.border_width_left = 3
	style.content_margin_left = 6
	style.content_margin_right = 4
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	return style


func _format_timestamp() -> String:
	# Prefer game_time (rounds since campaign start) so the log reads in the
	# game world's terms; fall back to wall-clock if game_time isn't set.
	var gt: int = int(_entry.get("game_time", 0))
	if gt > 0:
		var day: int = gt / 8640
		var rounds_today: int = gt % 8640
		var hour: int = rounds_today / 360
		var minute: int = (rounds_today % 360) / 6
		return "D%d %02d:%02d" % [day + 1, hour, minute]
	var ts: int = int(_entry.get("timestamp", 0))
	if ts > 0:
		return Time.get_time_string_from_unix_time(ts / 1000)
	return ""


# ---------------------------------------------------------------------------
# Click-to-link
# ---------------------------------------------------------------------------

func _on_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event
	if not mb.pressed:
		return
	var category: String = str(_entry.get("category", ""))
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if category == "narration":
			# Per resolved O-L7 narration entries are no-op on left-click.
			return
		var actor_id: String = str(_entry.get("actor_id", ""))
		var target_id: String = str(_entry.get("target_id", ""))
		var link_id: String = actor_id if not actor_id.is_empty() else target_id
		if not link_id.is_empty():
			entity_link_requested.emit(link_id)
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		_show_context_menu(mb.global_position, category)


# ---------------------------------------------------------------------------
# Right-click context menu — narration items (H.0) + Journal items (H.2)
# ---------------------------------------------------------------------------

const _MENU_COPY := 0
const _MENU_MARK := 1
const _MENU_HIDE := 2
const _MENU_BOOKMARK_JOURNAL := 3
const _MENU_NOTE_ABOUT_ENTRY := 4


func _show_context_menu(global_pos: Vector2, category: String) -> void:
	var menu := PopupMenu.new()
	menu.add_item("Copy", _MENU_COPY)
	# Journal items available on every category (H.2 polish item 1f). Per
	# gdd-journal-tab.md §8 cross-tab table — any log entry is bookmark-able
	# and any log entry can seed a note.
	menu.add_separator()
	menu.add_item("Bookmark in Journal", _MENU_BOOKMARK_JOURNAL)
	menu.add_item("Add note about this", _MENU_NOTE_ABOUT_ENTRY)
	if category == "narration":
		# Narration-only items per resolved O-L7 (H.0).
		menu.add_separator()
		menu.add_item("Mark", _MENU_MARK)
		menu.add_item("Hide this source", _MENU_HIDE)
	menu.id_pressed.connect(_on_context_menu_pressed)
	menu.popup_hide.connect(menu.queue_free)
	add_child(menu)
	menu.position = Vector2i(global_pos)
	menu.popup()


func _on_context_menu_pressed(item_id: int) -> void:
	match item_id:
		_MENU_COPY:
			DisplayServer.clipboard_set(str(_entry.get("summary", "")))
			EventBus.notification_requested.emit({
				"type":  "info",
				"title": "Log Entry Copied",
				"body":  "Entry text copied to clipboard.",
			})
		_MENU_BOOKMARK_JOURNAL:
			bookmark_in_journal_requested.emit(_entry)
		_MENU_NOTE_ABOUT_ENTRY:
			note_about_entry_requested.emit(_entry)
		_MENU_MARK:
			narration_mark_requested.emit(_entry)
		_MENU_HIDE:
			# `data.source_id` if the narration emitter populated it; otherwise
			# fall back to actor_id / target_id / category.
			var data: Dictionary = _entry.get("data", {}) if _entry.has("data") else {}
			var source_id: String = str(data.get("source_id", ""))
			if source_id.is_empty():
				source_id = str(_entry.get("actor_id", ""))
			if source_id.is_empty():
				source_id = str(_entry.get("category", ""))
			narration_hide_source_requested.emit(source_id, _entry)
