extends "res://tests/test_suite_base.gd"

## Tests for VehicleAbandonmentService (Bug 3 — unhitched-vehicle travel).
##
## Covers: detection of immobile vehicles, the "leave behind" park-as-cache flow
## (cargo + cart materialized into a conspicuous wilderness cache, vehicle
## removed), and the AbandonVehiclePrompt body copy.
##
## Seeds its own campaign/party and cleans up after itself.

const TEST_CAMPAIGN := "test_vas_campaign"
const TEST_PARTY := "test_vas_party"


func run_all_tests() -> void:
	test_detects_unhitched_vehicle()
	test_ignores_mobile_vehicle()
	test_abandon_parks_cargo_and_cart_into_cache()
	test_abandon_removes_vehicle_and_sets_raid_penalty()
	test_prompt_body_text_lists_vehicle()
	_cleanup()
	if not has_failures():
		print("VehicleAbandonmentService: all tests passed.")


# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

func _setup() -> void:
	_cleanup()
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[TEST_CAMPAIGN, "VAS Test"])
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO parties (id, campaign_id, name) VALUES (?, ?, ?)",
		[TEST_PARTY, TEST_CAMPAIGN, "Test Party"])
	GameState.campaign_id = TEST_CAMPAIGN
	GameState.party_id = TEST_PARTY


func _cleanup() -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE location_cache_id IN (SELECT id FROM location_caches WHERE campaign_id = ?)",
		[TEST_CAMPAIGN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE vehicle_id IN (SELECT id FROM draft_vehicles WHERE campaign_id = ?)",
		[TEST_CAMPAIGN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM location_caches WHERE campaign_id = ?", [TEST_CAMPAIGN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM draft_vehicles WHERE campaign_id = ?", [TEST_CAMPAIGN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM trained_creatures WHERE campaign_id = ?", [TEST_CAMPAIGN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM parties WHERE campaign_id = ?", [TEST_CAMPAIGN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [TEST_CAMPAIGN])
	GameState.campaign_id = ""
	GameState.party_id = ""


func _make_vehicle(item_key: String, hitched_json: String) -> String:
	return CampaignRepository.create_draft_vehicle({
		"campaign_id": TEST_CAMPAIGN,
		"party_id": TEST_PARTY,
		"item_key": item_key,
		"name": item_key.capitalize(),
		"hitched_creatures": hitched_json,
	})


func _make_cargo(vehicle_id: String, item_key: String) -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO inventory_items
			(id, character_id, vehicle_id, item_key, name, quantity, encumbrance_units,
			 slot, is_equipped, item_category)
		VALUES (?, '', ?, ?, ?, 1, 100, 'pack', 0, 'gear')
	""", [id, vehicle_id, item_key, item_key.capitalize()])
	return id


func _make_creature(species_id: String) -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO trained_creatures (id, campaign_id, party_id, species_id) VALUES (?, ?, ?, ?)",
		[id, TEST_CAMPAIGN, TEST_PARTY, species_id])
	return id


# ---------------------------------------------------------------------------
# Detection
# ---------------------------------------------------------------------------

func test_detects_unhitched_vehicle() -> void:
	_setup()
	var vid := _make_vehicle("cart_small", "[]")
	var unhitched := VehicleAbandonmentService.unhitched_vehicles_for_party(TEST_PARTY)
	check(unhitched.size() == 1, "one immobile vehicle expected; got %d" % unhitched.size())
	if unhitched.size() == 1:
		check(str(unhitched[0].get("id", "")) == vid, "detected vehicle id should match")
	_cleanup()


func test_ignores_mobile_vehicle() -> void:
	_setup()
	# cart_small needs >= 0.5 team equiv; an ox (1.0) makes it mobile.
	var ox := _make_creature("ox")
	_make_vehicle("cart_small", JSON.stringify([ox]))
	var unhitched := VehicleAbandonmentService.unhitched_vehicles_for_party(TEST_PARTY)
	check(unhitched.is_empty(), "a hitched, mobile vehicle should not be flagged; got %d" % unhitched.size())
	_cleanup()


# ---------------------------------------------------------------------------
# Abandon → park as cache
# ---------------------------------------------------------------------------

func test_abandon_parks_cargo_and_cart_into_cache() -> void:
	_setup()
	var vid := _make_vehicle("cart_large", "[]")
	_make_cargo(vid, "iron_ingot")
	_make_cargo(vid, "rope")

	var cache_id := VehicleAbandonmentService.abandon_to_hex(vid, Vector2i(5, 5))
	check(not cache_id.is_empty(), "abandon should return a cache id")

	var cache := CampaignRepository.get_location_cache(cache_id)
	check(cache.get("location_key", "") == "hex:5,5", "cache should be at the party's hex")

	var items := CampaignRepository.list_items_in_cache(cache_id)
	# 2 cargo items + 1 materialized cart item.
	check(items.size() == 3, "cache should hold 2 cargo + 1 cart item; got %d" % items.size())
	var has_cart := false
	for it in items:
		if str(it.get("item_key", "")) == "cart_large":
			has_cart = true
	check(has_cart, "the cart itself should be recoverable in the cache")
	_cleanup()


func test_abandon_removes_vehicle_and_sets_raid_penalty() -> void:
	_setup()
	var vid := _make_vehicle("cart_small", "[]")
	var cache_id := VehicleAbandonmentService.abandon_to_hex(vid, Vector2i(2, 3))

	check(CampaignRepository.get_draft_vehicle(vid).is_empty(),
		"the draft_vehicle should be removed after abandoning")

	var cache := CampaignRepository.get_location_cache(cache_id)
	check(int(cache.get("raid_monthly_modifier", 0)) == VehicleAbandonmentService.NOT_HIDDEN_RAID_PENALTY,
		"an abandoned cart cache should carry the heavy not-hidden raid penalty")
	check(cache.get("cache_variant", "") == "hidden_wilderness",
		"reuses the persistent wilderness-cache variant")
	_cleanup()


# ---------------------------------------------------------------------------
# Prompt copy (pure/static)
# ---------------------------------------------------------------------------

func test_prompt_body_text_lists_vehicle() -> void:
	var text := AbandonVehiclePrompt.body_text(["Ox Cart"])
	check(text.contains("Ox Cart"), "body text should name the vehicle")
	check(text.to_lower().contains("raid"), "body text should warn about raid risk")
