class_name DialogueScreen
extends CanvasLayer

## The dialogue UI shell (gdd-npc-dialogue.md §14). Shares visual language with
## EncounterScreen. Follows the DialogueScreen.open(session) static-entry
## precedent (EncounterScreen / CombatController). Phase 1 layout:
##   Left  — NPC name + attitude band indicator.
##   Center— scrolling transcript.
##   Bottom— grouped move menu (eligible_moves) + free-text box.
##
## The screen drives a DialogueSession: eligible_moves() -> buttons; a click calls
## session.submit_move(). Terminal replies close the screen and, for a combat
## outcome, emit combat_requested with the seed so the owning state performs the
## real transition (the DialogueSession only assembles the seed — combat transition
## is stubbed inside the session per §12.1).
##
## No LLM in Phase 1 — lines come from DialogueTemplateProvider via the session.

signal dialogue_closed(outcome: Dictionary)
signal combat_requested(combat_seed: Dictionary)

const HEADING_COLOR := Color(0.95, 0.90, 0.78, 1.0)
const BODY_COLOR := Color(0.85, 0.80, 0.70, 1.0)
const DIM_COLOR := Color(0.55, 0.50, 0.42, 1.0)
const HOSTILE_COLOR := Color(0.75, 0.22, 0.18, 1.0)
const FRIENDLY_COLOR := Color(0.25, 0.60, 0.30, 1.0)
const NEUTRAL_COLOR := Color(0.60, 0.58, 0.52, 1.0)

var _session: DialogueSession = null
var _transcript: RichTextLabel = null
var _move_panel: VBoxContainer = null
var _attitude_label: Label = null
var _free_text: LineEdit = null


## Static entry: instantiate the screen, add it to `parent`, bind the session.
static func open(session: DialogueSession, parent: Node) -> DialogueScreen:
	var screen: DialogueScreen = preload("res://scenes/ui/dialogue/dialogue_screen.tscn").instantiate()
	parent.add_child(screen)
	screen.bind(session)
	return screen


func _ready() -> void:
	layer = 50


## Bind a session and build the UI. Separated from open() so tests can construct
## the screen directly.
func bind(session: DialogueSession) -> void:
	_session = session
	_build_ui()
	_refresh()


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

	# Left: NPC info + attitude band.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(200, 0)
	left.add_theme_constant_override("separation", 8)
	columns.add_child(left)

	var name_label := Label.new()
	name_label.text = _session._npc_name() if _session != null else "NPC"
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", HEADING_COLOR)
	left.add_child(name_label)

	_attitude_label = Label.new()
	_attitude_label.add_theme_font_size_override("font_size", 13)
	left.add_child(_attitude_label)

	# Center: transcript.
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(center)

	_transcript = RichTextLabel.new()
	_transcript.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_transcript.bbcode_enabled = true
	_transcript.scroll_following = true
	_transcript.add_theme_color_override("default_color", BODY_COLOR)
	_transcript.add_theme_font_size_override("normal_font_size", 13)
	center.add_child(_transcript)

	_free_text = LineEdit.new()
	_free_text.placeholder_text = "Say something (optional)…"
	center.add_child(_free_text)

	# Right: move menu.
	_move_panel = VBoxContainer.new()
	_move_panel.custom_minimum_size = Vector2(200, 0)
	_move_panel.add_theme_constant_override("separation", 6)
	columns.add_child(_move_panel)


# ---------------------------------------------------------------------------
# Refresh / interaction
# ---------------------------------------------------------------------------

func _refresh() -> void:
	if _session == null:
		return
	_attitude_label.text = "Attitude: %s" % _session._attitude.capitalize()
	_attitude_label.add_theme_color_override("font_color", _attitude_color(_session._attitude))
	_rebuild_moves()


func _rebuild_moves() -> void:
	for child in _move_panel.get_children():
		child.queue_free()
	var heading := Label.new()
	heading.text = "Moves"
	heading.add_theme_font_size_override("font_size", 15)
	heading.add_theme_color_override("font_color", HEADING_COLOR)
	_move_panel.add_child(heading)

	for move in _session.eligible_moves():
		var btn := Button.new()
		var label: String = move.get("label", move.get("id", "?"))
		var locked: bool = bool(move.get("_ladder_locked", false))
		if locked:
			label += " (wait)"
			btn.disabled = true
		btn.text = label
		btn.add_theme_font_size_override("font_size", 13)
		btn.custom_minimum_size = Vector2(180, 30)
		var move_id: String = move.get("id", "")
		btn.pressed.connect(func(): _on_move_pressed(move_id))
		_move_panel.add_child(btn)


func _on_move_pressed(move_id: String) -> void:
	var free_text := _free_text.text if _free_text != null else ""
	var reply: Dictionary = _session.submit_move(move_id, free_text)
	if _free_text != null:
		_free_text.text = ""
	if reply.get("rejected", false):
		return
	# Append the rendered line to the transcript.
	_append_line(reply.get("line", ""))
	if reply.get("terminal", false):
		_on_terminal(reply)
	else:
		_refresh()


func _on_terminal(reply: Dictionary) -> void:
	var outcome: Dictionary = _session.close_outcome
	if reply.get("becomes_combat", false):
		var seed: Dictionary = outcome.get("combat_seed", {})
		combat_requested.emit(seed)
	dialogue_closed.emit(outcome)
	queue_free()


func _append_line(text: String) -> void:
	if _transcript == null or text.is_empty():
		return
	if not _transcript.text.is_empty():
		_transcript.text += "\n\n"
	_transcript.text += text


func _attitude_color(attitude: String) -> Color:
	match attitude:
		"hostile", "unfriendly": return HOSTILE_COLOR
		"friendly", "indifferent", "cowed": return FRIENDLY_COLOR
		"fearful": return HOSTILE_COLOR
	return NEUTRAL_COLOR
