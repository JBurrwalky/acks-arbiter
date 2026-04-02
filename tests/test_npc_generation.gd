extends "res://tests/test_suite_base.gd"

## Unit tests for NPC and henchman generation.
## Run via test_runner.tscn. Uses plain check() — no external framework.


func run_all_tests() -> void:
	test_npc_generation_basic()
	test_npc_attack_throw()
	test_npc_saving_throws()
	test_henchman_generation()
	test_npc_proficiencies()
	if not has_failures():
		print("NPC Generation: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_generator() -> CharacterGenerator:
	return CharacterGenerator.new(ClassRegistry.new(), PowerRegistry.new())


# ---------------------------------------------------------------------------
# NPC generation — basic
# ---------------------------------------------------------------------------

func test_npc_generation_basic() -> void:
	var gen := _make_generator()
	var npc := gen.generate_npc("thief", 3, "test_npc_campaign")
	check(npc != null, "generate_npc should return a CharacterData")
	check(npc.level == 3, "NPC level should be 3, got %d" % npc.level)
	check(npc.character_type == "npc",
		"character_type should be 'npc', got '%s'" % npc.character_type)
	check(npc.character_class == "thief",
		"class should be 'thief', got '%s'" % npc.character_class)
	check(npc.race == "human",
		"thief race should be 'human'")
	check(npc.combat_progression == "thief",
		"thief combat_progression should be 'thief'")
	check(npc.hit_die_type == "1d4",
		"thief hit_die_type should be '1d4'")
	# Ability scores should all be in range
	for score in [npc.strength, npc.intelligence, npc.wisdom,
			npc.dexterity, npc.constitution, npc.charisma]:
		check(score >= 3 and score <= 18,
			"ability score %d out of range [3, 18]" % score)
	# HP should be at least 1
	check(npc.hp_max >= 1, "HP should be >= 1")
	# ID should be set
	check(not npc.id.is_empty(), "NPC ID should not be empty")
	print("  npc_generation_basic: OK")


# ---------------------------------------------------------------------------
# NPC attack throw matches class table
# ---------------------------------------------------------------------------

func test_npc_attack_throw() -> void:
	var gen := _make_generator()
	var class_reg := ClassRegistry.new()

	# L3 Thief: attack_progression["3"] = 9
	var npc := gen.generate_npc("thief", 3, "test_npc_at")
	var expected_at := class_reg.get_attack_throw("thief", 3)
	check(npc.attack_throw == expected_at,
		"L3 thief attack throw should be %d, got %d" % [expected_at, npc.attack_throw])

	# L7 Fighter: attack_progression["7"] = 6
	var fighter_npc := gen.generate_npc("fighter", 7, "test_npc_at")
	var expected_at_f := class_reg.get_attack_throw("fighter", 7)
	check(fighter_npc.attack_throw == expected_at_f,
		"L7 fighter attack throw should be %d, got %d" % [expected_at_f, fighter_npc.attack_throw])
	print("  npc_attack_throw: OK")


# ---------------------------------------------------------------------------
# NPC saving throws match class table
# ---------------------------------------------------------------------------

func test_npc_saving_throws() -> void:
	var gen := _make_generator()
	var class_reg := ClassRegistry.new()

	# L5 Fighter saves from the JSON
	var npc := gen.generate_npc("fighter", 5, "test_npc_saves")
	var expected_saves := class_reg.get_saving_throws("fighter", 5)

	check(npc.save_petrification == int(expected_saves.get("petrification", 0)),
		"L5 fighter petrification should be %d, got %d" % [
			int(expected_saves.get("petrification", 0)), npc.save_petrification])
	check(npc.save_poison_death == int(expected_saves.get("poison_death", 0)),
		"L5 fighter poison_death should be %d, got %d" % [
			int(expected_saves.get("poison_death", 0)), npc.save_poison_death])
	check(npc.save_blast_breath == int(expected_saves.get("blast_breath", 0)),
		"L5 fighter blast_breath should be %d, got %d" % [
			int(expected_saves.get("blast_breath", 0)), npc.save_blast_breath])
	check(npc.save_staffs_wands == int(expected_saves.get("staffs_wands", 0)),
		"L5 fighter staffs_wands should be %d, got %d" % [
			int(expected_saves.get("staffs_wands", 0)), npc.save_staffs_wands])
	check(npc.save_spells == int(expected_saves.get("spells", 0)),
		"L5 fighter spells should be %d, got %d" % [
			int(expected_saves.get("spells", 0)), npc.save_spells])
	print("  npc_saving_throws: OK")


# ---------------------------------------------------------------------------
# Henchman generation
# ---------------------------------------------------------------------------

func test_henchman_generation() -> void:
	var gen := _make_generator()
	var employer_id := "employer_abc123"
	var henchman := gen.generate_henchman("fighter", 2, "test_hench_campaign", employer_id)
	check(henchman != null, "generate_henchman should return a CharacterData")
	check(henchman.character_type == "henchman",
		"character_type should be 'henchman', got '%s'" % henchman.character_type)
	check(henchman.persistence_tier == "full",
		"henchman persistence_tier should be 'full', got '%s'" % henchman.persistence_tier)
	check(henchman.employer_id == employer_id,
		"employer_id should be '%s', got '%s'" % [employer_id, henchman.employer_id])
	check(henchman.level == 2,
		"henchman level should be 2, got %d" % henchman.level)
	check(henchman.loyalty_score == 7,
		"henchman base loyalty should be 7, got %d" % henchman.loyalty_score)
	print("  henchman_generation: OK")


# ---------------------------------------------------------------------------
# NPC proficiency auto-selection
# ---------------------------------------------------------------------------

func test_npc_proficiencies() -> void:
	var gen := _make_generator()
	var proficiencies := gen.auto_select_proficiencies("fighter", 1)

	# At L1, fighter gets: 1 class slot (from proficiency_progression.class = [1, 3, 6, 9, 12])
	# and 1 general slot (from proficiency_progression.general = [1, 5, 9, 13])
	# adventuring takes one general slot automatically
	check(proficiencies.size() >= 2,
		"L1 fighter should have at least 2 proficiencies (adventuring + 1 class), got %d" % proficiencies.size())

	# adventuring should be included
	var has_adventuring := false
	for p in proficiencies:
		if p.get("proficiency_key", "") == "adventuring":
			has_adventuring = true
			break
	check(has_adventuring,
		"adventuring should be auto-selected for NPC proficiencies")

	# All proficiencies should have required fields
	for p in proficiencies:
		check(p.has("proficiency_key"), "proficiency should have proficiency_key")
		check(p.has("rank"), "proficiency should have rank")
		check(p.has("slot_type"), "proficiency should have slot_type")
		check(p.get("slot_type", "") in ["general", "class"],
			"slot_type should be 'general' or 'class', got '%s'" % p.get("slot_type", ""))
	print("  npc_proficiencies: OK")
