extends "res://tests/test_suite_base.gd"

## Unit tests for SpecialistCatalog (Wilderness closure Phase 6).
##
## SACRED tests against `le_wilderness_lair_rules.xml §hirelings`:
##   * Pathfinder and Land Surveyor both 25 gp/month.
##   * Both kinds defined.
## PROJECT-DESIGNED tests:
##   * Bonus values per resolver kind.
##   * Unknown-kind / unknown-resolver-kind return 0 / "" gracefully.


func run_all_tests() -> void:
	test_list_kinds_returns_pathfinder_and_land_surveyor()
	test_pathfinder_wage_25gp()
	test_land_surveyor_wage_25gp()
	test_pathfinder_bonuses()
	test_land_surveyor_bonuses()
	test_unknown_kind_returns_safe_defaults()
	test_get_definition_returns_copy()
	if not has_failures():
		print("SpecialistCatalog: all tests passed.")


func test_list_kinds_returns_pathfinder_and_land_surveyor() -> void:
	# v2 dual-path (gdd-specialists.md §4, 2026-06-11): scouts + sage + alchemist.
	var kinds := SpecialistCatalog.list_kinds()
	check(kinds.size() == 4, "v2 has 4 specialist kinds; got %d" % kinds.size())
	check("pathfinder" in kinds, "pathfinder kind present")
	check("land_surveyor" in kinds, "land_surveyor kind present")
	check("sage" in kinds, "sage kind present")
	check("alchemist" in kinds, "alchemist kind present")


func test_pathfinder_wage_25gp() -> void:
	# RAW le_wilderness_lair_rules.xml: <wage>25gp/month</wage> = 2500 cp/month.
	check(SpecialistCatalog.monthly_wage_cp("pathfinder") == 2500,
		"pathfinder wage = 2500 cp/month (= 25 gp)")


func test_land_surveyor_wage_25gp() -> void:
	check(SpecialistCatalog.monthly_wage_cp("land_surveyor") == 2500,
		"land_surveyor wage = 2500 cp/month (= 25 gp)")


func test_pathfinder_bonuses() -> void:
	# Pathfinder helps lair_search (active + passive) and tracking — not surveying.
	check(SpecialistCatalog.bonus_for_resolver("pathfinder",
		SpecialistCatalog.KIND_LAIR_SEARCH) == 4,
		"pathfinder → +4 lair_search")
	check(SpecialistCatalog.bonus_for_resolver("pathfinder",
		SpecialistCatalog.KIND_LAIR_SEARCH_PASSIVE) == 4,
		"pathfinder → +4 passive lair spot")
	check(SpecialistCatalog.bonus_for_resolver("pathfinder",
		SpecialistCatalog.KIND_TRACKING) == 4,
		"pathfinder → +4 tracking")
	check(SpecialistCatalog.bonus_for_resolver("pathfinder",
		SpecialistCatalog.KIND_SURVEYING) == 0,
		"pathfinder does NOT help surveying")


func test_land_surveyor_bonuses() -> void:
	# Land Surveyor helps surveying — not lair_search or tracking.
	check(SpecialistCatalog.bonus_for_resolver("land_surveyor",
		SpecialistCatalog.KIND_SURVEYING) == 4,
		"land_surveyor → +4 surveying")
	check(SpecialistCatalog.bonus_for_resolver("land_surveyor",
		SpecialistCatalog.KIND_LAIR_SEARCH) == 0,
		"land_surveyor does NOT help lair_search")
	check(SpecialistCatalog.bonus_for_resolver("land_surveyor",
		SpecialistCatalog.KIND_TRACKING) == 0,
		"land_surveyor does NOT help tracking")


func test_unknown_kind_returns_safe_defaults() -> void:
	# "alchemist" became a real kind in v2 (dual-path) — probe with a kind
	# that stays unknown.
	check(not SpecialistCatalog.is_known_kind("astrologer"),
		"astrologer is not a defined specialist kind")
	check(SpecialistCatalog.monthly_wage_cp("astrologer") == 0,
		"unknown kind wage = 0")
	check(SpecialistCatalog.bonus_for_resolver("astrologer",
		SpecialistCatalog.KIND_LAIR_SEARCH) == 0,
		"unknown kind bonus = 0")


func test_get_definition_returns_copy() -> void:
	# Ensure callers cannot mutate the catalog by editing the returned Dict.
	var def := SpecialistCatalog.get_definition("pathfinder")
	check(not def.is_empty(), "pathfinder def returned")
	def["monthly_wage_cp"] = 9999
	check(SpecialistCatalog.monthly_wage_cp("pathfinder") == 2500,
		"catalog wage unchanged after caller mutation")
