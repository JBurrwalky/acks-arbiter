extends "res://tests/test_suite_base.gd"

## Unit tests for the class power system integration.
## Run via test_runner.tscn. Uses plain check() — no external framework.
##
## Tests verify that class JSONs define correct powers and that
## CharacterGenerator.stamp_powers() produces correct records.


func run_all_tests() -> void:
	test_thief_has_thief_skills()
	test_assassin_shares_backstab()
	test_power_progression_lookup()
	test_stamp_powers()
	test_shared_power_ids()
	if not has_failures():
		print("ClassPowers: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _get_power_ids(class_powers: Array) -> Array[String]:
	var ids: Array[String] = []
	for cp in class_powers:
		var pid: String = cp.get("power_id", "")
		if not pid.is_empty():
			ids.append(pid)
	return ids


# ---------------------------------------------------------------------------
# Thief has all thief skills
# ---------------------------------------------------------------------------

func test_thief_has_thief_skills() -> void:
	var reg := ClassRegistry.new()
	var class_powers := reg.get_class_powers("thief")
	var power_ids := _get_power_ids(class_powers)

	# 7 thief skills plus backstab
	var expected_skills := [
		"open_locks", "find_remove_traps", "pick_pockets",
		"move_silently", "climb_walls", "hide_in_shadows", "hear_noise",
		"backstab",
	]
	for skill in expected_skills:
		check(skill in power_ids,
			"thief should have power '%s', powers are: %s" % [skill, str(power_ids)])
	print("  thief_has_thief_skills: OK")


# ---------------------------------------------------------------------------
# Assassin shares backstab
# ---------------------------------------------------------------------------

func test_assassin_shares_backstab() -> void:
	var reg := ClassRegistry.new()
	var class_powers := reg.get_class_powers("assassin")
	var power_ids := _get_power_ids(class_powers)
	check("backstab" in power_ids,
		"assassin should have 'backstab' power")

	# Assassin backstab has conditions
	for cp in class_powers:
		if cp.get("power_id", "") == "backstab":
			var conditions: Array = cp.get("conditions", [])
			check(not conditions.is_empty(),
				"assassin backstab should have conditions (armor restriction)")
			break
	print("  assassin_shares_backstab: OK")


# ---------------------------------------------------------------------------
# Power progression lookup from class JSON
# ---------------------------------------------------------------------------

func test_power_progression_lookup() -> void:
	var reg := ClassRegistry.new()
	var class_powers := reg.get_class_powers("thief")

	# Find open_locks and check progression values
	var found := false
	for cp in class_powers:
		if cp.get("power_id", "") == "open_locks":
			found = true
			var progression: Dictionary = cp.get("progression", {})
			# Thief open_locks L1 = 18 (throw target)
			check(int(progression.get("1", 0)) == 18,
				"thief open_locks L1 should be 18, got %d" % int(progression.get("1", 0)))
			# Thief open_locks L14 = 1
			check(int(progression.get("14", 0)) == 1,
				"thief open_locks L14 should be 1, got %d" % int(progression.get("14", 0)))
			break
	check(found, "open_locks should exist in thief class_powers")
	print("  power_progression_lookup: OK")


# ---------------------------------------------------------------------------
# stamp_powers produces correct records
# ---------------------------------------------------------------------------

func test_stamp_powers() -> void:
	var class_reg := ClassRegistry.new()
	var power_reg := PowerRegistry.new()
	var gen := CharacterGenerator.new(class_reg, power_reg)

	# Create a dummy character
	var character := CharacterData.new()
	character.id = "test_stamp_001"
	character.character_class = "thief"

	var records := gen.stamp_powers(character, "thief")

	# Thief has 11 class_powers entries (7 skills + backstab + read_languages
	# + arcane_scroll_use + stronghold_hideout)
	var thief_powers := class_reg.get_class_powers("thief")
	check(records.size() == thief_powers.size(),
		"stamp_powers should produce %d records for thief, got %d" % [thief_powers.size(), records.size()])

	# Verify each record has required fields
	for record in records:
		check(record.has("power_id"), "record should have power_id")
		check(record.has("unlock_level"), "record should have unlock_level")
		check(record.has("conditions"), "record should have conditions")
		check(record.has("progression_data"), "record should have progression_data")
		check(record.has("is_active"), "record should have is_active")

	# Check that backstab is among them
	var backstab_found := false
	for record in records:
		if record.get("power_id", "") == "backstab":
			backstab_found = true
			check(int(record.get("unlock_level", 0)) == 1,
				"backstab unlock_level should be 1")
			break
	check(backstab_found, "backstab should be in stamped powers")
	print("  stamp_powers: OK")


# ---------------------------------------------------------------------------
# Shared power_id across classes
# ---------------------------------------------------------------------------

func test_shared_power_ids() -> void:
	var reg := ClassRegistry.new()

	# backstab should use the same power_id string for Thief, Assassin, and Nightblade
	var thief_powers := _get_power_ids(reg.get_class_powers("thief"))
	var assassin_powers := _get_power_ids(reg.get_class_powers("assassin"))
	var nightblade_powers := _get_power_ids(reg.get_class_powers("elven_nightblade"))

	check("backstab" in thief_powers, "thief should have backstab")
	check("backstab" in assassin_powers, "assassin should have backstab")
	check("backstab" in nightblade_powers, "nightblade should have backstab")

	# The string value itself should be identical (not just similar)
	# This is verified by the 'in' checks above — same literal "backstab"
	print("  shared_power_ids: OK")
