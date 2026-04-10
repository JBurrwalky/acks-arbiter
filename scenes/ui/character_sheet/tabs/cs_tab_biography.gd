class_name CSTabBiography
extends VBoxContainer

## Biography tab — identity, portrait, HP, age, languages.

const PORTRAIT_DISPLAY_SIZE := Vector2(512, 512)


func display(bundle: CharacterBundle, registries: Dictionary) -> void:
	for child in get_children():
		child.queue_free()

	var character: CharacterData = bundle.character
	if character == null:
		_add_text("No character data.")
		return

	# Portrait
	var texture := _load_portrait(character.portrait_id)
	if texture != null:
		var img_rect := TextureRect.new()
		img_rect.texture = texture
		# Ignore the portrait's native imported size so large source images
		# stay inside the intended biography portrait frame.
		img_rect.custom_minimum_size = PORTRAIT_DISPLAY_SIZE
		img_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		img_rect.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		img_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		add_child(img_rect)

	# Name
	var name_lbl := Label.new()
	name_lbl.text = character.name if not character.name.is_empty() else "(unnamed)"
	name_lbl.add_theme_font_size_override("font_size", 18)
	add_child(name_lbl)

	add_child(HSeparator.new())

	# Class & level
	var class_registry: ClassRegistry = registries.get("class_registry")
	var class_name_str: String = character.character_class
	if class_registry != null and class_registry.has_class(character.character_class):
		class_name_str = class_registry.get_class_display_name(character.character_class, character.sex)
	_add_row("Class:", "%s (Level %d)" % [class_name_str, character.level])
	_add_row("Title:", character.title)
	_add_row("Race:", character.race.capitalize())
	_add_row("Alignment:", character.alignment.capitalize())
	_add_row("Sex:", character.sex.capitalize())

	add_child(HSeparator.new())

	# HP with color-coded label
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 8)
	add_child(hp_row)
	var hp_key := Label.new()
	hp_key.text = "Hit Points:"
	hp_key.custom_minimum_size = Vector2(160, 0)
	hp_row.add_child(hp_key)
	var hp_val := Label.new()
	hp_val.text = "%d / %d" % [character.hp_current, character.hp_max]
	if character.hp_max > 0:
		var ratio := float(character.hp_current) / float(character.hp_max)
		if ratio <= 0.0:
			hp_val.add_theme_color_override("font_color", Color(0.6, 0.1, 0.1))
		elif ratio < 0.25:
			hp_val.add_theme_color_override("font_color", Color(0.85, 0.15, 0.15))
		elif ratio < 0.5:
			hp_val.add_theme_color_override("font_color", Color(0.9, 0.65, 0.1))
		else:
			hp_val.add_theme_color_override("font_color", Color(0.2, 0.75, 0.2))
	hp_row.add_child(hp_val)

	if character.is_dead:
		var dead_lbl := Label.new()
		dead_lbl.text = "DEAD"
		dead_lbl.add_theme_color_override("font_color", Color(0.8, 0.1, 0.1))
		dead_lbl.add_theme_font_size_override("font_size", 12)
		add_child(dead_lbl)
	elif character.is_incapacitated:
		var inc_lbl := Label.new()
		inc_lbl.text = "Incapacitated"
		inc_lbl.add_theme_color_override("font_color", Color(0.9, 0.55, 0.1))
		add_child(inc_lbl)

	add_child(HSeparator.new())

	# Age
	if character.current_age > 0:
		_add_row("Age:", "%d (%s)" % [character.current_age, character.age_category.capitalize()])

	# XP adjustment
	var xp_adj := character.xp_adjustment_percent
	if xp_adj != 0:
		_add_row("XP Adjustment:", "%+d%%" % xp_adj)

	add_child(HSeparator.new())

	# Languages
	var lang_list: Array = []
	var raw: String = character.languages
	if not raw.is_empty() and raw != "[]":
		lang_list = CharacterData.parse_languages_json(raw)
	if not lang_list.is_empty():
		_add_section_header("Languages")
		for lang_id in lang_list:
			var lang_str: String = lang_id
			_add_bullet(lang_str.replace("_", " ").capitalize())


# ---------------------------------------------------------------------------
# Portrait loading
# ---------------------------------------------------------------------------

func _load_portrait(portrait_id: String) -> Texture2D:
	if portrait_id.is_empty():
		return null
	var user_path := "user://portraits/%s.png" % portrait_id
	if FileAccess.file_exists(user_path):
		var img := Image.load_from_file(user_path)
		if img != null:
			return ImageTexture.create_from_image(img)
	var res_path := "res://assets/portraits/%s.png" % portrait_id
	if ResourceLoader.exists(res_path):
		return load(res_path) as Texture2D
	return null


# ---------------------------------------------------------------------------
# Layout helpers
# ---------------------------------------------------------------------------

func _add_section_header(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	add_child(lbl)


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


func _add_bullet(text: String) -> void:
	var lbl := Label.new()
	lbl.text = "  \u2022 " + text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(lbl)


func _add_text(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(lbl)
