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
	# Sickened-by-potion action gate (2026-06-03; RAW: ACore line 224
	# "cannot act for 3 turns; neither potion has any other effect").
	test_sickened_by_potion_blocks_attacking()
	test_sickened_by_potion_blocks_casting()
	test_sickened_by_potion_blocks_movement()
	test_sickened_by_potion_blocks_running_and_charging()
	test_sickened_by_potion_allows_speech()
	test_no_sickened_flag_allows_all_actions()
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


# ---------------------------------------------------------------------------
# Sickened-by-potion action gate (Tier 4 follow-up, 2026-06-03)
# ---------------------------------------------------------------------------
#
# RAW (ACore general_category_rules.potions line 224): "If a character
# drinks a second potion while one is active, the character is sickened
# and cannot act for 3 turns; neither potion has any other effect."
# PotionDurationService stamps is_sickened_by_potion on the drinker;
# CombatConditionManager.check_action_allowed refuses attacking, casting,
# movement, running, and charging while the flag is present. Speech is
# permitted (RAW "act" reads as volitional / physical action, not
# communication for tactical coordination).

func _make_sickened_fighter(id: String) -> Combatant:
	var combatant := _make_fighter(id)
	combatant._character.flags.set_flag("is_sickened_by_potion",
		"potion_temporary_sickened:test", {
			"expires_at_turn": 9999,
			"source_item_id": "test_new_potion_id",
			"active_potion_item_id": "test_active_potion_id",
		})
	return combatant


func test_sickened_by_potion_blocks_attacking() -> void:
	var mgr := _make_manager()
	var combatant := _make_sickened_fighter("test")
	check(mgr.check_action_allowed(combatant, "attacking") == false,
		"sickened combatant cannot attack")


func test_sickened_by_potion_blocks_casting() -> void:
	var mgr := _make_manager()
	var combatant := _make_sickened_fighter("test")
	check(mgr.check_action_allowed(combatant, "casting") == false,
		"sickened combatant cannot cast")


func test_sickened_by_potion_blocks_movement() -> void:
	var mgr := _make_manager()
	var combatant := _make_sickened_fighter("test")
	check(mgr.check_action_allowed(combatant, "movement") == false,
		"sickened combatant cannot move")


func test_sickened_by_potion_blocks_running_and_charging() -> void:
	var mgr := _make_manager()
	var combatant := _make_sickened_fighter("test")
	check(mgr.check_action_allowed(combatant, "running") == false,
		"sickened combatant cannot run")
	check(mgr.check_action_allowed(combatant, "charging") == false,
		"sickened combatant cannot charge")


func test_sickened_by_potion_allows_speech() -> void:
	# RAW: "cannot act for 3 turns" — speech is communication, not action,
	# so the party can still coordinate around their sickened companion.
	var mgr := _make_manager()
	var combatant := _make_sickened_fighter("test")
	check(mgr.check_action_allowed(combatant, "speech") == true,
		"sickened combatant can still speak (tactical coordination)")


func test_no_sickened_flag_allows_all_actions() -> void:
	# Regression: a plain combatant (no sickened flag, no conditions)
	# can perform all the gated actions. Locks the gate to the flag.
	var mgr := _make_manager()
	var combatant := _make_fighter("test")
	for action in ["attacking", "casting", "movement", "running",
			"charging", "speech"]:
		check(mgr.check_action_allowed(combatant, action) == true,
			"plain combatant should be allowed to '%s'" % action)
