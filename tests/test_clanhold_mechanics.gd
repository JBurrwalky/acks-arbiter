extends "res://tests/test_suite_base.gd"

## Phase 11D.2 — Clanhold mechanics (style-driven, alignment-agnostic).
##
## Tests the suite of clanhold-only RAW exceptions from
## `rules/ax_domains_of_chaos.xml` §exceptions_from_clanholds L76-86:
##
##   * L79: Land revenue halved past 125 fam/hex.
##   * L82-83: Investment value halved (2,000gp per 1d10 new families).
##   * L86: Garrison cost +2gp/family (hard floor in expense calculator).
##   * L77-78: Tighter classification advancement gates (50mi borderlands /
##     25mi civilized) + same-realm requirement on the friendly settlement.
##   * L36 (military): chieftains cannot conscript peasants or levy militia.
##   * L48-51 (vassalage limits): chieftains cannot impose call_to_council /
##     loans / charter_of_monopoly / grant_of_land obligations.
##
## All mechanics fire on `domains.domain_style == 'clanhold'` regardless of
## alignment per gdd-domain-style-and-alignment.md §2 + §4.

const TEST_CAMPAIGN := "test_clanhold_mech_campaign"
const TEST_RULER := "test_clanhold_mech_ruler"
const TEST_DOMAIN := "test_clanhold_mech_domain"
const TEST_SETTLEMENT := "test_clanhold_mech_settlement"


func run_all_tests() -> void:
	_cleanup()
	# Revenue + land halving (RAW L79)
	test_clanhold_revenue_land_halved_above_125()
	test_civilized_revenue_no_land_halving()
	# Growth + investment halving (RAW L82-83)
	test_clanhold_growth_investment_halved_at_2000gp_per_roll()
	test_civilized_growth_investment_1000gp_per_roll_unchanged()
	# Expense calculator garrison floor (RAW L86)
	test_clanhold_expense_garrison_floor_doubled()
	test_civilized_expense_garrison_floor_unchanged()
	# Classification advancement distance gates (RAW L77-78)
	test_clanhold_advancement_borderlands_50mi_gate()
	test_clanhold_advancement_civilized_25mi_gate()
	test_clanhold_advancement_same_realm_required()
	test_civilized_advancement_distance_gates_unchanged()
	# Chieftain vassalage limits (RAW L36, L48-51)
	test_clanhold_conscript_troops_blocked()
	test_clanhold_levy_militia_blocked()
	test_civilized_conscript_troops_allowed()
	test_civilized_levy_militia_allowed()
	test_clanhold_grant_monopoly_blocked()
	_cleanup()
	if not has_failures():
		print("ClanholdMechanics: all tests passed.")


# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

func _setup() -> void:
	_cleanup()
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[TEST_CAMPAIGN, "Clanhold Mechanics Test"])
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_type, persistence_tier,
			 race, character_class, level, xp, combat_progression,
			 strength, intelligence, wisdom, dexterity, constitution, charisma,
			 alignment, is_active)
		VALUES (?, ?, ?, 'pc', 'full', 'human', 'fighter', 9, 0,
		        'fighter', 13, 10, 10, 10, 10, 10, 'chaotic', 1)
	""", [TEST_RULER, TEST_CAMPAIGN, "Test Clanhold Ruler"])


func _cleanup() -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM monopoly_holdings WHERE settlement_id = ?", [TEST_SETTLEMENT])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM settlement_entrances WHERE id = ?", [TEST_SETTLEMENT])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM domain_departure_log WHERE domain_id = ?", [TEST_DOMAIN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM troop_units WHERE assigned_domain_id = ?", [TEST_DOMAIN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM domain_hexes WHERE domain_id = ?", [TEST_DOMAIN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM domains WHERE id = ?", [TEST_DOMAIN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM characters WHERE id = ?", [TEST_RULER])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [TEST_CAMPAIGN])


func _make_domain(style: String, peasants: int = 100) -> Dictionary:
	return {
		"id": TEST_DOMAIN,
		"campaign_id": TEST_CAMPAIGN,
		"name": "Test Domain",
		"owner_character_id": TEST_RULER,
		"territory_type": "wilderness",
		"peasant_families": peasants,
		"domain_style": style,
		"alignment": "neutral",
		"religion": "",
		"tax_rate_cp_per_family": 200,
		"liturgy_rate_cp_per_family": 100,
		"tithe_rate_cp_per_family": 100,
		"tribute_out_owed": 0,
		"repression_cp_per_family_this_month": 0,
	}


func _make_hex(land_value: int = 5) -> Dictionary:
	return {"land_value": land_value, "land_improvement_level": 0}


# ---------------------------------------------------------------------------
# Revenue land halving (RAW L79)
# ---------------------------------------------------------------------------

func test_clanhold_revenue_land_halved_above_125() -> void:
	# 1 hex, 200 peasants, land_value=4gp.
	# Civilized rev: 200 × 4 = 800 gp = 80,000 cp.
	# Clanhold rev: 125 × 4 + 75 × 4 / 2 = 500 + 150 = 650 gp = 65,000 cp.
	# Test the clanhold formula.
	var d := _make_domain("clanhold", 200)
	var hexes := [_make_hex(4)]
	var result := DomainRevenueCalculator.calculate_monthly_revenue(d, hexes, 1000, 0)
	check(int(result["land"]) == 65_000,
		"clanhold land revenue at 200 fam/hex with 4gp land = 65,000 cp; got %d"
		% int(result["land"]))


func test_civilized_revenue_no_land_halving() -> void:
	# Same inputs, civilized: full 200 × 4 = 800 gp = 80,000 cp.
	var d := _make_domain("civilized", 200)
	var hexes := [_make_hex(4)]
	var result := DomainRevenueCalculator.calculate_monthly_revenue(d, hexes, 1000, 0)
	check(int(result["land"]) == 80_000,
		"civilized land revenue at 200 fam/hex with 4gp land = 80,000 cp; got %d"
		% int(result["land"]))


# ---------------------------------------------------------------------------
# Growth investment halving (RAW L82-83)
# ---------------------------------------------------------------------------

func test_clanhold_growth_investment_halved_at_2000gp_per_roll() -> void:
	# Scripted roller: returns count*8 for any call (1d10 with +8 per die).
	# Investment 4,000 gp + clanhold = 4000/2000 = 2 rolls.
	# investment_bonus = roller.call(10, 2, false) = 16.
	# Other dice phases: population=100, so groups=1 → 4 calls (random+/-,
	# morale tier=Apathetic → 0 dice).
	# Population=100 < 1000, so groups=1 each. Just check investment_bonus.
	var d := _make_domain("clanhold", 100)
	var dice_call_log: Array = []
	var roller := func(_faces: int, count: int, _exp: bool) -> int:
		dice_call_log.append(count)
		return count * 8
	var result := DomainGrowthResolver.resolve_growth(
		d, 100_000, 4000,
		DomainMoraleResolver.TIER_APATHETIC,
		false, false, roller)
	# With investment_gp=4000 and clanhold 2000gp/roll, expect 2 investment dice.
	check(int(result["investment_bonus"]) == 16,
		"clanhold 4000gp investment → 2 rolls × 8 = 16; got %d"
		% int(result["investment_bonus"]))


func test_civilized_growth_investment_1000gp_per_roll_unchanged() -> void:
	# Same setup but civilized: 4000gp / 1000 = 4 rolls × 8 = 32.
	var d := _make_domain("civilized", 100)
	var roller := func(_faces: int, count: int, _exp: bool) -> int:
		return count * 8
	var result := DomainGrowthResolver.resolve_growth(
		d, 100_000, 4000,
		DomainMoraleResolver.TIER_APATHETIC,
		false, false, roller)
	check(int(result["investment_bonus"]) == 32,
		"civilized 4000gp investment → 4 rolls × 8 = 32; got %d"
		% int(result["investment_bonus"]))


# ---------------------------------------------------------------------------
# Expense calculator garrison floor (RAW L86)
# ---------------------------------------------------------------------------

func test_clanhold_expense_garrison_floor_doubled() -> void:
	# 100 peasants, no actual garrison paid, no income gate.
	# Civilized floor: 100 × 200 cp = 20,000 cp.
	# Clanhold floor:  100 × 400 cp = 40,000 cp (RAW L86 +2gp).
	var d := _make_domain("clanhold", 100)
	var result := DomainExpenseCalculator.calculate_monthly_expenses(d, 0, false)
	check(int(result["garrison"]) == 40_000,
		"clanhold garrison hard floor at 100 fam = 40,000 cp; got %d"
		% int(result["garrison"]))


func test_civilized_expense_garrison_floor_unchanged() -> void:
	var d := _make_domain("civilized", 100)
	var result := DomainExpenseCalculator.calculate_monthly_expenses(d, 0, false)
	check(int(result["garrison"]) == 20_000,
		"civilized garrison hard floor at 100 fam = 20,000 cp; got %d"
		% int(result["garrison"]))


# ---------------------------------------------------------------------------
# Classification advancement distance gates (RAW L77-78)
# ---------------------------------------------------------------------------

func test_clanhold_advancement_borderlands_50mi_gate() -> void:
	# Wilderness clanhold at 60 miles from friendly city. Civilized gate is
	# 72mi (passes), clanhold gate is 50mi (FAILS).
	var d := _make_domain("clanhold", 2000)  # 16 hexes × 125 = saturated
	d["territory_type"] = "wilderness"
	var clanhold_result := ClassificationAdvancement.check_classification_change(
		d, 16, false, 0, 60, false, true)  # 60mi, same_realm=true
	check(not bool(clanhold_result["advanced"]),
		"clanhold at 60mi exceeds 50mi gate; should NOT advance; got %s"
		% str(clanhold_result["advanced"]))
	# Civilized at the same distance SHOULD advance.
	var d_civ := _make_domain("civilized", 2000)
	d_civ["territory_type"] = "wilderness"
	var civ_result := ClassificationAdvancement.check_classification_change(
		d_civ, 16, false, 0, 60, false, true)
	check(bool(civ_result["advanced"]),
		"civilized at 60mi within 72mi gate; should advance; got %s"
		% str(civ_result["advanced"]))


func test_clanhold_advancement_civilized_25mi_gate() -> void:
	# Borderlands clanhold at 30 miles. Civilized gate is 48mi (passes),
	# clanhold gate is 25mi (FAILS).
	var d := _make_domain("clanhold", 4000)  # 16 hexes × 250 = borderlands sat
	d["territory_type"] = "borderlands"
	var clanhold_result := ClassificationAdvancement.check_classification_change(
		d, 16, false, 0, 30, false, true)
	check(not bool(clanhold_result["advanced"]),
		"clanhold at 30mi exceeds 25mi civilized gate; should NOT advance; got %s"
		% str(clanhold_result["advanced"]))


func test_clanhold_advancement_same_realm_required() -> void:
	# Clanhold at 40mi (within 50mi gate) BUT friendly city is in a DIFFERENT
	# realm. Should NOT advance.
	var d := _make_domain("clanhold", 2000)
	d["territory_type"] = "wilderness"
	var result := ClassificationAdvancement.check_classification_change(
		d, 16, false, 0, 40, false,
		false)  # friendly_settlement_same_realm = false
	check(not bool(result["advanced"]),
		"clanhold at 40mi but cross-realm friendly city; should NOT advance; got %s"
		% str(result["advanced"]))


func test_civilized_advancement_distance_gates_unchanged() -> void:
	# Civilized domains ignore the same-realm flag (it defaults to true and is
	# only consulted for clanhold paths).
	var d := _make_domain("civilized", 2000)
	d["territory_type"] = "wilderness"
	var result := ClassificationAdvancement.check_classification_change(
		d, 16, false, 0, 60, false, false)  # cross-realm but civilized doesn't care
	check(bool(result["advanced"]),
		"civilized at 60mi within 72mi gate; same_realm=false ignored; got %s"
		% str(result["advanced"]))


# ---------------------------------------------------------------------------
# Chieftain vassalage limits (RAW L36, L48-51)
# ---------------------------------------------------------------------------

func test_clanhold_conscript_troops_blocked() -> void:
	_setup()
	# Insert a clanhold-style domain owned by TEST_RULER.
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO domains (id, campaign_id, name, owner_character_id,
		                     territory_type, peasant_families, domain_style)
		VALUES (?, ?, ?, ?, 'wilderness', 100, 'clanhold')
	""", [TEST_DOMAIN, TEST_CAMPAIGN, "Clanhold Test", TEST_RULER])
	var state: Dictionary = {
		"character_id": TEST_RULER,
		"params_json": "{}",
	}
	var result: Dictionary = ConscriptTroopsHandler.on_complete(state, null)
	check(String(result.get("blocked_reason", "")) == "clanhold_style_no_conscription",
		"clanhold conscript_troops blocked with explicit reason; got %s"
		% str(result.get("blocked_reason", "")))


func test_clanhold_levy_militia_blocked() -> void:
	_setup()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO domains (id, campaign_id, name, owner_character_id,
		                     territory_type, peasant_families, domain_style)
		VALUES (?, ?, ?, ?, 'wilderness', 100, 'clanhold')
	""", [TEST_DOMAIN, TEST_CAMPAIGN, "Clanhold Test", TEST_RULER])
	var state: Dictionary = {
		"character_id": TEST_RULER,
		"params_json": "{}",
	}
	var result: Dictionary = LevyMilitiaHandler.on_complete(state, null)
	check(String(result.get("blocked_reason", "")) == "clanhold_style_no_militia",
		"clanhold levy_militia blocked with explicit reason; got %s"
		% str(result.get("blocked_reason", "")))


func test_civilized_conscript_troops_allowed() -> void:
	_setup()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO domains (id, campaign_id, name, owner_character_id,
		                     territory_type, peasant_families, domain_style)
		VALUES (?, ?, ?, ?, 'wilderness', 100, 'civilized')
	""", [TEST_DOMAIN, TEST_CAMPAIGN, "Civilized Test", TEST_RULER])
	var state: Dictionary = {
		"character_id": TEST_RULER,
		"params_json": "{}",
	}
	var result: Dictionary = ConscriptTroopsHandler.on_complete(state, null)
	# Civilized should NOT have a blocked_reason.
	check(String(result.get("blocked_reason", "")).is_empty(),
		"civilized conscript_troops should NOT be blocked; got reason=%s"
		% str(result.get("blocked_reason", "")))


func test_civilized_levy_militia_allowed() -> void:
	_setup()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO domains (id, campaign_id, name, owner_character_id,
		                     territory_type, peasant_families, domain_style)
		VALUES (?, ?, ?, ?, 'wilderness', 100, 'civilized')
	""", [TEST_DOMAIN, TEST_CAMPAIGN, "Civilized Test", TEST_RULER])
	var state: Dictionary = {
		"character_id": TEST_RULER,
		"params_json": "{}",
	}
	var result: Dictionary = LevyMilitiaHandler.on_complete(state, null)
	check(String(result.get("blocked_reason", "")).is_empty(),
		"civilized levy_militia should NOT be blocked; got reason=%s"
		% str(result.get("blocked_reason", "")))


func test_clanhold_grant_monopoly_blocked() -> void:
	_setup()
	# Clanhold-style domain with a settlement child.
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO domains (id, campaign_id, name, owner_character_id,
		                     territory_type, peasant_families, domain_style)
		VALUES (?, ?, ?, ?, 'wilderness', 100, 'clanhold')
	""", [TEST_DOMAIN, TEST_CAMPAIGN, "Clanhold Settlement Parent", TEST_RULER])
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_entrances
			(id, campaign_id, parent_domain_id, name, settlement_kind,
			 urban_families, market_class)
		VALUES (?, ?, ?, ?, 'town', 100, 6)
	""", [TEST_SETTLEMENT, TEST_CAMPAIGN, TEST_DOMAIN, "Clanhold Town"])
	var grant_id: String = MonopolyRegistry.grant_monopoly(
		TEST_RULER, TEST_SETTLEMENT, "iron_ingots",
		1, "", "domain_ruler", null, "test")
	check(grant_id.is_empty(),
		"clanhold parent domain should block monopoly grant; got id=%s" % grant_id)
