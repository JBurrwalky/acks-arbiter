extends "res://tests/test_suite_base.gd"

## Stage 4 foundation: the data-driven sim config (SimConstants, §7.8) and the
## ACKS tier table (DomainTierTable, §12.1A). Smoke + boundary tests so the
## RAW-verified constants the history simulation will consume are proven to
## load and behave before the sim is built on them.

func run_all_tests() -> void:
	test_sim_constants_defaults()
	test_sim_constants_accessors()
	test_tier_table_boundaries()
	test_tier_table_accessors()
	print("SettingStage4FoundationTests: all tests passed (%d checks)" % test_count())


func test_sim_constants_defaults() -> void:
	var c := SimConstants.new()
	# Spot-check a few §7.8 values that the sim's behavior hinges on.
	check(c.tier_risk_mult == 1.35, "TIER_RISK_MULT should default 1.35")
	check(c.fade_rate == 0.985, "FADE_RATE should default 0.985")
	check(c.assimilation_step == 0.5, "ASSIMILATION_STEP should default 0.5")
	check(c.diffuse_rate == 0.02, "DIFFUSE_RATE should default 0.02")
	check(c.min_garrison_per_family == 2, "RAW 2gp/family floor")
	check(c.severity_band_rump == 0.50 and c.severity_band_shatter == 0.85,
		"severity bands should be 0.50 / 0.85")
	check(c.replay_cadence == 4, "REPLAY_CADENCE should be 4 ticks")


func test_sim_constants_accessors() -> void:
	var c := SimConstants.new()
	check(c.vassal_size_for_tier(DomainTierTable.PRINCIPALITY) == 3,
		"≤Principality VASSAL_SIZE should be 3")
	check(c.vassal_size_for_tier(DomainTierTable.KINGDOM) == 4, "Kingdom VASSAL_SIZE 4")
	check(c.vassal_size_for_tier(DomainTierTable.EMPIRE) == 6, "Empire VASSAL_SIZE 6")
	check(c.garrison_rate_for("civilized") == 2, "civilized garrison 2gp")
	check(c.garrison_rate_for("borderlands") == 3, "borderlands garrison 3gp")
	check(c.garrison_rate_for("wilderness") == 4, "wilderness garrison 4gp")
	check(c.cap_for("wilderness") == 2000, "wilderness 24-mi cap 2000")
	check(c.cap_for("civilized") == 12480, "civilized 24-mi cap 12480")


func test_tier_table_boundaries() -> void:
	# Overall-realm-families lower bounds (RAW titles_of_nobility, verified).
	check(DomainTierTable.tier_for_families(100) == DomainTierTable.BARONY,
		"below 160 should be Barony")
	check(DomainTierTable.tier_for_families(160) == DomainTierTable.BARONY, "160 = Barony")
	check(DomainTierTable.tier_for_families(959) == DomainTierTable.BARONY, "959 still Barony")
	check(DomainTierTable.tier_for_families(960) == DomainTierTable.MARCH, "960 = March")
	check(DomainTierTable.tier_for_families(4600) == DomainTierTable.COUNTY, "4600 = County")
	check(DomainTierTable.tier_for_families(20000) == DomainTierTable.DUCHY, "20000 = Duchy")
	check(DomainTierTable.tier_for_families(87000) == DomainTierTable.PRINCIPALITY, "87000 = Principality")
	check(DomainTierTable.tier_for_families(364000) == DomainTierTable.KINGDOM, "364000 = Kingdom")
	check(DomainTierTable.tier_for_families(2000000) == DomainTierTable.EMPIRE, "2M = Empire")
	check(DomainTierTable.tier_for_families(50000000) == DomainTierTable.EMPIRE, "above max = Empire")


func test_tier_table_accessors() -> void:
	check(DomainTierTable.title_for_tier(DomainTierTable.DUCHY) == "Duchy", "tier 3 = Duchy")
	check(DomainTierTable.title_for_tier(DomainTierTable.EMPIRE) == "Empire", "tier 6 = Empire")
	check(DomainTierTable.ruler_level_for_tier(DomainTierTable.DUCHY) == 9, "Duke is level 9")
	check(DomainTierTable.ruler_level_for_tier(DomainTierTable.EMPIRE) == 14, "Emperor is level 14")
	check(DomainTierTable.stronghold_value_for_tier(DomainTierTable.EMPIRE) == 720000,
		"Empire stronghold value 720K gp")
	check(DomainTierTable.stronghold_value_for_tier(DomainTierTable.BARONY) == 22500,
		"Barony stronghold value 22.5K gp")
