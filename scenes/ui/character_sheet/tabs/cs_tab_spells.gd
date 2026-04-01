class_name CSTabSpells
extends VBoxContainer

## Spells tab — spell slots, known spells, memorization status.
## Shows "not a caster" message for non-spellcasting classes.


func display(bundle: CharacterBundle, registries: Dictionary) -> void:
	for child in get_children():
		child.queue_free()

	var character: CharacterData = bundle.character
	if character == null:
		_add_text("No character data.")
		return

	var class_registry: ClassRegistry = registries.get("class_registry")
	var spell_registry: SpellRegistry  = registries.get("spell_registry")

	# Determine if caster
	var casting_power := {}
	if class_registry != null:
		casting_power = class_registry.get_casting_power(character.character_class)

	if casting_power.is_empty():
		_add_text("This character does not cast spells.")
		return

	var tradition: String = casting_power.get("tradition", "arcane")
	_add_section_header("%s Caster" % tradition.capitalize())

	# Spell slots per day
	var slots_by_level: Array = []
	if class_registry != null:
		slots_by_level = class_registry.get_spell_slots(character.character_class, character.level)

	if not slots_by_level.is_empty():
		_add_section_header("Spell Slots Per Day")
		var header_row := HBoxContainer.new()
		header_row.add_theme_constant_override("separation", 4)
		add_child(header_row)
		for i in range(slots_by_level.size()):
			var h := Label.new()
			h.text = "L%d" % (i + 1)
			h.custom_minimum_size = Vector2(32, 0)
			h.add_theme_font_size_override("font_size", 11)
			header_row.add_child(h)

		var slots_row := HBoxContainer.new()
		slots_row.add_theme_constant_override("separation", 4)
		add_child(slots_row)
		for slot_count in slots_by_level:
			var s := Label.new()
			s.text = str(slot_count)
			s.custom_minimum_size = Vector2(32, 0)
			s.add_theme_font_size_override("font_size", 11)
			slots_row.add_child(s)

	add_child(HSeparator.new())

	# Spells known, organized by level
	if bundle.spells.is_empty():
		_add_text("No spells recorded.")
		return

	## Group spells by level
	var by_level: Dictionary = {}
	var max_spell_level := 0
	for spell_dict in bundle.spells:
		var lvl: int = int(spell_dict.get("spell_level", 1))
		if lvl > max_spell_level:
			max_spell_level = lvl
		if not by_level.has(lvl):
			by_level[lvl] = []
		by_level[lvl].append(spell_dict)

	## Count memorized per level for summary
	var memorized_count: Dictionary = {}
	for spell_dict in bundle.spells:
		var lvl: int = int(spell_dict.get("spell_level", 1))
		if bool(int(spell_dict.get("is_memorized", 0))):
			memorized_count[lvl] = memorized_count.get(lvl, 0) + 1

	_add_section_header("Spells Known")

	for lvl in range(1, max_spell_level + 1):
		if not by_level.has(lvl):
			continue

		var slots_avail: int = slots_by_level[lvl - 1] if lvl - 1 < slots_by_level.size() else 0
		var memorized: int = memorized_count.get(lvl, 0)

		var level_lbl := Label.new()
		level_lbl.text = "Level %d  (%d/%d memorized)" % [lvl, memorized, slots_avail]
		level_lbl.add_theme_font_size_override("font_size", 12)
		add_child(level_lbl)

		for spell_dict in by_level[lvl]:
			var spell_key: String = spell_dict.get("spell_key", "")
			var is_memorized: bool = bool(int(spell_dict.get("is_memorized", 0)))
			var in_repertoire: bool = bool(int(spell_dict.get("is_in_repertoire", 0)))

			var spell_name := spell_key.replace("_", " ").capitalize()
			if spell_registry != null and spell_registry.has_spell(spell_key):
				var sdef := spell_registry.get_spell(spell_key)
				spell_name = sdef.get("spell_name", spell_name)

			var bullet := "  \u2022 "
			bullet += spell_name
			if is_memorized:
				bullet += "  [memorized]"
			elif in_repertoire:
				bullet += "  [known, not memorized]"

			var slbl := Label.new()
			slbl.text = bullet
			slbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			if not is_memorized:
				slbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
			add_child(slbl)


# ---------------------------------------------------------------------------
# Layout helpers
# ---------------------------------------------------------------------------

func _add_section_header(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	add_child(lbl)
	add_child(HSeparator.new())


func _add_text(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(lbl)
