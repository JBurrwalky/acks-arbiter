class_name EncounterDecisionPrompt
extends CanvasLayer

## Modal that asks the player how to handle a wilderness encounter.
##
## Disposition-keyed button matrix:
##   hostile / unfriendly  → [Stand & Fight, Attempt Evasion]
##   neutral / friendly    → [Engage, Parley, Continue Travel]
##   indifferent           → [Engage, Continue Travel]
##
## Usage:
##   var prompt := EncounterDecisionPrompt.new()
##   add_child(prompt)
##   var choice: String = await prompt.open(encounter_data)
##   # choice is one of "fight" | "evade" | "engage" | "parley" | "continue"
##
## Vellum chrome via UiSurfaceStyles, mirroring ConfirmationPrompt.

signal decided(choice: String)

const PANEL_WIDTH := 480
const PANEL_MIN_HEIGHT := 220
const HEADING_COLOR := Color(0.95, 0.90, 0.78, 1.0)
const BODY_COLOR := Color(0.85, 0.80, 0.70, 1.0)

const CHOICE_FIGHT := "fight"
const CHOICE_EVADE := "evade"
const CHOICE_ENGAGE := "engage"
const CHOICE_PARLEY := "parley"
const CHOICE_CONTINUE := "continue"

var _backdrop: ColorRect = null
var _panel: PanelContainer = null
var _title_label: Label = null
var _body_label: Label = null
var _btn_bar: HBoxContainer = null


func _ready() -> void:
	layer = 180
	_build_ui()
	_hide_all()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Open the prompt for [param encounter_data]. Awaits a button press and
## emits `decided(choice)`. The caller can `await prompt.decided` to receive
## the choice, or chain through the returned signal directly.
func open(encounter_data: Dictionary) -> void:
	var disposition: String = String(encounter_data.get("behavioral_disposition", "")).to_lower()
	var count: int = int(encounter_data.get("number", 1))
	var monster: String = String(encounter_data.get("monster_group", "unknown"))
	if monster.is_empty():
		monster = "unknown"
	var label: String = monster
	if count > 1 and not monster.ends_with("s"):
		label = monster + "s"

	_title_label.text = "%d× %s" % [count, label]
	_body_label.text = _flavor_for_disposition(disposition,
		int(encounter_data.get("reaction_roll", 0)))

	_clear_buttons()
	_populate_buttons(disposition)

	_show_all()


func close() -> void:
	_hide_all()


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	_backdrop = ColorRect.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = Color(0.0, 0.0, 0.0, 0.5)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_backdrop)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_MIN_HEIGHT)
	_panel.offset_left = -PANEL_WIDTH / 2
	_panel.offset_right = PANEL_WIDTH / 2
	_panel.offset_top = -PANEL_MIN_HEIGHT / 2
	_panel.offset_bottom = PANEL_MIN_HEIGHT / 2
	UiSurfaceStyles.apply_framed_window_chrome(_panel)
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 16)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 20)
	_title_label.add_theme_color_override("font_color", HEADING_COLOR)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title_label)

	_body_label = Label.new()
	_body_label.add_theme_font_size_override("font_size", 13)
	_body_label.add_theme_color_override("font_color", BODY_COLOR)
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_body_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	_btn_bar = HBoxContainer.new()
	_btn_bar.add_theme_constant_override("separation", 12)
	_btn_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(_btn_bar)


## Disposition → button matrix. Returns an Array of `{text, choice}` dicts in
## display order. Pure data so the matrix is unit-testable without spinning
## up the SceneTree.
static func buttons_for_disposition(disposition: String) -> Array:
	match disposition.to_lower():
		"hostile", "unfriendly":
			return [
				{"text": "Stand & Fight", "choice": CHOICE_FIGHT},
				{"text": "Attempt Evasion", "choice": CHOICE_EVADE},
			]
		"indifferent":
			return [
				{"text": "Engage", "choice": CHOICE_ENGAGE},
				{"text": "Continue Travel", "choice": CHOICE_CONTINUE},
			]
		"neutral", "friendly":
			return [
				{"text": "Engage", "choice": CHOICE_ENGAGE},
				{"text": "Parley", "choice": CHOICE_PARLEY},
				{"text": "Continue Travel", "choice": CHOICE_CONTINUE},
			]
		_:
			# Unknown disposition — safest fallback is the hostile path.
			return [
				{"text": "Stand & Fight", "choice": CHOICE_FIGHT},
				{"text": "Attempt Evasion", "choice": CHOICE_EVADE},
			]


func _populate_buttons(disposition: String) -> void:
	for spec in buttons_for_disposition(disposition):
		_add_button(String(spec["text"]), String(spec["choice"]))


func _add_button(text: String, choice: String) -> void:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 14)
	btn.custom_minimum_size = Vector2(120, 36)
	btn.pressed.connect(_on_button_pressed.bind(choice))
	_btn_bar.add_child(btn)


func _clear_buttons() -> void:
	for child in _btn_bar.get_children():
		child.queue_free()


# ---------------------------------------------------------------------------
# Body text
# ---------------------------------------------------------------------------

func _flavor_for_disposition(disposition: String, reaction_roll: int) -> String:
	match disposition:
		"hostile":
			return "Hostile reaction (rolled %d). They mean to attack." % reaction_roll
		"unfriendly":
			return "Unfriendly reaction (rolled %d). They look likely to attack." % reaction_roll
		"neutral":
			return "Neutral reaction (rolled %d). Their intentions are uncertain." % reaction_roll
		"indifferent":
			return "Indifferent reaction (rolled %d). They have no quarrel with you." % reaction_roll
		"friendly":
			return "Friendly reaction (rolled %d). They seem well-disposed." % reaction_roll
		_:
			return "Reaction unclear (rolled %d)." % reaction_roll


# ---------------------------------------------------------------------------
# Handlers
# ---------------------------------------------------------------------------

func _on_button_pressed(choice: String) -> void:
	_hide_all()
	decided.emit(choice)


func _show_all() -> void:
	_backdrop.visible = true
	_panel.visible = true


func _hide_all() -> void:
	_backdrop.visible = false
	_panel.visible = false
