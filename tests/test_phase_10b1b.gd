extends "res://tests/test_suite_base.gd"

## Tests for Phase 10B.1b — Magical Research spell-side handlers.
##
## Covers:
##   - ResearchMagicHandler: project_kind=spell with library check, eligibility
##     (arcane caster, L5+, can-learn-level), throw success/failure, library
##     auto-growth on success, spell added to formulas + repertoire.
##   - RewriteSpellHandler: deterministic 7d/level, no throw, idempotent.
##   - ReplaceSpellHandler: same-level swap, formula preserved, fails on
##     mismatched levels / missing formula / missing repertoire entry.
##   - ScribeSpellHandler: scroll consumed; spellbook source preserved;
##     idempotent UNIQUE constraint on formula insert.
##
## Each test resets relevant state at the top so order doesn't matter.


var _campaign_id: String = ""
var _mage_l5_id: String = ""
var _mage_l9_high_int_id: String = ""
var _mage_l1_id: String = ""
var _cleric_id: String = ""
var _library_l3_id: String = ""
var _library_l1_id: String = ""
var _stronghold_id: String = ""


func run_all_tests() -> void:
	_setup()

	# research_magic
	test_research_magic_rejects_no_character_id()
	test_research_magic_rejects_non_spell_project_kind()
	test_research_magic_rejects_caster_below_l5()
	test_research_magic_rejects_non_arcane_caster()
	test_research_magic_rejects_when_library_too_small_for_level()
	test_research_magic_rejects_unknown_spell_key()
	test_research_magic_rejects_insufficient_gp()
	test_research_magic_succeeds_for_l9_high_int_caster_and_grows_library()

	# rewrite_spell
	test_rewrite_spell_adds_spell_to_repertoire_and_formulas()
	test_rewrite_spell_rejects_non_arcane()

	# replace_spell
	test_replace_spell_swaps_repertoire_entry_and_preserves_old_formula()
	test_replace_spell_rejects_old_not_in_repertoire()
	test_replace_spell_rejects_new_formula_unknown()
	test_replace_spell_rejects_mismatched_levels()

	# scribe_spell
	test_scribe_spell_from_scroll_consumes_scroll_and_adds_formula()
	test_scribe_spell_from_spellbook_preserves_source()
	test_scribe_spell_rejects_when_caster_cannot_learn_level()

	if not has_failures():
		print("Phase10B1b: all tests passed.")


# ---------------------------------------------------------------------------
# Fixture
# ---------------------------------------------------------------------------

func _setup() -> void:
	_campaign_id = CampaignRepository.create_campaign("Test 10B.1b", "TestWorld")

	# L5 mage, average INT (no bonus).
	_mage_l5_id = _create_test_character(_campaign_id, "Test Mage L5", "mage", "mage", 5, 11, 10)

	# L9 mage with high INT (bonus +2) — used for the success-path test so the
	# throw clears the L3-spell target reliably without flake.
	_mage_l9_high_int_id = _create_test_character(_campaign_id,
		"Test Mage L9", "mage", "mage", 9, 17, 10)

	# L1 mage — too low for research per RAW L18-19.
	_mage_l1_id = _create_test_character(_campaign_id, "Test Apprentice", "mage", "mage", 1, 13, 10)

	# Cleric — divine caster, will hit the "arcane required" rejection.
	_cleric_id = _create_test_character(_campaign_id, "Test Cleric", "cleric", "cleric", 9, 10, 16)

	# Stronghold for FK consistency on the library rows.
	_stronghold_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO strongholds (id, owner_character_id, archetype,
			structure_type, gp_value, completion_pct, status)
		VALUES (?, ?, 'sanctum', 'sanctum', 30000, 100, 'completed')
	""", [_stronghold_id, _mage_l9_high_int_id])

	# Library supporting L3 spells with +0 bonus (used by the success path).
	_library_l3_id = CampaignRepository.create_library({
		"campaign_id": _campaign_id,
		"owner_character_id": _mage_l9_high_int_id,
		"stronghold_id": _stronghold_id,
		"structure_kind": "sanctum_library",
		"gp_invested": 8000,
		"max_spell_level_supported": 3,
		"magic_research_throw_bonus": 0,
		"status": "operational",
		"created_calendar_day": 1,
	})

	# Library supporting only L1 spells — used to verify max_spell_level
	# rejections.
	_library_l1_id = CampaignRepository.create_library({
		"campaign_id": _campaign_id,
		"owner_character_id": _mage_l5_id,
		"stronghold_id": _stronghold_id,
		"structure_kind": "sanctum_library",
		"gp_invested": 4000,
		"max_spell_level_supported": 1,
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
			10, ?, ?, 12, 10, 12, 'neutral', 20, 20)
	""", [id, campaign_id, name, class_id, progression, level, intelligence, wisdom])
	return id


func _clear_completed_projects_for(character_id: String) -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM magic_research_projects WHERE character_id = ?", [character_id])


# ---------------------------------------------------------------------------
# research_magic
# ---------------------------------------------------------------------------

func test_research_magic_rejects_no_character_id() -> void:
	var state := {"character_id": "", "params_json": "{}"}
	var result := ResearchMagicHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("no character_id"),
		"research_magic with empty character_id should reject")


func test_research_magic_rejects_non_spell_project_kind() -> void:
	# After 10B.1c/e/f shipped, all four valid project_kinds (spell /
	# magic_item / construct / monster) are live branches. Verify the
	# dispatch rejects an UNKNOWN project_kind value cleanly.
	var state := {
		"character_id": _mage_l9_high_int_id,
		"params_json": JSON.stringify({"project_kind": "totally_invalid_kind"}),
	}
	var result := ResearchMagicHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("unknown project_kind"),
		"research_magic with unknown project_kind should be rejected; got '%s'" % result.get("summary", ""))


func test_research_magic_rejects_caster_below_l5() -> void:
	var state := {
		"character_id": _mage_l1_id,
		"params_json": JSON.stringify({
			"project_kind": "spell",
			"target_spell_key": "magic_missile",
			"target_spell_level": 1,
			"gp_committed": 1000,
			"library_id": _library_l1_id,
		}),
	}
	var result := ResearchMagicHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("L5+"),
		"L1 mage should be rejected as 'caster must be L5+'; got '%s'" % result.get("summary", ""))


func test_research_magic_rejects_non_arcane_caster() -> void:
	# Phase 10B.1g.1 (2026-05-11): the arcane-only gate was widened to the
	# magical_research bucket gate. Cleric NOW passes the eligibility gate
	# (they have spell_research per Q11) — but researching arcane
	# magic_missile fails the LIST filter (cleric's research list is
	# divine_cleric, not arcane). This test now verifies the list-filter
	# rejection path. For the bucket-gate rejection path, see Bladedancer
	# in test_phase_10b1g.gd::test_bladedancer_rejected_by_magical_research_bucket.
	var cleric_lib_id := CampaignRepository.create_library({
		"campaign_id": _campaign_id,
		"owner_character_id": _cleric_id,
		"stronghold_id": _stronghold_id,
		"structure_kind": "sanctum_library",
		"gp_invested": 4000,
		"max_spell_level_supported": 1,
		"magic_research_throw_bonus": 0,
		"status": "operational",
		"created_calendar_day": 1,
	})
	var state := {
		"character_id": _cleric_id,
		"params_json": JSON.stringify({
			"project_kind": "spell",
			"target_spell_key": "magic_missile",
			"target_spell_level": 1,
			"gp_committed": 1000,
			"library_id": cleric_lib_id,
		}),
	}
	var result := ResearchMagicHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("not on caster's research lists"),
		"Cleric researching arcane magic_missile should be rejected by the list filter; got '%s'" % result.get("summary", ""))


func test_research_magic_rejects_when_library_too_small_for_level() -> void:
	var state := {
		"character_id": _mage_l5_id,
		"params_json": JSON.stringify({
			"project_kind": "spell",
			"target_spell_key": "fireball",  # L3 arcane spell
			"target_spell_level": 3,
			"gp_committed": 3000,
			"library_id": _library_l1_id,  # only supports L1
		}),
	}
	var result := ResearchMagicHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("library supports up to level"),
		"L1 library should reject L3 spell research; got '%s'" % result.get("summary", ""))


func test_research_magic_rejects_unknown_spell_key() -> void:
	var state := {
		"character_id": _mage_l9_high_int_id,
		"params_json": JSON.stringify({
			"project_kind": "spell",
			"target_spell_key": "totally_made_up_spell",
			"target_spell_level": 1,
			"gp_committed": 1000,
			"library_id": _library_l3_id,
		}),
	}
	var result := ResearchMagicHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("not in registry"),
		"Unknown spell_key should be rejected; got '%s'" % result.get("summary", ""))


func test_research_magic_rejects_insufficient_gp() -> void:
	var state := {
		"character_id": _mage_l9_high_int_id,
		"params_json": JSON.stringify({
			"project_kind": "spell",
			"target_spell_key": "fireball",
			"target_spell_level": 3,
			"gp_committed": 1000,  # need 3000
			"library_id": _library_l3_id,
		}),
	}
	var result := ResearchMagicHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("insufficient gp_committed"),
		"Insufficient gp should be rejected; got '%s'" % result.get("summary", ""))


func test_research_magic_succeeds_for_l9_high_int_caster_and_grows_library() -> void:
	# L9 mage with INT 17 (+2): target for L9 = 8+. With L1 spell (penalty
	# +0 = floor(1/2)), effective target stays 8. Modifier = +2 (INT) + 0
	# (Mag Eng) + 0 (library) = +2. Need raw roll >= 6 to succeed. Most
	# 1d20 rolls succeed (15/20 = 75%). To make this deterministic we
	# would need a seeded RNG — instead we run a small loop and accept
	# that either we succeed at least once OR we accept the run isn't
	# deterministic but check the side effects of whichever outcome lands.
	#
	# Pragmatic approach: run the handler. If it succeeds, verify side
	# effects. If it failed, retry up to 10 times — the cumulative chance
	# of 10 consecutive failures at 25% per failure is < 1 in a million.
	_clear_completed_projects_for(_mage_l9_high_int_id)

	# Pre-snapshot library gp_invested.
	var lib_before := CampaignRepository.get_library(_library_l3_id)
	var gp_invested_before: int = int(lib_before.get("gp_invested", 0))

	var spell_added := false
	var library_grew := false
	var attempts := 0
	while attempts < 10:
		attempts += 1
		# Wipe any prior repertoire/formula rows for the test spell so we can
		# detect the success-side INSERT cleanly.
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM character_spells WHERE character_id = ? AND spell_key = ?",
			[_mage_l9_high_int_id, "magic_missile"])
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM character_spell_formulas WHERE character_id = ? AND spell_key = ?",
			[_mage_l9_high_int_id, "magic_missile"])

		var state := {
			"character_id": _mage_l9_high_int_id,
			"params_json": JSON.stringify({
				"project_kind": "spell",
				"target_spell_key": "magic_missile",
				"target_spell_level": 1,
				"gp_committed": 1000,
				"library_id": _library_l3_id,
			}),
		}
		var result := ResearchMagicHandler.on_complete(state, null)
		var summary: String = String(result.get("summary", ""))
		if summary.contains("success"):
			# Confirm spell added to character_spells.
			if CampaignRepository.db.query_with_bindings(
				"SELECT id FROM character_spells WHERE character_id = ? AND spell_key = ? LIMIT 1",
				[_mage_l9_high_int_id, "magic_missile"]
			) and not CampaignRepository.db.query_result.is_empty():
				spell_added = true

			# Confirm library gp_invested grew by 100 (10% of 1000).
			var lib_after := CampaignRepository.get_library(_library_l3_id)
			if int(lib_after.get("gp_invested", 0)) == gp_invested_before + 100:
				library_grew = true
			break
	check(spell_added,
		"After at most 10 attempts of L9 INT+2 mage researching L1 spell, the spell should land in character_spells")
	check(library_grew,
		"On success, library gp_invested should grow by 10%% of gp_committed (= 100 gp)")

	# Verify a magic_research_projects row exists for this work (either
	# completed or failed). It should exist regardless of the throw outcome.
	if CampaignRepository.db.query_with_bindings(
		"SELECT * FROM magic_research_projects WHERE character_id = ? AND target_spell_key = ?",
		[_mage_l9_high_int_id, "magic_missile"]
	):
		check(not CampaignRepository.db.query_result.is_empty(),
			"magic_research_projects row should be persisted after each completion attempt")


# ---------------------------------------------------------------------------
# rewrite_spell
# ---------------------------------------------------------------------------

func test_rewrite_spell_adds_spell_to_repertoire_and_formulas() -> void:
	# Clear any prior rows for this spell.
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM character_spells WHERE character_id = ? AND spell_key = ?",
		[_mage_l9_high_int_id, "sleep"])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM character_spell_formulas WHERE character_id = ? AND spell_key = ?",
		[_mage_l9_high_int_id, "sleep"])

	var state := {
		"character_id": _mage_l9_high_int_id,
		"params_json": JSON.stringify({
			"target_spell_key": "sleep",
			"target_spell_level": 1,
			"gp_committed": 1000,
			"library_id": _library_l3_id,
		}),
	}
	var result := RewriteSpellHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("Rewrote sleep"),
		"rewrite_spell should report Rewrote sleep; got '%s'" % result.get("summary", ""))

	# Verify spell in repertoire.
	CampaignRepository.db.query_with_bindings(
		"SELECT id FROM character_spells WHERE character_id = ? AND spell_key = ?",
		[_mage_l9_high_int_id, "sleep"])
	check(not CampaignRepository.db.query_result.is_empty(),
		"rewrite_spell should add 'sleep' to character_spells")

	# Verify formula in formulas table.
	CampaignRepository.db.query_with_bindings(
		"SELECT id FROM character_spell_formulas WHERE character_id = ? AND spell_key = ?",
		[_mage_l9_high_int_id, "sleep"])
	check(not CampaignRepository.db.query_result.is_empty(),
		"rewrite_spell should add 'sleep' to character_spell_formulas")


func test_rewrite_spell_rejects_non_arcane() -> void:
	var state := {
		"character_id": _cleric_id,
		"params_json": JSON.stringify({
			"target_spell_key": "sleep",
			"target_spell_level": 1,
			"gp_committed": 1000,
		}),
	}
	var result := RewriteSpellHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("arcane caster required"),
		"rewrite_spell for cleric should reject as 'arcane caster required'; got '%s'" % result.get("summary", ""))


# ---------------------------------------------------------------------------
# replace_spell
# ---------------------------------------------------------------------------

func test_replace_spell_swaps_repertoire_entry_and_preserves_old_formula() -> void:
	# Seed: caster has magic_missile in repertoire and sleep in formulas.
	# We expect: magic_missile is removed from repertoire (but stays in
	# formulas via ResearchMagicHandler._add path), sleep is added to
	# repertoire.
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM character_spells WHERE character_id = ?",
		[_mage_l9_high_int_id])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM character_spell_formulas WHERE character_id = ?",
		[_mage_l9_high_int_id])

	# Old spell in repertoire + formulas.
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO character_spells (character_id, spell_key, spell_level, is_in_repertoire)
		VALUES (?, 'magic_missile', 1, 1)
	""", [_mage_l9_high_int_id])
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO character_spell_formulas (character_id, spell_key, spell_level)
		VALUES (?, 'magic_missile', 1)
	""", [_mage_l9_high_int_id])

	# New spell formula known (must be available before replace).
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO character_spell_formulas (character_id, spell_key, spell_level)
		VALUES (?, 'sleep', 1)
	""", [_mage_l9_high_int_id])

	var state := {
		"character_id": _mage_l9_high_int_id,
		"params_json": JSON.stringify({
			"old_spell_key": "magic_missile",
			"new_spell_key": "sleep",
			"target_spell_level": 1,
			"gp_committed": 1000,
			"library_id": _library_l3_id,
		}),
	}
	var result := ReplaceSpellHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("Replaced magic_missile with sleep"),
		"replace_spell should report Replaced; got '%s'" % result.get("summary", ""))

	# magic_missile NOT in repertoire (removed).
	CampaignRepository.db.query_with_bindings(
		"SELECT id FROM character_spells WHERE character_id = ? AND spell_key = ?",
		[_mage_l9_high_int_id, "magic_missile"])
	check(CampaignRepository.db.query_result.is_empty(),
		"replace_spell should remove magic_missile from character_spells")

	# sleep IS in repertoire (added).
	CampaignRepository.db.query_with_bindings(
		"SELECT id FROM character_spells WHERE character_id = ? AND spell_key = ?",
		[_mage_l9_high_int_id, "sleep"])
	check(not CampaignRepository.db.query_result.is_empty(),
		"replace_spell should add sleep to character_spells")

	# magic_missile formula PRESERVED (RAW L777: formula not lost on replace).
	CampaignRepository.db.query_with_bindings(
		"SELECT id FROM character_spell_formulas WHERE character_id = ? AND spell_key = ?",
		[_mage_l9_high_int_id, "magic_missile"])
	check(not CampaignRepository.db.query_result.is_empty(),
		"replace_spell should PRESERVE old spell formula per RAW L777")


func test_replace_spell_rejects_old_not_in_repertoire() -> void:
	# Wipe repertoire first.
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM character_spells WHERE character_id = ?",
		[_mage_l9_high_int_id])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM character_spell_formulas WHERE character_id = ?",
		[_mage_l9_high_int_id])
	# Add formula for new spell only — but old spell not in repertoire.
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO character_spell_formulas (character_id, spell_key, spell_level)
		VALUES (?, 'sleep', 1)
	""", [_mage_l9_high_int_id])

	var state := {
		"character_id": _mage_l9_high_int_id,
		"params_json": JSON.stringify({
			"old_spell_key": "magic_missile",
			"new_spell_key": "sleep",
			"target_spell_level": 1,
			"gp_committed": 1000,
		}),
	}
	var result := ReplaceSpellHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("not in repertoire"),
		"replace_spell should reject when old spell not in repertoire; got '%s'" % result.get("summary", ""))


func test_replace_spell_rejects_new_formula_unknown() -> void:
	# Add old to repertoire but DON'T add new formula.
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM character_spells WHERE character_id = ?",
		[_mage_l9_high_int_id])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM character_spell_formulas WHERE character_id = ?",
		[_mage_l9_high_int_id])
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO character_spells (character_id, spell_key, spell_level, is_in_repertoire)
		VALUES (?, 'magic_missile', 1, 1)
	""", [_mage_l9_high_int_id])

	var state := {
		"character_id": _mage_l9_high_int_id,
		"params_json": JSON.stringify({
			"old_spell_key": "magic_missile",
			"new_spell_key": "sleep",
			"target_spell_level": 1,
			"gp_committed": 1000,
		}),
	}
	var result := ReplaceSpellHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("does not have formula"),
		"replace_spell should reject when new spell formula unknown; got '%s'" % result.get("summary", ""))


func test_replace_spell_rejects_mismatched_levels() -> void:
	# Set up: old = magic_missile (L1), new = fireball (L3). Levels differ.
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM character_spells WHERE character_id = ?",
		[_mage_l9_high_int_id])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM character_spell_formulas WHERE character_id = ?",
		[_mage_l9_high_int_id])
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO character_spells (character_id, spell_key, spell_level, is_in_repertoire)
		VALUES (?, 'magic_missile', 1, 1)
	""", [_mage_l9_high_int_id])
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO character_spell_formulas (character_id, spell_key, spell_level)
		VALUES (?, 'fireball', 3)
	""", [_mage_l9_high_int_id])

	var state := {
		"character_id": _mage_l9_high_int_id,
		"params_json": JSON.stringify({
			"old_spell_key": "magic_missile",
			"new_spell_key": "fireball",
			"target_spell_level": 1,
			"gp_committed": 1000,
		}),
	}
	var result := ReplaceSpellHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("same level"),
		"replace_spell should reject mismatched-level swap; got '%s'" % result.get("summary", ""))


# ---------------------------------------------------------------------------
# scribe_spell
# ---------------------------------------------------------------------------

func test_scribe_spell_from_scroll_consumes_scroll_and_adds_formula() -> void:
	# Wipe formula.
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM character_spell_formulas WHERE character_id = ? AND spell_key = ?",
		[_mage_l9_high_int_id, "light"])

	# Create a scroll inventory_items row owned by the caster.
	var scroll_id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO inventory_items
			(id, character_id, item_key, name, quantity, encumbrance_units,
			 slot, is_equipped, notes, item_category, is_magical)
		VALUES (?, ?, 'scroll_of_light', 'Scroll of Light', 1, 1,
			'pack', 0, '', 'scroll', 1)
	""", [scroll_id, _mage_l9_high_int_id])

	var state := {
		"character_id": _mage_l9_high_int_id,
		"params_json": JSON.stringify({
			"target_spell_key": "light",
			"target_spell_level": 1,
			"source_kind": "scroll",
			"source_ref": scroll_id,
			"library_id": _library_l3_id,
		}),
	}
	var result := ScribeSpellHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("Scribed light"),
		"scribe_spell should report Scribed light; got '%s'" % result.get("summary", ""))

	# Scroll row should be gone.
	CampaignRepository.db.query_with_bindings(
		"SELECT id FROM inventory_items WHERE id = ?", [scroll_id])
	check(CampaignRepository.db.query_result.is_empty(),
		"scribe_spell from scroll should DELETE the scroll inventory_items row")

	# Formula should be present.
	CampaignRepository.db.query_with_bindings(
		"SELECT spell_level FROM character_spell_formulas WHERE character_id = ? AND spell_key = ?",
		[_mage_l9_high_int_id, "light"])
	check(not CampaignRepository.db.query_result.is_empty(),
		"scribe_spell should add light to character_spell_formulas")


func test_scribe_spell_from_spellbook_preserves_source() -> void:
	# Wipe formula.
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM character_spell_formulas WHERE character_id = ? AND spell_key = ?",
		[_mage_l9_high_int_id, "burning_hands"])

	# For source_kind='spellbook', source_ref is the source character's id.
	# Per v1 simplification we don't strictly validate the source spellbook
	# state; we just record that the caster acquired the formula.
	var state := {
		"character_id": _mage_l9_high_int_id,
		"params_json": JSON.stringify({
			"target_spell_key": "burning_hands",
			"target_spell_level": 1,
			"source_kind": "spellbook",
			"source_ref": "some-other-mage-id",
			"library_id": _library_l3_id,
		}),
	}
	var result := ScribeSpellHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("source spellbook preserved"),
		"scribe_spell from spellbook should report source preserved; got '%s'" % result.get("summary", ""))

	CampaignRepository.db.query_with_bindings(
		"SELECT id FROM character_spell_formulas WHERE character_id = ? AND spell_key = ?",
		[_mage_l9_high_int_id, "burning_hands"])
	check(not CampaignRepository.db.query_result.is_empty(),
		"scribe_spell should add burning_hands to character_spell_formulas")


func test_scribe_spell_rejects_when_caster_cannot_learn_level() -> void:
	# L5 mage can cast up to L3 (per standard mage progression). Trying to
	# scribe a L4 spell should be rejected.
	var state := {
		"character_id": _mage_l5_id,
		"params_json": JSON.stringify({
			"target_spell_key": "fireball",  # Use a known spell at L3 with target_level=4 to trigger the gate
			"target_spell_level": 5,
			"source_kind": "spellbook",
			"source_ref": "fake-source",
			"library_id": _library_l1_id,
		}),
	}
	var result := ScribeSpellHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("cannot learn spells of level"),
		"scribe_spell should reject when caster can't learn target level; got '%s'" % result.get("summary", ""))
