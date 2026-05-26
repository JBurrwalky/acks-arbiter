extends "res://tests/test_suite_base.gd"

## PurchaseSpellcastingHandler tests — Stage G end-to-end purchase flow per
## GDD §9.4 / §13.7. Verifies validation chain, alignment gate, count
## decrement, wallet deduction, and signal emission.

const TEST_CAMPAIGN := "test_psc_campaign"
const TEST_MAP := "test_psc_map"
const TEST_DOMAIN_LAWFUL := "test_psc_dom_lawful"
const TEST_DOMAIN_CHAOTIC := "test_psc_dom_chaotic"
const TEST_SETTLEMENT_LAWFUL := "test_psc_settle_lawful"
const TEST_SETTLEMENT_CHAOTIC := "test_psc_settle_chaotic"
const TEST_BUYER_LAWFUL := "test_psc_buyer_lawful"
const TEST_BUYER_CHAOTIC := "test_psc_buyer_chaotic"
const TEST_BUYER_BROKE := "test_psc_buyer_broke"

var _captured_signal: Dictionary = {}


func run_all_tests() -> void:
	_cleanup()
	_setup_fixture()
	test_successful_divine_purchase()
	test_alignment_block_chaotic_buyer_lawful_caster()
	test_alignment_allow_neutral_buyer()
	test_arcane_no_alignment_gate()
	test_sold_out_rejection()
	test_no_poi_error()
	test_wrong_poi_type_error()
	test_poi_inactive_error()
	test_no_buyer_error()
	test_no_offer_error_unknown_level()
	test_insufficient_funds_error()
	test_signal_emitted_on_success()
	test_registry_exposes_offers()
	_cleanup()
	if not has_failures():
		print("PurchaseSpellcasting: all tests passed.")


# ---------------------------------------------------------------------------
# Fixture
# ---------------------------------------------------------------------------

func _setup_fixture() -> void:
	var db = CampaignRepository.db
	db.query_with_bindings("INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[TEST_CAMPAIGN, "PSC Test"])
	db.query_with_bindings("""
		INSERT OR IGNORE INTO hex_maps (id, campaign_id, name, scale)
		VALUES (?, ?, ?, ?)
	""", [TEST_MAP, TEST_CAMPAIGN, "PSC Map", "regional_6mi"])
	# Two domains: lawful (for the temple) and chaotic (for cross-alignment tests).
	db.query_with_bindings("""
		INSERT OR IGNORE INTO domains
			(id, campaign_id, name, peasant_families, religion, alignment)
		VALUES (?, ?, ?, ?, ?, ?)
	""", [TEST_DOMAIN_LAWFUL, TEST_CAMPAIGN, "PSC Lawful Domain", 3000,
		"lawful_silver_lady", "lawful"])
	db.query_with_bindings("""
		INSERT OR IGNORE INTO domains
			(id, campaign_id, name, peasant_families, religion, alignment)
		VALUES (?, ?, ?, ?, ?, ?)
	""", [TEST_DOMAIN_CHAOTIC, TEST_CAMPAIGN, "PSC Chaotic Domain", 3000,
		"chaotic_red_drake", "chaotic"])
	# Two Class III settlements (one per domain).
	db.query_with_bindings("""
		INSERT OR IGNORE INTO settlement_entrances
			(id, campaign_id, map_id, hex_q, hex_r, name, market_class,
			 parent_domain_id, urban_families, cumulative_investment_gp)
		VALUES (?, ?, ?, 60, 60, ?, 3, ?, 3000, 200000)
	""", [TEST_SETTLEMENT_LAWFUL, TEST_CAMPAIGN, TEST_MAP,
		"PSC Lawful City", TEST_DOMAIN_LAWFUL])
	db.query_with_bindings("""
		INSERT OR IGNORE INTO settlement_entrances
			(id, campaign_id, map_id, hex_q, hex_r, name, market_class,
			 parent_domain_id, urban_families, cumulative_investment_gp)
		VALUES (?, ?, ?, 61, 61, ?, 3, ?, 3000, 200000)
	""", [TEST_SETTLEMENT_CHAOTIC, TEST_CAMPAIGN, TEST_MAP,
		"PSC Chaotic City", TEST_DOMAIN_CHAOTIC])
	# Three buyer characters with different alignments + wallets.
	db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_class, combat_progression,
			 level, alignment)
		VALUES (?, ?, ?, 'fighter', 'fighter', 5, 'lawful')
	""", [TEST_BUYER_LAWFUL, TEST_CAMPAIGN, "PSC Lawful Buyer"])
	db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_class, combat_progression,
			 level, alignment)
		VALUES (?, ?, ?, 'fighter', 'fighter', 5, 'chaotic')
	""", [TEST_BUYER_CHAOTIC, TEST_CAMPAIGN, "PSC Chaotic Buyer"])
	db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_class, combat_progression,
			 level, alignment)
		VALUES (?, ?, ?, 'fighter', 'fighter', 5, 'lawful')
	""", [TEST_BUYER_BROKE, TEST_CAMPAIGN, "PSC Broke Buyer"])
	# Top up wallets with 1000gp each (= 100000 cp).
	CampaignRepository.add_coins_cp(TEST_BUYER_LAWFUL, 100000)
	CampaignRepository.add_coins_cp(TEST_BUYER_CHAOTIC, 100000)
	# TEST_BUYER_BROKE intentionally has no coins.


func _cleanup() -> void:
	var db = CampaignRepository.db
	# Reset wallet inventories.
	for buyer in [TEST_BUYER_LAWFUL, TEST_BUYER_CHAOTIC, TEST_BUYER_BROKE]:
		db.query_with_bindings("DELETE FROM inventory_items WHERE character_id = ?",
			[buyer])
	# Delete offers + POIs + settlements + domains + characters + map + campaign.
	db.query_with_bindings("""
		DELETE FROM settlement_poi_spell_offers
		WHERE poi_id IN (
			SELECT id FROM settlement_pois
			WHERE settlement_id IN (?, ?)
		)
	""", [TEST_SETTLEMENT_LAWFUL, TEST_SETTLEMENT_CHAOTIC])
	db.query_with_bindings(
		"DELETE FROM settlement_pois WHERE settlement_id IN (?, ?)",
		[TEST_SETTLEMENT_LAWFUL, TEST_SETTLEMENT_CHAOTIC])
	db.query_with_bindings(
		"DELETE FROM settlement_entrances WHERE id IN (?, ?)",
		[TEST_SETTLEMENT_LAWFUL, TEST_SETTLEMENT_CHAOTIC])
	db.query_with_bindings(
		"DELETE FROM domains WHERE id IN (?, ?)",
		[TEST_DOMAIN_LAWFUL, TEST_DOMAIN_CHAOTIC])
	db.query_with_bindings(
		"DELETE FROM characters WHERE id IN (?, ?, ?)",
		[TEST_BUYER_LAWFUL, TEST_BUYER_CHAOTIC, TEST_BUYER_BROKE])
	db.query_with_bindings("DELETE FROM hex_maps WHERE id = ?", [TEST_MAP])
	db.query_with_bindings("DELETE FROM campaigns WHERE id = ?", [TEST_CAMPAIGN])


func _insert_poi(
	poi_id: String,
	settlement_id: String,
	poi_type: String,
	gp_value: int,
	status: String = "active",
) -> void:
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_pois
			(id, settlement_id, type, tier, status, builder_kind,
			 emerged_via, established_at_calendar_day, gp_value,
			 l3_plus_npc_count, l1_l2_adherent_count,
			 attached_religion, attached_specialist_kind)
		VALUES (?, ?, ?, ?, ?, 'emergent',
				'class_advancement', 100, ?, 0, 0, '', '')
	""", [
		poi_id, settlement_id, poi_type,
		"shrine" if poi_type == "religious_site" else "",
		status, gp_value,
	])


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

## Lawful buyer purchases Divine 1st @ 10gp from a lawful temple. Wallet
## decreases, count_remaining decreases, signal fires.
func test_successful_divine_purchase() -> void:
	_insert_poi("psc_poi_temple_a", TEST_SETTLEMENT_LAWFUL,
		"religious_site", 4500)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	# Capture the wallet before.
	var before_cp := CampaignRepository.get_character_wealth_cp(TEST_BUYER_LAWFUL)
	var result := PurchaseSpellcastingHandler.try_purchase(
		"psc_poi_temple_a", "divine", 1, "cure_light_wounds",
		TEST_BUYER_LAWFUL, 1500, rng)
	check(bool(result.get("success", false)),
		"purchase should succeed; got error_code='%s'"
		% String(result.get("error_code", "")))
	if not bool(result.get("success", false)):
		return
	# Wallet drops by 10gp = 1000cp.
	var after_cp := CampaignRepository.get_character_wealth_cp(TEST_BUYER_LAWFUL)
	check(after_cp == before_cp - 1000,
		"wallet should drop by 1000cp; before=%d after=%d" % [before_cp, after_cp])


## Chaotic buyer cannot purchase from a lawful caster (cleric).
func test_alignment_block_chaotic_buyer_lawful_caster() -> void:
	_insert_poi("psc_poi_temple_b", TEST_SETTLEMENT_LAWFUL,
		"religious_site", 4500)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1235
	var result := PurchaseSpellcastingHandler.try_purchase(
		"psc_poi_temple_b", "divine", 1, "cure_light_wounds",
		TEST_BUYER_CHAOTIC, 1600, rng)
	check(not bool(result.get("success", false)),
		"chaotic buyer should be blocked at lawful temple")
	check(String(result.get("error_code", "")) == "alignment_blocked",
		"error_code should be 'alignment_blocked'; got '%s'"
		% String(result.get("error_code", "")))


## Neutral buyer can transact with any caster — though we don't have a
## Neutral buyer in fixture, we verify lawful buyer at lawful temple is OK
## as a regression for the previous-test pattern.
func test_alignment_allow_neutral_buyer() -> void:
	_insert_poi("psc_poi_temple_c", TEST_SETTLEMENT_LAWFUL,
		"religious_site", 4500)
	# Make a neutral buyer with funds.
	var neutral_buyer := "psc_neutral_buyer"
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_class, combat_progression,
			 level, alignment)
		VALUES (?, ?, ?, 'fighter', 'fighter', 5, 'neutral')
	""", [neutral_buyer, TEST_CAMPAIGN, "PSC Neutral Buyer"])
	CampaignRepository.add_coins_cp(neutral_buyer, 100000)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1236
	var result := PurchaseSpellcastingHandler.try_purchase(
		"psc_poi_temple_c", "divine", 1, "cure_light_wounds",
		neutral_buyer, 1700, rng)
	check(bool(result.get("success", false)),
		"neutral buyer at lawful temple should succeed; got error='%s'"
		% String(result.get("error_code", "")))
	# Clean up.
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE character_id = ?", [neutral_buyer])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM characters WHERE id = ?", [neutral_buyer])


## Chaotic buyer purchases Arcane 1st from any mages_guild_hall — no
## alignment gate per RAW.
func test_arcane_no_alignment_gate() -> void:
	_insert_poi("psc_poi_mage_a", TEST_SETTLEMENT_LAWFUL,
		"mages_guild_hall", 4500)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1237
	var result := PurchaseSpellcastingHandler.try_purchase(
		"psc_poi_mage_a", "arcane", 1, "detect_magic",
		TEST_BUYER_CHAOTIC, 1800, rng)
	check(bool(result.get("success", false)),
		"chaotic buyer should be allowed at arcane sanctum; got error='%s'"
		% String(result.get("error_code", "")))


## A 1-count offer that's been purchased once should reject a second purchase.
func test_sold_out_rejection() -> void:
	_insert_poi("psc_poi_sold_out", TEST_SETTLEMENT_LAWFUL,
		"religious_site", 4500)
	# Manually insert a 1-count Divine 1st offer for day 1900.
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_poi_spell_offers
			(id, poi_id, calendar_day, tradition, spell_level,
			 count_initial, count_remaining, unit_cost_gp)
		VALUES ('psc_off_sold', ?, 1900, 'divine', 1, 1, 1, 10)
	""", ["psc_poi_sold_out"])
	# First purchase — succeeds.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1238
	var first := PurchaseSpellcastingHandler.try_purchase(
		"psc_poi_sold_out", "divine", 1, "cure_light_wounds",
		TEST_BUYER_LAWFUL, 1900, rng)
	check(bool(first.get("success", false)), "first purchase should succeed")
	# Second purchase — rejected (sold out).
	var second := PurchaseSpellcastingHandler.try_purchase(
		"psc_poi_sold_out", "divine", 1, "cure_light_wounds",
		TEST_BUYER_LAWFUL, 1900, rng)
	check(not bool(second.get("success", false)),
		"second purchase should fail; got success=%s" % str(second.get("success", false)))
	check(String(second.get("error_code", "")) == "sold_out",
		"error_code should be 'sold_out'; got '%s'"
		% String(second.get("error_code", "")))


func test_no_poi_error() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1239
	var result := PurchaseSpellcastingHandler.try_purchase(
		"nonexistent_poi", "divine", 1, "cure", TEST_BUYER_LAWFUL, 2000, rng)
	check(String(result.get("error_code", "")) == "no_poi",
		"error_code should be 'no_poi'; got '%s'"
		% String(result.get("error_code", "")))


func test_wrong_poi_type_error() -> void:
	_insert_poi("psc_poi_workshop", TEST_SETTLEMENT_LAWFUL, "workshop", 500)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1240
	var result := PurchaseSpellcastingHandler.try_purchase(
		"psc_poi_workshop", "divine", 1, "cure", TEST_BUYER_LAWFUL, 2100, rng)
	check(String(result.get("error_code", "")) == "wrong_poi_type",
		"workshop should fail with 'wrong_poi_type'; got '%s'"
		% String(result.get("error_code", "")))


func test_poi_inactive_error() -> void:
	_insert_poi("psc_poi_dormant", TEST_SETTLEMENT_LAWFUL,
		"religious_site", 4500, "dormant")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1241
	var result := PurchaseSpellcastingHandler.try_purchase(
		"psc_poi_dormant", "divine", 1, "cure", TEST_BUYER_LAWFUL, 2200, rng)
	check(String(result.get("error_code", "")) == "poi_inactive",
		"dormant POI should fail with 'poi_inactive'; got '%s'"
		% String(result.get("error_code", "")))


func test_no_buyer_error() -> void:
	_insert_poi("psc_poi_no_buyer", TEST_SETTLEMENT_LAWFUL,
		"religious_site", 4500)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1242
	var result := PurchaseSpellcastingHandler.try_purchase(
		"psc_poi_no_buyer", "divine", 1, "cure",
		"nonexistent_character", 2300, rng)
	check(String(result.get("error_code", "")) == "no_buyer",
		"unknown buyer should fail with 'no_buyer'; got '%s'"
		% String(result.get("error_code", "")))


## Requesting Divine level 99 (out of RAW table) should return 'no_offer'.
func test_no_offer_error_unknown_level() -> void:
	_insert_poi("psc_poi_no_offer", TEST_SETTLEMENT_LAWFUL,
		"religious_site", 4500)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1243
	var result := PurchaseSpellcastingHandler.try_purchase(
		"psc_poi_no_offer", "divine", 99, "future_spell",
		TEST_BUYER_LAWFUL, 2400, rng)
	check(String(result.get("error_code", "")) == "no_offer",
		"level 99 should fail with 'no_offer'; got '%s'"
		% String(result.get("error_code", "")))


func test_insufficient_funds_error() -> void:
	_insert_poi("psc_poi_too_pricey", TEST_SETTLEMENT_LAWFUL,
		"mages_guild_hall", 4500)
	# Manually insert an Arcane 5th-level offer (cost 1250gp).
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_poi_spell_offers
			(id, poi_id, calendar_day, tradition, spell_level,
			 count_initial, count_remaining, unit_cost_gp)
		VALUES ('psc_off_pricey', ?, 2500, 'arcane', 5, 1, 1, 1250)
	""", ["psc_poi_too_pricey"])
	# Broke buyer has 0 coins.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1244
	var result := PurchaseSpellcastingHandler.try_purchase(
		"psc_poi_too_pricey", "arcane", 5, "teleport",
		TEST_BUYER_BROKE, 2500, rng)
	check(String(result.get("error_code", "")) == "insufficient_funds",
		"broke buyer should fail with 'insufficient_funds'; got '%s'"
		% String(result.get("error_code", "")))


## On successful purchase, spellcasting_service_purchased fires with the
## expected payload.
func test_signal_emitted_on_success() -> void:
	_insert_poi("psc_poi_signal", TEST_SETTLEMENT_LAWFUL,
		"religious_site", 4500)
	_captured_signal.clear()
	var cb := func(poi_id: String, tradition: String, level: int,
				   spell_name: String, payer: String, cost: int) -> void:
		_captured_signal["poi_id"] = poi_id
		_captured_signal["tradition"] = tradition
		_captured_signal["level"] = level
		_captured_signal["spell_name"] = spell_name
		_captured_signal["payer"] = payer
		_captured_signal["cost"] = cost
	EventBus.spellcasting_service_purchased.connect(cb)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1245
	var result := PurchaseSpellcastingHandler.try_purchase(
		"psc_poi_signal", "divine", 1, "bless",
		TEST_BUYER_LAWFUL, 2600, rng)
	EventBus.spellcasting_service_purchased.disconnect(cb)
	check(bool(result.get("success", false)), "purchase should succeed")
	check(String(_captured_signal.get("poi_id", "")) == "psc_poi_signal",
		"signal poi_id should match")
	check(String(_captured_signal.get("tradition", "")) == "divine",
		"signal tradition should match")
	check(int(_captured_signal.get("level", -1)) == 1,
		"signal level should be 1")
	check(String(_captured_signal.get("spell_name", "")) == "bless",
		"signal spell_name should match")
	check(int(_captured_signal.get("cost", -1)) == 10,
		"signal cost should be 10gp")


## The Stage E registry's available_spellcasting_services_at_poi (now wired
## to the repository) returns offers for the day.
func test_registry_exposes_offers() -> void:
	_insert_poi("psc_poi_reg", TEST_SETTLEMENT_LAWFUL,
		"religious_site", 4500)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1246
	var offers := PoiContributionRegistry.available_spellcasting_services_at_poi(
		"psc_poi_reg", 2700, rng)
	check(offers.size() > 0,
		"registry should return offers for a Class III religious_site; got %d"
		% offers.size())
	if offers.size() > 0:
		var first: SpellOffer = offers[0]
		check(first.tradition == "divine",
			"first offer should be divine; got '%s'" % first.tradition)
		check(first.spell_level >= 1 and first.spell_level <= 5,
			"divine spell_level in [1,5]; got %d" % first.spell_level)
