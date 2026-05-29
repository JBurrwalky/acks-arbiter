extends "res://tests/test_suite_base.gd"

## SpellOfferRepository tests — Stage G lazy daily-roll + per-POI split
## mechanic per GDD §8.5.2 / §8.5.5.

const TEST_CAMPAIGN := "test_sor_campaign"
const TEST_MAP := "test_sor_map"
const TEST_DOMAIN := "test_sor_domain"
const TEST_SETTLEMENT := "test_sor_settle"


func run_all_tests() -> void:
	_cleanup()
	_setup_fixture()
	test_lazy_roll_populates_offers_on_first_visit()
	test_same_day_revisit_idempotent()
	test_no_offers_when_no_spell_offering_pois()
	test_offers_split_proportional_by_gp_value()
	test_offers_distinct_across_traditions()
	test_decrement_offer_remaining()
	test_decrement_offer_to_zero_then_again()
	test_retention_sweep_deletes_old_rows()
	test_retention_sweep_preserves_recent_rows()
	test_list_active_offers_for_poi_filters_zero_remaining()
	test_daily_refresh_rolls_new_offers()
	_cleanup()
	if not has_failures():
		print("SpellOfferRepository: all tests passed.")


# ---------------------------------------------------------------------------
# Fixture
# ---------------------------------------------------------------------------

func _setup_fixture() -> void:
	var db = CampaignRepository.db
	db.query_with_bindings("INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[TEST_CAMPAIGN, "SOR Test"])
	db.query_with_bindings("""
		INSERT OR IGNORE INTO hex_maps (id, campaign_id, name, scale)
		VALUES (?, ?, ?, ?)
	""", [TEST_MAP, TEST_CAMPAIGN, "SOR Map", "regional_6mi"])
	db.query_with_bindings("""
		INSERT OR IGNORE INTO domains
			(id, campaign_id, name, peasant_families, religion, alignment)
		VALUES (?, ?, ?, ?, ?, ?)
	""", [TEST_DOMAIN, TEST_CAMPAIGN, "SOR Domain", 3000,
		"lawful_silver_lady", "lawful"])
	# Class III settlement (urban_families = 3000).
	db.query_with_bindings("""
		INSERT OR IGNORE INTO settlement_entrances
			(id, campaign_id, map_id, hex_q, hex_r, name, market_class,
			 parent_domain_id, urban_families, cumulative_investment_gp)
		VALUES (?, ?, ?, 50, 50, ?, 3, ?, 3000, 200000)
	""", [TEST_SETTLEMENT, TEST_CAMPAIGN, TEST_MAP,
		"SOR City", TEST_DOMAIN])


func _cleanup() -> void:
	var db = CampaignRepository.db
	db.query_with_bindings("""
		DELETE FROM settlement_poi_spell_offers
		WHERE poi_id IN (SELECT id FROM settlement_pois WHERE settlement_id = ?)
	""", [TEST_SETTLEMENT])
	db.query_with_bindings(
		"DELETE FROM settlement_pois WHERE settlement_id = ?", [TEST_SETTLEMENT])
	db.query_with_bindings(
		"DELETE FROM settlement_entrances WHERE id = ?", [TEST_SETTLEMENT])
	db.query_with_bindings("DELETE FROM domains WHERE id = ?", [TEST_DOMAIN])
	db.query_with_bindings("DELETE FROM hex_maps WHERE id = ?", [TEST_MAP])
	db.query_with_bindings("DELETE FROM campaigns WHERE id = ?", [TEST_CAMPAIGN])


func _reset_pois() -> void:
	CampaignRepository.db.query_with_bindings("""
		DELETE FROM settlement_poi_spell_offers
		WHERE poi_id IN (SELECT id FROM settlement_pois WHERE settlement_id = ?)
	""", [TEST_SETTLEMENT])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM settlement_pois WHERE settlement_id = ?", [TEST_SETTLEMENT])


func _insert_poi(
	poi_id: String,
	poi_type: String,
	gp_value: int,
	tier: String = "",
) -> void:
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_pois
			(id, settlement_id, type, tier, status, builder_kind,
			 emerged_via, established_at_calendar_day, gp_value,
			 l3_plus_npc_count, l1_l2_adherent_count,
			 attached_religion, attached_specialist_kind)
		VALUES (?, ?, ?, ?, 'active', 'emergent',
				'class_advancement', 100, ?, 0, 0, '', '')
	""", [
		poi_id, TEST_SETTLEMENT, poi_type,
		tier if poi_type == "religious_site" else "",
		gp_value,
	])


func _count_offer_rows_for_poi(poi_id: String, calendar_day: int) -> int:
	CampaignRepository.db.query_with_bindings("""
		SELECT COUNT(*) AS c FROM settlement_poi_spell_offers
		WHERE poi_id = ? AND calendar_day = ?
	""", [poi_id, calendar_day])
	if CampaignRepository.db.query_result.is_empty():
		return 0
	return int(CampaignRepository.db.query_result[0].get("c", 0))


func _sum_count_initial_for_settlement(calendar_day: int, tradition: String) -> int:
	CampaignRepository.db.query_with_bindings("""
		SELECT COALESCE(SUM(o.count_initial), 0) AS total
		FROM settlement_poi_spell_offers o
		JOIN settlement_pois p ON o.poi_id = p.id
		WHERE p.settlement_id = ?
		  AND o.calendar_day = ?
		  AND o.tradition = ?
	""", [TEST_SETTLEMENT, calendar_day, tradition])
	if CampaignRepository.db.query_result.is_empty():
		return 0
	return int(CampaignRepository.db.query_result[0].get("total", 0))


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

## First visit on day 100 rolls offers for the settlement; subsequent reads
## see populated rows.
func test_lazy_roll_populates_offers_on_first_visit() -> void:
	_reset_pois()
	_insert_poi("sor_poi_temple", "religious_site", 3000, "shrine")
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	SpellOfferRepository.ensure_offers_for_settlement(TEST_SETTLEMENT, 100, rng)
	var count := _count_offer_rows_for_poi("sor_poi_temple", 100)
	check(count > 0,
		"first visit should populate offer rows; got %d" % count)


## Re-calling ensure_offers on the same day should NOT add duplicate rows.
func test_same_day_revisit_idempotent() -> void:
	_reset_pois()
	_insert_poi("sor_poi_temple", "religious_site", 3000, "shrine")
	var rng1 := RandomNumberGenerator.new()
	rng1.seed = 22
	SpellOfferRepository.ensure_offers_for_settlement(TEST_SETTLEMENT, 200, rng1)
	var first_count := _count_offer_rows_for_poi("sor_poi_temple", 200)
	# Second call same day must NOT re-roll.
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 33  # different seed — would produce different rolls if it ran
	SpellOfferRepository.ensure_offers_for_settlement(TEST_SETTLEMENT, 200, rng2)
	var second_count := _count_offer_rows_for_poi("sor_poi_temple", 200)
	check(first_count == second_count,
		"same-day re-visit must be idempotent; %d → %d" % [first_count, second_count])


## A settlement with no religious_sites or mages_guild_halls produces no
## offer rows.
func test_no_offers_when_no_spell_offering_pois() -> void:
	_reset_pois()
	# Only a workshop — no divine or arcane POIs.
	_insert_poi("sor_poi_w", "workshop", 500)
	var rng := RandomNumberGenerator.new()
	rng.seed = 44
	var rows := SpellOfferRepository.ensure_offers_for_settlement(
		TEST_SETTLEMENT, 300, rng)
	check(rows.size() == 0,
		"settlement with no spell-offering POIs should have no offers; got %d rows"
		% rows.size())


## Two religious_sites with different gp_values should split divine rolls
## proportionally — bigger temple gets more castings.
func test_offers_split_proportional_by_gp_value() -> void:
	_reset_pois()
	_insert_poi("sor_poi_big", "religious_site", 9000, "shrine")
	_insert_poi("sor_poi_small", "religious_site", 3000, "shrine")
	var rng := RandomNumberGenerator.new()
	rng.seed = 55
	SpellOfferRepository.ensure_offers_for_settlement(TEST_SETTLEMENT, 400, rng)
	# Sum the count_initial for divine spells across both POIs and confirm
	# big > small (proportional split).
	CampaignRepository.db.query_with_bindings("""
		SELECT poi_id, SUM(count_initial) AS total
		FROM settlement_poi_spell_offers
		WHERE poi_id IN ('sor_poi_big', 'sor_poi_small')
		  AND calendar_day = 400
		  AND tradition = 'divine'
		GROUP BY poi_id
	""", [])
	var big_total: int = 0
	var small_total: int = 0
	for row in CampaignRepository.db.query_result:
		if str(row.get("poi_id", "")) == "sor_poi_big":
			big_total = int(row.get("total", 0))
		else:
			small_total = int(row.get("total", 0))
	check(big_total >= small_total,
		"big temple (9000gp) should receive >= small temple (3000gp); big=%d small=%d"
		% [big_total, small_total])
	check(big_total > 0 and small_total > 0,
		"both temples should receive at least 1 casting (min-1 floor); big=%d small=%d"
		% [big_total, small_total])


## Divine and arcane offers are split independently — a religious_site
## should never receive arcane offers, a mages_guild_hall should never
## receive divine offers.
func test_offers_distinct_across_traditions() -> void:
	_reset_pois()
	_insert_poi("sor_poi_temple_x", "religious_site", 3000, "shrine")
	_insert_poi("sor_poi_mage_x", "mages_guild_hall", 1500)
	var rng := RandomNumberGenerator.new()
	rng.seed = 66
	SpellOfferRepository.ensure_offers_for_settlement(TEST_SETTLEMENT, 500, rng)
	# Verify no arcane rows at the temple.
	CampaignRepository.db.query_with_bindings("""
		SELECT COUNT(*) AS c FROM settlement_poi_spell_offers
		WHERE poi_id = 'sor_poi_temple_x' AND tradition = 'arcane'
	""", [])
	var temple_arcane: int = int(
		CampaignRepository.db.query_result[0].get("c", 0))
	check(temple_arcane == 0,
		"religious_site should never have arcane offers; got %d" % temple_arcane)
	# Verify no divine rows at the sanctum.
	CampaignRepository.db.query_with_bindings("""
		SELECT COUNT(*) AS c FROM settlement_poi_spell_offers
		WHERE poi_id = 'sor_poi_mage_x' AND tradition = 'divine'
	""", [])
	var mage_divine: int = int(
		CampaignRepository.db.query_result[0].get("c", 0))
	check(mage_divine == 0,
		"mages_guild_hall should never have divine offers; got %d" % mage_divine)


## decrement_offer_remaining decrements by 1 and returns true.
func test_decrement_offer_remaining() -> void:
	_reset_pois()
	_insert_poi("sor_poi_dec", "religious_site", 3000, "shrine")
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	SpellOfferRepository.ensure_offers_for_settlement(TEST_SETTLEMENT, 600, rng)
	# Get any offer row.
	CampaignRepository.db.query_with_bindings("""
		SELECT id, count_remaining FROM settlement_poi_spell_offers
		WHERE poi_id = 'sor_poi_dec' AND calendar_day = 600
		LIMIT 1
	""", [])
	if CampaignRepository.db.query_result.is_empty():
		check(false, "expected at least one offer row")
		return
	var offer_id: String = String(CampaignRepository.db.query_result[0].get("id", ""))
	var before: int = int(CampaignRepository.db.query_result[0].get("count_remaining", 0))
	check(SpellOfferRepository.decrement_offer_remaining(offer_id),
		"decrement should succeed")
	CampaignRepository.db.query_with_bindings(
		"SELECT count_remaining FROM settlement_poi_spell_offers WHERE id = ?",
		[offer_id])
	var after: int = int(
		CampaignRepository.db.query_result[0].get("count_remaining", 0))
	check(after == before - 1,
		"count_remaining should drop by 1; %d → %d" % [before, after])


## Decrementing an offer to 0 and then again should fail (CHECK constraint).
func test_decrement_offer_to_zero_then_again() -> void:
	_reset_pois()
	_insert_poi("sor_poi_zero", "religious_site", 3000, "shrine")
	# Direct INSERT a 1-count offer so we can deterministically test.
	var offer_id: String = "sor_offer_zero_1"
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_poi_spell_offers
			(id, poi_id, calendar_day, tradition, spell_level,
			 count_initial, count_remaining, unit_cost_gp)
		VALUES (?, ?, ?, 'divine', 1, 1, 1, 10)
	""", [offer_id, "sor_poi_zero", 700])
	# First decrement to 0 — succeeds.
	SpellOfferRepository.decrement_offer_remaining(offer_id)
	# Verify count_remaining is now 0.
	CampaignRepository.db.query_with_bindings(
		"SELECT count_remaining FROM settlement_poi_spell_offers WHERE id = ?",
		[offer_id])
	var after_first: int = int(
		CampaignRepository.db.query_result[0].get("count_remaining", 0))
	check(after_first == 0,
		"first decrement should land at 0; got %d" % after_first)
	# Second decrement — the UPDATE WHERE count_remaining > 0 clause means
	# no rows change. The decrement function returns true because the row
	# still exists, but count_remaining stays at 0.
	SpellOfferRepository.decrement_offer_remaining(offer_id)
	CampaignRepository.db.query_with_bindings(
		"SELECT count_remaining FROM settlement_poi_spell_offers WHERE id = ?",
		[offer_id])
	var after_second: int = int(
		CampaignRepository.db.query_result[0].get("count_remaining", 0))
	check(after_second == 0,
		"second decrement of a 0-count offer should NOT go negative; got %d"
		% after_second)


## retention_sweep deletes rows older than today - retention_days.
func test_retention_sweep_deletes_old_rows() -> void:
	_reset_pois()
	_insert_poi("sor_poi_ret", "religious_site", 3000, "shrine")
	# Insert offers on days 50, 90, 95.
	for day in [50, 90, 95]:
		CampaignRepository.db.query_with_bindings("""
			INSERT INTO settlement_poi_spell_offers
				(id, poi_id, calendar_day, tradition, spell_level,
				 count_initial, count_remaining, unit_cost_gp)
			VALUES (?, ?, ?, 'divine', 1, 1, 1, 10)
		""", ["sor_offer_ret_%d" % day, "sor_poi_ret", day])
	# Today is day 100; retention is 7 days, so threshold = 93. Days 50 and
	# 90 should be deleted; day 95 preserved.
	SpellOfferRepository.retention_sweep(100, 7)
	CampaignRepository.db.query_with_bindings(
		"SELECT calendar_day FROM settlement_poi_spell_offers WHERE poi_id = 'sor_poi_ret' ORDER BY calendar_day",
		[])
	var remaining_days: Array = []
	for row in CampaignRepository.db.query_result:
		remaining_days.append(int(row.get("calendar_day", 0)))
	check(not (50 in remaining_days),
		"day 50 should be swept; remaining=%s" % str(remaining_days))
	check(not (90 in remaining_days),
		"day 90 should be swept; remaining=%s" % str(remaining_days))
	check(95 in remaining_days,
		"day 95 should be preserved; remaining=%s" % str(remaining_days))


## Day-equal-to-threshold and same-day rows are preserved.
func test_retention_sweep_preserves_recent_rows() -> void:
	_reset_pois()
	_insert_poi("sor_poi_recent", "religious_site", 3000, "shrine")
	# Today=200, retention=7, threshold=193. Days 193, 195, 200 all preserved.
	for day in [193, 195, 200]:
		CampaignRepository.db.query_with_bindings("""
			INSERT INTO settlement_poi_spell_offers
				(id, poi_id, calendar_day, tradition, spell_level,
				 count_initial, count_remaining, unit_cost_gp)
			VALUES (?, ?, ?, 'divine', 1, 1, 1, 10)
		""", ["sor_offer_recent_%d" % day, "sor_poi_recent", day])
	SpellOfferRepository.retention_sweep(200, 7)
	CampaignRepository.db.query_with_bindings(
		"SELECT COUNT(*) AS c FROM settlement_poi_spell_offers WHERE poi_id = 'sor_poi_recent'",
		[])
	var remaining: int = int(
		CampaignRepository.db.query_result[0].get("c", 0))
	check(remaining == 3,
		"three recent-day rows should be preserved; got %d" % remaining)


## list_active_offers_for_poi filters out zero-count offers.
func test_list_active_offers_for_poi_filters_zero_remaining() -> void:
	_reset_pois()
	_insert_poi("sor_poi_filter", "religious_site", 3000, "shrine")
	# Insert a non-zero offer + a zero-count offer.
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_poi_spell_offers
			(id, poi_id, calendar_day, tradition, spell_level,
			 count_initial, count_remaining, unit_cost_gp)
		VALUES ('sor_off_nz', ?, 800, 'divine', 1, 5, 5, 10)
	""", ["sor_poi_filter"])
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_poi_spell_offers
			(id, poi_id, calendar_day, tradition, spell_level,
			 count_initial, count_remaining, unit_cost_gp)
		VALUES ('sor_off_zero', ?, 800, 'divine', 2, 3, 0, 40)
	""", ["sor_poi_filter"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 88
	# Call with calendar_day=800 — should NOT re-roll because rows exist.
	var offers := SpellOfferRepository.list_active_offers_for_poi(
		"sor_poi_filter", 800, rng)
	# Should return exactly 1 offer (the non-zero one).
	check(offers.size() == 1,
		"only non-zero offers should appear; got %d" % offers.size())
	if offers.size() == 1:
		var o: SpellOffer = offers[0]
		check(o.spell_level == 1, "should be the divine 1st offer; got level %d"
			% o.spell_level)


## A new calendar_day triggers a fresh roll. Sum of count_initial may
## differ between days since rolls are random.
func test_daily_refresh_rolls_new_offers() -> void:
	_reset_pois()
	_insert_poi("sor_poi_daily", "religious_site", 3000, "shrine")
	var rng1 := RandomNumberGenerator.new()
	rng1.seed = 100
	SpellOfferRepository.ensure_offers_for_settlement(TEST_SETTLEMENT, 1000, rng1)
	var day1_count := _count_offer_rows_for_poi("sor_poi_daily", 1000)
	# Day 1001 — fresh roll.
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 200
	SpellOfferRepository.ensure_offers_for_settlement(TEST_SETTLEMENT, 1001, rng2)
	var day2_count := _count_offer_rows_for_poi("sor_poi_daily", 1001)
	check(day1_count > 0 and day2_count > 0,
		"both days should have offer rows; day1=%d day2=%d"
		% [day1_count, day2_count])
	# Both days should have rows (the row count is per-(level) so may match
	# coincidentally — the key invariant is that day 1001 has its OWN rows).
	CampaignRepository.db.query_with_bindings("""
		SELECT COUNT(DISTINCT calendar_day) AS days
		FROM settlement_poi_spell_offers
		WHERE poi_id = 'sor_poi_daily'
	""", [])
	var days_seen: int = int(
		CampaignRepository.db.query_result[0].get("days", 0))
	check(days_seen == 2,
		"two distinct calendar_days should appear in the table; got %d"
		% days_seen)
