extends "res://tests/test_suite_base.gd"

## Tests for RealmTitleResolver per acore_axioms_strongholds_and_domains.xml
## §titles_of_nobility L273-285 + §muster_delay L373-382.


func run_all_tests() -> void:
	test_baron_default_for_small_realm()
	test_marquis_band_thresholds()
	test_count_band_thresholds()
	test_duke_band_thresholds()
	test_prince_band_thresholds()
	test_king_band_thresholds()
	test_emperor_band_thresholds()
	test_personal_min_gates_higher_titles()
	test_muster_period_per_title()
	if not has_failures():
		print("RealmTitleResolver: all tests passed.")


func test_baron_default_for_small_realm() -> void:
	# 160 personal, 1 domain, 160 realm — exactly Baron threshold.
	check(RealmTitleResolver.resolve_title(160, 1, 160) == "Baron",
		"160/1/160 → Baron")
	# Below thresholds — still Baron (the schema default).
	check(RealmTitleResolver.resolve_title(50, 1, 50) == "Baron",
		"sub-threshold → Baron default")


func test_marquis_band_thresholds() -> void:
	# 320/5/960 = Marquis floor.
	check(RealmTitleResolver.resolve_title(320, 5, 960) == "Marquis",
		"320/5/960 → Marquis")
	check(RealmTitleResolver.resolve_title(500, 6, 1100) == "Marquis",
		"mid-band Marquis")


func test_count_band_thresholds() -> void:
	check(RealmTitleResolver.resolve_title(780, 21, 4600) == "Count",
		"780/21/4600 → Count")


func test_duke_band_thresholds() -> void:
	check(RealmTitleResolver.resolve_title(1500, 85, 20000) == "Duke",
		"1500/85/20000 → Duke")


func test_prince_band_thresholds() -> void:
	check(RealmTitleResolver.resolve_title(7500, 341, 87000) == "Prince",
		"7500/341/87000 → Prince")


func test_king_band_thresholds() -> void:
	check(RealmTitleResolver.resolve_title(12500, 1365, 364000) == "King",
		"12500/1365/364000 → King")


func test_emperor_band_thresholds() -> void:
	check(RealmTitleResolver.resolve_title(12500, 5461, 2_000_000) == "Emperor",
		"12500/5461/2M → Emperor")


func test_personal_min_gates_higher_titles() -> void:
	# A small personal domain cannot be Emperor even if domains_ruled and
	# realm_families are huge: personal_min is 12500, so a 5000-family
	# personal domain caps at Duke.
	var t: String = RealmTitleResolver.resolve_title(5000, 10000, 5_000_000)
	check(t == "Duke", "5000-personal cannot exceed Duke; got %s" % t)
	# Personal=320 falls into Marquis bracket regardless of realm size.
	var t2: String = RealmTitleResolver.resolve_title(320, 10000, 5_000_000)
	check(t2 == "Marquis", "320-personal caps at Marquis; got %s" % t2)


func test_muster_period_per_title() -> void:
	check(RealmTitleResolver.muster_period("Baron") == "Week", "Baron → Week")
	check(RealmTitleResolver.muster_period("Marquis") == "Week", "Marquis → Week")
	check(RealmTitleResolver.muster_period("Count") == "Week", "Count → Week")
	check(RealmTitleResolver.muster_period("Duke") == "Month", "Duke → Month")
	check(RealmTitleResolver.muster_period("Prince") == "Month", "Prince → Month")
	check(RealmTitleResolver.muster_period("King") == "Season", "King → Season")
	check(RealmTitleResolver.muster_period("Emperor") == "Season", "Emperor → Season")
