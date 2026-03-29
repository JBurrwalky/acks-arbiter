extends Node

## Unit tests for SpellEffectRegistry.


func run_all_tests() -> void:
	test_registry_loads()
	test_has_effect_data_known()
	test_has_effect_data_unknown()
	test_get_effect_data_returns_dict()
	test_get_effect_data_unknown_returns_empty()
	test_comment_keys_excluded()
	test_get_all_spell_keys()
	test_get_modifiers_for_spell()
	test_get_modifiers_for_instant_spell()
	test_get_flags_for_spell()
	test_get_conditions_for_spell()
	test_get_damage_resistances()
	test_get_effect_type()
	test_get_duration_type()
	test_is_instant()
	test_requires_concentration()
	test_protection_from_evil_profile()
	test_magic_missile_profile()
	test_fly_profile()
	test_hold_person_profile()
	print("SpellEffectRegistry: all tests passed.")


func test_registry_loads() -> void:
	var reg := SpellEffectRegistry.new()
	assert(not reg.get_all_spell_keys().is_empty(),
		"SpellEffectRegistry: should have at least one spell after load")


func test_has_effect_data_known() -> void:
	var reg := SpellEffectRegistry.new()
	assert(reg.has_effect_data("protection_from_evil"),
		"SpellEffectRegistry: should have protection_from_evil")
	assert(reg.has_effect_data("magic_missile"),
		"SpellEffectRegistry: should have magic_missile")
	assert(reg.has_effect_data("fly"),
		"SpellEffectRegistry: should have fly")


func test_has_effect_data_unknown() -> void:
	var reg := SpellEffectRegistry.new()
	assert(not reg.has_effect_data("made_up_spell_xyz"),
		"SpellEffectRegistry: should not have unknown spell")


func test_get_effect_data_returns_dict() -> void:
	var reg := SpellEffectRegistry.new()
	var data := reg.get_effect_data("bless")
	assert(not data.is_empty(),
		"SpellEffectRegistry: get_effect_data('bless') should return non-empty dict")
	assert(data.has("effect_type"),
		"SpellEffectRegistry: bless effect data should have 'effect_type' key")


func test_get_effect_data_unknown_returns_empty() -> void:
	var reg := SpellEffectRegistry.new()
	var data := reg.get_effect_data("no_such_spell")
	assert(data.is_empty(),
		"SpellEffectRegistry: unknown spell should return empty dict")


func test_comment_keys_excluded() -> void:
	var reg := SpellEffectRegistry.new()
	assert(not reg.has_effect_data("_comment"),
		"SpellEffectRegistry: _comment key should be excluded from spell data")


func test_get_all_spell_keys() -> void:
	var reg := SpellEffectRegistry.new()
	var keys := reg.get_all_spell_keys()
	assert(keys.size() >= 10,
		"SpellEffectRegistry: should have at least 10 template spells, got %d" % keys.size())
	assert("protection_from_evil" in keys,
		"SpellEffectRegistry: protection_from_evil should be in all keys")
	assert("cure_light_wounds" in keys,
		"SpellEffectRegistry: cure_light_wounds should be in all keys")


func test_get_modifiers_for_spell() -> void:
	var reg := SpellEffectRegistry.new()
	var mods := reg.get_modifiers_for_spell("protection_from_evil")
	assert(mods.size() == 6,
		"SpellEffectRegistry: protection_from_evil should have 6 modifiers (AC + 5 saves), got %d" % mods.size())
	# All should be in 'protection' stacking group
	for mod in mods:
		assert(mod.get("stacking_group", "") == "protection",
			"SpellEffectRegistry: prot_from_evil modifiers should be in 'protection' group")


func test_get_modifiers_for_instant_spell() -> void:
	var reg := SpellEffectRegistry.new()
	var mods := reg.get_modifiers_for_spell("magic_missile")
	assert(mods.is_empty(),
		"SpellEffectRegistry: magic_missile should have no modifiers (it's instant)")


func test_get_flags_for_spell() -> void:
	var reg := SpellEffectRegistry.new()
	var flags := reg.get_flags_for_spell("fly")
	assert("can_fly" in flags,
		"SpellEffectRegistry: fly should have 'can_fly' flag")
	var prot_flags := reg.get_flags_for_spell("protection_from_evil")
	assert("protected_from_enchanted_melee" in prot_flags,
		"SpellEffectRegistry: protection_from_evil should have 'protected_from_enchanted_melee' flag")


func test_get_conditions_for_spell() -> void:
	var reg := SpellEffectRegistry.new()
	var conds := reg.get_conditions_for_spell("hold_person")
	assert("paralyzed" in conds,
		"SpellEffectRegistry: hold_person should apply 'paralyzed' condition")
	var fly_conds := reg.get_conditions_for_spell("fly")
	assert(fly_conds.is_empty(),
		"SpellEffectRegistry: fly should have no conditions")


func test_get_damage_resistances() -> void:
	var reg := SpellEffectRegistry.new()
	var res := reg.get_damage_resistances_for_spell("resist_fire")
	assert(res.size() == 1,
		"SpellEffectRegistry: resist_fire should have 1 damage resistance entry, got %d" % res.size())
	assert(res[0].get("damage_type", "") == "fire",
		"SpellEffectRegistry: resist_fire resistance should be for 'fire'")
	assert(res[0].get("factor", 1.0) == 0.5,
		"SpellEffectRegistry: resist_fire should have factor 0.5")
	var fly_res := reg.get_damage_resistances_for_spell("fly")
	assert(fly_res.is_empty(),
		"SpellEffectRegistry: fly should have no damage resistances")


func test_get_effect_type() -> void:
	var reg := SpellEffectRegistry.new()
	assert(reg.get_effect_type("protection_from_evil") == "modifier",
		"SpellEffectRegistry: protection_from_evil should be 'modifier' type")
	assert(reg.get_effect_type("magic_missile") == "instant",
		"SpellEffectRegistry: magic_missile should be 'instant' type")
	assert(reg.get_effect_type("fly") == "flag",
		"SpellEffectRegistry: fly should be 'flag' type")
	assert(reg.get_effect_type("hold_person") == "condition",
		"SpellEffectRegistry: hold_person should be 'condition' type")


func test_get_duration_type() -> void:
	var reg := SpellEffectRegistry.new()
	assert(reg.get_duration_type("protection_from_evil") == "turns",
		"SpellEffectRegistry: protection_from_evil duration should be 'turns'")
	assert(reg.get_duration_type("magic_missile") == "permanent",
		"SpellEffectRegistry: magic_missile duration should be 'permanent' (instant)")
	assert(reg.get_duration_type("invisibility") == "permanent",
		"SpellEffectRegistry: invisibility duration should be 'permanent' (until broken)")


func test_is_instant() -> void:
	var reg := SpellEffectRegistry.new()
	assert(reg.is_instant("magic_missile"),
		"SpellEffectRegistry: magic_missile should be instant")
	assert(reg.is_instant("cure_light_wounds"),
		"SpellEffectRegistry: cure_light_wounds should be instant")
	assert(not reg.is_instant("fly"),
		"SpellEffectRegistry: fly should not be instant")
	assert(not reg.is_instant("protection_from_evil"),
		"SpellEffectRegistry: protection_from_evil should not be instant")


func test_requires_concentration() -> void:
	var reg := SpellEffectRegistry.new()
	assert(not reg.requires_concentration("protection_from_evil"),
		"SpellEffectRegistry: protection_from_evil should not require concentration")
	assert(not reg.requires_concentration("fly"),
		"SpellEffectRegistry: fly should not require concentration")


func test_protection_from_evil_profile() -> void:
	var reg := SpellEffectRegistry.new()
	assert(reg.has_effect_data("protection_from_evil"),
		"protection_from_evil: has data")
	assert(reg.get_effect_type("protection_from_evil") == "modifier",
		"protection_from_evil: effect_type is modifier")
	assert(reg.get_duration_type("protection_from_evil") == "turns",
		"protection_from_evil: duration_type is turns")
	var mods := reg.get_modifiers_for_spell("protection_from_evil")
	assert(mods.size() == 6, "protection_from_evil: 6 modifiers")
	var flags := reg.get_flags_for_spell("protection_from_evil")
	assert(flags.size() == 1, "protection_from_evil: 1 flag")
	assert("protected_from_enchanted_melee" in flags, "protection_from_evil: correct flag")


func test_magic_missile_profile() -> void:
	var reg := SpellEffectRegistry.new()
	var data := reg.get_effect_data("magic_missile")
	assert(data.get("auto_hit", false) == true, "magic_missile: auto_hit is true")
	assert(data.get("damage_type", "") == "force", "magic_missile: damage_type is force")
	assert(data.has("damage"), "magic_missile: has damage field")
	assert(reg.is_instant("magic_missile"), "magic_missile: is instant")


func test_fly_profile() -> void:
	var reg := SpellEffectRegistry.new()
	assert("can_fly" in reg.get_flags_for_spell("fly"), "fly: has can_fly flag")
	var mods := reg.get_modifiers_for_spell("fly")
	assert(mods.size() == 1, "fly: 1 movement modifier")
	assert(mods[0].get("operation", "") == "set_floor", "fly: movement uses set_floor")


func test_hold_person_profile() -> void:
	var reg := SpellEffectRegistry.new()
	assert("paralyzed" in reg.get_conditions_for_spell("hold_person"),
		"hold_person: applies paralyzed")
	var data := reg.get_effect_data("hold_person")
	assert(data.get("save_type", "") == "save_spells",
		"hold_person: save_type is save_spells")
