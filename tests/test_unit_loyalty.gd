extends "res://tests/test_suite_base.gd"

## RAW Unit Loyalty for the NON-tribal troop source types (2026-08-03).
##
## The roll itself, the carryover columns and the tribal-warrior departure path
## are covered by `test_tribal_warriors.gd` and are not re-tested here. This
## suite covers what the 2026-08-03 build added:
##
##   * Who rolls — the RAW source-type gate (daw_armies_recruitment.xml:99 /
##     :353 / :458 / :477 / :611) and the vassal-troops exclusion.
##   * The :483 religious-fanatic exemption, with a non-fanatic control.
##   * Per-source-type departure disposition — desertion (:355 / :461 / :612)
##     vs leaving service (:103 / :104), and the :461-vs-:462 distinction that
##     makes a deserting militiaman NOT go home.
##   * Enmity fielding a real hostile force (:103), and the bands that do not.
##   * Militia desertion relieving the standing levy penalty WITHOUT the
##     permanent population loss that only battle DEATHS cause (:432).
##   * The militia season-of-continuous-campaigning calamity (:459).

const TEST_CAMPAIGN := "test_ul_campaign"
const TEST_RULER := "test_ul_ruler"
const TEST_DOMAIN := "test_ul_domain"


func run_all_tests() -> void:
	_cleanup()
	# Who rolls at all
	test_every_raw_source_type_rolls()
	test_vassal_troops_make_no_roll_of_their_own()
	test_religious_fanatic_followers_are_exempt_with_a_control()
	# Departure disposition
	test_mercenary_departure_leaves_service()
	test_conscript_and_slave_soldier_departures_are_desertion()
	test_deserting_militia_do_not_return_to_their_farms()
	# Enmity → hostile force
	test_enmity_fields_a_real_hostile_force()
	test_only_enmity_fields_a_force()
	test_mutineers_keep_their_own_troop_type_and_prorated_strength()
	test_mutineers_are_not_assigned_to_the_domain_they_turned_on()
	# The militia levy-penalty interaction
	test_militia_desertion_relieves_the_levy_penalty()
	test_militia_desertion_does_not_cost_the_domain_population()
	# RAW :459 continuous campaigning
	test_a_season_on_campaign_fires_the_militia_calamity()
	test_campaigning_shorter_than_a_season_does_not_fire()
	test_coming_off_campaign_clears_the_anchor()
	test_only_militia_accrue_the_campaigning_calamity()
	# Chronicle
	test_non_tribal_departures_use_their_own_departure_log_event_type()
	test_a_unit_with_no_domain_rolls_and_departs_cleanly()
	_cleanup()


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

class _FakeDice:
	var _queue: Array[int] = []
	var _last: int = 7

	func _init(totals: Array) -> void:
		for t in totals:
			_queue.append(int(t))

	func roll(_count: int, _sides: int) -> int:
		if _queue.is_empty():
			return _last
		_last = _queue.pop_front()
		return _last


class _StubRunner:
	var _cid: String = ""
	func _init(cid: String) -> void:
		_cid = cid
	func get_campaign_id() -> String:
		return _cid


func _setup() -> void:
	_cleanup()
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[TEST_CAMPAIGN, "Unit Loyalty Test"])
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_type, persistence_tier,
			 race, character_class, level, xp, combat_progression,
			 strength, intelligence, wisdom, dexterity, constitution, charisma,
			 alignment, is_active)
		VALUES (?, ?, 'UL Ruler', 'pc', 'full', 'human', 'fighter', 9, 0, 'fighter',
		        10, 10, 10, 10, 10, 10, 'lawful', 1)
	""", [TEST_RULER, TEST_CAMPAIGN])
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO domains
			(id, campaign_id, name, owner_character_id, territory_type,
			 peasant_families, alignment, religion, effective_religion,
			 domain_style, establishment_method, established_calendar_day, morale)
		VALUES (?, ?, 'Test Domain', ?, 'borderlands', 100, 'lawful',
		        'lawful-church', 'lawful-church', 'civilized', 'claim', 1, 0)
	""", [TEST_DOMAIN, TEST_CAMPAIGN, TEST_RULER])


func _cleanup() -> void:
	# Mutiny armies own their own captain NPC and troop rows, neither of which
	# is keyed to the test domain — sweep by campaign so a fielded force cannot
	# leak into the next test's counts.
	for t in ["army_unit_assignments", "army_officers"]:
		CampaignRepository.db.query(
			"DELETE FROM %s WHERE army_id IN (SELECT id FROM armies WHERE campaign_id = '%s')"
				% [t, TEST_CAMPAIGN])
	for t in ["armies", "troop_units", "characters", "domain_departure_log"]:
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM %s WHERE campaign_id = ?" % t, [TEST_CAMPAIGN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM domains WHERE id = ?", [TEST_DOMAIN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [TEST_CAMPAIGN])


## Insert a troop unit of any source type and return its id.
func _insert_unit(source_type: String, count: int, morale: int,
		assignment_kind: String = "garrison", troop_type: String = "light_infantry",
		religious_fanatic: bool = false) -> String:
	var unit_id: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO troop_units
			(id, campaign_id, owner_character_id, assigned_domain_id,
			 source_type, troop_type, race, tier, starting_count, count,
			 battle_rating, monthly_wage_cp, monthly_supply_cp, monthly_cost_cp,
			 morale, assignment_kind, status, is_religious_fanatic)
		VALUES (?, ?, ?, ?, ?, ?, 'human', 'average', ?, ?,
		        1.0, 30000, 10000, 40000, ?, ?, 'active', ?)
	""", [unit_id, TEST_CAMPAIGN, TEST_RULER, TEST_DOMAIN,
		source_type, troop_type, count, count, morale, assignment_kind,
		1 if religious_fanatic else 0])
	return unit_id


func _armies_in_campaign() -> Array:
	CampaignRepository.db.query_with_bindings(
		"SELECT * FROM armies WHERE campaign_id = ?", [TEST_CAMPAIGN])
	return CampaignRepository.db.query_result.duplicate()


# ---------------------------------------------------------------------------
# Who rolls
# ---------------------------------------------------------------------------

func test_every_raw_source_type_rolls() -> void:
	# RAW grants the Unit Loyalty roll to mercenaries (:99), conscripts (:353),
	# militia (:458), followers (:477), slave soldiers (:611) and tribal
	# warriors (ax_domains_of_chaos.xml:454). Before this build only the last
	# rolled; every other source type silently ignored every calamity.
	_setup()
	for source_type in ["mercenary", "conscript", "militia", "follower", "slave_soldier"]:
		var unit_id: String = _insert_unit(source_type, 60, 0)
		var res: Dictionary = UnitLoyaltyResolver.roll_loyalty(unit_id,
			[UnitLoyaltyResolver.CALAMITY_ROUT], 30, _FakeDice.new([7]))
		check(bool(res.get("ok", false)),
			"%s makes a Unit Loyalty roll, got error '%s'"
				% [source_type, String(res.get("error", ""))])
		check(String(res.get("source_type", "")) == source_type,
			"the result reports the source type it rolled for")
	_cleanup()


func test_vassal_troops_make_no_roll_of_their_own() -> void:
	# RAW §vassal_troops gives vassal troops no loyalty rule; it says a vassal's
	# garrison "is some mix of followers, mercenaries, conscripts, and militia",
	# i.e. they ARE those types once mustered. Rolling for source_type='vassal'
	# would be inventing a rule, so the gate must exclude it explicitly rather
	# than by accident.
	_setup()
	var unit_id: String = _insert_unit("vassal", 60, 0)
	var res: Dictionary = UnitLoyaltyResolver.roll_loyalty(unit_id,
		[UnitLoyaltyResolver.CALAMITY_ROUT], 30, _FakeDice.new([2]))
	check(not bool(res.get("ok", true)), "vassal troops do not roll")
	check(String(res.get("error", "")) == "source_type_does_not_roll",
		"and the reason names the gate, got '%s'" % String(res.get("error", "")))
	var row: Dictionary = TroopUnitRepository.get_unit(unit_id)
	check(String(row.get("status", "")) == "active",
		"a 2 that never got rolled cannot have ended their service")
	_cleanup()


func test_religious_fanatic_followers_are_exempt_with_a_control() -> void:
	# RAW :481-483 — "Cleric and bladedancer followers are religious fanatics …
	# Religious fanatics do not make loyalty rolls for calamities, but still
	# make morale rolls in battle."
	#
	# The CONTROL is the whole test: an ordinary follower unit with identical
	# stats takes the same guaranteed-Enmity roll and DOES depart. Without it,
	# "the fanatic survived" would pass just as happily if followers had been
	# excluded from the roll altogether, or if the dice had missed the band.
	_setup()
	var fanatic: String = _insert_unit("follower", 60, 0, "garrison", "heavy_infantry", true)
	var ordinary: String = _insert_unit("follower", 60, 0, "garrison", "heavy_infantry", false)

	var exempt: Dictionary = UnitLoyaltyResolver.roll_loyalty(fanatic,
		[UnitLoyaltyResolver.CALAMITY_ROUT], 30, _FakeDice.new([2]))
	check(not bool(exempt.get("ok", true)), "a religious fanatic does not roll")
	check(String(exempt.get("error", "")) == "religious_fanatic_exempt",
		"and reports the RAW reason, got '%s'" % String(exempt.get("error", "")))
	check(String(TroopUnitRepository.get_unit(fanatic).get("status", "")) == "active",
		"the faithful stay")

	var rolled: Dictionary = UnitLoyaltyResolver.roll_loyalty(ordinary,
		[UnitLoyaltyResolver.CALAMITY_ROUT], 30, _FakeDice.new([2]))
	check(bool(rolled.get("ok", false)), "CONTROL: an ordinary follower does roll")
	check(bool(rolled.get("departs", false)),
		"CONTROL: and the same 2 ends their service, proving the band was reachable")
	_cleanup()


# ---------------------------------------------------------------------------
# Departure disposition
# ---------------------------------------------------------------------------

func test_mercenary_departure_leaves_service() -> void:
	# RAW :104 — Resignation means "leave service at the first advantageous safe
	# moment". Per Jedidiah (2026-08-03) v1 resolves that immediately, matching
	# the tribal-warrior precedent.
	_setup()
	var unit_id: String = _insert_unit("mercenary", 60, 0)
	var res: Dictionary = UnitLoyaltyResolver.roll_loyalty(unit_id,
		[UnitLoyaltyResolver.CALAMITY_UNPAID], 30, _FakeDice.new([4]))
	check(String(res.get("outcome", "")) == UnitLoyaltyResolver.OUTCOME_RESIGNATION,
		"2d6 4 + morale 0 = 4 → Resignation")
	check(bool(res.get("departs", false)), "they leave")
	check(String(res.get("disposition", "")) == UnitLoyaltyResolver.DISPOSITION_LEFT_SERVICE,
		"mercenaries leave service rather than desert, got '%s'"
			% String(res.get("disposition", "")))
	check(String(TroopUnitRepository.get_unit(unit_id).get("departure_kind", ""))
		== UnitLoyaltyResolver.DEPARTURE_RESIGNATION, "the row records why")
	_cleanup()


func test_conscript_and_slave_soldier_departures_are_desertion() -> void:
	# RAW :355 — conscripts "cannot voluntarily leave service; loyalty results
	# that would cause departure represent desertion." RAW :612 — slave soldiers
	# behave "like conscripts".
	_setup()
	for source_type in ["conscript", "slave_soldier"]:
		var unit_id: String = _insert_unit(source_type, 60, 0)
		var res: Dictionary = UnitLoyaltyResolver.roll_loyalty(unit_id,
			[UnitLoyaltyResolver.CALAMITY_UNPAID], 30, _FakeDice.new([4]))
		check(bool(res.get("departs", false)), "%s departs on Resignation" % source_type)
		check(String(res.get("disposition", "")) == UnitLoyaltyResolver.DISPOSITION_DESERTED,
			"%s cannot resign, so the departure is desertion, got '%s'"
				% [source_type, String(res.get("disposition", ""))])
	_cleanup()


func test_deserting_militia_do_not_return_to_their_farms() -> void:
	# The easy mistake in this rule. RAW :462 — "If voluntarily RELEASED, militia
	# return to their farms" — is the leader's decision, a different event from a
	# failed loyalty roll. RAW :461 says militia "cannot voluntarily leave
	# service, but may desert". So a failed roll scatters them; it does not send
	# them home, and it must not be modelled as the release path.
	_setup()
	var unit_id: String = _insert_unit("militia", 60, 0)
	var res: Dictionary = UnitLoyaltyResolver.roll_loyalty(unit_id,
		[UnitLoyaltyResolver.CALAMITY_ROUT], 30, _FakeDice.new([4]))
	check(String(res.get("disposition", "")) == UnitLoyaltyResolver.DISPOSITION_DESERTED,
		"militia desert (:461); they do not take the :462 release path, got '%s'"
			% String(res.get("disposition", "")))
	check(int(res.get("returned_to_pool", -1)) == 0,
		"nobody goes home, got %d" % int(res.get("returned_to_pool", -1)))
	_cleanup()


# ---------------------------------------------------------------------------
# Enmity fields a real force (RAW :103, Jedidiah 2026-08-03)
# ---------------------------------------------------------------------------

func test_enmity_fields_a_real_hostile_force() -> void:
	# RAW :103 — troops leaving in Enmity "may attack or stage a coup if the
	# employer is vulnerable, or seek service with a strong enemy." Per Jedidiah
	# (2026-08-03) that becomes real troops on the map. A BR-0 phantom army would
	# be the same bug ThreatForceComposer was built to fix (conventions §100), so
	# assert the actual troop row, not just the armies row.
	_setup()
	var unit_id: String = _insert_unit("mercenary", 60, 0)
	var res: Dictionary = UnitLoyaltyResolver.roll_loyalty(unit_id,
		[UnitLoyaltyResolver.CALAMITY_UNPAID], 30, _FakeDice.new([2]))
	check(String(res.get("outcome", "")) == UnitLoyaltyResolver.OUTCOME_ENMITY,
		"2d6 2 + morale 0 = 2 → Enmity")
	var army_id: String = String(res.get("fielded_army_id", ""))
	check(not army_id.is_empty(), "an army was fielded")

	var armies: Array = _armies_in_campaign()
	check(armies.size() == 1, "exactly one hostile army, got %d" % armies.size())
	var owner: String = String((armies[0] as Dictionary).get("political_owner_id", ""))
	check(not owner.is_empty() and owner != TEST_RULER,
		"it belongs to its own captain, not the employer it turned on")

	CampaignRepository.db.query_with_bindings("""
		SELECT tu.count, tu.status FROM troop_units tu
		JOIN army_unit_assignments a ON a.troop_unit_id = tu.id
		WHERE a.army_id = ?
	""", [army_id])
	var fielded: Array = CampaignRepository.db.query_result.duplicate()
	check(fielded.size() == 1, "the army carries a real troop unit, got %d rows" % fielded.size())
	check(int((fielded[0] as Dictionary).get("count", 0)) == 60,
		"all 60 survivors took the field, got %d"
			% int((fielded[0] as Dictionary).get("count", 0)))
	_cleanup()


func test_only_enmity_fields_a_force() -> void:
	# The ruling was "Enmity only": Resignation (:104) and the two-consecutive-
	# Grudging departure (:105) end service without anyone taking up arms. Also
	# pins the standing GDD §7.4 / Q-TW-8 exemption — a tribal-warrior Enmity
	# still fields nothing — so extending it stays Jedidiah's call rather than a
	# silent side effect of this build.
	_setup()
	var resigning: String = _insert_unit("mercenary", 60, 0)
	var res: Dictionary = UnitLoyaltyResolver.roll_loyalty(resigning,
		[UnitLoyaltyResolver.CALAMITY_ROUT], 30, _FakeDice.new([4]))
	check(bool(res.get("departs", false)), "Resignation still ends service")
	check(String(res.get("fielded_army_id", "")).is_empty(),
		"but fields nothing")

	var grudging: String = _insert_unit("conscript", 60, 0)
	UnitLoyaltyResolver.roll_loyalty(grudging,
		[UnitLoyaltyResolver.CALAMITY_ROUT], 30, _FakeDice.new([7]))
	var second: Dictionary = UnitLoyaltyResolver.roll_loyalty(grudging,
		[UnitLoyaltyResolver.CALAMITY_ROUT], 31, _FakeDice.new([7]))
	check(bool(second.get("departs", false)), "two consecutive Grudging ends service (:105)")
	check(String(second.get("fielded_army_id", "")).is_empty(),
		"and fields nothing either")

	var tribal: String = _insert_unit("tribal_warrior", 60, 0)
	var tw: Dictionary = UnitLoyaltyResolver.roll_loyalty(tribal,
		[UnitLoyaltyResolver.CALAMITY_ROUT], 32, _FakeDice.new([2]))
	check(String(tw.get("outcome", "")) == UnitLoyaltyResolver.OUTCOME_ENMITY,
		"the tribal unit did roll Enmity")
	check(String(tw.get("fielded_army_id", "")).is_empty(),
		"tribal warriors keep their Q-TW-8 exemption from the brigand branch")

	check(_armies_in_campaign().is_empty(),
		"no army was created by any of the three, got %d" % _armies_in_campaign().size())
	_cleanup()


func test_mutineers_keep_their_own_troop_type_and_prorated_strength() -> void:
	# RAW :103 describes soldiers turning on an employer, not a company
	# degenerating into rabble — heavy cavalry that mutinies is still heavy
	# cavalry. Strength is prorated because `battle_rating` is stored for
	# `starting_count` and casualties only decrement `count`; a company that
	# mutinies at half strength must not field its full roster's BR.
	_setup()
	var unit_id: String = _insert_unit("mercenary", 60, 0, "garrison", "heavy_cavalry")
	CampaignRepository.db.query_with_bindings(
		"UPDATE troop_units SET starting_count = 120, battle_rating = 2.0 WHERE id = ?",
		[unit_id])

	var res: Dictionary = UnitLoyaltyResolver.roll_loyalty(unit_id,
		[UnitLoyaltyResolver.CALAMITY_ROUT], 30, _FakeDice.new([2]))
	var army_id: String = String(res.get("fielded_army_id", ""))
	check(not army_id.is_empty(), "the mutiny fielded an army")

	CampaignRepository.db.query_with_bindings("""
		SELECT tu.* FROM troop_units tu
		JOIN army_unit_assignments a ON a.troop_unit_id = tu.id
		WHERE a.army_id = ?
	""", [army_id])
	var row: Dictionary = CampaignRepository.db.query_result[0]
	check(String(row.get("troop_type", "")) == "heavy_cavalry",
		"they are still heavy cavalry, got '%s'" % String(row.get("troop_type", "")))
	check(abs(float(row.get("battle_rating", 0.0)) - 1.0) < 0.001,
		"BR prorated 60/120 of 2.0 = 1.0, got %f" % float(row.get("battle_rating", 0.0)))
	check(int(row.get("monthly_wage_cp", -1)) == 0,
		"mutineers carry no payroll — they live by pillage")
	_cleanup()


func test_mutineers_are_not_assigned_to_the_domain_they_turned_on() -> void:
	# If the new row kept `assigned_domain_id`, the domain would go on counting
	# these troops in its garrison, its wage bill and — for militia — its RAW
	# :429-431 levy penalty, for soldiers that just took the field against it.
	_setup()
	var unit_id: String = _insert_unit("militia", 20, 0)
	var res: Dictionary = UnitLoyaltyResolver.roll_loyalty(unit_id,
		[UnitLoyaltyResolver.CALAMITY_ROUT], 30, _FakeDice.new([2]))
	check(not String(res.get("fielded_army_id", "")).is_empty(), "a force was fielded")

	CampaignRepository.db.query_with_bindings(
		"SELECT COUNT(*) AS n FROM troop_units WHERE assigned_domain_id = ? AND status = 'active'",
		[TEST_DOMAIN])
	check(int(CampaignRepository.db.query_result[0].get("n", -1)) == 0,
		"the domain has no active troops left, got %d"
			% int(CampaignRepository.db.query_result[0].get("n", -1)))
	check(LevyPenaltyCalculator.levied_peasants_for_domain(TEST_DOMAIN) == 0,
		"and is not still charged for the militia that mutinied")
	_cleanup()


# ---------------------------------------------------------------------------
# Desertion vs the permanent militia population loss
# ---------------------------------------------------------------------------

func test_militia_desertion_relieves_the_levy_penalty() -> void:
	# Conventions §133: the levy-penalty basis is a LIVE query over ACTIVE rows,
	# so `status='departed'` relieves it with no extra wiring. This test exists
	# to pin that the loyalty path did not accidentally bypass it — e.g. by
	# leaving the row active, or by re-homing it to the same domain.
	_setup()
	var unit_id: String = _insert_unit("militia", 20, 0)
	check(LevyPenaltyCalculator.levied_peasants_for_domain(TEST_DOMAIN) == 20,
		"20 peasants under arms before the roll")
	var before: Dictionary = LevyPenaltyCalculator.penalties_for_domain(TEST_DOMAIN, 100)
	check(int(before.get("morale_penalty", 0)) == LevyPenaltyCalculator.MORALE_PENALTY_HEAVY,
		"20 per 100 families is the 2-per-10 heavy band")

	UnitLoyaltyResolver.roll_loyalty(unit_id,
		[UnitLoyaltyResolver.CALAMITY_ROUT], 30, _FakeDice.new([4]))

	check(LevyPenaltyCalculator.levied_peasants_for_domain(TEST_DOMAIN) == 0,
		"deserters stop costing the domain (:431 'until sent home'), got %d"
			% LevyPenaltyCalculator.levied_peasants_for_domain(TEST_DOMAIN))
	var after: Dictionary = LevyPenaltyCalculator.penalties_for_domain(TEST_DOMAIN, 100)
	check(int(after.get("morale_penalty", -99)) == 0, "morale penalty lifts")
	check(int(after.get("revenue_family_reduction", -99)) == 0, "revenue penalty lifts")
	_cleanup()


func test_militia_desertion_does_not_cost_the_domain_population() -> void:
	# RAW :432 makes the population + morale loss permanent when militia are
	# KILLED. Deserters are not dead — they walked off. `ArmyCasualtyResolver`
	# accumulates its militia population loss from the battle `crippled` count
	# only, and nothing on the loyalty path may reach it; if the two were ever
	# wired together, a domain would be permanently depopulated by a bad 2d6.
	_setup()
	var unit_id: String = _insert_unit("militia", 20, 0)
	var before: Dictionary = CampaignRepository.get_domain(TEST_DOMAIN)

	UnitLoyaltyResolver.roll_loyalty(unit_id,
		[UnitLoyaltyResolver.CALAMITY_ROUT], 30, _FakeDice.new([2]))

	var after: Dictionary = CampaignRepository.get_domain(TEST_DOMAIN)
	check(int(after.get("peasant_families", -1)) == int(before.get("peasant_families", -2)),
		"peasant_families untouched by desertion (%d → %d)"
			% [int(before.get("peasant_families", -2)), int(after.get("peasant_families", -1))])
	check(int(after.get("morale", -99)) == int(before.get("morale", -98)),
		"and no permanent morale loss either (%d → %d)"
			% [int(before.get("morale", -98)), int(after.get("morale", -99))])
	_cleanup()


# ---------------------------------------------------------------------------
# RAW :459 — a season of continuous campaigning is a calamity (militia only)
# ---------------------------------------------------------------------------

func test_a_season_on_campaign_fires_the_militia_calamity() -> void:
	# RAW :459. The anchor is maintained inside the monthly tick, so the first
	# tick under arms only ANCHORS; the calamity needs a full season to elapse
	# after it. The tick owns its own dice, so morale is set to -20 to put every
	# possible 2d6 in the 2- Enmity band (conventions §132) — "departed" then
	# deterministically means "rolled".
	_setup()
	var unit_id: String = _insert_unit("militia", 20, -20, "on_campaign")
	var handlers := DomainHandlers.new(_StubRunner.new(TEST_CAMPAIGN))

	handlers._tick_unit_loyalty(TEST_DOMAIN, 100)
	var anchored: Dictionary = TroopUnitRepository.get_unit(unit_id)
	check(int(anchored.get("campaigning_since_calendar_day", 0)) == 100,
		"the first tick anchors the stretch, got %d"
			% int(anchored.get("campaigning_since_calendar_day", 0)))
	check(String(anchored.get("status", "")) == "active",
		"and does not itself fire a calamity")

	handlers._tick_unit_loyalty(TEST_DOMAIN, 100 + UnitLoyaltyResolver.SEASON_DAYS)
	var rolled: Dictionary = TroopUnitRepository.get_unit(unit_id)
	check(String(rolled.get("status", "")) == "departed",
		"a full season under arms fires the calamity (morale -20 makes any roll Enmity)")
	_cleanup()


func test_campaigning_shorter_than_a_season_does_not_fire() -> void:
	# The boundary. One day short of RAW's 91-day season is not a season — and
	# 3 months (84 days), the tempting month-granularity approximation, falls
	# inside this window.
	_setup()
	var unit_id: String = _insert_unit("militia", 20, -20, "on_campaign")
	var handlers := DomainHandlers.new(_StubRunner.new(TEST_CAMPAIGN))

	handlers._tick_unit_loyalty(TEST_DOMAIN, 100)
	handlers._tick_unit_loyalty(TEST_DOMAIN, 100 + UnitLoyaltyResolver.SEASON_DAYS - 1)
	var row: Dictionary = TroopUnitRepository.get_unit(unit_id)
	check(String(row.get("status", "")) == "active",
		"90 days is not a season, so no calamity")
	check(int(row.get("campaigning_since_calendar_day", 0)) == 100,
		"and the anchor still points at the start of the stretch, got %d"
			% int(row.get("campaigning_since_calendar_day", 0)))
	_cleanup()


func test_coming_off_campaign_clears_the_anchor() -> void:
	# ":459 CONTINUOUS campaigning" — a unit that stands down for a month starts
	# over. Without the clear this would accumulate across unrelated campaigns
	# and fire on a unit that had been home for years.
	_setup()
	var unit_id: String = _insert_unit("militia", 20, -20, "on_campaign")
	var handlers := DomainHandlers.new(_StubRunner.new(TEST_CAMPAIGN))

	handlers._tick_unit_loyalty(TEST_DOMAIN, 100)
	TroopUnitRepository.update_unit(unit_id, {"assignment_kind": "garrison"})
	handlers._tick_unit_loyalty(TEST_DOMAIN, 128)
	check(int(TroopUnitRepository.get_unit(unit_id).get("campaigning_since_calendar_day", -1)) == 0,
		"coming off campaign clears the anchor, got %d"
			% int(TroopUnitRepository.get_unit(unit_id).get("campaigning_since_calendar_day", -1)))

	# Back under arms, a full season after the ORIGINAL anchor: still nothing,
	# because the stretch restarted.
	TroopUnitRepository.update_unit(unit_id, {"assignment_kind": "on_campaign"})
	handlers._tick_unit_loyalty(TEST_DOMAIN, 156)
	handlers._tick_unit_loyalty(TEST_DOMAIN, 100 + UnitLoyaltyResolver.SEASON_DAYS)
	check(String(TroopUnitRepository.get_unit(unit_id).get("status", "")) == "active",
		"the broken stretch does not count toward a season")
	_cleanup()


func test_only_militia_accrue_the_campaigning_calamity() -> void:
	# RAW :459 is printed in the militia chapter and nowhere else — mercenaries
	# campaign for a living. The control matters because the anchor column is on
	# every troop row, so "everyone accrues it" would be an easy accident.
	_setup()
	var merc: String = _insert_unit("mercenary", 20, -20, "on_campaign")
	var conscript: String = _insert_unit("conscript", 20, -20, "on_campaign")
	var handlers := DomainHandlers.new(_StubRunner.new(TEST_CAMPAIGN))

	handlers._tick_unit_loyalty(TEST_DOMAIN, 100)
	handlers._tick_unit_loyalty(TEST_DOMAIN, 100 + UnitLoyaltyResolver.SEASON_DAYS)

	for unit_id in [merc, conscript]:
		var row: Dictionary = TroopUnitRepository.get_unit(unit_id)
		check(String(row.get("status", "")) == "active",
			"%s does not suffer the militia campaigning calamity"
				% String(row.get("source_type", "")))
		check(int(row.get("campaigning_since_calendar_day", -1)) == 0,
			"and never even takes an anchor, got %d"
				% int(row.get("campaigning_since_calendar_day", -1)))
	_cleanup()


# ---------------------------------------------------------------------------
# Chronicle
# ---------------------------------------------------------------------------

func test_non_tribal_departures_use_their_own_departure_log_event_type() -> void:
	# Conventions §131: the log must not assert something false. The
	# migration-129 type is named `tribal_warriors_loyalty_failed`, so a
	# departing mercenary company gets migration 214's `troop_unit_loyalty_failed`
	# instead. `DepartureLogRecorder.record` rejects any type absent from its
	# list, so a missing registration would silently drop the line entirely —
	# the exact bug the 2026-08-01 note in that file describes.
	_setup()
	var unit_id: String = _insert_unit("mercenary", 60, 0)
	UnitLoyaltyResolver.roll_loyalty(unit_id,
		[UnitLoyaltyResolver.CALAMITY_UNPAID], 30, _FakeDice.new([4]))

	var entries: Array = DepartureLogRecorder.list_for_domain(TEST_DOMAIN, 20)
	var found: Dictionary = {}
	for e in entries:
		if String((e as Dictionary).get("event_type", "")) == "troop_unit_loyalty_failed":
			found = e
	check(not found.is_empty(),
		"the departure was chronicled under the non-tribal event type")
	var details: Variant = JSON.parse_string(String(found.get("full_details_json", "{}")))
	check(details is Dictionary
			and String((details as Dictionary).get("source_type", "")) == "mercenary",
		"and the metadata records which source type left")
	check(details is Dictionary
			and String((details as Dictionary).get("disposition", ""))
				== UnitLoyaltyResolver.DISPOSITION_LEFT_SERVICE,
		"and where they went")
	_cleanup()


func test_a_unit_with_no_domain_rolls_and_departs_cleanly() -> void:
	# Regression, conventions §106. `troop_units.assigned_domain_id` is NULLABLE,
	# and `row.get(key, default)` returns the STORED null rather than the default
	# when the key exists — so `String(row.get("assigned_domain_id", ""))` throws
	# "Invalid call. Nonexistent 'String' constructor" at runtime.
	#
	# This was latent for as long as tribal warriors were the only source type
	# that rolled, because a levied warrior always has a clanhold. Generalizing
	# the roll immediately hit it: every unit an army carries without a home
	# domain now rolls too, and the crash aborted `_chronicle` and
	# `_return_warriors_to_clanhold` mid-function on the out-of-supply path.
	# It passes `--check-only` and only fails when a real null flows through,
	# which is exactly why it needs a test rather than a reading.
	_setup()
	var unit_id: String = _insert_unit("mercenary", 40, 0)
	CampaignRepository.db.query_with_bindings(
		"UPDATE troop_units SET assigned_domain_id = NULL WHERE id = ?", [unit_id])

	var res: Dictionary = UnitLoyaltyResolver.roll_loyalty(unit_id,
		[UnitLoyaltyResolver.CALAMITY_OUT_OF_SUPPLY], 30, _FakeDice.new([4]))
	check(bool(res.get("ok", false)),
		"a homeless unit still rolls, got error '%s'" % String(res.get("error", "")))
	check(bool(res.get("departs", false)), "and departs on Resignation")
	check(String(res.get("disposition", "")) == UnitLoyaltyResolver.DISPOSITION_LEFT_SERVICE,
		"with its disposition resolved rather than lost to an aborted function")
	check(String(TroopUnitRepository.get_unit(unit_id).get("status", "")) == "departed",
		"and the row was actually written")

	# The Enmity branch reaches further into nullable territory — the mutiny
	# composer looks up a stronghold location for a domain that does not exist.
	var second: String = _insert_unit("mercenary", 40, 0)
	CampaignRepository.db.query_with_bindings(
		"UPDATE troop_units SET assigned_domain_id = NULL WHERE id = ?", [second])
	var enmity: Dictionary = UnitLoyaltyResolver.roll_loyalty(second,
		[UnitLoyaltyResolver.CALAMITY_OUT_OF_SUPPLY], 31, _FakeDice.new([2]))
	check(bool(enmity.get("ok", false)), "the Enmity path survives a null domain too")
	check(not String(enmity.get("fielded_army_id", "")).is_empty(),
		"and still fields the mutineers, with no map position to place them at")
	_cleanup()
