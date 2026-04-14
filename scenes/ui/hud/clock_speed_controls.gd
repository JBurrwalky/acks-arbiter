class_name ClockSpeedControls
extends HBoxContainer

## Clock speed control widget for the session status bar.
##
## Five buttons: Pause (||) / 1x (>) / 2x (>>) / 5x (>>>) / Max (>>>>)
## Emits EventBus.clock_speed_requested when a button is pressed.
## Listens to EventBus.scheduler_speed_changed to sync visual state.
##
## Keyboard shortcuts:
##   Space     — toggle pause / resume at last non-pause speed
##   1         — 1x (normal)
##   2         — 2x (fast)
##   3         — 5x (very fast)
##   4         — Max (instant)

const ACTIVE_COLOR := Color(0.95, 0.85, 0.55, 1.0)  # Gold highlight
const INACTIVE_COLOR := Color(0.55, 0.50, 0.42, 1.0)
const PAUSED_COLOR := Color(0.85, 0.35, 0.30, 1.0)   # Red-ish for pause
const FONT_SIZE := 11
const BTN_MIN_WIDTH := 32

var _buttons: Array[Button] = []
var _speed_map: Array[int] = []  # parallel to _buttons: speed value per button
var _current_speed: int = 0  # SchedulerLoop.SPEED_PAUSED
var _last_nonpause_speed: int = 1  # For toggle-pause resume


func _ready() -> void:
	add_theme_constant_override("separation", 2)
	_build_buttons()
	EventBus.scheduler_speed_changed.connect(_on_speed_changed)
	_highlight_active()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if not visible:
		return

	var key: Key = (event as InputEventKey).keycode if event is InputEventKey else KEY_NONE
	match key:
		KEY_SPACE:
			_toggle_pause()
			get_viewport().set_input_as_handled()
		KEY_1:
			_request_speed(SchedulerLoop.SPEED_NORMAL)
			get_viewport().set_input_as_handled()
		KEY_2:
			_request_speed(SchedulerLoop.SPEED_FAST)
			get_viewport().set_input_as_handled()
		KEY_3:
			_request_speed(SchedulerLoop.SPEED_VERY_FAST)
			get_viewport().set_input_as_handled()
		KEY_4:
			_request_speed(SchedulerLoop.SPEED_MAX)
			get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_buttons() -> void:
	var defs := [
		{"label": "||",   "speed": SchedulerLoop.SPEED_PAUSED,    "tooltip": "Pause (Space)"},
		{"label": ">",    "speed": SchedulerLoop.SPEED_NORMAL,    "tooltip": "Normal speed (1)"},
		{"label": ">>",   "speed": SchedulerLoop.SPEED_FAST,      "tooltip": "Fast (2)"},
		{"label": ">>>",  "speed": SchedulerLoop.SPEED_VERY_FAST, "tooltip": "Very fast (3)"},
		{"label": ">>>>", "speed": SchedulerLoop.SPEED_MAX,       "tooltip": "Max speed (4)"},
	]
	for def in defs:
		var btn := Button.new()
		btn.text = def["label"]
		btn.tooltip_text = def["tooltip"]
		btn.flat = true
		btn.add_theme_font_size_override("font_size", FONT_SIZE)
		btn.custom_minimum_size = Vector2(BTN_MIN_WIDTH, 0)
		var spd: int = def["speed"]
		btn.pressed.connect(func(): _request_speed(spd))
		add_child(btn)
		_buttons.append(btn)
		_speed_map.append(spd)


# ---------------------------------------------------------------------------
# Speed requests
# ---------------------------------------------------------------------------

func _request_speed(speed: int) -> void:
	if speed != SchedulerLoop.SPEED_PAUSED:
		_last_nonpause_speed = speed
	EventBus.clock_speed_requested.emit(speed)


func _toggle_pause() -> void:
	if _current_speed == SchedulerLoop.SPEED_PAUSED:
		_request_speed(_last_nonpause_speed)
	else:
		_request_speed(SchedulerLoop.SPEED_PAUSED)


# ---------------------------------------------------------------------------
# Visual state sync
# ---------------------------------------------------------------------------

func _on_speed_changed(new_speed: int) -> void:
	_current_speed = new_speed
	if new_speed != SchedulerLoop.SPEED_PAUSED:
		_last_nonpause_speed = new_speed
	_highlight_active()


func _highlight_active() -> void:
	for i in range(_buttons.size()):
		var btn: Button = _buttons[i]
		var spd: int = _speed_map[i]
		if spd == _current_speed:
			if spd == SchedulerLoop.SPEED_PAUSED:
				btn.add_theme_color_override("font_color", PAUSED_COLOR)
			else:
				btn.add_theme_color_override("font_color", ACTIVE_COLOR)
		else:
			btn.add_theme_color_override("font_color", INACTIVE_COLOR)
