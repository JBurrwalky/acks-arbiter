extends "res://tests/test_suite_base.gd"

## Phase 11D-prereq.0b: tests for the three RealmRepository helpers added
## to support the three-outcome conquest taxonomy.
##
## Coverage:
##   instantiate_realm_for_off_map_force — creates a tracked realm + head NPC
##   spawn_local_succession_npc          — creates a placeholder local NPC
##   apply_pillage                       — severity 0 / 1 / 2 effects

const TEST_CAMPAIGN := "test_reify_campaign"
const DOMAIN_ID := "test_reify_domain"
const OWNER_ID := "test_reify_owner"
const STRONGHOLD_ID := "test_reify_stronghold"
const HEX_MAP_ID := "test_reify_map"


func run_all_tests() -> void:
	_cleanup()
	test_instantiate_realm_for_off_map_force_creates_realm_and_head()
	test_instantiate_realm_defaults_alignment_to_chaotic()
	test_instantiate_realm_uses_head_npc_data_overrides()
	test_spawn_local_succession_npc_creates_npc_with_domain_alignment()
	test_apply_pillage_severity_zero_no_op()
	test_apply_pillage_light_reduces_population_treasury_shp_land()
	test_apply_pillage_heavy_reduces_more()
	test_apply_pillage_land_value_floors_at_1()
	_cleanup()
	if not has_failures():
		print("RealmReification: all tests passed.")


# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

func _setup() -> void:
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[TEST_CAMPAIGN, "Reification Test"])
	# Hex map for the pillage land_value tests.
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO hex_maps (id, campaign_id, name, scale)
		VALUES (?, ?, ?, ?)
	""", [HEX_MAP_ID, TEST_CAMPAIGN, "Reification Test Map", "regional_6mi"])


func _create_domain(treasury_cp: int, peasants: int, alignment: String = "neutral") -> void:
	# Owner character
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_type, persistence_tier,
			 race, character_class, level, xp,
			 combat_progression,
			 strength, intelligence, wisdom, dexterity, constitution, charisma,
			 alignment, is_active)
		VALUES (?, ?, 'Owner', 'pc', 'full', 'human', 'fighter', 5, 0,
		        'fighter', 10, 10, 10, 10, 10, 10, ?, 1)
	""", [OWNER_ID, TEST_CAMPAIGN, alignment])
	CampaignRepository.db.query_with_bindings("""
		INSERT OR REPLACE INTO domains
			(id, campaign_id, name, owner_character_id, territory_type,
			 peasant_families, morale, treasury_cp, alignment,
			 established_calendar_day, lifecycle_state)
		VALUES (?, ?, ?, ?, 'wilderness', ?, 0, ?, ?, 100, 'active')
	""", [DOMAIN_ID, TEST_CAMPAIGN, "Test Domain", OWNER_ID,
	      peasants, treasury_cp, alignment])


func _add_hex(q: int, r: int, land_value: int) -> void:
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO domain_hexes (id, domain_id, map_id, hex_q, hex_r, land_value)
		VALUES (?, ?, ?, ?, ?, ?)
	""", [CampaignRepository.generate_id(), DOMAIN_ID, HEX_MAP_ID, q, r, land_value])


func _add_stronghold(shp: int) -> void:
	CampaignRepository.db.query_with_bindings("""
		INSERT OR REPLACE INTO strongholds (id, domain_id, archetype, cp_value, shp)
		VALUES (?, ?, 'fortress', 1000000, ?)
	""", [STRONGHOLD_ID, DOMAIN_ID, shp])


func _cleanup() -> void:
	# Realms + relations created by instantiate_realm_for_off_map_force tests.
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM realm_relations WHERE campaign_id = ?", [TEST_CAMPAIGN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM realms WHERE campaign_id = ?", [TEST_CAMPAIGN])
	# Spawned NPCs (everything with type npc in this campaign).
	CampaignRepository.db.query_with_bindings("""
		DELETE FROM characters WHERE campaign_id = ? AND character_type = 'npc'
	""", [TEST_CAMPAIGN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM domain_hexes WHERE domain_id = ?", [DOMAIN_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM strongholds WHERE id = ?", [STRONGHOLD_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM domains WHERE id = ?", [DOMAIN_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM characters WHERE id = ?", [OWNER_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM hex_maps WHERE id = ?", [HEX_MAP_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [TEST_CAMPAIGN])


# ---------------------------------------------------------------------------
# Tests — instantiate_realm_for_off_map_force
# ---------------------------------------------------------------------------

func test_instantiate_realm_for_off_map_force_creates_realm_and_head() -> void:
	_cleanup(); _setup()
	var result: Dictionary = RealmRepository.instantiate_realm_for_off_map_force(
		TEST_CAMPAIGN, "Auran", {}, 100)
	var realm_id: String = str_field(result, "realm_id")
	var head_id: String = str_field(result, "head_character_id")
	check(not realm_id.is_empty(), "realm_id returned")
	check(not head_id.is_empty(), "head_character_id returned")
	# Verify realm row.
	var realm: Dictionary = RealmRepository.get_realm(realm_id)
	check(String(realm.get("realm_kind", "")) == "tracked",
		"new realm has realm_kind=tracked, got %s" % String(realm.get("realm_kind", "")))
	check(String(realm.get("culture", "")) == "Auran",
		"culture passed through, got %s" % String(realm.get("culture", "")))
	check(str_field(realm, "head_character_id") == head_id,
		"realm.head = the spawned npc")
	# Verify head character row.
	CampaignRepository.db.query_with_bindings(
		"SELECT character_type, alignment FROM characters WHERE id = ?", [head_id])
	check(not CampaignRepository.db.query_result.is_empty(), "head character row exists")
	check(String(CampaignRepository.db.query_result[0].get("character_type", "")) == "npc",
		"head is character_type=npc")


func test_instantiate_realm_defaults_alignment_to_chaotic() -> void:
	_cleanup(); _setup()
	var result: Dictionary = RealmRepository.instantiate_realm_for_off_map_force(
		TEST_CAMPAIGN, "Foreign", {}, 100)
	var realm: Dictionary = RealmRepository.get_realm(str_field(result, "realm_id"))
	check(str_field(realm, "alignment") == "chaotic",
		"off-map default alignment is chaotic, got %s" % str_field(realm, "alignment"))


func test_instantiate_realm_uses_head_npc_data_overrides() -> void:
	_cleanup(); _setup()
	var result: Dictionary = RealmRepository.instantiate_realm_for_off_map_force(
		TEST_CAMPAIGN, "TestCulture",
		{
			"name": "Custom Warlord",
			"realm_name": "Custom Realm",
			"alignment": "neutral",
		},
		100)
	var realm: Dictionary = RealmRepository.get_realm(str_field(result, "realm_id"))
	check(String(realm.get("name", "")) == "Custom Realm",
		"realm name overridden, got %s" % String(realm.get("name", "")))
	check(str_field(realm, "alignment") == "neutral",
		"alignment overridden, got %s" % str_field(realm, "alignment"))
	CampaignRepository.db.query_with_bindings(
		"SELECT name FROM characters WHERE id = ?", [str_field(result, "head_character_id")])
	check(String(CampaignRepository.db.query_result[0].get("name", "")) == "Custom Warlord",
		"head NPC name overridden, got %s" % String(CampaignRepository.db.query_result[0].get("name", "")))


# ---------------------------------------------------------------------------
# Tests — spawn_local_succession_npc
# ---------------------------------------------------------------------------

func test_spawn_local_succession_npc_creates_npc_with_domain_alignment() -> void:
	_cleanup(); _setup()
	_create_domain(0, 100, "chaotic")
	var npc_id: String = RealmRepository.spawn_local_succession_npc(DOMAIN_ID, 100)
	check(not npc_id.is_empty(), "npc_id returned")
	CampaignRepository.db.query_with_bindings(
		"SELECT character_type, alignment FROM characters WHERE id = ?", [npc_id])
	var row: Dictionary = CampaignRepository.db.query_result[0]
	check(str(row.get("character_type", "")) == "npc", "character_type=npc")
	check(str(row.get("alignment", "")) == "chaotic",
		"alignment matches domain's chaotic, got %s" % str(row.get("alignment", "")))


# ---------------------------------------------------------------------------
# Tests — apply_pillage
# ---------------------------------------------------------------------------

func test_apply_pillage_severity_zero_no_op() -> void:
	_cleanup(); _setup()
	_create_domain(10000, 200)
	_add_hex(0, 0, 5)
	_add_stronghold(100)
	var summary: Dictionary = RealmRepository.apply_pillage(DOMAIN_ID, 0)
	check(int(summary.get("looted_cp", -1)) == 0, "severity 0: looted_cp = 0")
	check(int(summary.get("families_lost", -1)) == 0, "severity 0: families_lost = 0")
	# Verify state unchanged.
	CampaignRepository.db.query_with_bindings(
		"SELECT treasury_cp, peasant_families FROM domains WHERE id = ?", [DOMAIN_ID])
	var d: Dictionary = CampaignRepository.db.query_result[0]
	check(int(d.get("treasury_cp", 0)) == 10000, "treasury unchanged")
	check(int(d.get("peasant_families", 0)) == 200, "peasants unchanged")


func test_apply_pillage_light_reduces_population_treasury_shp_land() -> void:
	_cleanup(); _setup()
	_create_domain(10000, 200)
	_add_hex(0, 0, 5)
	_add_hex(1, 0, 7)
	_add_stronghold(100)
	var summary: Dictionary = RealmRepository.apply_pillage(DOMAIN_ID, 1)
	# Treasury: looted entirely.
	check(int(summary.get("looted_cp", -1)) == 10000,
		"light: looted_cp = full treasury, got %d" % int(summary.get("looted_cp", -1)))
	# Peasants × 0.9 = 180; lost = 20.
	check(int(summary.get("families_lost", -1)) == 20,
		"light: families_lost = 20 (200 × 0.1), got %d" % int(summary.get("families_lost", -1)))
	# SHP × 0.75 = 75; lost = 25.
	check(int(summary.get("shp_lost", -1)) == 25,
		"light: shp_lost = 25 (100 × 0.25), got %d" % int(summary.get("shp_lost", -1)))
	# Land value delta = -1.
	check(int(summary.get("land_value_delta_per_hex", 0)) == -1,
		"light: land_value_delta = -1")
	# Verify domain row state.
	CampaignRepository.db.query_with_bindings(
		"SELECT treasury_cp, peasant_families FROM domains WHERE id = ?", [DOMAIN_ID])
	var d: Dictionary = CampaignRepository.db.query_result[0]
	check(int(d.get("treasury_cp", -1)) == 0, "treasury zeroed")
	check(int(d.get("peasant_families", -1)) == 180, "peasants reduced to 180")
	# Verify hex land_value reduced.
	CampaignRepository.db.query_with_bindings(
		"SELECT hex_q, land_value FROM domain_hexes WHERE domain_id = ? ORDER BY hex_q", [DOMAIN_ID])
	var rows: Array = CampaignRepository.db.query_result
	check(int(rows[0].get("land_value", -1)) == 4, "hex 0 land_value 5 -> 4")
	check(int(rows[1].get("land_value", -1)) == 6, "hex 1 land_value 7 -> 6")
	# Verify stronghold shp reduced.
	CampaignRepository.db.query_with_bindings(
		"SELECT shp FROM strongholds WHERE id = ?", [STRONGHOLD_ID])
	check(int(CampaignRepository.db.query_result[0].get("shp", -1)) == 75,
		"stronghold shp reduced to 75")


func test_apply_pillage_heavy_reduces_more() -> void:
	_cleanup(); _setup()
	_create_domain(5000, 100)
	_add_hex(0, 0, 5)
	_add_stronghold(80)
	var summary: Dictionary = RealmRepository.apply_pillage(DOMAIN_ID, 2)
	# Peasants × 0.75 = 75; lost = 25.
	check(int(summary.get("families_lost", -1)) == 25,
		"heavy: families_lost = 25 (100 × 0.25), got %d" % int(summary.get("families_lost", -1)))
	# SHP × 0.5 = 40; lost = 40.
	check(int(summary.get("shp_lost", -1)) == 40,
		"heavy: shp_lost = 40 (80 × 0.5), got %d" % int(summary.get("shp_lost", -1)))
	# Land value delta = -2.
	check(int(summary.get("land_value_delta_per_hex", 0)) == -2,
		"heavy: land_value_delta = -2")
	CampaignRepository.db.query_with_bindings(
		"SELECT land_value FROM domain_hexes WHERE domain_id = ?", [DOMAIN_ID])
	check(int(CampaignRepository.db.query_result[0].get("land_value", -1)) == 3,
		"heavy: hex land_value 5 -> 3")


func test_apply_pillage_land_value_floors_at_1() -> void:
	_cleanup(); _setup()
	_create_domain(0, 100)
	_add_hex(0, 0, 2)  # heavy (-2) would normally → 0, but floor at 1
	_add_hex(1, 0, 1)  # already at floor; heavy keeps it at 1
	RealmRepository.apply_pillage(DOMAIN_ID, 2)
	CampaignRepository.db.query_with_bindings(
		"SELECT hex_q, land_value FROM domain_hexes WHERE domain_id = ? ORDER BY hex_q", [DOMAIN_ID])
	var rows: Array = CampaignRepository.db.query_result
	check(int(rows[0].get("land_value", -1)) == 1,
		"land_value 2 - 2 = 0 → floored to 1, got %d" % int(rows[0].get("land_value", -1)))
	check(int(rows[1].get("land_value", -1)) == 1,
		"land_value 1 - 2 = -1 → floored to 1, got %d" % int(rows[1].get("land_value", -1)))
