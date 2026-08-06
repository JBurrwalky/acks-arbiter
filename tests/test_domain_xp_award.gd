extends "res://tests/test_suite_base.gd"
## R-7a — domain income actually becomes character experience.
##
## Covers the four defects the ruling names, each with a regression lock:
##   1. `XPAwardCalculator.calculate_domain_xp` had no callers — the RAW gp
##      threshold was never subtracted. Now `calculate_domain_xp_cp` is pinned
##      against the gp-native form at 100:1 so a unit slip cannot pass.
##   2. `domains.domain_xp_this_month` was read by nothing — no character ever
##      gained a point. Now asserted to land on `characters.xp`.
##   3. The stored value was raw COPPER handed to a gp table (a 100x inflation
##      waiting for its first reader).
##   4. `int(round(x * 1.05))` rounded half away from zero. The multiplier is
##      gone (it was mis-cited RAW) and the surviving arithmetic is banker's.
##
## The `resolve()` tests drive the resolver directly with a synthetic month
## result rather than through the economy, so the assertions pin the XP rules
## instead of whatever revenue the fixture happens to produce. One integration
## test runs the real monthly tick and checks the wiring holds end to end.

var _campaign_id: String = ""


func run_all_tests() -> void:
	_campaign_id = CampaignRepository.create_campaign("Domain XP Award Tests", "World")

	test_cp_threshold_matches_the_raw_gp_table()
	test_cp_and_gp_forms_agree_at_100_to_1()
	test_sub_gp_remainder_rounds_half_to_even()
	test_henchman_earns_half_rounded_once()
	test_award_service_persists_atomically()
	test_award_service_ignores_non_positive_amounts()
	test_ownerless_domain_is_skipped()
	test_income_below_the_lowest_threshold_earns_nothing()
	test_award_reaches_the_rulers_xp_column()
	test_double_award_guard_blocks_a_repeated_day()
	test_one_level_cap_bounds_the_award()
	test_full_tier_npc_ruler_levels_automatically()
	test_pc_ruler_is_not_auto_leveled()
	test_named_tier_stub_banks_xp_without_leveling()
	test_administer_domain_adds_five_percent()
	test_administration_and_prime_req_round_once_together()
	test_monthly_tick_records_the_raw_figure_and_stamps_the_guard()

	if not has_failures():
		print("DomainXpAward: all tests passed (%d checks)." % test_count())


## Minimal SessionRunner stand-in — DomainHandlers only ever calls
## get_campaign_id() (its one other _runner use is has_method-guarded).
class FakeRunner:
	var campaign_id: String
	func _init(cid: String) -> void:
		campaign_id = cid
	func get_campaign_id() -> String:
		return campaign_id


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _make_ruler(tag: String, opts: Dictionary = {}) -> String:
	return CampaignRepository.create_character({
		"campaign_id": _campaign_id,
		"name": "Ruler %s" % tag,
		"character_type": String(opts.get("character_type", "npc")),
		"persistence_tier": String(opts.get("persistence_tier", "full")),
		"character_class": String(opts.get("character_class", "fighter")),
		"level": int(opts.get("level", 1)),
		"xp": int(opts.get("xp", 0)),
		"xp_for_next_level": int(opts.get("xp_for_next_level", 2000)),
		"xp_adjustment_percent": int(opts.get("xp_adjustment_percent", 0)),
		"max_level": int(opts.get("max_level", 14)),
		"alignment": "lawful",
		# The tick's RulerLodManager.sync lazily builds a disposition for any
		# ruler it promotes, and that needs a personality to read.
		"personality": NpcPersonality.new().to_json(),
	})


func _make_domain(tag: String, owner_id: String, opts: Dictionary = {}) -> String:
	var domain_id := CampaignRepository.create_domain({
		"campaign_id": _campaign_id,
		"name": "Domain %s" % tag,
		"owner_character_id": owner_id,
		"territory_type": String(opts.get("territory_type", "civilized")),
	})
	CampaignRepository.db.query_with_bindings("""
		UPDATE domains SET peasant_families = ?, treasury_cp = ?, morale = ?,
			expenses_cp = ? WHERE id = ?
	""", [
		int(opts.get("peasants", 100)), int(opts.get("treasury_cp", 0)),
		int(opts.get("morale", 0)), int(opts.get("expenses_cp", 0)), domain_id,
	])
	return domain_id


func _character_xp(character_id: String) -> int:
	return int(CampaignRepository.get_character(character_id).get("xp", -1))


func _character_level(character_id: String) -> int:
	return int(CampaignRepository.get_character(character_id).get("level", -1))


# ---------------------------------------------------------------------------
# The calculation — units and rounding
# ---------------------------------------------------------------------------

func test_cp_threshold_matches_the_raw_gp_table() -> void:
	# RAW acore-campaign-hijinks.xml:1071 — level 9's threshold is 12,000 gp.
	# In copper that is 1,200,000, and income AT the threshold earns nothing
	# ("XP is only earned when monthly income EXCEEDS the threshold", L1030).
	check(XPAwardCalculator.calculate_domain_xp_cp(1_200_000, 9, false) == 0,
		"income exactly at the level-9 threshold earns 0")
	check(XPAwardCalculator.calculate_domain_xp_cp(1_199_900, 9, false) == 0,
		"income one gp below the threshold earns 0")
	check(XPAwardCalculator.calculate_domain_xp_cp(1_500_000, 9, false) == 3000,
		"15,000 gp at level 9 earns 3,000 XP (15,000 - 12,000)")
	# A domain running at a loss must never produce negative XP.
	check(XPAwardCalculator.calculate_domain_xp_cp(-500_000, 9, false) == 0,
		"a domain running at a loss earns 0, never negative XP")


func test_cp_and_gp_forms_agree_at_100_to_1() -> void:
	# THE 100x REGRESSION LOCK. The original defect was copper handed straight to
	# a gp-denominated table. Pinning the cp form against the gp form at exactly
	# 100:1 means any future unit slip on either side fails here rather than
	# silently inflating every ruler's advancement by two orders of magnitude.
	var calc := XPAwardCalculator.new(ClassRegistry.new())
	for gp in [26, 300, 1251, 15_000, 60_001]:
		for level in [1, 4, 9, 12]:
			check(XPAwardCalculator.calculate_domain_xp_cp(gp * 100, level, false)
					== calc.calculate_domain_xp(gp, level, false),
				"cp and gp forms agree at %d gp, level %d" % [gp, level])


func test_sub_gp_remainder_rounds_half_to_even() -> void:
	# Copper granularity means income can land on a fraction of a gp, so the
	# gp->XP rate divides. Banker's rounding is mandatory project-wide, and
	# roundi() (half away from zero) would give 3 and 4 for these two cases.
	# Level 1's threshold is 25 gp = 2,500 cp.
	check(XPAwardCalculator.calculate_domain_xp_cp(2_750, 1, false) == 2,
		"2.5 gp above threshold rounds to 2 (half to EVEN), not 3")
	check(XPAwardCalculator.calculate_domain_xp_cp(2_850, 1, false) == 4,
		"3.5 gp above threshold rounds to 4 (half to even)")
	check(XPAwardCalculator.calculate_domain_xp_cp(2_760, 1, false) == 3,
		"2.6 gp above threshold rounds to 3 normally")


func test_henchman_earns_half_rounded_once() -> void:
	# RAW L1040 — "a follower or henchman managing a domain earns 50% of normal
	# domain XP". The half-rate must fold into the same expression as the
	# gp->XP rate: rounding to an int and THEN halving drifts.
	check(XPAwardCalculator.calculate_domain_xp_cp(1_500_000, 9, true) == 1500,
		"a henchman earns half of 3,000")
	# 2.5 gp above threshold, halved = 1.25 -> 1. Halving a pre-rounded 2 would
	# give 1 too, but halving a pre-rounded 3 (roundi) would give 2 — this pins
	# the single-rounding path.
	check(XPAwardCalculator.calculate_domain_xp_cp(2_750, 1, true) == 1,
		"the henchman rate is applied before the single rounding")


# ---------------------------------------------------------------------------
# XpAwardService
# ---------------------------------------------------------------------------

func test_award_service_persists_atomically() -> void:
	var cid := _make_ruler("award", {"xp": 500, "xp_for_next_level": 2000})
	var r: Dictionary = XpAwardService.award(cid, 250, XpAwardService.SOURCE_DOMAIN_INCOME)
	check(int(r.get("awarded", 0)) == 250, "award reports what it added")
	check(int(r.get("xp_before", -1)) == 500, "xp_before is the pre-award total")
	check(int(r.get("xp_after", -1)) == 750, "xp_after is the post-award total")
	check(_character_xp(cid) == 750, "the award reached the characters.xp column")
	check(not bool(r.get("reaches_next_level", true)),
		"750 does not reach the 2,000 threshold")

	var r2: Dictionary = XpAwardService.award(cid, 2000, XpAwardService.SOURCE_DOMAIN_INCOME)
	check(_character_xp(cid) == 2750, "a second award accumulates rather than replacing")
	check(bool(r2.get("reaches_next_level", false)),
		"crossing the threshold is reported")


func test_award_service_ignores_non_positive_amounts() -> void:
	var cid := _make_ruler("zero_award", {"xp": 100})
	for amount in [0, -50]:
		var r: Dictionary = XpAwardService.award(cid, amount, "test")
		check(int(r.get("awarded", -1)) == 0, "amount %d is a no-op" % amount)
		check(not r.is_empty(), "a no-op still returns a populated dict, never {}")
	check(_character_xp(cid) == 100,
		"a non-positive award leaves xp untouched (XP loss needs its own path)")


# ---------------------------------------------------------------------------
# DomainXpResolver
# ---------------------------------------------------------------------------

func test_ownerless_domain_is_skipped() -> void:
	var out: Dictionary = DomainXpResolver.resolve(
		{"id": "d_ownerless", "owner_character_id": null}, {"net_income": 5_000_000}, 90)
	check(bool(out.get("skipped", false)), "an ownerless seat is skipped")
	check(String(out.get("reason", "")) == "ownerless", "and says why")
	check(int(out.get("awarded", -1)) == 0, "nothing is awarded")


func test_income_below_the_lowest_threshold_earns_nothing() -> void:
	var cid := _make_ruler("poor")
	var did := _make_domain("poor", cid)
	var row: Dictionary = CampaignRepository.get_domain(did)
	# 24 gp — under level 1's 25 gp threshold, so under EVERY level's threshold.
	var out: Dictionary = DomainXpResolver.resolve(row, {"net_income": 2_400}, 90)
	check(int(out.get("earned", -1)) == 0, "income below the lowest threshold earns 0")
	check(not bool(out.get("skipped", true)),
		"it is a real zero, not a skip — the month resolved and recorded 0")
	check(_character_xp(cid) == 0, "and nothing reached the ruler")


func test_award_reaches_the_rulers_xp_column() -> void:
	# THE HEADLINE DEFECT: before R-7a no character had ever gained a point of
	# domain XP, because domain_xp_this_month was written and read by nothing.
	var cid := _make_ruler("earner", {"level": 9, "xp": 0, "xp_for_next_level": 999_999})
	var did := _make_domain("earner", cid)
	var row: Dictionary = CampaignRepository.get_domain(did)
	var out: Dictionary = DomainXpResolver.resolve(row, {"net_income": 1_500_000}, 90)
	check(int(out.get("earned", 0)) == 3000, "earned the RAW figure (15,000 - 12,000 gp)")
	check(int(out.get("awarded", 0)) == 3000, "and awarded all of it")
	check(_character_xp(cid) == 3000, "the ruler's xp column actually grew")
	check(int(out.get("net_income_cp", 0)) == 1_500_000,
		"the report carries the cp income it was given")
	check(int(out.get("earned", 0)) != int(out.get("net_income_cp", 0)),
		"the XP figure is NOT the raw copper net income (the 100x defect)")


func test_double_award_guard_blocks_a_repeated_day() -> void:
	var cid := _make_ruler("guarded", {"level": 9, "xp_for_next_level": 999_999})
	var did := _make_domain("guarded", cid)
	var first: Dictionary = DomainXpResolver.resolve(
		CampaignRepository.get_domain(did), {"net_income": 1_500_000}, 120)
	check(int(first.get("awarded", 0)) == 3000, "the first resolution pays")

	# The tick stamps the guard through _save_domain; do the same here.
	CampaignRepository.update_domain_monthly_state(
		did, {"domain_xp_awarded_through_day": 120})
	var second: Dictionary = DomainXpResolver.resolve(
		CampaignRepository.get_domain(did), {"net_income": 1_500_000}, 120)
	check(bool(second.get("skipped", false)), "re-running the same day is skipped")
	check(String(second.get("reason", "")) == "already_awarded_through_day", "and says why")
	check(_character_xp(cid) == 3000, "the ruler was not paid twice for one month")

	# The NEXT month still pays.
	var third: Dictionary = DomainXpResolver.resolve(
		CampaignRepository.get_domain(did), {"net_income": 1_500_000}, 148)
	check(int(third.get("awarded", 0)) == 3000, "the following month is unaffected")
	check(_character_xp(cid) == 6000, "and accumulates")


func test_one_level_cap_bounds_the_award() -> void:
	# RAW L1011 — "a character can never earn enough campaign XP in one month to
	# advance 2 or more levels". Asserted relationally against the class table so
	# the test does not hard-code a fighter's XP curve.
	var cid := _make_ruler("capped", {"level": 1, "xp": 0, "xp_for_next_level": 2000})
	var did := _make_domain("capped", cid)
	var two_ahead: int = ClassRegistry.new().get_xp_for_level("fighter", 3)
	check(two_ahead > 0, "the class table knows a fighter's level-3 threshold")

	# 1,000,000 gp of net income at level 1 — vastly more than two levels' worth.
	var out: Dictionary = DomainXpResolver.resolve(
		CampaignRepository.get_domain(did), {"net_income": 100_000_000}, 90)
	check(bool(out.get("clamped_by_level_cap", false)), "the cap reports that it bit")
	check(int(out.get("awarded", 0)) < int(out.get("earned", 0)),
		"awarded is less than earned when the cap bites")
	check(_character_xp(cid) < two_ahead,
		"the ruler cannot reach the level+2 threshold in one month")
	check(_character_level(cid) == 2,
		"he advances exactly one level, not two")


func test_full_tier_npc_ruler_levels_automatically() -> void:
	# D-4 — NPC rulers DO level from domain XP, automatically. The RAW threshold
	# table is the throttle that keeps a baron at a baron's station.
	var cid := _make_ruler("climber", {"level": 1, "xp": 0, "xp_for_next_level": 2000})
	var did := _make_domain("climber", cid)
	check(_character_level(cid) == 1, "starts at level 1")
	var out: Dictionary = DomainXpResolver.resolve(
		CampaignRepository.get_domain(did), {"net_income": 300_000}, 90)
	check(int(out.get("awarded", 0)) >= 2000, "the award clears the level-2 threshold")
	check(bool(out.get("leveled_up", false)), "the resolver reports the advancement")
	check(_character_level(cid) == 2, "and the level actually persisted")


func test_pc_ruler_is_not_auto_leveled() -> void:
	# A PC advances interactively (LevelUpEngine.begin_interactive_level_up) so
	# he keeps his proficiency and spell picks. The tick reports and stops.
	var cid := _make_ruler("player", {
		"character_type": "pc", "level": 1, "xp": 0, "xp_for_next_level": 2000})
	var did := _make_domain("player", cid)
	var out: Dictionary = DomainXpResolver.resolve(
		CampaignRepository.get_domain(did), {"net_income": 300_000}, 90)
	check(int(out.get("awarded", 0)) >= 2000, "the PC still earns the XP")
	check(_character_xp(cid) >= 2000, "and it reaches his xp column")
	check(bool(out.get("pending_level_up", false)),
		"the advancement is reported as pending")
	check(not bool(out.get("leveled_up", true)), "but not applied")
	check(_character_level(cid) == 1, "the PC's level is untouched")


func test_named_tier_stub_banks_xp_without_leveling() -> void:
	# D-8's lazy-detail contract: a 'named'-tier row is a ruler STUB with no
	# proficiency/power/spell rows. apply_level_up_auto would materialise all of
	# them for every backdrop domain in the world — the eager cost D-8 rejected.
	# Stubs bank the XP instead and advance once promoted to 'full'.
	var cid := _make_ruler("stub", {
		"persistence_tier": "named", "level": 1, "xp": 0, "xp_for_next_level": 2000})
	var did := _make_domain("stub", cid)
	var out: Dictionary = DomainXpResolver.resolve(
		CampaignRepository.get_domain(did), {"net_income": 300_000}, 90)
	check(int(out.get("awarded", 0)) >= 2000, "the stub still banks the XP")
	check(_character_xp(cid) >= 2000, "in its characters.xp column")
	check(_character_level(cid) == 1, "but does not advance while off camera")
	check(bool(out.get("pending_level_up", false)), "the pending advance is reported")
	check(String(out.get("reason", "")) == "stub_banks_xp", "and attributed")


func test_administer_domain_adds_five_percent() -> void:
	# RAW ax_campaign_play.xml:511 — "Rulers who administer their domain gain +1 on
	# domain morale rolls and +5% on domain XP that month." Axioms is the project's
	# highest-precedence source. Two identical domains, one flagged administered.
	var plain_id := _make_ruler("admin_off", {"level": 9, "xp_for_next_level": 999_999})
	var admin_id := _make_ruler("admin_on", {"level": 9, "xp_for_next_level": 999_999})
	var plain_domain := _make_domain("admin_off", plain_id)
	var admin_domain := _make_domain("admin_on", admin_id)
	CampaignRepository.update_domain_monthly_state(
		admin_domain, {"administer_domain_completed_this_month": 1})

	var a: Dictionary = DomainXpResolver.resolve(
		CampaignRepository.get_domain(plain_domain), {"net_income": 1_500_000}, 90)
	var b: Dictionary = DomainXpResolver.resolve(
		CampaignRepository.get_domain(admin_domain), {"net_income": 1_500_000}, 90)
	check(int(a.get("earned", 0)) == 3000, "the un-administered domain earns the base figure")
	check(not bool(a.get("administered", true)), "and reports that it was not administered")
	check(int(b.get("earned", 0)) == 3150, "the administered domain earns +5% (3,000 -> 3,150)")
	check(bool(b.get("administered", false)), "and reports that it was")
	check(int(b.get("before_modifiers", 0)) == 3000,
		"the pre-modifier figure is reported unchanged")
	check(_character_xp(admin_id) - _character_xp(plain_id) == 150,
		"and the difference actually reached the rulers' xp columns")


func test_administration_and_prime_req_round_once_together() -> void:
	# Two RAW percentages scale the same figure: administer +5%
	# (ax_campaign_play.xml:511) and the prime-requisite adjustment (hijinks
	# L1010). Rounding after EACH multiply drifts, so they compose into one
	# multiplier and round once. This base is chosen to make the two disagree:
	#   base       = (1,499,000 - 1,200,000) / 100 = 2,990
	#   COMPOSED   -> 2990 * 1.05 * 1.05 = 3296.475 -> 3296   <-- correct
	#   sequential -> banker's(3139.5) = 3140, then 3140 * 1.05 = 3297 -> 3297
	# The intermediate half-rounding is amplified by the second multiply; that is
	# exactly the drift folding into one expression prevents.
	var cid := _make_ruler("compose", {
		"level": 9, "xp_for_next_level": 999_999, "xp_adjustment_percent": 5})
	var did := _make_domain("compose", cid)
	CampaignRepository.update_domain_monthly_state(
		did, {"administer_domain_completed_this_month": 1})
	var out: Dictionary = DomainXpResolver.resolve(
		CampaignRepository.get_domain(did), {"net_income": 1_499_000}, 90)
	check(int(out.get("before_modifiers", 0)) == 2990, "the base figure is 2,990")
	check(int(out.get("earned", 0)) == 3296,
		"the two percentages compose under ONE banker's rounding (got %d, want 3296 — "
			% int(out.get("earned", -1))
			+ "3297 means they were rounded separately)")


# ---------------------------------------------------------------------------
# Wiring — the real monthly tick
# ---------------------------------------------------------------------------

func test_monthly_tick_records_the_raw_figure_and_stamps_the_guard() -> void:
	var camp := CampaignRepository.create_campaign("Domain XP Tick", "World")
	var save := _campaign_id
	_campaign_id = camp
	var cid := _make_ruler("tick", {"level": 4, "xp": 0, "xp_for_next_level": 999_999})
	var did := _make_domain("tick", cid, {"peasants": 800})
	_campaign_id = save

	var handlers := DomainHandlers.new(FakeRunner.new(camp))
	handlers._handle_monthly_tick(_monthly_tick_event())

	var row: Dictionary = CampaignRepository.get_domain(did)
	var net_cp: int = int(row.get("net_income_cp", 0))
	var recorded: int = int(row.get("domain_xp_this_month", -1))
	var expected: int = XPAwardCalculator.calculate_domain_xp_cp(net_cp, 4, false)

	# Income-independent: whatever the economy produced, the column must hold the
	# RAW threshold figure derived from it — not the copper net income.
	check(recorded == expected,
		"domain_xp_this_month holds the RAW figure for %d cp net (got %d, want %d)"
			% [net_cp, recorded, expected])
	if net_cp > 0:
		check(recorded != net_cp,
			"the column is no longer the raw copper net income")

	var guard: int = int(row.get("domain_xp_awarded_through_day", -99))
	if expected > 0:
		# `<= expected` rather than `==` so the assertion survives the RAW
		# one-level cap biting on an unusually rich fixture; the point being
		# proven is that XP moved at all, which it never did before R-7a.
		var paid: int = _character_xp(cid)
		check(paid > 0 and paid <= expected,
			"the tick paid the ruler through to his xp column (got %d, earned %d)"
				% [paid, expected])
		check(guard >= 0, "and stamped the double-award guard")
	else:
		check(guard == -1, "no award, so the guard stays at its never-awarded default")
		check(_character_xp(cid) == 0, "and no XP moved")


func _monthly_tick_event() -> ScheduledEvent:
	var ev := ScheduledEvent.new()
	ev.fire_time = Timekeeping.get_total_rounds()
	ev.event_type = "domain_monthly_tick"
	ev.owner_id = "domain_global"
	return ev
