extends Node

## Unit tests for LevelUpEngine.
## Tests use DiceSystem.override queue (roll_type overrides) to make HP rolls deterministic.
## Source rules: acore_adventures_and_encounters.xml lines 669-680.


func run_all_tests() -> void:
	test_can_level_up_eligible()
	test_can_level_up_xp_too_low()
	test_can_level_up_max_level()
	test_hp_roll_within_hd_count()
	test_hp_roll_past_hd_count()
	test_proficiency_slots_at_correct_level()
	test_proficiency_slots_not_at_wrong_level()
	test_spell_slot_expansion_mage()
	test_auto_level_up_updates_level_and_title()
	test_new_powers_detected()
	print("LevelUpEngine: all tests passed.")


func _make_fighter(level: int = 1, xp: int = 0) -> CharacterData:
	var reg := ClassRegistry.new()
	var c := CharacterData.new()
	c.id = "test_fighter_%d" % level
	c.character_class = "fighter"
	c.race = "human"
	c.level = level
	c.xp = xp
	c.xp_for_next_level = reg.get_xp_for_level("fighter", level + 1) if level < 14 else 0
	c.max_level = 14
	c.hit_die_type = "1d8"
	c.constitution = 10  # +0 modifier
	c.hp_max = 8
	c.hp_current = 8
	c.attack_throw = reg.get_attack_throw("fighter", level)
	var saves := reg.get_saving_throws("fighter", level)
	c.save_petrification = int(saves.get("petrification", 15))
	c.save_poison_death  = int(saves.get("poison_death", 14))
	c.save_blast_breath  = int(saves.get("blast_breath", 16))
	c.save_staffs_wands  = int(saves.get("staffs_wands", 16))
	c.save_spells        = int(saves.get("spells", 17))
	c.title = reg.get_level_title("fighter", level)
	return c


func _make_mage(level: int = 1, xp: int = 0) -> CharacterData:
	var reg := ClassRegistry.new()
	var c := CharacterData.new()
	c.id = "test_mage_%d" % level
	c.character_class = "mage"
	c.race = "human"
	c.level = level
	c.xp = xp
	c.xp_for_next_level = reg.get_xp_for_level("mage", level + 1) if level < 14 else 0
	c.max_level = 14
	c.hit_die_type = "1d4"
	c.constitution = 10
	c.hp_max = 4
	c.hp_current = 4
	c.attack_throw = reg.get_attack_throw("mage", level)
	var saves := reg.get_saving_throws("mage", level)
	c.save_petrification = int(saves.get("petrification", 13))
	c.save_poison_death  = int(saves.get("poison_death", 13))
	c.save_blast_breath  = int(saves.get("blast_breath", 15))
	c.save_staffs_wands  = int(saves.get("staffs_wands", 11))
	c.save_spells        = int(saves.get("spells", 12))
	c.title = reg.get_level_title("mage", level)
	return c


func _make_engine() -> LevelUpEngine:
	return LevelUpEngine.new(ClassRegistry.new(), PowerRegistry.new(), ProficiencyRegistry.new())


func test_can_level_up_eligible() -> void:
	## Fighter at L1 with enough XP should be eligible.
	var fighter := _make_fighter(1, 2000)  # xp_for_next = 2000
	var engine := _make_engine()
	assert(engine.can_level_up(fighter), "Fighter with 2000 XP at L1 should be eligible")
	print("  can_level_up_eligible: OK")


func test_can_level_up_xp_too_low() -> void:
	## Fighter at L1 with 1999 XP should NOT be eligible.
	var fighter := _make_fighter(1, 1999)
	var engine := _make_engine()
	assert(not engine.can_level_up(fighter), "Fighter with 1999 XP at L1 should not be eligible")
	print("  can_level_up_xp_too_low: OK")


func test_can_level_up_max_level() -> void:
	## Fighter at max level should never be eligible regardless of XP.
	var fighter := _make_fighter(14, 999999)
	fighter.xp_for_next_level = 0
	var engine := _make_engine()
	assert(not engine.can_level_up(fighter), "Max-level fighter should never be eligible")
	print("  can_level_up_max_level: OK")


func test_hp_roll_within_hd_count() -> void:
	## Fighter L1→L2 (within 9 HD count). HP = roll(1d8) + CON mod (0). Min 1.
	## Override the roll to produce 5 — expect 5 gained.
	var fighter := _make_fighter(1, 2000)
	GameState.dice_overrides["level_up_hp_L2"] = 5
	var engine := _make_engine()
	var gained := engine.roll_level_up_hp(fighter)
	assert(gained == 5, "Fighter L1->L2 HP (rolled 5, CON +0): expected 5, got %d" % gained)
	print("  hp_roll_within_hd_count: OK")


func test_hp_roll_past_hd_count() -> void:
	## Fighter L9→L10 (past max 9 HD). HP = +2 fixed (no CON mod, no dice).
	var fighter := _make_fighter(9, 250000)
	var engine := _make_engine()
	var gained := engine.roll_level_up_hp(fighter)
	assert(gained == 2, "Fighter L9->L10 HP (fixed +2): expected 2, got %d" % gained)
	print("  hp_roll_past_hd_count: OK")


func test_proficiency_slots_at_correct_level() -> void:
	## Fighter gains a class proficiency slot at L3.
	var engine := _make_engine()
	var slots := engine._check_new_proficiency_slots("fighter", 3)
	assert(int(slots.get("class", 0)) == 1,
		"Fighter should gain 1 class prof slot at L3, got %d" % slots.get("class", 0))
	print("  proficiency_slots_at_correct_level: OK")


func test_proficiency_slots_not_at_wrong_level() -> void:
	## Fighter does NOT gain a class proficiency slot at L2.
	var engine := _make_engine()
	var slots := engine._check_new_proficiency_slots("fighter", 2)
	assert(int(slots.get("class", 0)) == 0,
		"Fighter should NOT gain class prof slot at L2, got %d" % slots.get("class", 0))
	print("  proficiency_slots_not_at_wrong_level: OK")


func test_spell_slot_expansion_mage() -> void:
	## Mage at L2 has spell slots [2,0,0,0,0,0]; at L3 gains level-2 slots [2,1,0,0,0,0].
	var reg := ClassRegistry.new()
	var slots_l2 := reg.get_spell_slots("mage", 2)
	var slots_l3 := reg.get_spell_slots("mage", 3)
	assert(not slots_l3.is_empty(), "Mage L3 should have spell slots")
	assert(int(slots_l2[0]) == 2, "Mage L2 slot[0]: expected 2, got %d" % slots_l2[0])
	assert(int(slots_l3[0]) == 2, "Mage L3 slot[0]: expected 2, got %d" % slots_l3[0])
	assert(int(slots_l3[1]) >= 1, "Mage L3 slot[1]: expected >= 1, got %d" % slots_l3[1])
	assert(int(slots_l2[1]) == 0, "Mage L2 slot[1]: expected 0, got %d" % slots_l2[1])
	print("  spell_slot_expansion_mage: OK")


func test_auto_level_up_updates_level_and_title() -> void:
	## Use _compute_level_up (not the auto path which requires DB) to verify the result dict.
	GameState.dice_overrides["level_up_hp_L2"] = 6
	var fighter := _make_fighter(1, 2000)
	var engine := _make_engine()
	# _compute_level_up is internal but accessible.
	var result := engine._compute_level_up(fighter)
	assert(result.get("new_level", 0) == 2, "Expected new_level=2, got %d" % result.get("new_level", 0))
	assert(not (result.get("new_title", "") as String).is_empty(), "new_title should not be empty")
	assert(int(result.get("hp_gained", 0)) >= 1, "hp_gained should be >= 1")
	print("  auto_level_up_updates_level_and_title: OK")


func test_new_powers_detected() -> void:
	## Fighter unlocks battlefield_leadership at L5.
	## (Class JSON has this power with unlock_level=5.)
	var engine := _make_engine()
	var powers := engine._get_new_powers("fighter", 5)
	assert("battlefield_leadership" in powers,
		"Fighter should unlock battlefield_leadership at L5. Got: %s" % str(powers))
	print("  new_powers_detected: OK")
