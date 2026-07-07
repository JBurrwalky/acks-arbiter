extends "res://tests/test_suite_base.gd"

## UI tests for armies_section + army_detail_panel + army_marching_context_menu
## + commander_departure_check.
##
## Tests focus on data binding correctness rather than pixel-perfect rendering:
## given known DB state, the UI scenes populate their internal nodes correctly.

const ArmiesSectionScript := preload("res://scenes/ui/notebook/troops/armies_section.gd")
const ArmyDetailPanelScript := preload("res://scenes/ui/notebook/troops/army_detail_panel.gd")
const MarchingMenuScript := preload("res://scenes/ui/troops/army_marching_context_menu.gd")

var _campaign_id: String = ""
var _ruler_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_armies_section_empty_state()
	test_armies_section_populates_card_list()
	test_armies_section_form_button_disabled_below_threshold()
	test_armies_section_form_button_enabled_at_threshold()
	test_army_detail_panel_renders_officer_hierarchy()
	test_army_detail_panel_renders_unit_roster()
	test_army_detail_panel_read_only_hides_actions()
	test_marching_menu_for_encamped_army_includes_march()
	test_marching_menu_for_marching_army_includes_encamp_only()
	test_marching_menu_executes_march_action()
	test_marching_menu_march_gated_by_adjacency()
	test_marching_menu_extraction_eligibility()
	test_marching_menu_extraction_dispatch()
	test_marching_menu_marching_has_disband_and_encamp()
	test_marching_menu_options_shape_has_cancel()
	test_commander_departure_check_returns_active_armies()
	test_commander_departure_check_excludes_disbanded()
	if not has_failures():
		print("ArmiesSectionUI: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("UI Test", "World")
	_ruler_id = _make_character("Wymar")


func _make_character(name: String) -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, ?, 'pc', 'full', 'human', 'fighter', 9,
			14, 12, 12, 12, 12, 14, 60, 60)
	""", [id, _campaign_id, name])
	return id


func _make_unit() -> String:
	return TroopUnitRepository.create_unit({
		"campaign_id": _campaign_id, "owner_character_id": _ruler_id,
		"source_type": "mercenary", "troop_type": "Heavy Infantry",
		"count": 60, "starting_count": 60, "battle_rating": 1.0,
		"monthly_wage_cp": 600,
	})


func _build_army_with_units(unit_count: int) -> String:
	var army_id: String = ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": "Test Host",
		"political_owner_id": _ruler_id, "command_character_id": _ruler_id,
		"state": "encamped",
	})
	ArmyRepository.create_supply_state({"army_id": army_id})
	var leader: String = ArmyRepository.create_officer({
		"army_id": army_id, "character_id": _ruler_id, "rank": "army_leader",
		"appointed_calendar_day": 100,
	})
	for i in range(unit_count):
		var unit_id: String = _make_unit()
		ArmyRepository.create_assignment({
			"army_id": army_id, "troop_unit_id": unit_id,
			"parent_officer_id": leader, "role": "line",
			"assigned_calendar_day": 100,
		})
	return army_id


func test_armies_section_empty_state() -> void:
	var section = ArmiesSectionScript.new()
	add_child(section)
	# Active entity has no armies.
	section.set_active_entity(_ruler_id, "pc")
	# Header should reflect 0.
	check(section._header_label.text == "Armies (0)", "header shows 0")
	section.queue_free()


func test_armies_section_populates_card_list() -> void:
	var army_id := _build_army_with_units(3)
	var section = ArmiesSectionScript.new()
	add_child(section)
	section.set_active_entity(_ruler_id, "pc")
	check(section._header_label.text.contains("(1)"), "header shows 1 army; got %s" % section._header_label.text)
	# Cards are children of _list_vbox.
	check(section._list_vbox.get_child_count() >= 1, "list has at least 1 card")
	section.queue_free()
	var _ignored := army_id


func test_armies_section_form_button_disabled_below_threshold() -> void:
	# Make a fresh ruler with only 2 unaligned units.
	var fresh_id := _make_character("FewUnits")
	for i in range(2):
		TroopUnitRepository.create_unit({
			"campaign_id": _campaign_id, "owner_character_id": fresh_id,
			"source_type": "mercenary", "troop_type": "Heavy Infantry",
			"count": 60, "starting_count": 60, "battle_rating": 1.0,
		})
	var section = ArmiesSectionScript.new()
	add_child(section)
	section.set_active_entity(fresh_id, "pc")
	check(section._form_button.disabled, "Form Army disabled with <3 units")
	section.queue_free()


func test_armies_section_form_button_enabled_at_threshold() -> void:
	var fresh_id := _make_character("ManyUnits")
	for i in range(3):
		TroopUnitRepository.create_unit({
			"campaign_id": _campaign_id, "owner_character_id": fresh_id,
			"source_type": "mercenary", "troop_type": "Heavy Infantry",
			"count": 60, "starting_count": 60, "battle_rating": 1.0,
		})
	var section = ArmiesSectionScript.new()
	add_child(section)
	section.set_active_entity(fresh_id, "pc")
	check(not section._form_button.disabled, "Form Army enabled with ≥3 units")
	section.queue_free()


func test_army_detail_panel_renders_officer_hierarchy() -> void:
	var army_id := _build_army_with_units(3)
	var panel = ArmyDetailPanelScript.new()
	add_child(panel)
	panel.display(army_id)
	check(panel._hierarchy_box != null, "hierarchy_box created")
	# Hierarchy box should have at least 2 children: header + at least 1 line.
	check(panel._hierarchy_box.get_child_count() >= 2, "hierarchy populated")
	panel.queue_free()


func test_army_detail_panel_renders_unit_roster() -> void:
	var army_id := _build_army_with_units(2)
	var panel = ArmyDetailPanelScript.new()
	add_child(panel)
	panel.display(army_id)
	# Roster box has header + 2 unit lines = 3 children.
	check(panel._roster_box.get_child_count() == 3, "roster has 1 header + 2 units; got %d" % panel._roster_box.get_child_count())
	panel.queue_free()


func test_army_detail_panel_read_only_hides_actions() -> void:
	var army_id := _build_army_with_units(2)
	var panel = ArmyDetailPanelScript.new()
	add_child(panel)
	panel.display(army_id, true)
	# Read-only mode shows an observation-only note, never command buttons.
	var has_button := false
	for child in panel._action_bar.get_children():
		if child is Button:
			has_button = true
	check(not has_button, "read-only detail panel shows no command buttons")
	panel.queue_free()


func test_marching_menu_for_encamped_army_includes_march() -> void:
	var army_id := _build_army_with_units(3)
	var items := MarchingMenuScript.build_items_for_army(army_id, 6, 5)
	var actions: Array = []
	for item in items:
		actions.append(str(item.get("action", "")))
	check(actions.has(MarchingMenuScript.ACTION_MARCH), "encamped army has March action")
	check(actions.has(MarchingMenuScript.ACTION_MARCH_FORCED), "has Forced March")
	check(actions.has(MarchingMenuScript.ACTION_MARCH_CAUTIOUS), "has Cautious March")
	check(actions.has(MarchingMenuScript.ACTION_DISBAND), "has Disband")


func test_marching_menu_for_marching_army_includes_encamp_only() -> void:
	var army_id := _build_army_with_units(3)
	ArmyRepository.update_army(army_id, {"state": "marching"})
	var items := MarchingMenuScript.build_items_for_army(army_id, 6, 5)
	var actions: Array = []
	for item in items:
		actions.append(str(item.get("action", "")))
	check(actions.has(MarchingMenuScript.ACTION_ENCAMP), "marching army has Encamp")
	check(not actions.has(MarchingMenuScript.ACTION_MARCH), "marching army does not have March")


func test_marching_menu_executes_march_action() -> void:
	var army_id := _build_army_with_units(2)
	var scheduler := EventScheduler.new()
	var result := MarchingMenuScript.execute_action(
		MarchingMenuScript.ACTION_MARCH, army_id, 6, 5, 0, scheduler
	)
	check(bool(result.get("success", false)), "execute_action march succeeded")


func test_marching_menu_march_gated_by_adjacency() -> void:
	var army_id := _build_army_with_units(2)
	ArmyRepository.update_army(army_id, {"hex_q": 5, "hex_r": 5})
	# Adjacent target (5,5)+(1,0) = (6,5): March enabled.
	var adj := MarchingMenuScript.build_items_for_army(army_id, 6, 5)
	check(_item_enabled(adj, MarchingMenuScript.ACTION_MARCH), "March enabled for adjacent hex")
	# Non-adjacent target (4 hexes away): March present but disabled with a tooltip.
	var far := MarchingMenuScript.build_items_for_army(army_id, 9, 9)
	check(_item_present(far, MarchingMenuScript.ACTION_MARCH), "March present for far hex")
	check(not _item_enabled(far, MarchingMenuScript.ACTION_MARCH), "March disabled for non-adjacent hex")
	check(not _item_tooltip(far, MarchingMenuScript.ACTION_MARCH).is_empty(),
		"disabled March explains why")


func test_marching_menu_extraction_eligibility() -> void:
	# Phase B live: extraction is gated on real eligibility (friendly territory + cooldown
	# + ceiling), not a flag. These test hexes are unclaimed, so Requisition is disabled
	# (nothing to requisition) while Loot is always available.
	var army_id := _build_army_with_units(2)
	ArmyRepository.update_army(army_id, {"hex_q": 5, "hex_r": 5})
	var items := MarchingMenuScript.build_items_for_army(army_id, 6, 5)
	check(not _item_enabled(items, MarchingMenuScript.ACTION_MARCH_REQUISITION),
		"March+Requisition disabled in unclaimed territory")
	check(_item_enabled(items, MarchingMenuScript.ACTION_MARCH_LOOT),
		"March+Loot always available")
	check(not _item_enabled(items, MarchingMenuScript.ACTION_REQUISITION_HERE),
		"Requisition-here disabled in unclaimed territory")
	check(_item_enabled(items, MarchingMenuScript.ACTION_LOOT_HERE),
		"Loot-here always available")
	check(not _item_tooltip(items, MarchingMenuScript.ACTION_MARCH_REQUISITION).is_empty(),
		"disabled Requisition explains why")


func test_marching_menu_extraction_dispatch() -> void:
	var army_id := _build_army_with_units(2)
	var scheduler := EventScheduler.new()
	# March+Requisition now dispatches a travel leg (Phase B live).
	var march := MarchingMenuScript.execute_action(
		MarchingMenuScript.ACTION_MARCH_REQUISITION, army_id, 6, 5, 0, scheduler)
	check(bool(march.get("success", false)), "March+Requisition dispatches a travel leg")
	# Encamped Requisition-here needs the session's ExtractionScheduler (not passed here).
	var here := MarchingMenuScript.execute_action(
		MarchingMenuScript.ACTION_REQUISITION_HERE, army_id, 6, 5, 0, scheduler)
	check(not bool(here.get("success", true)), "Requisition-here without an extraction scheduler is rejected")
	check(String(here.get("error", "")) == "no_extraction_scheduler", "error is no_extraction_scheduler")


func test_marching_menu_marching_has_disband_and_encamp() -> void:
	var army_id := _build_army_with_units(2)
	ArmyRepository.update_army(army_id, {"state": "marching"})
	var items := MarchingMenuScript.build_items_for_army(army_id, 6, 5)
	var actions: Array = []
	for item in items:
		actions.append(str(item.get("action", "")))
	check(actions.has(MarchingMenuScript.ACTION_ENCAMP), "marching army can Encamp")
	check(actions.has(MarchingMenuScript.ACTION_DISBAND), "marching army can Disband")
	check(not actions.has(MarchingMenuScript.ACTION_MARCH), "marching army has no March")


func test_marching_menu_options_shape_has_cancel() -> void:
	var army_id := _build_army_with_units(2)
	ArmyRepository.update_army(army_id, {"hex_q": 5, "hex_r": 5})
	var options := MarchingMenuScript.build_menu_options(army_id, 6, 5)
	check(options.size() >= 2, "menu options produced")
	var last: Dictionary = options[options.size() - 1]
	check(String((last.get("action_data", {}) as Dictionary).get("action_type", "")) == "cancel",
		"last option is Cancel")
	var first: Dictionary = options[0]
	check(String((first.get("action_data", {}) as Dictionary).get("action_type", "")) == "army_order",
		"army options use army_order action_type")
	check(String(first.get("category", "")) == MarchingMenuScript.MENU_CATEGORY,
		"army options carry the army category")


func _item_present(items: Array, action: String) -> bool:
	for item in items:
		if str(item.get("action", "")) == action:
			return true
	return false


func _item_enabled(items: Array, action: String) -> bool:
	for item in items:
		if str(item.get("action", "")) == action:
			return bool(item.get("enabled", false))
	return false


func _item_tooltip(items: Array, action: String) -> String:
	for item in items:
		if str(item.get("action", "")) == action:
			return str(item.get("tooltip", ""))
	return ""


func test_commander_departure_check_returns_active_armies() -> void:
	# Use a fresh ruler to avoid pollution from other tests in this suite.
	var fresh_ruler := _make_character("DepartureRuler")
	var army_id: String = ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": "Departure Host",
		"political_owner_id": fresh_ruler, "command_character_id": fresh_ruler,
		"state": "encamped",
	})
	var blocking := CommanderDepartureCheck.blocking_armies([fresh_ruler])
	check(blocking.size() == 1, "1 blocking army for fresh ruler; got %d" % blocking.size())
	check(String(blocking[0].get("army_id", "")) == army_id, "correct army returned")


func test_commander_departure_check_excludes_disbanded() -> void:
	var fresh_id := _make_character("DepartTest")
	var army_id: String = ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": "Disbanded Host",
		"political_owner_id": fresh_id, "command_character_id": fresh_id,
		"state": "disbanded",
	})
	var blocking := CommanderDepartureCheck.blocking_armies([fresh_id])
	check(blocking.is_empty(), "disbanded army excluded; got %s" % blocking)
	var _ignored := army_id
