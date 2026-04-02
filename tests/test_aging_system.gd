extends Node

## Unit tests for AgingSystem.
## Source rules: acore_aging_poisons_high-level-start_optional_rules.xml, pc_aging_tables.xml.


func run_all_tests() -> void:
	test_starting_age_range_fighter()
	test_starting_age_range_elf()
	test_age_category_human_boundaries()
	test_age_category_elf_capped()
	test_category_transition_adjustments_adult_to_middle_aged()
	test_ability_floor_clamping()
	test_death_from_age_trigger_max()
	test_death_from_age_no_trigger()
	test_next_category_age_human()
	test_no_adjustment_for_same_category()
	print("AgingSystem: all tests passed.")


func _make_human_adult() -> CharacterData:
	var c := CharacterData.new()
	c.id = "test_human"
	c.race = "human"
	c.character_class = "fighter"
	c.current_age = 25
	c.age_category = "adult"
	c.strength = 12
	c.intelligence = 10
	c.wisdom = 10
	c.dexterity = 12
	c.constitution = 12
	c.charisma = 10
	return c


func test_starting_age_range_fighter() -> void:
	## Fighter starting age formula: 15+1d8. Range: [16, 23].
	var aging := AgingSystem.new()
	# Roll 10 times to verify range (deterministic die faces via override aren't needed here
	# since we just verify the bounds from the formula, not a specific roll).
	var expr := aging.get_starting_age_expression("fighter")
	assert(expr == "15+1d8",
		"Fighter starting age expression: expected '15+1d8', got '%s'" % expr)
	# Roll and verify result is in [16, 23].
	var age := aging.roll_starting_age("fighter")
	assert(age >= 16 and age <= 23,
		"Fighter starting age should be in [16, 23], got %d" % age)
	print("  starting_age_range_fighter: OK")


func test_starting_age_range_elf() -> void:
	## Elf Spellsword: 75+5d4. Range: [80, 95].
	var aging := AgingSystem.new()
	var expr := aging.get_starting_age_expression("elf_spellsword")
	assert(expr == "75+5d4",
		"Elf spellsword starting age expression: expected '75+5d4', got '%s'" % expr)
	var age := aging.roll_starting_age("elf_spellsword")
	assert(age >= 80 and age <= 95,
		"Elf Spellsword starting age should be in [80, 95], got %d" % age)
	print("  starting_age_range_elf: OK")


func test_age_category_human_boundaries() -> void:
	## Human age categories per ACKS rules.
	var aging := AgingSystem.new()
	# Youth: 13-17
	assert(aging.get_age_category("human", 13) == "youth",  "age 13: expected youth")
	assert(aging.get_age_category("human", 17) == "youth",  "age 17: expected youth")
	# Adult: 18-35
	assert(aging.get_age_category("human", 18) == "adult",  "age 18: expected adult")
	assert(aging.get_age_category("human", 35) == "adult",  "age 35: expected adult")
	# Middle aged: 36-55
	assert(aging.get_age_category("human", 36) == "middle_aged", "age 36: expected middle_aged")
	assert(aging.get_age_category("human", 55) == "middle_aged", "age 55: expected middle_aged")
	# Old: 56-75
	assert(aging.get_age_category("human", 56) == "old",    "age 56: expected old")
	assert(aging.get_age_category("human", 75) == "old",    "age 75: expected old")
	# Ancient: 76-95
	assert(aging.get_age_category("human", 76) == "ancient","age 76: expected ancient")
	assert(aging.get_age_category("human", 95) == "ancient","age 95: expected ancient")
	print("  age_category_human_boundaries: OK")


func test_age_category_elf_capped() -> void:
	## Elves have only youth (15-50) and adult (51-200). No middle_aged, old, or ancient.
	var aging := AgingSystem.new()
	assert(aging.get_age_category("elf", 51)  == "adult", "elf age 51: expected adult")
	assert(aging.get_age_category("elf", 100) == "adult", "elf age 100: expected adult")
	assert(aging.get_age_category("elf", 200) == "adult", "elf age 200: expected adult")
	# Ages beyond 200 should also return adult (table max for elf adult is 200, no further cats).
	var cat_500 := aging.get_age_category("elf", 500)
	assert(cat_500 == "adult", "elf age 500: expected adult, got '%s'" % cat_500)
	print("  age_category_elf_capped: OK")


func test_category_transition_adjustments_adult_to_middle_aged() -> void:
	## Human adult → middle_aged: STR -2, DEX -2, CON -2.
	var c := _make_human_adult()
	var str_before := c.strength   # 12
	var dex_before := c.dexterity  # 12
	var con_before := c.constitution  # 12
	var int_before := c.intelligence  # 10
	var wis_before := c.wisdom       # 10

	var aging := AgingSystem.new()
	# Age the character from 35 (adult) to 36 (middle_aged).
	c.current_age = 35
	c.age_category = "adult"
	var result := aging.apply_age_change(c, 1)

	assert(result.get("category_changed", false),
		"Category should have changed from adult to middle_aged")
	assert(c.age_category == "middle_aged",
		"Expected middle_aged, got '%s'" % c.age_category)
	assert(c.strength == str_before - 2,
		"STR: expected %d, got %d" % [str_before - 2, c.strength])
	assert(c.dexterity == dex_before - 2,
		"DEX: expected %d, got %d" % [dex_before - 2, c.dexterity])
	assert(c.constitution == con_before - 2,
		"CON: expected %d, got %d" % [con_before - 2, c.constitution])
	# INT and WIS should NOT change on adult→middle_aged transition.
	assert(c.intelligence == int_before, "INT should not change on adult->middle_aged")
	assert(c.wisdom == wis_before, "WIS should not change on adult->middle_aged")
	print("  category_transition_adjustments_adult_to_middle_aged: OK")


func test_ability_floor_clamping() -> void:
	## STR floor for fighter prime req = 9. Starting at 10, two -2 transitions brings to 8.
	## But floor is 9 for prime req, so should clamp at 9.
	var c := CharacterData.new()
	c.id = "test_floor"
	c.race = "human"
	c.character_class = "fighter"  # Prime req: STR (min 9)
	c.current_age = 55  # middle_aged
	c.age_category = "middle_aged"
	c.strength = 10  # 10 - 2 (old) = 8, but floor is 9
	c.dexterity = 10
	c.constitution = 10
	c.intelligence = 10
	c.wisdom = 10
	c.charisma = 10

	var aging := AgingSystem.new()
	aging.apply_age_change(c, 1)  # → old (STR -2 attempted)

	# STR can't go below 9 (prime req floor for fighter).
	assert(c.strength >= 9,
		"STR should not drop below 9 (prime req floor), got %d" % c.strength)
	print("  ability_floor_clamping: OK")


func test_death_from_age_trigger_max() -> void:
	## Human at age 95 (max_age=95) should require a death save.
	var c := CharacterData.new()
	c.id = "test_death"
	c.race = "human"
	c.character_class = "fighter"
	c.current_age = 95
	c.age_category = "ancient"
	c.constitution = 10

	var aging := AgingSystem.new()
	var check := aging.check_death_from_age(c)
	assert(check.get("required", false),
		"Death save should be required at max age 95")
	assert(check.get("trigger", "") == "max_age_and_beyond",
		"Trigger should be max_age_and_beyond, got '%s'" % check.get("trigger", ""))
	print("  death_from_age_trigger_max: OK")


func test_death_from_age_no_trigger() -> void:
	## Human at age 30 (well within adult range) should not require a death save.
	var c := CharacterData.new()
	c.id = "test_no_death"
	c.race = "human"
	c.character_class = "fighter"
	c.current_age = 30
	c.age_category = "adult"
	c.constitution = 10

	var aging := AgingSystem.new()
	var check := aging.check_death_from_age(c)
	assert(not check.get("required", false),
		"Death save should NOT be required at age 30")
	print("  death_from_age_no_trigger: OK")


func test_next_category_age_human() -> void:
	## Human adult → middle_aged starts at 36.
	var aging := AgingSystem.new()
	var next := aging.get_next_category_age("human", "adult")
	assert(next == 36, "Human adult next category age: expected 36, got %d" % next)
	## Ancient has no next category.
	var no_next := aging.get_next_category_age("human", "ancient")
	assert(no_next == -1, "Human ancient next category: expected -1, got %d" % no_next)
	print("  next_category_age_human: OK")


func test_no_adjustment_for_same_category() -> void:
	## Aging within the same category (no transition) should not change ability scores.
	var c := _make_human_adult()
	var str_before := c.strength
	c.current_age = 20
	c.age_category = "adult"

	var aging := AgingSystem.new()
	aging.apply_age_change(c, 5)  # 20 → 25, still adult

	assert(c.age_category == "adult", "Should still be adult at age 25")
	assert(c.strength == str_before, "STR should not change within same category")
	print("  no_adjustment_for_same_category: OK")
