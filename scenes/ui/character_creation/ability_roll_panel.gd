class_name AbilityRollPanel
extends VBoxContainer

## Step 1 — Ability Score Rolling.
##
## Rolls 3d6 in order for STR, INT, WIS, DEX, CON, CHA.
## Displays each score and its modifier. Player may re-roll as many times
## as desired before advancing. ACKS rule: 3d6 in order, no rearranging.


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
	header.text = "Roll your ability scores (3d6 in order)."
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(header)

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
		score_lbl.text = "—"
		score_lbl.custom_minimum_size = Vector2(40, 0)
		score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(score_lbl)
		_score_labels[ability] = score_lbl

		var mod_lbl := Label.new()
		mod_lbl.text = "—"
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
	_roll_button.text = "Roll 3d6 In Order"
	_roll_button.pressed.connect(_on_roll_pressed)
	btn_row.add_child(_roll_button)

	_reroll_button = Button.new()
	_reroll_button.text = "Re-Roll All"
	_reroll_button.visible = false
	_reroll_button.pressed.connect(_on_roll_pressed)
	btn_row.add_child(_reroll_button)


func _refresh_display() -> void:
	var scores: Dictionary = _state.get("scores", {})
	if scores.is_empty():
		for ability in ABILITY_ORDER:
			_score_labels[ability].text = "—"
			_mod_labels[ability].text = "—"
		if _reroll_button != null:
			_reroll_button.visible = false
		if _roll_button != null:
			_roll_button.visible = true
		return

	for ability in ABILITY_ORDER:
		var val: int = int(scores.get(ability, 0))
		_score_labels[ability].text = str(val)
		var mod := CharacterData.ability_modifier(val)
		_mod_labels[ability].text = ("+%d" % mod) if mod >= 0 else str(mod)

	if _reroll_button != null:
		_reroll_button.visible = true
		_roll_button.visible = false


# ---------------------------------------------------------------------------
# Roll logic (async)
# ---------------------------------------------------------------------------

func _on_roll_pressed() -> void:
	if _rolling:
		return
	_rolling = true
	_roll_button.disabled = true
	_reroll_button.disabled = true
	_status_label.text = "Rolling…"

	var new_scores: Dictionary = {}
	for ability in ABILITY_ORDER:
		_status_label.text = "Rolling %s…" % ABILITY_NAMES[ability]
		var result: RollResult = await DiceSystem.player_roll(6, 3, 0,
			"ability_score_%s" % ability.to_lower(),
			"Roll %s (3d6)" % ABILITY_NAMES[ability])
		new_scores[ability] = result.modified_total

	_state["scores"] = new_scores
	_state["traded_scores"] = {}   # invalidate any prior trades

	_status_label.text = ""
	_rolling = false
	_roll_button.disabled = false
	_reroll_button.disabled = false
	_refresh_display()
