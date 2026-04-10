class_name ActionButtonPanel
extends PanelContainer

## Vertical panel of combat action buttons.
##
## Shows Move, Attack Melee, Attack Ranged, Cast Spell, Fighting Withdrawal,
## Full Retreat, and Pass. Buttons are enabled/disabled per combatant via
## set_available_actions(). Hidden during enemy turns.
##
## Emits action_selected(action_id) when a button is clicked.


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal action_selected(action_id: String)


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Ordered list of action IDs and their display labels.
const ACTIONS := [
	{"id": "move", "label": "Move", "icon": ">"},
	{"id": "attack_melee", "label": "Melee Attack", "icon": "/"},
	{"id": "attack_ranged", "label": "Ranged Attack", "icon": ")"},
	{"id": "cast_spell", "label": "Cast Spell", "icon": "*"},
	{"id": "delay", "label": "Delay", "icon": ".."},
	{"id": "pass", "label": "Pass", "icon": "-"},
]


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _buttons: Dictionary = {}  # action_id -> Button


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
	title.text = "Actions"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(title)

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

		# Cast Spell always disabled until F-3
		if action_id == "cast_spell":
			btn.tooltip_text = "Spell casting (F-3 — not yet available)"

		vbox.add_child(btn)
		_buttons[action_id] = btn


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Enable/disable buttons based on the combatant's available actions.
## [param actions] Array of action ID strings from CombatController.get_available_actions().
func set_available_actions(actions: Array) -> void:
	for action_id in _buttons:
		var btn: Button = _buttons[action_id]
		# cast_spell always disabled until F-3
		if action_id == "cast_spell":
			btn.disabled = true
			continue
		btn.disabled = not (action_id in actions)


## Disable a single action button by ID.
func disable_action(action_id: String) -> void:
	if _buttons.has(action_id):
		_buttons[action_id].disabled = true


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
