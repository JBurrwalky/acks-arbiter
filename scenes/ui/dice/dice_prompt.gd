extends CanvasLayer

## DicePrompt — modal roll prompt for PHYSICAL and HYBRID dice modes.
##
## Activated by EventBus.player_roll_requested. Presents the player with two options:
##   1. "Roll Dice" — app rolls digitally, shows a brief number-cycle animation,
##      then auto-fills the result and enables Confirm.
##   2. Manual entry — player types their physical dice total into a SpinBox
##      (range enforced to count..count*sides), then clicks Confirm.
##
## On Confirm: emits EventBus.player_roll_resolved(roll_type, raw_total, was_player_entered).
##   raw_total is the dice-only total; DiceSystem applies the modifier.
##
## Layer 64 — sits above normal game content, below Override Panel (layer 128).
## Hidden by default; shown only while a player roll is pending.
##
## All UI is built programmatically in _build_ui() to avoid editor-only layouts.


const ANIMATION_DURATION := 0.4   ## seconds the number cycles before settling
const ANIMATION_STEP     := 0.05  ## interval (seconds) between random number flashes


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _roll_type: String = ""
var _sides:     int    = 6
var _count:     int    = 1
var _modifier:  int    = 0

var _final_raw_total:  int  = 0
var _used_roll_button: bool = false   ## tracks whether Roll Dice was pressed

# Animation
var _anim_timer:   Timer
var _anim_elapsed: float = 0.0


# ---------------------------------------------------------------------------
# Cached UI nodes
# ---------------------------------------------------------------------------

var _dimmer:        ColorRect
var _panel:         PanelContainer
var _title_label:   Label
var _expr_label:    Label
var _desc_label:    Label
var _anim_label:    Label
var _roll_btn:      Button
var _manual_entry:  SpinBox
var _confirm_btn:   Button
var _mod_hint:      Label


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer = 64
	visible = false

	_build_ui()

	_anim_timer = Timer.new()
	_anim_timer.wait_time = ANIMATION_STEP
	_anim_timer.one_shot  = false
	_anim_timer.timeout.connect(_on_anim_step)
	add_child(_anim_timer)

	EventBus.player_roll_requested.connect(_on_roll_requested)


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_roll_requested(context: Dictionary) -> void:
	_roll_type = context.get("roll_type", "")
	_sides     = context.get("sides",    6)
	_count     = context.get("count",    1)
	_modifier  = context.get("modifier", 0)
	_used_roll_button = false

	_title_label.text = "Dice Roll Required"
	_expr_label.text  = "Roll: %dd%d" % [_count, _sides]

	var desc: String = context.get("description", "")
	_desc_label.text    = desc
	_desc_label.visible = not desc.is_empty()

	if _modifier != 0:
		_mod_hint.text    = "Modifier %+d applied separately by the app" % _modifier
		_mod_hint.visible = true
	else:
		_mod_hint.visible = false

	_manual_entry.min_value = _count
	_manual_entry.max_value = _count * _sides
	_manual_entry.value     = _count  # reset to minimum
	_anim_label.text        = "—"

	_roll_btn.disabled    = false
	_confirm_btn.disabled = false

	visible = true
	_roll_btn.grab_focus()


func _on_roll_btn_pressed() -> void:
	_used_roll_button = true
	_roll_btn.disabled    = true
	_confirm_btn.disabled = true

	# Roll all dice and compute total
	var individual: Array[int] = []
	for i in _count:
		individual.append(randi_range(1, _sides))
	_final_raw_total = 0
	for v in individual:
		_final_raw_total += v

	# Start number-cycling animation
	_anim_elapsed = 0.0
	_anim_timer.start()


func _on_anim_step() -> void:
	_anim_elapsed += ANIMATION_STEP
	if _anim_elapsed >= ANIMATION_DURATION:
		_anim_timer.stop()
		# Settle on final result
		_anim_label.text        = str(_final_raw_total)
		_manual_entry.value     = _final_raw_total
		_confirm_btn.disabled   = false
		_confirm_btn.grab_focus()
	else:
		# Cycle through random values in the legal range for visual effect
		_anim_label.text = str(randi_range(_count, _count * _sides))


func _on_confirm_btn_pressed() -> void:
	var raw_total: int          = int(_manual_entry.value)
	var was_player_entered: bool = not _used_roll_button
	visible = false
	EventBus.player_roll_resolved.emit(_roll_type, raw_total, was_player_entered)


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	# Full-screen dimmer behind the panel
	_dimmer = ColorRect.new()
	_dimmer.color                 = Color(0.0, 0.0, 0.0, 0.5)
	_dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dimmer.mouse_filter          = Control.MOUSE_FILTER_STOP  # blocks click-through
	add_child(_dimmer)

	# Centred panel
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(380, 0)
	add_child(_panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	_panel.add_child(outer)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   16)
	margin.add_theme_constant_override("margin_right",  16)
	margin.add_theme_constant_override("margin_top",    16)
	margin.add_theme_constant_override("margin_bottom", 16)
	outer.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	# Title
	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(_title_label)

	# Dice expression
	_expr_label = Label.new()
	_expr_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_expr_label.add_theme_font_size_override("font_size", 22)
	vbox.add_child(_expr_label)

	# Optional description
	_desc_label = Label.new()
	_desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc_label.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.visible              = false
	vbox.add_child(_desc_label)

	vbox.add_child(HSeparator.new())

	# Animated result display
	_anim_label = Label.new()
	_anim_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anim_label.add_theme_font_size_override("font_size", 48)
	_anim_label.custom_minimum_size  = Vector2(0, 64)
	vbox.add_child(_anim_label)

	# Roll Dice button
	_roll_btn = Button.new()
	_roll_btn.text = "Roll Dice"
	_roll_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_roll_btn.pressed.connect(_on_roll_btn_pressed)
	vbox.add_child(_roll_btn)

	vbox.add_child(HSeparator.new())

	# Manual entry row
	var manual_row := HBoxContainer.new()
	manual_row.add_theme_constant_override("separation", 8)
	vbox.add_child(manual_row)

	var manual_lbl := Label.new()
	manual_lbl.text = "Or enter total:"
	manual_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	manual_row.add_child(manual_lbl)

	_manual_entry = SpinBox.new()
	_manual_entry.min_value = 1
	_manual_entry.max_value = 100
	_manual_entry.step      = 1
	_manual_entry.custom_minimum_size = Vector2(80, 0)
	manual_row.add_child(_manual_entry)

	# Confirm button
	_confirm_btn = Button.new()
	_confirm_btn.text = "Confirm"
	_confirm_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm_btn.pressed.connect(_on_confirm_btn_pressed)
	vbox.add_child(_confirm_btn)

	# Modifier hint (hidden when modifier == 0)
	_mod_hint = Label.new()
	_mod_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mod_hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_mod_hint.visible = false
	vbox.add_child(_mod_hint)
