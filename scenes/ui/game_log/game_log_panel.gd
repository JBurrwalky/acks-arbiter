class_name GameLogPanel
extends CanvasLayer

## Collapsible left-side game state log panel accessible from any game screen.
##
## Toggle with F8 (game_log_toggle input action).
## Shows all game events from the current session, color-coded by category,
## with filter buttons for category groups.
##
## Connects to GameLogRecorder.entry_added for live updates.
## Reads full history from GameLogRecorder.game_log on open.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const PANEL_WIDTH := 360
const ENTRY_HEIGHT := 32
const MAX_VISIBLE := 500

const CATEGORY_COLORS := {
	"combat":      Color(0.75, 0.22, 0.18, 1.0),  # Red
	"exploration": Color(0.50, 0.70, 0.90, 1.0),  # Blue
	"character":   Color(0.20, 0.60, 0.30, 1.0),  # Green
	"inventory":   Color(0.65, 0.55, 0.20, 1.0),  # Gold
	"party":       Color(0.55, 0.55, 0.55, 1.0),  # Gray
	"henchman":    Color(0.55, 0.35, 0.65, 1.0),  # Purple
	"magic":       Color(0.60, 0.50, 0.90, 1.0),  # Violet
	"domain":      Color(0.70, 0.55, 0.10, 1.0),  # Amber
	"scheduler":   Color(0.45, 0.55, 0.60, 1.0),  # Teal
	"session":     Color(0.50, 0.50, 0.50, 1.0),  # Gray
	"time":        Color(0.65, 0.60, 0.52, 1.0),  # Neutral tan
	"dice":        Color(0.85, 0.50, 0.15, 1.0),  # Orange
	"reputation":  Color(0.55, 0.35, 0.65, 1.0),  # Purple
	"creature":    Color(0.65, 0.55, 0.20, 1.0),  # Gold
	"override":    Color(0.85, 0.35, 0.15, 1.0),  # Warning orange
	"narration":   Color(0.90, 0.85, 0.75, 1.0),  # Parchment
}
const DEFAULT_COLOR := Color(0.60, 0.58, 0.52, 1.0)

## Filter groups: filter_key -> Array of categories included.
const FILTER_GROUPS := {
	"all":       [],  # Special: shows everything
	"combat":    ["combat"],
	"explore":   ["exploration", "time", "scheduler"],
	"character": ["character", "inventory", "party", "henchman"],
	"magic":     ["magic"],
	"other":     ["domain", "session", "dice", "reputation", "creature", "override", "narration"],
}


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _panel: PanelContainer = null
var _scroll: ScrollContainer = null
var _entry_list: VBoxContainer = null
var _filter_buttons: HBoxContainer = null
var _active_filter: String = "all"
var _auto_scroll: bool = true
var _recorder: GameLogRecorder = null


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer = 85
	_build_ui()
	_panel.visible = false

	# Find the GameLogRecorder sibling.
	await get_tree().process_frame
	_recorder = get_parent().get_node_or_null("GameLogRecorder")
	if _recorder != null:
		_recorder.entry_added.connect(_on_entry_added)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("game_log_toggle"):
		toggle()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func toggle() -> void:
	_panel.visible = not _panel.visible
	if _panel.visible:
		_rebuild_entries()


func show_log() -> void:
	_panel.visible = true
	_rebuild_entries()


func hide_log() -> void:
	_panel.visible = false


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_panel.offset_left = 0
	_panel.offset_right = PANEL_WIDTH
	_panel.offset_top = 0
	_panel.offset_bottom = 0

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.08, 0.06, 0.96)
	style.border_color = UiSurfaceStyles.FRAME_BORDER_COLOR
	style.border_width_right = 2
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_panel.add_child(vbox)

	# Title bar.
	var title_bar := HBoxContainer.new()
	title_bar.add_theme_constant_override("separation", 8)
	vbox.add_child(title_bar)

	var title := Label.new()
	title.text = "Game Log"
	title.add_theme_color_override("font_color", Color(0.90, 0.85, 0.75, 1.0))
	title.add_theme_font_size_override("font_size", 16)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_bar.add_child(title)

	var export_btn := Button.new()
	export_btn.text = "Export"
	export_btn.flat = true
	export_btn.add_theme_color_override("font_color", Color(0.6, 0.55, 0.50, 1.0))
	export_btn.add_theme_font_size_override("font_size", 12)
	export_btn.pressed.connect(_on_export_pressed)
	title_bar.add_child(export_btn)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.flat = true
	close_btn.add_theme_color_override("font_color", Color(0.6, 0.55, 0.50, 1.0))
	close_btn.pressed.connect(func(): hide_log())
	title_bar.add_child(close_btn)

	# Filter bar.
	_filter_buttons = HBoxContainer.new()
	_filter_buttons.add_theme_constant_override("separation", 4)
	vbox.add_child(_filter_buttons)

	for filter_name in ["All", "Combat", "Explore", "Character", "Magic", "Other"]:
		var btn := Button.new()
		btn.text = filter_name
		btn.toggle_mode = true
		btn.button_pressed = (filter_name == "All")
		btn.flat = true
		btn.add_theme_font_size_override("font_size", 11)
		btn.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55, 1.0))
		btn.pressed.connect(_make_filter_handler(filter_name.to_lower()))
		_filter_buttons.add_child(btn)

	# Separator.
	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", UiSurfaceStyles.FRAME_BORDER_COLOR)
	vbox.add_child(sep)

	# Scroll area.
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_scroll)

	_entry_list = VBoxContainer.new()
	_entry_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entry_list.add_theme_constant_override("separation", 2)
	_scroll.add_child(_entry_list)


func _make_filter_handler(filter_key: String) -> Callable:
	return func():
		_active_filter = filter_key
		for btn in _filter_buttons.get_children():
			if btn is Button:
				btn.button_pressed = (btn.text.to_lower() == filter_key)
		_rebuild_entries()


# ---------------------------------------------------------------------------
# Entry rendering
# ---------------------------------------------------------------------------

func _rebuild_entries() -> void:
	for child in _entry_list.get_children():
		child.queue_free()

	if _recorder == null or _recorder.game_log == null:
		return

	var all_entries: Array = _recorder.game_log.get_all_entries()
	# Only show the last MAX_VISIBLE entries that pass the filter.
	var visible_count := 0
	# Walk backwards to find the starting index.
	var start_idx := 0
	if all_entries.size() > MAX_VISIBLE:
		var counted := 0
		for i in range(all_entries.size() - 1, -1, -1):
			if _passes_filter(all_entries[i]):
				counted += 1
				if counted >= MAX_VISIBLE:
					start_idx = i
					break

	for i in range(start_idx, all_entries.size()):
		var entry: Dictionary = all_entries[i]
		if not _passes_filter(entry):
			continue
		_entry_list.add_child(_create_entry_row(entry))
		visible_count += 1

	if _auto_scroll:
		await get_tree().process_frame
		_scroll.scroll_vertical = _scroll.get_v_scroll_bar().max_value


func _passes_filter(entry: Dictionary) -> bool:
	if _active_filter == "all":
		return true
	var category: String = entry.get("category", "")
	var group: Array = FILTER_GROUPS.get(_active_filter, [])
	return category in group


func _create_entry_row(entry: Dictionary) -> PanelContainer:
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, ENTRY_HEIGHT)

	var category: String = entry.get("category", "")
	var color: Color = CATEGORY_COLORS.get(category, DEFAULT_COLOR)

	var row_style := StyleBoxFlat.new()
	row_style.bg_color = Color(0.14, 0.12, 0.10, 0.8)
	row_style.border_color = color
	row_style.border_width_left = 3
	row_style.corner_radius_top_left = 2
	row_style.corner_radius_bottom_left = 2
	row_style.content_margin_left = 8
	row_style.content_margin_right = 6
	row_style.content_margin_top = 3
	row_style.content_margin_bottom = 3
	row.add_theme_stylebox_override("panel", row_style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	row.add_child(hbox)

	# Game time label.
	var time_label := Label.new()
	time_label.text = _format_short_time(entry.get("game_time", 0))
	time_label.add_theme_color_override("font_color", Color(0.55, 0.52, 0.45, 1.0))
	time_label.add_theme_font_size_override("font_size", 10)
	time_label.custom_minimum_size = Vector2(72, 0)
	hbox.add_child(time_label)

	# Summary label.
	var summary_label := Label.new()
	summary_label.text = entry.get("summary", "")
	summary_label.add_theme_color_override("font_color", color.lerp(Color.WHITE, 0.3))
	summary_label.add_theme_font_size_override("font_size", 12)
	summary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hbox.add_child(summary_label)

	return row


func _format_short_time(elapsed_rounds: int) -> String:
	## Compact time label: "D1 06:00" format.
	const ROUNDS_PER_MINUTE := 6
	const ROUNDS_PER_HOUR := 360
	const ROUNDS_PER_DAY := 8640

	var total_days := elapsed_rounds / ROUNDS_PER_DAY
	var hour := (elapsed_rounds % ROUNDS_PER_DAY) / ROUNDS_PER_HOUR
	var minute := (elapsed_rounds % ROUNDS_PER_HOUR) / ROUNDS_PER_MINUTE
	var day := total_days + 1  # 1-indexed

	return "D%d %02d:%02d" % [day, hour, minute]


# ---------------------------------------------------------------------------
# Live updates
# ---------------------------------------------------------------------------

func _on_entry_added(entry: Dictionary) -> void:
	if not _panel.visible:
		return
	if not _passes_filter(entry):
		return

	_entry_list.add_child(_create_entry_row(entry))

	# Prune oldest visible rows if over limit.
	while _entry_list.get_child_count() > MAX_VISIBLE:
		var oldest := _entry_list.get_child(0)
		_entry_list.remove_child(oldest)
		oldest.queue_free()

	if _auto_scroll:
		await get_tree().process_frame
		_scroll.scroll_vertical = _scroll.get_v_scroll_bar().max_value


# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------

func _on_export_pressed() -> void:
	if _recorder == null or _recorder.game_log == null:
		return

	var timestamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var json_path := "user://game_log_%s.json" % timestamp
	var txt_path := "user://game_log_%s.txt" % timestamp

	# JSON export.
	var json_file := FileAccess.open(json_path, FileAccess.WRITE)
	if json_file != null:
		json_file.store_string(_recorder.game_log.to_json_string())
		json_file.close()

	# TXT export.
	var txt_content := _recorder.game_log.to_text_string()
	var txt_file := FileAccess.open(txt_path, FileAccess.WRITE)
	if txt_file != null:
		txt_file.store_string(txt_content)
		txt_file.close()

	# Copy to clipboard.
	DisplayServer.clipboard_set(txt_content)

	# Notify.
	EventBus.notification_requested.emit({
		"type": "success",
		"category": "system",
		"title": "Game log exported",
		"body": "Saved to %s and copied to clipboard." % json_path,
		"duration": 4.0,
	})
