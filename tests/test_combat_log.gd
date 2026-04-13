extends "res://tests/test_suite_base.gd"

## Unit tests for CombatLog.
## Run via test_runner.tscn. Each test_*() method is called by run_all_tests().


func run_all_tests() -> void:
	test_add_and_retrieve_entries()
	test_filter_by_round()
	test_filter_by_type()
	test_filter_by_combatant()
	test_summary_counts()
	if not has_failures():
		print("CombatLog: all %d checks passed" % test_count())


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_add_and_retrieve_entries() -> void:
	var log := CombatLog.new()
	log.add_entry(CombatLog.EntryType.ATTACK, 1, "pc_1", "monster_1", {"hit": true})
	log.add_entry(CombatLog.EntryType.DAMAGE, 1, "pc_1", "monster_1", {"amount": 5})
	var all: Array = log.get_all_entries()
	check(all.size() == 2, "get_all_entries should return 2 entries after 2 adds")
	check(all[0]["type"] == CombatLog.EntryType.ATTACK, "first entry type should be ATTACK")
	check(all[1]["data"]["amount"] == 5, "second entry data should have amount 5")
	check(all[0]["timestamp"] == 0, "first timestamp should be 0")
	check(all[1]["timestamp"] == 1, "second timestamp should be 1")


func test_filter_by_round() -> void:
	var log := CombatLog.new()
	log.add_entry(CombatLog.EntryType.ROUND_START, 1, "", "", {})
	log.add_entry(CombatLog.EntryType.ATTACK, 1, "a", "b", {})
	log.add_entry(CombatLog.EntryType.ROUND_START, 2, "", "", {})
	log.add_entry(CombatLog.EntryType.ATTACK, 2, "b", "a", {})
	var r1: Array = log.get_round_entries(1)
	var r2: Array = log.get_round_entries(2)
	check(r1.size() == 2, "round 1 should have 2 entries")
	check(r2.size() == 2, "round 2 should have 2 entries")
	check(log.get_round_entries(99).is_empty(), "non-existent round should return empty")


func test_filter_by_type() -> void:
	var log := CombatLog.new()
	log.add_entry(CombatLog.EntryType.ATTACK, 1, "a", "b", {})
	log.add_entry(CombatLog.EntryType.DAMAGE, 1, "a", "b", {"amount": 3})
	log.add_entry(CombatLog.EntryType.ATTACK, 2, "b", "a", {})
	log.add_entry(CombatLog.EntryType.DEATH, 2, "b", "a", {})
	var attacks: Array = log.get_entries_by_type(CombatLog.EntryType.ATTACK)
	check(attacks.size() == 2, "should find 2 ATTACK entries")
	var deaths: Array = log.get_entries_by_type(CombatLog.EntryType.DEATH)
	check(deaths.size() == 1, "should find 1 DEATH entry")
	var morale: Array = log.get_entries_by_type(CombatLog.EntryType.MORALE)
	check(morale.is_empty(), "MORALE entries should be empty when none added")


func test_filter_by_combatant() -> void:
	var log := CombatLog.new()
	log.add_entry(CombatLog.EntryType.ATTACK, 1, "pc_1", "monster_1", {})
	log.add_entry(CombatLog.EntryType.ATTACK, 1, "monster_1", "pc_1", {})
	log.add_entry(CombatLog.EntryType.ATTACK, 2, "pc_2", "monster_2", {})
	var pc1_entries: Array = log.get_entries_for_combatant("pc_1")
	check(pc1_entries.size() == 2, "pc_1 appears as actor and target, should be 2")
	var monster2_entries: Array = log.get_entries_for_combatant("monster_2")
	check(monster2_entries.size() == 1, "monster_2 only as target, should be 1")
	var unknown_entries: Array = log.get_entries_for_combatant("nobody")
	check(unknown_entries.is_empty(), "unknown id should return empty")


func test_summary_counts() -> void:
	var log := CombatLog.new()
	log.add_entry(CombatLog.EntryType.ROUND_START, 1, "", "", {})
	log.add_entry(CombatLog.EntryType.ATTACK, 1, "pc_1", "m_1", {})
	log.add_entry(CombatLog.EntryType.DAMAGE, 1, "pc_1", "m_1", {"amount": 7})
	log.add_entry(CombatLog.EntryType.ATTACK, 1, "m_1", "pc_1", {})
	log.add_entry(CombatLog.EntryType.DAMAGE, 1, "m_1", "pc_1", {"amount": 4})
	log.add_entry(CombatLog.EntryType.DEATH, 1, "", "m_1", {})
	log.add_entry(CombatLog.EntryType.MORTAL_WOUND, 1, "", "pc_1",
		{"condition": "knocked_out"})
	var summary: Dictionary = log.get_summary()
	check(summary["rounds"] == 1, "summary rounds should be 1")
	check(summary["attacks"] == 2, "summary attacks should be 2")
	check(summary["kills"] == 1, "summary kills should be 1")
	check(summary["damage_dealt"]["m_1"] == 7, "m_1 took 7 damage")
	check(summary["damage_dealt"]["pc_1"] == 4, "pc_1 took 4 damage")
	check(summary["mortal_wounds"].size() == 1, "1 mortal wound entry")
	check(summary["mortal_wounds"][0]["condition"] == "knocked_out",
		"mortal wound condition should be knocked_out")
