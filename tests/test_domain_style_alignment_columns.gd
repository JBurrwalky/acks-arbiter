extends "res://tests/test_suite_base.gd"

## Phase 11D.1 / migration 127: domain_style + alignment as orthogonal columns.
##
## Migration 127 (`db/migrations/127_domain_style.sql`) rebuilds the `domains`
## table to:
##   1. ADD `domain_style TEXT NOT NULL DEFAULT 'civilized'
##           CHECK(domain_style IN ('civilized', 'clanhold'))`.
##   2. DROP the deprecated `is_chaotic_domain` flag entirely (Q-DSA-3
##      resolution: no production data, no back-compat — parse-time and
##      SQL-execution failures surface any missed callsite).
##   3. Backfill `domain_style = 'clanhold'` for rows whose pre-migration
##      `is_chaotic_domain` was 1 OR `establishment_method` was one of
##      `clanhold_annex` / `recruit_chieftain`; everything else → `civilized`.
##
## The `alignment` column already existed from Phase 0 (migration 056 line
## 583 of schema.sql) with CHECK ('lawful', 'neutral', 'chaotic'); 127 does
## not change it.
##
## These tests run against the LIVE schema (post-127) so backfill behavior
## is verified by manufacturing rows with the same shape pre-127 rows would
## have had (i.e. INSERTing with explicit `domain_style` values to match
## what the backfill would have produced).
##
## Tests:
##   * test_domain_style_default_is_civilized
##   * test_domain_style_check_rejects_invalid
##   * test_is_chaotic_domain_column_dropped
##   * test_alignment_column_still_present_and_checked
##   * test_domain_style_writable_via_update_settings
##   * test_clanhold_annex_establishment_writes_clanhold_style
##   * test_recruit_chieftain_establishment_writes_clanhold_style
##   * test_grant_establishment_writes_civilized_style
##   * test_clear_establishment_writes_civilized_style_default
##   * test_orthogonal_style_and_alignment_combine_freely

const TEST_CAMPAIGN := "test_dsa_campaign"
const TEST_CHAR := "test_dsa_char"
const TEST_DOMAIN_A := "test_dsa_domain_a"
const TEST_DOMAIN_B := "test_dsa_domain_b"
const TEST_DOMAIN_C := "test_dsa_domain_c"
const TEST_DOMAIN_D := "test_dsa_domain_d"


func run_all_tests() -> void:
	_cleanup()
	test_domain_style_default_is_civilized()
	test_domain_style_check_rejects_invalid()
	test_is_chaotic_domain_column_dropped()
	test_alignment_column_still_present_and_checked()
	test_domain_style_writable_via_update_settings()
	test_clanhold_annex_establishment_writes_clanhold_style()
	test_recruit_chieftain_establishment_writes_clanhold_style()
	test_grant_establishment_writes_civilized_style()
	test_clear_establishment_writes_civilized_style_default()
	test_orthogonal_style_and_alignment_combine_freely()
	_cleanup()
	if not has_failures():
		print("DomainStyleAlignment: all tests passed.")


# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

func _setup() -> void:
	_cleanup()
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[TEST_CAMPAIGN, "Domain Style Alignment Test"])
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_type, persistence_tier,
			 race, character_class, level, xp,
			 combat_progression,
			 strength, intelligence, wisdom, dexterity, constitution, charisma,
			 alignment, is_active)
		VALUES (?, ?, ?, 'pc', 'full', 'human', 'fighter', 5, 0,
		        'fighter', 10, 10, 10, 10, 10, 10, 'chaotic', 1)
	""", [TEST_CHAR, TEST_CAMPAIGN, "Test Chaotic Fighter"])


func _cleanup() -> void:
	for d in [TEST_DOMAIN_A, TEST_DOMAIN_B, TEST_DOMAIN_C, TEST_DOMAIN_D]:
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM domain_departure_log WHERE domain_id = ?", [d])
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM domains WHERE id = ?", [d])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM characters WHERE id = ?", [TEST_CHAR])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [TEST_CAMPAIGN])


# ---------------------------------------------------------------------------
# Tests — column shape
# ---------------------------------------------------------------------------

func test_domain_style_default_is_civilized() -> void:
	_setup()
	# Insert a domain row WITHOUT specifying domain_style; default should
	# kick in to 'civilized'.
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO domains (id, campaign_id, name, owner_character_id, territory_type)
		VALUES (?, ?, ?, ?, 'wilderness')
	""", [TEST_DOMAIN_A, TEST_CAMPAIGN, "Default Style Domain", TEST_CHAR])
	var domain: Dictionary = CampaignRepository.get_domain(TEST_DOMAIN_A)
	check(String(domain.get("domain_style", "")) == "civilized",
		"default domain_style is 'civilized', got %s" % str(domain.get("domain_style", "?")))


func test_domain_style_check_rejects_invalid() -> void:
	_setup()
	# The CHECK constraint should reject any value outside ('civilized', 'clanhold').
	var ok := CampaignRepository.db.query_with_bindings("""
		INSERT INTO domains (id, campaign_id, name, owner_character_id,
		                     territory_type, domain_style)
		VALUES (?, ?, ?, ?, 'wilderness', 'invalid_style')
	""", [TEST_DOMAIN_A, TEST_CAMPAIGN, "Invalid Style", TEST_CHAR])
	check(not ok, "CHECK constraint rejects 'invalid_style' as domain_style")


func test_is_chaotic_domain_column_dropped() -> void:
	_setup()
	# Attempt to INSERT writing to the dropped column. Should fail with
	# column-not-found. Per Q-DSA-3 + convention §61 the drop is intentional
	# and surfaces any missed callsite at SQL-execution time.
	var ok := CampaignRepository.db.query_with_bindings("""
		INSERT INTO domains (id, campaign_id, name, owner_character_id,
		                     territory_type, is_chaotic_domain)
		VALUES (?, ?, ?, ?, 'wilderness', 1)
	""", [TEST_DOMAIN_A, TEST_CAMPAIGN, "Should Fail", TEST_CHAR])
	check(not ok, "INSERT referencing dropped is_chaotic_domain column fails")


func test_alignment_column_still_present_and_checked() -> void:
	_setup()
	# Alignment column survived migration 127 untouched.
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO domains (id, campaign_id, name, owner_character_id,
		                     territory_type, alignment)
		VALUES (?, ?, ?, ?, 'wilderness', 'lawful')
	""", [TEST_DOMAIN_A, TEST_CAMPAIGN, "Lawful Domain", TEST_CHAR])
	var domain: Dictionary = CampaignRepository.get_domain(TEST_DOMAIN_A)
	check(String(domain.get("alignment", "")) == "lawful",
		"alignment='lawful' roundtripped, got %s" % str(domain.get("alignment", "?")))
	# Invalid alignment value should still be rejected by the original CHECK.
	var ok := CampaignRepository.db.query_with_bindings("""
		INSERT INTO domains (id, campaign_id, name, owner_character_id,
		                     territory_type, alignment)
		VALUES (?, ?, ?, ?, 'wilderness', 'badalignment')
	""", [TEST_DOMAIN_B, TEST_CAMPAIGN, "Bad Alignment", TEST_CHAR])
	check(not ok, "CHECK constraint rejects 'badalignment' as alignment value")


func test_domain_style_writable_via_update_settings() -> void:
	_setup()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO domains (id, campaign_id, name, owner_character_id, territory_type)
		VALUES (?, ?, ?, ?, 'wilderness')
	""", [TEST_DOMAIN_A, TEST_CAMPAIGN, "Switchable", TEST_CHAR])
	# domain_style is on the settings whitelist (campaign_repository.gd
	# _DOMAIN_SETTINGS_FIELDS), so update_domain_settings can flip it.
	check(CampaignRepository.update_domain_settings(TEST_DOMAIN_A,
			{"domain_style": "clanhold"}),
		"update_domain_settings accepts domain_style='clanhold'")
	var d := CampaignRepository.get_domain(TEST_DOMAIN_A)
	check(String(d.get("domain_style", "")) == "clanhold",
		"update flipped domain_style to clanhold")


# ---------------------------------------------------------------------------
# Tests — establishment flow integration
# ---------------------------------------------------------------------------

func test_clanhold_annex_establishment_writes_clanhold_style() -> void:
	_setup()
	# Chaotic-method paths force-lock domain_style='clanhold' per
	# EstablishDomainFlow.establish_domain.
	var chaotic_char := {"character_class": "fighter", "alignment": "chaotic"}
	var result := EstablishDomainFlow.establish_domain({
		"campaign_id": TEST_CAMPAIGN,
		"owner_character_id": TEST_CHAR,
		"character": chaotic_char,
		"name": "Annex Test Domain",
		"territory_type": "wilderness",
		"establishment_method": "clanhold_annex",
		"domain_style": "civilized",  # caller passes wrong value; flow force-locks
	})
	check(result["errors"].is_empty(),
		"establish OK, errors=%s" % str(result["errors"]))
	var domain := CampaignRepository.get_domain(result["domain_id"])
	check(String(domain.get("domain_style", "")) == "clanhold",
		"clanhold_annex force-locks domain_style=clanhold, got %s" % str(domain.get("domain_style", "?")))
	# Cleanup: this test inserts a fresh row.
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM domains WHERE id = ?", [result["domain_id"]])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM domain_departure_log WHERE domain_id = ?", [result["domain_id"]])


func test_recruit_chieftain_establishment_writes_clanhold_style() -> void:
	_setup()
	var chaotic_char := {"character_class": "fighter", "alignment": "chaotic"}
	var result := EstablishDomainFlow.establish_domain({
		"campaign_id": TEST_CAMPAIGN,
		"owner_character_id": TEST_CHAR,
		"character": chaotic_char,
		"name": "Recruit Test Domain",
		"territory_type": "wilderness",
		"establishment_method": "recruit_chieftain",
	})
	check(result["errors"].is_empty(),
		"establish OK, errors=%s" % str(result["errors"]))
	var domain := CampaignRepository.get_domain(result["domain_id"])
	check(String(domain.get("domain_style", "")) == "clanhold",
		"recruit_chieftain force-locks domain_style=clanhold, got %s" % str(domain.get("domain_style", "?")))
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM domains WHERE id = ?", [result["domain_id"]])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM domain_departure_log WHERE domain_id = ?", [result["domain_id"]])


func test_grant_establishment_writes_civilized_style() -> void:
	_setup()
	# A lawful PC + METHOD_GRANT establishment defaults to civilized style.
	# (We use a lawful character here to exercise the no-force-lock path.)
	CampaignRepository.db.query_with_bindings("""
		UPDATE characters SET alignment = 'lawful' WHERE id = ?
	""", [TEST_CHAR])
	var lawful_char := {"character_class": "fighter", "alignment": "lawful"}
	var result := EstablishDomainFlow.establish_domain({
		"campaign_id": TEST_CAMPAIGN,
		"owner_character_id": TEST_CHAR,
		"character": lawful_char,
		"name": "Grant Test Domain",
		"territory_type": "civilized",
		"establishment_method": "grant",
	})
	check(result["errors"].is_empty(),
		"establish OK, errors=%s" % str(result["errors"]))
	var domain := CampaignRepository.get_domain(result["domain_id"])
	check(String(domain.get("domain_style", "")) == "civilized",
		"grant + no domain_style param → civilized default, got %s"
		% str(domain.get("domain_style", "?")))
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM domains WHERE id = ?", [result["domain_id"]])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM domain_departure_log WHERE domain_id = ?", [result["domain_id"]])


func test_clear_establishment_writes_civilized_style_default() -> void:
	_setup()
	# METHOD_CLEAR does not force-lock style; default civilized.
	CampaignRepository.db.query_with_bindings("""
		UPDATE characters SET alignment = 'lawful' WHERE id = ?
	""", [TEST_CHAR])
	var lawful_char := {"character_class": "fighter", "alignment": "lawful"}
	var result := EstablishDomainFlow.establish_domain({
		"campaign_id": TEST_CAMPAIGN,
		"owner_character_id": TEST_CHAR,
		"character": lawful_char,
		"name": "Clear Test Domain",
		"territory_type": "wilderness",
		"establishment_method": "clear",
	})
	check(result["errors"].is_empty(),
		"establish OK, errors=%s" % str(result["errors"]))
	var domain := CampaignRepository.get_domain(result["domain_id"])
	check(String(domain.get("domain_style", "")) == "civilized",
		"clear + no domain_style param → civilized default, got %s"
		% str(domain.get("domain_style", "?")))
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM domains WHERE id = ?", [result["domain_id"]])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM domain_departure_log WHERE domain_id = ?", [result["domain_id"]])


# ---------------------------------------------------------------------------
# Test — the orthogonal-axes core invariant
# ---------------------------------------------------------------------------

func test_orthogonal_style_and_alignment_combine_freely() -> void:
	_setup()
	# Verify the core promise of the orthogonal-axes design: a domain can be
	# any combination of (style ∈ {civilized, clanhold}) × (alignment ∈
	# {lawful, neutral, chaotic}) at the SQL layer. Establishment-eligibility
	# gates are enforced by EstablishDomainFlow per Phase 11D.4; this test
	# exercises the raw schema.
	var combos := [
		[TEST_DOMAIN_A, "civilized", "lawful"],
		[TEST_DOMAIN_B, "civilized", "chaotic"],   # converted chaotic kingdom
		[TEST_DOMAIN_C, "clanhold",  "lawful"],    # kin clanhold of lawful alignment
		[TEST_DOMAIN_D, "clanhold",  "chaotic"],   # beastman clanhold (force-locked combo)
	]
	for combo in combos:
		var did := String(combo[0])
		var style := String(combo[1])
		var alignment := String(combo[2])
		var ok := CampaignRepository.db.query_with_bindings("""
			INSERT INTO domains (id, campaign_id, name, owner_character_id,
			                     territory_type, domain_style, alignment)
			VALUES (?, ?, ?, ?, 'wilderness', ?, ?)
		""", [did, TEST_CAMPAIGN, "Combo " + did, TEST_CHAR, style, alignment])
		check(ok, "INSERT %s + %s succeeds (orthogonal combo)" % [style, alignment])
		var d := CampaignRepository.get_domain(did)
		check(String(d.get("domain_style", "")) == style,
			"%s + %s: domain_style roundtripped" % [style, alignment])
		check(String(d.get("alignment", "")) == alignment,
			"%s + %s: alignment roundtripped" % [style, alignment])
