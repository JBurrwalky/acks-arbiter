extends "res://tests/test_suite_base.gd"

## Regression tests for removing deprecated alignment-language support.

const CHARACTER_CREATION_SCREEN := preload("res://scenes/ui/character_creation/character_creation_screen.gd")
const CHARACTER_SHEET_PANEL := preload("res://scenes/ui/components/character_sheet_panel.gd")

var _campaign_id: String = ""
var _party_id: String = ""


func run_all_tests() -> void:
	_setup_campaign()
	test_character_data_sanitizes_alignment_language_ids()
	test_default_languages_for_elf_and_dwarf()
	test_get_character_sanitizes_legacy_language_json()
	test_get_character_proficiencies_sanitizes_legacy_alignment_rows()
	test_character_creation_finalize_does_not_grant_alignment_languages()
	test_character_creation_finalize_applies_elf_language_defaults()
	test_character_sheet_preview_does_not_inject_alignment_languages()
	test_character_sheet_preview_uses_dwarf_language_defaults()
	if not has_failures():
		print("LanguageCleanup: all tests passed.")


func _setup_campaign() -> void:
	if not _campaign_id.is_empty():
		return
	_campaign_id = CampaignRepository.create_campaign(
		"Test Language Cleanup",
		"LanguageCleanupWorld"
	)
	check(not _campaign_id.is_empty(),
		"create_campaign should return a non-empty ID for language cleanup tests")
	_party_id = CampaignRepository.create_party(_campaign_id, "Language Cleanup Party")
	check(not _party_id.is_empty(),
		"create_party should return a non-empty ID for language cleanup tests")


func test_character_data_sanitizes_alignment_language_ids() -> void:
	var sanitized := CharacterData.parse_languages_json([
		"common",
		"alignment_lawful",
		"elvish",
		"",
		"common",
		"alignment_chaotic",
		"draconic",
	])
	check(sanitized.size() == 3,
		"sanitize_language_ids should keep only 3 real languages, got %d" % sanitized.size())
	check(sanitized[0] == "common", "common should remain first after sanitization")
	check(sanitized[1] == "elvish", "elvish should remain after sanitization")
	check(sanitized[2] == "draconic", "draconic should remain after sanitization")
	check(CharacterData.sanitize_languages_json(sanitized) == "[\"common\",\"elvish\",\"draconic\"]",
		"sanitize_languages_json should persist the cleaned language list")
	print("  character_data_sanitizes_alignment_language_ids: OK")


func test_default_languages_for_elf_and_dwarf() -> void:
	var elf_languages := CharacterData.get_default_languages_for_race("elf")
	check(elf_languages == ["common", "elvish", "gnoll", "hobgoblin", "orc"],
		"elf defaults should match ACKS racial languages, got %s" % str(elf_languages))

	var dwarf_languages := CharacterData.get_default_languages_for_race("dwarf")
	check(dwarf_languages == ["common", "dwarvish", "goblin", "gnome", "kobold"],
		"dwarf defaults should match ACKS racial languages, got %s" % str(dwarf_languages))
	print("  default_languages_for_elf_and_dwarf: OK")


func test_get_character_sanitizes_legacy_language_json() -> void:
	var character := _make_character("Legacy Language JSON")
	check(CampaignRepository.save_character(character.to_dict()),
		"save_character should succeed for legacy language JSON test")

	var raw_languages := "[\"common\",\"alignment_lawful\",\"elvish\",\"common\",\"alignment_chaotic\"]"
	check(CampaignRepository.db.query_with_bindings(
		"UPDATE characters SET languages = ? WHERE id = ?",
		[raw_languages, character.id]
	), "direct UPDATE should seed a legacy language JSON payload")

	var row := CampaignRepository.get_character(character.id)
	check(row.get("languages", "") == "[\"common\",\"elvish\"]",
		"get_character should sanitize legacy language JSON on read")

	var loaded := CharacterData.from_dict(row)
	check(loaded.languages == "[\"common\",\"elvish\"]",
		"CharacterData.from_dict should keep the sanitized language JSON")

	check(CampaignRepository.save_character(loaded.to_dict()),
		"save_character should succeed after loading the sanitized character")
	check(CampaignRepository.db.query_with_bindings(
		"SELECT languages FROM characters WHERE id = ?",
		[character.id]
	), "SELECT languages should succeed after re-saving sanitized data")
	check(not CampaignRepository.db.query_result.is_empty(),
		"SELECT languages should return the saved character row")
	check(CampaignRepository.db.query_result[0].get("languages", "") == "[\"common\",\"elvish\"]",
		"re-saving should heal the stored language JSON")
	print("  get_character_sanitizes_legacy_language_json: OK")


func test_get_character_proficiencies_sanitizes_legacy_alignment_rows() -> void:
	var character := _make_character("Legacy Language Proficiencies")
	check(CampaignRepository.save_character(character.to_dict()),
		"save_character should succeed for legacy language proficiency test")
	check(CampaignRepository.db.query_with_bindings(
		"INSERT INTO character_proficiencies (character_id, proficiency_key, rank, slot_type, selections_count, specialization) VALUES (?, ?, ?, ?, ?, ?)",
		[character.id, "language", 1, "general", 1, "common"]
	), "direct INSERT should seed a valid language proficiency row")
	check(CampaignRepository.db.query_with_bindings(
		"INSERT INTO character_proficiencies (character_id, proficiency_key, rank, slot_type, selections_count, specialization) VALUES (?, ?, ?, ?, ?, ?)",
		[character.id, "language", 1, "general", 1, "alignment_lawful"]
	), "direct INSERT should seed a legacy alignment-language row")
	check(CampaignRepository.db.query_with_bindings(
		"INSERT INTO character_proficiencies (character_id, proficiency_key, rank, slot_type, selections_count, specialization) VALUES (?, ?, ?, ?, ?, ?)",
		[character.id, "language", 1, "general", 1, "common"]
	), "direct INSERT should seed a duplicate language row")
	check(CampaignRepository.db.query_with_bindings(
		"INSERT INTO character_proficiencies (character_id, proficiency_key, rank, slot_type, selections_count, specialization) VALUES (?, ?, ?, ?, ?, ?)",
		[character.id, "healing", 1, "general", 1, ""]
	), "direct INSERT should seed a non-language proficiency row")

	var profs := CampaignRepository.get_character_proficiencies(character.id)
	check(profs.size() == 2,
		"get_character_proficiencies should remove the deprecated and duplicate language rows")

	var saw_common := false
	var saw_healing := false
	for prof_var in profs:
		var prof: Dictionary = prof_var
		if prof.get("proficiency_key", "") == "language":
			saw_common = prof.get("specialization", "") == "common"
		elif prof.get("proficiency_key", "") == "healing":
			saw_healing = true

	check(saw_common, "sanitized proficiencies should preserve the real common language row")
	check(saw_healing, "sanitized proficiencies should preserve non-language rows")

	check(CampaignRepository.save_character_proficiencies(character.id, profs),
		"save_character_proficiencies should succeed after sanitization")
	check(CampaignRepository.db.query_with_bindings(
		"SELECT proficiency_key, specialization FROM character_proficiencies WHERE character_id = ? ORDER BY rowid",
		[character.id]
	), "SELECT character_proficiencies should succeed after re-saving sanitized data")
	check(CampaignRepository.db.query_result.size() == 2,
		"re-saving should heal the stored proficiency rows")
	print("  get_character_proficiencies_sanitizes_legacy_alignment_rows: OK")


func test_character_creation_finalize_does_not_grant_alignment_languages() -> void:
	var previous_campaign_id: String = GameState.campaign_id
	var previous_party_id: String = GameState.party_id
	GameState.campaign_id = _campaign_id
	GameState.party_id = _party_id

	var screen = CHARACTER_CREATION_SCREEN.new()
	var character := _make_character("Finalize Cleanup")
	character.intelligence = 13

	screen.creation_state = {
		"character": character,
		"name": character.name,
		"sex": "male",
		"alignment": "lawful",
		"portrait_id": "",
		"hp_rolled": 4,
		"language_bonus_picks": ["elvish"],
		"proficiencies": [],
		"bonus_proficiencies": [],
		"spells": [],
		"apostasy_spells": [],
		"inventory": [],
		"gold_remaining_cp": 0,
	}

	screen._finalize_character()

	var row := CampaignRepository.get_character(character.id)
	var languages := CharacterData.parse_languages_json(row.get("languages", "[]"))
	check(languages.size() == 2,
		"finalize should store only Common plus the chosen bonus language, got %s" % str(languages))
	check("common" in languages, "finalize should preserve Common")
	check("elvish" in languages, "finalize should preserve selected bonus languages")
	check(not ("alignment_lawful" in languages),
		"finalize should not grant alignment_lawful")
	check(not ("alignment_chaotic" in languages),
		"finalize should not grant alignment_chaotic")

	var profs := CampaignRepository.get_character_proficiencies(character.id)
	var language_specs: Array[String] = []
	for prof_var in profs:
		var prof: Dictionary = prof_var
		if prof.get("proficiency_key", "") == "language":
			language_specs.append(prof.get("specialization", ""))
	check(language_specs.size() == 2,
		"finalize should save only two language proficiency rows, got %d" % language_specs.size())
	check(not ("alignment_lawful" in language_specs),
		"finalize should not save alignment_lawful as a language proficiency")

	GameState.campaign_id = previous_campaign_id
	GameState.party_id = previous_party_id
	print("  character_creation_finalize_does_not_grant_alignment_languages: OK")


func test_character_creation_finalize_applies_elf_language_defaults() -> void:
	var previous_campaign_id: String = GameState.campaign_id
	var previous_party_id: String = GameState.party_id
	GameState.campaign_id = _campaign_id
	GameState.party_id = _party_id

	var screen = CHARACTER_CREATION_SCREEN.new()
	var character := _make_character("Elf Language Defaults")
	character.race = "elf"
	character.alignment = "neutral"

	screen.creation_state = {
		"character": character,
		"name": character.name,
		"sex": "female",
		"alignment": "neutral",
		"portrait_id": "",
		"hp_rolled": 4,
		"language_bonus_picks": ["draconic"],
		"proficiencies": [],
		"bonus_proficiencies": [],
		"spells": [],
		"apostasy_spells": [],
		"inventory": [],
		"gold_remaining_cp": 0,
	}

	screen._finalize_character()

	var row := CampaignRepository.get_character(character.id)
	var languages := CharacterData.parse_languages_json(row.get("languages", "[]"))
	var expected := ["common", "elvish", "gnoll", "hobgoblin", "orc", "draconic"]
	check(languages == expected,
		"elf finalize should include full racial defaults plus bonus picks, got %s" % str(languages))
	print("  character_creation_finalize_applies_elf_language_defaults: OK")

	GameState.campaign_id = previous_campaign_id
	GameState.party_id = previous_party_id


func test_character_sheet_preview_does_not_inject_alignment_languages() -> void:
	var panel = CHARACTER_SHEET_PANEL.new()
	panel._ready()
	panel.setup_registry(ClassRegistry.new())

	var character := _make_character("Preview Cleanup")
	character.languages = "[]"
	panel.display({
		"character": character,
		"class_id": "fighter",
		"portrait_id": "",
		"inventory": [],
		"proficiencies": [],
		"spells": [],
		"alignment": "lawful",
		"language_bonus_picks": ["elvish"],
	})

	var label_texts: Array = []
	_collect_label_texts(panel, label_texts)
	var joined := " | ".join(label_texts)
	check(joined.contains("Common"),
		"preview should still show Common in the language summary")
	check(joined.contains("Elvish"),
		"preview should still show picked bonus languages")
	check(not joined.contains("Alignment lawful"),
		"preview should not inject an alignment language label")
	check(not joined.contains("Alignment chaotic"),
		"preview should not inject a chaotic alignment language label")
	print("  character_sheet_preview_does_not_inject_alignment_languages: OK")


func test_character_sheet_preview_uses_dwarf_language_defaults() -> void:
	var panel = CHARACTER_SHEET_PANEL.new()
	panel._ready()
	panel.setup_registry(ClassRegistry.new())

	var character := _make_character("Dwarf Preview Cleanup")
	character.race = "dwarf"
	character.languages = "[]"
	panel.display({
		"character": character,
		"class_id": "fighter",
		"portrait_id": "",
		"inventory": [],
		"proficiencies": [],
		"spells": [],
		"language_bonus_picks": [],
	})

	var label_texts: Array = []
	_collect_label_texts(panel, label_texts)
	var joined := " | ".join(label_texts)
	check(joined.contains("Common"),
		"dwarf preview should show Common")
	check(joined.contains("Dwarvish"),
		"dwarf preview should show Dwarvish")
	check(joined.contains("Goblin"),
		"dwarf preview should show Goblin")
	check(joined.contains("Gnome"),
		"dwarf preview should show Gnome")
	check(joined.contains("Kobold"),
		"dwarf preview should show Kobold")
	print("  character_sheet_preview_uses_dwarf_language_defaults: OK")


func _make_character(name: String) -> CharacterData:
	var character := CharacterData.new()
	character.id = CampaignRepository.generate_id()
	character.campaign_id = _campaign_id
	character.name = name
	character.character_type = "pc"
	character.persistence_tier = "full"
	character.race = "human"
	character.character_class = "fighter"
	character.combat_progression = "fighter"
	character.level = 1
	character.strength = 10
	character.intelligence = 10
	character.wisdom = 10
	character.dexterity = 10
	character.constitution = 10
	character.charisma = 10
	character.hp_max = 4
	character.hp_current = 4
	character.attack_throw = 10
	character.save_petrification = 15
	character.save_poison_death = 14
	character.save_blast_breath = 16
	character.save_staffs_wands = 16
	character.save_spells = 17
	character.hit_die_type = "1d8"
	character.max_level = 14
	character.xp_for_next_level = 2000
	character.title = "Venturer"
	character.alignment = "lawful"
	character.sex = "male"
	return character


func _collect_label_texts(root: Node, texts: Array) -> void:
	for child in root.get_children():
		if child is Label:
			texts.append((child as Label).text)
		_collect_label_texts(child, texts)
