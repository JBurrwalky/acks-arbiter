class_name SessionStatusBar
extends CanvasLayer

## Persistent bottom status bar showing party state at a glance.
##
## Widgets: party indicator | location | time | day budget | adventure pool |
##          party member chips | movement mode | light source
##
## Hidden during MAIN_MENU and CHARACTER_CREATION states.
## Visible during EXPLORATION, COMBAT, DOWNTIME, DOMAIN.

const BAR_HEIGHT := 48
const FONT_SIZE := 12
const LABEL_COLOR := Color(0.85, 0.80, 0.70, 1.0)
const DIM_COLOR := Color(0.55, 0.50, 0.42, 1.0)
const BG_COLOR := Color(0.08, 0.06, 0.04, 0.95)
const BORDER_COLOR := Color(0.46, 0.33, 0.19, 1.0)

var _bar: PanelContainer = null
var _location_label: Label = null
var _time_label: Label = null
var _speed_controls: ClockSpeedControls = null
var _pause_reason_label: Label = null
var _camp_btn: Button = null
var _plan_day_btn: Button = null


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
	_time_label.custom_minimum_size = Vector2(160, 0)
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

	# Spacer to push action buttons right.
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

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

	_plan_day_btn = Button.new()
	_plan_day_btn.text = "Plan Day"
	_plan_day_btn.flat = true
	_plan_day_btn.add_theme_font_size_override("font_size", FONT_SIZE)
	_plan_day_btn.add_theme_color_override("font_color", LABEL_COLOR)
	_plan_day_btn.custom_minimum_size = Vector2(65, 0)
	_plan_day_btn.pressed.connect(func(): EventBus.day_declaration_requested.emit())
	_plan_day_btn.visible = false
	hbox.add_child(_plan_day_btn)


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


func _on_state_changed(_from: int, _to: int) -> void:
	_update_visibility()
	_update_wilderness_buttons()


func _on_exploration_context_changed(_context: int) -> void:
	_update_wilderness_buttons()


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
	_plan_day_btn.visible = show_buttons


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
	var day: int = Timekeeping.get_total_days() + 1
	var hour: int = Timekeeping.get_time_of_day()
	var time_of_day := "Night"
	if hour >= 6 and hour < 12:
		time_of_day = "Morning"
	elif hour >= 12 and hour < 18:
		time_of_day = "Afternoon"
	elif hour >= 18 and hour < 21:
		time_of_day = "Evening"
	_time_label.text = "Day %d, %02d:00 (%s)" % [day, hour, time_of_day]


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


