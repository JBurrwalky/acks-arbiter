class_name CSTabAttributes
extends VBoxContainer

## Attributes tab — six ability scores with modifiers and five saving throws.
## Shows effective values (including active spell/modifier effects) alongside base values.


func display(bundle: CharacterBundle, _registries: Dictionary) -> void:
	for child in get_children():
		child.queue_free()

	var character: CharacterData = bundle.character
	if character == null:
		_add_text("No character data.")
		return

	_add_section_header("Ability Scores")

	var abilities: Array = [
		["STR", "strength",    character.strength],
		["INT", "intelligence", character.intelligence],
		["WIS", "wisdom",      character.wisdom],
		["DEX", "dexterity",   character.dexterity],
		["CON", "constitution", character.constitution],
		["CHA", "charisma",    character.charisma],
	]

	## Header row
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 4)
	add_child(hdr)
	_make_col_label(hdr, "Ability", 80)
	_make_col_label(hdr, "Score", 50)
	_make_col_label(hdr, "Mod", 50)
	_make_col_label(hdr, "Effective", 80)

	for entry in abilities:
		var label: String = entry[0]
		var key: String = entry[1]
		var base_score: int = entry[2]
		var base_mod := CharacterData.ability_modifier(base_score)
		var eff_score := character.get_effective_ability_score(key)
		var eff_mod := CharacterData.ability_modifier(eff_score)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		add_child(row)

		_make_col_label(row, label, 80)
		_make_col_label(row, str(base_score), 50)
		var mod_str := "+%d" % base_mod if base_mod >= 0 else str(base_mod)
		_make_col_label(row, mod_str, 50)

		var eff_text := ""
		if eff_score != base_score:
			var eff_mod_str := "+%d" % eff_mod if eff_mod >= 0 else str(eff_mod)
			eff_text = "%d (%s)*" % [eff_score, eff_mod_str]
		_make_col_label(row, eff_text, 80, eff_score != base_score)

	if _has_any_ability_modifier(character):
		var note := Label.new()
		note.text = "* Modified by active effects"
		note.add_theme_font_size_override("font_size", 10)
		note.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
		add_child(note)

	add_child(HSeparator.new())
	_add_section_header("Saving Throws")

	## Saving throw header
	var st_hdr := HBoxContainer.new()
	st_hdr.add_theme_constant_override("separation", 4)
	add_child(st_hdr)
	_make_col_label(st_hdr, "Save", 180)
	_make_col_label(st_hdr, "Base", 50)
	_make_col_label(st_hdr, "Effective", 80)

	var saves: Array = [
		["Petrification / Paralysis", "save_petrification", character.save_petrification],
		["Poison / Death",            "save_poison_death",  character.save_poison_death],
		["Blast / Breath",            "save_blast_breath",  character.save_blast_breath],
		["Staffs / Wands",            "save_staffs_wands",  character.save_staffs_wands],
		["Spells",                    "save_spells",         character.save_spells],
	]

	for entry in saves:
		var save_label: String = entry[0]
		var save_key: String = entry[1]
		var base_val: int = entry[2]
		var eff_val := character.get_effective_save(save_key)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		add_child(row)

		_make_col_label(row, save_label + ":", 180)
		_make_col_label(row, "%d+" % base_val, 50)
		var eff_text := ""
		if eff_val != base_val:
			eff_text = "%d+*" % eff_val
		_make_col_label(row, eff_text, 80, eff_val != base_val)

	if _has_any_save_modifier(character):
		var note := Label.new()
		note.text = "* Modified by active effects"
		note.add_theme_font_size_override("font_size", 10)
		note.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
		add_child(note)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _has_any_ability_modifier(character: CharacterData) -> bool:
	var keys := ["strength", "intelligence", "wisdom", "dexterity", "constitution", "charisma"]
	for key in keys:
		var base: int
		match key:
			"strength":     base = character.strength
			"intelligence": base = character.intelligence
			"wisdom":       base = character.wisdom
			"dexterity":    base = character.dexterity
			"constitution": base = character.constitution
			"charisma":     base = character.charisma
		if character.get_effective_ability_score(key) != base:
			return true
	return false


func _has_any_save_modifier(character: CharacterData) -> bool:
	var checks: Array = [
		["save_petrification", character.save_petrification],
		["save_poison_death",  character.save_poison_death],
		["save_blast_breath",  character.save_blast_breath],
		["save_staffs_wands",  character.save_staffs_wands],
		["save_spells",        character.save_spells],
	]
	for entry in checks:
		if character.get_effective_save(entry[0]) != entry[1]:
			return true
	return false


func _make_col_label(parent: HBoxContainer, text: String, min_width: int, highlight: bool = false) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.custom_minimum_size = Vector2(min_width, 0)
	if highlight:
		lbl.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	parent.add_child(lbl)


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
