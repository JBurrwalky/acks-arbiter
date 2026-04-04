extends "res://tests/test_suite_base.gd"

## Focused tests for portrait display sizing in character creation finalize
## and the character sheet biography tab.


func run_all_tests() -> void:
	test_finalize_summary_portrait_uses_fixed_512_box()
	test_biography_tab_portrait_uses_fixed_512_box()
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


func _make_character() -> CharacterData:
	var character := CharacterData.new()
	character.name = "Portrait Test"
	character.character_class = "fighter"
	character.race = "human"
	character.level = 1
	character.title = "Venturer"
	character.alignment = "neutral"
	character.sex = "male"
	character.hp_current = 4
	character.hp_max = 4
	character.portrait_id = "portrait_fighter_01"
	return character


func _find_texture_rect(root: Node) -> TextureRect:
	for child in root.get_children():
		if child is TextureRect:
			return child as TextureRect
		var nested := _find_texture_rect(child)
		if nested != null:
			return nested
	return null
