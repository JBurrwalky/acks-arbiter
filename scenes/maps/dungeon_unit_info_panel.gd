extends PanelContainer

## Left-side unit info panel for the currently selected dungeon entity.
##
## Shows portrait, name, class/level, HP, AC, current action, movement mode,
## light source, conditions, and encumbrance. Multi-select shows compact view.

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const HP_GREEN := Color(0.3, 0.8, 0.3)
const HP_YELLOW := Color(0.9, 0.8, 0.2)
const HP_RED := Color(0.9, 0.25, 0.2)
const PANEL_WIDTH := 200.0


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _vbox: VBoxContainer = null
var _name_label: Label = null
var _class_label: Label = null
var _hp_bar: ProgressBar = null
var _hp_label: Label = null
var _ac_label: Label = null
var _action_label: Label = null
var _movement_label: Label = null
var _light_label: Label = null
var _encumbrance_label: Label = null
var _conditions_label: Label = null

## Multi-select compact view.
var _multi_vbox: VBoxContainer = null


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	custom_minimum_size.x = PANEL_WIDTH

	# Dark panel style.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.10, 0.88)
	style.border_color = Color(0.3, 0.3, 0.4, 0.7)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	add_theme_stylebox_override("panel", style)

	# Build layout.
	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 4)
	add_child(_vbox)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 16)
	_vbox.add_child(_name_label)

	_class_label = Label.new()
	_class_label.add_theme_font_size_override("font_size", 12)
	_class_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	_vbox.add_child(_class_label)

	var sep1 := HSeparator.new()
	_vbox.add_child(sep1)

	# HP bar.
	_hp_bar = ProgressBar.new()
	_hp_bar.custom_minimum_size.y = 16
	_hp_bar.show_percentage = false
	_vbox.add_child(_hp_bar)

	_hp_label = Label.new()
	_hp_label.add_theme_font_size_override("font_size", 12)
	_vbox.add_child(_hp_label)

	_ac_label = Label.new()
	_ac_label.add_theme_font_size_override("font_size", 12)
	_vbox.add_child(_ac_label)

	var sep2 := HSeparator.new()
	_vbox.add_child(sep2)

	_action_label = Label.new()
	_action_label.add_theme_font_size_override("font_size", 11)
	_vbox.add_child(_action_label)

	_movement_label = Label.new()
	_movement_label.add_theme_font_size_override("font_size", 11)
	_vbox.add_child(_movement_label)

	_light_label = Label.new()
	_light_label.add_theme_font_size_override("font_size", 11)
	_vbox.add_child(_light_label)

	_encumbrance_label = Label.new()
	_encumbrance_label.add_theme_font_size_override("font_size", 11)
	_vbox.add_child(_encumbrance_label)

	_conditions_label = Label.new()
	_conditions_label.add_theme_font_size_override("font_size", 11)
	_conditions_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_vbox.add_child(_conditions_label)

	# Multi-select view (hidden by default).
	_multi_vbox = VBoxContainer.new()
	_multi_vbox.add_theme_constant_override("separation", 2)
	_multi_vbox.visible = false
	add_child(_multi_vbox)

	clear()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Show details for a single selected entity.
## [param cd]: CharacterData for the entity.
## [param action_status]: { "action": "Moving", "progress": "3/10" } or {}.
## [param light_info]: { "source_type": "torch", "remaining": 4 } or {}.
func show_entity(cd: CharacterData, action_status: Dictionary = {}, light_info: Dictionary = {}) -> void:
	_vbox.visible = true
	_multi_vbox.visible = false
	visible = true

	_name_label.text = cd.name
	_class_label.text = "%s %d" % [cd.character_class.capitalize(), cd.level]

	# HP bar.
	_hp_bar.max_value = cd.hp_max
	_hp_bar.value = cd.hp_current
	var hp_pct: float = float(cd.hp_current) / float(maxf(cd.hp_max, 1))
	var hp_color := HP_GREEN
	if hp_pct <= 0.25:
		hp_color = HP_RED
	elif hp_pct <= 0.50:
		hp_color = HP_YELLOW
	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = hp_color
	_hp_bar.add_theme_stylebox_override("fill", bar_style)
	_hp_label.text = "HP: %d / %d" % [cd.hp_current, cd.hp_max]
	_hp_label.add_theme_color_override("font_color", hp_color)

	_ac_label.text = "AC: %d" % cd.armor_class

	# Current action.
	var action_text: String = action_status.get("action", "Idle")
	var progress: String = action_status.get("progress", "")
	if not progress.is_empty():
		action_text += " (%s)" % progress
	_action_label.text = action_text

	# Movement mode.
	_movement_label.text = "Movement: Exploration"

	# Light source.
	var src_type: String = light_info.get("source_type", "")
	if src_type.is_empty():
		_light_label.text = "Light: None"
		_light_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	else:
		var remaining: int = light_info.get("remaining", 0)
		_light_label.text = "Light: %s (%d turns)" % [src_type.capitalize(), remaining]
		if remaining <= 2:
			_light_label.add_theme_color_override("font_color", Color(0.9, 0.5, 0.2))
		else:
			_light_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))

	# Encumbrance.
	_encumbrance_label.text = "Enc: --"  # TODO: wire to EncumbranceCalculator.

	# Conditions.
	_conditions_label.text = ""


## Show compact multi-select view with mini HP bars.
func show_multi_select(characters: Array) -> void:
	_vbox.visible = false
	_multi_vbox.visible = true
	visible = true

	# Clear previous entries.
	for child in _multi_vbox.get_children():
		child.queue_free()

	var header := Label.new()
	header.text = "%d Selected" % characters.size()
	header.add_theme_font_size_override("font_size", 14)
	_multi_vbox.add_child(header)

	for cd in characters:
		if cd == null:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)

		var name_lbl := Label.new()
		name_lbl.text = cd.name
		name_lbl.add_theme_font_size_override("font_size", 11)
		name_lbl.custom_minimum_size.x = 100
		row.add_child(name_lbl)

		var hp_bar := ProgressBar.new()
		hp_bar.max_value = cd.hp_max
		hp_bar.value = cd.hp_current
		hp_bar.custom_minimum_size = Vector2(60, 12)
		hp_bar.show_percentage = false
		hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var pct: float = float(cd.hp_current) / float(maxf(cd.hp_max, 1))
		var color := HP_GREEN if pct > 0.5 else (HP_YELLOW if pct > 0.25 else HP_RED)
		var fill := StyleBoxFlat.new()
		fill.bg_color = color
		hp_bar.add_theme_stylebox_override("fill", fill)
		row.add_child(hp_bar)

		_multi_vbox.add_child(row)


## Clear the panel (no selection).
func clear() -> void:
	visible = false
	_vbox.visible = false
	_multi_vbox.visible = false
