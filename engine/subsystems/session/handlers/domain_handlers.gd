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

	var domain_results: Array = []
	for domain_data: Dictionary in domains:
		var result := _resolve_domain_month(domain_data)
		domain_results.append(result)

		# Persist updated domain data.
		_save_domain(domain_data, result)

		# Emit domain signals.
		var domain_id: String = domain_data.get("id", "")
		if result.get("net_income", 0) != 0:
			EventBus.income_collected.emit(domain_id, result["net_income"])
		if result.get("morale_change", 0) != 0:
			var old_morale: int = domain_data.get("morale", 0)
			EventBus.domain_morale_changed.emit(domain_id, old_morale, old_morale + result["morale_change"])
		if result.has("domain_event"):
			EventBus.domain_event_occurred.emit(domain_id, result["domain_event"])

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
# Domain resolution (per ACKS rules)
# ---------------------------------------------------------------------------

## Resolve one month for a single domain. Returns a result dictionary.
## This is a simplified initial implementation — full ACKS domain rules
## (Domains at War tables, stronghold upkeep, market trade, etc.) will be
## expanded in future phases.
func _resolve_domain_month(domain_data: Dictionary) -> Dictionary:
	var domain_id: String = domain_data.get("id", "")
	var domain_name: String = domain_data.get("name", "Unknown")
	var territory: String = domain_data.get("territory_type", "wilderness")
	var urban: int = domain_data.get("urban_families", 0)
	var peasant: int = domain_data.get("peasant_families", 0)
	var garrison: int = domain_data.get("garrison_troops", 0)
	var morale: int = domain_data.get("morale", 0)

	# Revenue: ACKS standard is 3-9 gp per peasant family, 6-12 gp per urban family.
	# Simplified: 6 gp/peasant, 9 gp/urban.
	var revenue: int = (peasant * 6) + (urban * 9)

	# Expenses: garrison costs 12 gp per soldier per month (ACKS standard).
	var garrison_cost: int = garrison * 12

	# Stronghold maintenance: placeholder 2% of revenue.
	var maintenance: int = int(float(revenue) * 0.02)

	var total_expenses: int = garrison_cost + maintenance
	var net_income: int = revenue - total_expenses

	# Morale adjustment: positive income → +0, negative → -1 per 1000 gp deficit.
	var morale_change: int = 0
	if net_income < 0:
		morale_change = maxi(-3, net_income / 1000)

	# Population growth: 1d10 families per month in borderlands/wilderness,
	# 2d10 in civilized. Simplified roll.
	var growth_dice: int = 2 if territory == "civilized" else 1
	var growth_roll: RollResult = DiceSystem.roll_digital(10, growth_dice, 0, "domain_growth")
	var population_growth: int = growth_roll.modified_total

	# Domain event: 1-in-6 chance per month.
	var event_roll: RollResult = DiceSystem.roll_digital(6, 1, 0, "domain_event_check")
	var domain_event: Dictionary = {}
	if event_roll.modified_total <= 1:
		# Generate a domain event. Severity 1-3 from 1d6.
		var severity_roll: RollResult = DiceSystem.roll_digital(6, 1, 0, "domain_event_severity")
		var severity: int = 1
		if severity_roll.modified_total >= 5:
			severity = 3
		elif severity_roll.modified_total >= 3:
			severity = 2
		domain_event = {
			"event_type": "random",
			"severity": severity,
			"description": "A domain event of severity %d occurred in %s." % [severity, domain_name],
		}

	return {
		"domain_id": domain_id,
		"domain_name": domain_name,
		"revenue": revenue,
		"garrison_cost": garrison_cost,
		"maintenance": maintenance,
		"total_expenses": total_expenses,
		"net_income": net_income,
		"morale_change": morale_change,
		"population_growth": population_growth,
		"domain_event": domain_event,
	}


## Persist domain updates after monthly resolution.
func _save_domain(domain_data: Dictionary, result: Dictionary) -> void:
	var domain_id: String = domain_data.get("id", "")
	if domain_id.is_empty():
		return

	var new_morale: int = domain_data.get("morale", 0) + result.get("morale_change", 0)
	var new_peasants: int = domain_data.get("peasant_families", 0) + result.get("population_growth", 0)
	var net: int = result.get("net_income", 0)

	CampaignRepository.db.query_with_bindings("""
		UPDATE domains SET
			morale = ?,
			peasant_families = ?,
			revenue_gp = ?,
			expenses_gp = ?,
			net_income_gp = ?,
			domain_xp_this_month = ?,
			updated_at = datetime('now')
		WHERE id = ?
	""", [new_morale, maxi(0, new_peasants), result.get("revenue", 0),
		result.get("total_expenses", 0), net,
		maxi(0, net),  # Domain XP = net income (if positive)
		domain_id])


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
