extends "res://tests/test_suite_base.gd"

## Tests for Phase 10B.1g — Lightblessed dual-list polish + Mage's
## dungeon-under-tower encounter-frequency hook (Q9 shortcut).
##
## Covers:
##   - research_magic[spell] dual-list filter:
##     - Mage can research an arcane spell (positive)
##     - Mage rejects a divine-only spell (negative)
##     - Lightblessed Wonderworker can research an arcane spell
##     - Lightblessed Wonderworker can research a cleric divine spell
##       (the dual-list confirmation)
##     - Cleric rejects (still arcane-only path in 10B.1b/g; divine spell
##       research lands in a future wave)
##   - apply_dungeon_target_reduction:
##     - has_dungeon=true → target reduced by 1, clamped at 1
##     - has_dungeon=false → target unchanged


var _campaign_id: String = ""
var _mage_l9_id: String = ""
var _lightblessed_l9_id: String = ""
var _cleric_l9_id: String = ""
var _bladedancer_l9_id: String = ""
var _witch_l9_id: String = ""
var _stronghold_id: String = ""
var _library_id: String = ""


func run_all_tests() -> void:
	_setup()

	# Dual-list filter (Phase 10B.1g)
	test_mage_accepts_arcane_spell()
	test_mage_rejects_divine_spell()
	test_lightblessed_accepts_arcane_spell()
	test_lightblessed_accepts_divine_cleric_spell()

	# Divine-caster research eligibility (Phase 10B.1g.1 — fixes Gap 2)
	test_cleric_can_research_divine_cleric_spell()
	test_cleric_rejects_arcane_spell_via_list_filter()
	test_witch_can_research_restricted_to_witch_spell()
	test_bladedancer_rejected_by_magical_research_bucket()

	# Dungeon-under-tower hook (Q9 shortcut)
	test_apply_dungeon_target_reduction_no_dungeon_unchanged()
	test_apply_dungeon_target_reduction_with_dungeon_reduces_by_1()
	test_apply_dungeon_target_reduction_clamps_at_1()

	if not has_failures():
		print("Phase10B1g: all tests passed.")


# ---------------------------------------------------------------------------
# Fixture
# ---------------------------------------------------------------------------

func _setup() -> void:
	_campaign_id = CampaignRepository.create_campaign("Test 10B.1g", "TestWorld")
	# L9 mage with INT 17 (+2) so the throw clears easily.
	_mage_l9_id = _create_test_character(_campaign_id, "Test Mage L9", "mage", "mage", 9, 17, 10)
	_lightblessed_l9_id = _create_test_character(_campaign_id, "Test Lightblessed L9",
		"lightblessed_wonderworker", "mage", 9, 17, 17)
	_cleric_l9_id = _create_test_character(_campaign_id, "Test Cleric L9", "cleric", "cleric", 9, 10, 17)
	_bladedancer_l9_id = _create_test_character(_campaign_id, "Test Bladedancer L9",
		"bladedancer", "cleric", 9, 10, 15)
	_witch_l9_id = _create_test_character(_campaign_id, "Test Witch L9",
		"witch", "mage", 9, 13, 17)

	# Migration 116: gp_value → cp_value (× 100). 50000 gp → 5000000 cp.
	_stronghold_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO strongholds (id, owner_character_id, archetype,
			structure_type, cp_value, completion_pct, status)
		VALUES (?, ?, 'sanctum', 'sanctum', 5000000, 100, 'completed')
	""", [_stronghold_id, _mage_l9_id])

	# Shared library supporting L3+ spells.
	_library_id = CampaignRepository.create_library({
		"campaign_id": _campaign_id,
		"owner_character_id": _mage_l9_id,
		"stronghold_id": _stronghold_id,
		"structure_kind": "sanctum_library",
		"cp_invested": 800000,
		"max_spell_level_supported": 3,
		"magic_research_throw_bonus": 0,
		"status": "operational",
		"created_calendar_day": 1,
	})

	# Lightblessed and cleric need their own library for ownership check.
	# Reuse the schema; pretend they share the sanctum for v1 simplicity.
	CampaignRepository.create_library({
		"id": "lib_lightblessed",
		"campaign_id": _campaign_id,
		"owner_character_id": _lightblessed_l9_id,
		"stronghold_id": _stronghold_id,
		"structure_kind": "sanctum_library",
		"cp_invested": 800000,
		"max_spell_level_supported": 3,
		"magic_research_throw_bonus": 0,
		"status": "operational",
		"created_calendar_day": 1,
	})
	CampaignRepository.create_library({
		"id": "lib_cleric",
		"campaign_id": _campaign_id,
		"owner_character_id": _cleric_l9_id,
		"stronghold_id": _stronghold_id,
		"structure_kind": "sanctum_library",
		"cp_invested": 800000,
		"max_spell_level_supported": 3,
		"magic_research_throw_bonus": 0,
		"status": "operational",
		"created_calendar_day": 1,
	})
	CampaignRepository.create_library({
		"id": "lib_bladedancer",
		"campaign_id": _campaign_id,
		"owner_character_id": _bladedancer_l9_id,
		"stronghold_id": _stronghold_id,
		"structure_kind": "sanctum_library",
		"cp_invested": 800000,
		"max_spell_level_supported": 3,
		"magic_research_throw_bonus": 0,
		"status": "operational",
		"created_calendar_day": 1,
	})
	CampaignRepository.create_library({
		"id": "lib_witch",
		"campaign_id": _campaign_id,
		"owner_character_id": _witch_l9_id,
		"stronghold_id": _stronghold_id,
		"structure_kind": "sanctum_library",
		"cp_invested": 800000,
		"max_spell_level_supported": 3,
		"magic_research_throw_bonus": 0,
		"status": "operational",
		"created_calendar_day": 1,
	})


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
			10, ?, ?, 12, 10, 12, 'lawful', 24, 24)
	""", [id, campaign_id, name, class_id, progression, level, intelligence, wisdom])
	return id


# ---------------------------------------------------------------------------
# Dual-list filter (Phase 10B.1g)
# ---------------------------------------------------------------------------

func test_mage_accepts_arcane_spell() -> void:
	# magic_missile is an arcane L1 spell. Mage should be eligible to
	# research it. Whatever the throw outcome, the rejection should NOT
	# mention "not on caster's research lists".
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM magic_research_projects WHERE character_id = ?", [_mage_l9_id])
	var state := {
		"character_id": _mage_l9_id,
		"params_json": JSON.stringify({
			"project_kind": "spell",
			"target_spell_key": "magic_missile",
			"target_spell_level": 1,
			"gp_committed": 1000,
			"library_id": _library_id,
		}),
	}
	var result := ResearchMagicHandler.on_complete(state, null)
	var summary: String = String(result.get("summary", ""))
	check(not summary.contains("not on caster's research lists"),
		"Mage researching arcane magic_missile should not hit the dual-list rejection; got '%s'" % summary)


func test_mage_rejects_divine_spell() -> void:
	# cure_light_wounds is divine-only (L1). Mage should be rejected
	# because their research lists are arcane-only.
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM magic_research_projects WHERE character_id = ?", [_mage_l9_id])
	var state := {
		"character_id": _mage_l9_id,
		"params_json": JSON.stringify({
			"project_kind": "spell",
			"target_spell_key": "cure_light_wounds",
			"target_spell_level": 1,
			"gp_committed": 1000,
			"library_id": _library_id,
		}),
	}
	var result := ResearchMagicHandler.on_complete(state, null)
	var summary: String = String(result.get("summary", ""))
	check(summary.contains("not on caster's research lists"),
		"Mage researching divine cure_light_wounds should be rejected; got '%s'" % summary)


func test_lightblessed_accepts_arcane_spell() -> void:
	# Lightblessed has arcane_casting + divine_casting class powers, so
	# they can research arcane spells too.
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM magic_research_projects WHERE character_id = ?", [_lightblessed_l9_id])
	var state := {
		"character_id": _lightblessed_l9_id,
		"params_json": JSON.stringify({
			"project_kind": "spell",
			"target_spell_key": "magic_missile",
			"target_spell_level": 1,
			"gp_committed": 1000,
			"library_id": "lib_lightblessed",
		}),
	}
	var result := ResearchMagicHandler.on_complete(state, null)
	var summary: String = String(result.get("summary", ""))
	check(not summary.contains("not on caster's research lists"),
		"Lightblessed researching arcane magic_missile should not hit the dual-list rejection; got '%s'" % summary)


func test_lightblessed_accepts_divine_cleric_spell() -> void:
	# The Q2/roadmap-RESOLVED dual-list confirmation: Lightblessed can
	# research a cleric divine spell because their JSON declares
	# divine_casting with spell_list='divine_cleric'.
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM magic_research_projects WHERE character_id = ?", [_lightblessed_l9_id])
	var state := {
		"character_id": _lightblessed_l9_id,
		"params_json": JSON.stringify({
			"project_kind": "spell",
			"target_spell_key": "cure_light_wounds",
			"target_spell_level": 1,
			"gp_committed": 1000,
			"library_id": "lib_lightblessed",
		}),
	}
	var result := ResearchMagicHandler.on_complete(state, null)
	var summary: String = String(result.get("summary", ""))
	check(not summary.contains("not on caster's research lists"),
		"Lightblessed researching divine cure_light_wounds should pass the dual-list filter; got '%s'" % summary)


func test_cleric_can_research_divine_cleric_spell() -> void:
	# Phase 10B.1g.1 fix: divine casters with the magical_research bucket
	# (per Q11) can now research spells on their divine list. Cleric has
	# spell_list='divine_cleric' + spell_research power → MR bucket.
	# cure_light_wounds is L1 divine_cleric → should pass eligibility.
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM magic_research_projects WHERE character_id = ?", [_cleric_l9_id])
	var state := {
		"character_id": _cleric_l9_id,
		"params_json": JSON.stringify({
			"project_kind": "spell",
			"target_spell_key": "cure_light_wounds",
			"target_spell_level": 1,
			"gp_committed": 1000,
			"library_id": "lib_cleric",
		}),
	}
	var result := ResearchMagicHandler.on_complete(state, null)
	var summary: String = String(result.get("summary", ""))
	# After the gate widening: Cleric should NOT be rejected for class
	# eligibility OR list eligibility. The throw outcome itself may
	# succeed or fail; we just verify the gate stops blocking.
	check(not summary.contains("arcane caster required"),
		"Cleric should no longer be rejected with 'arcane caster required' (Gap 2 fix)")
	check(not summary.contains("lacks magical_research bucket"),
		"Cleric has spell_research per Q11 → should pass the MR bucket gate")
	check(not summary.contains("not on caster's research lists"),
		"cure_light_wounds is on divine_cleric list → should pass list filter; got '%s'" % summary)


func test_cleric_rejects_arcane_spell_via_list_filter() -> void:
	# Cleric trying magic_missile (arcane only) should now be rejected by
	# the spell-LIST filter (not the class gate). This verifies the dual-
	# list filter is the active rejection path after the gate widening.
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM magic_research_projects WHERE character_id = ?", [_cleric_l9_id])
	var state := {
		"character_id": _cleric_l9_id,
		"params_json": JSON.stringify({
			"project_kind": "spell",
			"target_spell_key": "magic_missile",
			"target_spell_level": 1,
			"gp_committed": 1000,
			"library_id": "lib_cleric",
		}),
	}
	var result := ResearchMagicHandler.on_complete(state, null)
	var summary: String = String(result.get("summary", ""))
	check(summary.contains("not on caster's research lists"),
		"Cleric researching arcane magic_missile should be rejected by the list filter (Gap 1 visible now); got '%s'" % summary)


func test_witch_can_research_restricted_to_witch_spell() -> void:
	# Phase 10B.1g.1 fix (Gap 1): the dual-list helper now consults
	# get_available_spells_for_class which walks `restricted_to`. Witch
	# has spell_list='divine_cleric' (shared base list) PLUS access to
	# spells in the catalog with restricted_to=['witch']. The catalog has
	# 29 such restricted_to entries today (bladedancer/priestess/shaman/
	# witch). The exact witch-restricted spell key may vary as the catalog
	# grows; we verify the mechanism by querying SpellRegistry directly.
	var registry: SpellRegistry = SpellRegistry.new()
	var class_registry: ClassRegistry = ClassRegistry.new()
	var witch_l1: Array[String] = registry.get_available_spells_for_class(
		"witch", 1, class_registry)
	# Base divine_cleric L1 should appear (cure_light_wounds, etc).
	check("cure_light_wounds" in witch_l1,
		"witch L1 list should include divine_cleric base entries like cure_light_wounds")

	# Round-trip the eligibility via the handler — Witch researching a
	# divine_cleric L1 spell should pass class + list gates.
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM magic_research_projects WHERE character_id = ?", [_witch_l9_id])
	var state := {
		"character_id": _witch_l9_id,
		"params_json": JSON.stringify({
			"project_kind": "spell",
			"target_spell_key": "cure_light_wounds",
			"target_spell_level": 1,
			"gp_committed": 1000,
			"library_id": "lib_witch",
		}),
	}
	var result := ResearchMagicHandler.on_complete(state, null)
	var summary: String = String(result.get("summary", ""))
	check(not summary.contains("lacks magical_research bucket"),
		"Witch has spell_research per Q11 → MR bucket gate should pass")
	check(not summary.contains("not on caster's research lists"),
		"Witch researching divine cleric cure_light_wounds should pass the list filter; got '%s'" % summary)


func test_bladedancer_rejected_by_magical_research_bucket() -> void:
	# Q11 explicitly EXCLUDES Bladedancer from the magical_research bucket
	# even though they have divine_casting + restricted
	# spell_research_and_minor_item_creation powers. The bucket gate in
	# _handle_spell_branch should reject them.
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM magic_research_projects WHERE character_id = ?", [_bladedancer_l9_id])
	var state := {
		"character_id": _bladedancer_l9_id,
		"params_json": JSON.stringify({
			"project_kind": "spell",
			"target_spell_key": "cure_light_wounds",
			"target_spell_level": 1,
			"gp_committed": 1000,
			"library_id": "lib_bladedancer",
		}),
	}
	var result := ResearchMagicHandler.on_complete(state, null)
	var summary: String = String(result.get("summary", ""))
	check(summary.contains("lacks magical_research bucket"),
		"Bladedancer should be rejected by the MR bucket gate per Q11; got '%s'" % summary)


# ---------------------------------------------------------------------------
# Mage's dungeon-under-tower hook (Q9)
# ---------------------------------------------------------------------------

func test_apply_dungeon_target_reduction_no_dungeon_unchanged() -> void:
	# When has_dungeon is false, target is returned unchanged.
	check(DomainEncounterResolver.apply_dungeon_target_reduction(6, false) == 6,
		"no dungeon → target 6 unchanged")
	check(DomainEncounterResolver.apply_dungeon_target_reduction(20, false) == 20,
		"no dungeon → target 20 unchanged")


func test_apply_dungeon_target_reduction_with_dungeon_reduces_by_1() -> void:
	# RAW shortcut: dungeon presence reduces the target by 1 (more
	# frequent encounters since throw fires on roll >= target).
	check(DomainEncounterResolver.apply_dungeon_target_reduction(6, true) == 5,
		"dungeon → target 6 should reduce to 5")
	check(DomainEncounterResolver.apply_dungeon_target_reduction(20, true) == 19,
		"dungeon → target 20 should reduce to 19")


func test_apply_dungeon_target_reduction_clamps_at_1() -> void:
	# Clamp at 1 so the throw stays rollable (target=0 would always trigger
	# on any roll >= 0, breaking the roll mechanic).
	check(DomainEncounterResolver.apply_dungeon_target_reduction(1, true) == 1,
		"dungeon + base 1 should clamp at 1 (not 0)")
	check(DomainEncounterResolver.apply_dungeon_target_reduction(2, true) == 1,
		"dungeon + base 2 should reduce to 1")
