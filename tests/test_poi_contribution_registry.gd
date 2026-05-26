extends "res://tests/test_suite_base.gd"

## PoiContributionRegistry tests — Stage E per GDD §13.5 + §8.3 / §8.4.
##
## Each test seeds a fresh campaign + realm + map + domain + settlement,
## inserts the POIs / altars the scenario needs, and queries the registry
## directly.

const TEST_CAMPAIGN := "test_pcr_campaign"
const TEST_REALM := "test_pcr_realm"
const TEST_REALM_OTHER := "test_pcr_realm_other"
const TEST_MAP := "test_pcr_map"
const TEST_DOMAIN := "test_pcr_domain"
const TEST_DOMAIN_OTHER := "test_pcr_domain_other"
const TEST_SETTLEMENT := "test_pcr_settle"
const TEST_SETTLEMENT_OTHER := "test_pcr_settle_other"
const TEST_CHARACTER := "test_pcr_character"


func run_all_tests() -> void:
	_cleanup()
	_setup_fixture()
	test_empty_domain_returns_zero()
	test_temple_plus_altar_sum()
	test_shrine_and_temple_both_count()
	test_wrong_religion_returns_zero()
	test_dormant_poi_excluded()
	test_specialist_workshop_alchemist()
	test_specialist_mercenary_officer_captain()
	test_specialist_mariner_navigator()
	test_specialist_tavern_ruffian()
	test_specialist_unknown_kind_returns_false()
	test_specialist_armorer_returns_false_no_poi()
	test_mages_guild_hall_count_for_realm()
	test_mages_guild_hall_excludes_other_realm()
	test_tavern_count_for_settlement()
	test_poi_factional_alignment_default_empty()
	test_mercenary_guild_halls_for_domain()
	test_available_spellcasting_services_returns_offers()
	test_alignment_gate_lawful_caster()
	test_alignment_gate_neutral_accepts_all()
	test_alignment_gate_chaotic_caster()
	_cleanup()
	if not has_failures():
		print("PoiContributionRegistry: all tests passed.")


# ---------------------------------------------------------------------------
# Fixture
# ---------------------------------------------------------------------------

func _setup_fixture() -> void:
	var db = CampaignRepository.db
	db.query_with_bindings("INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[TEST_CAMPAIGN, "PCR Test"])
	# Two realms — the test domain belongs to TEST_REALM; TEST_REALM_OTHER
	# is used to confirm cross-realm isolation.
	db.query_with_bindings("""
		INSERT OR IGNORE INTO realms (id, campaign_id, name, realm_kind)
		VALUES (?, ?, ?, 'tracked')
	""", [TEST_REALM, TEST_CAMPAIGN, "PCR Realm"])
	db.query_with_bindings("""
		INSERT OR IGNORE INTO realms (id, campaign_id, name, realm_kind)
		VALUES (?, ?, ?, 'tracked')
	""", [TEST_REALM_OTHER, TEST_CAMPAIGN, "PCR Realm Other"])
	db.query_with_bindings("""
		INSERT OR IGNORE INTO hex_maps (id, campaign_id, name, scale)
		VALUES (?, ?, ?, ?)
	""", [TEST_MAP, TEST_CAMPAIGN, "PCR Map", "regional_6mi"])
	db.query_with_bindings("""
		INSERT OR IGNORE INTO domains
			(id, campaign_id, name, peasant_families, religion, alignment, realm_id)
		VALUES (?, ?, ?, ?, ?, ?, ?)
	""", [TEST_DOMAIN, TEST_CAMPAIGN, "PCR Domain", 1000,
		"lawful_silver_lady", "lawful", TEST_REALM])
	db.query_with_bindings("""
		INSERT OR IGNORE INTO domains
			(id, campaign_id, name, peasant_families, religion, alignment, realm_id)
		VALUES (?, ?, ?, ?, ?, ?, ?)
	""", [TEST_DOMAIN_OTHER, TEST_CAMPAIGN, "PCR Domain Other", 800,
		"chaotic_red_drake", "chaotic", TEST_REALM_OTHER])
	db.query_with_bindings("""
		INSERT OR IGNORE INTO settlement_entrances
			(id, campaign_id, map_id, hex_q, hex_r, name, market_class,
			 parent_domain_id, urban_families, cumulative_investment_gp)
		VALUES (?, ?, ?, 30, 30, ?, 4, ?, 1000, 75000)
	""", [TEST_SETTLEMENT, TEST_CAMPAIGN, TEST_MAP,
		"PCR Town", TEST_DOMAIN])
	db.query_with_bindings("""
		INSERT OR IGNORE INTO settlement_entrances
			(id, campaign_id, map_id, hex_q, hex_r, name, market_class,
			 parent_domain_id, urban_families, cumulative_investment_gp)
		VALUES (?, ?, ?, 31, 31, ?, 4, ?, 1000, 75000)
	""", [TEST_SETTLEMENT_OTHER, TEST_CAMPAIGN, TEST_MAP,
		"PCR Other Town", TEST_DOMAIN_OTHER])
	# A character to use as the consecrated_altars FK target.
	db.query_with_bindings("""
		INSERT OR IGNORE INTO characters (id, campaign_id, name, character_class, level)
		VALUES (?, ?, ?, 'cleric', 9)
	""", [TEST_CHARACTER, TEST_CAMPAIGN, "PCR Cleric"])


func _cleanup() -> void:
	var db = CampaignRepository.db
	db.query_with_bindings(
		"DELETE FROM consecrated_altars WHERE character_id = ?", [TEST_CHARACTER])
	db.query_with_bindings("""
		DELETE FROM characters WHERE home_poi_id IN (
			SELECT id FROM settlement_pois WHERE settlement_id IN (?, ?)
		)
	""", [TEST_SETTLEMENT, TEST_SETTLEMENT_OTHER])
	db.query_with_bindings(
		"DELETE FROM settlement_pois WHERE settlement_id IN (?, ?)",
		[TEST_SETTLEMENT, TEST_SETTLEMENT_OTHER])
	db.query_with_bindings(
		"DELETE FROM settlement_entrances WHERE id IN (?, ?)",
		[TEST_SETTLEMENT, TEST_SETTLEMENT_OTHER])
	db.query_with_bindings(
		"DELETE FROM domains WHERE id IN (?, ?)",
		[TEST_DOMAIN, TEST_DOMAIN_OTHER])
	db.query_with_bindings(
		"DELETE FROM realms WHERE id IN (?, ?)",
		[TEST_REALM, TEST_REALM_OTHER])
	db.query_with_bindings(
		"DELETE FROM hex_maps WHERE id = ?", [TEST_MAP])
	db.query_with_bindings(
		"DELETE FROM characters WHERE id = ?", [TEST_CHARACTER])
	db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [TEST_CAMPAIGN])


func _reset_pois_for(settlement_id: String) -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM consecrated_altars WHERE character_id = ?", [TEST_CHARACTER])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM settlement_pois WHERE settlement_id = ?", [settlement_id])


func _insert_poi(
	poi_id: String,
	settlement_id: String,
	poi_type: String,
	gp_value: int,
	attached_religion: String = "",
	attached_specialist_kind: String = "",
	status: String = "active",
	tier: String = "",
) -> void:
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_pois
			(id, settlement_id, type, tier, status, builder_kind,
			 emerged_via, established_at_calendar_day, gp_value,
			 l3_plus_npc_count, l1_l2_adherent_count,
			 attached_religion, attached_specialist_kind)
		VALUES (?, ?, ?, ?, ?, 'emergent',
				'class_advancement', 100, ?, 0, 0, ?, ?)
	""", [
		poi_id, settlement_id, poi_type,
		tier if poi_type == "religious_site" else "",
		status,
		gp_value,
		attached_religion,
		attached_specialist_kind,
	])


func _insert_altar(
	altar_id: String,
	poi_id: String,
	cp_invested: int,
	status: String = "completed",
) -> void:
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO consecrated_altars
			(id, character_id, location_kind, location_ref, alignment,
			 status, cp_invested)
		VALUES (?, ?, 'settlement_poi', ?, 'lawful', ?, ?)
	""", [altar_id, TEST_CHARACTER, poi_id, status, cp_invested])


# ---------------------------------------------------------------------------
# §8.3.1 religious_structures_gp_value_for_domain
# ---------------------------------------------------------------------------

func test_empty_domain_returns_zero() -> void:
	_reset_pois_for(TEST_SETTLEMENT)
	var result := PoiContributionRegistry.religious_structures_gp_value_for_domain(
		TEST_DOMAIN, "lawful_silver_lady")
	check(result == 0,
		"empty domain should return 0; got %d" % result)


func test_temple_plus_altar_sum() -> void:
	_reset_pois_for(TEST_SETTLEMENT)
	# Temple gp_value=3000, attached altar cp_invested=200000 (= 2000gp).
	_insert_poi("pcr_poi_temple_1", TEST_SETTLEMENT, "religious_site",
		3000, "lawful_silver_lady", "", "active", "shrine")
	_insert_altar("pcr_altar_1", "pcr_poi_temple_1", 200000)
	var result := PoiContributionRegistry.religious_structures_gp_value_for_domain(
		TEST_DOMAIN, "lawful_silver_lady")
	check(result == 5000,
		"temple gp_value (3000) + altar gp_invested (2000) should sum to 5000; got %d"
		% result)


func test_shrine_and_temple_both_count() -> void:
	_reset_pois_for(TEST_SETTLEMENT)
	_insert_poi("pcr_poi_t", TEST_SETTLEMENT, "religious_site",
		3000, "lawful_silver_lady", "", "active", "shrine")
	_insert_poi("pcr_poi_s", TEST_SETTLEMENT, "religious_site",
		300, "lawful_silver_lady", "", "active", "shrine")
	var result := PoiContributionRegistry.religious_structures_gp_value_for_domain(
		TEST_DOMAIN, "lawful_silver_lady")
	check(result == 3300,
		"temple (3000) + shrine (300) should sum to 3300; got %d" % result)


func test_wrong_religion_returns_zero() -> void:
	_reset_pois_for(TEST_SETTLEMENT)
	_insert_poi("pcr_poi_other", TEST_SETTLEMENT, "religious_site",
		3000, "lawful_silver_lady", "", "active", "shrine")
	var result := PoiContributionRegistry.religious_structures_gp_value_for_domain(
		TEST_DOMAIN, "chaotic_red_drake")
	check(result == 0,
		"wrong religion should return 0; got %d" % result)


func test_dormant_poi_excluded() -> void:
	_reset_pois_for(TEST_SETTLEMENT)
	_insert_poi("pcr_poi_dormant", TEST_SETTLEMENT, "religious_site",
		3000, "lawful_silver_lady", "", "dormant", "shrine")
	var result := PoiContributionRegistry.religious_structures_gp_value_for_domain(
		TEST_DOMAIN, "lawful_silver_lady")
	check(result == 0,
		"dormant POI should be excluded; got %d" % result)


# ---------------------------------------------------------------------------
# §8.3.2 specialist_availability_for_settlement
# ---------------------------------------------------------------------------

func test_specialist_workshop_alchemist() -> void:
	_reset_pois_for(TEST_SETTLEMENT)
	_insert_poi("pcr_poi_alchem", TEST_SETTLEMENT, "workshop",
		500, "", "alchemist")
	check(PoiContributionRegistry.specialist_availability_for_settlement(
		TEST_SETTLEMENT, "alchemist") == true,
		"alchemist workshop should be available")
	check(PoiContributionRegistry.specialist_availability_for_settlement(
		TEST_SETTLEMENT, "healer_general") == false,
		"healer_general should NOT be available (no matching workshop)")


func test_specialist_mercenary_officer_captain() -> void:
	_reset_pois_for(TEST_SETTLEMENT)
	_insert_poi("pcr_poi_merc", TEST_SETTLEMENT, "mercenary_guild_hall", 800)
	check(PoiContributionRegistry.specialist_availability_for_settlement(
		TEST_SETTLEMENT, "mercenary_officer_captain") == true,
		"mercenary_officer_captain should be available via mercenary_guild_hall")
	check(PoiContributionRegistry.specialist_availability_for_settlement(
		TEST_SETTLEMENT, "siege_engineer") == true,
		"siege_engineer should be available via mercenary_guild_hall")


func test_specialist_mariner_navigator() -> void:
	_reset_pois_for(TEST_SETTLEMENT)
	_insert_poi("pcr_poi_port", TEST_SETTLEMENT, "port", 600)
	check(PoiContributionRegistry.specialist_availability_for_settlement(
		TEST_SETTLEMENT, "mariner_navigator") == true,
		"mariner_navigator should be available via port")
	check(PoiContributionRegistry.specialist_availability_for_settlement(
		TEST_SETTLEMENT, "mariner_captain") == true,
		"mariner_captain should be available via port")


func test_specialist_tavern_ruffian() -> void:
	_reset_pois_for(TEST_SETTLEMENT)
	_insert_poi("pcr_poi_tavern", TEST_SETTLEMENT, "named_tavern", 300)
	check(PoiContributionRegistry.specialist_availability_for_settlement(
		TEST_SETTLEMENT, "ruffian_thug") == true,
		"ruffian_thug should be available via named_tavern")
	check(PoiContributionRegistry.specialist_availability_for_settlement(
		TEST_SETTLEMENT, "ruffian_spy") == true,
		"ruffian_spy should be available via named_tavern")


func test_specialist_unknown_kind_returns_false() -> void:
	_reset_pois_for(TEST_SETTLEMENT)
	_insert_poi("pcr_poi_w", TEST_SETTLEMENT, "workshop", 500, "", "alchemist")
	check(PoiContributionRegistry.specialist_availability_for_settlement(
		TEST_SETTLEMENT, "not_a_real_specialist_kind") == false,
		"unknown kind should return false")


func test_specialist_armorer_returns_false_no_poi() -> void:
	_reset_pois_for(TEST_SETTLEMENT)
	# Armorer and Engineer are management-notebook-only per GDD §4.2; no
	# POI surface, so the registry returns false.
	_insert_poi("pcr_poi_misc", TEST_SETTLEMENT, "workshop", 500, "", "alchemist")
	check(PoiContributionRegistry.specialist_availability_for_settlement(
		TEST_SETTLEMENT, "armorer") == false,
		"armorer should return false (notebook-only)")
	check(PoiContributionRegistry.specialist_availability_for_settlement(
		TEST_SETTLEMENT, "engineer") == false,
		"engineer should return false (notebook-only)")


# ---------------------------------------------------------------------------
# §8.3.4 mages_guild_hall_count_for_realm
# ---------------------------------------------------------------------------

func test_mages_guild_hall_count_for_realm() -> void:
	_reset_pois_for(TEST_SETTLEMENT)
	_reset_pois_for(TEST_SETTLEMENT_OTHER)
	_insert_poi("pcr_poi_mage1", TEST_SETTLEMENT, "mages_guild_hall", 1500)
	_insert_poi("pcr_poi_mage2", TEST_SETTLEMENT, "mages_guild_hall", 1500)
	var result := PoiContributionRegistry.mages_guild_hall_count_for_realm(TEST_REALM)
	check(result == 2,
		"realm should have 2 mages_guild_halls; got %d" % result)


func test_mages_guild_hall_excludes_other_realm() -> void:
	_reset_pois_for(TEST_SETTLEMENT)
	_reset_pois_for(TEST_SETTLEMENT_OTHER)
	_insert_poi("pcr_poi_mage_a", TEST_SETTLEMENT, "mages_guild_hall", 1500)
	_insert_poi("pcr_poi_mage_b", TEST_SETTLEMENT_OTHER, "mages_guild_hall", 1500)
	var result_a := PoiContributionRegistry.mages_guild_hall_count_for_realm(TEST_REALM)
	check(result_a == 1,
		"realm A should have 1 mages_guild_hall; got %d" % result_a)
	var result_b := PoiContributionRegistry.mages_guild_hall_count_for_realm(TEST_REALM_OTHER)
	check(result_b == 1,
		"realm B should have 1 mages_guild_hall; got %d" % result_b)


# ---------------------------------------------------------------------------
# §8.4 forward-compat stubs
# ---------------------------------------------------------------------------

func test_tavern_count_for_settlement() -> void:
	_reset_pois_for(TEST_SETTLEMENT)
	_insert_poi("pcr_poi_tav1", TEST_SETTLEMENT, "named_tavern", 300)
	_insert_poi("pcr_poi_tav2", TEST_SETTLEMENT, "named_tavern", 300)
	_insert_poi("pcr_poi_tav3", TEST_SETTLEMENT, "named_tavern", 300, "", "", "dormant")
	var result := PoiContributionRegistry.tavern_count_for_settlement(TEST_SETTLEMENT)
	check(result == 2,
		"only active named_tavern POIs should count; got %d (expected 2)" % result)


func test_poi_factional_alignment_default_empty() -> void:
	_reset_pois_for(TEST_SETTLEMENT)
	_insert_poi("pcr_poi_fa", TEST_SETTLEMENT, "named_tavern", 300)
	var result := PoiContributionRegistry.poi_factional_alignment("pcr_poi_fa")
	check(result == "",
		"v1 POIs have NULL owner_faction_id → empty string; got '%s'" % result)


func test_mercenary_guild_halls_for_domain() -> void:
	_reset_pois_for(TEST_SETTLEMENT)
	_insert_poi("pcr_poi_mg1", TEST_SETTLEMENT, "mercenary_guild_hall", 800)
	_insert_poi("pcr_poi_mg2", TEST_SETTLEMENT, "mercenary_guild_hall", 800)
	var result := PoiContributionRegistry.mercenary_guild_halls_for_domain(TEST_DOMAIN)
	check(result == 2,
		"domain should have 2 mercenary_guild_halls; got %d" % result)


# ---------------------------------------------------------------------------
# §8.5.2 stub (Stage G fleshes out)
# ---------------------------------------------------------------------------

## Stage G fleshed out this contract: a Class IV religious_site should
## return at least one divine offer for the day. (Stage E originally
## stubbed this to return empty; Stage G wired it through the repository.)
func test_available_spellcasting_services_returns_offers() -> void:
	_reset_pois_for(TEST_SETTLEMENT)
	_insert_poi("pcr_poi_temple_s", TEST_SETTLEMENT, "religious_site",
		3000, "lawful_silver_lady", "", "active", "temple")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5050
	var offers := PoiContributionRegistry.available_spellcasting_services_at_poi(
		"pcr_poi_temple_s", 1, rng)
	check(offers.size() > 0,
		"Stage G should return offers for an active religious_site; got %d"
		% offers.size())


# ---------------------------------------------------------------------------
# §8.5.3 alignment gate
# ---------------------------------------------------------------------------

func test_alignment_gate_lawful_caster() -> void:
	check(PoiContributionRegistry.divine_alignment_gate_allows("lawful", "lawful") == true,
		"L+L should allow")
	check(PoiContributionRegistry.divine_alignment_gate_allows("neutral", "lawful") == true,
		"N+L should allow")
	check(PoiContributionRegistry.divine_alignment_gate_allows("chaotic", "lawful") == false,
		"C+L should REJECT")


func test_alignment_gate_neutral_accepts_all() -> void:
	for buyer in ["lawful", "neutral", "chaotic"]:
		check(PoiContributionRegistry.divine_alignment_gate_allows(buyer, "neutral") == true,
			"buyer=%s + neutral caster should allow" % buyer)


func test_alignment_gate_chaotic_caster() -> void:
	check(PoiContributionRegistry.divine_alignment_gate_allows("lawful", "chaotic") == false,
		"L+C should REJECT")
	check(PoiContributionRegistry.divine_alignment_gate_allows("neutral", "chaotic") == true,
		"N+C should allow")
	check(PoiContributionRegistry.divine_alignment_gate_allows("chaotic", "chaotic") == true,
		"C+C should allow")
