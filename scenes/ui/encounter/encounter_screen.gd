class_name EncounterScreen
extends CanvasLayer

## NPC encounter/social interaction screen.
##
## Layout: NPC info (left), narrative area (center), interaction controls (right).
## Wraps InteractionResolver for reaction rolls and influence checks.

signal encounter_resolved(result: Dictionary)
signal combat_requested
signal flee_requested

const HEADING_COLOR := Color(0.95, 0.90, 0.78, 1.0)
const BODY_COLOR := Color(0.85, 0.80, 0.70, 1.0)
const DIM_COLOR := Color(0.55, 0.50, 0.42, 1.0)
const HOSTILE_COLOR := Color(0.75, 0.22, 0.18, 1.0)
const FRIENDLY_COLOR := Color(0.25, 0.60, 0.30, 1.0)
const NEUTRAL_COLOR := Color(0.60, 0.58, 0.52, 1.0)

var _encounter_data: Dictionary = {}
var _reaction_result: int = 0
var _attitude: String = "neutral"
var _content: VBoxContainer = null
var _action_panel: VBoxContainer = null
var _narrative_area: RichTextLabel = null


func _ready() -> void:
	layer = 50


func setup(encounter_data: Dictionary) -> void:
	_encounter_data = encounter_data
	_roll_initial_reaction()
	_build_ui()


# ---------------------------------------------------------------------------
# Reaction roll
# ---------------------------------------------------------------------------

func _roll_initial_reaction() -> void:
	var roll := DiceSystem.roll_digital(6, 2, 0, "reaction")
	_reaction_result = roll.modified_total

	# Map reaction to attitude (ACKS reaction table).
	if _reaction_result <= 2:
		_attitude = "hostile"
	elif _reaction_result <= 5:
		_attitude = "unfriendly"
	elif _reaction_result <= 8:
		_attitude = "neutral"
	elif _reaction_result <= 11:
		_attitude = "indifferent"
	else:
		_attitude = "friendly"


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	for child in get_children():
		child.queue_free()

	var bg := PanelContainer.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	UiSurfaceStyles.apply_framed_window_chrome(bg)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	bg.add_child(margin)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	margin.add_child(columns)

	# Left: NPC info.
	_build_npc_info(columns)

	# Center: narrative.
	_build_narrative_area(columns)

	# Right: actions.
	_build_action_panel(columns)


func _build_npc_info(parent: Control) -> void:
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(200, 0)
	panel.add_theme_constant_override("separation", 8)
	parent.add_child(panel)

	# Portrait placeholder.
	var portrait := ColorRect.new()
	portrait.custom_minimum_size = Vector2(120, 120)
	portrait.color = Color(0.25, 0.22, 0.18, 0.8)
	panel.add_child(portrait)

	var monster_group: String = _encounter_data.get("monster_group", "Unknown")
	panel.add_child(_heading(monster_group.capitalize()))

	var number: int = _encounter_data.get("number", 1)
	if number > 1:
		panel.add_child(_body("Count: %d" % number))

	# Reaction result.
	var reaction_label := Label.new()
	reaction_label.text = "Reaction: %d (%s)" % [_reaction_result, _attitude.capitalize()]
	reaction_label.add_theme_font_size_override("font_size", 13)
	var att_color := NEUTRAL_COLOR
	match _attitude:
		"hostile": att_color = HOSTILE_COLOR
		"unfriendly": att_color = HOSTILE_COLOR
		"friendly": att_color = FRIENDLY_COLOR
		"indifferent": att_color = FRIENDLY_COLOR
	reaction_label.add_theme_color_override("font_color", att_color)
	panel.add_child(reaction_label)

	# Attitude ladder.
	var ladder := _build_attitude_ladder()
	panel.add_child(ladder)


func _build_attitude_ladder() -> VBoxContainer:
	var ladder := VBoxContainer.new()
	ladder.add_theme_constant_override("separation", 2)

	var tiers := ["Hostile", "Unfriendly", "Neutral", "Indifferent", "Friendly"]
	var tier_colors := [HOSTILE_COLOR, HOSTILE_COLOR, NEUTRAL_COLOR, FRIENDLY_COLOR, FRIENDLY_COLOR]

	for i in range(tiers.size()):
		var tier_name: String = tiers[i]
		var is_current: bool = _attitude == tier_name.to_lower()

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		ladder.add_child(row)

		var indicator := Label.new()
		indicator.text = ">" if is_current else " "
		indicator.add_theme_font_size_override("font_size", 11)
		indicator.add_theme_color_override("font_color", tier_colors[i])
		indicator.custom_minimum_size = Vector2(12, 0)
		row.add_child(indicator)

		var label := Label.new()
		label.text = tier_name
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color",
			tier_colors[i] if is_current else DIM_COLOR)
		row.add_child(label)

	return ladder


func _build_narrative_area(parent: Control) -> void:
	var panel := VBoxContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_constant_override("separation", 8)
	parent.add_child(panel)

	panel.add_child(_heading("Encounter"))

	_narrative_area = RichTextLabel.new()
	_narrative_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_narrative_area.bbcode_enabled = true
	_narrative_area.scroll_following = true
	_narrative_area.add_theme_color_override("default_color", BODY_COLOR)
	_narrative_area.add_theme_font_size_override("normal_font_size", 13)
	panel.add_child(_narrative_area)

	# Initial narrative.
	var monster: String = _encounter_data.get("monster_group", "creatures")
	_narrative_area.text = (
		"You encounter %d %s. Their initial disposition appears %s."
		% [_encounter_data.get("number", 1), monster, _attitude])


func _build_action_panel(parent: Control) -> void:
	_action_panel = VBoxContainer.new()
	_action_panel.custom_minimum_size = Vector2(180, 0)
	_action_panel.add_theme_constant_override("separation", 8)
	parent.add_child(_action_panel)

	_action_panel.add_child(_heading("Actions"))

	# Context-dependent actions based on attitude.
	match _attitude:
		"hostile":
			_add_action_btn("Fight", func(): combat_requested.emit())
			_add_action_btn("Flee", func(): flee_requested.emit())
		"unfriendly":
			_add_action_btn("Parley", func(): _attempt_influence("parley"))
			_add_action_btn("Intimidate", func(): _attempt_influence("intimidate"))
			_add_action_btn("Fight", func(): combat_requested.emit())
			_add_action_btn("Flee", func(): flee_requested.emit())
		"neutral":
			_add_action_btn("Parley", func(): _attempt_influence("parley"))
			_add_action_btn("Bribe", func(): _attempt_influence("bribe"))
			_add_action_btn("Fight", func(): _confirm_attack())
			_add_action_btn("Leave", func(): _resolve_peacefully())
		"indifferent", "friendly":
			_add_action_btn("Trade", func(): _resolve_peacefully())
			_add_action_btn("Ask Rumor", func(): _resolve_peacefully())
			_add_action_btn("Hire", func(): _resolve_peacefully())
			_add_action_btn("Leave", func(): _resolve_peacefully())


func _add_action_btn(text: String, callback: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 13)
	btn.custom_minimum_size = Vector2(160, 32)
	btn.pressed.connect(callback)
	_action_panel.add_child(btn)


# ---------------------------------------------------------------------------
# Interaction handlers
# ---------------------------------------------------------------------------

func _attempt_influence(tone: String) -> void:
	var roll := DiceSystem.roll_digital(6, 2, 0, "reaction")
	var new_reaction := roll.modified_total

	_narrative_area.text += "\n\nYou attempt to %s. Roll: %d." % [tone, new_reaction]

	if new_reaction >= 9:
		_attitude = "indifferent"
		_narrative_area.text += " They seem more receptive."
	elif new_reaction <= 3:
		_attitude = "hostile"
		_narrative_area.text += " They become hostile!"

	# Rebuild actions for new attitude.
	for child in _action_panel.get_children():
		child.queue_free()
	_build_action_panel(_action_panel.get_parent())


func _confirm_attack() -> void:
	# In a full implementation, show ConfirmationPrompt before attacking neutrals.
	combat_requested.emit()


func _resolve_peacefully() -> void:
	encounter_resolved.emit({
		"target_id": _encounter_data.get("encounter_id", ""),
		"outcome": "peaceful",
		"attitude": _attitude,
		"reaction_roll": _reaction_result,
	})


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", HEADING_COLOR)
	return label

func _body(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", BODY_COLOR)
	return label
