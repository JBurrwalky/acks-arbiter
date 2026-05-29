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
	# Driving caster (henchman).
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_type, persistence_tier,
			 race, character_class, level, xp, combat_progression,
			 strength, intelligence, wisdom, dexterity, constitution, charisma,
			 alignment, is_active)
		VALUES (?, ?, 'Test Driver', 'pc', 'henchman',
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
		allowed_by_alignment[String(opt.get("alignment", ""))] = bool(opt.get("allowed", false))
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
	# 1 roll × 11 × 200% morale × 110% henchman × 100% no altar = 24 → caps at room=201
	var deterministic_roller := func(_faces: int, count: int, _exp: bool) -> int:
		return 10 * count
	var result := ReligionConversionResolver.tick_conversion(d, 2, deterministic_roller)
	check(bool(result.get("completed", false)),
		"tick should complete: gain=%d completed=%s" % [
			int(result.get("congregant_gain", 0)),
			str(result.get("completed", false))])
	var d_after := CampaignRepository.get_domain(TEST_DOMAIN)
	check(String(d_after.get("effective_religion", "")) == "chaos-cult",
		"effective_religion flipped on completion")
	check(String(d_after.get("alignment", "")) == "chaotic",
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
