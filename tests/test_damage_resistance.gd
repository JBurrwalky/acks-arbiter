extends Node

## Unit tests for DamageResistance.


func run_all_tests() -> void:
	test_immunity_blocks_damage()
	test_immunity_only_for_that_type()
	test_multiple_immunities_different_types()
	test_remove_immunity_by_source()
	test_immunity_requires_all_sources_removed()
	test_half_damage_resistance()
	test_stacking_resistance_multiplies()
	test_remove_resistance_by_source()
	test_vulnerability_doubles_damage()
	test_immune_and_vulnerable_immune_wins()
	test_resistance_and_vulnerability_stack()
	test_untyped_bypasses_immunity()
	test_untyped_bypasses_resistance()
	test_untyped_still_takes_vulnerability()
	test_apply_to_damage_no_modifiers()
	test_clear_removes_all()
	test_remove_by_source_removes_all_types()
	test_zero_damage_stays_zero()
	print("DamageResistance: all tests passed.")


func test_immunity_blocks_damage() -> void:
	var dr := DamageResistance.new()
	dr.add_immunity("fire", "resist_fire")
	assert(dr.apply_to_damage(20, "fire") == 0,
		"DamageResistance: immune to fire should reduce 20 to 0")


func test_immunity_only_for_that_type() -> void:
	var dr := DamageResistance.new()
	dr.add_immunity("fire", "resist_fire")
	assert(dr.apply_to_damage(20, "cold") == 20,
		"DamageResistance: fire immunity should not affect cold damage")


func test_multiple_immunities_different_types() -> void:
	var dr := DamageResistance.new()
	dr.add_immunity("fire", "resist_fire")
	dr.add_immunity("cold", "resist_cold")
	assert(dr.apply_to_damage(10, "fire") == 0,
		"DamageResistance: fire immunity works with multiple immunities")
	assert(dr.apply_to_damage(10, "cold") == 0,
		"DamageResistance: cold immunity works with multiple immunities")
	assert(dr.apply_to_damage(10, "lightning") == 10,
		"DamageResistance: unprotected type still takes full damage")


func test_remove_immunity_by_source() -> void:
	var dr := DamageResistance.new()
	dr.add_immunity("fire", "resist_fire")
	dr.remove_by_source("resist_fire")
	assert(dr.apply_to_damage(20, "fire") == 20,
		"DamageResistance: after removing source, fire immunity should be gone")


func test_immunity_requires_all_sources_removed() -> void:
	var dr := DamageResistance.new()
	dr.add_immunity("fire", "source_a")
	dr.add_immunity("fire", "source_b")
	dr.remove_by_source("source_a")
	assert(dr.is_immune("fire"),
		"DamageResistance: fire immunity should remain when second source still active")
	dr.remove_by_source("source_b")
	assert(not dr.is_immune("fire"),
		"DamageResistance: fire immunity should be gone after all sources removed")


func test_half_damage_resistance() -> void:
	var dr := DamageResistance.new()
	dr.add_resistance("cold", 0.5, "protection_from_cold")
	assert(dr.apply_to_damage(20, "cold") == 10,
		"DamageResistance: 0.5 resistance should halve 20 to 10, got %d" % dr.apply_to_damage(20, "cold"))


func test_stacking_resistance_multiplies() -> void:
	var dr := DamageResistance.new()
	dr.add_resistance("acid", 0.5, "source_a")  # 50% damage
	dr.add_resistance("acid", 0.5, "source_b")  # another 50%
	# Combined: 0.5 * 0.5 = 0.25 — takes 25% damage
	assert(dr.apply_to_damage(20, "acid") == 5,
		"DamageResistance: two 0.5 resistances should give 0.25 factor (5 from 20), got %d" % dr.apply_to_damage(20, "acid"))


func test_remove_resistance_by_source() -> void:
	var dr := DamageResistance.new()
	dr.add_resistance("cold", 0.5, "protection_from_cold")
	dr.remove_by_source("protection_from_cold")
	assert(dr.apply_to_damage(20, "cold") == 20,
		"DamageResistance: after removing source, cold resistance should be gone")


func test_vulnerability_doubles_damage() -> void:
	var dr := DamageResistance.new()
	dr.add_vulnerability("fire", "oil_soaked")
	assert(dr.apply_to_damage(10, "fire") == 20,
		"DamageResistance: vulnerability should double 10 fire to 20, got %d" % dr.apply_to_damage(10, "fire"))


func test_immune_and_vulnerable_immune_wins() -> void:
	var dr := DamageResistance.new()
	dr.add_immunity("fire", "source_a")
	dr.add_vulnerability("fire", "source_b")
	assert(dr.apply_to_damage(20, "fire") == 0,
		"DamageResistance: immunity should win over vulnerability (result 0, not 40)")


func test_resistance_and_vulnerability_stack() -> void:
	var dr := DamageResistance.new()
	dr.add_resistance("lightning", 0.5, "partial_resistance")
	dr.add_vulnerability("lightning", "wetness")
	# 0.5 resistance then ×2 vulnerability = back to 1.0 (full damage)
	assert(dr.apply_to_damage(20, "lightning") == 20,
		"DamageResistance: 0.5 resistance + ×2 vulnerability should net to full damage (20), got %d" % dr.apply_to_damage(20, "lightning"))


func test_untyped_bypasses_immunity() -> void:
	var dr := DamageResistance.new()
	dr.add_immunity("physical", "invulnerability")
	assert(dr.apply_to_damage(10, "untyped") == 10,
		"DamageResistance: untyped damage bypasses immunity (even if physical is immune)")
	# Direct immunity check should also be false for untyped
	assert(not dr.is_immune("untyped"),
		"DamageResistance: untyped is never immune")


func test_untyped_bypasses_resistance() -> void:
	var dr := DamageResistance.new()
	dr.add_resistance("physical", 0.5, "some_source")
	assert(dr.apply_to_damage(20, "untyped") == 20,
		"DamageResistance: untyped damage bypasses resistance")


func test_untyped_still_takes_vulnerability() -> void:
	var dr := DamageResistance.new()
	dr.add_vulnerability("untyped", "some_curse")
	assert(dr.apply_to_damage(10, "untyped") == 20,
		"DamageResistance: untyped damage still takes vulnerability (10 -> 20)")


func test_apply_to_damage_no_modifiers() -> void:
	var dr := DamageResistance.new()
	assert(dr.apply_to_damage(15, "fire") == 15,
		"DamageResistance: no modifiers should return base damage 15")


func test_clear_removes_all() -> void:
	var dr := DamageResistance.new()
	dr.add_immunity("fire", "s1")
	dr.add_resistance("cold", 0.5, "s2")
	dr.add_vulnerability("acid", "s3")
	dr.clear()
	assert(not dr.is_immune("fire"),
		"DamageResistance: after clear, fire immunity should be gone")
	assert(dr.apply_to_damage(10, "cold") == 10,
		"DamageResistance: after clear, cold resistance should be gone")
	assert(dr.apply_to_damage(10, "acid") == 10,
		"DamageResistance: after clear, acid vulnerability should be gone")


func test_remove_by_source_removes_all_types() -> void:
	var dr := DamageResistance.new()
	dr.add_immunity("fire", "big_spell")
	dr.add_resistance("cold", 0.5, "big_spell")
	dr.add_vulnerability("acid", "big_spell")
	dr.remove_by_source("big_spell")
	assert(not dr.is_immune("fire"),
		"DamageResistance: remove_by_source should remove immunity")
	assert(dr.apply_to_damage(10, "cold") == 10,
		"DamageResistance: remove_by_source should remove resistance")
	assert(dr.apply_to_damage(10, "acid") == 10,
		"DamageResistance: remove_by_source should remove vulnerability")


func test_zero_damage_stays_zero() -> void:
	var dr := DamageResistance.new()
	dr.add_vulnerability("fire", "oily")
	assert(dr.apply_to_damage(0, "fire") == 0,
		"DamageResistance: 0 damage stays 0 even with vulnerability")
