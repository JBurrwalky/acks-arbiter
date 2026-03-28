extends Node

## Unit tests for character persistence round-trip through CampaignRepository.
## Run via test_runner.tscn. Uses plain assert() — no external framework.
##
## These tests verify save/load fidelity for characters, powers,
## proficiencies, and inventory items.

var _campaign_id: String = ""


func run_all_tests() -> void:
	_setup_campaign()
	test_character_round_trip()
	test_powers_round_trip()
	test_proficiencies_round_trip()
	test_inventory_round_trip()
	print("CharacterPersistence: all tests passed.")


# ---------------------------------------------------------------------------
# Setup — create a test campaign for all persistence tests
# ---------------------------------------------------------------------------

func _setup_campaign() -> void:
	_campaign_id = CampaignRepository.create_campaign(
		"Test Character Persistence", "TestWorld"
	)
	assert(not _campaign_id.is_empty(),
		"create_campaign should return a non-empty ID")


# ---------------------------------------------------------------------------
# Character round-trip
# ---------------------------------------------------------------------------

func test_character_round_trip() -> void:
	# Build a CharacterData manually
	var c := CharacterData.new()
	c.id = CampaignRepository.generate_id()
	c.campaign_id = _campaign_id
	c.name = "Test Fighter"
	c.character_type = "pc"
	c.persistence_tier = "full"
	c.race = "human"
	c.character_class = "fighter"
	c.level = 5
	c.xp = 16000
	c.combat_progression = "fighter"
	c.strength = 16
	c.intelligence = 10
	c.wisdom = 12
	c.dexterity = 14
	c.constitution = 13
	c.charisma = 11
	c.hp_max = 35
	c.hp_current = 28
	c.armor_class = 6
	c.attack_throw = 7
	c.save_petrification = 12
	c.save_poison_death = 11
	c.save_blast_breath = 13
	c.save_staffs_wands = 13
	c.save_spells = 14
	c.hit_die_type = "1d8"
	c.max_level = 14
	c.xp_for_next_level = 32000
	c.xp_adjustment_percent = 10
	c.title = "Exemplar"
	c.alignment = "lawful"
	c.is_dead = false
	c.is_active = true

	# Save
	var saved := CampaignRepository.save_character(c.to_dict())
	assert(saved, "save_character should succeed")

	# Load
	var loaded_dict := CampaignRepository.get_character(c.id)
	assert(not loaded_dict.is_empty(), "get_character should return data")

	var loaded := CharacterData.from_dict(loaded_dict)

	# Verify all fields match
	assert(loaded.id == c.id, "id should match")
	assert(loaded.campaign_id == c.campaign_id, "campaign_id should match")
	assert(loaded.name == c.name, "name should match")
	assert(loaded.character_type == c.character_type, "character_type should match")
	assert(loaded.race == c.race, "race should match")
	assert(loaded.character_class == c.character_class, "character_class should match")
	assert(loaded.level == c.level, "level should match")
	assert(loaded.xp == c.xp, "xp should match")
	assert(loaded.combat_progression == c.combat_progression, "combat_progression should match")
	assert(loaded.strength == c.strength, "STR should match")
	assert(loaded.intelligence == c.intelligence, "INT should match")
	assert(loaded.wisdom == c.wisdom, "WIS should match")
	assert(loaded.dexterity == c.dexterity, "DEX should match")
	assert(loaded.constitution == c.constitution, "CON should match")
	assert(loaded.charisma == c.charisma, "CHA should match")
	assert(loaded.hp_max == c.hp_max, "hp_max should match")
	assert(loaded.hp_current == c.hp_current, "hp_current should match")
	assert(loaded.armor_class == c.armor_class, "armor_class should match")
	assert(loaded.attack_throw == c.attack_throw, "attack_throw should match")
	assert(loaded.save_petrification == c.save_petrification, "save_petrification should match")
	assert(loaded.save_poison_death == c.save_poison_death, "save_poison_death should match")
	assert(loaded.save_blast_breath == c.save_blast_breath, "save_blast_breath should match")
	assert(loaded.save_staffs_wands == c.save_staffs_wands, "save_staffs_wands should match")
	assert(loaded.save_spells == c.save_spells, "save_spells should match")
	assert(loaded.hit_die_type == c.hit_die_type, "hit_die_type should match")
	assert(loaded.max_level == c.max_level, "max_level should match")
	assert(loaded.xp_for_next_level == c.xp_for_next_level, "xp_for_next_level should match")
	assert(loaded.xp_adjustment_percent == c.xp_adjustment_percent, "xp_adjustment_percent should match")
	assert(loaded.title == c.title, "title should match")
	assert(loaded.alignment == c.alignment, "alignment should match")
	assert(loaded.is_dead == c.is_dead, "is_dead should match")
	assert(loaded.is_active == c.is_active, "is_active should match")
	print("  character_round_trip: OK")


# ---------------------------------------------------------------------------
# Powers round-trip
# ---------------------------------------------------------------------------

func test_powers_round_trip() -> void:
	# Create a character first
	var char_id := CampaignRepository.generate_id()
	var c := CharacterData.new()
	c.id = char_id
	c.campaign_id = _campaign_id
	c.name = "Test Powers Char"
	c.character_class = "thief"
	CampaignRepository.save_character(c.to_dict())

	# Build power records (similar to what stamp_powers returns)
	var powers := [
		{
			"power_id": "backstab",
			"unlock_level": 1,
			"conditions": "[]",
			"progression_data": '{"1": 2, "2": 2, "3": 2}',
			"is_active": true,
		},
		{
			"power_id": "open_locks",
			"unlock_level": 1,
			"conditions": "[]",
			"progression_data": '{"1": 18, "2": 17}',
			"is_active": true,
		},
	]

	var saved := CampaignRepository.save_character_powers(char_id, powers)
	assert(saved, "save_character_powers should succeed")

	var loaded := CampaignRepository.get_character_powers(char_id)
	assert(loaded.size() == 2,
		"should load 2 powers, got %d" % loaded.size())

	# Verify power_ids are present
	var power_ids := []
	for p in loaded:
		power_ids.append(p.get("power_id", ""))
	assert("backstab" in power_ids, "backstab should be in loaded powers")
	assert("open_locks" in power_ids, "open_locks should be in loaded powers")

	# Verify progression_data survives the round-trip
	for p in loaded:
		if p.get("power_id", "") == "backstab":
			var prog_str: String = p.get("progression_data", "")
			assert(not prog_str.is_empty(),
				"backstab progression_data should not be empty")
	print("  powers_round_trip: OK")


# ---------------------------------------------------------------------------
# Proficiencies round-trip
# ---------------------------------------------------------------------------

func test_proficiencies_round_trip() -> void:
	var char_id := CampaignRepository.generate_id()
	var c := CharacterData.new()
	c.id = char_id
	c.campaign_id = _campaign_id
	c.name = "Test Prof Char"
	c.character_class = "fighter"
	CampaignRepository.save_character(c.to_dict())

	var proficiencies := [
		{"proficiency_key": "adventuring", "rank": 1, "slot_type": "general"},
		{"proficiency_key": "combat_reflexes", "rank": 1, "slot_type": "class"},
		{"proficiency_key": "riding", "rank": 1, "slot_type": "general"},
	]

	var saved := CampaignRepository.save_character_proficiencies(char_id, proficiencies)
	assert(saved, "save_character_proficiencies should succeed")

	var loaded := CampaignRepository.get_character_proficiencies(char_id)
	assert(loaded.size() == 3,
		"should load 3 proficiencies, got %d" % loaded.size())

	var prof_keys := []
	for p in loaded:
		prof_keys.append(p.get("proficiency_key", ""))
	assert("adventuring" in prof_keys, "adventuring should be in loaded proficiencies")
	assert("combat_reflexes" in prof_keys, "combat_reflexes should be in loaded proficiencies")
	assert("riding" in prof_keys, "riding should be in loaded proficiencies")
	print("  proficiencies_round_trip: OK")


# ---------------------------------------------------------------------------
# Inventory round-trip
# ---------------------------------------------------------------------------

func test_inventory_round_trip() -> void:
	var char_id := CampaignRepository.generate_id()
	var c := CharacterData.new()
	c.id = char_id
	c.campaign_id = _campaign_id
	c.name = "Test Inventory Char"
	c.character_class = "fighter"
	CampaignRepository.save_character(c.to_dict())

	var items := [
		{
			"item_key": "longsword_plus_1",
			"name": "Longsword +1",
			"quantity": 1,
			"encumbrance_sixths": 6,
			"slot": "hands_main",
			"is_equipped": true,
			"item_category": "weapon",
			"is_magical": true,
			"magical_bonus": 1,
			"weapon_damage": "1d8",
			"armor_ac_bonus": 0,
			"is_heavy": false,
			"notes": "Glows faintly blue",
		},
		{
			"item_key": "chain_mail",
			"name": "Chain Mail",
			"quantity": 1,
			"encumbrance_sixths": 24,
			"slot": "body",
			"is_equipped": true,
			"item_category": "armor",
			"is_magical": false,
			"magical_bonus": 0,
			"weapon_damage": "",
			"armor_ac_bonus": 4,
			"is_heavy": false,
			"notes": "",
		},
	]

	var saved := CampaignRepository.save_character_inventory(char_id, items)
	assert(saved, "save_character_inventory should succeed")

	var loaded := CampaignRepository.get_inventory_items(char_id)
	assert(loaded.size() == 2,
		"should load 2 inventory items, got %d" % loaded.size())

	# Find the sword and verify fields
	var sword_found := false
	for item in loaded:
		if item.get("item_key", "") == "longsword_plus_1":
			sword_found = true
			assert(item.get("name", "") == "Longsword +1",
				"sword name should match")
			assert(int(item.get("encumbrance_sixths", 0)) == 6,
				"sword encumbrance should be 6")
			assert(item.get("item_category", "") == "weapon",
				"sword category should be 'weapon'")
			assert(int(item.get("is_magical", 0)) == 1,
				"sword should be magical")
			assert(int(item.get("magical_bonus", 0)) == 1,
				"sword magical_bonus should be 1")
			assert(item.get("weapon_damage", "") == "1d8",
				"sword weapon_damage should be '1d8'")
			break
	assert(sword_found, "longsword_plus_1 should be in loaded inventory")
	print("  inventory_round_trip: OK")
