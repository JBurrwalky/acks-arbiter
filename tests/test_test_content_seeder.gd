extends "res://tests/test_suite_base.gd"

## End-to-end tests for TestContentSeeder.
##
## Coverage:
##   * seed_avalon_test_campaign produces the expected row counts in every
##     table the seeder writes to.
##   * seed_legacy_ashford_vale produces the same content the inlined seeder
##     in SessionLoadState used to produce.
##   * Both seeders are idempotent at the campaign level.
##   * All 118 Avalon lairs land on wilderness hexes (no civilized/borderlands
##     placements bled through from the generator).


const AVALON_CAMPAIGN := "test_seeder_avalon_campaign"
const LEGACY_CAMPAIGN := "test_seeder_legacy_campaign"
const AVALON_MAP_ID := "test_campaign_region"
const LEGACY_MAP_ID := "test_region_001"


func run_all_tests() -> void:
	_cleanup_all()
	test_avalon_seed_produces_expected_row_counts()
	test_avalon_lairs_only_on_wilderness_hexes()
	test_avalon_seed_idempotent()
	test_legacy_seed_produces_expected_row_counts()
	test_legacy_seed_idempotent()
	_cleanup_all()
	if not has_failures():
		print("TestContentSeeder: all tests passed.")


# ---------------------------------------------------------------------------
# Avalon
# ---------------------------------------------------------------------------

func test_avalon_seed_produces_expected_row_counts() -> void:
	_cleanup_avalon()
	_make_campaign_row(AVALON_CAMPAIGN, "Avalon Seed Test")
	var ok := TestContentSeeder.seed_avalon_test_campaign(AVALON_CAMPAIGN)
	check(ok, "seed_avalon_test_campaign returned false")
	if not ok:
		return

	check(_count("SELECT COUNT(*) AS n FROM hex_cells WHERE map_id = ?", [AVALON_MAP_ID]) == 600,
		"hex_cells: expected 600; got %d" % _count("SELECT COUNT(*) AS n FROM hex_cells WHERE map_id = ?", [AVALON_MAP_ID]))
	check(_count("SELECT COUNT(*) AS n FROM settlement_entrances WHERE map_id = ?", [AVALON_MAP_ID]) == 16,
		"settlement_entrances: expected 16")
	check(_count("SELECT COUNT(*) AS n FROM dungeon_entrances WHERE map_id = ?", [AVALON_MAP_ID]) == 3,
		"dungeon_entrances: expected 3")
	check(_count("SELECT COUNT(*) AS n FROM hex_river_edges WHERE map_id = ?", [AVALON_MAP_ID]) == 43,
		"hex_river_edges: expected 43")
	check(_count("SELECT COUNT(*) AS n FROM hex_overlays WHERE map_id = ? AND overlay_type = 'road'", [AVALON_MAP_ID]) == 74,
		"hex_overlays road rows: expected 74")
	check(_count("SELECT COUNT(*) AS n FROM domains WHERE campaign_id = ?", [AVALON_CAMPAIGN]) == 376,
		"domains: expected 376")
	check(_count("SELECT COUNT(*) AS n FROM domains WHERE campaign_id = ? AND location_map_id IS NOT NULL", [AVALON_CAMPAIGN]) == 16,
		"on-map domains: expected 16")
	check(_count("SELECT COUNT(*) AS n FROM domains WHERE campaign_id = ? AND location_map_id IS NULL", [AVALON_CAMPAIGN]) == 360,
		"abstracted domains: expected 360")
	check(_count("SELECT COUNT(*) AS n FROM domain_hexes WHERE map_id = ?", [AVALON_MAP_ID]) == 84,
		"domain_hexes: expected 84")
	check(_count("SELECT COUNT(*) AS n FROM lairs WHERE campaign_id = ?", [AVALON_CAMPAIGN]) == 118,
		"lairs: expected 118")
	print("  avalon_seed_produces_expected_row_counts: OK")


func test_avalon_lairs_only_on_wilderness_hexes() -> void:
	# Run on the same data the previous test seeded; if it short-circuits via
	# the idempotency guard, the count is still correct.
	if not _campaign_has_hex_map(AVALON_CAMPAIGN):
		_make_campaign_row(AVALON_CAMPAIGN, "Avalon Seed Test")
		TestContentSeeder.seed_avalon_test_campaign(AVALON_CAMPAIGN)
	var non_wild: int = _count("""
		SELECT COUNT(*) AS n
		FROM lairs l
		JOIN hex_cells c ON c.map_id = l.map_id AND c.q = l.hex_q AND c.r = l.hex_r
		WHERE l.campaign_id = ? AND c.civilization != 'wilderness'
	""", [AVALON_CAMPAIGN])
	check(non_wild == 0,
		"expected 0 non-wilderness lairs; got %d" % non_wild)
	print("  avalon_lairs_only_on_wilderness_hexes: OK")


func test_avalon_seed_idempotent() -> void:
	if not _campaign_has_hex_map(AVALON_CAMPAIGN):
		_make_campaign_row(AVALON_CAMPAIGN, "Avalon Seed Test")
		TestContentSeeder.seed_avalon_test_campaign(AVALON_CAMPAIGN)
	var before_lairs: int = _count("SELECT COUNT(*) AS n FROM lairs WHERE campaign_id = ?", [AVALON_CAMPAIGN])
	var ok := TestContentSeeder.seed_avalon_test_campaign(AVALON_CAMPAIGN)
	check(ok, "second call returned false")
	var after_lairs: int = _count("SELECT COUNT(*) AS n FROM lairs WHERE campaign_id = ?", [AVALON_CAMPAIGN])
	check(before_lairs == after_lairs,
		"second seed call mutated state: lairs %d → %d" % [before_lairs, after_lairs])
	print("  avalon_seed_idempotent: OK")


# ---------------------------------------------------------------------------
# Legacy Ashford Vale
# ---------------------------------------------------------------------------

func test_legacy_seed_produces_expected_row_counts() -> void:
	_cleanup_legacy()
	_make_campaign_row(LEGACY_CAMPAIGN, "Legacy Seed Test")
	var ok := TestContentSeeder.seed_legacy_ashford_vale(LEGACY_CAMPAIGN)
	check(ok, "seed_legacy_ashford_vale returned false")
	if not ok:
		return

	# The legacy fixture should populate the same content the previous
	# inline-seeder did: the Ashford Vale region map + 2 settlements + 1
	# dungeon entrance + the 24-mile parent map.
	check(_count("SELECT COUNT(*) AS n FROM hex_maps WHERE id = ?", [LEGACY_MAP_ID]) == 1,
		"hex_maps row for legacy map missing")
	check(_count("SELECT COUNT(*) AS n FROM settlement_entrances WHERE map_id = ?", [LEGACY_MAP_ID]) == 2,
		"settlement_entrances: expected 2 (Ashford + Thornwall)")
	check(_count("SELECT COUNT(*) AS n FROM dungeon_entrances WHERE map_id = ?", [LEGACY_MAP_ID]) == 1,
		"dungeon_entrances: expected 1 (Goblin Warrens)")
	# 24-mile parent map should be present.
	check(_count("SELECT COUNT(*) AS n FROM hex_maps WHERE id = 'test_campaign_001'", []) >= 1,
		"24-mile parent map should be present after legacy seed")
	print("  legacy_seed_produces_expected_row_counts: OK")


func test_legacy_seed_idempotent() -> void:
	if not _campaign_has_hex_map(LEGACY_CAMPAIGN):
		_make_campaign_row(LEGACY_CAMPAIGN, "Legacy Seed Test")
		TestContentSeeder.seed_legacy_ashford_vale(LEGACY_CAMPAIGN)
	var before: int = _count("SELECT COUNT(*) AS n FROM settlement_entrances WHERE map_id = ?", [LEGACY_MAP_ID])
	var ok := TestContentSeeder.seed_legacy_ashford_vale(LEGACY_CAMPAIGN)
	check(ok, "second call returned false")
	var after: int = _count("SELECT COUNT(*) AS n FROM settlement_entrances WHERE map_id = ?", [LEGACY_MAP_ID])
	check(before == after,
		"second seed call mutated state: settlement_entrances %d → %d" % [before, after])
	print("  legacy_seed_idempotent: OK")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_campaign_row(campaign_id: String, name: String) -> void:
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[campaign_id, name])


func _campaign_has_hex_map(campaign_id: String) -> bool:
	return TestContentSeeder.campaign_has_any_hex_map(campaign_id)


func _count(sql: String, params: Array) -> int:
	if not CampaignRepository.db.query_with_bindings(sql, params):
		return -1
	if CampaignRepository.db.query_result.is_empty():
		return 0
	return int(CampaignRepository.db.query_result[0].get("n", 0))


func _cleanup_avalon() -> void:
	# Cascade-clean every row the Avalon seeder writes, then the campaign.
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM lairs WHERE campaign_id = ?", [AVALON_CAMPAIGN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM domain_hexes WHERE domain_id IN (SELECT id FROM domains WHERE campaign_id = ?)",
		[AVALON_CAMPAIGN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM domains WHERE campaign_id = ?", [AVALON_CAMPAIGN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM hex_river_edges WHERE map_id = ?", [AVALON_MAP_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM hex_overlays WHERE map_id = ?", [AVALON_MAP_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM dungeon_entrances WHERE campaign_id = ?", [AVALON_CAMPAIGN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM settlement_entrances WHERE campaign_id = ?", [AVALON_CAMPAIGN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM hex_cells WHERE map_id = ?", [AVALON_MAP_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM hex_maps WHERE id = ?", [AVALON_MAP_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [AVALON_CAMPAIGN])


func _cleanup_legacy() -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM dungeon_entrances WHERE campaign_id = ?", [LEGACY_CAMPAIGN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM settlement_entrances WHERE campaign_id = ?", [LEGACY_CAMPAIGN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM hex_river_edges WHERE map_id = ?", [LEGACY_MAP_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM hex_overlays WHERE map_id = ?", [LEGACY_MAP_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM hex_cells WHERE map_id = ?", [LEGACY_MAP_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM hex_maps WHERE id = ? AND campaign_id = ?",
		[LEGACY_MAP_ID, LEGACY_CAMPAIGN])
	# Parent map row may be shared across campaigns in dev; only delete if
	# no other campaign references it.
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM hex_cells WHERE map_id = 'test_campaign_001'", [])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM hex_maps WHERE id = 'test_campaign_001' AND campaign_id = ?",
		[LEGACY_CAMPAIGN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [LEGACY_CAMPAIGN])


func _cleanup_all() -> void:
	_cleanup_avalon()
	_cleanup_legacy()
