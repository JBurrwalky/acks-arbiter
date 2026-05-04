extends "res://tests/test_suite_base.gd"

## Focused regression tests for the character-sheet Advancement tab lifecycle.

const CHARACTER_TAB_PAGE := preload("res://scenes/ui/notebook/tab_pages/character_tab_page.gd")

var _campaign_id: String = ""
var _class_registry: ClassRegistry = ClassRegistry.new()
var _spec_registry: SpecializationRegistry = SpecializationRegistry.new()
var _prof_registry: ProficiencyRegistry = ProficiencyRegistry.new(_spec_registry)
var _power_registry: PowerRegistry = PowerRegistry.new()
var _spell_registry: SpellRegistry = SpellRegistry.new()


func run_all_tests() -> void:
	_setup_campaign()
	test_interactive_begin_sets_pending_and_mutates_preview()
	test_cancel_restores_persisted_state()
	test_abort_pending_level_up_clears_popup_and_restores_character()
	test_overlay_tab_switch_aborts_pending_level_up()
	test_overlay_close_aborts_pending_level_up()
	test_confirm_persists_level_up()
	if not has_failures():
		print("CSTabAdvancement: all tests passed.")


func _setup_campaign() -> void:
	if not _campaign_id.is_empty():
		return
	_campaign_id = CampaignRepository.create_campaign(
		"Test Advancement Lifecycle",
		"AdvancementTestWorld"
	)
	check(not _campaign_id.is_empty(),
		"create_campaign should return a non-empty ID for advancement tests")


func _make_registries() -> Dictionary:
	return {
		"class_registry": _class_registry,
		"proficiency_registry": _prof_registry,
		"power_registry": _power_registry,
		"spell_registry": _spell_registry,
	}


func _create_fighter(level: int = 1, xp_override: int = -1) -> String:
	var character := CharacterData.new()
	character.id = CampaignRepository.generate_id()
	character.campaign_id = _campaign_id
	character.name = "Advancement Test Fighter L%d" % level
	character.character_type = "pc"
	character.persistence_tier = "full"
	character.race = "human"
	character.character_class = "fighter"
	character.combat_progression = "fighter"
	character.level = level
	character.strength = 10
	character.intelligence = 10
	character.wisdom = 10
	character.dexterity = 10
	character.constitution = 10
	character.charisma = 10
	character.hit_die_type = _class_registry.get_hit_die("fighter")
	character.max_level = 14
	character.xp_for_next_level = _class_registry.get_xp_for_level("fighter", level + 1) \
		if level < character.max_level else 0
	character.xp = xp_override if xp_override >= 0 else character.xp_for_next_level
	character.hp_max = 8 + ((level - 1) * 2)
	character.hp_current = character.hp_max
	character.attack_throw = _class_registry.get_attack_throw("fighter", level)
	var saves: Dictionary = _class_registry.get_saving_throws("fighter", level)
	character.save_petrification = int(saves.get("petrification", 15))
	character.save_poison_death = int(saves.get("poison_death", 14))
	character.save_blast_breath = int(saves.get("blast_breath", 16))
	character.save_staffs_wands = int(saves.get("staffs_wands", 16))
	character.save_spells = int(saves.get("spells", 17))
	character.title = _class_registry.get_level_title("fighter", level)

	check(CampaignRepository.save_character(character.to_dict()),
		"save_character should succeed for advancement test fighter")
	check(CampaignRepository.save_character_proficiencies(character.id, []),
		"save_character_proficiencies should succeed for advancement test fighter")
	return character.id


func _load_bundle(character_id: String) -> CharacterBundle:
	var row: Dictionary = CampaignRepository.get_character(character_id)
	var bundle := CharacterBundle.new()
	bundle.character = CharacterData.from_dict(row)
	bundle.proficiencies = CampaignRepository.get_character_proficiencies(character_id)
	bundle.character.proficiencies = bundle.proficiencies
	bundle.inventory = []
	bundle.spells = []
	bundle.formulas = []
	bundle.expended_slots = {}
	bundle.powers = CampaignRepository.get_character_powers(character_id)
	bundle.conditions = []
	bundle.active_effects = []
	bundle.henchmen = []
	return bundle


func _start_level_up(tab: CSTabAdvancement, bundle: CharacterBundle) -> LevelUpEngine:
	tab.display(bundle, _make_registries())
	var next_level: int = bundle.character.level + 1
	GameState.dice_overrides["level_up_hp_L%d" % next_level] = 5
	var engine: LevelUpEngine = tab._make_level_up_engine()
	tab._on_level_up_pressed(bundle.character, engine)
	return engine


func _create_party(character_ids: Array[String]) -> String:
	var party_id: String = CampaignRepository.create_party(_campaign_id, "Advancement Test Party")
	check(not party_id.is_empty(), "create_party should return a non-empty ID")
	for character_id in character_ids:
		check(CampaignRepository.add_party_member(party_id, character_id, "middle"),
			"add_party_member should succeed for '%s'" % character_id)
	return party_id


func test_interactive_begin_sets_pending_and_mutates_preview() -> void:
	var character_id: String = _create_fighter(1)
	var bundle: CharacterBundle = _load_bundle(character_id)
	var original_title: String = bundle.character.title
	var tab: CSTabAdvancement = CSTabAdvancement.new()

	var engine: LevelUpEngine = _start_level_up(tab, bundle)

	check(tab.has_pending_level_up(),
		"begin_interactive_level_up should mark the Advancement tab as pending")
	check(bundle.character.level == 2,
		"begin_interactive_level_up should mutate the in-memory preview level")
	check(bundle.character.title != original_title,
		"begin_interactive_level_up should update the in-memory preview title")
	check(not engine.can_level_up(bundle.character),
		"mutated preview state should no longer appear eligible until aborted or confirmed")
	print("  interactive_begin_sets_pending_and_mutates_preview: OK")


func test_cancel_restores_persisted_state() -> void:
	var character_id: String = _create_fighter(1)
	var bundle: CharacterBundle = _load_bundle(character_id)
	var original_title: String = bundle.character.title
	var tab: CSTabAdvancement = CSTabAdvancement.new()

	var engine: LevelUpEngine = _start_level_up(tab, bundle)
	tab._on_cancel_level_up(bundle.character)

	check(not tab.has_pending_level_up(), "cancel should clear pending level-up state")
	check(bundle.character.level == 1, "cancel should restore the persisted level")
	check(bundle.character.title == original_title, "cancel should restore the persisted title")
	check(engine.can_level_up(bundle.character),
		"cancel should restore a state that can level up again")
	print("  cancel_restores_persisted_state: OK")


func test_abort_pending_level_up_clears_popup_and_restores_character() -> void:
	var character_id: String = _create_fighter(2)
	var bundle: CharacterBundle = _load_bundle(character_id)
	var original_title: String = bundle.character.title
	var tab: CSTabAdvancement = CSTabAdvancement.new()

	var engine: LevelUpEngine = _start_level_up(tab, bundle)
	check(tab._proficiency_popup != null,
		"fighter level 2->3 should create a proficiency popup host")
	tab._on_open_proficiency_popup()
	check(tab._proficiency_popup != null and tab._proficiency_popup.visible,
		"opening the proficiency popup should show it before abort")

	tab.abort_pending_level_up()

	check(not tab.has_pending_level_up(), "abort_pending_level_up should clear pending state")
	check(bundle.character.level == 2, "abort_pending_level_up should restore the persisted level")
	check(bundle.character.title == original_title,
		"abort_pending_level_up should restore the persisted title")
	check(tab._proficiency_popup == null,
		"abort_pending_level_up should clear the popup reference after rebuilding")
	check(tab._proficiency_picker == null,
		"abort_pending_level_up should clear the picker reference after rebuilding")
	check(engine.can_level_up(bundle.character),
		"abort_pending_level_up should leave the character eligible to level up again")
	print("  abort_pending_level_up_clears_popup_and_restores_character: OK")


func test_overlay_tab_switch_aborts_pending_level_up() -> void:
	# Re-targeted in γ.1 to the notebook Character tab. Verifies that switching
	# away from the Advancement section discards an in-progress level-up
	# preview, mirroring the behavior the deleted CharacterSheetOverlay had on
	# TabContainer.tab_changed.
	var character_id: String = _create_fighter(1)
	var party_id: String = _create_party([character_id])
	GameState.campaign_id = _campaign_id
	GameState.party_id = party_id

	var page = CHARACTER_TAB_PAGE.new()
	add_child(page)
	page._on_section_selected("advancement")
	var advancement_tab: CSTabAdvancement = page._section_pages.get("advancement")
	check(advancement_tab != null,
		"selecting the Advancement section should instantiate CSTabAdvancement")

	advancement_tab._on_level_up_pressed(
		page._active_bundle.character,
		advancement_tab._make_level_up_engine()
	)

	check(advancement_tab.has_pending_level_up(),
		"page should have pending state after starting level-up")
	check(page._active_bundle.character.level == 2,
		"page bundle should hold the mutated preview before switching sections")

	page._on_section_selected("biography")

	var engine: LevelUpEngine = advancement_tab._make_level_up_engine()
	check(not advancement_tab.has_pending_level_up(),
		"switching away from Advancement should abort the pending level-up")
	check(page._active_bundle.character.level == 1,
		"switching sections should restore the persisted character level")
	check(engine.can_level_up(page._active_bundle.character),
		"switching sections should allow level-up to start again immediately")
	print("  character_tab_section_switch_aborts_pending_level_up: OK")
	page.queue_free()
	GameState.campaign_id = ""
	GameState.party_id = ""


func test_overlay_close_aborts_pending_level_up() -> void:
	# Re-targeted in γ.1 to the notebook Character tab. Verifies that the
	# notebook_closed signal aborts an in-progress level-up preview, mirroring
	# the behavior the deleted CharacterSheetOverlay had on _close().
	var character_id: String = _create_fighter(1)
	var party_id: String = _create_party([character_id])
	GameState.campaign_id = _campaign_id
	GameState.party_id = party_id

	var page = CHARACTER_TAB_PAGE.new()
	add_child(page)
	page._on_section_selected("advancement")
	var advancement_tab: CSTabAdvancement = page._section_pages.get("advancement")
	advancement_tab._on_level_up_pressed(
		page._active_bundle.character,
		advancement_tab._make_level_up_engine()
	)

	check(advancement_tab.has_pending_level_up(),
		"page should have pending state before notebook close")

	EventBus.notebook_closed.emit()

	check(not advancement_tab.has_pending_level_up(),
		"notebook_closed should abort the pending level-up")
	check(page._active_bundle.character.level == 1,
		"notebook_closed should restore the persisted character level")

	var engine: LevelUpEngine = advancement_tab._make_level_up_engine()
	check(engine.can_level_up(page._active_bundle.character),
		"after abort the character should be eligible to level up again")
	print("  character_tab_notebook_close_aborts_pending_level_up: OK")
	page.queue_free()
	GameState.campaign_id = ""
	GameState.party_id = ""


func test_confirm_persists_level_up() -> void:
	var character_id: String = _create_fighter(1)
	var bundle: CharacterBundle = _load_bundle(character_id)
	var tab: CSTabAdvancement = CSTabAdvancement.new()

	var engine: LevelUpEngine = _start_level_up(tab, bundle)
	tab._on_confirm_level_up(bundle.character, engine)

	var saved_row: Dictionary = CampaignRepository.get_character(character_id)
	check(not tab.has_pending_level_up(), "confirm should clear pending level-up state")
	check(int(saved_row.get("level", 0)) == 2,
		"confirm should persist the new level to the database")
	check(str(saved_row.get("title", "")) == _class_registry.get_level_title("fighter", 2),
		"confirm should persist the new title to the database")
	print("  confirm_persists_level_up: OK")
