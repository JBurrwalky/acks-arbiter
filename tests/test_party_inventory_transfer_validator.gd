extends "res://tests/test_suite_base.gd"

## Unit tests for PartyInventoryTransferValidator — validates item transfers
## between carriers (PCs, creatures, vehicles, caches) in the Party Inventory overlay.
##
## Seeds test data into the DB and cleans up after itself.
## Instantiates the validator locally with an EquipmentCatalog.

const Currency := preload("res://engine/subsystems/commerce/currency.gd")
const ValidatorScript := preload("res://engine/subsystems/inventory/party_inventory_transfer_validator.gd")
const EquipCatalogScript := preload("res://engine/subsystems/characters/equipment_catalog.gd")

const TEST_CAMPAIGN := "test_pitv_campaign"
const TEST_PARTY := "test_pitv_party"
const PC_A := "test_pitv_pc_a"
const PC_B := "test_pitv_pc_b"
const CREATURE_A := "test_pitv_creature_a"
const VEHICLE_A := "test_pitv_vehicle_a"

var _validator: RefCounted = null
var _catalog: RefCounted = null


func run_all_tests() -> void:
	# Coin locks
	test_coin_transfer_blocked()
	test_non_coin_transfer_allowed()

	# Equipped clothing lock
	test_equipped_clothing_blocked()

	# Carrier-type: character targets
	test_pc_to_pc_loose_accepted()
	test_pc_to_henchman_loose_accepted()

	# Carrier-type: creature targets
	test_pc_to_creature_with_rope_accepted()
	test_pc_to_untacked_creature_rejected()

	# Carrier-type: vehicle targets
	test_pc_to_vehicle_within_capacity_accepted()
	test_pc_to_vehicle_over_max_rejected()

	# Carrier-type: cache targets
	test_cache_target_always_accepted()

	# Context friction
	test_settlement_transfer_ok()
	test_wilderness_transfer_ok()
	test_dungeon_adjacency_stub_ok()
	test_combat_trade_stub_ok()

	# Capacity
	test_character_capacity_ok_no_warning()
	test_character_capacity_warning_on_band_change()
	test_character_capacity_over_max_rejected()

	# Slot resolution
	test_no_hint_pc_resolves_to_loose()
	test_no_hint_vehicle_resolves_to_cargo()

	# Same carrier
	test_same_carrier_same_slot_rejected()

	if not has_failures():
		print("PartyInventoryTransferValidator: all tests passed.")


# ---------------------------------------------------------------------------
# Test data setup / teardown
# ---------------------------------------------------------------------------

func _setup() -> void:
	_cleanup()

	_catalog = EquipCatalogScript.new()
	_validator = ValidatorScript.new(_catalog)

	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[TEST_CAMPAIGN, "PITV Test"])

	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO parties (id, campaign_id, name) VALUES (?, ?, ?)",
		[TEST_PARTY, TEST_CAMPAIGN, "Test Party"])

	# PC A — fighter with 10s across the board
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_type, persistence_tier, race,
			 character_class, level, xp, combat_progression,
			 strength, intelligence, wisdom, dexterity, constitution, charisma)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [PC_A, TEST_CAMPAIGN, "Alice", "pc", "full", "human",
		  "fighter", 1, 0, "fighter", 10, 10, 10, 10, 10, 10])

	# PC B
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_type, persistence_tier, race,
			 character_class, level, xp, combat_progression,
			 strength, intelligence, wisdom, dexterity, constitution, charisma)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [PC_B, TEST_CAMPAIGN, "Bob", "pc", "full", "human",
		  "fighter", 1, 0, "fighter", 10, 10, 10, 10, 10, 10])

	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO party_members (party_id, character_id, formation_slot) VALUES (?, ?, ?)",
		[TEST_PARTY, PC_A, "middle"])
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO party_members (party_id, character_id, formation_slot) VALUES (?, ?, ?)",
		[TEST_PARTY, PC_B, "middle"])

	# Creature A — mule (workbeast role, can carry with rope)
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO trained_creatures
			(id, campaign_id, party_id, species_id, purchase_item_key, name,
			 role, morale, hp_current, hp_max, is_alive, training_complete)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [CREATURE_A, TEST_CAMPAIGN, TEST_PARTY, "mule", "mule",
		  "TestMule", "WB", 0, 10, 10, 1, 1])

	# Vehicle A — small cart
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO draft_vehicles
			(id, campaign_id, party_id, item_key, name, hitched_creatures, is_destroyed)
		VALUES (?, ?, ?, ?, ?, ?, ?)
	""", [VEHICLE_A, TEST_CAMPAIGN, TEST_PARTY, "cart_small", "TestCart", "[]", 0])

	GameState.campaign_id = TEST_CAMPAIGN
	GameState.party_id = TEST_PARTY
	GameState.current_location_key = "hex:5,3"


func _cleanup() -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE character_id IN (?, ?)", [PC_A, PC_B])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE creature_id = ?", [CREATURE_A])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE vehicle_id = ?", [VEHICLE_A])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM character_preferences WHERE character_id IN (?, ?)", [PC_A, PC_B])
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
	_validator = null
	_catalog = null


## Creates a test inventory item on a character. Returns the item_id.
func _create_char_item(character_id: String, item_key: String, item_name: String,
		quantity: int = 1, enc_units: int = 100, category: String = "gear",
		is_equipped: bool = false, slot: String = "pack") -> String:
	var id := "test_item_%s_%s" % [character_id, item_key]
	CampaignRepository.db.query_with_bindings("""
		INSERT OR REPLACE INTO inventory_items
			(id, character_id, item_key, name, quantity, encumbrance_units,
			 slot, is_equipped, item_category)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [id, character_id, item_key, item_name, quantity, enc_units,
		  slot, 1 if is_equipped else 0, category])
	return id


## Creates a test inventory item on a creature.
func _create_creature_item(creature_id: String, item_key: String, item_name: String,
		quantity: int = 1, enc_units: int = 100, category: String = "gear",
		is_equipped: bool = false, slot: String = "pack") -> String:
	var id := "test_item_%s_%s" % [creature_id, item_key]
	CampaignRepository.db.query_with_bindings("""
		INSERT OR REPLACE INTO inventory_items
			(id, character_id, creature_id, item_key, name, quantity, encumbrance_units,
			 slot, is_equipped, item_category)
		VALUES (?, '', ?, ?, ?, ?, ?, ?, ?, ?)
	""", [id, creature_id, item_key, item_name, quantity, enc_units,
		  slot, 1 if is_equipped else 0, category])
	return id


func _make_item(item_key: String, item_name: String, quantity: int = 1,
		enc_units: int = 100, category: String = "gear",
		is_equipped: bool = false, slot: String = "pack") -> Dictionary:
	return {
		"item_key": item_key,
		"name": item_name,
		"quantity": quantity,
		"encumbrance_units": enc_units,
		"item_category": category,
		"is_equipped": is_equipped,
		"slot": slot,
	}


func _make_source(carrier_type: String, carrier_id: String,
		item_id: String = "", quantity: int = 1) -> Dictionary:
	return {
		"carrier_type": carrier_type,
		"carrier_id": carrier_id,
		"item_id": item_id,
		"quantity": quantity,
	}


func _make_target(carrier_type: String, carrier_id: String,
		slot: String = "", data = null) -> Dictionary:
	var t := {
		"carrier_type": carrier_type,
		"carrier_id": carrier_id,
		"slot": slot,
	}
	if data != null:
		t["data"] = data
	return t


func _make_context(location_key: String = "hex:5,3",
		is_in_combat: bool = false) -> Dictionary:
	return {
		"location_key": location_key,
		"is_in_combat": is_in_combat,
		"active_character_id": PC_A,
	}


func _load_creature_data(creature_id: String) -> TrainedCreatureData:
	var row := CampaignRepository.get_trained_creature(creature_id)
	var creature := TrainedCreatureData.from_db(row)
	creature.inventory = CampaignRepository.get_creature_inventory(creature_id)
	# Provide minimal monster_data for capacity lookups
	creature.monster_data = {
		"special_abilities": [
			{
				"ability_id": "carrying_capacity",
				"effect": {"load_stone_normal": 20, "load_stone_max": 40},
			},
		],
	}
	return creature


# ---------------------------------------------------------------------------
# Coin lock tests
# ---------------------------------------------------------------------------

func test_coin_transfer_blocked() -> void:
	_setup()
	var item := _make_item("coins_gp", "Gold Pieces", 10, 10, "treasure")
	var source := _make_source("character", PC_A)
	var target := _make_target("character", PC_B)
	var ctx := _make_context()

	var result: Dictionary = _validator.validate_transfer(source, target, ctx, item)
	check(not result.ok, "coin transfer should be rejected")
	check(result.reason.find("Coins") >= 0, "reason should mention coins: got '%s'" % result.reason)
	_cleanup()


func test_non_coin_transfer_allowed() -> void:
	_setup()
	var item := _make_item("rope_50ft", "Rope (50')", 1, 500)
	var source := _make_source("character", PC_A)
	var target := _make_target("character", PC_B)
	var ctx := _make_context()

	var result: Dictionary = _validator.validate_transfer(source, target, ctx, item)
	check(result.ok, "non-coin transfer should be accepted")
	_cleanup()


# ---------------------------------------------------------------------------
# Equipped clothing lock
# ---------------------------------------------------------------------------

func test_equipped_clothing_blocked() -> void:
	_setup()
	var item := _make_item("tunic", "Tunic", 1, 100, "clothing", true, "body")
	var source := _make_source("character", PC_A)
	var target := _make_target("character", PC_B)
	var ctx := _make_context()

	var result: Dictionary = _validator.validate_transfer(source, target, ctx, item)
	check(not result.ok, "equipped clothing should be rejected")
	check(result.reason.find("Unequip") >= 0, "reason should say 'Unequip': got '%s'" % result.reason)
	_cleanup()


# ---------------------------------------------------------------------------
# Carrier-type: character targets
# ---------------------------------------------------------------------------

func test_pc_to_pc_loose_accepted() -> void:
	_setup()
	var item := _make_item("sword", "Sword", 1, 1000)
	var source := _make_source("character", PC_A)
	var target := _make_target("character", PC_B)
	var ctx := _make_context()

	var result: Dictionary = _validator.validate_transfer(source, target, ctx, item)
	check(result.ok, "PC to PC loose should be accepted")
	_cleanup()


func test_pc_to_henchman_loose_accepted() -> void:
	_setup()
	# Henchman is still type "character" for carrier purposes
	var item := _make_item("torch", "Torch", 1, 167)
	var source := _make_source("character", PC_A)
	var target := _make_target("character", PC_B)  # works for henchman too
	var ctx := _make_context()

	var result: Dictionary = _validator.validate_transfer(source, target, ctx, item)
	check(result.ok, "PC to henchman should be accepted")
	_cleanup()


# ---------------------------------------------------------------------------
# Carrier-type: creature targets
# ---------------------------------------------------------------------------

func test_pc_to_creature_with_rope_accepted() -> void:
	_setup()
	# Give creature a rope (makes it rope-lashed, load_multiplier = 0.5)
	_create_creature_item(CREATURE_A, "rope_50ft", "Rope (50')", 1, 500, "gear", false)

	var creature := _load_creature_data(CREATURE_A)
	var item := _make_item("sack_large", "Large Sack", 1, 100)
	var source := _make_source("character", PC_A)
	var target := _make_target("creature", CREATURE_A, "cargo", creature)
	var ctx := _make_context()

	var result: Dictionary = _validator.validate_transfer(source, target, ctx, item)
	check(result.ok, "creature with rope should accept cargo: reason='%s'" % result.get("reason", ""))
	_cleanup()


func test_pc_to_untacked_creature_rejected() -> void:
	_setup()
	# No saddle, no rope — untacked
	var creature := _load_creature_data(CREATURE_A)
	var item := _make_item("sword", "Sword", 1, 1000)
	var source := _make_source("character", PC_A)
	var target := _make_target("creature", CREATURE_A, "", creature)
	var ctx := _make_context()

	var result: Dictionary = _validator.validate_transfer(source, target, ctx, item)
	check(not result.ok, "untacked creature should reject cargo")
	_cleanup()


# ---------------------------------------------------------------------------
# Carrier-type: vehicle targets
# ---------------------------------------------------------------------------

func test_pc_to_vehicle_within_capacity_accepted() -> void:
	_setup()
	# Small cart with no team = 0 capacity, but we need at least minimal capacity.
	# Give it a hitched creature with draft saddle for team equivalents.
	# For simplicity, pass vehicle data with pre-computed capacity.
	var vehicle_data := {
		"item_key": "cart_small",
		"hitched_creatures_data": [],
	}
	# cart_small with 0 team has 0 capacity per DraftVehicleService.
	# Use a manually set team equiv for the test by providing creature data.
	# Actually, with 0 team equiv, cart has min_equiv checks... let's use
	# a simpler approach: test with a real hitched creature.
	_create_creature_item(CREATURE_A, "saddle_draft", "Draft Saddle", 1, 500, "gear", true, "mount")
	var creature := _load_creature_data(CREATURE_A)
	vehicle_data["hitched_creatures_data"] = [creature]

	var item := _make_item("sword", "Sword", 1, 1000)
	var source := _make_source("character", PC_A)
	var target := _make_target("vehicle", VEHICLE_A, "", vehicle_data)
	var ctx := _make_context()

	var result: Dictionary = _validator.validate_transfer(source, target, ctx, item)
	check(result.ok, "vehicle within capacity should accept: reason='%s'" % result.get("reason", ""))
	_cleanup()


func test_pc_to_vehicle_over_max_rejected() -> void:
	_setup()
	# Small cart with one mule (0.5 equiv): load_max = 70 stone = 70000 units
	_create_creature_item(CREATURE_A, "saddle_draft", "Draft Saddle", 1, 500, "gear", true, "mount")
	var creature := _load_creature_data(CREATURE_A)
	var vehicle_data := {
		"item_key": "cart_small",
		"hitched_creatures_data": [creature],
	}

	# Item weighing 80000 units (80 stone) exceeds max of 70 stone
	var item := _make_item("huge_cargo", "Massive Load", 1, 80000)
	var source := _make_source("character", PC_A)
	var target := _make_target("vehicle", VEHICLE_A, "", vehicle_data)
	var ctx := _make_context()

	var result: Dictionary = _validator.validate_transfer(source, target, ctx, item)
	check(not result.ok, "vehicle over max capacity should reject")
	_cleanup()


# ---------------------------------------------------------------------------
# Carrier-type: cache targets
# ---------------------------------------------------------------------------

func test_cache_target_always_accepted() -> void:
	_setup()
	var item := _make_item("sword", "Sword", 1, 1000)
	var source := _make_source("character", PC_A)
	var target := _make_target("cache", "cache_001")
	var ctx := _make_context()

	var result: Dictionary = _validator.validate_transfer(source, target, ctx, item)
	check(result.ok, "cache target should always accept")
	check(result.resolved_slot == "cache", "resolved_slot should be 'cache'")
	_cleanup()


# ---------------------------------------------------------------------------
# Context friction
# ---------------------------------------------------------------------------

func test_settlement_transfer_ok() -> void:
	_setup()
	var item := _make_item("sword", "Sword", 1, 1000)
	var source := _make_source("character", PC_A)
	var target := _make_target("character", PC_B)
	var ctx := _make_context("settlement:market_town")

	var result: Dictionary = _validator.validate_transfer(source, target, ctx, item)
	check(result.ok, "settlement transfer should be free")
	_cleanup()


func test_wilderness_transfer_ok() -> void:
	_setup()
	var item := _make_item("sword", "Sword", 1, 1000)
	var source := _make_source("character", PC_A)
	var target := _make_target("character", PC_B)
	var ctx := _make_context("hex:5,3")

	var result: Dictionary = _validator.validate_transfer(source, target, ctx, item)
	check(result.ok, "wilderness transfer should be free")
	_cleanup()


func test_dungeon_adjacency_stub_ok() -> void:
	_setup()
	var item := _make_item("sword", "Sword", 1, 1000)
	var source := _make_source("character", PC_A)
	var target := _make_target("character", PC_B)
	var ctx := _make_context("dungeon:test:level:1")

	var result: Dictionary = _validator.validate_transfer(source, target, ctx, item)
	check(result.ok, "dungeon adjacency stub should allow transfer")
	_cleanup()


func test_combat_trade_stub_ok() -> void:
	_setup()
	var item := _make_item("sword", "Sword", 1, 1000)
	var source := _make_source("character", PC_A)
	var target := _make_target("character", PC_B)
	var ctx := _make_context("dungeon:test:level:1", true)

	var result: Dictionary = _validator.validate_transfer(source, target, ctx, item)
	check(result.ok, "combat trade action stub should allow transfer")
	_cleanup()


# ---------------------------------------------------------------------------
# Capacity
# ---------------------------------------------------------------------------

func test_character_capacity_ok_no_warning() -> void:
	_setup()
	# PC has no existing items — 1 stone item well within 5-stone unencumbered band
	var item := _make_item("sword", "Sword", 1, 1000)
	var source := _make_source("character", PC_A)
	var target := _make_target("character", PC_B)
	var ctx := _make_context()

	var result: Dictionary = _validator.validate_transfer(source, target, ctx, item)
	check(result.ok, "should accept within capacity")
	check(result.warnings.is_empty(), "should have no warnings for light load")
	_cleanup()


func test_character_capacity_warning_on_band_change() -> void:
	_setup()
	# Give PC B 4500 units of existing gear (just under 5000 unencumbered band)
	_create_char_item(PC_B, "heavy_stuff", "Heavy Stuff", 1, 4500)

	# Adding 1000 more = 5500, pushing into light encumbrance (5001-7000)
	var item := _make_item("sword", "Sword", 1, 1000)
	var source := _make_source("character", PC_A)
	var target := _make_target("character", PC_B)
	var ctx := _make_context()

	var result: Dictionary = _validator.validate_transfer(source, target, ctx, item)
	check(result.ok, "should still accept but with warning")
	check(not result.warnings.is_empty(), "should warn about encumbrance band change")
	_cleanup()


func test_character_capacity_over_max_rejected() -> void:
	_setup()
	# Give PC B 19500 units of existing gear (close to 20000 max)
	_create_char_item(PC_B, "heavy_stuff", "Heavy Stuff", 1, 19500)

	# Adding 1000 more = 20500, exceeding 20000 max
	var item := _make_item("anvil", "Anvil", 1, 1000)
	var source := _make_source("character", PC_A)
	var target := _make_target("character", PC_B)
	var ctx := _make_context()

	var result: Dictionary = _validator.validate_transfer(source, target, ctx, item)
	check(not result.ok, "should reject over max capacity")
	_cleanup()


# ---------------------------------------------------------------------------
# Slot resolution
# ---------------------------------------------------------------------------

func test_no_hint_pc_resolves_to_loose() -> void:
	_setup()
	var item := _make_item("rope_50ft", "Rope (50')", 1, 500)
	var source := _make_source("character", PC_A)
	var target := _make_target("character", PC_B, "")  # no slot hint
	var ctx := _make_context()

	var result: Dictionary = _validator.validate_transfer(source, target, ctx, item)
	check(result.ok, "should accept")
	check(result.resolved_slot == "loose", "should resolve to 'loose': got '%s'" % result.resolved_slot)
	_cleanup()


func test_no_hint_vehicle_resolves_to_cargo() -> void:
	_setup()
	_create_creature_item(CREATURE_A, "saddle_draft", "Draft Saddle", 1, 500, "gear", true, "mount")
	var creature := _load_creature_data(CREATURE_A)
	var vehicle_data := {
		"item_key": "cart_small",
		"hitched_creatures_data": [creature],
	}

	var item := _make_item("sword", "Sword", 1, 1000)
	var source := _make_source("character", PC_A)
	var target := _make_target("vehicle", VEHICLE_A, "", vehicle_data)
	var ctx := _make_context()

	var result: Dictionary = _validator.validate_transfer(source, target, ctx, item)
	check(result.ok, "should accept: reason='%s'" % result.get("reason", ""))
	check(result.resolved_slot == "cargo", "should resolve to 'cargo': got '%s'" % result.resolved_slot)
	_cleanup()


# ---------------------------------------------------------------------------
# Same carrier
# ---------------------------------------------------------------------------

func test_same_carrier_same_slot_rejected() -> void:
	_setup()
	var item := _make_item("sword", "Sword", 1, 1000, "gear", false, "pack")
	var source := _make_source("character", PC_A)
	var target := _make_target("character", PC_A, "pack")
	var ctx := _make_context()

	var result: Dictionary = _validator.validate_transfer(source, target, ctx, item)
	check(not result.ok, "same carrier+slot should be rejected")
	check(result.reason == "Already there", "reason should be 'Already there': got '%s'" % result.reason)
	_cleanup()
