class_name CommerceMonthlyResolver
extends RefCounted

## Commerce-side monthly tick dispatcher — Phase 10B.2 Wave 5 (Trade block).
##
## Per gdd-phase-10b-2-trade-block.md §11.4. Static-function library, not an
## autoload. Invoked from DomainHandlers._handle_monthly_tick (the existing
## monthly-tick coordinator) once per month per campaign.
##
## Drivers fire in narrative order (per §11.2):
##   1. Annual customs roll (year-boundary only; de-dup'd via
##      campaigns.last_customs_roll_year).
##   2. Ship operating costs (crew/maintenance debit per non-destroyed ship).
##   3. Merchant pool refresh (wipe transactional cohort; preserve manual +
##      promoted_npc_id rows; generate fresh max-count merchants per
##      settlement).
##   4. Market price drift (re-roll cached 4d4 dice with cumulative 10%/month
##      probability per settlement-merchandise pair).
##
## Determinism: caller seeds the RNG via hash("monthly|<campaign>|<day>") so
## the same (campaign, calendar_day) produces the same dice sequence across
## save/load (per §11.6).
##
## Emits commerce_monthly_tick_completed with the results Dictionary.


## Drives the four monthly commerce ticks for [param campaign_id]. Returns
## results Dictionary with per-driver counters + the input parameters for
## audit. Emits commerce_monthly_tick_completed on EventBus.
##
## Returns: {
##   campaign_id, calendar_day, year,
##   customs_rolled, ship_gp_debited, merchants_generated, prices_drifted,
## }
##
## v1 contracts:
##   * Empty campaign_id or null rng → returns minimal result with all
##     counters = 0; signal does NOT fire (no work to report).
##   * No domains required — fires on any campaign regardless of domain
##     presence. (DomainHandlers tick used to short-circuit when domains
##     were empty; Wave 5 changes that so commerce ticks fire alone.)
static func process_for_campaign(
		campaign_id: String,
		current_calendar_day: int,
		current_year: int,
		rng: RandomNumberGenerator
) -> Dictionary:
	if campaign_id.is_empty() or rng == null:
		return {
			"campaign_id": campaign_id,
			"calendar_day": current_calendar_day,
			"year": current_year,
			"customs_rolled": 0,
			"ship_gp_debited": 0,
			"merchants_generated": 0,
			"prices_drifted": 0,
			"skipped": true,
		}

	# 1. Annual customs roll — fires at most once per year per campaign.
	#    Self-dedupes via campaigns.last_customs_roll_year (Y-Option 3 per §12).
	var customs_rolled: int = _maybe_roll_annual_customs(campaign_id, current_year)

	# 2. Ship operating costs (cp total debited across all party ships).
	var ship_cp_debited: int = ShipRepository.process_monthly_operating_costs_for_campaign(
		campaign_id, current_calendar_day)

	# 3. Merchant pool refresh.
	var merchants_generated: int = MerchantPoolRepository.process_monthly_refresh_for_campaign(
		campaign_id, current_calendar_day, rng)

	# 4. Market price drift.
	var prices_drifted: int = MarketPriceResolver.process_monthly_drift_for_campaign(
		campaign_id, current_calendar_day, rng)

	var results: Dictionary = {
		"campaign_id": campaign_id,
		"calendar_day": current_calendar_day,
		"year": current_year,
		"customs_rolled": customs_rolled,
		"ship_cp_debited": ship_cp_debited,
		"merchants_generated": merchants_generated,
		"prices_drifted": prices_drifted,
	}
	EventBus.commerce_monthly_tick_completed.emit(campaign_id, results)
	return results


## Year-boundary check for the annual customs roll. Reads
## campaigns.last_customs_roll_year; if the current year is strictly greater,
## fires MarketFeesCalculator.process_annual_customs_roll_for_campaign
## (which updates last_customs_roll_year as part of its work).
##
## Returns the count of settlements whose customs rate was updated, or 0
## if not yet time / skipped.
##
## Per §12.2: this is Y-Option 3 — idempotent across save/load + retroactive
## monthly catch-up. Calling _maybe_roll repeatedly within the same year is
## a no-op once the substrate stamps last_customs_roll_year.
static func _maybe_roll_annual_customs(campaign_id: String, current_year: int) -> int:
	if campaign_id.is_empty() or current_year <= 0:
		return 0
	if not CampaignRepository.db.query_with_bindings(
			"SELECT last_customs_roll_year FROM campaigns WHERE id = ?",
			[campaign_id]):
		return 0
	if CampaignRepository.db.query_result.is_empty():
		return 0
	var last_year: int = int(CampaignRepository.db.query_result[0].get("last_customs_roll_year", 0))
	if current_year <= last_year:
		return 0  # Already rolled this year — no-op.
	return MarketFeesCalculator.process_annual_customs_roll_for_campaign(
		campaign_id, current_year)


## Deterministic RNG seed per (campaign_id, calendar_day) per §11.6. Exposed
## so callers (DomainHandlers + tests) can seed identically.
static func seeded_monthly_rng(campaign_id: String, calendar_day: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("monthly|%s|%d" % [campaign_id, calendar_day])
	return rng
