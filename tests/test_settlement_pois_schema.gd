extends "res://tests/test_suite_base.gd"

## Migration 126 schema tests for the Urban Growth Stocking substrate per
## `generation/gdd-urban-growth-stocking.md` §13.1 Stage A.
##
## Covers:
##   * settlement_pois CHECK constraints reject invalid inserts.
##   * INSERT / SELECT / UPDATE round-trip for each POI type.
##   * Tier-cache trigger flips religious_site to 'temple' when a completed
##     consecrated_altars row is inserted / updated with
##     location_kind='settlement_poi' and location_ref=<religious_site id>.
##   * Demotion trigger reverts to 'shrine' when the only completed altar is
##     broken; preserves 'temple' if another completed altar remains.
##   * strongholds.registered_settlement_poi_id column exists.
##   * characters.home_poi_id + npc_role columns exist with CHECK constraint
##     enforcement and indexes.
##   * settlement_poi_spell_offers CHECK constraints (count bounds, level
##     range, tradition enum) reject invalid rows.

const TEST_CAMPAIGN := "test_ugs_schema_campaign"
const TEST_MAP := "test_ugs_schema_map"
const TEST_SETTLEMENT := "test_ugs_schema_settlement"
const TEST_CHARACTER := "test_ugs_schema_character"


func run_all_tests() -> void:
	_cleanup()
	_setup_fixture()
	test_settlement_pois_table_exists()
	test_insert_religious_site_shrine()
	test_insert_workshop_with_specialist_kind()
	test_insert_port()
	test_check_invalid_type_rejected()
	test_check_invalid_tier_for_non_religious_site_rejected()
	test_check_emergent_builder_must_have_null_character_id()
	test_check_character_builder_must_have_character_id()
	test_check_l1_l2_adherent_count_non_negative_enforced()
	test_update_status_round_trip()
	test_trigger_promotes_shrine_to_temple_on_completed_altar_update()
	test_trigger_promotes_shrine_to_temple_on_completed_altar_insert()
	test_trigger_demotes_to_shrine_when_only_altar_broken()
	test_trigger_preserves_temple_when_another_altar_remains()
	test_strongholds_registered_settlement_poi_id_column_exists()
	test_characters_home_poi_id_column_exists()
	test_characters_npc_role_check_enforced()
	test_settlement_poi_spell_offers_round_trip()
	test_spell_offers_check_invalid_tradition_rejected()
	test_spell_offers_check_invalid_level_rejected()
	test_spell_offers_check_count_remaining_le_initial()
	_cleanup()
	if not has_failures():
		print("SettlementPoisSchema: all tests passed.")


# ---------------------------------------------------------------------------
# Fixture
# ---------------------------------------------------------------------------

func _setup_fixture() -> void:
	var db = CampaignRepository.db
	db.query_with_bindings("INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[TEST_CAMPAIGN, "UGS Schema"])
	db.query_with_bindings("""
		INSERT OR IGNORE INTO hex_maps (id, campaign_id, name, scale)
		VALUES (?, ?, ?, ?)
	""", [TEST_MAP, TEST_CAMPAIGN, "UGS Schema Map", "regional_6mi"])
	db.query_with_bindings("""
		INSERT OR IGNORE INTO settlement_entrances
			(id, campaign_id, map_id, hex_q, hex_r, name, market_class)
		VALUES (?, ?, ?, ?, ?, ?, ?)
	""", [TEST_SETTLEMENT, TEST_CAMPAIGN, TEST_MAP, 5, 5, "UGS Test Town", 4])
	db.query_with_bindings("""
		INSERT OR IGNORE INTO characters (id, campaign_id, name, character_class, level)
		VALUES (?, ?, ?, ?, ?)
	""", [TEST_CHARACTER, TEST_CAMPAIGN, "UGS Test Cleric", "cleric", 9])


func _cleanup() -> void:
	var db = CampaignRepository.db
	db.query_with_bindings(
		"DELETE FROM settlement_poi_spell_offers WHERE poi_id IN (SELECT id FROM settlement_pois WHERE settlement_id = ?)",
		[TEST_SETTLEMENT])
	db.query_with_bindings(
		"DELETE FROM consecrated_altars WHERE character_id = ?", [TEST_CHARACTER])
	db.query_with_bindings(
		"DELETE FROM settlement_pois WHERE settlement_id = ?", [TEST_SETTLEMENT])
	db.query_with_bindings(
		"DELETE FROM settlement_entrances WHERE id = ?", [TEST_SETTLEMENT])
	db.query_with_bindings(
		"DELETE FROM hex_maps WHERE id = ?", [TEST_MAP])
	db.query_with_bindings(
		"DELETE FROM characters WHERE id = ?", [TEST_CHARACTER])
	db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [TEST_CAMPAIGN])


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_settlement_pois_table_exists() -> void:
	var ok := CampaignRepository.db.query(
		"SELECT 1 FROM sqlite_master WHERE type='table' AND name='settlement_pois'")
	check(ok and not CampaignRepository.db.query_result.is_empty(),
		"settlement_pois table not present")


func test_insert_religious_site_shrine() -> void:
	var poi_id := "ugs_poi_shrine_1"
	var ok := CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_pois
			(id, settlement_id, type, tier, status, builder_kind,
			 emerged_via, established_at_calendar_day, gp_value,
			 l3_plus_npc_count, attached_religion)
		VALUES (?, ?, 'religious_site', 'shrine', 'active', 'emergent',
				'baseline_emergence', 100, 200, 1, 'lawful_silver_lady')
	""", [poi_id, TEST_SETTLEMENT])
	check(ok, "insert religious_site shrine should succeed")
	CampaignRepository.db.query_with_bindings(
		"SELECT tier, attached_religion FROM settlement_pois WHERE id = ?", [poi_id])
	check(not CampaignRepository.db.query_result.is_empty(), "shrine row should be readable")
	if not CampaignRepository.db.query_result.is_empty():
		var row: Dictionary = CampaignRepository.db.query_result[0]
		check(str(row.get("tier", "")) == "shrine", "tier should be 'shrine'")
		check(str(row.get("attached_religion", "")) == "lawful_silver_lady",
			"attached_religion preserved")


func test_insert_workshop_with_specialist_kind() -> void:
	var poi_id := "ugs_poi_workshop_1"
	var ok := CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_pois
			(id, settlement_id, type, status, builder_kind,
			 emerged_via, established_at_calendar_day, gp_value,
			 attached_specialist_kind)
		VALUES (?, ?, 'workshop', 'active', 'emergent',
				'baseline_emergence', 100, 500, 'alchemist')
	""", [poi_id, TEST_SETTLEMENT])
	check(ok, "insert workshop should succeed")


func test_insert_port() -> void:
	var poi_id := "ugs_poi_port_1"
	var ok := CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_pois
			(id, settlement_id, type, status, builder_kind,
			 emerged_via, established_at_calendar_day, gp_value)
		VALUES (?, ?, 'port', 'active', 'emergent',
				'baseline_emergence', 100, 600)
	""", [poi_id, TEST_SETTLEMENT])
	check(ok, "insert port should succeed")


func test_check_invalid_type_rejected() -> void:
	var ok := CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_pois
			(id, settlement_id, type, status, builder_kind,
			 emerged_via, established_at_calendar_day)
		VALUES ('ugs_poi_bad_type', ?, 'unknown_type', 'active', 'emergent',
				'baseline_emergence', 100)
	""", [TEST_SETTLEMENT])
	check(not ok, "invalid type CHECK constraint should reject")


func test_check_invalid_tier_for_non_religious_site_rejected() -> void:
	var ok := CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_pois
			(id, settlement_id, type, tier, status, builder_kind,
			 emerged_via, established_at_calendar_day)
		VALUES ('ugs_poi_bad_tier', ?, 'workshop', 'temple', 'active', 'emergent',
				'baseline_emergence', 100)
	""", [TEST_SETTLEMENT])
	check(not ok, "workshop with tier='temple' should be rejected by tier-invariant CHECK")


func test_check_emergent_builder_must_have_null_character_id() -> void:
	var ok := CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_pois
			(id, settlement_id, type, status, builder_kind, builder_character_id,
			 emerged_via, established_at_calendar_day)
		VALUES ('ugs_poi_bad_builder', ?, 'workshop', 'active', 'emergent', ?,
				'baseline_emergence', 100)
	""", [TEST_SETTLEMENT, TEST_CHARACTER])
	check(not ok,
		"emergent builder_kind with non-NULL builder_character_id should be rejected")


func test_check_character_builder_must_have_character_id() -> void:
	var ok := CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_pois
			(id, settlement_id, type, status, builder_kind,
			 emerged_via, established_at_calendar_day)
		VALUES ('ugs_poi_bad_char_builder', ?, 'workshop', 'active', 'character',
				'stronghold_register', 100)
	""", [TEST_SETTLEMENT])
	check(not ok,
		"character builder_kind with NULL builder_character_id should be rejected")


func test_check_l1_l2_adherent_count_non_negative_enforced() -> void:
	var ok := CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_pois
			(id, settlement_id, type, status, builder_kind,
			 emerged_via, established_at_calendar_day, l1_l2_adherent_count)
		VALUES ('ugs_poi_negative_adh', ?, 'workshop', 'active', 'emergent',
				'baseline_emergence', 100, -1)
	""", [TEST_SETTLEMENT])
	check(not ok, "negative l1_l2_adherent_count should be rejected")


func test_update_status_round_trip() -> void:
	var poi_id := "ugs_poi_status"
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_pois
			(id, settlement_id, type, status, builder_kind,
			 emerged_via, established_at_calendar_day)
		VALUES (?, ?, 'named_tavern', 'active', 'emergent',
				'baseline_emergence', 100)
	""", [poi_id, TEST_SETTLEMENT])
	var ok := CampaignRepository.db.query_with_bindings(
		"UPDATE settlement_pois SET status = 'dormant' WHERE id = ?", [poi_id])
	check(ok, "UPDATE status to 'dormant' should succeed")
	CampaignRepository.db.query_with_bindings(
		"SELECT status FROM settlement_pois WHERE id = ?", [poi_id])
	if not CampaignRepository.db.query_result.is_empty():
		check(String(CampaignRepository.db.query_result[0].get("status", "")) == "dormant",
			"status round-trip preserved 'dormant'")


# ---------------------------------------------------------------------------
# Tier-cache trigger tests
# ---------------------------------------------------------------------------

func test_trigger_promotes_shrine_to_temple_on_completed_altar_update() -> void:
	# Set up a shrine, then attach an in-progress altar and flip its status
	# to 'completed' via UPDATE — the AFTER UPDATE trigger should fire.
	var poi_id := "ugs_poi_promote_update"
	var altar_id := "ugs_altar_promote_update"
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_pois
			(id, settlement_id, type, tier, status, builder_kind,
			 emerged_via, established_at_calendar_day, attached_religion)
		VALUES (?, ?, 'religious_site', 'shrine', 'active', 'emergent',
				'baseline_emergence', 100, 'lawful_silver_lady')
	""", [poi_id, TEST_SETTLEMENT])
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO consecrated_altars
			(id, character_id, location_kind, location_ref, alignment, status, cp_invested)
		VALUES (?, ?, 'settlement_poi', ?, 'lawful', 'in_progress', 100000)
	""", [altar_id, TEST_CHARACTER, poi_id])
	# Trigger fires on UPDATE OF status.
	CampaignRepository.db.query_with_bindings(
		"UPDATE consecrated_altars SET status = 'completed' WHERE id = ?", [altar_id])
	CampaignRepository.db.query_with_bindings(
		"SELECT tier FROM settlement_pois WHERE id = ?", [poi_id])
	if not CampaignRepository.db.query_result.is_empty():
		check(String(CampaignRepository.db.query_result[0].get("tier", "")) == "temple",
			"shrine should promote to 'temple' after consecrated altar update")


func test_trigger_promotes_shrine_to_temple_on_completed_altar_insert() -> void:
	# Insert a religious_site shrine, then INSERT a row with status='completed'
	# directly — the AFTER INSERT trigger should fire.
	var poi_id := "ugs_poi_promote_insert"
	var altar_id := "ugs_altar_promote_insert"
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_pois
			(id, settlement_id, type, tier, status, builder_kind,
			 emerged_via, established_at_calendar_day, attached_religion)
		VALUES (?, ?, 'religious_site', 'shrine', 'active', 'emergent',
				'baseline_emergence', 100, 'lawful_silver_lady')
	""", [poi_id, TEST_SETTLEMENT])
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO consecrated_altars
			(id, character_id, location_kind, location_ref, alignment, status, cp_invested)
		VALUES (?, ?, 'settlement_poi', ?, 'lawful', 'completed', 100000)
	""", [altar_id, TEST_CHARACTER, poi_id])
	CampaignRepository.db.query_with_bindings(
		"SELECT tier FROM settlement_pois WHERE id = ?", [poi_id])
	if not CampaignRepository.db.query_result.is_empty():
		check(String(CampaignRepository.db.query_result[0].get("tier", "")) == "temple",
			"shrine should promote to 'temple' after completed altar insert")


func test_trigger_demotes_to_shrine_when_only_altar_broken() -> void:
	# Religious_site with one completed altar; break it. Should revert to shrine.
	var poi_id := "ugs_poi_demote"
	var altar_id := "ugs_altar_demote"
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_pois
			(id, settlement_id, type, tier, status, builder_kind,
			 emerged_via, established_at_calendar_day)
		VALUES (?, ?, 'religious_site', 'shrine', 'active', 'emergent',
				'baseline_emergence', 100)
	""", [poi_id, TEST_SETTLEMENT])
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO consecrated_altars
			(id, character_id, location_kind, location_ref, alignment, status, cp_invested)
		VALUES (?, ?, 'settlement_poi', ?, 'lawful', 'completed', 100000)
	""", [altar_id, TEST_CHARACTER, poi_id])
	# Now break it.
	CampaignRepository.db.query_with_bindings(
		"UPDATE consecrated_altars SET status = 'broken_unblessed' WHERE id = ?", [altar_id])
	CampaignRepository.db.query_with_bindings(
		"SELECT tier FROM settlement_pois WHERE id = ?", [poi_id])
	if not CampaignRepository.db.query_result.is_empty():
		check(String(CampaignRepository.db.query_result[0].get("tier", "")) == "shrine",
			"temple should demote to 'shrine' after only completed altar broken")


func test_trigger_preserves_temple_when_another_altar_remains() -> void:
	# Religious_site with two completed altars; break one. Should remain temple.
	var poi_id := "ugs_poi_preserve"
	var altar_a := "ugs_altar_preserve_a"
	var altar_b := "ugs_altar_preserve_b"
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_pois
			(id, settlement_id, type, tier, status, builder_kind,
			 emerged_via, established_at_calendar_day)
		VALUES (?, ?, 'religious_site', 'shrine', 'active', 'emergent',
				'baseline_emergence', 100)
	""", [poi_id, TEST_SETTLEMENT])
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO consecrated_altars
			(id, character_id, location_kind, location_ref, alignment, status, cp_invested)
		VALUES (?, ?, 'settlement_poi', ?, 'lawful', 'completed', 100000)
	""", [altar_a, TEST_CHARACTER, poi_id])
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO consecrated_altars
			(id, character_id, location_kind, location_ref, alignment, status, cp_invested)
		VALUES (?, ?, 'settlement_poi', ?, 'lawful', 'completed', 100000)
	""", [altar_b, TEST_CHARACTER, poi_id])
	# Break A; B remains completed.
	CampaignRepository.db.query_with_bindings(
		"UPDATE consecrated_altars SET status = 'broken_unblessed' WHERE id = ?", [altar_a])
	CampaignRepository.db.query_with_bindings(
		"SELECT tier FROM settlement_pois WHERE id = ?", [poi_id])
	if not CampaignRepository.db.query_result.is_empty():
		check(String(CampaignRepository.db.query_result[0].get("tier", "")) == "temple",
			"tier should remain 'temple' when another completed altar still attached")


# ---------------------------------------------------------------------------
# Cross-table column additions
# ---------------------------------------------------------------------------

func test_strongholds_registered_settlement_poi_id_column_exists() -> void:
	# pragma_table_info returns one row per column.
	var ok := CampaignRepository.db.query(
		"SELECT name FROM pragma_table_info('strongholds') WHERE name = 'registered_settlement_poi_id'")
	check(ok and not CampaignRepository.db.query_result.is_empty(),
		"strongholds.registered_settlement_poi_id column missing")


func test_characters_home_poi_id_column_exists() -> void:
	var ok := CampaignRepository.db.query(
		"SELECT name FROM pragma_table_info('characters') WHERE name = 'home_poi_id'")
	check(ok and not CampaignRepository.db.query_result.is_empty(),
		"characters.home_poi_id column missing")


func test_characters_npc_role_check_enforced() -> void:
	var bad_id := "ugs_test_bad_npc_role"
	var ok := CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, npc_role)
		VALUES (?, ?, ?, ?)
	""", [bad_id, TEST_CAMPAIGN, "Bad NPC Role", "not_a_valid_role"])
	check(not ok, "invalid npc_role value should be rejected by CHECK")
	# Clean up if it somehow inserted.
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM characters WHERE id = ?", [bad_id])


# ---------------------------------------------------------------------------
# settlement_poi_spell_offers
# ---------------------------------------------------------------------------

func test_settlement_poi_spell_offers_round_trip() -> void:
	var poi_id := "ugs_poi_offers_host"
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_pois
			(id, settlement_id, type, tier, status, builder_kind,
			 emerged_via, established_at_calendar_day, attached_religion)
		VALUES (?, ?, 'religious_site', 'shrine', 'active', 'emergent',
				'baseline_emergence', 100, 'lawful_silver_lady')
	""", [poi_id, TEST_SETTLEMENT])
	var ok := CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_poi_spell_offers
			(id, poi_id, calendar_day, tradition, spell_level,
			 count_initial, count_remaining, unit_cost_gp)
		VALUES (?, ?, ?, 'divine', 1, 5, 5, 10)
	""", ["ugs_offer_1", poi_id, 100])
	check(ok, "spell offer INSERT should succeed")
	CampaignRepository.db.query_with_bindings(
		"SELECT count_remaining FROM settlement_poi_spell_offers WHERE id = ?",
		["ugs_offer_1"])
	if not CampaignRepository.db.query_result.is_empty():
		check(int(CampaignRepository.db.query_result[0].get("count_remaining", -1)) == 5,
			"count_remaining round-trip")


func test_spell_offers_check_invalid_tradition_rejected() -> void:
	var poi_id := "ugs_poi_offers_host"  # already exists from prior test
	var ok := CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_poi_spell_offers
			(id, poi_id, calendar_day, tradition, spell_level,
			 count_initial, count_remaining, unit_cost_gp)
		VALUES (?, ?, ?, 'psionic', 1, 1, 1, 10)
	""", ["ugs_offer_bad_trad", poi_id, 100])
	check(not ok, "invalid tradition CHECK should reject")


func test_spell_offers_check_invalid_level_rejected() -> void:
	var poi_id := "ugs_poi_offers_host"
	var ok := CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_poi_spell_offers
			(id, poi_id, calendar_day, tradition, spell_level,
			 count_initial, count_remaining, unit_cost_gp)
		VALUES (?, ?, ?, 'arcane', 9, 1, 1, 10)
	""", ["ugs_offer_bad_level", poi_id, 100])
	check(not ok, "spell_level outside [1,6] should be rejected")


func test_spell_offers_check_count_remaining_le_initial() -> void:
	var poi_id := "ugs_poi_offers_host"
	var ok := CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_poi_spell_offers
			(id, poi_id, calendar_day, tradition, spell_level,
			 count_initial, count_remaining, unit_cost_gp)
		VALUES (?, ?, ?, 'divine', 1, 3, 5, 10)
	""", ["ugs_offer_bad_remaining", poi_id, 101])
	check(not ok,
		"count_remaining > count_initial should be rejected by CHECK")
