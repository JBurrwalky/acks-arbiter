class_name FamiliarPicker
extends VBoxContainer

## Stage 3a — Familiar acquisition picker (form / cosmetic variant / name).
##
## Pure-code panel; instantiate with `FamiliarPicker.new()` and call `setup`.
## Surfaces three fields the player chooses when bonding a familiar:
##   1. Form (bat / hawk / cat / rat / snake_small / toad / weasel)
##   2. Cosmetic species variant — only enabled when the selected form has more
##      than one variant (e.g. Hawk → Hawk/Raven/Eagle/Falcon/Owl)
##   3. Name
##
## State Dictionary shape (mutated in-place to preserve picks across step nav):
##   {
##     "form_key":         String,  # one of FamiliarFormRegistry.get_all_form_keys()
##     "cosmetic_species": String,  # variant pick from form's cosmetic_variants
##     "name":             String,
##   }
##
## `is_complete()` is true when all three fields are filled.
##
## **Stage 3a scope:** form / cosmetic / name only. The familiar-specific
## proficiency picker (per gdd-familiars.md §3.4.1) is Stage 3b — it slots into
## the right column when the player has finished choosing the form.

signal picker_changed

const SELECTED_FORM_TEXT_COLOR := Color(1.0, 0.85, 0.3, 1.0)

var _state: Dictionary = {}
var _registry: FamiliarFormRegistry

var _form_buttons: Dictionary = {}            # form_key → Button
var _selected_form_key: String = ""

var _cosmetic_dropdown: OptionButton
var _name_field: LineEdit
var _detail_area: VBoxContainer


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func setup(state: Dictionary, registry: FamiliarFormRegistry) -> void:
	_state = state
	_registry = registry
	# Provide defaults so callers don't need to pre-populate every field.
	_state["form_key"] = String(_state.get("form_key", ""))
	_state["cosmetic_species"] = String(_state.get("cosmetic_species", ""))
	_state["name"] = String(_state.get("name", ""))
	if get_child_count() == 0:
		_build_ui()
	# Restore prior picks if returning to this step.
	if not _state["form_key"].is_empty():
		_select_form(_state["form_key"], false)
	_name_field.text = _state["name"]


func is_complete() -> bool:
	if String(_state.get("form_key", "")).is_empty():
		return false
	if String(_state.get("cosmetic_species", "")).is_empty():
		return false
	if String(_state.get("name", "")).strip_edges().is_empty():
		return false
	return true


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	add_theme_constant_override("separation", 12)

	var hbox := HBoxContainer.new()
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 12)
	add_child(hbox)

	# --- Left: form list (~40% width) ---
	var left_panel := PanelContainer.new()
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_stretch_ratio = 0.4
	hbox.add_child(left_panel)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_panel.add_child(scroll)

	var list_vbox := VBoxContainer.new()
	list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_vbox)

	var header := Label.new()
	header.text = "Choose a Form"
	header.add_theme_font_size_override("font_size", 14)
	list_vbox.add_child(header)
	list_vbox.add_child(HSeparator.new())

	for form_key in _registry.get_all_form_keys():
		var btn := Button.new()
		btn.text = _registry.get_display_name(form_key)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.toggle_mode = true
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_form_pressed.bind(form_key))
		list_vbox.add_child(btn)
		_form_buttons[form_key] = btn

	# --- Right: detail panel + cosmetic + name (~60% width) ---
	var right_panel := PanelContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_stretch_ratio = 0.6
	hbox.add_child(right_panel)

	var right_vbox := VBoxContainer.new()
	right_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_theme_constant_override("separation", 8)
	right_panel.add_child(right_vbox)

	# Detail readout (filled when a form is selected)
	_detail_area = VBoxContainer.new()
	_detail_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(_detail_area)
	_render_detail_placeholder()

	right_vbox.add_child(HSeparator.new())

	# Cosmetic variant dropdown
	var cosmetic_row := HBoxContainer.new()
	cosmetic_row.add_theme_constant_override("separation", 8)
	right_vbox.add_child(cosmetic_row)

	var cosmetic_label := Label.new()
	cosmetic_label.text = "Species:"
	cosmetic_row.add_child(cosmetic_label)

	_cosmetic_dropdown = OptionButton.new()
	_cosmetic_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cosmetic_dropdown.item_selected.connect(_on_cosmetic_selected)
	_cosmetic_dropdown.disabled = true
	cosmetic_row.add_child(_cosmetic_dropdown)

	# Name field
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	right_vbox.add_child(name_row)

	var name_label := Label.new()
	name_label.text = "Name:"
	name_row.add_child(name_label)

	_name_field = LineEdit.new()
	_name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_field.placeholder_text = "Familiar's name"
	_name_field.text_changed.connect(_on_name_changed)
	name_row.add_child(_name_field)


# ---------------------------------------------------------------------------
# Event handlers
# ---------------------------------------------------------------------------

func _on_form_pressed(form_key: String) -> void:
	_select_form(form_key, true)


func _select_form(form_key: String, emit_change: bool) -> void:
	if not _registry.has_form(form_key):
		return
	# Toggle button state — single-select.
	_selected_form_key = form_key
	_state["form_key"] = form_key
	for key in _form_buttons:
		var btn: Button = _form_buttons[key]
		var selected: bool = (key == form_key)
		btn.button_pressed = selected
		if selected:
			btn.add_theme_color_override("font_color", SELECTED_FORM_TEXT_COLOR)
		else:
			btn.remove_theme_color_override("font_color")

	_render_detail_for_form(form_key)
	_repopulate_cosmetic_dropdown(form_key)

	if emit_change:
		picker_changed.emit()


func _on_cosmetic_selected(index: int) -> void:
	if index < 0:
		_state["cosmetic_species"] = ""
	else:
		_state["cosmetic_species"] = _cosmetic_dropdown.get_item_text(index)
	picker_changed.emit()


func _on_name_changed(new_text: String) -> void:
	_state["name"] = new_text
	picker_changed.emit()


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

func _render_detail_placeholder() -> void:
	for child in _detail_area.get_children():
		child.queue_free()
	var lbl := Label.new()
	lbl.text = "Select a form to see its details."
	lbl.modulate = Color(1, 1, 1, 0.6)
	_detail_area.add_child(lbl)


func _render_detail_for_form(form_key: String) -> void:
	for child in _detail_area.get_children():
		child.queue_free()

	var name_lbl := Label.new()
	name_lbl.text = _registry.get_display_name(form_key)
	name_lbl.add_theme_font_size_override("font_size", 16)
	_detail_area.add_child(name_lbl)

	var summary := _registry.get_summary(form_key)
	if not summary.is_empty():
		var summary_lbl := Label.new()
		summary_lbl.text = summary
		summary_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail_area.add_child(summary_lbl)

	_detail_area.add_child(HSeparator.new())

	var ac_lbl := Label.new()
	ac_lbl.text = "AC: %d" % _registry.get_armor_class(form_key)
	_detail_area.add_child(ac_lbl)

	var movement: Dictionary = _registry.get_movement(form_key)
	if not movement.is_empty():
		var move_lbl := Label.new()
		move_lbl.text = "Move: " + _format_movement(movement)
		_detail_area.add_child(move_lbl)

	var attacks: Array = _registry.get_attack_routines(form_key)
	if not attacks.is_empty():
		var atk_lbl := Label.new()
		atk_lbl.text = "Attacks: " + _format_attacks(attacks)
		atk_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail_area.add_child(atk_lbl)

	var abilities: Array = _registry.get_special_abilities(form_key)
	if not abilities.is_empty():
		var abilities_header := Label.new()
		abilities_header.text = "Special:"
		abilities_header.add_theme_font_size_override("font_size", 13)
		_detail_area.add_child(abilities_header)
		for ability in abilities:
			var a_lbl := Label.new()
			a_lbl.text = "• " + String(ability.get("description", ability.get("ability_id", "")))
			a_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_detail_area.add_child(a_lbl)

	# Footer: HD note (familiars derive HD from master, not the form)
	var note_lbl := Label.new()
	note_lbl.text = "(HD, HP, INT, save category, and proficiencies derive from your master per gdd-familiars.md §3.3.)"
	note_lbl.modulate = Color(1, 1, 1, 0.6)
	note_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_area.add_child(note_lbl)


func _repopulate_cosmetic_dropdown(form_key: String) -> void:
	_cosmetic_dropdown.clear()
	var variants: Array[String] = _registry.get_cosmetic_variants(form_key)
	for v in variants:
		_cosmetic_dropdown.add_item(v)
	# Always have at least one variant to select; auto-select index 0
	# unless the state already carries a valid pick (returning to step).
	if variants.is_empty():
		_cosmetic_dropdown.disabled = true
		_state["cosmetic_species"] = ""
		return
	var prior: String = String(_state.get("cosmetic_species", ""))
	var prior_index: int = variants.find(prior)
	if prior_index < 0:
		prior_index = 0
		_state["cosmetic_species"] = variants[0]
	_cosmetic_dropdown.select(prior_index)
	# Disabled only when there's literally nothing to pick.
	# Forms with a single variant (e.g. "Bat") still expose the dropdown so the
	# UI is consistent — but the dropdown is effectively read-only.
	_cosmetic_dropdown.disabled = variants.size() <= 1


# ---------------------------------------------------------------------------
# Formatters
# ---------------------------------------------------------------------------

func _format_movement(movement: Dictionary) -> String:
	var parts: Array[String] = []
	for mode in ["land", "fly", "swim", "climb"]:
		if movement.has(mode):
			var rates: Dictionary = movement[mode]
			var label: String = mode.capitalize()
			parts.append("%s %d'/%d'" % [
				label,
				int(rates.get("exploration", 0)),
				int(rates.get("combat", 0)),
			])
	return ", ".join(parts)


func _format_attacks(attack_routines: Array) -> String:
	var parts: Array[String] = []
	for routine in attack_routines:
		var attacks: Array = routine.get("attacks", [])
		for atk in attacks:
			var count: int = int(atk.get("count", 1))
			var atk_type: String = String(atk.get("attack_type", ""))
			var dmg: String = String(atk.get("damage", ""))
			if count > 1:
				parts.append("%d %ss (%s)" % [count, atk_type, dmg])
			else:
				parts.append("%s (%s)" % [atk_type, dmg])
	if parts.is_empty():
		return "None"
	return ", ".join(parts)
