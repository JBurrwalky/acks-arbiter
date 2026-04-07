class_name CSTabProficiencies
extends VBoxContainer

## Proficiencies tab — class proficiencies, general proficiencies, class powers,
## and a live thief-skill target panel.

const THIEF_SKILLS_PANEL_WIDTH := 252
const UNAVAILABLE_SKILL_COLOR := Color(0.18, 0.12, 0.07, 0.8)


func display(bundle: CharacterBundle, registries: Dictionary) -> void:
	for child in get_children():
		child.queue_free()

	var character: CharacterData = bundle.character
	if character == null:
		_add_text(self, "No character data.")
		return

	var class_registry: ClassRegistry = registries.get("class_registry")
	var prof_registry: ProficiencyRegistry = registries.get("proficiency_registry")
	var power_registry: PowerRegistry = registries.get("power_registry")
	var thief_skill_resolver := ThiefSkillResolver.new(class_registry, prof_registry, power_registry)

	var layout := HBoxContainer.new()
	layout.name = "ProficienciesLayout"
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 12)
	add_child(layout)

	var left_column := VBoxContainer.new()
	left_column.name = "LeftColumn"
	left_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(left_column)

	var aggregated := CharacterData.aggregate_proficiencies(bundle.proficiencies)
	if aggregated.is_empty():
		_add_text(left_column, "No proficiencies recorded.")
	else:
		_add_section_header(left_column, "Proficiencies")
		for p in aggregated:
			_render_proficiency(left_column, p, prof_registry)

	if not bundle.powers.is_empty():
		if not aggregated.is_empty():
			left_column.add_child(HSeparator.new())
		_add_section_header(left_column, "Class Powers & Abilities")
		for power_row in bundle.powers:
			_render_power(left_column, power_row, character.level, power_registry)

	layout.add_child(VSeparator.new())
	layout.add_child(_build_skill_panels_column(bundle, thief_skill_resolver))


func _build_skill_panels_column(bundle: CharacterBundle,
		resolver: ThiefSkillResolver) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.name = "SkillPanelsColumn"
	column.custom_minimum_size = Vector2(THIEF_SKILLS_PANEL_WIDTH, 0)
	column.add_theme_constant_override("separation", 12)

	var grouped := resolver.get_grouped_skill_checks(bundle)
	column.add_child(_build_skill_panel(
		"ThiefSkillsPanel",
		"Thief Skills",
		grouped.get(ThiefSkillResolver.THIEF_GROUP_KEY, [])
	))
	column.add_child(_build_skill_panel(
		"AdventuringSkillsPanel",
		"Adventuring Skills",
		grouped.get(ThiefSkillResolver.ADVENTURING_GROUP_KEY, [])
	))

	return column


func _build_skill_panel(panel_name: String, header_text: String,
		checks: Array) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = panel_name
	panel.custom_minimum_size = Vector2(THIEF_SKILLS_PANEL_WIDTH, 0)
	UiSurfaceStyles.apply_textured_panel(panel)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 6)
	margin.add_child(content)

	var header := Label.new()
	header.text = header_text
	header.add_theme_font_size_override("font_size", 13)
	content.add_child(header)
	content.add_child(HSeparator.new())

	for check in checks:
		content.add_child(_build_skill_row(check))

	return panel


func _build_skill_row(skill_check: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = str(skill_check.get("skill_key", "Skill"))
	row.add_theme_constant_override("separation", 8)
	row.tooltip_text = str(skill_check.get("tooltip_text", ""))

	var name_lbl := Label.new()
	name_lbl.name = "Name"
	name_lbl.text = str(skill_check.get("display_name", "Skill"))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.tooltip_text = row.tooltip_text
	row.add_child(name_lbl)

	var value_lbl := Label.new()
	value_lbl.name = "Value"
	value_lbl.text = str(skill_check.get("display_target", "NA"))
	value_lbl.custom_minimum_size = Vector2(54, 0)
	value_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_lbl.tooltip_text = row.tooltip_text
	if not bool(skill_check.get("is_available", false)):
		value_lbl.add_theme_color_override("font_color", UNAVAILABLE_SKILL_COLOR)
	row.add_child(value_lbl)

	return row


# ---------------------------------------------------------------------------
# Renderers
# ---------------------------------------------------------------------------

func _render_proficiency(parent: VBoxContainer, p: Dictionary,
		prof_registry: ProficiencyRegistry) -> void:
	var key: String = p.get("proficiency_key", "")
	var rank: int = int(p.get("rank", 1))
	var spec: String = p.get("specialization", "")

	var display_name := key.replace("_", " ").capitalize()
	var description := ""
	var effects_text := ""

	if prof_registry != null and prof_registry.has_proficiency(key):
		var pdef := prof_registry.get_proficiency(key)
		display_name = pdef.get("name", display_name)
		description = pdef.get("description", "")
		var effects := prof_registry.get_effects_for_rank(key, rank)
		if not effects.is_empty():
			effects_text = _effects_to_string(effects)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 4)
	parent.add_child(name_row)

	var name_lbl := Label.new()
	var full_name := display_name
	if rank > 1:
		full_name += " (Rank %d)" % rank
	if not spec.is_empty():
		full_name += "  [%s]" % spec.replace("_", " ").capitalize()
	var slot_types: Array = p.get("slot_types", [])
	if not slot_types.is_empty():
		if "class" in slot_types and "general" in slot_types:
			full_name += "  [C+G]"
		elif "class" in slot_types:
			full_name += "  [C]"
		elif "general" in slot_types:
			full_name += "  [G]"
	name_lbl.text = full_name
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_row.add_child(name_lbl)

	if not description.is_empty():
		var desc_lbl := Label.new()
		desc_lbl.text = "    " + description
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.add_theme_font_size_override("font_size", 10)
		desc_lbl.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_TEXT_COLOR)
		parent.add_child(desc_lbl)

	if not effects_text.is_empty():
		var eff_lbl := Label.new()
		eff_lbl.text = "    " + effects_text
		eff_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		eff_lbl.add_theme_font_size_override("font_size", 10)
		eff_lbl.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_TEXT_COLOR)
		parent.add_child(eff_lbl)


func _render_power(parent: VBoxContainer, power_row: Dictionary, character_level: int,
		power_registry: PowerRegistry) -> void:
	var power_id: String = power_row.get("power_id", "")
	var unlock_level: int = int(power_row.get("unlock_level", 1))
	var is_active: bool = bool(int(power_row.get("is_active", 1)))

	var display_name := power_id.replace("_", " ").capitalize()
	var description := ""

	if power_registry != null and power_registry.has_power(power_id):
		var pdef := power_registry.get_power(power_id)
		display_name = pdef.get("power_name", pdef.get("name", display_name))
		description = pdef.get("description", "")

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	parent.add_child(name_row)

	var name_lbl := Label.new()
	name_lbl.text = display_name
	name_lbl.add_theme_font_size_override("font_size", 12)
	if not is_active:
		name_lbl.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_TEXT_COLOR)
	name_row.add_child(name_lbl)

	if unlock_level > 1:
		var lvl_lbl := Label.new()
		lvl_lbl.text = "(gained at level %d)" % unlock_level
		lvl_lbl.add_theme_font_size_override("font_size", 10)
		lvl_lbl.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_TEXT_COLOR)
		name_row.add_child(lvl_lbl)

	if not is_active and unlock_level > character_level:
		var locked_lbl := Label.new()
		locked_lbl.text = "  [not yet gained]"
		locked_lbl.add_theme_font_size_override("font_size", 10)
		locked_lbl.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_TEXT_COLOR)
		name_row.add_child(locked_lbl)

	if not description.is_empty():
		var desc_lbl := Label.new()
		desc_lbl.text = "    " + description
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.add_theme_font_size_override("font_size", 10)
		desc_lbl.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_TEXT_COLOR)
		parent.add_child(desc_lbl)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _effects_to_string(effects: Dictionary) -> String:
	var parts: Array = []
	for key in effects:
		var val = effects[key]
		var key_str: String = str(key).replace("_", " ")
		if val is int or val is float:
			var sign_str := "+%s" % str(val) if float(val) >= 0 else str(val)
			parts.append("%s %s" % [key_str, sign_str])
		elif val is String and not val.is_empty():
			parts.append("%s: %s" % [key_str, val])
	return ", ".join(parts)


func _add_section_header(parent: VBoxContainer, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	parent.add_child(lbl)


func _add_text(parent: VBoxContainer, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(lbl)
