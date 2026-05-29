extends "res://tests/test_suite_base.gd"

## Phase 11A: verify the Departure Log sub-tab is wired into
## domain_tab_page's SUB_TABS registry as a non-placeholder entry and
## that its script reference resolves.
##
## This is a lightweight structural check — full UI instantiation is
## driven via the editor walkthrough listed in the Phase 11 plan.


const DOMAIN_TAB_PAGE_SCRIPT := preload("res://scenes/ui/notebook/tab_pages/domain_tab_page.gd")
const DEPARTURE_LOG_SUB_TAB_SCRIPT := preload("res://scenes/ui/notebook/domain/sub_tabs/departure_log_sub_tab.gd")


func run_all_tests() -> void:
	test_sub_tab_registered_as_real_not_placeholder()
	test_sub_tab_label_is_departure_log()
	test_sub_tab_script_instantiates()
	test_sub_tab_has_display_method()
	if not has_failures():
		print("DepartureLogSubTabVisibility: all tests passed.")


func test_sub_tab_registered_as_real_not_placeholder() -> void:
	var sub_tabs: Array = DOMAIN_TAB_PAGE_SCRIPT.SUB_TABS
	var entry: Dictionary = {}
	for e: Dictionary in sub_tabs:
		if String(e.get("id", "")) == "departure_log":
			entry = e
			break
	check(not entry.is_empty(), "departure_log entry exists in SUB_TABS")
	check(str(entry.get("script", "")) == "departure_log",
		"script kind is 'departure_log' (not 'placeholder'), got %s" % str(entry.get("script", "")))
	check(bool(entry.get("phase_2", false)),
		"phase_2=true (sub-tab is live, not deferred)")


func test_sub_tab_label_is_departure_log() -> void:
	var sub_tabs: Array = DOMAIN_TAB_PAGE_SCRIPT.SUB_TABS
	for e: Dictionary in sub_tabs:
		if String(e.get("id", "")) == "departure_log":
			check(String(e.get("label", "")) == "Departure Log",
				"label is 'Departure Log', got %s" % String(e.get("label", "")))
			return
	check(false, "departure_log entry not found in SUB_TABS")


func test_sub_tab_script_instantiates() -> void:
	var inst: Object = DEPARTURE_LOG_SUB_TAB_SCRIPT.new()
	check(inst != null, "sub-tab script instantiates")
	if inst is Node:
		(inst as Node).queue_free()


func test_sub_tab_has_display_method() -> void:
	var inst: Object = DEPARTURE_LOG_SUB_TAB_SCRIPT.new()
	check(inst.has_method("display"), "sub-tab exposes display(domain_data) per Phase 2 convention")
	if inst is Node:
		(inst as Node).queue_free()
