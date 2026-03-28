extends Node

## Unit tests for AbilityUtils and CharacterData.ability_modifier().
## Run via test_runner.tscn. Uses plain assert() — no external framework.


func run_all_tests() -> void:
	test_modifier_table()
	test_xp_adjustment_single_prime()
	test_xp_adjustment_multiple_primes()
	test_max_henchmen()
	test_languages_bonus()
	print("AbilityUtils: all tests passed.")


# ---------------------------------------------------------------------------
# Ability modifier table (CharacterData.ability_modifier)
# ---------------------------------------------------------------------------

func test_modifier_table() -> void:
	# ACKS modifier table: score -> modifier
	# 3: -3, 4-5: -2, 6-8: -1, 9-12: 0, 13-15: +1, 16-17: +2, 18: +3
	var expected := {
		3: -3,
		4: -2, 5: -2,
		6: -1, 7: -1, 8: -1,
		9: 0, 10: 0, 11: 0, 12: 0,
		13: 1, 14: 1, 15: 1,
		16: 2, 17: 2,
		18: 3,
	}
	for score in range(3, 19):
		var mod := CharacterData.ability_modifier(score)
		assert(mod == expected[score],
			"ability_modifier(%d) should be %d, got %d" % [score, expected[score], mod])
	print("  modifier_table: OK")


# ---------------------------------------------------------------------------
# XP adjustment from prime requisites
# ---------------------------------------------------------------------------

func test_xp_adjustment_single_prime() -> void:
	# Score 16+ -> +10%, 13-15 -> +5%, 9-12 -> 0%, 6-8 -> -5%, 3-5 -> -10%
	assert(AbilityUtils.get_xp_adjustment([16]) == 10,
		"single prime 16 should give +10%")
	assert(AbilityUtils.get_xp_adjustment([13]) == 5,
		"single prime 13 should give +5%")
	assert(AbilityUtils.get_xp_adjustment([10]) == 0,
		"single prime 10 should give 0%")
	assert(AbilityUtils.get_xp_adjustment([5]) == -10,
		"single prime 5 should give -10%")
	assert(AbilityUtils.get_xp_adjustment([8]) == -5,
		"single prime 8 should give -5%")
	print("  xp_adjustment_single_prime: OK")


func test_xp_adjustment_multiple_primes() -> void:
	# Uses the LOWEST prime requisite score
	assert(AbilityUtils.get_xp_adjustment([16, 10]) == 0,
		"[16, 10] should use lowest (10) -> 0%")
	assert(AbilityUtils.get_xp_adjustment([13, 15]) == 5,
		"[13, 15] should use lowest (13) -> +5%")
	assert(AbilityUtils.get_xp_adjustment([18, 18]) == 10,
		"[18, 18] should give +10%")
	assert(AbilityUtils.get_xp_adjustment([16, 5]) == -10,
		"[16, 5] should use lowest (5) -> -10%")
	print("  xp_adjustment_multiple_primes: OK")


# ---------------------------------------------------------------------------
# Max henchmen (CHA-based)
# ---------------------------------------------------------------------------

func test_max_henchmen() -> void:
	# Formula: 4 + CHA modifier, clamped [1, 7]
	# CHA 3 -> mod -3 -> 4+(-3)=1
	assert(AbilityUtils.get_max_henchmen(3) == 1,
		"CHA 3 -> 1 henchman")
	# CHA 10 -> mod 0 -> 4+0=4
	assert(AbilityUtils.get_max_henchmen(10) == 4,
		"CHA 10 -> 4 henchmen")
	# CHA 18 -> mod +3 -> 4+3=7
	assert(AbilityUtils.get_max_henchmen(18) == 7,
		"CHA 18 -> 7 henchmen")
	# CHA 13 -> mod +1 -> 4+1=5
	assert(AbilityUtils.get_max_henchmen(13) == 5,
		"CHA 13 -> 5 henchmen")
	# CHA 6 -> mod -1 -> 4+(-1)=3
	assert(AbilityUtils.get_max_henchmen(6) == 3,
		"CHA 6 -> 3 henchmen")
	print("  max_henchmen: OK")


# ---------------------------------------------------------------------------
# Languages bonus (INT-based)
# ---------------------------------------------------------------------------

func test_languages_bonus() -> void:
	# INT modifier, minimum 0
	# INT 3 -> mod -3 -> clamped to 0
	assert(AbilityUtils.get_languages_bonus(3) == 0,
		"INT 3 -> 0 bonus languages (min 0)")
	# INT 10 -> mod 0 -> 0
	assert(AbilityUtils.get_languages_bonus(10) == 0,
		"INT 10 -> 0 bonus languages")
	# INT 13 -> mod +1 -> 1
	assert(AbilityUtils.get_languages_bonus(13) == 1,
		"INT 13 -> 1 bonus language")
	# INT 18 -> mod +3 -> 3
	assert(AbilityUtils.get_languages_bonus(18) == 3,
		"INT 18 -> 3 bonus languages")
	# INT 8 -> mod -1 -> clamped to 0
	assert(AbilityUtils.get_languages_bonus(8) == 0,
		"INT 8 -> 0 bonus languages (min 0)")
	print("  languages_bonus: OK")
