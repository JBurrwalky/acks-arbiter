class_name AbilityRollPanel
extends VBoxContainer

## Step 1 - Ability Score Rolling.
##
## Rolls five 3d6-in-order arrays for STR, INT, WIS, DEX, CON, CHA.
## Displays each array and lets the player choose one before advancing.
## ACKS rule: 3d6 in order, no rearranging.


const ABILITY_ORDER: Array[String] = ["STR", "INT", "WIS", "DEX", "CON", "CHA"]
const ABILITY_NAMES: Dictionary = {
	"STR": "Strength",
	"INT": "Intelligence",
	"WIS": "Wisdom",
	"DEX": "Dexterity",
	"CON": "Constitution",
	"CHA": "Charisma",
}

var _state: Dictionary = {}
var _generator: CharacterGenerator

var _roll_button: Button
var _reroll_button: Button
var _array_list_container: VBoxContainer
var _score_labels: Dictionary = {}   # ability -> Label showing score
var _mod_labels: Dictionary = {}     # ability -> Label showing modifier
var _status_label: Label
var _rolling: bool = false


func setup(state: Dictionary, generator: CharacterGenerator) -> void:
	_state = state
	_generator = generator
	if get_child_count() == 0:
		_build_ui()
	_refresh_display()


func is_complete() -> bool:
	return not _state.get("scores", {}).is_empty()


# ---------------------------------------------------------------------------
# UI Construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	add_theme_constant_override("separation", 12)

	var header := Label.new()
	header.text = "Roll five ability arrays (3d6 in order) and choose one to use for this character."
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(header)

	var chooser_lbl := Label.new()
	chooser_lbl.text = "Rolled arrays:"
	add_child(chooser_lbl)

	_array_list_container = VBoxContainer.new()
	_array_list_container.add_theme_constant_override("separation", 6)
	add_child(_array_list_container)

	add_child(HSeparator.new())

	var selected_lbl := Label.new()
	selected_lbl.text = "Selected array:"
	add_child(selected_lbl)

	# Score grid: label | score | modifier
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 6)
	add_child(grid)

	# Grid header
	for header_text in ["Ability", "Score", "Modifier"]:
		var lbl := Label.new()
		lbl.text = header_text
		lbl.add_theme_font_size_override("font_size", 13)
		grid.add_child(lbl)

	for ability in ABILITY_ORDER:
		var name_lbl := Label.new()
		name_lbl.text = ABILITY_NAMES[ability]
		grid.add_child(name_lbl)

		var score_lbl := Label.new()
		score_lbl.text = "-"
		score_lbl.custom_minimum_size = Vector2(40, 0)
		score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(score_lbl)
		_score_labels[ability] = score_lbl

		var mod_lbl := Label.new()
		mod_lbl.text = "-"
		mod_lbl.custom_minimum_size = Vector2(40, 0)
		mod_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(mod_lbl)
		_mod_labels[ability] = mod_lbl

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status_label)

	var btn_row := HBoxContainer.new()
	add_child(btn_row)

	_roll_button = Button.new()
	_roll_button.text = "Roll Attributes"
	_roll_button.pressed.connect(_on_roll_pressed)
	btn_row.add_child(_roll_button)

	_reroll_button = Button.new()
	_reroll_button.text = "Roll 5 New Arrays"
	_reroll_button.visible = false
	_reroll_button.pressed.connect(_on_roll_pressed)
	btn_row.add_child(_reroll_button)


func _refresh_display() -> void:
	for child in _array_list_container.get_children():
		child.queue_free()

	var score_options: Array = _state.get("score_options", [])
	var selected_idx: int = int(_state.get("selected_score_index", -1))
	var scores: Dictionary = _state.get("scores", {})
	if score_options.is_empty() or scores.is_empty():
		for ability in ABILITY_ORDER:
			_score_labels[ability].text = "-"
			_mod_labels[ability].text = "-"
		if _reroll_button != null:
			_reroll_button.visible = false
		if _roll_button != null:
			_roll_button.visible = true
		return

	for idx in range(score_options.size()):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_array_list_container.add_child(row)

		var choose_btn := Button.new()
		choose_btn.text = "Selected" if idx == selected_idx else "Choose"
		choose_btn.disabled = (idx == selected_idx)
		choose_btn.pressed.connect(select_score_option.bind(idx))
		row.add_child(choose_btn)

		var summary_lbl := Label.new()
		summary_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		summary_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		summary_lbl.text = "Array %d: %s" % [idx + 1, _format_score_summary(score_options[idx])]
		if idx == selected_idx:
			summary_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 1.0))
		row.add_child(summary_lbl)

	for ability in ABILITY_ORDER:
		var val: int = int(scores.get(ability, 0))
		_score_labels[ability].text = str(val)
		var mod := CharacterData.ability_modifier(val)
		_mod_labels[ability].text = ("+%d" % mod) if mod >= 0 else str(mod)

	if _reroll_button != null:
		_reroll_button.visible = true
		_roll_button.visible = false


# ---------------------------------------------------------------------------
# Roll logic
# ---------------------------------------------------------------------------

func _on_roll_pressed() -> void:
	if _rolling:
		return
	_rolling = true
	_roll_button.disabled = true
	_reroll_button.disabled = true
	_status_label.text = "Rolling 5 arrays..."

	var rolled_arrays: Array = []
	for array_idx in range(5):
		var new_scores: Dictionary = {}
		for ability in ABILITY_ORDER:
			var result: RollResult = DiceSystem.roll_digital(
				6, 3, 0,
				"ability_score_array_%d_%s" % [array_idx + 1, ability.to_lower()]
			)
			new_scores[ability] = result.modified_total
		rolled_arrays.append(new_scores)

	_state["score_options"] = rolled_arrays
	select_score_option(0)

	_status_label.text = "Five arrays rolled. Choose one."
	_rolling = false
	_roll_button.disabled = false
	_reroll_button.disabled = false
	_refresh_display()


func select_score_option(index: int) -> void:
	var score_options: Array = _state.get("score_options", [])
	if index < 0 or index >= score_options.size():
		return
	_state["selected_score_index"] = index
	_state["scores"] = (score_options[index] as Dictionary).duplicate()
	_state["traded_scores"] = {}   # invalidate any prior trades
	if get_child_count() > 0:
		_refresh_display()


func _format_score_summary(scores: Dictionary) -> String:
	var parts: Array[String] = []
	for ability in ABILITY_ORDER:
		parts.append("%s %d" % [ability, int(scores.get(ability, 0))])
	return "  ".join(parts)
