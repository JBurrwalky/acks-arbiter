extends "res://tests/test_suite_base.gd"

## Multi-activity workflow integration test — Phase 10B.2 Wave 6 (close-out).
##
## Per gdd-phase-10b-2-trade-block.md §18.3 + §19.6. Composes the
## Wave-3 persuade / solicit / locate handlers end-to-end. Also exercises
## the §0.1.1 LLM-promotion preservation case: a seeded promoted merchant
## survives persuade-fail (refused_at_calendar_day flag set) AND survives
## monthly refresh (refused_at_calendar_day cleared back to NULL when the
## cohort re-cycles).

var _campaign_id: String = ""
var _map_id: String = ""
var _suffix: int = 0


func run_all_tests() -> void:
	_setup()
	test_solicit_then_locate_then_persuade_workflow()
	test_promoted_merchant_survives_persuade_fail_and_monthly_refresh()
	test_locate_failure_suggests_persuade_in_summary()

	if not has_failures():
		print("PersuadeSolicitLocateWorkflow: all %d tests passed." % test_count())


func _setup() -> void:
	_campaign_id = CampaignRepository.create_campaign("PersuadeSolicitLocateWorkflowTests", "World")
	_map_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO hex_maps (id, campaign_id, name, scale) VALUES (?, ?, ?, 'regional_6mi')",
		[_map_id, _campaign_id, "PSLWMap"])


func _next_id(tag: String = "pslw") -> String:
	_suffix += 1
	return "%s_%d_%d" % [tag, Time.get_ticks_msec(), _suffix]


func _build_fixture(opts: Dictionary = {}) -> Dictionary:
	# Bare fixture: one Class III settlement, one PC + party + wagon.
	var fx := TradeFixtures.new()
	var f: Dictionary = fx.build_bare({
		"name": "PSLW_" + _next_id(),
		"market_class": int(opts.get("market_class", 3)),
		"starting_wealth_cp": 1_000_000,
	})
	# Enter the visit — closes the no-active-visit branch in the handlers'
	# defensive auto-open.
	VisitStateManager.on_party_entered_settlement(
		f["party_id"], f["settlement_id"], f["pc_id"], Timekeeping.get_total_days())
	return f


# ---------------------------------------------------------------------------
# 1. Solicit → Locate → Persuade workflow
# ---------------------------------------------------------------------------

func test_solicit_then_locate_then_persuade_workflow() -> void:
	# Setup: Class III pool of 8 INVISIBLE merchants.
	var f: Dictionary = _build_fixture({"market_class": 3})
	var settlement_id: String = f["settlement_id"]
	var party_id: String = f["party_id"]
	var pc_id: String = f["pc_id"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 100
	MerchantPoolRepository.generate_pool_for_settlement(settlement_id, 0, rng, false)
	var current_day: int = Timekeeping.get_total_days()

	# --- Step 1: Solicit ---
	var prep: Dictionary = SolicitMerchantsHandler.prepare_launch(party_id, settlement_id, pc_id)
	check(bool(prep.get("success", false)),
		"solicit prepare_launch succeeds, got: %s" % str(prep.get("error", "?")))
	check(int(prep.get("merchants_revealed", 0)) == 8,
		"solicit reveals all 8 invisible merchants on the staggered schedule, got %d" % int(prep.get("merchants_revealed", 0)))
	# Substrate set becomes_visible_calendar_day to current+7/+14/+21 per the
	# half-ceil / quarter-floor-min1 / remainder split. Verify the schedule.
	CampaignRepository.db.query_with_bindings("""
		SELECT becomes_visible_calendar_day, COUNT(*) AS n FROM merchant_pool
		WHERE settlement_entrance_id = ?
		GROUP BY becomes_visible_calendar_day
		ORDER BY becomes_visible_calendar_day ASC
	""", [settlement_id])
	var schedule: Dictionary = {}
	for row in CampaignRepository.db.query_result:
		schedule[int((row as Dictionary).get("becomes_visible_calendar_day", -1))] = \
			int((row as Dictionary).get("n", 0))
	check(int(schedule.get(current_day + 7, 0)) == 4,
		"day+7 reveal tranche = 4 (Class III half-ceil), got %d" % int(schedule.get(current_day + 7, 0)))
	check(int(schedule.get(current_day + 14, 0)) == 2,
		"day+14 reveal tranche = 2 (quarter-floor), got %d" % int(schedule.get(current_day + 14, 0)))
	check(int(schedule.get(current_day + 21, 0)) == 2,
		"day+21 reveal tranche = 2 (remainder), got %d" % int(schedule.get(current_day + 21, 0)))

	# --- Step 2: Locate ---
	# Pick a merchandise type the cohort happens to carry (read one merchant's
	# type to guarantee a hit).
	CampaignRepository.db.query_with_bindings(
		"SELECT merchandise_type FROM merchant_pool WHERE settlement_entrance_id = ? LIMIT 1",
		[settlement_id])
	var target_type: String = String(CampaignRepository.db.query_result[0].get("merchandise_type", ""))
	var locate_state := {
		"character_id": pc_id,
		"location_ref": settlement_id,
		"params_json": JSON.stringify({"merchandise_type": target_type}),
	}
	var locate_result: Dictionary = LocateMerchandiseHandler.on_complete(locate_state, null)
	check(bool(locate_result.get("success", false)),
		"locate succeeds for cohort-resident type '%s'" % target_type)
	# The merchant should now have becomes_visible_calendar_day = current_day
	# (substrate's surface action). Verify.
	var surfaced_id: String = String(locate_result.get("merchant_id", ""))
	check(not surfaced_id.is_empty(), "locate returns merchant_id of the surfaced merchant")
	var surfaced: Dictionary = MerchantPoolRepository.get_merchant(surfaced_id)
	check(int(surfaced.get("becomes_visible_calendar_day", -1)) <= current_day,
		"surfaced merchant now visible (becomes_visible_calendar_day <= current_day)")

	# --- Step 3: Persuade ---
	# Convert the surfaced merchant to deal in a DIFFERENT type.
	var new_type: String = "wood_common" if target_type != "wood_common" else "salt"
	var persuade_state := {
		"character_id": pc_id,
		"location_ref": settlement_id,
		"params_json": JSON.stringify({
			"merchant_id": surfaced_id,
			"target_merchandise_type": new_type,
			"direction": "buy",
		}),
	}
	var persuade_result: Dictionary = PersuadeMerchantsHandler.on_complete(persuade_state, null)
	# Outcome depends on the deterministic _persuade_rng — either success
	# (merchant's type updates to new_type) OR failure (merchant DELETEd since
	# it's transactional). Verify each path.
	if bool(persuade_result.get("success", false)):
		var updated: Dictionary = MerchantPoolRepository.get_merchant(surfaced_id)
		check(String(updated.get("merchandise_type", "")) == new_type,
			"persuade success: merchant's merchandise_type updated to '%s'" % new_type)
	else:
		check(MerchantPoolRepository.get_merchant(surfaced_id).is_empty(),
			"persuade failure: transactional merchant DELETEd")


# ---------------------------------------------------------------------------
# 2. LLM-promotion preservation (§0.1.1 forward-compat hook)
# ---------------------------------------------------------------------------

func test_promoted_merchant_survives_persuade_fail_and_monthly_refresh() -> void:
	var f: Dictionary = _build_fixture()
	var settlement_id: String = f["settlement_id"]
	var pc_id: String = f["pc_id"]
	# Set PC CHA to 3 (-3 mod) and seed -3 demand to force persuade failure.
	CampaignRepository.db.query_with_bindings(
		"UPDATE characters SET charisma = 3 WHERE id = ?", [pc_id])
	# Seed a NPC character to serve as the promoted merchant's link.
	var npc_id: String = _next_id("npc")
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO characters (id, campaign_id, name, character_type) VALUES (?, ?, 'PromotedNPC', 'npc')",
		[npc_id, _campaign_id])
	# Seed a PROMOTED merchant at this settlement (promoted_npc_id IS NOT NULL).
	var promoted_mid: String = _next_id("pm")
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO merchant_pool
			(id, campaign_id, settlement_entrance_id, merchandise_type,
			 loads_available, loads_initial, created_at_calendar_day,
			 expires_at_calendar_day, becomes_visible_calendar_day, status, source_kind,
			 promoted_npc_id)
		VALUES (?, ?, ?, 'wood_common', 5, 5, 0, 999999, 0, 'active', 'monthly_refresh', ?)
	""", [promoted_mid, _campaign_id, settlement_id, npc_id])
	# Seed -3 demand for 'spices' (target type) so persuade fails decisively.
	CampaignRepository.db.query_with_bindings("""
		INSERT OR REPLACE INTO settlement_merchandise_demand
			(settlement_entrance_id, merchandise_type,
			 demand_modifier, pre_trade_route_shift_value,
			 dice_4d4_value, dice_last_rolled_calendar_day,
			 source_kind, generated_at_calendar_day)
		VALUES (?, 'spices', -3, -3, 10, 0, 'manual', 0)
	""", [settlement_id])

	# Try to persuade: CHA -3 + sell direction with -3 demand = -6 total to roll;
	# precious 'spices' threshold = 12. Max roll = 12 + (-6) = 6 < 12 → fails.
	var persuade_state := {
		"character_id": pc_id,
		"location_ref": settlement_id,
		"params_json": JSON.stringify({
			"merchant_id": promoted_mid,
			"target_merchandise_type": "spices",
			"direction": "sell",
		}),
	}
	var captured := {"outcome": ""}
	var cb: Callable = func(_mid: String, _sid: String, _mt: String, outcome: String) -> void:
		captured["outcome"] = outcome
	EventBus.merchant_persuasion_failed.connect(cb)
	var r: Dictionary = PersuadeMerchantsHandler.on_complete(persuade_state, null)
	EventBus.merchant_persuasion_failed.disconnect(cb)
	check(not bool(r.get("success", true)), "persuade fails decisively")
	check(str(captured["outcome"]) == "refused_cohort",
		"signal outcome = 'refused_cohort' (promoted NPC, not deleted)")
	# Promoted merchant still in the table.
	var still_there: Dictionary = MerchantPoolRepository.get_merchant(promoted_mid)
	check(not still_there.is_empty(), "promoted merchant NOT DELETEd")
	check(still_there.get("refused_at_calendar_day", null) != null,
		"refused_at_calendar_day flag set")
	# Merchant is now hidden from list_visible (refused filter on substrate query).
	var visible_now: Array = MerchantPoolRepository.list_visible_merchants(
		settlement_id, Timekeeping.get_total_days())
	var found_promoted: bool = false
	for m in visible_now:
		if String((m as Dictionary).get("id", "")) == promoted_mid:
			found_promoted = true
			break
	check(not found_promoted,
		"refused promoted merchant hidden from list_visible_merchants")

	# --- Monthly refresh — should re-cycle the promoted row (clear refused flag) ---
	var refresh_rng := RandomNumberGenerator.new()
	refresh_rng.seed = 42
	MerchantPoolRepository.generate_pool_for_settlement(
		settlement_id, Timekeeping.get_total_days() + 30, refresh_rng, false)
	# Verify the promoted row was UPDATEd in place (not DELETEd) and refused
	# flag cleared.
	var after_refresh: Dictionary = MerchantPoolRepository.get_merchant(promoted_mid)
	check(not after_refresh.is_empty(),
		"promoted row survives monthly refresh")
	check(after_refresh.get("refused_at_calendar_day", null) == null,
		"refused_at_calendar_day CLEARED on monthly refresh, got %s" % str(after_refresh.get("refused_at_calendar_day", null)))
	check(int(after_refresh.get("loads_available", 0)) > 0,
		"promoted merchant's loads_available re-rolled to non-zero")


# ---------------------------------------------------------------------------
# 3. Locate-failure fall-through to persuade hint
# ---------------------------------------------------------------------------

func test_locate_failure_suggests_persuade_in_summary() -> void:
	var f: Dictionary = _build_fixture()
	# Seed merchants of only ONE type so locate fails for any other type.
	for _i in 3:
		var mid: String = _next_id("salt")
		CampaignRepository.db.query_with_bindings("""
			INSERT INTO merchant_pool
				(id, campaign_id, settlement_entrance_id, merchandise_type,
				 loads_available, loads_initial, created_at_calendar_day,
				 expires_at_calendar_day, becomes_visible_calendar_day, status, source_kind)
			VALUES (?, ?, ?, 'salt', 5, 5, 0, 999999, 0, 'active', 'monthly_refresh')
		""", [mid, _campaign_id, f["settlement_id"]])
	# Locate 'gems' — no matching merchant.
	var state := {
		"character_id": f["pc_id"],
		"location_ref": f["settlement_id"],
		"params_json": JSON.stringify({"merchandise_type": "gems"}),
	}
	var r: Dictionary = LocateMerchandiseHandler.on_complete(state, null)
	check(not bool(r.get("success", true)),
		"locate fails for absent type")
	check(String(r.get("summary", "")).contains("persuad"),
		"failure summary mentions persuade fall-through (§7.5.2 hint): '%s'" % String(r.get("summary", "")))
