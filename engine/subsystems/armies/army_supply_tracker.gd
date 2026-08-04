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

## RAW: rules/daw_campaigning_armies.xml:367 — "Unsupplied units suffer an
## additional -1 penalty on their loyalty rolls because they are visibly being
## left to starve." Additional to, not instead of, the out-of-supply calamity.
const UNSUPPLIED_LOYALTY_PENALTY := -1


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

## [param designator] optional player-override for RAW's partial-supply
## allocation (`daw_campaigning_armies.xml:365`), signature
## `(stockpile_cp: int, units: Array) -> Array` returning the ids of the units
## the leader chose to feed. The scheduled handler never supplies one, so NPC
## armies always get `ArmySupplyAllocationResolver`'s best-first default.
func run_supply_tick(army_id: String, calendar_day: int,
		designator: Callable = Callable()) -> Dictionary:
	if army_id.is_empty():
		return {"success": false, "error": "army_id_required"}
	var army: Dictionary = ArmyRepository.get_army(army_id)
	if army.is_empty():
		return {"success": false, "error": "army_not_found"}
	var supply: Dictionary = ArmyRepository.get_supply_state(army_id)
	if supply.is_empty():
		return {"success": false, "error": "no_supply_state"}

	# Step 1: weekly supply cost + RAW's partial-supply allocation. The leader
	# decides who eats BEFORE the deduction, because who eats is what the
	# deduction pays for (`daw_campaigning_armies.xml:365`). With a full
	# stockpile the allocation is a no-op that marks every unit supplied.
	var stockpile_before: int = int(supply.get("current_stockpile_cp", 0))
	var allocation: Dictionary = ArmySupplyAllocationResolver.resolve_for_army(
		army_id, stockpile_before, designator)
	var weekly_cost: int = int(allocation.get("weekly_cost_cp", 0))

	# Step 2: deduct from stockpile; track shortfall. On a shortfall week this
	# zeroes the stockpile, which is exactly what the allocation spends — the
	# residue too small to feed anyone goes to the best starving unit as partial
	# supply (RAW :360; see ArmySupplyAllocationResolver).
	var consecutive_unsupplied: int = int(supply.get("consecutive_unsupplied_weeks", 0))
	var shortfall: int = 0
	var new_stockpile: int = stockpile_before - weekly_cost
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

	# RAW: rules/daw_campaigning_armies.xml:360-361 — "Each week a unit is
	# partially or completely unsupplied counts as a calamity. Each such unit
	# must make a loyalty roll." So the calamity is PER WEEK, not at a 2-week
	# threshold, and it is a per-unit roll rather than an army-wide event.
	#
	# `calamity_triggered` below keeps its original >= 2 meaning because it is
	# an existing published return-dict key with a test pinning it
	# (test_army_supply_tracker.gd:125-129). It is NOT the RAW rule and nothing
	# consumes it for mechanical effect; treating it as the supply calamity
	# would under-fire by a week. Left as-is deliberately rather than
	# redefined out from under its caller.
	#
	# RAW :366 — supplied units "do not make the weekly lack-of-supply check",
	# so only the allocation's unsupplied set rolls, not the whole army.
	var unit_loyalty_rolls: Array = []
	if shortfall > 0:
		unit_loyalty_rolls = _roll_unit_supply_loyalty(
			army_id, calendar_day, allocation.get("unsupplied_unit_ids", []))

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
		# Renamed from `tribal_warrior_loyalty_rolls` 2026-08-03 when the roll
		# stopped being tribal-only; the old key is kept as an alias so any
		# reader written against it still works.
		"unit_loyalty_rolls": unit_loyalty_rolls,
		"tribal_warrior_loyalty_rolls": unit_loyalty_rolls,
		"supplied_unit_ids": allocation.get("supplied_unit_ids", []),
		"unsupplied_unit_ids": allocation.get("unsupplied_unit_ids", []),
		"partially_supplied_unit_id": allocation.get("partially_supplied_unit_id", ""),
		"supply_designator": allocation.get("designator", ""),
		"vagary_of_war": vagary_outcome,
		"calendar_day": calendar_day,
	}


## RAW: rules/daw_campaigning_armies.xml:360-361 — each unsupplied week is a
## calamity and each affected unit makes a loyalty roll. Every source type RAW
## grants the roll to takes it (daw_armies_recruitment.xml:99 mercenaries, :353
## conscripts, :458 militia, :477 followers, :611 slave soldiers,
## ax_domains_of_chaos.xml:454 tribal warriors); `UnitLoyaltyResolver.rolls_loyalty`
## owns that gate together with the :483 religious-fanatic exemption, so this
## call site repeats neither.
##
## [param unsupplied_unit_ids] is `ArmySupplyAllocationResolver`'s designation.
## It arrives as a parameter rather than being recomputed here, per conventions
## §70: the resolver never goes hunting for its own trigger. Units NOT in it ate
## this week and are exempt from the check entirely (RAW :366).
##
## Every unsupplied unit takes RAW :367's additional -1 "because they are
## visibly being left to starve", including when the stockpile was empty and the
## whole army starved together. [Jedidiah ruling 2026-08-03: the -1 attaches to
## the unit being out of supply, not to whether anyone else was fed.] Note this
## makes the all-starve case one point harsher than it was before partial supply
## existed — that is the intended reading, not drift.
func _roll_unit_supply_loyalty(army_id: String, calendar_day: int,
		unsupplied_unit_ids: Array) -> Array:
	var out: Array = []
	if unsupplied_unit_ids.is_empty():
		return out
	for assignment in ArmyRepository.list_active_assignments_for_army(army_id):
		if not (assignment is Dictionary):
			continue
		var unit_id: String = String((assignment as Dictionary).get("troop_unit_id", ""))
		if unit_id.is_empty():
			continue
		if not unsupplied_unit_ids.has(unit_id):
			continue
		var unit: Dictionary = TroopUnitRepository.get_unit(unit_id)
		if unit.is_empty():
			continue
		if String(unit.get("status", "")) != "active":
			continue
		if not UnitLoyaltyResolver.rolls_loyalty(unit):
			continue
		var res: Dictionary = UnitLoyaltyResolver.roll_loyalty(
			unit_id, [UnitLoyaltyResolver.CALAMITY_OUT_OF_SUPPLY],
			calendar_day, null, UNSUPPLIED_LOYALTY_PENALTY)
		if bool(res.get("ok", false)):
			out.append(res)
	return out


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _calendar_day() -> int:
	return Timekeeping.get_calendar_day()


func _safe_string(v: Variant, default_value: String = "") -> String:
	if v == null:
		return default_value
	return String(v)
