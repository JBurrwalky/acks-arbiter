class_name SettingsScreen
extends CanvasLayer

## Settings screen — pushed onto NavigationStack from Main Menu or Pause Menu.
##
## Sections: Dice Mode, Display (read-only for now), Audio (stubs),
## Key Bindings (read-only for v1), LLM Provider (placeholder).

signal settings_closed

const SECTION_FONT_SIZE := 16
const LABEL_FONT_SIZE := 13
const LABEL_COLOR := Color(0.85, 0.80, 0.70, 1.0)
const HEADING_COLOR := Color(0.95, 0.90, 0.80, 1.0)
const DIM_COLOR := Color(0.55, 0.50, 0.42, 1.0)

var _dice_mode_group: ButtonGroup = null


func _ready() -> void:
	layer = 50
	_build_ui()


# ---------------------------------------------------------------------------
# NavigationStack duck-type interface
# ---------------------------------------------------------------------------

func enter(_params: Dictionary = {}) -> void:
	visible = true


func exit() -> void:
	visible = false


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var bg := PanelContainer.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	UiSurfaceStyles.apply_framed_window_chrome(bg)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	bg.add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 12)
	scroll.add_child(vbox)

	# Title bar.
	var title_bar := HBoxContainer.new()
	vbox.add_child(title_bar)

	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", HEADING_COLOR)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_bar.add_child(title)

	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.add_theme_font_size_override("font_size", 14)
	back_btn.pressed.connect(func():
		settings_closed.emit()
		# If on NavigationStack, pop self.
		if NavigationStack.instance != null:
			NavigationStack.instance.pop()
	)
	title_bar.add_child(back_btn)

	_add_separator(vbox)
	_build_dice_mode_section(vbox)
	_add_separator(vbox)
	_build_display_section(vbox)
	_add_separator(vbox)
	_build_audio_section(vbox)
	_add_separator(vbox)
	_build_keybindings_section(vbox)
	_add_separator(vbox)
	_build_llm_section(vbox)


func _add_separator(parent: Control) -> void:
	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", UiSurfaceStyles.FRAME_BORDER_COLOR)
	parent.add_child(sep)


func _section_heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", SECTION_FONT_SIZE)
	label.add_theme_color_override("font_color", HEADING_COLOR)
	return label


func _info_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	label.add_theme_color_override("font_color", LABEL_COLOR)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _dim_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", DIM_COLOR)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


# ---------------------------------------------------------------------------
# Dice Mode
# ---------------------------------------------------------------------------

func _build_dice_mode_section(parent: Control) -> void:
	parent.add_child(_section_heading("Dice Mode"))
	parent.add_child(_info_label(
		"Choose how dice rolls are resolved during play."))

	_dice_mode_group = ButtonGroup.new()

	var modes := [
		["Digital", "All rolls are handled automatically by the engine.",
		 GameState.DiceMode.DIGITAL],
		["Physical", "You are always prompted to enter results from physical dice.",
		 GameState.DiceMode.PHYSICAL],
		["Hybrid", "Player-facing rolls (attacks, saves, skills) prompt for physical dice. "
		 + "NPC/GM rolls (encounters, morale, reactions) are automatic.",
		 GameState.DiceMode.HYBRID],
	]

	for mode_info in modes:
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)
		parent.add_child(hbox)

		var radio := CheckBox.new()
		radio.text = mode_info[0]
		radio.button_group = _dice_mode_group
		radio.button_pressed = (GameState.dice_mode == mode_info[2])
		radio.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
		radio.add_theme_color_override("font_color", LABEL_COLOR)
		var mode_value: int = mode_info[2]
		radio.toggled.connect(func(pressed: bool):
			if pressed:
				GameState.set_dice_mode(mode_value)
				GameState.save_settings()
		)
		hbox.add_child(radio)

		var desc := _dim_label(mode_info[1])
		desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(desc)


# ---------------------------------------------------------------------------
# Display
# ---------------------------------------------------------------------------

func _build_display_section(parent: Control) -> void:
	parent.add_child(_section_heading("Display"))

	var res_label := _info_label(
		"Resolution: %dx%d" % [
			DisplayServer.window_get_size().x,
			DisplayServer.window_get_size().y,
		])
	parent.add_child(res_label)
	parent.add_child(_dim_label("Resolution and UI scaling options will be available in a future update."))


# ---------------------------------------------------------------------------
# Audio
# ---------------------------------------------------------------------------

func _build_audio_section(parent: Control) -> void:
	parent.add_child(_section_heading("Audio"))
	parent.add_child(_dim_label("Audio controls will be available when the audio system is implemented."))


# ---------------------------------------------------------------------------
# Key Bindings
# ---------------------------------------------------------------------------

## Mapping of input-action name → human-readable label, in display order.
## Keys are looked up against the live InputMap so re-binds (and additions
## like the Phase α.2 single-letter notebook toggles) reflect automatically.
const _ACTION_LABELS: Array = [
	# Notebook tabs (Phase β single-letter binds).
	["notebook_toggle_character", "Notebook: Character"],
	["notebook_toggle_inventory", "Notebook: Inventory"],
	["notebook_toggle_party", "Notebook: Party"],
	["notebook_toggle_henchmen", "Notebook: Henchmen"],
	["notebook_toggle_troops", "Notebook: Troops"],
	["notebook_toggle_domain", "Notebook: Domain"],
	["notebook_toggle_journal", "Notebook: Journal"],
	["notebook_toggle_quests", "Notebook: Quests"],
	["unified_log_cycle", "Log: cycle tabs"],
	["ui_cancel", "Pause Menu / Cancel"],
	# Developer / debugging.
	["override_panel_toggle", "Dev: Override Panel"],
	["dev_char_creation", "Dev: Character Creation"],
	["dev_dice_test", "Dev: Dice Prompt Test"],
]


func _build_keybindings_section(parent: Control) -> void:
	parent.add_child(_section_heading("Key Bindings"))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 4)
	parent.add_child(grid)

	for entry in _ACTION_LABELS:
		var action_name: String = entry[0]
		var display_name: String = entry[1]
		if not InputMap.has_action(action_name):
			continue

		var key_text := _format_action_keys(action_name)
		if key_text.is_empty():
			continue

		var key_label := Label.new()
		key_label.text = key_text
		key_label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
		key_label.add_theme_color_override("font_color", HEADING_COLOR)
		key_label.custom_minimum_size = Vector2(120, 0)
		grid.add_child(key_label)

		var action_label := Label.new()
		action_label.text = display_name
		action_label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
		action_label.add_theme_color_override("font_color", LABEL_COLOR)
		grid.add_child(action_label)

	parent.add_child(_dim_label("Custom key bindings will be available in a future update."))


## Returns a human-readable shortcut for the first key event bound to
## [param action_name]. Empty string if the action has no key event.
func _format_action_keys(action_name: String) -> String:
	for ev in InputMap.action_get_events(action_name):
		if ev is InputEventKey:
			return _format_key_event(ev as InputEventKey)
	return ""


func _format_key_event(ev: InputEventKey) -> String:
	var parts: Array[String] = []
	if ev.ctrl_pressed:
		parts.append("Ctrl")
	if ev.alt_pressed:
		parts.append("Alt")
	if ev.shift_pressed:
		parts.append("Shift")
	if ev.meta_pressed:
		parts.append("Meta")

	# Prefer the physical keycode label (independent of OS keymap); fall back
	# to keycode then unicode.
	var key_string := OS.get_keycode_string(ev.physical_keycode)
	if key_string.is_empty():
		key_string = OS.get_keycode_string(ev.keycode)
	if key_string.is_empty() and ev.unicode != 0:
		key_string = char(ev.unicode).to_upper()
	if key_string.is_empty():
		return ""

	parts.append(key_string)
	return "+".join(parts)


# ---------------------------------------------------------------------------
# LLM Provider
# ---------------------------------------------------------------------------

func _build_llm_section(parent: Control) -> void:
	parent.add_child(_section_heading("LLM Provider"))
	parent.add_child(_dim_label(
		"LLM provider configuration (cloud API, local model, or offline mode) "
		+ "will be available in Phase J of development. The game currently uses "
		+ "template-based narration for all text."))
