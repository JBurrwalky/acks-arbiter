extends "res://tests/test_suite_base.gd"

## Phase 11B: LifecycleHandler tests covering all six public methods +
## the monthly-tick skip-filter behaviour.
##
## Each test sets up an isolated TEST_CAMPAIGN + a fresh domain + (where
## relevant) supporting vassals / treasury / characters.

const TEST_CAMPAIGN := "test_lifecycle_campaign"
const DOMAIN_ID := "test_lifecycle_domain"
const OWNER_ID := "test_lifecycle_owner"
const HENCHMAN_VASSAL_ID := "test_lifecycle_vassal"
const VASSAL_DOMAIN_ID := "test_lifecycle_vassal_domain"
const CONQUEROR_NPC_ID := "test_lifecycle_npc_conqueror"
const STRONGHOLD_ID := "test_lifecycle_stronghold"
const HEX_MAP_ID := "test_lifecycle_map"


func run_all_tests() -> void:
	_cleanup()
	_setup_campaign_and_owner()
	test_record_establishment_writes_log_entry()
	# Phase 11D-prereq.0b: conquest tests moved to test_lifecycle_conquest_outcomes.gd
	# now that conquer_domain uses the three-outcome taxonomy with pillage_severity.
	test_voluntary_abandon_liquidates_treasury_to_ruler()
	test_voluntary_abandon_releases_hexes_and_cascades_vassals()
	test_stronghold_collapse_sets_ruined_state_and_grace()
	test_stronghold_collapse_idempotent_does_not_extend_grace()
	test_restore_from_ruin_returns_to_active()
	test_tick_lifecycle_state_grace_lapse_auto_abandons()
	test_tick_lifecycle_state_active_no_op()
	test_invalid_inputs_rejected()
	_cleanup()
	if not has_failures():
		print("LifecycleHandler: all tests passed.")


# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

func _setup_campaign_and_owner() -> void:
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[TEST_CAMPAIGN, "Lifecycle Test"])
	# Bare-minimum character rows. The owner gets enough columns to insert
	# successfully; we don't drive class logic in this suite.
	_insert_character(OWNER_ID, "Lifecycle Owner")
	_insert_character(HENCHMAN_VASSAL_ID, "Lifecycle Vassal")
	_insert_character(CONQUEROR_NPC_ID, "NPC Conqueror")
	# Test hex map for hex-release verification.
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO hex_maps (id, campaign_id, name, scale)
		VALUES (?, ?, ?, ?)
	""", [HEX_MAP_ID, TEST_CAMPAIGN, "Lifecycle Test Map", "regional_6mi"])


func _insert_character(id: String, name: String) -> void:
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_type, persistence_tier,
			 race, character_class, level, xp,
			 combat_progression,
			 strength, intelligence, wisdom, dexterity, constitution, charisma)
		VALUES (?, ?, ?, 'pc', 'full', 'human', 'fighter', 1, 0,
		        'fighter', 10, 10, 10, 10, 10, 10)
	""", [id, TEST_CAMPAIGN, name])


func _create_domain(domain_id: String, owner_id: String, treasury_cp: int = 0) -> void:
	CampaignRepository.db.query_with_bindings("""
		INSERT OR REPLACE INTO domains
			(id, campaign_id, name, owner_character_id, territory_type,
			 peasant_families, morale, treasury_cp,
			 established_calendar_day, lifecycle_state)
		VALUES (?, ?, ?, ?, 'wilderness', 100, 0, ?, 100, 'active')
	""", [domain_id, TEST_CAMPAIGN, "Test Domain " + domain_id, owner_id, treasury_cp])


func _add_hex(domain_id: String, q: int, r: int) -> void:
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO domain_hexes (id, domain_id, map_id, hex_q, hex_r, land_value)
		VALUES (?, ?, ?, ?, ?, 6)
	""", [CampaignRepository.generate_id(), domain_id, HEX_MAP_ID, q, r])


func _create_vassal_assignment(liege_id: String, vassal_id: String, vassal_domain_id: String) -> String:
	return VassalRepository.create_assignment({
		"campaign_id": TEST_CAMPAIGN,
		"liege_character_id": liege_id,
		"vassal_character_id": vassal_id,
		"vassal_domain_id": vassal_domain_id,
		"assigned_calendar_day": 100,
		"status": "active",
		"is_henchman_vassal": true,
	})


func _cleanup() -> void:
	for d in [DOMAIN_ID, VASSAL_DOMAIN_ID]:
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM domain_hexes WHERE domain_id = ?", [d])
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM domains WHERE id = ?", [d])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM domain_departure_log WHERE campaign_id = ?", [TEST_CAMPAIGN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM vassal_assignments WHERE campaign_id = ?", [TEST_CAMPAIGN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE character_id IN (?, ?, ?)",
		[OWNER_ID, HENCHMAN_VASSAL_ID, CONQUEROR_NPC_ID])
	for c in [OWNER_ID, HENCHMAN_VASSAL_ID, CONQUEROR_NPC_ID]:
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM characters WHERE id = ?", [c])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM hex_maps WHERE id = ?", [HEX_MAP_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [TEST_CAMPAIGN])


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_record_establishment_writes_log_entry() -> void:
	_create_domain(DOMAIN_ID, OWNER_ID)
	var ok := LifecycleHandler.record_establishment(
		TEST_CAMPAIGN, DOMAIN_ID, 100, "grant", OWNER_ID)
	check(ok, "record_establishment returned true")
	var rows: Array = DepartureLogRecorder.list_for_domain(DOMAIN_ID)
	check(rows.size() == 1, "one departure-log row written, got %d" % rows.size())
	check(String(rows[0].get("event_type", "")) == "established",
		"event_type=established, got %s" % String(rows[0].get("event_type", "")))
	var details: Dictionary = rows[0].get("full_details", {})
	check(String(details.get("method", "")) == "grant",
		"detail.method=grant, got %s" % String(details.get("method", "")))


func test_voluntary_abandon_liquidates_treasury_to_ruler() -> void:
	_cleanup(); _setup_campaign_and_owner()
	_create_domain(DOMAIN_ID, OWNER_ID, 12_345)  # cp
	# Owner starts with 0 coins (no initial inventory rows).
	LifecycleHandler.abandon_domain(
		DOMAIN_ID, 400,
		LifecycleHandler.REASON_VOLUNTARY,
		OWNER_ID)
	# Treasury zeroed.
	check(CampaignRepository.get_domain_treasury_cp(DOMAIN_ID) == 0,
		"treasury zeroed after voluntary abandon")
	# Owner's coin total equals the liquidated amount.
	var wealth_cp: int = CampaignRepository.get_character_wealth_cp(OWNER_ID)
	check(wealth_cp == 12_345,
		"owner's wealth = liquidated cp (12,345), got %d" % wealth_cp)
	# State terminal.
	if not CampaignRepository.db.query_with_bindings(
		"SELECT lifecycle_state FROM domains WHERE id = ?", [DOMAIN_ID]):
		check(false, "could not read domain row")
		return
	check(String(CampaignRepository.db.query_result[0].get("lifecycle_state", "")) == "abandoned",
		"lifecycle_state=abandoned")


func test_voluntary_abandon_releases_hexes_and_cascades_vassals() -> void:
	_cleanup(); _setup_campaign_and_owner()
	_create_domain(DOMAIN_ID, OWNER_ID, 0)
	_create_domain(VASSAL_DOMAIN_ID, HENCHMAN_VASSAL_ID, 0)
	_add_hex(DOMAIN_ID, 0, 0)
	_add_hex(DOMAIN_ID, 1, 0)
	var assignment_id := _create_vassal_assignment(OWNER_ID, HENCHMAN_VASSAL_ID, VASSAL_DOMAIN_ID)
	LifecycleHandler.abandon_domain(
		DOMAIN_ID, 400,
		LifecycleHandler.REASON_VOLUNTARY,
		OWNER_ID)
	var hexes: Array = CampaignRepository.get_domain_hexes(DOMAIN_ID)
	check(hexes.is_empty(), "hexes released, got %d" % hexes.size())
	var post: Dictionary = VassalRepository.get_assignment(assignment_id)
	check(String(post.get("status", "")) == "departed",
		"vassal cascade fired on voluntary abandon, status=%s" % String(post.get("status", "")))


func test_stronghold_collapse_sets_ruined_state_and_grace() -> void:
	_cleanup(); _setup_campaign_and_owner()
	_create_domain(DOMAIN_ID, OWNER_ID, 0)
	LifecycleHandler.mark_stronghold_collapsed(DOMAIN_ID, STRONGHOLD_ID, 500)
	if not CampaignRepository.db.query_with_bindings(
		"SELECT lifecycle_state, ruined_stronghold_grace_until_day FROM domains WHERE id = ?",
		[DOMAIN_ID]):
		check(false, "could not read domain row")
		return
	var row: Dictionary = CampaignRepository.db.query_result[0]
	check(str(row.get("lifecycle_state", "")) == "ruined_stronghold",
		"state=ruined_stronghold")
	check(int(row.get("ruined_stronghold_grace_until_day", 0)) == 530,
		"grace_until = 500 + 30 = 530, got %d" % int(row.get("ruined_stronghold_grace_until_day", 0)))


func test_stronghold_collapse_idempotent_does_not_extend_grace() -> void:
	_cleanup(); _setup_campaign_and_owner()
	_create_domain(DOMAIN_ID, OWNER_ID, 0)
	LifecycleHandler.mark_stronghold_collapsed(DOMAIN_ID, STRONGHOLD_ID, 500)
	# Second call later in the grace window: should NOT extend.
	LifecycleHandler.mark_stronghold_collapsed(DOMAIN_ID, "other_stronghold", 520)
	if not CampaignRepository.db.query_with_bindings(
		"SELECT ruined_stronghold_grace_until_day FROM domains WHERE id = ?",
		[DOMAIN_ID]):
		check(false, "could not read domain row")
		return
	check(int(CampaignRepository.db.query_result[0].get("ruined_stronghold_grace_until_day", 0)) == 530,
		"grace unchanged on re-entry, got %d" % int(CampaignRepository.db.query_result[0].get("ruined_stronghold_grace_until_day", 0)))


func test_restore_from_ruin_returns_to_active() -> void:
	_cleanup(); _setup_campaign_and_owner()
	_create_domain(DOMAIN_ID, OWNER_ID, 0)
	LifecycleHandler.mark_stronghold_collapsed(DOMAIN_ID, STRONGHOLD_ID, 500)
	LifecycleHandler.restore_from_ruin(DOMAIN_ID, STRONGHOLD_ID, 510)
	if not CampaignRepository.db.query_with_bindings(
		"SELECT lifecycle_state FROM domains WHERE id = ?", [DOMAIN_ID]):
		check(false, "could not read domain row")
		return
	check(String(CampaignRepository.db.query_result[0].get("lifecycle_state", "")) == "active",
		"restore returns state to active")
	# Departure log carries both stronghold_lost AND restored entries.
	var rows: Array = DepartureLogRecorder.list_for_domain(DOMAIN_ID)
	var has_collapsed: bool = false
	var has_restored: bool = false
	for r in rows:
		var et: String = String(r.get("event_type", ""))
		if et == "stronghold_lost": has_collapsed = true
		if et == "restored": has_restored = true
	check(has_collapsed and has_restored,
		"both stronghold_lost and restored log entries present (collapsed=%s restored=%s)" % [
			has_collapsed, has_restored])


func test_tick_lifecycle_state_grace_lapse_auto_abandons() -> void:
	_cleanup(); _setup_campaign_and_owner()
	_create_domain(DOMAIN_ID, OWNER_ID, 100)  # 100 cp; should be FORFEIT on auto-abandon
	LifecycleHandler.mark_stronghold_collapsed(DOMAIN_ID, STRONGHOLD_ID, 500)
	# Reload the row to get the new lifecycle columns.
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM domains WHERE id = ?", [DOMAIN_ID]):
		check(false, "could not read domain row")
		return
	var domain_data: Dictionary = CampaignRepository.db.query_result[0]
	# Tick on day 531 — past the grace day (500 + 30 = 530).
	var summary: Dictionary = LifecycleHandler.tick_lifecycle_state(domain_data, 531)
	check(bool(summary.get("auto_abandoned", false)),
		"auto_abandoned=true after grace, got %s" % str(summary.get("auto_abandoned", false)))
	check(String(summary.get("reason", "")) == "stronghold_collapsed",
		"reason=stronghold_collapsed")
	# Treasury forfeit (no liquidate_to passed).
	check(CampaignRepository.get_domain_treasury_cp(DOMAIN_ID) == 0,
		"treasury forfeit on grace lapse, got %d" % CampaignRepository.get_domain_treasury_cp(DOMAIN_ID))
	# Owner did NOT receive cp.
	check(CampaignRepository.get_character_wealth_cp(OWNER_ID) == 0,
		"owner did not receive liquidation (no_liquidate path)")


func test_tick_lifecycle_state_active_no_op() -> void:
	_cleanup(); _setup_campaign_and_owner()
	_create_domain(DOMAIN_ID, OWNER_ID, 0)
	# Active domain on any calendar day — tick should be a no-op.
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM domains WHERE id = ?", [DOMAIN_ID]):
		check(false, "could not read domain row")
		return
	var domain_data: Dictionary = CampaignRepository.db.query_result[0]
	var summary: Dictionary = LifecycleHandler.tick_lifecycle_state(domain_data, 9999)
	check(not bool(summary.get("auto_abandoned", true)),
		"active domain tick is a no-op")


func test_invalid_inputs_rejected() -> void:
	_cleanup(); _setup_campaign_and_owner()
	_create_domain(DOMAIN_ID, OWNER_ID, 0)
	# Bad outcome.
	var ok1 := LifecycleHandler.conquer_domain(
		DOMAIN_ID, 200, "not_a_real_outcome", CONQUEROR_NPC_ID, 0, {})
	check(not ok1, "invalid outcome rejected")
	# Bad abandon reason.
	var ok2 := LifecycleHandler.abandon_domain(
		DOMAIN_ID, 200, "not_a_real_reason", OWNER_ID)
	check(not ok2, "invalid abandon reason rejected")
	# Unknown domain id.
	var ok3 := LifecycleHandler.conquer_domain(
		"nonexistent_domain", 200,
		LifecycleHandler.OUTCOME_OCCUPIED, CONQUEROR_NPC_ID, 0, {})
	check(not ok3, "unknown domain id rejected")
