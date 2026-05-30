extends "res://tests/test_suite_base.gd"

## Tests for the Decanter of Endless Water wilderness water auto-refill
## (gdd-treasure-item-backing.md §14, engine/subsystems/inventory/
##  decanter_refill_service.gd).
##
## Strategy:
##   - DB-backed: a real campaign / party / character with inventory rows
##     inserted via CampaignRepository.
##   - Call `DecanterRefillService.refill_party_water(...)` directly with the
##     live CampaignRepository autoload + a stub EventBus so we can assert
##     refill semantics in isolation from the noon-tick scheduler.
##   - One coverage row also confirms the Decanter sells through ShopService
##     by value_cp (regression-locks the catalog price).
##
## Scope: tests refill counter arithmetic and the carry-detection (member +
## party pool). The wilderness-noon-tick integration is exercised at runtime;
## here we focus on the service contract.

const _DB_CAMPAIGN := "test_decanter_campaign"
const _DB_PARTY := "test_decanter_party"
const _DB_CHAR := "test_decanter_char"
const _DB_CHAR_B := "test_decanter_char_b"
const _DB_POI := "test_decanter_poi"


# ---------------------------------------------------------------------------
# EventBus stub — captures emitted notification dictionaries for assertion.
# ---------------------------------------------------------------------------

class _StubSignal extends RefCounted:
	var emitted: Array = []
	func emit(payload) -> void:
		emitted.append(payload)


class _StubEventBus extends RefCounted:
	var notification_requested: _StubSignal = null
	func _init() -> void:
		notification_requested = _StubSignal.new()


func run_all_tests() -> void:
	test_no_decanter_no_refill()
	test_decanter_refills_thirsty_party()
	test_per_tick_cap_clamps_at_party_size()
	test_already_full_no_refill()
	test_multiple_decanters_stack()
	test_party_pool_decanter_counts()
	test_summary_records_decanter_count_and_delta()
	test_shop_sells_decanter_by_value_cp()
	if not has_failures():
		print("DecanterOfEndlessWater: all tests passed.")


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

## Baseline: party with NO decanter, thirsty (water_units = 0). Service must
## leave water_units untouched. Regression-locks the "no Decanter → no free
## water" semantic.
func test_no_decanter_no_refill() -> void:
	_setup()
	var party_data := _make_party_data(2)
	party_data.water_units = 0
	var bus := _StubEventBus.new()

	var summary := DecanterRefillService.refill_party_water(
		party_data, CampaignRepository, bus)

	check(int(summary["decanter_count"]) == 0,
		"no decanter present should report 0, got %d" % int(summary["decanter_count"]))
	check(int(summary["refilled"]) == 0,
		"no decanter should refill 0, got %d" % int(summary["refilled"]))
	check(party_data.water_units == 0,
		"no decanter should leave water_units at 0, got %d" % party_data.water_units)
	check(bus.notification_requested.emitted.is_empty(),
		"no refill should emit no toast")

	_teardown()
	print("  no_decanter_no_refill: OK")


## Decanter present + thirsty party (water_units = 0, party_size = 2): single
## decanter adds OUTPUT_PER_TICK_UNITS (= 1) person-day per tick. After two
## ticks the counter reaches party_size = 2 (one day's draw).
func test_decanter_refills_thirsty_party() -> void:
	_setup()
	var party_data := _make_party_data(2)
	party_data.water_units = 0
	_give_decanter_to_char(_DB_CHAR)
	var bus := _StubEventBus.new()

	var s1 := DecanterRefillService.refill_party_water(
		party_data, CampaignRepository, bus)
	check(int(s1["refilled"]) == DecanterRefillService.OUTPUT_PER_TICK_UNITS,
		"tick 1 refills %d, got %d" % [
			DecanterRefillService.OUTPUT_PER_TICK_UNITS, int(s1["refilled"])])
	check(party_data.water_units == DecanterRefillService.OUTPUT_PER_TICK_UNITS,
		"after tick 1 water_units = OUTPUT_PER_TICK_UNITS, got %d"
			% party_data.water_units)

	var s2 := DecanterRefillService.refill_party_water(
		party_data, CampaignRepository, bus)
	check(party_data.water_units == 2,
		"after tick 2 water_units = 2 (capped at party_size), got %d"
			% party_data.water_units)
	check(int(s2["refilled"]) == 1,
		"tick 2 refills 1 (clamped to remaining room), got %d" % int(s2["refilled"]))

	# DB roundtrip: state was persisted.
	var ok_select: bool = CampaignRepository.db.query_with_bindings(
		"SELECT water_units FROM party_state WHERE party_id = ?", [_DB_PARTY])
	check(ok_select,
		"save_party_state should succeed (select on party_state ok)")
	if not CampaignRepository.db.query_result.is_empty():
		var persisted := int(CampaignRepository.db.query_result[0].get("water_units", -1))
		check(persisted == 2,
			"persisted water_units should be 2, got %d" % persisted)

	_teardown()
	print("  decanter_refills_thirsty_party: OK")


## Single tick must never exceed party_size (one day's draw) — mirrors the
## river-hex cap. Even if a future tuning raises OUTPUT_PER_TICK_UNITS above
## party_size, the per-tick cap still clamps. This pin protects that contract.
func test_per_tick_cap_clamps_at_party_size() -> void:
	_setup()
	var party_data := _make_party_data(1)  # solo: cap = 1
	party_data.water_units = 0
	# Insert 5 decanters → raw per-tick output would be 5, but cap clamps to 1.
	for i in range(5):
		_give_decanter_to_char(_DB_CHAR)
	var bus := _StubEventBus.new()

	var s := DecanterRefillService.refill_party_water(
		party_data, CampaignRepository, bus)

	check(int(s["decanter_count"]) == 5,
		"five decanters should count as 5, got %d" % int(s["decanter_count"]))
	check(int(s["refilled"]) == 1,
		"per-tick refill clamped to party_size=1, got %d" % int(s["refilled"]))
	check(party_data.water_units == 1,
		"water_units capped at party_size, got %d" % party_data.water_units)

	_teardown()
	print("  per_tick_cap_clamps_at_party_size: OK")


## Calling refill on a party already at-or-above party_size should yield a
## zero-refill no-op (idempotent / safe to fire repeatedly).
func test_already_full_no_refill() -> void:
	_setup()
	var party_data := _make_party_data(3)
	party_data.water_units = 3
	_give_decanter_to_char(_DB_CHAR)
	var bus := _StubEventBus.new()

	var s := DecanterRefillService.refill_party_water(
		party_data, CampaignRepository, bus)
	check(int(s["refilled"]) == 0,
		"full party refill should be 0, got %d" % int(s["refilled"]))
	check(party_data.water_units == 3,
		"full party water_units unchanged, got %d" % party_data.water_units)
	check(bus.notification_requested.emitted.is_empty(),
		"zero-refill should not toast")

	# Above-cap is also a no-op (defensive — wouldn't normally happen).
	party_data.water_units = 10
	var s2 := DecanterRefillService.refill_party_water(
		party_data, CampaignRepository, bus)
	check(int(s2["refilled"]) == 0,
		"above-cap refill should be 0, got %d" % int(s2["refilled"]))
	check(party_data.water_units == 10,
		"above-cap water_units unchanged, got %d" % party_data.water_units)

	_teardown()
	print("  already_full_no_refill: OK")


## Multiple decanters stack additively per spec. Party of 4, two decanters
## (one each on two members): tick contributes 2 person-days per tick (until
## clamped to party_size).
func test_multiple_decanters_stack() -> void:
	_setup()
	var party_data := _make_party_data(4)
	party_data.water_units = 0
	_give_decanter_to_char(_DB_CHAR)
	_give_decanter_to_char(_DB_CHAR_B)
	var bus := _StubEventBus.new()

	var s := DecanterRefillService.refill_party_water(
		party_data, CampaignRepository, bus)
	check(int(s["decanter_count"]) == 2,
		"two decanters across two members should count as 2, got %d"
			% int(s["decanter_count"]))
	check(int(s["refilled"]) == 2,
		"two-decanter tick refills 2 person-days (below party_size=4 cap), got %d"
			% int(s["refilled"]))
	check(party_data.water_units == 2,
		"water_units after refill = 2, got %d" % party_data.water_units)

	_teardown()
	print("  multiple_decanters_stack: OK")


## A Decanter in the party-shared pool (party_id set, character_id empty)
## should count exactly like a member-held one. Mirrors party_inventory
## semantics: shared loot before someone picks it up still benefits the party.
func test_party_pool_decanter_counts() -> void:
	_setup()
	var party_data := _make_party_data(3)
	party_data.water_units = 0
	# No member-held decanter — only the party pool.
	CampaignRepository.add_party_inventory_item(_DB_PARTY, {
		"item_key": DecanterRefillService.ITEM_KEY,
		"name": "Decanter of Endless Water",
		"quantity": 1,
		"encumbrance_units": 167,
		"item_category": "magic",
		"is_magical": true,
		"value_cp": 15000000,
	})
	var bus := _StubEventBus.new()

	var s := DecanterRefillService.refill_party_water(
		party_data, CampaignRepository, bus)
	check(int(s["decanter_count"]) == 1,
		"party-pool decanter must count as 1, got %d" % int(s["decanter_count"]))
	check(int(s["refilled"]) == 1,
		"party-pool decanter refills 1 per tick, got %d" % int(s["refilled"]))

	_teardown()
	print("  party_pool_decanter_counts: OK")


## Summary contract: returns decanter_count, prior_units, final_units,
## refilled, emitted_notification. Tests pin the shape so downstream code
## (UI, save-game audit, telemetry) can rely on the fields.
func test_summary_records_decanter_count_and_delta() -> void:
	_setup()
	var party_data := _make_party_data(3)
	party_data.water_units = 1
	_give_decanter_to_char(_DB_CHAR)
	var bus := _StubEventBus.new()

	var s := DecanterRefillService.refill_party_water(
		party_data, CampaignRepository, bus)
	check(s.has("decanter_count") and int(s["decanter_count"]) == 1,
		"summary must record decanter_count, got %s" % str(s.get("decanter_count")))
	check(s.has("prior_units") and int(s["prior_units"]) == 1,
		"summary must record prior_units = 1, got %s" % str(s.get("prior_units")))
	check(s.has("final_units") and int(s["final_units"]) == 2,
		"summary must record final_units = 2, got %s" % str(s.get("final_units")))
	check(s.has("refilled") and int(s["refilled"]) == 1,
		"summary must record refilled = 1, got %s" % str(s.get("refilled")))
	check(s.has("emitted_notification") and bool(s["emitted_notification"]),
		"summary must record emitted_notification = true on refill")
	check(bus.notification_requested.emitted.size() == 1,
		"exactly one toast emitted on a positive refill")
	var toast: Dictionary = bus.notification_requested.emitted[0]
	check(str(toast.get("category", "")) == "exploration",
		"toast category should be 'exploration', got '%s'" % str(toast.get("category", "")))
	check(str(toast.get("title", "")).contains("Decanter"),
		"toast title should mention Decanter, got '%s'" % str(toast.get("title", "")))

	_teardown()
	print("  summary_records_decanter_count_and_delta: OK")


## The Decanter must sell through ShopService at its catalog value_cp. Pins
## that the magic-item triage's KEEP+BUILD disposition (positive value_gp,
## no cut_for_v1 / defer_reason) survives.
func test_shop_sells_decanter_by_value_cp() -> void:
	_setup()
	var item_id: String = CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR,
		"item_key": DecanterRefillService.ITEM_KEY,
		"name": "Decanter of Endless Water",
		"quantity": 1,
		"encumbrance_units": 167,
		"item_category": "magic",
		"is_magical": true,
		"value_cp": 15000000,  # 150,000 gp × 100 cp/gp
	})

	var service := ShopService.new()
	var sellable_ids := {}
	for s in service.get_sellable_items(_DB_CHAR):
		sellable_ids[str(s.get("item_id", ""))] = true
	check(sellable_ids.has(item_id),
		"priced Decanter is sellable-listed")

	var wealth_before: int = CampaignRepository.get_character_wealth_cp(_DB_CHAR)
	var ok: Dictionary = service.sell_item(_DB_CHAR, item_id, _DB_POI, _DB_CAMPAIGN)
	check(ok["success"],
		"Decanter sells through ShopService: %s" % str(ok.get("message", "")))
	var wealth_after: int = CampaignRepository.get_character_wealth_cp(_DB_CHAR)
	check(wealth_after == wealth_before + 15000000,
		"selling a 150000gp Decanter adds 15000000cp, was %d now %d"
			% [wealth_before, wealth_after])

	_teardown()
	print("  shop_sells_decanter_by_value_cp: OK")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Builds an in-memory PartyData with [param member_count] members. Members
## are also inserted in the characters table so per-character inventory rows
## (FK to characters(id)) accept the insert.
func _make_party_data(member_count: int) -> PartyData:
	var pd := PartyData.new()
	pd.id = _DB_PARTY
	pd.character_data = []
	for i in range(member_count):
		var cd := CharacterData.new()
		# Both _DB_CHAR and _DB_CHAR_B already exist in characters; further
		# slots reuse the secondary char (the count needs to match
		# party_size for the cap math, not the DB row count).
		if i == 0:
			cd.id = _DB_CHAR
			cd.name = "Member A"
		elif i == 1:
			cd.id = _DB_CHAR_B
			cd.name = "Member B"
		else:
			cd.id = "%s_extra_%d" % [_DB_CHAR, i]
			cd.name = "Member %d" % (i + 1)
		cd.character_class = "fighter"
		cd.combat_progression = "fighter"
		cd.level = 1
		cd.alignment = "neutral"
		cd.hp_max = 8
		cd.hp_current = 8
		pd.character_data.append(cd)
	return pd


## Inserts a Decanter row into [param character_id]'s inventory.
func _give_decanter_to_char(character_id: String) -> String:
	return CampaignRepository.add_inventory_item({
		"character_id": character_id,
		"item_key": DecanterRefillService.ITEM_KEY,
		"name": "Decanter of Endless Water",
		"quantity": 1,
		"encumbrance_units": 167,
		"item_category": "magic",
		"is_magical": true,
		"value_cp": 15000000,
	})


func _setup() -> void:
	# Campaign + party rows are needed because save_party_state has a FK on
	# parties(id), and inventory rows have an FK on characters(id).
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name, world_name) VALUES (?, ?, ?)",
		[_DB_CAMPAIGN, "Decanter Test", "Test World"])
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO parties
			(id, campaign_id, name, current_map_id, current_hex_q, current_hex_r,
			 current_location_type)
		VALUES (?, ?, ?, ?, ?, ?, ?)
	""", [_DB_PARTY, _DB_CAMPAIGN, "Decanter Party", "", 0, 0, "wilderness"])
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_class, level, xp, hp_max, hp_current)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)
	""", [_DB_CHAR, _DB_CAMPAIGN, "Member A", "fighter", 1, 0, 8, 8])
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_class, level, xp, hp_max, hp_current)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)
	""", [_DB_CHAR_B, _DB_CAMPAIGN, "Member B", "fighter", 1, 0, 8, 8])
	GameState.campaign_id = _DB_CAMPAIGN
	# Clear any prior inventory / state for these IDs.
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE character_id IN (?, ?) OR party_id = ?",
		[_DB_CHAR, _DB_CHAR_B, _DB_PARTY])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM party_state WHERE party_id = ?", [_DB_PARTY])


func _teardown() -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE character_id IN (?, ?) OR party_id = ?",
		[_DB_CHAR, _DB_CHAR_B, _DB_PARTY])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM party_state WHERE party_id = ?", [_DB_PARTY])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM characters WHERE id IN (?, ?)", [_DB_CHAR, _DB_CHAR_B])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM parties WHERE id = ?", [_DB_PARTY])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [_DB_CAMPAIGN])
