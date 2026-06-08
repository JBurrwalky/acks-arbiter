extends "res://tests/test_suite_base.gd"

## Focused tests for portrait display sizing in character creation finalize
## and the character sheet biography tab.


func run_all_tests() -> void:
	test_finalize_summary_portrait_uses_fixed_512_box()
	test_biography_tab_portrait_uses_fixed_512_box()
	test_male_priestess_uses_priest_display_in_finalize_summary()
	test_male_priestess_uses_priest_display_in_biography_tab()
	if not has_failures():
		print("PortraitDisplaySizing: all tests passed.")


func test_finalize_summary_portrait_uses_fixed_512_box() -> void:
	var panel := CharacterSheetPanel.new()
	panel._ready()
	panel.setup_registry(ClassRegistry.new())

	var character := _make_character()
	panel.display({
		"character": character,
		"class_id": "fighter",
		"portrait_id": character.portrait_id,
		"inventory": [],
		"proficiencies": [],
		"spells": [],
	})

	var portrait_rect := _find_texture_rect(panel)
	check(portrait_rect != null, "finalize summary should render a portrait TextureRect")
	if portrait_rect != null:
		check(portrait_rect.expand_mode == TextureRect.EXPAND_IGNORE_SIZE,
			"finalize summary portrait should ignore native texture size")
		check(portrait_rect.custom_minimum_size == Vector2(512, 512),
			"finalize summary portrait should use a 512x512 display box")
	print("  finalize_summary_portrait_uses_fixed_512_box: OK")


func test_biography_tab_portrait_uses_fixed_512_box() -> void:
	var tab := CSTabBiography.new()
	var bundle := CharacterBundle.new()
	bundle.character = _make_character()

	tab.display(bundle, {
		"class_registry": ClassRegistry.new(),
	})

	var portrait_rect := _find_texture_rect(tab)
	check(portrait_rect != null, "biography tab should render a portrait TextureRect")
	if portrait_rect != null:
		check(portrait_rect.expand_mode == TextureRect.EXPAND_IGNORE_SIZE,
			"biography tab portrait should ignore native texture size")
		check(portrait_rect.custom_minimum_size == Vector2(512, 512),
			"biography tab portrait should use a 512x512 display box")
	print("  biography_tab_portrait_uses_fixed_512_box: OK")


func test_male_priestess_uses_priest_display_in_finalize_summary() -> void:
	var panel := CharacterSheetPanel.new()
	panel._ready()
	panel.setup_registry(ClassRegistry.new())

	var character := _make_character("priestess", "male")
	panel.display({
		"character": character,
		"class_id": "priestess",
		"portrait_id": character.portrait_id,
		"inventory": [],
		"proficiencies": [],
		"spells": [],
	})

	check(_find_row_value(panel, "Class:") == "Priest (Level 1)",
		"finalize summary should show 'Priest' for a male priestess character")
	check(character.character_class == "priestess",
		"finalize summary display override should not change the stored class key")
	print("  male_priestess_uses_priest_display_in_finalize_summary: OK")


func test_male_priestess_uses_priest_display_in_biography_tab() -> void:
	var tab := CSTabBiography.new()
	var bundle := CharacterBundle.new()
	bundle.character = _make_character("priestess", "male")

	tab.display(bundle, {
		"class_registry": ClassRegistry.new(),
	})

	check(_find_row_value(tab, "Class:") == "Priest (Level 1)",
		"biography tab should show 'Priest' for a male priestess character")
	check(bundle.character.character_class == "priestess",
		"biography tab display override should not change the stored class key")
	print("  male_priestess_uses_priest_display_in_biography_tab: OK")


func _make_character(class_id: String = "fighter", sex: String = "male") -> CharacterData:
	var character := CharacterData.new()
	character.name = "Portrait Test"
	character.character_class = class_id
	character.race = "human"
	character.level = 1
	character.title = "Venturer"
	character.alignment = "neutral"
	character.sex = sex
	character.hp_current = 4
	character.hp_max = 4
	character.portrait_id = "asian_fighter_male_01"
	return character


func _find_texture_rect(root: Node) -> TextureRect:
	for child in root.get_children():
		if child is TextureRect:
			return child as TextureRect
		var nested := _find_texture_rect(child)
		if nested != null:
			return nested
	return null


func _find_row_value(root: Node, label_text: String) -> String:
	for child in root.get_children():
		if child is HBoxContainer and child.get_child_count() >= 2:
			var key := child.get_child(0) as Label
			var value := child.get_child(1) as Label
			if key != null and value != null and key.text == label_text:
				return value.text
		var nested := _find_row_value(child, label_text)
		if not nested.is_empty():
			return nested
	return ""
