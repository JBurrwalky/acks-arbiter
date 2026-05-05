extends "res://tests/test_suite_base.gd"

## Unit tests for TargetingController — eligibility filtering, HD-budget
## tracking, lowest-first selection ordering, count caps, area cells.


# Fake DiceSystem with fixed roll values per roll_type. Identical pattern to
# the one in test_casting_resolver.gd but local to this suite.
class _FakeDice extends RefCounted:
	var fixed: Dictionary = {}

	func set_fixed(roll_type: String, value: int) -> void:
		fixed[roll_type] = value

	func roll_expression(_expression: String, roll_type: String = "") -> RollResult:
		var r := RollResult.new()
		r.roll_type = roll_type
		r.modified_total = int(fixed.get(roll_type, 0))
		r.raw_total = r.modified_total
		return r

	func roll_digital(sides: int, count: int = 1, modifier: int = 0, roll_type: String = "") -> RollResult:
		var r := RollResult.new()
		r.modified_total = int(fixed.get(roll_type, count * sides))
		r.raw_total = r.modified_total - modifier
		return r


func run_all_tests() -> void:
	test_single_target_eligible()
	test_single_target_out_of_range()
	test_creature_filter_excludes_undead()
	test_creature_filter_max_size()
	test_hd_budget_tracks_remaining()
	test_hd_budget_rejects_over_budget()
	test_hd_budget_refunds_on_deselect()
	test_lowest_hd_first_blocks_skipping_smaller()
	test_lowest_hd_first_allows_after_smaller_picked()
	test_count_cap_per_level_scaling()
	test_count_cap_blocks_extra()
	test_area_at_point_collects_entities_in_cells()
	test_area_from_caster_uses_caster_position()
	test_self_kind_returns_caster_only()
	test_reset_selection_restores_budget()
	if not has_failures():
		print("TargetingController: all tests passed.")


# Fixtures ------------------------------------------------------------------

func _kobold(name: String = "Kobold") -> Dictionary:
	return {"hit_dice": {"base": 0.5, "modifier": 0}, "name": name}


func _goblin(name: String = "Goblin") -> Dictionary:
	return {"hit_dice": {"base": 1, "modifier": 0}, "name": name}


func _bugbear(name: String = "Bugbear") -> Dictionary:
	return {"hit_dice": {"base": 3, "modifier": 1}, "name": name}


func _ogre_4_plus_1(name: String = "Ogre") -> Dictionary:
	return {"hit_dice": {"base": 4, "modifier": 1}, "name": name}


func _skeleton() -> Dictionary:
	return {"hit_dice": {"base": 1, "modifier": 0}, "name": "Skeleton", "monster_type": "undead"}


# Tests ---------------------------------------------------------------------

func test_single_target_eligible() -> void:
	var spec := {"kind": "single_creature", "count": 1}
	var ctl := TargetingController.new(spec, Vector3i(0, 0, 0), 5, _FakeDice.new())
	ctl.add_candidate("g1", _goblin(), Vector3i(2, 0, 0))
	ctl.begin()
	var result := ctl.try_select("g1")
	check(result.accepted, "single_creature: goblin should be selectable")


func test_single_target_out_of_range() -> void:
	var spec := {"kind": "single_creature", "count": 1, "range_feet": 30}
	var ctl := TargetingController.new(spec, Vector3i(0, 0, 0), 1, _FakeDice.new())
	# 8 cells × 5ft = 40 ft, out of 30ft range
	ctl.add_candidate("far", _goblin(), Vector3i(8, 0, 0))
	ctl.begin()
	var result := ctl.try_select("far")
	check(not result.accepted, "out of range: should reject")
	check("range" in result.reason, "out of range: reason mentions range, got '%s'" % result.reason)


func test_creature_filter_excludes_undead() -> void:
	var spec := {
		"kind": "multiple_creatures_hd_budget",
		"hd_budget": {"formula": "2d8"},
		"creature_filter": {"living_only": true, "excludes_type": ["undead"]}
	}
	var dice := _FakeDice.new()
	dice.set_fixed("spell_hd_budget", 6)
	var ctl := TargetingController.new(spec, Vector3i(0, 0, 0), 1, dice)
	ctl.add_candidate("g1", _goblin(), Vector3i(1, 0, 0))
	ctl.add_candidate("sk1", _skeleton(), Vector3i(2, 0, 0))
	ctl.begin()
	check(not ctl.try_select("sk1").accepted,
		"creature_filter: skeleton excluded (undead)")
	check(ctl.try_select("g1").accepted,
		"creature_filter: goblin allowed")


func test_creature_filter_max_size() -> void:
	# Charm Person caps at "ogre" size; large creatures excluded.
	var spec := {
		"kind": "single_creature", "count": 1,
		"creature_filter": {"max_size": "ogre", "living_only": true}
	}
	var huge := {"hit_dice": {"base": 3, "modifier": 0}, "size_category": "huge", "name": "Giant"}
	var ctl := TargetingController.new(spec, Vector3i(0, 0, 0), 1, _FakeDice.new())
	ctl.add_candidate("huge1", huge, Vector3i(1, 0, 0))
	ctl.begin()
	var result := ctl.try_select("huge1")
	check(not result.accepted, "max_size ogre: huge giant rejected")


func test_hd_budget_tracks_remaining() -> void:
	var spec := {
		"kind": "multiple_creatures_hd_budget",
		"hd_budget": {"formula": "2d8"},
		"sub_1_hd_counts_as": 1,
		"ignore_hd_bonus_in_count": true,
	}
	var dice := _FakeDice.new()
	dice.set_fixed("spell_hd_budget", 6)
	var ctl := TargetingController.new(spec, Vector3i(0, 0, 0), 1, dice)
	ctl.add_candidate("g1", _goblin(), Vector3i(1, 0, 0))
	ctl.add_candidate("g2", _goblin(), Vector3i(2, 0, 0))
	ctl.begin()
	check(ctl.get_budget_total() == 6.0, "budget total 6")
	var r1 := ctl.try_select("g1")
	check(r1.accepted, "g1 accepted")
	check(ctl.get_budget_remaining() == 5.0,
		"budget after g1 should be 5, got %.1f" % ctl.get_budget_remaining())


func test_hd_budget_rejects_over_budget() -> void:
	var spec := {
		"kind": "multiple_creatures_hd_budget",
		"hd_budget": {"formula": "2d8"},
		"sub_1_hd_counts_as": 1,
		"ignore_hd_bonus_in_count": true,
	}
	var dice := _FakeDice.new()
	dice.set_fixed("spell_hd_budget", 2)
	var ctl := TargetingController.new(spec, Vector3i(0, 0, 0), 1, dice)
	ctl.add_candidate("bug1", _bugbear(), Vector3i(1, 0, 0))  # base 3 → counted 3 (bonus ignored)
	ctl.begin()
	var r := ctl.try_select("bug1")
	check(not r.accepted, "bugbear (3 HD) over budget 2: rejected")


func test_hd_budget_refunds_on_deselect() -> void:
	var spec := {
		"kind": "multiple_creatures_hd_budget",
		"hd_budget": {"formula": "2d8"},
		"ignore_hd_bonus_in_count": true,
		"sub_1_hd_counts_as": 1,
	}
	var dice := _FakeDice.new()
	dice.set_fixed("spell_hd_budget", 5)
	var ctl := TargetingController.new(spec, Vector3i(0, 0, 0), 1, dice)
	ctl.add_candidate("g1", _goblin(), Vector3i(1, 0, 0))
	ctl.begin()
	ctl.try_select("g1")
	check(ctl.get_budget_remaining() == 4.0, "after select: 4 remaining")
	var d := ctl.deselect("g1")
	check(d.removed, "deselect removed=true")
	check(ctl.get_budget_remaining() == 5.0,
		"after deselect: 5 remaining, got %.1f" % ctl.get_budget_remaining())


func test_lowest_hd_first_blocks_skipping_smaller() -> void:
	var spec := {
		"kind": "multiple_creatures_hd_budget",
		"hd_budget": {"formula": "2d8"},
		"selection_order": "lowest_hd_first",
		"sub_1_hd_counts_as": 1,
		"ignore_hd_bonus_in_count": true,
		"hd_cap_per_target": 4,
	}
	var dice := _FakeDice.new()
	dice.set_fixed("spell_hd_budget", 10)
	var ctl := TargetingController.new(spec, Vector3i(0, 0, 0), 1, dice)
	ctl.add_candidate("k1", _kobold(), Vector3i(1, 0, 0))    # 1 HD counted (sub-1 → 1)
	ctl.add_candidate("g1", _goblin(), Vector3i(2, 0, 0))    # 1 HD
	ctl.add_candidate("bug1", _bugbear(), Vector3i(3, 0, 0)) # 3 HD (bonus ignored)
	ctl.begin()
	# Try to pick the bugbear first — should be blocked by lowest_hd_first.
	var r := ctl.try_select("bug1")
	check(not r.accepted, "lowest_hd_first: bugbear blocked while smaller available")
	check("lowest" in r.reason, "reason mentions lowest, got '%s'" % r.reason)


func test_lowest_hd_first_allows_after_smaller_picked() -> void:
	var spec := {
		"kind": "multiple_creatures_hd_budget",
		"hd_budget": {"formula": "2d8"},
		"selection_order": "lowest_hd_first",
		"sub_1_hd_counts_as": 1,
		"ignore_hd_bonus_in_count": true,
		"hd_cap_per_target": 4,
	}
	var dice := _FakeDice.new()
	dice.set_fixed("spell_hd_budget", 10)
	var ctl := TargetingController.new(spec, Vector3i(0, 0, 0), 1, dice)
	ctl.add_candidate("k1", _kobold(), Vector3i(1, 0, 0))
	ctl.add_candidate("g1", _goblin(), Vector3i(2, 0, 0))
	ctl.add_candidate("bug1", _bugbear(), Vector3i(3, 0, 0))
	ctl.begin()
	ctl.try_select("k1")  # 1 HD picked
	ctl.try_select("g1")  # 1 HD picked
	var r := ctl.try_select("bug1")  # Now bugbear is the smallest unselected
	check(r.accepted, "lowest_hd_first: bugbear OK after smaller picked")


func test_count_cap_per_level_scaling() -> void:
	var spec := {
		"kind": "multiple_creatures_count",
		"count": "level",
	}
	var ctl := TargetingController.new(spec, Vector3i(0, 0, 0), 3, _FakeDice.new())
	for i in range(5):
		ctl.add_candidate("g%d" % i, _goblin(), Vector3i(i + 1, 0, 0))
	ctl.begin()
	check(ctl.try_select("g0").accepted, "1st pick OK")
	check(ctl.try_select("g1").accepted, "2nd pick OK")
	check(ctl.try_select("g2").accepted, "3rd pick OK at L3")
	check(not ctl.try_select("g3").accepted, "4th pick blocked at L3 (cap=level=3)")


func test_count_cap_blocks_extra() -> void:
	var spec := {"kind": "multiple_creatures_count", "count": 1}
	var ctl := TargetingController.new(spec, Vector3i(0, 0, 0), 5, _FakeDice.new())
	ctl.add_candidate("g1", _goblin(), Vector3i(1, 0, 0))
	ctl.add_candidate("g2", _goblin(), Vector3i(2, 0, 0))
	ctl.begin()
	ctl.try_select("g1")
	var r := ctl.try_select("g2")
	check(not r.accepted, "count=1: 2nd pick blocked")


func test_area_at_point_collects_entities_in_cells() -> void:
	# Sphere of diameter 20 ft = radius 2 cells around anchor.
	var spec := {
		"kind": "area_at_point",
		"geometry": {"shape": "sphere", "diameter_feet": 20},
	}
	var ctl := TargetingController.new(spec, Vector3i(0, 0, 0), 5, _FakeDice.new())
	ctl.add_candidate("near", _goblin(), Vector3i(11, 0, 0))   # inside 2-cell radius of anchor (10,0,0)
	ctl.add_candidate("far", _goblin(), Vector3i(20, 0, 0))    # outside
	ctl.begin()
	ctl.set_anchor_cell(Vector3i(10, 0, 0))
	var td := ctl.commit()
	check("near" in td.target_ids, "area_at_point: near goblin in target_ids")
	check(not ("far" in td.target_ids), "area_at_point: far goblin excluded")


func test_area_from_caster_uses_caster_position() -> void:
	var spec := {
		"kind": "area_from_caster",
		"geometry": {"shape": "sphere", "radius_feet": 10},
	}
	var ctl := TargetingController.new(spec, Vector3i(5, 5, 0), 1, _FakeDice.new())
	ctl.add_candidate("near", _goblin(), Vector3i(6, 5, 0))   # within 10 ft (2 cells)
	ctl.add_candidate("far", _goblin(), Vector3i(15, 5, 0))   # 50 ft away
	ctl.begin()
	var td := ctl.commit()
	check(td.origin_cell == Vector3i(5, 5, 0), "area_from_caster: origin = caster")
	check("near" in td.target_ids, "area_from_caster: near goblin in target_ids")
	check(not ("far" in td.target_ids), "area_from_caster: far goblin excluded")


func test_self_kind_returns_caster_only() -> void:
	var spec := {"kind": "self"}
	var ctl := TargetingController.new(spec, Vector3i(7, 7, 0), 1, _FakeDice.new())
	ctl.begin()
	var td := ctl.commit()
	check(td.kind == "self", "self kind preserved")
	check(td.origin_cell == Vector3i(7, 7, 0), "self origin = caster pos")


func test_reset_selection_restores_budget() -> void:
	var spec := {
		"kind": "multiple_creatures_hd_budget",
		"hd_budget": {"formula": "2d8"},
		"sub_1_hd_counts_as": 1,
		"ignore_hd_bonus_in_count": true,
	}
	var dice := _FakeDice.new()
	dice.set_fixed("spell_hd_budget", 6)
	var ctl := TargetingController.new(spec, Vector3i(0, 0, 0), 1, dice)
	ctl.add_candidate("g1", _goblin(), Vector3i(1, 0, 0))
	ctl.add_candidate("g2", _goblin(), Vector3i(2, 0, 0))
	ctl.begin()
	ctl.try_select("g1")
	ctl.try_select("g2")
	check(ctl.get_budget_remaining() == 4.0, "after 2 picks: 4 remain")
	ctl.reset_selection()
	check(ctl.get_budget_remaining() == 6.0, "after reset: 6 remain")
	check(ctl.get_selected().is_empty(), "after reset: selection empty")
