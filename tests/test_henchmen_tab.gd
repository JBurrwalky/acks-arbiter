extends "res://tests/test_suite_base.gd"

## H.1 — Henchmen tab smoke tests.
##
## Covers the UI integration concerns the new tab introduces:
##   - Empty-state surfaces when both active and departed lists are empty
##   - Status header reports humanoid / animal counts + monthly wages
##   - Per-tab substate (active sub-tab) persists via NotebookState round-trip
##   - Loyalty band derivation matches HenchmanTables.loyalty_result with
##     the grudging/fanatic flag overrides
##   - CampaignRepository.list_party_henchmen / list_departed_henchmen short-
##     circuit on empty inputs without DB queries
##
## Tests instantiate the tab page directly without the full notebook tree.
## The page subscribes to several EventBus signals on _build_content; tests
## free the page after each scenario to drop those connections cleanly.


const HenchmenTabPageScript := preload("res://scenes/ui/notebook/tab_pages/henchmen_tab_page.gd")


func run_all_tests() -> void:
	test_repository_short_circuit_on_empty_party()
	test_repository_short_circuit_on_empty_campaign()
	test_empty_state_when_no_henchmen()
	test_status_header_zero_henchmen_text()
	test_status_header_summary_with_mock_rows()
	test_loyalty_band_label_for_each_morale_band()
	test_loyalty_band_grudging_override()
	test_loyalty_band_fanatic_override()
	test_substate_round_trip_active_subtab()
	test_subtab_press_persists()
	if not has_failures():
		print("HenchmenTab: all tests passed.")


# ---------------------------------------------------------------------------
# Repository helpers
# ---------------------------------------------------------------------------

func test_repository_short_circuit_on_empty_party() -> void:
	# Empty party_id should bypass the DB query and return [] without error.
	var rows: Array = CampaignRepository.list_party_henchmen("")
	check(rows.is_empty(),
		"list_party_henchmen('') should return empty array (got %d rows)" % rows.size())


func test_repository_short_circuit_on_empty_campaign() -> void:
	var rows: Array = CampaignRepository.list_departed_henchmen("")
	check(rows.is_empty(),
		"list_departed_henchmen('') should return empty array (got %d rows)" % rows.size())


# ---------------------------------------------------------------------------
# Empty-state
# ---------------------------------------------------------------------------

func test_empty_state_when_no_henchmen() -> void:
	# With no active campaign / party, both queries return empty and the page
	# should surface an EmptyStatePage child.
	GameState.active_party_id = ""
	GameState.campaign_id = ""
	var page = HenchmenTabPageScript.new()
	add_child(page)
	var empty_pages: Array = []
	_collect_empty_state_pages(page, empty_pages)
	check(empty_pages.size() >= 1,
		"Empty state should surface when there are zero henchmen")
	page.queue_free()


# ---------------------------------------------------------------------------
# Status header
# ---------------------------------------------------------------------------

func test_status_header_zero_henchmen_text() -> void:
	GameState.active_party_id = ""
	GameState.campaign_id = ""
	var page = HenchmenTabPageScript.new()
	add_child(page)
	var label: Label = page._status_summary_label
	check(label != null, "Status summary label should exist")
	if label != null:
		check(label.text.contains("No henchmen"),
			"Empty roster should set summary 'No henchmen' (got '%s')" % label.text)
	page.queue_free()


func test_status_header_summary_with_mock_rows() -> void:
	# Drive _refresh_status_header directly with synthetic rows so we don't
	# need a populated DB.
	var page = HenchmenTabPageScript.new()
	add_child(page)
	# wage_cp_per_month is cp; 25 gp = 2500 cp for a typical L1 fighter henchman.
	# Sum = 2500 + 2500 + 5000 = 10000 cp = 100 gp displayed as "100gp" via
	# Currency.format_cost.
	var rows: Array = [
		{"character_type": "henchman", "class_id": "fighter", "wage_cp_per_month": 2500},
		{"character_type": "henchman", "class_id": "thief",   "wage_cp_per_month": 2500},
		{"character_type": "henchman", "class_id": "",        "wage_cp_per_month": 5000},
	]
	page._refresh_status_header(rows)
	var text: String = page._status_summary_label.text
	check(text.contains("3 henchmen"),
		"Summary should report 3 henchmen total (got '%s')" % text)
	check(text.contains("2 humanoid"),
		"Summary should report 2 humanoid (got '%s')" % text)
	check(text.contains("1 animal"),
		"Summary should report 1 animal (got '%s')" % text)
	check(text.contains("100gp"),
		"Summary should report 100gp monthly wages via Currency.format_cost (got '%s')" % text)
	page.queue_free()


# ---------------------------------------------------------------------------
# Loyalty band derivation
# ---------------------------------------------------------------------------

func test_loyalty_band_label_for_each_morale_band() -> void:
	var page = HenchmenTabPageScript.new()
	add_child(page)
	# Per acore_equipment.xml §loyalty_results table:
	#   ≤ 2  Hostility, 3-5 Resignation, 6-8 Grudging, 9-11 Loyalty, 12+ Fanatic
	check(page._loyalty_label(-3, false, false).text == "Hostility",
		"morale -3 should render Hostility")
	check(page._loyalty_label(4, false, false).text == "Resignation",
		"morale 4 should render Resignation")
	check(page._loyalty_label(7, false, false).text == "Grudging Loyalty",
		"morale 7 should render Grudging Loyalty")
	check(page._loyalty_label(10, false, false).text == "Loyalty",
		"morale 10 should render Loyalty")
	check(page._loyalty_label(15, false, false).text == "Fanatic Loyalty",
		"morale 15 should render Fanatic Loyalty")
	page.queue_free()


func test_loyalty_band_grudging_override() -> void:
	var page = HenchmenTabPageScript.new()
	add_child(page)
	# is_grudging flag forces Grudging Loyalty unless score is already in
	# Hostility/Resignation territory (worse states win).
	check(page._loyalty_label(10, true, false).text == "Grudging Loyalty",
		"is_grudging=true should override Loyalty band downward to Grudging")
	check(page._loyalty_label(-1, true, false).text == "Hostility",
		"is_grudging=true must not upgrade Hostility")
	page.queue_free()


func test_loyalty_band_fanatic_override() -> void:
	var page = HenchmenTabPageScript.new()
	add_child(page)
	check(page._loyalty_label(5, false, true).text == "Fanatic Loyalty",
		"is_fanatic=true should override band upward to Fanatic")
	page.queue_free()


# ---------------------------------------------------------------------------
# Substate persistence
# ---------------------------------------------------------------------------

func test_substate_round_trip_active_subtab() -> void:
	# Direct round-trip via NotebookState — does the dict persist + restore?
	var test_party := "party_h1_substate"
	NotebookState.set_substate_for_tab(test_party, "henchmen", {
		"active_subtab": "departure_log",
	})
	var got: Dictionary = NotebookState.get_substate_for_tab(test_party, "henchmen")
	check(got.get("active_subtab", "") == "departure_log",
		"Henchmen substate active_subtab should round-trip (got '%s')" % got.get("active_subtab", ""))


func test_subtab_press_persists() -> void:
	# Pressing the Departure Log sub-tab should persist active_subtab via
	# NotebookState. Use a synthetic active party id.
	var test_party := "party_h1_press"
	GameState.active_party_id = test_party
	GameState.campaign_id = ""
	var page = HenchmenTabPageScript.new()
	add_child(page)
	page._on_subtab_pressed("departure_log")
	var got: Dictionary = NotebookState.get_substate_for_tab(test_party, "henchmen")
	check(got.get("active_subtab", "") == "departure_log",
		"After pressing Departure Log sub-tab, substate should record it")
	GameState.active_party_id = ""
	page.queue_free()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _collect_empty_state_pages(node: Node, out: Array) -> void:
	if node == null:
		return
	if node.get_script() != null and node is MarginContainer:
		# EmptyStatePage extends MarginContainer; check by class_name when
		# possible. The simpler signal: it has a `_heading_label` field set.
		if "_heading_label" in node and node._heading_label != null:
			out.append(node)
	for child in node.get_children():
		_collect_empty_state_pages(child, out)
