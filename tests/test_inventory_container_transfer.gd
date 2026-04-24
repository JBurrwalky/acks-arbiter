extends "res://tests/test_suite_base.gd"

## Unit tests for container-cascade behavior on inventory transfers.
##
## When a container (backpack, sack, chest) is transferred via any of the
## CampaignRepository.transfer_item_* functions or via LocationCacheManager
## drop/pickup, every descendant item (transitively through nested containers)
## must follow the outer container to the new carrier. Children keep their
## own container_id pointing at their parent, so nested structure is
## preserved on the destination.

const TEST_CAMPAIGN := "test_ict_campaign"
const TEST_PARTY := "test_ict_party"
const PC_A := "test_ict_pc_a"
const PC_B := "test_ict_pc_b"
const CREATURE_A := "test_ict_creature_a"
const VEHICLE_A := "test_ict_vehicle_a"

const DUNGEON_ID := "test_ict_dungeon"


func run_all_tests() -> void:
	test_backpack_to_character_carries_contents()
	test_backpack_to_party_carries_contents()
	test_sack_to_creature_carries_contents()
	test_sack_to_vehicle_carries_contents()
	test_chest_to_cache_carries_contents()
	test_cache_to_character_pickup_carries_contents()
	test_creature_to_character_carries_contents()
	test_vehicle_to_party_carries_contents()
	test_nested_containers_cascade()
	test_empty_container_transfers_without_error()

	if not has_failures():
		print("InventoryContainerTransfer: all tests passed.")


# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

func _setup() -> void:
	_cleanup()

	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[TEST_CAMPAIGN, "ICT Test"])

	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO parties (id, campaign_id, name) VALUES (?, ?, ?)",
		[TEST_PARTY, TEST_CAMPAIGN, "Test Party"])

	for pc_id in [PC_A, PC_B]:
		CampaignRepository.db.query_with_bindings("""
			INSERT OR IGNORE INTO characters
				(id, campaign_id, name, character_type, persistence_tier, race,
				 character_class, level, xp, combat_progression,
				 strength, intelligence, wisdom, dexterity, constitution, charisma)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		""", [pc_id, TEST_CAMPAIGN, "Name_" + pc_id, "pc", "full", "human",
			  "fighter", 1, 0, "fighter", 10, 10, 10, 10, 10, 10])
		CampaignRepository.db.query_with_bindings(
			"INSERT OR IGNORE INTO party_members (party_id, character_id, formation_slot) VALUES (?, ?, ?)",
			[TEST_PARTY, pc_id, "middle"])

	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO trained_creatures
			(id, campaign_id, party_id, species_id, name, hp_current, hp_max)
		VALUES (?, ?, ?, ?, ?, ?, ?)
	""", [CREATURE_A, TEST_CAMPAIGN, TEST_PARTY, "mule", "Bessie", 5, 5])

	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO draft_vehicles
			(id, campaign_id, party_id, item_key, name)
		VALUES (?, ?, ?, ?, ?)
	""", [VEHICLE_A, TEST_CAMPAIGN, TEST_PARTY, "cart", "Cart"])

	GameState.campaign_id = TEST_CAMPAIGN
	GameState.party_id = TEST_PARTY
	GameState.current_location_key = "hex:0,0"


func _cleanup() -> void:
	GameState.dice_overrides.clear()

	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE character_id IN (?, ?)", [PC_A, PC_B])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE creature_id = ?", [CREATURE_A])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE vehicle_id = ?", [VEHICLE_A])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE party_id = ?", [TEST_PARTY])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE location_cache_id IN (SELECT id FROM location_caches WHERE campaign_id = ?)",
		[TEST_CAMPAIGN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM location_caches WHERE campaign_id = ?", [TEST_CAMPAIGN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM trained_creatures WHERE id = ?", [CREATURE_A])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM draft_vehicles WHERE id = ?", [VEHICLE_A])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM party_members WHERE party_id = ?", [TEST_PARTY])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM characters WHERE id IN (?, ?)", [PC_A, PC_B])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM parties WHERE id = ?", [TEST_PARTY])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [TEST_CAMPAIGN])

	GameState.campaign_id = ""
	GameState.party_id = ""
	GameState.current_location_key = "unknown"


## Creates a test item on a character with optional container nesting.
func _mk_item(character_id: String, item_key: String, item_name: String,
		container_id: String = "") -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO inventory_items
			(id, character_id, item_key, name, quantity, encumbrance_units,
			 slot, is_equipped, item_category, container_id)
		VALUES (?, ?, ?, ?, 1, 100, 'pack', 0, 'gear', ?)
	""", [id, character_id, item_key, item_name, container_id])
	return id


## Fetches a single item row by id. Returns {} if missing.
func _get_item(item_id: String) -> Dictionary:
	CampaignRepository.db.query_with_bindings(
		"SELECT * FROM inventory_items WHERE id = ?", [item_id])
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0]


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_backpack_to_character_carries_contents() -> void:
	_setup()
	var backpack := _mk_item(PC_A, "backpack", "Backpack")
	var dagger := _mk_item(PC_A, "dagger", "Dagger", backpack)
	var torch := _mk_item(PC_A, "torch", "Torch", backpack)
	var rope := _mk_item(PC_A, "rope", "50ft Rope", backpack)

	var ok := CampaignRepository.transfer_item_to_character(backpack, PC_B)
	check(ok, "transfer_item_to_character should return true")

	check(str(_get_item(backpack).get("character_id", "")) == PC_B,
		"backpack should be on PC_B")
	for child_id in [dagger, torch, rope]:
		var row := _get_item(child_id)
		check(str(row.get("character_id", "")) == PC_B,
			"content %s should be on PC_B" % row.get("name", child_id))
		check(str(row.get("container_id", "")) == backpack,
			"content %s should still point at backpack" % row.get("name", child_id))
	_cleanup()


func test_backpack_to_party_carries_contents() -> void:
	_setup()
	var backpack := _mk_item(PC_A, "backpack", "Backpack")
	var potion := _mk_item(PC_A, "potion", "Healing Potion", backpack)

	var ok := CampaignRepository.transfer_item_to_party(backpack, TEST_PARTY)
	check(ok, "transfer_item_to_party should return true")

	var bp_row := _get_item(backpack)
	check(str(bp_row.get("party_id", "")) == TEST_PARTY, "backpack should be in party pool")
	check(str(bp_row.get("character_id", "")) == "", "backpack character_id should be cleared")

	var pot_row := _get_item(potion)
	check(str(pot_row.get("party_id", "")) == TEST_PARTY, "potion should be in party pool")
	check(str(pot_row.get("character_id", "")) == "", "potion character_id should be cleared")
	check(str(pot_row.get("container_id", "")) == backpack, "potion still in backpack")
	_cleanup()


func test_sack_to_creature_carries_contents() -> void:
	_setup()
	var sack := _mk_item(PC_A, "sack_large", "Sack of Grain")
	var coin := _mk_item(PC_A, "coin", "Gold Coin", sack)

	var ok := CampaignRepository.transfer_item_to_creature(sack, CREATURE_A)
	check(ok, "transfer_item_to_creature should return true")

	var sack_row := _get_item(sack)
	check(str(sack_row.get("creature_id", "")) == CREATURE_A, "sack on creature")

	var coin_row := _get_item(coin)
	check(str(coin_row.get("creature_id", "")) == CREATURE_A, "coin on creature")
	check(str(coin_row.get("character_id", "")) == "", "coin character_id cleared")
	check(str(coin_row.get("container_id", "")) == sack, "coin still in sack")
	_cleanup()


func test_sack_to_vehicle_carries_contents() -> void:
	_setup()
	var sack := _mk_item(PC_A, "sack_large", "Sack")
	var grain := _mk_item(PC_A, "grain", "Grain", sack)

	var ok := CampaignRepository.transfer_item_to_vehicle(sack, VEHICLE_A)
	check(ok, "transfer_item_to_vehicle should return true")

	var sack_row := _get_item(sack)
	check(str(sack_row.get("vehicle_id", "")) == VEHICLE_A, "sack on vehicle")

	var grain_row := _get_item(grain)
	check(str(grain_row.get("vehicle_id", "")) == VEHICLE_A, "grain on vehicle")
	check(str(grain_row.get("container_id", "")) == sack, "grain still in sack")
	_cleanup()


func test_chest_to_cache_carries_contents() -> void:
	_setup()
	GameState.dice_overrides["cache_decay_timer"] = 7
	var cache_id := LocationCacheManager.create_dungeon_loose_cache(
		DUNGEON_ID, Vector3i(0, 0, 0))
	var chest := _mk_item(PC_A, "chest_large", "Chest")
	var gem := _mk_item(PC_A, "gem", "Ruby", chest)
	var scroll := _mk_item(PC_A, "scroll", "Scroll", chest)

	var ok := LocationCacheManager.drop_item_to_cache(chest, cache_id, PC_A)
	check(ok, "drop_item_to_cache should return true")

	for item_id in [chest, gem, scroll]:
		var row := _get_item(item_id)
		check(str(row.get("location_cache_id", "")) == cache_id,
			"%s should be in cache" % row.get("name", item_id))
		check(str(row.get("character_id", "")) == "",
			"%s character_id should be cleared" % row.get("name", item_id))
	check(str(_get_item(gem).get("container_id", "")) == chest, "gem still in chest")
	check(str(_get_item(scroll).get("container_id", "")) == chest, "scroll still in chest")
	_cleanup()


func test_cache_to_character_pickup_carries_contents() -> void:
	_setup()
	GameState.dice_overrides["cache_decay_timer"] = 7
	var cache_id := LocationCacheManager.create_dungeon_loose_cache(
		DUNGEON_ID, Vector3i(0, 0, 0))
	var chest := _mk_item(PC_A, "chest_large", "Chest")
	var gem := _mk_item(PC_A, "gem", "Ruby", chest)
	LocationCacheManager.drop_item_to_cache(chest, cache_id, PC_A)

	var ok := LocationCacheManager.pick_up_item(chest, PC_B, "character")
	check(ok, "pick_up_item should return true")

	for item_id in [chest, gem]:
		var row := _get_item(item_id)
		check(str(row.get("character_id", "")) == PC_B,
			"%s should be on PC_B" % row.get("name", item_id))
		var lci = row.get("location_cache_id")
		check(lci == null or str(lci) == "",
			"%s location_cache_id should be cleared" % row.get("name", item_id))
	check(str(_get_item(gem).get("container_id", "")) == chest, "gem still in chest")
	_cleanup()


func test_creature_to_character_carries_contents() -> void:
	_setup()
	# Seed a sack on the creature with contents.
	var sack := _mk_item(PC_A, "sack_large", "Sack")
	var coin := _mk_item(PC_A, "coin", "Gold Coin", sack)
	# Transfer to creature first (exercises the function but also sets up the next transfer).
	CampaignRepository.transfer_item_to_creature(sack, CREATURE_A)
	# Verify precondition.
	check(str(_get_item(coin).get("creature_id", "")) == CREATURE_A,
		"precondition: coin should now be on creature")

	var ok := CampaignRepository.transfer_item_from_creature_to_character(sack, PC_B)
	check(ok, "transfer_item_from_creature_to_character should return true")

	var coin_row := _get_item(coin)
	check(str(coin_row.get("character_id", "")) == PC_B, "coin on PC_B")
	check(str(coin_row.get("creature_id", "")) == "", "coin creature_id cleared")
	check(str(coin_row.get("container_id", "")) == sack, "coin still in sack")
	_cleanup()


func test_vehicle_to_party_carries_contents() -> void:
	_setup()
	var barrel := _mk_item(PC_A, "barrel", "Barrel")
	var ale := _mk_item(PC_A, "ale", "Ale", barrel)
	CampaignRepository.transfer_item_to_vehicle(barrel, VEHICLE_A)
	check(str(_get_item(ale).get("vehicle_id", "")) == VEHICLE_A,
		"precondition: ale should now be on vehicle")

	var ok := CampaignRepository.transfer_item_from_vehicle_to_party(barrel, TEST_PARTY)
	check(ok, "transfer_item_from_vehicle_to_party should return true")

	var ale_row := _get_item(ale)
	check(str(ale_row.get("party_id", "")) == TEST_PARTY, "ale in party pool")
	check(str(ale_row.get("container_id", "")) == barrel, "ale still in barrel")
	_cleanup()


func test_nested_containers_cascade() -> void:
	_setup()
	var backpack := _mk_item(PC_A, "backpack", "Backpack")
	var pouch := _mk_item(PC_A, "pouch", "Pouch", backpack)
	var coin_a := _mk_item(PC_A, "coin", "Coin A", pouch)
	var coin_b := _mk_item(PC_A, "coin", "Coin B", pouch)

	var ok := CampaignRepository.transfer_item_to_character(backpack, PC_B)
	check(ok, "nested transfer should return true")

	# All four items on PC_B.
	for item_id in [backpack, pouch, coin_a, coin_b]:
		var row := _get_item(item_id)
		check(str(row.get("character_id", "")) == PC_B,
			"%s should be on PC_B" % row.get("name", item_id))

	# Nested structure preserved.
	check(str(_get_item(pouch).get("container_id", "")) == backpack,
		"pouch still inside backpack")
	check(str(_get_item(coin_a).get("container_id", "")) == pouch,
		"coin_a still inside pouch")
	check(str(_get_item(coin_b).get("container_id", "")) == pouch,
		"coin_b still inside pouch")
	_cleanup()


func test_empty_container_transfers_without_error() -> void:
	_setup()
	var backpack := _mk_item(PC_A, "backpack", "Empty Backpack")

	var ok := CampaignRepository.transfer_item_to_character(backpack, PC_B)
	check(ok, "empty container transfer should succeed")
	check(str(_get_item(backpack).get("character_id", "")) == PC_B,
		"empty backpack should be on PC_B")
	_cleanup()
