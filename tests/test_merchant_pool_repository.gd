extends "res://tests/test_suite_base.gd"

## Unit tests for MerchantPoolRepository — pool generation, visibility,
## solicit/locate, consume/expire mechanics per Prereq.4.
##
## Per generation/gdd-settlement-economy.md §7.12.

var _campaign_id: String = ""
var _map_id: String = ""
var _suffix: int = 0


func run_all_tests() -> void:
	_setup()
	# Constants + accessors
	test_max_merchant_count_table()
	test_toll_dice_for_class_table()

	# Generation
	test_generate_pool_pc_owned_visible()
	test_generate_pool_non_pc_invisible()
	test_generate_pool_count_matches_class()
	test_generate_wipes_previous_active_rows()
	test_generate_preserves_manual_rows()
	test_generate_emits_signal()
	test_merchandise_distribution_covers_registry()

	# Visibility-aware reads
	test_list_visible_filters_correctly()
	test_list_visible_for_merchandise_filters()
	test_list_invisible_filters_correctly()

	# Consume loads
	test_consume_loads_decrement()
	test_consume_loads_depletion_and_signal()
	test_consume_loads_insufficient()

	# Expirations
	test_process_expirations_deletes_overdue()
	test_process_expirations_emits_signal()

	# Solicit
	test_solicitation_staggered_reveal_class_iii()
	test_solicitation_rejects_when_already_visible()
	test_solicitation_small_pool_class_vi()

	# Locate
	test_locate_finds_visible_match()
	test_locate_surfaces_invisible_match()
	test_locate_fails_when_no_match()

	# Campaign-wide refresh + pc_owned detection
	test_monthly_refresh_pc_owned_detection()

	# Phase 10B.2 Wave 1 substrate amendments (§4.8 + §11.7 + §0.1.1)
	test_refused_filter_excludes_from_list_visible()
	test_refused_filter_excludes_from_list_visible_for_merchandise()
	test_refused_filter_excludes_from_list_invisible()
	test_promoted_row_preserved_through_monthly_refresh()
	test_promoted_row_loads_refreshed_in_place()
	test_promoted_row_skipped_by_process_expirations()
	test_promoted_refused_flag_cleared_on_monthly_refresh()
	test_cohort_cap_counts_promoted_rows()

	if not has_failures():
		print("MerchantPoolRepository: all %d tests passed." % test_count())


func _setup() -> void:
	_campaign_id = CampaignRepository.create_campaign("MerchantPoolRepositoryTests", "World")
	_map_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO hex_maps (id, campaign_id, name, scale) VALUES (?, ?, ?, 'regional_6mi')",
		[_map_id, _campaign_id, "MPRPMap"]
	)


func _next_id() -> String:
	_suffix += 1
	return "mpr_%d_%d" % [Time.get_ticks_msec(), _suffix]


func _make_settlement(market_class: int, name: String = "Town", parent_domain_id = null) -> String:
	var id: String = _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_entrances
			(id, campaign_id, map_id, hex_q, hex_r, name, market_class, parent_domain_id)
		VALUES (?, ?, ?, ?, 0, ?, ?, ?)
	""", [id, _campaign_id, _map_id, _suffix, name, market_class, parent_domain_id])
	return id


func _seeded_rng(seed_val: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	return rng


# ---------------------------------------------------------------------------
# Constants + accessors
# ---------------------------------------------------------------------------

func test_max_merchant_count_table() -> void:
	check(MerchantPoolRepository.max_merchant_count(1) == 14, "Class I max = 14 (2d6+2)")
	check(MerchantPoolRepository.max_merchant_count(2) == 9, "Class II max = 9 (2d4+1)")
	check(MerchantPoolRepository.max_merchant_count(3) == 8, "Class III max = 8 (2d4)")
	check(MerchantPoolRepository.max_merchant_count(4) == 4, "Class IV max = 4 (1d4)")
	check(MerchantPoolRepository.max_merchant_count(5) == 3, "Class V max = 3 (1d4-1)")
	check(MerchantPoolRepository.max_merchant_count(6) == 2, "Class VI max = 2 (1d3-1)")
	check(MerchantPoolRepository.max_merchant_count(0) == 0, "out-of-range → 0")


func test_toll_dice_for_class_table() -> void:
	check(MerchantPoolRepository.toll_dice_for_class(1) == "1d6+15", "Class I toll = 1d6+15")
	check(MerchantPoolRepository.toll_dice_for_class(2) == "1d10+10", "Class II toll = 1d10+10")
	check(MerchantPoolRepository.toll_dice_for_class(3) == "1d8+5", "Class III toll = 1d8+5")
	check(MerchantPoolRepository.toll_dice_for_class(4) == "1d6+3", "Class IV toll = 1d6+3")
	check(MerchantPoolRepository.toll_dice_for_class(5) == "1d6", "Class V toll = 1d6")
	check(MerchantPoolRepository.toll_dice_for_class(6) == "1d3", "Class VI toll = 1d3")


# ---------------------------------------------------------------------------
# Generation
# ---------------------------------------------------------------------------

func test_generate_pool_pc_owned_visible() -> void:
	var s: String = _make_settlement(3, "PCOwned")
	var rng: RandomNumberGenerator = _seeded_rng(1)
	var count: int = MerchantPoolRepository.generate_pool_for_settlement(s, 100, rng, true)
	check(count == 8, "Class III pc_owned should generate 8 merchants, got %d" % count)
	# All should have becomes_visible_calendar_day = 100 (immediately visible).
	CampaignRepository.db.query_with_bindings("""
		SELECT COUNT(*) AS n FROM merchant_pool
		WHERE settlement_entrance_id = ? AND becomes_visible_calendar_day = 100
	""", [s])
	check(int(CampaignRepository.db.query_result[0].get("n", 0)) == 8,
		"all 8 merchants should be immediately visible at day 100 for pc_owned")


func test_generate_pool_non_pc_invisible() -> void:
	var s: String = _make_settlement(3, "NPCOwned")
	var rng: RandomNumberGenerator = _seeded_rng(2)
	var count: int = MerchantPoolRepository.generate_pool_for_settlement(s, 100, rng, false)
	check(count == 8, "Class III non-pc should still generate 8 merchants")
	# All should have becomes_visible_calendar_day = INVISIBLE_SENTINEL.
	CampaignRepository.db.query_with_bindings("""
		SELECT COUNT(*) AS n FROM merchant_pool
		WHERE settlement_entrance_id = ? AND becomes_visible_calendar_day = ?
	""", [s, MerchantPoolRepository.INVISIBLE_SENTINEL])
	check(int(CampaignRepository.db.query_result[0].get("n", 0)) == 8,
		"all 8 merchants should be invisible for non-pc-owned")


func test_generate_pool_count_matches_class() -> void:
	# Class I → 14, Class VI → 2.
	var s1: String = _make_settlement(1, "ClassI")
	var c1: int = MerchantPoolRepository.generate_pool_for_settlement(s1, 0, _seeded_rng(1), false)
	check(c1 == 14, "Class I → 14 merchants, got %d" % c1)
	var s6: String = _make_settlement(6, "ClassVI")
	var c6: int = MerchantPoolRepository.generate_pool_for_settlement(s6, 0, _seeded_rng(1), false)
	check(c6 == 2, "Class VI → 2 merchants, got %d" % c6)


func test_generate_wipes_previous_active_rows() -> void:
	var s: String = _make_settlement(3, "WipeTest")
	# First generation.
	MerchantPoolRepository.generate_pool_for_settlement(s, 0, _seeded_rng(1), false)
	CampaignRepository.db.query_with_bindings(
		"SELECT id FROM merchant_pool WHERE settlement_entrance_id = ?", [s])
	var first_ids: Array = []
	for row in CampaignRepository.db.query_result:
		first_ids.append(str((row as Dictionary).get("id", "")))
	check(first_ids.size() == 8, "first gen produces 8 rows")
	# Second generation.
	MerchantPoolRepository.generate_pool_for_settlement(s, 28, _seeded_rng(2), false)
	CampaignRepository.db.query_with_bindings(
		"SELECT id FROM merchant_pool WHERE settlement_entrance_id = ?", [s])
	var second_ids: Array = []
	for row in CampaignRepository.db.query_result:
		second_ids.append(str((row as Dictionary).get("id", "")))
	check(second_ids.size() == 8, "second gen produces 8 rows")
	# No overlap — first cohort was wiped.
	for fid in first_ids:
		check(not second_ids.has(fid), "first-cohort id %s should not survive second gen" % fid)


func test_generate_preserves_manual_rows() -> void:
	var s: String = _make_settlement(3, "ManualPreserve")
	# Insert a manual row.
	var manual_id: String = _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO merchant_pool
			(id, campaign_id, settlement_entrance_id, merchandise_type,
			 loads_available, loads_initial,
			 created_at_calendar_day, expires_at_calendar_day,
			 becomes_visible_calendar_day, status, source_kind)
		VALUES (?, ?, ?, 'silk', 10, 10, 0, 999, 0, 'active', 'manual')
	""", [manual_id, _campaign_id, s])
	# Generate.
	MerchantPoolRepository.generate_pool_for_settlement(s, 0, _seeded_rng(1), false)
	# Manual row should still exist.
	CampaignRepository.db.query_with_bindings(
		"SELECT id FROM merchant_pool WHERE id = ?", [manual_id])
	check(not CampaignRepository.db.query_result.is_empty(),
		"manual row should survive generation")
	# Total rows for the settlement = 8 (monthly_refresh) + 1 (manual) = 9.
	CampaignRepository.db.query_with_bindings(
		"SELECT COUNT(*) AS n FROM merchant_pool WHERE settlement_entrance_id = ?", [s])
	check(int(CampaignRepository.db.query_result[0].get("n", 0)) == 9,
		"total rows should be 8 generated + 1 manual = 9")


func test_generate_emits_signal() -> void:
	var s: String = _make_settlement(4, "SignalSettlement")
	var received := {"emitted": false, "sid": "", "count": -1}
	var cb: Callable = func(sid: String, count: int) -> void:
		received["emitted"] = true
		received["sid"] = sid
		received["count"] = count
	EventBus.merchant_pool_refreshed.connect(cb)
	MerchantPoolRepository.generate_pool_for_settlement(s, 0, _seeded_rng(1), false)
	EventBus.merchant_pool_refreshed.disconnect(cb)
	check(bool(received["emitted"]), "merchant_pool_refreshed should emit on generation")
	check(str(received["sid"]) == s, "signal sid matches")
	check(int(received["count"]) == 4, "signal count = 4 for Class IV")


func test_merchandise_distribution_covers_registry() -> void:
	# Generate many Class I pools (~14 merchants each); over many runs, every
	# merchandise type should appear at least once (probabilistically — the
	# uniform d100 distribution covers all 31 types).
	var seen_types: Dictionary = {}
	for trial in range(20):
		var s: String = _make_settlement(1, "Dist%d" % trial)
		MerchantPoolRepository.generate_pool_for_settlement(s, 0, _seeded_rng(trial + 1), false)
		CampaignRepository.db.query_with_bindings(
			"SELECT merchandise_type FROM merchant_pool WHERE settlement_entrance_id = ?", [s])
		for row in CampaignRepository.db.query_result:
			seen_types[str((row as Dictionary).get("merchandise_type", ""))] = true
	# Sanity: we should have seen at least 10 distinct types across 20 × 14 = 280 merchants.
	check(seen_types.size() >= 10,
		"merchandise distribution should sample many types over 280 merchants, got %d distinct" % seen_types.size())


# ---------------------------------------------------------------------------
# Visibility-aware reads
# ---------------------------------------------------------------------------

func test_list_visible_filters_correctly() -> void:
	var s: String = _make_settlement(3, "ListVisible")
	# Mixed pool: 4 visible (day 50), 4 invisible (INT_MAX).
	for i in range(4):
		var mid: String = _next_id()
		CampaignRepository.db.query_with_bindings("""
			INSERT INTO merchant_pool
				(id, campaign_id, settlement_entrance_id, merchandise_type,
				 loads_available, loads_initial, created_at_calendar_day,
				 expires_at_calendar_day, becomes_visible_calendar_day, status, source_kind)
			VALUES (?, ?, ?, 'salt', 5, 5, 0, 999, 50, 'active', 'monthly_refresh')
		""", [mid, _campaign_id, s])
	for i in range(4):
		var mid: String = _next_id()
		CampaignRepository.db.query_with_bindings("""
			INSERT INTO merchant_pool
				(id, campaign_id, settlement_entrance_id, merchandise_type,
				 loads_available, loads_initial, created_at_calendar_day,
				 expires_at_calendar_day, becomes_visible_calendar_day, status, source_kind)
			VALUES (?, ?, ?, 'silk', 5, 5, 0, 999, ?, 'active', 'monthly_refresh')
		""", [mid, _campaign_id, s, MerchantPoolRepository.INVISIBLE_SENTINEL])
	# At day 100 (after visibility day 50): list_visible returns 4.
	check(MerchantPoolRepository.list_visible_merchants(s, 100).size() == 4,
		"list_visible at day 100 should return 4")
	# At day 30 (before visibility day 50): list_visible returns 0 (the visible-day-50 merchants aren't yet visible).
	check(MerchantPoolRepository.list_visible_merchants(s, 30).size() == 0,
		"list_visible at day 30 (before visibility day 50) should return 0")
	# list_invisible at day 100: still 4 (the INT_MAX ones).
	check(MerchantPoolRepository.list_invisible_merchants(s, 100).size() == 4,
		"list_invisible at day 100 should return 4 (the sentinel ones)")


func test_list_visible_for_merchandise_filters() -> void:
	var s: String = _make_settlement(3, "ListByMerch")
	for tup in [["salt", 50], ["silk", 50], ["salt", 50], ["spices", 100]]:
		var mid: String = _next_id()
		CampaignRepository.db.query_with_bindings("""
			INSERT INTO merchant_pool
				(id, campaign_id, settlement_entrance_id, merchandise_type,
				 loads_available, loads_initial, created_at_calendar_day,
				 expires_at_calendar_day, becomes_visible_calendar_day, status, source_kind)
			VALUES (?, ?, ?, ?, 5, 5, 0, 999, ?, 'active', 'monthly_refresh')
		""", [mid, _campaign_id, s, tup[0], tup[1]])
	# At day 75: salt (2) + silk (1) visible; spices (1) not yet.
	check(MerchantPoolRepository.list_visible_merchants_for_merchandise(s, "salt", 75).size() == 2,
		"2 salt merchants visible at day 75")
	check(MerchantPoolRepository.list_visible_merchants_for_merchandise(s, "silk", 75).size() == 1,
		"1 silk merchant visible at day 75")
	check(MerchantPoolRepository.list_visible_merchants_for_merchandise(s, "spices", 75).size() == 0,
		"0 spices merchants visible at day 75 (visible at 100)")
	# At day 150: all visible.
	check(MerchantPoolRepository.list_visible_merchants_for_merchandise(s, "spices", 150).size() == 1,
		"1 spices merchant visible at day 150")


func test_list_invisible_filters_correctly() -> void:
	var s: String = _make_settlement(3, "ListInvis")
	# 3 invisible + 2 visible.
	for _i in range(3):
		var mid: String = _next_id()
		CampaignRepository.db.query_with_bindings("""
			INSERT INTO merchant_pool
				(id, campaign_id, settlement_entrance_id, merchandise_type,
				 loads_available, loads_initial, created_at_calendar_day,
				 expires_at_calendar_day, becomes_visible_calendar_day, status, source_kind)
			VALUES (?, ?, ?, 'wood_common', 5, 5, 0, 999, ?, 'active', 'monthly_refresh')
		""", [mid, _campaign_id, s, MerchantPoolRepository.INVISIBLE_SENTINEL])
	for _i in range(2):
		var mid: String = _next_id()
		CampaignRepository.db.query_with_bindings("""
			INSERT INTO merchant_pool
				(id, campaign_id, settlement_entrance_id, merchandise_type,
				 loads_available, loads_initial, created_at_calendar_day,
				 expires_at_calendar_day, becomes_visible_calendar_day, status, source_kind)
			VALUES (?, ?, ?, 'salt', 5, 5, 0, 999, 0, 'active', 'monthly_refresh')
		""", [mid, _campaign_id, s])
	check(MerchantPoolRepository.list_invisible_merchants(s, 10).size() == 3,
		"3 invisible merchants returned, got %d" % MerchantPoolRepository.list_invisible_merchants(s, 10).size())


# ---------------------------------------------------------------------------
# Consume loads
# ---------------------------------------------------------------------------

func test_consume_loads_decrement() -> void:
	var s: String = _make_settlement(3, "ConsumeDec")
	var mid: String = _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO merchant_pool
			(id, campaign_id, settlement_entrance_id, merchandise_type,
			 loads_available, loads_initial, created_at_calendar_day,
			 expires_at_calendar_day, becomes_visible_calendar_day, status, source_kind)
		VALUES (?, ?, ?, 'salt', 10, 10, 0, 999, 0, 'active', 'monthly_refresh')
	""", [mid, _campaign_id, s])
	check(MerchantPoolRepository.consume_loads(mid, 3), "consume_loads(3) on 10-load merchant should succeed")
	var m: Dictionary = MerchantPoolRepository.get_merchant(mid)
	check(int(m.get("loads_available", -1)) == 7, "loads_available = 7 after consuming 3")
	check(str(m.get("status", "")) == "active", "status still 'active' after partial consume")


func test_consume_loads_depletion_and_signal() -> void:
	var s: String = _make_settlement(3, "ConsumeDepleted")
	var mid: String = _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO merchant_pool
			(id, campaign_id, settlement_entrance_id, merchandise_type,
			 loads_available, loads_initial, created_at_calendar_day,
			 expires_at_calendar_day, becomes_visible_calendar_day, status, source_kind)
		VALUES (?, ?, ?, 'silk', 5, 5, 0, 999, 0, 'active', 'monthly_refresh')
	""", [mid, _campaign_id, s])
	var depleted: Dictionary = {"emitted": false}
	var cb: Callable = func(merchant_id: String, settlement_id: String) -> void:
		if merchant_id == mid:
			depleted["emitted"] = true
	EventBus.merchant_depleted.connect(cb)
	check(MerchantPoolRepository.consume_loads(mid, 5), "consume_loads(5) on 5-load merchant should succeed")
	EventBus.merchant_depleted.disconnect(cb)
	var m: Dictionary = MerchantPoolRepository.get_merchant(mid)
	check(int(m.get("loads_available", -1)) == 0, "loads_available = 0 after full consume")
	check(str(m.get("status", "")) == "depleted", "status flips to 'depleted'")
	check(bool(depleted["emitted"]), "merchant_depleted signal fires")


func test_consume_loads_insufficient() -> void:
	var s: String = _make_settlement(3, "ConsumeInsuff")
	var mid: String = _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO merchant_pool
			(id, campaign_id, settlement_entrance_id, merchandise_type,
			 loads_available, loads_initial, created_at_calendar_day,
			 expires_at_calendar_day, becomes_visible_calendar_day, status, source_kind)
		VALUES (?, ?, ?, 'salt', 3, 3, 0, 999, 0, 'active', 'monthly_refresh')
	""", [mid, _campaign_id, s])
	check(not MerchantPoolRepository.consume_loads(mid, 5),
		"consume_loads(5) on 3-load merchant should fail")
	# Row unchanged.
	var m: Dictionary = MerchantPoolRepository.get_merchant(mid)
	check(int(m.get("loads_available", -1)) == 3, "loads_available unchanged at 3")
	check(str(m.get("status", "")) == "active", "status unchanged 'active'")


# ---------------------------------------------------------------------------
# Expirations
# ---------------------------------------------------------------------------

func test_process_expirations_deletes_overdue() -> void:
	var s: String = _make_settlement(3, "ExpireOverdue")
	# Two merchants: one expires day 10, one day 20.
	for tup in [["expire_a", 10], ["expire_b", 20]]:
		var mid: String = "%s_%s" % [_next_id(), tup[0]]
		CampaignRepository.db.query_with_bindings("""
			INSERT INTO merchant_pool
				(id, campaign_id, settlement_entrance_id, merchandise_type,
				 loads_available, loads_initial, created_at_calendar_day,
				 expires_at_calendar_day, becomes_visible_calendar_day, status, source_kind)
			VALUES (?, ?, ?, 'salt', 5, 5, 0, ?, 0, 'active', 'monthly_refresh')
		""", [mid, _campaign_id, s, tup[1]])
	# At day 15: only the day-10 merchant is overdue.
	var count: int = MerchantPoolRepository.process_expirations(s, 15)
	check(count == 1, "1 merchant expired at day 15, got %d" % count)
	CampaignRepository.db.query_with_bindings(
		"SELECT COUNT(*) AS n FROM merchant_pool WHERE settlement_entrance_id = ?", [s])
	check(int(CampaignRepository.db.query_result[0].get("n", 0)) == 1, "1 merchant remains")


func test_process_expirations_emits_signal() -> void:
	var s: String = _make_settlement(3, "ExpireSignal")
	var mid: String = "%s_expire_signal" % _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO merchant_pool
			(id, campaign_id, settlement_entrance_id, merchandise_type,
			 loads_available, loads_initial, created_at_calendar_day,
			 expires_at_calendar_day, becomes_visible_calendar_day, status, source_kind)
		VALUES (?, ?, ?, 'salt', 5, 5, 0, 10, 0, 'active', 'monthly_refresh')
	""", [mid, _campaign_id, s])
	var got_signal := {"emitted": false}
	var cb: Callable = func(merchant_id: String, settlement_id: String) -> void:
		if merchant_id == mid:
			got_signal["emitted"] = true
	EventBus.merchant_expired.connect(cb)
	MerchantPoolRepository.process_expirations(s, 100)
	EventBus.merchant_expired.disconnect(cb)
	check(bool(got_signal["emitted"]), "merchant_expired signal fires on expiration")


# ---------------------------------------------------------------------------
# Solicit
# ---------------------------------------------------------------------------

func test_solicitation_staggered_reveal_class_iii() -> void:
	# Class III: 8 invisible merchants. first_half=4, second_quarter=2, remainder=2.
	# After solicit at day 0: 4 → day 7, 2 → day 14, 2 → day 21.
	var s: String = _make_settlement(3, "Solicit3")
	MerchantPoolRepository.generate_pool_for_settlement(s, 0, _seeded_rng(1), false)
	var result: Dictionary = MerchantPoolRepository.process_solicitation(s, "char_test", 0)
	check(bool(result.get("success", false)), "solicit should succeed")
	check(int(result.get("merchants_revealed", 0)) == 8, "all 8 merchants revealed")
	# Count by becomes_visible_calendar_day.
	for tup in [[7, 4], [14, 2], [21, 2]]:
		CampaignRepository.db.query_with_bindings("""
			SELECT COUNT(*) AS n FROM merchant_pool
			WHERE settlement_entrance_id = ? AND becomes_visible_calendar_day = ?
		""", [s, tup[0]])
		check(int(CampaignRepository.db.query_result[0].get("n", 0)) == tup[1],
			"day +%d should have %d merchants, got %d" % [tup[0], tup[1], int(CampaignRepository.db.query_result[0].get("n", 0))])


func test_solicitation_rejects_when_already_visible() -> void:
	# Pool already fully visible (e.g., PC-owned).
	var s: String = _make_settlement(3, "SolicitNoOp")
	MerchantPoolRepository.generate_pool_for_settlement(s, 0, _seeded_rng(1), true)
	var result: Dictionary = MerchantPoolRepository.process_solicitation(s, "char", 0)
	check(not bool(result.get("success", true)), "solicit should reject when pool already visible")
	check(str(result.get("error", "")) == "already_revealed", "error code 'already_revealed'")


func test_solicitation_small_pool_class_vi() -> void:
	# Class VI: 2 invisible merchants. first_half=1, second_quarter=max(0,1)=1, remainder=0.
	# Clamp logic: first+second=2 == N=2, so no remainder week-3 entries.
	var s: String = _make_settlement(6, "Solicit6")
	MerchantPoolRepository.generate_pool_for_settlement(s, 0, _seeded_rng(1), false)
	var result: Dictionary = MerchantPoolRepository.process_solicitation(s, "char", 0)
	check(bool(result.get("success", false)), "Class VI solicit should succeed without crashing")
	check(int(result.get("merchants_revealed", 0)) == 2, "2 merchants revealed in Class VI")
	# 1 at day 7, 1 at day 14, 0 at day 21.
	CampaignRepository.db.query_with_bindings(
		"SELECT becomes_visible_calendar_day FROM merchant_pool WHERE settlement_entrance_id = ? ORDER BY becomes_visible_calendar_day ASC", [s])
	var days: Array = []
	for row in CampaignRepository.db.query_result:
		days.append(int((row as Dictionary).get("becomes_visible_calendar_day", -1)))
	check(days.size() == 2, "2 rows returned")
	if days.size() == 2:
		check(days[0] == 7, "first merchant at day 7, got %d" % days[0])
		check(days[1] == 14, "second merchant at day 14, got %d" % days[1])


# ---------------------------------------------------------------------------
# Locate
# ---------------------------------------------------------------------------

func test_locate_finds_visible_match() -> void:
	var s: String = _make_settlement(3, "LocateVisible")
	# Insert a visible silk merchant directly.
	var mid: String = _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO merchant_pool
			(id, campaign_id, settlement_entrance_id, merchandise_type,
			 loads_available, loads_initial, created_at_calendar_day,
			 expires_at_calendar_day, becomes_visible_calendar_day, status, source_kind)
		VALUES (?, ?, ?, 'silk', 5, 5, 0, 999, 0, 'active', 'monthly_refresh')
	""", [mid, _campaign_id, s])
	var result: Dictionary = MerchantPoolRepository.process_locate(s, "silk", 10)
	check(bool(result.get("success", false)), "locate should find visible silk merchant")
	check(not bool(result.get("surfaced_now", true)), "surfaced_now=false (already visible)")
	check(str(result.get("merchant_id", "")) == mid, "merchant_id matches")


func test_locate_surfaces_invisible_match() -> void:
	var s: String = _make_settlement(3, "LocateInvisible")
	var mid: String = _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO merchant_pool
			(id, campaign_id, settlement_entrance_id, merchandise_type,
			 loads_available, loads_initial, created_at_calendar_day,
			 expires_at_calendar_day, becomes_visible_calendar_day, status, source_kind)
		VALUES (?, ?, ?, 'silk', 5, 5, 0, 999, ?, 'active', 'monthly_refresh')
	""", [mid, _campaign_id, s, MerchantPoolRepository.INVISIBLE_SENTINEL])
	var got_signal := {"emitted": false}
	var cb: Callable = func(merchant_id: String, settlement_id: String, merchandise_type: String) -> void:
		if merchant_id == mid:
			got_signal["emitted"] = true
	EventBus.merchant_surfaced_via_locate.connect(cb)
	var result: Dictionary = MerchantPoolRepository.process_locate(s, "silk", 50)
	EventBus.merchant_surfaced_via_locate.disconnect(cb)
	check(bool(result.get("success", false)), "locate should surface invisible silk merchant")
	check(bool(result.get("surfaced_now", false)), "surfaced_now=true")
	check(str(result.get("merchant_id", "")) == mid, "merchant_id matches surfaced row")
	check(bool(got_signal["emitted"]), "merchant_surfaced_via_locate signal fires")
	# becomes_visible_calendar_day should now be 50.
	var m: Dictionary = MerchantPoolRepository.get_merchant(mid)
	check(int(m.get("becomes_visible_calendar_day", -1)) == 50,
		"becomes_visible_calendar_day = 50 after surface")


func test_locate_fails_when_no_match() -> void:
	var s: String = _make_settlement(3, "LocateMiss")
	# Pool has only salt merchants.
	for _i in range(3):
		var mid: String = _next_id()
		CampaignRepository.db.query_with_bindings("""
			INSERT INTO merchant_pool
				(id, campaign_id, settlement_entrance_id, merchandise_type,
				 loads_available, loads_initial, created_at_calendar_day,
				 expires_at_calendar_day, becomes_visible_calendar_day, status, source_kind)
			VALUES (?, ?, ?, 'salt', 5, 5, 0, 999, 0, 'active', 'monthly_refresh')
		""", [mid, _campaign_id, s])
	var result: Dictionary = MerchantPoolRepository.process_locate(s, "silk", 10)
	check(not bool(result.get("success", true)), "locate should fail with no silk merchant")
	check(str(result.get("error", "")) == "no_merchant_of_type", "error code 'no_merchant_of_type'")


# ---------------------------------------------------------------------------
# Campaign-wide refresh + PC-ownership detection
# ---------------------------------------------------------------------------

func test_monthly_refresh_pc_owned_detection() -> void:
	# Create two settlements, one owned by a PC, one with no domain.
	var pc_id: String = "%s_pc" % _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type)
		VALUES (?, ?, 'PCOwner', 'pc')
	""", [pc_id, _campaign_id])
	var pc_domain: String = CampaignRepository.create_domain({
		"campaign_id": _campaign_id, "name": "PCRefreshDomain",
		"owner_character_id": pc_id,
	})
	var pc_settlement: String = _make_settlement(3, "PCRefreshTown", pc_domain)
	var npc_settlement: String = _make_settlement(3, "NPCRefreshTown")
	var rng: RandomNumberGenerator = _seeded_rng(42)
	var total: int = MerchantPoolRepository.process_monthly_refresh_for_campaign(_campaign_id, 100, rng)
	# total should include all settlements created in the campaign (this test's 2 + previous tests'),
	# but we just verify the two we care about.
	check(total > 0, "monthly refresh should generate at least the campaign's settlement count, got %d" % total)
	# PC-owned settlement: all merchants visible at day 100.
	CampaignRepository.db.query_with_bindings("""
		SELECT COUNT(*) AS n FROM merchant_pool
		WHERE settlement_entrance_id = ? AND becomes_visible_calendar_day = 100
			AND source_kind = 'monthly_refresh'
	""", [pc_settlement])
	check(int(CampaignRepository.db.query_result[0].get("n", 0)) == 8,
		"PC-owned settlement: 8 merchants visible at day 100")
	# NPC settlement: all merchants invisible.
	CampaignRepository.db.query_with_bindings("""
		SELECT COUNT(*) AS n FROM merchant_pool
		WHERE settlement_entrance_id = ? AND becomes_visible_calendar_day = ?
			AND source_kind = 'monthly_refresh'
	""", [npc_settlement, MerchantPoolRepository.INVISIBLE_SENTINEL])
	check(int(CampaignRepository.db.query_result[0].get("n", 0)) == 8,
		"NPC settlement: 8 merchants invisible (sentinel)")


# ---------------------------------------------------------------------------
# Phase 10B.2 Wave 1 substrate amendments (§4.8 + §11.7 + §0.1.1)
# Refused-cohort filter on list_visible* + promoted-row preservation across
# monthly refresh / expiration.
# ---------------------------------------------------------------------------

func _insert_refused_merchant(settlement_id: String, merchandise_type: String, refused_day: int) -> String:
	# Helper: inserts a visible merchant with refused_at_calendar_day set.
	var mid: String = _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO merchant_pool
			(id, campaign_id, settlement_entrance_id, merchandise_type,
			 loads_available, loads_initial, created_at_calendar_day,
			 expires_at_calendar_day, becomes_visible_calendar_day, status, source_kind,
			 refused_at_calendar_day)
		VALUES (?, ?, ?, ?, 5, 5, 0, 999, 0, 'active', 'monthly_refresh', ?)
	""", [mid, _campaign_id, settlement_id, merchandise_type, refused_day])
	return mid


func _insert_active_merchant(settlement_id: String, merchandise_type: String, visible_day: int = 0) -> String:
	var mid: String = _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO merchant_pool
			(id, campaign_id, settlement_entrance_id, merchandise_type,
			 loads_available, loads_initial, created_at_calendar_day,
			 expires_at_calendar_day, becomes_visible_calendar_day, status, source_kind)
		VALUES (?, ?, ?, ?, 5, 5, 0, 999, ?, 'active', 'monthly_refresh')
	""", [mid, _campaign_id, settlement_id, merchandise_type, visible_day])
	return mid


func _insert_promoted_merchant(
		settlement_id: String, merchandise_type: String,
		npc_id: String, expires_day: int = 999, visible_day: int = 0
) -> String:
	var mid: String = _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO merchant_pool
			(id, campaign_id, settlement_entrance_id, merchandise_type,
			 loads_available, loads_initial, created_at_calendar_day,
			 expires_at_calendar_day, becomes_visible_calendar_day, status, source_kind,
			 promoted_npc_id)
		VALUES (?, ?, ?, ?, 7, 7, 0, ?, ?, 'active', 'monthly_refresh', ?)
	""", [mid, _campaign_id, settlement_id, merchandise_type, expires_day, visible_day, npc_id])
	return mid


func test_refused_filter_excludes_from_list_visible() -> void:
	var s: String = _make_settlement(3, "RefusedFilterListVisible")
	_insert_active_merchant(s, "silk")
	_insert_refused_merchant(s, "silk", 50)
	var rows: Array = MerchantPoolRepository.list_visible_merchants(s, 100)
	check(rows.size() == 1,
		"list_visible_merchants filters refused row, got %d rows" % rows.size())


func test_refused_filter_excludes_from_list_visible_for_merchandise() -> void:
	var s: String = _make_settlement(3, "RefusedFilterByMerch")
	_insert_active_merchant(s, "salt")
	_insert_refused_merchant(s, "salt", 50)
	var rows: Array = MerchantPoolRepository.list_visible_merchants_for_merchandise(s, "salt", 100)
	check(rows.size() == 1,
		"list_visible_merchants_for_merchandise filters refused row, got %d" % rows.size())


func test_refused_filter_excludes_from_list_invisible() -> void:
	var s: String = _make_settlement(3, "RefusedFilterInvisible")
	# Set up: one invisible (sentinel) + one refused invisible.
	_insert_active_merchant(s, "silk", MerchantPoolRepository.INVISIBLE_SENTINEL)
	var refused_invisible_id: String = _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO merchant_pool
			(id, campaign_id, settlement_entrance_id, merchandise_type,
			 loads_available, loads_initial, created_at_calendar_day,
			 expires_at_calendar_day, becomes_visible_calendar_day, status, source_kind,
			 refused_at_calendar_day)
		VALUES (?, ?, ?, 'silk', 5, 5, 0, 999, ?, 'active', 'monthly_refresh', 50)
	""", [refused_invisible_id, _campaign_id, s, MerchantPoolRepository.INVISIBLE_SENTINEL])
	var rows: Array = MerchantPoolRepository.list_invisible_merchants(s, 100)
	check(rows.size() == 1,
		"list_invisible_merchants filters refused row, got %d" % rows.size())


func test_promoted_row_preserved_through_monthly_refresh() -> void:
	var s: String = _make_settlement(3, "PromotedPreserve")
	# Seed a promoted NPC merchant.
	var npc_id: String = "%s_npc" % _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type)
		VALUES (?, ?, 'PromotedNPC', 'npc')
	""", [npc_id, _campaign_id])
	var promoted_mid: String = _insert_promoted_merchant(s, "silk", npc_id)
	# Add a regular transactional row.
	var transact_mid: String = _insert_active_merchant(s, "salt")
	# Refresh.
	MerchantPoolRepository.generate_pool_for_settlement(s, 28, _seeded_rng(99), false)
	# Promoted row should still exist with the same id.
	CampaignRepository.db.query_with_bindings(
		"SELECT id FROM merchant_pool WHERE id = ?", [promoted_mid])
	check(not CampaignRepository.db.query_result.is_empty(),
		"promoted row survives monthly refresh (id=%s)" % promoted_mid)
	# Transactional row should have been deleted (replaced by new cohort).
	CampaignRepository.db.query_with_bindings(
		"SELECT id FROM merchant_pool WHERE id = ?", [transact_mid])
	check(CampaignRepository.db.query_result.is_empty(),
		"transactional row deleted on monthly refresh")


func test_promoted_row_loads_refreshed_in_place() -> void:
	var s: String = _make_settlement(3, "PromotedLoadsRefresh")
	var npc_id: String = "%s_npc" % _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type)
		VALUES (?, ?, 'PromotedLoadsNPC', 'npc')
	""", [npc_id, _campaign_id])
	var promoted_mid: String = _insert_promoted_merchant(s, "silk", npc_id, 50, 0)
	# Deplete the merchant's loads to verify refresh re-rolls them.
	CampaignRepository.db.query_with_bindings(
		"UPDATE merchant_pool SET loads_available = 0 WHERE id = ?", [promoted_mid])
	# Refresh at day 28 — expires_at should extend to 28 + 28 = 56.
	MerchantPoolRepository.generate_pool_for_settlement(s, 28, _seeded_rng(7), false)
	var row: Dictionary = MerchantPoolRepository.get_merchant(promoted_mid)
	check(int(row.get("loads_available", 0)) > 0,
		"promoted row's loads_available re-rolled to non-zero, got %d" % int(row.get("loads_available", 0)))
	check(int(row.get("expires_at_calendar_day", 0)) == 28 + Timekeeping.DAYS_PER_MONTH,
		"promoted row expires extended to current + 28 days, got %d" % int(row.get("expires_at_calendar_day", 0)))
	check(str(row.get("status", "")) == "active",
		"promoted row status reset to 'active'")


func test_promoted_row_skipped_by_process_expirations() -> void:
	var s: String = _make_settlement(3, "PromotedExpireSkip")
	var npc_id: String = "%s_npc" % _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type)
		VALUES (?, ?, 'PromotedExpireNPC', 'npc')
	""", [npc_id, _campaign_id])
	# Promoted row that's "overdue" — expires day 10.
	var promoted_mid: String = _insert_promoted_merchant(s, "silk", npc_id, 10)
	# A transactional row that's also overdue.
	var transact_mid: String = _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO merchant_pool
			(id, campaign_id, settlement_entrance_id, merchandise_type,
			 loads_available, loads_initial, created_at_calendar_day,
			 expires_at_calendar_day, becomes_visible_calendar_day, status, source_kind)
		VALUES (?, ?, ?, 'salt', 5, 5, 0, 10, 0, 'active', 'monthly_refresh')
	""", [transact_mid, _campaign_id, s])
	var expired_count: int = MerchantPoolRepository.process_expirations(s, 50)
	check(expired_count == 1,
		"process_expirations skips promoted row, deletes 1 transactional, got %d" % expired_count)
	# Promoted survives.
	CampaignRepository.db.query_with_bindings(
		"SELECT id FROM merchant_pool WHERE id = ?", [promoted_mid])
	check(not CampaignRepository.db.query_result.is_empty(),
		"promoted row survives process_expirations")


func test_promoted_refused_flag_cleared_on_monthly_refresh() -> void:
	var s: String = _make_settlement(3, "PromotedRefusedClear")
	var npc_id: String = "%s_npc" % _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type)
		VALUES (?, ?, 'PromotedRefusedNPC', 'npc')
	""", [npc_id, _campaign_id])
	var promoted_mid: String = _insert_promoted_merchant(s, "silk", npc_id)
	# Mark the promoted row as refused this cohort (simulating persuade-fail).
	CampaignRepository.db.query_with_bindings(
		"UPDATE merchant_pool SET refused_at_calendar_day = 5 WHERE id = ?", [promoted_mid])
	# Verify it's hidden from list_visible while refused.
	var before: Array = MerchantPoolRepository.list_visible_merchants(s, 10)
	check(before.is_empty(),
		"refused promoted row hidden before refresh, got %d row(s)" % before.size())
	# Run monthly refresh.
	MerchantPoolRepository.generate_pool_for_settlement(s, 28, _seeded_rng(11), true)
	# Refused flag should be NULL after refresh, and the row should be visible again.
	var row: Dictionary = MerchantPoolRepository.get_merchant(promoted_mid)
	check(row.get("refused_at_calendar_day", null) == null,
		"refused_at_calendar_day cleared to NULL on refresh, got %s" % str(row.get("refused_at_calendar_day", null)))


func test_cohort_cap_counts_promoted_rows() -> void:
	# Class IV cap = 4. Seed 2 promoted rows; refresh should create only
	# 4 - 2 = 2 new transactional rows (total cohort = 4).
	var s: String = _make_settlement(4, "PromotedCohortCap")
	var npc_id: String = "%s_npc" % _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type)
		VALUES (?, ?, 'CohortNPC', 'npc')
	""", [npc_id, _campaign_id])
	_insert_promoted_merchant(s, "silk", npc_id)
	_insert_promoted_merchant(s, "spices", npc_id)
	# generate_pool_for_settlement should report 2 NEW transactional rows
	# (cohort cap 4 - existing 2 promoted = 2).
	var new_count: int = MerchantPoolRepository.generate_pool_for_settlement(
		s, 28, _seeded_rng(13), false)
	check(new_count == 2,
		"cohort cap 4 - 2 promoted = 2 new transactional rows, got %d" % new_count)
	# Total rows should be 4 (2 promoted + 2 new transactional).
	CampaignRepository.db.query_with_bindings(
		"SELECT COUNT(*) AS n FROM merchant_pool WHERE settlement_entrance_id = ?", [s])
	check(int(CampaignRepository.db.query_result[0].get("n", 0)) == 4,
		"total cohort size = 4 (promoted + new), got %d" % int(CampaignRepository.db.query_result[0].get("n", 0)))
