extends "res://tests/test_suite_base.gd"

## Verifies the SessionLoadState backwards-compat seed fallback.
##
## A campaign created before the TestContentSeeder seam existed has no
## hex_maps row. On first session load, SessionLoadState now calls
## `TestContentSeeder.campaign_has_any_hex_map` → `seed_legacy_ashford_vale`
## as a fallback so pre-existing campaigns continue to work.
##
## SessionLoadState.enter() touches a SessionRunner and a HexMapRenderer
## scene, so this test exercises the underlying gate + seeder calls
## directly (which is what SessionLoadState invokes) rather than spinning
## up the full session machinery.


const FALLBACK_CAMPAIGN := "test_session_load_fallback_campaign"
const LEGACY_MAP_ID := "test_region_001"


func run_all_tests() -> void:
	_cleanup()
	test_fresh_campaign_has_no_hex_maps()
	test_fallback_path_seeds_legacy_ashford_vale()
	_cleanup()
	if not has_failures():
		print("SessionLoadFallback: all tests passed.")


func test_fresh_campaign_has_no_hex_maps() -> void:
	_cleanup()
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[FALLBACK_CAMPAIGN, "Fallback Test"])
	check(not TestContentSeeder.campaign_has_any_hex_map(FALLBACK_CAMPAIGN),
		"fresh campaign should have no hex_maps")
	print("  fresh_campaign_has_no_hex_maps: OK")


func test_fallback_path_seeds_legacy_ashford_vale() -> void:
	# Recreate the exact sequence SessionLoadState.enter() runs.
	_cleanup()
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[FALLBACK_CAMPAIGN, "Fallback Test"])
	check(not TestContentSeeder.campaign_has_any_hex_map(FALLBACK_CAMPAIGN),
		"pre-seed: campaign should have no hex_maps")
	var ok := TestContentSeeder.seed_legacy_ashford_vale(FALLBACK_CAMPAIGN)
	check(ok, "fallback seeder returned false")
	check(TestContentSeeder.campaign_has_any_hex_map(FALLBACK_CAMPAIGN),
		"post-seed: campaign should have hex_maps")
	if not CampaignRepository.db.query_with_bindings(
		"SELECT id FROM hex_maps WHERE id = ?", [LEGACY_MAP_ID]):
		check(false, "query failed")
		return
	check(not CampaignRepository.db.query_result.is_empty(),
		"legacy hex_map row should exist after fallback fires")
	print("  fallback_path_seeds_legacy_ashford_vale: OK")


func _cleanup() -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM dungeon_entrances WHERE campaign_id = ?", [FALLBACK_CAMPAIGN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM settlement_entrances WHERE campaign_id = ?", [FALLBACK_CAMPAIGN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM hex_river_edges WHERE map_id = ?", [LEGACY_MAP_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM hex_overlays WHERE map_id = ?", [LEGACY_MAP_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM hex_cells WHERE map_id = ?", [LEGACY_MAP_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM hex_maps WHERE id = ? AND campaign_id = ?",
		[LEGACY_MAP_ID, FALLBACK_CAMPAIGN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM hex_cells WHERE map_id = 'test_campaign_001'", [])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM hex_maps WHERE id = 'test_campaign_001' AND campaign_id = ?",
		[FALLBACK_CAMPAIGN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [FALLBACK_CAMPAIGN])
