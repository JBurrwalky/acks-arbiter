extends "res://tests/test_suite_base.gd"

## PoiCleanup tests — Stage H per GDD §13.8 / Q-UGS-57 / Q-UGS-58 / Q-UGS-4.

const TEST_CAMPAIGN := "test_pcu_campaign"
const TEST_MAP := "test_pcu_map"
const TEST_DOMAIN := "test_pcu_domain"
const TEST_SETTLEMENT := "test_pcu_settle"
const TEST_PC := "test_pcu_pc"


func run_all_tests() -> void:
	_cleanup()
	_setup_fixture()
	test_party_departure_sweep_deletes_unretained_on_demand()
	test_party_departure_sweep_preserves_retained_henchman()
	test_party_departure_sweep_preserves_specialist_role()
	test_session_boundary_sweep_catches_all_on_demand()
	test_session_boundary_sweep_preserves_retained()
	test_spell_offers_retention_sweep_deletes_old()
	test_poi_is_abandoned_true_when_both_null()
	test_poi_is_abandoned_false_when_baseline_present()
	test_poi_is_abandoned_false_when_stocked_present()
	test_poi_is_abandoned_returns_false_for_unknown_poi()
	test_character_retention_helper_pc()
	test_character_retention_helper_employed()
	test_character_retention_helper_on_demand_alone()
	_cleanup()
	if not has_failures():
		print("PoiCleanup: all tests passed.")


# ---------------------------------------------------------------------------
# Fixture
# ---------------------------------------------------------------------------

func _setup_fixture() -> void:
	var db = CampaignRepository.db
	db.query_with_bindings("INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[TEST_CAMPAIGN, "PoiCleanup Test"])
	db.query_with_bindings("""
		INSERT OR IGNORE INTO hex_maps (id, campaign_id, name, scale)
		VALUES (?, ?, ?, ?)
	""", [TEST_MAP, TEST_CAMPAIGN, "Map", "regional_6mi"])
	db.query_with_bindings("""
		INSERT OR IGNORE INTO domains
			(id, campaign_id, name, peasant_families, religion, alignment)
		VALUES (?, ?, ?, ?, ?, ?)
	""", [TEST_DOMAIN, TEST_CAMPAIGN, "PCU Domain", 1000,
		"lawful_silver_lady", "lawful"])
	db.query_with_bindings("""
		INSERT OR IGNORE INTO settlement_entrances
			(id, campaign_id, map_id, hex_q, hex_r, name, market_class,
			 parent_domain_id, urban_families, cumulative_investment_gp)
		VALUES (?, ?, ?, 80, 80, 'PCU Town', 4, ?, 800, 75000)
	""", [TEST_SETTLEMENT, TEST_CAMPAIGN, TEST_MAP, TEST_DOMAIN])
	# A PC for retention tests.
	db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_type, character_class,
			 combat_progression, level, alignment, npc_role)
		VALUES (?, ?, 'PCU PC', 'pc', 'fighter', 'fighter', 5, 'lawful', 'player')
	""", [TEST_PC, TEST_CAMPAIGN])


func _cleanup() -> void:
	var db = CampaignRepository.db
	db.query_with_bindings("""
		DELETE FROM characters
		WHERE home_poi_id IN (SELECT id FROM settlement_pois WHERE settlement_id = ?)
		   OR id LIKE 'pcu_test_%'
	""", [TEST_SETTLEMENT])
	db.query_with_bindings("""
		DELETE FROM settlement_poi_spell_offers
		WHERE poi_id IN (SELECT id FROM settlement_pois WHERE settlement_id = ?)
		   OR poi_id LIKE 'pcu_p_%'
	""", [TEST_SETTLEMENT])
	db.query_with_bindings(
		"DELETE FROM settlement_pois WHERE settlement_id = ? OR id LIKE 'pcu_p_%'",
		[TEST_SETTLEMENT])
	db.query_with_bindings("DELETE FROM characters WHERE id = ?", [TEST_PC])
	db.query_with_bindings(
		"DELETE FROM settlement_entrances WHERE id = ?", [TEST_SETTLEMENT])
	db.query_with_bindings("DELETE FROM domains WHERE id = ?", [TEST_DOMAIN])
	db.query_with_bindings("DELETE FROM hex_maps WHERE id = ?", [TEST_MAP])
	db.query_with_bindings("DELETE FROM campaigns WHERE id = ?", [TEST_CAMPAIGN])


func _insert_poi(poi_id: String) -> void:
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_pois
			(id, settlement_id, type, tier, status, builder_kind,
			 emerged_via, established_at_calendar_day, gp_value,
			 l3_plus_npc_count, l1_l2_adherent_count,
			 attached_religion, attached_specialist_kind)
		VALUES (?, ?, 'religious_site', 'shrine', 'active', 'emergent',
				'class_advancement', 100, 1000, 0, 0, '', '')
	""", [poi_id, TEST_SETTLEMENT])


func _insert_on_demand_npc(character_id: String, home_poi_id: String) -> void:
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters
			(id, campaign_id, name, character_type, character_class,
			 combat_progression, level, alignment, home_poi_id, npc_role)
		VALUES (?, ?, 'OnDemand', 'npc', 'cleric', 'cleric', 1, 'lawful', ?, 'on_demand')
	""", [character_id, TEST_CAMPAIGN, home_poi_id])


func _character_exists(character_id: String) -> bool:
	CampaignRepository.db.query_with_bindings(
		"SELECT 1 FROM characters WHERE id = ?", [character_id])
	return not CampaignRepository.db.query_result.is_empty()


# ---------------------------------------------------------------------------
# party_departure_sweep
# ---------------------------------------------------------------------------

func test_party_departure_sweep_deletes_unretained_on_demand() -> void:
	_insert_poi("pcu_p_dep_a")
	var cid := "pcu_test_unretained"
	_insert_on_demand_npc(cid, "pcu_p_dep_a")
	var deleted := PoiCleanup.party_departure_sweep(TEST_SETTLEMENT)
	check(deleted >= 1, "should delete at least 1 unretained on_demand NPC; got %d" % deleted)
	check(not _character_exists(cid),
		"unretained on_demand NPC should be deleted from characters table")


func test_party_departure_sweep_preserves_retained_henchman() -> void:
	_insert_poi("pcu_p_dep_b")
	var cid := "pcu_test_retained_h"
	# Insert as on_demand, then upgrade to henchman to simulate retention.
	_insert_on_demand_npc(cid, "pcu_p_dep_b")
	CampaignRepository.db.query_with_bindings("""
		UPDATE characters
		SET character_type = 'henchman', npc_role = 'henchman',
		    employer_id = ?
		WHERE id = ?
	""", [TEST_PC, cid])
	# Now run the sweep — character_type='henchman' so retention helper
	# returns true; should NOT be deleted. BUT — the sweep only lists
	# characters where npc_role='on_demand', so changing role to 'henchman'
	# already removes them from the candidate list. The point of this test
	# is to confirm that retention DOES preserve. Let me reset the npc_role
	# back to 'on_demand' to make sure retention path is exercised.
	CampaignRepository.db.query_with_bindings(
		"UPDATE characters SET npc_role = 'on_demand' WHERE id = ?", [cid])
	# Now the candidate appears in on_demand list BUT character_type=henchman
	# and employer_id is set → retention helper says retained → sweep skips.
	PoiCleanup.party_departure_sweep(TEST_SETTLEMENT)
	check(_character_exists(cid),
		"on_demand NPC with character_type='henchman' should be preserved")


func test_party_departure_sweep_preserves_specialist_role() -> void:
	_insert_poi("pcu_p_dep_c")
	var cid := "pcu_test_specialist"
	# An on_demand NPC whose npc_role gets upgraded to 'specialist' but
	# the home_poi_id still points here — retention helper should preserve.
	_insert_on_demand_npc(cid, "pcu_p_dep_c")
	# Don't change npc_role, but DO set employer_id (retention via employer).
	CampaignRepository.db.query_with_bindings(
		"UPDATE characters SET employer_id = ? WHERE id = ?", [TEST_PC, cid])
	PoiCleanup.party_departure_sweep(TEST_SETTLEMENT)
	check(_character_exists(cid),
		"on_demand NPC with employer_id set should be preserved")


# ---------------------------------------------------------------------------
# session_boundary_sweep
# ---------------------------------------------------------------------------

func test_session_boundary_sweep_catches_all_on_demand() -> void:
	_insert_poi("pcu_p_sb_a")
	var cid1 := "pcu_test_sb_1"
	var cid2 := "pcu_test_sb_2"
	_insert_on_demand_npc(cid1, "pcu_p_sb_a")
	_insert_on_demand_npc(cid2, "pcu_p_sb_a")
	var deleted := PoiCleanup.session_boundary_sweep()
	check(deleted >= 2,
		"session-boundary sweep should delete both unretained on_demand; got %d" % deleted)
	check(not _character_exists(cid1) and not _character_exists(cid2),
		"both on_demand NPCs should be gone")


func test_session_boundary_sweep_preserves_retained() -> void:
	_insert_poi("pcu_p_sb_b")
	var cid := "pcu_test_sb_keep"
	_insert_on_demand_npc(cid, "pcu_p_sb_b")
	CampaignRepository.db.query_with_bindings(
		"UPDATE characters SET employer_id = ? WHERE id = ?", [TEST_PC, cid])
	PoiCleanup.session_boundary_sweep()
	check(_character_exists(cid),
		"retained on_demand NPC should survive session-boundary sweep")


# ---------------------------------------------------------------------------
# spell_offers_retention_sweep
# ---------------------------------------------------------------------------

func test_spell_offers_retention_sweep_deletes_old() -> void:
	_insert_poi("pcu_p_offers")
	# Insert offers on day 90 (old) and day 99 (recent). Today=100, retention=7.
	# Threshold = today - retention = 93. Day 90 < 93 → deleted; day 99 ≥ 93 → kept.
	for day in [90, 99]:
		CampaignRepository.db.query_with_bindings("""
			INSERT INTO settlement_poi_spell_offers
				(id, poi_id, calendar_day, tradition, spell_level,
				 count_initial, count_remaining, unit_cost_gp)
			VALUES (?, ?, ?, 'divine', 1, 1, 1, 10)
		""", ["pcu_offer_%d" % day, "pcu_p_offers", day])
	PoiCleanup.spell_offers_retention_sweep(100, 7)
	CampaignRepository.db.query_with_bindings(
		"SELECT calendar_day FROM settlement_poi_spell_offers WHERE poi_id = ?",
		["pcu_p_offers"])
	var remaining_days: Array = []
	for row in CampaignRepository.db.query_result:
		remaining_days.append(int(row.get("calendar_day", 0)))
	check(not (90 in remaining_days),
		"day 90 should be swept (old); remaining=%s" % str(remaining_days))
	check(99 in remaining_days,
		"day 99 should be preserved (within retention window); remaining=%s"
		% str(remaining_days))


# ---------------------------------------------------------------------------
# poi_is_abandoned predicate (Q-UGS-4)
# ---------------------------------------------------------------------------

func test_poi_is_abandoned_true_when_both_null() -> void:
	_insert_poi("pcu_p_abandoned")
	check(PoiCleanup.poi_is_abandoned("pcu_p_abandoned") == true,
		"freshly-inserted POI with no head/stocked should be abandoned")


func test_poi_is_abandoned_false_when_baseline_present() -> void:
	_insert_poi("pcu_p_with_baseline")
	# Insert a character + point the POI's baseline_head pointer at it.
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters
			(id, campaign_id, name, character_class, level, npc_role)
		VALUES ('pcu_test_baseline_h', ?, 'B', 'cleric', 1, 'baseline_placeholder')
	""", [TEST_CAMPAIGN])
	CampaignRepository.update_settlement_poi_baseline_head(
		"pcu_p_with_baseline", "pcu_test_baseline_h")
	check(PoiCleanup.poi_is_abandoned("pcu_p_with_baseline") == false,
		"POI with baseline head should NOT be abandoned")


func test_poi_is_abandoned_false_when_stocked_present() -> void:
	_insert_poi("pcu_p_with_stocked")
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters
			(id, campaign_id, name, character_class, level, npc_role)
		VALUES ('pcu_test_stocked', ?, 'S', 'cleric', 5, 'stocked')
	""", [TEST_CAMPAIGN])
	CampaignRepository.set_settlement_poi_stocked_character(
		"pcu_p_with_stocked", "pcu_test_stocked")
	check(PoiCleanup.poi_is_abandoned("pcu_p_with_stocked") == false,
		"POI with stocked character should NOT be abandoned")


func test_poi_is_abandoned_returns_false_for_unknown_poi() -> void:
	check(PoiCleanup.poi_is_abandoned("nonexistent_poi") == false,
		"unknown POI should return false (defensive default)")


# ---------------------------------------------------------------------------
# CharacterRetentionHelper
# ---------------------------------------------------------------------------

func test_character_retention_helper_pc() -> void:
	check(CharacterRetentionHelper.is_character_retained(TEST_PC) == true,
		"PC should always be retained")


func test_character_retention_helper_employed() -> void:
	# Create an on_demand NPC, then employ them.
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters
			(id, campaign_id, name, character_type, character_class,
			 combat_progression, level, alignment, npc_role, employer_id)
		VALUES ('pcu_test_employed', ?, 'E', 'npc', 'fighter',
				'fighter', 1, 'neutral', 'on_demand', ?)
	""", [TEST_CAMPAIGN, TEST_PC])
	check(CharacterRetentionHelper.is_character_retained("pcu_test_employed") == true,
		"on_demand NPC with employer_id should be retained")


func test_character_retention_helper_on_demand_alone() -> void:
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters
			(id, campaign_id, name, character_type, character_class,
			 combat_progression, level, alignment, npc_role)
		VALUES ('pcu_test_alone', ?, 'A', 'npc', 'fighter',
				'fighter', 1, 'neutral', 'on_demand')
	""", [TEST_CAMPAIGN])
	check(CharacterRetentionHelper.is_character_retained("pcu_test_alone") == false,
		"bare on_demand NPC with no retention signal should NOT be retained")
