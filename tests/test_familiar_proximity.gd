extends "res://tests/test_suite_base.gd"

## Tests for FamiliarController proximity bonus.
##
## Verifies the +1-saves-while-within-30ft rule:
##   - Chebyshev distance ≤ 6 cells (= 30 ft) sets the flag and pushes -1
##     modifiers into master.modifiers for all five save categories.
##   - Distance > 6 cells clears flag + modifiers atomically.
##   - Idempotent: repeated set_proximity_state(true) doesn't stack modifiers.
##   - clear_proximity_for_master removes the bonus regardless of state.


func run_all_tests() -> void:
	test_within_range_at_zero_distance()
	test_within_range_at_six_cells_chebyshev()
	test_out_of_range_at_seven_cells()
	test_diagonal_six_cells_still_in_range()
	test_save_target_lower_when_in_range()
	test_set_proximity_state_idempotent_no_stacking()
	test_state_flips_off_when_moving_out()
	test_clear_proximity_for_master_removes_bonus()
	test_is_in_proximity_query()

	if not has_failures():
		print("FamiliarProximity: all tests passed.")


# --- Helpers ---

func _make_master() -> CharacterData:
	var c := CharacterData.new()
	c.id = "test_prox_master"
	c.campaign_id = "test_prox_camp"
	c.name = "Master"
	c.character_type = "pc"
	c.character_class = "mage"
	c.combat_progression = "mage"
	c.level = 3
	c.hp_max = 12
	c.hp_current = 12
	c.intelligence = 14
	# Defaults from CharacterData (NM/L0 baseline):
	#   save_petrification = 15, save_poison_death = 14, save_blast_breath = 16,
	#   save_staffs_wands = 16, save_spells = 17
	c.proficiencies = []
	# Reset the FamiliarController's per-master state map. The controller is an
	# autoload (single instance for the whole test run); the same master.id is
	# reused across tests, so without this reset the controller's idempotent
	# `if prev == in_range: return` guard would skip re-applying the bonus to
	# a fresh CharacterData whose flags+modifiers are empty.
	FamiliarController.clear_proximity_for_master(c)
	return c


# --- Tests ---

func test_within_range_at_zero_distance() -> void:
	var master := _make_master()
	var ok := FamiliarController.evaluate_proximity(master, Vector3i(5, 5, 0), Vector3i(5, 5, 0))
	check(ok == true, "0 cells should be in range")
	check(master.flags.has_flag(FamiliarController.PROXIMITY_FLAG),
		"familiar_within_30ft flag should be set on master")


func test_within_range_at_six_cells_chebyshev() -> void:
	var master := _make_master()
	# d=6 in one axis, 0 elsewhere — Chebyshev distance 6
	var ok := FamiliarController.evaluate_proximity(master, Vector3i(0, 0, 0), Vector3i(6, 0, 0))
	check(ok == true, "exactly 6 cells should be in range (inclusive)")
	check(master.flags.has_flag(FamiliarController.PROXIMITY_FLAG),
		"flag should be set at d=6")


func test_out_of_range_at_seven_cells() -> void:
	var master := _make_master()
	var ok := FamiliarController.evaluate_proximity(master, Vector3i(0, 0, 0), Vector3i(7, 0, 0))
	check(ok == false, "7 cells should be out of range")
	check(not master.flags.has_flag(FamiliarController.PROXIMITY_FLAG),
		"flag should NOT be set at d=7")


func test_diagonal_six_cells_still_in_range() -> void:
	var master := _make_master()
	# Chebyshev: max(|dx|, |dy|, |dz|) = 6 — diagonal counts the same
	var ok := FamiliarController.evaluate_proximity(master, Vector3i(0, 0, 0), Vector3i(6, 6, 0))
	check(ok == true, "Chebyshev: diagonal 6,6,0 should be d=6 (in range)")


func test_save_target_lower_when_in_range() -> void:
	var master := _make_master()
	var base_target: int = master.get_effective_save("save_poison_death")
	check(base_target == 14, "baseline save_poison_death should be 14, got %d" % base_target)

	FamiliarController.set_proximity_state(master, true)
	var bonused: int = master.get_effective_save("save_poison_death")
	check(bonused == 13, "with proximity bonus, save target should drop by 1 to 13, got %d" % bonused)

	# All five saves should drop by 1
	check(master.get_effective_save("save_petrification") == 14, "save_petrification 15 → 14")
	check(master.get_effective_save("save_blast_breath") == 15, "save_blast_breath 16 → 15")
	check(master.get_effective_save("save_staffs_wands") == 15, "save_staffs_wands 16 → 15")
	check(master.get_effective_save("save_spells") == 16, "save_spells 17 → 16")


func test_set_proximity_state_idempotent_no_stacking() -> void:
	var master := _make_master()
	FamiliarController.set_proximity_state(master, true)
	FamiliarController.set_proximity_state(master, true)
	FamiliarController.set_proximity_state(master, true)
	# After three sets, the bonus should still be -1, not -3
	var target: int = master.get_effective_save("save_poison_death")
	check(target == 13, "repeated set_proximity_state(true) must not stack — expected 13, got %d" % target)


func test_state_flips_off_when_moving_out() -> void:
	var master := _make_master()
	FamiliarController.evaluate_proximity(master, Vector3i(0, 0, 0), Vector3i(3, 0, 0))
	check(master.get_effective_save("save_poison_death") == 13, "in range → 13")

	# Move familiar far away
	FamiliarController.evaluate_proximity(master, Vector3i(0, 0, 0), Vector3i(20, 0, 0))
	check(not master.flags.has_flag(FamiliarController.PROXIMITY_FLAG), "flag cleared on move out")
	check(master.get_effective_save("save_poison_death") == 14, "back to baseline 14")


func test_clear_proximity_for_master_removes_bonus() -> void:
	var master := _make_master()
	FamiliarController.set_proximity_state(master, true)
	FamiliarController.clear_proximity_for_master(master)
	check(not master.flags.has_flag(FamiliarController.PROXIMITY_FLAG), "flag cleared")
	check(master.get_effective_save("save_poison_death") == 14, "modifiers cleared")
	check(FamiliarController.is_in_proximity(master.id) == false, "state map cleared")


func test_is_in_proximity_query() -> void:
	var master := _make_master()
	check(FamiliarController.is_in_proximity(master.id) == false, "default: not in proximity")
	FamiliarController.set_proximity_state(master, true)
	check(FamiliarController.is_in_proximity(master.id) == true, "set true → reports true")
	FamiliarController.set_proximity_state(master, false)
	check(FamiliarController.is_in_proximity(master.id) == false, "set false → reports false")
