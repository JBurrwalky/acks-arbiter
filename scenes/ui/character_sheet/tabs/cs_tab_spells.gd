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

	# Spell repertoire and known formulae display
	if bundle.spells.is_empty():
		_add_text("Spells will be available once you reach casting level.")
		return

	# Build repertoire index for quick lookup.
	var repertoire_keys: Dictionary = {}
	var repertoire_by_level: Dictionary = {}  # int -> Array[Dictionary]
	var max_spell_level := 0
	for spell_dict in bundle.spells:
		var lvl: int = int(spell_dict.get("spell_level", 1))
		if lvl > max_spell_level:
			max_spell_level = lvl
		repertoire_keys[spell_dict.get("spell_key", "")] = true
		if not repertoire_by_level.has(lvl):
			repertoire_by_level[lvl] = []
		repertoire_by_level[lvl].append(spell_dict)

	# Formulas not in active repertoire (arcane only).
	var known_not_active: Array = []
	for formula in bundle.formulas:
		if not repertoire_keys.has(formula.get("spell_key", "")):
			known_not_active.append(formula)

	_add_section_header("Spell Repertoire")

	for lvl in range(1, max_spell_level + 1):
		if not repertoire_by_level.has(lvl):
			continue
		var slots_avail: int = slots_by_level[lvl - 1] if lvl - 1 < slots_by_level.size() else 0
		var expended: int = bundle.expended_slots.get(lvl, 0)

		var level_lbl := Label.new()
		level_lbl.text = "Level %d — %d slots/day (%d expended today)" % [lvl, slots_avail, expended]
		level_lbl.add_theme_font_size_override("font_size", 12)
		add_child(level_lbl)

		for spell_dict in repertoire_by_level[lvl]:
			var spell_key: String = spell_dict.get("spell_key", "")
			var spell_name := spell_key.replace("_", " ").capitalize()
			if spell_registry != null and spell_registry.has_spell(spell_key):
				spell_name = spell_registry.get_spell(spell_key).get("spell_name", spell_name)
			var slbl := Label.new()
			slbl.text = "  \u2022 " + spell_name
			slbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			add_child(slbl)

	# Arcane casters: show known-but-not-in-active-repertoire spells.
	if not known_not_active.is_empty():
		add_child(HSeparator.new())
		_add_section_header("Spells Known (Not in Active Repertoire)")
		var known_by_level: Dictionary = {}
		for formula in known_not_active:
			var lvl: int = int(formula.get("spell_level", 1))
			if not known_by_level.has(lvl):
				known_by_level[lvl] = []
			known_by_level[lvl].append(formula)
		var known_levels: Array = known_by_level.keys()
		known_levels.sort()
		for lvl in known_levels:
			var level_lbl := Label.new()
			level_lbl.text = "Level %d" % lvl
			level_lbl.add_theme_font_size_override("font_size", 12)
			add_child(level_lbl)
			for formula in known_by_level[lvl]:
				var spell_key: String = formula.get("spell_key", "")
				var spell_name := spell_key.replace("_", " ").capitalize()
				if spell_registry != null and spell_registry.has_spell(spell_key):
					spell_name = spell_registry.get_spell(spell_key).get("spell_name", spell_name)
				var slbl := Label.new()
				slbl.text = "  \u2022 " + spell_name
				slbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				slbl.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_TEXT_COLOR)
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
