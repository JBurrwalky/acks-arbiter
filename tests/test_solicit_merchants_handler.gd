extends "res://tests/test_suite_base.gd"

## Unit tests for SolicitMerchantsHandler — Phase 10B.2 Wave 3.
##
## Per gdd-phase-10b-2-trade-block.md §5 + §18.1. Exercises:
##   * prepare_launch invokes substrate process_solicitation, records start_day.
##   * prepare_launch rejects when invisible pool is empty (already_revealed).
##   * on_complete emits solicit_merchants_completed.
##   * handle_forfeit rolls back UNFIRED reveals (>current_day) to INVISIBLE_SENTINEL.
##   * Forfeit-rollback skips promoted_npc_id IS NOT NULL rows per §0.1.1.
##   * Forfeit-rollback skips manual rows (source_kind = 'manual').
##   * on_tick is a no-op.

var _campaign_id: String = ""
var _map_id: String = ""
var _suffix: int = 0


func run_all_tests() -> void:
	_setup()
	test_prepare_launch_sets_reveal_days()
	test_prepare_launch_records_start_day_in_params()
	test_prepare_launch_rejects_already_revealed()
	test_on_complete_emits_completed_signal()
	test_handle_forfeit_rolls_back_unfired_reveals()
	test_handle_forfeit_preserves_fired_reveals()
	test_handle_forfeit_skips_promoted_merchants()
	test_handle_forfeit_skips_manual_rows()
	test_handle_forfeit_emits_signal_with_rollback_count()
	test_handle_forfeit_zero_rollback_when_all_fired()
	test_on_tick_is_noop()

	if not has_failures():
		print("SolicitMerchantsHandler: all %d tests passed." % test_count())


func _setup() -> void:
	_campaign_id = CampaignRepository.create_campaign("SolicitMerchantsTests", "World")
	_map_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO hex_maps (id, campaign_id, name, scale) VALUES (?, ?, ?, 'regional_6mi')",
		[_map_id, _campaign_id, "SMHMap"])


func _next_id(tag: String = "sm") -> String:
	_suffix += 1
	return "%s_%d_%d" % [tag, Time.get_ticks_msec(), _suffix]


func _build_fixture(opts: Dictionary = {}) -> Dictionary:
	var fx := TradeFixtures.new()
	var f: Dictionary = fx.build_bare({
		"name": "SM_" + _next_id(),
		"market_class": int(opts.get("market_class", 3)),
		"starting_wealth_cp": 1_000_000,
	})
	# Seed a cohort of invisible merchants (PC-owned=false → INVISIBLE_SENTINEL).
	var rng := RandomNumberGenerator.new()
	rng.seed = int(opts.get("pool_seed", 42))
	MerchantPoolRepository.generate_pool_for_settlement(
		f["settlement_id"], 0, rng, false)
	VisitStateManager.on_party_entered_settlement(
		f["party_id"], f["settlement_id"], f["pc_id"], 0)
	return f


# ---------------------------------------------------------------------------
# prepare_launch
# ---------------------------------------------------------------------------

func test_prepare_launch_sets_reveal_days() -> void:
	var fx: Dictionary = _build_fixture({"market_class": 3})  # Class III → 8 merchants
	var result: Dictionary = SolicitMerchantsHandler.prepare_launch(
		fx["party_id"], fx["settlement_id"], fx["pc_id"])
	check(bool(result.get("success", false)),
		"prepare_launch succeeds, got error: %s" % String(result.get("error", "?")))
	check(int(result.get("merchants_revealed", 0)) == 8,
		"Class III prepare_launch reveals 8 merchants, got %d" % int(result.get("merchants_revealed", 0)))


func test_prepare_launch_records_start_day_in_params() -> void:
	var fx: Dictionary = _build_fixture()
	var current_day: int = Timekeeping.get_total_days()
	var result: Dictionary = SolicitMerchantsHandler.prepare_launch(
		fx["party_id"], fx["settlement_id"], fx["pc_id"])
	check(bool(result.get("success", false)), "prepare_launch succeeds")
	var params: Dictionary = result.get("params", {})
	check(int(params.get("started_at_calendar_day", -1)) == current_day,
		"params.started_at_calendar_day = current_day (%d), got %d" % [
			current_day, int(params.get("started_at_calendar_day", -1))])


func test_prepare_launch_rejects_already_revealed() -> void:
	# Build fixture with PC-owned domain (all merchants visible at gen day).
	var fx_tr := TradeFixtures.new()
	var f: Dictionary = fx_tr.build_bare({
		"name": "SM_revealed_" + _next_id(),
		"market_class": 3,
		"pc_owns_parent_domain": true,
		"starting_wealth_cp": 100_000,
	})
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	MerchantPoolRepository.generate_pool_for_settlement(
		f["settlement_id"], 0, rng, true)  # pc_owned=true → immediately visible
	var result: Dictionary = SolicitMerchantsHandler.prepare_launch(
		f["party_id"], f["settlement_id"], f["pc_id"])
	check(not bool(result.get("success", true)),
		"prepare_launch rejects when invisible pool empty")
	check(str(result.get("error", "")) == "already_revealed",
		"error = 'already_revealed', got '%s'" % str(result.get("error", "")))


# ---------------------------------------------------------------------------
# on_complete
# ---------------------------------------------------------------------------

func test_on_complete_emits_completed_signal() -> void:
	var fx: Dictionary = _build_fixture()
	var state := {
		"character_id": fx["pc_id"],
		"location_ref": fx["settlement_id"],
		"params_json": JSON.stringify({"started_at_calendar_day": 0}),
	}
	var captured := {"emitted": false, "sid": ""}
	var cb: Callable = func(sid: String, _cid: String) -> void:
		captured["emitted"] = true
		captured["sid"] = sid
	EventBus.solicit_merchants_completed.connect(cb)
	var r: Dictionary = SolicitMerchantsHandler.on_complete(state, null)
	EventBus.solicit_merchants_completed.disconnect(cb)
	check(bool(r.get("success", false)), "on_complete returns success=true")
	check(bool(captured["emitted"]), "solicit_merchants_completed signal fired")
	check(str(captured["sid"]) == fx["settlement_id"], "settlement_id in signal payload")


# ---------------------------------------------------------------------------
# handle_forfeit (the §5.4 rollback)
# ---------------------------------------------------------------------------

func test_handle_forfeit_rolls_back_unfired_reveals() -> void:
	var fx: Dictionary = _build_fixture()
	# prepare_launch uses Timekeeping.get_total_days() (NOT necessarily 0 —
	# prior test suites in the run can advance Timekeeping); compute expected
	# reveal days dynamically.
	var start_day: int = Timekeeping.get_total_days()
	SolicitMerchantsHandler.prepare_launch(fx["party_id"], fx["settlement_id"], fx["pc_id"])
	# Sanity: merchants have becomes_visible_calendar_day in {start+7, start+14, start+21}.
	CampaignRepository.db.query_with_bindings("""
		SELECT COUNT(*) AS n FROM merchant_pool
		WHERE settlement_entrance_id = ? AND becomes_visible_calendar_day IN (?, ?, ?)
	""", [fx["settlement_id"], start_day + 7, start_day + 14, start_day + 21])
	var pre_count: int = int(CampaignRepository.db.query_result[0].get("n", 0))
	check(pre_count == 8,
		"8 merchants scheduled for {start+7,+14,+21} with start=%d, got %d" % [start_day, pre_count])

	# Forfeit with started_at_calendar_day = start_day; current_day still = start_day
	# (Timekeeping hasn't moved). All offsets {7, 14, 21} land at days strictly
	# greater than current_day, so all 8 rolls back.
	var state := {
		"character_id": fx["pc_id"],
		"location_ref": fx["settlement_id"],
		"params_json": JSON.stringify({"started_at_calendar_day": start_day}),
	}
	SolicitMerchantsHandler.handle_forfeit(state)

	# Now all 8 merchants should be back at INVISIBLE_SENTINEL.
	CampaignRepository.db.query_with_bindings("""
		SELECT COUNT(*) AS n FROM merchant_pool
		WHERE settlement_entrance_id = ? AND becomes_visible_calendar_day = ?
	""", [fx["settlement_id"], MerchantPoolRepository.INVISIBLE_SENTINEL])
	var post_count: int = int(CampaignRepository.db.query_result[0].get("n", 0))
	check(post_count == 8,
		"all 8 merchants rolled back to INVISIBLE_SENTINEL, got %d" % post_count)


func test_handle_forfeit_preserves_fired_reveals() -> void:
	# Test the attribution + already-fired filter:
	#   * Solicit started at start_day (= Timekeeping.get_total_days()).
	#   * Reveal days = start_day + {7, 14, 21}.
	#   * Pretend the FIRST week's reveal already fired — i.e., we simulate a
	#     state where the day-7 merchants are now visible at start_day (i.e.,
	#     they fired and now look like "already-visible-at-current"). We do
	#     this by manually inserting rows at day start_day instead of start_day+7.
	#   * Day +14 and +21 are still scheduled.
	# Forfeit:
	#   unfired_reveal_days = filter([+7, +14, +21], > current_day)
	#                      = [+14, +21]  (since current_day = start_day and
	#                                     +7 == start_day < +14 ≤ +21)
	#   Wait: +7 > start_day (= current_day) → +7 should be in unfired. But our
	#   day-7 rows aren't at day +7 anymore; they're at start_day. So the IN
	#   filter on becomes_visible_calendar_day matches only the +14 and +21 rows.
	#
	# Net: day +14 + day +21 rows roll back to INVISIBLE_SENTINEL; day start_day
	# rows (the "already fired") are preserved at start_day.
	var fx: Dictionary = _build_fixture()
	var start_day: int = Timekeeping.get_total_days()
	# Wipe the auto-generated pool + seed test-specific rows.
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM merchant_pool WHERE settlement_entrance_id = ?", [fx["settlement_id"]])
	# 4 "already-fired" rows visible at start_day (simulating day-7 reveals
	# that happened at start of solicit window).
	for i in 4:
		var mid: String = _next_id("m")
		CampaignRepository.db.query_with_bindings("""
			INSERT INTO merchant_pool
				(id, campaign_id, settlement_entrance_id, merchandise_type,
				 loads_available, loads_initial, created_at_calendar_day,
				 expires_at_calendar_day, becomes_visible_calendar_day, status, source_kind)
			VALUES (?, ?, ?, 'salt', 5, 5, 0, 999, ?, 'active', 'monthly_refresh')
		""", [mid, _campaign_id, fx["settlement_id"], start_day])
	# 2 unfired rows at +14.
	for i in 2:
		var mid: String = _next_id("m")
		CampaignRepository.db.query_with_bindings("""
			INSERT INTO merchant_pool
				(id, campaign_id, settlement_entrance_id, merchandise_type,
				 loads_available, loads_initial, created_at_calendar_day,
				 expires_at_calendar_day, becomes_visible_calendar_day, status, source_kind)
			VALUES (?, ?, ?, 'wood_common', 5, 5, 0, 999, ?, 'active', 'monthly_refresh')
		""", [mid, _campaign_id, fx["settlement_id"], start_day + 14])
	# 2 unfired rows at +21.
	for i in 2:
		var mid: String = _next_id("m")
		CampaignRepository.db.query_with_bindings("""
			INSERT INTO merchant_pool
				(id, campaign_id, settlement_entrance_id, merchandise_type,
				 loads_available, loads_initial, created_at_calendar_day,
				 expires_at_calendar_day, becomes_visible_calendar_day, status, source_kind)
			VALUES (?, ?, ?, 'spices', 5, 5, 0, 999, ?, 'active', 'monthly_refresh')
		""", [mid, _campaign_id, fx["settlement_id"], start_day + 21])

	# Forfeit. handle_forfeit computes unfired_reveal_days = filter(
	# [start_day+7, start_day+14, start_day+21], > current_day=start_day) =
	# [start_day+7, +14, +21]. UPDATE rolls back rows whose
	# becomes_visible_calendar_day matches ANY of those. The 4 rows at
	# start_day are NOT in the filter list, so they survive. The +14 and +21
	# rows match and roll back. The +7 entry in the filter has no matching
	# rows (we didn't seed any), so it touches nothing there.
	var state := {
		"character_id": fx["pc_id"],
		"location_ref": fx["settlement_id"],
		"params_json": JSON.stringify({"started_at_calendar_day": start_day}),
	}
	SolicitMerchantsHandler.handle_forfeit(state)

	CampaignRepository.db.query_with_bindings("""
		SELECT becomes_visible_calendar_day, COUNT(*) AS n FROM merchant_pool
		WHERE settlement_entrance_id = ?
		GROUP BY becomes_visible_calendar_day
	""", [fx["settlement_id"]])
	var by_day: Dictionary = {}
	for row in CampaignRepository.db.query_result:
		by_day[int((row as Dictionary).get("becomes_visible_calendar_day", -1))] = \
			int((row as Dictionary).get("n", 0))
	check(int(by_day.get(start_day, 0)) == 4,
		"4 'already-fired' rows preserved at start_day=%d, got %d" % [
			start_day, int(by_day.get(start_day, 0))])
	check(int(by_day.get(MerchantPoolRepository.INVISIBLE_SENTINEL, 0)) == 4,
		"4 rows rolled back to INVISIBLE_SENTINEL (2@+14 + 2@+21), got %d" % int(by_day.get(MerchantPoolRepository.INVISIBLE_SENTINEL, 0)))


func test_handle_forfeit_skips_promoted_merchants() -> void:
	var fx: Dictionary = _build_fixture()
	var start_day: int = Timekeeping.get_total_days()
	# Create a promoted NPC merchant scheduled to reveal at start_day + 7.
	var npc_id: String = _next_id("npc")
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO characters (id, campaign_id, name, character_type) VALUES (?, ?, 'PromotedNPC', 'npc')",
		[npc_id, _campaign_id])
	var promoted_mid: String = _next_id("pm")
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO merchant_pool
			(id, campaign_id, settlement_entrance_id, merchandise_type,
			 loads_available, loads_initial, created_at_calendar_day,
			 expires_at_calendar_day, becomes_visible_calendar_day, status, source_kind,
			 promoted_npc_id)
		VALUES (?, ?, ?, 'silk', 5, 5, 0, 999, ?, 'active', 'monthly_refresh', ?)
	""", [promoted_mid, _campaign_id, fx["settlement_id"], start_day + 7, npc_id])
	# Forfeit with start=start_day → unfired = [start+7, +14, +21]; current=start_day.
	var state := {
		"character_id": fx["pc_id"],
		"location_ref": fx["settlement_id"],
		"params_json": JSON.stringify({"started_at_calendar_day": start_day}),
	}
	SolicitMerchantsHandler.handle_forfeit(state)
	# The promoted merchant should still have visibility = start_day + 7.
	var merchant: Dictionary = MerchantPoolRepository.get_merchant(promoted_mid)
	check(int(merchant.get("becomes_visible_calendar_day", -1)) == start_day + 7,
		"promoted merchant visibility preserved at start_day+7=%d, got %d" % [
			start_day + 7, int(merchant.get("becomes_visible_calendar_day", -1))])


func test_handle_forfeit_skips_manual_rows() -> void:
	var fx: Dictionary = _build_fixture()
	var start_day: int = Timekeeping.get_total_days()
	# Add a manual row at start_day + 7.
	var manual_mid: String = _next_id("man")
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO merchant_pool
			(id, campaign_id, settlement_entrance_id, merchandise_type,
			 loads_available, loads_initial, created_at_calendar_day,
			 expires_at_calendar_day, becomes_visible_calendar_day, status, source_kind)
		VALUES (?, ?, ?, 'gems', 5, 5, 0, 999, ?, 'active', 'manual')
	""", [manual_mid, _campaign_id, fx["settlement_id"], start_day + 7])
	var state := {
		"character_id": fx["pc_id"],
		"location_ref": fx["settlement_id"],
		"params_json": JSON.stringify({"started_at_calendar_day": start_day}),
	}
	SolicitMerchantsHandler.handle_forfeit(state)
	var merchant: Dictionary = MerchantPoolRepository.get_merchant(manual_mid)
	check(int(merchant.get("becomes_visible_calendar_day", -1)) == start_day + 7,
		"manual row visibility preserved at start_day+7=%d, got %d" % [
			start_day + 7, int(merchant.get("becomes_visible_calendar_day", -1))])


func test_handle_forfeit_emits_signal_with_rollback_count() -> void:
	var fx: Dictionary = _build_fixture()
	var start_day: int = Timekeeping.get_total_days()
	SolicitMerchantsHandler.prepare_launch(fx["party_id"], fx["settlement_id"], fx["pc_id"])
	var captured := {"emitted": false, "rolled_back": -1, "sid": ""}
	var cb: Callable = func(sid: String, _cid: String, rolled_back: int) -> void:
		captured["emitted"] = true
		captured["rolled_back"] = rolled_back
		captured["sid"] = sid
	EventBus.solicit_merchants_forfeited.connect(cb)
	var state := {
		"character_id": fx["pc_id"],
		"location_ref": fx["settlement_id"],
		"params_json": JSON.stringify({"started_at_calendar_day": start_day}),
	}
	SolicitMerchantsHandler.handle_forfeit(state)
	EventBus.solicit_merchants_forfeited.disconnect(cb)
	check(bool(captured["emitted"]), "solicit_merchants_forfeited fired")
	check(int(captured["rolled_back"]) == 8,
		"signal reports 8 rows rolled back, got %d" % int(captured["rolled_back"]))
	check(str(captured["sid"]) == fx["settlement_id"], "settlement_id in signal payload")


func test_handle_forfeit_zero_rollback_when_all_fired() -> void:
	# started_at = current_day - 28 means reveal days = current - 21/14/7 —
	# all in the past relative to current_day. Forfeit rolls back zero rows.
	var fx: Dictionary = _build_fixture()
	var current_day: int = Timekeeping.get_total_days()
	var state := {
		"character_id": fx["pc_id"],
		"location_ref": fx["settlement_id"],
		"params_json": JSON.stringify({"started_at_calendar_day": current_day - 28}),
	}
	var captured := {"rolled_back": -1}
	var cb: Callable = func(_sid: String, _cid: String, rolled_back: int) -> void:
		captured["rolled_back"] = rolled_back
	EventBus.solicit_merchants_forfeited.connect(cb)
	SolicitMerchantsHandler.handle_forfeit(state)
	EventBus.solicit_merchants_forfeited.disconnect(cb)
	check(int(captured["rolled_back"]) == 0,
		"all reveals already past → rolled_back = 0, got %d" % int(captured["rolled_back"]))


# ---------------------------------------------------------------------------
# on_tick
# ---------------------------------------------------------------------------

func test_on_tick_is_noop() -> void:
	var state := {
		"character_id": "x",
		"location_ref": "y",
		"params_json": "{}",
	}
	var result: Dictionary = SolicitMerchantsHandler.on_tick(state, null)
	check(result.is_empty(), "on_tick returns empty Dict (no-op)")
