extends Node

## Unit tests for ConditionCatalog.


func run_all_tests() -> void:
	test_catalog_loads()
	test_has_condition()
	test_get_condition_returns_data()
	test_get_condition_unknown_returns_empty()
	test_get_all_condition_keys()
	test_prevents_action_attacking()
	test_prevents_action_casting()
	test_prevents_action_movement()
	test_prevents_action_speech()
	test_prevents_action_running()
	test_prevents_action_charging()
	test_prevents_action_unknown_action()
	test_prevents_action_unknown_condition()
	test_get_ac_modifier()
	test_get_attack_modifier()
	test_is_helpless()
	test_is_vulnerable()
	test_grants_auto_hit_melee()
	test_attacker_bonus_vs_ranged()
	test_attacker_bonus_vs_melee()
	test_paralyzed_full_profile()
	test_charging_profile()
	test_restrained_can_still_attack()
	test_vulnerable_no_helpless()
	print("ConditionCatalog: all tests passed.")


func test_catalog_loads() -> void:
	var catalog := ConditionCatalog.new()
	assert(not catalog.get_all_condition_keys().is_empty(),
		"ConditionCatalog: catalog should have at least one condition after load")


func test_has_condition() -> void:
	var catalog := ConditionCatalog.new()
	assert(catalog.has_condition("paralyzed"),
		"ConditionCatalog: should have 'paralyzed' condition")
	assert(catalog.has_condition("blinded"),
		"ConditionCatalog: should have 'blinded' condition")
	assert(not catalog.has_condition("nonexistent_xyz"),
		"ConditionCatalog: should not have 'nonexistent_xyz'")


func test_get_condition_returns_data() -> void:
	var catalog := ConditionCatalog.new()
	var data := catalog.get_condition("paralyzed")
	assert(not data.is_empty(),
		"ConditionCatalog: get_condition('paralyzed') should return non-empty dict")
	assert(data.has("condition_key"),
		"ConditionCatalog: condition dict should have 'condition_key' field")
	assert(data["condition_key"] == "paralyzed",
		"ConditionCatalog: condition_key should be 'paralyzed'")


func test_get_condition_unknown_returns_empty() -> void:
	var catalog := ConditionCatalog.new()
	var data := catalog.get_condition("not_a_real_condition")
	assert(data.is_empty(),
		"ConditionCatalog: unknown condition key should return empty dict")


func test_get_all_condition_keys() -> void:
	var catalog := ConditionCatalog.new()
	var keys := catalog.get_all_condition_keys()
	assert(keys.size() >= 20,
		"ConditionCatalog: should have at least 20 conditions, got %d" % keys.size())
	assert("paralyzed" in keys, "ConditionCatalog: 'paralyzed' should be in all keys")
	assert("blinded" in keys, "ConditionCatalog: 'blinded' should be in all keys")
	assert("prone" in keys, "ConditionCatalog: 'prone' should be in all keys")
	assert("vulnerable" in keys, "ConditionCatalog: 'vulnerable' should be in all keys")


func test_prevents_action_attacking() -> void:
	var catalog := ConditionCatalog.new()
	assert(catalog.prevents_action("paralyzed", "attacking"),
		"ConditionCatalog: paralyzed should prevent attacking")
	assert(not catalog.prevents_action("charging", "attacking"),
		"ConditionCatalog: charging should not prevent attacking")


func test_prevents_action_casting() -> void:
	var catalog := ConditionCatalog.new()
	assert(catalog.prevents_action("paralyzed", "casting"),
		"ConditionCatalog: paralyzed should prevent casting")
	assert(not catalog.prevents_action("restrained", "casting"),
		"ConditionCatalog: restrained should NOT prevent casting")


func test_prevents_action_movement() -> void:
	var catalog := ConditionCatalog.new()
	assert(catalog.prevents_action("helpless", "movement"),
		"ConditionCatalog: helpless should prevent movement")
	assert(not catalog.prevents_action("blinded", "movement"),
		"ConditionCatalog: blinded should not prevent movement (just slows it)")


func test_prevents_action_speech() -> void:
	var catalog := ConditionCatalog.new()
	assert(catalog.prevents_action("paralyzed", "speech"),
		"ConditionCatalog: paralyzed should prevent speech")
	assert(not catalog.prevents_action("stunned", "speech"),
		"ConditionCatalog: stunned should not prevent speech")


func test_prevents_action_running() -> void:
	var catalog := ConditionCatalog.new()
	assert(catalog.prevents_action("exhausted", "running"),
		"ConditionCatalog: exhausted should prevent running")
	assert(not catalog.prevents_action("infuriated", "running"),
		"ConditionCatalog: infuriated should not prevent running")


func test_prevents_action_charging() -> void:
	var catalog := ConditionCatalog.new()
	assert(catalog.prevents_action("exhausted", "charging"),
		"ConditionCatalog: exhausted should prevent charging")
	assert(not catalog.prevents_action("infuriated", "charging"),
		"ConditionCatalog: infuriated should not prevent charging")


func test_prevents_action_unknown_action() -> void:
	var catalog := ConditionCatalog.new()
	assert(not catalog.prevents_action("paralyzed", "unknown_action_type"),
		"ConditionCatalog: unknown action should return false safely")


func test_prevents_action_unknown_condition() -> void:
	var catalog := ConditionCatalog.new()
	assert(not catalog.prevents_action("no_such_condition", "attacking"),
		"ConditionCatalog: unknown condition should return false safely")


func test_get_ac_modifier() -> void:
	var catalog := ConditionCatalog.new()
	assert(catalog.get_ac_modifier("charging") == -2,
		"ConditionCatalog: charging should have -2 AC modifier, got %d" % catalog.get_ac_modifier("charging"))
	assert(catalog.get_ac_modifier("paralyzed") == 0,
		"ConditionCatalog: paralyzed has no AC modifier (helpless handles it), got %d" % catalog.get_ac_modifier("paralyzed"))
	assert(catalog.get_ac_modifier("nonexistent") == 0,
		"ConditionCatalog: unknown condition AC modifier should be 0")


func test_get_attack_modifier() -> void:
	var catalog := ConditionCatalog.new()
	assert(catalog.get_attack_modifier("blinded") == -4,
		"ConditionCatalog: blinded should have -4 attack modifier, got %d" % catalog.get_attack_modifier("blinded"))
	assert(catalog.get_attack_modifier("charging") == 2,
		"ConditionCatalog: charging should have +2 attack modifier, got %d" % catalog.get_attack_modifier("charging"))
	assert(catalog.get_attack_modifier("infuriated") == 2,
		"ConditionCatalog: infuriated should have +2 attack modifier, got %d" % catalog.get_attack_modifier("infuriated"))
	assert(catalog.get_attack_modifier("prone") == -4,
		"ConditionCatalog: prone should have -4 attack modifier, got %d" % catalog.get_attack_modifier("prone"))


func test_is_helpless() -> void:
	var catalog := ConditionCatalog.new()
	assert(catalog.is_helpless("paralyzed"),
		"ConditionCatalog: paralyzed should be helpless")
	assert(catalog.is_helpless("unconscious"),
		"ConditionCatalog: unconscious should be helpless")
	assert(catalog.is_helpless("helpless"),
		"ConditionCatalog: helpless should be helpless")
	assert(not catalog.is_helpless("stunned"),
		"ConditionCatalog: stunned should not be helpless")
	assert(not catalog.is_helpless("restrained"),
		"ConditionCatalog: restrained should not be helpless")


func test_is_vulnerable() -> void:
	var catalog := ConditionCatalog.new()
	assert(catalog.is_vulnerable("paralyzed"),
		"ConditionCatalog: paralyzed should be vulnerable")
	assert(catalog.is_vulnerable("grabbed"),
		"ConditionCatalog: grabbed should be vulnerable")
	assert(catalog.is_vulnerable("restrained"),
		"ConditionCatalog: restrained should be vulnerable")
	assert(not catalog.is_vulnerable("blinded"),
		"ConditionCatalog: blinded should not be vulnerable")
	assert(not catalog.is_vulnerable("frightened"),
		"ConditionCatalog: frightened should not be vulnerable")


func test_grants_auto_hit_melee() -> void:
	var catalog := ConditionCatalog.new()
	assert(catalog.grants_auto_hit_melee("paralyzed"),
		"ConditionCatalog: paralyzed should grant auto-hit melee")
	assert(catalog.grants_auto_hit_melee("helpless"),
		"ConditionCatalog: helpless should grant auto-hit melee")
	assert(catalog.grants_auto_hit_melee("slumbering"),
		"ConditionCatalog: slumbering should grant auto-hit melee")
	assert(not catalog.grants_auto_hit_melee("prone"),
		"ConditionCatalog: prone should not grant auto-hit melee")
	assert(not catalog.grants_auto_hit_melee("stunned"),
		"ConditionCatalog: stunned should not grant auto-hit melee")


func test_attacker_bonus_vs_ranged() -> void:
	var catalog := ConditionCatalog.new()
	assert(catalog.get_attacker_bonus_vs("helpless") == 4,
		"ConditionCatalog: helpless ranged attacker bonus should be 4, got %d" % catalog.get_attacker_bonus_vs("helpless"))
	assert(catalog.get_attacker_bonus_vs("prone") == 4,
		"ConditionCatalog: prone ranged attacker bonus should be 4, got %d" % catalog.get_attacker_bonus_vs("prone"))
	assert(catalog.get_attacker_bonus_vs("blinded") == 0,
		"ConditionCatalog: blinded has no ranged attacker bonus, got %d" % catalog.get_attacker_bonus_vs("blinded"))


func test_attacker_bonus_vs_melee() -> void:
	var catalog := ConditionCatalog.new()
	assert(catalog.get_attacker_bonus_vs("helpless", "melee") == 2,
		"ConditionCatalog: helpless melee attacker bonus should be 2, got %d" % catalog.get_attacker_bonus_vs("helpless", "melee"))
	assert(catalog.get_attacker_bonus_vs("prone", "melee") == 2,
		"ConditionCatalog: prone melee attacker bonus should be 2, got %d" % catalog.get_attacker_bonus_vs("prone", "melee"))


func test_paralyzed_full_profile() -> void:
	var catalog := ConditionCatalog.new()
	assert(catalog.prevents_action("paralyzed", "attacking"), "paralyzed: prevents attacking")
	assert(catalog.prevents_action("paralyzed", "casting"), "paralyzed: prevents casting")
	assert(catalog.prevents_action("paralyzed", "movement"), "paralyzed: prevents movement")
	assert(catalog.prevents_action("paralyzed", "speech"), "paralyzed: prevents speech")
	assert(catalog.is_helpless("paralyzed"), "paralyzed: is helpless")
	assert(catalog.is_vulnerable("paralyzed"), "paralyzed: is vulnerable")
	assert(catalog.grants_auto_hit_melee("paralyzed"), "paralyzed: auto-hit melee")
	assert(catalog.get_attacker_bonus_vs("paralyzed") == 4, "paralyzed: +4 ranged bonus")
	assert(catalog.get_attacker_bonus_vs("paralyzed", "melee") == 2, "paralyzed: +2 melee bonus")


func test_charging_profile() -> void:
	var catalog := ConditionCatalog.new()
	assert(not catalog.prevents_action("charging", "attacking"), "charging: does not prevent attacking")
	assert(catalog.get_attack_modifier("charging") == 2, "charging: +2 attack")
	assert(catalog.get_ac_modifier("charging") == -2, "charging: -2 AC")
	assert(not catalog.is_helpless("charging"), "charging: not helpless")
	assert(not catalog.is_vulnerable("charging"), "charging: not vulnerable")


func test_restrained_can_still_attack() -> void:
	var catalog := ConditionCatalog.new()
	assert(not catalog.prevents_action("restrained", "attacking"),
		"ConditionCatalog: restrained should NOT prevent attacking")
	assert(not catalog.prevents_action("restrained", "casting"),
		"ConditionCatalog: restrained should NOT prevent casting")
	assert(catalog.prevents_action("restrained", "movement"),
		"ConditionCatalog: restrained should prevent movement")
	assert(catalog.is_vulnerable("restrained"),
		"ConditionCatalog: restrained should be vulnerable")


func test_vulnerable_no_helpless() -> void:
	var catalog := ConditionCatalog.new()
	assert(catalog.is_vulnerable("vulnerable"), "vulnerable: is vulnerable")
	assert(not catalog.is_helpless("vulnerable"), "vulnerable: is NOT helpless")
	assert(not catalog.grants_auto_hit_melee("vulnerable"), "vulnerable: no auto-hit melee")
	assert(catalog.get_attacker_bonus_vs("vulnerable", "melee") == 2, "vulnerable: +2 melee bonus")
	assert(catalog.get_attacker_bonus_vs("vulnerable") == 4, "vulnerable: +4 ranged bonus")
