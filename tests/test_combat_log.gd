## Unit tests for CombatLog.
## Run via test_runner.tscn. Each test_*() method is called by run_all_tests().

var _passed: int = 0
var _failed: int = 0


func run_all_tests() -> void:
	_passed = 0
	_failed = 0
	test_add_and_retrieve_entries()
	test_filter_by_round()
	test_filter_by_type()
	test_filter_by_combatant()
	test_summary_counts()
	print("CombatLog: %d passed, %d failed" % [_passed, _failed])


func _assert(condition: bool, msg: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL [test_combat_log]: " + msg)


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_add_and_retrieve_entries() -> void:
	var log := CombatLog.new()
	log.add_entry(CombatLog.EntryType.ATTACK, 1, "pc_1", "monster_1", {"hit": true})
	log.add_entry(CombatLog.EntryType.DAMAGE, 1, "pc_1", "monster_1", {"amount": 5})
	var all: Array = log.get_all_entries()
	_assert(all.size() == 2, "get_all_entries should return 2 entries after 2 adds")
	_assert(all[0]["type"] == CombatLog.EntryType.ATTACK, "first entry type should be ATTACK")
	_assert(all[1]["data"]["amount"] == 5, "second entry data should have amount 5")
	_assert(all[0]["timestamp"] == 0, "first timestamp should be 0")
	_assert(all[1]["timestamp"] == 1, "second timestamp should be 1")


func test_filter_by_round() -> void:
	var log := CombatLog.new()
	log.add_entry(CombatLog.EntryType.ROUND_START, 1, "", "", {})
	log.add_entry(CombatLog.EntryType.ATTACK, 1, "a", "b", {})
	log.add_entry(CombatLog.EntryType.ROUND_START, 2, "", "", {})
	log.add_entry(CombatLog.EntryType.ATTACK, 2, "b", "a", {})
	var r1: Array = log.get_round_entries(1)
	var r2: Array = log.get_round_entries(2)
	_assert(r1.size() == 2, "round 1 should have 2 entries")
	_assert(r2.size() == 2, "round 2 should have 2 entries")
	_assert(log.get_round_entries(99).is_empty(), "non-existent round should return empty")


func test_filter_by_type() -> void:
	var log := CombatLog.new()
	log.add_entry(CombatLog.EntryType.ATTACK, 1, "a", "b", {})
	log.add_entry(CombatLog.EntryType.DAMAGE, 1, "a", "b", {"amount": 3})
	log.add_entry(CombatLog.EntryType.ATTACK, 2, "b", "a", {})
	log.add_entry(CombatLog.EntryType.DEATH, 2, "b", "a", {})
	var attacks: Array = log.get_entries_by_type(CombatLog.EntryType.ATTACK)
	_assert(attacks.size() == 2, "should find 2 ATTACK entries")
	var deaths: Array = log.get_entries_by_type(CombatLog.EntryType.DEATH)
	_assert(deaths.size() == 1, "should find 1 DEATH entry")
	var morale: Array = log.get_entries_by_type(CombatLog.EntryType.MORALE)
	_assert(morale.is_empty(), "MORALE entries should be empty when none added")


func test_filter_by_combatant() -> void:
	var log := CombatLog.new()
	log.add_entry(CombatLog.EntryType.ATTACK, 1, "pc_1", "monster_1", {})
	log.add_entry(CombatLog.EntryType.ATTACK, 1, "monster_1", "pc_1", {})
	log.add_entry(CombatLog.EntryType.ATTACK, 2, "pc_2", "monster_2", {})
	var pc1_entries: Array = log.get_entries_for_combatant("pc_1")
	_assert(pc1_entries.size() == 2, "pc_1 appears as actor and target, should be 2")
	var monster2_entries: Array = log.get_entries_for_combatant("monster_2")
	_assert(monster2_entries.size() == 1, "monster_2 only as target, should be 1")
	var unknown_entries: Array = log.get_entries_for_combatant("nobody")
	_assert(unknown_entries.is_empty(), "unknown id should return empty")


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
	_assert(summary["rounds"] == 1, "summary rounds should be 1")
	_assert(summary["attacks"] == 2, "summary attacks should be 2")
	_assert(summary["kills"] == 1, "summary kills should be 1")
	_assert(summary["damage_dealt"]["m_1"] == 7, "m_1 took 7 damage")
	_assert(summary["damage_dealt"]["pc_1"] == 4, "pc_1 took 4 damage")
	_assert(summary["mortal_wounds"].size() == 1, "1 mortal wound entry")
	_assert(summary["mortal_wounds"][0]["condition"] == "knocked_out",
		"mortal wound condition should be knocked_out")
