extends "res://tests/test_suite_base.gd"

## Focused tests for the Notebook Inventory tab page (γ.2 migration target).
##
## Covers:
##   - Page builds without error and creates a `_modal_layer` CanvasLayer at
##     layer 100 for sub-modal parenting
##   - Carrier columns load for the active party (PCs + henchmen)
##   - Sub-modal lazy instantiation parents the modal under `_modal_layer`,
##     not the page Control directly
##   - Filter dropdown applies to all columns


const INVENTORY_TAB_PAGE := preload("res://scenes/ui/notebook/tab_pages/inventory_tab_page.gd")


var _campaign_id: String = ""


func run_all_tests() -> void:
	_setup_campaign()

	test_page_builds_modal_layer()
	test_load_columns_for_party_with_pc_and_henchman()
	test_prefs_modal_parents_under_modal_layer()
	test_filter_dropdown_propagates_to_columns()

	if not has_failures():
		print("InventoryTab: all tests passed.")


func _setup_campaign() -> void:
	if not _campaign_id.is_empty():
		return
	_campaign_id = CampaignRepository.create_campaign(
		"Test Inventory Tab",
		"InventoryTabTestWorld"
	)
	check(not _campaign_id.is_empty(),
		"create_campaign should return a non-empty ID for inventory-tab tests")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _create_basic_pc(suffix: String = "") -> String:
	var c := CharacterData.new()
	c.id = CampaignRepository.generate_id()
	c.campaign_id = _campaign_id
	c.name = "Inv Test PC%s" % suffix
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


func _create_henchman(employer_id: String) -> String:
	var c := CharacterData.new()
	c.id = CampaignRepository.generate_id()
	c.campaign_id = _campaign_id
	c.name = "Test Henchman"
	c.character_type = "henchman"
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
	c.hp_max = 5
	c.hp_current = 5
	c.max_level = 14
	c.employer_id = employer_id
	check(CampaignRepository.save_character(c.to_dict()),
		"save_character should succeed for henchman")
	check(CampaignRepository.save_character_proficiencies(c.id, []),
		"save_character_proficiencies should succeed for henchman")
	return c.id


func _setup_party_with_pc_and_henchman() -> Dictionary:
	var pc_id: String = _create_basic_pc()
	var henchman_id: String = _create_henchman(pc_id)
	var party_id: String = CampaignRepository.create_party(_campaign_id, "Inv Tab Party")
	check(not party_id.is_empty(), "create_party should return a non-empty ID")
	check(CampaignRepository.add_party_member(party_id, pc_id, "middle"),
		"add_party_member should succeed for PC")
	check(CampaignRepository.add_party_member(party_id, henchman_id, "middle"),
		"add_party_member should succeed for henchman")
	GameState.campaign_id = _campaign_id
	GameState.party_id = party_id
	return {"party_id": party_id, "pc_id": pc_id, "henchman_id": henchman_id}


func _teardown() -> void:
	GameState.campaign_id = ""
	GameState.party_id = ""


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_page_builds_modal_layer() -> void:
	var party := _setup_party_with_pc_and_henchman()
	var page = INVENTORY_TAB_PAGE.new()
	add_child(page)

	check(page._modal_layer != null,
		"page should construct a _modal_layer for sub-modal parenting")
	check(page._modal_layer is CanvasLayer,
		"_modal_layer should be a CanvasLayer")
	check(page._modal_layer.layer == 100,
		"_modal_layer should sit at layer 100 (above notebook layer 35)")

	page.queue_free()
	_teardown()
	print("  page_builds_modal_layer: OK (party_id=%s)" % party["party_id"])


func test_load_columns_for_party_with_pc_and_henchman() -> void:
	var party := _setup_party_with_pc_and_henchman()
	var page = INVENTORY_TAB_PAGE.new()
	add_child(page)

	# _build_content was called from _ready and ran _load_columns since the
	# session is active. Both PCs and henchmen should render columns.
	check(page._columns.size() >= 2,
		"page should load at least 2 carrier columns (PC + henchman); got %d"
		% page._columns.size())

	page.queue_free()
	_teardown()
	print("  load_columns_for_party_with_pc_and_henchman: OK (party_id=%s)" % party["party_id"])


func test_prefs_modal_parents_under_modal_layer() -> void:
	var party := _setup_party_with_pc_and_henchman()
	var page = INVENTORY_TAB_PAGE.new()
	add_child(page)

	page._ensure_prefs_modal()
	check(page._prefs_modal != null,
		"_ensure_prefs_modal should instantiate the prefs modal")
	check(page._prefs_modal.get_parent() == page._modal_layer,
		"prefs modal should be parented to _modal_layer for layer-100 rendering")

	page.queue_free()
	_teardown()
	print("  prefs_modal_parents_under_modal_layer: OK (party_id=%s)" % party["party_id"])


func test_filter_dropdown_propagates_to_columns() -> void:
	var party := _setup_party_with_pc_and_henchman()
	var page = INVENTORY_TAB_PAGE.new()
	add_child(page)

	# Programmatically apply the "weapons" filter (index 2 per FILTER_LABELS).
	page._apply_filter(2)

	for col in page._columns:
		check(col._current_filter == "weapons",
			"every carrier column should adopt the active filter; got '%s'"
			% col._current_filter)

	page.queue_free()
	_teardown()
	print("  filter_dropdown_propagates_to_columns: OK (party_id=%s)" % party["party_id"])
