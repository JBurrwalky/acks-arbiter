class_name CSTabEffects
extends VBoxContainer

## Effects tab — active conditions, spell effects, character status.
## Reputation section is a stub pending the reputation system.


func display(bundle: CharacterBundle, registries: Dictionary) -> void:
	for child in get_children():
		child.queue_free()

	var character: CharacterData = bundle.character
	if character == null:
		_add_text("No character data.")
		return

	var spell_registry: SpellRegistry = registries.get("spell_registry")

	# -- Character status --
	_add_section_header("Status")

	if character.is_dead:
		var dead_lbl := Label.new()
		dead_lbl.text = "DEAD"
		dead_lbl.add_theme_color_override("font_color", Color(0.8, 0.1, 0.1))
		dead_lbl.add_theme_font_size_override("font_size", 14)
		add_child(dead_lbl)
	elif character.is_incapacitated:
		var inc_lbl := Label.new()
		inc_lbl.text = "Incapacitated"
		inc_lbl.add_theme_color_override("font_color", Color(0.9, 0.55, 0.1))
		add_child(inc_lbl)
	else:
		_add_text("Active")

	if not character.is_active:
		_add_row("Party Status:", "Not in active party")

	if character.temp_hp > 0:
		_add_row("Temporary HP:", "+%d" % character.temp_hp)

	add_child(HSeparator.new())

	# -- Active Conditions --
	_add_section_header("Conditions")

	if bundle.conditions.is_empty():
		_add_text("No active conditions.")
	else:
		for cond in bundle.conditions:
			var cond_name: String = cond.get("condition_name", "Unknown")
			var source: String = cond.get("source_id", "")
			var applied: int = int(cond.get("applied_at_round", -1))
			var expires: int = int(cond.get("expires_at_round", -1))

			var text := "  \u2022 %s" % cond_name.replace("_", " ").capitalize()
			if not source.is_empty():
				text += "  (from: %s)" % source
			if expires > 0:
				text += "  [expires round %d]" % expires
			elif applied >= 0:
				text += "  [since round %d]" % applied

			var lbl := Label.new()
			lbl.text = text
			lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			add_child(lbl)

	add_child(HSeparator.new())

	# -- Active Spell Effects --
	_add_section_header("Active Spell Effects")

	if bundle.active_effects.is_empty():
		_add_text("No active spell effects.")
	else:
		for effect in bundle.active_effects:
			var spell_key: String = effect.get("spell_key", "")
			var source_id: String = effect.get("source_character_id", "")
			var duration_remaining: int = int(effect.get("duration_remaining", -1))
			var requires_concentration: bool = bool(int(effect.get("requires_concentration", 0)))
			var applied_modifiers: String = effect.get("applied_modifiers", "{}")
			var applied_flags: String = effect.get("applied_flags", "[]")

			var spell_name := spell_key.replace("_", " ").capitalize()
			if spell_registry != null and spell_registry.has_spell(spell_key):
				var sdef := spell_registry.get_spell(spell_key)
				spell_name = sdef.get("spell_name", spell_name)

			var header_row := HBoxContainer.new()
			header_row.add_theme_constant_override("separation", 8)
			add_child(header_row)

			var name_lbl := Label.new()
			name_lbl.text = "  \u2022 " + spell_name
			name_lbl.add_theme_font_size_override("font_size", 12)
			header_row.add_child(name_lbl)

			if requires_concentration:
				var conc_lbl := Label.new()
				conc_lbl.text = "[concentration]"
				conc_lbl.add_theme_color_override("font_color", Color(0.9, 0.65, 0.1))
				conc_lbl.add_theme_font_size_override("font_size", 10)
				header_row.add_child(conc_lbl)

			if duration_remaining >= 0:
				var dur_lbl := Label.new()
				dur_lbl.text = "%d rounds remaining" % duration_remaining
				dur_lbl.add_theme_font_size_override("font_size", 10)
				dur_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
				header_row.add_child(dur_lbl)

			## Show modifier summary if present
			var mods = JSON.parse_string(applied_modifiers)
			if mods is Dictionary and not mods.is_empty():
				var mod_parts: Array = []
				for stat in mods:
					var v = mods[stat]
					var vstr := "+%s" % str(v) if float(v) >= 0 else str(v)
					mod_parts.append("%s %s" % [stat.replace("_", " "), vstr])
				var mod_lbl := Label.new()
				mod_lbl.text = "    Modifiers: %s" % ", ".join(mod_parts)
				mod_lbl.add_theme_font_size_override("font_size", 10)
				mod_lbl.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
				add_child(mod_lbl)

			## Show flag summary if present
			var flags = JSON.parse_string(applied_flags)
			if flags is Array and not flags.is_empty():
				var flags_lbl := Label.new()
				flags_lbl.text = "    Flags: %s" % ", ".join(flags)
				flags_lbl.add_theme_font_size_override("font_size", 10)
				flags_lbl.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
				add_child(flags_lbl)

	add_child(HSeparator.new())

	# -- Reputation stub --
	_add_section_header("Reputation")
	var rep_lbl := Label.new()
	rep_lbl.text = "Reputation system not yet implemented."
	rep_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	rep_lbl.add_theme_font_size_override("font_size", 11)
	add_child(rep_lbl)


# ---------------------------------------------------------------------------
# Layout helpers
# ---------------------------------------------------------------------------

func _add_section_header(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	add_child(lbl)
	add_child(HSeparator.new())


func _add_row(label_text: String, value_text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(160, 0)
	row.add_child(lbl)
	var val := Label.new()
	val.text = value_text
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(val)


func _add_text(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(lbl)
