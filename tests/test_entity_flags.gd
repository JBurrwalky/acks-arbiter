extends Node

## Unit tests for EntityFlags.


func run_all_tests() -> void:
	test_set_and_has_flag()
	test_clear_flag_removes_source()
	test_multi_source_flag_stays_until_all_cleared()
	test_clear_all_from_source()
	test_has_flag_false_when_not_set()
	test_get_flag_sources()
	test_get_flag_metadata()
	test_set_flag_updates_existing_source_metadata()
	test_get_all_flags()
	test_clear_all()
	test_clear_nonexistent_flag_is_safe()
	print("EntityFlags: all tests passed.")


func test_set_and_has_flag() -> void:
	var f := EntityFlags.new()
	f.set_flag("can_fly", "fly_spell")
	assert(f.has_flag("can_fly"),
		"EntityFlags: has_flag should return true after set_flag")


func test_clear_flag_removes_source() -> void:
	var f := EntityFlags.new()
	f.set_flag("can_fly", "fly_spell")
	f.clear_flag("can_fly", "fly_spell")
	assert(not f.has_flag("can_fly"),
		"EntityFlags: flag should be gone after sole source is cleared")


func test_multi_source_flag_stays_until_all_cleared() -> void:
	var f := EntityFlags.new()
	f.set_flag("can_fly", "fly_spell")
	f.set_flag("can_fly", "winged_flight")
	f.clear_flag("can_fly", "fly_spell")
	assert(f.has_flag("can_fly"),
		"EntityFlags: flag should remain when one of two sources is cleared")
	f.clear_flag("can_fly", "winged_flight")
	assert(not f.has_flag("can_fly"),
		"EntityFlags: flag should be gone after both sources are cleared")


func test_clear_all_from_source() -> void:
	var f := EntityFlags.new()
	f.set_flag("can_fly", "haste_spell")
	f.set_flag("is_hasted", "haste_spell")
	f.set_flag("is_invisible", "other_spell")
	f.clear_all_from_source("haste_spell")
	assert(not f.has_flag("can_fly"),
		"EntityFlags: clear_all_from_source should remove can_fly from haste_spell")
	assert(not f.has_flag("is_hasted"),
		"EntityFlags: clear_all_from_source should remove is_hasted from haste_spell")
	assert(f.has_flag("is_invisible"),
		"EntityFlags: clear_all_from_source should NOT affect flags from other sources")


func test_has_flag_false_when_not_set() -> void:
	var f := EntityFlags.new()
	assert(not f.has_flag("can_fly"),
		"EntityFlags: has_flag should return false for unset flag")


func test_get_flag_sources() -> void:
	var f := EntityFlags.new()
	f.set_flag("can_fly", "fly_spell")
	f.set_flag("can_fly", "magic_carpet")
	var sources := f.get_flag_sources("can_fly")
	assert(sources.size() == 2,
		"EntityFlags: get_flag_sources should return 2 sources, got %d" % sources.size())
	assert("fly_spell" in sources,
		"EntityFlags: fly_spell should be in sources")
	assert("magic_carpet" in sources,
		"EntityFlags: magic_carpet should be in sources")


func test_get_flag_metadata() -> void:
	var f := EntityFlags.new()
	f.set_flag("is_invisible", "invis_spell", { "break_on_attack": true })
	var meta := f.get_flag_metadata("is_invisible")
	assert(meta.get("break_on_attack", false) == true,
		"EntityFlags: get_flag_metadata should return stored metadata")


func test_set_flag_updates_existing_source_metadata() -> void:
	var f := EntityFlags.new()
	f.set_flag("is_invisible", "invis_spell", { "break_on_attack": true })
	f.set_flag("is_invisible", "invis_spell", { "break_on_attack": false })  # update
	var meta := f.get_flag_metadata("is_invisible")
	assert(meta.get("break_on_attack", true) == false,
		"EntityFlags: re-setting same source should update metadata")
	assert(f.get_flag_sources("is_invisible").size() == 1,
		"EntityFlags: re-setting same source should not duplicate it")


func test_get_all_flags() -> void:
	var f := EntityFlags.new()
	f.set_flag("can_fly", "s1")
	f.set_flag("is_invisible", "s2")
	f.set_flag("is_hasted", "s3")
	var all_flags := f.get_all_flags()
	assert(all_flags.size() == 3,
		"EntityFlags: get_all_flags should return 3 flags, got %d" % all_flags.size())
	assert("can_fly" in all_flags, "EntityFlags: can_fly should be in all_flags")
	assert("is_invisible" in all_flags, "EntityFlags: is_invisible should be in all_flags")
	assert("is_hasted" in all_flags, "EntityFlags: is_hasted should be in all_flags")


func test_clear_all() -> void:
	var f := EntityFlags.new()
	f.set_flag("can_fly", "s1")
	f.set_flag("is_invisible", "s2")
	f.clear()
	assert(f.get_all_flags().is_empty(),
		"EntityFlags: after clear(), all flags should be gone")


func test_clear_nonexistent_flag_is_safe() -> void:
	var f := EntityFlags.new()
	f.clear_flag("can_fly", "nonexistent")  # should not crash
	f.clear_all_from_source("nobody")       # should not crash
	assert(true, "EntityFlags: clearing nonexistent flags should not crash")
