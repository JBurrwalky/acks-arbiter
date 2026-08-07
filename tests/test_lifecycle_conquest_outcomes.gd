extends "res://tests/test_suite_base.gd"

## Phase 11D-prereq.0b: LifecycleHandler.conquer_domain tests under the
## new three-outcome taxonomy (replaces the deleted same_campaign_npc /
## foreign_realm tests from 11B's test_lifecycle_handler.gd).
##
## Coverage:
##   OCCUPIED — preserves hexes + reassigns owner; vassal cascade fires;
##              departure log records outcome + payload
##   LOOTED_LOCAL_SUCCESSION — pillage applied + ownership transfers to
##              the spawned local NPC (caller supplies it)
##   SALTED_TO_RUIN — terminal: hexes release + lifecycle_state set;
##              treasury looted; vassals cascade
##   Monthly tick continues to skip salted rows (regression on 11B's filter)

const TEST_CAMPAIGN := "test_outcomes_campaign"
const DOMAIN_ID := "test_outcomes_domain"
const VASSAL_DOMAIN_ID := "test_outcomes_vassal_domain"
# R-1 cascade-scoping fixture: a second domain under the SAME liege, with its own
# vassal, so a conquest can be shown not to touch it.
const OTHER_DOMAIN_ID := "test_outcomes_other_domain"
const OTHER_VASSAL_DOMAIN_ID := "test_outcomes_other_vassal_domain"
const OWNER_ID := "test_outcomes_owner"
const HENCHMAN_VASSAL_ID := "test_outcomes_henchman_vassal"
const ATTACKER_ID := "test_outcomes_attacker"
const LOCAL_NPC_ID := "test_outcomes_local_npc"
const STRONGHOLD_ID := "test_outcomes_stronghold"
const HEX_MAP_ID := "test_outcomes_map"


func run_all_tests() -> void:
	_cleanup()
	test_outcome_occupied_preserves_hexes_reassigns_owner()
	test_outcome_occupied_transfers_or_breaks_vassals()
	test_cascade_is_scoped_to_the_lost_domain()
	test_cascade_leaves_landless_personal_oaths_alone()
	test_outcome_occupied_logs_payload_with_outcome_and_new_owner()
	test_outcome_looted_local_succession_applies_pillage_and_reassigns()
	test_outcome_looted_requires_new_owner_id()
	test_refused_conquest_changes_nothing()
	test_outcome_salted_to_ruin_releases_hexes_and_sets_state()
	test_outcome_salted_to_ruin_loots_treasury_via_pillage()
	test_outcome_salted_domains_skipped_by_monthly_tick_filter()
	_cleanup()
	if not has_failures():
		print("LifecycleConquestOutcomes: all tests passed.")


# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

func _setup() -> void:
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[TEST_CAMPAIGN, "Outcomes Test"])
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO hex_maps (id, campaign_id, name, scale)
		VALUES (?, ?, ?, ?)
	""", [HEX_MAP_ID, TEST_CAMPAIGN, "Outcomes Test Map", "regional_6mi"])
	for cid in [OWNER_ID, HENCHMAN_VASSAL_ID, ATTACKER_ID, LOCAL_NPC_ID]:
		CampaignRepository.db.query_with_bindings("""
			INSERT OR IGNORE INTO characters
				(id, campaign_id, name, character_type, persistence_tier,
				 race, character_class, level, xp,
				 combat_progression,
				 strength, intelligence, wisdom, dexterity, constitution, charisma,
				 is_active)
			VALUES (?, ?, ?, 'pc', 'full', 'human', 'fighter', 1, 0,
			        'fighter', 10, 10, 10, 10, 10, 10, 1)
		""", [cid, TEST_CAMPAIGN, "Char " + cid])


## [param liege_domain_id] is the authoritative realm pointer (ruling R-1). A vassal
## domain MUST carry it: `LifecycleHandler._cascade_vassals` is scoped to the lost
## domain via `domains.liege_domain_id`, so a vassal_assignment whose vassal domain
## does not point at the conquered domain is — correctly — left alone.
func _create_domain(domain_id: String, owner_id: String, treasury_cp: int = 0,
		peasants: int = 100, liege_domain_id: String = "") -> void:
	CampaignRepository.db.query_with_bindings("""
		INSERT OR REPLACE INTO domains
			(id, campaign_id, name, owner_character_id, territory_type,
			 peasant_families, morale, treasury_cp,
			 established_calendar_day, lifecycle_state, liege_domain_id)
		VALUES (?, ?, ?, ?, 'wilderness', ?, 0, ?, 100, 'active', ?)
	""", [domain_id, TEST_CAMPAIGN, "Test " + domain_id, owner_id, peasants, treasury_cp,
		null if liege_domain_id.is_empty() else liege_domain_id])


func _add_hex(domain_id: String, q: int, r: int) -> void:
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO domain_hexes (id, domain_id, map_id, hex_q, hex_r, land_value)
		VALUES (?, ?, ?, ?, ?, 6)
	""", [CampaignRepository.generate_id(), domain_id, HEX_MAP_ID, q, r])


func _create_vassal_assignment(liege: String, vassal: String, vassal_domain: String) -> String:
	return VassalRepository.create_assignment({
		"campaign_id": TEST_CAMPAIGN,
		"liege_character_id": liege,
		"vassal_character_id": vassal,
		"vassal_domain_id": vassal_domain,
		"assigned_calendar_day": 100,
		"status": "active",
		"is_henchman_vassal": true,
	})


func _cleanup() -> void:
	for d in [DOMAIN_ID, VASSAL_DOMAIN_ID, OTHER_DOMAIN_ID, OTHER_VASSAL_DOMAIN_ID]:
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM domain_hexes WHERE domain_id = ?", [d])
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM domains WHERE id = ?", [d])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM strongholds WHERE id = ?", [STRONGHOLD_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM domain_departure_log WHERE campaign_id = ?", [TEST_CAMPAIGN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM vassal_assignments WHERE campaign_id = ?", [TEST_CAMPAIGN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE character_id IN (?, ?, ?, ?)",
		[OWNER_ID, HENCHMAN_VASSAL_ID, ATTACKER_ID, LOCAL_NPC_ID])
	for c in [OWNER_ID, HENCHMAN_VASSAL_ID, ATTACKER_ID, LOCAL_NPC_ID]:
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM characters WHERE id = ?", [c])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM hex_maps WHERE id = ?", [HEX_MAP_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [TEST_CAMPAIGN])


# ---------------------------------------------------------------------------
# Tests — OCCUPIED
# ---------------------------------------------------------------------------

func test_outcome_occupied_preserves_hexes_reassigns_owner() -> void:
	_cleanup(); _setup()
	_create_domain(DOMAIN_ID, OWNER_ID, 50_000, 200)
	_add_hex(DOMAIN_ID, 0, 0)
	_add_hex(DOMAIN_ID, 1, 0)
	var ok := LifecycleHandler.conquer_domain(
		DOMAIN_ID, 200,
		LifecycleHandler.OUTCOME_OCCUPIED,
		ATTACKER_ID,
		0,  # severity 0 = no pillage on clean occupy
		{})
	check(ok, "conquer_domain returned true")
	CampaignRepository.db.query_with_bindings(
		"SELECT owner_character_id, lifecycle_state, treasury_cp, peasant_families FROM domains WHERE id = ?",
		[DOMAIN_ID])
	var row: Dictionary = CampaignRepository.db.query_result[0]
	check(str(row.get("owner_character_id", "")) == ATTACKER_ID,
		"owner reassigned to attacker")
	check(str(row.get("lifecycle_state", "")) == "active",
		"lifecycle stays active for occupied")
	check(int(row.get("treasury_cp", -1)) == 50_000,
		"treasury preserved when pillage severity = 0")
	check(int(row.get("peasant_families", -1)) == 200,
		"peasants preserved when pillage severity = 0")
	var hexes: Array = CampaignRepository.get_domain_hexes(DOMAIN_ID)
	check(hexes.size() == 2, "hexes preserved, got %d" % hexes.size())


## R-5 changed what "cascade" MEANS on an occupied conquest. A sub-vassal no
## longer simply departs — he rolls loyalty against the man who took his lord's
## place, and either serves him (edge re-pointed, oath intact) or breaks away
## (revolted, and the fief leaves the realm tree). The invariant that holds
## whatever the dice say: he is no longer the PRIOR owner's vassal.
func test_outcome_occupied_transfers_or_breaks_vassals() -> void:
	_cleanup(); _setup()
	_create_domain(DOMAIN_ID, OWNER_ID)
	_create_domain(VASSAL_DOMAIN_ID, HENCHMAN_VASSAL_ID, 0, 100, DOMAIN_ID)
	var assignment_id := _create_vassal_assignment(OWNER_ID, HENCHMAN_VASSAL_ID, VASSAL_DOMAIN_ID)
	LifecycleHandler.conquer_domain(
		DOMAIN_ID, 200,
		LifecycleHandler.OUTCOME_OCCUPIED, ATTACKER_ID, 0, {})
	var post: Dictionary = VassalRepository.get_assignment(assignment_id)
	var status := String(post.get("status", ""))
	var liege := String(post.get("liege_character_id", ""))
	check(not (status == "active" and liege == OWNER_ID),
		"the sub-vassal no longer serves the lord who lost the domain (status=%s liege=%s)"
			% [status, liege])
	if status == "active":
		check(liege == ATTACKER_ID,
			"a retained sub-vassal is re-pointed to the conqueror, keeping his loyalty history")
	else:
		check(status == "revolted",
			"a sub-vassal who refuses the conqueror REVOLTS rather than quietly departing")


## R-1 companion lock. `_cascade_vassals` Case 1 was liege-WIDE BY CHARACTER: it
## departed every assignment where the prior owner was the liege, no matter which
## domain the fief was held of. That was invisible while world generation left
## `vassal_assignments` empty; once R-1 fills it, a duke who lost one frontier
## barony would have his ENTIRE realm dissolve in a single conquest.
##
## Setup: one liege holding TWO domains, with one vassal under each. Conquering the
## first must release ONLY the fief held of it.
func test_cascade_is_scoped_to_the_lost_domain() -> void:
	_cleanup(); _setup()
	var other_vassal := LOCAL_NPC_ID  # a second, distinct vassal character
	_create_domain(DOMAIN_ID, OWNER_ID)
	_create_domain(OTHER_DOMAIN_ID, OWNER_ID)
	_create_domain(VASSAL_DOMAIN_ID, HENCHMAN_VASSAL_ID, 0, 100, DOMAIN_ID)
	_create_domain(OTHER_VASSAL_DOMAIN_ID, other_vassal, 0, 100, OTHER_DOMAIN_ID)
	var lost_edge := _create_vassal_assignment(
		OWNER_ID, HENCHMAN_VASSAL_ID, VASSAL_DOMAIN_ID)
	var kept_edge := _create_vassal_assignment(
		OWNER_ID, other_vassal, OTHER_VASSAL_DOMAIN_ID)

	LifecycleHandler.conquer_domain(
		DOMAIN_ID, 200,
		LifecycleHandler.OUTCOME_OCCUPIED, ATTACKER_ID, 0, {})

	var lost: Dictionary = VassalRepository.get_assignment(lost_edge)
	check(not (String(lost.get("status", "")) == "active"
			and String(lost.get("liege_character_id", "")) == OWNER_ID),
		"the fief held OF the conquered domain leaves the prior owner (R-5 rolls it)")
	var kept: Dictionary = VassalRepository.get_assignment(kept_edge)
	check(String(kept.get("status", "")) == "active"
			and String(kept.get("liege_character_id", "")) == OWNER_ID,
		"the same liege's OTHER domain keeps its vassal, still sworn to him — the "
		+ "cascade is scoped to the lost domain, not liege-wide")


## A personal oath with no fief attached (`vassal_domain_id` NULL) is sworn to the
## RULER, not to one of his domains, so losing one domain must not dissolve it.
func test_cascade_leaves_landless_personal_oaths_alone() -> void:
	_cleanup(); _setup()
	_create_domain(DOMAIN_ID, OWNER_ID)
	var landless := VassalRepository.create_assignment({
		"campaign_id": TEST_CAMPAIGN,
		"liege_character_id": OWNER_ID,
		"vassal_character_id": HENCHMAN_VASSAL_ID,
		"vassal_domain_id": "",
		"assigned_calendar_day": 100,
		"status": "active",
		"is_henchman_vassal": true,
	})
	LifecycleHandler.conquer_domain(
		DOMAIN_ID, 200,
		LifecycleHandler.OUTCOME_OCCUPIED, ATTACKER_ID, 0, {})
	check(String(VassalRepository.get_assignment(landless).get("status", "")) == "active",
		"a landless personal oath survives the loss of one of the lord's domains")


func test_outcome_occupied_logs_payload_with_outcome_and_new_owner() -> void:
	_cleanup(); _setup()
	_create_domain(DOMAIN_ID, OWNER_ID)
	LifecycleHandler.conquer_domain(
		DOMAIN_ID, 200,
		LifecycleHandler.OUTCOME_OCCUPIED, ATTACKER_ID, 0, {})
	var rows: Array = DepartureLogRecorder.list_for_domain(DOMAIN_ID)
	var conquered_row: Dictionary = {}
	for r in rows:
		if String(r.get("event_type", "")) == "conquered":
			conquered_row = r
			break
	check(not conquered_row.is_empty(), "conquered log entry exists")
	var details: Dictionary = conquered_row.get("full_details", {})
	check(String(details.get("outcome", "")) == "occupied",
		"detail.outcome = occupied, got %s" % String(details.get("outcome", "")))
	check(String(details.get("new_owner_id", "")) == ATTACKER_ID,
		"detail.new_owner_id = attacker")
	check(int(details.get("pillage_severity", -1)) == 0,
		"detail.pillage_severity = 0")


# ---------------------------------------------------------------------------
# Tests — LOOTED_LOCAL_SUCCESSION
# ---------------------------------------------------------------------------

func test_outcome_looted_local_succession_applies_pillage_and_reassigns() -> void:
	_cleanup(); _setup()
	_create_domain(DOMAIN_ID, OWNER_ID, 10_000, 100)
	_add_hex(DOMAIN_ID, 0, 0)
	var ok := LifecycleHandler.conquer_domain(
		DOMAIN_ID, 200,
		LifecycleHandler.OUTCOME_LOOTED_LOCAL_SUCCESSION,
		LOCAL_NPC_ID,
		1,  # severity 1 = light pillage
		{})
	check(ok, "conquer_domain returned true")
	CampaignRepository.db.query_with_bindings(
		"SELECT owner_character_id, lifecycle_state, treasury_cp, peasant_families FROM domains WHERE id = ?",
		[DOMAIN_ID])
	var row: Dictionary = CampaignRepository.db.query_result[0]
	check(str(row.get("owner_character_id", "")) == LOCAL_NPC_ID,
		"owner reassigned to local NPC")
	check(str(row.get("lifecycle_state", "")) == "active",
		"lifecycle stays active for looted")
	check(int(row.get("treasury_cp", -1)) == 0,
		"treasury looted to 0")
	check(int(row.get("peasant_families", -1)) == 90,
		"peasants × 0.9 = 90 (light pillage), got %d" % int(row.get("peasant_families", -1)))
	var hexes: Array = CampaignRepository.get_domain_hexes(DOMAIN_ID)
	check(hexes.size() == 1, "hex preserved")


func test_outcome_looted_requires_new_owner_id() -> void:
	_cleanup(); _setup()
	_create_domain(DOMAIN_ID, OWNER_ID)
	var ok := LifecycleHandler.conquer_domain(
		DOMAIN_ID, 200,
		LifecycleHandler.OUTCOME_LOOTED_LOCAL_SUCCESSION,
		"",  # missing new_owner_id should fail
		1,
		{})
	check(not ok, "LOOTED_LOCAL_SUCCESSION without new_owner_id rejected")


## 2026-07-31 regression lock: `conquer_domain` is ALL-OR-NOTHING. Until the
## Tier-0 validation reorder, `apply_pillage` and `_cascade_vassals` ran BEFORE
## the outcome-specific checks, so a refused conquest left the domain in place
## but pillaged and with every vassal edge marked 'departed' — the realm was
## destroyed by a conquest that never happened. See
## docs/domain-acquisition-audit-2026-07-28.md `refused-conquest-corrupts-vassal-state`.
func test_refused_conquest_changes_nothing() -> void:
	_cleanup(); _setup()
	_create_domain(DOMAIN_ID, OWNER_ID, 50_000, 200)
	# The vassal domain is held OF the conquered domain, so this edge WOULD
	# cascade if the validation gate failed to refuse — without the liege pointer
	# the assertion below would pass vacuously under the R-1 scoped cascade.
	_create_domain(VASSAL_DOMAIN_ID, HENCHMAN_VASSAL_ID, 0, 100, DOMAIN_ID)
	_add_hex(DOMAIN_ID, 0, 0)
	var assignment_id := _create_vassal_assignment(
		OWNER_ID, HENCHMAN_VASSAL_ID, VASSAL_DOMAIN_ID)

	# Refuse via the missing-new_owner_id gate, with a pillage severity that
	# WOULD loot the treasury and cull the population if it were applied.
	var ok := LifecycleHandler.conquer_domain(
		DOMAIN_ID, 200,
		LifecycleHandler.OUTCOME_LOOTED_LOCAL_SUCCESSION, "", 2, {})
	check(not ok, "refused conquest returns false")

	# Nothing may have moved.
	var post: Dictionary = VassalRepository.get_assignment(assignment_id)
	check(String(post.get("status", "")) == "active",
		"refused conquest leaves the vassal edge ACTIVE, got '%s'" % String(post.get("status", "")))
	CampaignRepository.db.query_with_bindings(
		"SELECT owner_character_id, treasury_cp, peasant_families FROM domains WHERE id = ?",
		[DOMAIN_ID])
	var row: Dictionary = CampaignRepository.db.query_result[0]
	check(str_field(row, "owner_character_id") == OWNER_ID,
		"refused conquest leaves the prior owner in place")
	check(int(row.get("treasury_cp", -1)) == 50_000,
		"refused conquest does not loot the treasury, got %d" % int(row.get("treasury_cp", -1)))
	check(int(row.get("peasant_families", -1)) == 200,
		"refused conquest does not cull the population, got %d" % int(row.get("peasant_families", -1)))
	check(CampaignRepository.get_domain_hexes(DOMAIN_ID).size() == 1,
		"refused conquest does not release hexes")


# ---------------------------------------------------------------------------
# Tests — SALTED_TO_RUIN
# ---------------------------------------------------------------------------

func test_outcome_salted_to_ruin_releases_hexes_and_sets_state() -> void:
	_cleanup(); _setup()
	_create_domain(DOMAIN_ID, OWNER_ID, 5000, 100)
	_add_hex(DOMAIN_ID, 0, 0)
	_add_hex(DOMAIN_ID, 1, 0)
	_add_hex(DOMAIN_ID, 2, 0)
	LifecycleHandler.conquer_domain(
		DOMAIN_ID, 200,
		LifecycleHandler.OUTCOME_SALTED_TO_RUIN,
		"",  # no new owner for terminal outcome
		2,
		{})
	CampaignRepository.db.query_with_bindings(
		"SELECT lifecycle_state FROM domains WHERE id = ?", [DOMAIN_ID])
	check(String(CampaignRepository.db.query_result[0].get("lifecycle_state", "")) == "salted_to_ruin",
		"lifecycle_state = salted_to_ruin (renamed from lost_to_foreign in migration 125)")
	var hexes: Array = CampaignRepository.get_domain_hexes(DOMAIN_ID)
	check(hexes.is_empty(), "hexes released, got %d" % hexes.size())


func test_outcome_salted_to_ruin_loots_treasury_via_pillage() -> void:
	_cleanup(); _setup()
	_create_domain(DOMAIN_ID, OWNER_ID, 7777, 100)
	LifecycleHandler.conquer_domain(
		DOMAIN_ID, 200,
		LifecycleHandler.OUTCOME_SALTED_TO_RUIN, "", 2, {})
	CampaignRepository.db.query_with_bindings(
		"SELECT treasury_cp FROM domains WHERE id = ?", [DOMAIN_ID])
	check(int(CampaignRepository.db.query_result[0].get("treasury_cp", -1)) == 0,
		"salt-the-earth: treasury looted to 0 via apply_pillage(severity=2)")
	# Verify the pillage_result is in the log payload.
	var rows: Array = DepartureLogRecorder.list_for_domain(DOMAIN_ID)
	for r in rows:
		if String(r.get("event_type", "")) == "conquered":
			var details: Dictionary = r.get("full_details", {})
			var pillage: Dictionary = details.get("pillage_result", {})
			check(int(pillage.get("looted_cp", -1)) == 7777,
				"log pillage_result records looted_cp=7777")
			return
	check(false, "no conquered log entry found")


func test_outcome_salted_domains_skipped_by_monthly_tick_filter() -> void:
	# Regression check for the 11B filter in DomainHandlers._handle_monthly_tick
	# after the lost_to_foreign → salted_to_ruin rename. Salted-to-ruin domains
	# must continue to be skipped (the tick body explicitly checks both
	# STATE_ABANDONED and STATE_SALTED_TO_RUIN).
	_cleanup(); _setup()
	_create_domain(DOMAIN_ID, OWNER_ID)
	LifecycleHandler.conquer_domain(
		DOMAIN_ID, 200,
		LifecycleHandler.OUTCOME_SALTED_TO_RUIN, "", 2, {})
	# Reload the domain.
	CampaignRepository.db.query_with_bindings(
		"SELECT * FROM domains WHERE id = ?", [DOMAIN_ID])
	var domain_data: Dictionary = CampaignRepository.db.query_result[0]
	# The monthly tick's filter is a string compare against the two terminal
	# states; we exercise that compare directly.
	var state: String = String(domain_data.get("lifecycle_state", ""))
	var should_skip: bool = (
		state == LifecycleHandler.STATE_ABANDONED
		or state == LifecycleHandler.STATE_SALTED_TO_RUIN)
	check(should_skip, "salted_to_ruin satisfies the monthly-tick skip filter")
