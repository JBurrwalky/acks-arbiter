extends "res://tests/test_suite_base.gd"

## Tests for Phase 10B.1a — Magical Research block schema + repo + shell.
##
## Covers:
##   - migration 093 applied cleanly; tables visible
##   - magic_research_projects CRUD + status enum CHECK
##   - libraries / workshops CRUD
##   - followers CRUD + status/source_kind/intended_class enums
##   - list_aspirants_due_for_promotion filtering by promotion_eligible_day
##   - promote_follower_to_henchman cross-table operation
##   - Q25a retro migration: solicit_followers writes to `followers` (not
##     `characters`) and the row carries source_kind='bardic_recruit'
##   - ClassBucketResolver returns 'magical_research' for mage / warlock /
##     witch / 4 elven mage subclasses / darkblood / lightblessed; hidden
##     for fighter / pure cleric / thief / assassin / bard / dwarven_vaultguard
##   - Monthly-tick stub advances magic_research_projects.days_completed by 30


var _campaign_id: String = ""
var _mage_id: String = ""
var _lightblessed_id: String = ""
var _fighter_id: String = ""
var _bard_l9_id: String = ""
var _stronghold_id: String = ""


func run_all_tests() -> void:
	_setup()

	# Schema sanity
	test_migration_093_tables_exist()

	# magic_research_projects
	test_create_magic_research_project_round_trip()
	test_magic_research_project_status_enum_rejects_bad_value()

	# libraries / workshops
	test_create_library_and_list_for_owner()
	test_create_workshop_and_list_for_owner()

	# followers
	test_create_follower_round_trip()
	test_followers_status_enum_rejects_bad_value()
	test_list_followers_for_owner_filters_by_status()
	test_list_aspirants_due_for_promotion_filters_by_day()
	test_promote_follower_to_henchman_creates_characters_row()

	# Q25a retro migration
	test_solicit_followers_inserts_into_followers_table()

	# Visibility matrix (sample — full matrix lives in test_class_bucket_resolver.gd)
	test_magical_research_bucket_visible_for_mage_and_lightblessed()
	test_magical_research_bucket_hidden_for_fighter_and_bard()

	if not has_failures():
		print("Phase10B1a: all tests passed.")


# ---------------------------------------------------------------------------
# Fixture
# ---------------------------------------------------------------------------

func _setup() -> void:
	_campaign_id = CampaignRepository.create_campaign("Test 10B.1a", "TestWorld")

	_mage_id = _create_test_character(_campaign_id, "Test Mage", "mage", "mage", 9, 16, 10)
	_lightblessed_id = _create_test_character(_campaign_id, "Test Lightblessed",
		"lightblessed_wonderworker", "mage", 9, 16, 16)
	_fighter_id = _create_test_character(_campaign_id, "Test Fighter", "fighter", "fighter", 5, 10, 10)
	_bard_l9_id = _create_test_character(_campaign_id, "Test Bard", "bard", "thief", 9, 12, 10)

	# Make a sanctum stronghold for FK testing.
	# Migration 116: gp_value renamed to cp_value (× 100). 25000 gp → 2500000 cp.
	_stronghold_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO strongholds (id, owner_character_id, archetype,
			structure_type, cp_value, completion_pct, status)
		VALUES (?, ?, 'sanctum', 'sanctum', 2500000, 100, 'completed')
	""", [_stronghold_id, _mage_id])


func _create_test_character(
	campaign_id: String, name: String, class_id: String,
	progression: String, level: int, intelligence: int, wisdom: int,
) -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, combat_progression, level,
			strength, intelligence, wisdom, dexterity, constitution, charisma,
			alignment, hp_max, hp_current)
		VALUES (?, ?, ?, 'pc', 'full', 'human', ?, ?, ?,
			10, ?, ?, 12, 10, 12, 'lawful', 20, 20)
	""", [id, campaign_id, name, class_id, progression, level, intelligence, wisdom])
	return id


# ---------------------------------------------------------------------------
# Schema sanity
# ---------------------------------------------------------------------------

func test_migration_093_tables_exist() -> void:
	# Confirm all four tables can be queried (they exist + are reachable).
	var ok1: bool = CampaignRepository.db.query(
		"SELECT id FROM magic_research_projects WHERE 1=0")
	var ok2: bool = CampaignRepository.db.query("SELECT id FROM libraries WHERE 1=0")
	var ok3: bool = CampaignRepository.db.query("SELECT id FROM workshops WHERE 1=0")
	var ok4: bool = CampaignRepository.db.query("SELECT id FROM followers WHERE 1=0")
	check(ok1 and ok2 and ok3 and ok4,
		"migration 093 should create tables magic_research_projects / libraries / workshops / followers")


# ---------------------------------------------------------------------------
# magic_research_projects
# ---------------------------------------------------------------------------

func test_create_magic_research_project_round_trip() -> void:
	var project_id := CampaignRepository.create_magic_research_project({
		"campaign_id": _campaign_id,
		"character_id": _mage_id,
		"project_kind": "spell",
		"target_spell_key": "fireball",
		"target_spell_level": 3,
		"cp_committed": 300000,
		"days_total": 60,
		"days_completed": 0,
		"target_value": 16,
		"status": "in_progress",
		"started_calendar_day": 1,
	})
	check(not project_id.is_empty(),
		"create_magic_research_project should return a non-empty id")
	var row := CampaignRepository.get_magic_research_project(project_id)
	check(not row.is_empty() and str(row.get("project_kind", "")) == "spell",
		"round-tripped row should have project_kind='spell'")
	check(int(row.get("target_spell_level", 0)) == 3,
		"round-tripped row should preserve target_spell_level=3")


func test_magic_research_project_status_enum_rejects_bad_value() -> void:
	var bad_id := CampaignRepository.create_magic_research_project({
		"campaign_id": _campaign_id,
		"character_id": _mage_id,
		"project_kind": "spell",
		"cp_committed": 10000,
		"days_total": 10,
		"target_value": 16,
		"status": "not_a_real_status",
		"started_calendar_day": 1,
	})
	check(bad_id.is_empty(),
		"create_magic_research_project with invalid status should fail CHECK constraint and return ''")


# advance_magic_research_projects_for_character and its test were REMOVED
# 2026-06-12: the 10B.1a monthly "+30 days" stub advance was dead code (no
# code path ever creates an in_progress magic_research_projects row — the
# 10B.1b/c handlers insert rows already terminal) and unit-wrong (30-day
# month on the 13×28 calendar).


# ---------------------------------------------------------------------------
# libraries / workshops
# ---------------------------------------------------------------------------

func test_create_library_and_list_for_owner() -> void:
	var library_id := CampaignRepository.create_library({
		"campaign_id": _campaign_id,
		"owner_character_id": _mage_id,
		"stronghold_id": _stronghold_id,
		"structure_kind": "sanctum_library",
		"cp_invested": 5000000,
		"max_spell_level_supported": 6,
		"magic_research_throw_bonus": 1,
		"status": "operational",
		"created_calendar_day": 1,
	})
	check(not library_id.is_empty(), "create_library should return a non-empty id")
	var rows: Array = CampaignRepository.list_libraries_for_owner(_mage_id)
	var found := false
	for row in rows:
		if str(row.get("id", "")) == library_id:
			found = true
			check(int(row.get("max_spell_level_supported", 0)) == 6,
				"library row should preserve max_spell_level_supported=6")
			check(int(row.get("magic_research_throw_bonus", 0)) == 1,
				"library row should preserve magic_research_throw_bonus=+1")
	check(found, "list_libraries_for_owner should include the just-created library")


func test_create_workshop_and_list_for_owner() -> void:
	var workshop_id := CampaignRepository.create_workshop({
		"campaign_id": _campaign_id,
		"owner_character_id": _mage_id,
		"stronghold_id": _stronghold_id,
		"structure_kind": "tower_workshop",
		"cp_invested": 2500000,
		"max_item_value_supported_cp": 1500000,
		"magic_research_throw_bonus": 1,
		"status": "operational",
		"created_calendar_day": 1,
	})
	check(not workshop_id.is_empty(), "create_workshop should return a non-empty id")
	var rows: Array = CampaignRepository.list_workshops_for_owner(_mage_id)
	var found := false
	for row in rows:
		if str(row.get("id", "")) == workshop_id:
			found = true
			check(int(row.get("max_item_value_supported_cp", 0)) == 1500000,
				"workshop row should preserve max_item_value_supported_cp=1,500,000")
	check(found, "list_workshops_for_owner should include the just-created workshop")


# ---------------------------------------------------------------------------
# followers
# ---------------------------------------------------------------------------

func test_create_follower_round_trip() -> void:
	var follower_id := CampaignRepository.create_follower({
		"campaign_id": _campaign_id,
		"owner_character_id": _lightblessed_id,
		"stronghold_id": _stronghold_id,
		"source_kind": "aspirant",
		"intended_class": "mage",
		"name": "Test Aspirant",
		"race": "human",
		"character_class": "normal_man",
		"combat_progression": "fighter",
		"level": 0,
		"strength": 10, "intelligence": 9, "wisdom": 10,
		"dexterity": 10, "constitution": 10, "charisma": 10,
		"hp_max": 4, "hp_current": 4,
		"status": "aspirant_in_training",
		"joined_calendar_day": 1,
		"promotion_eligible_day": 121,
	})
	check(not follower_id.is_empty(), "create_follower should return a non-empty id")
	var row := CampaignRepository.get_follower(follower_id)
	check(str(row.get("source_kind", "")) == "aspirant",
		"follower row should preserve source_kind='aspirant'")
	check(str(row.get("intended_class", "")) == "mage",
		"follower row should preserve intended_class='mage'")
	check(str(row.get("status", "")) == "aspirant_in_training",
		"follower row should preserve status='aspirant_in_training'")
	check(int(row.get("promotion_eligible_day", 0)) == 121,
		"follower row should preserve promotion_eligible_day=121")


func test_followers_status_enum_rejects_bad_value() -> void:
	var bad_id := CampaignRepository.create_follower({
		"campaign_id": _campaign_id,
		"owner_character_id": _lightblessed_id,
		"source_kind": "aspirant",
		"name": "Bad Status Aspirant",
		"status": "not_a_real_status",
		"joined_calendar_day": 1,
	})
	check(bad_id.is_empty(),
		"create_follower with invalid status should fail CHECK constraint and return ''")


func test_list_followers_for_owner_filters_by_status() -> void:
	# Create one aspirant + one present follower.
	var asp_id := CampaignRepository.create_follower({
		"campaign_id": _campaign_id,
		"owner_character_id": _bard_l9_id,
		"source_kind": "aspirant",
		"intended_class": "mage",
		"name": "Filter-Test Aspirant",
		"level": 0, "status": "aspirant_in_training",
		"joined_calendar_day": 1, "promotion_eligible_day": 121,
	})
	var present_id := CampaignRepository.create_follower({
		"campaign_id": _campaign_id,
		"owner_character_id": _bard_l9_id,
		"source_kind": "bardic_recruit",
		"name": "Filter-Test Present",
		"character_class": "bard",
		"combat_progression": "thief",
		"level": 2, "status": "present",
		"joined_calendar_day": 1,
	})
	check(not asp_id.is_empty() and not present_id.is_empty(), "fixtures should be created")

	var all_for_bard: Array = CampaignRepository.list_followers_for_owner(_bard_l9_id)
	check(all_for_bard.size() >= 2,
		"list_followers_for_owner without status filter should return both rows")

	var aspirants_only: Array = CampaignRepository.list_followers_for_owner(
		_bard_l9_id, "aspirant_in_training")
	check(aspirants_only.size() >= 1,
		"list_followers_for_owner with status='aspirant_in_training' should return at least the aspirant")
	for row in aspirants_only:
		check(str(row.get("status", "")) == "aspirant_in_training",
			"all filtered rows should have status='aspirant_in_training'")


func test_list_aspirants_due_for_promotion_filters_by_day() -> void:
	# Create one aspirant due on day 100 + one due on day 200.
	var due_soon := CampaignRepository.create_follower({
		"campaign_id": _campaign_id,
		"owner_character_id": _lightblessed_id,
		"source_kind": "aspirant",
		"intended_class": "mage",
		"name": "Due-Soon Aspirant",
		"level": 0, "status": "aspirant_in_training",
		"joined_calendar_day": 1, "promotion_eligible_day": 100,
	})
	var due_later := CampaignRepository.create_follower({
		"campaign_id": _campaign_id,
		"owner_character_id": _lightblessed_id,
		"source_kind": "aspirant",
		"intended_class": "cleric",
		"name": "Due-Later Aspirant",
		"level": 0, "status": "aspirant_in_training",
		"joined_calendar_day": 1, "promotion_eligible_day": 200,
	})
	check(not due_soon.is_empty() and not due_later.is_empty(),
		"fixtures should be created")

	var on_day_120: Array = CampaignRepository.list_aspirants_due_for_promotion(120)
	var found_soon := false
	var found_later := false
	for row in on_day_120:
		if str(row.get("id", "")) == due_soon:
			found_soon = true
		if str(row.get("id", "")) == due_later:
			found_later = true
	check(found_soon, "due_soon (day=100) should appear in list_aspirants_due_for_promotion(120)")
	check(not found_later, "due_later (day=200) should NOT appear in list_aspirants_due_for_promotion(120)")


func test_promote_follower_to_henchman_creates_characters_row() -> void:
	var follower_id := CampaignRepository.create_follower({
		"campaign_id": _campaign_id,
		"owner_character_id": _bard_l9_id,
		"source_kind": "bardic_recruit",
		"name": "Promotion Candidate",
		"character_class": "bard",
		"combat_progression": "thief",
		"level": 2,
		"strength": 11, "intelligence": 12, "wisdom": 10,
		"dexterity": 14, "constitution": 11, "charisma": 15,
		"hp_max": 12, "hp_current": 12,
		"status": "present",
		"joined_calendar_day": 1,
	})
	check(not follower_id.is_empty(), "fixture follower should be created")

	var new_char_id := CampaignRepository.promote_follower_to_henchman(follower_id)
	check(not new_char_id.is_empty(),
		"promote_follower_to_henchman should return the new characters.id")

	# Verify the characters row exists.
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM characters WHERE id = ? LIMIT 1", [new_char_id]
	):
		check(false, "characters table query should not error")
		return
	check(not CampaignRepository.db.query_result.is_empty(),
		"new characters row should exist after promotion")
	var char_row: Dictionary = CampaignRepository.db.query_result[0]
	check(String(char_row.get("character_type", "")) == "henchman",
		"promoted character should have character_type='henchman'")
	check(String(char_row.get("persistence_tier", "")) == "named",
		"promoted character should have persistence_tier='named'")
	check(String(char_row.get("character_class", "")) == "bard",
		"promoted character should preserve character_class='bard'")
	check(int(char_row.get("level", 0)) == 2,
		"promoted character should preserve level=2")

	# Verify the follower row is now marked.
	var updated_follower := CampaignRepository.get_follower(follower_id)
	check(String(updated_follower.get("status", "")) == "promoted_to_henchman",
		"follower status should transition to 'promoted_to_henchman'")
	check(str_field(updated_follower, "promoted_to_henchman_id") == new_char_id,
		"follower.promoted_to_henchman_id should match the new characters.id")


# ---------------------------------------------------------------------------
# Q25a retro migration
# ---------------------------------------------------------------------------

func test_solicit_followers_inserts_into_followers_table() -> void:
	# Simulate a solicit_followers completion by directly invoking the handler.
	# Per the Phase 10A.3-rewritten handler (Q25a [RESOLVED 2026-05-11]), the
	# 1d6 bard applicants should land in `followers` with
	# source_kind='bardic_recruit', NOT in `characters` with
	# character_type='henchman'.
	var state: Dictionary = {
		"character_id": _bard_l9_id,
		"params_json": {},
	}
	var result: Dictionary = SolicitFollowersHandler.on_complete(state, null)
	check(not String(result.get("summary", "")).is_empty(),
		"solicit_followers should return a non-empty summary")

	# Count followers created from this solicitation (source_kind='bardic_recruit').
	var bardic_followers: Array = CampaignRepository.list_followers_by_source_kind(
		_bard_l9_id, "bardic_recruit")
	check(bardic_followers.size() >= 1,
		"solicit_followers should create at least 1 follower with source_kind='bardic_recruit' (got %d)" % bardic_followers.size())

	# Confirm none of the new rows landed in `characters` as henchman.
	if CampaignRepository.db.query_with_bindings("""
		SELECT COUNT(*) AS n FROM characters
		WHERE campaign_id = ? AND character_type = 'henchman'
		  AND name LIKE 'Bard Applicant%'
	""", [_campaign_id]):
		var n: int = int(CampaignRepository.db.query_result[0].get("n", 0))
		check(n == 0,
			"solicit_followers should NOT insert bard applicants into characters anymore (found %d)" % n)


# ---------------------------------------------------------------------------
# Class-bucket visibility (sample, not exhaustive)
# ---------------------------------------------------------------------------

func test_magical_research_bucket_visible_for_mage_and_lightblessed() -> void:
	check(ClassBucketResolver.has_bucket(_mage_id, "magical_research"),
		"Mage should have magical_research bucket")
	check(ClassBucketResolver.has_bucket(_lightblessed_id, "magical_research"),
		"Lightblessed Wonderworker should have magical_research bucket")


func test_magical_research_bucket_hidden_for_fighter_and_bard() -> void:
	check(not ClassBucketResolver.has_bucket(_fighter_id, "magical_research"),
		"Fighter should NOT have magical_research bucket")
	check(not ClassBucketResolver.has_bucket(_bard_l9_id, "magical_research"),
		"Bard should NOT have magical_research bucket")
