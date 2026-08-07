extends "res://tests/test_suite_base.gd"

## Phase 11D.3 — Religion conversion + alignment effects.
##
## Covers the alignment-vs-religion morale penalty matrix per
## `acore_axioms` L466-471, the beastman-ruler-over-kin stack per
## `ax_domains_of_chaos.xml:44`, and the religion conversion mechanic per
## `gdd-religion-conversion.md` §3-§7.
##
## Most tests exercise `DomainMoraleResolver.resolve_base_morale` and
## `ReligionConversionResolver` directly (no monthly-tick orchestration —
## those are integration-level concerns covered by scenarios in Phase 11E).

const TEST_CAMPAIGN := "test_rc_campaign"
const TEST_RULER := "test_rc_ruler"
const TEST_DRIVER := "test_rc_driver"
const TEST_DOMAIN := "test_rc_domain"


func run_all_tests() -> void:
	_cleanup()
	# Alignment-vs-religion morale penalty matrix (acore_axioms L466-471)
	test_alignment_match_no_penalty()
	test_alignment_lc_pair_minus_2()
	test_alignment_ln_or_nc_minus_1()
	# Beastman-ruler-over-kin stack (ax_domains_of_chaos:44)
	test_beastman_ruler_over_kin_minus_2_additional()
	test_beastman_ruler_over_beastman_no_stack()
	test_kin_ruler_over_kin_no_stack()
	# Active conversion adds −1 base morale (§5.5)
	test_active_conversion_minus_1_base_morale()
	# Conversion lifecycle
	test_start_conversion_inserts_row_and_sets_declared_religion()
	test_start_conversion_rejects_duplicate_active_arc()
	test_start_conversion_rejects_beastman_clanhold_to_lawful()
	test_abort_conversion_reverts_religion_and_marks_aborted()
	test_eligible_targets_for_kin_clanhold_allows_all()
	test_eligible_targets_for_beastman_clanhold_chaotic_only()
	# Tick mechanic
	test_tick_no_active_arc_is_noop()
	test_tick_completion_at_60pct_threshold_flips_effective_religion()
	test_tick_failed_morale_after_3_rebellious_months()
	# §106 null-safety regression (2026-08-03)
	test_null_driving_character_id_does_not_abort_the_driver_helpers()
	test_null_domain_owner_does_not_abort_the_owner_lookup()
	# Driver-tier selection — reachable for the first time once the TEST_DRIVER
	# fixture actually reaches the database (2026-08-03).
	test_driver_bonus_tier_selection()
	_cleanup()
	if not has_failures():
		print("ReligionConversion: all tests passed.")


# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

func _setup() -> void:
	_cleanup()
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[TEST_CAMPAIGN, "Religion Conversion Test"])
	# Default ruler: chaotic Cleric. NOTE: the `characters` table does not
	# carry a `religion` column — a divine caster's religion is implicit in
	# class + alignment + (future) deity field. Per gdd-religion-conversion.md
	# §3 the per-character congregants row is what associates a caster with
	# a religion via the conversion arc's driving_character_id.
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_type, persistence_tier,
			 race, character_class, level, xp, combat_progression,
			 strength, intelligence, wisdom, dexterity, constitution, charisma,
			 alignment, is_active)
		VALUES (?, ?, 'Test Ruler', 'pc', 'full',
		        'human', 'cleric', 9, 0, 'cleric',
		        10, 10, 10, 10, 10, 13, 'chaotic', 1)
	""", [TEST_RULER, TEST_CAMPAIGN])
	# Driving caster (henchman divine caster of the target religion).
	#
	# [2026-08-03] This row previously carried `character_type='pc',
	# persistence_tier='henchman'` — but 'henchman' is a CHARACTER_TYPE value and
	# `characters.persistence_tier` is CHECK(... IN ('full','named','transient')),
	# so the INSERT was silently rejected and THE ROW NEVER EXISTED. Every
	# driver-dependent path in this suite therefore took the missing-driver
	# fallback (`ReligionConversionResolver._driver_bonus_pct` returning
	# MISSIONARY_ONLY through its `if driver.is_empty()` guard), and the
	# henchman-divine tier plus the ruler-vs-henchman selection below it were
	# never exercised. The two columns are now in their intended places.
	#
	# Charisma 14 (→ +1) is load-bearing: `test_tick_completion_*` documents its
	# arithmetic as "1d10 + Cha mod (14 → +1)". Do not change it without
	# re-deriving that test.
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_type, persistence_tier,
			 race, character_class, level, xp, combat_progression,
			 strength, intelligence, wisdom, dexterity, constitution, charisma,
			 alignment, is_active)
		VALUES (?, ?, 'Test Driver', 'henchman', 'full',
		        'human', 'cleric', 5, 0, 'cleric',
		        10, 10, 10, 10, 10, 14, 'chaotic', 1)
	""", [TEST_DRIVER, TEST_CAMPAIGN])


func _cleanup() -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM domain_religion_conversion WHERE domain_id = ?", [TEST_DOMAIN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM congregants WHERE domain_id = ?", [TEST_DOMAIN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM domain_departure_log WHERE domain_id = ?", [TEST_DOMAIN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM domain_hexes WHERE domain_id = ?", [TEST_DOMAIN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM domains WHERE id = ?", [TEST_DOMAIN])
	for c in [TEST_RULER, TEST_DRIVER]:
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM congregants WHERE character_id = ?", [c])
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM characters WHERE id = ?", [c])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [TEST_CAMPAIGN])


func _make_domain(
	alignment: String = "lawful",
	style: String = "civilized",
	establishment_method: String = "grant",
	effective_religion: String = "sun-cult"
) -> Dictionary:
	return {
		"id": TEST_DOMAIN,
		"campaign_id": TEST_CAMPAIGN,
		"name": "Test Domain",
		"owner_character_id": TEST_RULER,
		"territory_type": "civilized",  # avoid classification penalty
		"peasant_families": 500,
		"alignment": alignment,
		"religion": effective_religion,
		"effective_religion": effective_religion,
		"domain_style": style,
		"establishment_method": establishment_method,
		"tax_rate_cp_per_family": 200,
		"liturgy_rate_cp_per_family": 100,
		"tithe_rate_cp_per_family": 100,
		"tribute_out_owed": 0,
		"repression_cp_per_family_this_month": 0,
	}


func _make_ruler(alignment: String = "lawful", race: String = "human") -> Dictionary:
	return {
		"cha_modifier": 0,
		"level": 5,
		"has_leadership_proficiency": false,
		"alignment": alignment,
		"race": race,
	}


func _insert_domain_row(
	alignment: String = "lawful",
	style: String = "civilized",
	establishment_method: String = "grant",
	religion: String = "sun-cult"
) -> void:
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO domains
			(id, campaign_id, name, owner_character_id, territory_type,
			 peasant_families, alignment, religion, effective_religion,
			 domain_style, establishment_method, established_calendar_day)
		VALUES (?, ?, ?, ?, 'civilized', 500, ?, ?, ?, ?, ?, 1)
	""", [TEST_DOMAIN, TEST_CAMPAIGN, "Test Domain", TEST_RULER,
		  alignment, religion, religion, style, establishment_method])


# ---------------------------------------------------------------------------
# Alignment-vs-religion morale penalty matrix (acore_axioms L466-471)
# ---------------------------------------------------------------------------

func test_alignment_match_no_penalty() -> void:
	# Lawful ruler in lawful domain — alignment penalty = 0.
	var d := _make_domain("lawful")
	var r := _make_ruler("lawful")
	var base: int = DomainMoraleResolver.resolve_base_morale(d, r, 100_000, 1000, 0, 0)
	# civilized classification = 0, level=5 + income (mid-band) ≈ a few; we
	# just check that lawful+lawful does NOT add a negative alignment chunk.
	# Comparison: same setup with chaotic vs lawful should be base-2.
	var r_chaotic := _make_ruler("chaotic")
	var base_lc: int = DomainMoraleResolver.resolve_base_morale(d, r_chaotic, 100_000, 1000, 0, 0)
	check(base - base_lc == 2,
		"lawful-lawful should be 2 better than chaotic-lawful (L/C pair): %d vs %d" % [base, base_lc])


func test_alignment_lc_pair_minus_2() -> void:
	var d := _make_domain("lawful")
	var r := _make_ruler("chaotic")
	var base: int = DomainMoraleResolver.resolve_base_morale(d, r, 100_000, 1000, 0, 0)
	# Build reference where ruler matches.
	var r_match := _make_ruler("lawful")
	var base_match: int = DomainMoraleResolver.resolve_base_morale(d, r_match, 100_000, 1000, 0, 0)
	check(base_match - base == 2,
		"L/C pair adds −2 vs match: match=%d lc=%d" % [base_match, base])


func test_alignment_ln_or_nc_minus_1() -> void:
	var d_lawful := _make_domain("lawful")
	var r_neutral := _make_ruler("neutral")
	var base_ln: int = DomainMoraleResolver.resolve_base_morale(d_lawful, r_neutral, 100_000, 1000, 0, 0)
	var r_match := _make_ruler("lawful")
	var base_match: int = DomainMoraleResolver.resolve_base_morale(d_lawful, r_match, 100_000, 1000, 0, 0)
	check(base_match - base_ln == 1,
		"L/N or N/C pair adds −1 vs match: match=%d ln=%d" % [base_match, base_ln])


# ---------------------------------------------------------------------------
# Beastman-rules-kin stack (ax_domains_of_chaos:44)
# ---------------------------------------------------------------------------

func test_beastman_ruler_over_kin_minus_2_additional() -> void:
	# Chaotic hobgoblin ruler over a kin (human-pop, civilized-style) chaotic
	# domain. Alignment matches (both chaotic) so no L466-471 penalty.
	# But the beastman-rules-kin rule applies = −2.
	var d := _make_domain("chaotic", "civilized", "grant")
	var r := _make_ruler("chaotic", "hobgoblin")
	var base: int = DomainMoraleResolver.resolve_base_morale(d, r, 100_000, 1000, 0, 0)
	# Compare with a human chaotic ruler — same setup minus the beastman stack.
	var r_human := _make_ruler("chaotic", "human")
	var base_human: int = DomainMoraleResolver.resolve_base_morale(d, r_human, 100_000, 1000, 0, 0)
	check(base_human - base == 2,
		"beastman ruler over kin domain: -2 stack vs human ruler: human=%d beastman=%d"
		% [base_human, base])


func test_beastman_ruler_over_beastman_no_stack() -> void:
	# Beastman ruler over beastman clanhold (establishment_method=clanhold_annex)
	# → no stack (the rule only applies over KIN populations).
	var d := _make_domain("chaotic", "clanhold", "clanhold_annex")
	var r := _make_ruler("chaotic", "hobgoblin")
	var base: int = DomainMoraleResolver.resolve_base_morale(d, r, 100_000, 1000, 0, 0)
	var r_human := _make_ruler("chaotic", "human")
	var base_human: int = DomainMoraleResolver.resolve_base_morale(d, r_human, 100_000, 1000, 0, 0)
	check(base_human - base == 0,
		"beastman ruler over beastman: no stack: human=%d beastman=%d"
		% [base_human, base])


func test_kin_ruler_over_kin_no_stack() -> void:
	var d := _make_domain("neutral", "civilized", "grant")
	var r := _make_ruler("neutral", "human")
	var r_dwarf := _make_ruler("neutral", "dwarf")
	var base_h: int = DomainMoraleResolver.resolve_base_morale(d, r, 100_000, 1000, 0, 0)
	var base_d: int = DomainMoraleResolver.resolve_base_morale(d, r_dwarf, 100_000, 1000, 0, 0)
	check(base_h == base_d,
		"kin ruler over kin (no beastman stack triggers): human=%d dwarf=%d"
		% [base_h, base_d])


# ---------------------------------------------------------------------------
# Active conversion penalty (§5.5)
# ---------------------------------------------------------------------------

func test_active_conversion_minus_1_base_morale() -> void:
	_setup()
	_insert_domain_row("lawful", "civilized", "grant", "sun-cult")
	# No active conversion yet — compute baseline.
	var d := CampaignRepository.get_domain(TEST_DOMAIN)
	var r := _make_ruler("lawful", "human")
	var base_before: int = DomainMoraleResolver.resolve_base_morale(d, r, 100_000, 1000, 0, 0)
	# Insert an active conversion arc.
	var conv_id: String = ReligionConversionResolver.start_conversion(
		TEST_DOMAIN, "chaos-cult", "chaotic", "", 1)
	check(not conv_id.is_empty(), "start_conversion succeeded")
	var d_after := CampaignRepository.get_domain(TEST_DOMAIN)
	var base_after: int = DomainMoraleResolver.resolve_base_morale(d_after, r, 100_000, 1000, 0, 0)
	check(base_before - base_after == 1,
		"active conversion adds −1 base morale: before=%d after=%d"
		% [base_before, base_after])


# ---------------------------------------------------------------------------
# Conversion lifecycle: start / abort / eligibility
# ---------------------------------------------------------------------------

func test_start_conversion_inserts_row_and_sets_declared_religion() -> void:
	_setup()
	_insert_domain_row("lawful", "civilized", "grant", "sun-cult")
	var conv_id: String = ReligionConversionResolver.start_conversion(
		TEST_DOMAIN, "chaos-cult", "chaotic", TEST_DRIVER, 1)
	check(not conv_id.is_empty(), "start_conversion returns id")
	check(ReligionConversionResolver.get_active_for_domain(TEST_DOMAIN) == conv_id,
		"get_active_for_domain returns the new arc")
	# domains.religion flipped to declared; effective_religion unchanged.
	var d := CampaignRepository.get_domain(TEST_DOMAIN)
	check(str(d.get("religion", "")) == "chaos-cult",
		"declared religion (domains.religion) flipped to to_religion")
	check(str(d.get("effective_religion", "")) == "sun-cult",
		"effective_religion still original until completion")
	check(str(d.get("alignment", "")) == "lawful",
		"alignment still original until completion")


func test_start_conversion_rejects_duplicate_active_arc() -> void:
	_setup()
	_insert_domain_row("lawful", "civilized", "grant", "sun-cult")
	var first: String = ReligionConversionResolver.start_conversion(
		TEST_DOMAIN, "chaos-cult", "chaotic", "", 1)
	check(not first.is_empty(), "first start_conversion succeeds")
	var second: String = ReligionConversionResolver.start_conversion(
		TEST_DOMAIN, "neutral-faith", "neutral", "", 1)
	check(second.is_empty(),
		"second start_conversion rejected when arc already active; got '%s'" % second)


func test_start_conversion_rejects_beastman_clanhold_to_lawful() -> void:
	_setup()
	_insert_domain_row("chaotic", "clanhold", "clanhold_annex", "chaos-cult")
	# Per §9.7: beastman clanhold (clanhold_annex / recruit_chieftain) cannot
	# convert to non-chaotic.
	var attempt: String = ReligionConversionResolver.start_conversion(
		TEST_DOMAIN, "sun-cult", "lawful", "", 1)
	check(attempt.is_empty(),
		"beastman clanhold rejects lawful-religion conversion; got '%s'" % attempt)


func test_abort_conversion_reverts_religion_and_marks_aborted() -> void:
	_setup()
	_insert_domain_row("lawful", "civilized", "grant", "sun-cult")
	var conv_id: String = ReligionConversionResolver.start_conversion(
		TEST_DOMAIN, "chaos-cult", "chaotic", "", 1)
	check(not conv_id.is_empty(), "arc started")
	var ok := ReligionConversionResolver.abort_conversion(conv_id, 30, "player_cancel")
	check(ok, "abort returned true")
	var d := CampaignRepository.get_domain(TEST_DOMAIN)
	check(str(d.get("religion", "")) == "sun-cult",
		"declared religion reverted to original")
	check(str(d.get("effective_religion", "")) == "sun-cult",
		"effective_religion unchanged")
	check(ReligionConversionResolver.get_active_for_domain(TEST_DOMAIN) == "",
		"no longer an active arc")


func test_eligible_targets_for_kin_clanhold_allows_all() -> void:
	_setup()
	_insert_domain_row("lawful", "clanhold", "clear", "sun-cult")
	# clear = kin-clanhold (not beastman). All three alignments allowed.
	var options: Array = ReligionConversionResolver.eligible_conversion_targets(TEST_DOMAIN)
	check(options.size() == 3, "three alignment options surfaced")
	for opt in options:
		check(bool(opt.get("allowed", false)),
			"%s allowed for kin clanhold" % str(opt.get("alignment", "?")))


func test_eligible_targets_for_beastman_clanhold_chaotic_only() -> void:
	_setup()
	_insert_domain_row("chaotic", "clanhold", "clanhold_annex", "chaos-cult")
	var options: Array = ReligionConversionResolver.eligible_conversion_targets(TEST_DOMAIN)
	var allowed_by_alignment: Dictionary = {}
	for opt in options:
		allowed_by_alignment[str_field(opt, "alignment")] = bool(opt.get("allowed", false))
	check(bool(allowed_by_alignment.get("chaotic", false)),
		"chaotic allowed for beastman clanhold")
	check(not bool(allowed_by_alignment.get("lawful", true)),
		"lawful NOT allowed for beastman clanhold")
	check(not bool(allowed_by_alignment.get("neutral", true)),
		"neutral NOT allowed for beastman clanhold")


# ---------------------------------------------------------------------------
# Tick mechanic
# ---------------------------------------------------------------------------

func test_tick_no_active_arc_is_noop() -> void:
	_setup()
	_insert_domain_row("lawful", "civilized", "grant", "sun-cult")
	var d := CampaignRepository.get_domain(TEST_DOMAIN)
	d["morale"] = 0
	var result := ReligionConversionResolver.tick_conversion(d, 1)
	check(not bool(result.get("applied", true)),
		"no active arc → applied=false")
	check(int(result.get("congregant_gain", -1)) == 0,
		"no active arc → no congregant gain")


func test_tick_completion_at_60pct_threshold_flips_effective_religion() -> void:
	_setup()
	_insert_domain_row("lawful", "civilized", "grant", "sun-cult")
	# Driver is the chaos-cult cleric henchman.
	var conv_id: String = ReligionConversionResolver.start_conversion(
		TEST_DOMAIN, "chaos-cult", "chaotic", TEST_DRIVER, 1)
	check(not conv_id.is_empty(), "arc started")
	# Pre-seed 299 chaos-cult congregants in the domain (just below 60% of 500 = 300).
	CampaignRepository.adjust_congregant_count(TEST_DRIVER, 299, TEST_DOMAIN)
	# Tick with non-zero proselytizing to push past threshold.
	CampaignRepository.add_congregant_pending_cp(TEST_DRIVER, 100_000, TEST_DOMAIN)  # 1000 gp
	var d := CampaignRepository.get_domain(TEST_DOMAIN)
	d["morale"] = 4  # Stalwart × 2.0 multiplier to make completion likely
	# Force-roll deterministic 10 on 1d10 + Cha mod (14 → +1) = 11 per roll.
	# 1 roll × 11 × 200% morale × 110% henchman × 100% no altar = 24, under room=201.
	#
	# [2026-08-03] That arithmetic is what this comment always CLAIMED, but until
	# the TEST_DRIVER fixture was repaired it was not what ran: the driver row
	# never existed, so Cha mod was 0 (base 10, not 11) and the driver tier was
	# the missionary-only 100% (not 110%), giving 20. The completion assertion
	# below could not tell the difference — 299+20 and 299+24 both clear the 300
	# threshold — so a documented-but-false calculation sat here unchallenged.
	# The gain is now asserted, not just described, so the comment is enforceable.
	var deterministic_roller := func(_faces: int, count: int, _exp: bool) -> int:
		return 10 * count
	var result := ReligionConversionResolver.tick_conversion(d, 2, deterministic_roller)
	check(int(result.get("congregant_gain", -1)) == 24,
		"gain = (10 + 1) x 2.0 morale x 1.1 henchman = 24, got %d (20 means the driver fixture is dead again)"
			% int(result.get("congregant_gain", -1)))
	check(bool(result.get("completed", false)),
		"tick should complete: gain=%d completed=%s" % [
			int(result.get("congregant_gain", 0)),
			str(result.get("completed", false))])
	var d_after := CampaignRepository.get_domain(TEST_DOMAIN)
	check(String(d_after.get("effective_religion", "")) == "chaos-cult",
		"effective_religion flipped on completion")
	check(str_field(d_after, "alignment") == "chaotic",
		"alignment flipped on completion")


func test_tick_failed_morale_after_3_rebellious_months() -> void:
	_setup()
	_insert_domain_row("lawful", "civilized", "grant", "sun-cult")
	var conv_id: String = ReligionConversionResolver.start_conversion(
		TEST_DOMAIN, "chaos-cult", "chaotic", "", 1)
	check(not conv_id.is_empty(), "arc started")
	var d := CampaignRepository.get_domain(TEST_DOMAIN)
	d["morale"] = -4  # Rebellious
	# Three rebellious ticks in a row should fail the arc.
	var t1 := ReligionConversionResolver.tick_conversion(d, 2)
	check(not bool(t1.get("failed_morale", false)),
		"month 1 at Rebellious: not yet failed")
	var t2 := ReligionConversionResolver.tick_conversion(d, 3)
	check(not bool(t2.get("failed_morale", false)),
		"month 2 at Rebellious: not yet failed")
	var t3 := ReligionConversionResolver.tick_conversion(d, 4)
	check(bool(t3.get("failed_morale", false)),
		"month 3 at Rebellious: failed_morale fires; got %s" % str(t3))
	check(ReligionConversionResolver.get_active_for_domain(TEST_DOMAIN) == "",
		"arc no longer active after failed_morale")


# ---------------------------------------------------------------------------
# §106 null-safety regressions (2026-08-03)
#
# `domain_religion_conversion.driving_character_id` and
# `domains.owner_character_id` are both NULLABLE, and `row.get(key, default)`
# returns the STORED null rather than the default when the key exists — so the
# `""` defaults these helpers passed never protected them and `String(null)`
# threw "Invalid call. Nonexistent 'String' constructor" at runtime.
#
# HOW THESE TESTS DETECT IT: a GDScript runtime error aborts the function and
# hands the caller the RETURN TYPE'S DEFAULT (0 / ""). So each assertion below
# pins the correct NON-default answer for the null case — 100 rather than 0,
# the ruler's id rather than "". A test that merely called the helper and
# checked it "didn't crash" would pass either way, because the abort is silent
# to the assertion layer: the pre-fix suite was 574/0 with nine of these firing.
# ---------------------------------------------------------------------------

func test_null_driving_character_id_does_not_abort_the_driver_helpers() -> void:
	_setup()
	_insert_domain_row("chaotic", "civilized", "grant", "sun-cult")
	var arc: Dictionary = _insert_arc_with_null_driver()

	# Missionary-only arcs legitimately have no driver — this is the NORMAL
	# state for one, not an edge case.
	var bonus: int = ReligionConversionResolver._driver_bonus_pct(arc, TEST_DOMAIN)
	check(bonus == ReligionConversionResolver.DRIVER_BONUS_PCT_MISSIONARY_ONLY,
		"missionary-only bonus is %d, got %d (0 means the function aborted on String(null))"
			% [ReligionConversionResolver.DRIVER_BONUS_PCT_MISSIONARY_ONLY, bonus])

	# Falls through to the ruler's Cha mod. TEST_RULER has Cha 13 → +1, chosen
	# so the correct answer differs from the aborted function's 0.
	var cha: int = ReligionConversionResolver._driver_cha_mod(arc)
	check(cha == 1,
		"falls back to the ruler's Cha 13 → +1, got %d (0 means it aborted)" % cha)

	# Resolves to the domain's ruler, not "".
	var caster: String = ReligionConversionResolver._proselytizing_caster_id(arc, TEST_DOMAIN)
	check(caster == TEST_RULER,
		"proselytizer of record falls back to the ruler, got '%s'" % caster)

	# CONTROL: with a real driver the same helpers must still USE it, so the
	# null-safe coercion cannot have collapsed every arc to the fallback.
	#
	# Discriminates on the BONUS, not on Cha: TEST_DRIVER (14) and TEST_RULER
	# (13) both sit in the 13-15 band and both yield +1, so a Cha assertion
	# could not tell "read the driver" from "fell back to the ruler". The
	# henchman tier (110) vs missionary-only (100) separates them cleanly — and
	# is the branch the dead-fixture fix made reachable for the first time.
	var driven: Dictionary = _insert_arc_with_null_driver(TEST_DRIVER)
	check(ReligionConversionResolver._proselytizing_caster_id(driven, TEST_DOMAIN) == TEST_DRIVER,
		"CONTROL: a driven arc still reports its driver")
	check(ReligionConversionResolver._driver_bonus_pct(driven, TEST_DOMAIN)
			== ReligionConversionResolver.DRIVER_BONUS_PCT_HENCHMAN_DIVINE,
		"CONTROL: and prices it at the henchman tier (%d), not missionary-only, got %d"
			% [ReligionConversionResolver.DRIVER_BONUS_PCT_HENCHMAN_DIVINE,
			   ReligionConversionResolver._driver_bonus_pct(driven, TEST_DOMAIN)])
	_cleanup()


func test_null_domain_owner_does_not_abort_the_owner_lookup() -> void:
	# `domains.owner_character_id` is nullable and goes null exactly when a ruler
	# dies — the same moment a conversion arc is most likely to still be open.
	# Latent rather than observed: unlike the driver columns above, the correct
	# answer here ("") equals the aborted function's default, so the VALUE cannot
	# discriminate. What this test buys is that the line is exercised at all, so a
	# regression shows up as a "Nonexistent 'String' constructor" in the run log.
	_setup()
	_insert_domain_row("chaotic", "civilized", "grant", "sun-cult")
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET owner_character_id = NULL WHERE id = ?", [TEST_DOMAIN])
	var arc: Dictionary = _insert_arc_with_null_driver()

	check(ReligionConversionResolver._proselytizing_caster_id(arc, TEST_DOMAIN) == "",
		"an ownerless domain yields no proselytizer of record")
	check(ReligionConversionResolver._driver_cha_mod(arc) == 0,
		"and contributes no Cha modifier")
	# The discriminating half: the bonus helper does NOT depend on the owner, so
	# it must still return the missionary-only figure rather than an aborted 0.
	check(ReligionConversionResolver._driver_bonus_pct(arc, TEST_DOMAIN)
			== ReligionConversionResolver.DRIVER_BONUS_PCT_MISSIONARY_ONLY,
		"the driver-bonus path is unaffected by the missing owner")
	_cleanup()


## Insert a conversion arc whose `driving_character_id` is SQL NULL (or
## [param driver] when given). Deliberately a raw insert: `start_conversion`
## always records a driver, so the null case cannot be built through it.
func _insert_arc_with_null_driver(driver = null) -> Dictionary:
	var arc_id: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO domain_religion_conversion
			(id, campaign_id, domain_id, from_religion, to_religion,
			 from_alignment, to_alignment, progress_pct, driving_character_id,
			 started_calendar_day, status)
		VALUES (?, ?, ?, 'sun-cult', 'chaos-cult', 'chaotic', 'chaotic', 10, ?, 1, 'active')
	""", [arc_id, TEST_CAMPAIGN, TEST_DOMAIN, driver])
	CampaignRepository.db.query_with_bindings(
		"SELECT * FROM domain_religion_conversion WHERE id = ?", [arc_id])
	return CampaignRepository.db.query_result[0].duplicate()

# ---------------------------------------------------------------------------
# Driver-tier selection (gdd-religion-conversion.md §5.4 / §9.6)
# ---------------------------------------------------------------------------

func test_driver_bonus_tier_selection() -> void:
	# `_driver_bonus_pct` picks between three tiers, and until 2026-08-03 only
	# ONE of them was ever reached: the TEST_DRIVER fixture never landed in the
	# database (persistence_tier held a character_type value, which the CHECK
	# rejected), so `get_character` missed and the `if driver.is_empty()` guard
	# returned MISSIONARY_ONLY for every arc — including the ones that passed a
	# driver in. The suite was green on a branch it was not running.
	#
	# All three tiers are asserted here so the selection cannot silently collapse
	# to one value again. The numbers come from the resolver constants rather
	# than being written out, so a rebalance moves the test with the rule.
	_setup()
	_insert_domain_row("chaotic", "civilized", "grant", "sun-cult")

	# (a) No driver at all → missionary-only.
	check(ReligionConversionResolver._driver_bonus_pct(
			_insert_arc_with_null_driver(), TEST_DOMAIN)
			== ReligionConversionResolver.DRIVER_BONUS_PCT_MISSIONARY_ONLY,
		"no driver → missionary-only tier")

	# (b) A driver who is NOT the domain owner → henchman-divine. This is the
	# branch that had never executed.
	var henchman_pct: int = ReligionConversionResolver._driver_bonus_pct(
		_insert_arc_with_null_driver(TEST_DRIVER), TEST_DOMAIN)
	check(henchman_pct == ReligionConversionResolver.DRIVER_BONUS_PCT_HENCHMAN_DIVINE,
		"a henchman divine caster is priced at %d, got %d"
			% [ReligionConversionResolver.DRIVER_BONUS_PCT_HENCHMAN_DIVINE, henchman_pct])

	# (c) A driver who IS the domain owner → ruler tier. The ruler-vs-henchman
	# comparison is the whole point of the branch, so both sides are pinned.
	var ruler_pct: int = ReligionConversionResolver._driver_bonus_pct(
		_insert_arc_with_null_driver(TEST_RULER), TEST_DOMAIN)
	check(ruler_pct == ReligionConversionResolver.DRIVER_BONUS_PCT_RULER_DIVINE_CASTER,
		"a divine-caster ruler is priced at %d, got %d"
			% [ReligionConversionResolver.DRIVER_BONUS_PCT_RULER_DIVINE_CASTER, ruler_pct])
	check(ruler_pct > henchman_pct,
		"and outranks the henchman tier (%d > %d)" % [ruler_pct, henchman_pct])

	# A driver id that does not resolve to a character falls back rather than
	# crediting a tier it cannot verify — the guard that was masking all of the
	# above. Pinned so the fixture repair cannot be silently undone.
	check(ReligionConversionResolver._driver_bonus_pct(
			_insert_arc_with_null_driver("no_such_character"), TEST_DOMAIN)
			== ReligionConversionResolver.DRIVER_BONUS_PCT_MISSIONARY_ONLY,
		"an unresolvable driver falls back to missionary-only")
	_cleanup()
