extends "res://tests/test_suite_base.gd"

## Unit tests for BagOfDevouringService (RAW per Jedidiah 2026-05-31).
##
## Tests cover:
##   - Timer activation on first item into empty bag
##   - Timer NOT reset by additional items mid-cycle
##   - Timer NOT reset by item removal mid-cycle
##   - Timer reset when bag empties (devour OR last item removed)
##   - try_devour_if_expired devours contents + resets timer
##   - try_devour_if_expired no-op before expiration
##   - find_expired_bags scopes by campaign + filters by expiration
##   - Catalog shape: both bags have container_behavior + is_extradimensional
##   - DiceSystem.roll_digital integration via GameState.dice_overrides
##   - Container polish (2026-05-31): capacity refusal notifications +
##     EquipmentCatalog fallback for mundane container capacity.

const _DB_CAMPAIGN := "test_bod_campaign"
const _DB_CHAR := "test_bod_char"


func run_all_tests() -> void:
	test_catalog_shape_for_both_bags()
	test_start_timer_on_first_item_into_empty_bag()
	test_dice_override_forces_specific_timer_offset()
	test_additional_items_do_not_reset_active_timer()
	test_removal_mid_cycle_does_not_reset_timer()
	test_try_devour_before_expiration_is_noop()
	test_try_devour_after_expiration_deletes_contents_and_resets()
	test_reset_timer_when_bag_goes_empty_via_removal()
	test_find_expired_bags_filters_correctly()
	test_non_bag_of_devouring_items_unaffected_by_helpers()
	# Container follow-ups (2026-05-31): capacity + materializer + transfer hook.
	test_treasure_instantiator_stamps_container_behavior_on_bags()
	test_capacity_enforcement_refuses_overflow()
	test_capacity_zero_means_unlimited()
	test_transfer_into_empty_bag_of_devouring_activates_timer()
	test_transfer_into_non_devouring_bag_does_not_set_timer()
	# Container polish (2026-05-31): notifications + catalog fallback.
	test_capacity_refusal_emits_won_t_fit_notification()
	test_mundane_container_capacity_via_equipment_catalog()
	if not has_failures():
		print("BagOfDevouringService: all tests passed.")


# ---------------------------------------------------------------------------
# Catalog shape
# ---------------------------------------------------------------------------

func test_catalog_shape_for_both_bags() -> void:
	# Verify the extractor stamped container_behavior + the RAW-correct
	# encumbrance_units (6000 = 6 stone fixed) on both bags.
	var catalog := MagicItemCatalog.new()

	var holding: Dictionary = catalog.get_item("bag_of_holding")
	check(not holding.is_empty(), "bag_of_holding must exist in catalog")
	check(int(holding.get("encumbrance_units", 0)) == 6000,
		"Bag of Holding own weight = 6 stone (6000 units), got %d" %
			int(holding.get("encumbrance_units", 0)))
	var hb: Dictionary = holding.get("container_behavior", {})
	check(bool(hb.get("is_extradimensional", false)),
		"Bag of Holding is_extradimensional must be true")
	check(int(hb.get("capacity_units", 0)) == 100_000,
		"Bag of Holding capacity = 100 stone (100,000 units), got %d" %
			int(hb.get("capacity_units", 0)))

	var devour: Dictionary = catalog.get_item("bag_of_devouring")
	check(not devour.is_empty(), "bag_of_devouring must exist in catalog")
	check(int(devour.get("encumbrance_units", 0)) == 6000,
		"Bag of Devouring own weight = 6 stone, got %d" %
			int(devour.get("encumbrance_units", 0)))
	var db_: Dictionary = devour.get("container_behavior", {})
	check(bool(db_.get("is_extradimensional", false)),
		"Bag of Devouring is_extradimensional must be true (indistinguishable from BoH)")
	check(bool(db_.get("is_devouring", false)),
		"Bag of Devouring carries is_devouring flag")


# ---------------------------------------------------------------------------
# Timer activation
# ---------------------------------------------------------------------------

func test_start_timer_on_first_item_into_empty_bag() -> void:
	_setup()
	# Create an empty Bag of Devouring on the character.
	var bag_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR,
		"item_key": "bag_of_devouring",
		"name": "Bag of Devouring",
		"quantity": 1,
		"encumbrance_units": 6000,
		"item_category": "container",
		"is_magical": true,
		"is_extradimensional": true,
	})
	var bag_pre: Dictionary = CampaignRepository.get_inventory_item_by_id(bag_id)
	check(int(bag_pre.get("devouring_at_turn", 0)) == -1,
		"freshly-created bag starts with devouring_at_turn = -1, got %d" %
			int(bag_pre.get("devouring_at_turn", 0)))

	# Place an item in the empty bag and trigger the timer.
	var current_turn := 1000
	var started: bool = BagOfDevouringService.start_timer_on_first_item(
		bag_id, current_turn)
	check(started, "first item into empty bag should start the timer")

	var bag_post: Dictionary = CampaignRepository.get_inventory_item_by_id(bag_id)
	var fires_at: int = int(bag_post.get("devouring_at_turn", -1))
	check(fires_at >= current_turn + 7 and fires_at <= current_turn + 10,
		"timer should fire 7-10 turns out (6+1d4), got fires_at=%d, current=%d" %
			[fires_at, current_turn])

	_teardown()


func test_dice_override_forces_specific_timer_offset() -> void:
	# DiceSystem.roll_digital integration: tests can force a deterministic
	# timer value by queuing GameState.dice_overrides[DEVOURING_TIMER_ROLL_TYPE].
	# The override value is the final modified_total (raw 1d4 + 6 modifier),
	# so an override of 8 means "fires 8 turns after the placement".
	_setup()
	var bag_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "bag_of_devouring",
		"name": "Bag of Devouring", "is_extradimensional": true,
	})
	# Force the timer roll to land on exactly 9 turns out.
	GameState.dice_overrides[BagOfDevouringService.DEVOURING_TIMER_ROLL_TYPE] = 9
	var started: bool = BagOfDevouringService.start_timer_on_first_item(bag_id, 500)
	check(started, "override-driven start should succeed")
	var bag_post: Dictionary = CampaignRepository.get_inventory_item_by_id(bag_id)
	check(int(bag_post.get("devouring_at_turn", -1)) == 509,
		"forced override 9 + current_turn 500 = 509; got %d" %
			int(bag_post.get("devouring_at_turn", -1)))
	# Confirm override was consumed (subsequent rolls would re-randomize).
	check(not GameState.dice_overrides.has(BagOfDevouringService.DEVOURING_TIMER_ROLL_TYPE),
		"override should be consumed after the roll")
	_teardown()


func test_additional_items_do_not_reset_active_timer() -> void:
	_setup()
	var bag_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "bag_of_devouring",
		"name": "Bag of Devouring", "is_extradimensional": true,
	})

	# Start the timer manually (simulating first-item placement).
	BagOfDevouringService.start_timer_on_first_item(bag_id, 100)
	var initial_fires_at: int = int(
		CampaignRepository.get_inventory_item_by_id(bag_id).get("devouring_at_turn", -1))

	# Drop an item into the now non-empty bag, simulating a second placement.
	# The service should NOT reset the timer (active timer is left alone).
	# We test this by manually creating an item in the bag, then calling
	# start_timer_on_first_item again (which should be a no-op).
	CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "dagger",
		"name": "Dagger", "container_id": bag_id, "encumbrance_units": 1000,
	})
	# Attempt to "restart" the timer with a different turn.
	var started_again: bool = BagOfDevouringService.start_timer_on_first_item(
		bag_id, 200)
	check(not started_again,
		"start_timer_on_first_item should be a no-op when bag has active timer")
	var still_fires_at: int = int(
		CampaignRepository.get_inventory_item_by_id(bag_id).get("devouring_at_turn", -1))
	check(still_fires_at == initial_fires_at,
		"timer must not be reset by additional placements; was %d, now %d" %
			[initial_fires_at, still_fires_at])

	_teardown()


func test_removal_mid_cycle_does_not_reset_timer() -> void:
	_setup()
	var bag_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "bag_of_devouring",
		"name": "Bag of Devouring", "is_extradimensional": true,
	})
	BagOfDevouringService.start_timer_on_first_item(bag_id, 50)
	var fires_at: int = int(
		CampaignRepository.get_inventory_item_by_id(bag_id).get("devouring_at_turn", -1))

	# Add two items to the bag.
	var item1 := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "dagger", "name": "Dagger 1",
		"container_id": bag_id, "encumbrance_units": 1000,
	})
	var item2 := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "dagger", "name": "Dagger 2",
		"container_id": bag_id, "encumbrance_units": 1000,
	})

	# Remove ONE item (bag still has item2 inside). Timer should not reset.
	CampaignRepository.remove_inventory_item(item1)
	BagOfDevouringService.reset_timer_on_empty(bag_id)  # idempotent no-op since bag not empty
	var fires_at_post: int = int(
		CampaignRepository.get_inventory_item_by_id(bag_id).get("devouring_at_turn", -1))
	check(fires_at_post == fires_at,
		"removing one item from a non-empty bag must NOT reset the timer; was %d, now %d" %
			[fires_at, fires_at_post])

	_teardown()


# ---------------------------------------------------------------------------
# Devouring
# ---------------------------------------------------------------------------

func test_try_devour_before_expiration_is_noop() -> void:
	_setup()
	var bag_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "bag_of_devouring",
		"name": "Bag of Devouring", "is_extradimensional": true,
	})
	BagOfDevouringService.start_timer_on_first_item(bag_id, 100)
	var item_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "dagger", "name": "Dagger",
		"container_id": bag_id,
	})

	# Try to devour BEFORE the timer expires (current_turn = 100, timer ~107-110).
	var devoured: bool = BagOfDevouringService.try_devour_if_expired(bag_id, 105)
	check(not devoured, "try_devour should be no-op when timer not expired")

	# Item must still exist.
	var item_post: Dictionary = CampaignRepository.get_inventory_item_by_id(item_id)
	check(not item_post.is_empty(), "item should still exist before timer expires")

	_teardown()


func test_try_devour_after_expiration_deletes_contents_and_resets() -> void:
	_setup()
	var bag_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "bag_of_devouring",
		"name": "Bag of Devouring", "is_extradimensional": true,
	})
	BagOfDevouringService.start_timer_on_first_item(bag_id, 50)
	var fires_at: int = int(
		CampaignRepository.get_inventory_item_by_id(bag_id).get("devouring_at_turn", -1))

	# Add multiple items to the bag.
	var i1 := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "dagger", "name": "D1",
		"container_id": bag_id,
	})
	var i2 := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "dagger", "name": "D2",
		"container_id": bag_id,
	})

	# Advance to expiration and devour.
	var devoured: bool = BagOfDevouringService.try_devour_if_expired(bag_id, fires_at)
	check(devoured, "try_devour at exact expiration turn should fire")

	# All items inside should be gone.
	check(CampaignRepository.get_inventory_item_by_id(i1).is_empty(),
		"D1 should be devoured (deleted from inventory_items)")
	check(CampaignRepository.get_inventory_item_by_id(i2).is_empty(),
		"D2 should be devoured (deleted from inventory_items)")

	# The bag itself remains (it's the container; only contents go).
	var bag_after: Dictionary = CampaignRepository.get_inventory_item_by_id(bag_id)
	check(not bag_after.is_empty(),
		"the bag itself must survive — only contents are devoured")
	# Timer reset to -1 after devour.
	check(int(bag_after.get("devouring_at_turn", 0)) == -1,
		"timer must reset to -1 after devouring, got %d" %
			int(bag_after.get("devouring_at_turn", 0)))

	# Second try_devour is a no-op.
	var devoured_again: bool = BagOfDevouringService.try_devour_if_expired(
		bag_id, fires_at + 5)
	check(not devoured_again,
		"try_devour with reset timer should be no-op")

	_teardown()


func test_reset_timer_when_bag_goes_empty_via_removal() -> void:
	_setup()
	var bag_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "bag_of_devouring",
		"name": "Bag of Devouring", "is_extradimensional": true,
	})
	BagOfDevouringService.start_timer_on_first_item(bag_id, 0)
	var item := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "dagger", "name": "Lone Dagger",
		"container_id": bag_id,
	})

	# Remove the only item from the bag. Bag is now empty.
	CampaignRepository.remove_inventory_item(item)
	BagOfDevouringService.reset_timer_on_empty(bag_id)

	var bag_after: Dictionary = CampaignRepository.get_inventory_item_by_id(bag_id)
	check(int(bag_after.get("devouring_at_turn", 0)) == -1,
		"timer should reset to -1 when bag goes empty via removal, got %d" %
			int(bag_after.get("devouring_at_turn", 0)))

	_teardown()


# ---------------------------------------------------------------------------
# find_expired_bags
# ---------------------------------------------------------------------------

func test_find_expired_bags_filters_correctly() -> void:
	_setup()
	# Two bags on the character.
	var bag1 := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "bag_of_devouring",
		"name": "BoD 1", "is_extradimensional": true,
	})
	var bag2 := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "bag_of_devouring",
		"name": "BoD 2", "is_extradimensional": true,
	})
	BagOfDevouringService.start_timer_on_first_item(bag1, 100)  # fires 107-110
	BagOfDevouringService.start_timer_on_first_item(bag2, 200)  # fires 207-210

	# At turn 105: neither has expired.
	var expired_early: Array = BagOfDevouringService.find_expired_bags(_DB_CAMPAIGN, 105)
	check(expired_early.is_empty(),
		"no bags should be expired at turn 105, got %s" % str(expired_early))

	# At turn 115: bag1 expired (fires 107-110); bag2 not yet (fires 207-210).
	var expired_mid: Array = BagOfDevouringService.find_expired_bags(_DB_CAMPAIGN, 115)
	check(bag1 in expired_mid,
		"bag1 should be in expired list at turn 115, got %s" % str(expired_mid))
	check(not (bag2 in expired_mid),
		"bag2 should NOT be in expired list at turn 115")

	# At turn 250: both expired.
	var expired_late: Array = BagOfDevouringService.find_expired_bags(_DB_CAMPAIGN, 250)
	check(bag1 in expired_late and bag2 in expired_late,
		"both bags should be in expired list at turn 250")

	_teardown()


# ---------------------------------------------------------------------------
# Guards
# ---------------------------------------------------------------------------

func test_non_bag_of_devouring_items_unaffected_by_helpers() -> void:
	_setup()
	# Insert a Bag of Holding (not Devouring). is_bag_of_devouring must
	# return false; helpers must no-op.
	var boh := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "bag_of_holding",
		"name": "Bag of Holding", "is_extradimensional": true,
	})
	check(not BagOfDevouringService.is_bag_of_devouring(
		CampaignRepository.get_inventory_item_by_id(boh)),
		"Bag of Holding must NOT be identified as Bag of Devouring")
	# Attempting to start the timer must be a no-op.
	check(not BagOfDevouringService.start_timer_on_first_item(boh, 100),
		"start_timer_on_first_item must no-op for non-devouring bag")
	# try_devour must be no-op.
	check(not BagOfDevouringService.try_devour_if_expired(boh, 999),
		"try_devour_if_expired must no-op for non-devouring bag")
	# A regular dagger gets the same treatment.
	var dagger := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "dagger", "name": "Dagger",
	})
	check(not BagOfDevouringService.is_bag_of_devouring(
		CampaignRepository.get_inventory_item_by_id(dagger)),
		"dagger must NOT be identified as Bag of Devouring")
	_teardown()


# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

func _setup() -> void:
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name, world_name) VALUES (?, ?, ?)",
		[_DB_CAMPAIGN, "BoD Test", "Test World"])
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_class, level, xp, hp_max, hp_current)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)
	""", [_DB_CHAR, _DB_CAMPAIGN, "BoD Wielder", "fighter", 1, 0, 8, 8])
	GameState.campaign_id = _DB_CAMPAIGN
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE character_id = ?", [_DB_CHAR])
	# Defensive: clear any leftover dice override so tests don't poison
	# each other when an earlier failure skipped consumption.
	GameState.dice_overrides.erase(BagOfDevouringService.DEVOURING_TIMER_ROLL_TYPE)


func _teardown() -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE character_id = ?", [_DB_CHAR])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM characters WHERE id = ?", [_DB_CHAR])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [_DB_CAMPAIGN])
	GameState.dice_overrides.erase(BagOfDevouringService.DEVOURING_TIMER_ROLL_TYPE)


# ---------------------------------------------------------------------------
# Container follow-ups (2026-05-31): capacity enforcement + materializer
# wiring + bag-of-devouring transfer hook through update_inventory_item_equip_state.
# ---------------------------------------------------------------------------

func test_treasure_instantiator_stamps_container_behavior_on_bags() -> void:
	# When TreasureInstantiator resolves a magic item from a hoard and the
	# catalog entry carries container_behavior, the materialized inventory
	# row dict should override item_category to "container" + propagate
	# is_extradimensional + capacity_units. Test by building a hoard with
	# magic_items pointing at the misc_magic category, sweeping seeds until
	# we land on a bag.
	var catalog := MagicItemCatalog.new()
	var hoard := TreasureHoardData.new()
	hoard.magic_items = [{"category": "misc_magic", "notes": "Test"}]
	var found_bag := false
	for seed_val in range(1, 500):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_val
		var plan := TreasureInstantiator.hoard_to_loot(hoard, rng, catalog)
		for item: Dictionary in plan["items"]:
			var key: String = str(item.get("item_key", ""))
			if key == "bag_of_holding" or key == "bag_of_devouring":
				found_bag = true
				check(str(item.get("item_category", "")) == "container",
					"materialized %s should have item_category 'container', got '%s'" %
						[key, str(item.get("item_category", ""))])
				check(bool(item.get("is_extradimensional", false)) == true,
					"materialized %s should have is_extradimensional=true" % key)
				check(int(item.get("capacity_units", 0)) == 100_000,
					"materialized %s should have capacity_units 100000, got %d" %
						[key, int(item.get("capacity_units", 0))])
				check(int(item.get("encumbrance_units", 0)) == 6000,
					"materialized %s should have own weight 6000 (6 stone), got %d" %
						[key, int(item.get("encumbrance_units", 0))])
				break
		if found_bag:
			break
	check(found_bag,
		"across 500 seeds a misc_magic-token hoard should land on bag_of_holding " +
		"or bag_of_devouring at least once")


func test_capacity_enforcement_refuses_overflow() -> void:
	_setup()
	# Container with capacity 1000 units (1 stone).
	var small_bag := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "small_pouch",
		"name": "Small Pouch", "item_category": "container",
		"encumbrance_units": 100, "capacity_units": 1000,
	})
	# Place a 500-unit item inside (fits — current 0, after 500, cap 1000).
	var first_item := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "first", "name": "First",
		"encumbrance_units": 500,
	})
	var first_ok := CampaignRepository.update_inventory_item_equip_state(
		first_item, false, "pack", small_bag)
	check(first_ok, "500-unit item should fit in 1000-unit-cap bag")
	# Try to place another 600-unit item (would total 1100 > cap 1000 — refuse).
	var overflow := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "overflow", "name": "Overflow",
		"encumbrance_units": 600,
	})
	var overflow_ok := CampaignRepository.update_inventory_item_equip_state(
		overflow, false, "pack", small_bag)
	check(not overflow_ok,
		"500+600=1100 should refuse to fit in 1000-unit-cap bag")
	# Confirm the second item is NOT in the bag (still has empty container_id).
	var overflow_after: Dictionary = CampaignRepository.get_inventory_item_by_id(overflow)
	check(str(overflow_after.get("container_id", "")) == "",
		"refused item should remain outside the bag, got container_id='%s'" %
			str(overflow_after.get("container_id", "")))
	_teardown()


func test_capacity_zero_means_unlimited() -> void:
	_setup()
	# Container with no row-level capacity AND no EquipmentCatalog entry —
	# unknown item_key falls through both lookups to "unlimited".
	var bag := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "improvised_sling_bag",
		"name": "Improvised Sling Bag", "item_category": "container",
		"encumbrance_units": 167, "capacity_units": 0,
	})
	# Fit an absurdly large item — capacity check should short-circuit true.
	var huge := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "huge", "name": "Huge",
		"encumbrance_units": 50000,  # 50 stone
	})
	var ok := CampaignRepository.update_inventory_item_equip_state(
		huge, false, "pack", bag)
	check(ok, "capacity_units=0 with no catalog entry should allow any size (unlimited)")
	_teardown()


func test_transfer_into_empty_bag_of_devouring_activates_timer() -> void:
	_setup()
	# Set Timekeeping to a known turn for deterministic-ish assertion.
	# (We can't seed the timer's 1d4 roll without injecting RNG, so we
	# accept the range 7-10 turns out from current.)
	var current_turn := Timekeeping.get_total_turns()
	# Create a Bag of Devouring (correctly identified by item_key).
	var bag := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "bag_of_devouring",
		"name": "Bag of Devouring", "is_extradimensional": true,
		"capacity_units": 100_000,
	})
	var pre: Dictionary = CampaignRepository.get_inventory_item_by_id(bag)
	check(int(pre.get("devouring_at_turn", 0)) == -1,
		"bag starts with no active timer")

	# Place an item into the empty bag via the standard transfer path.
	var trinket := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "trinket", "name": "Trinket",
		"encumbrance_units": 100,
	})
	var moved := CampaignRepository.update_inventory_item_equip_state(
		trinket, false, "pack", bag)
	check(moved, "transfer into Bag of Devouring should succeed")

	# Timer should now be active (fires_at = current_turn + 7-10).
	var post: Dictionary = CampaignRepository.get_inventory_item_by_id(bag)
	var fires_at: int = int(post.get("devouring_at_turn", -1))
	check(fires_at >= current_turn + 7 and fires_at <= current_turn + 10,
		"timer fires 7-10 turns after transfer; current=%d, fires_at=%d" %
			[current_turn, fires_at])
	_teardown()


func test_transfer_into_non_devouring_bag_does_not_set_timer() -> void:
	_setup()
	# Regression: transferring into a non-devouring container must NOT
	# trigger the timer. The hook is gated on
	# BagOfDevouringService.is_bag_of_devouring() — checks item_key.
	var holding := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "bag_of_holding",
		"name": "Bag of Holding", "is_extradimensional": true,
		"capacity_units": 100_000,
	})
	var item := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "trinket", "name": "Trinket",
		"encumbrance_units": 100,
	})
	var ok := CampaignRepository.update_inventory_item_equip_state(
		item, false, "pack", holding)
	check(ok, "transfer into Bag of Holding should succeed")
	# Bag of Holding has no timer — devouring_at_turn must stay -1.
	var post: Dictionary = CampaignRepository.get_inventory_item_by_id(holding)
	check(int(post.get("devouring_at_turn", 0)) == -1,
		"Bag of Holding must NOT have an active timer after transfer, got %d" %
			int(post.get("devouring_at_turn", 0)))
	_teardown()


# ---------------------------------------------------------------------------
# Container polish (2026-05-31): UI affordance + per-item mundane container
# capacities via EquipmentCatalog fallback.
# ---------------------------------------------------------------------------

func test_capacity_refusal_emits_won_t_fit_notification() -> void:
	# When a transfer is refused by the capacity gate, the repo emits an
	# EventBus.notification_requested signal so the player sees why the drop
	# was rejected (in addition to the engine-log push_warning).
	_setup()
	var bag := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "small_pouch",
		"name": "Small Pouch", "item_category": "container",
		"encumbrance_units": 100, "capacity_units": 500,
	})
	# Item too big to fit (700 > 500-unit cap).
	var oversize := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "boulder", "name": "Boulder",
		"encumbrance_units": 700,
	})
	# Subscribe a transient listener to capture the emitted notification.
	var captured: Array[Dictionary] = []
	var listener := func(data: Dictionary) -> void:
		captured.append(data)
	EventBus.notification_requested.connect(listener)

	var moved := CampaignRepository.update_inventory_item_equip_state(
		oversize, false, "pack", bag)

	EventBus.notification_requested.disconnect(listener)
	check(not moved, "transfer should be refused by capacity gate")
	check(captured.size() >= 1,
		"capacity refusal must emit at least one notification_requested; got %d" %
			captured.size())
	if captured.size() >= 1:
		var n: Dictionary = captured[0]
		check(str(n.get("category", "")) == "encumbrance",
			"notification category should be 'encumbrance', got '%s'" %
				str(n.get("category", "")))
		check(str(n.get("type", "")) == "warning",
			"notification type should be 'warning', got '%s'" %
				str(n.get("type", "")))
		check(str(n.get("title", "")) == "Won't fit",
			"notification title should be \"Won't fit\", got '%s'" %
				str(n.get("title", "")))
		var body: String = str(n.get("body", ""))
		check("Boulder" in body and "Small Pouch" in body,
			"notification body should mention both item + container names, got '%s'" %
				body)
	_teardown()


func test_mundane_container_capacity_via_equipment_catalog() -> void:
	# A backpack inserted with capacity_units=0 (e.g. from a code path that
	# doesn't know to look up the cap) must STILL enforce capacity by falling
	# back to EquipmentCatalog. base_equipment.json declares backpack
	# container_capacity_units = 4000 (4 stone).
	_setup()
	var backpack := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "backpack",
		"name": "Backpack", "item_category": "container",
		"encumbrance_units": 167, "capacity_units": 0,  # row cap unset
	})
	# 3000-unit item fits (within 4000 cap).
	var ok_item := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "ok", "name": "OK Item",
		"encumbrance_units": 3000,
	})
	var ok := CampaignRepository.update_inventory_item_equip_state(
		ok_item, false, "pack", backpack)
	check(ok, "3000-unit item should fit in backpack (cap 4000 from catalog)")

	# 1500-unit item would overflow (3000 + 1500 = 4500 > 4000). Refuse.
	var overflow_item := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "ovf", "name": "Overflow",
		"encumbrance_units": 1500,
	})
	var overflow_ok := CampaignRepository.update_inventory_item_equip_state(
		overflow_item, false, "pack", backpack)
	check(not overflow_ok,
		"3000+1500=4500 should refuse to fit in backpack (cap 4000 from catalog)")

	# Pouch fallback: capacity 500 (1/2 stone). 600-unit item must refuse.
	var pouch := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "pouch",
		"name": "Pouch", "item_category": "container",
		"encumbrance_units": 167, "capacity_units": 0,
	})
	var too_big_for_pouch := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "tbig", "name": "Too Big",
		"encumbrance_units": 600,
	})
	var pouch_ok := CampaignRepository.update_inventory_item_equip_state(
		too_big_for_pouch, false, "pack", pouch)
	check(not pouch_ok,
		"600-unit item should NOT fit in pouch (cap 500 from catalog)")
	_teardown()
