extends "res://tests/test_suite_base.gd"

## Tests for Phase 10B.1d — Sanctum apprentices + aspirants.
##
## Covers:
##   - SanctumApprenticeResolver.resolve_for_stronghold:
##     - Rejects non-sanctum archetype
##     - Rejects below-L9 owner
##     - Rejects non-sanctum class (e.g. fighter)
##     - Rejects warlock (disabled from play in v1)
##     - Spawns 1d6 apprentices + 2d6 aspirants for a mage
##     - Spawns intended_class='witch' for a witch
##     - 50/50 split for Lightblessed Wonderworker
##     - Lightblessed cleric aspirants get WIS floor of 9
##   - SanctumApprenticeResolver.resolve_promotion_throw:
##     - Mage aspirant with INT 17 → high modifier → almost always promotes
##     - Cleric aspirant uses WIS not INT
##     - Failed throw sets status='failed_promotion'
##   - Aspirant promotion_eligible_day = joined_day + 4 months per Q20
##     (112 days on the 13×28 calendar).


var _campaign_id: String = ""
var _mage_l9_id: String = ""
var _mage_l5_id: String = ""
var _witch_l9_id: String = ""
var _lightblessed_l9_id: String = ""
var _warlock_l9_id: String = ""
var _fighter_l9_id: String = ""


func run_all_tests() -> void:
	_setup()

	# resolve_for_stronghold gates
	test_rejects_non_sanctum_archetype()
	test_rejects_below_l9_owner()
	test_rejects_non_sanctum_class()
	test_rejects_warlock()

	# Spawn paths
	test_mage_sanctum_spawns_apprentices_and_aspirants()
	test_mage_aspirants_have_promotion_eligible_day_4_months_out()
	test_witch_sanctum_intended_class_is_witch()
	test_lightblessed_50_50_split()
	test_lightblessed_cleric_aspirants_get_wis_floor_of_9()

	# Promotion throw
	test_promotion_throw_mage_aspirant_uses_int_modifier()
	test_promotion_throw_cleric_aspirant_uses_wis_modifier()
	test_promotion_failure_sets_failed_promotion_status()
	test_promotion_success_sets_level_1_and_class()

	if not has_failures():
		print("Phase10B1d: all tests passed.")


# ---------------------------------------------------------------------------
# Fixture
# ---------------------------------------------------------------------------

func _setup() -> void:
	_campaign_id = CampaignRepository.create_campaign("Test 10B.1d", "TestWorld")

	_mage_l9_id = _create_test_character(
		_campaign_id, "Test Mage", "mage", "mage", 9, 14, 10)
	_mage_l5_id = _create_test_character(
		_campaign_id, "Test Apprentice Mage", "mage", "mage", 5, 14, 10)
	_witch_l9_id = _create_test_character(
		_campaign_id, "Test Witch", "witch", "mage", 9, 14, 14)
	_lightblessed_l9_id = _create_test_character(
		_campaign_id, "Test Lightblessed", "lightblessed_wonderworker", "mage", 9, 16, 16)
	_warlock_l9_id = _create_test_character(
		_campaign_id, "Test Warlock", "warlock", "mage", 9, 14, 10)
	_fighter_l9_id = _create_test_character(
		_campaign_id, "Test Fighter", "fighter", "fighter", 9, 10, 10)


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
			10, ?, ?, 12, 10, 12, 'neutral', 24, 24)
	""", [id, campaign_id, name, class_id, progression, level, intelligence, wisdom])
	return id


func _create_sanctum_for(owner_id: String, archetype: String = "sanctum") -> String:
	var id := CampaignRepository.generate_id()
	# Migration 116: gp_value → cp_value (× 100). 25000 gp → 2500000 cp.
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO strongholds (id, owner_character_id, archetype,
			structure_type, cp_value, completion_pct, status)
		VALUES (?, ?, ?, ?, 2500000, 100, 'completed')
	""", [id, owner_id, archetype, archetype])
	return id


func _purge_followers_for(owner_id: String) -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM followers WHERE owner_character_id = ?", [owner_id])


# ---------------------------------------------------------------------------
# resolve_for_stronghold gates
# ---------------------------------------------------------------------------

func test_rejects_non_sanctum_archetype() -> void:
	# A fortress (not sanctum) owned by a mage should NOT attract aspirants.
	var castle_id := _create_sanctum_for(_mage_l9_id, "fortress")
	var resolver := SanctumApprenticeResolver.new()
	var result := resolver.resolve_for_stronghold(castle_id)
	check(String(result.get("summary", "")).contains("not 'sanctum'"),
		"non-sanctum archetype should be rejected; got '%s'" % result.get("summary", ""))


func test_rejects_below_l9_owner() -> void:
	var sanctum_id := _create_sanctum_for(_mage_l5_id)
	var resolver := SanctumApprenticeResolver.new()
	var result := resolver.resolve_for_stronghold(sanctum_id)
	check(String(result.get("summary", "")).contains("below L"),
		"L5 mage should be rejected; got '%s'" % result.get("summary", ""))


func test_rejects_non_sanctum_class() -> void:
	# A fighter owning a sanctum is unusual but possible — explicitly reject.
	var sanctum_id := _create_sanctum_for(_fighter_l9_id)
	var resolver := SanctumApprenticeResolver.new()
	var result := resolver.resolve_for_stronghold(sanctum_id)
	check(String(result.get("summary", "")).contains("does not attract sanctum apprentices"),
		"fighter class should not attract sanctum apprentices; got '%s'" % result.get("summary", ""))


func test_rejects_warlock() -> void:
	var sanctum_id := _create_sanctum_for(_warlock_l9_id)
	var resolver := SanctumApprenticeResolver.new()
	var result := resolver.resolve_for_stronghold(sanctum_id)
	check(String(result.get("summary", "")).contains("warlock is disabled"),
		"warlock should be explicitly rejected (disabled from play in v1); got '%s'" % result.get("summary", ""))


# ---------------------------------------------------------------------------
# Spawn paths
# ---------------------------------------------------------------------------

func test_mage_sanctum_spawns_apprentices_and_aspirants() -> void:
	_purge_followers_for(_mage_l9_id)
	var sanctum_id := _create_sanctum_for(_mage_l9_id)
	var resolver := SanctumApprenticeResolver.new()
	var result := resolver.resolve_for_stronghold(sanctum_id)
	var apprentice_count: int = int(result.get("apprentice_count", -1))
	var aspirant_count: int = int(result.get("aspirant_count", -1))
	check(apprentice_count >= 1 and apprentice_count <= 6,
		"mage sanctum should produce 1-6 apprentices (1d6), got %d" % apprentice_count)
	check(aspirant_count >= 2 and aspirant_count <= 12,
		"mage sanctum should produce 2-12 aspirants (2d6), got %d" % aspirant_count)

	# Verify rows persisted.
	var followers: Array = CampaignRepository.list_followers_for_owner(_mage_l9_id)
	check(followers.size() == apprentice_count + aspirant_count,
		"followers table should have %d rows for the mage, got %d" % [
			apprentice_count + aspirant_count, followers.size(),
		])
	# Apprentices should have level 1-3, status='present'.
	var apprentice_rows := 0
	var aspirant_rows := 0
	for f in followers:
		var fd: Dictionary = f
		if String(fd.get("source_kind", "")) == "class_follower":
			apprentice_rows += 1
			check(int(fd.get("level", 0)) >= 1 and int(fd.get("level", 0)) <= 3,
				"apprentice level should be 1-3")
			check(String(fd.get("status", "")) == "present",
				"apprentice status should be 'present'")
			check(String(fd.get("character_class", "")) == "mage",
				"mage apprentice should have character_class='mage'")
		elif String(fd.get("source_kind", "")) == "aspirant":
			aspirant_rows += 1
			check(int(fd.get("level", 0)) == 0,
				"aspirant level should be 0")
			check(String(fd.get("character_class", "")) == "normal_man",
				"aspirant character_class should be 'normal_man'")
			check(String(fd.get("intended_class", "")) == "mage",
				"mage aspirant intended_class should be 'mage'")
			check(String(fd.get("status", "")) == "aspirant_in_training",
				"aspirant status should be 'aspirant_in_training'")
	check(apprentice_rows == apprentice_count, "apprentice row count mismatch")
	check(aspirant_rows == aspirant_count, "aspirant row count mismatch")


func test_mage_aspirants_have_promotion_eligible_day_4_months_out() -> void:
	# Q20: exactly 4 months. On the 13-month × 28-day calendar that is 112
	# days — the original constant said 120 (a 30-day-month slip).
	var expected_delay: int = SanctumApprenticeResolver.PROMOTION_DELAY_MONTHS \
		* Timekeeping.DAYS_PER_MONTH
	check(expected_delay == 112,
		"Q20 4-month timer should be 112 days on the 13x28 calendar, got %d" % expected_delay)
	_purge_followers_for(_mage_l9_id)
	var sanctum_id := _create_sanctum_for(_mage_l9_id)
	var resolver := SanctumApprenticeResolver.new()
	var _result := resolver.resolve_for_stronghold(sanctum_id)
	var aspirants: Array = CampaignRepository.list_followers_by_source_kind(_mage_l9_id, "aspirant")
	check(not aspirants.is_empty(), "fixture: at least one aspirant should exist")
	for a in aspirants:
		var ad: Dictionary = a
		var joined: int = int(ad.get("joined_calendar_day", 0))
		var eligible: int = int(ad.get("promotion_eligible_day", 0))
		check(eligible == joined + expected_delay,
			"aspirant promotion_eligible_day should be joined_day + 112 (Q20, 4 months); got %d - %d = %d" % [
				eligible, joined, eligible - joined,
			])


func test_witch_sanctum_intended_class_is_witch() -> void:
	_purge_followers_for(_witch_l9_id)
	var sanctum_id := _create_sanctum_for(_witch_l9_id)
	var resolver := SanctumApprenticeResolver.new()
	var _result := resolver.resolve_for_stronghold(sanctum_id)
	var aspirants: Array = CampaignRepository.list_followers_by_source_kind(_witch_l9_id, "aspirant")
	check(not aspirants.is_empty(), "witch sanctum should produce aspirants")
	for a in aspirants:
		check(String((a as Dictionary).get("intended_class", "")) == "witch",
			"witch aspirant intended_class should be 'witch'")
	# Apprentices should have character_class='witch' too.
	var apprentices: Array = CampaignRepository.list_followers_by_source_kind(_witch_l9_id, "class_follower")
	for app in apprentices:
		check(String((app as Dictionary).get("character_class", "")) == "witch",
			"witch apprentice character_class should be 'witch'")


func test_lightblessed_50_50_split() -> void:
	_purge_followers_for(_lightblessed_l9_id)
	var sanctum_id := _create_sanctum_for(_lightblessed_l9_id)
	var resolver := SanctumApprenticeResolver.new()
	var result := resolver.resolve_for_stronghold(sanctum_id)
	var split: Dictionary = result.get("lightblessed_split", {})
	check(not split.is_empty(),
		"Lightblessed should produce a 50/50 split summary; got %s" % result.get("summary", ""))
	# mage + cleric quotas should equal the total counts.
	var apprentice_total: int = int(result.get("apprentice_count", 0))
	var aspirant_total: int = int(result.get("aspirant_count", 0))
	check(int(split.get("apprentice_mage", 0)) + int(split.get("apprentice_cleric", 0)) == apprentice_total,
		"apprentice_mage + apprentice_cleric should equal apprentice_count")
	check(int(split.get("aspirant_mage", 0)) + int(split.get("aspirant_cleric", 0)) == aspirant_total,
		"aspirant_mage + aspirant_cleric should equal aspirant_count")
	# Mage count is the ceiling of half (with the cleric getting the remainder).
	check(int(split.get("apprentice_mage", 0)) == int(ceil(float(apprentice_total) * 0.5)),
		"apprentice_mage should be ceil(count/2)")
	check(int(split.get("aspirant_mage", 0)) == int(ceil(float(aspirant_total) * 0.5)),
		"aspirant_mage should be ceil(count/2)")
	# Verify both mage and cleric aspirants exist (provided total >= 2).
	var aspirants: Array = CampaignRepository.list_followers_by_source_kind(_lightblessed_l9_id, "aspirant")
	var mage_aspirants := 0
	var cleric_aspirants := 0
	for a in aspirants:
		match String((a as Dictionary).get("intended_class", "")):
			"mage":   mage_aspirants += 1
			"cleric": cleric_aspirants += 1
	check(mage_aspirants == int(split.get("aspirant_mage", 0)),
		"mage aspirant rows should match the split count")
	check(cleric_aspirants == int(split.get("aspirant_cleric", 0)),
		"cleric aspirant rows should match the split count")


func test_lightblessed_cleric_aspirants_get_wis_floor_of_9() -> void:
	_purge_followers_for(_lightblessed_l9_id)
	var sanctum_id := _create_sanctum_for(_lightblessed_l9_id)
	var resolver := SanctumApprenticeResolver.new()
	var _result := resolver.resolve_for_stronghold(sanctum_id)
	var aspirants: Array = CampaignRepository.list_followers_by_source_kind(_lightblessed_l9_id, "aspirant")
	for a in aspirants:
		var ad: Dictionary = a
		if String(ad.get("intended_class", "")) == "cleric":
			check(int(ad.get("wisdom", 0)) >= 9,
				"Lightblessed cleric aspirant should have WIS >= 9 (Q20 floor); got %d" % int(ad.get("wisdom", 0)))
		if String(ad.get("intended_class", "")) == "mage":
			check(int(ad.get("intelligence", 0)) >= 9,
				"Lightblessed mage aspirant should have INT >= 9 (Q20 floor); got %d" % int(ad.get("intelligence", 0)))


# ---------------------------------------------------------------------------
# Promotion throw
# ---------------------------------------------------------------------------

func test_promotion_throw_mage_aspirant_uses_int_modifier() -> void:
	# Construct an aspirant with INT 18 (+3 mod) and verify the promotion
	# throw's modifier label is INT. Use a high INT so the chance of any
	# random failure is minimal, but retry up to 10 times if a natural 1
	# blocks.
	_purge_followers_for(_mage_l9_id)
	var promoted := false
	var attempts := 0
	while attempts < 10 and not promoted:
		attempts += 1
		var aspirant_id := CampaignRepository.create_follower({
			"campaign_id": _campaign_id,
			"owner_character_id": _mage_l9_id,
			"source_kind": "aspirant",
			"intended_class": "mage",
			"name": "Promotable Mage Aspirant",
			"character_class": "normal_man",
			"combat_progression": "fighter",
			"level": 0,
			"strength": 10, "intelligence": 18, "wisdom": 10,
			"dexterity": 10, "constitution": 10, "charisma": 10,
			"hp_max": 4, "hp_current": 4,
			"status": "aspirant_in_training",
			"joined_calendar_day": 1,
			"promotion_eligible_day": 121,
		})
		check(not aspirant_id.is_empty(), "fixture aspirant should be created")
		var aspirant: Dictionary = CampaignRepository.get_follower(aspirant_id)
		var result: Dictionary = SanctumApprenticeResolver.resolve_promotion_throw(aspirant, 200)
		var summary: String = String(result.get("summary", ""))
		check(summary.contains("INT mod"),
			"mage aspirant promotion throw should use INT mod label; got '%s'" % summary)
		if bool(result.get("success", false)):
			promoted = true
		# Clean up for retry.
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM followers WHERE id = ?", [aspirant_id])
	check(promoted,
		"Mage aspirant with INT 18 (+3) needs raw_roll >= 11 to clear 14+. Cumulative failure across 10 attempts is < 1 in 1024.")


func test_promotion_throw_cleric_aspirant_uses_wis_modifier() -> void:
	_purge_followers_for(_lightblessed_l9_id)
	var aspirant_id := CampaignRepository.create_follower({
		"campaign_id": _campaign_id,
		"owner_character_id": _lightblessed_l9_id,
		"source_kind": "aspirant",
		"intended_class": "cleric",
		"name": "Test Cleric Aspirant",
		"character_class": "normal_man",
		"combat_progression": "fighter",
		"level": 0,
		"strength": 10, "intelligence": 10, "wisdom": 18,
		"dexterity": 10, "constitution": 10, "charisma": 10,
		"hp_max": 4, "hp_current": 4,
		"status": "aspirant_in_training",
		"joined_calendar_day": 1,
		"promotion_eligible_day": 121,
	})
	check(not aspirant_id.is_empty(), "fixture cleric aspirant should be created")
	var aspirant: Dictionary = CampaignRepository.get_follower(aspirant_id)
	var result: Dictionary = SanctumApprenticeResolver.resolve_promotion_throw(aspirant, 200)
	var summary: String = String(result.get("summary", ""))
	check(summary.contains("WIS mod"),
		"cleric aspirant promotion throw should use WIS mod label; got '%s'" % summary)


func test_promotion_failure_sets_failed_promotion_status() -> void:
	_purge_followers_for(_mage_l9_id)
	# Construct an aspirant with INT 3 (-3 mod) and try until we get a
	# failure. The probability of a single failure at INT-3 is high
	# (any roll < 17, since 17+(-3) = 14; so only natural 17-20 succeed
	# = 20% success → 80% failure). Test by sampling.
	var failure_found := false
	for i in range(10):
		var aspirant_id := CampaignRepository.create_follower({
			"campaign_id": _campaign_id,
			"owner_character_id": _mage_l9_id,
			"source_kind": "aspirant",
			"intended_class": "mage",
			"name": "Fail-Test Aspirant %d" % i,
			"character_class": "normal_man",
			"combat_progression": "fighter",
			"level": 0,
			"strength": 10, "intelligence": 3, "wisdom": 10,
			"dexterity": 10, "constitution": 10, "charisma": 10,
			"hp_max": 4, "hp_current": 4,
			"status": "aspirant_in_training",
			"joined_calendar_day": 1,
			"promotion_eligible_day": 121,
		})
		var aspirant: Dictionary = CampaignRepository.get_follower(aspirant_id)
		var result: Dictionary = SanctumApprenticeResolver.resolve_promotion_throw(aspirant, 200)
		if not bool(result.get("success", true)):
			# Verify the follower status was updated to failed_promotion.
			var post: Dictionary = CampaignRepository.get_follower(aspirant_id)
			check(String(post.get("status", "")) == "failed_promotion",
				"failed throw should set status='failed_promotion'; got '%s'" % post.get("status", ""))
			check(int(post.get("departed_day", 0)) == 200,
				"failed throw should set departed_day=calendar_day=200; got %d" % int(post.get("departed_day", 0)))
			failure_found = true
			break
	check(failure_found,
		"INT-3 mage aspirant should fail at least once in 10 attempts (~80%% per-attempt failure rate)")


func test_promotion_success_sets_level_1_and_class() -> void:
	_purge_followers_for(_mage_l9_id)
	# INT 18 mage aspirant — likely to promote; sample with retries.
	var promoted := false
	var attempts := 0
	while attempts < 10 and not promoted:
		attempts += 1
		var aspirant_id := CampaignRepository.create_follower({
			"campaign_id": _campaign_id,
			"owner_character_id": _mage_l9_id,
			"source_kind": "aspirant",
			"intended_class": "mage",
			"name": "Success-Test Aspirant",
			"character_class": "normal_man",
			"combat_progression": "fighter",
			"level": 0,
			"strength": 10, "intelligence": 18, "wisdom": 10,
			"dexterity": 10, "constitution": 10, "charisma": 10,
			"hp_max": 4, "hp_current": 4,
			"status": "aspirant_in_training",
			"joined_calendar_day": 1,
			"promotion_eligible_day": 121,
		})
		var aspirant: Dictionary = CampaignRepository.get_follower(aspirant_id)
		var result: Dictionary = SanctumApprenticeResolver.resolve_promotion_throw(aspirant, 200)
		if bool(result.get("success", false)):
			var post: Dictionary = CampaignRepository.get_follower(aspirant_id)
			check(int(post.get("level", 0)) == 1,
				"successful promotion should set level=1; got %d" % int(post.get("level", 0)))
			check(String(post.get("character_class", "")) == "mage",
				"successful mage-intent promotion should set character_class='mage'; got '%s'" % post.get("character_class", ""))
			check(String(post.get("status", "")) == "present",
				"successful promotion should set status='present'; got '%s'" % post.get("status", ""))
			promoted = true
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM followers WHERE id = ?", [aspirant_id])
	check(promoted,
		"INT 18 mage aspirant should promote at least once in 10 attempts")
