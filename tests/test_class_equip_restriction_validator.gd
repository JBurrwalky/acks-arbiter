extends "res://tests/test_suite_base.gd"

## Unit tests for ClassEquipRestrictionValidator.

const Validator := preload("res://engine/subsystems/inventory/class_equipment_restriction_validator.gd")


var _registry: ClassRegistry
var _catalog: EquipmentCatalog


func run_all_tests() -> void:
	_registry = ClassRegistry.new()
	_catalog = EquipmentCatalog.new()

	test_fighter_can_equip_anything()
	test_mage_blocked_from_armor()
	test_mage_blocked_from_sword()
	test_mage_can_equip_dagger_and_quarterstaff()
	test_cleric_blocked_from_bladed_weapons()
	test_cleric_can_equip_blunt_weapons()
	test_cleric_can_equip_morning_star()
	test_thief_blocked_from_chain_mail()
	test_thief_can_equip_leather_armor()
	test_thief_blocked_from_two_handed_sword()
	test_thief_blocked_from_shield()
	test_barbarian_unresolved_origin_permits_all()
	test_barbarian_jutland_origin_permits_jutland_weapons()
	test_barbarian_jutland_origin_blocks_off_list_weapons()
	test_barbarian_origin_via_top_level_field()
	test_barbarian_origin_via_class_metadata_json()
	test_non_weapon_armor_shield_always_permitted()
	test_empty_class_def_permits_all()
	if not has_failures():
		print("ClassEquipRestrictionValidator: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _check_ok(class_id: String, item_key: String, msg: String) -> void:
	var class_def: Dictionary = _registry.get_class_def(class_id)
	var item: Dictionary = _catalog.get_item(item_key)
	check(not item.is_empty(), "fixture missing: item '%s'" % item_key)
	var result: Dictionary = Validator.can_equip(class_def, {}, item, _catalog)
	check(result.get("ok", false),
		"%s: expected OK for %s + %s, got rejection: %s" %
		[msg, class_id, item_key, result.get("reason", "")])


func _check_blocked(class_id: String, item_key: String, msg: String) -> void:
	var class_def: Dictionary = _registry.get_class_def(class_id)
	var item: Dictionary = _catalog.get_item(item_key)
	check(not item.is_empty(), "fixture missing: item '%s'" % item_key)
	var result: Dictionary = Validator.can_equip(class_def, {}, item, _catalog)
	check(not result.get("ok", true),
		"%s: expected BLOCK for %s + %s, but it was permitted" % [msg, class_id, item_key])


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_fighter_can_equip_anything() -> void:
	# Fighter has weapon_permissions=["all"], armor_permissions=["all"], shield_permitted=true
	_check_ok("fighter", "two_handed_sword", "fighter + two-handed sword")
	_check_ok("fighter", "plate_armor", "fighter + plate")
	_check_ok("fighter", "shield", "fighter + shield")
	_check_ok("fighter", "crossbow", "fighter + crossbow")
	print("  fighter_can_equip_anything: OK")


func test_mage_blocked_from_armor() -> void:
	# Mage has armor_permissions=[], shield_permitted=false
	_check_blocked("mage", "leather_armor", "mage + leather")
	_check_blocked("mage", "chain_mail", "mage + chain")
	_check_blocked("mage", "plate_armor", "mage + plate")
	_check_blocked("mage", "shield", "mage + shield")
	print("  mage_blocked_from_armor: OK")


func test_mage_blocked_from_sword() -> void:
	# Mage's only permitted weapons are quarterstaff, club, dagger, dart.
	_check_blocked("mage", "sword", "mage + sword")
	_check_blocked("mage", "two_handed_sword", "mage + two-handed sword")
	_check_blocked("mage", "battle_axe", "mage + battle axe")
	_check_blocked("mage", "warhammer", "mage + warhammer")
	print("  mage_blocked_from_sword: OK")


func test_mage_can_equip_dagger_and_quarterstaff() -> void:
	_check_ok("mage", "dagger", "mage + dagger")
	# quarterstaff exists in catalog under that exact item_key (verified in base_equipment.json)
	var qs: Dictionary = _catalog.get_item("quarterstaff")
	check(not qs.is_empty(), "fixture: quarterstaff item should exist in catalog")
	_check_ok("mage", "quarterstaff", "mage + quarterstaff")
	print("  mage_can_equip_dagger_and_quarterstaff: OK")


func test_cleric_blocked_from_bladed_weapons() -> void:
	# Cleric weapon_permissions: warhammer, mace, morning_star, club, quarterstaff, sling
	# Bladed weapons (sword, dagger, battle_axe, two_handed_sword) are not on the list.
	_check_blocked("cleric", "sword", "cleric + sword")
	_check_blocked("cleric", "dagger", "cleric + dagger")
	_check_blocked("cleric", "battle_axe", "cleric + battle axe")
	_check_blocked("cleric", "two_handed_sword", "cleric + two-handed sword")
	print("  cleric_blocked_from_bladed_weapons: OK")


func test_cleric_can_equip_blunt_weapons() -> void:
	_check_ok("cleric", "mace", "cleric + mace")
	_check_ok("cleric", "warhammer", "cleric + warhammer")
	_check_ok("cleric", "club", "cleric + club")
	# Cleric also wears any armor and uses shields.
	_check_ok("cleric", "plate_armor", "cleric + plate (cleric has armor_permissions=all)")
	_check_ok("cleric", "shield", "cleric + shield")
	print("  cleric_can_equip_blunt_weapons: OK")


func test_cleric_can_equip_morning_star() -> void:
	# This test guards the recent JSON change that added morning_star to cleric weapons.
	_check_ok("cleric", "morning_star", "cleric + morning star")
	print("  cleric_can_equip_morning_star: OK")


func test_thief_blocked_from_chain_mail() -> void:
	# Thief armor_permissions: ["leather"] (alias for leather_armor).
	# Chain mail and plate are heavier — should be blocked.
	_check_blocked("thief", "chain_mail", "thief + chain mail")
	_check_blocked("thief", "plate_armor", "thief + plate")
	print("  thief_blocked_from_chain_mail: OK")


func test_thief_can_equip_leather_armor() -> void:
	# "leather" alias resolves to leather_armor (via ARMOR_KEY_ALIASES).
	_check_ok("thief", "leather_armor", "thief + leather armor")
	print("  thief_can_equip_leather_armor: OK")


func test_thief_blocked_from_two_handed_sword() -> void:
	# Thief weapon_permissions: any_missile, any_one_handed_melee.
	# Two-handed sword is melee+two_handed → not permitted.
	_check_blocked("thief", "two_handed_sword", "thief + two-handed sword")
	# But sword (one-handed) is permitted via any_one_handed_melee.
	_check_ok("thief", "sword", "thief + sword (one-handed melee)")
	# And crossbow (ranged) via any_missile.
	_check_ok("thief", "crossbow", "thief + crossbow (missile)")
	print("  thief_blocked_from_two_handed_sword: OK")


func test_thief_blocked_from_shield() -> void:
	# Thief shield_permitted = false.
	_check_blocked("thief", "shield", "thief + shield")
	print("  thief_blocked_from_shield: OK")


func test_barbarian_unresolved_origin_permits_all() -> void:
	# Barbarian uses determined_by_regional_origin. With no origin on the
	# character, the validator falls back to ["all"] (shortcut).
	var barbarian: Dictionary = _registry.get_class_def("barbarian")
	check(not barbarian.is_empty(), "barbarian class fixture should exist")
	var item: Dictionary = _catalog.get_item("two_handed_sword")
	var result: Dictionary = Validator.can_equip(barbarian, {}, item, _catalog)
	check(result.get("ok", false),
		"barbarian with no origin should permit any weapon (shortcut), got: %s" %
		result.get("reason", ""))
	print("  barbarian_unresolved_origin_permits_all: OK")


func test_barbarian_jutland_origin_permits_jutland_weapons() -> void:
	# Jutland origin permits: battle_axe, club, dagger, great_axe, hand_axe,
	# shortbow, spear, sword, two_handed_sword, warhammer.
	var barbarian: Dictionary = _registry.get_class_def("barbarian")
	var character: Dictionary = {"class_metadata": '{"regional_origin": "jutland"}'}
	for item_key in ["battle_axe", "sword", "two_handed_sword", "warhammer"]:
		var item: Dictionary = _catalog.get_item(item_key)
		check(not item.is_empty(), "fixture: %s should exist" % item_key)
		var result: Dictionary = Validator.can_equip(barbarian, character, item, _catalog)
		check(result.get("ok", false),
			"jutland barbarian should equip %s, got rejection: %s" %
			[item_key, result.get("reason", "")])
	print("  barbarian_jutland_origin_permits_jutland_weapons: OK")


func test_barbarian_jutland_origin_blocks_off_list_weapons() -> void:
	# Jutland does NOT permit ranged crossbows or composite bows.
	var barbarian: Dictionary = _registry.get_class_def("barbarian")
	var character: Dictionary = {"class_metadata": '{"regional_origin": "jutland"}'}
	var crossbow: Dictionary = _catalog.get_item("crossbow")
	var result: Dictionary = Validator.can_equip(barbarian, character, crossbow, _catalog)
	check(not result.get("ok", true),
		"jutland barbarian should NOT equip crossbow (not on origin list), but it was permitted")
	print("  barbarian_jutland_origin_blocks_off_list_weapons: OK")


func test_barbarian_origin_via_top_level_field() -> void:
	# The equipment-shop synthesizes a top-level `regional_origin` during
	# character creation (before class_metadata is persisted). Both shapes
	# must resolve to the same permissions.
	var barbarian: Dictionary = _registry.get_class_def("barbarian")
	var character: Dictionary = {"regional_origin": "jutland"}
	var sword: Dictionary = _catalog.get_item("sword")
	var result: Dictionary = Validator.can_equip(barbarian, character, sword, _catalog)
	check(result.get("ok", false),
		"top-level regional_origin should resolve same as class_metadata, got: %s" %
		result.get("reason", ""))
	print("  barbarian_origin_via_top_level_field: OK")


func test_barbarian_origin_via_class_metadata_json() -> void:
	# Skysostan permits sling and javelin but not battle_axe.
	var barbarian: Dictionary = _registry.get_class_def("barbarian")
	var character: Dictionary = {"class_metadata": '{"regional_origin": "skysostan"}'}
	# Battle axe is NOT on the skysostan list.
	var battle_axe: Dictionary = _catalog.get_item("battle_axe")
	var result: Dictionary = Validator.can_equip(barbarian, character, battle_axe, _catalog)
	check(not result.get("ok", true),
		"skysostan barbarian should NOT equip battle_axe (not on origin list)")
	print("  barbarian_origin_via_class_metadata_json: OK")


func test_non_weapon_armor_shield_always_permitted() -> void:
	# Gear, ammunition, foodstuff etc. fall through and are permitted regardless of class.
	var mage: Dictionary = _registry.get_class_def("mage")
	var torch: Dictionary = _catalog.get_item("torch")
	check(not torch.is_empty(), "fixture: torch should exist in catalog")
	var result: Dictionary = Validator.can_equip(mage, {}, torch, _catalog)
	check(result.get("ok", false), "mage should be able to equip a torch (gear)")
	print("  non_weapon_armor_shield_always_permitted: OK")


func test_empty_class_def_permits_all() -> void:
	# Defensive: missing/empty class_def shouldn't false-positive a block.
	var item: Dictionary = _catalog.get_item("plate_armor")
	var result: Dictionary = Validator.can_equip({}, {}, item, _catalog)
	check(result.get("ok", false), "empty class_def should default to permitted")
	print("  empty_class_def_permits_all: OK")
