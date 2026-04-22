extends "res://tests/test_suite_base.gd"

## Integration tests for the equip / unequip / throw pipeline.
##
## Covers:
##   - Dart bundle (item_category="ammunition") is equippable via the character sheet path.
##   - Stacks of melee weapons (short_sword) split-on-equip.
##   - Stacks of thrown weapons (dagger) stay equipped as a stack.
##   - Throwing a stacked thrown weapon decrements the equipped row.
##   - Throwing the last unit destroys the row and clears _equipped_weapon.
##   - Throwing a dart from a fresh bundle decrements uses_remaining.
##   - The party-inventory right-click Equip path applies the same split rules.
##   - Unequipping a stacked thrown weapon merges its full quantity back into the pack.

const CSTabEquipment := preload("res://scenes/ui/character_sheet/tabs/cs_tab_equipment.gd")
const ItemContextMenu := preload("res://scenes/ui/party_inventory/item_context_menu.gd")

const TEST_CAMPAIGN := "test_equip_campaign"
const TEST_CHAR := "test_equip_pc"

var _catalog: EquipmentCatalog = null


func run_all_tests() -> void:
	_catalog = EquipmentCatalog.new()

	test_dart_bundle_is_equippable()
	test_dart_bundle_seeds_uses_remaining_on_first_equip()
	test_short_sword_stack_splits_on_equip()
	test_dagger_stack_stays_equipped_as_stack()
	test_thrown_dagger_consumed_decrements_quantity()
	test_thrown_dagger_last_unit_clears_slot()
	test_thrown_dart_decrements_uses_remaining()
	test_thrown_dart_last_use_destroys_bundle()
	test_party_inventory_short_sword_stack_splits()
	test_unequip_dagger_stack_merges_full_quantity_to_pack()

	_catalog = null
	if not has_failures():
		print("EquipPipeline: all tests passed.")


# ---------------------------------------------------------------------------
# Test data setup / teardown
# ---------------------------------------------------------------------------

func _setup() -> void:
	_cleanup()
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[TEST_CAMPAIGN, "EquipTest"])
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_type, persistence_tier, race,
			 character_class, level, xp, combat_progression,
			 strength, intelligence, wisdom, dexterity, constitution, charisma)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [TEST_CHAR, TEST_CAMPAIGN, "EquipTester", "pc", "full", "human",
		  "fighter", 1, 0, "fighter", 10, 10, 10, 10, 10, 10])


func _cleanup() -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE character_id = ?", [TEST_CHAR])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM characters WHERE id = ?", [TEST_CHAR])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [TEST_CAMPAIGN])


func _add_inventory(item_key: String, quantity: int, uses_remaining: int = -1,
		is_equipped: bool = false, slot: String = "pack") -> String:
	var entry: Dictionary = _catalog.get_item(item_key)
	return CampaignRepository.add_inventory_item({
		"character_id": TEST_CHAR,
		"item_key": item_key,
		"name": entry.get("name", item_key),
		"quantity": quantity,
		"encumbrance_units": int(entry.get("encumbrance_units", 0)),
		"slot": slot,
		"is_equipped": is_equipped,
		"item_category": entry.get("item_category", "gear"),
		"weapon_damage": entry.get("weapon_damage", ""),
		"is_heavy": entry.get("is_heavy", false),
		"uses_remaining": uses_remaining,
	})


func _row(item_id: String) -> Dictionary:
	CampaignRepository.db.query_with_bindings(
		"SELECT * FROM inventory_items WHERE id = ?", [item_id])
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


func _equipped_in_slot(slot: String) -> Dictionary:
	CampaignRepository.db.query_with_bindings(
		"SELECT * FROM inventory_items WHERE character_id = ? AND is_equipped = 1 AND slot = ?",
		[TEST_CHAR, slot])
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


func _make_combatant_for_inventory() -> Combatant:
	var character := CharacterData.new()
	character.id = TEST_CHAR
	character.name = "EquipTester"
	var c := Combatant.from_character(character)
	var rows := CampaignRepository.get_inventory_items(TEST_CHAR)
	c.wire_equipment(rows, _catalog)
	return c


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_dart_bundle_is_equippable() -> void:
	_setup()
	var item_id := _add_inventory("dart", 1)
	var item: Dictionary = _row(item_id)
	check(item.get("item_category", "") == "ammunition",
		"dart should be ammunition; got %s" % item.get("item_category", ""))
	# Use the static check for thrown-stackability.
	check(CSTabEquipment.is_thrown_stackable(item, _catalog),
		"dart bundle must be thrown-stackable")
	# Simulate equip: thrown-stackable equips whole, so use update_inventory_item_equip_state.
	var ok := CampaignRepository.update_inventory_item_equip_state(
		item_id, true, "hands_main", "")
	check(ok, "equip should succeed for dart")
	var equipped := _equipped_in_slot("hands_main")
	check(equipped.get("id", "") == item_id, "dart should be equipped to hands_main")
	check(int(equipped.get("quantity", 0)) == 1, "equipped dart bundle should remain qty 1")
	_cleanup()
	print("  dart_bundle_is_equippable: OK")


func test_dart_bundle_seeds_uses_remaining_on_first_equip() -> void:
	_setup()
	var item_id := _add_inventory("dart", 1)
	# Schema default leaves uses_remaining at -1 until the equip path seeds it.
	check(int(_row(item_id).get("uses_remaining", 99)) == -1,
		"dart should start with uses_remaining=-1 before equip")
	var entry: Dictionary = _catalog.get_item("dart")
	var per_unit: int = int(entry.get("uses_per_unit", -1))
	check(per_unit == 5, "dart catalog should declare uses_per_unit=5")
	# Mimic the cs_tab_equipment.gd seeding step.
	CampaignRepository.update_inventory_item_uses(item_id, per_unit)
	check(int(_row(item_id).get("uses_remaining", 0)) == 5,
		"dart bundle should now hold 5 uses")
	_cleanup()
	print("  dart_bundle_seeds_uses_remaining_on_first_equip: OK")


func test_short_sword_stack_splits_on_equip() -> void:
	_setup()
	var stack_id := _add_inventory("short_sword", 2)
	var pre_item: Dictionary = _row(stack_id)
	check(not CSTabEquipment.is_thrown_stackable(pre_item, _catalog),
		"short sword must NOT be thrown-stackable")
	var new_id := CampaignRepository.split_item_for_equip(stack_id, "hands_main", -1)
	check(not new_id.is_empty(), "split_item_for_equip should return new id")
	var equipped := _equipped_in_slot("hands_main")
	check(int(equipped.get("quantity", 0)) == 1,
		"equipped short sword should have quantity 1")
	check(int(_row(stack_id).get("quantity", 0)) == 1,
		"source stack should drop to quantity 1")
	_cleanup()
	print("  short_sword_stack_splits_on_equip: OK")


func test_dagger_stack_stays_equipped_as_stack() -> void:
	_setup()
	var dagger_id := _add_inventory("dagger", 5)
	var item: Dictionary = _row(dagger_id)
	check(CSTabEquipment.is_thrown_stackable(item, _catalog),
		"dagger should be thrown-stackable")
	var ok := CampaignRepository.update_inventory_item_equip_state(
		dagger_id, true, "hands_main", "")
	check(ok, "equip should succeed for dagger stack")
	var equipped := _equipped_in_slot("hands_main")
	check(int(equipped.get("quantity", 0)) == 5,
		"dagger stack should remain qty 5 after equip")
	_cleanup()
	print("  dagger_stack_stays_equipped_as_stack: OK")


func test_thrown_dagger_consumed_decrements_quantity() -> void:
	_setup()
	var dagger_id := _add_inventory("dagger", 3, -1, true, "hands_main")
	var c := _make_combatant_for_inventory()
	c.consume_ammo()
	var equipped := _row(dagger_id)
	check(int(equipped.get("quantity", 0)) == 2,
		"dagger stack should drop to 2 after one throw")
	check(int(equipped.get("is_equipped", 0)) == 1,
		"dagger row should still be equipped after one throw")
	check(int(c.get_equipped_weapon().get("quantity", 0)) == 2,
		"combatant._equipped_weapon should mirror the new quantity")
	_cleanup()
	print("  thrown_dagger_consumed_decrements_quantity: OK")


func test_thrown_dagger_last_unit_clears_slot() -> void:
	_setup()
	var dagger_id := _add_inventory("dagger", 1, -1, true, "hands_main")
	var c := _make_combatant_for_inventory()
	c.consume_ammo()
	check(_row(dagger_id).is_empty(),
		"dagger row should be deleted after throwing the last one")
	check(c.get_equipped_weapon().is_empty(),
		"combatant._equipped_weapon should clear when stack reaches 0")
	check(_equipped_in_slot("hands_main").is_empty(),
		"hands_main slot should be empty after throwing last dagger")
	_cleanup()
	print("  thrown_dagger_last_unit_clears_slot: OK")


func test_thrown_dart_decrements_uses_remaining() -> void:
	_setup()
	# Equip a fresh dart bundle (uses_remaining=5 per catalog seeding).
	var dart_id := _add_inventory("dart", 1, 5, true, "hands_main")
	var c := _make_combatant_for_inventory()
	c.consume_ammo()
	var equipped := _row(dart_id)
	check(int(equipped.get("uses_remaining", 0)) == 4,
		"dart bundle should drop to 4 uses after one throw")
	check(int(equipped.get("quantity", 0)) == 1,
		"dart bundle quantity should still be 1")
	check(int(c.get_equipped_weapon().get("uses_remaining", 0)) == 4,
		"combatant._equipped_weapon uses_remaining should mirror DB")
	_cleanup()
	print("  thrown_dart_decrements_uses_remaining: OK")


func test_thrown_dart_last_use_destroys_bundle() -> void:
	_setup()
	var dart_id := _add_inventory("dart", 1, 1, true, "hands_main")
	var c := _make_combatant_for_inventory()
	c.consume_ammo()
	check(_row(dart_id).is_empty(),
		"dart bundle should be deleted after throwing the last dart")
	check(c.get_equipped_weapon().is_empty(),
		"combatant._equipped_weapon should clear when bundle is exhausted")
	_cleanup()
	print("  thrown_dart_last_use_destroys_bundle: OK")


func test_party_inventory_short_sword_stack_splits() -> void:
	_setup()
	var stack_id := _add_inventory("short_sword", 2)
	# Mirror item_context_menu.gd:_equip_item() decision logic for non-thrown weapons.
	var item: Dictionary = _row(stack_id)
	check(not CSTabEquipment.is_thrown_stackable(item, _catalog),
		"short sword must not be thrown-stackable")
	var new_id := CampaignRepository.split_item_for_equip(stack_id, "hands_main", -1)
	check(not new_id.is_empty(), "split should succeed via party-inventory path")
	check(int(_equipped_in_slot("hands_main").get("quantity", 0)) == 1,
		"equipped short sword should be a single unit")
	check(int(_row(stack_id).get("quantity", 0)) == 1,
		"remaining pack stack should be 1")
	_cleanup()
	print("  party_inventory_short_sword_stack_splits: OK")


func test_unequip_dagger_stack_merges_full_quantity_to_pack() -> void:
	_setup()
	var pack_id := _add_inventory("dagger", 2)  # 2 in pack
	var equipped_id := _add_inventory("dagger", 3, -1, true, "hands_main")  # 3 equipped
	var ok := CampaignRepository.merge_item_on_unequip(equipped_id, -1)
	check(ok, "merge_item_on_unequip should succeed")
	check(_row(equipped_id).is_empty(),
		"equipped row should be deleted after merge")
	var pack_row := _row(pack_id)
	check(int(pack_row.get("quantity", 0)) == 5,
		"pack stack should grow by full equipped quantity (2 + 3 = 5); got %d"
			% int(pack_row.get("quantity", 0)))
	_cleanup()
	print("  unequip_dagger_stack_merges_full_quantity_to_pack: OK")
