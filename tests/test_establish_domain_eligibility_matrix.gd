extends "res://tests/test_suite_base.gd"

## Phase 11D.4 — Establishment eligibility matrix tests per
## `gdd-domain-style-and-alignment.md` §7.
##
## Coverage:
##   * S3 enforcement: lawful/neutral PC blocked from METHOD_CONQUEST vs
##     beastman target; METHOD_CLEAR vs beastman lair ALLOWED (scatters).
##   * Chaotic-method paths require chaotic alignment (existing constraint).
##   * Explicit civilized style with clanhold-only methods → error.
##   * LifecycleHandler.conquer_domain defense-in-depth rejection.
##   * Vassal-appointment warning helper output.

const TEST_CAMPAIGN := "test_em_campaign"
const TEST_LAWFUL_PC := "test_em_lawful_pc"
const TEST_NEUTRAL_PC := "test_em_neutral_pc"
const TEST_CHAOTIC_PC := "test_em_chaotic_pc"
const TEST_BEASTMAN_HENCHMAN := "test_em_beastman_hench"
const TEST_TARGET_BEASTMAN_DOMAIN := "test_em_beastman_target"
const TEST_TARGET_KIN_DOMAIN := "test_em_kin_target"
const TEST_NEW_DOMAIN := "test_em_new_domain"


func run_all_tests() -> void:
	_cleanup()
	# Eligibility matrix
	test_lawful_conquest_vs_beastman_blocked()
	test_neutral_conquest_vs_beastman_blocked()
	test_chaotic_conquest_vs_beastman_allowed()
	test_lawful_clear_vs_beastman_lair_allowed()
	test_lawful_clear_vs_beastman_lair_explicit_clanhold_allowed()
	test_chaotic_methods_require_chaotic_alignment()
	test_clanhold_annex_with_explicit_civilized_style_rejected()
	test_recruit_chieftain_with_explicit_civilized_style_rejected()
	test_chaotic_methods_default_civilized_omission_still_allowed()
	test_lawful_conquest_vs_kin_target_allowed()
	# LifecycleHandler defense-in-depth
	test_conquer_domain_blocks_lawful_conqueror_of_beastman()
	test_conquer_domain_allows_chaotic_conqueror_of_beastman()
	# Vassal-appointment warnings
	test_vassal_warning_aligned_henchman_no_warnings()
	test_vassal_warning_alignment_mismatch_minus_1()
	test_vassal_warning_lc_pair_minus_2()
	test_vassal_warning_beastman_over_kin_stack()
	_cleanup()
	if not has_failures():
		print("EstablishDomainEligibilityMatrix: all tests passed.")


# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

func _setup() -> void:
	_cleanup()
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[TEST_CAMPAIGN, "Eligibility Matrix Test"])
	# Three PC alignments + a beastman henchman.
	var pcs := [
		[TEST_LAWFUL_PC,  "lawful",  "human"],
		[TEST_NEUTRAL_PC, "neutral", "human"],
		[TEST_CHAOTIC_PC, "chaotic", "human"],
		[TEST_BEASTMAN_HENCHMAN, "chaotic", "hobgoblin"],
	]
	for pc in pcs:
		CampaignRepository.db.query_with_bindings("""
			INSERT OR IGNORE INTO characters
				(id, campaign_id, name, character_type, persistence_tier,
				 race, character_class, level, xp, combat_progression,
				 strength, intelligence, wisdom, dexterity, constitution, charisma,
				 alignment, is_active)
			VALUES (?, ?, ?, 'pc', 'full', ?, 'fighter', 9, 0, 'fighter',
			        10, 10, 10, 10, 10, 10, ?, 1)
		""", [pc[0], TEST_CAMPAIGN, "Test PC " + pc[0], pc[2], pc[1]])
	# Beastman-populated target (establishment_method=clanhold_annex).
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO domains
			(id, campaign_id, name, owner_character_id, territory_type,
			 peasant_families, alignment, religion, effective_religion,
			 domain_style, establishment_method, established_calendar_day)
		VALUES (?, ?, ?, ?, 'wilderness', 200, 'chaotic', 'chaos-cult', 'chaos-cult',
		        'clanhold', 'clanhold_annex', 1)
	""", [TEST_TARGET_BEASTMAN_DOMAIN, TEST_CAMPAIGN,
		  "Beastman Target", TEST_CHAOTIC_PC])
	# Kin-populated target (METHOD_GRANT → civilized).
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO domains
			(id, campaign_id, name, owner_character_id, territory_type,
			 peasant_families, alignment, religion, effective_religion,
			 domain_style, establishment_method, established_calendar_day)
		VALUES (?, ?, ?, ?, 'civilized', 500, 'lawful', 'sun-cult', 'sun-cult',
		        'civilized', 'grant', 1)
	""", [TEST_TARGET_KIN_DOMAIN, TEST_CAMPAIGN,
		  "Kin Target", TEST_LAWFUL_PC])


func _cleanup() -> void:
	for d in [TEST_TARGET_BEASTMAN_DOMAIN, TEST_TARGET_KIN_DOMAIN, TEST_NEW_DOMAIN]:
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM domain_departure_log WHERE domain_id = ?", [d])
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM domain_hexes WHERE domain_id = ?", [d])
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM domains WHERE id = ?", [d])
	for c in [TEST_LAWFUL_PC, TEST_NEUTRAL_PC, TEST_CHAOTIC_PC, TEST_BEASTMAN_HENCHMAN]:
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM characters WHERE id = ?", [c])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [TEST_CAMPAIGN])


func _character_dict(pc_id: String) -> Dictionary:
	return CampaignRepository.get_character(pc_id)


# ---------------------------------------------------------------------------
# Eligibility matrix — S3 enforcement
# ---------------------------------------------------------------------------

func test_lawful_conquest_vs_beastman_blocked() -> void:
	_setup()
	var errors: Array = EstablishDomainFlow.validate_establishment({
		"campaign_id": TEST_CAMPAIGN,
		"owner_character_id": TEST_LAWFUL_PC,
		"character": _character_dict(TEST_LAWFUL_PC),
		"name": "Should Fail",
		"territory_type": "wilderness",
		"establishment_method": "conquest",
		"target_domain_id": TEST_TARGET_BEASTMAN_DOMAIN,
	})
	check(EstablishDomainFlow.ERR_BEASTMAN_BLOCKED_FOR_LAWFUL_NEUTRAL in errors,
		"lawful METHOD_CONQUEST vs beastman blocked; errors=%s" % str(errors))


func test_neutral_conquest_vs_beastman_blocked() -> void:
	_setup()
	var errors: Array = EstablishDomainFlow.validate_establishment({
		"campaign_id": TEST_CAMPAIGN,
		"owner_character_id": TEST_NEUTRAL_PC,
		"character": _character_dict(TEST_NEUTRAL_PC),
		"name": "Should Fail",
		"territory_type": "wilderness",
		"establishment_method": "conquest",
		"target_domain_id": TEST_TARGET_BEASTMAN_DOMAIN,
	})
	check(EstablishDomainFlow.ERR_BEASTMAN_BLOCKED_FOR_LAWFUL_NEUTRAL in errors,
		"neutral METHOD_CONQUEST vs beastman blocked; errors=%s" % str(errors))


func test_chaotic_conquest_vs_beastman_allowed() -> void:
	_setup()
	var errors: Array = EstablishDomainFlow.validate_establishment({
		"campaign_id": TEST_CAMPAIGN,
		"owner_character_id": TEST_CHAOTIC_PC,
		"character": _character_dict(TEST_CHAOTIC_PC),
		"name": "Chaotic Conquest",
		"territory_type": "wilderness",
		"establishment_method": "conquest",
		"target_domain_id": TEST_TARGET_BEASTMAN_DOMAIN,
	})
	check(not (EstablishDomainFlow.ERR_BEASTMAN_BLOCKED_FOR_LAWFUL_NEUTRAL in errors),
		"chaotic METHOD_CONQUEST vs beastman allowed; errors=%s" % str(errors))


func test_lawful_clear_vs_beastman_lair_allowed() -> void:
	_setup()
	# METHOD_CLEAR vs beastman lair (no target domain; caller flags target_is_beastman).
	var errors: Array = EstablishDomainFlow.validate_establishment({
		"campaign_id": TEST_CAMPAIGN,
		"owner_character_id": TEST_LAWFUL_PC,
		"character": _character_dict(TEST_LAWFUL_PC),
		"name": "Cleared Wilderness",
		"territory_type": "wilderness",
		"establishment_method": "clear",
		"target_is_beastman": true,
	})
	# METHOD_CLEAR scatters the beastmen; the S3 block does NOT fire.
	check(not (EstablishDomainFlow.ERR_BEASTMAN_BLOCKED_FOR_LAWFUL_NEUTRAL in errors),
		"lawful METHOD_CLEAR vs beastman lair allowed; errors=%s" % str(errors))


func test_lawful_clear_vs_beastman_lair_explicit_clanhold_allowed() -> void:
	_setup()
	# Lawful player can elect clanhold style at METHOD_CLEAR establishment.
	var errors: Array = EstablishDomainFlow.validate_establishment({
		"campaign_id": TEST_CAMPAIGN,
		"owner_character_id": TEST_LAWFUL_PC,
		"character": _character_dict(TEST_LAWFUL_PC),
		"name": "Cleared Kin Clanhold",
		"territory_type": "wilderness",
		"establishment_method": "clear",
		"domain_style": "clanhold",
		"target_is_beastman": true,
	})
	check(errors.is_empty(),
		"lawful METHOD_CLEAR + clanhold style after clearing beastman lair allowed; errors=%s" % str(errors))


func test_chaotic_methods_require_chaotic_alignment() -> void:
	_setup()
	var errors: Array = EstablishDomainFlow.validate_establishment({
		"campaign_id": TEST_CAMPAIGN,
		"owner_character_id": TEST_LAWFUL_PC,
		"character": _character_dict(TEST_LAWFUL_PC),
		"name": "Should Fail",
		"territory_type": "wilderness",
		"establishment_method": "clanhold_annex",
	})
	check(EstablishDomainFlow.ERR_CHAOTIC_REQUIRED in errors,
		"lawful PC CLANHOLD_ANNEX requires chaotic alignment; errors=%s" % str(errors))


func test_clanhold_annex_with_explicit_civilized_style_rejected() -> void:
	_setup()
	var errors: Array = EstablishDomainFlow.validate_establishment({
		"campaign_id": TEST_CAMPAIGN,
		"owner_character_id": TEST_CHAOTIC_PC,
		"character": _character_dict(TEST_CHAOTIC_PC),
		"name": "Should Fail",
		"territory_type": "wilderness",
		"establishment_method": "clanhold_annex",
		"domain_style": "civilized",
	})
	check(EstablishDomainFlow.ERR_INVALID_STYLE_FOR_METHOD in errors,
		"CLANHOLD_ANNEX + explicit civilized style → ERR_INVALID_STYLE_FOR_METHOD; got errors=%s"
		% str(errors))


func test_recruit_chieftain_with_explicit_civilized_style_rejected() -> void:
	_setup()
	var errors: Array = EstablishDomainFlow.validate_establishment({
		"campaign_id": TEST_CAMPAIGN,
		"owner_character_id": TEST_CHAOTIC_PC,
		"character": _character_dict(TEST_CHAOTIC_PC),
		"name": "Should Fail",
		"territory_type": "wilderness",
		"establishment_method": "recruit_chieftain",
		"domain_style": "civilized",
	})
	check(EstablishDomainFlow.ERR_INVALID_STYLE_FOR_METHOD in errors,
		"RECRUIT_CHIEFTAIN + explicit civilized style → ERR_INVALID_STYLE_FOR_METHOD; got errors=%s"
		% str(errors))


func test_chaotic_methods_default_civilized_omission_still_allowed() -> void:
	_setup()
	# When caller OMITS domain_style entirely, establish_domain's force-lock
	# path kicks in — no error. (This test validates that ERR_INVALID_STYLE
	# fires only on explicit civilized values, not on the default fallback.)
	var errors: Array = EstablishDomainFlow.validate_establishment({
		"campaign_id": TEST_CAMPAIGN,
		"owner_character_id": TEST_CHAOTIC_PC,
		"character": _character_dict(TEST_CHAOTIC_PC),
		"name": "No-style Caller",
		"territory_type": "wilderness",
		"establishment_method": "clanhold_annex",
		# no domain_style key
	})
	check(not (EstablishDomainFlow.ERR_INVALID_STYLE_FOR_METHOD in errors),
		"omitted domain_style should NOT trigger ERR_INVALID_STYLE_FOR_METHOD; errors=%s"
		% str(errors))


func test_lawful_conquest_vs_kin_target_allowed() -> void:
	_setup()
	# Lawful conquest of a kin (non-beastman) target is allowed by the matrix
	# (with alignment penalty applied at the morale layer per §8.1).
	var errors: Array = EstablishDomainFlow.validate_establishment({
		"campaign_id": TEST_CAMPAIGN,
		"owner_character_id": TEST_LAWFUL_PC,
		"character": _character_dict(TEST_LAWFUL_PC),
		"name": "Kin Conquest",
		"territory_type": "civilized",
		"establishment_method": "conquest",
		"target_domain_id": TEST_TARGET_KIN_DOMAIN,
	})
	check(not (EstablishDomainFlow.ERR_BEASTMAN_BLOCKED_FOR_LAWFUL_NEUTRAL in errors),
		"lawful METHOD_CONQUEST vs kin allowed; errors=%s" % str(errors))


# ---------------------------------------------------------------------------
# LifecycleHandler defense-in-depth
# ---------------------------------------------------------------------------

func test_conquer_domain_blocks_lawful_conqueror_of_beastman() -> void:
	_setup()
	# Try to conquer the beastman target with a lawful conqueror — should
	# be refused at the conquer_domain boundary even if the caller bypassed
	# the EstablishDomainFlow validator.
	var ok := LifecycleHandler.conquer_domain(
		TEST_TARGET_BEASTMAN_DOMAIN,
		1,
		LifecycleHandler.OUTCOME_OCCUPIED,
		TEST_LAWFUL_PC,   # lawful conqueror
		0,                # no pillage
		{})
	check(not ok,
		"conquer_domain should reject lawful conqueror over beastman target; got ok=%s"
		% str(ok))
	# Confirm ownership did NOT change.
	var d := CampaignRepository.get_domain(TEST_TARGET_BEASTMAN_DOMAIN)
	check(String(d.get("owner_character_id", "")) == TEST_CHAOTIC_PC,
		"ownership preserved after blocked conquest")


func test_conquer_domain_allows_chaotic_conqueror_of_beastman() -> void:
	_setup()
	var ok := LifecycleHandler.conquer_domain(
		TEST_TARGET_BEASTMAN_DOMAIN,
		1,
		LifecycleHandler.OUTCOME_OCCUPIED,
		TEST_CHAOTIC_PC,
		0,
		{})
	check(ok, "chaotic conqueror over beastman target allowed; got ok=%s" % str(ok))


# ---------------------------------------------------------------------------
# Vassal-appointment warnings
# ---------------------------------------------------------------------------

func test_vassal_warning_aligned_henchman_no_warnings() -> void:
	_setup()
	# Lawful henchman over lawful kin domain: no warning.
	var warnings: Array = VassalAppointmentWarnings.warnings_for_appointment(
		TEST_LAWFUL_PC, TEST_TARGET_KIN_DOMAIN)
	check(warnings.is_empty(),
		"aligned appointment: no warnings; got %s" % str(warnings))


func test_vassal_warning_alignment_mismatch_minus_1() -> void:
	_setup()
	# Neutral henchman over lawful kin domain: N/L → −1.
	var warnings: Array = VassalAppointmentWarnings.warnings_for_appointment(
		TEST_NEUTRAL_PC, TEST_TARGET_KIN_DOMAIN)
	check(warnings.size() == 1,
		"single −1 alignment warning; got %d warnings" % warnings.size())
	check(String(warnings[0]).contains("−1"),
		"warning text mentions −1; got %s" % str(warnings[0]))


func test_vassal_warning_lc_pair_minus_2() -> void:
	_setup()
	# Chaotic henchman over lawful kin domain: L/C → −2.
	var warnings: Array = VassalAppointmentWarnings.warnings_for_appointment(
		TEST_CHAOTIC_PC, TEST_TARGET_KIN_DOMAIN)
	check(warnings.size() == 1,
		"single −2 alignment warning; got %d warnings" % warnings.size())
	check(String(warnings[0]).contains("−2"),
		"warning text mentions −2; got %s" % str(warnings[0]))


func test_vassal_warning_beastman_over_kin_stack() -> void:
	_setup()
	# Beastman (chaotic hobgoblin) henchman over lawful kin domain:
	# alignment penalty (L/C, −2) + beastman-rules-kin (−2). Two warnings
	# + a third "religion conversion" guidance line.
	var warnings: Array = VassalAppointmentWarnings.warnings_for_appointment(
		TEST_BEASTMAN_HENCHMAN, TEST_TARGET_KIN_DOMAIN)
	check(warnings.size() == 3,
		"alignment + beastman + guidance: 3 warnings; got %d" % warnings.size())
	var combined: String = " ".join(warnings)
	check(combined.contains("−2"),
		"warnings include −2 alignment penalty")
	check(combined.contains("beastman ruler over kin"),
		"warnings include beastman-rules-kin stack text; got %s" % combined)
