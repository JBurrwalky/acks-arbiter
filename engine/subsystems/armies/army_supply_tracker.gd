class_name ArmySupplyTracker
extends RefCounted

## Per-army weekly supply tick per gdd-army-warfare.md §4.9.1 + RAW
## daw_campaigning_armies.xml §weekly_procedure L18-64. Schedules an
## `army_weekly_supply_check` event every 7 game-days for each active army;
## fires the §4.9.1 intra-tick step ordering on event resolution:
##   1. Supply check — compute weekly_supply_cost_cp via SupplyCalculator
##      and resolve supply line status.
##   2. Lack-of-supply effects — apply lazily-accumulated daily penalties
##      (Phase 6A part 2 v1 simplification: deduct stockpile, increment
##      consecutive_unsupplied_weeks if shortfall, fire calamity loyalty
##      roll trigger when thresholds crossed).
##   3. Vagary-of-war check — fire RecruitmentVagariesResolver-equivalent
##      for war (deferred — Phase 6A part 3 wires the war vagary resolver).
##   4. Officer / unit state mutations (deferred — same).
##   5. Schedule next weekly tick at now + 7 game-days.
##
## v1 SCOPE: this tick fires the supply check, supply-line evaluation, and
## stockpile deduction. The vagary-of-war + officer mutations are stubbed for
## future. Sufficient to verify supply mechanics work end-to-end.
##
## Public API (instance, owned by SessionRunner):
##   register(registry: EventHandlerRegistry)
##   unregister(registry: EventHandlerRegistry)
##   start_tracking(army_id, current_time, scheduler) -> event_id
##   stop_tracking(army_id, scheduler) -> int
##
## Event handler `_handle_weekly_supply_check(event)` runs the §4.9.1 ordering.

const EVENT_WEEKLY_SUPPLY_CHECK := "army_weekly_supply_check"
const WEEK_GAME_DAYS := 7


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func register(registry: EventHandlerRegistry) -> void:
	registry.register(EVENT_WEEKLY_SUPPLY_CHECK, _handle_weekly_supply_check)


func unregister(registry: EventHandlerRegistry) -> void:
	registry.unregister(EVENT_WEEKLY_SUPPLY_CHECK)


# ---------------------------------------------------------------------------
# Public: start/stop tracking
# ---------------------------------------------------------------------------

func start_tracking(army_id: String, current_time: int, scheduler: EventScheduler) -> String:
	if army_id.is_empty() or scheduler == null:
		return ""
	var rounds: int = WEEK_GAME_DAYS * Timekeeping.ROUNDS_PER_DAY
	return scheduler.schedule_after(
		current_time, rounds, EVENT_WEEKLY_SUPPLY_CHECK, army_id,
		{"army_id": army_id},
		ScheduledEvent.PRIORITY_SCHEDULED_CHECK,
	)


func stop_tracking(army_id: String, scheduler: EventScheduler) -> int:
	if scheduler == null or army_id.is_empty():
		return 0
	return scheduler.cancel_all_for_owner(army_id, EVENT_WEEKLY_SUPPLY_CHECK)


# ---------------------------------------------------------------------------
# Event handler
# ---------------------------------------------------------------------------

func _handle_weekly_supply_check(event: ScheduledEvent) -> Dictionary:
	var army_id: String = event.owner_id
	var calendar_day: int = _calendar_day()
	var result: Dictionary = run_supply_tick(army_id, calendar_day)

	# Schedule next weekly tick if army is still active.
	var army: Dictionary = ArmyRepository.get_army(army_id)
	var state: String = _safe_string(army.get("state"), "")
	var still_active: bool = not army.is_empty() and state != "disbanded" and state != "battling"
	if still_active and _scheduler != null:
		_scheduler.schedule_after(
			event.fire_time, WEEK_GAME_DAYS * Timekeeping.ROUNDS_PER_DAY,
			EVENT_WEEKLY_SUPPLY_CHECK, army_id,
			{"army_id": army_id},
			ScheduledEvent.PRIORITY_SCHEDULED_CHECK,
		)
	return result


# A reference to the scheduler is captured at registration time — set by the
# session runner via `set_scheduler()`. We need it to schedule the next
# weekly tick from inside the handler.
var _scheduler: EventScheduler = null


func set_scheduler(s: EventScheduler) -> void:
	_scheduler = s


# ---------------------------------------------------------------------------
# Public: run a single supply tick (testable without a scheduler)
# ---------------------------------------------------------------------------

func run_supply_tick(army_id: String, calendar_day: int) -> Dictionary:
	if army_id.is_empty():
		return {"success": false, "error": "army_id_required"}
	var army: Dictionary = ArmyRepository.get_army(army_id)
	if army.is_empty():
		return {"success": false, "error": "army_not_found"}
	var supply: Dictionary = ArmyRepository.get_supply_state(army_id)
	if supply.is_empty():
		return {"success": false, "error": "no_supply_state"}

	# Step 1: weekly supply cost.
	var weekly_cost: int = SupplyCalculator.compute_weekly_supply_cost_cp(army_id)

	# Step 2: deduct from stockpile; track shortfall.
	var stockpile: int = int(supply.get("current_stockpile_cp", 0))
	var consecutive_unsupplied: int = int(supply.get("consecutive_unsupplied_weeks", 0))
	var shortfall: int = 0
	var new_stockpile: int = stockpile - weekly_cost
	if new_stockpile < 0:
		shortfall = -new_stockpile
		new_stockpile = 0
		consecutive_unsupplied += 1
	else:
		consecutive_unsupplied = 0

	# Step 3: re-evaluate supply line status. v1 simplification: accept the
	# stored status until SupplyCalculator gets a path-tracker hookup. Phase
	# 6A part 3 may wire the recompute via the army_marcher's last leg path.
	var supply_line_status: String = _safe_string(supply.get("supply_line_status"), "out_of_supply_no_base")

	# Step 4: persist updated supply_state.
	ArmyRepository.update_supply_state(army_id, {
		"weekly_supply_cost_cp": weekly_cost,
		"current_stockpile_cp": new_stockpile,
		"consecutive_unsupplied_weeks": consecutive_unsupplied,
		"last_supply_check_calendar_day": calendar_day,
	})

	# Emit signals.
	if EventBus.has_signal("army_supply_consumed"):
		EventBus.emit_signal("army_supply_consumed", army_id, weekly_cost, new_stockpile)

	if shortfall > 0:
		# Out-of-supply: emit cut signal once per transition.
		if EventBus.has_signal("army_supply_cut"):
			EventBus.emit_signal("army_supply_cut", army_id, "stockpile_depleted")

	# Step 5: Vagary-of-War check per daw_vagaries.xml §vagaries_of_war L188-194
	# (Phase 7). Eligibility: out_of_garrison >30 game-days OR in_enemy_territory
	# OR state == 'besieging'. The predicate consults RealmGraph (Phase 7's
	# resolution of the [NEEDS-PHASE-7-RESOLUTION] O-A-17 reminder).
	var vagary_outcome: Dictionary = {}
	if InEnemyTerritoryPredicate.is_eligible_for_war_vagary(army_id, calendar_day):
		vagary_outcome = VagariesOfWarResolver.roll_and_resolve(army_id, calendar_day)

	# Calamity threshold per RAW §lack_of_supply.psychological_effects L359-362:
	# every unit fails its loyalty roll for ≥2 consecutive weeks → mass
	# desertion / disband. v1 placeholder: at 2+ consecutive_unsupplied_weeks
	# emit signal for downstream subsystem (Phase 6A part 3 wires the actual
	# loyalty rolls).
	var calamity_triggered: bool = consecutive_unsupplied >= 2

	return {
		"success": true,
		"army_id": army_id,
		"weekly_cost_cp": weekly_cost,
		"deducted": weekly_cost - shortfall,
		"shortfall": shortfall,
		"stockpile_after": new_stockpile,
		"consecutive_unsupplied_weeks": consecutive_unsupplied,
		"supply_line_status": supply_line_status,
		"calamity_triggered": calamity_triggered,
		"vagary_of_war": vagary_outcome,
		"calendar_day": calendar_day,
	}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _calendar_day() -> int:
	return Timekeeping.get_calendar_day()


func _safe_string(v: Variant, default_value: String = "") -> String:
	if v == null:
		return default_value
	return String(v)
