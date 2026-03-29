extends Node

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
	# ModifierContainer tests
	test_container_add_and_get()
	test_container_remove_all_from_source()
	test_container_has_modifier_from()
	test_container_no_modifier_returns_base()
	test_container_multiple_stats()
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


func test_add_single_modifier() -> void:
	var s := ModifierStack.new()
	s.add_modifier(_make_add("s1", 2))
	assert(s.calculate(10) == 12,
		"ModifierStack: single +2 add should give 12 from base 10, got %d" % s.calculate(10))


func test_add_multiple_ungrouped() -> void:
	var s := ModifierStack.new()
	s.add_modifier(_make_add("s1", 2))
	s.add_modifier(_make_add("s2", 3))
	assert(s.calculate(10) == 15,
		"ModifierStack: two ungrouped adds +2+3 should give 15, got %d" % s.calculate(10))


func test_stacking_group_highest_wins() -> void:
	var s := ModifierStack.new()
	s.add_modifier(_make_add("s1", 1, "protection"))  # Ring of Protection +1
	s.add_modifier(_make_add("s2", 2, "protection"))  # Protection from Evil +2 (higher)
	# Only +2 should apply
	assert(s.calculate(10) == 12,
		"ModifierStack: stacking group should take highest (+2), got %d" % s.calculate(10))


func test_stacking_group_same_value_higher_priority_wins() -> void:
	var s := ModifierStack.new()
	s.add_modifier(_make_add("s1", 1, "protection", 0))
	s.add_modifier(_make_add("s2", 1, "protection", 5))  # same value, higher priority
	# Still only +1 applied (same value, priority just breaks tie)
	assert(s.calculate(10) == 11,
		"ModifierStack: equal stacking group values should apply only once, got %d" % s.calculate(10))


func test_ungrouped_and_grouped_together() -> void:
	var s := ModifierStack.new()
	s.add_modifier(_make_add("s1", 1, "protection"))  # group: only highest
	s.add_modifier(_make_add("s2", 2, "protection"))  # group: +2 wins
	s.add_modifier(_make_add("s3", 4))                 # ungrouped: +4
	# Total: +2 (protection group) + 4 (ungrouped) = +6
	assert(s.calculate(10) == 16,
		"ModifierStack: grouped + ungrouped should give 16, got %d" % s.calculate(10))


func test_multiply_operation() -> void:
	var s := ModifierStack.new()
	s.add_modifier(_make_mul("haste", 2.0))
	assert(s.calculate(60) == 120,
		"ModifierStack: ×2 multiply on 60 should give 120, got %d" % s.calculate(60))


func test_set_floor_operation() -> void:
	var s := ModifierStack.new()
	s.add_modifier(_make_add("s1", -8))   # would take 10 to 2
	s.add_modifier(_make_floor("s2", 5))  # but floor is 5
	assert(s.calculate(10) == 5,
		"ModifierStack: set_floor should prevent result going below 5, got %d" % s.calculate(10))


func test_set_ceiling_operation() -> void:
	var s := ModifierStack.new()
	s.add_modifier(_make_add("s1", 10))   # would take 10 to 20
	s.add_modifier(_make_ceil("s2", 15))  # but ceiling is 15
	assert(s.calculate(10) == 15,
		"ModifierStack: set_ceiling should cap result at 15, got %d" % s.calculate(10))


func test_floor_and_ceiling_combined() -> void:
	var s := ModifierStack.new()
	s.add_modifier(_make_floor("s1", 0))
	s.add_modifier(_make_ceil("s2", 0))
	# Floor and ceiling at 0 means result is always 0
	assert(s.calculate(10) == 0,
		"ModifierStack: floor=ceiling=0 should produce 0, got %d" % s.calculate(10))


func test_remove_by_source() -> void:
	var s := ModifierStack.new()
	s.add_modifier(_make_add("s1", 3))
	s.add_modifier(_make_add("s2", 5))
	s.remove_by_source("s1")
	assert(s.calculate(10) == 15,
		"ModifierStack: after removing s1 (+3), result should be 15, got %d" % s.calculate(10))


func test_has_source() -> void:
	var s := ModifierStack.new()
	s.add_modifier(_make_add("s1", 1))
	assert(s.has_source("s1"),
		"ModifierStack: has_source should return true for s1")
	assert(not s.has_source("s99"),
		"ModifierStack: has_source should return false for unknown source")


func test_clear() -> void:
	var s := ModifierStack.new()
	s.add_modifier(_make_add("s1", 5))
	s.clear()
	assert(s.calculate(10) == 10,
		"ModifierStack: after clear, calculate should return base value 10, got %d" % s.calculate(10))


func test_returns_int_for_int_base() -> void:
	var s := ModifierStack.new()
	s.add_modifier(_make_mul("s1", 2.5))
	var result = s.calculate(4)  # 4 * 2.5 = 10.0 -> rounds to 10
	assert(result is int,
		"ModifierStack: int base should return int, got %s" % type_string(typeof(result)))
	assert(result == 10,
		"ModifierStack: 4 × 2.5 rounded should be 10, got %d" % result)


func test_negative_add_modifier() -> void:
	var s := ModifierStack.new()
	s.add_modifier(_make_add("bane", -1))
	assert(s.calculate(12) == 11,
		"ModifierStack: -1 add on 12 should give 11, got %d" % s.calculate(12))


# ---------------------------------------------------------------------------
# ModifierContainer tests
# ---------------------------------------------------------------------------

func test_container_add_and_get() -> void:
	var c := ModifierContainer.new()
	c.add_modifier("armor_class", _make_add("prot_evil", 1, "protection"))
	var result = c.get_effective_value("armor_class", 5)
	assert(result == 6,
		"ModifierContainer: base AC 5 + prot_evil +1 should be 6, got %d" % result)


func test_container_remove_all_from_source() -> void:
	var c := ModifierContainer.new()
	c.add_modifier("armor_class", _make_add("bless", 1))
	c.add_modifier("attack_throw", _make_add("bless", -1))  # bless also lowers attack target
	c.remove_all_from_source("bless")
	assert(c.get_effective_value("armor_class", 5) == 5,
		"ModifierContainer: after removing bless, AC modifier should be gone")
	assert(c.get_effective_value("attack_throw", 10) == 10,
		"ModifierContainer: after removing bless, attack_throw modifier should be gone")


func test_container_has_modifier_from() -> void:
	var c := ModifierContainer.new()
	c.add_modifier("save_spells", _make_add("shield", 2))
	assert(c.has_modifier_from("shield"),
		"ModifierContainer: has_modifier_from should return true for shield")
	assert(not c.has_modifier_from("unknown"),
		"ModifierContainer: has_modifier_from should return false for unknown source")


func test_container_no_modifier_returns_base() -> void:
	var c := ModifierContainer.new()
	var result = c.get_effective_value("armor_class", 7)
	assert(result == 7,
		"ModifierContainer: no modifier should return base value 7, got %d" % result)


func test_container_multiple_stats() -> void:
	var c := ModifierContainer.new()
	c.add_modifier("armor_class", _make_add("prayer", 1))
	c.add_modifier("attack_throw", _make_add("prayer", -1))
	c.add_modifier("save_spells", _make_add("prayer", 1))
	assert(c.get_effective_value("armor_class", 5) == 6,
		"ModifierContainer: prayer AC modifier correct")
	assert(c.get_effective_value("attack_throw", 10) == 9,
		"ModifierContainer: prayer attack_throw modifier correct")
	assert(c.get_effective_value("save_spells", 14) == 15,
		"ModifierContainer: prayer save_spells modifier correct")
