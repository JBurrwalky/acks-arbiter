extends "res://tests/test_suite_base.gd"

## Tests for DomainStocker — the bootstrap that seeds strongholds, garrisons,
## and market-demand rows for on-map domains and their settlement entrances
## (Avalon test campaign, future scripted scenarios).
##
## Unit coverage:
##   * stronghold value calculation across all three RAW territory types.
##   * garrison sizing per peasant-family customary spend.
##
## Integration coverage:
##   * stock_domain_infrastructure against the actual Avalon-seeded campaign:
##     16 on-map domains → 16 strongholds + 16 garrison troop_unit rows;
##     16 settlement_entrances → 16 × N merchandise demand rows.

const _CAMPAIGN_ID := "test_domain_stocker_unit"
const _AVALON_CAMPAIGN_ID := "test_domain_stocker_avalon"
const _AVALON_MAP_ID := "test_campaign_region"
const _AVALON_ON_MAP_DOMAINS := 16
const _AVALON_SETTLEMENT_COUNT := 16

# Total merchandise types in the registry (20 common + 11 precious per
# data/commerce/*.json). The exact value isn't load-bearing for the assertion
# below — we only assert > 0 — but documenting it here records the expected
# row count per settlement so a future drop in the registry is loud.
const _MERCHANDISE_TYPE_COUNT := 31


func run_all_tests() -> void:
	_cleanup_unit()
	test_stronghold_value_within_expected_range_civilized()
	test_stronghold_value_within_expected_range_borderlands()
	test_stronghold_value_within_expected_range_wilderness()
	test_structure_type_band_matches_landmark_icon_thresholds()
	test_garrison_sizing_civilized()
	test_garrison_sizing_borderlands()
	test_garrison_sizing_wilderness()
	test_garrison_meets_calculator_minimum()
	_cleanup_unit()
	test_integration_avalon_full_stocking()
	_cleanup_avalon()
	if not has_failures():
		print("DomainStocker: all tests passed.")


# ---------------------------------------------------------------------------
# Unit: stronghold value
# ---------------------------------------------------------------------------

## RAW per-hex minimums (gp) — duplicated here so the test fails loudly if the
## production constants drift away from RAW.
const _MIN_GP_PER_HEX := {
	"civilized": 15000,
	"borderlands": 22500,
	"wilderness": 32000,
}


func test_stronghold_value_within_expected_range_civilized() -> void:
	_assert_stronghold_value_in_range("civilized", 5)
	print("  stronghold_value_within_expected_range_civilized: OK")


func test_stronghold_value_within_expected_range_borderlands() -> void:
	_assert_stronghold_value_in_range("borderlands", 3)
	print("  stronghold_value_within_expected_range_borderlands: OK")


func test_stronghold_value_within_expected_range_wilderness() -> void:
	_assert_stronghold_value_in_range("wilderness", 1)
	print("  stronghold_value_within_expected_range_wilderness: OK")


## Drive the RNG across the full 0.0-1.0 range (10 samples) and verify every
## sampled value lands inside [minimum, 1.5 × minimum]. The test is RNG-pinned
## so a flake-by-randomness can't slip through.
func _assert_stronghold_value_in_range(territory: String, hex_count: int) -> void:
	var per_hex: int = int(_MIN_GP_PER_HEX[territory])
	var min_gp: int = per_hex * hex_count
	var max_gp: int = int(round(float(min_gp) * 1.5))
	var rng := RandomNumberGenerator.new()
	for seed in range(10):
		rng.seed = seed * 7919 + 1  # arbitrary distinct primes per iteration
		var value: int = DomainStocker.compute_stronghold_value_gp(
			territory, hex_count, rng)
		check(value >= min_gp,
			"%s: value %d below minimum %d (hex_count=%d, seed=%d)" % [
				territory, value, min_gp, hex_count, seed])
		check(value <= max_gp,
			"%s: value %d above max %d (hex_count=%d, seed=%d)" % [
				territory, value, max_gp, hex_count, seed])


func test_structure_type_band_matches_landmark_icon_thresholds() -> void:
	# tower: ≤ 20,000 SHP
	check(DomainStocker.structure_type_for_shp(1) == "tower",
		"shp=1 should be tower")
	check(DomainStocker.structure_type_for_shp(20000) == "tower",
		"shp=20000 should be tower (≤ STRONGHOLD_SHP_TOWER_MAX)")
	# keep: 20,001 – 100,000 SHP
	check(DomainStocker.structure_type_for_shp(20001) == "keep",
		"shp=20001 should be keep")
	check(DomainStocker.structure_type_for_shp(100000) == "keep",
		"shp=100000 should be keep (≤ STRONGHOLD_SHP_KEEP_MAX)")
	# fortress: > 100,000 SHP
	check(DomainStocker.structure_type_for_shp(100001) == "fortress",
		"shp=100001 should be fortress")
	check(DomainStocker.structure_type_for_shp(512000) == "fortress",
		"shp=512000 should be fortress (RAW wilderness 24-mile hex threshold)")
	print("  structure_type_band_matches_landmark_icon_thresholds: OK")


# ---------------------------------------------------------------------------
# Unit: garrison sizing
# ---------------------------------------------------------------------------

func test_garrison_sizing_civilized() -> void:
	check(DomainStocker.garrison_gp_per_family("civilized") == 2,
		"civilized should spend 2 gp/family per RAW §domain_income L262")
	print("  garrison_sizing_civilized: OK")


func test_garrison_sizing_borderlands() -> void:
	check(DomainStocker.garrison_gp_per_family("borderlands") == 3,
		"borderlands should spend 3 gp/family per RAW §domain_income L261")
	print("  garrison_sizing_borderlands: OK")


func test_garrison_sizing_wilderness() -> void:
	check(DomainStocker.garrison_gp_per_family("wilderness") == 4,
		"wilderness should spend 4 gp/family per RAW §domain_income L260")
	print("  garrison_sizing_wilderness: OK")


## Smoke-stock a fixture domain in each classification and confirm that the
## GarrisonExpenditureCalculator reports meets_minimum=true and the universal
## 2 gp/family RAW floor is satisfied. This is the load-bearing assertion:
## if stocking ever falls below the floor, monthly tick morale drops every
## month, defeating the bootstrap purpose.
func test_garrison_meets_calculator_minimum() -> void:
	_cleanup_unit()
	_make_campaign(_CAMPAIGN_ID)
	for territory in ["civilized", "borderlands", "wilderness"]:
		var domain_id: String = _make_domain(_CAMPAIGN_ID, territory, 250)
		var domain: Dictionary = CampaignRepository.get_domain(domain_id)
		var ids: Array = DomainStocker.stock_garrison(domain)
		check(ids.size() == 1,
			"%s: expected 1 garrison unit; got %d" % [territory, ids.size()])
		var breakdown: Dictionary = GarrisonExpenditureCalculator.compute(domain_id)
		check(bool(breakdown.get("meets_minimum", false)),
			"%s: stocked garrison must meet RAW 2gp/family minimum; got %d cp vs %d cp" % [
				territory,
				int(breakdown.get("total_value_cp", 0)),
				int(breakdown.get("minimum_total_cp", 0)),
			])
	print("  garrison_meets_calculator_minimum: OK")


# ---------------------------------------------------------------------------
# Integration: Avalon
# ---------------------------------------------------------------------------

func test_integration_avalon_full_stocking() -> void:
	_cleanup_avalon()
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[_AVALON_CAMPAIGN_ID, "Avalon Stocker Integration"])

	# Seed the Avalon test campaign and copy its 600-hex region + 16 domains +
	# 16 settlements + 84 domain_hexes into our test campaign. We don't reuse
	# the TestContentSeeder's own campaign because it asserts row counts on a
	# clean slate — running the stocker mutates that.
	var ok: bool = TestContentSeeder.seed_avalon_test_campaign(_AVALON_CAMPAIGN_ID)
	check(ok, "seed_avalon_test_campaign returned false")
	if not ok:
		return

	# Verify baseline shape after the seeder ran. The seeder's step 7 now
	# calls DomainStocker.stock_domain_infrastructure internally, so the
	# Avalon DB is ALREADY stocked at this point. This test verifies that
	# integrated state is correct.
	check(_count("SELECT COUNT(*) AS n FROM domains WHERE campaign_id = ? AND location_map_id IS NOT NULL",
			[_AVALON_CAMPAIGN_ID]) == _AVALON_ON_MAP_DOMAINS,
		"baseline: expected %d on-map domains" % _AVALON_ON_MAP_DOMAINS)
	check(_count("SELECT COUNT(*) AS n FROM settlement_entrances WHERE campaign_id = ?",
			[_AVALON_CAMPAIGN_ID]) == _AVALON_SETTLEMENT_COUNT,
		"baseline: expected %d settlement_entrances" % _AVALON_SETTLEMENT_COUNT)
	check(_count("SELECT COUNT(*) AS n FROM strongholds s JOIN domains d ON d.id = s.domain_id WHERE d.campaign_id = ?",
			[_AVALON_CAMPAIGN_ID]) == _AVALON_ON_MAP_DOMAINS,
		"expected %d strongholds in DB after seed orchestration" % _AVALON_ON_MAP_DOMAINS)

	# Re-run the stocker manually — should be a no-op (idempotent), returning
	# zero new ids since everything is already stocked.
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xACE5_C0DE  # pinned for reproducibility
	var summary: Dictionary = DomainStocker.stock_domain_infrastructure(
		_AVALON_CAMPAIGN_ID, rng)

	check((summary.get("stronghold_ids", []) as Array).is_empty(),
		"second-pass stocker should create 0 strongholds (seed already stocked); got %d" % [
			(summary.get("stronghold_ids", []) as Array).size(),
		])

	# DB-level row counts unchanged.
	check(_count("SELECT COUNT(*) AS n FROM strongholds s JOIN domains d ON d.id = s.domain_id WHERE d.campaign_id = ?",
			[_AVALON_CAMPAIGN_ID]) == _AVALON_ON_MAP_DOMAINS,
		"expected %d strongholds in DB (stable after idempotent re-run)" % _AVALON_ON_MAP_DOMAINS)

	# Garrison troop_units — one per on-map domain.
	var garrison_count: int = _count("""
		SELECT COUNT(*) AS n FROM troop_units
		WHERE campaign_id = ? AND assignment_kind = 'garrison'
	""", [_AVALON_CAMPAIGN_ID])
	check(garrison_count == _AVALON_ON_MAP_DOMAINS,
		"expected %d garrison units; got %d" % [_AVALON_ON_MAP_DOMAINS, garrison_count])

	# Demand modifier rows. The registry exposes N merchandise types; assert
	# the row count equals N × settlements, and N matches the documented total.
	var registry_size: int = MerchandiseRegistry.all_merchandise().size()
	check(registry_size > 0, "MerchandiseRegistry returned 0 entries — autoload not loaded?")
	check(registry_size == _MERCHANDISE_TYPE_COUNT,
		"merchandise registry: expected %d entries; got %d" % [_MERCHANDISE_TYPE_COUNT, registry_size])

	var demand_rows: int = _count("""
		SELECT COUNT(*) AS n FROM settlement_merchandise_demand smd
		JOIN settlement_entrances s ON s.id = smd.settlement_entrance_id
		WHERE s.campaign_id = ?
	""", [_AVALON_CAMPAIGN_ID])
	check(demand_rows == _AVALON_SETTLEMENT_COUNT * registry_size,
		"expected %d demand rows (%d settlements × %d merchandise types); got %d" % [
			_AVALON_SETTLEMENT_COUNT * registry_size,
			_AVALON_SETTLEMENT_COUNT, registry_size, demand_rows,
		])

	# Triple-idempotency: a THIRD call must also be a no-op.
	var summary3: Dictionary = DomainStocker.stock_domain_infrastructure(
		_AVALON_CAMPAIGN_ID, rng)
	check((summary3.get("stronghold_ids", []) as Array).is_empty(),
		"third run should also create 0 new strongholds (idempotency); got %d" % [
			(summary3.get("stronghold_ids", []) as Array).size(),
		])
	check(_count("SELECT COUNT(*) AS n FROM strongholds s JOIN domains d ON d.id = s.domain_id WHERE d.campaign_id = ?",
			[_AVALON_CAMPAIGN_ID]) == _AVALON_ON_MAP_DOMAINS,
		"stronghold count must be stable across idempotent re-runs")

	print("  integration_avalon_full_stocking: OK")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_campaign(id: String) -> void:
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[id, "DomainStocker Unit Tests"])


func _make_domain(campaign_id: String, territory: String, peasants: int) -> String:
	# Create a minimal NPC character to own the domain (troop_units.owner_character_id
	# is NOT NULL + FK to characters, so stock_garrison requires a real owner).
	var ruler_id: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters
			(id, campaign_id, name, character_type, persistence_tier,
			 race, character_class, level, combat_progression)
		VALUES (?, ?, ?, 'npc', 'named', 'human', 'fighter', 6, 'fighter')
	""", [ruler_id, campaign_id, "Stocker Fixture Ruler %s" % territory])
	var domain_id: String = CampaignRepository.create_domain({
		"campaign_id": campaign_id,
		"name": "Stocker Fixture %s" % territory,
		"territory_type": territory,
		"owner_character_id": ruler_id,
	})
	# peasant_families lives behind the monthly-state whitelist.
	CampaignRepository.update_domain_monthly_state(domain_id, {"peasant_families": peasants})
	return domain_id


func _count(sql: String, params: Array) -> int:
	if not CampaignRepository.db.query_with_bindings(sql, params):
		return -1
	if CampaignRepository.db.query_result.is_empty():
		return 0
	return int(CampaignRepository.db.query_result[0].get("n", 0))


func _cleanup_unit() -> void:
	# Cascade-clean the unit-test fixture rows.
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM troop_units WHERE campaign_id = ?", [_CAMPAIGN_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM strongholds WHERE domain_id IN (SELECT id FROM domains WHERE campaign_id = ?)",
		[_CAMPAIGN_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM domains WHERE campaign_id = ?", [_CAMPAIGN_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [_CAMPAIGN_ID])


func _cleanup_avalon() -> void:
	CampaignRepository.db.query_with_bindings("""
		DELETE FROM settlement_merchandise_demand
		WHERE settlement_entrance_id IN (
			SELECT id FROM settlement_entrances WHERE campaign_id = ?
		)
	""", [_AVALON_CAMPAIGN_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM troop_units WHERE campaign_id = ?", [_AVALON_CAMPAIGN_ID])
	CampaignRepository.db.query_with_bindings("""
		DELETE FROM strongholds
		WHERE domain_id IN (SELECT id FROM domains WHERE campaign_id = ?)
	""", [_AVALON_CAMPAIGN_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM lairs WHERE campaign_id = ?", [_AVALON_CAMPAIGN_ID])
	CampaignRepository.db.query_with_bindings("""
		DELETE FROM domain_hexes
		WHERE domain_id IN (SELECT id FROM domains WHERE campaign_id = ?)
	""", [_AVALON_CAMPAIGN_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM domains WHERE campaign_id = ?", [_AVALON_CAMPAIGN_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM hex_river_edges WHERE map_id = ?", [_AVALON_MAP_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM hex_overlays WHERE map_id = ?", [_AVALON_MAP_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM dungeon_entrances WHERE campaign_id = ?", [_AVALON_CAMPAIGN_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM settlement_entrances WHERE campaign_id = ?", [_AVALON_CAMPAIGN_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM hex_cells WHERE map_id = ?", [_AVALON_MAP_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM hex_maps WHERE id = ?", [_AVALON_MAP_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [_AVALON_CAMPAIGN_ID])
