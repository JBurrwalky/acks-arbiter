class_name OncePerDayRechargeService
extends RefCounted

## Bulk-recharge service for once-per-day misc-magic items. Twin of
## `OncePerTurnRechargeService` — same shape, different time signal
## (`Timekeeping.day_changed` instead of `turn_advanced`).
##
## V1 covers the four Elemental Commanders. RAW (per ACore item
## descriptions): each commander summons + controls one elemental
## "once per day" (Stone of Controlling Earth Elementals explicitly,
## the Bowl/Brazier/Censer by parallel construction):
##
##   "Once per day summons and controls one [earth/water/fire/air]
##    elemental as conjure elemental. User must ready the item and
##    perform 1 turn of rituals before summoning. The summoning itself
##    takes 1 round. Continuous concentration is required to command
##    the elemental."
##
## Future once-per-day items (Helm of Teleportation comes to mind —
## "1/day" in some printings) extend `RECHARGEABLE_ITEM_KEYS`.
##
## ── How it works ──────────────────────────────────────────────────────
## Identical pattern to OncePerTurnRechargeService: a single bulk SQL
## UPDATE per `Timekeeping.day_changed` boundary that resets
## `uses_remaining = 1` for any once-per-day item with current charges
## < 1 (or NULL).
##
##   UPDATE inventory_items
##   SET uses_remaining = 1
##   WHERE item_key IN ('bowl_of_commanding_water_elementals',
##                       'brazier_of_commanding_fire_elementals',
##                       'censer_of_controlling_air_elementals',
##                       'stone_of_controlling_earth_elementals')
##     AND (uses_remaining IS NULL OR uses_remaining < 1)
##
## The `< 1 OR NULL` guard prevents needless writes for items already at
## full charge. The UPDATE is campaign-scoped — V1 single-campaign-
## loaded-at-a-time scope means the global UPDATE is safe; the
## `campaign_id` parameter is reserved for the future multi-campaign
## scenario where it would need a JOIN against the owning character's
## campaign_id.
##
## ── Why a bulk UPDATE, not per-character iteration ────────────────────
## Same as OncePerTurnRechargeService: Elemental Commanders can live in
## PC inventory / shared / creature / container. One SQL UPDATE finds
## them all without traversing five different in-memory roster
## structures.
##
## ── Sync with the Python extractor ────────────────────────────────────
## `RECHARGEABLE_ITEM_KEYS` mirrors
## `tools/extract_magic_item_catalog.py:ELEMENTAL_COMMANDER_KEYS`.
## Out-of-sync between these two is a project-level bug class — the
## extractor stamps `default_charges: 1 + misc_magic_consumable: false`
## on items in the Python set; this service refills them. If they
## disagree, an item either gets stuck at 0 charges (in service but not
## in extractor) or never recharges (in extractor but not in service).
##
## ── Timing semantics ──────────────────────────────────────────────────
## `Timekeeping.day_changed` fires when the in-game clock crosses
## midnight. So an Elemental Commander used at 11pm refills 1 hour later,
## not 24 hours later. This matches RAW intent (the item is "once per
## day," not "with a 24-hour cooldown"); the same player using two
## different items at 11pm and then at 1am the next morning has both
## available again at 1am.
##
## A more conservative "24-hour rolling cooldown" interpretation would
## need a per-item-row last-used timestamp + a per-item comparison —
## strictly more state for V1 minimal benefit. The midnight-rollover
## model also matches Horn's "every turn boundary" model: refill is
## driven by the period-boundary signal, not a per-use timer.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Canonical list of once-per-day item_keys. Mirrors
## `tools/extract_magic_item_catalog.py:ELEMENTAL_COMMANDER_KEYS`.
## See header comment for the sync-bug class explanation.
const RECHARGEABLE_ITEM_KEYS: Array[String] = [
	"bowl_of_commanding_water_elementals",
	"brazier_of_commanding_fire_elementals",
	"censer_of_controlling_air_elementals",
	"stone_of_controlling_earth_elementals",
]


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Recharges all once-per-day items in [param campaign_id] that have fewer
## than 1 charge remaining. Returns the size of `RECHARGEABLE_ITEM_KEYS`
## (informational — most call sites discard).
##
## No-op when [param campaign_id] is empty or `CampaignRepository.db` is
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
	# documented + intentionally unused in V1. Same pattern as
	# OncePerTurnRechargeService.
	#
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
		push_error("OncePerDayRechargeService.recharge_for_campaign: UPDATE failed")
		return 0
	return RECHARGEABLE_ITEM_KEYS.size()


## Returns true if [param item_key] is in the once-per-day rechargeable
## set. Exposed for tests and for the activator's refusal-hint dispatch.
static func is_rechargeable(item_key: String) -> bool:
	return item_key in RECHARGEABLE_ITEM_KEYS
