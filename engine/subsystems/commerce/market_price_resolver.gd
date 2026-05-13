class_name MarketPriceResolver
extends RefCounted

## Market price resolver — encodes the RAW 8-step "Determine Market Price of
## Merchandise" procedure at rules/acore-campaign-hijinks.xml:725-734 plus
## the monthly drift mechanic at L737-739.
##
## Per generation/gdd-settlement-economy.md §6. Consumes the post-step-6
## demand_modifier cache (Prereq.2b output) plus a cached 4d4 dice value
## stored on the same settlement_merchandise_demand row.
##
## The 4d4 dice is RAW's "market price is calculated once per type of
## merchandise for each visit to a market" rule (L722-723): all merchants in
## the same settlement transact at the same price for the same merchandise
## during a visit. The dice persists across visits until monthly drift
## re-rolls it at cumulative 10%/month probability (Q-MERC-6 [RESOLVED]:
## only the dice drifts, demand modifier stays anchored to structural inputs).


# ---------------------------------------------------------------------------
# §6.3 class-size adjustment (RAW acore-campaign-hijinks.xml:729-730)
# ---------------------------------------------------------------------------

## Returns the per-market-class adjustment per RAW step 4-5:
##   +1 for Class I or II (large/major markets)
##   -1 for Class V or VI (small/borderline markets)
##    0 otherwise (Class III, Class IV, or out-of-range defensive default)
static func class_size_adjust(market_class: int) -> int:
	match market_class:
		1, 2: return 1
		3, 4: return 0
		5, 6: return -1
		_:    return 0


# ---------------------------------------------------------------------------
# Pure dice roll (RAW step 2)
# ---------------------------------------------------------------------------

## Rolls 4d4 and returns the sum. Range: [4, 16] inclusive.
static func roll_4d4(rng: RandomNumberGenerator) -> int:
	var total: int = 0
	for _i in 4:
		total += rng.randi_range(1, 4)
	return total


# ---------------------------------------------------------------------------
# Pure percentage arithmetic (RAW step 8)
# ---------------------------------------------------------------------------

## Returns (sum of inputs) × 10. The "percentage" that step 8 applies to base
## price. No banker rounding here — pure integer arithmetic.
static func compute_percentage(
		dice_4d4: int,
		demand_modifier: int,
		class_size_adj: int,
		monopolist_favor: int,
		judge_modifier: int,
) -> int:
	return (dice_4d4 + demand_modifier + class_size_adj + monopolist_favor + judge_modifier) * 10


# ---------------------------------------------------------------------------
# Main entry point — RAW 8-step formula + drift check
# ---------------------------------------------------------------------------

## Computes the per-load market price for [param merchandise_type] at
## [param settlement_id]. Encodes the RAW 8-step procedure plus the dice-cache
## + monthly drift mechanism per §6.
##
## Parameters:
##   monopolist_favor — caller-supplied per §6.4. +1 when adventurer is the
##       monopolist AND selling; -1 when monopolist AND buying; 0 otherwise.
##   judge_modifier — caller-supplied integer for war, calamity, scripted
##       events; default 0.
##   rng — optional RandomNumberGenerator. If null, creates a randomized
##       generator. Tests should always pass a seeded RNG.
##   current_calendar_day — if -1, reads from the active campaign row.
##
## Returns dict with: gp_per_load, percentage, drift_occurred, breakdown.
static func compute_market_price(
		merchandise_type: String,
		settlement_id: String,
		monopolist_favor: int = 0,
		judge_modifier: int = 0,
		rng: RandomNumberGenerator = null,
		current_calendar_day: int = -1,
) -> Dictionary:
	if merchandise_type.is_empty() or settlement_id.is_empty():
		return _empty_result()
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	if current_calendar_day < 0:
		current_calendar_day = _read_current_calendar_day()

	# Inputs.
	var base_price_gp: int = MerchandiseRegistry.base_price_gp(merchandise_type)
	var demand_modifier: int = DemandModifierGenerator.get_demand_modifier(settlement_id, merchandise_type)
	var market_class: int = _read_market_class(settlement_id)
	var class_adj: int = class_size_adjust(market_class)

	# Ensure cache row exists with a rolled dice value.
	var dice_status: Dictionary = _ensure_dice_row(settlement_id, merchandise_type, current_calendar_day, rng)

	# If this wasn't a fresh roll, check drift (may re-roll).
	var drift_occurred: bool = false
	if not bool(dice_status.get("freshly_rolled", false)):
		drift_occurred = check_and_apply_drift(settlement_id, merchandise_type, current_calendar_day, rng)

	# Read final dice value (post-drift if drift fired).
	var dice_4d4: int = _read_dice(settlement_id, merchandise_type)

	var percentage: int = compute_percentage(
		dice_4d4, demand_modifier, class_adj, monopolist_favor, judge_modifier)
	var gp_per_load: int = _bankers_round(float(base_price_gp) * float(percentage) / 100.0)

	return {
		"gp_per_load": gp_per_load,
		"percentage": percentage,
		"drift_occurred": drift_occurred,
		"breakdown": {
			"base_price_gp": base_price_gp,
			"dice_4d4": dice_4d4,
			"demand_modifier": demand_modifier,
			"class_size_adjust": class_adj,
			"monopolist_favor": monopolist_favor,
			"judge_modifier": judge_modifier,
		},
	}


# ---------------------------------------------------------------------------
# §6.6 monthly drift
# ---------------------------------------------------------------------------

## Checks whether the monthly drift mechanic should re-roll the dice for
## the given (settlement, merchandise) pair, and applies the re-roll if so.
## Per RAW L737-739: cumulative 10% per month, forced at month 10.
##
## Returns true if a re-roll fired. Emits `EventBus.market_price_drifted`
## with (settlement_id, merchandise_type, old_dice, new_dice).
static func check_and_apply_drift(
		settlement_id: String,
		merchandise_type: String,
		current_calendar_day: int,
		rng: RandomNumberGenerator,
) -> bool:
	if settlement_id.is_empty() or merchandise_type.is_empty() or rng == null:
		return false
	var row: Dictionary = _read_dice_row(settlement_id, merchandise_type)
	if row.is_empty():
		return false
	var old_dice: int = int(row.get("dice_4d4_value", 0))
	if old_dice == 0:
		# Sentinel — dice never rolled. Not a drift candidate; the lazy-roll
		# path in compute_market_price handles initial dice population.
		return false
	var last_rolled_day: int = int(row.get("dice_last_rolled_calendar_day", 0))
	var days_since: int = current_calendar_day - last_rolled_day
	if days_since <= 0:
		return false
	var months_since: int = days_since / Timekeeping.DAYS_PER_MONTH
	if months_since <= 0:
		return false
	# §6.6.1: cumulative chance caps at 100% at month 10. §6.6.2 single-check
	# shortcut: roll once against current cumulative pct.
	var cumulative_pct: int = mini(months_since * 10, 100)
	if rng.randi_range(1, 100) > cumulative_pct:
		return false
	# Re-roll fires.
	var new_dice: int = roll_4d4(rng)
	_write_dice(settlement_id, merchandise_type, new_dice, current_calendar_day)
	EventBus.market_price_drifted.emit(settlement_id, merchandise_type, old_dice, new_dice)
	return true


## Walks every cached (settlement, merchandise) pair in the campaign and runs
## the drift check on each. Used at monthly tick (§6.6.3) so prices drift at
## markets the player hasn't visited recently.
##
## Returns count of re-rolls fired.
static func process_monthly_drift_for_campaign(
		campaign_id: String,
		current_calendar_day: int,
		rng: RandomNumberGenerator,
) -> int:
	if campaign_id.is_empty() or rng == null:
		return 0
	if not CampaignRepository.db.query_with_bindings("""
		SELECT smd.settlement_entrance_id, smd.merchandise_type
		FROM settlement_merchandise_demand smd
		JOIN settlement_entrances se ON smd.settlement_entrance_id = se.id
		WHERE se.campaign_id = ? AND smd.dice_4d4_value > 0
	""", [campaign_id]):
		return 0
	var pairs: Array = CampaignRepository.db.query_result.duplicate()
	var count: int = 0
	for row in pairs:
		var d: Dictionary = row
		var sid: String = str(d.get("settlement_entrance_id", ""))
		var mtype: String = str(d.get("merchandise_type", ""))
		if check_and_apply_drift(sid, mtype, current_calendar_day, rng):
			count += 1
	return count


# ---------------------------------------------------------------------------
# Internals — dice cache I/O
# ---------------------------------------------------------------------------

## Reads the existing cache row's dice. If dice_4d4_value == 0 (sentinel) or
## no row exists, rolls fresh and writes it. Returns {"dice": int,
## "freshly_rolled": bool}.
static func _ensure_dice_row(
		settlement_id: String,
		merchandise_type: String,
		current_calendar_day: int,
		rng: RandomNumberGenerator,
) -> Dictionary:
	var row: Dictionary = _read_dice_row(settlement_id, merchandise_type)
	if not row.is_empty() and int(row.get("dice_4d4_value", 0)) > 0:
		return {"dice": int(row.get("dice_4d4_value", 0)), "freshly_rolled": false}
	# Either no row (no demand modifier cache yet) or sentinel dice. Roll fresh.
	var new_dice: int = roll_4d4(rng)
	if row.is_empty():
		# Create a row. demand_modifier defaults to 0 — caller should have
		# generated demand modifiers first, but we don't strictly require it.
		CampaignRepository.db.query_with_bindings("""
			INSERT INTO settlement_merchandise_demand
				(settlement_entrance_id, merchandise_type,
				 demand_modifier, generated_at_calendar_day, source_kind,
				 pre_trade_route_shift_value,
				 dice_4d4_value, dice_last_rolled_calendar_day)
			VALUES (?, ?, 0, ?, 'generated', 0, ?, ?)
		""", [settlement_id, merchandise_type, current_calendar_day, new_dice, current_calendar_day])
	else:
		_write_dice(settlement_id, merchandise_type, new_dice, current_calendar_day)
	return {"dice": new_dice, "freshly_rolled": true}


static func _read_dice_row(settlement_id: String, merchandise_type: String) -> Dictionary:
	if not CampaignRepository.db.query_with_bindings("""
		SELECT dice_4d4_value, dice_last_rolled_calendar_day
		FROM settlement_merchandise_demand
		WHERE settlement_entrance_id = ? AND merchandise_type = ?
	""", [settlement_id, merchandise_type]):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0]


static func _read_dice(settlement_id: String, merchandise_type: String) -> int:
	var row: Dictionary = _read_dice_row(settlement_id, merchandise_type)
	if row.is_empty():
		return 0
	return int(row.get("dice_4d4_value", 0))


static func _write_dice(
		settlement_id: String,
		merchandise_type: String,
		dice_value: int,
		calendar_day: int,
) -> void:
	CampaignRepository.db.query_with_bindings("""
		UPDATE settlement_merchandise_demand
		SET dice_4d4_value = ?, dice_last_rolled_calendar_day = ?
		WHERE settlement_entrance_id = ? AND merchandise_type = ?
	""", [dice_value, calendar_day, settlement_id, merchandise_type])


# ---------------------------------------------------------------------------
# Internals — small helpers
# ---------------------------------------------------------------------------

static func _read_market_class(settlement_id: String) -> int:
	if not CampaignRepository.db.query_with_bindings(
			"SELECT market_class FROM settlement_entrances WHERE id = ?",
			[settlement_id]):
		return 6
	if CampaignRepository.db.query_result.is_empty():
		return 6
	return int(CampaignRepository.db.query_result[0].get("market_class", 6))


static func _read_current_calendar_day() -> int:
	if not CampaignRepository.db.query("SELECT calendar_day FROM campaigns WHERE is_active = 1 LIMIT 1"):
		return 0
	if CampaignRepository.db.query_result.is_empty():
		return 0
	return int(CampaignRepository.db.query_result[0].get("calendar_day", 0))


static func _empty_result() -> Dictionary:
	return {
		"gp_per_load": 0,
		"percentage": 0,
		"drift_occurred": false,
		"breakdown": {},
	}


## Banker's rounding (round half to even) per CLAUDE.md core principle.
## GDScript's roundi() rounds half AWAY from zero — not banker's.
static func _bankers_round(value: float) -> int:
	var floor_val: int = int(floor(value))
	var frac: float = value - float(floor_val)
	if absf(frac - 0.5) < 0.0000001:
		if floor_val % 2 == 0:
			return floor_val
		return floor_val + 1
	return int(roundf(value))
