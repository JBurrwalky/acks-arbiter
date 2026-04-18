extends "res://tests/test_suite_base.gd"

## Unit tests for entity promotion: animals → trained_creatures,
## vehicles → draft_vehicles, livestock → inventory_items (unchanged).

const TEST_CAMPAIGN_ID := "test_entity_promo_campaign"
const TEST_CHARACTER_ID := "test_entity_promo_char_01"
const TEST_PARTY_ID := "test_entity_promo_party"
const TEST_SETTLEMENT_ID := "test_entity_promo_settlement"
const TEST_POI_ID := "test_entity_promo_poi"

var _service: ShopService
var _catalog: EquipmentCatalog


func run_all_tests() -> void:
	_setup()
	test_classify_creature()
	test_classify_vehicle()
	test_classify_livestock()
	test_classify_gear()
	test_promote_creature()
	test_promote_vehicle()
	test_promote_non_promotable()
	test_promote_multi_quantity()
	test_shop_buy_mule()
	test_shop_buy_cart()
	test_shop_buy_cow()
	test_roster_includes_creatures()
	test_roster_excludes_dead()
	_teardown()
	if not has_failures():
		print("EntityPromotion: all tests passed.")


# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

func _setup() -> void:
	_service = ShopService.new()
	_catalog = EquipmentCatalog.new()

	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name, world_name) VALUES (?, ?, ?)",
		[TEST_CAMPAIGN_ID, "Entity Promo Test", "Test World"])

	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_class, level, xp, hp_max, hp_current)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)
	""", [TEST_CHARACTER_ID, TEST_CAMPAIGN_ID, "Test Buyer", "fighter", 1, 0, 8, 8])

	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO parties (id, campaign_id, name) VALUES (?, ?, ?)",
		[TEST_PARTY_ID, TEST_CAMPAIGN_ID, "Test Party"])

	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO party_members (party_id, character_id) VALUES (?, ?)",
		[TEST_PARTY_ID, TEST_CHARACTER_ID])

	GameState.campaign_id = TEST_CAMPAIGN_ID

	# Give 500gp (50000cp) to cover any purchase.
	CampaignRepository.add_specific_coins(TEST_CHARACTER_ID, "coins_gp", 500)


func _teardown() -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM trained_creatures WHERE campaign_id = ?", [TEST_CAMPAIGN_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM draft_vehicles WHERE campaign_id = ?", [TEST_CAMPAIGN_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM shop_inventory WHERE campaign_id = ?", [TEST_CAMPAIGN_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE character_id = ?", [TEST_CHARACTER_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM party_members WHERE party_id = ?", [TEST_PARTY_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM parties WHERE id = ?", [TEST_PARTY_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM characters WHERE id = ?", [TEST_CHARACTER_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [TEST_CAMPAIGN_ID])


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _seed_shop_stock(item_key: String, qty: int) -> void:
	CampaignRepository.db.query_with_bindings("""
		INSERT OR REPLACE INTO shop_inventory
			(id, campaign_id, settlement_id, poi_id, item_key, quantity_available, generated_at_round)
		VALUES (?, ?, ?, ?, ?, ?, ?)
	""", [
		"stock_%s" % item_key, TEST_CAMPAIGN_ID, TEST_SETTLEMENT_ID,
		TEST_POI_ID, item_key, qty, 0,
	])


func _count_trained_creatures() -> int:
	CampaignRepository.db.query_with_bindings(
		"SELECT COUNT(*) AS cnt FROM trained_creatures WHERE campaign_id = ?",
		[TEST_CAMPAIGN_ID])
	return int(CampaignRepository.db.query_result[0].get("cnt", 0))


func _count_draft_vehicles() -> int:
	CampaignRepository.db.query_with_bindings(
		"SELECT COUNT(*) AS cnt FROM draft_vehicles WHERE campaign_id = ?",
		[TEST_CAMPAIGN_ID])
	return int(CampaignRepository.db.query_result[0].get("cnt", 0))


func _count_inventory_items_by_key(item_key: String) -> int:
	CampaignRepository.db.query_with_bindings(
		"SELECT COUNT(*) AS cnt FROM inventory_items WHERE character_id = ? AND item_key = ?",
		[TEST_CHARACTER_ID, item_key])
	return int(CampaignRepository.db.query_result[0].get("cnt", 0))


# ---------------------------------------------------------------------------
# Tests: classify_item_for_promotion
# ---------------------------------------------------------------------------

func test_classify_creature() -> void:
	var entry := _catalog.get_item("mule")
	var result := CampaignRepository.classify_item_for_promotion(entry)
	check(result == "creature", "mule should classify as creature, got: %s" % result)
	print("  classify_creature: OK")


func test_classify_vehicle() -> void:
	var entry := _catalog.get_item("cart_small")
	var result := CampaignRepository.classify_item_for_promotion(entry)
	check(result == "vehicle", "cart should classify as vehicle, got: %s" % result)
	print("  classify_vehicle: OK")


func test_classify_livestock() -> void:
	var entry := _catalog.get_item("cow")
	var result := CampaignRepository.classify_item_for_promotion(entry)
	check(result == "inventory", "cow should classify as inventory, got: %s" % result)
	print("  classify_livestock: OK")


func test_classify_gear() -> void:
	var entry := _catalog.get_item("sword")
	var result := CampaignRepository.classify_item_for_promotion(entry)
	check(result == "inventory", "sword should classify as inventory, got: %s" % result)
	print("  classify_gear: OK")


# ---------------------------------------------------------------------------
# Tests: promote_inventory_to_entity
# ---------------------------------------------------------------------------

func test_promote_creature() -> void:
	var registry := MonsterRegistry.new()
	var before := _count_trained_creatures()
	var result := CampaignRepository.promote_inventory_to_entity(
		"mule", 1, TEST_CHARACTER_ID, TEST_CAMPAIGN_ID, TEST_PARTY_ID, _catalog, registry)
	check(result != "", "promote mule should return creature_id, got empty")
	var after := _count_trained_creatures()
	check(after == before + 1, "should have 1 more creature, before=%d after=%d" % [before, after])
	print("  promote_creature: OK")


func test_promote_vehicle() -> void:
	var registry := MonsterRegistry.new()
	var item_key := "cart_small"
	var before := _count_draft_vehicles()
	var result := CampaignRepository.promote_inventory_to_entity(
		item_key, 1, TEST_CHARACTER_ID, TEST_CAMPAIGN_ID, TEST_PARTY_ID, _catalog, registry)
	check(result != "", "promote cart should return vehicle_id, got empty")
	var after := _count_draft_vehicles()
	check(after == before + 1, "should have 1 more vehicle, before=%d after=%d" % [before, after])
	print("  promote_vehicle: OK")


func test_promote_non_promotable() -> void:
	var registry := MonsterRegistry.new()
	var result := CampaignRepository.promote_inventory_to_entity(
		"sword", 1, TEST_CHARACTER_ID, TEST_CAMPAIGN_ID, TEST_PARTY_ID, _catalog, registry)
	check(result == "", "promote sword should return empty, got: %s" % result)
	print("  promote_non_promotable: OK")


func test_promote_multi_quantity() -> void:
	var registry := MonsterRegistry.new()
	var before := _count_trained_creatures()
	CampaignRepository.promote_inventory_to_entity(
		"mule", 3, TEST_CHARACTER_ID, TEST_CAMPAIGN_ID, TEST_PARTY_ID, _catalog, registry)
	var after := _count_trained_creatures()
	check(after == before + 3, "should have 3 more creatures, before=%d after=%d" % [before, after])
	print("  promote_multi_quantity: OK")


# ---------------------------------------------------------------------------
# Tests: shop buy with promotion
# ---------------------------------------------------------------------------

func test_shop_buy_mule() -> void:
	_seed_shop_stock("mule", 5)
	var creatures_before := _count_trained_creatures()
	var result := _service.buy_item(TEST_CHARACTER_ID, "mule", 1, TEST_POI_ID, TEST_CAMPAIGN_ID)
	check(result["success"], "buy mule should succeed: %s" % result.get("message", ""))
	var creatures_after := _count_trained_creatures()
	check(creatures_after == creatures_before + 1,
		"should create trained_creature row, before=%d after=%d" % [creatures_before, creatures_after])
	var inv_count := _count_inventory_items_by_key("mule")
	check(inv_count == 0, "mule should NOT be in inventory_items, found %d" % inv_count)
	print("  shop_buy_mule: OK")


func test_shop_buy_cart() -> void:
	var item_key := "cart_small"
	_seed_shop_stock(item_key, 5)
	var vehicles_before := _count_draft_vehicles()
	var result := _service.buy_item(TEST_CHARACTER_ID, item_key, 1, TEST_POI_ID, TEST_CAMPAIGN_ID)
	check(result["success"], "buy cart should succeed: %s" % result.get("message", ""))
	var vehicles_after := _count_draft_vehicles()
	check(vehicles_after == vehicles_before + 1,
		"should create draft_vehicle row, before=%d after=%d" % [vehicles_before, vehicles_after])
	var inv_count := _count_inventory_items_by_key(item_key)
	check(inv_count == 0, "cart should NOT be in inventory_items, found %d" % inv_count)
	print("  shop_buy_cart: OK")


func test_shop_buy_cow() -> void:
	_seed_shop_stock("cow", 5)
	var creatures_before := _count_trained_creatures()
	var result := _service.buy_item(TEST_CHARACTER_ID, "cow", 1, TEST_POI_ID, TEST_CAMPAIGN_ID)
	check(result["success"], "buy cow should succeed: %s" % result.get("message", ""))
	var creatures_after := _count_trained_creatures()
	check(creatures_after == creatures_before,
		"cow should NOT create trained_creature, before=%d after=%d" % [creatures_before, creatures_after])
	var inv_count := _count_inventory_items_by_key("cow")
	check(inv_count == 1, "cow should be in inventory_items, found %d" % inv_count)
	print("  shop_buy_cow: OK")


# ---------------------------------------------------------------------------
# Tests: combat roster
# ---------------------------------------------------------------------------

func test_roster_includes_creatures() -> void:
	var registry := MonsterRegistry.new()

	# Create a war dog creature (combat role G = Guard).
	CampaignRepository.promote_inventory_to_entity(
		"war_dog", 1, TEST_CHARACTER_ID, TEST_CAMPAIGN_ID, TEST_PARTY_ID, _catalog, registry)

	# Build a minimal party data with the creature.
	var party_data := PartyData.new()
	var cd := CharacterData.new()
	cd.id = TEST_CHARACTER_ID
	cd.name = "Test Fighter"
	cd.is_dead = false
	cd.is_active = true
	party_data.character_data.append(cd)

	# Load creatures from DB.
	var creatures := CampaignRepository.get_trained_creatures_for_party(TEST_PARTY_ID)
	for c_row in creatures:
		var creature := TrainedCreatureData.from_db(c_row)
		creature.monster_data = registry.get_monster(creature.species_id)
		party_data.creature_data.append(creature)

	# Build roster and add creatures.
	var encounter := {"monster_group": "goblin", "number": 1}
	var roster := CombatRoster.build_from_encounter(party_data, encounter, registry)
	roster.add_party_creatures(party_data, registry)

	var party_combatants := roster.get_party_combatants()
	# Should have at least 2: 1 PC + 1 war dog
	check(party_combatants.size() >= 2,
		"roster should include creature combatant, got %d party combatants" % party_combatants.size())
	print("  roster_includes_creatures: OK")


func test_roster_excludes_dead() -> void:
	var registry := MonsterRegistry.new()

	# Create a party data with a dead creature.
	var party_data := PartyData.new()
	var cd := CharacterData.new()
	cd.id = TEST_CHARACTER_ID
	cd.name = "Test Fighter"
	cd.is_dead = false
	cd.is_active = true
	party_data.character_data.append(cd)

	# Create a dead creature manually.
	var dead_creature := TrainedCreatureData.new()
	dead_creature.id = "dead_test_creature"
	dead_creature.species_id = "dog_war"
	dead_creature.role = "G"
	dead_creature.is_alive = false
	dead_creature.hp_current = 0
	dead_creature.hp_max = 6
	dead_creature.monster_data = registry.get_monster("dog_war")
	party_data.creature_data.append(dead_creature)

	var encounter := {"monster_group": "goblin", "number": 1}
	var roster := CombatRoster.build_from_encounter(party_data, encounter, registry)
	roster.add_party_creatures(party_data, registry)

	var party_combatants := roster.get_party_combatants()
	# Should only have 1: the PC. Dead creature excluded.
	check(party_combatants.size() == 1,
		"dead creature should be excluded, got %d party combatants" % party_combatants.size())
	print("  roster_excludes_dead: OK")
