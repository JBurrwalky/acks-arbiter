class_name AbilityTradePanel
extends VBoxContainer

## Step 3 — Ability Score Trading (optional).
##
## ACKS rule: Trade 2 points from a non-prime-requisite ability to gain 1 point
## in a prime requisite. Source may not drop below 9. Source may not be a
## prime requisite of the chosen class. Trading is optional.
##
## Maintains an undo stack so the player can reverse trades one at a time.


const ABILITY_ORDER: Array[String] = ["STR", "INT", "WIS", "DEX", "CON", "CHA"]

var _state: Dictionary = {}
var _generator: CharacterGenerator
var _class_registry: ClassRegistry

# Working copy of scores; committed to _state["traded_scores"] after each trade.
# Reset to original scores on "Reset All".
var _current_scores: Dictionary = {}

# Undo stack: each entry is {source, target, points} for reversal
var _undo_stack: Array = []

# UI refs
var _score_labels: Dictionary = {}    # ability -> Label showing current value
var _mod_labels: Dictionary = {}      # ability -> Label showing modifier
var _original_labels: Dictionary = {} # ability -> Label showing original value
var _source_option: OptionButton
var _target_option: OptionButton
var _points_option: OptionButton
var _apply_btn: Button
var _undo_btn: Button
var _reset_btn: Button
var _status_label: Label
var _xp_label: Label


func setup(state: Dictionary, generator: CharacterGenerator,
		class_registry: ClassRegistry) -> void:
	_state = state
	_generator = generator
	_class_registry = class_registry
	if get_child_count() == 0:
		_build_ui()
	_init_working_scores()
	_rebuild_option_buttons()
	_refresh_display()


func is_complete() -> bool:
	return true  # Always completeable — trading is optional


# ---------------------------------------------------------------------------
# State management
# ---------------------------------------------------------------------------

func _init_working_scores() -> void:
	## Initialize from traded_scores if they exist (back navigation), else from base scores.
	var traded: Dictionary = _state.get("traded_scores", {})
	if not traded.is_empty():
		_current_scores = traded.duplicate()
	else:
		_current_scores = _state.get("scores", {}).duplicate()
	_undo_stack.clear()


func _commit_scores() -> void:
	_state["traded_scores"] = _current_scores.duplicate()


# ---------------------------------------------------------------------------
# UI Construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	add_theme_constant_override("separation", 10)

	var header := Label.new()
	header.text = "Optionally trade ability points to improve prime requisites (2 points from source → 1 to target). Scores may not drop below 9."
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(header)

	# Score grid: Ability | Original | Current | Modifier
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4)
	add_child(grid)

	for h in ["Ability", "Original", "Current", "Modifier"]:
		var lbl := Label.new()
		lbl.text = h
		lbl.add_theme_font_size_override("font_size", 12)
		grid.add_child(lbl)

	for ability in ABILITY_ORDER:
		var name_lbl := Label.new()
		name_lbl.text = ability
		grid.add_child(name_lbl)

		var orig_lbl := Label.new()
		orig_lbl.text = "—"
		orig_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		orig_lbl.custom_minimum_size = Vector2(40, 0)
		grid.add_child(orig_lbl)
		_original_labels[ability] = orig_lbl

		var cur_lbl := Label.new()
		cur_lbl.text = "—"
		cur_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cur_lbl.custom_minimum_size = Vector2(40, 0)
		grid.add_child(cur_lbl)
		_score_labels[ability] = cur_lbl

		var mod_lbl := Label.new()
		mod_lbl.text = "—"
		mod_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mod_lbl.custom_minimum_size = Vector2(40, 0)
		grid.add_child(mod_lbl)
		_mod_labels[ability] = mod_lbl

	add_child(HSeparator.new())

	# Trade controls
	var controls_lbl := Label.new()
	controls_lbl.text = "Trade:"
	add_child(controls_lbl)

	var ctrl_row := HBoxContainer.new()
	ctrl_row.add_theme_constant_override("separation", 8)
	add_child(ctrl_row)

	_source_option = OptionButton.new()
	_source_option.custom_minimum_size = Vector2(90, 0)
	ctrl_row.add_child(_source_option)

	var arrow_lbl := Label.new()
	arrow_lbl.text = "→"
	ctrl_row.add_child(arrow_lbl)

	_points_option = OptionButton.new()
	for pts in [2, 4, 6]:
		_points_option.add_item("%d pts" % pts)
		_points_option.set_item_metadata(_points_option.item_count - 1, pts)
	ctrl_row.add_child(_points_option)

	var into_lbl := Label.new()
	into_lbl.text = "into"
	ctrl_row.add_child(into_lbl)

	_target_option = OptionButton.new()
	_target_option.custom_minimum_size = Vector2(90, 0)
	ctrl_row.add_child(_target_option)

	_apply_btn = Button.new()
	_apply_btn.text = "Apply Trade"
	_apply_btn.pressed.connect(_on_apply_pressed)
	ctrl_row.add_child(_apply_btn)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status_label)

	# Undo / Reset row
	var undo_row := HBoxContainer.new()
	undo_row.add_theme_constant_override("separation", 8)
	add_child(undo_row)

	_undo_btn = Button.new()
	_undo_btn.text = "Undo Last Trade"
	_undo_btn.disabled = true
	_undo_btn.pressed.connect(_on_undo_pressed)
	undo_row.add_child(_undo_btn)

	_reset_btn = Button.new()
	_reset_btn.text = "Reset All"
	_reset_btn.pressed.connect(_on_reset_pressed)
	undo_row.add_child(_reset_btn)

	# XP adjustment display
	_xp_label = Label.new()
	_xp_label.text = ""
	add_child(_xp_label)


# ---------------------------------------------------------------------------
# Refresh
# ---------------------------------------------------------------------------

func _rebuild_option_buttons() -> void:
	## Populate source/target dropdowns based on current class prime requisites.
	var class_id: String = _state.get("class_id", "")
	var cls := _class_registry.get_class_def(class_id)
	var primes: Array = cls.get("prime_requisites", [])

	_source_option.clear()
	_target_option.clear()

	for ability in ABILITY_ORDER:
		if ability not in primes:
			_source_option.add_item(ability)
		else:
			_target_option.add_item(ability)

	_apply_btn.disabled = (_source_option.item_count == 0 or _target_option.item_count == 0)


func _refresh_display() -> void:
	var original: Dictionary = _state.get("scores", {})
	for ability in ABILITY_ORDER:
		var orig_val: int = int(original.get(ability, 0))
		var cur_val: int = int(_current_scores.get(ability, 0))
		_original_labels[ability].text = str(orig_val) if orig_val > 0 else "—"
		_score_labels[ability].text = str(cur_val) if cur_val > 0 else "—"
		if cur_val > 0:
			var mod := CharacterData.ability_modifier(cur_val)
			_mod_labels[ability].text = ("+%d" % mod) if mod >= 0 else str(mod)
			# Color: green if raised from original, red if lowered
			if cur_val > orig_val:
				_score_labels[ability].add_theme_color_override("font_color", Color.GREEN)
			elif cur_val < orig_val:
				_score_labels[ability].add_theme_color_override("font_color", Color(1.0, 0.4, 0.3))
			else:
				_score_labels[ability].remove_theme_color_override("font_color")

	_undo_btn.disabled = _undo_stack.is_empty()
	_update_xp_label()


func _update_xp_label() -> void:
	var class_id: String = _state.get("class_id", "")
	var cls := _class_registry.get_class_def(class_id)
	var primes: Array = cls.get("prime_requisites", [])
	var prime_scores: Array = []
	for pr in primes:
		prime_scores.append(int(_current_scores.get(pr, 10)))
	var adj := AbilityUtils.get_xp_adjustment(prime_scores)
	var adj_str := ("+%d%%" % adj) if adj >= 0 else ("%d%%" % adj)
	_xp_label.text = "XP Adjustment: %s" % adj_str


# ---------------------------------------------------------------------------
# Trade actions
# ---------------------------------------------------------------------------

func _on_apply_pressed() -> void:
	var source: String = _source_option.get_item_text(_source_option.selected)
	var target: String = _target_option.get_item_text(_target_option.selected)
	var pts_idx := _points_option.selected
	var points: int = _points_option.get_item_metadata(pts_idx)
	var class_id: String = _state.get("class_id", "")

	var new_scores := _generator.apply_ability_trade(_current_scores, class_id,
		source, target, points)
	if new_scores.is_empty():
		_status_label.text = "Trade is not valid. Check source/target and point limits."
		return

	_undo_stack.append({"source": source, "target": target, "points": points})
	_current_scores = new_scores
	_commit_scores()
	_status_label.text = ""
	_refresh_display()


func _on_undo_pressed() -> void:
	if _undo_stack.is_empty():
		return
	var last: Dictionary = _undo_stack.pop_back()
	# Reverse: return points from target back to source (target loses target_gain, source gains points)
	var source: String = last["source"]
	var target: String = last["target"]
	var points: int = last["points"]
	@warning_ignore("integer_division")
	var target_gain: int = points / 2
	_current_scores[source] = int(_current_scores[source]) + points
	_current_scores[target] = int(_current_scores[target]) - target_gain
	_commit_scores()
	_status_label.text = ""
	_refresh_display()


func _on_reset_pressed() -> void:
	_current_scores = _state.get("scores", {}).duplicate()
	_undo_stack.clear()
	_commit_scores()
	_status_label.text = ""
	_refresh_display()
