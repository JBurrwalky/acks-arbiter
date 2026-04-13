class_name ConfirmationPrompt
extends CanvasLayer

## Reusable modal confirmation dialog with vellum styling.
##
## Usage:
##   var dialog = ConfirmationPrompt.new()
##   add_child(dialog)
##   dialog.show_prompt("Leave Settlement?",
##       "You have 340 XP in the adventure pool that has not been banked.",
##       func(): _exit_settlement(),
##       Callable(),
##       true)  # danger = true shows red confirm button with delay

signal confirmed
signal cancelled

const PANEL_WIDTH := 440
const PANEL_MIN_HEIGHT := 180
const HEADING_COLOR := Color(0.95, 0.90, 0.78, 1.0)
const BODY_COLOR := Color(0.85, 0.80, 0.70, 1.0)
const DANGER_COLOR := Color(0.75, 0.22, 0.18, 1.0)
const BUTTON_DELAY := 2.0  # Seconds before danger confirm button is clickable.

var _backdrop: ColorRect = null
var _panel: PanelContainer = null
var _title_label: Label = null
var _body_label: Label = null
var _confirm_btn: Button = null
var _cancel_btn: Button = null
var _on_confirm: Callable = Callable()
var _on_cancel: Callable = Callable()
var _danger_timer: SceneTreeTimer = null


func _ready() -> void:
	layer = 180
	_build_ui()
	_hide_all()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func show_prompt(title: String, body: String,
		on_confirm: Callable = Callable(),
		on_cancel: Callable = Callable(),
		danger: bool = false) -> void:
	_on_confirm = on_confirm
	_on_cancel = on_cancel

	_title_label.text = title
	_body_label.text = body
	_body_label.visible = not body.is_empty()

	if danger:
		_confirm_btn.add_theme_color_override("font_color", DANGER_COLOR)
		_confirm_btn.disabled = true
		_confirm_btn.text = "Confirm (2s)"
		_danger_timer = get_tree().create_timer(BUTTON_DELAY)
		_danger_timer.timeout.connect(func():
			_confirm_btn.disabled = false
			_confirm_btn.text = "Confirm"
		)
	else:
		_confirm_btn.add_theme_color_override("font_color", HEADING_COLOR)
		_confirm_btn.disabled = false
		_confirm_btn.text = "Confirm"

	_show_all()


func hide_prompt() -> void:
	_hide_all()


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	_backdrop = ColorRect.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = Color(0.0, 0.0, 0.0, 0.5)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_backdrop)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_MIN_HEIGHT)
	_panel.offset_left = -PANEL_WIDTH / 2
	_panel.offset_right = PANEL_WIDTH / 2
	_panel.offset_top = -PANEL_MIN_HEIGHT / 2
	_panel.offset_bottom = PANEL_MIN_HEIGHT / 2
	UiSurfaceStyles.apply_framed_window_chrome(_panel)
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 16)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 18)
	_title_label.add_theme_color_override("font_color", HEADING_COLOR)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title_label)

	_body_label = Label.new()
	_body_label.add_theme_font_size_override("font_size", 13)
	_body_label.add_theme_color_override("font_color", BODY_COLOR)
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_body_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	var btn_bar := HBoxContainer.new()
	btn_bar.add_theme_constant_override("separation", 16)
	btn_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_bar)

	_cancel_btn = Button.new()
	_cancel_btn.text = "Cancel"
	_cancel_btn.add_theme_font_size_override("font_size", 14)
	_cancel_btn.custom_minimum_size = Vector2(100, 36)
	_cancel_btn.pressed.connect(_on_cancel_pressed)
	btn_bar.add_child(_cancel_btn)

	_confirm_btn = Button.new()
	_confirm_btn.text = "Confirm"
	_confirm_btn.add_theme_font_size_override("font_size", 14)
	_confirm_btn.custom_minimum_size = Vector2(100, 36)
	_confirm_btn.pressed.connect(_on_confirm_pressed)
	btn_bar.add_child(_confirm_btn)


# ---------------------------------------------------------------------------
# Handlers
# ---------------------------------------------------------------------------

func _on_confirm_pressed() -> void:
	_hide_all()
	confirmed.emit()
	if _on_confirm.is_valid():
		_on_confirm.call()


func _on_cancel_pressed() -> void:
	_hide_all()
	cancelled.emit()
	if _on_cancel.is_valid():
		_on_cancel.call()


func _show_all() -> void:
	_backdrop.visible = true
	_panel.visible = true


func _hide_all() -> void:
	_backdrop.visible = false
	_panel.visible = false
