extends Node

## Unit tests for PowerRegistry.
## Run via test_runner.tscn. Uses plain assert() — no external framework.


func run_all_tests() -> void:
	test_powers_load()
	test_known_power_exists()
	test_power_type_filter()
	test_power_metadata()
	print("PowerRegistry: all tests passed.")


# ---------------------------------------------------------------------------
# Power loading
# ---------------------------------------------------------------------------

func test_powers_load() -> void:
	var reg := PowerRegistry.new()
	assert(reg.get_power_count() > 30,
		"PowerRegistry should load > 30 powers, got %d" % reg.get_power_count())
	print("  powers_load: OK (%d powers)" % reg.get_power_count())


# ---------------------------------------------------------------------------
# Power existence checks
# ---------------------------------------------------------------------------

func test_known_power_exists() -> void:
	var reg := PowerRegistry.new()
	assert(reg.has_power("backstab") == true,
		"backstab should exist in power catalog")
	assert(reg.has_power("open_locks") == true,
		"open_locks should exist in power catalog")
	assert(reg.has_power("nonexistent") == false,
		"nonexistent should not exist in power catalog")
	assert(reg.has_power("") == false,
		"empty string should not exist in power catalog")
	print("  known_power_exists: OK")


# ---------------------------------------------------------------------------
# Power type filtering
# ---------------------------------------------------------------------------

func test_power_type_filter() -> void:
	var reg := PowerRegistry.new()
	var skill_throws := reg.get_powers_by_type("skill_throw")
	assert(skill_throws.size() > 1,
		"skill_throw type should have multiple entries, got %d" % skill_throws.size())
	# open_locks should be among them
	var found_open_locks := false
	for power in skill_throws:
		if power.get("power_id", "") == "open_locks":
			found_open_locks = true
			break
	assert(found_open_locks, "open_locks should be in skill_throw powers")

	# Check that a non-skill_throw power is NOT in the list
	var found_backstab := false
	for power in skill_throws:
		if power.get("power_id", "") == "backstab":
			found_backstab = true
			break
	assert(not found_backstab,
		"backstab (scaling_multiplier) should NOT be in skill_throw results")
	print("  power_type_filter: OK")


# ---------------------------------------------------------------------------
# Power metadata
# ---------------------------------------------------------------------------

func test_power_metadata() -> void:
	var reg := PowerRegistry.new()
	var backstab := reg.get_power("backstab")
	assert(not backstab.is_empty(), "backstab power should not be empty")
	assert(backstab.has("power_name"), "backstab should have power_name")
	assert(backstab.get("power_name", "") == "Backstab",
		"backstab power_name should be 'Backstab'")
	assert(backstab.has("power_type"), "backstab should have power_type")
	assert(backstab.get("power_type", "") == "scaling_multiplier",
		"backstab power_type should be 'scaling_multiplier'")
	assert(backstab.has("description"), "backstab should have description")
	assert(not backstab.get("description", "").is_empty(),
		"backstab description should not be empty")
	print("  power_metadata: OK")
