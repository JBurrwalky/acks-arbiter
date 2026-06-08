class_name PauseMenuOverlay
extends CanvasLayer

## Pause menu overlay — Resume / Save / Load / Settings / Quit.
##
## Toggled via Escape key. Uses GameState.pause() / resume().

const HEADING_COLOR := Color(0.95, 0.90, 0.78, 1.0)
const LABEL_COLOR := Color(0.85, 0.80, 0.70, 1.0)
const BUTTON_WIDTH := 200
const BUTTON_HEIGHT := 40

var _backdrop: ColorRect = null
var _panel: PanelContainer = null
var _confirm_dialog: ConfirmationPrompt = null


func _ready() -> void:
	layer = 160
	_build_ui()
	_backdrop.visible = false
	_panel.visible = false
	GameState.state_changed.connect(_on_state_changed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_toggle_pause()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# Pause toggle
# ---------------------------------------------------------------------------

func _toggle_pause() -> void:
	if GameState.current_state == GameState.State.PAUSED:
		_hide()
		GameState.resume()
		# Resume the scheduler if it was running before the menu opened.
		EventBus.scheduler_resumed.emit()
	elif GameState.current_state in [
		GameState.State.EXPLORATION,
		GameState.State.COMBAT,
		GameState.State.DOWNTIME,
		GameState.State.DOMAIN,
	]:
		# Pause the scheduler along with the game state.
		EventBus.clock_speed_requested.emit(SchedulerLoop.SPEED_PAUSED)
		GameState.pause()
		_show()


func _show() -> void:
	_backdrop.visible = true
	_panel.visible = true


func _hide() -> void:
	_backdrop.visible = false
	_panel.visible = false


func _on_state_changed(_from: int, to: int) -> void:
	if to != GameState.State.PAUSED:
		_hide()


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	_backdrop = ColorRect.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = Color(0.0, 0.0, 0.0, 0.6)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_backdrop)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(280, 320)
	_panel.offset_left = -140
	_panel.offset_right = 140
	_panel.offset_top = -160
	_panel.offset_bottom = 160
	UiSurfaceStyles.apply_framed_window_chrome(_panel)
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Paused"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", HEADING_COLOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", UiSurfaceStyles.FRAME_BORDER_COLOR)
	vbox.add_child(sep)

	_add_button(vbox, "Resume", _on_resume)
	_add_button(vbox, "Save", _on_save)
	_add_button(vbox, "Save / Load…", _on_save_load)
	_add_button(vbox, "Settings", _on_settings)
	_add_button(vbox, "Quit to Menu", _on_quit)

	# Confirmation dialog (child, reusable).
	_confirm_dialog = ConfirmationPrompt.new()
	add_child(_confirm_dialog)


func _add_button(parent: Control, text: String, callback: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 15)
	btn.add_theme_color_override("font_color", LABEL_COLOR)
	btn.custom_minimum_size = Vector2(BUTTON_WIDTH, BUTTON_HEIGHT)
	btn.pressed.connect(callback)
	parent.add_child(btn)


# ---------------------------------------------------------------------------
# Button handlers
# ---------------------------------------------------------------------------

func _on_resume() -> void:
	_hide()
	GameState.resume()
	# Scheduler remains in whatever speed state it was in before the menu.
	# The player uses the clock speed controls to unpause the scheduler.


func _on_save() -> void:
	# Find SessionRunner and call save.
	var main := get_parent()
	if main:
		var runner := main.get_node_or_null("SessionRunner")
		if runner and runner.has_method("save_session"):
			# Saving during combat is disallowed (gdd-savegame-system.md §5.7) —
			# surface a message rather than silently no-op inside save_session().
			if runner.has_method("is_in_combat") and runner.is_in_combat():
				EventBus.notification_requested.emit({
					"type": "warning",
					"category": "system",
					"title": "Cannot Save During Combat",
					"duration": 3.0,
				})
				return
			runner.save_session()
			EventBus.notification_requested.emit({
				"type": "success",
				"category": "system",
				"title": "Game Saved",
				"duration": 3.0,
			})


func _on_save_load() -> void:
	# Open the unified Save/Load slot panel (Phase S-3). It overlays the pause
	# menu and is freed on close; loading a slot tears the session down and
	# re-enters via the context-aware loader.
	var main := get_parent()
	if main == null:
		return
	var runner := main.get_node_or_null("SessionRunner")
	if runner == null:
		return
	var panel = preload("res://scenes/ui/saveload/save_load_panel.gd").new()
	panel.setup(runner)
	main.add_child(panel)


func _on_settings() -> void:
	# Push settings screen onto nav stack.
	if NavigationStack.instance != null:
		NavigationStack.instance.push("res://scenes/ui/settings/settings_screen.tscn")
	_hide()
	GameState.resume()


func _on_quit() -> void:
	_confirm_dialog.show_prompt(
		"Quit to Main Menu?",
		"Make sure you have saved your progress.",
		func():
			_hide()
			GameState.end_session(),
		Callable(),
		false
	)
