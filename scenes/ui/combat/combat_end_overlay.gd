class_name CombatEndOverlay
extends PanelContainer

## Victory/defeat card shown when combat ends.
##
## Displays: outcome, rounds fought, XP earned, monsters defeated,
## downed PCs with mortal wound results.
## "Continue" button emits continue_pressed() to dismiss.


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal continue_pressed()


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const COLOR_VICTORY := Color(0.3, 0.8, 0.3)
const COLOR_DEFEAT  := Color(0.8, 0.2, 0.2)
const COLOR_FLED    := Color(0.8, 0.7, 0.2)


# ---------------------------------------------------------------------------
# Scene references
# ---------------------------------------------------------------------------

var _title_label: Label = null
var _rounds_label: Label = null
var _xp_label: Label = null
var _details_container: VBoxContainer = null
var _continue_btn: Button = null


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	custom_minimum_size = Vector2(420, 280)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.13, 0.95)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 14.0
	style.content_margin_bottom = 14.0
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.5, 0.5, 0.6)
	add_theme_stylebox_override("panel", style)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	add_child(outer)

	# Outcome title (VICTORY / DEFEAT / FLED)
	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 22)
	outer.add_child(_title_label)

	# Summary row: rounds + XP
	var summary_row := HBoxContainer.new()
	summary_row.alignment = BoxContainer.ALIGNMENT_CENTER
	summary_row.add_theme_constant_override("separation", 20)
	outer.add_child(summary_row)

	_rounds_label = Label.new()
	_rounds_label.add_theme_font_size_override("font_size", 12)
	_rounds_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	summary_row.add_child(_rounds_label)

	_xp_label = Label.new()
	_xp_label.add_theme_font_size_override("font_size", 12)
	_xp_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.4))
	summary_row.add_child(_xp_label)

	var sep := HSeparator.new()
	outer.add_child(sep)

	# Scrollable details area for downed PCs / mortal wounds
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	_details_container = VBoxContainer.new()
	_details_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details_container.add_theme_constant_override("separation", 6)
	scroll.add_child(_details_container)

	# Continue button
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_child(btn_row)

	_continue_btn = Button.new()
	_continue_btn.text = "Continue"
	_continue_btn.custom_minimum_size = Vector2(140, 36)
	_continue_btn.pressed.connect(_on_continue_pressed)
	btn_row.add_child(_continue_btn)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Show the combat end summary.
## [param result] Dict from CombatController.advance() when status == "combat_over":
##   {result, rounds, monster_xp_total, downed_pcs: [{combatant_id, mortal_wound_result}]}
func show_result(result: Dictionary) -> void:
	var outcome: String = result.get("result", "unknown")
	var rounds: int = result.get("rounds", 0)
	var xp: int = result.get("monster_xp_total", 0)
	var downed_pcs: Array = result.get("downed_pcs", [])

	# Title + colour
	match outcome:
		"victory":
			_title_label.text = "VICTORY"
			_title_label.add_theme_color_override("font_color", COLOR_VICTORY)
		"defeat":
			_title_label.text = "DEFEAT"
			_title_label.add_theme_color_override("font_color", COLOR_DEFEAT)
		"fled":
			_title_label.text = "PARTY FLED"
			_title_label.add_theme_color_override("font_color", COLOR_FLED)
		_:
			_title_label.text = outcome.to_upper()
			_title_label.add_theme_color_override("font_color", Color.WHITE)

	_rounds_label.text = "%d round%s" % [rounds, "" if rounds == 1 else "s"]
	_xp_label.text = "%d XP earned" % xp if outcome == "victory" else ""

	# Details: downed PCs and mortal wounds
	for child in _details_container.get_children():
		child.queue_free()

	if downed_pcs.is_empty() and outcome == "victory":
		var msg := Label.new()
		msg.text = "No casualties."
		msg.add_theme_font_size_override("font_size", 12)
		msg.add_theme_color_override("font_color", Color(0.6, 0.8, 0.6))
		_details_container.add_child(msg)
	else:
		for pc_entry in downed_pcs:
			_add_downed_pc_entry(pc_entry)

	visible = true


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _add_downed_pc_entry(pc_entry: Dictionary) -> void:
	var cid: String = pc_entry.get("combatant_id", "???")
	var mw: Dictionary = pc_entry.get("mortal_wound_result", {})

	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	_details_container.add_child(row)

	# Name + status
	var name_label := Label.new()
	var is_dead: bool = mw.get("is_dead", false)
	if is_dead:
		name_label.text = "%s — DEAD" % cid
		name_label.add_theme_color_override("font_color", Color(0.8, 0.2, 0.2))
	else:
		name_label.text = "%s — Downed" % cid
		name_label.add_theme_color_override("font_color", Color(0.8, 0.6, 0.3))
	name_label.add_theme_font_size_override("font_size", 12)
	row.add_child(name_label)

	# Mortal wound description
	var wound_desc: String = mw.get("wound_description", "")
	if not wound_desc.is_empty():
		var wound_label := Label.new()
		wound_label.text = "  %s" % wound_desc
		wound_label.add_theme_font_size_override("font_size", 10)
		wound_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		wound_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(wound_label)

	# Recovery time
	var recovery: Dictionary = mw.get("recovery_time", {})
	if not recovery.is_empty() and not is_dead:
		var rec_val: int = recovery.get("value", 0)
		var rec_unit: String = recovery.get("unit", "days")
		var rec_label := Label.new()
		rec_label.text = "  Recovery: %d %s" % [rec_val, rec_unit]
		rec_label.add_theme_font_size_override("font_size", 10)
		rec_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		row.add_child(rec_label)

	# Separator between PCs
	var sep := HSeparator.new()
	_details_container.add_child(sep)


func _on_continue_pressed() -> void:
	continue_pressed.emit()
