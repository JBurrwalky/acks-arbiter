extends "res://tests/test_suite_base.gd"

## Tests for equipment-derived Armor Class (CharacterAcCalculator) and its
## persistence integration through CampaignRepository's equip-state write paths.
##
## ACKS ascending AC (RAW): base 0 (unarmored) + best equipped body-armor AC +
## equipped shield AC + Dexterity modifier + armor/shield magical_bonus. Spell /
## condition AC effects are NOT folded in here — they layer via
## CharacterData.get_effective_ac() (coding_conventions §12).
##   armor table — acore_equipment.xml:143-149 (Leather 2 ... Plate 6, Shield +1)
##   DEX → AC    — acore_basics_and_characters.xml:242, :150

const TEST_CAMPAIGN := "test_ac_campaign"
const TEST_CHAR := "test_ac_pc"


func run_all_tests() -> void:
	# Pure calculator unit tests
	test_unarmored_ac_is_dex_mod()
	test_leather_armor_adds_2()
	test_magic_leather_plus_one_adds_3()
	test_shield_adds()
	test_dexterity_modifier_adds()
	test_unequipped_armor_ignored()
	test_non_armor_items_ignored()
	test_shield_must_be_hands_off()
	test_full_loadout()
	test_best_of_duplicate_body_armor()
	test_accepts_inventory_item_objects()
	test_recompute_writes_field()
	# DB integration tests
	test_db_equip_and_unequip_armor()
	test_db_equip_shield_stacks_with_armor()
	test_db_magic_armor_bonus()
	test_db_dexterity_change_recomputes()
	test_db_sanitize_repairs_stale_ac()

	_cleanup()
	if not has_failures():
		print("CharacterAcCalculator: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _char(dex: int) -> CharacterData:
	var c := CharacterData.new()
	c.dexterity = dex
	return c


func _row(category: String, slot: String, ac_bonus: int, magic: int = 0,
		equipped: bool = true) -> Dictionary:
	return {
		"item_category": category,
		"slot": slot,
		"is_equipped": 1 if equipped else 0,
		"armor_ac_bonus": ac_bonus,
		"magical_bonus": magic,
	}


# ---------------------------------------------------------------------------
# Pure calculator unit tests
# ---------------------------------------------------------------------------

func test_unarmored_ac_is_dex_mod() -> void:
	check(CharacterAcCalculator.compute(_char(10), []) == 0,
		"unarmored dex 10 (mod 0) → AC 0")
	check(CharacterAcCalculator.compute(_char(16), []) == 2,
		"unarmored dex 16 (mod +2) → AC 2")
	check(CharacterAcCalculator.compute(_char(6), []) == -1,
		"unarmored dex 6 (mod -1) → AC -1")


func test_leather_armor_adds_2() -> void:
	var rows := [_row("armor", "body", 2)]
	check(CharacterAcCalculator.compute(_char(10), rows) == 2,
		"leather (AC 2) + dex 10 → AC 2")


func test_magic_leather_plus_one_adds_3() -> void:
	var rows := [_row("armor", "body", 2, 1)]  # +1 leather
	check(CharacterAcCalculator.compute(_char(10), rows) == 3,
		"+1 leather (2 + magic 1) + dex 10 → AC 3")


func test_shield_adds() -> void:
	var rows := [_row("armor", "body", 2), _row("shield", "hands_off", 1)]
	check(CharacterAcCalculator.compute(_char(10), rows) == 3,
		"leather (2) + shield (1) + dex 10 → AC 3")


func test_dexterity_modifier_adds() -> void:
	var rows := [_row("armor", "body", 2)]
	check(CharacterAcCalculator.compute(_char(13), rows) == 3,
		"leather (2) + dex 13 (mod +1) → AC 3")


func test_unequipped_armor_ignored() -> void:
	var rows := [_row("armor", "body", 2, 0, false)]  # leather, NOT equipped
	check(CharacterAcCalculator.compute(_char(10), rows) == 0,
		"unequipped leather contributes nothing → AC 0 (dex 10)")


func test_non_armor_items_ignored() -> void:
	var rows := [
		_row("weapon", "hands_main", 0),       # equipped sword (no AC)
		_row("gear", "hands_off", 0),          # equipped torch (no AC)
		_row("armor", "body", 2),              # leather (counts)
	]
	check(CharacterAcCalculator.compute(_char(10), rows) == 2,
		"only body armor contributes; weapon/gear ignored → AC 2")


func test_shield_must_be_hands_off() -> void:
	# A shield row equipped in the wrong slot (e.g. left in pack) is not worn.
	var rows := [_row("shield", "pack", 1)]
	check(CharacterAcCalculator.compute(_char(10), rows) == 0,
		"shield not in hands_off does not grant AC → AC 0")


func test_full_loadout() -> void:
	var rows := [
		_row("armor", "body", 6, 1),       # +1 plate → 7
		_row("shield", "hands_off", 1),    # shield → 1
	]
	check(CharacterAcCalculator.compute(_char(16), rows) == 10,
		"+1 plate (7) + shield (1) + dex 16 (+2) → AC 10")


func test_best_of_duplicate_body_armor() -> void:
	# Defensive: if malformed data has two equipped body suits, take the best.
	var rows := [_row("armor", "body", 2), _row("armor", "body", 6)]
	check(CharacterAcCalculator.compute(_char(10), rows) == 6,
		"two equipped body armors → best (plate 6), not sum → AC 6")


func test_accepts_inventory_item_objects() -> void:
	# The dual-shape contract: InventoryItem objects work as well as dicts.
	var leather := InventoryItem.from_dict({
		"item_category": "armor", "slot": "body",
		"is_equipped": 1, "armor_ac_bonus": 2, "magical_bonus": 0,
	})
	var shield := InventoryItem.from_dict({
		"item_category": "shield", "slot": "hands_off",
		"is_equipped": 1, "armor_ac_bonus": 1, "magical_bonus": 0,
	})
	check(CharacterAcCalculator.compute(_char(10), [leather, shield]) == 3,
		"InventoryItem objects: leather + shield + dex 10 → AC 3")


func test_recompute_writes_field() -> void:
	var c := _char(13)
	c.armor_class = 99  # stale value
	var result := CharacterAcCalculator.recompute(c, [_row("armor", "body", 4)])
	check(result == 5, "recompute returns chain (4) + dex 13 (+1) → 5")
	check(c.armor_class == 5, "recompute writes armor_class field → 5")


# ---------------------------------------------------------------------------
# DB integration tests (equip-state write paths persist recomputed AC)
# ---------------------------------------------------------------------------

func _setup(dex: int = 10) -> void:
	_cleanup()
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[TEST_CAMPAIGN, "AcTest"])
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_type, persistence_tier, race,
			 character_class, level, xp, combat_progression,
			 strength, intelligence, wisdom, dexterity, constitution, charisma,
			 armor_class)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [TEST_CHAR, TEST_CAMPAIGN, "AcTester", "pc", "full", "human",
		  "fighter", 1, 0, "fighter", 10, 10, 10, dex, 10, 10, 0])


func _cleanup() -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE character_id = ?", [TEST_CHAR])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM characters WHERE id = ?", [TEST_CHAR])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [TEST_CAMPAIGN])


func _add_armor(item_key: String, category: String, ac_bonus: int,
		magic: int = 0, equipped: bool = false, slot: String = "pack") -> String:
	return CampaignRepository.add_inventory_item({
		"character_id": TEST_CHAR,
		"item_key": item_key,
		"name": item_key,
		"quantity": 1,
		"encumbrance_units": 0,
		"slot": slot,
		"is_equipped": equipped,
		"item_category": category,
		"is_magical": magic > 0,
		"magical_bonus": magic,
		"armor_ac_bonus": ac_bonus,
	})


func _db_ac() -> int:
	return int(CampaignRepository.get_character(TEST_CHAR).get("armor_class", -999))


func test_db_equip_and_unequip_armor() -> void:
	_setup(10)
	var item_id := _add_armor("leather_armor", "armor", 2)
	check(_db_ac() == 0, "before equip: AC 0 (dex 10, nothing worn)")
	CampaignRepository.update_inventory_item_equip_state(item_id, true, "body")
	check(_db_ac() == 2, "after equipping leather: DB AC 2")
	CampaignRepository.update_inventory_item_equip_state(item_id, false, "pack")
	check(_db_ac() == 0, "after unequipping leather: DB AC back to 0")
	_cleanup()


func test_db_equip_shield_stacks_with_armor() -> void:
	_setup(10)
	var leather := _add_armor("leather_armor", "armor", 2)
	var shield := _add_armor("shield", "shield", 1)
	CampaignRepository.update_inventory_item_equip_state(leather, true, "body")
	CampaignRepository.update_inventory_item_equip_state(shield, true, "hands_off")
	check(_db_ac() == 3, "leather (2) + shield (1) + dex 10 → DB AC 3")
	_cleanup()


func test_db_magic_armor_bonus() -> void:
	_setup(10)
	var item_id := _add_armor("leather_armor_plus_1", "armor", 2, 1)
	CampaignRepository.update_inventory_item_equip_state(item_id, true, "body")
	check(_db_ac() == 3, "+1 leather (2 + magic 1) + dex 10 → DB AC 3")
	_cleanup()


func test_db_dexterity_change_recomputes() -> void:
	_setup(10)
	var item_id := _add_armor("leather_armor", "armor", 2)
	CampaignRepository.update_inventory_item_equip_state(item_id, true, "body")
	check(_db_ac() == 2, "leather + dex 10 → AC 2")
	# Simulate a Dexterity change (as the GM-override path does), then recompute.
	CampaignRepository.db.query_with_bindings(
		"UPDATE characters SET dexterity = ? WHERE id = ?", [16, TEST_CHAR])
	CampaignRepository.recompute_character_armor_class(TEST_CHAR)
	check(_db_ac() == 4, "leather (2) + dex 16 (+2) after recompute → AC 4")
	_cleanup()


func test_db_sanitize_repairs_stale_ac() -> void:
	# Legacy-save repair: a fighter wearing leather whose stored AC is stale (0).
	# sanitize_character_equipment leaves the (legal) leather equipped and the
	# end-of-function recompute repairs the AC.
	_setup(10)
	var item_id := _add_armor("leather_armor", "armor", 2, 0, true, "body")
	CampaignRepository.db.query_with_bindings(
		"UPDATE characters SET armor_class = ? WHERE id = ?", [0, TEST_CHAR])
	check(_db_ac() == 0, "precondition: stale AC 0 with leather equipped")
	CampaignRepository.sanitize_character_equipment(TEST_CHAR)
	check(_db_ac() == 2, "sanitize repairs stale AC: leather (2) + dex 10 → AC 2")
	check(item_id != "", "leather row was created")
	_cleanup()
