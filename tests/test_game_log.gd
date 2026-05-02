extends "res://tests/test_suite_base.gd"

## Unit tests for GameLogStore (the RefCounted value class owned by the
## GameLog autoload).
## Run via test_runner.tscn. Each test_*() method is called by run_all_tests().


func run_all_tests() -> void:
	test_add_and_retrieve_entries()
	test_filter_by_category()
	test_filter_by_type()
	test_filter_by_entity()
	test_filter_by_time_range()
	test_get_recent()
	test_clear()
	test_to_text_string()
	test_to_json_string()
	if not has_failures():
		print("GameLogStore: all %d checks passed" % test_count())


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_add_and_retrieve_entries() -> void:
	var log := GameLogStore.new()
	var entry := log.add_entry("exploration", "hex_entered", "Entered hex 0305",
		"party_1", "", {"hex_id": "0305"})
	log.add_entry("combat", "combat_started", "Combat started")

	var all: Array = log.get_all_entries()
	check(all.size() == 2, "get_all_entries should return 2 entries after 2 adds")
	check(all[0]["category"] == "exploration", "first entry category should be exploration")
	check(all[0]["type"] == "hex_entered", "first entry type should be hex_entered")
	check(all[0]["summary"] == "Entered hex 0305", "first entry summary should match")
	check(all[0]["actor_id"] == "party_1", "first entry actor_id should be party_1")
	check(all[0]["data"]["hex_id"] == "0305", "first entry data should have hex_id")
	check(all[0]["id"] == 0, "first entry id should be 0")
	check(all[1]["id"] == 1, "second entry id should be 1")
	check(entry["id"] == 0, "add_entry should return the created entry")
	check(log.entry_count() == 2, "entry_count should return 2")


func test_filter_by_category() -> void:
	var log := GameLogStore.new()
	log.add_entry("exploration", "hex_entered", "Hex 1")
	log.add_entry("combat", "combat_started", "Combat 1")
	log.add_entry("exploration", "room_entered", "Room 1")
	log.add_entry("dice", "dice_rolled", "Roll 1")

	var explore: Array = log.get_entries_by_category("exploration")
	check(explore.size() == 2, "should find 2 exploration entries")
	var combat: Array = log.get_entries_by_category("combat")
	check(combat.size() == 1, "should find 1 combat entry")
	var empty: Array = log.get_entries_by_category("domain")
	check(empty.is_empty(), "domain entries should be empty when none added")


func test_filter_by_type() -> void:
	var log := GameLogStore.new()
	log.add_entry("exploration", "hex_entered", "Hex 1")
	log.add_entry("exploration", "hex_entered", "Hex 2")
	log.add_entry("exploration", "room_entered", "Room 1")

	var hexes: Array = log.get_entries_by_type("hex_entered")
	check(hexes.size() == 2, "should find 2 hex_entered entries")
	var rooms: Array = log.get_entries_by_type("room_entered")
	check(rooms.size() == 1, "should find 1 room_entered entry")
	var empty: Array = log.get_entries_by_type("nonexistent")
	check(empty.is_empty(), "nonexistent type should return empty")


func test_filter_by_entity() -> void:
	var log := GameLogStore.new()
	log.add_entry("combat", "damage_dealt", "Damage", "attacker_1", "target_1")
	log.add_entry("combat", "damage_dealt", "Damage", "attacker_2", "target_1")
	log.add_entry("character", "xp_awarded", "XP", "target_1")

	var target1: Array = log.get_entries_for_entity("target_1")
	check(target1.size() == 3, "target_1 appears in 3 entries (2 as target, 1 as actor)")
	var attacker1: Array = log.get_entries_for_entity("attacker_1")
	check(attacker1.size() == 1, "attacker_1 appears in 1 entry")
	var nobody: Array = log.get_entries_for_entity("nobody")
	check(nobody.is_empty(), "unknown entity should return empty")


func test_filter_by_time_range() -> void:
	var log := GameLogStore.new()
	# Manually set game_time since Timekeeping won't be available in tests.
	var e1 := log.add_entry("exploration", "hex_entered", "Hex 1")
	e1["game_time"] = 100
	var e2 := log.add_entry("exploration", "hex_entered", "Hex 2")
	e2["game_time"] = 200
	var e3 := log.add_entry("exploration", "hex_entered", "Hex 3")
	e3["game_time"] = 300

	var range_result: Array = log.get_entries_in_time_range(100, 200)
	check(range_result.size() == 2, "time range 100-200 should return 2 entries")
	var single: Array = log.get_entries_in_time_range(300, 300)
	check(single.size() == 1, "time range 300-300 should return 1 entry")
	var empty: Array = log.get_entries_in_time_range(400, 500)
	check(empty.is_empty(), "time range 400-500 should return empty")


func test_get_recent() -> void:
	var log := GameLogStore.new()
	for i in range(10):
		log.add_entry("dice", "dice_rolled", "Roll %d" % i)

	var recent: Array = log.get_recent(3)
	check(recent.size() == 3, "get_recent(3) should return 3 entries")
	check(recent[0]["summary"] == "Roll 7", "first of recent 3 should be Roll 7")
	check(recent[2]["summary"] == "Roll 9", "last of recent 3 should be Roll 9")

	var all: Array = log.get_recent(100)
	check(all.size() == 10, "get_recent(100) with 10 entries should return all 10")


func test_clear() -> void:
	var log := GameLogStore.new()
	log.add_entry("exploration", "hex_entered", "Hex 1")
	log.add_entry("combat", "combat_started", "Combat 1")
	check(log.entry_count() == 2, "should have 2 entries before clear")
	log.clear()
	check(log.entry_count() == 0, "should have 0 entries after clear")
	check(log.get_all_entries().is_empty(), "get_all_entries should be empty after clear")

	# Verify ID counter resets.
	var entry := log.add_entry("dice", "dice_rolled", "New roll")
	check(entry["id"] == 0, "first entry after clear should have id 0")


func test_to_text_string() -> void:
	var log := GameLogStore.new()
	var e1 := log.add_entry("exploration", "hex_entered", "Entered hex 0305")
	e1["game_time"] = 0  # Y1 M1 D1 00:00
	var e2 := log.add_entry("combat", "combat_started", "Combat started")
	e2["game_time"] = 8640  # Y1 M1 D2 00:00

	var text: String = log.to_text_string()
	check(text.contains("Entered hex 0305"), "text should contain first summary")
	check(text.contains("Combat started"), "text should contain second summary")
	check(text.contains("[Y1 M1 D1 00:00]"), "text should contain first timestamp")
	check(text.contains("[Y1 M1 D2 00:00]"), "text should contain second timestamp")


func test_to_json_string() -> void:
	var log := GameLogStore.new()
	var e1 := log.add_entry("exploration", "hex_entered", "Entered hex 0305")
	e1["game_time"] = 0

	var json_str: String = log.to_json_string()
	var parsed = JSON.parse_string(json_str)
	check(parsed is Array, "JSON should parse to Array")
	check(parsed.size() == 1, "JSON array should have 1 entry")
	check(parsed[0]["category"] == "exploration", "JSON entry category should be exploration")
	check(parsed[0].has("game_time_formatted"), "JSON entry should include game_time_formatted")
