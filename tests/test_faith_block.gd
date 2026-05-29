extends "res://tests/test_suite_base.gd"

## Tests for Phase 10A.2 — Faith block.
##
## Covers the 8 divine activity handlers + the FaithMonthlyResolver monthly
## integration. Each test isolates one handler / resolver step against a
## minimal campaign + cleric ruler fixture.
##
## Test naming: test_<handler>_<scenario>. Each test resets the relevant
## state at the top so test order does not matter.


var _campaign_id: String = ""
var _ruler_id: String = ""
var _chaotic_caster_id: String = ""
var _lawful_caster_id: String = ""
var _domain_id: String = ""


func run_all_tests() -> void:
	_setup()

	# Dispatch missionaries (Restricted, monthly).
	test_dispatch_missionaries_accrues_pending_gp()
	test_dispatch_missionaries_zero_gp_no_op()

	# Cast charitable spells (Singular minor).
	test_cast_charitable_spells_accrues_pending_gp()

	# Consecrate altar (Ongoing major).
	test_consecrate_altar_completes_and_inserts_row()
	test_consecrate_altar_dp_substitution()

	# Consecrate fields (Ongoing major; magic-research throw).
	test_consecrate_fields_insufficient_dp_aborts()
	test_consecrate_fields_consumes_dp_and_enqueues_effect()

	# Consecrate ruler (Restricted yearly).
	test_consecrate_ruler_below_level_9_aborts()
	test_consecrate_ruler_consumes_dp_and_enqueues_buff()

	# Extract divine power (Restricted weekly).
	test_extract_dp_below_50_congregants_fails()
	test_extract_dp_base_formula_congregants_div_5_times_10()
	test_extract_dp_stamps_last_extraction()

	# Perform blood sacrifice (Restricted daily, Chaotic only).
	test_blood_sacrifice_lawful_caster_aborts()
	test_blood_sacrifice_chaotic_caster_adds_xp_as_dp()

	# Perform ceremonial sacrifice (Restricted daily, Lawful only).
	test_ceremonial_sacrifice_chaotic_caster_aborts()
	test_ceremonial_sacrifice_lawful_caster_accrues_pending_gp()

	# FaithMonthlyResolver — monthly tick integration.
	test_monthly_congregant_growth_4500_gp_rolls_four_times()
	test_monthly_congregant_upkeep_paid_from_dp()
	test_monthly_congregant_attrition_when_unpaid()
	test_monthly_pre_resolve_consecrate_fields_bonus()
	test_monthly_pre_resolve_consecrate_ruler_active_buff()
	test_monthly_expire_stale_effects()

	if not has_failures():
		print("FaithBlock: all tests passed.")


# ---------------------------------------------------------------------------
# Fixture
# ---------------------------------------------------------------------------

func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("Test Faith", "TestWorld")

	_ruler_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, combat_progression, level,
			strength, intelligence, wisdom, dexterity, constitution, charisma,
			alignment, hp_max, hp_current)
		VALUES (?, ?, 'Test Bishop', 'pc', 'full', 'human', 'cleric', 'cleric', 9,
			10, 12, 15, 10, 10, 14, 'lawful', 60, 60)
	""", [_ruler_id, _campaign_id])

	_chaotic_caster_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, combat_progression, level,
			strength, intelligence, wisdom, dexterity, constitution, charisma,
			alignment, hp_max, hp_current)
		VALUES (?, ?, 'Test Cultist', 'pc', 'full', 'human', 'cleric', 'cleric', 7,
			10, 12, 14, 10, 10, 10, 'chaotic', 45, 45)
	""", [_chaotic_caster_id, _campaign_id])

	_lawful_caster_id = _ruler_id  # alias for clarity in lawful-only tests

	_domain_id = CampaignRepository.create_domain({
		"campaign_id": _campaign_id,
		"name": "Test Diocese",
		"territory_type": "borderlands",
		"owner_character_id": _ruler_id,
	})
	# create_domain doesn't take monthly-state fields; set them via the
	# monthly-state updater so they're persisted onto the row.
	# All money columns are now cp (1 gp = 100 cp) per the unified standard.
	CampaignRepository.update_domain_monthly_state(_domain_id, {
		"peasant_families": 500,
		"treasury_cp": 100_000,   # 1,000 gp working balance
		"revenue_cp":  300_000,   # 3,000 gp monthly revenue (used by consecrate_ruler DP cost)
	})


func _state_for(character_id: String, activity_def_id: String, params: Dictionary = {}) -> Dictionary:
	return {
		"id": "test_state_id_%s" % activity_def_id,
		"character_id": character_id,
		"activity_def_id": activity_def_id,
		"params_json": JSON.stringify(params),
		"started_calendar_day": 1,
	}


# ---------------------------------------------------------------------------
# dispatch_missionaries
# ---------------------------------------------------------------------------

func test_dispatch_missionaries_accrues_pending_gp() -> void:
	CampaignRepository.upsert_congregants(_ruler_id, {
		"count": 0, "monthly_growth_pending_cp": 0,
	})
	# Launcher commits 800 gp → executor stores 80,000 cp in state column.
	var state := _state_for(_ruler_id, "dispatch_missionaries", {"gp_committed": 800})
	state["cp_committed"] = 80_000  # mirrors what the executor writes to the column
	var result := DispatchMissionariesHandler.on_complete(state, null)
	check(not String(result.get("summary", "")).is_empty(),
		"handler should return a summary")
	var row := CampaignRepository.get_congregants(_ruler_id)
	check(int(row.get("monthly_growth_pending_cp", 0)) == 80_000,
		"pending_cp should be 80,000 (= 800 gp), got %s" % str(row.get("monthly_growth_pending_cp", 0)))


func test_dispatch_missionaries_zero_gp_no_op() -> void:
	CampaignRepository.upsert_congregants(_ruler_id, {
		"count": 0, "monthly_growth_pending_cp": 0,
	})
	var state := _state_for(_ruler_id, "dispatch_missionaries", {"gp_committed": 0})
	state["cp_committed"] = 0
	var result := DispatchMissionariesHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("no cp"),
		"summary should note zero cp; got '%s'" % result.get("summary", ""))
	var row := CampaignRepository.get_congregants(_ruler_id)
	check(int(row.get("monthly_growth_pending_cp", 0)) == 0,
		"pending_gp should remain 0")


# ---------------------------------------------------------------------------
# cast_charitable_spells
# ---------------------------------------------------------------------------

func test_cast_charitable_spells_accrues_pending_gp() -> void:
	CampaignRepository.upsert_congregants(_ruler_id, {
		"count": 0, "monthly_growth_pending_cp": 0,
	})
	# Launcher reports 150 gp of charitable spell value → handler stores 15,000 cp.
	var state := _state_for(_ruler_id, "cast_charitable_spells", {
		"gp_value_total": 150, "spell_keys": ["bless", "cure_light_wounds"],
	})
	var result := CastCharitableSpellsHandler.on_complete(state, null)
	check(not String(result.get("summary", "")).is_empty(), "should return summary")
	var row := CampaignRepository.get_congregants(_ruler_id)
	check(int(row.get("monthly_growth_pending_cp", 0)) == 15_000,
		"pending_cp should be 15,000 (= 150 gp), got %s" % str(row.get("monthly_growth_pending_cp", 0)))


# ---------------------------------------------------------------------------
# consecrate_altar
# ---------------------------------------------------------------------------

func test_consecrate_altar_completes_and_inserts_row() -> void:
	var prior_count := CampaignRepository.list_consecrated_altars_for_character(_ruler_id).size()
	var state := _state_for(_ruler_id, "consecrate_altar", {
		"gp_invested": 2500,
		"alignment": "lawful",
		"location_kind": "stronghold",
		"location_ref": _domain_id,
	})
	var result := ConsecrateAltarHandler.on_complete(state, null)
	check(not String(result.get("summary", "")).is_empty(), "should return summary")
	var altars := CampaignRepository.list_consecrated_altars_for_character(_ruler_id)
	check(altars.size() == prior_count + 1,
		"altar row should be inserted (prior=%d new=%d)" % [prior_count, altars.size()])
	var most_recent: Dictionary = altars[altars.size() - 1]
	check(String(most_recent.get("status", "")) == "completed",
		"new altar should have status='completed', got '%s'" % most_recent.get("status", ""))
	# Aura size: 100 sq ft per 100 gp = 1 sq ft per gp = 2500 sq ft.
	check(int(most_recent.get("aura_size_sq_ft", 0)) == 2500,
		"aura_size_sq_ft should equal gp_invested for 100sq ft/100gp ratio, got %d" % most_recent.get("aura_size_sq_ft", 0))


func test_consecrate_altar_dp_substitution() -> void:
	# Substitute 500 gp DP (= 50,000 cp) for 500 gp altar value; total aura
	# should include both.
	var state := _state_for(_ruler_id, "consecrate_altar", {
		"gp_invested": 500,
		"dp_substituted_cp": 50000,
		"alignment": "lawful",
		"location_kind": "stronghold",
		"location_ref": _domain_id,
	})
	var prior_count := CampaignRepository.list_consecrated_altars_for_character(_ruler_id).size()
	ConsecrateAltarHandler.on_complete(state, null)
	var altars := CampaignRepository.list_consecrated_altars_for_character(_ruler_id)
	check(altars.size() == prior_count + 1, "altar inserted")
	# list ordering is by (started_calendar_day, id) which UUID-sorts. Filter
	# by dp_substituted_cp > 0 to pick the row this test created (the prior
	# test's altar has dp_substituted_cp=0).
	var dp_altar: Dictionary = {}
	for r: Dictionary in altars:
		if int(r.get("dp_substituted_cp", 0)) > 0:
			dp_altar = r
			break
	check(not dp_altar.is_empty(), "should find the dp-substituted altar")
	check(int(dp_altar.get("aura_size_sq_ft", 0)) == 1000,
		"aura_size_sq_ft should be 1000 (500 gp + 500 dp), got %d" % dp_altar.get("aura_size_sq_ft", 0))
	check(int(dp_altar.get("dp_substituted_cp", 0)) == 50000,
		"dp_substituted_cp recorded")


# ---------------------------------------------------------------------------
# consecrate_fields
# ---------------------------------------------------------------------------

func test_consecrate_fields_insufficient_dp_aborts() -> void:
	# 500 families × 2 gp = 1000 gp DP required = 100,000 cp. Seed balance to
	# 10,000 cp (= 100 gp); handler must abort with insufficient DP.
	CampaignRepository.add_divine_power_cp(_ruler_id, -CampaignRepository.get_divine_power_cp(_ruler_id))
	CampaignRepository.add_divine_power_cp(_ruler_id, 10_000)
	var state := _state_for(_ruler_id, "consecrate_fields")
	var result := ConsecrateFieldsHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("insufficient"),
		"summary should report insufficient DP; got '%s'" % result.get("summary", ""))
	# DP balance unchanged.
	check(CampaignRepository.get_divine_power_cp(_ruler_id) == 10_000,
		"DP balance should be unchanged on insufficient-DP abort")


func test_consecrate_fields_consumes_dp_and_enqueues_effect() -> void:
	# Reset DP to a generous balance: 5,000 gp = 500,000 cp.
	CampaignRepository.add_divine_power_cp(_ruler_id, -CampaignRepository.get_divine_power_cp(_ruler_id))
	CampaignRepository.add_divine_power_cp(_ruler_id, 500_000)
	var prior_pending := CampaignRepository.list_pending_divine_effects_due(
		_domain_id, 99999, "consecrate_fields_land_value").size()
	var state := _state_for(_ruler_id, "consecrate_fields")
	var result := ConsecrateFieldsHandler.on_complete(state, null)
	check(not String(result.get("summary", "")).is_empty(), "summary present")
	# DP debited by 500 fam × 2 gp = 1,000 gp = 100,000 cp; remaining 400,000 cp.
	var new_dp := CampaignRepository.get_divine_power_cp(_ruler_id)
	check(new_dp == 400_000,
		"DP should be 400,000 cp after 100,000 cp debit, got %d" % new_dp)
	# Whether or not the throw succeeded, the handler should have done the
	# debit. A pending effect is enqueued IFF the throw was success or
	# natural-1 — non-natural-1 failures simply don't enqueue.
	# We can't deterministically force throw outcomes here without dice
	# injection; just confirm that EITHER no new pending row OR a new pending
	# row with the expected payload shape.
	var new_pending := CampaignRepository.list_pending_divine_effects_due(
		_domain_id, 99999, "consecrate_fields_land_value")
	# Either no change, or a new row with a delta_gp_per_family of +1 or -1.
	if new_pending.size() > prior_pending:
		var most_recent: Dictionary = new_pending[new_pending.size() - 1]
		var payload: Variant = JSON.parse_string(String(most_recent.get("effect_payload_json", "{}")))
		check(payload is Dictionary, "payload should be a dict")
		var delta: int = int((payload as Dictionary).get("delta_gp_per_family", 0))
		check(delta == 1 or delta == -1,
			"delta_gp_per_family should be +1 (success) or -1 (natural 1), got %d" % delta)


# ---------------------------------------------------------------------------
# consecrate_ruler
# ---------------------------------------------------------------------------

func test_consecrate_ruler_below_level_9_aborts() -> void:
	var state := _state_for(_chaotic_caster_id, "consecrate_ruler", {})
	var result := ConsecrateRulerHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("level 9"),
		"L7 caster should fail with level-9 requirement; got '%s'" % result.get("summary", ""))


func test_consecrate_ruler_consumes_dp_and_enqueues_buff() -> void:
	# Ruler's domain monthly revenue is 3,000 gp = 300,000 cp (set in _setup).
	# Give the caster 500,000 cp DP (= 5,000 gp) and confirm 300,000 cp is
	# consumed, leaving 200,000 cp.
	CampaignRepository.add_divine_power_cp(_ruler_id, -CampaignRepository.get_divine_power_cp(_ruler_id))
	CampaignRepository.add_divine_power_cp(_ruler_id, 500_000)
	var state := _state_for(_ruler_id, "consecrate_ruler", {
		"ruler_character_id": _ruler_id,
	})
	ConsecrateRulerHandler.on_complete(state, null)
	check(CampaignRepository.get_divine_power_cp(_ruler_id) == 200_000,
		"DP should be 500,000 - 300,000 = 200,000 cp, got %d" % CampaignRepository.get_divine_power_cp(_ruler_id))
	# Whether success or natural-1, an 'applied' row should exist with a buff
	# payload. (Ordinary failure produces no row.)
	var active := CampaignRepository.list_active_divine_effects(_domain_id, 1, "consecrate_ruler_buff")
	# Probabilistic — either no row (ordinary failure), or one row with buff
	# bonus +1/-1.
	if not active.is_empty():
		var row: Dictionary = active[0]
		var payload: Variant = JSON.parse_string(str(row.get("effect_payload_json", "{}")))
		check(payload is Dictionary, "buff payload is dict")
		var bonus: int = int((payload as Dictionary).get("base_morale_bonus", 0))
		check(bonus == 1 or bonus == -1,
			"base_morale_bonus should be +1 (success) or -1 (natural 1), got %d" % bonus)


# ---------------------------------------------------------------------------
# extract_divine_power
# ---------------------------------------------------------------------------

func test_extract_dp_below_50_congregants_fails() -> void:
	CampaignRepository.upsert_congregants(_ruler_id, {
		"count": 49, "monthly_growth_pending_cp": 0,
	})
	var state := _state_for(_ruler_id, "extract_divine_power")
	var result := ExtractDivinePowerHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("50+"),
		"should fail with 50+ requirement; got '%s'" % result.get("summary", ""))


func test_extract_dp_base_formula_congregants_div_5_times_10() -> void:
	# 250 congregants → base_dp = 250 / 5 = 50 gp = 5,000 cp. Ruler bonus is
	# randomized (0..8 per 10 families with 500 families = 0..400 gp bonus,
	# 0..40,000 cp); verify DP increases by AT LEAST 5,000 cp.
	CampaignRepository.upsert_congregants(_ruler_id, {
		"count": 250, "monthly_growth_pending_cp": 0,
	})
	CampaignRepository.add_divine_power_cp(_ruler_id, -CampaignRepository.get_divine_power_cp(_ruler_id))
	var state := _state_for(_ruler_id, "extract_divine_power")
	ExtractDivinePowerHandler.on_complete(state, null)
	var new_dp := CampaignRepository.get_divine_power_cp(_ruler_id)
	check(new_dp >= 5_000,
		"DP should increase by >= 5,000 cp (50 gp) from congregants/5×10 formula, got %d" % new_dp)


func test_extract_dp_stamps_last_extraction() -> void:
	CampaignRepository.upsert_congregants(_ruler_id, {
		"count": 100, "monthly_growth_pending_cp": 0,
	})
	CampaignRepository.set_divine_power_last_extraction(_ruler_id, 0)
	var state := _state_for(_ruler_id, "extract_divine_power")
	ExtractDivinePowerHandler.on_complete(state, null)
	var row := CampaignRepository.get_character_divine_power(_ruler_id)
	check(int(row.get("last_extraction_calendar_day", 0)) > 0,
		"last_extraction_calendar_day should be stamped > 0")


# ---------------------------------------------------------------------------
# perform_blood_sacrifice
# ---------------------------------------------------------------------------

func test_blood_sacrifice_lawful_caster_aborts() -> void:
	var state := _state_for(_ruler_id, "perform_blood_sacrifice", {
		"sacrifice_xp_values": [100, 200],
	})
	var result := PerformBloodSacrificeHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("chaotic"),
		"lawful caster should fail chaotic requirement; got '%s'" % result.get("summary", ""))


func test_blood_sacrifice_chaotic_caster_adds_xp_as_dp() -> void:
	CampaignRepository.add_divine_power_cp(_chaotic_caster_id, -CampaignRepository.get_divine_power_cp(_chaotic_caster_id))
	# Chaotic caster L7 → up to 7 sacrifices per session. 3 XP values; should all be consumed.
	# Total XP = 50+100+300 = 450 gp DP = 45,000 cp.
	var state := _state_for(_chaotic_caster_id, "perform_blood_sacrifice", {
		"sacrifice_xp_values": [50, 100, 300],
	})
	PerformBloodSacrificeHandler.on_complete(state, null)
	var new_dp := CampaignRepository.get_divine_power_cp(_chaotic_caster_id)
	check(new_dp == 45_000,
		"DP should be (50+100+300) gp × 100 = 45,000 cp, got %d" % new_dp)


# ---------------------------------------------------------------------------
# perform_ceremonial_sacrifice
# ---------------------------------------------------------------------------

func test_ceremonial_sacrifice_chaotic_caster_aborts() -> void:
	var state := _state_for(_chaotic_caster_id, "perform_ceremonial_sacrifice", {
		"gp_value_total": 100,
	})
	var result := PerformCeremonialSacrificeHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("lawful"),
		"chaotic caster should fail lawful requirement; got '%s'" % result.get("summary", ""))


func test_ceremonial_sacrifice_lawful_caster_accrues_pending_gp() -> void:
	CampaignRepository.upsert_congregants(_lawful_caster_id, {
		"count": 0, "monthly_growth_pending_cp": 0,
	})
	# 75 gp offering → handler stores 7,500 cp.
	var state := _state_for(_lawful_caster_id, "perform_ceremonial_sacrifice", {
		"gp_value_total": 75,
	})
	PerformCeremonialSacrificeHandler.on_complete(state, null)
	var row := CampaignRepository.get_congregants(_lawful_caster_id)
	check(int(row.get("monthly_growth_pending_cp", 0)) == 7_500,
		"pending_cp should be 7,500 (= 75 gp), got %s" % str(row.get("monthly_growth_pending_cp", 0)))


# ---------------------------------------------------------------------------
# FaithMonthlyResolver
# ---------------------------------------------------------------------------

func test_monthly_congregant_growth_4500_gp_rolls_four_times() -> void:
	# 4,500 gp pending (= 450,000 cp) → 4 rolls of 1d10+CHA mod (caster CHA=14
	# → +1 mod), each triggered per 100,000 cp (RAW: 1,000 gp).
	# Each roll yields 2..11 (1+1 to 10+1). Expected growth: 8..44. Pending
	# remainder: 50,000 cp (= 500 gp).
	CampaignRepository.upsert_congregants(_ruler_id, {
		"count": 100,
		"monthly_growth_pending_cp": 450_000,
		"last_resolved_calendar_day": 0,
	})
	# Use the caster's actual CHA mod (CHA 14 → +1).
	var result := FaithMonthlyResolver.resolve_congregants_monthly(
		_ruler_id, 1, _domain_id, 28)
	check(int(result.get("pending_cp_consumed", 0)) == 400_000,
		"should consume 400,000 cp (4 × 100,000), got %d" % result.get("pending_cp_consumed", 0))
	check(int(result.get("pending_cp_remaining", 0)) == 50_000,
		"50,000 cp should remain, got %d" % result.get("pending_cp_remaining", 0))
	check(int(result.get("growth_rolled", 0)) >= 8,
		"growth should be >= 8 (4 × min 2), got %d" % result.get("growth_rolled", 0))
	check(int(result.get("growth_rolled", 0)) <= 44,
		"growth should be <= 44 (4 × max 11), got %d" % result.get("growth_rolled", 0))
	# Congregant count should be 100 + growth_rolled - any attrition (none at
	# this pending balance; upkeep covered if DP available).


func test_monthly_congregant_upkeep_paid_from_dp() -> void:
	# 100 congregants × 1 gp = 100 gp upkeep = 10,000 cp. Caster has 100,000
	# cp DP → upkeep paid in full from DP; treasury untouched.
	CampaignRepository.upsert_congregants(_ruler_id, {
		"count": 100, "monthly_growth_pending_cp": 0,
	})
	CampaignRepository.add_divine_power_cp(_ruler_id, -CampaignRepository.get_divine_power_cp(_ruler_id))
	CampaignRepository.add_divine_power_cp(_ruler_id, 100_000)
	var prior_treasury := int(_get_domain_field("treasury_cp"))
	var result := FaithMonthlyResolver.resolve_congregants_monthly(
		_ruler_id, 1, _domain_id, 28)
	check(int(result.get("upkeep_paid", 0)) == 10_000,
		"upkeep_paid should be 10,000 cp (= 100 gp), got %d" % result.get("upkeep_paid", 0))
	check(int(result.get("upkeep_unpaid", 0)) == 0,
		"upkeep_unpaid should be 0")
	check(CampaignRepository.get_divine_power_cp(_ruler_id) == 90_000,
		"DP should be 100,000 - 10,000 = 90,000 cp, got %d" % CampaignRepository.get_divine_power_cp(_ruler_id))
	check(int(_get_domain_field("treasury_cp")) == prior_treasury,
		"treasury_cp should be unchanged when DP covers upkeep")


func test_monthly_congregant_attrition_when_unpaid() -> void:
	# 5,000 congregants × 1 gp = 5,000 gp upkeep = 500,000 cp. DP = 0,
	# treasury = 100,000 cp (= 1,000 gp). After paying 100,000 cp from
	# treasury, 400,000 cp remain unpaid. Attrition: 4 × 1d10 congregants
	# depart (4..40 range) per RAW 1d10 per 1,000 gp unpaid.
	CampaignRepository.upsert_congregants(_ruler_id, {
		"count": 5000, "monthly_growth_pending_cp": 0,
	})
	CampaignRepository.add_divine_power_cp(_ruler_id, -CampaignRepository.get_divine_power_cp(_ruler_id))
	CampaignRepository.update_domain_monthly_state(_domain_id, {"treasury_cp": 100_000})
	var result := FaithMonthlyResolver.resolve_congregants_monthly(
		_ruler_id, 1, _domain_id, 28)
	check(int(result.get("upkeep_paid", 0)) == 100_000,
		"upkeep_paid should be 100,000 cp (= 1,000 gp from treasury), got %d" % result.get("upkeep_paid", 0))
	check(int(result.get("upkeep_unpaid", 0)) == 400_000,
		"upkeep_unpaid should be 400,000 cp (= 4,000 gp), got %d" % result.get("upkeep_unpaid", 0))
	check(int(result.get("attrition", 0)) >= 4 and int(result.get("attrition", 0)) <= 40,
		"attrition should be 4..40 (4 × 1d10), got %d" % result.get("attrition", 0))
	check(int(_get_domain_field("treasury_cp")) == 0,
		"treasury should be drained to 0")


func test_monthly_pre_resolve_consecrate_fields_bonus() -> void:
	# Earlier tests (consecrate_fields_consumes_dp_and_enqueues_effect) may
	# have left 'pending' rows in the table; clear them so we test in isolation.
	_purge_pending_divine_effects()
	# Enqueue a consecrate_fields_land_value pending row that's due today.
	var today := 100
	var effect_id := CampaignRepository.create_pending_divine_effect({
		"domain_id": _domain_id,
		"character_id": _ruler_id,
		"effect_kind": "consecrate_fields_land_value",
		"effect_payload_json": JSON.stringify({"delta_gp_per_family": 1, "peasant_families": 500}),
		"issued_calendar_day": today - 5,
		"applies_at_calendar_day": today,
		"expires_at_calendar_day": today + 1,
		"status": "pending",
	})
	check(not effect_id.is_empty(), "pending row should insert")
	var mods := FaithMonthlyResolver.compute_pre_resolve_modifiers(_domain_id, today)
	check(int(mods.get("consecrate_fields_bonus_per_family", 0)) == 1,
		"bonus should be +1/family, got %d" % mods.get("consecrate_fields_bonus_per_family", 0))
	check((mods.get("consecrate_fields_fired_effect_ids", []) as Array).has(effect_id),
		"the firing effect id should be returned for status flip")
	# Apply the flip and verify the row no longer fires on a subsequent call.
	FaithMonthlyResolver.apply_pending_consecrate_fields([effect_id])
	var mods2 := FaithMonthlyResolver.compute_pre_resolve_modifiers(_domain_id, today)
	check(int(mods2.get("consecrate_fields_bonus_per_family", 0)) == 0,
		"after apply, second call should return 0 bonus")


func test_monthly_pre_resolve_consecrate_ruler_active_buff() -> void:
	_purge_pending_divine_effects()
	var today := 200
	# Create an active 'applied' buff row that hasn't expired yet.
	CampaignRepository.create_pending_divine_effect({
		"domain_id": _domain_id,
		"character_id": _ruler_id,
		"effect_kind": "consecrate_ruler_buff",
		"effect_payload_json": JSON.stringify({
			"base_morale_bonus": 1, "vassal_loyalty_bonus": 1, "vagary_roll_pick": "best_of_two",
		}),
		"issued_calendar_day": today - 30,
		"applies_at_calendar_day": today - 30,
		"expires_at_calendar_day": today + 100,
		"status": "applied",
	})
	var mods := FaithMonthlyResolver.compute_pre_resolve_modifiers(_domain_id, today)
	check(int(mods.get("consecrate_ruler_base_morale_bonus", 0)) == 1,
		"active buff should report +1 base morale, got %d" % mods.get("consecrate_ruler_base_morale_bonus", 0))
	check(int(mods.get("consecrate_ruler_vassal_loyalty_bonus", 0)) == 1,
		"vassal loyalty bonus +1")
	check(String(mods.get("consecrate_ruler_vagary_pick", "")) == "best_of_two",
		"vagary pick recorded")


func test_monthly_expire_stale_effects() -> void:
	var today := 300
	# Create an 'applied' row whose expires_at has passed.
	var effect_id := CampaignRepository.create_pending_divine_effect({
		"domain_id": _domain_id,
		"character_id": _ruler_id,
		"effect_kind": "consecrate_ruler_buff",
		"effect_payload_json": "{}",
		"issued_calendar_day": today - 365,
		"applies_at_calendar_day": today - 365,
		"expires_at_calendar_day": today - 1,  # expired yesterday
		"status": "applied",
	})
	FaithMonthlyResolver.expire_stale_effects(_domain_id, today)
	# After expiration, the row should not appear in list_active_divine_effects.
	var active := CampaignRepository.list_active_divine_effects(_domain_id, today, "consecrate_ruler_buff")
	for row: Dictionary in active:
		check(str(row.get("id", "")) != effect_id,
			"expired row should be filtered out of active list")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _purge_pending_divine_effects() -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM pending_divine_effects WHERE domain_id = ?", [_domain_id])


func _get_domain_field(field: String) -> Variant:
	CampaignRepository.db.query_with_bindings(
		"SELECT %s FROM domains WHERE id = ?" % field, [_domain_id])
	if CampaignRepository.db.query_result.is_empty():
		return null
	return CampaignRepository.db.query_result[0].get(field, null)
