class_name RollLogOverlay
extends CanvasLayer

## Collapsible movable/resizable roll log panel accessible from any game screen.
##
## Toggle with Ctrl+Alt+R (roll_log_toggle input action).
## Shows all dice rolls from the current session, color-coded by type,
## with click-to-expand modifier breakdowns.
##
## Reads from dice_rolls DB table on open and subscribes to
## EventBus.dice_rolled for live updates.

const PANEL_WIDTH := 360
const PANEL_HEIGHT := 500
const ENTRY_HEIGHT := 36
const MAX_ENTRIES := 200

# Drag / resize
const GRIP_SIZE := 14.0
const MIN_WIDTH := 280.0
const MIN_HEIGHT := 200.0

const ROLL_TYPE_COLORS := {
	"attack_throw": Color(0.75, 0.22, 0.18, 1.0),      # Red
	"damage": Color(0.85, 0.50, 0.15, 1.0),             # Orange
	"saving_throw": Color(0.20, 0.45, 0.70, 1.0),       # Blue
	"thief_skill": Color(0.20, 0.60, 0.30, 1.0),        # Green
	"proficiency_throw": Color(0.20, 0.60, 0.30, 1.0),  # Green
	"morale": Color(0.55, 0.35, 0.65, 1.0),             # Purple
	"reaction": Color(0.55, 0.35, 0.65, 1.0),           # Purple
	"initiative": Color(0.45, 0.55, 0.60, 1.0),         # Teal
	"encounter_check": Color(0.50, 0.50, 0.50, 1.0),    # Gray
	"hp_roll": Color(0.85, 0.50, 0.15, 1.0),            # Orange
}
const DEFAULT_ROLL_COLOR := Color(0.60, 0.58, 0.52, 1.0)  # Neutral tan

var _panel: PanelContainer = null
var _scroll: ScrollContainer = null
var _entry_list: VBoxContainer = null
var _filter_buttons: HBoxContainer = null
var _title_bar: HBoxContainer = null
var _resize_grip: Control = null
var _active_filter: String = "all"
var _auto_scroll: bool = true
var _entries: Array[Dictionary] = []  # Cached roll entries

# Drag / resize state
var _dragging: bool = false
var _drag_mouse_start: Vector2 = Vector2.ZERO
var _drag_panel_start: Vector2 = Vector2.ZERO
var _resizing: bool = false
var _resize_mouse_start: Vector2 = Vector2.ZERO
var _resize_panel_start_size: Vector2 = Vector2.ZERO


func _ready() -> void:
	layer = 90
	_build_ui()
	_panel.visible = false
	EventBus.dice_rolled.connect(_on_dice_rolled)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("roll_log_toggle"):
		toggle()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func toggle() -> void:
	_panel.visible = not _panel.visible
	if _panel.visible:
		_load_from_db()
		_rebuild_entries()


func show_log() -> void:
	_panel.visible = true
	_load_from_db()
	_rebuild_entries()


func hide_log() -> void:
	_panel.visible = false


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	_panel = PanelContainer.new()
	# Dock the default position to the right edge of the viewport; the user
	# can drag it anywhere once the overlay is shown.
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT, true)
	var vp := get_viewport().get_visible_rect().size
	_panel.position = Vector2(vp.x - PANEL_WIDTH - 8.0, 8.0)
	_panel.size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	_panel.custom_minimum_size = Vector2(MIN_WIDTH, MIN_HEIGHT)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.08, 0.06, 0.96)
	style.border_color = UiSurfaceStyles.FRAME_BORDER_COLOR
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	# Content wrapper: a plain Control (non-Container) inside the PanelContainer
	# so children that need corner anchoring (the resize grip) keep their
	# geometry. A direct PanelContainer child would be forced to fill the
	# whole panel, which would spread the grip's resize cursor/mouse-stop
	# over every pixel.
	var wrap := Control.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(wrap)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrap.add_child(vbox)

	# Title bar doubles as drag handle.
	_title_bar = HBoxContainer.new()
	_title_bar.add_theme_constant_override("separation", 8)
	_title_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_title_bar.gui_input.connect(_on_title_bar_input)
	vbox.add_child(_title_bar)

	var title := Label.new()
	title.text = "Roll Log  ⠿"  # drag-handle glyph
	title.add_theme_color_override("font_color", Color(0.90, 0.85, 0.75, 1.0))
	title.add_theme_font_size_override("font_size", 16)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_bar.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.flat = true
	close_btn.add_theme_color_override("font_color", Color(0.6, 0.55, 0.50, 1.0))
	close_btn.pressed.connect(func(): hide_log())
	_title_bar.add_child(close_btn)

	# Filter bar.
	_filter_buttons = HBoxContainer.new()
	_filter_buttons.add_theme_constant_override("separation", 4)
	vbox.add_child(_filter_buttons)

	for filter_name in ["All", "Attack", "Save", "Skill", "Other"]:
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

	# Resize grip in bottom-right corner of the content wrapper.
	_resize_grip = _build_resize_grip()
	wrap.add_child(_resize_grip)


func _build_resize_grip() -> Control:
	var grip := ColorRect.new()
	grip.name = "ResizeGrip"
	grip.color = Color(1, 1, 1, 0.18)
	grip.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	grip.mouse_filter = Control.MOUSE_FILTER_STOP
	grip.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	grip.size = Vector2(GRIP_SIZE, GRIP_SIZE)
	grip.offset_left = -GRIP_SIZE
	grip.offset_top = -GRIP_SIZE
	grip.offset_right = 0.0
	grip.offset_bottom = 0.0
	grip.gui_input.connect(_on_grip_input)
	return grip


# ---------------------------------------------------------------------------
# Drag / Resize
# ---------------------------------------------------------------------------

func _on_title_bar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		_dragging = true
		_drag_mouse_start = event.global_position
		_drag_panel_start = _panel.position
		get_viewport().set_input_as_handled()


func _on_grip_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		_resizing = true
		_resize_mouse_start = event.global_position
		_resize_panel_start_size = _panel.size
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	## Handle motion/release globally so drag continues when mouse leaves the
	## title bar or grip.
	if not (_dragging or _resizing):
		return
	if event is InputEventMouseMotion:
		if _dragging:
			var delta: Vector2 = event.global_position - _drag_mouse_start
			_panel.position = _drag_panel_start + delta
			_clamp_to_viewport()
		elif _resizing:
			var delta2: Vector2 = event.global_position - _resize_mouse_start
			var new_size: Vector2 = _resize_panel_start_size + delta2
			new_size.x = maxf(MIN_WIDTH, new_size.x)
			new_size.y = maxf(MIN_HEIGHT, new_size.y)
			_panel.size = new_size
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and not event.pressed:
		_dragging = false
		_resizing = false


func _clamp_to_viewport() -> void:
	## Keep at least the title bar on screen so the panel is always reachable.
	var vp := get_viewport().get_visible_rect().size
	var header_h: float = _title_bar.size.y if _title_bar != null else 24.0
	_panel.position.x = clampf(_panel.position.x, -_panel.size.x + 64.0, vp.x - 64.0)
	_panel.position.y = clampf(_panel.position.y, 0.0, vp.y - header_h)


func _make_filter_handler(filter_key: String) -> Callable:
	return func():
		_active_filter = filter_key
		# Update button states.
		for btn in _filter_buttons.get_children():
			if btn is Button:
				btn.button_pressed = (btn.text.to_lower() == filter_key)
		_rebuild_entries()


# ---------------------------------------------------------------------------
# Data loading
# ---------------------------------------------------------------------------

func _load_from_db() -> void:
	_entries.clear()
	if CampaignRepository.db == null:
		return
	CampaignRepository.db.query(
		"SELECT * FROM dice_rolls ORDER BY id DESC LIMIT %d" % MAX_ENTRIES
	)
	for row in CampaignRepository.db.query_result:
		_entries.append(_row_to_entry(row))
	_entries.reverse()  # Oldest first for display (newest at bottom).


func _row_to_entry(row: Dictionary) -> Dictionary:
	var individual: Array = []
	var raw_json: String = row.get("individual_results", "[]")
	var parsed = JSON.parse_string(raw_json)
	if parsed is Array:
		individual = parsed

	return {
		"roll_type": row.get("roll_type", ""),
		"sides": row.get("sides", 0),
		"count": row.get("count", 0),
		"modifier": row.get("modifier", 0),
		"individual_results": individual,
		"raw_total": row.get("raw_total", 0),
		"modified_total": row.get("modified_total", 0),
		"was_overridden": row.get("was_overridden", 0) == 1,
		"was_player_entered": row.get("was_player_entered", 0) == 1,
		"game_day": row.get("game_day", 0),
	}


# ---------------------------------------------------------------------------
# Entry rendering
# ---------------------------------------------------------------------------

func _rebuild_entries() -> void:
	for child in _entry_list.get_children():
		child.queue_free()

	for entry in _entries:
		if not _passes_filter(entry):
			continue
		_entry_list.add_child(_create_entry_row(entry))

	# Auto-scroll to bottom.
	if _auto_scroll:
		await get_tree().process_frame
		_scroll.scroll_vertical = _scroll.get_v_scroll_bar().max_value


func _passes_filter(entry: Dictionary) -> bool:
	if _active_filter == "all":
		return true
	var rt: String = entry.get("roll_type", "")
	match _active_filter:
		"attack":
			return rt in ["attack_throw", "damage"]
		"save":
			return rt in ["saving_throw"]
		"skill":
			return rt in ["thief_skill", "proficiency_throw"]
		"other":
			return rt not in ["attack_throw", "damage", "saving_throw", "thief_skill", "proficiency_throw"]
	return true


func _create_entry_row(entry: Dictionary) -> PanelContainer:
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, ENTRY_HEIGHT)

	var rt: String = entry.get("roll_type", "")
	var color: Color = ROLL_TYPE_COLORS.get(rt, DEFAULT_ROLL_COLOR)

	var row_style := StyleBoxFlat.new()
	row_style.bg_color = Color(0.14, 0.12, 0.10, 0.8)
	row_style.border_color = color
	row_style.border_width_left = 3
	row_style.corner_radius_top_left = 2
	row_style.corner_radius_bottom_left = 2
	row_style.content_margin_left = 8
	row_style.content_margin_right = 6
	row_style.content_margin_top = 4
	row_style.content_margin_bottom = 4
	row.add_theme_stylebox_override("panel", row_style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	row.add_child(hbox)

	# Roll type label.
	var type_label := Label.new()
	type_label.text = _format_roll_type(rt)
	type_label.add_theme_color_override("font_color", color)
	type_label.add_theme_font_size_override("font_size", 12)
	type_label.custom_minimum_size = Vector2(90, 0)
	hbox.add_child(type_label)

	# Expression.
	var count: int = entry.get("count", 1)
	var sides: int = entry.get("sides", 20)
	var modifier: int = entry.get("modifier", 0)
	var expr_text := "%dd%d" % [count, sides]
	if modifier > 0:
		expr_text += "+%d" % modifier
	elif modifier < 0:
		expr_text += "%d" % modifier

	var expr_label := Label.new()
	expr_label.text = expr_text
	expr_label.add_theme_color_override("font_color", Color(0.65, 0.60, 0.52, 1.0))
	expr_label.add_theme_font_size_override("font_size", 11)
	expr_label.custom_minimum_size = Vector2(60, 0)
	hbox.add_child(expr_label)

	# Result.
	var result_label := Label.new()
	result_label.text = str(entry.get("modified_total", 0))
	result_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85, 1.0))
	result_label.add_theme_font_size_override("font_size", 14)
	result_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(result_label)

	# Override/player icon.
	if entry.get("was_overridden", false):
		var override_icon := Label.new()
		override_icon.text = "!"
		override_icon.add_theme_color_override("font_color", Color(0.85, 0.35, 0.15, 1.0))
		override_icon.add_theme_font_size_override("font_size", 14)
		override_icon.tooltip_text = "This roll was overridden"
		hbox.add_child(override_icon)
	elif entry.get("was_player_entered", false):
		var player_icon := Label.new()
		player_icon.text = "P"
		player_icon.add_theme_color_override("font_color", Color(0.35, 0.65, 0.85, 1.0))
		player_icon.add_theme_font_size_override("font_size", 12)
		player_icon.tooltip_text = "Player-entered physical dice result"
		hbox.add_child(player_icon)

	# Click to expand details.
	row.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_toggle_detail(row, entry)
	)

	return row


func _toggle_detail(row: PanelContainer, entry: Dictionary) -> void:
	var detail_name := "__detail"
	var existing := row.get_node_or_null(detail_name)
	if existing != null:
		existing.queue_free()
		return

	var detail := VBoxContainer.new()
	detail.name = detail_name
	detail.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	detail.offset_top = row.size.y

	var individual: Array = entry.get("individual_results", [])
	if individual.size() > 0:
		var dice_label := Label.new()
		dice_label.text = "  Dice: %s" % str(individual)
		dice_label.add_theme_color_override("font_color", Color(0.55, 0.52, 0.45, 1.0))
		dice_label.add_theme_font_size_override("font_size", 11)
		detail.add_child(dice_label)

	var raw: int = entry.get("raw_total", 0)
	var mod: int = entry.get("modifier", 0)
	if mod != 0:
		var mod_label := Label.new()
		var mod_sign := "+" if mod > 0 else ""
		mod_label.text = "  Raw: %d, Modifier: %s%d" % [raw, mod_sign, mod]
		mod_label.add_theme_color_override("font_color", Color(0.55, 0.52, 0.45, 1.0))
		mod_label.add_theme_font_size_override("font_size", 11)
		detail.add_child(mod_label)

	row.add_child(detail)
	row.custom_minimum_size.y = ENTRY_HEIGHT + 20 * detail.get_child_count()


func _format_roll_type(rt: String) -> String:
	match rt:
		"attack_throw": return "Attack"
		"damage": return "Damage"
		"saving_throw": return "Save"
		"thief_skill": return "Skill"
		"proficiency_throw": return "Prof."
		"morale": return "Morale"
		"reaction": return "Reaction"
		"initiative": return "Init."
		"encounter_check": return "Encounter"
		"hp_roll": return "HP Roll"
		_: return rt.capitalize() if not rt.is_empty() else "Roll"


# ---------------------------------------------------------------------------
# Live updates
# ---------------------------------------------------------------------------

func _on_dice_rolled(roll: Dictionary) -> void:
	_entries.append(roll)
	if _entries.size() > MAX_ENTRIES:
		_entries.pop_front()

	if _panel.visible:
		if _passes_filter(roll):
			_entry_list.add_child(_create_entry_row(roll))
			if _auto_scroll:
				await get_tree().process_frame
				_scroll.scroll_vertical = _scroll.get_v_scroll_bar().max_value
