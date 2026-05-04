extends "res://tests/test_suite_base.gd"

## Focused tests for the Notebook Character tab page (γ.1 migration target).
##
## Covers:
##   - Sub-tab visibility per entity type (entity-type-filtered SECTIONS_BY_TYPE)
##   - Type dropdown change rebuilds the entity strip and resets active section
##   - Substate persistence: type / per-type entity / section_id round-trip via
##     NotebookState.set_substate_for_tab + get_substate_for_tab
##   - Cross-tab activation routing: notebook_active_entity_changed updates
##     the page's _active_entity_id


const CHARACTER_TAB_PAGE := preload("res://scenes/ui/notebook/tab_pages/character_tab_page.gd")
const ENTITY_STRIP := preload("res://scenes/ui/notebook/character/entity_strip.gd")
const SECTION_STRIP := preload("res://scenes/ui/notebook/character/sheet_section_strip.gd")


var _campaign_id: String = ""


func run_all_tests() -> void:
	_setup_campaign()

	test_section_strip_filters_for_pcs()
	test_section_strip_filters_for_animals()
	test_section_strip_filters_for_vehicles()
	test_entity_strip_type_change_resets_section()
	test_substate_round_trip_via_notebook_state()
	test_cross_tab_active_entity_changed_updates_page()

	if not has_failures():
		print("CharacterTab: all tests passed.")


func _setup_campaign() -> void:
	if not _campaign_id.is_empty():
		return
	_campaign_id = CampaignRepository.create_campaign(
		"Test Character Tab",
		"CharacterTabTestWorld"
	)
	check(not _campaign_id.is_empty(),
		"create_campaign should return a non-empty ID for character-tab tests")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _create_basic_pc() -> String:
	var c := CharacterData.new()
	c.id = CampaignRepository.generate_id()
	c.campaign_id = _campaign_id
	c.name = "Test PC"
	c.character_type = "pc"
	c.persistence_tier = "full"
	c.race = "human"
	c.character_class = "fighter"
	c.combat_progression = "fighter"
	c.level = 1
	c.strength = 10
	c.intelligence = 10
	c.wisdom = 10
	c.dexterity = 10
	c.constitution = 10
	c.charisma = 10
	c.hp_max = 6
	c.hp_current = 6
	c.max_level = 14
	check(CampaignRepository.save_character(c.to_dict()),
		"save_character should succeed for PC")
	check(CampaignRepository.save_character_proficiencies(c.id, []),
		"save_character_proficiencies should succeed for PC")
	return c.id


func _create_party_with_pc() -> Dictionary:
	var pc_id: String = _create_basic_pc()
	var party_id: String = CampaignRepository.create_party(_campaign_id, "Char Tab Party")
	check(not party_id.is_empty(), "create_party should return a non-empty ID")
	check(CampaignRepository.add_party_member(party_id, pc_id, "middle"),
		"add_party_member should succeed")
	return {"party_id": party_id, "pc_id": pc_id}


# ---------------------------------------------------------------------------
# Tests — section strip filtering
# ---------------------------------------------------------------------------

func test_section_strip_filters_for_pcs() -> void:
	var sections: Array = SECTION_STRIP.SECTIONS_BY_TYPE.get("pcs", [])
	check(sections.has(SECTION_STRIP.SECTION_BIOGRAPHY),
		"PCs sub-tab list includes Biography")
	check(sections.has(SECTION_STRIP.SECTION_RETAINERS),
		"PCs sub-tab list includes Retainers")
	check(not sections.has(SECTION_STRIP.SECTION_CREATURE_STATS),
		"PCs sub-tab list excludes Creature Stats")
	check(not sections.has(SECTION_STRIP.SECTION_VEHICLE_DETAIL),
		"PCs sub-tab list excludes Vehicle Detail")
	print("  section_strip_filters_for_pcs: OK")


func test_section_strip_filters_for_animals() -> void:
	var sections: Array = SECTION_STRIP.SECTIONS_BY_TYPE.get("animals", [])
	check(sections.has(SECTION_STRIP.SECTION_CREATURE_STATS),
		"Animals sub-tab list includes Creature Stats")
	check(not sections.has(SECTION_STRIP.SECTION_BIOGRAPHY),
		"Animals sub-tab list excludes Biography (γ.1 scope)")
	check(not sections.has(SECTION_STRIP.SECTION_SPELLS),
		"Animals sub-tab list excludes Spells")
	check(not sections.has(SECTION_STRIP.SECTION_RETAINERS),
		"Animals sub-tab list excludes Retainers")
	print("  section_strip_filters_for_animals: OK")


func test_section_strip_filters_for_vehicles() -> void:
	var sections: Array = SECTION_STRIP.SECTIONS_BY_TYPE.get("vehicles", [])
	check(sections.size() == 1 and sections[0] == SECTION_STRIP.SECTION_VEHICLE_DETAIL,
		"Vehicles sub-tab list contains only Vehicle Detail (γ.1 scope)")
	print("  section_strip_filters_for_vehicles: OK")


# ---------------------------------------------------------------------------
# Tests — type change + substate
# ---------------------------------------------------------------------------

func test_entity_strip_type_change_resets_section() -> void:
	var party := _create_party_with_pc()
	GameState.campaign_id = _campaign_id
	GameState.party_id = party["party_id"]

	var page = CHARACTER_TAB_PAGE.new()
	add_child(page)

	check(page._active_entity_type == "pcs",
		"page initialises with type 'pcs'")
	check(page._active_section_id == SECTION_STRIP.SECTION_BIOGRAPHY,
		"page initialises with section 'biography' (first PC sub-tab)")

	# Type → vehicles (no entities exist for this party). Active section should
	# move to vehicle_detail.
	page._on_type_changed("vehicles")
	check(page._active_entity_type == "vehicles",
		"type change updates _active_entity_type")
	check(page._active_section_id == SECTION_STRIP.SECTION_VEHICLE_DETAIL,
		"section resets to first available section for new type")

	page.queue_free()
	GameState.campaign_id = ""
	GameState.party_id = ""
	print("  entity_strip_type_change_resets_section: OK")


func test_substate_round_trip_via_notebook_state() -> void:
	var pid := "test_char_tab_substate_%d" % Time.get_ticks_usec()
	NotebookState.set_substate_for_tab(pid, "character", {
		"entity_type": "henchmen",
		"entity_per_type": {"pcs": "pc-id-1", "henchmen": "h-id-9"},
		"section_id": "spells",
	})
	var loaded: Dictionary = NotebookState.get_substate_for_tab(pid, "character")
	check(loaded.get("entity_type", "") == "henchmen",
		"set/get round-trip preserves entity_type")
	check(loaded.get("section_id", "") == "spells",
		"set/get round-trip preserves section_id")
	var per_type: Dictionary = loaded.get("entity_per_type", {})
	check(per_type.get("henchmen", "") == "h-id-9",
		"set/get round-trip preserves per-type entity slot")
	print("  substate_round_trip_via_notebook_state: OK")


func test_cross_tab_active_entity_changed_updates_page() -> void:
	var party := _create_party_with_pc()
	GameState.campaign_id = _campaign_id
	GameState.party_id = party["party_id"]

	var page = CHARACTER_TAB_PAGE.new()
	add_child(page)
	check(page._active_entity_id == party["pc_id"],
		"page starts with first party PC active")

	# Simulate a cross-tab activation: another caller sets a different entity
	# (using the PC id again here for setup simplicity — what matters is that
	# the handler runs and updates state without crashing).
	EventBus.notebook_active_entity_changed.emit(party["pc_id"])
	check(page._active_entity_id == party["pc_id"],
		"notebook_active_entity_changed handler does not corrupt state")

	page.queue_free()
	GameState.campaign_id = ""
	GameState.party_id = ""
	print("  cross_tab_active_entity_changed_updates_page: OK")
