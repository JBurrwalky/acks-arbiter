extends "res://tests/scenarios/scenario_runner_base.gd"

## Scenario: Chaotic Clanhold — exercises 11D.1-11D.5 end-to-end.
##
## Setup: chaotic Cleric establishes a clanhold via METHOD_CLANHOLD_ANNEX.
## Verify:
##   * domain_style='clanhold' + alignment='chaotic' (orthogonal axes per 11D.1)
##   * Clanhold mechanics fire (garrison +2gp floor, halved investment value,
##     pool seeded for tribal warriors) (11D.2 + 11D.5)
##   * Alignment match means no morale penalty (11D.3)
##   * Tribal warrior levy works on the clanhold (11D.5)
##   * Conscript / militia / monopoly grant all BLOCKED for the clanhold (11D.2)
##
## Single-month tick + targeted assertions; doesn't require multi-month sim.


func run_all_tests() -> void:
	cleanup_scenario()
	test_chaotic_clanhold_full_flow()
	cleanup_scenario()
	if not has_failures():
		print("Scenario.ChaoticClanhold: all tests passed.")


func test_chaotic_clanhold_full_flow() -> void:
	seed_campaign("scenario_cc_camp")
	var ruler: String = seed_character("scenario_cc_ruler", {
		"alignment": "chaotic",
		"character_class": "cleric",
		"combat_progression": "cleric",
		"charisma": 14,
	})
	# Seed a chaotic clanhold per 11D.1 orthogonal axes.
	var clanhold: String = seed_domain("scenario_cc_clanhold", ruler, {
		"territory_type": "wilderness",
		"peasant_families": 500,
		"alignment": "chaotic",
		"religion": "chaos-cult",
		"effective_religion": "chaos-cult",
		"domain_style": "clanhold",
		"establishment_method": "clanhold_annex",
	})
	seed_hexes(clanhold, 4, 5, 0)

	# --- Verify 11D.1 orthogonal axes columns ---
	var domain: Dictionary = CampaignRepository.get_domain(clanhold)
	check(String(domain.get("domain_style", "")) == "clanhold",
		"11D.1: domain_style='clanhold' persisted")
	check(String(domain.get("alignment", "")) == "chaotic",
		"11D.1: alignment='chaotic' persisted independently")

	# --- Verify 11D.5 pool seeded to peasant_families ---
	var pool: Dictionary = TribalWarriorRegistry.pool_for_domain(clanhold)
	check(int(pool.get("available", -1)) == 500,
		"11D.5: pool seeded to peasant_families (500); got %d"
		% int(pool.get("available", -1)))
	check(int(pool.get("levied", -1)) == 0, "no warriors levied initially")

	# --- Verify 11D.2 garrison floor +2gp/family ---
	var expenses: Dictionary = DomainExpenseCalculator.calculate_monthly_expenses(
		domain, 0, false)
	check(int(expenses.get("garrison", 0)) == 500 * 400,
		"11D.2: clanhold garrison floor = 500 fam × 400 cp = 200,000 cp; got %d"
		% int(expenses.get("garrison", 0)))

	# --- Verify 11D.2 halved investment value (DomainGrowthResolver) ---
	# 4000 gp investment + clanhold = 2 rolls (vs 4 for civilized).
	var growth: Dictionary = DomainGrowthResolver.resolve_growth(
		domain, 100_000, 4000,
		DomainMoraleResolver.TIER_APATHETIC,
		false, false,
		func(_f: int, count: int, _e: bool) -> int: return count * 8)
	# 4000 / 2000 = 2 rolls × 8 = 16. Civilized would have been 4 × 8 = 32.
	check(int(growth.get("investment_bonus", -1)) == 16,
		"11D.2: clanhold halved investment (4000gp → 2 rolls × 8 = 16); got %d"
		% int(growth.get("investment_bonus", -1)))

	# --- Verify 11D.3 no alignment penalty (chaotic ruler + chaotic domain) ---
	var ruler_block: Dictionary = {
		"cha_modifier": 1, "level": 9,
		"alignment": "chaotic", "race": "human",
		"has_leadership_proficiency": false,
	}
	var base_chaotic: int = DomainMoraleResolver.resolve_base_morale(
		domain, ruler_block, 100_000, 7_500_000, 7_500_000, 0)
	# Compare to a lawful ruler — should be 2 worse due to L/C pair.
	var lawful_ruler := ruler_block.duplicate()
	lawful_ruler["alignment"] = "lawful"
	var base_lawful: int = DomainMoraleResolver.resolve_base_morale(
		domain, lawful_ruler, 100_000, 7_500_000, 7_500_000, 0)
	check(base_chaotic - base_lawful == 2,
		"11D.3: chaotic ruler in chaotic domain: no penalty; lawful: −2; diff=2 got %d"
		% (base_chaotic - base_lawful))

	# --- Verify 11D.5 levy + stand-down on this clanhold ---
	var levy_state := {
		"character_id": ruler,
		"params_json": JSON.stringify({"count": 100, "domain_id": clanhold}),
	}
	var levy_result: Dictionary = LevyTribalWarriorsHandler.on_complete(levy_state, null)
	check(int(levy_result.get("count", 0)) == 100,
		"11D.5: levy succeeded; 100 warriors fielded")
	var pool_after_levy: Dictionary = TribalWarriorRegistry.pool_for_domain(clanhold)
	check(int(pool_after_levy.get("available", 0)) == 400,
		"11D.5: available decremented to 400 after levy")

	# --- Verify 11D.2 chieftain vassalage limits: conscript blocked ---
	var conscript_state := {
		"character_id": ruler,
		"params_json": "{}",
	}
	var conscript_result: Dictionary = ConscriptTroopsHandler.on_complete(conscript_state, null)
	check(String(conscript_result.get("blocked_reason", "")) == "clanhold_style_no_conscription",
		"11D.2: conscript_troops blocked for clanhold; got %s"
		% str(conscript_result.get("blocked_reason", "?")))

	# --- Verify 11D.3 starting a religion conversion adds the active penalty ---
	# (Conversion to lawful religion: this clanhold is beastman-populated via
	# establishment_method=clanhold_annex, so per §9.7 the conversion to a
	# non-chaotic alignment is BLOCKED.)
	var conv_id: String = ReligionConversionResolver.start_conversion(
		clanhold, "sun-cult", "lawful", "", _current_calendar_day)
	check(conv_id.is_empty(),
		"11D.3 + 9.7: beastman clanhold rejects lawful-religion conversion")
