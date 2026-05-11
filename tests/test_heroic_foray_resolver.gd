extends "res://tests/test_suite_base.gd"

## Tests for HeroicForayResolver (Phase 6B engine surface).


var _campaign_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_pc_qualifies_at_any_level()
	test_npc_threshold_seven_levels()
	test_henchman_threshold_four_levels()
	test_scale_offset_platoon_decreases_threshold()
	test_compute_foe_pool_picks_lowest_first()
	test_encounter_distance_yards_clear()
	test_simulate_foray_high_level_low_stake_likely_wins()
	if not has_failures():
		print("HeroicForayResolver: all tests passed.")


func _setup() -> void:
	_campaign_id = CampaignRepository.create_campaign("Foray Test", "World")


func _make_character(name: String, character_type: String, level: int) -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, ?, ?, 'full', 'human', 'fighter', ?,
			14, 12, 12, 12, 12, 12, 60, 60)
	""", [id, _campaign_id, name, character_type, level])
	return id


func test_pc_qualifies_at_any_level() -> void:
	var pc := _make_character("Brave PC", "pc", 1)
	check(HeroicForayResolver.is_qualifying_hero(pc, "company", false), "PC level 1 qualifies at company")
	check(HeroicForayResolver.is_qualifying_hero(pc, "brigade", false), "PC qualifies at brigade")


func test_npc_threshold_seven_levels() -> void:
	var npc7 := _make_character("Captain", "npc", 7)
	var npc6 := _make_character("Sergeant", "npc", 6)
	check(HeroicForayResolver.is_qualifying_hero(npc7, "company", false), "NPC L7 qualifies at company")
	check(not HeroicForayResolver.is_qualifying_hero(npc6, "company", false), "NPC L6 does not qualify at company")


func test_henchman_threshold_four_levels() -> void:
	var hench4 := _make_character("Hench", "henchman", 4)
	var hench3 := _make_character("Hench Junior", "henchman", 3)
	check(HeroicForayResolver.is_qualifying_hero(hench4, "company", true), "henchman L4 qualifies (with leader)")
	check(not HeroicForayResolver.is_qualifying_hero(hench3, "company", true), "henchman L3 does not")
	# Without is_henchman_of_qualifier flag, henchman cannot qualify.
	check(not HeroicForayResolver.is_qualifying_hero(hench4, "company", false), "henchman L4 without leader flag → no")


func test_scale_offset_platoon_decreases_threshold() -> void:
	# Platoon offset is -2 → NPC threshold drops from 7 to 5.
	var npc5 := _make_character("Platoon NPC", "npc", 5)
	check(HeroicForayResolver.is_qualifying_hero(npc5, "platoon", false), "NPC L5 qualifies at platoon (5 ≥ 7-2)")
	check(not HeroicForayResolver.is_qualifying_hero(npc5, "company", false), "NPC L5 does not qualify at company")


func test_compute_foe_pool_picks_lowest_first() -> void:
	# Provide a synthetic list of opposing units; resolver should pick lowest BR first.
	var states := [
		{"id": "s1", "troop_unit_id": "u1", "br_current": 5.0},
		{"id": "s2", "troop_unit_id": "u2", "br_current": 1.0},
		{"id": "s3", "troop_unit_id": "u3", "br_current": 3.0},
	]
	var result := HeroicForayResolver.compute_foe_pool(2.0, states, func(_c, _s): return 1)
	# br_staked = 2 → target 2.0 BR; lowest is u2 (1.0); next u3 (3.0) brings cumulative to 4.0 ≥ target.
	var picked: Array = result.get("foe_unit_ids", [])
	check(picked.size() == 2, "picked 2 units, got %d" % picked.size())
	check(picked.has("u2"), "picked u2 first (lowest BR)")
	check(picked.has("u3"), "picked u3 second")
	check(float(result.get("foes_br_actual", 0.0)) == 4.0, "actual BR 4.0")


func test_encounter_distance_yards_clear() -> void:
	# clear_or_grass missile = 4d6 × 10. Roller returns the TOTAL of 4d6.
	# All-max would be 24 × 10 = 240 yards.
	var dist := HeroicForayResolver.encounter_distance_yards("clear_or_grass", "missile",
		func(_c, _s): return 24)
	check(dist == 240, "max roll = 240 yards, got %d" % dist)


func test_simulate_foray_high_level_low_stake_likely_wins() -> void:
	# Hero level 9, stake 0.5, foes_br 0.5 → high target chance.
	var result := HeroicForayResolver.simulate_foray_silently(0.5, 9, 0.5,
		func(_c, _s): return 50)
	# target = 50 + 5×9 - 5 = 90; roll 50 ≤ 90 → success
	check(String(result.get("result", "")).begins_with("victory"), "victory at high level / low stake")
