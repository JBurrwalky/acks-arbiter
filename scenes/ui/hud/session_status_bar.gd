class_name SessionStatusBar
extends CanvasLayer

## SessionStatusBar — bottom HUD bar reorganized in γ.4 around the
## three-zone architecture per gdd-ui-architecture.md §3.8:
##
##   [ portrait zone (left, fixed ~280px) ]
##   [ 3×3 widget grid (center, EXPAND_FILL) ]
##   [ log placeholder (right, fixed ~360px) — γ.5 fills with UnifiedLog ]
##
## Top-edge drag handle adjusts bar height across four states (Hidden,
## Minimal, Default, Expanded). Height persists per profile via
## user://session_status_bar_height.txt.
##
## Hides while the notebook is open via EventBus.notebook_open_state_changed.
## Hidden during MAIN_MENU and CHARACTER_CREATION.

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Bar height states per gdd-ui-architecture.md §3.8.
const HEIGHT_HIDDEN := 8
const HEIGHT_MINIMAL := 50
const HEIGHT_DEFAULT := 200
const HEIGHT_EXPANDED_PCT := 0.40  ## fraction of viewport height for max

const HEIGHT_STATE_HIDDEN := "hidden"
const HEIGHT_STATE_MINIMAL := "minimal"
const HEIGHT_STATE_DEFAULT := "default"
const HEIGHT_STATE_EXPANDED := "expanded"

const HEIGHT_STATES := [
	HEIGHT_STATE_HIDDEN,
	HEIGHT_STATE_MINIMAL,
	HEIGHT_STATE_DEFAULT,
	HEIGHT_STATE_EXPANDED,
]

const HEIGHT_PERSIST_PATH := "user://session_status_bar_height.txt"

const PORTRAIT_ZONE_WIDTH := 280
const LOG_ZONE_WIDTH := 360
const DRAG_HANDLE_HEIGHT := 6

const PORTRAIT_SIZE := Vector2(56, 56)
const PORTRAIT_SLOT_PADDING := 2

const FONT_SIZE := 12
const SMALL_FONT_SIZE := 10

const LABEL_COLOR := Color(0.85, 0.80, 0.70, 1.0)
const DIM_COLOR := Color(0.55, 0.50, 0.42, 1.0)
const BG_COLOR := Color(0.08, 0.06, 0.04, 0.95)
const BORDER_COLOR := Color(0.46, 0.33, 0.19, 1.0)
const SUBPANEL_BG := Color(0.13, 0.10, 0.07, 0.85)
const HANDLE_COLOR := Color(0.46, 0.33, 0.19, 0.6)

## Back-compat: other surfaces import SessionStatusBar.BAR_HEIGHT for their
## own bottom-padding calculations. γ.4 keeps this as the default-state
## height; surfaces should refresh on EventBus.bar_height_changed when that
## signal lands.
const BAR_HEIGHT := HEIGHT_DEFAULT

const TRAVEL_TERRAINS := ["clear", "woods", "hills", "desert",
	"jungle", "swamp", "mountains"]

const TERRAIN_LABELS := {
	"clear": "Clear", "woods": "Woods", "hills": "Hills",
	"desert": "Desert", "jungle": "Jungle", "swamp": "Swamp",
	"mountains": "Mtns",
}


# ---------------------------------------------------------------------------
# Fields — top-level layout
# ---------------------------------------------------------------------------

var _bar: PanelContainer = null
var _drag_handle: Control = null
var _height_state: String = HEIGHT_STATE_DEFAULT
var _last_non_hidden_state: String = HEIGHT_STATE_DEFAULT
var _drag_origin_y: float = 0.0
var _drag_start_height: int = 0
var _is_dragging: bool = false


# ---------------------------------------------------------------------------
# Fields — portrait zone (left)
# ---------------------------------------------------------------------------

var _portrait_zone: Control = null
const PortraitWithBadgeScript := preload("res://scenes/ui/components/portrait_with_badge.gd")

# Level-badge tinting palette per the prior γ.4 inline builder. Bright color
# = off-focus level (draws the eye); muted = on-focus level (de-emphasised
# because the camera is already there).
const LEVEL_BADGE_COLOR := Color(1.0, 0.92, 0.45, 1.0)
const LEVEL_BADGE_OUTLINE := Color(0, 0, 0, 1)
const LEVEL_BADGE_TINT_OFF_FOCUS := Color(1.0, 0.95, 0.55, 1.0)
const LEVEL_BADGE_TINT_ON_FOCUS := Color(0.55, 0.52, 0.40, 1.0)

var _portraits_hbox: HBoxContainer = null
## Texture cache keyed by portrait_id (not by character_id) — multiple
## characters may share a portrait. Lifetime is the autoload session;
## invalidated on EventBus.session_ended (γ.4 cleanup).
static var _portrait_cache: Dictionary = {}
var _party_levels: Dictionary = {}
var _current_focus_level: int = -9999
## Per-character widget cache. Replaces γ.4's `_portrait_badges` Label dict;
## the PortraitWithBadge instance holds its own badge Label internally and
## exposes `set_badge` / `set_badge_modulate` per the H.0 API extension.
## Item 4 — H.2-deferred polish: SessionStatusBar PortraitWithBadge migration.
var _portrait_widgets: Dictionary = {}


# ---------------------------------------------------------------------------
# Fields — center widget zone (3×3)
# ---------------------------------------------------------------------------

var _widget_zone: GridContainer = null

# Row 1
var _location_label: Label = null
var _time_label: Label = null
var _speed_controls: ClockSpeedControls = null

# Row 2
var _rations_panel: PanelContainer = null
var _rations_label: Label = null
var _speeds_panel: PanelContainer = null
var _speeds_base_label: Label = null
var _speeds_grid: GridContainer = null
var _speed_labels: Dictionary = {}
var _encumbrance_label: Label = null

# Row 3
var _camp_btn: Button = null
var _notebook_btn: Button = null
var _notification_label: Label = null

# Pause-reason flash (re-uses existing color scheme).
var _pause_reason_label: Label = null


# ---------------------------------------------------------------------------
# Fields — log zone (right)
# ---------------------------------------------------------------------------

var _log_zone: PanelContainer = null


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer = 80
	_load_persisted_height()
	_build_ui()
	_apply_height_state()
	_connect_signals()
	_update_visibility()


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	_bar = PanelContainer.new()
	_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bar.add_theme_stylebox_override("panel", _bar_style())
	add_child(_bar)

	var bar_vbox := VBoxContainer.new()
	bar_vbox.add_theme_constant_override("separation", 0)
	_bar.add_child(bar_vbox)

	# Drag handle (top edge of bar).
	_drag_handle = _build_drag_handle()
	bar_vbox.add_child(_drag_handle)

	# Three-zone HBox.
	var zones := HBoxContainer.new()
	zones.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zones.size_flags_vertical = Control.SIZE_EXPAND_FILL
	zones.add_theme_constant_override("separation", 6)
	bar_vbox.add_child(zones)

	_portrait_zone = _build_portrait_zone()
	zones.add_child(_portrait_zone)

	_widget_zone = _build_widget_zone()
	zones.add_child(_widget_zone)

	_log_zone = _build_log_zone()
	zones.add_child(_log_zone)


func _bar_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	style.border_color = BORDER_COLOR
	style.border_width_top = 1
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 2
	style.content_margin_bottom = 4
	return style


func _build_drag_handle() -> Control:
	var handle := PanelContainer.new()
	handle.custom_minimum_size = Vector2(0, DRAG_HANDLE_HEIGHT)
	handle.mouse_default_cursor_shape = Control.CURSOR_VSIZE
	handle.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = HANDLE_COLOR
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	handle.add_theme_stylebox_override("panel", style)
	handle.gui_input.connect(_on_drag_handle_input)
	return handle


# ---------------------------------------------------------------------------
# Portrait zone (left)
# ---------------------------------------------------------------------------

func _build_portrait_zone() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PORTRAIT_ZONE_WIDTH, 0)
	panel.size_flags_horizontal = Control.SIZE_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _subpanel_style())
	panel.clip_contents = true

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)

	_portraits_hbox = HBoxContainer.new()
	_portraits_hbox.add_theme_constant_override("separation", 4)
	_portraits_hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	scroll.add_child(_portraits_hbox)
	return panel


# ---------------------------------------------------------------------------
# Widget zone (center 3×3)
# ---------------------------------------------------------------------------

func _build_widget_zone() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)

	# Row 1: Location · Time · Clock-speed controls.
	_location_label = _make_label("--", LABEL_COLOR, FONT_SIZE)
	_location_label.custom_minimum_size = Vector2(120, 0)
	grid.add_child(_location_label)

	_time_label = _make_label("Day 1", LABEL_COLOR, FONT_SIZE)
	_time_label.custom_minimum_size = Vector2(220, 0)
	grid.add_child(_time_label)

	_speed_controls = ClockSpeedControls.new()
	grid.add_child(_speed_controls)

	# Row 2: Rations panel · Travel speeds panel · Encumbrance label.
	_rations_panel = _build_rations_panel()
	grid.add_child(_rations_panel)

	_speeds_panel = _build_speeds_panel()
	grid.add_child(_speeds_panel)

	_encumbrance_label = _make_label("Enc: --", DIM_COLOR, SMALL_FONT_SIZE)
	_encumbrance_label.custom_minimum_size = Vector2(120, 0)
	grid.add_child(_encumbrance_label)

	# Row 3: Camp button · Notebook button · Notification surface.
	_camp_btn = Button.new()
	_camp_btn.text = "Camp"
	_camp_btn.flat = true
	_camp_btn.add_theme_font_size_override("font_size", FONT_SIZE)
	_camp_btn.add_theme_color_override("font_color", LABEL_COLOR)
	_camp_btn.custom_minimum_size = Vector2(60, 0)
	_camp_btn.pressed.connect(func(): EventBus.camp_requested.emit())
	_camp_btn.visible = false
	grid.add_child(_camp_btn)

	_notebook_btn = Button.new()
	_notebook_btn.text = "Notebook"
	_notebook_btn.flat = true
	_notebook_btn.add_theme_font_size_override("font_size", FONT_SIZE)
	_notebook_btn.add_theme_color_override("font_color", LABEL_COLOR)
	_notebook_btn.custom_minimum_size = Vector2(80, 0)
	_notebook_btn.pressed.connect(_on_notebook_btn_pressed)
	grid.add_child(_notebook_btn)
	_refresh_notebook_btn_tooltip()

	# Notification surface holds the latest non-modal notification.
	# Pause-reason text reuses this slot when scheduler pauses.
	var notif_box := HBoxContainer.new()
	notif_box.add_theme_constant_override("separation", 6)
	_notification_label = _make_label("", LABEL_COLOR, SMALL_FONT_SIZE)
	_notification_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notif_box.add_child(_notification_label)
	_pause_reason_label = _make_label("", DIM_COLOR, SMALL_FONT_SIZE)
	_pause_reason_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notif_box.add_child(_pause_reason_label)
	grid.add_child(notif_box)

	return grid


func _build_rations_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _subpanel_style())
	panel.visible = false
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	panel.add_child(vbox)
	var header := _make_label("Rations", DIM_COLOR, SMALL_FONT_SIZE)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)
	_rations_label = _make_label("--", LABEL_COLOR, FONT_SIZE)
	_rations_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rations_label.custom_minimum_size = Vector2(110, 0)
	vbox.add_child(_rations_label)
	return panel


func _build_speeds_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _subpanel_style())
	panel.visible = false
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	panel.add_child(vbox)
	_speeds_base_label = _make_label("Base: --", LABEL_COLOR, SMALL_FONT_SIZE)
	_speeds_base_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_speeds_base_label)
	_speeds_grid = GridContainer.new()
	_speeds_grid.columns = 4
	_speeds_grid.add_theme_constant_override("h_separation", 8)
	_speeds_grid.add_theme_constant_override("v_separation", 0)
	vbox.add_child(_speeds_grid)
	_speed_labels.clear()
	for terrain in TRAVEL_TERRAINS:
		var cell := _make_label("%s: --" % TERRAIN_LABELS[terrain],
			LABEL_COLOR, SMALL_FONT_SIZE)
		cell.custom_minimum_size = Vector2(72, 0)
		_speeds_grid.add_child(cell)
		_speed_labels[terrain] = cell
	return panel


# ---------------------------------------------------------------------------
# Log zone (right) — γ.5 embedded UnifiedLog
# ---------------------------------------------------------------------------

const UnifiedLogScript := preload("res://scenes/ui/hud/unified_log/unified_log.gd")

func _build_log_zone() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(LOG_ZONE_WIDTH, 0)
	panel.size_flags_horizontal = Control.SIZE_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _subpanel_style())
	var unified_log = UnifiedLogScript.new()
	panel.add_child(unified_log)
	return panel


# ---------------------------------------------------------------------------
# Drag handle + height states
# ---------------------------------------------------------------------------

func _on_drag_handle_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_is_dragging = true
			_drag_origin_y = mb.global_position.y
			_drag_start_height = _bar_height_for_state(_height_state)
		else:
			_is_dragging = false
			_snap_height_state()
	elif event is InputEventMouseMotion and _is_dragging:
		var mm: InputEventMouseMotion = event
		var delta_y: float = _drag_origin_y - mm.global_position.y  # up = grow
		var new_height: int = _drag_start_height + int(delta_y)
		_apply_height_pixels(new_height)


func _bar_height_for_state(state: String) -> int:
	match state:
		HEIGHT_STATE_HIDDEN:
			return HEIGHT_HIDDEN
		HEIGHT_STATE_MINIMAL:
			return HEIGHT_MINIMAL
		HEIGHT_STATE_DEFAULT:
			return HEIGHT_DEFAULT
		HEIGHT_STATE_EXPANDED:
			return _expanded_height_pixels()
	return HEIGHT_DEFAULT


func _expanded_height_pixels() -> int:
	var vp_h: float = get_viewport().get_visible_rect().size.y
	return int(vp_h * HEIGHT_EXPANDED_PCT)


func _apply_height_state() -> void:
	if _bar == null:
		return
	var h: int = _bar_height_for_state(_height_state)
	_apply_height_pixels(h)


func _apply_height_pixels(pixels: int) -> void:
	if _bar == null:
		return
	var clamped: int = clampi(pixels, HEIGHT_HIDDEN, _expanded_height_pixels())
	_bar.offset_top = -float(clamped)
	_bar.offset_bottom = 0


## Snaps the current pixel height to the nearest discrete height state and
## persists it. Called when the player releases the drag handle.
func _snap_height_state() -> void:
	var current_h: int = -int(_bar.offset_top)
	var states_with_pixels: Array = [
		[HEIGHT_STATE_HIDDEN, HEIGHT_HIDDEN],
		[HEIGHT_STATE_MINIMAL, HEIGHT_MINIMAL],
		[HEIGHT_STATE_DEFAULT, HEIGHT_DEFAULT],
		[HEIGHT_STATE_EXPANDED, _expanded_height_pixels()],
	]
	var best_state: String = HEIGHT_STATE_DEFAULT
	var best_dist: int = 999999
	for entry in states_with_pixels:
		var d: int = absi(current_h - int(entry[1]))
		if d < best_dist:
			best_dist = d
			best_state = entry[0]
	_set_height_state(best_state)


func _set_height_state(state: String) -> void:
	if not HEIGHT_STATES.has(state):
		state = HEIGHT_STATE_DEFAULT
	_height_state = state
	if state != HEIGHT_STATE_HIDDEN:
		_last_non_hidden_state = state
	_apply_height_state()
	_persist_height()


func _load_persisted_height() -> void:
	if not FileAccess.file_exists(HEIGHT_PERSIST_PATH):
		return
	var f := FileAccess.open(HEIGHT_PERSIST_PATH, FileAccess.READ)
	if f == null:
		return
	var raw := f.get_as_text().strip_edges()
	f.close()
	if HEIGHT_STATES.has(raw):
		_height_state = raw
		if raw != HEIGHT_STATE_HIDDEN:
			_last_non_hidden_state = raw


func _persist_height() -> void:
	var f := FileAccess.open(HEIGHT_PERSIST_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(_height_state)
	f.close()


# ---------------------------------------------------------------------------
# Style helpers
# ---------------------------------------------------------------------------

func _subpanel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = SUBPANEL_BG
	style.border_color = BORDER_COLOR
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	return style


func _make_label(text: String, color: Color, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", size)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


# ---------------------------------------------------------------------------
# Signal wiring
# ---------------------------------------------------------------------------

func _connect_signals() -> void:
	GameState.state_changed.connect(_on_state_changed)
	GameState.exploration_context_changed.connect(_on_exploration_context_changed)
	EventBus.hex_entered.connect(_on_hex_entered)
	EventBus.room_entered.connect(_on_room_entered)
	EventBus.settlement_entered.connect(_on_settlement_entered)
	Timekeeping.round_advanced.connect(_on_time_advanced)
	EventBus.scheduler_paused.connect(_on_scheduler_paused)
	EventBus.scheduler_resumed.connect(_on_scheduler_resumed)
	EventBus.active_party_changed.connect(_on_active_party_changed)
	GameState.session_started.connect(_on_session_started)
	EventBus.party_member_joined.connect(_on_party_membership_changed)
	EventBus.party_member_left.connect(_on_party_membership_changed)
	Timekeeping.day_changed.connect(_on_day_changed)
	EventBus.inventory_updated.connect(_on_inventory_changed)
	EventBus.creature_added.connect(_on_party_roster_changed)
	EventBus.creature_removed.connect(_on_party_roster_changed)
	EventBus.vehicle_changed.connect(_on_party_roster_changed)
	EventBus.party_member_levels_snapshot.connect(_on_party_member_levels_snapshot)
	EventBus.dungeon_focus_level_changed.connect(_on_dungeon_focus_level_changed)
	GameState.session_ended.connect(_on_session_ended)
	# γ.4 — hide while notebook is open.
	EventBus.notebook_open_state_changed.connect(_on_notebook_open_state_changed)
	# γ.4 — track pc-input state to disable the notebook button during enemy
	# resolution. Combat surfaces emit when CombatUIController.active_instance
	# transitions; we re-evaluate cheaply on every state-change tick.
	EventBus.notification_requested.connect(_on_notification_requested)
	_refresh_party_portraits(GameState.active_party_id)
	_refresh_party_status(GameState.active_party_id)
	_refresh_notebook_btn_state()


# ---------------------------------------------------------------------------
# Notebook visibility + combat-blocked button state (γ.4)
# ---------------------------------------------------------------------------

func _on_notebook_open_state_changed(is_open: bool) -> void:
	if _bar == null:
		return
	# Hide the bar while the notebook is open. The drag-handle and height
	# state are preserved; the bar reappears at its prior height on close.
	_bar.visible = (not is_open) and _state_allows_visibility()


func _refresh_notebook_btn_state() -> void:
	if _notebook_btn == null:
		return
	var allowed: bool = CombatUIController.notebook_open_allowed()
	_notebook_btn.disabled = not allowed
	if allowed:
		_refresh_notebook_btn_tooltip()
	else:
		_notebook_btn.tooltip_text = "Notebook unavailable during enemy resolution."


func _on_notification_requested(payload: Dictionary) -> void:
	# Show the latest non-modal notification body in the notification slot.
	var body: String = str(payload.get("body", ""))
	if _notification_label != null:
		_notification_label.text = body


# ---------------------------------------------------------------------------
# Lifecycle handlers (ported from pre-γ.4)
# ---------------------------------------------------------------------------

func _on_session_ended() -> void:
	_portrait_cache.clear()
	# Item 4 — flush widget cache too. The portraits HBox is rebuilt on the
	# next _refresh_party_portraits, but the dict reference can dangle past
	# session boundaries if a widget queue_free races the next refresh.
	_portrait_widgets.clear()


func _on_active_party_changed(_prev_id: String, new_id: String) -> void:
	_refresh_party_portraits(new_id)
	_refresh_party_status(new_id)


func _on_session_started(_campaign_id: String) -> void:
	_refresh_party_portraits(GameState.active_party_id)
	_refresh_party_status(GameState.active_party_id)


func _on_party_membership_changed(party_id: String, _character_id: String) -> void:
	if party_id == GameState.active_party_id:
		_refresh_party_portraits(party_id)
		_refresh_party_status(party_id)


func _on_day_changed(_d: int, _m: int, _y: int) -> void:
	_refresh_party_status(GameState.active_party_id)


func _on_inventory_changed(character_id: String) -> void:
	if not character_id.is_empty():
		_refresh_party_status(GameState.active_party_id)


func _on_party_roster_changed(party_id: String, _other_id: String) -> void:
	if party_id == GameState.active_party_id:
		_refresh_party_status(party_id)


func _on_party_member_levels_snapshot(levels: Dictionary) -> void:
	_party_levels = levels.duplicate()
	_apply_level_badges()


func _on_dungeon_focus_level_changed(level: int) -> void:
	_current_focus_level = level
	_apply_level_badges()


# ---------------------------------------------------------------------------
# Portrait click → cross-tab activation
# ---------------------------------------------------------------------------

func _on_portrait_pressed(character_id: String) -> void:
	if character_id.is_empty():
		return
	EventBus.notebook_active_entity_requested.emit(character_id)
	EventBus.party_portrait_clicked.emit(character_id)


## Apply level badges per the cached `_party_levels` snapshot. Each portrait
## widget either shows "L<level>" or hides the badge when no level data is
## available. On-focus levels (i.e., the dungeon level the camera is on)
## render the badge with a muted modulate so they don't draw the eye away
## from the active level. Item 4 — uses the H.0 PortraitWithBadge API.
func _apply_level_badges() -> void:
	for character_id in _portrait_widgets.keys():
		var widget: PortraitWithBadge = _portrait_widgets[character_id]
		if widget == null or not is_instance_valid(widget):
			continue
		if not _party_levels.has(character_id):
			widget.clear_badge()
			continue
		var lvl: int = int(_party_levels[character_id])
		widget.set_badge("L%d" % lvl, LEVEL_BADGE_COLOR)
		var on_focus := (lvl == _current_focus_level)
		widget.set_badge_modulate(LEVEL_BADGE_TINT_ON_FOCUS if on_focus
			else LEVEL_BADGE_TINT_OFF_FOCUS)


func _refresh_party_portraits(party_id: String) -> void:
	if _portraits_hbox == null:
		return
	for child in _portraits_hbox.get_children():
		child.queue_free()
	_portrait_widgets.clear()
	if party_id.is_empty():
		_portraits_hbox.visible = false
		return
	var rows: Array = CampaignRepository.list_party_characters(party_id)
	if rows.is_empty():
		_portraits_hbox.visible = false
		return
	_portraits_hbox.visible = true
	for row in rows:
		var character_id: String = str(row.get("id", ""))
		var portrait_id: String = str(row.get("portrait_id", ""))
		var texture: Texture2D = _resolve_portrait(portrait_id)
		var display_name: String = str(row.get("name", ""))

		# Item 4 — replaces the prior ~70-line inline builder
		# (PanelContainer + Button + TextureRect + Label) with the shared
		# component. PortraitWithBadge owns the slot chrome (border, corner
		# radius, padding) — the loose constants here only configure the
		# inner portrait area.
		var widget := PortraitWithBadgeScript.new()
		widget.set_portrait_size(PORTRAIT_SIZE)
		widget.set_texture(texture)
		widget.set_tooltip(display_name)
		widget.set_entity_id(character_id)
		# Forward the component's portrait_clicked into the existing
		# `_on_portrait_pressed` flow so cross-tab activation +
		# party_portrait_clicked emission continue unchanged.
		widget.portrait_clicked.connect(_on_portrait_pressed)
		widget.set_meta("character_id", character_id)
		_portraits_hbox.add_child(widget)
		if not character_id.is_empty():
			_portrait_widgets[character_id] = widget

	_apply_level_badges()


func _resolve_portrait(portrait_id: String) -> Texture2D:
	if portrait_id.is_empty():
		return null
	if _portrait_cache.has(portrait_id):
		return _portrait_cache[portrait_id]
	var texture: Texture2D = null
	var user_path := "user://portraits/%s.png" % portrait_id
	if FileAccess.file_exists(user_path):
		var img := Image.load_from_file(user_path)
		if img != null:
			texture = ImageTexture.create_from_image(img)
	if texture == null:
		var res_path := "res://assets/portraits/%s.png" % portrait_id
		if ResourceLoader.exists(res_path):
			texture = load(res_path) as Texture2D
	if texture != null:
		_portrait_cache[portrait_id] = texture
	return texture


# ---------------------------------------------------------------------------
# State / context handlers
# ---------------------------------------------------------------------------

func _on_state_changed(_from: int, _to: int) -> void:
	_update_visibility()
	_update_wilderness_buttons()
	_refresh_party_portraits(GameState.active_party_id)
	_refresh_party_status(GameState.active_party_id)
	_refresh_notebook_btn_state()


func _on_exploration_context_changed(_context: int) -> void:
	_update_wilderness_buttons()
	_refresh_party_status(GameState.active_party_id)
	if _context != GameState.ExplorationContext.DUNGEON:
		_party_levels.clear()
		_current_focus_level = -9999
		_apply_level_badges()


func _state_allows_visibility() -> bool:
	var state: int = GameState.current_state
	return state in [
		GameState.State.EXPLORATION,
		GameState.State.COMBAT,
		GameState.State.DOWNTIME,
		GameState.State.DOMAIN,
		GameState.State.PAUSED,
	]


func _update_visibility() -> void:
	if _bar == null:
		return
	_bar.visible = _state_allows_visibility()


func _update_wilderness_buttons() -> void:
	var show_buttons: bool = (
		GameState.current_state == GameState.State.EXPLORATION
		and GameState.exploration_context == GameState.ExplorationContext.WILDERNESS
	)
	if _camp_btn != null:
		_camp_btn.visible = show_buttons


func _on_hex_entered(hex_id: String) -> void:
	_location_label.text = "Hex %s" % hex_id


func _on_room_entered(room_id: String) -> void:
	_location_label.text = "Room %s" % room_id


func _on_settlement_entered(settlement_id: String, _district_id: String) -> void:
	_location_label.text = settlement_id.capitalize()


func _on_time_advanced(_rounds: int) -> void:
	_update_time_display()


# ---------------------------------------------------------------------------
# Update methods
# ---------------------------------------------------------------------------

func _update_time_display() -> void:
	var date := Timekeeping.get_date()
	var day: int = Timekeeping.get_total_days() + 1
	var hour: int = date["hour"]
	var minute: int = date["minute"]
	var second: int = date["round"] * 10
	var time_of_day := "Night"
	if hour >= 6 and hour < 12:
		time_of_day = "Morning"
	elif hour >= 12 and hour < 18:
		time_of_day = "Afternoon"
	elif hour >= 18 and hour < 21:
		time_of_day = "Evening"
	_time_label.text = "Day %d, %02d:%02d:%02d (%s)" % [day, hour, minute, second, time_of_day]


func _on_scheduler_paused(reason: String) -> void:
	if _pause_reason_label != null:
		_pause_reason_label.text = reason
		_time_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4, 1.0))
		var tween := create_tween()
		tween.tween_property(_time_label, "theme_override_colors/font_color",
			LABEL_COLOR, 1.0).set_delay(1.0)


func _on_scheduler_resumed() -> void:
	if _pause_reason_label != null:
		_pause_reason_label.text = ""


# ---------------------------------------------------------------------------
# Rations / travel speed sub-panels
# ---------------------------------------------------------------------------

func _refresh_party_status(party_id: String) -> void:
	if _rations_panel == null or _speeds_panel == null:
		return
	var show: bool = (
		GameState.current_state == GameState.State.EXPLORATION
		and GameState.exploration_context == GameState.ExplorationContext.WILDERNESS
	)
	if party_id.is_empty() or not show:
		_rations_panel.visible = false
		_speeds_panel.visible = false
		_encumbrance_label.text = "Enc: --"
		return

	var party_data: PartyData = CampaignRepository.load_party_data(party_id)
	if party_data == null:
		_rations_panel.visible = false
		_speeds_panel.visible = false
		_encumbrance_label.text = "Enc: --"
		return
	party_data.character_data = []
	for char_row: Dictionary in CampaignRepository.list_party_characters(party_id):
		party_data.character_data.append(CharacterData.from_dict(char_row))

	# Rations.
	var party_size: int = party_data.character_data.size()
	var consumption: int = CampManager.compute_ration_consumption(party_size)
	var days_left: int = party_data.rations_days_remaining
	_rations_label.text = "%d days  −%d/day" % [days_left, consumption]
	var ration_color: Color = LABEL_COLOR
	if consumption > 0:
		if days_left <= 1:
			ration_color = Color(0.90, 0.35, 0.30, 1.0)
		elif days_left <= 3:
			ration_color = Color(0.90, 0.75, 0.30, 1.0)
	_rations_label.add_theme_color_override("font_color", ration_color)
	_rations_panel.visible = true

	# Travel speeds.
	var base_speed: int = _compute_base_exploration_speed(party_data)
	_speeds_base_label.text = "Base: %d' / turn" % base_speed
	for terrain in TRAVEL_TERRAINS:
		var mpd: float = TravelSpeedCalculator.get_miles_per_day(
			party_data, terrain, false)
		var label: Label = _speed_labels[terrain]
		label.text = "%s: %d mi" % [TERRAIN_LABELS[terrain], int(mpd)]
	_speeds_panel.visible = true

	# Encumbrance: report the slowest member (mirrors the Party tab header).
	var slowest: int = party_data.get_slowest_movement()
	_encumbrance_label.text = "Slowest: %d'/turn" % slowest


func _compute_base_exploration_speed(party_data: PartyData) -> int:
	var result: Dictionary = TravelSpeedCalculator.calculate_party_speed(
		party_data, "clear", false)
	return int(result.get("base_exploration_speed", 0))


# ---------------------------------------------------------------------------
# Open Notebook button
# ---------------------------------------------------------------------------

func _on_notebook_btn_pressed() -> void:
	var pid: String = GameState.active_party_id
	var tab_id: String = NotebookState.DEFAULT_TAB
	if not pid.is_empty():
		tab_id = NotebookState.get_active_tab(pid)
	EventBus.notebook_open_requested.emit(tab_id)


func _refresh_notebook_btn_tooltip() -> void:
	if _notebook_btn == null:
		return
	var entries := [
		["notebook_toggle_character", "Character"],
		["notebook_toggle_inventory", "Inventory"],
		["notebook_toggle_party", "Party"],
		["notebook_toggle_henchmen", "Henchmen"],
		["notebook_toggle_troops", "Troops"],
		["notebook_toggle_domain", "Domain"],
		["notebook_toggle_journal", "Journal"],
		["notebook_toggle_quests", "Quests"],
	]
	var lines: Array[String] = ["Open Management Notebook"]
	for entry in entries:
		var key_label: String = _format_first_key_for_action(entry[0])
		if key_label.is_empty():
			continue
		lines.append("  %s — %s" % [key_label, entry[1]])
	_notebook_btn.tooltip_text = "\n".join(lines)


func _format_first_key_for_action(action_name: String) -> String:
	if not InputMap.has_action(action_name):
		return ""
	for ev in InputMap.action_get_events(action_name):
		if ev is InputEventKey:
			var ekey: InputEventKey = ev
			var keycode: int = ekey.physical_keycode if ekey.physical_keycode != 0 else ekey.keycode
			if keycode != 0:
				return OS.get_keycode_string(keycode)
	return ""
