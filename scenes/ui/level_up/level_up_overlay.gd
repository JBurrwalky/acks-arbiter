class_name LevelUpOverlay
extends CanvasLayer

## Multi-step level-up wizard overlay.
##
## Displays: congratulations → HP roll → attack/save advancement →
## proficiency selection (if slot granted) → spell selection (if new level) →
## power unlocks → summary with confirm.
##
## Wraps LevelUpEngine.begin_interactive_level_up() for the computation
## and LevelUpEngine.finalize_interactive_level_up() for persistence.

signal level_up_completed(character_id: String)
signal level_up_cancelled(character_id: String)

const HEADING_COLOR := Color(0.95, 0.90, 0.78, 1.0)
const BODY_COLOR := Color(0.85, 0.80, 0.70, 1.0)
const DIM_COLOR := Color(0.55, 0.50, 0.42, 1.0)
const ACCENT_COLOR := Color(0.30, 0.65, 0.30, 1.0)
const DANGER_COLOR := Color(0.75, 0.22, 0.18, 1.0)

var _panel: PanelContainer = null
var _step_container: VBoxContainer = null
var _nav_bar: HBoxContainer = null
var _next_btn: Button = null
var _prev_btn: Button = null

var _character: CharacterData = null
var _level_up_result: Dictionary = {}
var _player_choices: Dictionary = {}
var _current_step: int = 0
var _steps: Array[Dictionary] = []  # [{title, build_func}]
var _level_up_engine: LevelUpEngine = null


func _ready() -> void:
	layer = 100
	_build_chrome()
	_panel.visible = false


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func open(character: CharacterData, engine: LevelUpEngine) -> void:
	_character = character
	_level_up_engine = engine
	_player_choices = {"proficiencies": [], "spells": []}

	_level_up_result = engine.begin_interactive_level_up(character)
	if _level_up_result.is_empty():
		push_error("LevelUpOverlay.open: level-up computation failed")
		return

	_build_steps()
	_current_step = 0
	_show_step(0)
	_panel.visible = true


func close() -> void:
	_panel.visible = false
	_character = null
	_level_up_result = {}


# ---------------------------------------------------------------------------
# Chrome
# ---------------------------------------------------------------------------

func _build_chrome() -> void:
	# Dimming backdrop.
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.0, 0.0, 0.0, 0.55)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(600, 450)
	_panel.offset_left = -300
	_panel.offset_right = 300
	_panel.offset_top = -225
	_panel.offset_bottom = 225
	UiSurfaceStyles.apply_framed_window_chrome(_panel)
	add_child(_panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	_panel.add_child(outer)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(margin)

	_step_container = VBoxContainer.new()
	_step_container.add_theme_constant_override("separation", 10)
	margin.add_child(_step_container)

	# Navigation bar.
	_nav_bar = HBoxContainer.new()
	_nav_bar.add_theme_constant_override("separation", 12)
	_nav_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_child(_nav_bar)

	_prev_btn = Button.new()
	_prev_btn.text = "< Back"
	_prev_btn.add_theme_font_size_override("font_size", 13)
	_prev_btn.pressed.connect(func(): _navigate(-1))
	_nav_bar.add_child(_prev_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_nav_bar.add_child(spacer)

	_next_btn = Button.new()
	_next_btn.text = "Next >"
	_next_btn.add_theme_font_size_override("font_size", 13)
	_next_btn.pressed.connect(func(): _navigate(1))
	_nav_bar.add_child(_next_btn)


# ---------------------------------------------------------------------------
# Step management
# ---------------------------------------------------------------------------

func _build_steps() -> void:
	_steps.clear()
	_steps.append({"title": "Level Up!", "build": _build_congrats_step})
	_steps.append({"title": "Hit Points", "build": _build_hp_step})
	_steps.append({"title": "Combat Advancement", "build": _build_combat_step})

	var new_class_slots: int = _level_up_result.get("new_class_proficiency_slots", 0)
	var new_general_slots: int = _level_up_result.get("new_general_proficiency_slots", 0)
	if new_class_slots > 0 or new_general_slots > 0:
		_steps.append({"title": "Proficiencies", "build": _build_proficiency_step})

	var new_spell_levels: Array = _level_up_result.get("new_spell_levels_unlocked", [])
	if not new_spell_levels.is_empty():
		_steps.append({"title": "Spells", "build": _build_spell_step})

	var new_powers: Array = _level_up_result.get("new_powers", [])
	if not new_powers.is_empty():
		_steps.append({"title": "New Abilities", "build": _build_powers_step})

	_steps.append({"title": "Summary", "build": _build_summary_step})


func _show_step(index: int) -> void:
	_current_step = clampi(index, 0, _steps.size() - 1)
	for child in _step_container.get_children():
		child.queue_free()

	_steps[_current_step]["build"].call()

	_prev_btn.visible = _current_step > 0
	var is_last := _current_step == _steps.size() - 1
	_next_btn.text = "Confirm" if is_last else "Next >"


func _navigate(direction: int) -> void:
	var new_index := _current_step + direction
	if new_index < 0:
		return
	if new_index >= _steps.size():
		_finalize()
		return
	_show_step(new_index)


func _finalize() -> void:
	if _level_up_engine == null or _character == null:
		return
	_level_up_engine.finalize_interactive_level_up(
		_character, _level_up_result, _player_choices)
	var char_id := _character.id
	close()
	level_up_completed.emit(char_id)


# ---------------------------------------------------------------------------
# Step builders
# ---------------------------------------------------------------------------

func _build_congrats_step() -> void:
	var title := _heading("Level Up!")
	_step_container.add_child(title)

	var new_level: int = _level_up_result.get("new_level", 0)
	var new_title: String = _level_up_result.get("new_title", "")
	var name_str: String = _character.name if _character else "Character"
	var class_str: String = _character.character_class if _character else ""

	_step_container.add_child(_body(
		"%s has reached Level %d!" % [name_str, new_level]))

	if not new_title.is_empty():
		_step_container.add_child(_body(
			"New title: %s" % new_title))

	_step_container.add_child(_body("Class: %s" % class_str.capitalize()))

	var next_xp: int = _level_up_result.get("new_xp_for_next_level", 0)
	if next_xp > 0:
		_step_container.add_child(_dim(
			"XP for next level: %s" % _format_number(next_xp)))


func _build_hp_step() -> void:
	_step_container.add_child(_heading("Hit Points"))
	var hp_gained: int = _level_up_result.get("hp_gained", 0)
	var new_max: int = _level_up_result.get("new_hp_max", 0)

	_step_container.add_child(_body("HP gained this level: +%d" % hp_gained))
	_step_container.add_child(_body("New HP maximum: %d" % new_max))


func _build_combat_step() -> void:
	_step_container.add_child(_heading("Combat Advancement"))

	var new_attack: int = _level_up_result.get("new_attack_throw", 0)
	_step_container.add_child(_body("Attack Throw: %d+" % new_attack))

	var saves: Dictionary = _level_up_result.get("new_saves", {})
	if not saves.is_empty():
		_step_container.add_child(_body("Saving Throws:"))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 16)
		grid.add_theme_constant_override("v_separation", 4)
		_step_container.add_child(grid)

		var save_names := {
			"petrification": "Petrification & Paralysis",
			"poison_death": "Poison & Death",
			"blast_breath": "Blast & Breath",
			"staffs_wands": "Staffs & Wands",
			"spells": "Spells",
		}
		for key in save_names:
			var val: int = saves.get(key, 0)
			grid.add_child(_dim(save_names[key]))
			grid.add_child(_body("%d+" % val))


func _build_proficiency_step() -> void:
	_step_container.add_child(_heading("New Proficiency Slots"))

	var class_slots: int = _level_up_result.get("new_class_proficiency_slots", 0)
	var general_slots: int = _level_up_result.get("new_general_proficiency_slots", 0)

	if class_slots > 0:
		_step_container.add_child(_body(
			"%d new class proficiency slot(s) available." % class_slots))
	if general_slots > 0:
		_step_container.add_child(_body(
			"%d new general proficiency slot(s) available." % general_slots))

	_step_container.add_child(_dim(
		"Proficiency selection is available in the Character Sheet after confirming level-up."))


func _build_spell_step() -> void:
	_step_container.add_child(_heading("New Spell Levels"))

	var new_levels: Array = _level_up_result.get("new_spell_levels_unlocked", [])
	for spell_level in new_levels:
		_step_container.add_child(_body(
			"Level %d spells are now available!" % spell_level))

	_step_container.add_child(_dim(
		"Spell selection is available in the Character Sheet after confirming level-up."))


func _build_powers_step() -> void:
	_step_container.add_child(_heading("New Abilities"))

	var powers: Array = _level_up_result.get("new_powers", [])
	for power_id in powers:
		var display_name: String = power_id.capitalize().replace("_", " ")
		_step_container.add_child(_body("  Unlocked: %s" % display_name))


func _build_summary_step() -> void:
	_step_container.add_child(_heading("Level-Up Summary"))

	var name_str: String = _character.name if _character else "Character"
	var new_level: int = _level_up_result.get("new_level", 0)

	_step_container.add_child(_body("%s is now Level %d" % [name_str, new_level]))
	_step_container.add_child(_body("HP: %d (+%d)" % [
		_level_up_result.get("new_hp_max", 0),
		_level_up_result.get("hp_gained", 0),
	]))
	_step_container.add_child(_body("Attack Throw: %d+" % _level_up_result.get("new_attack_throw", 0)))

	var class_slots: int = _level_up_result.get("new_class_proficiency_slots", 0)
	var general_slots: int = _level_up_result.get("new_general_proficiency_slots", 0)
	if class_slots > 0 or general_slots > 0:
		_step_container.add_child(_body(
			"New proficiency slots: %d class, %d general" % [class_slots, general_slots]))

	var new_powers: Array = _level_up_result.get("new_powers", [])
	if not new_powers.is_empty():
		_step_container.add_child(_body(
			"New abilities: %d" % new_powers.size()))

	_step_container.add_child(_dim("\nClick Confirm to apply all changes."))


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", HEADING_COLOR)
	return label


func _body(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", BODY_COLOR)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _dim(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", DIM_COLOR)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _format_number(n: int) -> String:
	var s := str(n)
	var result := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = s[i] + result
		count += 1
	return result
