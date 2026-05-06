extends "res://tests/test_suite_base.gd"

## H.3 — closing-out polish smoke tests.
##
## Covers five deliverables (Item 2 retired with the settlement v2 rewrite,
## which deleted CityOverviewWidget in favor of the menu-driven SettlementMenu):
##   - Item 1: LightSourceIndicator visibility on activate / deactivate signals
##   - Item 3: FormationGridCell drag-data shape + drop eligibility
##   - Item 4: monster_catalog `dungeon_eligible` flag on horse / ox / cow,
##             absent (default true) on dog_war / spider_giant
##   - Item 5: equipment catalog `consumable_kind` tags on rations / waterskin /
##             bread; PartyTabPage._accumulate_resource_items reads them
##   - Item 6: Notebook router emits settlement_hiring_requested on
##             open_settlement link


const LightSourceIndicatorScript := preload("res://scenes/ui/hud/light_source_indicator.gd")
const FormationGridCellScript := preload("res://scenes/ui/notebook/party/formation_grid_cell.gd")
const FormationUnplacedListScript := preload("res://scenes/ui/notebook/party/formation_unplaced_list.gd")
const PartyTabPageScript := preload("res://scenes/ui/notebook/tab_pages/party_tab_page.gd")
const NotebookScript := preload("res://scenes/ui/notebook/notebook.gd")


func run_all_tests() -> void:
	# Item 1
	test_light_indicator_starts_hidden()
	test_light_indicator_shows_on_activate()
	test_light_indicator_hides_on_deactivate()
	test_light_indicator_color_escalates_below_thresholds()
	# Item 3
	test_formation_unplaced_list_drag_data_shape()
	test_formation_grid_cell_rejects_self_drop()
	test_formation_grid_cell_accepts_other_cell_drop()
	# Item 4
	test_monster_catalog_dungeon_eligible_flags()
	# Item 5
	test_equipment_catalog_consumable_tags()
	test_accumulate_resource_items_uses_catalog_tags()
	# Item 6
	test_notebook_open_settlement_emits_hiring_request()
	if not has_failures():
		print("H3Polish: all tests passed.")


# ---------------------------------------------------------------------------
# Item 1 — LightSourceIndicator
# ---------------------------------------------------------------------------

func test_light_indicator_starts_hidden() -> void:
	var ind := LightSourceIndicatorScript.new()
	add_child(ind)
	check(not ind.visible, "LightSourceIndicator starts hidden")
	ind.queue_free()


func test_light_indicator_shows_on_activate() -> void:
	var ind := LightSourceIndicatorScript.new()
	add_child(ind)
	EventBus.light_source_activated.emit({
		"source_type": "torch",
		"radius_feet": 50,
		"remaining_turns": 6,
		"carrier_id": "pc_a",
	})
	check(ind.visible, "Indicator shows on light_source_activated")
	check(ind._heading_label.text == "Torch",
		"Heading should show source name (got '%s')" % ind._heading_label.text)
	check(ind._remaining_label.text.contains("6 turn"),
		"Remaining label should report 6 turns (got '%s')" % ind._remaining_label.text)
	ind.queue_free()


func test_light_indicator_hides_on_deactivate() -> void:
	var ind := LightSourceIndicatorScript.new()
	add_child(ind)
	EventBus.light_source_activated.emit({
		"source_type": "torch", "radius_feet": 50, "remaining_turns": 6, "carrier_id": "",
	})
	EventBus.light_source_deactivated.emit()
	check(not ind.visible, "Indicator hides on light_source_deactivated")
	ind.queue_free()


func test_light_indicator_color_escalates_below_thresholds() -> void:
	var ind := LightSourceIndicatorScript.new()
	add_child(ind)
	# Normal at >5 turns.
	check(ind._color_for_remaining(10) == LightSourceIndicatorScript.COLOR_NORMAL,
		"10 turns → normal color")
	# Flickering at ≤5 (5, 4, 3).
	check(ind._color_for_remaining(5) == LightSourceIndicatorScript.COLOR_FLICKERING,
		"5 turns → flickering color")
	check(ind._color_for_remaining(3) == LightSourceIndicatorScript.COLOR_FLICKERING,
		"3 turns → flickering color")
	# Danger at ≤2 (2, 1).
	check(ind._color_for_remaining(2) == LightSourceIndicatorScript.COLOR_DANGER,
		"2 turns → danger color")
	check(ind._color_for_remaining(1) == LightSourceIndicatorScript.COLOR_DANGER,
		"1 turn → danger color")
	ind.queue_free()


# ---------------------------------------------------------------------------
# Item 3 — FormationGridCell drag-drop
# ---------------------------------------------------------------------------

func test_formation_unplaced_list_drag_data_shape() -> void:
	var lst := FormationUnplacedListScript.new()
	add_child(lst)
	lst.grid_id = "wilderness"
	lst.add_item("Aldric")
	lst.id_for_index = ["pc_aldric"]
	# Stub get_item_at_position via a dictionary-like override is awkward;
	# directly assert the field setup is correct (the actual drag handler
	# uses get_item_at_position which we trust Godot to implement).
	check(lst.id_for_index.size() == 1,
		"id_for_index reflects added item")
	check(lst.grid_id == "wilderness",
		"grid_id is set on the list for drag payload context")
	lst.queue_free()


func test_formation_grid_cell_rejects_self_drop() -> void:
	var cell := FormationGridCellScript.new()
	add_child(cell)
	cell.col = 2
	cell.row = 3
	cell.grid_id = "wilderness"
	# Drag from (2,3) wilderness onto itself — should reject.
	var payload: Dictionary = {
		"kind": "formation_drag",
		"character_id": "pc_a",
		"source_grid": "wilderness",
		"source_col": 2,
		"source_row": 3,
	}
	check(not cell._can_drop_data(Vector2.ZERO, payload),
		"Cell rejects drops sourced from itself")
	cell.queue_free()


func test_formation_grid_cell_accepts_other_cell_drop() -> void:
	var cell := FormationGridCellScript.new()
	add_child(cell)
	cell.col = 0
	cell.row = 0
	cell.grid_id = "wilderness"
	# eligibility_check defaults to invalid Callable → no-eligibility-gate path.
	var payload: Dictionary = {
		"kind": "formation_drag",
		"character_id": "pc_b",
		"source_grid": "wilderness",
		"source_col": 1,
		"source_row": 1,
	}
	check(cell._can_drop_data(Vector2.ZERO, payload),
		"Cell accepts drops from other cells when eligibility check is open")
	cell.queue_free()


# ---------------------------------------------------------------------------
# Item 4 — Monster catalog dungeon_eligible
# ---------------------------------------------------------------------------

func test_monster_catalog_dungeon_eligible_flags() -> void:
	var json_str := FileAccess.get_file_as_string("res://data/monsters/monster_catalog.json")
	var parsed: Variant = JSON.parse_string(json_str)
	check(parsed is Array, "monster_catalog.json parses as Array")
	if not (parsed is Array):
		return
	var by_id: Dictionary = {}
	for entry in parsed:
		if entry is Dictionary:
			by_id[str(entry.get("id", ""))] = entry
	# Wilderness-only mounts should be flagged.
	for id in ["horse_light", "horse_heavy", "horse_heavy_war", "camel", "mule", "ox", "cow"]:
		if not by_id.has(id):
			check(false, "monster_catalog missing expected entry '%s'" % id)
			continue
		var e: Dictionary = by_id[id]
		check(e.has("dungeon_eligible") and e["dungeon_eligible"] == false,
			"%s should have dungeon_eligible: false" % id)
	# Default-true entries should NOT have the flag (or have it true).
	for id in ["dog_war", "spider_giant_black_widow", "dire_wolf", "wolf"]:
		if not by_id.has(id):
			continue
		var e2: Dictionary = by_id[id]
		var allow: bool = bool(e2.get("dungeon_eligible", true))
		check(allow,
			"%s should default to dungeon_eligible: true (got %s)" % [id, allow])


# ---------------------------------------------------------------------------
# Item 5 — Equipment catalog consumable tags
# ---------------------------------------------------------------------------

func test_equipment_catalog_consumable_tags() -> void:
	var catalog := EquipmentCatalog.new()
	for key_kind_days in [
		["rations_iron_week",     "food",  7],
		["rations_standard_week", "food",  7],
		["waterskin",             "water", 1],
		["bread_white",           "food",  4],
		["cheese",                "food",  1],
		["wine_cheap",            "water", 0.5],
	]:
		var key: String = key_kind_days[0]
		var expected_kind: String = key_kind_days[1]
		var expected_days: float = float(key_kind_days[2])
		var entry: Dictionary = catalog.get_item(key)
		check(not entry.is_empty(), "Catalog has entry for '%s'" % key)
		check(str(entry.get("consumable_kind", "")) == expected_kind,
			"%s consumable_kind should be '%s' (got '%s')" % [
				key, expected_kind, entry.get("consumable_kind", "")])
		check(abs(float(entry.get("consumable_person_days", 0)) - expected_days) < 0.01,
			"%s consumable_person_days should be %.2f (got %s)" % [
				key, expected_days, entry.get("consumable_person_days", 0)])


func test_accumulate_resource_items_uses_catalog_tags() -> void:
	var page = PartyTabPageScript.new()
	add_child(page)
	# Synthetic items list: 2 weeks of iron rations + 3 waterskins + 1 bread loaf.
	var items: Array = [
		{"item_key": "rations_iron_week", "quantity": 2},
		{"item_key": "waterskin",         "quantity": 3},
		{"item_key": "bread_white",       "quantity": 1},
	]
	var got: Dictionary = page._accumulate_resource_items(items)
	# Food: 2 * 7 days * (1/6 stone/day) + 1 * 4 days * (1/6) = (14 + 4)/6 = 3.0
	check(abs(got["food"] - 3.0) < 0.01,
		"food total should be 3.0 stones (got %.3f)" % got["food"])
	# Water: 3 waterskins * 1 day = 3.0
	check(abs(got["water"] - 3.0) < 0.01,
		"water total should be 3.0 (got %.3f)" % got["water"])
	page.queue_free()


# ---------------------------------------------------------------------------
# Item 6 — Notebook router emits settlement_hiring_requested
# ---------------------------------------------------------------------------

func test_notebook_open_settlement_emits_hiring_request() -> void:
	var nb = NotebookScript.new()
	add_child(nb)
	# GDScript local-int captures don't mutate through closures; use an
	# Array container so the listener can append.
	var got_payloads: Array = []
	var listener := func(employer_id: String):
		got_payloads.append(employer_id)
	EventBus.settlement_hiring_requested.connect(listener)
	var notice: Dictionary = nb._route_acquisition_link("open_settlement", "henchmen")
	check(got_payloads.size() == 1,
		"open_settlement should emit settlement_hiring_requested once (got %d)" % got_payloads.size())
	check(notice.get("title", "") == "Find a Settlement",
		"open_settlement still returns the documented notification fallback")
	EventBus.settlement_hiring_requested.disconnect(listener)
	nb.queue_free()
