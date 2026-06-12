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
const LOCKED_COLOR := Color(0.40, 0.36, 0.30, 1.0)   # Dimmed for clock lock
const FONT_SIZE := 11
const BTN_MIN_WIDTH := 32

var _buttons: Array[Button] = []
var _speed_map: Array[int] = []  # parallel to _buttons: speed value per button
var _current_speed: int = 0  # SchedulerLoop.SPEED_PAUSED
var _last_nonpause_speed: int = 1  # For toggle-pause resume
## Focus-coupled clock (Option 1 ruling 2026-06-12): while a party is in a
## dungeon, time advances only on the dungeon layer. Non-empty = the non-pause
## buttons are disabled and the reason shows as their tooltip.
var _lock_reason: String = ""


func _ready() -> void:
	add_theme_constant_override("separation", 2)
	_build_buttons()
	EventBus.scheduler_speed_changed.connect(_on_speed_changed)
	EventBus.clock_lock_changed.connect(_on_clock_lock_changed)
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


## Disable/enable the non-pause buttons per the focus-coupled clock lock.
## Pause stays enabled (pausing is always allowed). SessionRunner remains the
## authoritative gate — this is presentation; keyboard requests that slip
## through are refused (with a toast) by SessionRunner._on_clock_speed_requested.
func _on_clock_lock_changed(reason: String) -> void:
	_lock_reason = reason
	for i in range(_buttons.size()):
		var btn: Button = _buttons[i]
		if _speed_map[i] == SchedulerLoop.SPEED_PAUSED:
			continue
		btn.disabled = not reason.is_empty()
		btn.tooltip_text = reason if not reason.is_empty() else _default_tooltip(i)
	_highlight_active()


func _default_tooltip(index: int) -> String:
	match _speed_map[index]:
		SchedulerLoop.SPEED_NORMAL: return "Normal speed (1)"
		SchedulerLoop.SPEED_FAST: return "Fast (2)"
		SchedulerLoop.SPEED_VERY_FAST: return "Very fast (3)"
		SchedulerLoop.SPEED_MAX: return "Max speed (4)"
	return "Pause (Space)"


func _highlight_active() -> void:
	for i in range(_buttons.size()):
		var btn: Button = _buttons[i]
		var spd: int = _speed_map[i]
		if btn.disabled:
			btn.add_theme_color_override("font_color", LOCKED_COLOR)
		elif spd == _current_speed:
			if spd == SchedulerLoop.SPEED_PAUSED:
				btn.add_theme_color_override("font_color", PAUSED_COLOR)
			else:
				btn.add_theme_color_override("font_color", ACTIVE_COLOR)
		else:
			btn.add_theme_color_override("font_color", INACTIVE_COLOR)
