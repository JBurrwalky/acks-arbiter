extends Node

## Unit tests for ActiveEffectTracker.


func run_all_tests() -> void:
	test_add_and_get_effect()
	test_has_effect()
	test_add_returns_effect_id()
	test_remove_effect_returns_dict()
	test_remove_effect_unknown_returns_empty()
	test_get_effects_on_target()
	test_get_effects_by_caster()
	test_get_concentration_effects()
	test_tick_rounds_decrements()
	test_tick_rounds_expires_effect()
	test_tick_turns_expires_effect()
	test_tick_does_not_affect_other_duration_type()
	test_permanent_effect_never_expires()
	test_break_concentration_removes_concentration_effects()
	test_break_concentration_leaves_non_concentration_effects()
	test_dispel_auto_succeeds_when_level_equal()
	test_dispel_auto_succeeds_when_dispeller_higher()
	test_dispel_failure_removed_after_success()
	test_dispel_only_affects_target()
	test_clear_removes_all()
	test_tick_multiple_n()
	print("ActiveEffectTracker: all tests passed.")


func _make_effect(eid: String, caster_id: String, target_ids: Array,
		duration_type: String = "rounds", duration_remaining: int = 3,
		caster_level: int = 5, concentration: bool = false) -> Dictionary:
	return {
		"effect_id": eid,
		"spell_key": "test_spell",
		"caster_id": caster_id,
		"caster_level": caster_level,
		"target_ids": target_ids,
		"effect_type": "modifier",
		"applied_modifiers": [],
		"applied_conditions": [],
		"applied_flags": [],
		"duration_type": duration_type,
		"duration_remaining": duration_remaining,
		"requires_concentration": concentration,
		"is_active": true,
		"metadata": {},
	}


func test_add_and_get_effect() -> void:
	var t := ActiveEffectTracker.new()
	var e := _make_effect("e1", "caster1", ["target1"])
	t.add_effect(e)
	var retrieved := t.get_effect("e1")
	assert(not retrieved.is_empty(),
		"ActiveEffectTracker: get_effect should return the added effect")
	assert(retrieved["effect_id"] == "e1",
		"ActiveEffectTracker: retrieved effect should have correct effect_id")


func test_has_effect() -> void:
	var t := ActiveEffectTracker.new()
	t.add_effect(_make_effect("e1", "caster1", ["target1"]))
	assert(t.has_effect("e1"), "ActiveEffectTracker: has_effect should be true after add")
	assert(not t.has_effect("e99"), "ActiveEffectTracker: has_effect should be false for unknown id")


func test_add_returns_effect_id() -> void:
	var t := ActiveEffectTracker.new()
	var returned_id := t.add_effect(_make_effect("e_abc", "c1", ["t1"]))
	assert(returned_id == "e_abc",
		"ActiveEffectTracker: add_effect should return the effect_id")


func test_remove_effect_returns_dict() -> void:
	var t := ActiveEffectTracker.new()
	t.add_effect(_make_effect("e1", "caster1", ["t1"]))
	var removed := t.remove_effect("e1")
	assert(not removed.is_empty(),
		"ActiveEffectTracker: remove_effect should return the removed dict")
	assert(removed["effect_id"] == "e1",
		"ActiveEffectTracker: removed dict should have correct effect_id")
	assert(not t.has_effect("e1"),
		"ActiveEffectTracker: effect should be gone after remove")


func test_remove_effect_unknown_returns_empty() -> void:
	var t := ActiveEffectTracker.new()
	var result := t.remove_effect("nonexistent")
	assert(result.is_empty(),
		"ActiveEffectTracker: removing unknown effect should return empty dict")


func test_get_effects_on_target() -> void:
	var t := ActiveEffectTracker.new()
	t.add_effect(_make_effect("e1", "c1", ["alice"]))
	t.add_effect(_make_effect("e2", "c1", ["alice", "bob"]))
	t.add_effect(_make_effect("e3", "c1", ["bob"]))
	var alice_effects := t.get_effects_on_target("alice")
	assert(alice_effects.size() == 2,
		"ActiveEffectTracker: alice should have 2 effects, got %d" % alice_effects.size())
	var bob_effects := t.get_effects_on_target("bob")
	assert(bob_effects.size() == 2,
		"ActiveEffectTracker: bob should have 2 effects, got %d" % bob_effects.size())
	var carol_effects := t.get_effects_on_target("carol")
	assert(carol_effects.is_empty(),
		"ActiveEffectTracker: carol should have 0 effects")


func test_get_effects_by_caster() -> void:
	var t := ActiveEffectTracker.new()
	t.add_effect(_make_effect("e1", "mage1", ["t1"]))
	t.add_effect(_make_effect("e2", "mage1", ["t2"]))
	t.add_effect(_make_effect("e3", "cleric1", ["t1"]))
	var mage1_effects := t.get_effects_by_caster("mage1")
	assert(mage1_effects.size() == 2,
		"ActiveEffectTracker: mage1 should have 2 effects, got %d" % mage1_effects.size())
	var cleric1_effects := t.get_effects_by_caster("cleric1")
	assert(cleric1_effects.size() == 1,
		"ActiveEffectTracker: cleric1 should have 1 effect, got %d" % cleric1_effects.size())


func test_get_concentration_effects() -> void:
	var t := ActiveEffectTracker.new()
	t.add_effect(_make_effect("e1", "mage1", ["t1"], "concentration", -1, 5, true))
	t.add_effect(_make_effect("e2", "mage1", ["t2"], "turns", 6, 5, false))
	t.add_effect(_make_effect("e3", "mage1", ["t3"], "concentration", -1, 5, true))
	var conc := t.get_concentration_effects("mage1")
	assert(conc.size() == 2,
		"ActiveEffectTracker: mage1 should have 2 concentration effects, got %d" % conc.size())


func test_tick_rounds_decrements() -> void:
	var t := ActiveEffectTracker.new()
	t.add_effect(_make_effect("e1", "c1", ["t1"], "rounds", 5))
	var expired := t.tick_rounds(2)
	assert(expired.is_empty(), "ActiveEffectTracker: no effect should expire after decrement")
	var e := t.get_effect("e1")
	assert(e["duration_remaining"] == 3,
		"ActiveEffectTracker: duration should be 3 after ticking 2, got %d" % e["duration_remaining"])


func test_tick_rounds_expires_effect() -> void:
	var t := ActiveEffectTracker.new()
	t.add_effect(_make_effect("e1", "c1", ["t1"], "rounds", 2))
	var expired := t.tick_rounds(2)
	assert("e1" in expired,
		"ActiveEffectTracker: e1 should be in expired list after ticking to 0")
	assert(not t.has_effect("e1"),
		"ActiveEffectTracker: expired effect should be removed")


func test_tick_turns_expires_effect() -> void:
	var t := ActiveEffectTracker.new()
	t.add_effect(_make_effect("e1", "c1", ["t1"], "turns", 3))
	var expired := t.tick_turns(5)
	assert("e1" in expired,
		"ActiveEffectTracker: e1 should expire after ticking turns past duration")


func test_tick_does_not_affect_other_duration_type() -> void:
	var t := ActiveEffectTracker.new()
	t.add_effect(_make_effect("rounds_effect", "c1", ["t1"], "rounds", 2))
	t.add_effect(_make_effect("turns_effect", "c1", ["t1"], "turns", 2))
	var expired := t.tick_rounds(10)
	assert("rounds_effect" in expired,
		"ActiveEffectTracker: rounds_effect should expire on tick_rounds")
	assert("turns_effect" not in expired,
		"ActiveEffectTracker: turns_effect should NOT expire on tick_rounds")
	assert(t.has_effect("turns_effect"),
		"ActiveEffectTracker: turns_effect should still be active")


func test_permanent_effect_never_expires() -> void:
	var t := ActiveEffectTracker.new()
	t.add_effect(_make_effect("e1", "c1", ["t1"], "permanent", -1))
	var expired := t.tick_rounds(9999)
	assert(expired.is_empty(),
		"ActiveEffectTracker: permanent effect should never expire from tick_rounds")
	assert(t.has_effect("e1"),
		"ActiveEffectTracker: permanent effect should still be active")


func test_break_concentration_removes_concentration_effects() -> void:
	var t := ActiveEffectTracker.new()
	t.add_effect(_make_effect("e1", "mage1", ["t1"], "concentration", -1, 5, true))
	t.add_effect(_make_effect("e2", "mage1", ["t2"], "concentration", -1, 5, true))
	var ended := t.break_concentration("mage1")
	assert(ended.size() == 2,
		"ActiveEffectTracker: break_concentration should end 2 effects, got %d" % ended.size())
	assert(not t.has_effect("e1"), "ActiveEffectTracker: e1 should be removed")
	assert(not t.has_effect("e2"), "ActiveEffectTracker: e2 should be removed")


func test_break_concentration_leaves_non_concentration_effects() -> void:
	var t := ActiveEffectTracker.new()
	t.add_effect(_make_effect("conc", "mage1", ["t1"], "concentration", -1, 5, true))
	t.add_effect(_make_effect("norm", "mage1", ["t1"], "turns", 6, 5, false))
	t.break_concentration("mage1")
	assert(not t.has_effect("conc"),
		"ActiveEffectTracker: concentration effect should be removed")
	assert(t.has_effect("norm"),
		"ActiveEffectTracker: non-concentration effect should remain")


func test_dispel_auto_succeeds_when_level_equal() -> void:
	var t := ActiveEffectTracker.new()
	var e := _make_effect("e1", "c1", ["victim"], "turns", 10, 5)
	t.add_effect(e)
	var results := t.dispel_check("victim", 5)
	assert(results.size() == 1,
		"ActiveEffectTracker: dispel_check should return 1 result, got %d" % results.size())
	assert(results[0]["dispelled"] == true,
		"ActiveEffectTracker: dispel should auto-succeed when levels equal")
	assert(not t.has_effect("e1"),
		"ActiveEffectTracker: effect should be removed after successful dispel")


func test_dispel_auto_succeeds_when_dispeller_higher() -> void:
	var t := ActiveEffectTracker.new()
	t.add_effect(_make_effect("e1", "c1", ["victim"], "turns", 10, 3))
	var results := t.dispel_check("victim", 7)
	assert(results[0]["dispelled"] == true,
		"ActiveEffectTracker: dispel should succeed when dispeller_level > caster_level")


func test_dispel_failure_removed_after_success() -> void:
	var t := ActiveEffectTracker.new()
	t.add_effect(_make_effect("e1", "c1", ["victim"], "turns", 10, 5))
	t.dispel_check("victim", 5)
	assert(not t.has_effect("e1"),
		"ActiveEffectTracker: effect successfully dispelled should be removed")


func test_dispel_only_affects_target() -> void:
	var t := ActiveEffectTracker.new()
	t.add_effect(_make_effect("e_victim", "c1", ["victim"], "turns", 5, 3))
	t.add_effect(_make_effect("e_other", "c1", ["innocent"], "turns", 5, 3))
	t.dispel_check("victim", 10)
	assert(not t.has_effect("e_victim"),
		"ActiveEffectTracker: victim's effect should be dispelled")
	assert(t.has_effect("e_other"),
		"ActiveEffectTracker: innocent's effect should NOT be dispelled")


func test_clear_removes_all() -> void:
	var t := ActiveEffectTracker.new()
	t.add_effect(_make_effect("e1", "c1", ["t1"]))
	t.add_effect(_make_effect("e2", "c2", ["t2"]))
	t.clear()
	assert(t.get_all_effects().is_empty(),
		"ActiveEffectTracker: clear() should remove all effects")


func test_tick_multiple_n() -> void:
	var t := ActiveEffectTracker.new()
	t.add_effect(_make_effect("e1", "c1", ["t1"], "rounds", 10))
	var expired := t.tick_rounds(4)
	assert(expired.is_empty(), "ActiveEffectTracker: 10 - 4 = 6 rounds left, should not expire")
	var e := t.get_effect("e1")
	assert(e["duration_remaining"] == 6,
		"ActiveEffectTracker: 10 - 4 = 6 remaining, got %d" % e["duration_remaining"])
