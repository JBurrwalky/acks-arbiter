class_name HijinkPlanningResolver
extends RefCounted

## Drives the `plan_hijink` Ongoing activity per RAW §plan_hijink L1217-1233.
##
## RAW: planning takes 2d8+3 days (L1-4 perpetrator), 2d6+3 (L5-8), or
## 2d4+3 (L9+). The perpetrator does not know the required time until
## planning completes. Each day in the planning ongoing window advances
## `hijink_assignments.planning_days_completed` by 1; when it reaches
## `planning_days_required`, the planning_state flips to `'planned'`.
##
## The activity handler calls `roll_planning_duration(level, rng)` once at
## launch, stores the rolled days on the hijink row, and calls
## `advance_planning(hijink_id)` on each day-tick. When planning completes,
## emits `EventBus.hijink_planned`.
##
## Plannable hijinks per RAW L1225 (subset relevant to v1):
##   * smuggling, stealing, assassinating
##
## Non-plannable per RAW L1232: carousing, spying, treasure_hunting. The
## perform_hijink handler skips this resolver for those kinds.


# RAW L1225 — only these kinds benefit from planning.
const PLANNABLE_KINDS := ["assassinating", "smuggling", "stealing"]


## Returns true if the named hijink kind benefits from / requires planning.
static func is_plannable(hijink_kind: String) -> bool:
	return hijink_kind in PLANNABLE_KINDS


## Rolls the per-RAW planning duration in days. Pass a seeded RNG for
## deterministic tests.
##   L1-4  → 2d8+3 (range 5-19, mean 12)
##   L5-8  → 2d6+3 (range 5-15, mean 10)
##   L9+   → 2d4+3 (range 5-11, mean 8)
static func roll_planning_duration(perpetrator_level: int, rng: RandomNumberGenerator) -> int:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var die_sides: int = 8
	if perpetrator_level >= 9:
		die_sides = 4
	elif perpetrator_level >= 5:
		die_sides = 6
	return rng.randi_range(1, die_sides) + rng.randi_range(1, die_sides) + 3


## Initializes the planning state on a hijink_assignments row.
## Sets planning_state='planning', planning_days_required=<rolled>,
## planning_days_completed=0, status='planning'.
## Returns the rolled duration (in days).
static func start_planning(
		hijink_id: String,
		perpetrator_level: int,
		rng: RandomNumberGenerator,
) -> int:
	if hijink_id.is_empty():
		return 0
	var days: int = roll_planning_duration(perpetrator_level, rng)
	SyndicateRepository.update_hijink(hijink_id, {
		"planning_state": "planning",
		"planning_days_required": days,
		"planning_days_completed": 0,
		"status": "planning",
	})
	return days


## Advances planning_days_completed by 1. When it reaches the rolled
## requirement, flips planning_state to 'planned' and emits
## EventBus.hijink_planned. Returns true if planning completed on this
## call, false otherwise.
static func advance_planning(hijink_id: String) -> bool:
	if hijink_id.is_empty():
		return false
	var row := SyndicateRepository.get_hijink(hijink_id)
	if row.is_empty():
		return false
	if String(row.get("planning_state", "")) != "planning":
		return false
	var completed: int = int(row.get("planning_days_completed", 0)) + 1
	var required: int = int(row.get("planning_days_required", 0))
	var fields: Dictionary = {"planning_days_completed": completed}
	var finished: bool = completed >= required
	if finished:
		fields["planning_state"] = "planned"
		fields["status"] = "queued"  # awaits the perform_hijink launch
	SyndicateRepository.update_hijink(hijink_id, fields)
	if finished:
		EventBus.hijink_planned.emit(
			hijink_id,
			String(row.get("hijink_kind", "")),
			String(row.get("target_id", "")),
		)
	return finished


## RAW L1229: if the hijink is performed before planning is complete, apply
## -1 to the proficiency throw per day of incomplete planning. Returns the
## penalty to subtract from the d20 roll. Returns 0 if planning is complete
## or if the kind isn't plannable.
static func incomplete_planning_penalty(hijink_id: String) -> int:
	var row := SyndicateRepository.get_hijink(hijink_id)
	if row.is_empty():
		return 0
	var kind := String(row.get("hijink_kind", ""))
	if not is_plannable(kind):
		return 0
	var state := String(row.get("planning_state", ""))
	if state == "planned" or state == "complete":
		return 0
	var required: int = int(row.get("planning_days_required", 0))
	var completed: int = int(row.get("planning_days_completed", 0))
	# RAW: planning_days_required is unknown to the perpetrator until completion.
	# If planning was never started, the entire RAW-rolled requirement is
	# "incomplete" — but we don't know what that is yet. v1 uses a conservative
	# stand-in: if start_planning was never called, treat penalty as 0 and let
	# the perform_hijink handler decide; if planning is mid-flight, penalty is
	# (required - completed).
	if required <= 0:
		return 0
	return max(0, required - completed)
