extends "res://tests/test_suite_base.gd"

## Unit tests for ModifierStack and ModifierContainer.


func run_all_tests() -> void:
	# ModifierStack tests
	test_add_single_modifier()
	test_add_multiple_ungrouped()
	test_stacking_group_highest_wins()
	test_stacking_group_same_value_higher_priority_wins()
	test_ungrouped_and_grouped_together()
	test_multiply_operation()
	test_set_floor_operation()
	test_set_ceiling_operation()
	test_floor_and_ceiling_combined()
	test_remove_by_source()
	test_has_source()
	test_clear()
	test_returns_int_for_int_base()
	test_negative_add_modifier()
	# `set` operation (2026-05-29 — for Gauntlets of Ogre Power, Cursed
	# Bracers, and other RAW REPLACEMENT mechanics).
	test_set_overrides_base_value()
	test_set_overrides_add_modifiers()
	test_set_overrides_multiply_and_floor()
	test_set_multiple_highest_priority_wins()
	test_set_curse_dominates_normal_set()
	# ModifierContainer tests
	test_container_add_and_get()
	test_container_remove_all_from_source()
	test_container_has_modifier_from()
	test_container_no_modifier_returns_base()
	test_container_multiple_stats()
	if not has_failures():
		print("ModifierStack: all tests passed.")


# ---------------------------------------------------------------------------
# ModifierStack tests
# ---------------------------------------------------------------------------

func _make_add(source_id: String, value, group: String = "", priority: int = 0) -> Dictionary:
	return { "source_id": source_id, "source_type": "spell", "operation": "add",
		"value": value, "stacking_group": group, "priority": priority }


func _make_mul(source_id: String, value: float) -> Dictionary:
	return { "source_id": source_id, "source_type": "spell", "operation": "multiply",
		"value": value, "stacking_group": "", "priority": 0 }


func _make_floor(source_id: String, value) -> Dictionary:
	return { "source_id": source_id, "source_type": "spell", "operation": "set_floor",
		"value": value, "stacking_group": "", "priority": 0 }


func _make_ceil(source_id: String, value) -> Dictionary:
	return { "source_id": source_id, "source_type": "spell", "operation": "set_ceiling",
		"value": value, "stacking_group": "", "priority": 0 }


## `set` operation — replaces the entire computed result. Multiple sets
## resolve by highest priority. Used for replacement mechanics like
## Gauntlets of Ogre Power (STR = 18) and Cursed Bracers (AC = 0).
func _make_set(source_id: String, value, priority: int = 0) -> Dictionary:
	return { "source_id": source_id, "source_type": "item", "operation": "set",
		"value": value, "stacking_group": "", "priority": priority }


func test_add_single_modifier() -> void:
	var s := ModifierStack.new()
	s.add_modifier(_make_add("s1", 2))
	check(s.calculate(10) == 12,
		"ModifierStack: single +2 add should give 12 from base 10, got %d" % s.calculate(10))


func test_add_multiple_ungrouped() -> void:
	var s := ModifierStack.new()
	s.add_modifier(_make_add("s1", 2))
	s.add_modifier(_make_add("s2", 3))
	check(s.calculate(10) == 15,
		"ModifierStack: two ungrouped adds +2+3 should give 15, got %d" % s.calculate(10))


func test_stacking_group_highest_wins() -> void:
	var s := ModifierStack.new()
	s.add_modifier(_make_add("s1", 1, "protection"))  # Ring of Protection +1
	s.add_modifier(_make_add("s2", 2, "protection"))  # Protection from Evil +2 (higher)
	# Only +2 should apply
	check(s.calculate(10) == 12,
		"ModifierStack: stacking group should take highest (+2), got %d" % s.calculate(10))


func test_stacking_group_same_value_higher_priority_wins() -> void:
	var s := ModifierStack.new()
	s.add_modifier(_make_add("s1", 1, "protection", 0))
	s.add_modifier(_make_add("s2", 1, "protection", 5))  # same value, higher priority
	# Still only +1 applied (same value, priority just breaks tie)
	check(s.calculate(10) == 11,
		"ModifierStack: equal stacking group values should apply only once, got %d" % s.calculate(10))


func test_ungrouped_and_grouped_together() -> void:
	var s := ModifierStack.new()
	s.add_modifier(_make_add("s1", 1, "protection"))  # group: only highest
	s.add_modifier(_make_add("s2", 2, "protection"))  # group: +2 wins
	s.add_modifier(_make_add("s3", 4))                 # ungrouped: +4
	# Total: +2 (protection group) + 4 (ungrouped) = +6
	check(s.calculate(10) == 16,
		"ModifierStack: grouped + ungrouped should give 16, got %d" % s.calculate(10))


func test_multiply_operation() -> void:
	var s := ModifierStack.new()
	s.add_modifier(_make_mul("haste", 2.0))
	check(s.calculate(60) == 120,
		"ModifierStack: ×2 multiply on 60 should give 120, got %d" % s.calculate(60))


func test_set_floor_operation() -> void:
	var s := ModifierStack.new()
	s.add_modifier(_make_add("s1", -8))   # would take 10 to 2
	s.add_modifier(_make_floor("s2", 5))  # but floor is 5
	check(s.calculate(10) == 5,
		"ModifierStack: set_floor should prevent result going below 5, got %d" % s.calculate(10))


func test_set_ceiling_operation() -> void:
	var s := ModifierStack.new()
	s.add_modifier(_make_add("s1", 10))   # would take 10 to 20
	s.add_modifier(_make_ceil("s2", 15))  # but ceiling is 15
	check(s.calculate(10) == 15,
		"ModifierStack: set_ceiling should cap result at 15, got %d" % s.calculate(10))


func test_floor_and_ceiling_combined() -> void:
	var s := ModifierStack.new()
	s.add_modifier(_make_floor("s1", 0))
	s.add_modifier(_make_ceil("s2", 0))
	# Floor and ceiling at 0 means result is always 0
	check(s.calculate(10) == 0,
		"ModifierStack: floor=ceiling=0 should produce 0, got %d" % s.calculate(10))


func test_remove_by_source() -> void:
	var s := ModifierStack.new()
	s.add_modifier(_make_add("s1", 3))
	s.add_modifier(_make_add("s2", 5))
	s.remove_by_source("s1")
	check(s.calculate(10) == 15,
		"ModifierStack: after removing s1 (+3), result should be 15, got %d" % s.calculate(10))


func test_has_source() -> void:
	var s := ModifierStack.new()
	s.add_modifier(_make_add("s1", 1))
	check(s.has_source("s1"),
		"ModifierStack: has_source should return true for s1")
	check(not s.has_source("s99"),
		"ModifierStack: has_source should return false for unknown source")


func test_clear() -> void:
	var s := ModifierStack.new()
	s.add_modifier(_make_add("s1", 5))
	s.clear()
	check(s.calculate(10) == 10,
		"ModifierStack: after clear, calculate should return base value 10, got %d" % s.calculate(10))


func test_returns_int_for_int_base() -> void:
	var s := ModifierStack.new()
	s.add_modifier(_make_mul("s1", 2.5))
	var result = s.calculate(4)  # 4 * 2.5 = 10.0 -> rounds to 10
	check(result is int,
		"ModifierStack: int base should return int, got %s" % type_string(typeof(result)))
	check(result == 10,
		"ModifierStack: 4 × 2.5 rounded should be 10, got %d" % result)


func test_negative_add_modifier() -> void:
	var s := ModifierStack.new()
	s.add_modifier(_make_add("bane", -1))
	check(s.calculate(12) == 11,
		"ModifierStack: -1 add on 12 should give 11, got %d" % s.calculate(12))


# ---------------------------------------------------------------------------
# `set` operation (2026-05-29)
# ---------------------------------------------------------------------------

func test_set_overrides_base_value() -> void:
	# Gauntlets of Ogre Power: STR set to 18, regardless of base STR.
	var s := ModifierStack.new()
	s.add_modifier(_make_set("gauntlets_of_ogre_power", 18))
	check(s.calculate(10) == 18, "base 10 + set 18 = 18, got %d" % s.calculate(10))
	check(s.calculate(15) == 18, "base 15 + set 18 = 18, got %d" % s.calculate(15))


func test_set_overrides_add_modifiers() -> void:
	# `set` runs after ADD; ADD modifiers are overridden, not compounded.
	var s := ModifierStack.new()
	s.add_modifier(_make_add("buff_a", 5))    # +5
	s.add_modifier(_make_add("buff_b", 3))    # +3
	s.add_modifier(_make_set("gauntlets", 18))
	# Without set: base 10 + 5 + 3 = 18 (would coincidentally equal set).
	# Without set: base 20 + 5 + 3 = 28, but set forces 18.
	check(s.calculate(20) == 18,
		"set should override adds (base 20 + 5 + 3 set 18 = 18), got %d" % s.calculate(20))


func test_set_overrides_multiply_and_floor() -> void:
	# `set` is the last word — multiply, set_floor, set_ceiling all
	# applied first, then `set` replaces the result.
	var s := ModifierStack.new()
	s.add_modifier(_make_mul("haste", 2.0))
	s.add_modifier(_make_floor("min_speed", 100))
	s.add_modifier(_make_set("cursed_slow", 5))   # AC dropped to 5 by a curse
	# Without set: base 40 × 2 = 80, then floor 100 → 100.
	# With set: 100 → replaced with 5.
	check(s.calculate(40) == 5,
		"set should win over multiply + floor (would be 100 without set), got %d" %
			s.calculate(40))


func test_set_multiple_highest_priority_wins() -> void:
	# Two set modifiers — highest priority wins.
	var s := ModifierStack.new()
	s.add_modifier(_make_set("low_priority", 10, 0))
	s.add_modifier(_make_set("high_priority", 99, 50))
	check(s.calculate(5) == 99,
		"priority 50 (99) should beat priority 0 (10), got %d" % s.calculate(5))


func test_set_curse_dominates_normal_set() -> void:
	# Real-world Cursed Bracers scenario: Gauntlets of Ogre Power set STR
	# to 18 at default priority 0; a hypothetical Cursed Helm sets STR to
	# 3 (mind-curse) at priority 100. The curse wins because higher prio.
	var s := ModifierStack.new()
	s.add_modifier(_make_set("gauntlets", 18, 0))         # normal set
	s.add_modifier(_make_set("cursed_mind_warp", 3, 100)) # curse priority
	check(s.calculate(14) == 3,
		"curse (prio 100) should dominate normal set (prio 0), got %d" % s.calculate(14))


# ---------------------------------------------------------------------------
# ModifierContainer tests
# ---------------------------------------------------------------------------

func test_container_add_and_get() -> void:
	var c := ModifierContainer.new()
	c.add_modifier("armor_class", _make_add("prot_evil", 1, "protection"))
	var result = c.get_effective_value("armor_class", 5)
	check(result == 6,
		"ModifierContainer: base AC 5 + prot_evil +1 should be 6, got %d" % result)


func test_container_remove_all_from_source() -> void:
	var c := ModifierContainer.new()
	c.add_modifier("armor_class", _make_add("bless", 1))
	c.add_modifier("attack_throw", _make_add("bless", -1))  # bless also lowers attack target
	c.remove_all_from_source("bless")
	check(c.get_effective_value("armor_class", 5) == 5,
		"ModifierContainer: after removing bless, AC modifier should be gone")
	check(c.get_effective_value("attack_throw", 10) == 10,
		"ModifierContainer: after removing bless, attack_throw modifier should be gone")


func test_container_has_modifier_from() -> void:
	var c := ModifierContainer.new()
	c.add_modifier("save_spells", _make_add("shield", 2))
	check(c.has_modifier_from("shield"),
		"ModifierContainer: has_modifier_from should return true for shield")
	check(not c.has_modifier_from("unknown"),
		"ModifierContainer: has_modifier_from should return false for unknown source")


func test_container_no_modifier_returns_base() -> void:
	var c := ModifierContainer.new()
	var result = c.get_effective_value("armor_class", 7)
	check(result == 7,
		"ModifierContainer: no modifier should return base value 7, got %d" % result)


func test_container_multiple_stats() -> void:
	var c := ModifierContainer.new()
	c.add_modifier("armor_class", _make_add("prayer", 1))
	c.add_modifier("attack_throw", _make_add("prayer", -1))
	c.add_modifier("save_spells", _make_add("prayer", 1))
	check(c.get_effective_value("armor_class", 5) == 6,
		"ModifierContainer: prayer AC modifier correct")
	check(c.get_effective_value("attack_throw", 10) == 9,
		"ModifierContainer: prayer attack_throw modifier correct")
	check(c.get_effective_value("save_spells", 14) == 15,
		"ModifierContainer: prayer save_spells modifier correct")
