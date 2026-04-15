class_name ActionButtonPanel
extends PanelContainer

## Quick-action bar for combat.
##
## Shows Pass and Delay buttons (context-independent actions), plus conditional
## Confirm Move and Skip Cleave buttons. All spatially-targeted actions are
## accessed via the right-click context menu (see CombatContextMenuBuilder).
##
## Emits action_selected(action_id) when a button is clicked.


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal action_selected(action_id: String)


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Quick actions always available (context-independent).
const ACTIONS := [
	{"id": "delay", "label": "Delay", "icon": ".."},
	{"id": "pass", "label": "Pass", "icon": "-"},
]


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _buttons: Dictionary = {}  # action_id -> Button
var _confirm_move_btn: Button = null
var _skip_cleave_btn: Button = null


signal confirm_move_pressed()
signal skip_cleave_pressed()


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	custom_minimum_size = Vector2(180, 0)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.85)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	var title := Label.new()
	title.text = "Quick Actions"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "Right-click for actions"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	vbox.add_child(hint)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	for action_def in ACTIONS:
		var btn := Button.new()
		btn.name = action_def["id"]
		btn.text = "%s  %s" % [action_def["icon"], action_def["label"]]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size.y = 32.0
		btn.disabled = true
		var action_id: String = action_def["id"]
		btn.pressed.connect(_on_button_pressed.bind(action_id))
		vbox.add_child(btn)
		_buttons[action_id] = btn

	# Confirm Move button (hidden unless in facing-selection state)
	var confirm_sep := HSeparator.new()
	vbox.add_child(confirm_sep)

	_confirm_move_btn = Button.new()
	_confirm_move_btn.text = "Confirm Move"
	_confirm_move_btn.custom_minimum_size.y = 36.0
	_confirm_move_btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	_confirm_move_btn.visible = false
	_confirm_move_btn.pressed.connect(func(): confirm_move_pressed.emit())
	vbox.add_child(_confirm_move_btn)

	_skip_cleave_btn = Button.new()
	_skip_cleave_btn.text = "Skip Cleave"
	_skip_cleave_btn.custom_minimum_size.y = 36.0
	_skip_cleave_btn.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
	_skip_cleave_btn.visible = false
	_skip_cleave_btn.pressed.connect(func(): skip_cleave_pressed.emit())
	vbox.add_child(_skip_cleave_btn)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Enable/disable buttons based on the combatant's available actions.
## [param actions] Array of action ID strings from CombatController.get_available_actions().
func set_available_actions(actions: Array) -> void:
	for action_id in _buttons:
		var btn: Button = _buttons[action_id]
		# Pass and Delay are always enabled during PC turns
		btn.disabled = false


## Disable a single action button by ID.
func disable_action(action_id: String) -> void:
	if _buttons.has(action_id):
		_buttons[action_id].disabled = true


## Show or hide the Confirm Move button (used during facing-selection phase).
func show_confirm_move(is_visible: bool) -> void:
	if _confirm_move_btn != null:
		_confirm_move_btn.visible = is_visible


## Show or hide the Skip Cleave button (used during cleave-selection phase).
func show_skip_cleave(is_visible: bool) -> void:
	if _skip_cleave_btn != null:
		_skip_cleave_btn.visible = is_visible


## Show or hide the entire panel (hide during enemy turns).
func set_panel_visible(is_visible: bool) -> void:
	visible = is_visible


## Disable all buttons (e.g. while waiting for target selection).
func disable_all() -> void:
	for btn: Button in _buttons.values():
		btn.disabled = true


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _on_button_pressed(action_id: String) -> void:
	action_selected.emit(action_id)
