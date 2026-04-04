class_name CSTabProficiencies
extends VBoxContainer

## Proficiencies tab — class proficiencies, general proficiencies, class powers/abilities.


func display(bundle: CharacterBundle, registries: Dictionary) -> void:
	for child in get_children():
		child.queue_free()

	var character: CharacterData = bundle.character
	if character == null:
		_add_text("No character data.")
		return

	var prof_registry: ProficiencyRegistry = registries.get("proficiency_registry")
	var power_registry: PowerRegistry = registries.get("power_registry")

	# -- Proficiencies (aggregated across class/general sources) --
	var aggregated := CharacterData.aggregate_proficiencies(bundle.proficiencies)
	if aggregated.is_empty():
		_add_text("No proficiencies recorded.")
	else:
		_add_section_header("Proficiencies")
		for p in aggregated:
			_render_proficiency(p, prof_registry)

	# -- Class Powers --
	if not bundle.powers.is_empty():
		add_child(HSeparator.new())
		_add_section_header("Class Powers & Abilities")
		for power_row in bundle.powers:
			_render_power(power_row, character.level, power_registry)


# ---------------------------------------------------------------------------
# Renderers
# ---------------------------------------------------------------------------

func _render_proficiency(p: Dictionary, prof_registry: ProficiencyRegistry) -> void:
	var key: String = p.get("proficiency_key", "")
	var rank: int = int(p.get("rank", 1))
	var spec: String = p.get("specialization", "")

	var display_name := key.replace("_", " ").capitalize()
	var description := ""
	var effects_text := ""

	if prof_registry != null and prof_registry.has_proficiency(key):
		var pdef := prof_registry.get_proficiency(key)
		display_name = pdef.get("name", display_name)
		description  = pdef.get("description", "")
		var effects  := prof_registry.get_effects_for_rank(key, rank)
		if not effects.is_empty():
			effects_text = _effects_to_string(effects)

	# Name line
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 4)
	add_child(name_row)

	var name_lbl := Label.new()
	var full_name := display_name
	if rank > 1:
		full_name += " (Rank %d)" % rank
	if not spec.is_empty():
		full_name += "  [%s]" % spec.replace("_", " ").capitalize()
	# Provenance tag from aggregated slot_types
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

	# Description (wrapped)
	if not description.is_empty():
		var desc_lbl := Label.new()
		desc_lbl.text = "    " + description
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.add_theme_font_size_override("font_size", 10)
		desc_lbl.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_TEXT_COLOR)
		add_child(desc_lbl)

	# Effects summary
	if not effects_text.is_empty():
		var eff_lbl := Label.new()
		eff_lbl.text = "    " + effects_text
		eff_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		eff_lbl.add_theme_font_size_override("font_size", 10)
		eff_lbl.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_TEXT_COLOR)
		add_child(eff_lbl)


func _render_power(power_row: Dictionary, character_level: int, power_registry: PowerRegistry) -> void:
	var power_id: String = power_row.get("power_id", "")
	var unlock_level: int = int(power_row.get("unlock_level", 1))
	var is_active: bool = bool(int(power_row.get("is_active", 1)))

	var display_name := power_id.replace("_", " ").capitalize()
	var description := ""

	if power_registry != null and power_registry.has_power(power_id):
		var pdef := power_registry.get_power(power_id)
		display_name = pdef.get("name", display_name)
		description  = pdef.get("description", "")

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	add_child(name_row)

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
		add_child(desc_lbl)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _effects_to_string(effects: Dictionary) -> String:
	## Convert the proficiency effects dict to a readable one-line summary.
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


func _add_section_header(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	add_child(lbl)


func _add_text(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(lbl)
