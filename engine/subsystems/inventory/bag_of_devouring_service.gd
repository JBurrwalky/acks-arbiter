class_name BagOfDevouringService
extends RefCounted

## Timer mechanic for the Bag of Devouring magic item.
##
## RAW (ACKS Core 2026-05-31, Jedidiah-supplied):
##   "This magical bag is the size of a small sack. It opens into a
##   nondimensional space, seemingly identical to that of a bag of holding.
##   After 6+1d4 turns, all items placed in this bag vanish and are
##   permanently lost. The bag must be fully closed for this effect to take
##   place."
##
## Project simplification (Jedidiah 2026-05-31):
##   The timer begins ticking after any item is placed in the empty bag,
##   whether empty due to acquisition (a freshly-found bag) or due to a
##   prior devouring event. No explicit "is closed" toggle; V1 assumes the
##   bag is always closed while in inventory.
##
## Lifecycle:
##   1. Empty Bag of Devouring sits in inventory with `devouring_at_turn = -1`.
##   2. Player drops an item into the bag (via inventory UI or programmatic
##      transfer). The activation hook calls `start_timer_on_first_item`,
##      which sets `devouring_at_turn = current_turn + 6 + 1d4` (= 7-10 turns
##      out). Additional items placed during this window do NOT reset the
##      timer.
##   3. Player may remove items mid-cycle. The remaining items still vanish
##      at the original `devouring_at_turn`. If removal empties the bag,
##      `devouring_at_turn` resets to -1.
##   4. On every `Timekeeping.turn_advanced` signal, the tick handler calls
##      `find_expired_bags` for the active campaign and `try_devour_if_expired`
##      for each. Expired bags have their contents deleted + timer reset.
##
## Identification: Bag of Devouring is recognised by `item_key == "bag_of_devouring"`.
## No new column; the catalog flag `is_devouring` lives in the magic_item_catalog
## metadata for documentation, but the runtime check is item_key-based for
## simplicity (avoids threading another column into add_inventory_item).
##
## Not an autoload — static methods, instantiated as needed. The Timekeeping
## subscription lives on `LocationCacheManager` (which already wires similar
## timer/decay logic).


const BAG_OF_DEVOURING_ITEM_KEY := "bag_of_devouring"

# RAW timer: 6 + 1d4 turns. Result range: 7 to 10 turns. Rolled via
# DiceSystem.roll_digital(4, 1, 6, "bag_of_devouring_timer") so tests can
# force a specific result via GameState.dice_overrides + production runs
# stay deterministic-seed compatible.
const DEVOURING_TIMER_BASE_TURNS: int = 6
const DEVOURING_TIMER_DIE_SIZE: int = 4
const DEVOURING_TIMER_ROLL_TYPE := "bag_of_devouring_timer"


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Identify a bag of devouring by its item_key (avoids threading a separate
## `is_devouring` column through every INSERT path).
static func is_bag_of_devouring(item_row: Dictionary) -> bool:
	return str(item_row.get("item_key", "")) == BAG_OF_DEVOURING_ITEM_KEY


## Called when an item is placed into a Bag of Devouring (i.e. its
## container_id is being set to the bag's id). If the bag is currently empty
## AND has no active timer, sets `devouring_at_turn = current_turn + 6 + 1d4`.
## Subsequent placements during the active window do not reset the timer.
##
## [param bag_id] must be the id of a Bag of Devouring row.
## [param current_turn] from `Timekeeping.get_total_turns()`.
##
## The 1d4 timer roll goes through `DiceSystem.roll_digital(4, 1, 6,
## "bag_of_devouring_timer")` so tests can force a specific result by
## queuing `GameState.dice_overrides[DEVOURING_TIMER_ROLL_TYPE] = N` (where
## N is the final modified_total, e.g. 8 for "rolled a 2 + 6 modifier").
## Production runs use the project's standard digital-dice path.
##
## Returns true if a new timer was started, false if no-op (bag already had
## active timer, or bag has existing contents from before the new item).
static func start_timer_on_first_item(bag_id: String, current_turn: int) -> bool:
	if bag_id.is_empty():
		return false
	# Inspect bag row to confirm timer state.
	var bag: Dictionary = CampaignRepository.get_inventory_item_by_id(bag_id)
	if bag.is_empty() or not is_bag_of_devouring(bag):
		return false
	# If a timer is already running, don't reset.
	if int(bag.get("devouring_at_turn", -1)) >= 0:
		return false
	# Count current contents. If non-empty, no new timer (the bag must have
	# had items in it pre-call — defensive; in normal flow the caller checks
	# emptiness before adding, but this catches mis-ordered calls).
	var existing_contents: Array = CampaignRepository.get_items_in_container(bag_id)
	if not existing_contents.is_empty():
		return false
	# Roll 6 + 1d4 turns via DiceSystem. modified_total = raw + modifier
	# = (1..4) + 6 = 7..10.
	var roll: RollResult = DiceSystem.roll_digital(
		DEVOURING_TIMER_DIE_SIZE, 1, DEVOURING_TIMER_BASE_TURNS,
		DEVOURING_TIMER_ROLL_TYPE)
	var fires_at: int = current_turn + roll.modified_total
	return _set_devouring_at_turn(bag_id, fires_at)


## Checks the bag's timer state and devours contents if expired.
## Idempotent — re-calling after a successful devour is a no-op (timer is
## already reset).
##
## Returns true if devouring fired this call; false otherwise.
static func try_devour_if_expired(bag_id: String, current_turn: int) -> bool:
	if bag_id.is_empty():
		return false
	var bag: Dictionary = CampaignRepository.get_inventory_item_by_id(bag_id)
	if bag.is_empty() or not is_bag_of_devouring(bag):
		return false
	var fires_at: int = int(bag.get("devouring_at_turn", -1))
	if fires_at < 0:
		return false  # no active timer
	if current_turn < fires_at:
		return false  # not yet expired
	# Devour: delete all contents + reset timer.
	devour_contents(bag_id)
	return true


## Delete every item inside the bag + reset its timer to -1. Used by
## try_devour_if_expired when the timer fires; also called directly by the
## bag-becomes-empty hook (e.g. removal that empties the bag → timer should
## reset for the next cycle).
static func devour_contents(bag_id: String) -> void:
	if bag_id.is_empty():
		return
	var db = CampaignRepository.db
	db.query("BEGIN TRANSACTION")
	db.query_with_bindings(
		"DELETE FROM inventory_items WHERE container_id = ?", [bag_id])
	db.query_with_bindings(
		"UPDATE inventory_items SET devouring_at_turn = -1 WHERE id = ?", [bag_id])
	db.query("COMMIT")


## Reset the timer to -1 without touching contents. Called from the
## removal hook when the LAST item is removed from the bag (the bag goes
## empty without devouring; future placement starts a fresh cycle).
static func reset_timer_on_empty(bag_id: String) -> void:
	if bag_id.is_empty():
		return
	var bag: Dictionary = CampaignRepository.get_inventory_item_by_id(bag_id)
	if bag.is_empty() or not is_bag_of_devouring(bag):
		return
	# Only reset if currently empty.
	var contents: Array = CampaignRepository.get_items_in_container(bag_id)
	if contents.is_empty():
		_set_devouring_at_turn(bag_id, -1)


## Find all bags of devouring across the active campaign with active timers
## that have expired (current_turn >= devouring_at_turn). Returns an Array of
## bag ids. The caller (the Timekeeping tick handler) iterates and calls
## devour_contents on each.
static func find_expired_bags(campaign_id: String, current_turn: int) -> Array:
	var out: Array = []
	var db = CampaignRepository.db
	if not db.query_with_bindings(
			"""SELECT i.id FROM inventory_items i
			   LEFT JOIN characters c ON i.character_id = c.id
			   WHERE i.item_key = ?
			     AND i.devouring_at_turn >= 0
			     AND i.devouring_at_turn <= ?
			     AND (c.campaign_id = ? OR i.character_id = '')""",
			[BAG_OF_DEVOURING_ITEM_KEY, current_turn, campaign_id]):
		return out
	for row in db.query_result:
		out.append(str(row.get("id", "")))
	return out


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

static func _set_devouring_at_turn(bag_id: String, fires_at: int) -> bool:
	return CampaignRepository.db.query_with_bindings(
		"UPDATE inventory_items SET devouring_at_turn = ? WHERE id = ?",
		[fires_at, bag_id])
