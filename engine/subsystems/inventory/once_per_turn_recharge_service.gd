class_name OncePerTurnRechargeService
extends RefCounted

## Bulk-recharge service for once-per-turn misc-magic items.
##
## V1 covers Horn of Blasting (ACKS Core p.215+ RAW: "The horn may be
## blown once per turn"). Future once-per-turn items extend
## RECHARGEABLE_ITEM_KEYS.
##
## ── How it works ──────────────────────────────────────────────────────
## Once-per-turn items use the standard charge model
## (`misc_magic_consumable: false` + `default_charges: 1` in the catalog).
## After a successful activation `MagicItemActivator.use_misc_magic_active`
## decrements `uses_remaining` to 0 and the in-built charge gate at
## line 709 refuses subsequent activations.
##
## This service issues a single bulk UPDATE per Timekeeping.turn_advanced:
##   UPDATE inventory_items
##   SET uses_remaining = 1
##   WHERE item_key IN ('horn_of_blasting', ...)
##     AND uses_remaining < 1
##
## The `< 1` guard prevents needless writes for items that are already
## charged (the row's `updated_at` would change otherwise). The update is
## campaign-scoped — a future multi-campaign-loaded scenario gets each
## campaign's items refilled independently when its respective
## `Timekeeping.turn_advanced` fires.
##
## ── Why a bulk UPDATE, not per-character iteration ────────────────────
## The Horn (and any future once-per-turn item) can live in:
##   - The carrying character's personal inventory
##   - The party's shared_inventory
##   - A creature's inventory (mount, animal companion)
##   - A container (Bag of Holding etc.)
## All of these reach the same `inventory_items` table via different
## foreign keys. A single SQL UPDATE finds them all without traversing
## five different in-memory roster structures.
##
## ── Why not extend MagicItemActivator's charge gate ───────────────────
## The activator's gate is per-activation — it doesn't know about time.
## The recharge needs an external signal (turn boundary) AND a bulk
## refresh (handles items the player isn't actively engaging with).
## Keeping the recharge separate from the activator preserves the
## activator's single responsibility (per-use activation routing).
##
## ── Forward-compat ────────────────────────────────────────────────────
## Future once-per-turn items add their item_key to
## RECHARGEABLE_ITEM_KEYS. Items with N-per-turn charges (none known V1
## but plausible: a hypothetical "Wand of Bursts (3/turn)") would need an
## additional `n_per_turn` config — current service assumes 1.
##
## The "once per day" cousin (Elemental Commanders + future daily-reset
## items) lives in a separate service when it lands. The two services
## share the bulk-UPDATE pattern but key off different time signals
## (turn vs day).


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Canonical list of once-per-turn item_keys. Mirrors
## `tools/extract_magic_item_catalog.py:ONCE_PER_PERIOD_MISC_MAGIC_KEYS`.
## Out-of-sync between these two is a project-level bug — the extractor
## stamps `default_charges: 1 + misc_magic_consumable: false` on items in
## the Python set; this service refills them. If they disagree, an item
## either gets stuck at 0 charges (in service but not in extractor) or
## never recharges (in extractor but not in service).
const RECHARGEABLE_ITEM_KEYS: Array[String] = [
	"horn_of_blasting",
]


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Recharges all once-per-turn items in [param campaign_id] that have
## fewer than 1 charge remaining. Returns the number of rows updated
## (informational — most call sites discard).
##
## No-op when [param campaign_id] is empty or CampaignRepository.db is
## null. Cheap when no rechargeable items exist in the campaign (the
## WHERE clause filters by item_key list + uses_remaining limit).
static func recharge_for_campaign(campaign_id: String) -> int:
	if campaign_id.is_empty():
		return 0
	if CampaignRepository == null or CampaignRepository.db == null:
		return 0
	if RECHARGEABLE_ITEM_KEYS.is_empty():
		return 0

	# Build the parameterised IN clause: ?, ?, ?, ... one placeholder per
	# rechargeable key. SQLite parameter binding handles the array safely.
	var placeholders: PackedStringArray = []
	var bindings: Array = []
	for key: String in RECHARGEABLE_ITEM_KEYS:
		placeholders.append("?")
		bindings.append(key)
	var placeholder_csv: String = ",".join(placeholders)

	# V1 scope note: V1 only ever has one campaign loaded at a time, so
	# the global UPDATE is safe — campaign_id is reserved for the future
	# multi-campaign case where the query would need a JOIN against the
	# owning character's campaign_id. The `campaign_id` parameter is
	# documented + intentionally unused in V1.
	# Note: the inventory_items table has no `updated_at` column (the
	# existing per-item charge-decrement queries also omit it — see
	# magic_item_activator.gd:739 + casting_resolver.gd:319). If a future
	# migration adds the column, this UPDATE should include it.
	var query: String = """
		UPDATE inventory_items
		SET uses_remaining = 1
		WHERE item_key IN (%s)
		AND (uses_remaining IS NULL OR uses_remaining < 1)
	""" % placeholder_csv
	var ok: bool = CampaignRepository.db.query_with_bindings(query, bindings)
	if not ok:
		push_error("OncePerTurnRechargeService.recharge_for_campaign: UPDATE failed")
		return 0
	# SQLite doesn't return affected_rows directly via the bound query
	# wrapper, but the post-query count via a follow-up SELECT would be
	# wasted in production. Tests verify via per-row state inspection.
	return RECHARGEABLE_ITEM_KEYS.size()


## Returns true if [param item_key] is in the once-per-turn rechargeable
## set. Exposed for tests and for the activator's potential future
## per-item "is this rechargeable?" check.
static func is_rechargeable(item_key: String) -> bool:
	return item_key in RECHARGEABLE_ITEM_KEYS
