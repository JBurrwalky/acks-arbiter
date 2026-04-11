extends "res://tests/test_suite_base.gd"

## Unit tests for HandlerEligibility.


func run_all_tests() -> void:
	test_handler_is_tier_1()
	test_beast_friendship_is_tier_1()
	test_animal_training_matching_spec_is_tier_1()
	test_animal_training_wrong_spec_is_not_tier_1()
	test_introduced_handler_is_tier_2()
	test_unknown_handler_is_tier_3()
	test_capacity_proficient_guard()
	test_capacity_introduced_mount()
	test_species_to_specialization_mapping()

	if not has_failures():
		print("HandlerEligibility: all tests passed.")


# --- Helpers ---

func _make_character(id: String = "char_1", profs: Array = []) -> CharacterData:
	var cd := CharacterData.new()
	cd.id = id
	cd.name = "Test Character"
	cd.proficiencies = profs
	return cd


func _make_creature(
		species: String = "dog_war",
		handler: String = "char_1",
		introduced: Array = []) -> TrainedCreatureData:
	var c := TrainedCreatureData.new()
	c.id = "creature_1"
	c.species_id = species
	c.role = "G"
	c.handler_id = handler
	c.introduced_handlers = introduced
	c.monster_data = {"name": "War Dog"}
	return c


func _prof(key: String, spec: String = "") -> Dictionary:
	return {"proficiency_key": key, "specialization": spec, "rank": 1, "slot_type": "general", "selections_count": 1}


# --- Tests ---

func test_handler_is_tier_1() -> void:
	var cd := _make_character("char_1")
	var creature := _make_creature("dog_war", "char_1")
	var tier := HandlerEligibility.get_handler_tier(cd, creature)
	check(tier == HandlerEligibility.Tier.PROFICIENT,
		"primary handler should be Tier 1, got %d" % tier)
	print("  handler_is_tier_1: OK")


func test_beast_friendship_is_tier_1() -> void:
	var cd := _make_character("char_2", [_prof("beast_friendship")])
	var creature := _make_creature("dog_war", "char_1")
	var tier := HandlerEligibility.get_handler_tier(cd, creature)
	check(tier == HandlerEligibility.Tier.PROFICIENT,
		"beast_friendship should grant Tier 1, got %d" % tier)
	print("  beast_friendship_tier_1: OK")


func test_animal_training_matching_spec_is_tier_1() -> void:
	var cd := _make_character("char_2", [_prof("animal_training", "dogs")])
	var creature := _make_creature("dog_war", "char_1")
	var tier := HandlerEligibility.get_handler_tier(cd, creature)
	check(tier == HandlerEligibility.Tier.PROFICIENT,
		"animal_training(dogs) should be Tier 1 for dog_war, got %d" % tier)
	print("  animal_training_match: OK")


func test_animal_training_wrong_spec_is_not_tier_1() -> void:
	var cd := _make_character("char_2", [_prof("animal_training", "horses")])
	var creature := _make_creature("dog_war", "char_1")
	var tier := HandlerEligibility.get_handler_tier(cd, creature)
	check(tier != HandlerEligibility.Tier.PROFICIENT,
		"animal_training(horses) should not be Tier 1 for dog_war, got %d" % tier)
	print("  animal_training_wrong_spec: OK")


func test_introduced_handler_is_tier_2() -> void:
	var cd := _make_character("char_2")
	var creature := _make_creature("dog_war", "char_1", ["char_2"])
	var tier := HandlerEligibility.get_handler_tier(cd, creature)
	check(tier == HandlerEligibility.Tier.INTRODUCED,
		"introduced handler should be Tier 2, got %d" % tier)
	print("  introduced_tier_2: OK")


func test_unknown_handler_is_tier_3() -> void:
	var cd := _make_character("char_3")
	var creature := _make_creature("dog_war", "char_1", ["char_2"])
	var tier := HandlerEligibility.get_handler_tier(cd, creature)
	check(tier == HandlerEligibility.Tier.UNKNOWN,
		"unknown character should be Tier 3, got %d" % tier)
	print("  unknown_tier_3: OK")


func test_capacity_proficient_guard() -> void:
	var cap := HandlerEligibility.get_capacity_for_tier("G", HandlerEligibility.Tier.PROFICIENT)
	check(cap.get("outside_battle", 0) == 20,
		"proficient guard capacity outside battle should be 20, got %d" % cap.get("outside_battle", 0))
	print("  capacity_proficient_guard: OK")


func test_capacity_introduced_mount() -> void:
	var cap := HandlerEligibility.get_capacity_for_tier("M", HandlerEligibility.Tier.INTRODUCED)
	check(cap.get("outside_battle", 0) == 1,
		"introduced mount capacity should be 1, got %d" % cap.get("outside_battle", 0))
	check(cap.get("in_battle", 0) == 0,
		"introduced mount in-battle capacity should be 0")
	print("  capacity_introduced_mount: OK")


func test_species_to_specialization_mapping() -> void:
	check(HandlerEligibility.get_required_specialization("horse_medium_war") == "horses",
		"horse_medium_war should map to 'horses'")
	check(HandlerEligibility.get_required_specialization("dog_hunting") == "dogs",
		"dog_hunting should map to 'dogs'")
	check(HandlerEligibility.get_required_specialization("hawk_ordinary") == "hawks_falcons",
		"hawk_ordinary should map to 'hawks_falcons'")
	check(HandlerEligibility.get_required_specialization("camel") == "camels",
		"camel should map to 'camels'")
	print("  species_specialization_mapping: OK")
