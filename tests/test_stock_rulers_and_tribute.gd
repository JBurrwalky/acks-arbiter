extends "res://tests/test_suite_base.gd"

## Integration test for NpcRulerGenerator.stock_rulers_and_tribute.
##
## Seeds the full Avalon test campaign, runs the bootstrap, and asserts:
##   * 16 character rows are created (one per on-map domain).
##   * Every abstract domain (location_map_id IS NULL) has tribute_out_owed > 0.
##   * On-map domains with a liege also have tribute_out_owed > 0.
##   * The Prince (no liege) has tribute_out_owed == 0.
##   * Owner reassignment happened on every on-map domain.

const CAMPAIGN_ID := "test_stock_rulers_campaign"
const MAP_ID := "test_campaign_region"


func run_all_tests() -> void:
	_cleanup()
	test_stock_rulers_and_tribute_end_to_end()
	_cleanup()
	if not has_failures():
		print("StockRulersAndTribute: all tests passed.")


func test_stock_rulers_and_tribute_end_to_end() -> void:
	_make_campaign_row()
	var seeded: bool = TestContentSeeder.seed_avalon_test_campaign(CAMPAIGN_ID)
	check(seeded, "seed_avalon_test_campaign returned false")
	if not seeded:
		return

	# The seeder's step 8 now calls NpcRulerGenerator.stock_rulers_and_tribute
	# internally, so the Avalon DB is ALREADY stocked at this point. Calling
	# the stocker again must be a no-op for ruler creation (idempotent skip
	# for already-owned domains) but should still rewrite tribute_out_owed.
	var ruler_gen := NpcRulerGenerator.new()
	var summary: Dictionary = ruler_gen.stock_rulers_and_tribute(CAMPAIGN_ID)

	check(int(summary.get("total_domains", 0)) == 376,
		"summary.total_domains: expected 376, got %d" % int(summary.get("total_domains", 0)))

	# Idempotent re-call: 0 new rulers, all 376 tribute entries re-written.
	check(int(summary.get("rulers_created", 0)) == 0,
		"summary.rulers_created on re-run: expected 0 (seed already stocked), got %d" % int(summary.get("rulers_created", 0)))

	check(int(summary.get("tribute_set", 0)) == 376,
		"summary.tribute_set: expected 376, got %d" % int(summary.get("tribute_set", 0)))

	var errors: Array = summary.get("errors", [])
	check(errors.is_empty(),
		"summary.errors should be empty; got %s" % str(errors))

	# Database assertions ---------------------------------------------------
	var character_count: int = _count("""
		SELECT COUNT(*) AS n FROM characters
		WHERE campaign_id = ? AND character_type = 'npc'
	""", [CAMPAIGN_ID])
	check(character_count == 16,
		"npc character rows: expected 16, got %d" % character_count)

	var owned_on_map: int = _count("""
		SELECT COUNT(*) AS n FROM domains
		WHERE campaign_id = ? AND location_map_id IS NOT NULL
		  AND owner_character_id IS NOT NULL
	""", [CAMPAIGN_ID])
	check(owned_on_map == 16,
		"on-map domains with owner_character_id: expected 16, got %d" % owned_on_map)

	# All abstract domains must have non-zero tribute_out_owed.
	var abstract_zero: int = _count("""
		SELECT COUNT(*) AS n FROM domains
		WHERE campaign_id = ? AND location_map_id IS NULL
		  AND tribute_out_owed = 0
	""", [CAMPAIGN_ID])
	check(abstract_zero == 0,
		"abstract domains with tribute_out_owed == 0: expected 0, got %d" % abstract_zero)

	# Prince (no liege) should have tribute_out_owed == 0.
	var prince_zero: int = _count("""
		SELECT COUNT(*) AS n FROM domains
		WHERE campaign_id = ? AND realm_title = 'Prince'
		  AND tribute_out_owed = 0
	""", [CAMPAIGN_ID])
	check(prince_zero == 1,
		"Prince tribute should be 0; got %d Prince rows at 0" % prince_zero)

	# Non-Prince on-map domains (Dukes, Counts) must have non-zero tribute.
	var on_map_non_prince_zero: int = _count("""
		SELECT COUNT(*) AS n FROM domains
		WHERE campaign_id = ? AND location_map_id IS NOT NULL
		  AND realm_title != 'Prince'
		  AND tribute_out_owed = 0
	""", [CAMPAIGN_ID])
	check(on_map_non_prince_zero == 0,
		"on-map non-Prince domains with tribute_out_owed == 0: expected 0, got %d" % on_map_non_prince_zero)

	print("  stock_rulers_and_tribute_end_to_end: OK")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_campaign_row() -> void:
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[CAMPAIGN_ID, "Stock Rulers Test"])


func _count(sql: String, params: Array) -> int:
	if not CampaignRepository.db.query_with_bindings(sql, params):
		return -1
	if CampaignRepository.db.query_result.is_empty():
		return 0
	return int(CampaignRepository.db.query_result[0].get("n", 0))


func _cleanup() -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM character_proficiencies WHERE character_id IN (SELECT id FROM characters WHERE campaign_id = ?)",
		[CAMPAIGN_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM character_powers WHERE character_id IN (SELECT id FROM characters WHERE campaign_id = ?)",
		[CAMPAIGN_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM characters WHERE campaign_id = ?", [CAMPAIGN_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM lairs WHERE campaign_id = ?", [CAMPAIGN_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM domain_hexes WHERE domain_id IN (SELECT id FROM domains WHERE campaign_id = ?)",
		[CAMPAIGN_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM domains WHERE campaign_id = ?", [CAMPAIGN_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM hex_river_edges WHERE map_id = ?", [MAP_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM hex_overlays WHERE map_id = ?", [MAP_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM dungeon_entrances WHERE campaign_id = ?", [CAMPAIGN_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM settlement_entrances WHERE campaign_id = ?", [CAMPAIGN_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM hex_cells WHERE map_id = ?", [MAP_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM hex_maps WHERE id = ?", [MAP_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [CAMPAIGN_ID])
