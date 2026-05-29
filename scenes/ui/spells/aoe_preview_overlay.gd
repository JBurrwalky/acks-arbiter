extends CanvasLayer

## AoE confirmation modal — shown after the player anchors an area spell
## (Fireball, Cloudkill, Lightning Bolt, Burning Hands) but before the cast
## commits. Lists every entity caught in the area, calls out allies in red,
## and asks for explicit confirmation.
##
## Map-level cell highlighting (the warning-red overlay on the projected
## area) lives in the targeting controller / map renderer integration; this
## panel is the textual confirmation dialog.

signal confirmed
signal cancelled


var _root_panel: PanelContainer = null
var _summary_label: RichTextLabel = null


func _ready() -> void:
	layer = 60
	visible = false
	_build_ui()


func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.35)
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	add_child(center)

	_root_panel = PanelContainer.new()
	_root_panel.custom_minimum_size = Vector2(440, 240)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.10, 0.10, 0.97)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.55, 0.30, 0.20)
	_root_panel.add_theme_stylebox_override("panel", style)
	center.add_child(_root_panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	_root_panel.add_child(outer)

	var header := Label.new()
	header.text = "Confirm Area Spell"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 15)
	header.add_theme_color_override("font_color", Color(0.92, 0.65, 0.45))
	outer.add_child(header)

	outer.add_child(HSeparator.new())

	_summary_label = RichTextLabel.new()
	_summary_label.bbcode_enabled = true
	_summary_label.fit_content = true
	_summary_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_summary_label.custom_minimum_size = Vector2(0, 120)
	outer.add_child(_summary_label)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_child(btn_row)

	var confirm_btn := Button.new()
	confirm_btn.text = "Confirm"
	confirm_btn.pressed.connect(_on_confirm_pressed)
	btn_row.add_child(confirm_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(_on_cancel_pressed)
	btn_row.add_child(cancel_btn)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func setup(spell_name: String, affected: Array, ally_ids: Array) -> void:
	## affected: Array[Dictionary] of {id, name} for each entity in the AoE
	## ally_ids: Array[String] subset of affected.id that should be flagged
	visible = true
	var lines := PackedStringArray()
	lines.append("[b]%s[/b] will affect %d target(s):\n" % [spell_name, affected.size()])
	for entry in affected:
		var eid := str(entry.get("id", ""))
		var nm := str(entry.get("name", eid))
		if eid in ally_ids:
			lines.append("  [color=red]• %s (ally!)[/color]" % nm)
		else:
			lines.append("  • %s" % nm)
	_summary_label.text = "\n".join(lines)


func close() -> void:
	visible = false
	queue_free()


func _on_confirm_pressed() -> void:
	emit_signal("confirmed")
	close()


func _on_cancel_pressed() -> void:
	emit_signal("cancelled")
	close()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_on_cancel_pressed()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ENTER:
			_on_confirm_pressed()
			get_viewport().set_input_as_handled()
