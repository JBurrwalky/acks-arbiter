class_name DomainHandlers
extends RefCounted

## Event handlers for domain monthly resolution.
##
## Registered globally when a campaign with active domains is loaded.
## The domain_monthly_tick fires on the 1st of each calendar month and
## resolves revenue, expenses, morale, population growth, construction
## progress, and domain encounters per ACKS rules.
##
## Event types handled:
##   "domain_monthly_tick"  — monthly domain cycle resolution


# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------

var _runner = null  # SessionRunner
var _campaign_id: String = ""


func _init(runner) -> void:
	_runner = runner
	_campaign_id = runner.get_campaign_id()


# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------

func register(registry: EventHandlerRegistry) -> void:
	registry.register("domain_monthly_tick", _handle_monthly_tick)


func unregister(registry: EventHandlerRegistry) -> void:
	registry.unregister("domain_monthly_tick")


# ---------------------------------------------------------------------------
# Scheduling helpers
# ---------------------------------------------------------------------------

## Schedule the first domain_monthly_tick at the start of the next month.
## Should be called once during session load if the campaign has domains.
func seed_monthly_tick(scheduler: EventScheduler, party_id: String) -> void:
	var fire_time: int = _rounds_until_next_month()
	if fire_time <= 0:
		# Already at the start of a month — schedule for next month.
		fire_time = Timekeeping.DAYS_PER_MONTH * Timekeeping.ROUNDS_PER_DAY
	# Use absolute time (current + delta).
	var current_time: int = Timekeeping.get_party_time(party_id)
	scheduler.schedule_at(
		current_time + fire_time,
		"domain_monthly_tick",
		"domain_global",  # Not owned by a specific party — world-level event.
		{},
		ScheduledEvent.PRIORITY_ENVIRONMENTAL,
	)


# ---------------------------------------------------------------------------
# Event handler
# ---------------------------------------------------------------------------

## Resolve the monthly domain cycle for all domains in the campaign.
func _handle_monthly_tick(event: ScheduledEvent) -> Dictionary:
	var domains: Array = CampaignRepository.list_campaign_domains(_campaign_id)
	if domains.is_empty():
		# No domains — don't reschedule.
		return {}

	var date: Dictionary = Timekeeping.get_date()
	var month_name := "Month %d, Year %d" % [date.get("month", 1), date.get("year", 1)]
	var calendar_day: int = _calendar_day_from_date(date)

	var domain_results: Array = []
	for domain_data: Dictionary in domains:
		var result := _resolve_domain_month(domain_data, calendar_day)
		domain_results.append(result)
		_save_domain(domain_data, result)
		_emit_signals(domain_data, result)

	# Reschedule for next month.
	var next_month_rounds: int = Timekeeping.DAYS_PER_MONTH * Timekeeping.ROUNDS_PER_DAY
	var next_events := [{
		"fire_time": event.fire_time + next_month_rounds,
		"event_type": "domain_monthly_tick",
		"owner_id": "domain_global",
		"data": {},
		"priority": ScheduledEvent.PRIORITY_ENVIRONMENTAL,
	}]

	return {
		"auto_pause": true,
		"pause_reason": "Domain monthly report — %s" % month_name,
		"next_events": next_events,
		"presentation": {
			"type": "domain_monthly_report",
			"month": month_name,
			"domain_results": domain_results,
		},
	}


# ---------------------------------------------------------------------------
# Domain resolution (per ACKS rules — RAW-correct as of Domain Phase 0)
# ---------------------------------------------------------------------------

## Resolve one month for a single domain by delegating to the Phase 0 resolvers.
## All math lives in the resolvers; this method's job is orchestration plus
## ledger writes plus the random event roll.
func _resolve_domain_month(domain_data: Dictionary, calendar_day: int) -> Dictionary:
	var domain_id: String = domain_data.get("id", "")
	var domain_name: String = domain_data.get("name", "Unknown")
	var territory: String = String(domain_data.get("territory_type", "wilderness"))

	# --- Context: hexes, stronghold, ruler, additional garrison ---
	var hexes: Array = CampaignRepository.get_domain_hexes(domain_id)
	var hex_count: int = hexes.size()
	var stronghold_value_gp: int = _stub_stronghold_value(domain_id)
	var stronghold_minimum_gp: int = _classification_minimum_gp(territory, hex_count)
	var ruler: Dictionary = _build_ruler_context(domain_data)
	var actual_garrison_paid_gp: int = int(domain_data.get("garrison_troops", 0)) \
		* DomainExpenseCalculator.GARRISON_MIN_GP_PER_FAMILY
	var additional_garrison_gp_per_family: int = _additional_garrison_per_family(
		domain_data, actual_garrison_paid_gp)
	var tribute_in: int = 0  # Phase 6 fills this in via tribute_calculator
	var investment_gp: int = 0  # Phase 3 activity feeds this in

	# --- Resolvers: revenue → expenses → morale → growth → classification ---
	var revenue := DomainRevenueCalculator.calculate_monthly_revenue(
		domain_data, hexes, stronghold_value_gp, stronghold_minimum_gp, tribute_in)
	var expenses := DomainExpenseCalculator.calculate_monthly_expenses(
		domain_data, actual_garrison_paid_gp, revenue["income_gate_active"])

	var base_morale := DomainMoraleResolver.resolve_base_morale(
		domain_data, ruler, revenue["total"],
		stronghold_value_gp, stronghold_minimum_gp,
		additional_garrison_gp_per_family)

	var event_modifiers_sum: int = _event_modifiers_sum(domain_data, expenses)
	var repression_bonus: int = int(domain_data.get(
		"repression_gp_per_family_this_month", 0))
	var is_repressed: bool = bool(domain_data.get(
		"is_repressed_this_month", 0))
	var morale_roll: int = DiceSystem.roll_digital(6, 2, 0, "domain_morale").modified_total
	var morale := DomainMoraleResolver.resolve_current_morale(
		domain_data, base_morale, event_modifiers_sum,
		repression_bonus, is_repressed, morale_roll)

	var morale_tier: String = DomainMoraleResolver.morale_tier(morale["current_morale"])
	var growth := DomainGrowthResolver.resolve_growth(
		domain_data, revenue["total"], investment_gp, morale_tier,
		bool(domain_data.get("is_active_adventuring_this_month", 0)),
		revenue["income_gate_active"])

	var class_change := ClassificationAdvancement.check_classification_change(
		domain_data, hex_count, _has_urban_settlement(domain_data),
		_urban_pct_of_peasants(domain_data),
		_distance_to_friendly_city(domain_data),
		_contiguous_expansion_blocked(domain_data))

	# --- Ledger writes (one row per nonzero subcategory) ---
	if not domain_id.is_empty():
		_write_revenue_ledger(domain_id, calendar_day, revenue)
		_write_expense_ledger(domain_id, calendar_day, expenses)

	# --- Random event roll (kept simple in Phase 0; Phase 8 replaces this) ---
	var domain_event: Dictionary = _maybe_generate_event(domain_name)

	var net_income: int = revenue["total"] - expenses["total"]
	return {
		"domain_id": domain_id,
		"domain_name": domain_name,
		"revenue": revenue["total"],
		"revenue_breakdown": revenue,
		"garrison_cost": expenses["garrison"],
		"maintenance": expenses["maintenance"],
		"total_expenses": expenses["total"],
		"expense_breakdown": expenses,
		"net_income": net_income,
		"base_morale": base_morale,
		"morale_change": morale["morale_change"],
		"current_morale": morale["current_morale"],
		"morale_tier": morale_tier,
		"morale_roll": morale,
		"population_growth": growth["net_change"],
		"growth_breakdown": growth,
		"classification_change": class_change,
		"domain_event": domain_event,
		"income_gate_active": revenue["income_gate_active"],
	}


## Persist domain updates after monthly resolution.
func _save_domain(domain_data: Dictionary, result: Dictionary) -> void:
	var domain_id: String = domain_data.get("id", "")
	if domain_id.is_empty():
		return

	var net: int = result.get("net_income", 0)
	var prior_peasants: int = int(domain_data.get("peasant_families", 0))
	var new_peasants: int = maxi(0, prior_peasants + int(result.get("population_growth", 0)))
	var class_change: Dictionary = result.get("classification_change", {})
	var new_territory: String = String(class_change.get(
		"new_classification", domain_data.get("territory_type", "wilderness")))
	var prior_treasury: int = int(domain_data.get("treasury_gp", 0))
	var new_treasury: int = prior_treasury + net

	var fields := {
		"morale": result.get("current_morale", domain_data.get("morale", 0)),
		"peasant_families": new_peasants,
		"treasury_gp": new_treasury,
		"revenue_gp": result.get("revenue", 0),
		"expenses_gp": result.get("total_expenses", 0),
		"net_income_gp": net,
		"domain_xp_this_month": maxi(0, net),
		"territory_type": new_territory,
	}
	CampaignRepository.update_domain_monthly_state(domain_id, fields)


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

func _emit_signals(domain_data: Dictionary, result: Dictionary) -> void:
	var domain_id: String = domain_data.get("id", "")
	if domain_id.is_empty():
		return

	var net: int = result.get("net_income", 0)
	if net != 0:
		EventBus.income_collected.emit(domain_id, net)

	var prior_morale: int = int(domain_data.get("morale", 0))
	var current_morale: int = int(result.get("current_morale", prior_morale))
	if current_morale != prior_morale:
		EventBus.domain_morale_changed.emit(domain_id, prior_morale, current_morale)

	if net != 0:
		var prior_treasury: int = int(domain_data.get("treasury_gp", 0))
		EventBus.domain_treasury_changed.emit(domain_id, prior_treasury, prior_treasury + net)

	var class_change: Dictionary = result.get("classification_change", {})
	var prior_class: String = String(domain_data.get("territory_type", "wilderness"))
	if bool(class_change.get("advanced", false)):
		EventBus.classification_advanced.emit(domain_id, prior_class,
			String(class_change["new_classification"]))
	elif bool(class_change.get("regressed", false)):
		EventBus.classification_regressed.emit(domain_id, prior_class,
			String(class_change["new_classification"]))

	var domain_event: Dictionary = result.get("domain_event", {})
	if not domain_event.is_empty():
		EventBus.domain_event_occurred.emit(domain_id, domain_event)


# ---------------------------------------------------------------------------
# Ledger writes
# ---------------------------------------------------------------------------

func _write_revenue_ledger(domain_id: String, calendar_day: int, revenue: Dictionary) -> void:
	for sub: String in ["service", "tax", "land"]:
		var amount: int = int(revenue.get(sub, 0))
		if amount != 0:
			CampaignRepository.add_ledger_entry({
				"domain_id": domain_id, "calendar_day": calendar_day,
				"category": "revenue", "subcategory": sub,
				"gp_amount": amount, "description": "",
			})
	var tin: int = int(revenue.get("tribute_in", 0))
	if tin != 0:
		CampaignRepository.add_ledger_entry({
			"domain_id": domain_id, "calendar_day": calendar_day,
			"category": "tribute_in", "subcategory": "vassal_tribute",
			"gp_amount": tin, "description": "",
		})


func _write_expense_ledger(domain_id: String, calendar_day: int, expenses: Dictionary) -> void:
	for sub: String in ["garrison", "liturgy", "maintenance", "tithe", "repression"]:
		var amount: int = int(expenses.get(sub, 0))
		if amount != 0:
			CampaignRepository.add_ledger_entry({
				"domain_id": domain_id, "calendar_day": calendar_day,
				"category": "expense", "subcategory": sub,
				"gp_amount": amount, "description": "",
			})
	var tout: int = int(expenses.get("tribute_out", 0))
	if tout != 0:
		CampaignRepository.add_ledger_entry({
			"domain_id": domain_id, "calendar_day": calendar_day,
			"category": "tribute_out", "subcategory": "liege_tribute",
			"gp_amount": tout, "description": "",
		})


# ---------------------------------------------------------------------------
# Resolver inputs (helpers)
# ---------------------------------------------------------------------------

## Sum the gp_value of completed strongholds in a domain. Phase 1 wired this
## via `StrongholdRepository.get_stronghold_value_for_domain`; Phase 2+
## may add caching or contiguous-territory enforcement at this seam.
func _stub_stronghold_value(domain_id: String) -> int:
	return StrongholdRepository.get_stronghold_value_for_domain(domain_id)


## Per-hex classification minimums per `acore_axioms` §minimum_stronghold_value
## L88-94. Total = per_hex_minimum × hex_count.
func _classification_minimum_gp(territory_type: String, hex_count: int) -> int:
	var per_hex: int = 0
	match territory_type:
		"civilized":   per_hex = 15000
		"borderlands": per_hex = 22500
		"wilderness":  per_hex = 32000
		_:             per_hex = 32000
	return per_hex * maxi(1, hex_count)


## Build the ruler context dict the morale resolver expects. Looks up CHA mod,
## level, leadership proficiency, and alignment from the ruler character row.
func _build_ruler_context(domain_data: Dictionary) -> Dictionary:
	var ruler_id: String = String(domain_data.get("owner_character_id", ""))
	if ruler_id.is_empty():
		return {}
	var character: Dictionary = CampaignRepository.get_character(ruler_id)
	if character.is_empty():
		return {}
	# CHA modifier — characters store ability scores 3-18; convert to ACKS adj.
	var cha: int = int(character.get("cha", 10))
	return {
		"cha_modifier": _cha_modifier(cha),
		"level": int(character.get("level", 1)),
		"has_leadership_proficiency": _has_leadership_proficiency(ruler_id),
		"alignment": String(character.get("alignment", "neutral")),
	}


## ACKS ability modifier: 3 → -3; 4-5 → -2; 6-8 → -1; 9-12 → 0;
## 13-15 → +1; 16-17 → +2; 18 → +3 per `acore_*` ability tables.
func _cha_modifier(cha: int) -> int:
	if cha <= 3:   return -3
	elif cha <= 5: return -2
	elif cha <= 8: return -1
	elif cha <= 12: return 0
	elif cha <= 15: return 1
	elif cha <= 17: return 2
	return 3


func _has_leadership_proficiency(character_id: String) -> bool:
	if character_id.is_empty():
		return false
	if not CampaignRepository.db.query_with_bindings("""
		SELECT 1 FROM character_proficiencies
		WHERE character_id = ? AND proficiency_id = 'leadership'
		LIMIT 1
	""", [character_id]):
		return false
	return not CampaignRepository.db.query_result.is_empty()


## Phase 0: Phase 5 will compute (paid_garrison_gp - 2gp/family × peasants) /
## peasants. For now we have no troop_units table feeding the handler, so
## additional garrison is whatever the ruler over-paid above the universal
## 2gp/fam minimum, divided by peasant families.
func _additional_garrison_per_family(
	domain_data: Dictionary,
	actual_garrison_paid_gp: int
) -> int:
	var peasants: int = int(domain_data.get("peasant_families", 0))
	if peasants <= 0:
		return 0
	var minimum: int = peasants * DomainExpenseCalculator.GARRISON_MIN_GP_PER_FAMILY
	var extra: int = maxi(0, actual_garrison_paid_gp - minimum)
	return extra / peasants  # integer truncation; +1 morale at 1+ extra


## Sum the morale roll modifiers driven by the current month's domain settings.
## Per §monthly_event_modifiers L488-499. Phase 0 wires up the modifiers we can
## compute deterministically (tax, liturgy, tithes, garrison underpayment).
## Pillage / occupation / new-religion are deferred to Phase 8 / Phase 10.
func _event_modifiers_sum(domain_data: Dictionary, expenses: Dictionary) -> int:
	var sum: int = 0
	var liturgy_rate: int = int(domain_data.get("liturgy_rate_gp_per_family", 1))
	# Liturgy bonus/penalty per L492-493 (1 gp/fam baseline).
	sum += (liturgy_rate - 1)
	# Tax bonus/penalty per L494-495 (2 gp/fam baseline; raising taxes harms,
	# lowering helps).
	var tax_rate: int = int(domain_data.get("tax_rate_gp_per_family", 2))
	sum += (2 - tax_rate)
	# Garrison underpayment: -1 per gp below the 2 gp/fam minimum. Since the
	# expense calculator clamps actual garrison to the minimum, this only
	# fires if the caller supplied an `actual_garrison_paid_gp` below that —
	# Phase 0 always pays the minimum so this evaluates to 0.
	var peasants: int = int(domain_data.get("peasant_families", 0))
	var garrison: int = int(expenses.get("garrison", peasants * DomainExpenseCalculator.GARRISON_MIN_GP_PER_FAMILY))
	var min_garrison: int = peasants * DomainExpenseCalculator.GARRISON_MIN_GP_PER_FAMILY
	if garrison < min_garrison and peasants > 0:
		sum -= int(ceil(float(min_garrison - garrison) / float(peasants)))
	return sum


# Phase 0 simplifications — Phase 2+ will surface real values.
func _has_urban_settlement(_domain_data: Dictionary) -> bool:
	return false


func _urban_pct_of_peasants(domain_data: Dictionary) -> int:
	var peasants: int = int(domain_data.get("peasant_families", 0))
	var urban: int = int(domain_data.get("urban_families", 0))
	if peasants <= 0:
		return 0
	return int(round(100.0 * float(urban) / float(peasants)))


func _distance_to_friendly_city(_domain_data: Dictionary) -> int:
	return 0  # Phase 2+ replaces with an actual hex-distance lookup


func _contiguous_expansion_blocked(_domain_data: Dictionary) -> bool:
	return false  # Phase 2+ replaces with terrain / neighbor analysis


# ---------------------------------------------------------------------------
# Random event roll (Phase 0 placeholder; Phase 8 replaces with full table)
# ---------------------------------------------------------------------------

func _maybe_generate_event(domain_name: String) -> Dictionary:
	var event_roll: RollResult = DiceSystem.roll_digital(6, 1, 0, "domain_event_check")
	if event_roll.modified_total > 1:
		return {}
	var severity_roll: RollResult = DiceSystem.roll_digital(6, 1, 0, "domain_event_severity")
	var severity: int = 1
	if severity_roll.modified_total >= 5:
		severity = 3
	elif severity_roll.modified_total >= 3:
		severity = 2
	return {
		"event_type": "random",
		"severity": severity,
		"description": "A domain event of severity %d occurred in %s." % [severity, domain_name],
	}


# ---------------------------------------------------------------------------
# Date helper
# ---------------------------------------------------------------------------

## Convert a Timekeeping date dict into a single integer day-of-campaign for
## ledger entries (year × 12 × DAYS_PER_MONTH + month-1 × DAYS_PER_MONTH + day).
func _calendar_day_from_date(date: Dictionary) -> int:
	var year: int = int(date.get("year", 1))
	var month: int = int(date.get("month", 1))
	var day: int = int(date.get("day", 1))
	return ((year - 1) * 12 + (month - 1)) * Timekeeping.DAYS_PER_MONTH + day


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

## Calculate rounds from now until the start of the next calendar month.
func _rounds_until_next_month() -> int:
	var date: Dictionary = Timekeeping.get_date()
	var current_day: int = date.get("day", 1)  # 1-28
	var days_remaining: int = Timekeeping.DAYS_PER_MONTH - current_day + 1
	# Subtract the elapsed portion of today.
	var hour: int = date.get("hour", 0)
	var minute: int = date.get("minute", 0)
	var rnd: int = date.get("round", 0)
	var rounds_elapsed_today: int = (hour * Timekeeping.ROUNDS_PER_HOUR) + \
		(minute * Timekeeping.ROUNDS_PER_MINUTE) + rnd
	return (days_remaining * Timekeeping.ROUNDS_PER_DAY) - rounds_elapsed_today
