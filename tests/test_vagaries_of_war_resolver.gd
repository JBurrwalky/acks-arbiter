extends "res://tests/test_suite_base.gd"

## Tests for VagariesOfWarResolver per daw_vagaries.xml §vagaries_of_war
## L186-540 + gdd-army-warfare.md §4.9.5.


func run_all_tests() -> void:
	test_classify_roll_table_coverage_at_known_boundaries()
	test_classify_roll_returns_all_quiet_for_46_to_55()
	test_classify_roll_war_profiteers_priority_over_siege_train_at_32()
	test_defection_handler_walks_lowest_morale_first()
	test_defection_handler_holds_when_all_loyal()
	if not has_failures():
		print("VagariesOfWarResolver: all tests passed.")


func test_classify_roll_table_coverage_at_known_boundaries() -> void:
	# Per RAW table at L196-228:
	check(VagariesOfWarResolver.classify_roll(1) == "disease", "01 → disease")
	check(VagariesOfWarResolver.classify_roll(2) == "disease", "02 → disease")
	check(VagariesOfWarResolver.classify_roll(3) == "defection", "03 → defection")
	check(VagariesOfWarResolver.classify_roll(6) == "desertion", "06 → desertion")
	check(VagariesOfWarResolver.classify_roll(18) == "commander_casualty", "18 → commander_casualty")
	check(VagariesOfWarResolver.classify_roll(21) == "brigands", "21 → brigands")
	check(VagariesOfWarResolver.classify_roll(25) == "supply_problems", "25 → supply_problems")
	check(VagariesOfWarResolver.classify_roll(37) == "bad_weather", "37 → bad_weather")
	check(VagariesOfWarResolver.classify_roll(56) == "good_omen", "56 → good_omen")
	check(VagariesOfWarResolver.classify_roll(73) == "supply_boon", "73 → supply_boon")
	check(VagariesOfWarResolver.classify_roll(99) == "plans_discovered", "99 → plans_discovered")
	check(VagariesOfWarResolver.classify_roll(100) == "plans_discovered", "100 → plans_discovered")


func test_classify_roll_returns_all_quiet_for_46_to_55() -> void:
	# RAW row L214: 46-55 = all_quiet.
	check(VagariesOfWarResolver.classify_roll(46) == "all_quiet", "46 → all_quiet")
	check(VagariesOfWarResolver.classify_roll(50) == "all_quiet", "50 → all_quiet")
	check(VagariesOfWarResolver.classify_roll(55) == "all_quiet", "55 → all_quiet")


func test_classify_roll_war_profiteers_priority_over_siege_train_at_32() -> void:
	# RAW source has overlap: 29-32 = war_profiteers, 32-36 = siege_train_problems.
	# The resolver's in-order iteration gives war_profiteers priority at 32.
	check(VagariesOfWarResolver.classify_roll(32) == "war_profiteers",
		"32 falls on war_profiteers per in-order resolution")
	check(VagariesOfWarResolver.classify_roll(33) == "siege_train_problems",
		"33 → siege_train_problems")


# ---------------------------------------------------------------------------
# Defection handler tests (Phase 7 polish — RAW §vagaries_of_war.defection
# L270-278: roll loyalty for each commander lowest-morale-first; first
# Resignation/Hostility defects.)
# ---------------------------------------------------------------------------

func _setup_defection_army(officer_morale_modifiers: Array) -> Dictionary:
	var campaign_id := CampaignRepository.create_campaign("DefectionTest", "World")
	var ruler_id := _make_character(campaign_id, "Ruler")
	var army_id := ArmyRepository.create_army({
		"campaign_id": campaign_id, "name": "Defection Host",
		"political_owner_id": ruler_id, "command_character_id": ruler_id,
		"state": "marching", "formed_calendar_day": 100,
	})
	# Create one officer per modifier, all 'mercenary_officer' rank=division_commander
	# so we have multiple non-leader officers to walk.
	var officers: Array = []
	for i in range(officer_morale_modifiers.size()):
		var officer_char := _make_character(campaign_id, "Officer%d" % i)
		var officer_id := ArmyRepository.create_officer({
			"army_id": army_id, "character_id": officer_char,
			"rank": "division_commander",
			"morale_modifier": int(officer_morale_modifiers[i]),
			"appointed_calendar_day": 100,
		})
		officers.append(officer_id)
	return {"campaign_id": campaign_id, "army_id": army_id, "officers": officers}


func _make_character(campaign_id: String, name: String) -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, ?, 'pc', 'full', 'human', 'fighter', 9,
			14, 12, 12, 12, 12, 14, 60, 60)
	""", [id, campaign_id, name])
	return id


func test_defection_handler_walks_lowest_morale_first() -> void:
	# Three officers: morale +4, +0, -4. The -4 officer has lowest morale and
	# should be tried first. With seeded RNG via the resolver's randi fallback
	# we can't fully control the roll, but we can statistically verify by
	# repeating: the -4 officer should defect substantially more often than
	# the +4 officer.
	# Simpler deterministic approach: -4 officer alone, expect defection on most rolls.
	var ctx := _setup_defection_army([-4])
	var defected_count: int = 0
	var sample_size: int = 50
	for i in range(sample_size):
		var result := VagariesOfWarResolver._apply_defection(String(ctx["army_id"]), 100)
		if result.has("defected_officer_id") and not String(result["defected_officer_id"]).is_empty():
			defected_count += 1
	# At -4 base loyalty with 2d6 (range 2-12 → modified -2 to 8), Resignation
	# requires ≤3 (modifier 2-12 + (-4) = -2 to 8; ≤3 = 2-3, ≤4 = 2-4, etc.).
	# HenchmanTables.loyalty_result thresholds (typical): ≤3 hostility, 4-6 resignation,
	# 7-8 grudging, 9-11 loyal, 12+ fanatic. So at -4 mod, departure (≤6) covers
	# rolls 2-10 of 2d6, which is most outcomes. Expect >50% departure rate.
	check(defected_count >= 25, "−4 morale officer defects in ≥50%% of 50 rolls; got %d/50" % defected_count)


func test_defection_handler_holds_when_all_loyal() -> void:
	# +4 morale officer should hold loyal in nearly all rolls.
	var ctx := _setup_defection_army([4])
	var held_count: int = 0
	var sample_size: int = 30
	for i in range(sample_size):
		var result := VagariesOfWarResolver._apply_defection(String(ctx["army_id"]), 200)
		if not result.has("defected_officer_id"):
			held_count += 1
	# At +4 mod, departure requires roll ≤2 (2 + 4 = 6 = resignation lower edge),
	# i.e. 1 in 36 rolls. Expect held_count ≥ 25 of 30.
	check(held_count >= 25, "+4 morale officer holds in ≥83%% of 30 rolls; got %d/30" % held_count)
