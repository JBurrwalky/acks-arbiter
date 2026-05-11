class_name MarketClassModifierResolver
extends RefCounted

## Manages temporary market-class shifts from the Vagaries-of-Recruitment +
## Vagaries-of-War tables (Phase 7 carry-forward, replacing the prior
## signal-only stubs).
##
## Sources handled:
##   - vagary_recruitment_commerce_disrupted: largest urban settlement treated
##     as 1 market class smaller for 1d6 months (RAW daw_vagaries L867).
##   - vagary_recruitment_commerce_improves: largest urban settlement treated
##     as 1 market class larger for 1d6 months (L871).
##   - vagary_war_war_profiteers: artillery / armor / mounts / supplies /
##     weapons cost +10% (cumulative on each repeat) for 1d4 seasons
##     (L210 in vagaries_of_war + L868 in vagaries_of_recruitment).
##
## Public API:
##   apply_commerce_disrupted(campaign_id, settlement_id, calendar_day, dice = null) -> Dictionary
##   apply_commerce_improves(campaign_id, settlement_id, calendar_day, dice = null) -> Dictionary
##   apply_war_profiteers(campaign_id, settlement_id, calendar_day, dice = null) -> Dictionary
##   effective_market_class(settlement_id) -> int
##     Returns base class + sum(active deltas), clamped 1..6.
##   expire_modifiers(campaign_id, calendar_day) -> int
##     Calls DomainThreatRepository.expire_modifiers_for_campaign;
##     intended for the monthly-tick orchestrator.

const _MIN_CLASS := 1
const _MAX_CLASS := 6


# ---------------------------------------------------------------------------
# Apply handlers
# ---------------------------------------------------------------------------

static func apply_commerce_disrupted(
	campaign_id: String,
	settlement_id: String,
	calendar_day: int,
	dice = null
) -> Dictionary:
	## RAW daw_vagaries L867: "Largest urban settlement treated as 1 market
	## class smaller for 1d6 months."
	var months: int = _roll_die(6, dice)
	var expires: int = calendar_day + months * Timekeeping.DAYS_PER_MONTH
	var id: String = DomainThreatRepository.create_market_modifier({
		"campaign_id": campaign_id,
		"settlement_entrance_id": settlement_id,
		"source_kind": "vagary_recruitment_commerce_disrupted",
		"delta": -1,
		"price_multiplier_pct": 100,
		"affected_categories": "",
		"issued_calendar_day": calendar_day,
		"expires_calendar_day": expires,
	})
	if EventBus.has_signal("market_class_modifier_applied"):
		EventBus.emit_signal("market_class_modifier_applied",
			settlement_id, -1, expires)
	return {
		"success": not id.is_empty(),
		"modifier_id": id,
		"delta": -1,
		"duration_months": months,
		"expires_calendar_day": expires,
	}


static func apply_commerce_improves(
	campaign_id: String,
	settlement_id: String,
	calendar_day: int,
	dice = null
) -> Dictionary:
	## RAW daw_vagaries L871: "Largest urban settlement treated as 1 market
	## class larger for 1d6 months."
	var months: int = _roll_die(6, dice)
	var expires: int = calendar_day + months * Timekeeping.DAYS_PER_MONTH
	var id: String = DomainThreatRepository.create_market_modifier({
		"campaign_id": campaign_id,
		"settlement_entrance_id": settlement_id,
		"source_kind": "vagary_recruitment_commerce_improves",
		"delta": 1,
		"price_multiplier_pct": 100,
		"affected_categories": "",
		"issued_calendar_day": calendar_day,
		"expires_calendar_day": expires,
	})
	if EventBus.has_signal("market_class_modifier_applied"):
		EventBus.emit_signal("market_class_modifier_applied",
			settlement_id, 1, expires)
	return {
		"success": not id.is_empty(),
		"modifier_id": id,
		"delta": 1,
		"duration_months": months,
		"expires_calendar_day": expires,
	}


static func apply_war_profiteers(
	campaign_id: String,
	settlement_id: String,
	calendar_day: int,
	dice = null
) -> Dictionary:
	## RAW vagaries_of_war L210 + vagaries_of_recruitment L868:
	## "Artillery / armor / mounts / supplies / weapons cost +10%
	## (cumulative on each repeat) for 1d4 seasons."
	var seasons: int = _roll_die(4, dice)
	# 1 season = 3 months in ACKS calendar. Approximate as 90 days.
	var expires: int = calendar_day + seasons * 3 * Timekeeping.DAYS_PER_MONTH
	var id: String = DomainThreatRepository.create_market_modifier({
		"campaign_id": campaign_id,
		"settlement_entrance_id": settlement_id,
		"source_kind": "vagary_war_war_profiteers",
		"delta": 0,  # market class unaffected; only price multiplier
		"price_multiplier_pct": 110,
		"affected_categories": "artillery,armor,mounts,supplies,weapons",
		"issued_calendar_day": calendar_day,
		"expires_calendar_day": expires,
	})
	return {
		"success": not id.is_empty(),
		"modifier_id": id,
		"price_multiplier_pct": 110,
		"affected_categories": "artillery,armor,mounts,supplies,weapons",
		"duration_seasons": seasons,
		"expires_calendar_day": expires,
	}


# ---------------------------------------------------------------------------
# Effective lookups
# ---------------------------------------------------------------------------

static func effective_market_class(settlement_id: String) -> int:
	if settlement_id.is_empty():
		return 6  # default class VI
	if not CampaignRepository.db.query_with_bindings(
		"SELECT market_class FROM settlement_entrances WHERE id = ?", [settlement_id]):
		return 6
	if CampaignRepository.db.query_result.is_empty():
		return 6
	var base_class: int = int(CampaignRepository.db.query_result[0].get("market_class", 6))
	var delta: int = DomainThreatRepository.sum_market_class_delta(settlement_id)
	return clampi(base_class + delta, _MIN_CLASS, _MAX_CLASS)


static func price_multiplier_for_category(settlement_id: String, category: String) -> int:
	## Compound multiplier (in percent) of all active war_profiteers modifiers
	## affecting this settlement + category. 100 = no change.
	return DomainThreatRepository.sum_price_multiplier_pct(settlement_id, category)


static func expire_modifiers(campaign_id: String, calendar_day: int) -> int:
	return DomainThreatRepository.expire_modifiers_for_campaign(campaign_id, calendar_day)


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _roll_die(sides: int, dice) -> int:
	if dice != null and dice.has_method("roll"):
		return int(dice.roll(1, sides))
	return randi_range(1, sides)
