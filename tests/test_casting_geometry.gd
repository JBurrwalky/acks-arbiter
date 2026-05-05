extends "res://tests/test_suite_base.gd"

## Unit tests for CastingGeometry — HD counting rules and HD-budget rolls.


func run_all_tests() -> void:
	test_compute_counted_hd_sub_1_kobold()
	test_compute_counted_hd_4_plus_1_ogre_with_ignore_bonus()
	test_compute_counted_hd_no_ignore_bonus_keeps_bonus()
	test_compute_counted_hd_charm_monster_half_kobold()
	test_compute_counted_hd_pc_uses_level()
	test_compute_effective_hd_includes_bonus()
	test_is_within_hd_cap_max_hd_inclusive()
	test_is_within_hd_cap_min_hd()
	test_is_within_hd_cap_per_target()
	test_roll_hd_budget_formula_path()
	test_roll_hd_budget_fixed_path()
	test_roll_hd_budget_per_caster_level()
	test_distance_feet_uses_5ft_cells()
	if not has_failures():
		print("CastingGeometry: all tests passed.")


# Helpers -------------------------------------------------------------------

func _kobold() -> Dictionary:
	# 0.5 HD, no bonus
	return {"hit_dice": {"base": 0.5, "modifier": 0}}


func _ogre_4_plus_1() -> Dictionary:
	return {"hit_dice": {"base": 4, "modifier": 1}}


func _orc_4() -> Dictionary:
	return {"hit_dice": {"base": 4, "modifier": 0}}


func _pc_at_level(level: int) -> CharacterData:
	var cd := CharacterData.new()
	cd.id = "pc_l%d" % level
	cd.level = level
	return cd


# Tests ---------------------------------------------------------------------

func test_compute_counted_hd_sub_1_kobold() -> void:
	# Sleep group branch: sub_1_hd_counts_as: 1, ignore_hd_bonus_in_count: true.
	# A 0.5 HD kobold counts as 1 HD against the budget.
	var spec := {"sub_1_hd_counts_as": 1, "ignore_hd_bonus_in_count": true}
	var counted := CastingGeometry.compute_counted_hd(_kobold(), spec)
	check(counted == 1.0,
		"Sleep: 0.5 HD kobold should count as 1 HD against budget, got %.2f" % counted)


func test_compute_counted_hd_4_plus_1_ogre_with_ignore_bonus() -> void:
	# Sleep group branch: 4+1 ogre counted as 4 (bonus ignored).
	var spec := {"sub_1_hd_counts_as": 1, "ignore_hd_bonus_in_count": true}
	var counted := CastingGeometry.compute_counted_hd(_ogre_4_plus_1(), spec)
	check(counted == 4.0,
		"Sleep: 4+1 HD ogre should count as 4 HD (bonus ignored), got %.2f" % counted)


func test_compute_counted_hd_no_ignore_bonus_keeps_bonus() -> void:
	# Smite Undead default rules: bonus counted.
	var spec := {}
	var counted := CastingGeometry.compute_counted_hd(_ogre_4_plus_1(), spec)
	check(counted == 5.0,
		"Default: 4+1 HD should count as 5 HD (bonus counted), got %.2f" % counted)


func test_compute_counted_hd_charm_monster_half_kobold() -> void:
	# Charm Monster: sub_1_hd_counts_as: 0.5
	var spec := {"sub_1_hd_counts_as": 0.5, "ignore_hd_bonus_in_count": true}
	var counted := CastingGeometry.compute_counted_hd(_kobold(), spec)
	check(counted == 0.5,
		"Charm Monster: 0.5 HD kobold should count as 0.5 HD, got %.2f" % counted)


func test_compute_counted_hd_pc_uses_level() -> void:
	var pc := _pc_at_level(3)
	var counted := CastingGeometry.compute_counted_hd(pc, {})
	check(counted == 3.0,
		"PC: level 3 should count as 3 HD, got %.2f" % counted)


func test_compute_effective_hd_includes_bonus() -> void:
	check(CastingGeometry.compute_effective_hd(_ogre_4_plus_1()) == 5.0,
		"Effective HD of 4+1 ogre is 5")
	check(CastingGeometry.compute_effective_hd(_kobold()) == 0.5,
		"Effective HD of kobold is 0.5")


func test_is_within_hd_cap_max_hd_inclusive() -> void:
	# Sleep single branch: max_hd: 5 (4+1 ogre eligible, 5+1 champion not).
	var spec := {"max_hd": 5, "hd_cap_inclusive_of_bonus": true}
	check(CastingGeometry.is_within_hd_cap(_ogre_4_plus_1(), spec),
		"Sleep single: 4+1 ogre eligible (effective 5 ≤ max 5)")
	var champion := {"hit_dice": {"base": 5, "modifier": 1}}
	check(not CastingGeometry.is_within_hd_cap(champion, spec),
		"Sleep single: 5+1 champion rejected (effective 6 > max 5)")


func test_is_within_hd_cap_min_hd() -> void:
	var spec := {"min_hd": 5}
	check(not CastingGeometry.is_within_hd_cap(_orc_4(), spec),
		"Min HD 5: 4 HD orc rejected")
	var ogre := {"hit_dice": {"base": 5, "modifier": 0}}
	check(CastingGeometry.is_within_hd_cap(ogre, spec),
		"Min HD 5: 5 HD ogre eligible")


func test_is_within_hd_cap_per_target() -> void:
	# Sleep group: hd_cap_per_target: 4. 4+1 ogre rejected (effective 5 > 4).
	var spec := {"hd_cap_per_target": 4, "ignore_hd_bonus_in_count": true}
	check(not CastingGeometry.is_within_hd_cap(_ogre_4_plus_1(), spec),
		"Sleep group: 4+1 ogre rejected by cap (effective 5 > 4)")
	check(CastingGeometry.is_within_hd_cap(_orc_4(), spec),
		"Sleep group: 4 HD orc passes cap")


func test_roll_hd_budget_formula_path() -> void:
	# Override 2d8 → 11 deterministically.
	GameState.dice_overrides["spell_hd_budget"] = 11
	var budget := CastingGeometry.roll_hd_budget({"formula": "2d8"}, 1, DiceSystem)
	check(budget == 11.0,
		"roll_hd_budget formula 2d8 with override should be 11.0, got %.2f" % budget)


func test_roll_hd_budget_fixed_path() -> void:
	var budget := CastingGeometry.roll_hd_budget({"fixed": 12}, 5, DiceSystem)
	check(budget == 12.0,
		"roll_hd_budget fixed=12 should return 12.0, got %.2f" % budget)


func test_roll_hd_budget_per_caster_level() -> void:
	var budget := CastingGeometry.roll_hd_budget({"per_caster_level": true}, 7, DiceSystem)
	check(budget == 7.0,
		"roll_hd_budget per_caster_level at L7 should return 7.0, got %.2f" % budget)


func test_distance_feet_uses_5ft_cells() -> void:
	var a := Vector3i(0, 0, 0)
	var b := Vector3i(3, 0, 0)
	check(CastingGeometry.distance_feet(a, b) == 15,
		"Distance: 3 cells = 15 feet, got %d" % CastingGeometry.distance_feet(a, b))
	check(CastingGeometry.is_within_range(a, b, 15),
		"Range 15ft: 3 cells away should be in range")
	check(not CastingGeometry.is_within_range(a, b, 10),
		"Range 10ft: 3 cells away should be out of range")
