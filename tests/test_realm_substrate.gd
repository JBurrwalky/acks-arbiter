extends "res://tests/test_suite_base.gd"

## Phase 11D-prereq.0a: RealmRepository tests covering CRUD, lookups (with
## cache hit + apex-walk fallback), relations (canonical pair ordering +
## six-band disposition), and the conquest-outcome resolver (three-outcome
## taxonomy per the 2026-05-20 revision).

const TEST_CAMPAIGN := "test_realm_campaign"
const OTHER_CAMPAIGN := "test_realm_other_campaign"
const APEX_DOMAIN := "test_realm_apex_domain"
const VASSAL_DOMAIN := "test_realm_vassal_domain"
const APEX_OWNER := "test_realm_apex_owner"
const VASSAL_OWNER := "test_realm_vassal_owner"
const ATTACKER_TRACKED := "test_realm_attacker_tracked"
const ATTACKER_FOREIGN := "test_realm_attacker_foreign"
const REALM_A := "test_realm_a"
const REALM_B := "test_realm_b"
const REALM_FOREIGN := "test_realm_foreign"


func run_all_tests() -> void:
	_cleanup()
	test_create_realm_roundtrip()
	test_create_realm_rejects_invalid_kind_and_missing_campaign()
	test_get_realm_for_character_returns_realm()
	test_get_realm_for_domain_uses_cached_realm_id()
	test_get_realm_for_domain_walks_apex_when_cache_null()
	test_relation_default_is_neutral()
	test_relation_self_is_allied()
	test_relation_canonical_pair_ordering()
	test_set_relation_rejects_invalid_disposition()
	test_set_relation_rejects_cross_campaign_pair()
	test_resolve_conquest_outcome_salt_the_earth()
	test_resolve_conquest_outcome_loot_and_scoot()
	test_resolve_conquest_outcome_tracked_attacker_occupy()
	test_resolve_conquest_outcome_off_map_attacker_occupy()
	test_resolve_conquest_outcome_rejects_invalid_intent()
	_cleanup()
	if not has_failures():
		print("RealmSubstrate: all tests passed.")


# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

func _setup_campaigns() -> void:
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[TEST_CAMPAIGN, "Realm Substrate Test"])
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[OTHER_CAMPAIGN, "Realm Substrate Test — Other"])


func _insert_character(id: String, name: String, campaign_id: String = TEST_CAMPAIGN) -> void:
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_type, persistence_tier,
			 race, character_class, level, xp,
			 combat_progression,
			 strength, intelligence, wisdom, dexterity, constitution, charisma,
			 is_active)
		VALUES (?, ?, ?, 'pc', 'full', 'human', 'fighter', 5, 0,
		        'fighter', 10, 10, 10, 10, 10, 10, 1)
	""", [id, campaign_id, name])


func _create_domain(
	domain_id: String,
	owner_id: String,
	liege_domain_id: String = "",
	realm_id: String = "",
) -> void:
	var liege_v: Variant = null
	if not liege_domain_id.is_empty():
		liege_v = liege_domain_id
	var realm_v: Variant = null
	if not realm_id.is_empty():
		realm_v = realm_id
	CampaignRepository.db.query_with_bindings("""
		INSERT OR REPLACE INTO domains
			(id, campaign_id, name, owner_character_id, territory_type,
			 peasant_families, morale, treasury_cp,
			 established_calendar_day, lifecycle_state,
			 liege_domain_id, realm_id)
		VALUES (?, ?, ?, ?, 'wilderness', 100, 0, 0, 100, 'active', ?, ?)
	""", [domain_id, TEST_CAMPAIGN, "Test Domain " + domain_id, owner_id, liege_v, realm_v])


func _cleanup() -> void:
	for d in [APEX_DOMAIN, VASSAL_DOMAIN]:
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM domain_hexes WHERE domain_id = ?", [d])
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM domains WHERE id = ?", [d])
	for r in [REALM_A, REALM_B, REALM_FOREIGN]:
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM realm_relations WHERE realm_a_id = ? OR realm_b_id = ?", [r, r])
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM realms WHERE id = ?", [r])
	for c in [APEX_OWNER, VASSAL_OWNER, ATTACKER_TRACKED, ATTACKER_FOREIGN]:
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM characters WHERE id = ?", [c])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [TEST_CAMPAIGN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [OTHER_CAMPAIGN])


# ---------------------------------------------------------------------------
# Tests — Realm CRUD
# ---------------------------------------------------------------------------

func test_create_realm_roundtrip() -> void:
	_cleanup(); _setup_campaigns()
	_insert_character(APEX_OWNER, "Apex Owner")
	var id := RealmRepository.create_realm({
		"id": REALM_A,
		"campaign_id": TEST_CAMPAIGN,
		"name": "Test Realm A",
		"head_character_id": APEX_OWNER,
		"alignment": "lawful",
		"dominant_religion": "Sun-cult",
		"culture": "auran",
		"realm_kind": RealmRepository.KIND_TRACKED,
	})
	check(id == REALM_A, "create returned id, got %s" % id)
	var realm: Dictionary = RealmRepository.get_realm(REALM_A)
	check(not realm.is_empty(), "realm row exists")
	check(String(realm.get("name", "")) == "Test Realm A", "name roundtripped")
	check(String(realm.get("head_character_id", "")) == APEX_OWNER, "head roundtripped")
	check(String(realm.get("alignment", "")) == "lawful", "alignment roundtripped")
	check(String(realm.get("realm_kind", "")) == "tracked", "realm_kind roundtripped")


func test_create_realm_rejects_invalid_kind_and_missing_campaign() -> void:
	_cleanup(); _setup_campaigns()
	# Invalid kind.
	var bad_kind := RealmRepository.create_realm({
		"campaign_id": TEST_CAMPAIGN,
		"realm_kind": "not_a_kind",
	})
	check(bad_kind.is_empty(), "invalid realm_kind rejected")
	# Missing campaign.
	var no_campaign := RealmRepository.create_realm({
		"name": "Orphan",
	})
	check(no_campaign.is_empty(), "missing campaign_id rejected")


func test_get_realm_for_character_returns_realm() -> void:
	_cleanup(); _setup_campaigns()
	_insert_character(APEX_OWNER, "Apex Owner")
	RealmRepository.create_realm({
		"id": REALM_A, "campaign_id": TEST_CAMPAIGN,
		"name": "Realm A", "head_character_id": APEX_OWNER,
		"realm_kind": "tracked",
	})
	var realm: Dictionary = RealmRepository.get_realm_for_character(APEX_OWNER)
	check(String(realm.get("id", "")) == REALM_A,
		"get_realm_for_character returns the right realm, got %s" % String(realm.get("id", "")))


# ---------------------------------------------------------------------------
# Tests — Domain -> realm lookup with cache hit + apex-walk fallback
# ---------------------------------------------------------------------------

func test_get_realm_for_domain_uses_cached_realm_id() -> void:
	_cleanup(); _setup_campaigns()
	_insert_character(APEX_OWNER, "Apex Owner")
	RealmRepository.create_realm({
		"id": REALM_A, "campaign_id": TEST_CAMPAIGN,
		"name": "Realm A", "head_character_id": APEX_OWNER,
		"realm_kind": "tracked",
	})
	# Domain with cached realm_id set.
	_create_domain(APEX_DOMAIN, APEX_OWNER, "", REALM_A)
	var realm: Dictionary = RealmRepository.get_realm_for_domain(APEX_DOMAIN)
	check(String(realm.get("id", "")) == REALM_A,
		"cached realm_id resolves directly, got %s" % String(realm.get("id", "")))


func test_get_realm_for_domain_walks_apex_when_cache_null() -> void:
	_cleanup(); _setup_campaigns()
	_insert_character(APEX_OWNER, "Apex Owner")
	_insert_character(VASSAL_OWNER, "Vassal Owner")
	RealmRepository.create_realm({
		"id": REALM_A, "campaign_id": TEST_CAMPAIGN,
		"name": "Realm A", "head_character_id": APEX_OWNER,
		"realm_kind": "tracked",
	})
	# Apex has the cache; vassal has NULL realm_id and falls back via
	# RealmGraph to walk up to the apex, then look up the realm via the
	# apex's owner's head_character_id.
	_create_domain(APEX_DOMAIN, APEX_OWNER, "", REALM_A)
	_create_domain(VASSAL_DOMAIN, VASSAL_OWNER, APEX_DOMAIN, "")
	# Verify the cache is actually null on the vassal row.
	CampaignRepository.db.query_with_bindings(
		"SELECT realm_id FROM domains WHERE id = ?", [VASSAL_DOMAIN])
	var cache_v: Variant = CampaignRepository.db.query_result[0].get("realm_id", null)
	check(cache_v == null or String(cache_v).is_empty(),
		"vassal's realm_id cache is null (precondition)")
	# Lookup should still resolve via apex walk.
	var realm: Dictionary = RealmRepository.get_realm_for_domain(VASSAL_DOMAIN)
	check(String(realm.get("id", "")) == REALM_A,
		"apex-walk fallback resolves realm, got %s" % String(realm.get("id", "")))


# ---------------------------------------------------------------------------
# Tests — Realm relations
# ---------------------------------------------------------------------------

func _create_pair_of_realms() -> void:
	_insert_character(APEX_OWNER, "Apex Owner")
	_insert_character(VASSAL_OWNER, "Vassal Owner")
	RealmRepository.create_realm({
		"id": REALM_A, "campaign_id": TEST_CAMPAIGN,
		"name": "Realm A", "head_character_id": APEX_OWNER,
		"realm_kind": "tracked",
	})
	RealmRepository.create_realm({
		"id": REALM_B, "campaign_id": TEST_CAMPAIGN,
		"name": "Realm B", "head_character_id": VASSAL_OWNER,
		"realm_kind": "tracked",
	})


func test_relation_default_is_neutral() -> void:
	_cleanup(); _setup_campaigns()
	_create_pair_of_realms()
	var disp: String = RealmRepository.get_relation(REALM_A, REALM_B)
	check(disp == "neutral",
		"default disposition is neutral, got %s" % disp)


func test_relation_self_is_allied() -> void:
	_cleanup(); _setup_campaigns()
	_create_pair_of_realms()
	var disp: String = RealmRepository.get_relation(REALM_A, REALM_A)
	check(disp == "allied",
		"realm vs. self is allied, got %s" % disp)


func test_relation_canonical_pair_ordering() -> void:
	_cleanup(); _setup_campaigns()
	_create_pair_of_realms()
	# Set (A, B); read (B, A); should return the same disposition.
	RealmRepository.set_relation(REALM_A, REALM_B, "friendly", 100)
	var disp_ab: String = RealmRepository.get_relation(REALM_A, REALM_B)
	var disp_ba: String = RealmRepository.get_relation(REALM_B, REALM_A)
	check(disp_ab == "friendly", "(A,B) reads friendly, got %s" % disp_ab)
	check(disp_ba == "friendly", "(B,A) reads same row, got %s" % disp_ba)
	# Set (B, A) to a different value; (A, B) should reflect.
	RealmRepository.set_relation(REALM_B, REALM_A, "hostile", 110)
	check(RealmRepository.get_relation(REALM_A, REALM_B) == "hostile",
		"set (B,A) updates the same row, (A,B) reads hostile")
	# Confirm only ONE row exists in the table.
	CampaignRepository.db.query_with_bindings(
		"SELECT COUNT(*) AS n FROM realm_relations WHERE realm_a_id IN (?, ?) OR realm_b_id IN (?, ?)",
		[REALM_A, REALM_B, REALM_A, REALM_B])
	var n: int = int(CampaignRepository.db.query_result[0].get("n", 0))
	check(n == 1, "exactly one realm_relations row exists for the pair, got %d" % n)


func test_set_relation_rejects_invalid_disposition() -> void:
	_cleanup(); _setup_campaigns()
	_create_pair_of_realms()
	var ok := RealmRepository.set_relation(REALM_A, REALM_B, "not_a_disp", 100)
	check(not ok, "invalid disposition rejected")


func test_set_relation_rejects_cross_campaign_pair() -> void:
	_cleanup(); _setup_campaigns()
	_create_pair_of_realms()
	# Create a realm in OTHER_CAMPAIGN.
	_insert_character(ATTACKER_TRACKED, "Other Realm Head", OTHER_CAMPAIGN)
	RealmRepository.create_realm({
		"id": REALM_FOREIGN, "campaign_id": OTHER_CAMPAIGN,
		"name": "Other Campaign Realm", "head_character_id": ATTACKER_TRACKED,
		"realm_kind": "tracked",
	})
	var ok := RealmRepository.set_relation(REALM_A, REALM_FOREIGN, "friendly", 100)
	check(not ok, "cross-campaign pair rejected")


# ---------------------------------------------------------------------------
# Tests — Conquest-outcome resolver
# ---------------------------------------------------------------------------

func test_resolve_conquest_outcome_salt_the_earth() -> void:
	_cleanup(); _setup_campaigns()
	_create_pair_of_realms()
	_create_domain(APEX_DOMAIN, APEX_OWNER, "", REALM_A)
	var result: Dictionary = RealmRepository.resolve_conquest_outcome(
		APEX_DOMAIN, VASSAL_OWNER, RealmRepository.INTENT_SALT_THE_EARTH)
	check(String(result.get("outcome", "")) == "salted_to_ruin",
		"outcome=salted_to_ruin, got %s" % String(result.get("outcome", "")))
	check(int(result.get("pillage_severity", 0)) == 2,
		"pillage_severity=2 for salt, got %d" % int(result.get("pillage_severity", 0)))
	check(String(result.get("new_owner_id", "x")) == "",
		"new_owner_id empty for terminal outcome")


func test_resolve_conquest_outcome_loot_and_scoot() -> void:
	_cleanup(); _setup_campaigns()
	_create_pair_of_realms()
	_create_domain(APEX_DOMAIN, APEX_OWNER, "", REALM_A)
	var result: Dictionary = RealmRepository.resolve_conquest_outcome(
		APEX_DOMAIN, VASSAL_OWNER, RealmRepository.INTENT_LOOT_AND_SCOOT)
	check(String(result.get("outcome", "")) == "looted_local_succession",
		"outcome=looted_local_succession, got %s" % String(result.get("outcome", "")))
	check(int(result.get("pillage_severity", 0)) == 1,
		"pillage_severity=1 for loot, got %d" % int(result.get("pillage_severity", 0)))
	check(String(result.get("new_owner_id", "x")) == "",
		"new_owner_id empty in v1 (0b's spawn_local_succession_npc will fill)")


func test_resolve_conquest_outcome_tracked_attacker_occupy() -> void:
	_cleanup(); _setup_campaigns()
	_create_pair_of_realms()
	_create_domain(APEX_DOMAIN, APEX_OWNER, "", REALM_A)
	# VASSAL_OWNER is head of REALM_B (tracked); occupies APEX_DOMAIN.
	var result: Dictionary = RealmRepository.resolve_conquest_outcome(
		APEX_DOMAIN, VASSAL_OWNER, RealmRepository.INTENT_OCCUPY)
	check(String(result.get("outcome", "")) == "occupied",
		"outcome=occupied for tracked attacker, got %s" % String(result.get("outcome", "")))
	check(String(result.get("new_owner_id", "")) == VASSAL_OWNER,
		"new_owner_id = tracked attacker's character_id, got %s" % String(result.get("new_owner_id", "")))
	check(int(result.get("pillage_severity", -1)) == 0,
		"pillage_severity=0 for clean occupy, got %d" % int(result.get("pillage_severity", -1)))
	check(String(result.get("attacker_realm_id", "")) == REALM_B,
		"attacker_realm_id surfaced, got %s" % String(result.get("attacker_realm_id", "")))


func test_resolve_conquest_outcome_off_map_attacker_occupy() -> void:
	_cleanup(); _setup_campaigns()
	_insert_character(APEX_OWNER, "Apex Owner")
	_insert_character(ATTACKER_FOREIGN, "Off-Map Attacker")
	# Defender has a tracked realm; attacker has NO realm row.
	RealmRepository.create_realm({
		"id": REALM_A, "campaign_id": TEST_CAMPAIGN,
		"name": "Realm A", "head_character_id": APEX_OWNER,
		"realm_kind": "tracked",
	})
	_create_domain(APEX_DOMAIN, APEX_OWNER, "", REALM_A)
	var result: Dictionary = RealmRepository.resolve_conquest_outcome(
		APEX_DOMAIN, ATTACKER_FOREIGN, RealmRepository.INTENT_OCCUPY)
	check(String(result.get("outcome", "")) == "occupied",
		"outcome=occupied for off-map attacker, got %s" % String(result.get("outcome", "")))
	check(String(result.get("new_owner_id", "x")) == "",
		"new_owner_id empty in v1 (0b's instantiate_realm_for_off_map_force will fill)")
	check(String(result.get("attacker_realm_id", "x")) == "",
		"attacker_realm_id empty (no tracked realm)")


func test_resolve_conquest_outcome_rejects_invalid_intent() -> void:
	_cleanup(); _setup_campaigns()
	_create_pair_of_realms()
	_create_domain(APEX_DOMAIN, APEX_OWNER, "", REALM_A)
	var result: Dictionary = RealmRepository.resolve_conquest_outcome(
		APEX_DOMAIN, VASSAL_OWNER, "not_a_real_intent")
	check(String(result.get("outcome", "x")) == "",
		"invalid intent returns empty outcome dict")
