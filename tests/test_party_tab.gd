extends "res://tests/test_suite_base.gd"

## Focused tests for the Notebook Party tab page (γ.3 migration target).
##
## Covers:
##   - Page builds with header + 3 sub-tabs + modal layer at layer 100
##   - Composition sub-tab loads members for the active party
##   - Wilderness vs dungeon formation grids are independent (placement on
##     one does not affect the other; persistence round-trips through the
##     new dungeon_formation_col / dungeon_formation_row columns from
##     migration 043)
##   - Travel sub-tab daily/total/days computation for humanoid food + water
##   - Substate persistence: active sub-tab and active formation grid
##     round-trip via NotebookState


const PARTY_TAB_PAGE := preload("res://scenes/ui/notebook/tab_pages/party_tab_page.gd")


var _campaign_id: String = ""


func run_all_tests() -> void:
	_setup_campaign()

	test_page_builds_with_modal_layer_and_sub_tabs()
	test_composition_loads_party_members()
	test_wilderness_and_dungeon_grids_are_independent()
	test_travel_consumption_humanoid_food_and_water()
	test_substate_round_trip_active_subtab_and_grid()

	if not has_failures():
		print("PartyTab: all tests passed.")


func _setup_campaign() -> void:
	if not _campaign_id.is_empty():
		return
	_campaign_id = CampaignRepository.create_campaign(
		"Test Party Tab",
		"PartyTabTestWorld"
	)
	check(not _campaign_id.is_empty(),
		"create_campaign should return a non-empty ID for party-tab tests")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _create_basic_pc(suffix: String = "") -> String:
	var c := CharacterData.new()
	c.id = CampaignRepository.generate_id()
	c.campaign_id = _campaign_id
	c.name = "Party PC%s" % suffix
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
		"save_character should succeed for PC%s" % suffix)
	check(CampaignRepository.save_character_proficiencies(c.id, []),
		"save_character_proficiencies should succeed for PC%s" % suffix)
	return c.id


func _setup_party_with_two_pcs() -> Dictionary:
	var pc_a: String = _create_basic_pc("A")
	var pc_b: String = _create_basic_pc("B")
	var party_id: String = CampaignRepository.create_party(_campaign_id, "Party Tab Test")
	check(not party_id.is_empty(), "create_party should return a non-empty ID")
	check(CampaignRepository.add_party_member(party_id, pc_a, "middle"),
		"add_party_member should succeed for PC A")
	check(CampaignRepository.add_party_member(party_id, pc_b, "middle"),
		"add_party_member should succeed for PC B")
	GameState.campaign_id = _campaign_id
	GameState.party_id = party_id
	return {"party_id": party_id, "pc_a": pc_a, "pc_b": pc_b}


func _teardown() -> void:
	GameState.campaign_id = ""
	GameState.party_id = ""


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_page_builds_with_modal_layer_and_sub_tabs() -> void:
	var party := _setup_party_with_two_pcs()
	var page = PARTY_TAB_PAGE.new()
	add_child(page)

	check(page._modal_layer != null and page._modal_layer is CanvasLayer,
		"page should construct a CanvasLayer modal layer")
	check(page._modal_layer.layer == 100,
		"modal layer should sit at layer 100")
	check(page._subtab_buttons.size() == 3,
		"page should expose 3 sub-tab buttons; got %d" % page._subtab_buttons.size())
	for sid in [page.SUBTAB_COMPOSITION, page.SUBTAB_TRAVEL, page.SUBTAB_FORMATION]:
		check(page._subtab_buttons.has(sid),
			"sub-tab '%s' should be wired" % sid)

	page.queue_free()
	_teardown()
	print("  page_builds_with_modal_layer_and_sub_tabs: OK (party_id=%s)" % party["party_id"])


func test_composition_loads_party_members() -> void:
	var party := _setup_party_with_two_pcs()
	var page = PARTY_TAB_PAGE.new()
	add_child(page)

	page._activate_subtab(page.SUBTAB_COMPOSITION)
	check(page._party != null,
		"page should resolve _party for the active GameState.party_id")
	check(page._party.character_data.size() == 2,
		"composition should load both PCs into PartyData; got %d"
		% page._party.character_data.size())

	page.queue_free()
	_teardown()
	print("  composition_loads_party_members: OK (party_id=%s)" % party["party_id"])


func test_wilderness_and_dungeon_grids_are_independent() -> void:
	var party := _setup_party_with_two_pcs()
	var page = PARTY_TAB_PAGE.new()
	add_child(page)

	# Wilderness placement (PC A at row 2 col 3).
	CampaignRepository.update_party_member_formation(party["party_id"], party["pc_a"], 3, 2)
	# Dungeon placement (PC A at row 0 col 1).
	CampaignRepository.update_party_member_dungeon_formation(party["party_id"], party["pc_a"], 1, 0)

	# Reload via the page's _load_party so PartyData reflects DB state.
	page._load_party()

	var wilderness_pos: Vector2i = page._party.get_formation_pos_for(party["pc_a"], PartyData.GRID_WILDERNESS)
	var dungeon_pos: Vector2i = page._party.get_formation_pos_for(party["pc_a"], PartyData.GRID_DUNGEON)

	check(wilderness_pos == Vector2i(3, 2),
		"wilderness formation should round-trip; got (%d, %d)" % [wilderness_pos.x, wilderness_pos.y])
	check(dungeon_pos == Vector2i(1, 0),
		"dungeon formation should round-trip independently; got (%d, %d)"
		% [dungeon_pos.x, dungeon_pos.y])
	check(wilderness_pos != dungeon_pos,
		"the two grids must persist independent positions")

	page.queue_free()
	_teardown()
	print("  wilderness_and_dungeon_grids_are_independent: OK (party_id=%s)" % party["party_id"])


func test_travel_consumption_humanoid_food_and_water() -> void:
	var party := _setup_party_with_two_pcs()
	var page = PARTY_TAB_PAGE.new()
	add_child(page)
	page._activate_subtab(page.SUBTAB_TRAVEL)

	var consumption := page._compute_daily_consumption()
	# 2 PCs × 1/6 stone food/day = 2/6 ≈ 0.333
	check(abs(consumption["food"] - 2.0 / 6.0) < 0.001,
		"food consumption for 2 PCs should be 2/6 stone; got %.3f" % consumption["food"])
	# 2 PCs × 5/6 stone water/day (no animals) = 10/6 ≈ 1.667
	check(abs(consumption["water"] - 2.0 * 5.0 / 6.0) < 0.001,
		"water consumption for 2 PCs (no animals) should be 10/6 stone; got %.3f" % consumption["water"])
	# No animals → fodder = 0
	check(consumption["fodder"] == 0.0,
		"no animals → fodder consumption should be 0; got %.3f" % consumption["fodder"])

	page.queue_free()
	_teardown()
	print("  travel_consumption_humanoid_food_and_water: OK (party_id=%s)" % party["party_id"])


func test_substate_round_trip_active_subtab_and_grid() -> void:
	var pid := "test_party_tab_substate_%d" % Time.get_ticks_usec()
	NotebookState.set_substate_for_tab(pid, "party", {
		"active_subtab":         "formation",
		"formation_active_grid": "dungeon",
	})
	var loaded := NotebookState.get_substate_for_tab(pid, "party")
	check(loaded.get("active_subtab", "") == "formation",
		"substate should preserve active_subtab")
	check(loaded.get("formation_active_grid", "") == "dungeon",
		"substate should preserve formation_active_grid")
	print("  substate_round_trip_active_subtab_and_grid: OK")
