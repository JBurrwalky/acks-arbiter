extends "res://tests/test_suite_base.gd"

## Unit tests for ActivityCatalog (Domain Phase 3).
##
## Verifies the catalog loads data/activities/domain_category.json and exposes
## the expected lookups: get_definition, list_by_category, list_by_location_kind,
## get_remote_capable_ids.


func run_all_tests() -> void:
	test_catalog_loads_domain_category()
	test_get_definition_known_id()
	test_get_definition_unknown_id_returns_empty()
	test_list_by_category_domain()
	test_list_by_location_kind()
	test_remote_capable_ids_match_gdd_section_11_1()
	test_repress_population_present()
	if not has_failures():
		print("ActivityCatalog: all tests passed.")


func test_catalog_loads_domain_category() -> void:
	var c := ActivityCatalog.new()
	var ids := c.list_by_category("domain")
	check(ids.size() >= 16, "expected at least 16 domain activities, got %d" % ids.size())


func test_get_definition_known_id() -> void:
	var c := ActivityCatalog.new()
	var def := c.get_definition("administer_domain")
	check(not def.is_empty(), "administer_domain definition should exist")
	check(String(def.get("frequency", "")) == "ongoing",
		"administer_domain frequency should be ongoing")
	check(String(def.get("activity_level", "")) == "major",
		"administer_domain activity_level should be major")


func test_get_definition_unknown_id_returns_empty() -> void:
	var c := ActivityCatalog.new()
	var def := c.get_definition("nonexistent_activity_xyz")
	check(def.is_empty(), "unknown id should return empty dict")


func test_list_by_category_domain() -> void:
	var c := ActivityCatalog.new()
	var ids := c.list_by_category("domain")
	check(ids.has("administer_domain"), "administer_domain should be in domain category")
	check(ids.has("issue_decree"), "issue_decree should be in domain category")
	check(ids.has("repress_population"), "repress_population should be in domain category")


func test_list_by_location_kind() -> void:
	var c := ActivityCatalog.new()
	var anywhere := c.list_by_location_kind("anywhere")
	check(anywhere.has("administer_domain"),
		"administer_domain location_kind should be anywhere")
	check(anywhere.has("issue_decree"), "issue_decree location_kind should be anywhere")
	var settlement := c.list_by_location_kind("at_settlement")
	check(settlement.has("hire_mercenaries"),
		"hire_mercenaries location_kind should be at_settlement")


func test_remote_capable_ids_match_gdd_section_11_1() -> void:
	var c := ActivityCatalog.new()
	var ids := c.get_remote_capable_ids()
	check(ids.size() == 8, "expected 8 remote-capable ids per gdd-domain-tab.md §11.1, got %d" % ids.size())
	check(ids.has("administer_domain"), "administer_domain remote-capable")
	check(ids.has("issue_decree"), "issue_decree remote-capable")
	check(ids.has("manage_henchmen"), "manage_henchmen remote-capable")
	check(ids.has("conscript_troops"), "conscript_troops remote-capable")
	check(ids.has("levy_militia"), "levy_militia remote-capable")
	check(ids.has("solicit_mercenaries"), "solicit_mercenaries remote-capable")
	check(ids.has("call_to_arms"), "call_to_arms remote-capable")
	check(ids.has("oversee_investment"), "oversee_investment remote-capable")


func test_repress_population_present() -> void:
	var c := ActivityCatalog.new()
	var def := c.get_definition("repress_population")
	check(not def.is_empty(), "repress_population [RAW PATCH] activity should be present")
	check(String(def.get("frequency", "")) == "ongoing",
		"repress_population frequency should be ongoing")
