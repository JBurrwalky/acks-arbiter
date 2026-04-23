class_name SessionStatusBar
extends CanvasLayer

## Persistent bottom status bar showing party state at a glance.
##
## Widgets: party indicator | location | time | day budget | adventure pool |
##          party member chips | movement mode | light source
##
## Hidden during MAIN_MENU and CHARACTER_CREATION states.
## Visible during EXPLORATION, COMBAT, DOWNTIME, DOMAIN.

const BAR_HEIGHT := 72  # 56 portrait + 8 padding top/bottom
const FONT_SIZE := 12
const SMALL_FONT_SIZE := 10
const PORTRAIT_SIZE := Vector2(56, 56)
const LABEL_COLOR := Color(0.85, 0.80, 0.70, 1.0)
const DIM_COLOR := Color(0.55, 0.50, 0.42, 1.0)
const BG_COLOR := Color(0.08, 0.06, 0.04, 0.95)
const BORDER_COLOR := Color(0.46, 0.33, 0.19, 1.0)
const SUBPANEL_BG := Color(0.13, 0.10, 0.07, 0.85)

## Terrain categories shown in the travel-speed panel, in display order.
const TRAVEL_TERRAINS := ["clear", "woods", "hills", "desert",
	"jungle", "swamp", "mountains"]

## Short display labels for the travel-speed grid cells.
const TERRAIN_LABELS := {
	"clear": "Clear",
	"woods": "Woods",
	"hills": "Hills",
	"desert": "Desert",
	"jungle": "Jungle",
	"swamp": "Swamp",
	"mountains": "Mtns",
}

var _bar: PanelContainer = null
var _location_label: Label = null
var _time_label: Label = null
var _speed_controls: ClockSpeedControls = null
var _pause_reason_label: Label = null
var _camp_btn: Button = null
var _portraits_hbox: HBoxContainer = null
var _rations_panel: PanelContainer = null
var _rations_label: Label = null
var _speeds_panel: PanelContainer = null
var _speeds_base_label: Label = null
var _speeds_grid: GridContainer = null
## movement_cost_category -> Label for the miles/day value.
var _speed_labels: Dictionary = {}

## portrait_id -> Texture2D. Avoids decoding user-portrait PNGs every refresh.
static var _portrait_cache: Dictionary = {}

## character_id -> level (int). Populated from party_member_levels_snapshot.
## Used to show the per-portrait level badge. Empty dict ⇒ no badges shown.
var _party_levels: Dictionary = {}

## Last known dungeon focus level from dungeon_focus_level_changed. Determines
## whether each portrait's badge is muted (on focus) or bright (off focus).
var _current_focus_level: int = -9999

## character_id -> Label (the level badge node). Populated by
## _refresh_party_portraits().
var _portrait_badges: Dictionary = {}


func _ready() -> void:
	layer = 80
	_build_ui()
	_connect_signals()
	_update_visibility()


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	_bar = PanelContainer.new()
	_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bar.offset_top = -BAR_HEIGHT
	_bar.offset_bottom = 0

	var style := StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	style.border_color = BORDER_COLOR
	style.border_width_top = 1
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	_bar.add_theme_stylebox_override("panel", style)
	add_child(_bar)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_bar.add_child(hbox)

	# Location.
	_location_label = _make_label("--", LABEL_COLOR, FONT_SIZE)
	_location_label.custom_minimum_size = Vector2(100, 0)
	hbox.add_child(_location_label)

	hbox.add_child(_vsep())

	# Time.
	_time_label = _make_label("Day 1", LABEL_COLOR, FONT_SIZE)
	_time_label.custom_minimum_size = Vector2(220, 0)
	hbox.add_child(_time_label)

	hbox.add_child(_vsep())

	# Clock speed controls.
	_speed_controls = ClockSpeedControls.new()
	hbox.add_child(_speed_controls)

	# Auto-pause reason (shown briefly when scheduler pauses on an event).
	_pause_reason_label = _make_label("", DIM_COLOR, FONT_SIZE)
	_pause_reason_label.custom_minimum_size = Vector2(0, 0)
	_pause_reason_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hbox.add_child(_pause_reason_label)

	hbox.add_child(_vsep())

	# Left spacer: takes half the slack so portraits appear centered in the bar.
	var spacer_left := Control.new()
	spacer_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer_left)

	# Party-member portrait strip (populated on active_party_changed).
	_portraits_hbox = HBoxContainer.new()
	_portraits_hbox.add_theme_constant_override("separation", 4)
	_portraits_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(_portraits_hbox)

	# Right spacer: balances the left spacer so portraits stay centered.
	var spacer_right := Control.new()
	spacer_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer_right)

	# Rations sub-panel (wilderness only).
	_rations_panel = _build_rations_panel()
	hbox.add_child(_rations_panel)

	# Travel speeds sub-panel (wilderness only).
	_speeds_panel = _build_speeds_panel()
	hbox.add_child(_speeds_panel)

	# Wilderness action buttons (hidden outside wilderness exploration).
	_camp_btn = Button.new()
	_camp_btn.text = "Camp"
	_camp_btn.flat = true
	_camp_btn.add_theme_font_size_override("font_size", FONT_SIZE)
	_camp_btn.add_theme_color_override("font_color", LABEL_COLOR)
	_camp_btn.custom_minimum_size = Vector2(50, 0)
	_camp_btn.pressed.connect(func(): EventBus.camp_requested.emit())
	_camp_btn.visible = false
	hbox.add_child(_camp_btn)


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
	_rations_label.custom_minimum_size = Vector2(90, 0)
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

	# 7 terrains in a 4-col grid → 2 rows (4 + 3).
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


func _vsep() -> VSeparator:
	var sep := VSeparator.new()
	sep.add_theme_constant_override("separation", 1)
	sep.add_theme_color_override("separator", Color(0.35, 0.30, 0.22, 0.5))
	return sep


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
	# `start_session` assigns active_party_id directly without emitting
	# active_party_changed, so we also refresh on session_started and when
	# members join/leave the active party.
	GameState.session_started.connect(_on_session_started)
	EventBus.party_member_joined.connect(_on_party_membership_changed)
	EventBus.party_member_left.connect(_on_party_membership_changed)
	# Rations / speeds refresh triggers.
	Timekeeping.day_changed.connect(_on_day_changed)
	EventBus.inventory_updated.connect(_on_inventory_changed)
	EventBus.creature_added.connect(_on_party_roster_changed)
	EventBus.creature_removed.connect(_on_party_roster_changed)
	EventBus.vehicle_changed.connect(_on_party_roster_changed)
	# Session 8 level badge wiring.
	EventBus.party_member_levels_snapshot.connect(_on_party_member_levels_snapshot)
	EventBus.dungeon_focus_level_changed.connect(_on_dungeon_focus_level_changed)
	_refresh_party_portraits(GameState.active_party_id)
	_refresh_party_status(GameState.active_party_id)


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
	# Encumbrance change could shift travel speed. Refresh unconditionally —
	# cheap enough vs. resolving character_id → party_id.
	if not character_id.is_empty():
		_refresh_party_status(GameState.active_party_id)


func _on_party_roster_changed(party_id: String, _other_id: String) -> void:
	if party_id == GameState.active_party_id:
		_refresh_party_status(party_id)


## EventBus.party_member_levels_snapshot handler — the dungeon renderer emits
## this whenever party positions refresh. An empty snapshot clears badges.
func _on_party_member_levels_snapshot(levels: Dictionary) -> void:
	_party_levels = levels.duplicate()
	_apply_level_badges()


## EventBus.dungeon_focus_level_changed handler — restyles badges so the
## member on the focus level is muted (they're already "here").
func _on_dungeon_focus_level_changed(level: int) -> void:
	_current_focus_level = level
	_apply_level_badges()


## Portrait button handler — emits party_portrait_clicked. The dungeon renderer
## listens, resolves the voxel position, and focuses + selects.
func _on_portrait_pressed(character_id: String) -> void:
	EventBus.party_portrait_clicked.emit(character_id)


## Applies level text + visibility + muted/bright tint to all portrait badges
## based on the current _party_levels snapshot and _current_focus_level.
func _apply_level_badges() -> void:
	for character_id in _portrait_badges.keys():
		var badge: Label = _portrait_badges[character_id]
		if badge == null:
			continue
		if not _party_levels.has(character_id):
			badge.visible = false
			continue
		var lvl: int = int(_party_levels[character_id])
		badge.visible = true
		badge.text = "L%d" % lvl
		var on_focus := (lvl == _current_focus_level)
		badge.modulate = Color(0.55, 0.52, 0.40, 1.0) if on_focus else Color(1.0, 0.95, 0.55, 1.0)


## Rebuilds the party-member portrait strip. Silently hides the strip if the
## party has no members or the party id is empty (e.g. pre-session).
func _refresh_party_portraits(party_id: String) -> void:
	if _portraits_hbox == null:
		return
	for child in _portraits_hbox.get_children():
		child.queue_free()
	_portrait_badges.clear()
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

		var btn := Button.new()
		btn.flat = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = PORTRAIT_SIZE
		btn.tooltip_text = display_name
		if not character_id.is_empty():
			btn.pressed.connect(_on_portrait_pressed.bind(character_id))
		btn.set_meta("character_id", character_id)

		var tr := TextureRect.new()
		tr.custom_minimum_size = PORTRAIT_SIZE
		tr.size = PORTRAIT_SIZE
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.texture = texture
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		btn.add_child(tr)

		var badge := Label.new()
		badge.name = "LevelBadge"
		badge.text = ""
		badge.visible = false
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_theme_color_override("font_color", Color(1.0, 0.92, 0.45, 1.0))
		badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		badge.add_theme_constant_override("outline_size", 3)
		badge.add_theme_font_size_override("font_size", SMALL_FONT_SIZE)
		badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		badge.offset_left = -24
		badge.offset_right = -2
		badge.offset_top = 1
		badge.offset_bottom = 14
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		btn.add_child(badge)

		_portraits_hbox.add_child(btn)
		if not character_id.is_empty():
			_portrait_badges[character_id] = badge

	_apply_level_badges()


## Resolves a portrait texture by id. Shipped portraits live under
## res://assets/portraits; user-added portraits under user://portraits.
## Returns null if neither file exists — the TextureRect simply renders blank.
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


func _on_state_changed(_from: int, _to: int) -> void:
	_update_visibility()
	_update_wilderness_buttons()
	# Covers returning to EXPLORATION from dungeon/combat where the active
	# party may have changed while we were hidden.
	_refresh_party_portraits(GameState.active_party_id)
	_refresh_party_status(GameState.active_party_id)


func _on_exploration_context_changed(_context: int) -> void:
	_update_wilderness_buttons()
	_refresh_party_status(GameState.active_party_id)
	# Clear dungeon level badges when leaving dungeon context.
	if _context != GameState.ExplorationContext.DUNGEON:
		_party_levels.clear()
		_current_focus_level = -9999
		_apply_level_badges()


func _update_visibility() -> void:
	var state: int = GameState.current_state
	_bar.visible = state in [
		GameState.State.EXPLORATION,
		GameState.State.COMBAT,
		GameState.State.DOWNTIME,
		GameState.State.DOMAIN,
		GameState.State.PAUSED,
	]


func _update_wilderness_buttons() -> void:
	var show_buttons: bool = (
		GameState.current_state == GameState.State.EXPLORATION
		and GameState.exploration_context == GameState.ExplorationContext.WILDERNESS
	)
	_camp_btn.visible = show_buttons
	# Rations/speeds panel visibility is managed by `_refresh_party_status`,
	# which runs right after this in every caller that cares.


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
	var second: int = date["round"] * 10  # each round = 10 seconds
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
		# Flash the time label to draw attention.
		_time_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4, 1.0))
		# Create a tween to fade back to normal after 2 seconds.
		var tween := create_tween()
		tween.tween_property(_time_label, "theme_override_colors/font_color",
			LABEL_COLOR, 1.0).set_delay(1.0)


func _on_scheduler_resumed() -> void:
	if _pause_reason_label != null:
		_pause_reason_label.text = ""


# ---------------------------------------------------------------------------
# Rations / travel speed sub-panels
# ---------------------------------------------------------------------------

## Refreshes the rations and travel-speeds panels for the given party. Hides
## the panels when there is no party loaded or the state isn't wilderness.
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
		return

	var party_data: PartyData = CampaignRepository.load_party_data(party_id)
	if party_data == null:
		_rations_panel.visible = false
		_speeds_panel.visible = false
		return
	# `load_party_data` returns a bare PartyData; populate characters the way
	# SessionRunner does so TravelSpeedCalculator sees the real roster.
	party_data.character_data = []
	for char_row: Dictionary in CampaignRepository.list_party_characters(party_id):
		party_data.character_data.append(CharacterData.from_dict(char_row))

	# Rations.
	var party_size: int = party_data.character_data.size()
	var consumption: int = CampManager.compute_ration_consumption(party_size)
	var days_left: int = party_data.rations_days_remaining
	_rations_label.text = "%d days\n−%d/day" % [days_left, consumption]
	# Color-warn when rations are nearly exhausted.
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


## Derives the party's base exploration speed (ft/turn) by asking the travel
## calculator with a "clear" terrain — `base_exploration_speed` is unaffected
## by terrain multiplier, so any land terrain returns the same figure.
func _compute_base_exploration_speed(party_data: PartyData) -> int:
	var result: Dictionary = TravelSpeedCalculator.calculate_party_speed(
		party_data, "clear", false)
	return int(result.get("base_exploration_speed", 0))


