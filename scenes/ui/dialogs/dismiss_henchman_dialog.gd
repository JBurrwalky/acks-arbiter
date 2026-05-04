class_name DismissHenchmanDialog
extends CanvasLayer

## Phase 4 of the henchman closure plan: state-rich dismissal modal
## per gdd-henchmen-tab.md §7.2. ConfirmationPrompt's title/body/buttons
## contract is not a fit for multi-checkbox + slider input — this dialog
## is a dedicated surface following the gdd-ui-architecture.md §2.3 modal
## pattern (layer 100-199, full-screen backdrop, vellum styling).
##
## Usage:
##   var dialog := DismissHenchmanDialog.new()
##   add_child(dialog)
##   dialog.show_dialog(character_id, settlement_id, party_id,
##       on_confirm = func(opts): _do_dismiss(character_id, opts),
##       on_cancel  = func(): _close())

signal confirmed(options: Dictionary)
signal cancelled

const PANEL_WIDTH := 540
const HEADING_COLOR := Color(0.95, 0.90, 0.78, 1.0)
const BODY_COLOR := Color(0.85, 0.80, 0.70, 1.0)
const DANGER_COLOR := Color(0.75, 0.22, 0.18, 1.0)

const RETENTION_KEEP_ALL := "keep_all"
const RETENTION_TAKE_PARTY_GEAR := "take_party_gear"
const RETENTION_TAKE_EVERYTHING := "take_everything"

var _backdrop: ColorRect = null
var _panel: PanelContainer = null
var _title_label: Label = null
var _body_label: Label = null
var _final_wages_spin: SpinBox = null
var _parting_bonus_spin: SpinBox = null
var _retention_keep: CheckBox = null
var _retention_take_party: CheckBox = null
var _retention_take_all: CheckBox = null
var _confirm_btn: Button = null
var _cancel_btn: Button = null
var _on_confirm: Callable = Callable()
var _on_cancel: Callable = Callable()

# Context captured from show_dialog.
var _character_id: String = ""
var _settlement_id: String = ""
var _party_id: String = ""


func _ready() -> void:
	layer = 180
	_build_ui()
	_hide_all()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func show_dialog(character_id: String, settlement_id: String, party_id: String,
		henchman_name: String,
		default_final_wages_gp: int,
		on_confirm: Callable = Callable(),
		on_cancel: Callable = Callable()) -> void:
	_character_id = character_id
	_settlement_id = settlement_id
	_party_id = party_id
	_on_confirm = on_confirm
	_on_cancel = on_cancel

	_title_label.text = "Dismiss %s" % (henchman_name if not henchman_name.is_empty() else "henchman")
	_body_label.text = "%s will leave service and the Henchmen tab Departure Log will record the result. Choose how to send them off." % \
		(henchman_name if not henchman_name.is_empty() else "This henchman")

	_final_wages_spin.value = float(maxi(0, default_final_wages_gp))
	_parting_bonus_spin.value = 0.0

	_retention_keep.button_pressed = true
	_retention_take_party.button_pressed = false
	_retention_take_all.button_pressed = false

	_show_all()


func hide_dialog() -> void:
	_hide_all()


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	# Backdrop.
	_backdrop = ColorRect.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = Color(0.0, 0.0, 0.0, 0.5)
	_backdrop.gui_input.connect(func(_e): pass)  # consume clicks
	add_child(_backdrop)

	# Panel — centered MarginContainer wrapping a VBox.
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	_panel.position = Vector2(-PANEL_WIDTH / 2.0, -180)
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# Title.
	_title_label = Label.new()
	_title_label.text = "Dismiss Henchman"
	_title_label.add_theme_color_override("font_color", HEADING_COLOR)
	_title_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(_title_label)

	# Body.
	_body_label = Label.new()
	_body_label.text = ""
	_body_label.add_theme_color_override("font_color", BODY_COLOR)
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.custom_minimum_size = Vector2(PANEL_WIDTH - 48, 0)
	vbox.add_child(_body_label)

	# Separator.
	var sep1 := HSeparator.new()
	vbox.add_child(sep1)

	# Final wages row.
	var fw_row := HBoxContainer.new()
	var fw_label := Label.new()
	fw_label.text = "Final wages owed (gp):"
	fw_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fw_label.add_theme_color_override("font_color", BODY_COLOR)
	fw_row.add_child(fw_label)
	_final_wages_spin = SpinBox.new()
	_final_wages_spin.min_value = 0
	_final_wages_spin.max_value = 100000
	_final_wages_spin.step = 1
	_final_wages_spin.custom_minimum_size = Vector2(120, 0)
	fw_row.add_child(_final_wages_spin)
	vbox.add_child(fw_row)

	# Parting bonus row.
	var pb_row := HBoxContainer.new()
	var pb_label := Label.new()
	pb_label.text = "Parting bonus (gp, +1 morale on goodbye):"
	pb_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pb_label.add_theme_color_override("font_color", BODY_COLOR)
	pb_row.add_child(pb_label)
	_parting_bonus_spin = SpinBox.new()
	_parting_bonus_spin.min_value = 0
	_parting_bonus_spin.max_value = 100000
	_parting_bonus_spin.step = 1
	_parting_bonus_spin.custom_minimum_size = Vector2(120, 0)
	pb_row.add_child(_parting_bonus_spin)
	vbox.add_child(pb_row)

	# Separator.
	var sep2 := HSeparator.new()
	vbox.add_child(sep2)

	# Equipment retention.
	var eq_label := Label.new()
	eq_label.text = "Equipment:"
	eq_label.add_theme_color_override("font_color", BODY_COLOR)
	vbox.add_child(eq_label)

	var bg := ButtonGroup.new()
	_retention_keep = CheckBox.new()
	_retention_keep.text = "Keep all (henchman walks with everything)"
	_retention_keep.button_group = bg
	_retention_keep.button_pressed = true
	vbox.add_child(_retention_keep)

	_retention_take_party = CheckBox.new()
	_retention_take_party.text = "Take back party gear (recover henchman's inventory to employer)"
	_retention_take_party.button_group = bg
	vbox.add_child(_retention_take_party)

	_retention_take_all = CheckBox.new()
	_retention_take_all.text = "Take everything (angry dismissal — strip equipment)"
	_retention_take_all.button_group = bg
	vbox.add_child(_retention_take_all)

	# Buttons row.
	var sep3 := HSeparator.new()
	vbox.add_child(sep3)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	_cancel_btn = Button.new()
	_cancel_btn.text = "Cancel"
	_cancel_btn.pressed.connect(_on_cancel_pressed)
	btn_row.add_child(_cancel_btn)

	_confirm_btn = Button.new()
	_confirm_btn.text = "Dismiss"
	_confirm_btn.add_theme_color_override("font_color", DANGER_COLOR)
	_confirm_btn.pressed.connect(_on_confirm_pressed)
	btn_row.add_child(_confirm_btn)


# ---------------------------------------------------------------------------
# Internal handlers
# ---------------------------------------------------------------------------

func _on_confirm_pressed() -> void:
	var retention: String = RETENTION_KEEP_ALL
	if _retention_take_party.button_pressed:
		retention = RETENTION_TAKE_PARTY_GEAR
	elif _retention_take_all.button_pressed:
		retention = RETENTION_TAKE_EVERYTHING

	var options := {
		"final_wages_gp":      int(_final_wages_spin.value),
		"parting_bonus_gp":    int(_parting_bonus_spin.value),
		"equipment_retention": retention,
		"settlement_id":       _settlement_id,
		"party_id":            _party_id,
	}
	_hide_all()
	confirmed.emit(options)
	if _on_confirm.is_valid():
		_on_confirm.call(options)


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
