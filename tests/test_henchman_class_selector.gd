extends "res://tests/test_suite_base.gd"

## Tests for HenchmanClassSelector — the 3-layer decision rule that picks a
## 1st-level class for a Normal Man henchman when they hit 100 XP.
##
## Stages (deterministic):
##   1. Prime requisite score (highest sum of (score - 9) wins)
##   2. Proficiency overlap with class_proficiency_list (highest count wins)
##   3. Patron's combat_progression match (match wins)
##   4. Alphabetical (deterministic fallback)


func run_all_tests() -> void:
	test_str15_picks_fighter()
	test_int16_picks_mage()
	test_wis15_picks_cleric()
	test_dex15_picks_thief()
	test_tied_stats_with_lockpicking_picks_thief()
	test_tied_stats_no_profs_with_cleric_patron_picks_cleric()
	test_tied_stats_no_profs_no_patron_falls_back_alphabetical()
	test_all_eights_falls_back_to_fighter()
	test_determinism_repeated_calls_same_result()
	test_orphan_no_patron_uses_alphabetical()
	test_score_breakdown_populated()
	test_narrative_hint_non_empty()
	if not has_failures():
		print("HenchmanClassSelector: all tests passed.")


# ---------------------------------------------------------------------------
# Test fixtures
# ---------------------------------------------------------------------------

func _make_nm(scores: Dictionary, profs: Array = []) -> CharacterData:
	var nm := CharacterData.new()
	nm.id = "nm_test_id"
	nm.name = "Test NM"
	nm.character_type = "henchman"
	nm.character_class = "normal_man"
	nm.level = 0
	nm.strength = int(scores.get("STR", 10))
	nm.intelligence = int(scores.get("INT", 10))
	nm.wisdom = int(scores.get("WIS", 10))
	nm.dexterity = int(scores.get("DEX", 10))
	nm.constitution = int(scores.get("CON", 10))
	nm.charisma = int(scores.get("CHA", 10))
	nm.proficiencies = profs
	return nm


func _make_patron(progression: String) -> CharacterData:
	var patron := CharacterData.new()
	patron.id = "patron_test_id"
	patron.name = "Test Patron"
	patron.character_type = "pc"
	patron.character_class = progression  # convenience
	patron.combat_progression = progression
	patron.level = 1
	return patron


# ---------------------------------------------------------------------------
# Stage 1: Prime requisite score
# ---------------------------------------------------------------------------

func test_str15_picks_fighter() -> void:
	var reg := ClassRegistry.new()
	var nm := _make_nm({"STR": 15, "INT": 9, "WIS": 9, "DEX": 9, "CON": 10, "CHA": 10})
	var patron := _make_patron("mage")  # patron progression should NOT override stage-1
	var result := HenchmanClassSelector.select_class_for_normal_man(nm, patron, reg)
	check(result["selected_class"] == "fighter",
		"STR-15 NM should pick fighter, got %s" % result["selected_class"])


func test_int16_picks_mage() -> void:
	var reg := ClassRegistry.new()
	var nm := _make_nm({"STR": 10, "INT": 16, "WIS": 10, "DEX": 10, "CON": 10, "CHA": 10})
	var patron := _make_patron("fighter")
	var result := HenchmanClassSelector.select_class_for_normal_man(nm, patron, reg)
	check(result["selected_class"] == "mage",
		"INT-16 NM should pick mage, got %s" % result["selected_class"])


func test_wis15_picks_cleric() -> void:
	var reg := ClassRegistry.new()
	var nm := _make_nm({"STR": 9, "INT": 9, "WIS": 15, "DEX": 9, "CON": 10, "CHA": 10})
	var patron := _make_patron("fighter")
	var result := HenchmanClassSelector.select_class_for_normal_man(nm, patron, reg)
	check(result["selected_class"] == "cleric",
		"WIS-15 NM should pick cleric, got %s" % result["selected_class"])


func test_dex15_picks_thief() -> void:
	var reg := ClassRegistry.new()
	var nm := _make_nm({"STR": 9, "INT": 9, "WIS": 9, "DEX": 15, "CON": 10, "CHA": 10})
	var patron := _make_patron("fighter")
	var result := HenchmanClassSelector.select_class_for_normal_man(nm, patron, reg)
	check(result["selected_class"] == "thief",
		"DEX-15 NM should pick thief, got %s" % result["selected_class"])


# ---------------------------------------------------------------------------
# Stage 2: Proficiency overlap tiebreak
# ---------------------------------------------------------------------------

func test_tied_stats_with_lockpicking_picks_thief() -> void:
	var reg := ClassRegistry.new()
	var nm := _make_nm(
		{"STR": 10, "INT": 10, "WIS": 10, "DEX": 10, "CON": 10, "CHA": 10},
		[{"proficiency_key": "lockpicking", "rank": 1, "slot_type": "general",
			"selections_count": 1, "specialization": ""}])
	var patron := _make_patron("fighter")
	var result := HenchmanClassSelector.select_class_for_normal_man(nm, patron, reg)
	check(result["selected_class"] == "thief",
		"Stage-1-tied NM with Lockpicking should pick thief via Stage 2, got %s" % result["selected_class"])


# ---------------------------------------------------------------------------
# Stage 3: Patron progression match
# ---------------------------------------------------------------------------

func test_tied_stats_no_profs_with_cleric_patron_picks_cleric() -> void:
	var reg := ClassRegistry.new()
	var nm := _make_nm({"STR": 10, "INT": 10, "WIS": 10, "DEX": 10, "CON": 10, "CHA": 10})
	var patron := _make_patron("cleric")
	var result := HenchmanClassSelector.select_class_for_normal_man(nm, patron, reg)
	check(result["selected_class"] == "cleric",
		"All-tied NM with cleric patron should pick cleric via Stage 3, got %s" % result["selected_class"])


# ---------------------------------------------------------------------------
# Stage 4: Alphabetical fallback
# ---------------------------------------------------------------------------

func test_tied_stats_no_profs_no_patron_falls_back_alphabetical() -> void:
	var reg := ClassRegistry.new()
	var nm := _make_nm({"STR": 10, "INT": 10, "WIS": 10, "DEX": 10, "CON": 10, "CHA": 10})
	var result := HenchmanClassSelector.select_class_for_normal_man(nm, null, reg)
	# Alphabetical of [cleric, fighter, mage, thief] → cleric
	check(result["selected_class"] == "cleric",
		"All-tied no-patron NM should fall back alphabetically to cleric, got %s" % result["selected_class"])


# ---------------------------------------------------------------------------
# Eligibility / RAW fallback
# ---------------------------------------------------------------------------

func test_all_eights_falls_back_to_fighter() -> void:
	# All stats below the 9-minimum prime requisite. Cleric/thief/mage all
	# have a prime requisite at 9; fighter has STR 9 too. So... all four
	# fail eligibility. Per the selector's RAW-fallback rule, fighter wins.
	var reg := ClassRegistry.new()
	var nm := _make_nm({"STR": 8, "INT": 8, "WIS": 8, "DEX": 8, "CON": 8, "CHA": 8})
	var result := HenchmanClassSelector.select_class_for_normal_man(nm, null, reg)
	check(result["selected_class"] == "fighter",
		"NM with all stats <9 should fall back to fighter, got %s" % result["selected_class"])


# ---------------------------------------------------------------------------
# Determinism + structure
# ---------------------------------------------------------------------------

func test_determinism_repeated_calls_same_result() -> void:
	var reg := ClassRegistry.new()
	var nm := _make_nm({"STR": 13, "INT": 13, "WIS": 9, "DEX": 9, "CON": 10, "CHA": 10})
	var patron := _make_patron("fighter")
	var first := HenchmanClassSelector.select_class_for_normal_man(nm, patron, reg)
	var second := HenchmanClassSelector.select_class_for_normal_man(nm, patron, reg)
	var third := HenchmanClassSelector.select_class_for_normal_man(nm, patron, reg)
	check(first["selected_class"] == second["selected_class"],
		"selector must be deterministic across calls 1 vs 2")
	check(second["selected_class"] == third["selected_class"],
		"selector must be deterministic across calls 2 vs 3")


func test_orphan_no_patron_uses_alphabetical() -> void:
	# Patron is null (e.g., post-PC-death). Selector must not crash.
	var reg := ClassRegistry.new()
	var nm := _make_nm({"STR": 12, "INT": 12, "WIS": 9, "DEX": 9, "CON": 10, "CHA": 10})
	var result := HenchmanClassSelector.select_class_for_normal_man(nm, null, reg)
	# Stage 1 ties fighter (STR 12 -> +3) and mage (INT 12 -> +3). Stage 2:
	# no profs, no overlap. Stage 3: no patron, no match. Stage 4: alphabetical
	# → fighter wins (fighter < mage).
	check(result["selected_class"] == "fighter",
		"orphan NM with STR=INT tied should fall back alphabetically to fighter, got %s" % result["selected_class"])


func test_score_breakdown_populated() -> void:
	var reg := ClassRegistry.new()
	var nm := _make_nm({"STR": 14, "INT": 9, "WIS": 9, "DEX": 9, "CON": 10, "CHA": 10})
	var patron := _make_patron("fighter")
	var result := HenchmanClassSelector.select_class_for_normal_man(nm, patron, reg)
	var breakdown: Dictionary = result["score_breakdown"]
	check(breakdown.has("fighter"), "breakdown must include fighter")
	check(int(breakdown["fighter"].get("prime_score", -1)) == 5,
		"fighter prime_score should be 14-9=5, got %d" % int(breakdown["fighter"].get("prime_score", -1)))


func test_narrative_hint_non_empty() -> void:
	var reg := ClassRegistry.new()
	var nm := _make_nm({"STR": 13, "INT": 9, "WIS": 9, "DEX": 9, "CON": 10, "CHA": 10})
	var result := HenchmanClassSelector.select_class_for_normal_man(nm, null, reg)
	check(not String(result.get("narrative_hint", "")).is_empty(),
		"narrative_hint should be a non-empty string")
