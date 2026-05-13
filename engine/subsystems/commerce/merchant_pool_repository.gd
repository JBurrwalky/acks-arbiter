class_name MerchantPoolRepository
extends RefCounted

## Merchant-pool data layer — generates, surfaces, consumes, and expires
## merchants per settlement cohort.
##
## Per generation/gdd-settlement-economy.md §7. The pool is regenerated on
## the monthly tick (one row per merchant, always max count). Visibility
## is controlled by `becomes_visible_calendar_day`:
##   * PC-owned domain settlements: visible immediately on generation.
##   * Other settlements: invisible (INVISIBLE_SENTINEL) until
##     solicit_merchants flips them on a staggered schedule, or
##     locate_merchandise surfaces a single targeted merchant.
##
## Cohort lifecycle = Timekeeping.DAYS_PER_MONTH (28 days). process_expirations
## deletes rows whose expires_at_calendar_day has passed.
##
## RefCounted static-function library — no instance state, no autoload.


# ---------------------------------------------------------------------------
# §7.1 Markets and Merchants table (RAW acore-campaign-hijinks.xml:656-672)
# ---------------------------------------------------------------------------

const MARKETS_AND_MERCHANTS := {
	1: {"toll_dice": "1d6+15", "merchants_dice": "2d6+2", "loads_dice": "6d8"},
	2: {"toll_dice": "1d10+10", "merchants_dice": "2d4+1", "loads_dice": "4d6"},
	3: {"toll_dice": "1d8+5",  "merchants_dice": "2d4",   "loads_dice": "3d4"},
	4: {"toll_dice": "1d6+3",  "merchants_dice": "1d4",   "loads_dice": "2d4"},
	5: {"toll_dice": "1d6",    "merchants_dice": "1d4-1", "loads_dice": "1d4"},
	6: {"toll_dice": "1d3",    "merchants_dice": "1d3-1", "loads_dice": "1d2"},
}

## §7.2 max merchant count per market class (max of the merchants_dice spec).
## I=14, II=9, III=8, IV=4, V=3, VI=2.
const _MAX_MERCHANT_COUNT := {
	1: 14,
	2: 9,
	3: 8,
	4: 4,
	5: 3,
	6: 2,
}

## INT32_MAX sentinel — `becomes_visible_calendar_day` value meaning "invisible
## until solicit_merchants or locate_merchandise flips it." Per §7.4 / §7.8.
const INVISIBLE_SENTINEL := 2147483647


# ---------------------------------------------------------------------------
# Pure-function table accessors (consumed by MarketFeesCalculator §8 + tests)
# ---------------------------------------------------------------------------

## Returns the maximum number of merchants for a market class. Used by
## generate_pool_for_settlement to size the cohort.
static func max_merchant_count(market_class: int) -> int:
	return int(_MAX_MERCHANT_COUNT.get(market_class, 0))


## Returns the toll-dice spec for a market class (e.g., "1d8+5" for Class III).
## Canonical source for MarketFeesCalculator.entry_toll_gp.
static func toll_dice_for_class(market_class: int) -> String:
	var row: Dictionary = MARKETS_AND_MERCHANTS.get(market_class, {})
	return String(row.get("toll_dice", "1d3"))


# ---------------------------------------------------------------------------
# Read API (visibility-aware)
# ---------------------------------------------------------------------------

## Returns active merchants visible at [param current_calendar_day]. A merchant
## is visible iff `status='active'` AND `becomes_visible_calendar_day <= current_day`.
static func list_visible_merchants(settlement_id: String, current_calendar_day: int) -> Array:
	if settlement_id.is_empty():
		return []
	if not CampaignRepository.db.query_with_bindings("""
		SELECT * FROM merchant_pool
		WHERE settlement_entrance_id = ? AND status = 'active'
			AND becomes_visible_calendar_day <= ?
		ORDER BY id ASC
	""", [settlement_id, current_calendar_day]):
		return []
	return CampaignRepository.db.query_result.duplicate()


## Same as list_visible_merchants but filtered by [param merchandise_type].
static func list_visible_merchants_for_merchandise(
		settlement_id: String,
		merchandise_type: String,
		current_calendar_day: int,
) -> Array:
	if settlement_id.is_empty() or merchandise_type.is_empty():
		return []
	if not CampaignRepository.db.query_with_bindings("""
		SELECT * FROM merchant_pool
		WHERE settlement_entrance_id = ? AND status = 'active'
			AND merchandise_type = ?
			AND becomes_visible_calendar_day <= ?
		ORDER BY id ASC
	""", [settlement_id, merchandise_type, current_calendar_day]):
		return []
	return CampaignRepository.db.query_result.duplicate()


## Returns active merchants whose `becomes_visible_calendar_day` is in the
## future (or equal to the INVISIBLE_SENTINEL). Used by solicit_merchants
## and locate_merchandise to find reveal candidates.
static func list_invisible_merchants(settlement_id: String, current_calendar_day: int) -> Array:
	if settlement_id.is_empty():
		return []
	if not CampaignRepository.db.query_with_bindings("""
		SELECT * FROM merchant_pool
		WHERE settlement_entrance_id = ? AND status = 'active'
			AND becomes_visible_calendar_day > ?
		ORDER BY id ASC
	""", [settlement_id, current_calendar_day]):
		return []
	return CampaignRepository.db.query_result.duplicate()


static func get_merchant(merchant_id: String) -> Dictionary:
	if merchant_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
			"SELECT * FROM merchant_pool WHERE id = ?", [merchant_id]):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0]


# ---------------------------------------------------------------------------
# §7.4 Pool generation
# ---------------------------------------------------------------------------

## Wipes the settlement's previous `source_kind='monthly_refresh'` rows
## (preserving `source_kind='manual'`) and generates a fresh cohort of
## `max_merchant_count(class)` merchants. Each merchant's merchandise type
## is rolled via MerchandiseRegistry.random_common; loads_available rolled
## from the class's loads_dice spec.
##
## Visibility depends on [param pc_owned]:
##   * pc_owned = true  → becomes_visible_calendar_day = current_calendar_day (visible)
##   * pc_owned = false → becomes_visible_calendar_day = INVISIBLE_SENTINEL (invisible)
##
## Returns the number of merchants generated.
static func generate_pool_for_settlement(
		settlement_id: String,
		current_calendar_day: int,
		rng: RandomNumberGenerator,
		pc_owned: bool,
) -> int:
	if settlement_id.is_empty():
		return 0
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	# Resolve campaign_id + market_class.
	var settlement: Dictionary = _read_settlement(settlement_id)
	if settlement.is_empty():
		return 0
	var campaign_id: String = str(settlement.get("campaign_id", ""))
	var market_class: int = int(settlement.get("market_class", 6))
	if market_class < 1 or market_class > 6:
		return 0

	# Delete previous monthly_refresh rows; preserve manual.
	CampaignRepository.db.query_with_bindings("""
		DELETE FROM merchant_pool
		WHERE settlement_entrance_id = ? AND source_kind = 'monthly_refresh'
	""", [settlement_id])

	var visibility_default: int = current_calendar_day if pc_owned else INVISIBLE_SENTINEL
	var expires: int = current_calendar_day + Timekeeping.DAYS_PER_MONTH
	var loads_spec: String = String((MARKETS_AND_MERCHANTS.get(market_class, {}) as Dictionary).get("loads_dice", "1d2"))
	var n: int = max_merchant_count(market_class)

	for _i in n:
		var entry: Dictionary = MerchandiseRegistry.random_common(rng)
		var merchandise_type: String = String(entry.get("merchandise_type", ""))
		if merchandise_type.is_empty():
			continue
		var loads: int = maxi(1, _roll_dice_spec(loads_spec, rng))
		var merchant_id: String = CampaignRepository.generate_id()
		CampaignRepository.db.query_with_bindings("""
			INSERT INTO merchant_pool
				(id, campaign_id, settlement_entrance_id, merchandise_type,
				 loads_available, loads_initial,
				 created_at_calendar_day, expires_at_calendar_day,
				 becomes_visible_calendar_day, status, source_kind)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'active', 'monthly_refresh')
		""", [
			merchant_id, campaign_id, settlement_id, merchandise_type,
			loads, loads,
			current_calendar_day, expires,
			visibility_default,
		])

	EventBus.merchant_pool_refreshed.emit(settlement_id, n)
	return n


## Walks every settlement in [param campaign_id], processes its expirations,
## determines PC-ownership via the parent domain's owner_character_id, and
## regenerates the cohort. Used by the monthly tick path.
##
## Returns the total count of merchants generated across all settlements.
static func process_monthly_refresh_for_campaign(
		campaign_id: String,
		current_calendar_day: int,
		rng: RandomNumberGenerator,
) -> int:
	if campaign_id.is_empty():
		return 0
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	if not CampaignRepository.db.query_with_bindings("""
		SELECT id, parent_domain_id FROM settlement_entrances WHERE campaign_id = ?
	""", [campaign_id]):
		return 0
	var settlements: Array = CampaignRepository.db.query_result.duplicate()
	var total: int = 0
	for s in settlements:
		var sd: Dictionary = s
		var s_id: String = str(sd.get("id", ""))
		if s_id.is_empty():
			continue
		var parent_var: Variant = sd.get("parent_domain_id", null)
		var pc_owned: bool = false
		if parent_var != null and not str(parent_var).is_empty():
			pc_owned = _domain_is_pc_owned(str(parent_var))
		process_expirations(s_id, current_calendar_day)
		total += generate_pool_for_settlement(s_id, current_calendar_day, rng, pc_owned)
	return total


# ---------------------------------------------------------------------------
# §7.5.1 solicit_merchants — staggered reveal
# ---------------------------------------------------------------------------

## Per RAW acore-campaign-hijinks.xml:679-684. Reads invisible merchants;
## sorts by id; assigns becomes_visible_calendar_day on the half/quarter/
## remainder schedule (week 1 / 2 / 3 after solicit_day).
##
## Rejects if no invisible merchants exist (already revealed or PC-owned
## pool). Returns:
##   {success: bool, error: String, merchants_revealed: int}
static func process_solicitation(
		settlement_id: String,
		character_id: String,
		current_calendar_day: int,
) -> Dictionary:
	var result := {"success": false, "error": "", "merchants_revealed": 0}
	if settlement_id.is_empty():
		result["error"] = "empty_settlement_id"
		return result
	# Reach invisible merchants only — visible ones aren't candidates.
	if not CampaignRepository.db.query_with_bindings("""
		SELECT id FROM merchant_pool
		WHERE settlement_entrance_id = ? AND status = 'active'
			AND becomes_visible_calendar_day > ?
		ORDER BY id ASC
	""", [settlement_id, current_calendar_day]):
		result["error"] = "query_failed"
		return result
	var invisible_rows: Array = CampaignRepository.db.query_result.duplicate()
	var n: int = invisible_rows.size()
	if n == 0:
		result["error"] = "already_revealed"
		return result

	# §7.5.1 thirds.
	var first_half: int = int(ceili(float(n) / 2.0))
	var second_quarter: int = maxi(int(floori(float(n) / 4.0)), 1)
	# Clamp to remaining merchants (N=1 case).
	if first_half + second_quarter > n:
		second_quarter = n - first_half
	if second_quarter < 0:
		second_quarter = 0

	var week_1_day: int = current_calendar_day + 7
	var week_2_day: int = current_calendar_day + 14
	var week_3_day: int = current_calendar_day + 21

	for idx in n:
		var merchant_id: String = str((invisible_rows[idx] as Dictionary).get("id", ""))
		var reveal_day: int = week_3_day
		if idx < first_half:
			reveal_day = week_1_day
		elif idx < first_half + second_quarter:
			reveal_day = week_2_day
		CampaignRepository.db.query_with_bindings(
			"UPDATE merchant_pool SET becomes_visible_calendar_day = ? WHERE id = ?",
			[reveal_day, merchant_id])

	EventBus.solicitation_started.emit(settlement_id, character_id, n)
	result["success"] = true
	result["merchants_revealed"] = n
	return result


# ---------------------------------------------------------------------------
# §7.5.2 locate_merchandise — alter-not-spawn targeted reveal
# ---------------------------------------------------------------------------

## Per RAW conceptual grounding at acore-campaign-hijinks.xml:707-715.
## Searches active merchants for the merchandise type:
##   * If any visible match exists → no-op success (player already knew).
##   * Else if any invisible match → surface ONE (set
##     becomes_visible_calendar_day = current_calendar_day); emit signal.
##   * Else → fail with no_merchant_of_type.
##
## Returns:
##   {success: bool, error: String, merchant_id: String, surfaced_now: bool}
static func process_locate(
		settlement_id: String,
		merchandise_type: String,
		current_calendar_day: int,
) -> Dictionary:
	var result := {"success": false, "error": "", "merchant_id": "", "surfaced_now": false}
	if settlement_id.is_empty() or merchandise_type.is_empty():
		result["error"] = "empty_arg"
		return result
	# Visible match first.
	if not CampaignRepository.db.query_with_bindings("""
		SELECT id FROM merchant_pool
		WHERE settlement_entrance_id = ? AND status = 'active'
			AND merchandise_type = ?
			AND becomes_visible_calendar_day <= ?
		ORDER BY id ASC LIMIT 1
	""", [settlement_id, merchandise_type, current_calendar_day]):
		result["error"] = "query_failed"
		return result
	if not CampaignRepository.db.query_result.is_empty():
		result["success"] = true
		result["merchant_id"] = str(CampaignRepository.db.query_result[0].get("id", ""))
		result["surfaced_now"] = false
		return result
	# Invisible match — surface one.
	if not CampaignRepository.db.query_with_bindings("""
		SELECT id FROM merchant_pool
		WHERE settlement_entrance_id = ? AND status = 'active'
			AND merchandise_type = ?
			AND becomes_visible_calendar_day > ?
		ORDER BY id ASC LIMIT 1
	""", [settlement_id, merchandise_type, current_calendar_day]):
		result["error"] = "query_failed"
		return result
	if CampaignRepository.db.query_result.is_empty():
		result["error"] = "no_merchant_of_type"
		return result
	var merchant_id: String = str(CampaignRepository.db.query_result[0].get("id", ""))
	CampaignRepository.db.query_with_bindings(
		"UPDATE merchant_pool SET becomes_visible_calendar_day = ? WHERE id = ?",
		[current_calendar_day, merchant_id])
	EventBus.merchant_surfaced_via_locate.emit(merchant_id, settlement_id, merchandise_type)
	result["success"] = true
	result["merchant_id"] = merchant_id
	result["surfaced_now"] = true
	return result


# ---------------------------------------------------------------------------
# §7.7.1 consume_loads — within-month depletion
# ---------------------------------------------------------------------------

## Decrements [param loads_count] from the merchant's loads_available.
## If insufficient loads → returns false; row unchanged. If reaches 0 →
## status flips to 'depleted' and merchant_depleted signal fires.
static func consume_loads(merchant_id: String, loads_count: int) -> bool:
	if merchant_id.is_empty() or loads_count <= 0:
		return false
	var merchant: Dictionary = get_merchant(merchant_id)
	if merchant.is_empty():
		return false
	if str(merchant.get("status", "")) != "active":
		return false
	var available: int = int(merchant.get("loads_available", 0))
	if loads_count > available:
		return false
	var new_available: int = available - loads_count
	var new_status: String = "depleted" if new_available <= 0 else "active"
	CampaignRepository.db.query_with_bindings(
		"UPDATE merchant_pool SET loads_available = ?, status = ? WHERE id = ?",
		[new_available, new_status, merchant_id])
	EventBus.merchant_loads_consumed.emit(merchant_id, loads_count, new_available)
	if new_status == "depleted":
		EventBus.merchant_depleted.emit(merchant_id, str(merchant.get("settlement_entrance_id", "")))
	return true


# ---------------------------------------------------------------------------
# §7.7 process_expirations
# ---------------------------------------------------------------------------

## Deletes 'active' rows where expires_at_calendar_day < current_calendar_day.
## Emits one merchant_expired signal per deleted row.
## Returns the count of deleted rows.
static func process_expirations(settlement_id: String, current_calendar_day: int) -> int:
	if settlement_id.is_empty():
		return 0
	# Collect IDs before delete so we can fire signals.
	if not CampaignRepository.db.query_with_bindings("""
		SELECT id FROM merchant_pool
		WHERE settlement_entrance_id = ? AND status = 'active'
			AND expires_at_calendar_day < ?
	""", [settlement_id, current_calendar_day]):
		return 0
	var ids: Array = []
	for row in CampaignRepository.db.query_result:
		ids.append(str((row as Dictionary).get("id", "")))
	if ids.is_empty():
		return 0
	for mid in ids:
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM merchant_pool WHERE id = ?", [mid])
		EventBus.merchant_expired.emit(mid, settlement_id)
	return ids.size()


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _read_settlement(settlement_id: String) -> Dictionary:
	if settlement_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings("""
		SELECT id, campaign_id, market_class, parent_domain_id
		FROM settlement_entrances WHERE id = ?
	""", [settlement_id]):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0]


## Returns true iff the domain's owner_character_id resolves to a PC
## character (characters.character_type == 'pc'). NPC-owned domains return
## false. Unowned domains (NULL owner_character_id) return false — the
## settlement is treated as non-PC for visibility purposes.
static func _domain_is_pc_owned(domain_id: String) -> bool:
	if domain_id.is_empty():
		return false
	if not CampaignRepository.db.query_with_bindings("""
		SELECT c.character_type FROM domains d
		JOIN characters c ON d.owner_character_id = c.id
		WHERE d.id = ?
	""", [domain_id]):
		return false
	if CampaignRepository.db.query_result.is_empty():
		return false
	return str(CampaignRepository.db.query_result[0].get("character_type", "")) == "pc"


## NdM / NdM+K / NdM-K dice parser. Mirrors MerchandiseRegistry._roll_subroll
## and MarketFeesCalculator._roll_dice_spec; if a fourth subsystem needs it,
## extract into a shared DiceUtil helper.
static func _roll_dice_spec(spec: String, rng: RandomNumberGenerator) -> int:
	var add_idx: int = spec.find("+")
	var sub_idx: int = spec.find("-")
	var modifier: int = 0
	var dice_part: String = spec
	if add_idx > -1:
		dice_part = spec.substr(0, add_idx)
		modifier = int(spec.substr(add_idx + 1))
	elif sub_idx > -1:
		dice_part = spec.substr(0, sub_idx)
		modifier = -int(spec.substr(sub_idx + 1))
	var d_idx: int = dice_part.find("d")
	if d_idx < 0:
		push_error("MerchantPoolRepository._roll_dice_spec: malformed '%s'" % spec)
		return 0
	var n: int = int(dice_part.substr(0, d_idx))
	var sides: int = int(dice_part.substr(d_idx + 1))
	if n <= 0 or sides <= 0:
		push_error("MerchantPoolRepository._roll_dice_spec: invalid dice in '%s'" % spec)
		return 0
	var total: int = 0
	for _i in n:
		total += rng.randi_range(1, sides)
	return total + modifier
