extends "res://tests/test_suite_base.gd"

## Unit tests for SettlementEconomyInputs + schema-side coverage for the §1
## settlement-entrances column additions per Prereq.2a (migration 097).
##
## Per generation/gdd-settlement-economy.md §1.8 (schema/aggregation) and §3.10
## (input resolvers).

var _campaign_id: String = ""
var _map_id: String = ""
var _suffix: int = 0


func run_all_tests() -> void:
	_setup()
	# §1 schema-side + aggregation tests
	test_settlement_entrances_has_new_columns()
	test_domains_no_longer_has_urban_families()
	test_data_move_settlement_urban_families_backfilled()
	test_settlement_without_parent_domain_defaults_to_zero()
	test_age_bucket_boundary_cases()
	test_set_domain_urban_families_existing_settlement()
	test_set_domain_urban_families_creates_placeholder()
	test_get_domain_aggregates_urban_families()
	test_list_campaign_domains_aggregates_urban_families()

	# §3 input-resolver tests
	test_climate_columns_single_column_cases()
	test_climate_columns_composite_clear_default()
	test_climate_columns_narrowing_subtypes()
	test_climate_columns_swamp_composite()
	test_climate_columns_mountain_subtype_inheritance()
	test_climate_override_replaces_composite()
	test_resolve_water_sources_ocean_adjacency()
	test_resolve_water_sources_swamp_implies_lake_shore()
	test_resolve_water_sources_river_overlay()
	test_resolve_water_sources_multi_source()
	test_elevation_bucket()
	test_domain_land_revenue_averaging()
	test_domain_land_revenue_no_parent_domain()
	test_resolve_all_aggregator()

	if not has_failures():
		print("SettlementEconomyInputs: all %d tests passed." % test_count())


func _setup() -> void:
	_campaign_id = CampaignRepository.create_campaign("SettlementEconomyInputsTests", "World")
	_map_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO hex_maps (id, campaign_id, name, scale) VALUES (?, ?, ?, 'regional_6mi')",
		[_map_id, _campaign_id, "TestMap"]
	)


func _next_id() -> String:
	_suffix += 1
	return "sei_%d_%d" % [Time.get_ticks_msec(), _suffix]


func _make_settlement(args: Dictionary) -> String:
	## args may contain: hex_q, hex_r, age_years, dominant_race, urban_families,
	## climate_override, parent_domain_id. Defaults match column defaults.
	var id: String = _next_id()
	var hex_q: int = int(args.get("hex_q", 0))
	var hex_r: int = int(args.get("hex_r", 0))
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_entrances
			(id, campaign_id, map_id, hex_q, hex_r, name,
			 age_years, dominant_race, urban_families, climate_override, parent_domain_id)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		id, _campaign_id, _map_id, hex_q, hex_r,
		str(args.get("name", "TestSettlement")),
		int(args.get("age_years", 500)),
		str(args.get("dominant_race", "human")),
		int(args.get("urban_families", 0)),
		str(args.get("climate_override", "")),
		args.get("parent_domain_id", null),
	])
	return id


func _make_hex(q: int, r: int, biome: String, biome_subtype: String,
		elevation: String = "flat", water: String = "") -> void:
	CampaignRepository.db.query_with_bindings("""
		INSERT OR REPLACE INTO hex_cells
			(map_id, q, r, biome, biome_subtype, elevation, water)
		VALUES (?, ?, ?, ?, ?, ?, ?)
	""", [_map_id, q, r, biome, biome_subtype, elevation, water])


func _add_river_overlay(q: int, r: int) -> void:
	CampaignRepository.db.query_with_bindings("""
		INSERT OR REPLACE INTO hex_overlays (map_id, q, r, overlay_type, edges)
		VALUES (?, ?, ?, 'river', '[]')
	""", [_map_id, q, r])


# ---------------------------------------------------------------------------
# §1 schema + aggregation tests
# ---------------------------------------------------------------------------

func test_settlement_entrances_has_new_columns() -> void:
	CampaignRepository.db.query("PRAGMA table_info(settlement_entrances)")
	var columns: Dictionary = {}
	for row in CampaignRepository.db.query_result:
		columns[str((row as Dictionary).get("name", ""))] = row
	check(columns.has("age_years"), "settlement_entrances should have age_years column")
	check(columns.has("dominant_race"), "settlement_entrances should have dominant_race column")
	check(columns.has("urban_families"), "settlement_entrances should have urban_families column")
	check(columns.has("climate_override"), "settlement_entrances should have climate_override column")
	check(columns.has("economy_inputs_changed_day"),
		"settlement_entrances should have economy_inputs_changed_day column")
	check(columns.has("customs_duty_rate_pct"),
		"settlement_entrances should have customs_duty_rate_pct column")


func test_domains_no_longer_has_urban_families() -> void:
	CampaignRepository.db.query("PRAGMA table_info(domains)")
	for row in CampaignRepository.db.query_result:
		check(str((row as Dictionary).get("name", "")) != "urban_families",
			"domains.urban_families should be dropped (post-097)")


func test_data_move_settlement_urban_families_backfilled() -> void:
	# The data-move runs at migration time on pre-existing rows. For the
	# test, we verify the migration-equivalent behavior via the
	# CampaignRepository.set_domain_urban_families compat path.
	var domain_id: String = CampaignRepository.create_domain({
		"campaign_id": _campaign_id, "name": "DataMoveDomain",
		"location_map_id": _map_id, "location_hex_q": 0, "location_hex_r": 0,
	})
	# Create a settlement with parent_domain_id pointing at the new domain.
	var settlement_id: String = _make_settlement({
		"hex_q": 10, "hex_r": 0, "parent_domain_id": domain_id,
	})
	# Write 1500 via the canonical compat path.
	check(CampaignRepository.set_domain_urban_families(domain_id, 1500),
		"set_domain_urban_families should succeed")
	# Read back: the settlement's urban_families is now 1500.
	CampaignRepository.db.query_with_bindings(
		"SELECT urban_families FROM settlement_entrances WHERE id = ?",
		[settlement_id]
	)
	check(int(CampaignRepository.db.query_result[0].get("urban_families", 0)) == 1500,
		"settlement_entrances.urban_families should equal 1500 after set")


func test_settlement_without_parent_domain_defaults_to_zero() -> void:
	var settlement_id: String = _make_settlement({"hex_q": 20, "hex_r": 0})
	CampaignRepository.db.query_with_bindings(
		"SELECT urban_families FROM settlement_entrances WHERE id = ?",
		[settlement_id]
	)
	check(int(CampaignRepository.db.query_result[0].get("urban_families", -1)) == 0,
		"settlement without parent_domain_id should default urban_families = 0")


func test_age_bucket_boundary_cases() -> void:
	# Per §1.2 inclusive boundaries.
	check(SettlementEconomyInputs.age_bucket_for(0) == "0_20_years", "age=0 → 0_20_years")
	check(SettlementEconomyInputs.age_bucket_for(20) == "0_20_years", "age=20 → 0_20_years")
	check(SettlementEconomyInputs.age_bucket_for(21) == "21_100_years", "age=21 → 21_100_years")
	check(SettlementEconomyInputs.age_bucket_for(100) == "21_100_years", "age=100 → 21_100_years")
	check(SettlementEconomyInputs.age_bucket_for(101) == "101_1000_years", "age=101 → 101_1000_years")
	check(SettlementEconomyInputs.age_bucket_for(500) == "101_1000_years", "age=500 → 101_1000_years (default)")
	check(SettlementEconomyInputs.age_bucket_for(1000) == "101_1000_years", "age=1000 → 101_1000_years")
	check(SettlementEconomyInputs.age_bucket_for(1001) == "1001_2000_years", "age=1001 → 1001_2000_years")
	check(SettlementEconomyInputs.age_bucket_for(2000) == "1001_2000_years", "age=2000 → 1001_2000_years")
	check(SettlementEconomyInputs.age_bucket_for(2001) == "2001_plus_years", "age=2001 → 2001_plus_years")
	check(SettlementEconomyInputs.age_bucket_for(50000) == "2001_plus_years", "age=50000 → 2001_plus_years")


func test_set_domain_urban_families_existing_settlement() -> void:
	# Setting on a domain whose settlement already exists should UPDATE that row.
	var domain_id: String = CampaignRepository.create_domain({
		"campaign_id": _campaign_id, "name": "ExistingSettlementDomain",
	})
	var settlement_id: String = _make_settlement({
		"hex_q": 30, "hex_r": 0, "parent_domain_id": domain_id, "urban_families": 100,
	})
	CampaignRepository.set_domain_urban_families(domain_id, 800)
	CampaignRepository.db.query_with_bindings(
		"SELECT urban_families FROM settlement_entrances WHERE id = ?",
		[settlement_id]
	)
	check(int(CampaignRepository.db.query_result[0].get("urban_families", 0)) == 800,
		"set_domain_urban_families should UPDATE existing settlement to 800")


func test_set_domain_urban_families_creates_placeholder() -> void:
	# Setting on a domain with no settlement should INSERT a placeholder.
	var domain_id: String = CampaignRepository.create_domain({
		"campaign_id": _campaign_id, "name": "PlaceholderDomain",
		"location_map_id": _map_id, "location_hex_q": 5, "location_hex_r": 5,
	})
	# Before: no settlement_entrances row for this domain.
	CampaignRepository.db.query_with_bindings(
		"SELECT COUNT(*) AS n FROM settlement_entrances WHERE parent_domain_id = ?",
		[domain_id]
	)
	check(int(CampaignRepository.db.query_result[0].get("n", -1)) == 0,
		"no settlement should exist for new domain before set")
	# Set urban_families — placeholder gets inserted.
	CampaignRepository.set_domain_urban_families(domain_id, 600)
	CampaignRepository.db.query_with_bindings(
		"SELECT urban_families FROM settlement_entrances WHERE parent_domain_id = ?",
		[domain_id]
	)
	check(not CampaignRepository.db.query_result.is_empty(),
		"placeholder settlement should be created")
	check(int(CampaignRepository.db.query_result[0].get("urban_families", 0)) == 600,
		"placeholder settlement should have urban_families = 600")


func test_get_domain_aggregates_urban_families() -> void:
	var domain_id: String = CampaignRepository.create_domain({
		"campaign_id": _campaign_id, "name": "AggregateDomain",
	})
	_make_settlement({"hex_q": 40, "hex_r": 0, "parent_domain_id": domain_id, "urban_families": 500})
	_make_settlement({"hex_q": 40, "hex_r": 1, "parent_domain_id": domain_id, "urban_families": 200})
	_make_settlement({"hex_q": 40, "hex_r": 2, "parent_domain_id": domain_id, "urban_families": 100})
	var domain: Dictionary = CampaignRepository.get_domain(domain_id)
	check(int(domain.get("urban_families", -1)) == 800,
		"get_domain should aggregate urban_families = 800 (500+200+100), got %d" % int(domain.get("urban_families", -1)))


func test_list_campaign_domains_aggregates_urban_families() -> void:
	# Fresh campaign so we don't pick up other test domains.
	var cid: String = CampaignRepository.create_campaign("AggListCampaign", "")
	var d1: String = CampaignRepository.create_domain({"campaign_id": cid, "name": "D1"})
	var d2: String = CampaignRepository.create_domain({"campaign_id": cid, "name": "D2"})
	CampaignRepository.set_domain_urban_families(d1, 250)
	CampaignRepository.set_domain_urban_families(d2, 750)
	var domains: Array = CampaignRepository.list_campaign_domains(cid)
	check(domains.size() == 2, "expected 2 domains in fresh campaign")
	var by_id: Dictionary = {}
	for d in domains:
		by_id[str((d as Dictionary).get("id", ""))] = int((d as Dictionary).get("urban_families", 0))
	check(by_id.get(d1, -1) == 250, "D1 urban_families should be 250")
	check(by_id.get(d2, -1) == 750, "D2 urban_families should be 750")


# ---------------------------------------------------------------------------
# §3 input-resolver tests
# ---------------------------------------------------------------------------

func test_climate_columns_single_column_cases() -> void:
	check(SettlementEconomyInputs.climate_columns_for("woods", "") == ["deciduous_forest"],
		"woods/'' → [deciduous_forest]")
	check(SettlementEconomyInputs.climate_columns_for("jungle", "") == ["rainforest"],
		"jungle/'' → [rainforest]")
	check(SettlementEconomyInputs.climate_columns_for("desert", "") == ["desert"],
		"desert/'' → [desert]")
	check(SettlementEconomyInputs.climate_columns_for("woods", "forest_taiga") == ["taiga"],
		"woods/forest_taiga → [taiga]")


func test_climate_columns_composite_clear_default() -> void:
	var result: Array = SettlementEconomyInputs.climate_columns_for("clear", "")
	check(result.size() == 2, "clear/'' should return 2 columns, got %d" % result.size())
	check(result.has("grasslands") and result.has("plains"),
		"clear/'' should be [grasslands, plains] composite")


func test_climate_columns_narrowing_subtypes() -> void:
	check(SettlementEconomyInputs.climate_columns_for("clear", "clear_grassland") == ["grasslands"],
		"clear/clear_grassland → [grasslands]")
	check(SettlementEconomyInputs.climate_columns_for("clear", "clear_steppe") == ["steppe"],
		"clear/clear_steppe → [steppe]")
	check(SettlementEconomyInputs.climate_columns_for("clear", "clear_scrub") == ["scrub"],
		"clear/clear_scrub → [scrub]")
	check(SettlementEconomyInputs.climate_columns_for("clear", "clear_savanna") == ["savanna"],
		"clear/clear_savanna → [savanna]")
	check(SettlementEconomyInputs.climate_columns_for("clear", "clear_tundra") == ["tundra"],
		"clear/clear_tundra → [tundra]")


func test_climate_columns_swamp_composite() -> void:
	# §3.4: swamp climate = scrub. (lake_shore is verified in water-source test.)
	check(SettlementEconomyInputs.climate_columns_for("swamp", "") == ["scrub"],
		"swamp/'' → [scrub] climate (lake_shore handled separately by water-source resolver)")


func test_climate_columns_mountain_subtype_inheritance() -> void:
	var clear_volcanic: Array = SettlementEconomyInputs.climate_columns_for("clear", "mountains_volcanic")
	check(clear_volcanic.has("grasslands") and clear_volcanic.has("plains"),
		"clear/mountains_volcanic should inherit composite climate")
	check(SettlementEconomyInputs.climate_columns_for("desert", "mountains_glacial") == ["desert"],
		"desert/mountains_glacial inherits desert climate")
	check(SettlementEconomyInputs.climate_columns_for("jungle", "mountains_volcanic") == ["rainforest"],
		"jungle/mountains_volcanic inherits rainforest climate")


func test_climate_override_replaces_composite() -> void:
	# clear-default settlement (which would map to [grasslands, plains])
	# with climate_override='steppe' should collapse to [steppe].
	_make_hex(50, 0, "clear", "", "flat", "")
	var settlement_id: String = _make_settlement({
		"hex_q": 50, "hex_r": 0, "climate_override": "steppe",
	})
	var inputs: Dictionary = SettlementEconomyInputs.resolve_all(settlement_id)
	check(inputs.get("climate_columns", []) == ["steppe"],
		"climate_override='steppe' should yield climate_columns=[steppe], got %s" % str(inputs.get("climate_columns")))


func test_resolve_water_sources_ocean_adjacency() -> void:
	# Hex with ocean on the home cell.
	_make_hex(60, 0, "clear", "", "flat", "ocean")
	var s1: String = _make_settlement({"hex_q": 60, "hex_r": 0})
	var ws1: Dictionary = SettlementEconomyInputs.resolve_water_sources(s1)
	check(ws1.get("sea_coast", false), "settlement on ocean hex → sea_coast=true")

	# Hex adjacent to ocean.
	_make_hex(61, 0, "clear", "", "flat", "")
	_make_hex(62, 0, "clear", "", "flat", "ocean")  # neighbor of (61, 0)
	var s2: String = _make_settlement({"hex_q": 61, "hex_r": 0})
	var ws2: Dictionary = SettlementEconomyInputs.resolve_water_sources(s2)
	check(ws2.get("sea_coast", false), "settlement adjacent to ocean → sea_coast=true")

	# Two-away from ocean: NOT sea_coast.
	_make_hex(70, 0, "clear", "", "flat", "")
	_make_hex(71, 0, "clear", "", "flat", "")
	_make_hex(72, 0, "clear", "", "flat", "ocean")
	var s3: String = _make_settlement({"hex_q": 70, "hex_r": 0})
	var ws3: Dictionary = SettlementEconomyInputs.resolve_water_sources(s3)
	check(not ws3.get("sea_coast", true), "settlement two-away from ocean → sea_coast=false")


func test_resolve_water_sources_swamp_implies_lake_shore() -> void:
	_make_hex(80, 0, "swamp", "", "flat", "")  # No actual lake adjacent.
	var s: String = _make_settlement({"hex_q": 80, "hex_r": 0})
	var ws: Dictionary = SettlementEconomyInputs.resolve_water_sources(s)
	check(ws.get("lake_shore", false), "swamp biome → lake_shore=true (project composite)")


func test_resolve_water_sources_river_overlay() -> void:
	# Settlement on a hex with river overlay.
	_make_hex(90, 0, "clear", "", "flat", "")
	_add_river_overlay(90, 0)
	var s1: String = _make_settlement({"hex_q": 90, "hex_r": 0})
	var ws1: Dictionary = SettlementEconomyInputs.resolve_water_sources(s1)
	check(ws1.get("river_bank", false), "settlement on river-overlay hex → river_bank=true")

	# Settlement on adjacent hex but river is on neighbor.
	_make_hex(91, 0, "clear", "", "flat", "")
	# No overlay on (91,0)
	var s2: String = _make_settlement({"hex_q": 91, "hex_r": 0})
	var ws2: Dictionary = SettlementEconomyInputs.resolve_water_sources(s2)
	check(not ws2.get("river_bank", true), "settlement adjacent to but not on river → river_bank=false")


func test_resolve_water_sources_multi_source() -> void:
	# Coastal river-mouth: ocean on home hex + river overlay.
	_make_hex(100, 0, "clear", "", "flat", "ocean")
	_add_river_overlay(100, 0)
	var s: String = _make_settlement({"hex_q": 100, "hex_r": 0})
	var ws: Dictionary = SettlementEconomyInputs.resolve_water_sources(s)
	check(ws.get("sea_coast", false), "coastal river-mouth → sea_coast=true")
	check(ws.get("river_bank", false), "coastal river-mouth → river_bank=true")


func test_elevation_bucket() -> void:
	check(SettlementEconomyInputs.elevation_bucket_for("flat") == "",
		"flat → '' (sentinel — no modifier)")
	check(SettlementEconomyInputs.elevation_bucket_for("hills") == "hills",
		"hills → 'hills'")
	check(SettlementEconomyInputs.elevation_bucket_for("mountains") == "mountains",
		"mountains → 'mountains'")


func test_domain_land_revenue_averaging() -> void:
	# Fixture: domain with three hexes (land_value 3, 5, 7) → avg 5.
	var domain_id: String = CampaignRepository.create_domain({
		"campaign_id": _campaign_id, "name": "LandRevenue357",
		"location_map_id": _map_id, "location_hex_q": 0, "location_hex_r": 0,
	})
	CampaignRepository.add_domain_hex({"domain_id": domain_id, "hex_q": 0, "hex_r": 0, "land_value": 3})
	CampaignRepository.add_domain_hex({"domain_id": domain_id, "hex_q": 0, "hex_r": 1, "land_value": 5})
	CampaignRepository.add_domain_hex({"domain_id": domain_id, "hex_q": 0, "hex_r": 2, "land_value": 7})
	var settlement_id: String = _make_settlement({
		"hex_q": 110, "hex_r": 0, "parent_domain_id": domain_id,
	})
	check(SettlementEconomyInputs.resolve_domain_land_revenue(settlement_id) == 5,
		"land_value(3, 5, 7) → avg 5")

	# Banker's rounding: hexes (3, 4) → avg 3.5 → 4 (rounds to even; 4 is even)
	var d2: String = CampaignRepository.create_domain({"campaign_id": _campaign_id, "name": "LandRevenue34"})
	CampaignRepository.add_domain_hex({"domain_id": d2, "hex_q": 0, "hex_r": 0, "land_value": 3})
	CampaignRepository.add_domain_hex({"domain_id": d2, "hex_q": 0, "hex_r": 1, "land_value": 4})
	var s2: String = _make_settlement({"hex_q": 111, "hex_r": 0, "parent_domain_id": d2})
	check(SettlementEconomyInputs.resolve_domain_land_revenue(s2) == 4,
		"land_value(3, 4) → 3.5 → banker rounds to 4")

	# Banker's: hexes (4, 5) → avg 4.5 → 4 (rounds to even)
	var d3: String = CampaignRepository.create_domain({"campaign_id": _campaign_id, "name": "LandRevenue45"})
	CampaignRepository.add_domain_hex({"domain_id": d3, "hex_q": 0, "hex_r": 0, "land_value": 4})
	CampaignRepository.add_domain_hex({"domain_id": d3, "hex_q": 0, "hex_r": 1, "land_value": 5})
	var s3: String = _make_settlement({"hex_q": 112, "hex_r": 0, "parent_domain_id": d3})
	check(SettlementEconomyInputs.resolve_domain_land_revenue(s3) == 4,
		"land_value(4, 5) → 4.5 → banker rounds to 4")


func test_domain_land_revenue_no_parent_domain() -> void:
	var s: String = _make_settlement({"hex_q": 120, "hex_r": 0})
	check(SettlementEconomyInputs.resolve_domain_land_revenue(s) == 5,
		"settlement with no parent_domain_id → 5 (mid-scale fallback)")


func test_resolve_all_aggregator() -> void:
	# clear-grassland biome, age=750 (101_1000), dwarf, parent domain
	# with hexes (4,5,6) avg 5, ocean-adjacent neighbor, no climate_override.
	_make_hex(130, 0, "clear", "clear_grassland", "flat", "")
	_make_hex(131, 0, "clear", "", "flat", "ocean")  # neighbor → sea_coast=true
	var domain_id: String = CampaignRepository.create_domain({
		"campaign_id": _campaign_id, "name": "AggregatorDomain",
	})
	CampaignRepository.add_domain_hex({"domain_id": domain_id, "hex_q": 0, "hex_r": 0, "land_value": 4})
	CampaignRepository.add_domain_hex({"domain_id": domain_id, "hex_q": 0, "hex_r": 1, "land_value": 5})
	CampaignRepository.add_domain_hex({"domain_id": domain_id, "hex_q": 0, "hex_r": 2, "land_value": 6})
	var s: String = _make_settlement({
		"hex_q": 130, "hex_r": 0,
		"age_years": 750, "dominant_race": "dwarf",
		"parent_domain_id": domain_id,
	})
	var inputs: Dictionary = SettlementEconomyInputs.resolve_all(s)
	check(str(inputs.get("age_bucket", "")) == "101_1000_years",
		"resolve_all: age_bucket=101_1000_years, got %s" % str(inputs.get("age_bucket")))
	check(inputs.get("climate_columns", []) == ["grasslands"],
		"resolve_all: clear/clear_grassland → [grasslands], got %s" % str(inputs.get("climate_columns")))
	check(str(inputs.get("climate_override", "x")) == "",
		"resolve_all: climate_override='' for non-override path")
	check(str(inputs.get("elevation_bucket", "x")) == "",
		"resolve_all: flat elevation → '' sentinel")
	check((inputs.get("water_sources", {}) as Dictionary).get("sea_coast", false),
		"resolve_all: ocean-adjacent neighbor → sea_coast=true")
	check(not (inputs.get("water_sources", {}) as Dictionary).get("lake_shore", true),
		"resolve_all: no lake → lake_shore=false")
	check(not (inputs.get("water_sources", {}) as Dictionary).get("river_bank", true),
		"resolve_all: no river → river_bank=false")
	check(str(inputs.get("dominant_race", "")) == "dwarf",
		"resolve_all: dominant_race=dwarf, got %s" % str(inputs.get("dominant_race")))
	check(int(inputs.get("domain_land_revenue", 0)) == 5,
		"resolve_all: land_revenue(4,5,6) avg 5, got %d" % int(inputs.get("domain_land_revenue", 0)))
