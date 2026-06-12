class_name MonthlyRecruitmentVagaryTicker
extends RefCounted

## Per gdd-army-warfare.md §5: once per game-month per character who launched
## a recruitment activity (Conscript / Levy Militia / Hire Mercenaries /
## Solicit Mercenaries / Call to Arms) that month, roll on the Vagaries of
## Recruitment table and emit EventBus.recruitment_vagary_resolved.
##
## Implementation: a single recurring `monthly_recruitment_vagary_tick` event
## scheduled per campaign. On fire, the handler queries
## RecruitmentVagariesResolver.list_recruiting_characters() for the trailing
## 30-day window and invokes resolve() for each character. Then schedules the
## next tick at now + 30 game-days.
##
## v1 SCOPE: scheduler-driven monthly tick. Phase 7 will wire the per-result
## consequences (war_declared → realm graph mutation, brigands → spawn enemy
## army, etc.).
##
## Public API (instance, owned by SessionRunner):
##   register(registry)
##   unregister(registry)
##   start(campaign_id, current_time, scheduler) -> event_id
##   stop(campaign_id, scheduler) -> int
##   tick_once(campaign_id, calendar_day, dice_roller=Callable()) -> Array
##     (returns the list of {character_id, roll, result_key, ...} for each
##      character who rolled this month — testable without scheduler)

const EVENT_MONTHLY_RECRUITMENT_VAGARY_TICK := "monthly_recruitment_vagary_tick"
const MONTH_GAME_DAYS := 30
const VAGARY_WINDOW_DAYS := 30


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func register(registry: EventHandlerRegistry) -> void:
	registry.register(EVENT_MONTHLY_RECRUITMENT_VAGARY_TICK, _handle_monthly_tick)


func unregister(registry: EventHandlerRegistry) -> void:
	registry.unregister(EVENT_MONTHLY_RECRUITMENT_VAGARY_TICK)


var _scheduler: EventScheduler = null


func set_scheduler(s: EventScheduler) -> void:
	_scheduler = s


# ---------------------------------------------------------------------------
# Scheduling
# ---------------------------------------------------------------------------

func start(campaign_id: String, current_time: int, scheduler: EventScheduler) -> String:
	if campaign_id.is_empty() or scheduler == null:
		return ""
	var rounds: int = MONTH_GAME_DAYS * Timekeeping.ROUNDS_PER_DAY
	return scheduler.schedule_after(
		current_time, rounds, EVENT_MONTHLY_RECRUITMENT_VAGARY_TICK, campaign_id,
		{"campaign_id": campaign_id},
		ScheduledEvent.PRIORITY_SCHEDULED_CHECK,
	)


func stop(campaign_id: String, scheduler: EventScheduler) -> int:
	if scheduler == null or campaign_id.is_empty():
		return 0
	return scheduler.cancel_all_for_owner(campaign_id, EVENT_MONTHLY_RECRUITMENT_VAGARY_TICK)


# ---------------------------------------------------------------------------
# Event handler
# ---------------------------------------------------------------------------

func _handle_monthly_tick(event: ScheduledEvent) -> Dictionary:
	var campaign_id: String = event.owner_id
	var calendar_day: int = _calendar_day()
	var rolled: Array = tick_once(campaign_id, calendar_day, Callable())

	# Schedule next tick.
	if _scheduler != null:
		_scheduler.schedule_after(
			event.fire_time, MONTH_GAME_DAYS * Timekeeping.ROUNDS_PER_DAY,
			EVENT_MONTHLY_RECRUITMENT_VAGARY_TICK, campaign_id,
			{"campaign_id": campaign_id},
			ScheduledEvent.PRIORITY_SCHEDULED_CHECK,
		)
	return {
		"event_type": EVENT_MONTHLY_RECRUITMENT_VAGARY_TICK,
		"campaign_id": campaign_id,
		"rolled_count": rolled.size(),
		"results": rolled,
	}


# ---------------------------------------------------------------------------
# Public: run a single tick (testable without scheduler)
# ---------------------------------------------------------------------------

func tick_once(campaign_id: String, calendar_day: int, dice_roller: Callable = Callable()) -> Array:
	if campaign_id.is_empty():
		return []
	var recruiting: Array = RecruitmentVagariesResolver.list_recruiting_characters(
		campaign_id, calendar_day, VAGARY_WINDOW_DAYS
	)
	var results: Array = []
	for character_id in recruiting:
		var resolved: Dictionary = RecruitmentVagariesResolver.resolve(
			"monthly_tick", String(character_id), calendar_day, dice_roller
		)
		resolved["character_id"] = character_id
		results.append(resolved)
	return results


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _calendar_day() -> int:
	return Timekeeping.get_calendar_day()
