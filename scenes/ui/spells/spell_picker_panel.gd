extends CanvasLayer

## Modal spell picker — shared across combat declaration, dungeon context
## menu, character tab Cast button, and party inventory item submenus.
##
## Lives at CanvasLayer 56 (between LootDistributionModal at 52 and DicePrompt
## at 64 per docs/coding_conventions.md §13.1).
##
## Usage:
##   var picker = preload("res://scenes/ui/spells/spell_picker_panel.tscn").instantiate()
##   add_child(picker)
##   picker.setup(caster: CharacterData, ctx: Dictionary)
##   picker.spell_chosen.connect(...)  # SpellChoice
##   picker.cancelled.connect(...)
##
## ctx keys:
##   spell_registry        — SpellRegistry  (required)
##   effect_registry       — SpellEffectRegistry (required)
##   campaign_repo         — CampaignRepository (required for slot lookup)
##   pre_selected_target   — TargetDescriptor or null (optional pre-filter)
##   allowed_target_kinds  — Array[String] or [] (optional pre-filter)
##
## Picker emits one of two terminal signals; closes itself before the caller
## reacts so the picker doesn't linger if the caller opens another modal.

signal spell_chosen(choice: SpellChoice)
signal cancelled


# Scene-local fields
var _caster: CharacterData = null
var _spell_registry: SpellRegistry = null
var _effect_registry: SpellEffectRegistry = null
var _campaign_repo = null
var _allowed_kinds: Array = []
var _pre_target = null

var _root_panel: PanelContainer = null
var _level_sections: VBoxContainer = null
var _expended_slots: Dictionary = {}


func _ready() -> void:
	layer = 56
	visible = false
	_build_ui()


func _build_ui() -> void:
	# Backdrop intercepts clicks outside the panel.
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.45)
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(_on_backdrop_input)
	add_child(backdrop)

	# Centered panel.
	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	add_child(center)

	_root_panel = PanelContainer.new()
	_root_panel.custom_minimum_size = Vector2(560, 500)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.10, 0.13, 0.97)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.45, 0.40, 0.20)
	_root_panel.add_theme_stylebox_override("panel", style)
	center.add_child(_root_panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	_root_panel.add_child(outer)

	# Header
	var header := Label.new()
	header.name = "Header"
	header.text = "Cast a Spell"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", Color(0.92, 0.86, 0.62))
	outer.add_child(header)

	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 11)
	subtitle.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	outer.add_child(subtitle)

	outer.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	_level_sections = VBoxContainer.new()
	_level_sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_level_sections.add_theme_constant_override("separation", 10)
	scroll.add_child(_level_sections)

	# Cancel button
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	outer.add_child(btn_row)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel  (Esc)"
	cancel_btn.pressed.connect(_on_cancel_pressed)
	btn_row.add_child(cancel_btn)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func setup(caster: CharacterData, ctx: Dictionary) -> void:
	## Opens the picker for the given caster. Reads ctx.spell_registry,
	## .effect_registry, .campaign_repo (required) and optional .pre_selected_target,
	## .allowed_target_kinds.
	_caster = caster
	_spell_registry = ctx.get("spell_registry", null)
	_effect_registry = ctx.get("effect_registry", null)
	_campaign_repo = ctx.get("campaign_repo", null)
	_allowed_kinds = ctx.get("allowed_target_kinds", [])
	_pre_target = ctx.get("pre_selected_target", null)

	if _campaign_repo != null:
		_expended_slots = _campaign_repo.get_expended_slots(_caster.id)
	else:
		_expended_slots = {}

	_refresh()
	visible = true


func close() -> void:
	visible = false
	queue_free()


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _refresh() -> void:
	# Header text
	var header_label: Label = _root_panel.get_node("VBoxContainer/Header") as Label if _root_panel.has_node("VBoxContainer/Header") else null
	if header_label == null:
		# CanvasLayer/PanelContainer/VBoxContainer/Header
		for child in _root_panel.get_children():
			if child is VBoxContainer:
				header_label = child.get_node_or_null("Header") as Label
				break
	if header_label != null:
		header_label.text = "Cast a Spell — %s" % _caster.name

	# Clear sections
	for child in _level_sections.get_children():
		child.queue_free()

	# Build per-level sections from caster's repertoire.
	var by_level := _group_repertoire_by_level()
	var levels := by_level.keys()
	levels.sort()
	for level in levels:
		_build_level_section(int(level), by_level[level])


func _group_repertoire_by_level() -> Dictionary:
	# Read from CharacterData.proficiencies? No — repertoire is in
	# CampaignRepository.get_character_repertoire. For Session 2, accept the
	# repertoire as a pre-loaded list on caster.spells_in_repertoire if set,
	# else fetch from campaign_repo.
	var entries: Array = []
	if _campaign_repo != null and _campaign_repo.has_method("get_character_repertoire"):
		entries = _campaign_repo.get_character_repertoire(_caster.id)

	var grouped: Dictionary = {}
	for entry in entries:
		var lvl := int(entry.get("spell_level", 1))
		if not grouped.has(lvl):
			grouped[lvl] = []
		grouped[lvl].append(entry)
	return grouped


func _build_level_section(level: int, entries: Array) -> void:
	var slots_used := int(_expended_slots.get(level, 0))
	var section_header := Label.new()
	section_header.text = "Level %d  (%d expended)" % [level, slots_used]
	section_header.add_theme_font_size_override("font_size", 14)
	section_header.add_theme_color_override("font_color", Color(0.85, 0.78, 0.50))
	_level_sections.add_child(section_header)

	for entry in entries:
		_build_spell_row(level, entry)


func _build_spell_row(level: int, entry: Dictionary) -> void:
	var spell_key := str(entry.get("spell_key", ""))
	if spell_key.is_empty() or _spell_registry == null:
		return
	var spell_data: Dictionary = _spell_registry.get_spell(spell_key)
	if spell_data.is_empty():
		return

	var has_effect := _effect_registry != null and _effect_registry.has_effect(spell_key)
	var is_disjunctive := has_effect and _effect_registry.is_disjunctive(spell_key, false)

	# Pre-target filter: drop rows that can't target the pre-selected entity.
	if not _allowed_kinds.is_empty() and has_effect:
		var payload := _effect_registry.get_effect_payload(spell_key, false, -1)
		var ts: Dictionary = payload.get("target_spec", {})
		var kind := String(ts.get("kind", ""))
		if not (kind in _allowed_kinds):
			return

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_level_sections.add_child(row)

	# Spell name (with reverse name if reversible)
	var name_text := String(spell_data.get("spell_name", spell_key))
	if bool(spell_data.get("is_reversible", false)):
		var rev_name := String(spell_data.get("reverse_name", ""))
		if not rev_name.is_empty():
			name_text += " / " + rev_name
	var name_lbl := Label.new()
	name_lbl.text = name_text
	name_lbl.custom_minimum_size.x = 200.0
	row.add_child(name_lbl)

	# Range / duration mini-line
	var meta := Label.new()
	meta.text = "%s · %s" % [spell_data.get("range", "?"), spell_data.get("duration", "?")]
	meta.add_theme_font_size_override("font_size", 10)
	meta.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	meta.custom_minimum_size.x = 140.0
	row.add_child(meta)

	# Reverse toggle (only for reversible spells)
	var reverse_check: CheckBox = null
	if bool(spell_data.get("is_reversible", false)):
		reverse_check = CheckBox.new()
		reverse_check.text = "Reverse"
		row.add_child(reverse_check)

	# Cast button
	var cast_btn := Button.new()
	cast_btn.text = "Cast"
	if not has_effect:
		cast_btn.disabled = true
		cast_btn.tooltip_text = "Spell not yet implemented"
	cast_btn.pressed.connect(_on_cast_pressed.bind(spell_key, level, reverse_check, is_disjunctive))
	row.add_child(cast_btn)


func _on_cast_pressed(spell_key: String, level: int, reverse_check: CheckBox, is_disjunctive: bool) -> void:
	var is_reversed := reverse_check != null and reverse_check.button_pressed
	var disjunctive_index: int = -1
	# For a disjunctive spell we'd open DisjunctiveBranchModal here. Session 2
	# wires that surface via the caller (DeclarationOverlay): the picker emits
	# the choice with disjunctive_index = -1, the caller opens the modal, and
	# re-emits with the chosen branch. Keeping that flow at the caller level
	# avoids embedding modal-on-modal logic here.
	var choice := SpellChoice.new(spell_key, level, is_reversed, disjunctive_index)
	emit_signal("spell_chosen", choice)
	close()


func _on_cancel_pressed() -> void:
	emit_signal("cancelled")
	close()


func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_cancel_pressed()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_cancel_pressed()
		get_viewport().set_input_as_handled()
