extends Node

## Unit tests for CharacterGenerator (PC generation, ability scores, ability trading).
## Run via test_runner.tscn. Uses plain assert() — no external framework.


func run_all_tests() -> void:
	test_ability_score_generation()
	test_pc_generation_fighter()
	test_pc_generation_hp_minimum()
	test_ability_trade_valid()
	test_ability_trade_con_allowed_for_non_prime()
	test_ability_trade_invalid_prime_requisite_source()
	test_ability_trade_invalid_below_9()
	print("CharacterGenerator: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_generator() -> CharacterGenerator:
	return CharacterGenerator.new(ClassRegistry.new(), PowerRegistry.new())


# ---------------------------------------------------------------------------
# Ability score generation
# ---------------------------------------------------------------------------

func test_ability_score_generation() -> void:
	var gen := _make_generator()
	# Roll 10 sets and verify all scores are 3-18
	for i in range(10):
		var result := gen.roll_ability_scores()
		var scores: Dictionary = result.scores
		assert(scores.size() == 6,
			"should generate 6 ability scores, got %d" % scores.size())
		for ability in ["STR", "INT", "WIS", "DEX", "CON", "CHA"]:
			assert(scores.has(ability),
				"scores should include %s" % ability)
			var val: int = int(scores[ability])
			assert(val >= 3 and val <= 18,
				"%s score %d out of range [3, 18]" % [ability, val])
	print("  ability_score_generation: OK (10 sets validated)")


# ---------------------------------------------------------------------------
# PC generation — Fighter
# ---------------------------------------------------------------------------

func test_pc_generation_fighter() -> void:
	var gen := _make_generator()
	var scores := {"STR": 14, "INT": 10, "WIS": 10, "DEX": 12, "CON": 13, "CHA": 11}
	var campaign_id := "test_campaign_001"
	var character := gen.generate_pc("fighter", scores, campaign_id)

	assert(character != null, "generate_pc should return a CharacterData")
	assert(character.character_class == "fighter",
		"class should be 'fighter'")
	assert(character.combat_progression == "fighter",
		"combat_progression should be 'fighter'")
	assert(character.hit_die_type == "1d8",
		"hit_die_type should be '1d8'")
	assert(character.max_level == 14,
		"max_level should be 14")
	assert(character.level == 1,
		"level should be 1")
	assert(character.xp == 0,
		"starting XP should be 0")
	assert(character.character_type == "pc",
		"character_type should be 'pc'")
	assert(character.race == "human",
		"race should be 'human'")
	assert(character.strength == 14,
		"STR should be 14")
	assert(character.constitution == 13,
		"CON should be 13")
	# Attack throw at level 1 for fighter is 10
	assert(character.attack_throw == 10,
		"fighter L1 attack throw should be 10, got %d" % character.attack_throw)
	# XP for next level (fighter L2 = 2000)
	assert(character.xp_for_next_level == 2000,
		"fighter xp_for_next_level should be 2000")
	# Title at level 1
	assert(character.title == "Man-at-Arms",
		"fighter L1 title should be 'Man-at-Arms', got '%s'" % character.title)
	# ID and campaign_id should be set
	assert(not character.id.is_empty(), "character ID should not be empty")
	assert(character.campaign_id == campaign_id,
		"campaign_id should match")
	print("  pc_generation_fighter: OK")


# ---------------------------------------------------------------------------
# PC generation — HP minimum 1
# ---------------------------------------------------------------------------

func test_pc_generation_hp_minimum() -> void:
	var gen := _make_generator()
	# CON 3 gives -3 modifier. Even with d4 rolling 1, HP should be minimum 1.
	var scores := {"STR": 10, "INT": 10, "WIS": 10, "DEX": 10, "CON": 3, "CHA": 10}
	# Generate multiple characters to test the minimum HP floor
	for i in range(20):
		var character := gen.generate_pc("mage", scores, "test_hp_min")
		assert(character != null, "generate_pc should not return null")
		assert(character.hp_max >= 1,
			"hp_max should be >= 1 even with CON 3 (-3 mod), got %d" % character.hp_max)
	print("  pc_generation_hp_minimum: OK (20 characters verified)")


# ---------------------------------------------------------------------------
# Ability score trading — valid trade
# ---------------------------------------------------------------------------

func test_ability_trade_valid() -> void:
	var gen := _make_generator()
	var scores := {"STR": 16, "INT": 12, "WIS": 10, "DEX": 10, "CON": 10, "CHA": 10}
	# Fighter prime requisite is STR. Trade 2 from INT to STR.
	var result := gen.apply_ability_trade(scores, "fighter", "INT", "STR", 2)
	assert(not result.is_empty(), "valid trade should return non-empty dictionary")
	assert(int(result["INT"]) == 10,
		"INT should drop by 2: 12 -> 10, got %d" % int(result["INT"]))
	assert(int(result["STR"]) == 17,
		"STR should increase by 1: 16 -> 17, got %d" % int(result["STR"]))
	# Other scores should be unchanged
	assert(int(result["WIS"]) == 10, "WIS should be unchanged")
	assert(int(result["CON"]) == 10, "CON should be unchanged")
	print("  ability_trade_valid: OK")


# ---------------------------------------------------------------------------
# Ability score trading — CON/CHA allowed when not prime requisite (ACKS RAW)
# ---------------------------------------------------------------------------

func test_ability_trade_con_allowed_for_non_prime() -> void:
	var gen := _make_generator()
	# Fighter prime req is STR only. CON and CHA are NOT prime reqs, so they CAN be traded.
	var scores := {"STR": 10, "INT": 10, "WIS": 10, "DEX": 10, "CON": 14, "CHA": 11}
	# Trade 2 from CON (14→12) to raise STR (10→11) — valid for Fighter
	var result := gen.apply_ability_trade(scores, "fighter", "CON", "STR", 2)
	assert(not result.is_empty(),
		"trading from CON should succeed for Fighter (CON is not Fighter's prime req)")
	assert(int(result["CON"]) == 12, "CON should drop from 14 to 12, got %d" % int(result["CON"]))
	assert(int(result["STR"]) == 11, "STR should rise from 10 to 11, got %d" % int(result["STR"]))

	# Trade 2 from CHA (11→9) to raise STR (11→12) — also valid
	var result2 := gen.apply_ability_trade(result, "fighter", "CHA", "STR", 2)
	assert(not result2.is_empty(),
		"trading from CHA should succeed for Fighter (CHA is not Fighter's prime req)")
	assert(int(result2["CHA"]) == 9, "CHA should drop from 11 to 9")
	assert(int(result2["STR"]) == 12, "STR should rise from 11 to 12")
	print("  ability_trade_con_allowed_for_non_prime: OK")


# ---------------------------------------------------------------------------
# Ability score trading — cannot trade from a prime requisite source
# ---------------------------------------------------------------------------

func test_ability_trade_invalid_prime_requisite_source() -> void:
	var gen := _make_generator()
	# Mage prime req is INT. Cannot trade from INT to raise INT.
	var scores := {"STR": 10, "INT": 14, "WIS": 10, "DEX": 10, "CON": 10, "CHA": 10}
	var result := gen.apply_ability_trade(scores, "mage", "INT", "INT", 2)
	assert(result.is_empty(),
		"trading from a prime requisite should return empty dict (invalid)")
	print("  ability_trade_invalid_prime_requisite_source: OK")


# ---------------------------------------------------------------------------
# Ability score trading — cannot reduce below 9
# ---------------------------------------------------------------------------

func test_ability_trade_invalid_below_9() -> void:
	var gen := _make_generator()
	var scores := {"STR": 10, "INT": 10, "WIS": 10, "DEX": 10, "CON": 10, "CHA": 10}
	# Trading 2 from INT would drop it to 8 — below the 9 minimum
	var result := gen.apply_ability_trade(scores, "fighter", "INT", "STR", 2)
	assert(result.is_empty(),
		"trade that would reduce INT below 9 should return empty dict (invalid)")

	# Trading 4 from INT 12 would drop to 8 — also invalid
	var scores2 := {"STR": 10, "INT": 12, "WIS": 10, "DEX": 10, "CON": 10, "CHA": 10}
	var result2 := gen.apply_ability_trade(scores2, "fighter", "INT", "STR", 4)
	assert(result2.is_empty(),
		"trade dropping INT from 12 to 8 should return empty dict (invalid)")
	print("  ability_trade_invalid_below_9: OK")
