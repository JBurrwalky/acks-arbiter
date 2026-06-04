class_name CommissionPipeline
extends RefCounted

## Stronghold construction commission lifecycle manager.
##
## Owns the DAILY-tick handler that advances all in-progress commissions and
## fires milestone signals (`stronghold_construction_progressed` for halfway
## and completed crossings, `stronghold_completed` on completion). Daily
## granularity is required by `acore_stronghold_construction_costs.pdf`
## (1 day per 500 gp); a monthly tick would lose 27 days of resolution.
##
## Integrates with the session_runner load path matching `DomainHandlers`:
##   var _commission_pipeline = CommissionPipeline.new(self)
##   _commission_pipeline.register(_handler_registry)
##   _commission_pipeline.seed_construction_tick(_scheduler, party_id)


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
	registry.register("stronghold_construction_daily_tick", _handle_daily_tick)


func unregister(registry: EventHandlerRegistry) -> void:
	registry.unregister("stronghold_construction_daily_tick")


# ---------------------------------------------------------------------------
# Scheduling helpers
# ---------------------------------------------------------------------------

## Schedule the first stronghold_construction_daily_tick at the start of the
## next game day. Should be called once during session load if the campaign
## has any active commissions (or pre-emptively to ensure new commissions
## get picked up). owner_id is "stronghold_global" — strongholds advance
## independent of party context.
func seed_construction_tick(scheduler: EventScheduler, party_id: String) -> void:
	var fire_time: int = _rounds_until_next_day()
	if fire_time <= 0:
		fire_time = Timekeeping.ROUNDS_PER_DAY
	var current_time: int = Timekeeping.get_party_time(party_id)
	scheduler.schedule_at(
		current_time + fire_time,
		"stronghold_construction_daily_tick",
		"stronghold_global",
		{},
		ScheduledEvent.PRIORITY_ENVIRONMENTAL,
	)


# ---------------------------------------------------------------------------
# Public API: starting a commission
# ---------------------------------------------------------------------------

## Start a construction commission. Validates engineer count and class location
## restrictions before committing. Creates the strongholds row + the
## stronghold_commissions row (in two sequential CRUD calls; SQLite atomicity
## is per-statement, so test fixtures that hit a rollback path should rely on
## the wrapper instead).
##
## Returns Dictionary with keys:
##   stronghold_id: String                  — empty on validation failure
##   commission_id: String                  — empty on validation failure
##   expected_halfway_day: int
##   expected_completion_day: int
##   errors: Array[String]                  — empty on success; codes per
##                                            StrongholdCostCalculator.validate_*
static func start_commission(
	stronghold_data: Dictionary,
	cost_breakdown: Dictionary,
	started_calendar_day: int,
	territory_type: String = "wilderness",
	territory_predominant_race: String = "human",
	is_underground: bool = false
) -> Dictionary:
	var errors: Array[String] = []

	# Class location validation.
	var location_errors: Array = StrongholdCostCalculator.validate_class_location(
		String(stronghold_data.get("archetype_power_id", "")),
		territory_type,
		territory_predominant_race,
		is_underground)
	for e in location_errors:
		errors.append(String(e))

	# Engineer requirement validation. Calculator returns gp values; convert at
	# the column-write boundary (cp columns since Migration 115).
	var gp_committed: int = int(cost_breakdown.get("gp_committed", 0))
	var cp_committed: int = gp_committed * 100
	var engineers_assigned: int = int(stronghold_data.get("engineers_assigned",
		cost_breakdown.get("engineers_required", 1)))
	if not StrongholdCostCalculator.validate_engineer_requirement(
			gp_committed, engineers_assigned):
		errors.append("insufficient_engineers")

	# Thief→Syndicate refactor: the three syndicate classes (thief / assassin /
	# elven nightblade) cannot build a domain-securing stronghold. A thief's
	# hideout is its own structure (HideoutRepository), never a strongholds row.
	# Belt-and-suspenders engine guard; the UI hides the commission path for them.
	# owner_character_id may be a literal null (nullable FK) — guard String(null).
	var owner_value: Variant = stronghold_data.get("owner_character_id", "")
	var owner_id: String = String(owner_value) if owner_value != null else ""
	if not owner_id.is_empty():
		var owner_class: String = String(
			CampaignRepository.get_character(owner_id).get("character_class", ""))
		if ClassBucketResolver.is_syndicate_class(owner_class):
			errors.append("syndicate_class_cannot_build_stronghold")
		elif ClassBucketResolver.is_venturer_class(owner_class):
			# Venturer→Guildhouse refactor: a Venturer's guildhouse is its own
			# entity (GuildhouseRepository), never a domain-securing stronghold.
			errors.append("venturer_class_cannot_build_stronghold")

	if not errors.is_empty():
		return {
			"stronghold_id": "",
			"commission_id": "",
			"expected_halfway_day": 0,
			"expected_completion_day": 0,
			"errors": errors,
		}

	# Phase 1: store the structure base cost as the stronghold's cp_value
	# (the value that drives sufficiency) — speed-tier premium and class
	# discount don't affect the security value, only the price paid.
	# Migration 116: cost_breakdown values are gp; multiply × 100 at the
	# column-write boundary.
	var sufficiency_gp_value: int = int(cost_breakdown.get("base_structure_cost", 0)) \
		+ int(cost_breakdown.get("accessory_cost", 0))
	var sufficiency_cp_value: int = sufficiency_gp_value * 100

	var stronghold_id: String = CampaignRepository.create_stronghold({
		"domain_id": stronghold_data.get("domain_id", null),
		"owner_character_id": stronghold_data.get("owner_character_id", null),
		"archetype": stronghold_data.get("archetype", "fortress"),
		"archetype_power_id": stronghold_data.get("archetype_power_id", ""),
		"structure_type": stronghold_data.get("structure_type", "keep"),
		"cp_value": sufficiency_cp_value,
		"shp": int(stronghold_data.get("shp", 0)),
		"ac": int(stronghold_data.get("ac", 6)),
		"garrison_capacity": int(stronghold_data.get("garrison_capacity", 0)),
		"completion_pct": 0,
		"is_conforming_to_class": stronghold_data.get("is_conforming_to_class", true),
		"is_claimed": false,
		"claimed_from_source": "",
		"location_map_id": stronghold_data.get("location_map_id", null),
		"location_hex_q": stronghold_data.get("location_hex_q", null),
		"location_hex_r": stronghold_data.get("location_hex_r", null),
		"status": "in_progress",
	})
	if stronghold_id.is_empty():
		errors.append("create_stronghold_failed")
		return {
			"stronghold_id": "", "commission_id": "",
			"expected_halfway_day": 0, "expected_completion_day": 0,
			"errors": errors,
		}

	var daily_rate_gp: int = int(cost_breakdown.get("daily_construction_rate_gp", 500))
	var daily_rate_cp: int = daily_rate_gp * 100
	var duration_days: int = int(cost_breakdown.get("estimated_duration_days", 0))
	if duration_days <= 0 and daily_rate_gp > 0:
		duration_days = int(ceil(float(gp_committed) / float(daily_rate_gp)))
	var halfway_days: int = int(ceil(float(duration_days) / 2.0))
	var expected_halfway_day: int = started_calendar_day + halfway_days
	var expected_completion_day: int = started_calendar_day + duration_days

	var commission_id: String = CampaignRepository.create_commission({
		"stronghold_id": stronghold_id,
		"cp_committed": cp_committed,
		"daily_construction_rate_cp": daily_rate_cp,
		"speed_tier_pct": int(cost_breakdown.get("speed_tier_pct", 100)),
		"engineers_required": int(cost_breakdown.get("engineers_required", 1)),
		"engineers_assigned": engineers_assigned,
		"engineer_monthly_wage_cp": int(cost_breakdown.get("engineer_monthly_wage_cp", 25000)),
		"supervisor_character_id": stronghold_data.get("supervisor_character_id", null),
		"magic_rate_modifier_pct": int(cost_breakdown.get("magic_rate_modifier_pct", 100)),
		"materials_strategy": stronghold_data.get("materials_strategy", "local"),
		"class_cost_reduction_pct": int(cost_breakdown.get("class_cost_reduction_pct", 0)),
		"started_calendar_day": started_calendar_day,
		"expected_halfway_day": expected_halfway_day,
		"expected_completion_day": expected_completion_day,
		"cp_progressed": 0,
		"halfway_signal_fired": false,
		"status": "in_progress",
	})

	if not commission_id.is_empty():
		EventBus.stronghold_commission_started.emit(
			stronghold_id, String(stronghold_data.get("domain_id", "")),
			cp_committed, expected_completion_day)

	return {
		"stronghold_id": stronghold_id,
		"commission_id": commission_id,
		"expected_halfway_day": expected_halfway_day,
		"expected_completion_day": expected_completion_day,
		"errors": [],
	}


# ---------------------------------------------------------------------------
# Public API: daily advancement
# ---------------------------------------------------------------------------

## Advance every in-progress commission by one game day. For each commission:
##   1. Add daily_construction_rate_cp to cp_progressed.
##   2. If cp_progressed crosses 50% cp_committed and not halfway_signal_fired,
##      mark halfway_signal_fired=1, update strongholds.completion_pct=50, and
##      emit `stronghold_construction_progressed(stronghold_id, 50, "halfway")`.
##   3. If cp_progressed reaches cp_committed, set status='completed', set
##      completed_calendar_day=today, update strongholds.status='completed'
##      and completion_pct=100, emit
##      `stronghold_construction_progressed(stronghold_id, 100, "completed")`,
##      `stronghold_completed(stronghold_id)`, and call
##      `StrongholdRepository.recompute_sufficiency_after_change(domain_id)`
##      (which may emit `stronghold_sufficiency_changed`).
## Returns Array of milestone events for caller bookkeeping: each entry is
##   {commission_id, stronghold_id, milestone, completion_pct, domain_id}
static func advance_commissions(today_calendar_day: int) -> Array:
	var milestones: Array = []
	var commissions: Array = CampaignRepository.list_active_commissions()
	for commission: Dictionary in commissions:
		var commission_id: String = String(commission.get("id", ""))
		var stronghold_id: String = String(commission.get("stronghold_id", ""))
		if commission_id.is_empty() or stronghold_id.is_empty():
			continue

		var rate: int = int(commission.get("daily_construction_rate_cp", 50000))
		var prior_progressed: int = int(commission.get("cp_progressed", 0))
		var cp_committed: int = int(commission.get("cp_committed", 0))
		var new_progressed: int = mini(prior_progressed + rate, cp_committed)
		var halfway_threshold: int = int(ceil(float(cp_committed) / 2.0))
		var halfway_was_fired: bool = bool(commission.get("halfway_signal_fired", false))

		var sh_row: Dictionary = CampaignRepository.get_stronghold(stronghold_id)
		var domain_id: String = String(sh_row.get("domain_id", ""))

		# Detect crossings (without yet writing).
		var fires_halfway: bool = (not halfway_was_fired) \
			and (new_progressed >= halfway_threshold)
		var fires_completion: bool = (new_progressed >= cp_committed)

		# Single commission update per iteration — coalesces all field changes
		# (cp_progressed always; halfway/completion flags as needed).
		var commission_fields: Dictionary = {"cp_progressed": new_progressed}
		if fires_halfway or fires_completion:
			commission_fields["halfway_signal_fired"] = true
		if fires_completion:
			commission_fields["completed_calendar_day"] = today_calendar_day
			commission_fields["status"] = "completed"
		CampaignRepository.update_commission(commission_id, commission_fields)

		# Stronghold-side denormalized cache update (only on crossings).
		if fires_completion:
			CampaignRepository.update_stronghold(stronghold_id, {
				"completion_pct": 100,
				"status": "completed",
			})
		elif fires_halfway:
			CampaignRepository.update_stronghold(stronghold_id, {
				"completion_pct": 50,
			})

		# Signals (after writes are in place).
		if fires_halfway:
			EventBus.stronghold_construction_progressed.emit(
				stronghold_id, 50, "halfway")
			milestones.append({
				"commission_id": commission_id,
				"stronghold_id": stronghold_id,
				"milestone": "halfway",
				"completion_pct": 50,
				"domain_id": domain_id,
			})
		if fires_completion:
			EventBus.stronghold_construction_progressed.emit(
				stronghold_id, 100, "completed")
			EventBus.stronghold_completed.emit(stronghold_id)
			if not domain_id.is_empty():
				StrongholdRepository.recompute_sufficiency_after_change(domain_id)
			milestones.append({
				"commission_id": commission_id,
				"stronghold_id": stronghold_id,
				"milestone": "completed",
				"completion_pct": 100,
				"domain_id": domain_id,
			})

	return milestones


## Apply a percentage bonus to a commission's daily construction rate.
## Called by Phase 3's oversee_construction (+5%) and supervise_construction
## (+10%) handlers per `ax_campaign_play.xml` §oversee_construction L661-672.
##
## The bonus stacks ON TOP of the current rate (i.e. +5% means the new rate
## is 1.05× the previous rate, not 1.05× the base rate). Returns the new
## daily_construction_rate_cp; returns 0 if the commission is missing or no
## longer in_progress. Banker's rounding via XPAwardCalculator.
##
## bonus_pct is an integer percentage (5, 10, etc.). Negative bonuses are
## rejected (this is a one-way bump; rate decreases happen via engineer
## departure or commission pause).
static func bump_daily_construction_rate(commission_id: String, bonus_pct: int) -> int:
	if commission_id.is_empty() or bonus_pct <= 0:
		return 0
	var commission: Dictionary = CampaignRepository.get_commission(commission_id)
	if commission.is_empty():
		return 0
	if String(commission.get("status", "")) != "in_progress":
		return 0
	var prior_rate: int = int(commission.get("daily_construction_rate_cp", 0))
	if prior_rate <= 0:
		return 0
	var new_rate: int = XPAwardCalculator.bankers_round(
		float(prior_rate) * (1.0 + float(bonus_pct) / 100.0))
	if new_rate == prior_rate:
		# Banker's rounding collapsed the bump (rate too small for rounding to
		# bite). Force at least +1 cp/day so successive Phase 3 supervisors
		# accumulate progress.
		new_rate = prior_rate + 1
	CampaignRepository.update_commission(commission_id, {
		"daily_construction_rate_cp": new_rate,
	})
	return new_rate


## Returns the in-progress commission for a given domain, or empty Dict if
## the domain has no active construction. Used by Phase 3's oversee /
## supervise construction handlers to find the commission to bump.
static func get_in_progress_commission_for_domain(domain_id: String) -> Dictionary:
	if domain_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings("""
		SELECT c.* FROM stronghold_commissions c
		JOIN strongholds s ON s.id = c.stronghold_id
		WHERE s.domain_id = ? AND c.status = 'in_progress'
		ORDER BY c.expected_completion_day
		LIMIT 1
	""", [domain_id]):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


## Re-check engineer requirement for a single commission and pause if
## insufficient. Called when an engineer departs (Phase 5 henchman lifecycle)
## or when the commission loads on session start. Returns true if paused.
static func recheck_engineer_requirement(commission_id: String) -> bool:
	var commission: Dictionary = CampaignRepository.get_commission(commission_id)
	if commission.is_empty():
		return false
	var assigned: int = int(commission.get("engineers_assigned", 0))
	# Calculator works in gp; convert from the now-cp column.
	var cp_committed: int = int(commission.get("cp_committed", 0))
	var gp_committed: int = cp_committed / 100
	if not StrongholdCostCalculator.validate_engineer_requirement(gp_committed, assigned):
		CampaignRepository.update_commission(commission_id, {
			"status": "paused_engineers",
		})
		return true
	return false


# ---------------------------------------------------------------------------
# Event handler
# ---------------------------------------------------------------------------

## Daily tick handler. Advances all in-progress commissions (which emits
## milestone signals via `advance_commissions`) and reschedules itself for
## tomorrow. Returns auto_pause=false — construction is a background process.
func _handle_daily_tick(event: ScheduledEvent) -> Dictionary:
	var date: Dictionary = Timekeeping.get_date()
	var calendar_day: int = _calendar_day_from_date(date)
	advance_commissions(calendar_day)

	# Reschedule for tomorrow.
	var next_events := [{
		"fire_time": event.fire_time + Timekeeping.ROUNDS_PER_DAY,
		"event_type": "stronghold_construction_daily_tick",
		"owner_id": "stronghold_global",
		"data": {},
		"priority": ScheduledEvent.PRIORITY_ENVIRONMENTAL,
	}]

	return {
		"auto_pause": false,
		"next_events": next_events,
	}


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _rounds_until_next_day() -> int:
	var date: Dictionary = Timekeeping.get_date()
	var hour: int = int(date.get("hour", 0))
	var minute: int = int(date.get("minute", 0))
	var rnd: int = int(date.get("round", 0))
	var rounds_elapsed_today: int = (hour * Timekeeping.ROUNDS_PER_HOUR) \
		+ (minute * Timekeeping.ROUNDS_PER_MINUTE) + rnd
	return Timekeeping.ROUNDS_PER_DAY - rounds_elapsed_today


func _calendar_day_from_date(date: Dictionary) -> int:
	var year: int = int(date.get("year", 1))
	var month: int = int(date.get("month", 1))
	var day: int = int(date.get("day", 1))
	return ((year - 1) * 12 + (month - 1)) * Timekeeping.DAYS_PER_MONTH + day
