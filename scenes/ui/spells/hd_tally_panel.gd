extends CanvasLayer

## Side panel showing live HD-budget state during HD-budget targeting (Sleep
## group branch, Charm Monster group branch, Death Spell, Smite Undead). Reads
## state from a TargetingController instance and re-renders on demand.
##
## Integration note: this panel is a view over TargetingController. The map-
## level highlighting (red strike-through for over-cap, green for selected,
## yellow for available) lives in the map renderer's targeting overlay; the
## panel is a textual mirror. Full integration with the voxel combat grid is
## a Session 2.5+ task — for now it ships with a clean public API so the
## targeting flow can drive it as soon as the renderer surface lands.

signal selection_changed
signal confirmed
signal cancelled
## Emitted when the player rescinds the spell declaration (returns slot).
signal rescinded


var _controller = null  # TargetingController
var _spell_name: String = ""

var _root_panel: PanelContainer = null
var _budget_label: Label = null
var _selected_list: VBoxContainer = null
var _candidate_list: VBoxContainer = null
var _rescind_btn: Button = null


func _ready() -> void:
	layer = 56  # Same as picker — only one is visible at a time per cast.
	visible = false
	_build_ui()


func _build_ui() -> void:
	var anchor := MarginContainer.new()
	anchor.anchor_top = 0.0
	anchor.anchor_bottom = 1.0
	anchor.anchor_left = 0.7
	anchor.anchor_right = 1.0
	anchor.add_theme_constant_override("margin_left", 8)
	anchor.add_theme_constant_override("margin_right", 8)
	anchor.add_theme_constant_override("margin_top", 8)
	anchor.add_theme_constant_override("margin_bottom", 8)
	add_child(anchor)

	_root_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.10, 0.95)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_root_panel.add_theme_stylebox_override("panel", style)
	anchor.add_child(_root_panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	_root_panel.add_child(outer)

	_budget_label = Label.new()
	_budget_label.add_theme_font_size_override("font_size", 13)
	_budget_label.add_theme_color_override("font_color", Color(0.85, 0.78, 0.50))
	outer.add_child(_budget_label)

	outer.add_child(HSeparator.new())

	var sel_header := Label.new()
	sel_header.text = "Selected:"
	sel_header.add_theme_font_size_override("font_size", 11)
	outer.add_child(sel_header)

	_selected_list = VBoxContainer.new()
	outer.add_child(_selected_list)

	outer.add_child(HSeparator.new())

	var cand_header := Label.new()
	cand_header.text = "Candidates:"
	cand_header.add_theme_font_size_override("font_size", 11)
	outer.add_child(cand_header)

	_candidate_list = VBoxContainer.new()
	outer.add_child(_candidate_list)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_child(btn_row)

	var rescind_btn := Button.new()
	rescind_btn.text = "Rescind"
	rescind_btn.tooltip_text = "Return the spell slot and cancel casting"
	rescind_btn.pressed.connect(_on_rescind_pressed)
	btn_row.add_child(rescind_btn)
	_rescind_btn = rescind_btn

	var reset_btn := Button.new()
	reset_btn.text = "Reset all"
	reset_btn.pressed.connect(_on_reset_pressed)
	btn_row.add_child(reset_btn)

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

func setup(controller, spell_name: String) -> void:
	# Disconnect from any previous controller before re-binding.
	if _controller != null and _controller.selection_changed.is_connected(refresh):
		_controller.selection_changed.disconnect(refresh)
	_controller = controller
	_spell_name = spell_name
	if _controller != null:
		_controller.selection_changed.connect(refresh)
	visible = true
	refresh()


func refresh() -> void:
	if _controller == null:
		return
	var selection_empty: bool = _controller.get_selected().is_empty()
	if _controller.has_hd_budget():
		_budget_label.text = "%s — Budget: %.1f / %.1f HD" % [
			_spell_name,
			_controller.get_budget_remaining(),
			_controller.get_budget_total()]
	else:
		_budget_label.text = "%s — Selecting Targets" % _spell_name

	for child in _selected_list.get_children():
		child.queue_free()
	for sid in _controller.get_selected():
		var info: Dictionary = _controller.get_candidate_info(sid)
		var lbl := Label.new()
		var entity = info.get("entity", null)
		var name_str := _entity_name(entity, sid)
		lbl.text = "  • %s (%.1f HD)" % [name_str, info.get("counted_hd", 0.0)]
		_selected_list.add_child(lbl)

	for child in _candidate_list.get_children():
		child.queue_free()
	for cid in _controller.get_eligible_candidates():
		if cid in _controller.get_selected():
			continue
		var info: Dictionary = _controller.get_candidate_info(cid)
		var entity = info.get("entity", null)
		var name_str := _entity_name(entity, cid)
		var lbl := Label.new()
		lbl.text = "  · %s (%.1f HD)" % [name_str, info.get("counted_hd", 0.0)]
		_candidate_list.add_child(lbl)

	# Rescind button only available when no selection has been made (Session 2.9).
	if _rescind_btn != null:
		_rescind_btn.visible = selection_empty


func close() -> void:
	if _controller != null and _controller.selection_changed.is_connected(refresh):
		_controller.selection_changed.disconnect(refresh)
	_controller = null
	visible = false
	queue_free()


# ---------------------------------------------------------------------------
# Internal handlers
# ---------------------------------------------------------------------------

func _on_reset_pressed() -> void:
	if _controller != null:
		_controller.reset_selection()
		refresh()
		emit_signal("selection_changed")


func _on_confirm_pressed() -> void:
	emit_signal("confirmed")
	close()


func _on_cancel_pressed() -> void:
	emit_signal("cancelled")
	close()


func _on_rescind_pressed() -> void:
	emit_signal("rescinded")
	close()


func _entity_name(entity: Variant, fallback_id: String) -> String:
	if entity is CharacterData:
		return entity.name
	if entity is Dictionary:
		return String(entity.get("name", entity.get("monster_id", fallback_id)))
	return fallback_id
