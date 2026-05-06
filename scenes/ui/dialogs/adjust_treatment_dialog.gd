class_name AdjustTreatmentDialog
extends CanvasLayer

## Phase 5 of the henchman closure plan: state-rich modal for adjusting a
## henchman's treasure share + paying a one-time goodwill bonus.
## Per gdd-henchmen-tab.md §7.3.1.
##
## Slider + SpinBox state means ConfirmationPrompt's title/body/buttons
## contract isn't a fit; this is a dedicated surface following the
## gdd-ui-architecture.md §2.3 modal pattern (layer 100-199).
##
## Usage:
##   var dialog := AdjustTreatmentDialog.new()
##   add_child(dialog)
##   dialog.show_dialog(character_id, name, current_share, current_morale,
##       on_confirm = func(opts): _do_adjust(character_id, opts),
##       on_cancel  = func(): dialog.queue_free())

signal confirmed(options: Dictionary)
signal cancelled

const PANEL_WIDTH := 480
## Vellum chrome installs a dark text theme; the per-label color overrides
## below are no-ops by default (left in place so a future palette tweak can
## restore semantic accents without re-threading every call site).
const HEADING_COLOR := UiSurfaceStyles.VELLUM_TEXT_COLOR
const BODY_COLOR := UiSurfaceStyles.VELLUM_TEXT_COLOR
const ACCENT_COLOR := Color(0.20, 0.45, 0.20, 1.0)

var _backdrop: ColorRect = null
var _panel: PanelContainer = null
var _title_label: Label = null
var _body_label: Label = null
var _share_slider: HSlider = null
var _share_value_label: Label = null
var _bonus_spin: SpinBox = null
var _confirm_btn: Button = null
var _cancel_btn: Button = null
var _on_confirm: Callable = Callable()
var _on_cancel: Callable = Callable()

var _character_id: String = ""


func _ready() -> void:
	layer = 180
	_build_ui()
	_hide_all()


func show_dialog(character_id: String, henchman_name: String,
		current_share_percent: int, current_morale: int,
		on_confirm: Callable = Callable(),
		on_cancel: Callable = Callable()) -> void:
	_character_id = character_id
	_on_confirm = on_confirm
	_on_cancel = on_cancel

	_title_label.text = "Adjust treatment — %s" % \
		(henchman_name if not henchman_name.is_empty() else "henchman")
	_body_label.text = "Current morale: %+d. Treasure share is the henchman's cut of party loot (default 15%%, ACKS RAW). A one-time bonus is a goodwill payment that nudges morale +1." % current_morale

	_share_slider.value = float(clampi(current_share_percent, 0, 100))
	_share_value_label.text = "%d%%" % int(_share_slider.value)
	_bonus_spin.value = 0.0

	_show_all()


func hide_dialog() -> void:
	_hide_all()


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	_backdrop = ColorRect.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = Color(0.0, 0.0, 0.0, 0.5)
	_backdrop.gui_input.connect(func(_e): pass)
	add_child(_backdrop)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	_panel.position = Vector2(-PANEL_WIDTH / 2.0, -160)
	UiSurfaceStyles.apply_framed_window_chrome(_panel)
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

	_title_label = Label.new()
	_title_label.add_theme_color_override("font_color", HEADING_COLOR)
	_title_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(_title_label)

	_body_label = Label.new()
	_body_label.add_theme_color_override("font_color", BODY_COLOR)
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.custom_minimum_size = Vector2(PANEL_WIDTH - 48, 0)
	vbox.add_child(_body_label)

	vbox.add_child(HSeparator.new())

	# Share slider row.
	var share_label := Label.new()
	share_label.text = "Treasure share:"
	share_label.add_theme_color_override("font_color", BODY_COLOR)
	vbox.add_child(share_label)

	var share_row := HBoxContainer.new()
	share_row.add_theme_constant_override("separation", 12)
	_share_slider = HSlider.new()
	_share_slider.min_value = 0
	_share_slider.max_value = 50  # ACKS RAW: at least 15%; cap UI at 50%
	_share_slider.step = 5
	_share_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_share_slider.value_changed.connect(_on_share_changed)
	share_row.add_child(_share_slider)
	_share_value_label = Label.new()
	_share_value_label.text = "15%"
	_share_value_label.add_theme_color_override("font_color", ACCENT_COLOR)
	_share_value_label.custom_minimum_size = Vector2(48, 0)
	share_row.add_child(_share_value_label)
	vbox.add_child(share_row)

	# Bonus payment row.
	var bonus_row := HBoxContainer.new()
	var bonus_label := Label.new()
	bonus_label.text = "One-time bonus (gp, +1 morale if > 0):"
	bonus_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bonus_label.add_theme_color_override("font_color", BODY_COLOR)
	bonus_row.add_child(bonus_label)
	_bonus_spin = SpinBox.new()
	_bonus_spin.min_value = 0
	_bonus_spin.max_value = 100000
	_bonus_spin.step = 1
	_bonus_spin.custom_minimum_size = Vector2(120, 0)
	bonus_row.add_child(_bonus_spin)
	vbox.add_child(bonus_row)

	vbox.add_child(HSeparator.new())

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	_cancel_btn = Button.new()
	_cancel_btn.text = "Cancel"
	_cancel_btn.pressed.connect(_on_cancel_pressed)
	btn_row.add_child(_cancel_btn)

	_confirm_btn = Button.new()
	_confirm_btn.text = "Apply"
	_confirm_btn.pressed.connect(_on_confirm_pressed)
	btn_row.add_child(_confirm_btn)


func _on_share_changed(value: float) -> void:
	_share_value_label.text = "%d%%" % int(value)


func _on_confirm_pressed() -> void:
	var options := {
		"treasure_share_percent": int(_share_slider.value),
		"bonus_gp":               int(_bonus_spin.value),
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
