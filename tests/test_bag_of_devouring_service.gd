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

const _DB_CAMPAIGN := "test_bod_campaign"
const _DB_CHAR := "test_bod_char"


func run_all_tests() -> void:
	test_catalog_shape_for_both_bags()
	test_start_timer_on_first_item_into_empty_bag()
	test_additional_items_do_not_reset_active_timer()
	test_removal_mid_cycle_does_not_reset_timer()
	test_try_devour_before_expiration_is_noop()
	test_try_devour_after_expiration_deletes_contents_and_resets()
	test_reset_timer_when_bag_goes_empty_via_removal()
	test_find_expired_bags_filters_correctly()
	test_non_bag_of_devouring_items_unaffected_by_helpers()
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
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var current_turn := 1000
	var started: bool = BagOfDevouringService.start_timer_on_first_item(
		bag_id, current_turn, rng)
	check(started, "first item into empty bag should start the timer")

	var bag_post: Dictionary = CampaignRepository.get_inventory_item_by_id(bag_id)
	var fires_at: int = int(bag_post.get("devouring_at_turn", -1))
	check(fires_at >= current_turn + 7 and fires_at <= current_turn + 10,
		"timer should fire 7-10 turns out (6+1d4), got fires_at=%d, current=%d" %
			[fires_at, current_turn])

	_teardown()


func test_additional_items_do_not_reset_active_timer() -> void:
	_setup()
	var bag_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "bag_of_devouring",
		"name": "Bag of Devouring", "is_extradimensional": true,
	})
	var rng := RandomNumberGenerator.new()
	rng.seed = 42

	# Start the timer manually (simulating first-item placement).
	BagOfDevouringService.start_timer_on_first_item(bag_id, 100, rng)
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
		bag_id, 200, rng)
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
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	BagOfDevouringService.start_timer_on_first_item(bag_id, 50, rng)
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
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	BagOfDevouringService.start_timer_on_first_item(bag_id, 100, rng)
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
	var rng := RandomNumberGenerator.new()
	rng.seed = 999
	BagOfDevouringService.start_timer_on_first_item(bag_id, 50, rng)
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
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	BagOfDevouringService.start_timer_on_first_item(bag_id, 0, rng)
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
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	# Two bags on the character.
	var bag1 := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "bag_of_devouring",
		"name": "BoD 1", "is_extradimensional": true,
	})
	var bag2 := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "bag_of_devouring",
		"name": "BoD 2", "is_extradimensional": true,
	})
	BagOfDevouringService.start_timer_on_first_item(bag1, 100, rng)  # fires 107-110
	BagOfDevouringService.start_timer_on_first_item(bag2, 200, rng)  # fires 207-210

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
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	check(not BagOfDevouringService.is_bag_of_devouring(
		CampaignRepository.get_inventory_item_by_id(boh)),
		"Bag of Holding must NOT be identified as Bag of Devouring")
	# Attempting to start the timer must be a no-op.
	check(not BagOfDevouringService.start_timer_on_first_item(boh, 100, rng),
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


func _teardown() -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE character_id = ?", [_DB_CHAR])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM characters WHERE id = ?", [_DB_CHAR])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [_DB_CAMPAIGN])
