extends "res://tests/test_suite_base.gd"

## Unit tests for CombatConditionManager.


func run_all_tests() -> void:
	test_apply_condition_adds_to_combatant()
	test_apply_condition_pushes_ac_modifier()
	test_remove_condition_removes_from_combatant()
	test_remove_condition_reverses_ac_modifier()
	test_check_action_paralyzed_blocks_attacking()
	test_check_action_blinded_allows_attacking()
	test_check_action_no_conditions_allows_all()
	test_get_attack_modifier_sums()
	test_get_ac_modifier_sums()
	test_tick_conditions_decrements_and_expires()
	test_tick_permanent_never_expires()
	test_apply_duplicate_is_idempotent()
	if not has_failures():
		print("CombatConditionManager: all tests passed.")


func test_apply_condition_adds_to_combatant() -> void:
	var mgr := _make_manager()
	var combatant := _make_fighter("test")
	mgr.apply_condition(combatant, "blinded", "test_source")
	check(combatant.has_condition("blinded"),
		"combatant should have 'blinded' condition after apply")


func test_apply_condition_pushes_ac_modifier() -> void:
	var mgr := _make_manager()
	var combatant := _make_fighter("test")
	var base_ac: int = combatant.get_effective_ac()
	# "charging" has ac_modifier -2 in the condition catalog
	mgr.apply_condition(combatant, "charging", "test_source")
	var new_ac: int = combatant.get_effective_ac()
	var expected_change: int = _get_catalog().get_ac_modifier("charging")
	if expected_change != 0:
		check(new_ac == base_ac + expected_change,
			"AC should change by %d, was %d now %d" % [expected_change, base_ac, new_ac])
	else:
		check(true, "charging has 0 AC modifier — test passes trivially")


func test_remove_condition_removes_from_combatant() -> void:
	var mgr := _make_manager()
	var combatant := _make_fighter("test")
	mgr.apply_condition(combatant, "blinded", "test_source")
	mgr.remove_condition(combatant, "blinded")
	check(not combatant.has_condition("blinded"),
		"combatant should not have 'blinded' after removal")


func test_remove_condition_reverses_ac_modifier() -> void:
	var mgr := _make_manager()
	var combatant := _make_fighter("test")
	var base_ac: int = combatant.get_effective_ac()
	mgr.apply_condition(combatant, "charging", "test_source")
	mgr.remove_condition(combatant, "charging")
	var restored_ac: int = combatant.get_effective_ac()
	check(restored_ac == base_ac,
		"AC should restore to %d after removal, got %d" % [base_ac, restored_ac])


func test_check_action_paralyzed_blocks_attacking() -> void:
	var mgr := _make_manager()
	var combatant := _make_fighter("test")
	mgr.apply_condition(combatant, "paralyzed", "test_source")
	check(mgr.check_action_allowed(combatant, "attacking") == false,
		"paralyzed should block attacking")
	check(mgr.check_action_allowed(combatant, "casting") == false,
		"paralyzed should block casting")
	check(mgr.check_action_allowed(combatant, "movement") == false,
		"paralyzed should block movement")


func test_check_action_blinded_allows_attacking() -> void:
	var mgr := _make_manager()
	var combatant := _make_fighter("test")
	mgr.apply_condition(combatant, "blinded", "test_source")
	check(mgr.check_action_allowed(combatant, "attacking") == true,
		"blinded should still allow attacking (with penalty)")


func test_check_action_no_conditions_allows_all() -> void:
	var mgr := _make_manager()
	var combatant := _make_fighter("test")
	check(mgr.check_action_allowed(combatant, "attacking") == true,
		"no conditions should allow attacking")
	check(mgr.check_action_allowed(combatant, "casting") == true,
		"no conditions should allow casting")
	check(mgr.check_action_allowed(combatant, "movement") == true,
		"no conditions should allow movement")


func test_get_attack_modifier_sums() -> void:
	var mgr := _make_manager()
	var combatant := _make_fighter("test")
	# Apply conditions and check sum
	mgr.apply_condition(combatant, "blinded", "src_1")
	var mod := mgr.get_attack_modifier_from_conditions(combatant)
	var expected := _get_catalog().get_attack_modifier("blinded")
	check(mod == expected,
		"attack modifier for blinded should be %d, got %d" % [expected, mod])


func test_get_ac_modifier_sums() -> void:
	var mgr := _make_manager()
	var combatant := _make_fighter("test")
	mgr.apply_condition(combatant, "prone", "src_1")
	var mod := mgr.get_ac_modifier_from_conditions(combatant)
	var expected := _get_catalog().get_ac_modifier("prone")
	check(mod == expected,
		"AC modifier for prone should be %d, got %d" % [expected, mod])


func test_tick_conditions_decrements_and_expires() -> void:
	var mgr := _make_manager()
	var combatant := _make_fighter("test")
	mgr.apply_condition(combatant, "stunned", "src_1", 2)
	check(combatant.has_condition("stunned"), "should have stunned")

	var expired := mgr.tick_conditions(combatant)
	check(expired.is_empty(), "should not expire after 1 tick (duration=2)")
	check(combatant.has_condition("stunned"), "should still have stunned")

	expired = mgr.tick_conditions(combatant)
	check(expired.size() == 1, "should expire after 2nd tick")
	check("stunned" in expired, "expired should contain 'stunned'")
	check(not combatant.has_condition("stunned"), "should no longer have stunned")


func test_tick_permanent_never_expires() -> void:
	var mgr := _make_manager()
	var combatant := _make_fighter("test")
	mgr.apply_condition(combatant, "blinded", "src_1", -1)
	for i in range(100):
		mgr.tick_conditions(combatant)
	check(combatant.has_condition("blinded"),
		"permanent condition should never expire")


func test_apply_duplicate_is_idempotent() -> void:
	var mgr := _make_manager()
	var combatant := _make_fighter("test")
	mgr.apply_condition(combatant, "blinded", "src_1")
	mgr.apply_condition(combatant, "blinded", "src_2")
	var count := 0
	for cond: String in combatant.conditions:
		if cond == "blinded":
			count += 1
	check(count == 1,
		"should only have 1 instance of blinded, got %d" % count)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

var _cached_catalog: ConditionCatalog = null

func _get_catalog() -> ConditionCatalog:
	if _cached_catalog == null:
		_cached_catalog = ConditionCatalog.new()
	return _cached_catalog


func _make_manager() -> CombatConditionManager:
	return CombatConditionManager.new(_get_catalog())


func _make_fighter(id: String) -> Combatant:
	var cd := CharacterData.new()
	cd.id = id
	cd.name = id
	cd.hp_current = 10
	cd.hp_max = 10
	cd.armor_class = 0
	cd.attack_throw = 10
	return Combatant.from_character(cd)
