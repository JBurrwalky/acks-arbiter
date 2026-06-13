class_name AbandonVehiclePrompt
extends CanvasLayer

## Modal shown when the party tries to travel with one or more unhitched (immobile)
## vehicles. The player must choose to leave them behind or cancel the journey.
##
## "Leave Behind" parks each cart + its cargo at the current hex as a conspicuous
## (non-hidden) wilderness cache — recoverable, but at heavy raid risk. See
## VehicleAbandonmentService. "Cancel Travel" aborts the move so the player can
## hitch a team first.
##
## Usage (mirrors EncounterDecisionPrompt):
##   var prompt := AbandonVehiclePrompt.new()
##   add_child(prompt)
##   prompt.decided.connect(_on_decided, CONNECT_ONE_SHOT)
##   prompt.open(["Ox Cart", "Wagon"])
##   # choice is "leave_behind" | "cancel"

signal decided(choice: String)

const CHOICE_LEAVE := "leave_behind"
const CHOICE_CANCEL := "cancel"

const PANEL_WIDTH := 480
const PANEL_MIN_HEIGHT := 240
const HEADING_COLOR := Color(0.95, 0.90, 0.78, 1.0)
const BODY_COLOR := Color(0.85, 0.80, 0.70, 1.0)

var _backdrop: ColorRect = null
var _panel: PanelContainer = null
var _title_label: Label = null
var _body_label: Label = null
var _btn_bar: HBoxContainer = null


func _ready() -> void:
	layer = 180
	_build_ui()
	_hide_all()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Open the prompt for the given unhitched vehicle names. Emits decided(choice).
func open(vehicle_names: Array) -> void:
	_title_label.text = "Unhitched Vehicle" + ("s" if vehicle_names.size() != 1 else "")
	_body_label.text = body_text(vehicle_names)
	_show_all()


func close() -> void:
	_hide_all()


## Body copy describing the consequence. Pure/static so it is unit-testable
## without a SceneTree.
static func body_text(vehicle_names: Array) -> String:
	var listed := ", ".join(vehicle_names) if not vehicle_names.is_empty() else "A vehicle"
	return ("%s cannot move without a hitched team. Leave it behind and it stays at "
		+ "this hex with its cargo — recoverable, but in plain sight and at heavy "
		+ "risk of being raided. Or cancel and hitch a team first.") % listed


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
	_title_label.add_theme_font_size_override("font_size", 20)
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

	_btn_bar = HBoxContainer.new()
	_btn_bar.add_theme_constant_override("separation", 12)
	_btn_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(_btn_bar)

	_add_button("Leave Behind", CHOICE_LEAVE)
	_add_button("Cancel Travel", CHOICE_CANCEL)


func _add_button(text: String, choice: String) -> void:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 14)
	btn.custom_minimum_size = Vector2(140, 36)
	btn.pressed.connect(_on_button_pressed.bind(choice))
	_btn_bar.add_child(btn)


# ---------------------------------------------------------------------------
# Handlers
# ---------------------------------------------------------------------------

func _on_button_pressed(choice: String) -> void:
	_hide_all()
	decided.emit(choice)


func _show_all() -> void:
	_backdrop.visible = true
	_panel.visible = true


func _hide_all() -> void:
	_backdrop.visible = false
	_panel.visible = false
