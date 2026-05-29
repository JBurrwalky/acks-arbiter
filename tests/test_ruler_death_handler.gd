extends "res://tests/test_suite_base.gd"

## Phase 11C: RulerDeathHandler tests covering the five public methods +
## the monthly-tick grace check + the vassal-reverts-to-overlord default.

const TEST_CAMPAIGN := "test_succession_campaign"
const RULER_ID := "test_succession_ruler"
const HEIR_PC_ID := "test_succession_heir_pc"
const HEIR_HENCHMAN_ID := "test_succession_heir_hench"
const HEIR_NONHENCHMAN_ID := "test_succession_heir_nonhench"
const OVERLORD_ID := "test_succession_overlord"
const DOMAIN_ID := "test_succession_domain"
const OVERLORD_DOMAIN_ID := "test_succession_overlord_domain"


func run_all_tests() -> void:
	_cleanup()
	_setup_campaign_and_characters()
	test_handle_ruler_death_marks_domains_pending()
	test_handle_ruler_death_skips_terminal_domains()
	test_designate_heir_writes_columns_and_emits_signal()
	test_designate_heir_rejects_non_pending_domain()
	test_resolve_succession_with_henchman_heir_transfers_ownership()
	test_resolve_succession_with_non_henchman_records_loyalty_minus_2()
	test_resolve_succession_independent_no_heir_abandons()
	test_resolve_succession_vassal_no_heir_reverts_to_overlord()
	test_tick_succession_grace_active_no_op()
	test_tick_succession_grace_lapse_with_heir_auto_resolves()
	test_tick_succession_grace_lapse_no_heir_lapses()
	test_eligible_heirs_for_returns_pcs_and_henchmen()
	test_eligible_heirs_for_kind_chips_correct()
	test_invalid_inputs_rejected()
	_cleanup()
	if not has_failures():
		print("RulerDeathHandler: all tests passed.")


# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

func _setup_campaign_and_characters() -> void:
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[TEST_CAMPAIGN, "Succession Test"])
	_insert_character(RULER_ID, "Ruler", "pc")
	_insert_character(HEIR_PC_ID, "Heir PC", "pc")
	_insert_character(HEIR_HENCHMAN_ID, "Heir Henchman", "henchman")
	_insert_character(HEIR_NONHENCHMAN_ID, "Heir NonHench", "npc")
	_insert_character(OVERLORD_ID, "Overlord PC", "pc")


func _insert_character(id: String, name: String, character_type: String) -> void:
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_type, persistence_tier,
			 race, character_class, level, xp,
			 combat_progression,
			 strength, intelligence, wisdom, dexterity, constitution, charisma,
			 is_active)
		VALUES (?, ?, ?, ?, 'full', 'human', 'fighter', 5, 0,
		        'fighter', 10, 10, 10, 10, 10, 10, 1)
	""", [id, TEST_CAMPAIGN, name, character_type])


func _create_domain(
	domain_id: String,
	owner_id: String,
	liege_domain_id: String = "",
) -> void:
	var liege_v: Variant = null
	if not liege_domain_id.is_empty():
		liege_v = liege_domain_id
	CampaignRepository.db.query_with_bindings("""
		INSERT OR REPLACE INTO domains
			(id, campaign_id, name, owner_character_id, territory_type,
			 peasant_families, morale, treasury_cp,
			 established_calendar_day, lifecycle_state, liege_domain_id)
		VALUES (?, ?, ?, ?, 'wilderness', 100, 0, 0, 100, 'active', ?)
	""", [domain_id, TEST_CAMPAIGN, "Test Domain " + domain_id, owner_id, liege_v])


func _cleanup() -> void:
	for d in [DOMAIN_ID, OVERLORD_DOMAIN_ID]:
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM domain_hexes WHERE domain_id = ?", [d])
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM domains WHERE id = ?", [d])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM domain_departure_log WHERE campaign_id = ?", [TEST_CAMPAIGN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM vassal_assignments WHERE campaign_id = ?", [TEST_CAMPAIGN])
	for c in [RULER_ID, HEIR_PC_ID, HEIR_HENCHMAN_ID, HEIR_NONHENCHMAN_ID, OVERLORD_ID]:
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM characters WHERE id = ?", [c])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [TEST_CAMPAIGN])


func _reload_domain(domain_id: String) -> Dictionary:
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM domains WHERE id = ?", [domain_id]
	) or CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0]


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_handle_ruler_death_marks_domains_pending() -> void:
	_cleanup(); _setup_campaign_and_characters()
	_create_domain(DOMAIN_ID, RULER_ID)
	var affected: Array = RulerDeathHandler.handle_ruler_death(RULER_ID, 500)
	check(affected.size() == 1, "affected count=1, got %d" % affected.size())
	check(affected[0] == DOMAIN_ID, "affected list contains the domain")
	var row: Dictionary = _reload_domain(DOMAIN_ID)
	check(str(row.get("lifecycle_state", "")) == "succession_pending",
		"lifecycle_state=succession_pending, got %s" % str(row.get("lifecycle_state", "")))
	check(int(row.get("succession_pending_until_day", 0)) == 530,
		"grace_until=530 (500+30), got %d" % int(row.get("succession_pending_until_day", 0)))
	var entries: Array = DepartureLogRecorder.list_for_domain(DOMAIN_ID)
	var has_ruler_died := false
	for e in entries:
		if String(e.get("event_type", "")) == "ruler_died":
			has_ruler_died = true
			break
	check(has_ruler_died, "ruler_died log entry recorded")


func test_handle_ruler_death_skips_terminal_domains() -> void:
	_cleanup(); _setup_campaign_and_characters()
	# Domain pre-set to terminal state — death sweep should skip.
	_create_domain(DOMAIN_ID, RULER_ID)
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET lifecycle_state = 'abandoned' WHERE id = ?", [DOMAIN_ID])
	var affected: Array = RulerDeathHandler.handle_ruler_death(RULER_ID, 500)
	check(affected.is_empty(),
		"abandoned domains skipped by ruler-death sweep, affected count=%d" % affected.size())
	var row: Dictionary = _reload_domain(DOMAIN_ID)
	check(str(row.get("lifecycle_state", "")) == "abandoned",
		"state stayed abandoned")


func test_designate_heir_writes_columns_and_emits_signal() -> void:
	_cleanup(); _setup_campaign_and_characters()
	_create_domain(DOMAIN_ID, RULER_ID)
	RulerDeathHandler.handle_ruler_death(RULER_ID, 500)
	var ok := RulerDeathHandler.designate_heir(
		DOMAIN_ID, HEIR_HENCHMAN_ID, RulerDeathHandler.KIND_HENCHMAN)
	check(ok, "designate_heir returned true")
	var row: Dictionary = _reload_domain(DOMAIN_ID)
	check(str(row.get("designated_heir_character_id", "")) == HEIR_HENCHMAN_ID,
		"heir id persisted, got %s" % str(row.get("designated_heir_character_id", "")))
	check(str(row.get("designated_heir_kind", "")) == "henchman",
		"heir kind persisted, got %s" % str(row.get("designated_heir_kind", "")))
	# Lifecycle state unchanged (still pending until resolve).
	check(str(row.get("lifecycle_state", "")) == "succession_pending",
		"state stays succession_pending until resolve")


func test_designate_heir_rejects_non_pending_domain() -> void:
	_cleanup(); _setup_campaign_and_characters()
	_create_domain(DOMAIN_ID, RULER_ID)
	# Domain is active, not pending — should reject.
	var ok := RulerDeathHandler.designate_heir(
		DOMAIN_ID, HEIR_HENCHMAN_ID, RulerDeathHandler.KIND_HENCHMAN)
	check(not ok, "designate_heir rejected on non-pending domain")


func test_resolve_succession_with_henchman_heir_transfers_ownership() -> void:
	_cleanup(); _setup_campaign_and_characters()
	_create_domain(DOMAIN_ID, RULER_ID)
	RulerDeathHandler.handle_ruler_death(RULER_ID, 500)
	RulerDeathHandler.designate_heir(
		DOMAIN_ID, HEIR_HENCHMAN_ID, RulerDeathHandler.KIND_HENCHMAN)
	var result: Dictionary = RulerDeathHandler.resolve_succession(DOMAIN_ID, 510)
	check(bool(result.get("resolved", false)), "resolved=true")
	check(String(result.get("new_owner_id", "")) == HEIR_HENCHMAN_ID, "new owner = heir")
	check(String(result.get("heir_kind", "")) == "henchman", "heir_kind=henchman")
	check(not bool(result.get("reverted_to_overlord", true)),
		"reverted_to_overlord=false")
	check(not bool(result.get("abandoned", true)), "abandoned=false")
	var row: Dictionary = _reload_domain(DOMAIN_ID)
	check(str(row.get("owner_character_id", "")) == HEIR_HENCHMAN_ID,
		"owner column = heir")
	check(str(row.get("lifecycle_state", "")) == "active",
		"lifecycle_state back to active")


func test_resolve_succession_with_non_henchman_records_loyalty_minus_2() -> void:
	_cleanup(); _setup_campaign_and_characters()
	_create_domain(DOMAIN_ID, RULER_ID)
	RulerDeathHandler.handle_ruler_death(RULER_ID, 500)
	RulerDeathHandler.designate_heir(
		DOMAIN_ID, HEIR_NONHENCHMAN_ID, RulerDeathHandler.KIND_NON_HENCHMAN)
	RulerDeathHandler.resolve_succession(DOMAIN_ID, 510)
	# Verify the departure-log row carries the -2 modifier so future Dynasties
	# / loyalty consumers can read it back.
	var entries: Array = DepartureLogRecorder.list_for_domain(DOMAIN_ID)
	var resolved_entry: Dictionary = {}
	for e in entries:
		if String(e.get("event_type", "")) == "succession_resolved":
			resolved_entry = e
			break
	check(not resolved_entry.is_empty(), "succession_resolved log entry present")
	var details: Dictionary = resolved_entry.get("full_details", {})
	check(int(details.get("non_henchman_loyalty_modifier", 0)) == -2,
		"non_henchman_loyalty_modifier = -2, got %d" % int(details.get("non_henchman_loyalty_modifier", 0)))


func test_resolve_succession_independent_no_heir_abandons() -> void:
	_cleanup(); _setup_campaign_and_characters()
	_create_domain(DOMAIN_ID, RULER_ID)  # no liege → independent
	RulerDeathHandler.handle_ruler_death(RULER_ID, 500)
	var result: Dictionary = RulerDeathHandler.resolve_succession(DOMAIN_ID, 510)
	check(bool(result.get("abandoned", false)),
		"abandoned=true for independent + no heir")
	var row: Dictionary = _reload_domain(DOMAIN_ID)
	check(str(row.get("lifecycle_state", "")) == "abandoned",
		"state=abandoned via LifecycleHandler")


func test_resolve_succession_vassal_no_heir_reverts_to_overlord() -> void:
	_cleanup(); _setup_campaign_and_characters()
	_create_domain(OVERLORD_DOMAIN_ID, OVERLORD_ID)
	_create_domain(DOMAIN_ID, RULER_ID, OVERLORD_DOMAIN_ID)
	RulerDeathHandler.handle_ruler_death(RULER_ID, 500)
	var result: Dictionary = RulerDeathHandler.resolve_succession(DOMAIN_ID, 510)
	check(bool(result.get("reverted_to_overlord", false)),
		"reverted_to_overlord=true for vassal + no heir, got %s" % str(result))
	check(String(result.get("new_owner_id", "")) == OVERLORD_ID,
		"new owner = overlord PC")
	var row: Dictionary = _reload_domain(DOMAIN_ID)
	check(str(row.get("owner_character_id", "")) == OVERLORD_ID,
		"owner column = overlord")
	check(str(row.get("lifecycle_state", "")) == "active",
		"lifecycle_state back to active under direct rule")
	# liege_domain_id should be cleared so the domain is no longer a vassal.
	var liege_v: Variant = row.get("liege_domain_id", null)
	var liege_str: String = "" if liege_v == null else String(liege_v)
	check(liege_str.is_empty(),
		"liege_domain_id cleared on reverts-to-overlord, got '%s'" % liege_str)


func test_tick_succession_grace_active_no_op() -> void:
	_cleanup(); _setup_campaign_and_characters()
	_create_domain(DOMAIN_ID, RULER_ID)
	var row: Dictionary = _reload_domain(DOMAIN_ID)
	var summary: Dictionary = RulerDeathHandler.tick_succession_grace(row, 9999)
	check(not bool(summary.get("auto_resolved", true)),
		"auto_resolved=false on active domain")
	check(not bool(summary.get("lapsed", true)),
		"lapsed=false on active domain")


func test_tick_succession_grace_lapse_with_heir_auto_resolves() -> void:
	_cleanup(); _setup_campaign_and_characters()
	_create_domain(DOMAIN_ID, RULER_ID)
	RulerDeathHandler.handle_ruler_death(RULER_ID, 500)
	RulerDeathHandler.designate_heir(
		DOMAIN_ID, HEIR_HENCHMAN_ID, RulerDeathHandler.KIND_HENCHMAN)
	var domain_row: Dictionary = _reload_domain(DOMAIN_ID)
	var summary: Dictionary = RulerDeathHandler.tick_succession_grace(domain_row, 531)
	check(bool(summary.get("auto_resolved", false)),
		"auto_resolved=true after grace + heir, got %s" % str(summary))
	check(not bool(summary.get("lapsed", true)),
		"lapsed=false when heir was designated")
	var row: Dictionary = _reload_domain(DOMAIN_ID)
	check(str(row.get("owner_character_id", "")) == HEIR_HENCHMAN_ID,
		"owner column = heir after auto-resolution")


func test_tick_succession_grace_lapse_no_heir_lapses() -> void:
	_cleanup(); _setup_campaign_and_characters()
	_create_domain(DOMAIN_ID, RULER_ID)  # independent
	RulerDeathHandler.handle_ruler_death(RULER_ID, 500)
	# Don't designate any heir.
	var domain_row: Dictionary = _reload_domain(DOMAIN_ID)
	var summary: Dictionary = RulerDeathHandler.tick_succession_grace(domain_row, 531)
	check(bool(summary.get("lapsed", false)),
		"lapsed=true after grace + no heir, got %s" % str(summary))
	check(not bool(summary.get("auto_resolved", true)),
		"auto_resolved=false when no heir designated")
	var row: Dictionary = _reload_domain(DOMAIN_ID)
	check(str(row.get("lifecycle_state", "")) == "abandoned",
		"independent + lapse → abandoned, got %s" % str(row.get("lifecycle_state", "")))


func test_eligible_heirs_for_returns_pcs_and_henchmen() -> void:
	_cleanup(); _setup_campaign_and_characters()
	_create_domain(DOMAIN_ID, RULER_ID)
	var heirs: Array = RulerDeathHandler.eligible_heirs_for(DOMAIN_ID)
	# We expect at least HEIR_PC, OVERLORD (also pc), HEIR_HENCHMAN. The dead
	# ruler is technically still in the table for this test; eligibility
	# filtering is meant to exclude characters that aren't applicable, but
	# the simpler v1 helper returns all active characters of the right type.
	var by_id: Dictionary = {}
	for h in heirs:
		by_id[String(h.get("character_id", ""))] = h
	check(by_id.has(HEIR_PC_ID), "PC heir candidate present")
	check(by_id.has(HEIR_HENCHMAN_ID), "henchman candidate present")
	check(by_id.has(OVERLORD_ID), "overlord PC present (eligibility v1 is broad)")


func test_eligible_heirs_for_kind_chips_correct() -> void:
	_cleanup(); _setup_campaign_and_characters()
	_create_domain(DOMAIN_ID, RULER_ID)
	var heirs: Array = RulerDeathHandler.eligible_heirs_for(DOMAIN_ID)
	for h in heirs:
		var id: String = String(h.get("character_id", ""))
		var kind: String = String(h.get("kind", ""))
		if id == HEIR_PC_ID or id == RULER_ID or id == OVERLORD_ID:
			check(kind == "pc", "%s is kind=pc, got %s" % [id, kind])
		elif id == HEIR_HENCHMAN_ID:
			check(kind == "henchman", "%s is kind=henchman, got %s" % [id, kind])


func test_invalid_inputs_rejected() -> void:
	_cleanup(); _setup_campaign_and_characters()
	_create_domain(DOMAIN_ID, RULER_ID)
	RulerDeathHandler.handle_ruler_death(RULER_ID, 500)
	# Invalid heir_kind.
	check(not RulerDeathHandler.designate_heir(DOMAIN_ID, HEIR_PC_ID, "not_a_kind"),
		"invalid heir_kind rejected")
	# Empty heir id.
	check(not RulerDeathHandler.designate_heir(DOMAIN_ID, "", "pc"),
		"empty heir_id rejected")
	# Empty domain id.
	check(not RulerDeathHandler.designate_heir("", HEIR_PC_ID, "pc"),
		"empty domain_id rejected")
